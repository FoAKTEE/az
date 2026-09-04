#!/bin/bash -l
# node data_budget - exit-code contract for scratch_guard.sh and prune_retention.py.
# Every threshold branch is exercised against a committed constants fixture, so the guard's
# refusal paths are demonstrated rather than asserted. Exits 0 only if all cases match.
#
# Cases A-K: the original threshold contract.
# Cases L-S4 (obligation o28): the loosening vectors a validator demonstrated, each paired
# with a positive control that takes the OTHER branch, so no case can pass without reaching
# the assertion it claims to make.
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
GUARD="$HERE/../scratch_guard.sh"
PRUNE="$HERE/../prune_retention.py"
MISSION_ROOT=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
FAIL=0
PASSED=0

# Scratch for the negative tests. It must live on the GROUP SCRATCH POOL: a temp root under
# /tmp would make `df -B1` report the login node's small local filesystem and every case
# below would exit 2 on the group free-space floor instead of reaching the branch under
# test. Cases that assert exit 1 or 3 would then pass for the wrong reason.
WORK="$(mktemp -d "$MISSION_ROOT/runtime/guard_tests.XXXXXX")" || {
  echo "run_guard_tests: cannot create a scratch dir under $MISSION_ROOT/runtime" >&2
  exit 3
}
# Cases N1/O need an identical constants file INSIDE the guard's directory; it is created
# at run time and never committed, so no loose constants file is left lying next to the
# guard where a later caller could point at it.
INTREE_LOOSE="$HERE/loose_probe.$$.env"
# Sweep any probe left behind by a killed run BEFORE the suite starts: a raised-cap
# constants file sitting inside the guard's own directory is inside the allow-list, so it
# must never be allowed to outlive the test that created it.
rm -f -- "$HERE"/loose_probe.*.env
FAKE_QUOTAS="$WORK/fake_quotas.py"
cleanup() { chmod -R u+rwX -- "$WORK" 2>/dev/null; rm -rf -- "$WORK" "$INTREE_LOOSE"; }
trap cleanup EXIT

expect() {   # expect <want_exit> <name> -- <command...>
  local want="$1" name="$2"; shift 3
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    PASSED=$((PASSED+1)); printf 'PASS  exit %-2s  %s\n' "$rc" "$name"
  else
    FAIL=$((FAIL+1));     printf 'FAIL  exit %-2s (wanted %s)  %s\n' "$rc" "$want" "$name"
  fi
  printf '%s\n' "$out" | sed 's/^/      | /'
}

expect_out() {   # expect_out <want_exit> <grep -E pattern that MUST appear> <name> -- <command...>
  local want="$1" pat="$2" name="$3"; shift 4
  local out rc hit
  out="$("$@" 2>&1)"; rc=$?
  hit=0; printf '%s\n' "$out" | grep -Eq -- "$pat" && hit=1
  if [ "$rc" -eq "$want" ] && [ "$hit" -eq 1 ]; then
    PASSED=$((PASSED+1)); printf 'PASS  exit %-2s  %s\n' "$rc" "$name"
  else
    FAIL=$((FAIL+1))
    printf 'FAIL  exit %-2s (wanted %s), pattern %s  %s\n' \
      "$rc" "$want" "$([ "$hit" -eq 1 ] && echo matched || echo MISSING)" "$name"
    printf '      | (required pattern: %s)\n' "$pat"
  fi
  printf '%s\n' "$out" | sed 's/^/      | /'
}

echo "== scratch_guard exit-code contract  $(date -Iseconds) =="
echo "guard: $GUARD"
echo

expect 0 "A. within budget, default 20 GiB projection" -- \
  bash "$GUARD" --quiet --label "A within-budget"

expect 1 "B. projected write crosses the 500 GiB hard cap" -- \
  bash "$GUARD" --quiet --projected-bytes 529312333000 --label "B projected-over-cap"

expect 1 "C. a stray KTG_SCRATCH_HARD_BYTES in the environment cannot loosen the cap" -- \
  env KTG_SCRATCH_HARD_BYTES=99999999999999 bash "$GUARD" --quiet \
      --projected-bytes 529312333000 --label "C env-cannot-loosen"

expect 1 "D. current usage already over the cap, zero projection" -- \
  env KTG_BUDGET_ENV="$HERE/fixture_tinycap.env" bash "$GUARD" --quiet \
      --projected-bytes 0 --label "D over-cap-now"

expect 2 "E. group scratch free space below the safety floor" -- \
  env KTG_BUDGET_ENV="$HERE/fixture_failfloor.env" bash "$GUARD" --quiet \
      --label "E group-fail-floor"

expect 0 "F. group free below the warn floor only: warns, does not abort" -- \
  env KTG_BUDGET_ENV="$HERE/fixture_warnfloor.env" bash "$GUARD" --quiet \
      --label "F warn-only"

expect 3 "G. mission root does not exist" -- \
  bash "$GUARD" --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/no-such-root

expect 3 "H. malformed --projected-bytes" -- \
  bash "$GUARD" --quiet --projected-bytes 12.5GB

expect 3 "I. unknown argument" -- \
  bash "$GUARD" --quiet --no-such-flag

expect 3 "J. constants file missing" -- \
  env KTG_BUDGET_ENV="$HERE/no-such-constants.env" bash "$GUARD" --quiet

expect 0 "K. quotas.py unreadable: falls back to df on the same pool and warns" -- \
  env KTG_QUOTAS_BIN=/apps/helpers/does-not-exist.py bash "$GUARD" --quiet \
      --label "K df-fallback"

# ======================================================================================
# o28 repair cases. Every one is a REAL negative test: the paired positive control shows
# the guard would have taken the other branch under the vector being closed, so a case
# cannot pass by never reaching the assertion.
# ======================================================================================

# --- vector: KTG_CYCLE_PROJECTED_BYTES in the environment zeroes the projection --------
# Control M first: with the 1 MB fixture cap and an EMPTY root, a projection of 0 exits 0.
# So case L's exit 1 can only come from the pinned 20 GiB file default being used instead
# of the exported 0 - the branch is provably reached.
expect 0 "M. control: an EXPLICIT --projected-bytes 0 is caller control and passes" -- \
  env KTG_BUDGET_ENV="$HERE/fixture_tinycap.env" bash "$GUARD" --quiet \
      --root "$WORK" --projected-bytes 0 --label "M explicit-zero-projection"

expect_out 1 'projected write      : 21474836480 B' \
  "L. KTG_CYCLE_PROJECTED_BYTES=0 in the environment cannot zero the projection" -- \
  env KTG_CYCLE_PROJECTED_BYTES=0 KTG_BUDGET_ENV="$HERE/fixture_tinycap.env" \
      bash "$GUARD" --quiet --root "$WORK" --label "L env-zero-projection"

# --- vector: KTG_SCRATCH_ROOT / --root redirect the measured root ----------------------
# Control Q first: --root on the same empty dir with the 1 MB fixture cap exits 0 and is
# announced. Case P exports the SAME path as KTG_SCRATCH_ROOT and passes no --root: it
# must measure the 7.5 GB mission root instead and exit 1 on the 1 MB cap.
expect_out 0 '^NOTE  measuring an OVERRIDDEN root: --root ' \
  "Q. control: an EXPLICIT --root is caller control, and is announced in the log" -- \
  env KTG_BUDGET_ENV="$HERE/fixture_tinycap.env" bash "$GUARD" --quiet \
      --root "$WORK" --projected-bytes 0 --label "Q explicit-root-announced"

expect_out 1 "^root                 : $MISSION_ROOT\$" \
  "P. KTG_SCRATCH_ROOT in the environment cannot redirect the measured root" -- \
  env KTG_SCRATCH_ROOT="$WORK" KTG_BUDGET_ENV="$HERE/fixture_tinycap.env" \
      bash "$GUARD" --quiet --projected-bytes 0 --label "P env-root-redirect"

# --- vector: KTG_BUDGET_ENV swaps the constants for a loose file -----------------------
# One file, two locations. N1 proves the CONTENT would raise the cap to 99999999999999 B
# and let a 529312333000 B projection through; N2 refuses the byte-identical file from
# outside the guard's directory. The refusal is therefore about location, not content.
sed 's/^KTG_SCRATCH_HARD_BYTES=.*/KTG_SCRATCH_HARD_BYTES=99999999999999/' \
    "$HERE/../budget.env" > "$INTREE_LOOSE"
cp -- "$INTREE_LOOSE" "$WORK/loose.env"

expect_out 0 'hard cap 99999999999999 B' \
  "N1. control: a raised-cap constants file INSIDE the guard dir is honoured" -- \
  env KTG_BUDGET_ENV="$INTREE_LOOSE" bash "$GUARD" --quiet \
      --projected-bytes 529312333000 --label "N1 in-tree-loose-file"

expect_out 3 'refusing an out-of-tree constants file' \
  "N2. the byte-identical file OUTSIDE the guard dir is refused, cap not raised" -- \
  env KTG_BUDGET_ENV="$WORK/loose.env" bash "$GUARD" --quiet \
      --projected-bytes 529312333000 --label "N2 out-of-tree-loose-file"

# --- vector: a constants file that re-opens the environment channel --------------------
# fixture_legacy_shellform.env is in-tree, so N2's location rule does not apply; it is
# refused for its FORM. Without this rule, exporting KTG_SCRATCH_HARD_BYTES together with
# such a file would loosen the cap again.
expect_out 3 'constants file is not literal' \
  "O. an in-tree constants file with a \${...} indirection is refused by the guard" -- \
  env KTG_BUDGET_ENV="$HERE/fixture_legacy_shellform.env" bash "$GUARD" --quiet \
      --label "O non-literal-constants"

# --- KTG_QUOTAS_BIN is caller control but cannot LOOSEN the free-space check -----------
# A fake reporter claiming 99999.00 TB free is discarded by min(quotas.py, df -B1), so the
# unreachable fail floor in fixture_failfloor.env still aborts. Case E is the same
# assertion with the real reporter; this case shows the min() rule doing the work.
cat > "$FAKE_QUOTAS" <<'FAKEQ'
print("| FS | Used | Quota | Used % |")
print("| /scratch/ssci-anima/ | 0.01 TB | 99999.00 TB | 0% |")
FAKEQ

expect_out 2 'VIOLATION: group scratch free space' \
  "R. a fake KTG_QUOTAS_BIN overstating free space cannot lift the group floor" -- \
  env KTG_QUOTAS_BIN="$FAKE_QUOTAS" KTG_BUDGET_ENV="$HERE/fixture_failfloor.env" \
      bash "$GUARD" --quiet --label "R fake-quotas-cannot-loosen"

# --- the pruner under the documented call contract -------------------------------------
# The o28 defect itself: `python3 prune_retention.py` with no --root exited 3 on a root
# literally named '${KTG_SCRATCH_ROOT:-...}', so the startup sweep in the scratch_guard.sh
# header pruned nothing. Dry run (no --apply) - it must reach the mission root and report.
expect_out 0 "^root      : $MISSION_ROOT\$" \
  "S1. pruner with no --root (documented contract) dry-runs the MISSION ROOT" -- \
  python3 "$PRUNE"

expect_out 0 'pinned to the file default' \
  "S2. the legacy \${NAME:-default} form resolves to the file default, not the env" -- \
  env KTG_SCRATCH_ROOT="$WORK" python3 "$PRUNE" \
      --budget-env "$HERE/fixture_legacy_shellform.env"

expect_out 0 "^root      : $MISSION_ROOT\$" \
  "S3. an exported KTG_SCRATCH_ROOT cannot redirect the pruner" -- \
  env KTG_SCRATCH_ROOT="$WORK" python3 "$PRUNE"

expect_out 3 'refusing an out-of-tree constants file' \
  "S4. pruner refuses an out-of-tree --budget-env" -- \
  python3 "$PRUNE" --budget-env "$WORK/loose.env"

# --- du -sb is retried, but a partial total is never accepted --------------------------
# The bug this closes: a single non-zero `du -sb` (an entry vanishing from under the walk on
# a live mission root) used to be read as "cannot measure", so the guard exited 3 and a
# healthy cycle was aborted. It was caught here as an intermittent failure of case D.
# T1 control: the same root WITHOUT the unreadable subdirectory measures fine and exits 1
# on the 1 MB fixture cap - so T2's exit 3 is the du path, not the tree being missing.
# T2: du exits non-zero on every attempt AND prints a partial total (7 GB of readable files
# under an unreadable subdir); the guard must discard that under-count and refuse, because
# accepting it would let an unreadable subtree hide usage from the cap.
DUROOT="$WORK/duroot"
mkdir -p "$DUROOT/readable" "$DUROOT/locked"
head -c 2000000 /dev/zero > "$DUROOT/readable/big.bin"
head -c 2000000 /dev/zero > "$DUROOT/locked/hidden.bin"

expect_out 1 'projected root total : ' \
  "T1. control: the same root, nothing unreadable, measures and refuses on the cap" -- \
  env KTG_BUDGET_ENV="$HERE/fixture_tinycap.env" bash "$GUARD" --quiet \
      --root "$DUROOT" --projected-bytes 0 --label "T1 du-readable"

chmod 000 "$DUROOT/locked"
expect_out 3 'partial total is discarded' \
  "T2. du -sb non-zero on every attempt: partial total discarded, guard refuses" -- \
  env KTG_BUDGET_ENV="$HERE/fixture_tinycap.env" KTG_DU_RETRY_SLEEP=1 \
      bash "$GUARD" --quiet --root "$DUROOT" --projected-bytes 0 --label "T2 du-unreadable"
chmod 755 "$DUROOT/locked"

echo
echo "== $PASSED passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
