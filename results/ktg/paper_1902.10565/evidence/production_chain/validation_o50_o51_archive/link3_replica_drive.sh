#!/bin/bash
# drive.sh <tag> <codes_dir> <mode>   mode: stage | cycle | term-wrapper | term-group | term-group-ignore
set -u
M=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/work/o50_o51_validator
S=$M/sandbox
tag=$1; CODES=$2; mode=$3
export PATH="$S/shim:$PATH"
export KTG_ROOT="$S/root" AZ_ROOT="$S/az" KTG_CODES="$CODES" KTG_LOOP_SBATCH="$M/loop.sbatch.link3"
export KTG_SCRATCH_GUARD="$S/src/guard_stub.sh" KTG_PRUNE_RETENTION="$S/src/prune_stub.py"
export TRAIN_WRAPPER="$S/src/train_stub.sh" EXPORT_WRAPPER="$S/src/export_stub.sh"
export SLURM_CPUS_PER_TASK=32 SLURM_JOB_NAME=ktg-loop KTG_MIN_RUNTIME_SECONDS=2 KTG_MON_PS_INTERVAL=1 KTG_MON_GPU_INTERVAL=5
export KTG_SHIM_LOG="$S/shim_$tag.log" BASEDIR="$S/root/loop" SLURM_JOB_ID=700001
rm -rf "$S/root/loop" "$S/root/logs"; mkdir -p "$S/root/loop" "$S/root/logs"; : > "$KTG_SHIM_LOG"
LOG=$M/run_$tag.log
case $mode in
  stage) export KTG_STAGE_ONLY=1 ;;
  cycle) export KTG_ONE_CYCLE=1 KTG_STUB_SELFPLAY_TICKS=3 ;;
  term-wrapper) export KTG_ONE_CYCLE=1 KTG_STUB_SELFPLAY_TICKS=25 ;;
  term-group) export KTG_STUB_SELFPLAY_TICKS=2000 ;;
  term-group-ignore) export KTG_STUB_SELFPLAY_TICKS=40 KTG_STUB_IGNORE_TERM=1 KTG_ONE_CYCLE=1 ;;
esac
setsid bash -c 'echo $$ > "$0.pid"; exec bash "$1"' "$M/run_$tag" "$M/loop.sbatch.link3" > "$LOG" 2>&1 &
sleep 0.5; WRAP=$(cat "$M/run_$tag.pid")
case $mode in
  term-wrapper|term-group|term-group-ignore)
    for i in $(seq 1 600); do grep -q 'Started 30 games' "$LOG" 2>/dev/null && break; sleep 0.05; done
    echo "kill at $(date -Is) mode=$mode wrapper=$WRAP pgid=$(ps -o pgid= -p $WRAP|tr -d ' ')"
    if [ $mode = term-wrapper ]; then kill -TERM "$WRAP"; else kill -TERM -- -"$WRAP"; fi ;;
esac
while kill -0 "$WRAP" 2>/dev/null; do sleep 0.2; done
sleep 0.3; rm -rf "$M/root_$tag"; cp -a "$S/root/loop" "$M/root_$tag"
# exit status: read from the wrapper's own final say line is not available; capture via wait is impossible across setsid, so record from log
echo "---- $tag ($mode) ended $(date -Is); .cycles_completed='$(cat $S/root/loop/.cycles_completed 2>/dev/null)' .failcount='$(cat $S/root/loop/.failcount 2>/dev/null)' shim: $(tr '\n' ';' < $KTG_SHIM_LOG)"
grep -nE "SIGTERM|scheduler termination|loop exited rc=|clean exit|failcount|Exited cleanly|abandoning|cycle 1 complete|KTG_STAGE_ONLY|escalat|Terminated|stage_monitor: stopped|successor" "$LOG" | cut -c1-200
