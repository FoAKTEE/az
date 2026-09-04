#!/bin/bash -l
#SBATCH --job-name=ktg-loop
#SBATCH --account=ssci-anima
#SBATCH --partition=b200
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=24
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
#   contract   1 GPU, 24 CPUs, 120G, 2-23:30:00 (30 min inside MaxTime),
#              b300 when it has free GPUs, b200 otherwise (a02, a04)
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
#   breaker    $BASEDIR/.failcount, three consecutive non-zero exits stop the
#              chain; reset to 0 only after a cycle that ran and exited 0
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

# The compute-policy check script and the GPU cap are named by mission.json;
# there is deliberately no hard-coded fallback for either, so a missing or
# unreadable mission.json stops the chain instead of silently skipping the
# pre-flight.
POLICY_CHECK_REL=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["compute"]["policyCheck"])' "$AZ_ROOT/mission.json" 2>/dev/null)
POLICY_CHECK="$AZ_ROOT/$POLICY_CHECK_REL"
GPU_CAP_TOTAL=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["compute"]["gpuCapTotal"])' "$AZ_ROOT/mission.json" 2>/dev/null)

# ---------------------------------------------------------------- contract
# 24 CPUs is an honest declaration for this job, not a policy cap: the loop runs
# selfplay MCTS, an 8-process shuffle and the trainer inside one allocation, and
# mission.json compute.cpuPolicy withdrew the 20 % clause on 2026-09-03. Raising
# it is a scaling decision for measure_stage_throughput, not a free win.
REQ_GPUS=1
REQ_CPUS=24
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

# ---------------------------------------------------------------- chain state
FAILCOUNT_FILE="$BASEDIR/.failcount"
CHAINDEPTH_FILE="$BASEDIR/.chain_depth"
[ -f "$FAILCOUNT_FILE" ] || echo 0 > "$FAILCOUNT_FILE"
[ -f "$CHAINDEPTH_FILE" ] || echo 0 > "$CHAINDEPTH_FILE"
failcount=$(cat "$FAILCOUNT_FILE")
chaindepth=$(( $(cat "$CHAINDEPTH_FILE") + 1 ))
echo "$chaindepth" > "$CHAINDEPTH_FILE"
say "chain depth $chaindepth/$KTG_MAX_CHAIN, failcount $failcount/$KTG_MAX_FAILS"

# ---------------------------------------------------------------- partition pick
pick_partition() {
    local p free
    for p in b300 b200; do
        free=$(sinfo -p "$p" -N -h -o "%N" 2>/dev/null | sort -u | while read -r n; do
            info=$(scontrol show node "$n" 2>/dev/null)
            st=$(grep -oP 'State=\K\S+' <<<"$info")
            a=$(grep -oP 'AllocTRES=.*?gres/gpu=\K\d+' <<<"$info"); a=${a:-0}
            case "$st" in *RESERVED*|*DRAIN*|*DOWN*|*MAINT*) echo 0 ;; *) echo $((8-a)) ;; esac
        done | awk '{s+=$1} END{print s+0}')
        if [ "${free:-0}" -ge "$REQ_GPUS" ]; then echo "$p"; return 0; fi
    done
    echo b200
}

# ---------------------------------------------------------------- exit accounting
# State the EXIT trap reads. Declared before resubmit so the trap can never see
# an unset variable, whatever aborts the script.
SUCCESSOR=""      # job id of the queued successor, "" when none
LOOP_STARTED=0    # 1 once the loop script has actually been launched
CHAIN_STOP=0      # 1 for a deliberate stop (storage guard) -- not a failure
SCHED_TERM=0      # 1 once this wrapper has been sent SIGTERM by the scheduler
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
    local rc="${1:-0}" elapsed reason
    [ "$FINALIZED" -eq 0 ] || return 0
    FINALIZED=1
    trap - EXIT
    elapsed=$(( $(date +%s) - START_EPOCH ))

    if [ "$CHAIN_STOP" -eq 1 ]; then
        # Storage refusal: correct behaviour, not a crash. The chain must not
        # continue, but the attempt must not spend a breaker slot either.
        say "deliberate chain stop (rc=$rc after ${elapsed}s) -- failcount left at $failcount"
        cancel_successor "storage guard stopped the chain"
        return 0
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
        say "scheduler termination at walltime after ${elapsed}s ($reason) -- successor continues, failcount left at $failcount"
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
    local part check_out check_rc out
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
    out=$(sbatch --parsable --partition="$part" \
        --dependency=afterany:"${SLURM_JOB_ID:-0}" "$SELF" 2>&1)
    if [[ "$out" =~ ^[0-9]+$ ]]; then
        SUCCESSOR="$out"
        say "successor queued: $SUCCESSOR (partition $part, dependency afterany:${SLURM_JOB_ID:-0})"
    else
        SUCCESSOR=""
        say "sbatch did not return a job id -- chain not extended: $out"
    fi
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

# 24 CPUs for the whole job; keep BLAS/OMP from oversubscribing the trainer.
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

say "starting the loop: $LOOP_SH $NAMEPREFIX $BASEDIR $TRAININGNAME $MODELKIND $USEGATING"
LOOP_STARTED=1
bash "$LOOP_SH" "$NAMEPREFIX" "$BASEDIR" "$TRAININGNAME" "$MODELKIND" "$USEGATING"
RC=$?
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
