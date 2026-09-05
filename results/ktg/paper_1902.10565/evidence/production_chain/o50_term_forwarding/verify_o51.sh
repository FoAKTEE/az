#!/bin/bash
# Verifier for obligation o51 -- the append-only per-net rows/game record.
# Runs the unit tests (which carry the frozen gap-refusal and the validator's
# 16.9087 = 118361 / 7000), then reads the committed record, then runs the closing
# knob check against it. Login node, read-only, no job.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
AZ="$(cd "$D/../../../../../.." && pwd)"
P="$AZ/results/ktg/paper_1902.10565"
HIST="$P/evidence/production_chain/rows_per_game_history.jsonl"

# (i) the unit tests: append idempotence, gap refusal, the contiguous fit
python3 "$P/codes/eval/test_rows_history.py" > /dev/null

# (ii) the committed record: it holds the nets the retention pass deleted, and it
# knows where the gap is
KTG_EVAL_DIR="$P/codes/eval" python3 - "$HIST" <<'PY'
import os, sys
sys.path.insert(0, os.environ["KTG_EVAL_DIR"])
import rows_history as H
recs = H.ordered(H.read_history(sys.argv[1]))
assert len(recs) >= 46, len(recs)
gaps = [(x, y) for x, y, ok in H.adjacency(recs) if not ok]
assert len(gaps) == 1, gaps
assert gaps[0][0]["net"] == "t9-s11352064-d2008893", gaps[0][0]["net"]
assert gaps[0][1]["net"] == "t9-s15847040-d2653436", gaps[0][1]["net"]
assert gaps[0][0]["net_index"] == 37 and gaps[0][1]["net_index"] == 51, "index"
assert "13 accepted net(s) in between have no complete record" in H.describe_gap(*gaps[0])
# the twelve accepted nets the validator could find nowhere are still nowhere, and
# the record says so instead of fitting through them
names = {r["net"] for r in recs}
assert "t9-s11951360-d2093144" not in names
assert "t9-s15547392-d2603142" not in names
print("RECORDS=%d GAPS=%d TAIL_RUN=%d" % (len(recs), len(gaps), len(H.tail_run(recs))))
PY

# (iii) the closing knob check reads the record and still passes
cd "$P"
python3 codes/eval/check_knobs_9x9.py --knobs codes/loop/knobs_9x9.env \
    --throughput "$D/throughput_at_acceptance.json" --rows-file "$HIST" \
    --marginal-nets 3 --trend-nets 9 --horizon-nets 10 > "$D/.verify_o51_run.txt" 2>&1
grep -q '^CHECK_KNOBS_9X9: PASS' "$D/.verify_o51_run.txt"
grep -q 'ROWS/GAME SOURCE: the append-only per-net record' "$D/.verify_o51_run.txt"
grep -qE 'GAP  t9-s11352064-d2008893 \(accepted net 37\) -> t9-s15847040-d2653436 \(accepted net 51\): 13 accepted net\(s\) in between have no complete record' "$D/.verify_o51_run.txt"
rm -f "$D/.verify_o51_run.txt"
echo "O51_ROWS_HISTORY_VERIFIED: the append-only record carries the pruned nets, names its one gap, never fits across it, and check_knobs_9x9 reads it and PASSes"
