#!/bin/bash
# Verifier for the human stop of the 9x9 production chain, 2026-09-06.
#
# Checks, in order:
#   1. the pending afterany successor 314831 is CANCELLED and never ran
#   2. the loop job 305318 is COMPLETED with ExitCode 0:0
#   3. the wrapper log shows the STOP brake path and a clean finalize
#   4. no ktg-loop job is left in the queue
#   5. runs/p1 dot-state is the final state, STOP present, breaker not tripped
#   6. the checkpoint directory exists with the recorded size and file count
#   7. MANIFEST.sha256 is intact and every file in it verifies
#   8. the best/latest net is the one the ledger row names, by sha256
#
# Exit 0 iff every check passes. Prints one line per check.
set -uo pipefail

JOB=305318
SUCC=314831
BASE=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/p1
BASE_REAL=/weka/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/p1   # the path the wrapper log prints
LOG=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/loop-305318.log
CKPT=/home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop
NET=t9-s28711040-d3032547
NET_SHA=4cbedf24ac86f97f1d15ec69706161e7ac98c3f3a2fddadb543d40bea897f49c
MANIFEST_SHA=ef75ba6c3155593a687daaf70e0b3ef5f0c705af6ec17974e8f12bc0a7efc4d2
WANT_FILES=10956          # files covered by the manifest
WANT_BYTES=7683842860     # du -sb over the checkpoint dir, final
WANT_CYCLES=249

RC=0
ok()   { printf 'PASS  %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; RC=1; }

# ---- 1. the successor was cancelled before the brake was set ----------------
S=$(sacct -j "$SUCC" -X -n -o State,Elapsed 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//')
case "$S" in
  CANCELLED*00:00:00) ok "successor $SUCC cancelled without running ($S)" ;;
  *)                  bad "successor $SUCC state is '$S', expected CANCELLED with 00:00:00" ;;
esac

# ---- 2. the loop job ended clean -------------------------------------------
J=$(sacct -j "$JOB" -X -n -P -o State,Elapsed,ExitCode 2>/dev/null)
if [ "$J" = "COMPLETED|18:39:50|0:0" ]; then
  ok "job $JOB $J"
else
  bad "job $JOB is '$J', expected COMPLETED|18:39:50|0:0"
fi

# ---- 3. the log shows the brake path and a clean finalize -------------------
for pat in \
  "STOP file present at $BASE_REAL/STOP -- exiting the loop cleanly." \
  "loop exited rc=0 after 67185s" \
  "clean exit -- failcount reset to 0" \
  "cycle 92 complete -- $WANT_CYCLES cycle(s) recorded"
do
  if grep -qF -- "$pat" "$LOG"; then ok "log: $pat"; else bad "log is missing: $pat"; fi
done
# and nothing after the finalize line
if [ "$(tail -1 "$LOG")" = "=== [2026-09-06T13:03:10-04:00] clean exit -- failcount reset to 0 ===" ]; then
  ok "log ends on the finalize line -- nothing ran after it"
else
  bad "log does not end on the finalize line"
fi

# ---- 4. nothing left in the queue ------------------------------------------
Q=$(squeue -u "$USER" -h -o "%i %j" 2>/dev/null | grep -c ktg-loop)
if [ "$Q" -eq 0 ]; then ok "no ktg-loop job in the queue"; else bad "$Q ktg-loop job(s) still queued"; fi

# ---- 5. final dot-state -----------------------------------------------------
C=$(cat "$BASE/.cycles_completed" 2>/dev/null)
[ "$C" = "$WANT_CYCLES" ] && ok ".cycles_completed = $C" || bad ".cycles_completed = '$C', expected $WANT_CYCLES"
F=$(cat "$BASE/.failcount" 2>/dev/null)
[ "$F" = "0" ] && ok ".failcount = 0" || bad ".failcount = '$F', expected 0"
[ -e "$BASE/STOP" ] && ok "STOP present" || bad "STOP absent -- the brake is not set"
[ -e "$BASE/.breaker_tripped" ] && bad ".breaker_tripped present" || ok ".breaker_tripped absent"
N=$(ls -1 "$BASE/models" 2>/dev/null | wc -l)
[ "$N" -eq 93 ] && ok "93 accepted exports" || bad "$N accepted exports, expected 93"

# ---- 6. the checkpoint is there, at the recorded size -----------------------
if [ -d "$CKPT" ]; then ok "checkpoint dir $CKPT"; else bad "checkpoint dir missing: $CKPT"; fi
B=$(du -sb "$CKPT" 2>/dev/null | cut -f1)
[ "$B" = "$WANT_BYTES" ] && ok "checkpoint size $B B" || bad "checkpoint size $B B, expected $WANT_BYTES"
F=$(find "$CKPT" -type f ! -name MANIFEST.sha256 2>/dev/null | wc -l)
[ "$F" -eq "$WANT_FILES" ] && ok "$F files under the manifest" || bad "$F files, expected $WANT_FILES"

# ---- 7. the manifest is intact and everything in it verifies ---------------
M=$(sha256sum "$CKPT/MANIFEST.sha256" 2>/dev/null | awk '{print $1}')
[ "$M" = "$MANIFEST_SHA" ] && ok "MANIFEST.sha256 sha256 $M" || bad "MANIFEST.sha256 sha256 $M, expected $MANIFEST_SHA"
L=$(wc -l < "$CKPT/MANIFEST.sha256" 2>/dev/null)
[ "$L" -eq "$WANT_FILES" ] && ok "manifest lists $L files" || bad "manifest lists $L files, expected $WANT_FILES"
BADC=$( (cd "$CKPT" && sha256sum -c MANIFEST.sha256 2>&1) | grep -vc ': OK$')
if [ "$BADC" -eq 0 ]; then ok "sha256sum -c: all $WANT_FILES files OK"; else bad "sha256sum -c: $BADC line(s) not OK"; fi

# ---- 8. the net the row names is the net that is saved ---------------------
A=$(sha256sum "$CKPT/p1/models/$NET/model.bin.gz" 2>/dev/null | awk '{print $1}')
[ "$A" = "$NET_SHA" ] && ok "$NET model.bin.gz sha256 $A" || bad "$NET sha256 $A, expected $NET_SHA"

echo
if [ "$RC" -eq 0 ]; then
  echo "STOP_VERIFIED: chain stopped clean at cycle $WANT_CYCLES; $WANT_FILES files ($WANT_BYTES B) saved and hash-verified at $CKPT; best/latest net $NET"
else
  echo "STOP_NOT_VERIFIED: see the FAIL lines above"
fi
exit "$RC"
