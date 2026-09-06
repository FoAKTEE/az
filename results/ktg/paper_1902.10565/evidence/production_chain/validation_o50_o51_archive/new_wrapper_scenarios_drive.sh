#!/bin/bash
# drive2.sh <tag> <mode> -- NEW wrapper (repo loop.sbatch), SIGTERM to the wrapper pid only (the site's form)
set -u
M=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/work/o50_o51_validator
S=$M/sandbox2; R=/weka/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes
tag=$1; mode=$2
export PATH="$S/shim:$PATH"
export KTG_ROOT="$S/root" AZ_ROOT="$S/az" KTG_CODES="$R" KTG_LOOP_SBATCH="$R/loop/loop.sbatch"
export KTG_SCRATCH_GUARD="$M/src2/guard_stub.sh" KTG_PRUNE_RETENTION="$M/src2/prune_stub.py"
export TRAIN_WRAPPER="$M/src2/train_stub.sh" EXPORT_WRAPPER="$M/src2/export_stub.sh"
export SLURM_CPUS_PER_TASK=32 SLURM_JOB_NAME=ktg-loop KTG_MIN_RUNTIME_SECONDS=2 KTG_MON_PS_INTERVAL=1 KTG_MON_GPU_INTERVAL=5
export KTG_SHIM_LOG="$S/shim_$tag.log" BASEDIR="$S/root/loop" SLURM_JOB_ID=700002 KTG_STUB_SELFPLAY_TICKS=3
rm -rf "$S/root/loop" "$S/root/logs"; mkdir -p "$S/root/loop" "$S/root/logs"; : > "$KTG_SHIM_LOG"
LOG=$M/run2_$tag.log; marker=""
case $mode in
  gate)    export KTG_STUB_GATE_SLEEP=200; marker='STUB gatekeeper sleeping' ;;
  train)   export KTG_STUB_TRAIN_SLEEP=120; marker='STUB train sleeping' ;;
  shuffle) export KTG_STUB_SHUFFLE_SLEEP=120; marker='STUB shuffle sleeping' ;;
  grace15) export KTG_STUB_SELFPLAY_TICKS=2000 KTG_STUB_IGNORE_TERM=1; marker='Started 30 games' ;;
  double)  export KTG_STUB_SELFPLAY_TICKS=2000; marker='Started 30 games' ;;
esac
setsid bash -c 'echo $$ > "$0.pid"; exec bash "$1"' "$M/run2_$tag" "$R/loop/loop.sbatch" > "$LOG" 2>&1 &
sleep 0.5; WRAP=$(cat "$M/run2_$tag.pid")
for i in $(seq 1 1200); do grep -q -- "$marker" "$LOG" 2>/dev/null && break; sleep 0.05; done
K0=$(date +%s.%N); echo "kill -TERM $WRAP (wrapper only) at $(date -Is) mode=$mode"; kill -TERM "$WRAP"
if [ $mode = double ]; then sleep 0.5; kill -TERM "$WRAP"; fi
while kill -0 "$WRAP" 2>/dev/null; do sleep 0.1; done
K1=$(date +%s.%N); echo "wrapper gone after $(python3 -c "print(round($K1-$K0,1))") s"
sleep 0.3
echo "---- $tag ($mode): .cycles_completed='$(cat $S/root/loop/.cycles_completed 2>/dev/null)' .failcount='$(cat $S/root/loop/.failcount 2>/dev/null)' shim: $(tr '\n' ';' < $KTG_SHIM_LOG)"
echo "  leftover processes in the loop group / sandbox: $(pgrep -f "$S/root" | wc -l)"
grep -nE "SIGTERM|scheduler termination|loop exited rc=|clean exit|failcount|Exited cleanly|abandoning|cycle 1 complete|escalat|SIGKILL|Terminated|stage_monitor: stopped|successor queued|not sent" "$LOG" | cut -c1-210
