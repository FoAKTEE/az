#!/bin/bash -l
#SBATCH --job-name=ktg-l40s-probe
#SBATCH --account=ssci-anima
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --time=00:40:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/l40s-probe-%j.log
#SBATCH --error=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/l40s-probe-%j.log
#
# Mission ktg-train, node arxiv-1902.10565::env_build.
#
# Question, settled by measurement and not by argument: does the mission engine
# binary -- built with CUDA arch images for sm_50..sm_86, sm_87, sm_90, sm_100,
# sm_120 but NOT sm_89 -- run on an L40S (Ada, sm_89), which the human admitted
# as a production partition on 2026-09-04?
#
# Phase A runs the engine and torch as they stand and records everything.
# Phase B fires ONLY if phase A shows a missing kernel image or a pathologically
# slow benchmark: it patches the scratch clone's cpp/CMakeLists.txt with
# codes/env/cmake-sm89.diff, rebuilds incrementally, and re-runs phase A's legs.
# The ref-code mirror is never touched.
#
# The binary is shared with the queued production chain job, so the sha256 of
# $KATAGO_BIN is recorded before and after.

set -uo pipefail

R=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
REPO=/home/schmidt/ssci-haiyangw/az
CODES="$REPO/results/ktg/paper_1902.10565/codes/env"
MODEL_KIND=b7c96h3tfrs
POS_LEN=9
NPROC=${SLURM_CPUS_PER_TASK:-8}

# B200 reference, one search thread, 9x9, 80 visits, same model kind
# (evidence/env/smoke.txt, slurm job 298018).
B200_VISITS_PER_S=2322.17
# "pathologically slow" = worse than a tenth of the B200 figure. An L40S is
# expected to be several times slower than a B200; an order of magnitude below
# it would be the signature of a JIT/fallback path rather than of the device.
SLOW_FLOOR=232.2

T="$R/evidence/env/l40s-${SLURM_JOB_ID}.txt"
mkdir -p "$R/evidence/env" "$R/logs" "$R/runtime/l40s_probe"
: > "$T"

say()  { echo; echo "=== [$(date -Is)] $* ==="; }
rec()  { echo "$*" | tee -a "$T"; }
die()  { echo "!!! FAILED: $*" | tee -a "$T" >&2; exit 2; }

# leg <label> <cmd...> -- run, tee into the transcript, record the exit code.
LEG_FAIL=0
leg() {
  local label="$1"; shift
  echo "--- $label" | tee -a "$T"
  "$@" >>"$T" 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then echo "[OK] $label (exit 0)" | tee -a "$T"
  else echo "[FAIL] $label (exit $rc)" | tee -a "$T"; LEG_FAIL=1; fi
  return 0
}

rec "== ktg-train l40s engine probe -- node arxiv-1902.10565::env_build"
rec "== slurm job ${SLURM_JOB_ID} on $(hostname), partition ${SLURM_JOB_PARTITION:-?}, $(date -Is)"
rec "== cpus=${NPROC} mem=48G walltime=00:40:00"

say "device"
echo "--- nvidia-smi (name, compute cap, memory, driver)" | tee -a "$T"
nvidia-smi --query-gpu=index,name,compute_cap,memory.total,driver_version \
           --format=csv,noheader 2>&1 | tee -a "$T"

say "environment"
source "$R/env.sh" || die "source env.sh"
rec "KATAGO_BIN = $KATAGO_BIN"
echo "--- module list" | tee -a "$T"
module list 2>&1 | tee -a "$T"

SHA_BEFORE=$(sha256sum "$KATAGO_BIN" | awk '{print $1}')
rec "katago sha256 BEFORE = $SHA_BEFORE"
rec "katago mtime  BEFORE = $(date -Is -r "$KATAGO_BIN")"

arch_list() { cuobjdump --list-elf "$KATAGO_BIN" | grep -oE 'sm_[0-9]+' | sort -u | tr '\n' ' '; echo; }
sm89_count() { cuobjdump --list-elf "$KATAGO_BIN" | grep -c 'sm_89'; }
sm89_ptx_count() { cuobjdump --list-ptx "$KATAGO_BIN" | grep -c 'sm_89'; }

SM89_ELF_BEFORE=$(sm89_count)
SM89_PTX_BEFORE=$(sm89_ptx_count)
rec "cuobjdump --list-elf arch set BEFORE : $(arch_list)"
rec "cuobjdump --list-elf | grep -c sm_89 BEFORE = $SM89_ELF_BEFORE"
rec "cuobjdump --list-ptx | grep -c sm_89 BEFORE = $SM89_PTX_BEFORE"

MODEL="$R/runtime/smoke/model-$MODEL_KIND/model.bin.gz"
CFG="$KATAGO_SRC/cpp/configs/gtp_example.cfg"
[ -f "$MODEL" ] || die "model not found: $MODEL"
rec "model  = $MODEL  ($(stat -c %s "$MODEL") bytes, sha256 $(sha256sum "$MODEL" | awk '{print $1}'))"
rec "config = $CFG"

cd "$R/runtime/l40s_probe" || die "cd runtime/l40s_probe"

# ------------------------------------------------------------------ phase legs
BENCH_LOG=""
run_phase() {   # run_phase <tag>
  local tag="$1"
  LEG_FAIL=0
  BENCH_LOG="$R/runtime/l40s_probe/benchmark-${tag}.txt"

  say "phase $tag: engine legs"
  echo "########## PHASE $tag ##########" | tee -a "$T"

  leg "[$tag] katago version" "$KATAGO_BIN" version
  leg "[$tag] katago runtests" "$KATAGO_BIN" runtests

  echo "--- [$tag] katago benchmark ($MODEL_KIND, 9x9, 80 visits, 1 thread)" | tee -a "$T"
  "$KATAGO_BIN" benchmark -model "$MODEL" -config "$CFG" -v 80 -t 1 -boardsize 9 \
      >"$BENCH_LOG" 2>&1
  BENCH_RC=$?
  cat "$BENCH_LOG" >> "$T"
  if [ "$BENCH_RC" -eq 0 ]; then echo "[OK] [$tag] katago benchmark (exit 0)" | tee -a "$T"
  else echo "[FAIL] [$tag] katago benchmark (exit $BENCH_RC)" | tee -a "$T"; LEG_FAIL=1; fi

  VISITS=$(grep -oE 'visits/s = [0-9.]+ nnEvals/s' "$BENCH_LOG" | tail -1 | grep -oE '[0-9.]+' | head -1)
  [ -n "${VISITS:-}" ] || VISITS=0
  NOKERNEL=$(grep -ci 'no kernel image is available' "$BENCH_LOG")
  rec "[$tag] benchmark visits/s (1 thread, 9x9, 80 visits) = $VISITS   (B200 reference $B200_VISITS_PER_S)"
  rec "[$tag] 'no kernel image is available' occurrences in benchmark log = $NOKERNEL"

  leg "[$tag] torch cuda capability + forward/backward ($MODEL_KIND, pos_len $POS_LEN)" \
      python "$R/runtime/smoke/torch_smoke.py" "$MODEL_KIND" "$POS_LEN"

  PHASE_FAIL=$LEG_FAIL
}

run_phase A
A_VISITS=$VISITS
A_NOKERNEL=$NOKERNEL
A_FAIL=$PHASE_FAIL

# ------------------------------------------------------------- rebuild verdict
say "phase A verdict"
REBUILD=0
REASON=""
if [ "$A_NOKERNEL" -gt 0 ]; then
  REBUILD=1; REASON="benchmark log carries 'no kernel image is available'"
elif [ "$A_FAIL" -ne 0 ]; then
  REBUILD=1; REASON="at least one phase-A leg exited non-zero"
elif awk -v v="$A_VISITS" -v f="$SLOW_FLOOR" 'BEGIN{exit !(v < f)}'; then
  REBUILD=1; REASON="benchmark visits/s $A_VISITS is below the pathological floor $SLOW_FLOOR (a tenth of the B200 $B200_VISITS_PER_S)"
fi
rec "PHASE A: legs_failed=$A_FAIL visits_per_s=$A_VISITS no_kernel_image=$A_NOKERNEL"
if [ "$REBUILD" -eq 1 ]; then
  rec "PHASE A VERDICT: the stock binary does NOT serve this device acceptably -- $REASON"
else
  rec "PHASE A VERDICT: the stock binary runs on this device; no rebuild triggered"
fi

SHA_AFTER="$SHA_BEFORE"
SM89_ELF_AFTER="$SM89_ELF_BEFORE"
SM89_PTX_AFTER="$SM89_PTX_BEFORE"
B_VISITS=""
B_FAIL=""

# ------------------------------------------------------------------- phase B
if [ "$REBUILD" -eq 1 ]; then
  say "phase B: add sm_89 to the scratch build clone and rebuild"
  echo "########## PHASE B: sm_89 REBUILD ##########" | tee -a "$T"
  rec "trigger: $REASON"

  PATCH="$CODES/cmake-sm89.diff"
  if grep -q '86 87 89 90 100 120' "$R/build/KataGo/cpp/CMakeLists.txt"; then
    rec "cpp/CMakeLists.txt already carries 89; skipping git apply"
  else
    git -C "$R/build/KataGo" apply --verbose "$PATCH" 2>&1 | tee -a "$T" || die "git apply cmake-sm89.diff"
  fi
  echo "--- cpp/CMakeLists.txt CUDA 12.8 architecture line after the patch" | tee -a "$T"
  grep -n 'CMAKE_CUDA_ARCHITECTURES 50 52 53 60 61 62 70 72 75 80 86 87 89' \
       "$R/build/KataGo/cpp/CMakeLists.txt" 2>&1 | tee -a "$T"

  echo "--- cmake --build (incremental, -j$NPROC)" | tee -a "$T"
  cmake --build "$KATAGO_BUILD" -j"$NPROC" > "$R/runtime/l40s_probe/rebuild.log" 2>&1
  BUILD_RC=$?
  tail -40 "$R/runtime/l40s_probe/rebuild.log" | tee -a "$T"
  rec "cmake --build exit = $BUILD_RC   (full log $R/runtime/l40s_probe/rebuild.log)"
  [ "$BUILD_RC" -eq 0 ] || die "incremental rebuild failed"
  [ -x "$KATAGO_BIN" ] || die "katago binary missing after rebuild"

  SHA_AFTER=$(sha256sum "$KATAGO_BIN" | awk '{print $1}')
  SM89_ELF_AFTER=$(sm89_count)
  SM89_PTX_AFTER=$(sm89_ptx_count)
  rec "katago sha256 AFTER = $SHA_AFTER"
  rec "katago mtime  AFTER = $(date -Is -r "$KATAGO_BIN")"
  rec "cuobjdump --list-elf arch set AFTER : $(arch_list)"
  rec "cuobjdump --list-elf | grep -c sm_89 AFTER = $SM89_ELF_AFTER"
  rec "cuobjdump --list-ptx | grep -c sm_89 AFTER = $SM89_PTX_AFTER"
  SM89_FAIL=0
  if [ "$SM89_ELF_AFTER" -le 0 ]; then
    rec "[FAIL] sm_89 still absent from the rebuilt binary"
    SM89_FAIL=1
  else
    rec "[OK] sm_89 ELF images present in the rebuilt binary ($SM89_ELF_AFTER)"
  fi

  run_phase B
  B_VISITS=$VISITS
  B_FAIL=$(( PHASE_FAIL | SM89_FAIL ))
fi

# ------------------------------------------------------------------- verdict
say "verdict"
{
  echo
  echo "########## SUMMARY ##########"
  echo "device                     : $(nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader)"
  echo "katago sha256 before       : $SHA_BEFORE"
  echo "katago sha256 after        : $SHA_AFTER"
  echo "sm_89 ELF images  before/after : $SM89_ELF_BEFORE / $SM89_ELF_AFTER"
  echo "sm_89 PTX images  before/after : $SM89_PTX_BEFORE / $SM89_PTX_AFTER"
  echo "phase A legs_failed        : $A_FAIL"
  echo "phase A visits/s (1 thread): $A_VISITS   (B200 reference $B200_VISITS_PER_S)"
  echo "phase A no-kernel-image    : $A_NOKERNEL"
  echo "rebuild triggered          : $REBUILD ${REASON:+-- $REASON}"
  if [ "$REBUILD" -eq 1 ]; then
    echo "phase B legs_failed        : $B_FAIL"
    echo "phase B visits/s (1 thread): $B_VISITS"
  fi
} | tee -a "$T"

FINAL_FAIL=$A_FAIL
if [ "$REBUILD" -eq 1 ]; then FINAL_FAIL=$B_FAIL; fi

if [ "$FINAL_FAIL" -eq 0 ]; then
  rec "L40S PROBE RESULT: PASS"
  exit 0
else
  rec "L40S PROBE RESULT: FAIL"
  exit 1
fi
