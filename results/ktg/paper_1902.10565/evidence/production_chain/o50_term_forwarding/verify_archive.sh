#!/bin/bash
# Verifier for the SGF archive step -- DISABLED BY DEFAULT, byte-neutral at 0.
# The human has not decided; this asserts that the committed state is OFF and that
# OFF costs nothing, and that the machinery works when it is switched on.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
AZ="$(cd "$D/../../../../../.." && pwd)"
C="$AZ/results/ktg/paper_1902.10565/codes"
A="$C/data_budget/archive_sgf.sh"

# (i) parse + mode
bash -n "$A"; bash -n "$C/loop/loop.sbatch"; bash -n "$C/loop/synchronous_loop_9x9.sh"
[ "$(stat -c %a "$A")" = "755" ]

# (ii) the committed knob file ships the flag OFF, and every call site is guarded
grep -qx 'KTG_ARCHIVE_SGF=0' "$C/loop/knobs_9x9.env"
grep -q 'if \[ "${KTG_ARCHIVE_SGF:-0}" = "1" \]' "$C/loop/loop.sbatch"
grep -q 'if \[ "${KTG_ARCHIVE_SGF:-0}" = "1" \]' "$C/loop/synchronous_loop_9x9.sh"

# (iii) with the flag unset the archiver creates nothing at all
T="${CHANDRA_RUNTIME:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime}"
mkdir -p "$T"
S=$(mktemp -d "$T/verify_archive.XXXXXX")
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/selfplay/t9-s1-d1/sgfs"
printf '(;FF[4]SZ[9];B[cc])\n' > "$S/selfplay/t9-s1-d1/sgfs/A.sgfs"
bash "$A" "$S" >/dev/null 2>&1
[ ! -e "$S/archive" ]
# (iv) with the flag on it hard-links, is idempotent, and survives the prune
out=$(KTG_ARCHIVE_SGF=1 bash "$A" "$S")
printf '%s' "$out" | grep -q 'linked=1 copied=0 already-linked=0 failed=0'
[ "$S/archive/sgf/t9-s1-d1/A.sgfs" -ef "$S/selfplay/t9-s1-d1/sgfs/A.sgfs" ]
out=$(KTG_ARCHIVE_SGF=1 bash "$A" "$S")
printf '%s' "$out" | grep -q 'linked=0 copied=0 already-linked=1'
rm -rf "$S/selfplay/t9-s1-d1"
[ -s "$S/archive/sgf/t9-s1-d1/A.sgfs" ]

# (v) prune_retention protects the archive tree
python3 "$C/data_budget/prune_retention.py" --root "$S" --basedir "$S" \
    --budget-env "$C/data_budget/budget.env" 2>&1 | grep -q 'PROTECT .*archive .*SGF archive'

# (vi) the recorded harness run, including the staged-file no-op proof
grep -q 'archive harness: 17 passed, 0 failed' "$D/archive_output.txt"
grep -q 'ok    3b the staged trees are byte-identical' "$D/archive_output.txt"
grep -q 'ok    3c no archive/ directory was created at 0' "$D/archive_output.txt"
grep -q 'ok    7b check_knobs_9x9 says PASS' "$D/archive_output.txt"
echo "SGF_ARCHIVE_VERIFIED: KTG_ARCHIVE_SGF=0 in the committed knob file; at 0 nothing is spawned and the KTG_STAGE_ONLY staged tree is byte-identical to HEAD's; at 1 the archiver hard-links, is idempotent, outlives the prune, and the pruner protects it"
