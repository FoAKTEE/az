#!/bin/bash -l
#SBATCH --job-name=ktg-loop
#SBATCH --account=ssci-anima
#SBATCH --partition=b200
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=120G
#SBATCH --time=2-23:30:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/loop-%j.log
#
# Mission ktg-train, node arxiv-1902.10565::loop_resume_under_walltime.
#
# The cluster MaxTime is 3-00:00:00 on every partition and the self-play loop is
# open-ended, so the run survives only as a chain of resubmitting jobs
# (assumption a03_walltime_resume). This wrapper encodes the run contract and the
# guards that make an unattended chain safe:
#
#   contract   1 GPU, 32 CPUs, 120G, 2-23:30:00 (30 min inside MaxTime),
#              b300 when it has free GPUs, else the next candidate -- by default
#              b200, and whatever KTG_PARTITIONS names when it is set, which may
#              be a comma-joined multi-partition set such as b200,l40s
#              (a02, a04, mission.json decisions[3])
#   chain      sbatch --dependency=afterany:$SLURM_JOB_ID issued at the TOP of the
#              body, so the successor is queued before anything can kill us --
#              it survives OOM, node failure and the hard walltime kill
#   accounting an EXIT trap installed immediately after the resubmit, so EVERY
#              termination path -- explicit exit, set -u abort, missing env.sh,
#              missing loop script -- updates .failcount and cancels the queued
#              successor when it must (obligation o26)
#   signals    a TERM trap installed before the resubmit. SIGTERM to the step is
#              how the scheduler ends every HEALTHY link at --time (SIGKILL
#              follows KillWait seconds later) and how scancel works, and bash
#              runs the EXIT trap on that path, so the wrapper must tell that
#              end apart from a clean cycle and from a failure: it is neither,
#              the count is left alone and the queued successor -- the resume
#              itself -- is kept (obligation o31)
#   breaker    $BASEDIR/.failcount, three non-zero exits IN A ROW stop the
#              chain. "In a row" is measured in completed cycles, not in links:
#              the count is cleared by a link that exited 0 and by any link that
#              advanced $BASEDIR/.cycles_completed, the counter the loop bumps
#              after every cycle whose five stages all returned 0. Without the
#              second rule the first would never fire in production -- a healthy
#              link is ended by the scheduler, never by an exit 0 -- and three
#              failures days apart would trip the breaker (obligation o33)
#   depth      $BASEDIR/.chain_depth against KTG_MAX_CHAIN
#   brake      $BASEDIR/STOP -- no resubmit, exit 0
#   sweep      stale torchmodels_toexport/*.exported and shuffleddata/*.tmp
#   scratch    codes/data_budget/scratch_guard.sh, called before the loop starts.
#              This file holds NO storage number of its own: every threshold
#              lives in codes/data_budget/budget.env, which is node data_budget's
#              single source of truth (obligations o04, o27).
#
# The executed kill/resume proof belongs to node verify_preemption_resume and the
# executed breaker proof to node loop_failure_circuit_breaker. This file is
# authored, parse-checked and policy-checked here; it is not submitted here.

set -uo pipefail

# ---------------------------------------------------------------- roots
KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
AZ_ROOT="${AZ_ROOT:-/home/schmidt/ssci-haiyangw/az}"
KTG_CODES="${KTG_CODES:-$AZ_ROOT/results/ktg/paper_1902.10565/codes}"
BASEDIR="${BASEDIR:-$KTG_ROOT/loop}"

# $0 inside a batch job is the scheduler's spool copy, not this file, so the
# resubmit must name the script by absolute path.
SELF="${KTG_LOOP_SBATCH:-$KTG_CODES/loop/loop.sbatch}"
LOOP_SH="$KTG_CODES/loop/synchronous_loop_9x9.sh"

# Storage policy is node data_budget's, delivered as two executables. The guard
# is never advisory: its exit code decides whether a cycle may start.
#   scratch_guard.sh  exit 0 ok / 1 hard cap / 2 group free floor / 3 cannot measure
#   prune_retention.py --apply  bounded rolling retention, run once at startup
SCRATCH_GUARD="${KTG_SCRATCH_GUARD:-$KTG_CODES/data_budget/scratch_guard.sh}"
PRUNE_RETENTION="${KTG_PRUNE_RETENTION:-$KTG_CODES/data_budget/prune_retention.py}"

# The stage sampler (node synchronous_loop_smoke's instrument, codes/eval/stage_monitor.sh).
# The smoke job carried it in smoke_loop.sbatch and this wrapper had none, so a production
# link produced no thread or GPU sample at all -- which is the measurement o03 (thread
# budget), o39's third conjunct (nlwp_max <= 32 on a real-net cycle) and c06 (GPU duty) all
# wait on. It is started once per link here and stopped in finalize, so every stage of
# every cycle of the link is inside one file per JOB (stage_monitor.sh:50-55, o37).
STAGE_MONITOR="${KTG_STAGE_MONITOR:-$KTG_CODES/eval/stage_monitor.sh}"
MONITOR_DIR="${KTG_MONITOR_DIR:-$BASEDIR/monitor}"
# A 3-day link at the smoke's 0.2 s / 2 s would be ~1.3 M ps sweeps and a ~250 MB tsv. The
# link samples at 1 s / 5 s instead; the smoke's own defaults are untouched, so every
# recorded smoke number stays reproducible (stage_monitor.sh header).
export KTG_MON_PS_INTERVAL="${KTG_MON_PS_INTERVAL:-1}"
export KTG_MON_GPU_INTERVAL="${KTG_MON_GPU_INTERVAL:-5}"

# The compute-policy check script and the GPU cap are named by mission.json;
# there is deliberately no hard-coded fallback for either, so a missing or
# unreadable mission.json stops the chain instead of silently skipping the
# pre-flight.
POLICY_CHECK_REL=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["compute"]["policyCheck"])' "$AZ_ROOT/mission.json" 2>/dev/null)
POLICY_CHECK="$AZ_ROOT/$POLICY_CHECK_REL"
GPU_CAP_TOTAL=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["compute"]["gpuCapTotal"])' "$AZ_ROOT/mission.json" 2>/dev/null)

# ---------------------------------------------------------------- contract
# The CPU count is NOT typed here. codes/loop/knobs_9x9.env is node
# derive_cycle_knobs_9x9's single source of truth for the eleven loop knobs and
# for the two allocation-side numbers, and this wrapper reads it in the "loop
# knobs" section below; REQ_CPUS is its KTG_CPUS_PER_TASK and the #SBATCH line
# at the top of this file carries the same number (obligation o39). 32 is what
# the measured thread budget requires -- jobs 298712 and 299259 measured
# nlwp_max 25 on every stage holding a CUDA context, against the 24 this file
# used to declare, and the projected two-real-net gate is 28 -- and it is an
# honest declaration, not a policy cap: mission.json compute.cpuPolicy withdrew
# the 20 % clause on 2026-09-03, so declaring what the job uses costs nothing.
# Raising the THREAD counts is still a scaling decision for
# measure_stage_throughput, not a free win.
REQ_GPUS=1
REQ_CPUS=""
# Operator knobs, deliberately environment-readable. resubmit() calls sbatch with
# no --export, so Slurm's default --export=ALL carries whatever the submitting
# shell had in it down the WHOLE chain, not just the first link: a stray
# KTG_MIN_RUNTIME_SECONDS=0 left over from a test shell would wave every fast
# crash through as a scheduler termination for 200 links. That propagation is the
# point -- it is how an operator retunes a running chain without editing a file
# under a live job -- so the knobs stay overridable and the rule is to submit the
# first link from a clean shell (obligation o33 (b)/(v)). The two classification
# CONSTANTS below are not knobs and are hard-coded for exactly that reason.
KTG_MAX_CHAIN="${KTG_MAX_CHAIN:-200}"
KTG_MAX_FAILS="${KTG_MAX_FAILS:-3}"
KTG_MIN_RUNTIME_SECONDS="${KTG_MIN_RUNTIME_SECONDS:-600}"

# Exit code the loop script uses when the storage guard refuses a cycle. It is a
# deliberate refusal, not a crash, so it must not spend a breaker attempt. The
# code alone is not the evidence: the loop writes $BASEDIR/STOP before it exits
# with it (synchronous_loop_9x9.sh:245-246), and only that file distinguishes a
# storage refusal from any other stage that happens to exit 3 under bash -e.
KTG_RC_SCRATCH_STOP=3

# 128 + SIGTERM(15): the status bash reports for a child the scheduler killed at
# the time limit.
KTG_RC_SIGTERM=143

# Loop arguments: NAMEPREFIX BASEDIR TRAININGNAME MODELKIND USEGATING
# (order fixed by python/selfplay/synchronous_loop.sh:12-32). USEGATING stays 1.
NAMEPREFIX="${KTG_NAMEPREFIX:-ktg9}"
TRAININGNAME="${KTG_TRAININGNAME:-t9}"
MODELKIND="${KTG_MODELKIND:-b7c96h3tfrs}"
USEGATING=1

START_EPOCH=$(date +%s)
mkdir -p "$BASEDIR" "$KTG_ROOT/logs"

say() { echo "=== [$(date -Is)] $* ==="; }

say "loop.sbatch job ${SLURM_JOB_ID:-none} on ${SLURMD_NODENAME:-$(hostname)}"
say "BASEDIR=$BASEDIR  MODELKIND=$MODELKIND  TRAININGNAME=$TRAININGNAME"

# ---------------------------------------------------------------- loop knobs
# obligation o39. `set -a` exports the eleven loop knobs as well as the two
# allocation-side ones. That is deliberate and changes no value: the eleven equal
# the CHANGE 9 ${VAR:-default} block of synchronous_loop_9x9.sh, which
# codes/eval/check_knobs_9x9.py asserts against this same file. What it buys is
# that an operator retunes ONE file instead of two. The three classification
# knobs of the contract section are deliberately NOT in it -- they are this
# wrapper's own and must not travel with a knob set -- and the pre-flight below
# asserts that they are absent.
#
# Read here WITHOUT exiting: this runs before the EXIT trap is installed, so an
# exit at this point would leave the link unaccounted -- the o26 class. A missing
# or unreadable file leaves REQ_CPUS empty, resubmit() then refuses to chain for
# exactly the reason it refuses on an unresolvable policy check, and the
# environment section turns it into a counted pre-flight failure with exit 2.
KNOBS_ENV="${KTG_KNOBS_ENV:-$KTG_CODES/loop/knobs_9x9.env}"
KNOBS_SHA=""
# Checked BEFORE the source, not after: sourcing a file that sets KTG_MAX_FAILS would
# already have retuned the breaker for this link's own resubmit(), and an assertion
# downstream of that is too late. A file that carries one is not sourced at all, so
# REQ_CPUS stays empty and every guard below treats it as an unresolved knob set.
KNOBS_STRAY=0
if [ -r "$KNOBS_ENV" ]; then
    KNOBS_STRAY=$(grep -c -E '^[[:space:]]*(KTG_MAX_FAILS|KTG_MAX_CHAIN|KTG_MIN_RUNTIME_SECONDS)=' "$KNOBS_ENV" 2>/dev/null || true)
    case "$KNOBS_STRAY" in ''|*[!0-9]*) KNOBS_STRAY=0 ;; esac
fi
if [ ! -r "$KNOBS_ENV" ]; then
    say "loop knobs $KNOBS_ENV missing or unreadable -- REQ_CPUS unresolved"
elif [ "$KNOBS_STRAY" -ne 0 ]; then
    say "loop knobs $KNOBS_ENV sets $KNOBS_STRAY classification knob(s) (KTG_MAX_FAILS/KTG_MAX_CHAIN/KTG_MIN_RUNTIME_SECONDS) -- not sourced, REQ_CPUS unresolved"
else
    KNOBS_SHA=$(sha256sum "$KNOBS_ENV" 2>/dev/null | cut -c1-16)
    set -a
    # shellcheck disable=SC1090
    . "$KNOBS_ENV"
    set +a
    REQ_CPUS="${KTG_CPUS_PER_TASK:-}"
    say "loop knobs $KNOBS_ENV (sha256 ${KNOBS_SHA:-unreadable}) KTG_CPUS_PER_TASK=${KTG_CPUS_PER_TASK:-<unset>} KTG_NUM_GAME_THREADS=${KTG_NUM_GAME_THREADS:-<unset>}"
fi
case "$REQ_CPUS" in
    ''|*[!0-9]*) REQ_CPUS_RESOLVED=0 ;;
    *)           REQ_CPUS_RESOLVED=1 ;;
esac

# ---------------------------------------------------------------- chain state
FAILCOUNT_FILE="$BASEDIR/.failcount"
CHAINDEPTH_FILE="$BASEDIR/.chain_depth"
# Progress counter, written by the loop after every completed cycle
# (synchronous_loop_9x9.sh CHANGE 10). Read here and again in finalize; the
# difference is what this link achieved. Absent = 0, and a corrupt value is read
# as 0 rather than aborting a three-day link on a stray byte.
CYCLES_FILE="$BASEDIR/.cycles_completed"

# Obligation o35. Every integer that comes back out of a chain state file goes
# through this one function, because a digit-string guard alone is NOT enough to
# make a value safe for $(( )):
#
#   * base. `$(( 08 ))` is an OCTAL literal to bash and 8 is not an octal digit,
#     so a value the `*[!0-9]*` pattern happily admits still aborts the
#     expansion with "value too great for base". An arithmetic error in a
#     non-interactive shell discards the whole enclosing command list, and
#     inside finalize that is the o26 class all over again: no count written, no
#     .breaker_tripped, the queued successor left to repeat the crash, and the
#     chain bounded only by KTG_MAX_CHAIN. `10#` pins the base and is the fix.
#   * bare words. `$(( abc ))` is a variable reference, so under `set -u` a
#     .failcount of "abc" aborted finalize the same way.
#   * width. Past 2^63 bash wraps silently, and a negative failcount would mean
#     a breaker that never trips; 18 digits is the widest that cannot wrap.
#   * whitespace. An operator who edits a state file by hand leaves a space or a
#     newline behind; `$(cat)` eats trailing newlines, this eats the rest.
#
# It never fails and never aborts a link: anything that is not a plain decimal
# reads as 0 and the CALLER decides whether that is worth a line in the log. A
# three-day link must not die because a state file holds a stray byte.
read_counter() {
    local raw="${1:-}"
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"
    case "$raw" in ''|*[!0-9]*) echo 0; return 0 ;; esac
    if [ "${#raw}" -gt 18 ]; then echo 0; return 0; fi
    echo $(( 10#$raw ))
}

[ -f "$FAILCOUNT_FILE" ] || echo 0 > "$FAILCOUNT_FILE"
[ -f "$CHAINDEPTH_FILE" ] || echo 0 > "$CHAINDEPTH_FILE"
failcount_raw=$(cat "$FAILCOUNT_FILE" 2>/dev/null || echo 0)
failcount=$(read_counter "$failcount_raw")
if [ "$failcount_raw" != "$failcount" ]; then
    # Not fatal by design: the breaker resumes counting from what could be read,
    # and the line below is the only evidence that the file had been mangled.
    say "WARNING: $FAILCOUNT_FILE held '$failcount_raw', which is not a plain decimal -- reading it as $failcount"
fi
chaindepth_raw=$(cat "$CHAINDEPTH_FILE" 2>/dev/null || echo 0)
chaindepth=$(read_counter "$chaindepth_raw")
if [ "$chaindepth_raw" != "$chaindepth" ]; then
    say "WARNING: $CHAINDEPTH_FILE held '$chaindepth_raw', which is not a plain decimal -- reading it as $chaindepth"
fi
chaindepth=$(( chaindepth + 1 ))
echo "$chaindepth" > "$CHAINDEPTH_FILE"
CYCLES_AT_ENTRY=$(read_counter "$(cat "$CYCLES_FILE" 2>/dev/null || echo 0)")
say "chain depth $chaindepth/$KTG_MAX_CHAIN, failcount $failcount/$KTG_MAX_FAILS, cycles completed so far $CYCLES_AT_ENTRY"

# ---------------------------------------------------------------- partition pick
# The candidate list is a knob, not a hard-coded pair, because the successors of a
# multi-partition first link must inherit the SAME allowed set: resubmit() passes
# --partition on the sbatch command line, and a command-line --partition beats
# SBATCH_PARTITION, so a link 1 submitted with --partition=b200,l40s would have
# queued links 2..N on b300/b200 only and l40s would never be used again
# (evidence/production_chain/preflight.txt section R6).
#
# KTG_PARTITIONS is read as a list of CANDIDATES separated by whitespace, tried in
# order. A candidate may itself be a comma-joined Slurm partition SET --
# "b200,l40s" -- because Slurm accepts --partition=b200,l40s and starts the job in
# whichever of those partitions can run it first; the free-GPU count for such a
# candidate is the sum over its members, since sinfo -p takes the same comma list.
# Comma is therefore Slurm's own spelling and never a candidate separator: a value
# that is purely comma-separated is one multi-partition candidate. So
# "b300 b200,l40s" means exactly the documented behaviour -- prefer b300 when it
# has a free GPU and no reservation/drain blocks it, otherwise submit to the
# multi-partition set b200,l40s -- and the fallback when nothing is free is the
# LAST candidate, which is where the multi-partition set belongs.
#
# Unset (or empty) KTG_PARTITIONS keeps the historical list and the historical
# b200 fallback byte for byte, so nothing about an existing chain changes.
#
# Propagation is the same path as the other operator knobs (KTG_MAX_CHAIN,
# KTG_MAX_FAILS, KTG_MIN_RUNTIME_SECONDS): a plain ${VAR:-default} assignment,
# which keeps the export attribute of a value that came in from the environment,
# plus resubmit()'s sbatch call carrying no --export, so Slurm's default
# --export=ALL hands KTG_PARTITIONS to the successor and on down the whole chain.
# An operator therefore sets it once, on the first link, and every link resolves
# its own partition from the same allowed set.
KTG_PARTITIONS="${KTG_PARTITIONS:-b300 b200}"
pick_partition() {
    local p free last=""
    # deliberate word splitting: this is a list, not one word.
    # shellcheck disable=SC2086
    for p in $KTG_PARTITIONS; do
        last="$p"
        free=$(sinfo -p "$p" -N -h -o "%N" 2>/dev/null | sort -u | while read -r n; do
            info=$(scontrol show node "$n" 2>/dev/null)
            st=$(grep -oP 'State=\K\S+' <<<"$info")
            a=$(grep -oP 'AllocTRES=.*?gres/gpu=\K\d+' <<<"$info"); a=${a:-0}
            case "$st" in *RESERVED*|*DRAIN*|*DOWN*|*MAINT*) echo 0 ;; *) echo $((8-a)) ;; esac
        done | awk '{s+=$1} END{print s+0}')
        if [ "${free:-0}" -ge "$REQ_GPUS" ]; then echo "$p"; return 0; fi
    done
    echo "${last:-b200}"
}

# ---------------------------------------------------------------- exit accounting
# State the EXIT trap reads. Declared before resubmit so the trap can never see
# an unset variable, whatever aborts the script.
SUCCESSOR=""      # job id of the queued successor, "" when none
LOOP_STARTED=0    # 1 once the loop script has actually been launched
CHAIN_STOP=0      # 1 for a deliberate stop (storage guard) -- not a failure
SCHED_TERM=0      # 1 once this wrapper has been sent SIGTERM by the scheduler
LOOP_RC=0         # the loop's own exit status, valid only once LOOP_RC_SET=1
LOOP_RC_SET=0     # 1 once that status has been recorded
TERM_AFTER_LOOP_RC=0  # 1 if a SIGTERM was first seen AFTER that recording
FINALIZED=0

# The scheduler's SIGTERM is the chain's NORMAL end: slurmstepd signals the whole
# step at --time and sends SIGKILL KillWait seconds later, and scancel takes the
# same route. Trapping it does two things.
#   1. It records WHY the link ended, which finalize cannot otherwise tell: bash
#      runs the EXIT trap on SIGTERM, so without this flag the same end shows up
#      as a clean cycle (the reset that would wipe a real failure count) or as a
#      failure (three of them scancel a perfectly healthy chain).
#   2. It keeps this wrapper alive past the signal, so finalize still runs. Bash
#      defers a trap handler until the foreground command it is waiting on
#      returns, so the wrapper outlives the loop by construction -- the loop does
#      NOT need its own process group, and giving it one would only hide it from
#      the group signal while slurmstepd's cgroup tracking reaches it anyway.
# SIGKILL runs no handler at all (KillWait expiry, cgroup OOM, node failure):
# nothing is written and the queued successor simply runs. That residue is
# obligation o25's, and it is why the successor is queued before anything else.
on_term() {
    SCHED_TERM=1
    # obligation o33 (b): remember WHEN the signal was seen relative to the
    # loop's own exit status. bash defers a trap handler until the foreground
    # command it is waiting on returns, so on the walltime path this handler runs
    # after the loop dies but BEFORE the status is recorded below -- LOOP_RC_SET
    # is still 0 and the link is the scheduler termination it looks like. A
    # signal that arrives later, with a failure already in hand, must not wave
    # that failure through, and this flag is how finalize tells the two apart.
    if [ "$LOOP_RC_SET" -eq 1 ]; then
        TERM_AFTER_LOOP_RC=1
    fi
    say "SIGTERM received -- scheduler termination (walltime or scancel); the queued successor is the resume path"
}
trap on_term TERM

cancel_successor() {
    if [ -n "$SUCCESSOR" ]; then
        say "cancelling queued successor $SUCCESSOR ($1)"
        scancel "$SUCCESSOR" 2>/dev/null
        SUCCESSOR=""
    else
        say "no queued successor to cancel ($1)"
    fi
}

# The single place where .failcount is written and the successor is cancelled.
# It runs from an EXIT trap, so it covers the paths that used to escape the
# breaker entirely (obligation o26): a missing env.sh aborting under set -u with
# "KATAGO_SRC: unbound variable", a missing loop script, a failed cd, and any
# future early exit somebody adds between the resubmit and the end of the file.
finalize() {
    local rc="${1:-0}" elapsed reason cycles_now cycles_this_link
    [ "$FINALIZED" -eq 0 ] || return 0
    # Read the clock BEFORE anything in this function can sleep: the monitor's stop drains
    # its samplers for a few seconds, and that must not be booked as link runtime, which is
    # what the minimum-runtime rule below classifies on.
    elapsed=$(( $(date +%s) - START_EPOCH ))
    FINALIZED=1
    # First statement after the guard: the samplers are background children of this step
    # and every other path out of this function ends the link. `|| true` because an
    # instrument must never change how a link is accounted -- if the stop fails the
    # samplers still end on their own when this pid is gone (stage_monitor.sh sample_ps).
    if [ -f "$STAGE_MONITOR" ] && [ -e "$MONITOR_DIR/monitor.run" ]; then
        bash "$STAGE_MONITOR" stop "$MONITOR_DIR" || true
    fi
    trap - EXIT

    # obligation o33 (c): what this link actually achieved. Every cycle whose
    # five stages all returned 0 bumps $BASEDIR/.cycles_completed, so the
    # difference against the entry value is this link's progress and it is the
    # only evidence available that the failure run should restart.
    # read_counter, not a bare $(( )): o35. This is the read that must never
    # fail, because everything below it -- the count, .breaker_tripped and the
    # successor cancellation -- is downstream of this line.
    cycles_now=$(read_counter "$(cat "$CYCLES_FILE" 2>/dev/null || echo 0)")
    cycles_this_link=$(( cycles_now - CYCLES_AT_ENTRY ))
    [ "$cycles_this_link" -ge 0 ] || cycles_this_link=0

    if [ "$CHAIN_STOP" -eq 1 ]; then
        # Storage refusal: correct behaviour, not a crash. The chain must not
        # continue, but the attempt must not spend a breaker slot either.
        say "deliberate chain stop (rc=$rc after ${elapsed}s) -- failcount left at $failcount"
        cancel_successor "storage guard stopped the chain"
        return 0
    fi

    # obligation o33 (b): a failure the loop had ALREADY reported outranks a
    # SIGTERM that arrived afterwards. The window is the handful of statements
    # between the loop's return and this function, and on the cluster SIGKILL
    # follows KillWait seconds later, so it is narrow -- but a failure waved
    # through leaves the count untouched and the successor queued, which is the
    # one wrong answer. A recorded 143 past the runtime floor is a scheduler kill
    # by the rule below and is deliberately NOT caught here. Residual, and it
    # keeps the safe direction: a signal landing between the loop's return and
    # the two assignments that record its status is still read as a walltime end.
    if [ "$TERM_AFTER_LOOP_RC" -eq 1 ] && [ "$LOOP_RC" -ne 0 ] &&
       ! { [ "$LOOP_RC" -eq "$KTG_RC_SIGTERM" ] && [ "$elapsed" -ge "$KTG_MIN_RUNTIME_SECONDS" ]; }; then
        say "the loop had already exited rc=$LOOP_RC when the SIGTERM arrived -- counting the failure, not the signal"
        SCHED_TERM=0
    fi

    # Scheduler termination: the third outcome, and the one every healthy link
    # of a three-day chain ends in (obligation o31). It is not a clean cycle --
    # the cycle was cut mid-flight, so a real failure count must NOT be wiped --
    # and it is not a failure -- nothing went wrong, and the queued afterany
    # successor IS the resume, so it must NOT be cancelled. Two ways to see it,
    # both needed because the order in which the step's processes are signalled
    # is not fixed:
    #   * this wrapper got the SIGTERM itself -> SCHED_TERM, set by the TERM trap;
    #   * only the loop got it and this wrapper reaped a 128+15 status -> the
    #     $rc test, but only once the link has run at least
    #     KTG_MIN_RUNTIME_SECONDS. A time-limit kill cannot arrive in the first
    #     minutes of a link, so a stage that returns 143 within them is a crash
    #     to be counted, not a resume to be waved through.
    if [ "$SCHED_TERM" -eq 1 ] ||
       { [ "$rc" -eq "$KTG_RC_SIGTERM" ] && [ "$elapsed" -ge "$KTG_MIN_RUNTIME_SECONDS" ]; }; then
        if [ "$SCHED_TERM" -eq 1 ]; then
            reason="SIGTERM to this wrapper"
        else
            reason="loop status $rc, this wrapper not signalled"
        fi
        if [ "$cycles_this_link" -gt 0 ] && [ "$failcount" -ne 0 ]; then
            # The link ran real cycles before the scheduler ended it, so any
            # older failure is not part of a run of consecutive ones.
            say "scheduler termination at walltime after ${elapsed}s ($reason) -- successor continues; $cycles_this_link cycle(s) completed, so failcount $failcount is cleared"
            failcount=0
            echo 0 > "$FAILCOUNT_FILE"
        else
            say "scheduler termination at walltime after ${elapsed}s ($reason) -- successor continues, failcount left at $failcount"
        fi
        return 0
    fi

    if [ "$LOOP_STARTED" -eq 0 ] && [ "$rc" -eq 0 ]; then
        # STOP brake at entry, or a successor that started after the breaker had
        # already tripped. Nothing ran, so nothing is proven: leave the count.
        say "exit 0 before the loop started -- failcount left at $failcount"
        return 0
    fi

    if [ "$rc" -eq 0 ]; then
        echo 0 > "$FAILCOUNT_FILE"
        say "clean exit -- failcount reset to 0"
        return 0
    fi

    if [ "$LOOP_STARTED" -eq 0 ]; then
        say "PRE-FLIGHT FAILURE rc=$rc after ${elapsed}s -- the loop never started"
    fi
    if [ "$cycles_this_link" -gt 0 ] && [ "$failcount" -ne 0 ]; then
        say "this link completed $cycles_this_link cycle(s) before failing -- the run of consecutive failures restarts, old count $failcount dropped"
        failcount=0
    fi
    failcount=$(( failcount + 1 ))
    # Minimum-runtime guard: a link that dies in seconds would otherwise spawn a
    # successor immediately and spin the chain at scheduler speed. A failure
    # faster than KTG_MIN_RUNTIME_SECONDS costs two of the three attempts, so a
    # crash loop trips the breaker on the second link instead of the third.
    if [ "$elapsed" -lt "$KTG_MIN_RUNTIME_SECONDS" ]; then
        say "fast failure: ${elapsed}s < ${KTG_MIN_RUNTIME_SECONDS}s -- counting it twice"
        failcount=$(( failcount + 1 ))
    fi
    echo "$failcount" > "$FAILCOUNT_FILE"
    say "failure rc=$rc -- failcount now $failcount/$KTG_MAX_FAILS"

    if [ "$failcount" -ge "$KTG_MAX_FAILS" ]; then
        say "circuit breaker tripped after $failcount consecutive failures (last ran ${elapsed}s)"
        touch "$BASEDIR/.breaker_tripped"
        cancel_successor "circuit breaker tripped"
    elif [ "$LOOP_STARTED" -eq 0 ]; then
        # Deterministic: the successor would hit the same missing file or the
        # same unset variable, in seconds, forever. Cut it now.
        cancel_successor "pre-flight failure -- the successor would repeat it"
    else
        say "chain continues, $(( KTG_MAX_FAILS - failcount )) attempt(s) left before the breaker"
    fi
}

# ---------------------------------------------------------------- resubmit first
# Issued at the top so the chain survives a hard kill later in this job. The
# successor is queued with afterany and starts whatever way this job ends; if
# this job ends badly the EXIT trap cancels it.
#
# The pre-flight runs INSIDE this job's own allocation, so check.sh counts this
# job's GPU in "my jobs" and then adds the successor's request on top of it. The
# successor cannot start before this job ends and releases that GPU (the
# dependency is afterany on this job), so the real concurrent footprint is
# my_gpus - own_gpus + request. This helper accepts a refusal ONLY when the
# footprint line is the sole violation and the recomputed concurrent total is
# within the mission GPU cap; every other VIOLATION still refuses to chain
# (validation.md F5).
preflight_self_gpu_ok() {
    local out="$1" nviol my_gpus own recomputed
    [ -n "${SLURM_JOB_ID:-}" ] || return 1
    [ -n "$GPU_CAP_TOTAL" ] || return 1
    nviol=$(printf '%s\n' "$out" | grep -c 'VIOLATION')
    [ "$nviol" -eq 1 ] || return 1
    printf '%s\n' "$out" | grep -q 'VIOLATION.*my_gpus(' || return 1
    my_gpus=$(printf '%s\n' "$out" | sed -n 's/^my jobs *: gpus=\([0-9][0-9]*\).*/\1/p' | head -1)
    case "${my_gpus:-x}" in ''|*[!0-9]*) return 1 ;; esac
    own="${SLURM_GPUS_ON_NODE:-$REQ_GPUS}"
    case "$own" in ''|*[!0-9]*) own="$REQ_GPUS" ;; esac
    recomputed=$(( my_gpus - own + REQ_GPUS ))
    [ "$recomputed" -ge 0 ] || return 1
    [ "$recomputed" -le "$GPU_CAP_TOTAL" ] || return 1
    say "pre-flight adjusted: check.sh counted this job's own $own GPU(s) inside my_gpus=$my_gpus; the afterany successor starts only after this job releases them, so the concurrent footprint is $recomputed <= $GPU_CAP_TOTAL"
    return 0
}

resubmit() {
    if [ -e "$BASEDIR/STOP" ]; then
        say "STOP present -- not resubmitting"; return 0
    fi
    if [ "$failcount" -ge "$KTG_MAX_FAILS" ]; then
        say "circuit breaker: failcount $failcount >= $KTG_MAX_FAILS -- not resubmitting"
        touch "$BASEDIR/.breaker_tripped"; return 0
    fi
    if [ "$chaindepth" -ge "$KTG_MAX_CHAIN" ]; then
        say "chain depth $chaindepth >= $KTG_MAX_CHAIN -- not resubmitting"; return 0
    fi
    if [ ! -f "$SELF" ]; then
        say "cannot resubmit: $SELF not found"; return 0
    fi
    # Same rule as the unresolvable policy check below: the successor's request
    # must be a number this wrapper actually derived from the knob file, never a
    # default this file invented (obligation o39).
    if [ "$REQ_CPUS_RESOLVED" -ne 1 ]; then
        say "REQ_CPUS unresolved (KTG_CPUS_PER_TASK not read from $KNOBS_ENV) -- refusing to chain"; return 0
    fi
    local part check_out check_rc out sb_rc sb_err sb_id _try
    part=$(pick_partition)
    say "compute-budget pre-flight for the successor (gpus=$REQ_GPUS cpus=$REQ_CPUS part=$part)"
    if [ -z "$POLICY_CHECK_REL" ] || [ ! -f "$POLICY_CHECK" ]; then
        say "compute-policy check not resolvable from mission.json -- refusing to chain"; return 0
    fi
    check_out=$(bash "$POLICY_CHECK" --gpus "$REQ_GPUS" --cpus "$REQ_CPUS" --partition "$part" 2>&1)
    check_rc=$?
    printf '%s\n' "$check_out"
    if [ "$check_rc" -ne 0 ] && ! preflight_self_gpu_ok "$check_out"; then
        say "compute-budget check failed (exit $check_rc) -- refusing to chain"; return 0
    fi
    # The successor's id must be read from sbatch's STDOUT alone. The site's
    # Slurm cli_filter prints a two-line banner
    #     [BILLING] loaded!
    #     [BILLING] Re-emitting cost at job start!
    # on STDERR at every submission, and the old form captured the two streams
    # together with `2>&1` and then tested the whole capture against ^[0-9]+$.
    # A submission that SUCCEEDED therefore read as a failed one: SUCCESSOR
    # stayed empty for the life of the chain, so cancel_successor() could never
    # fire (the pre-flight-failure and breaker paths that exist to cut a
    # deterministic crash early were dead), the storage stop logged "no queued
    # successor to cancel" while one was queued, and every link logged "chain
    # not extended" over a successor scontrol showed correctly wired. Measured
    # on job 301099, link 1 of the production chain: the log carried the banner
    # and the id 305318 on one "did not return a job id" line while 305318 was
    # PENDING with Dependency=afterany:301099 (evidence/production_chain/
    # status_log.txt, read 1).
    #
    # So: stderr goes to its own file -- it is diagnostic, never the id, and it
    # is echoed verbatim when something actually went wrong -- and the id is
    # parsed out of stdout. `: >` first, because a redirection that cannot be
    # created would abort the whole command substitution and the successor would
    # never be submitted at all; /dev/null loses the diagnostic, not the chain.
    sb_err="$BASEDIR/.resubmit_stderr.${SLURM_JOB_ID:-$$}"
    : > "$sb_err" 2>/dev/null || sb_err=/dev/null
    out=$(sbatch --parsable --partition="$part" \
        --dependency=afterany:"${SLURM_JOB_ID:-0}" "$SELF" 2>"$sb_err")
    sb_rc=$?
    # --parsable prints "jobid" on a stand-alone cluster and "jobid;clustername"
    # on a federated one, so both shapes are accepted and only the leading digits
    # are kept. The LAST matching line wins: a site wrapper is free to print its
    # own lines on stdout before it, and the id is the last thing sbatch writes.
    sb_id=$(printf '%s\n' "$out" | sed -n 's/^\([0-9][0-9]*\)\(;[^;]*\)\{0,1\}$/\1/p' | tail -1)
    if [ -n "$sb_id" ]; then
        SUCCESSOR="$sb_id"
        say "successor queued: $SUCCESSOR (partition $part, dependency afterany:${SLURM_JOB_ID:-0})"
        if [ -s "$sb_err" ]; then
            say "sbatch wrote to stderr and still succeeded -- verbatim: $(tr '\n' ' ' < "$sb_err")"
        fi
    elif [ "$sb_rc" -eq 0 ]; then
        # sbatch reported success but this wrapper could not read an id out of
        # its stdout. The submission most likely EXISTS, so this is a WARNING and
        # never "chain not extended": declaring the chain dead here is what the
        # banner defect did, and it is the one wrong answer. Ask the scheduler
        # instead -- a pending job of this job's own name whose dependency names
        # this job id is the successor, whatever sbatch printed.
        say "WARNING: sbatch exited 0 but no job id could be parsed from its stdout: '${out:-<empty>}' -- looking the successor up in squeue"
        if [ -s "$sb_err" ]; then
            say "sbatch stderr, verbatim: $(tr '\n' ' ' < "$sb_err")"
        fi
        for _try in 1 2 3; do
            sb_id=$(squeue -h -u "${USER:-$(id -un)}" \
                        -n "${SLURM_JOB_NAME:-ktg-loop}" -t PENDING -o '%i|%E' 2>/dev/null \
                    | grep -F "afterany:${SLURM_JOB_ID:-0}" | cut -d'|' -f1 \
                    | sed -n 's/^\([0-9][0-9]*\)$/\1/p' | tail -1)
            [ -n "$sb_id" ] && break
            say "squeue lookup attempt $_try/3 found no pending successor of ${SLURM_JOB_NAME:-ktg-loop} depending on afterany:${SLURM_JOB_ID:-0}"
            [ "$_try" -lt 3 ] && sleep 5
        done
        if [ -n "$sb_id" ]; then
            SUCCESSOR="$sb_id"
            say "successor queued: $SUCCESSOR (partition $part, dependency afterany:${SLURM_JOB_ID:-0}) -- id recovered from squeue, not from sbatch stdout"
        else
            SUCCESSOR=""
            say "WARNING: sbatch exited 0 but neither its stdout nor squeue yielded a successor id -- the successor may nevertheless exist; cancel_successor() cannot reach it, so read the queue before assuming the chain ended"
        fi
    else
        SUCCESSOR=""
        say "sbatch failed (exit $sb_rc) -- chain not extended; stdout: '${out:-<empty>}'"
        if [ -s "$sb_err" ]; then
            say "sbatch stderr, verbatim: $(tr '\n' ' ' < "$sb_err")"
        else
            say "sbatch wrote nothing to stderr"
        fi
    fi
    [ "$sb_err" = /dev/null ] || rm -f "$sb_err"
}
resubmit

# From here on nothing can leave the chain in an unaccounted state: every exit,
# including a set -u abort, runs finalize.
trap 'finalize $?' EXIT

# ---------------------------------------------------------------- post-trip guard
# A successor that starts after the breaker tripped (a scancel that raced, or a
# manual submission) must NOT run one more cycle: resubmit() already refused to
# extend the chain, so this link would be a free extra attempt (validation.md
# F2). Exit before the loop; finalize leaves .failcount where it is.
if [ "$failcount" -ge "$KTG_MAX_FAILS" ] || [ -e "$BASEDIR/.breaker_tripped" ]; then
    say "breaker already tripped (failcount $failcount/$KTG_MAX_FAILS) -- this link exits without running the loop"
    say "to restart the chain: fix the cause, then rm $FAILCOUNT_FILE $BASEDIR/.breaker_tripped"
    exit 0
fi

# The manual brake, checked before anything expensive (the retention pass and the
# storage guard both walk the mission root).
if [ -e "$BASEDIR/STOP" ]; then
    say "STOP present at entry -- nothing to do"
    exit 0
fi

# ---------------------------------------------------------------- environment
if [ ! -r "$KTG_ROOT/env.sh" ]; then
    say "missing or unreadable $KTG_ROOT/env.sh -- pre-flight failure"
    exit 2
fi
say "sourcing $KTG_ROOT/env.sh"
# shellcheck disable=SC1091
source "$KTG_ROOT/env.sh"
if [ -z "${KATAGO_SRC:-}" ]; then
    say "env.sh did not export KATAGO_SRC -- pre-flight failure"
    exit 2
fi
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader || true

# ---------------------------------------------------------------- knob asserts
# obligation o39, second and third conjuncts. Everything here is a pre-flight
# FAILURE (exit 2), never a warning: a link that runs with fewer CPUs than the
# stages spawn threads repeats exactly the defect the smoke measured, and it
# would do so for the whole chain.
#
#   (a) the allocation actually granted equals the number the knob file asks
#       for. $SLURM_CPUS_PER_TASK is what slurmstepd granted; the #SBATCH line
#       is only what was requested, and a --cpus-per-task on the sbatch command
#       line or a partition default overrides it silently. Checked only when the
#       variable is set: unset means this is not a scheduler step at all (an
#       offline parse or a dry run), and there is nothing to compare.
#   (b) both engine configs declare the game-thread count the budget was
#       computed at. A cfg edited to a larger numGameThreads invalidates the
#       32 without changing anything this wrapper can see.
if [ "$KNOBS_STRAY" -ne 0 ]; then
    say "$KNOBS_ENV sets $KNOBS_STRAY classification knob(s) (KTG_MAX_FAILS/KTG_MAX_CHAIN/KTG_MIN_RUNTIME_SECONDS) -- pre-flight failure"
    exit 2
fi
if [ "$REQ_CPUS_RESOLVED" -ne 1 ]; then
    say "loop knobs did not yield KTG_CPUS_PER_TASK ($KNOBS_ENV) -- pre-flight failure"
    exit 2
fi
if [ -n "${SLURM_CPUS_PER_TASK:-}" ] && [ "$SLURM_CPUS_PER_TASK" != "$REQ_CPUS" ]; then
    say "declared CPUs $SLURM_CPUS_PER_TASK != KTG_CPUS_PER_TASK $REQ_CPUS -- pre-flight failure"
    exit 2
fi
say "cpus granted ${SLURM_CPUS_PER_TASK:-<no scheduler step>} == KTG_CPUS_PER_TASK $REQ_CPUS"
for _cfg in "$KTG_CODES/cfg/selfplay_9x9.cfg" "$KTG_CODES/cfg/gatekeeper_9x9.cfg"; do
    if [ ! -r "$_cfg" ]; then
        say "missing or unreadable $_cfg -- pre-flight failure"
        exit 2
    fi
    _gt=$(sed -n 's/^numGameThreads *= *\([0-9][0-9]*\).*/\1/p' "$_cfg" | head -1)
    if [ -z "$_gt" ] || [ "$_gt" != "${KTG_NUM_GAME_THREADS:-}" ]; then
        say "cfg numGameThreads '${_gt:-<none>}' != KTG_NUM_GAME_THREADS '${KTG_NUM_GAME_THREADS:-<unset>}' in $_cfg -- pre-flight failure"
        exit 2
    fi
done
say "cfg numGameThreads = ${KTG_NUM_GAME_THREADS} on both engine configs"
# ---------------------------------------------------------------- stage monitor
# obligation o03 / o39 (third conjunct) / c06: the link's own thread and GPU samples.
# Started here, after env.sh (so nvidia-smi resolves) and after the knob asserts (so a link
# that is about to refuse never leaves a sampler behind), with THIS wrapper's pid as the
# root: stage_monitor.sh walks each candidate's ppid chain and keeps only descendants of
# it, so no other tenant of a shared node can enter the measurement (stage_monitor.sh:71-94,
# o37). Missing instrument = pre-flight failure, like the other mission tools: a three-day
# link that produces no measurement is a link that has to be run again.
if [ ! -f "$STAGE_MONITOR" ]; then
    say "missing $STAGE_MONITOR (node synchronous_loop_smoke's sampler) -- pre-flight failure"
    exit 2
fi
bash "$STAGE_MONITOR" start "$MONITOR_DIR" "$$" || say "stage_monitor start returned non-zero -- the link continues without samples"

# 32 CPUs for the whole job; keep BLAS/OMP from oversubscribing the trainer.
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-4}"
export KTG_ONE_CYCLE="${KTG_ONE_CYCLE:-0}"
export KTG_CODES

# ---------------------------------------------------------------- startup sweep
# obligation o09: a killed export leaves <NAME>.exported in torchmodels_toexport,
# which export_model_for_selfplay.sh:54-56 skips forever. Remove markers whose
# rename never completed. shuffle.sh:105 renames shuffleddata/<ts>.tmp at the
# end and cleanup_old_dirs.py:24 never prunes the leftovers; train.py:1206-1210
# ignores them, so they are dead weight against the scratch cap.
say "startup sweep"
rm -rf "$BASEDIR"/torchmodels_toexport/*.exported
rm -rf "$BASEDIR"/torchmodels_toexport_extra/*.exported
rm -rf "$BASEDIR"/shuffleddata/*.tmp

# ---------------------------------------------------------------- retention
# One dated archive is created per chain link (synchronous_loop.sh:75-81), each
# holding a full python/ copy plus the ~100 MB engine binary; longterm
# checkpoints, rejected models and shuffle windows grow the same way. All of it
# is bounded by node data_budget's retention policy, whose keep-counts live in
# budget.env -- not here (scratch_guard.sh header, obligation o04).
if [ ! -f "$PRUNE_RETENTION" ]; then
    say "missing $PRUNE_RETENTION (node data_budget) -- pre-flight failure"
    exit 2
fi
say "startup retention prune"
# No --root: the pruner reads the pinned mission root from budget.env, exactly as
# the guard does (scratch_guard.sh header, obligation o28). Passing a root from
# the environment here would re-open the very channel that pinning closed. Only
# --basedir is passed, and only to name the loop tree this wrapper owns.
python3 "$PRUNE_RETENTION" --basedir "$BASEDIR" --apply \
    || say "prune_retention.py exited non-zero -- the scratch guard below decides whether a cycle may start"

# ---------------------------------------------------------------- scratch guard
# obligation o04 / o27. Every threshold -- the 500 GiB mission-root cap, the
# projected-write allowance and the group free-space floor -- is read by the
# guard from codes/data_budget/budget.env. This wrapper contributes no storage
# number of its own; it only honours the guard's exit code, which is never
# advisory:
#   0  within budget            -> start the cycle
#   1  projected write crosses the mission-root hard cap -> stop, do not resubmit
#   2  group scratch free space below the safety floor   -> stop, do not resubmit
#   3  the guard could not measure                       -> failure
# The startup prune above has already run, so a 1 here is a genuine hard stop
# rather than something a retention pass could clear.
if [ ! -f "$SCRATCH_GUARD" ]; then
    say "missing $SCRATCH_GUARD (node data_budget) -- pre-flight failure"
    exit 2
fi
say "scratch guard (thresholds from codes/data_budget/budget.env)"
bash "$SCRATCH_GUARD" --label "chain link $chaindepth pre-flight"
GUARD_RC=$?
case "$GUARD_RC" in
    0)
        ;;
    1)
        say "scratch_guard exit 1: projected mission-root usage would cross the hard cap -- stopping the chain"
        touch "$BASEDIR/STOP"
        CHAIN_STOP=1
        exit "$KTG_RC_SCRATCH_STOP"
        ;;
    2)
        say "scratch_guard exit 2: group scratch free space below the safety floor -- stopping the chain"
        touch "$BASEDIR/STOP"
        CHAIN_STOP=1
        exit "$KTG_RC_SCRATCH_STOP"
        ;;
    *)
        say "scratch_guard exit $GUARD_RC: the guard could not measure -- treating as a failure"
        exit 2
        ;;
esac

# ---------------------------------------------------------------- run
if [ ! -f "$LOOP_SH" ]; then
    say "missing $LOOP_SH"; exit 2
fi
# synchronous_loop_9x9.sh keeps upstream's git rev-parse (:35) and git show/diff
# (:84-86), so it must run from inside the scratch clone, never the mirror.
cd "$KATAGO_SRC" || { say "cannot cd to \$KATAGO_SRC"; exit 2; }

# obligation o33 (a): a SIGTERM seen anywhere in the pre-flight above means the
# scheduler is already tearing this link down -- slurmstepd sends SIGKILL
# KillWait seconds later -- so launching a three-day loop now can only produce a
# cycle that is killed seconds in, or a link booked as having run when it did
# not. bash defers a trap handler until the foreground command it is waiting on
# returns, so by this line every signal delivered during the pre-flight has been
# seen. Exit as the scheduler termination it is: finalize leaves .failcount alone
# and KEEPS the queued afterany successor, which is the resume path.
if [ "$SCHED_TERM" -eq 1 ]; then
    say "SIGTERM already received during the pre-flight -- not starting the loop; the queued successor is the resume path"
    exit "$KTG_RC_SIGTERM"
fi

say "starting the loop: $LOOP_SH $NAMEPREFIX $BASEDIR $TRAININGNAME $MODELKIND $USEGATING"
LOOP_STARTED=1
bash "$LOOP_SH" "$NAMEPREFIX" "$BASEDIR" "$TRAININGNAME" "$MODELKIND" "$USEGATING"
RC=$?
# obligation o33 (b): record the loop's own status the instant it is known, so a
# SIGTERM arriving after this point cannot be mistaken for the cause of the end.
LOOP_RC="$RC"
LOOP_RC_SET=1
ELAPSED=$(( $(date +%s) - START_EPOCH ))
say "loop exited rc=$RC after ${ELAPSED}s"

# The loop script uses the same code when its own per-cycle scratch_guard call
# refuses a cycle. That is a deliberate stop, not a failure: it must not spend a
# breaker attempt, and the queued successor must not run.
#
# The exit code alone does not prove it, though. Under bash -e any stage inside
# the loop that exits 3 for its own reasons ends the script with 3 as well, and
# reading that as a storage refusal would stop a healthy chain silently, without
# spending an attempt and without anything in the tree to explain it. The
# storage path always writes the brake file first (synchronous_loop_9x9.sh:245
# touches $BASEDIR/STOP, then :246 exits 3), so STOP is the discriminator and
# its absence makes the exit an ordinary failure (obligation o31).
if [ "$RC" -eq "$KTG_RC_SCRATCH_STOP" ]; then
    if [ -e "$BASEDIR/STOP" ]; then
        say "the loop stopped on the storage guard ($BASEDIR/STOP present) -- treating as a deliberate chain stop"
        CHAIN_STOP=1
    else
        say "loop exit $KTG_RC_SCRATCH_STOP with no $BASEDIR/STOP -- not a storage refusal, counting it as a failure"
    fi
fi

# .failcount, the breaker and the successor cancellation are all handled by
# finalize() from the EXIT trap -- one code path for every way this job can end.
exit "$RC"
