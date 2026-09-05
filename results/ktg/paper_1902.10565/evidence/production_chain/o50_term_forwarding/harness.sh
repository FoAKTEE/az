#!/bin/bash
# ============================================================================
# o50 harness -- codes/loop/loop.sbatch SIGTERM forwarding.
# CPU only, on the login node. NO Slurm job is submitted and NONE is signalled:
# sbatch / scancel / squeue / sinfo / scontrol all resolve to shims under
# $S/shim that only append to $S/shim.log. The live chain (305318 / 314831) is
# never read and never touched; this harness runs entirely inside
# $W = /scratch/.../ktg-train/work/o50_o51, which is not runs/p1.
# ============================================================================
set -u
W=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/work/o50_o51
S="$W/sandbox"
AZ=/home/schmidt/ssci-haiyangw/az
CODES="$AZ/results/ktg/paper_1902.10565/codes"
LOOPSB="$CODES/loop/loop.sbatch"

export PATH="$S/shim:$PATH"
export KTG_ROOT="$S/root"
export AZ_ROOT="$S/az"
export KTG_CODES="$CODES"
export KTG_LOOP_SBATCH="$LOOPSB"
export KTG_SCRATCH_GUARD="$S/src/guard_stub.sh"
export KTG_PRUNE_RETENTION="$S/src/prune_stub.py"
export TRAIN_WRAPPER="$S/src/train_stub.sh"
export EXPORT_WRAPPER="$S/src/export_stub.sh"
export SLURM_CPUS_PER_TASK=32
export SLURM_JOB_NAME=ktg-loop
export KTG_MIN_RUNTIME_SECONDS=2
export KTG_MON_PS_INTERVAL=1
export KTG_MON_GPU_INTERVAL=5
export KTG_SHIM_LOG="$S/shim.log"
export BASEDIR="$S/root/loop"

PASS=0; FAIL=0
ck() { # ck <label> <condition-cmd...>
  local label="$1"; shift
  if "$@"; then printf '    ok    %s\n' "$label"; PASS=$((PASS+1));
  else printf '    FAIL  %s\n' "$label"; FAIL=$((FAIL+1)); fi
}
has()  { grep -qE -- "$2" "$1"; }
hasnt(){ ! grep -qE -- "$2" "$1"; }

reset_state() {
    rm -rf "$S/root/loop" "$S/root/logs"
    mkdir -p "$S/root/loop" "$S/root/logs"
    : > "$S/shim.log"
}

wait_for() {   # wait_for <file> <regex> <timeout_s>
    local f="$1" re="$2" t="$3" i
    for i in $(seq 1 $(( t * 20 ))); do
        grep -qE -- "$re" "$f" 2>/dev/null && return 0
        sleep 0.05
    done
    return 1
}

epoch_of_say() {  # first `say` line matching $2 in $1 -> epoch seconds
    local ts
    ts=$(grep -E -m1 -- "$2" "$1" | sed -n 's/^=== \[\([^]]*\)\].*/\1/p')
    [ -n "$ts" ] && date -d "$ts" +%s || echo ""
}

sect() { echo; echo "########## $*"; }

echo "host: $(hostname)  date: $(date -Is)"
echo "az HEAD: $(cd $AZ && git rev-parse --short HEAD)   bash: $BASH_VERSION"
echo "under test:"
sha256sum "$LOOPSB" "$CODES/loop/synchronous_loop_9x9.sh" | sed 's/^/    /'
echo "scheduler shims on PATH (nothing reaches the real scheduler):"
ls "$S/shim" | sed 's/^/    /'

# ---------------------------------------------------------------- A: clean cycle
sect "A: one clean cycle (KTG_ONE_CYCLE=1) -- the unchanged path, loop exits 0"
reset_state
LOG="$S/A.log"
KTG_ONE_CYCLE=1 SLURM_JOB_ID=800001 KTG_STUB_SELFPLAY_TICKS=3 bash "$LOOPSB" > "$LOG" 2>&1 &
WRAP=$!
wait "$WRAP"; RC_A=$?
grep -E "starting the loop|loop pid|loop exited rc=|clean exit|cycle 1 complete|successor queued|Exited cleanly" "$LOG" | sed 's/^/  /'
echo "  wrapper exit status: $RC_A"
ck "A1 wrapper exits 0"                     test "$RC_A" = "0"
ck "A2 loop exited rc=0"                    has "$LOG" 'loop exited rc=0'
ck "A3 clean exit -> failcount reset to 0"  has "$LOG" 'clean exit -- failcount reset to 0'
ck "A4 .failcount == 0"                     test "$(cat $BASEDIR/.failcount)" = "0"
ck "A5 one cycle recorded"                  test "$(cat $BASEDIR/.cycles_completed)" = "1"
ck "A6 loop got its own process group"      has "$LOG" 'in its own process group'
ck "A7 no TERM was involved"                hasnt "$LOG" 'SIGTERM received'
ck "A8 no SIGKILL escalation"               hasnt "$LOG" 'escalating to SIGKILL'

# ---------------------------------------------------------------- B: the o50 proof
sect "B: SIGTERM to the WRAPPER ONLY, mid-selfplay (the walltime path)"
reset_state
LOG="$S/B.log"
SLURM_JOB_ID=800002 KTG_STUB_SELFPLAY_TICKS=2000 bash "$LOOPSB" > "$LOG" 2>&1 &
WRAP=$!
wait_for "$LOG" 'Started 30 games' 60 || echo "  (selfplay never started)"
KILL_EPOCH=$(date +%s)
echo "  kill -TERM $WRAP   at $(date -Is)   (the wrapper pid ONLY, not its group)"
kill -TERM "$WRAP"
wait "$WRAP"; RC_B=$?
TRAP_EPOCH=$(epoch_of_say "$LOG" 'SIGTERM received')
echo "  wrapper exit status: $RC_B"
grep -nE "SIGTERM received|forwarding SIGTERM|SIGTERM -> loop process group|abandoning the cycle|Exited cleanly after signal|loop exited rc=|scheduler termination|escalating to SIGKILL|stage_monitor: stopped" "$LOG" | sed 's/^/  /'
echo "  kill epoch $KILL_EPOCH ; trap epoch ${TRAP_EPOCH:-none} ; delta $(( ${TRAP_EPOCH:-0} - KILL_EPOCH ))s"
ck "B1 the TERM trap fired at all"          test -n "$TRAP_EPOCH"
ck "B2 the trap fired within 2 s"           test $(( ${TRAP_EPOCH:-99999} - KILL_EPOCH )) -le 2
ck "B3 the signal was forwarded to the loop process group" has "$LOG" 'SIGTERM -> loop process group'
ck "B4 the stub katago saw the TERM"        has "$LOG" 'Exited cleanly after signal'
ck "B4b the stage stdout.txt kept the engine's shutdown lines" \
                                            has "$BASEDIR/selfplay/stdout.txt" 'Exited cleanly after signal'
ck "B5 the loop abandoned the cycle at 143" has "$LOG" 'abandoning the cycle in flight, exiting 143'
ck "B6 the wrapper reaped rc=143"           has "$LOG" 'loop exited rc=143'
ck "B7 finalize ran (monitor stopped)"      has "$LOG" 'stage_monitor: stopped'
ck "B8 classified as scheduler termination" has "$LOG" 'scheduler termination at walltime after'
ck "B9 failcount left alone"                has "$LOG" 'failcount left at 0'
ck "B10 .failcount still 0"                 test "$(cat $BASEDIR/.failcount)" = "0"
ck "B11 the queued successor was NOT cancelled" hasnt "$S/shim.log" 'scancel'
ck "B12 a successor WAS queued"             has "$LOG" 'successor queued: 900001'
ck "B13 NO SIGKILL was needed"              hasnt "$LOG" 'escalating to SIGKILL'
ck "B14 wrapper exit status 143"            test "$RC_B" = "143"
ck "B15 the cut cycle did not bump .cycles_completed" test ! -s "$BASEDIR/.cycles_completed"

# ---------------------------------------------------------------- C: escalation
sect "C: SIGTERM with an engine that IGNORES it -- the bounded SIGKILL escalation"
reset_state
LOG="$S/C.log"
SLURM_JOB_ID=800003 KTG_STUB_SELFPLAY_TICKS=2000 KTG_STUB_IGNORE_TERM=1 \
  KTG_TERM_GRACE_SECONDS=3 bash "$LOOPSB" > "$LOG" 2>&1 &
WRAP=$!
wait_for "$LOG" 'Started 30 games' 60 || echo "  (selfplay never started)"
KILL_EPOCH=$(date +%s)
kill -TERM "$WRAP"
wait "$WRAP"; RC_C=$?
END_EPOCH=$(date +%s)
grep -nE "SIGTERM received|forwarding SIGTERM|SIG(TERM|KILL) -> loop process group|escalating to SIGKILL|loop exited rc=|scheduler termination" "$LOG" | sed 's/^/  /'
echo "  wrapper exit status: $RC_C ; wall from kill to wrapper exit: $(( END_EPOCH - KILL_EPOCH ))s"
ck "C1 escalated to SIGKILL"                has "$LOG" 'escalating to SIGKILL'
ck "C2 SIGKILL went to the loop group"      has "$LOG" 'SIGKILL -> loop process group'
ck "C3 the loop was reaped as 137"          has "$LOG" 'loop exited rc=137'
ck "C4 still classified as scheduler termination" has "$LOG" 'scheduler termination at walltime after'
ck "C5 finalize ran"                        has "$LOG" 'stage_monitor: stopped'
ck "C6 the whole teardown fitted in KillWait (30 s)" test $(( END_EPOCH - KILL_EPOCH )) -lt 30
ck "C7 the queued successor was NOT cancelled" hasnt "$S/shim.log" 'scancel'
ck "C8 the stub never logged a clean signal exit" hasnt "$LOG" 'Exited cleanly after signal'

# ---------------------------------------------------------------- D: plain failure
sect "D: the loop FAILS (no signal) -- the unchanged failure accounting"
reset_state
LOG="$S/D.log"
SLURM_JOB_ID=800004 KTG_STUB_SELFPLAY_RC=1 bash "$LOOPSB" > "$LOG" 2>&1 &
WRAP=$!
wait "$WRAP"; RC_D=$?
grep -nE "loop exited rc=|failure rc=|fast failure|failcount now|chain continues" "$LOG" | sed 's/^/  /'
echo "  wrapper exit status: $RC_D"
ck "D1 loop exited rc=1"                    has "$LOG" 'loop exited rc=1'
ck "D2 counted as a failure"                has "$LOG" 'failure rc=1 -- failcount now'
ck "D3 no scheduler-termination claim"      hasnt "$LOG" 'scheduler termination at walltime'
ck "D4 wrapper exit status 1"               test "$RC_D" = "1"

# ---------------------------------------------------------------- E: o33(b)
sect "E: SIGTERM that arrives AFTER the loop already failed (o33 (b) must still win)"
reset_state
LOG="$S/E.log"
SLURM_JOB_ID=800005 KTG_STUB_SELFPLAY_RC=1 bash "$LOOPSB" > "$LOG" 2>&1 &
WRAP=$!
# finalize's stage_monitor stop drains the samplers for min(GPU_INTERVAL,3)+0.5 s,
# which is the window this signal has to land in.
wait_for "$LOG" 'loop exited rc=1' 120 && kill -TERM "$WRAP" 2>/dev/null
wait "$WRAP"; RC_E=$?
grep -nE "loop exited rc=|SIGTERM received|already exited rc=|failure rc=|failcount now|scheduler termination" "$LOG" | sed 's/^/  /'
echo "  wrapper exit status: $RC_E"
ck "E1 the signal was seen after the status" has "$LOG" 'the loop had already exited rc=1 when the SIGTERM arrived'
ck "E2 the failure was counted, not waved through" has "$LOG" 'failure rc=1 -- failcount now'
ck "E3 no scheduler-termination claim"      hasnt "$LOG" 'scheduler termination at walltime'

# ---------------------------------------------------------------- F: storage stop
sect "F: the storage guard stops the chain (CHAIN_STOP) -- unchanged"
reset_state
LOG="$S/F.log"
SLURM_JOB_ID=800006 KTG_STUB_GUARD_RC=1 bash "$LOOPSB" > "$LOG" 2>&1 &
WRAP=$!
wait "$WRAP"; RC_F=$?
grep -nE "scratch_guard exit 1|deliberate chain stop|cancelling queued successor|failcount left at" "$LOG" | sed 's/^/  /'
echo "  wrapper exit status: $RC_F ; shim log:"; sed 's/^/    /' "$S/shim.log"
ck "F1 deliberate chain stop"               has "$LOG" 'deliberate chain stop'
ck "F2 the successor WAS cancelled"         has "$S/shim.log" 'scancel 900001'
ck "F3 wrapper exit status 3"               test "$RC_F" = "3"

# ---------------------------------------------------------------- G: pre-flight TERM
sect "G: SIGTERM during the pre-flight, before the loop starts (o33 (a)) -- unchanged"
reset_state
LOG="$S/G.log"
SLURM_JOB_ID=800007 KTG_STUB_GUARD_SLEEP=6 bash "$LOOPSB" > "$LOG" 2>&1 &
WRAP=$!
wait_for "$LOG" 'scratch guard \(thresholds' 60 && sleep 1 && kill -TERM "$WRAP" 2>/dev/null
wait "$WRAP"; RC_G=$?
grep -nE "SIGTERM received|already received during the pre-flight|scheduler termination|failcount left at" "$LOG" | sed 's/^/  /'
echo "  wrapper exit status: $RC_G"
ck "G1 the pre-flight TERM was seen"        has "$LOG" 'SIGTERM already received during the pre-flight'
ck "G2 the loop was never started"          hasnt "$LOG" 'starting the loop: '
ck "G3 classified as scheduler termination" has "$LOG" 'scheduler termination at walltime'
ck "G4 the successor was NOT cancelled"     hasnt "$S/shim.log" 'scancel'
ck "G5 wrapper exit status 143"             test "$RC_G" = "143"

echo
echo "########## RESULT"
echo "o50 harness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
