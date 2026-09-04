#!/bin/bash
# probe_gate_9x9.sh -- mission ktg-train, task paper_code_map_search section 2,
# assertion (d); node arxiv-1902.10565::gating_rule.
#
#   usage: probe_gate_9x9.sh [GATEKEEPER_STDOUT]
#          default $KTG_SMOKE_BASEDIR/gatekeepersgf/stdout.txt
#
# No engine is invoked here: the smoke job's cycle-2 gatekeeper already gated the
# cycle-1 candidate against an EMPTY accepted-models-dir, and this reads that log.
#
# What it asserts, and why it is the gating_rule promotion:
#   LoadModel::findLatestModel returns true unconditionally (cpp/dataio/loadmodel.cpp:77-78,93)
#   with modelName "random" and modelFile "/dev/null"; cpp/program/setup.cpp:126 turns
#   "/dev/null" into debugSkipNeuralNet, i.e. a random-play net. The gatekeeper therefore
#   RUNS in cycle 1 -- it does not skip -- and logs
#     "Loaded accepted neural net random from: /dev/null"   (cpp/command/gatekeeper.cpp:427)
#   Assertion (d): gate_random >= 1.
# Also reported (not asserted here): the candidate verdict line, gatekeeper.cpp:583/603.

set -u
set -o pipefail

KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
W="${KTG_SMOKE_BASEDIR:-$KTG_ROOT/runs/smoke}"
LOG="${1:-$W/gatekeepersgf/stdout.txt}"

echo "probe_gate_9x9.sh"
echo "  gatekeeper log = $LOG"

if [ ! -f "$LOG" ]; then
  echo "FAIL: gatekeeper log not found: $LOG" >&2
  exit 2
fi

GATE_RANDOM=$(grep -c 'Loaded accepted neural net random' "$LOG" || true)
GATE_CANDIDATE=$(grep -c 'Loaded candidate neural net' "$LOG" || true)
GATED=$(grep -cE 'Candidate (won|lost) match' "$LOG" || true)
WON=$(grep -c 'Candidate won match' "$LOG" || true)
LOST=$(grep -c 'Candidate lost match' "$LOG" || true)
NGATING=$(grep -cE '^numGamesPerGating[[:space:]]*=[[:space:]]*200' "$LOG" || true)

echo "  GATE_RANDOM       = $GATE_RANDOM   (Loaded accepted neural net random)"
echo "  gate_candidate    = $GATE_CANDIDATE"
echo "  CANDIDATE_GATED   = $GATED   (won $WON / lost $LOST)"
echo "  numGamesPerGating_200_lines = $NGATING"
echo "  --- matching lines:"
grep -nE 'Loaded (accepted|candidate) neural net|Candidate (won|lost) match|Candidate has already' "$LOG" | sed 's/^/    /' || true

FAILURES=0
if [ "$GATE_RANDOM" -lt 1 ]; then
  echo "FAIL: assertion (d) gate_random = $GATE_RANDOM, expected >= 1"
  FAILURES=$((FAILURES + 1))
fi

echo "  FAILURES = $FAILURES"
if [ "$FAILURES" -eq 0 ]; then
  echo "PROBE_GATE_9X9: PASS"
  exit 0
fi
echo "PROBE_GATE_9X9: FAIL"
exit 1
