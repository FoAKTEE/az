#!/bin/bash
# probe_train_9x9.sh -- mission ktg-train, task paper_code_map_training section 2.
# Driver for leg D2 of codes/loop/smoke_loop.sbatch: sources the mission env, caps the
# torch thread count (o11_torch_threads_cap), runs probe_train_9x9.py (assertions 1-3
# plus the scorebelief_len cross-check) and probe_resume_9x9.sh (assertion 4), and
# exits non-zero if either fails. No job of its own.
#
#   usage: probe_train_9x9.sh [REAL_NPZ_DIR]
#          default $KTG_SMOKE_BASEDIR/selfplay/random/tdata

set -u
set -o pipefail

KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
AZ_ROOT="${AZ_ROOT:-/home/schmidt/ssci-haiyangw/az}"
KTG_CODES="${KTG_CODES:-$AZ_ROOT/results/ktg/paper_1902.10565/codes}"
W="${KTG_SMOKE_BASEDIR:-$KTG_ROOT/runs/smoke}"
WP="${KTG_PROBE_TRAIN_DIR:-$KTG_ROOT/runs/smoke_probe/train}"
SRC_NPZ_DIR="${1:-$W/selfplay/random/tdata}"

if [ -z "${KATAGO_SRC:-}" ]; then
  set +u
  # shellcheck disable=SC1091
  source "$KTG_ROOT/env.sh"
  set -u
fi
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4

echo "probe_train_9x9.sh"
echo "  npz dir     = $SRC_NPZ_DIR"
echo "  probe dir   = $WP"
echo "  OMP/MKL     = $OMP_NUM_THREADS / $MKL_NUM_THREADS"
echo

mkdir -p "$WP"

FAILURES=0

echo "=== assertions 1-3 (+ scorebelief_len): probe_train_9x9.py"
python3 "$KTG_CODES/eval/probe_train_9x9.py" "$SRC_NPZ_DIR" --json "$WP/probe_train.json"
RC1=$?
echo "  probe_train_9x9.py exit = $RC1"
[ "$RC1" -eq 0 ] || FAILURES=$((FAILURES + 1))

echo
echo "=== assertion 4: probe_resume_9x9.sh"
bash "$KTG_CODES/eval/probe_resume_9x9.sh" "$SRC_NPZ_DIR"
RC2=$?
echo "  probe_resume_9x9.sh exit = $RC2"
[ "$RC2" -eq 0 ] || FAILURES=$((FAILURES + 1))

echo
echo "  FAILURES = $FAILURES"
if [ "$FAILURES" -eq 0 ]; then
  echo "PROBE_TRAIN_PACKET: PASS"
  exit 0
fi
echo "PROBE_TRAIN_PACKET: FAIL"
exit 1
