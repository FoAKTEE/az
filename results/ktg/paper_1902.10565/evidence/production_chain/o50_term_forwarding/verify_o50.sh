#!/bin/bash
# Verifier for obligation o50 -- the wrapper's SIGTERM reaches the loop.
# Static: the wiring is in the committed scripts. Executed: the recorded harness
# run (harness_output.txt, produced by harness.sh in this directory, CPU only, no
# Slurm job, no scheduler call) asserted every conjunct and passed all of them.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
AZ="$(cd "$D/../../../../../.." && pwd)"
L="$AZ/results/ktg/paper_1902.10565/codes/loop/loop.sbatch"
S="$AZ/results/ktg/paper_1902.10565/codes/loop/synchronous_loop_9x9.sh"
H="$D/harness_output.txt"

# (i) both scripts parse
bash -n "$L"; bash -n "$S"

# (ii) the loop is launched in the BACKGROUND, in its own process group, and reaped
grep -qE '^bash "\$LOOP_SH" .* "\$USEGATING" &$' "$L"
grep -q 'LOOP_PID=\$!' "$L"
grep -q 'set -m 2>/dev/null || true' "$L"
grep -q 'LOOP_PGID=\$(ps -o pgid= -p "\$LOOP_PID"' "$L"
grep -q 'wait "\$LOOP_PID"' "$L"
grep -q '_tick_before' "$L"
# the foreground call is gone
! grep -qE '^bash "\$LOOP_SH" "\$NAMEPREFIX" .*"\$USEGATING"$' "$L"

# (iii) on_term forwards, with a bounded escalation to SIGKILL
grep -q 'signal_loop_tree TERM' "$L"
grep -q 'signal_loop_tree KILL' "$L"
grep -q 'KTG_TERM_GRACE_SECONDS' "$L"
grep -q 'kill -"\$sig" -- "-\$LOOP_PGID"' "$L"

# (iv) the loop abandons the cycle at 143 and its tee survives the signal
grep -q 'trap on_loop_term TERM' "$S"
grep -q 'exit 143' "$S"
grep -q 'tee_through_term()' "$S"
[ "$(grep -c 'tee_through_term "\$BASEDIR"' "$S")" -eq 4 ]
! grep -q '| tee -a "\$BASEDIR"' "$S"

# (v) the recorded harness run: every conjunct of o50, all green
grep -q 'o50 harness: 47 passed, 0 failed' "$H"
grep -q 'ok    B1 the TERM trap fired at all' "$H"
grep -q 'ok    B2 the trap fired within 2 s' "$H"
grep -q 'ok    B3 the signal was forwarded to the loop process group' "$H"
grep -q 'ok    B4 the stub katago saw the TERM' "$H"
grep -q "ok    B4b the stage stdout.txt kept the engine's shutdown lines" "$H"
grep -q 'ok    B5 the loop abandoned the cycle at 143' "$H"
grep -q 'ok    B6 the wrapper reaped rc=143' "$H"
grep -q 'ok    B7 finalize ran (monitor stopped)' "$H"
grep -q 'ok    B8 classified as scheduler termination' "$H"
grep -q 'ok    B11 the queued successor was NOT cancelled' "$H"
grep -q 'ok    B13 NO SIGKILL was needed' "$H"
grep -q 'ok    B15 the cut cycle did not bump .cycles_completed' "$H"
grep -q 'ok    A3 clean exit -> failcount reset to 0' "$H"
grep -q 'ok    C1 escalated to SIGKILL' "$H"
grep -q 'ok    E1 the signal was seen after the status' "$H"
grep -q 'ok    G1 the pre-flight TERM was seen' "$H"
echo "O50_TERM_FORWARDING_VERIFIED: loop launched in its own process group and reaped; SIGTERM forwarded to that group; katago exits via 'Exited cleanly after signal'; loop exits 143; finalize runs, failcount untouched, successor kept; no SIGKILL needed (harness 47/47)"
