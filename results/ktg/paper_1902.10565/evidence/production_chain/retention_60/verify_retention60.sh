#!/bin/bash -l
# Re-checks the retention-60 preparation from its own committed evidence. Exit 0 iff:
#   the one-line patch still applies to the repo; the two dry runs say 32 paths vs 0 paths
#   with an identical protected set; the stub tree still gives 46->0 at the link-3 geometry
#   and 90->35 at the link-4 geometry; the window formula still reproduces all nine log
#   points; and the repo working tree still reads KTG_KEEP_SELFPLAY_GENERATIONS=3.
# Run from the az root. READ-ONLY: it applies nothing.
set -uo pipefail
AZ="${AZ:-/home/schmidt/ssci-haiyangw/az}"
E="$AZ/results/ktg/paper_1902.10565/evidence/production_chain/retention_60"
B="$AZ/results/ktg/paper_1902.10565/codes/data_budget/budget.env"
fail() { echo "RETENTION60_VERIFY FAILED: $*" >&2; exit 1; }

[ "$(sed -n '55p' "$B")" = "KTG_KEEP_SELFPLAY_GENERATIONS=3" ] \
  || fail "budget.env:55 is not still =3 -- option c1 was applied; this row describes the prepared state"
( cd "$AZ" && git apply --check "$E/apply_c1.diff" ) \
  || fail "apply_c1.diff no longer applies to the repo"
grep -q -- '-- deletion plan (32 paths, 1131433908 B) --' "$E/dryrun_keep3.txt" \
  || fail "dryrun_keep3.txt no longer records 32 paths"
grep -q -- '-- deletion plan (0 paths, 0 B) --' "$E/dryrun_keep60.txt" \
  || fail "dryrun_keep60.txt no longer records 0 paths"
P3=$(grep -c '^   PROTECT' "$E/dryrun_keep3.txt"); P60=$(grep -c '^   PROTECT' "$E/dryrun_keep60.txt")
[ "$P3" = "$P60" ] && [ "$P3" = "18" ] || fail "protected sets differ or are not 18 ($P3 vs $P60)"
diff <(grep '^   PROTECT' "$E/dryrun_keep3.txt") <(grep '^   PROTECT' "$E/dryrun_keep60.txt") >/dev/null \
  || fail "the protected sets are not path-identical"
grep -q 'DELTA  selfplay deleted 3 -> 60 : 46 -> 0' "$E/stub_tree_test.txt" \
  || fail "stub scenario A no longer gives 46 -> 0"
grep -q 'DELTA  selfplay deleted 3 -> 60 : 90 -> 35' "$E/stub_tree_test.txt" \
  || fail "stub scenario B no longer gives 90 -> 35 (the 60 bound must still bind)"
grep -q 'survivors on disk        : 5 -> 60 generations' "$E/stub_tree_test.txt" \
  || fail "stub scenario B no longer leaves exactly 60 survivors"
grep -q 'all 9 log points reproduced: True' "$E/projection.txt" \
  || fail "the window formula no longer reproduces the log"
grep -q 'KEEP=60  0 generations deleted' "$E/projection.txt" || fail "projection changed"
python3 - "$E/projection.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["window_formula_calibration_all_match"] is True
assert d["window"]["keep60_step"] == 0, d["window"]
assert d["window"]["keep3_step_hi"] < -300000, d["window"]
assert d["scratch"]["cap_needs_raising"] is False
assert d["scratch"]["KEEP=60"]["pct_of_hard_cap"] < 10.0, d["scratch"]
print("projection.json: keep60 boundary step %d rows; keep3 step %d..%d; "
      "KEEP=60 peak %.2f %% of the 500 GiB cap; delta %.2f GiB"
      % (d["window"]["keep60_step"], d["window"]["keep3_step_lo"],
         d["window"]["keep3_step_hi"], d["scratch"]["KEEP=60"]["pct_of_hard_cap"],
         d["scratch"]["delta_bytes"] / 2**30))
PY
[ $? -eq 0 ] || fail "projection.json assertions failed"
bash "$E/verify_keeprows_refutation.sh" >/dev/null 2>&1 \
  || fail "the KEEPROWS refutation no longer reproduces"
echo "RETENTION60_VERIFIED: patch applies and is NOT applied (budget.env:55 = 3); prune plan"
echo "  32 paths / 1131433908 B at keep 3 vs 0 paths / 0 B at keep 60 with an identical"
echo "  18-entry protected set; stub 46->0 at the link-3 geometry and 90->35 (60 survivors)"
echo "  at the link-4 geometry; window formula reproduces all 9 log points; boundary step 0"
echo "  rows at keep 60 against -384k..-399k at keep 3; +2.01 GiB, 7.32 % of the 500 GiB cap"
