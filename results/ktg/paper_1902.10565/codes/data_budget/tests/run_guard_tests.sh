#!/bin/bash -l
# node data_budget - exit-code contract for scratch_guard.sh.
# Every threshold branch is exercised against a committed constants fixture, so the guard's
# refusal paths are demonstrated rather than asserted. Exits 0 only if all cases match.
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../scratch_guard.sh"
FAIL=0
PASSED=0

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

echo
echo "== $PASSED passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
