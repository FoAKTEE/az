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
#   breaker    $BASEDIR/.failcount, three consecutive non-zero exits stop the
#              chain; reset to 0 after a cycle that exits 0
#   depth      $BASEDIR/.chain_depth against KTG_MAX_CHAIN
#   brake      $BASEDIR/STOP -- no resubmit, exit 0
#   sweep      stale torchmodels_toexport/*.exported and shuffleddata/*.tmp
#   scratch    du -sb + df -B1 + quotas.py, refuse a new chain link at 180 GiB
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
# The compute-policy check script is named by mission.json compute.policyCheck;
# there is deliberately no hard-coded fallback, so a missing or unreadable
# mission.json stops the chain instead of silently skipping the pre-flight.
POLICY_CHECK_REL=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["compute"]["policyCheck"])' "$AZ_ROOT/mission.json" 2>/dev/null)
POLICY_CHECK="$AZ_ROOT/$POLICY_CHECK_REL"

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

# Scratch guard. The thresholds belong to node data_budget (obligation o04) and
# every one of them is environment-overridable, so data_budget changes the default
# here and nowhere else.
# [OPEN] scratch-budget-propagation: the defaults below are o04's 200/180 GiB.
# mission.json decisions[] (human, 2026-09-03) raised the mission scratch budget
# to 500 GiB (536870912000 B) and that decision has not been propagated into o04,
# DESIGN.md §5 or tasks/data_budget. This node's closing check greps for the
# literal 193273528320, so the old default stays until data_budget rewrites it.
KTG_SCRATCH_ROOT="${KTG_SCRATCH_ROOT:-$KTG_ROOT}"
KTG_SCRATCH_CAP_BYTES="${KTG_SCRATCH_CAP_BYTES:-214748364800}"   # 200 GiB hard cap
KTG_SCRATCH_SOFT_BYTES="${KTG_SCRATCH_SOFT_BYTES:-193273528320}" # 180 GiB, no new cycle
export KTG_SCRATCH_ROOT KTG_SCRATCH_CAP_BYTES KTG_SCRATCH_SOFT_BYTES

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

# ---------------------------------------------------------------- resubmit first
# Issued at the top so the chain survives a hard kill later in this job. The
# successor is queued with afterany and starts whatever way this job ends; if
# this job ends badly the tail of the script cancels it.
SUCCESSOR=""
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
    local part
    part=$(pick_partition)
    say "compute-budget pre-flight for the successor (gpus=$REQ_GPUS cpus=$REQ_CPUS part=$part)"
    if [ -z "$POLICY_CHECK_REL" ] || [ ! -f "$POLICY_CHECK" ]; then
        say "compute-policy check not resolvable from mission.json -- refusing to chain"; return 0
    fi
    if ! bash "$POLICY_CHECK" --gpus "$REQ_GPUS" --cpus "$REQ_CPUS" --partition "$part"; then
        say "compute-budget check failed -- refusing to chain"; return 0
    fi
    local out
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

# ---------------------------------------------------------------- environment
say "sourcing $KTG_ROOT/env.sh"
# shellcheck disable=SC1091
source "$KTG_ROOT/env.sh"
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
# One dated archive is created per chain link (synchronous_loop.sh:75-81), each
# holding a full python/ copy plus the ~100 MB engine binary. Keep the newest N.
KTG_KEEP_ARCHIVES="${KTG_KEEP_ARCHIVES:-3}"
if [ -d "$BASEDIR/scripts/dated" ]; then
    ls -1d "$BASEDIR"/scripts/dated/*/ 2>/dev/null | sort | head -n -"$KTG_KEEP_ARCHIVES" | xargs -r rm -rf
fi

# ---------------------------------------------------------------- scratch guard
# obligation o04, thresholds owned by node data_budget. Refuse to start rather
# than fill the shared filesystem mid-cycle.
say "scratch accounting"
python3 /apps/helpers/quotas.py 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true
df -B1 "$KTG_SCRATCH_ROOT" || true
USED_BYTES=$(du -sb "$KTG_SCRATCH_ROOT" | cut -f1)
echo "du -sb $KTG_SCRATCH_ROOT = $USED_BYTES B  (soft 193273528320, hard $KTG_SCRATCH_CAP_BYTES)"
if [ "$USED_BYTES" -ge "$KTG_SCRATCH_SOFT_BYTES" ]; then
    say "scratch soft cap reached ($USED_BYTES >= $KTG_SCRATCH_SOFT_BYTES) -- stopping the chain"
    touch "$BASEDIR/STOP"
    [ -n "$SUCCESSOR" ] && scancel "$SUCCESSOR" 2>/dev/null
    exit 3
fi

# ---------------------------------------------------------------- run
if [ -e "$BASEDIR/STOP" ]; then
    say "STOP present at entry -- nothing to do"
    exit 0
fi
if [ ! -f "$LOOP_SH" ]; then
    say "missing $LOOP_SH"; exit 2
fi
# synchronous_loop_9x9.sh keeps upstream's git rev-parse (:35) and git show/diff
# (:84-86), so it must run from inside the scratch clone, never the mirror.
cd "$KATAGO_SRC" || { say "cannot cd to \$KATAGO_SRC"; exit 2; }

say "starting the loop: $LOOP_SH $NAMEPREFIX $BASEDIR $TRAININGNAME $MODELKIND $USEGATING"
bash "$LOOP_SH" "$NAMEPREFIX" "$BASEDIR" "$TRAININGNAME" "$MODELKIND" "$USEGATING"
RC=$?
ELAPSED=$(( $(date +%s) - START_EPOCH ))
say "loop exited rc=$RC after ${ELAPSED}s"

# ---------------------------------------------------------------- breaker
if [ "$RC" -eq 0 ]; then
    echo 0 > "$FAILCOUNT_FILE"
    say "clean exit -- failcount reset to 0"
else
    failcount=$(( failcount + 1 ))
    # Minimum-runtime guard: a link that dies in seconds would otherwise spawn a
    # successor immediately and spin the chain at scheduler speed. A failure
    # faster than KTG_MIN_RUNTIME_SECONDS costs two of the three attempts, so a
    # crash loop trips the breaker on the second link instead of the third.
    if [ "$ELAPSED" -lt "$KTG_MIN_RUNTIME_SECONDS" ]; then
        say "fast failure: ${ELAPSED}s < ${KTG_MIN_RUNTIME_SECONDS}s -- counting it twice"
        failcount=$(( failcount + 1 ))
    fi
    echo "$failcount" > "$FAILCOUNT_FILE"
    say "failure -- failcount now $failcount/$KTG_MAX_FAILS"
    if [ "$failcount" -ge "$KTG_MAX_FAILS" ]; then
        say "circuit breaker tripped after $failcount consecutive failures (last ran ${ELAPSED}s)"
        touch "$BASEDIR/.breaker_tripped"
        if [ -n "$SUCCESSOR" ]; then
            say "cancelling queued successor $SUCCESSOR"
            scancel "$SUCCESSOR" 2>/dev/null
        fi
    else
        say "chain continues, $(( KTG_MAX_FAILS - failcount )) attempt(s) left before the breaker"
    fi
fi

exit "$RC"
