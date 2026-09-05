#!/bin/bash
# A/B reproduction of the `tee` defect the o50 harness found, and of its fix.
# Scenario B of harness.sh, run twice: once against a copy of the loop script in
# which tee_through_term is replaced by the plain `tee -a` it had before, and once
# against the committed script. CPU only, no Slurm job, no scheduler call.
set -u
W=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/work/o50_o51
S="$W/sandbox"
AZ=/home/schmidt/ssci-haiyangw/az
CODES="$AZ/results/ktg/paper_1902.10565/codes"
LOOPSB="$CODES/loop/loop.sbatch"
LOOPSH="$CODES/loop/synchronous_loop_9x9.sh"

export PATH="$S/shim:$PATH" KTG_ROOT="$S/root" AZ_ROOT="$S/az" \
  KTG_LOOP_SBATCH="$LOOPSB" KTG_SCRATCH_GUARD="$S/src/guard_stub.sh" \
  KTG_PRUNE_RETENTION="$S/src/prune_stub.py" TRAIN_WRAPPER="$S/src/train_stub.sh" \
  EXPORT_WRAPPER="$S/src/export_stub.sh" SLURM_CPUS_PER_TASK=32 \
  SLURM_JOB_NAME=ktg-loop KTG_MIN_RUNTIME_SECONDS=2 KTG_MON_PS_INTERVAL=1 \
  KTG_MON_GPU_INTERVAL=5 KTG_SHIM_LOG="$S/shim.log" BASEDIR="$S/root/loop"

run_leg() {   # run_leg <label> <codes-dir-with-the-loop-script>
  local label="$1" codes="$2"
  local log="$W/tee_$label.log"
  rm -rf "$S/root/loop" "$S/root/logs"; mkdir -p "$S/root/loop" "$S/root/logs"; : > "$S/shim.log"
  KTG_CODES="$codes" SLURM_JOB_ID="8100${label:0:1}" KTG_STUB_SELFPLAY_TICKS=2000 \
      bash "$LOOPSB" > "$log" 2>&1 &
  local wrap=$! i
  for i in $(seq 1 1200); do grep -q 'Started 30 games' "$log" 2>/dev/null && break; sleep 0.05; done
  kill -TERM "$wrap"; wait "$wrap"; local rc=$?
  echo "--- leg $label: wrapper exit $rc"
  echo "    engine clean-exit line in the LINK LOG      : $(grep -c 'Exited cleanly after signal' "$log")"
  echo "    engine clean-exit line in selfplay/stdout.txt: $(grep -c 'Exited cleanly after signal' "$S/root/loop/selfplay/stdout.txt" 2>/dev/null | head -1)"
  echo "    bytes tee wrote to selfplay/stdout.txt       : $(stat -c %s "$S/root/loop/selfplay/stdout.txt" 2>/dev/null || echo 0)"
  echo "    bash reported a killed child ('Terminated')  : $(grep -c '^Terminated' "$log")"
  echo "    loop abandoned the cycle at 143             : $(grep -c 'abandoning the cycle in flight, exiting 143' "$log")"
}

# leg A: the loop script as it was, with a plain `tee -a`
A="$W/codes_plain_tee"; rm -rf "$A"; mkdir -p "$A"
cp -r "$CODES"/* "$A"/
sed -i 's/| tee_through_term /| tee -a /g' "$A/loop/synchronous_loop_9x9.sh"
grep -c '| tee -a "\$BASEDIR"' "$A/loop/synchronous_loop_9x9.sh" | sed 's/^/plain-tee pipelines in leg A: /'
run_leg A "$A"

# leg B: the committed loop script, with tee_through_term
run_leg B "$CODES"
