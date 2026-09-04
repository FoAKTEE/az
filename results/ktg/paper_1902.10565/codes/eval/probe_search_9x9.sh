#!/bin/bash
# probe_search_9x9.sh -- mission ktg-train, task paper_code_map_search section 2.
# Leg D1 of codes/loop/smoke_loop.sbatch. No job of its own (section 13 of that task).
#
#   usage: probe_search_9x9.sh [NGAMES]        default 20
#
# Runs NGAMES selfplay games with the mission 9x9 config and the six -override-config
# keys that make the two visit regimes distinguishable in the log, against a REAL
# exported net (the smoke's cycle-1 candidate, wherever the gate left it), then hands
# the log and the written data to probe_search_9x9.py.
#
# Why each override (task paper_code_map_search section 10):
#   logSearchInfo=true              cpp/program/play.cpp:2611 -> emits "Root visits: N" at :779
#   logGamesEvery=1                 :684, so every game is logged, not one in ten
#   reduceVisits=false              :1151-1187 would taper a winning side to 100 visits,
#                                   which is indistinguishable from a cheap search
#   normalAsymmetricPlayoutProb=0.0
#   handicapAsymmetricPlayoutProb=0.0
#   estimateLeadProb=0.0            all three perturb root visits
# The four keys actually being MEASURED -- cheapSearchProb, cheapSearchVisits, maxVisits,
# rootDesiredPerChildVisitsCoeff -- are never touched.
#
# env in: KTG_ROOT, KTG_SMOKE_BASEDIR (default $KTG_ROOT/runs/smoke), KATAGO_BIN,
#         KTG_PROBE_MODEL (override the net directory to symlink)
# out   : $KTG_ROOT/runs/smoke_probe/search/{selfplay,logs,models,probe_search.json}
# The multi-GB logSearchInfo log is deleted after extraction (scratch is at 94 % group
# usage); the metrics JSON and the printed summary are the retained evidence.

set -u
set -o pipefail

NGAMES="${1:-20}"

KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
AZ_ROOT="${AZ_ROOT:-/home/schmidt/ssci-haiyangw/az}"
KTG_CODES="${KTG_CODES:-$AZ_ROOT/results/ktg/paper_1902.10565/codes}"
W="${KTG_SMOKE_BASEDIR:-$KTG_ROOT/runs/smoke}"
WP="${KTG_PROBE_SEARCH_DIR:-$KTG_ROOT/runs/smoke_probe/search}"
SP_CFG="$KTG_CODES/cfg/selfplay_9x9.cfg"

if [ -z "${KATAGO_BIN:-}" ]; then
  set +u
  # shellcheck disable=SC1091
  source "$KTG_ROOT/env.sh"
  set -u
fi

echo "probe_search_9x9.sh"
echo "  ngames     = $NGAMES"
echo "  basedir    = $W"
echo "  probe dir  = $WP"
echo "  katago_bin = ${KATAGO_BIN:-<unset>}"
echo "  config     = $SP_CFG"

if [ ! -x "${KATAGO_BIN:-}" ]; then
  echo "FAIL: KATAGO_BIN unset or not executable" >&2
  exit 2
fi

# ---- locate the cycle-1 candidate -------------------------------------------
# The gate may have left it in models/ (accepted), rejectedmodels/ (rejected) or
# modelstobetested/ (not yet gated). Whichever it is, the probe runs a real net:
# take the OLDEST model.bin.gz under $W, which is cycle 1's candidate.
MODEL_SRC="${KTG_PROBE_MODEL:-}"
if [ -z "$MODEL_SRC" ]; then
  MODEL_SRC="$(find "$W/models" "$W/rejectedmodels" "$W/modelstobetested" \
                 -maxdepth 2 -name model.bin.gz -printf '%T@ %p\n' 2>/dev/null \
               | sort -n | head -n 1 | cut -d' ' -f2-)"
fi
if [ -z "$MODEL_SRC" ] || [ ! -f "$MODEL_SRC" ]; then
  echo "FAIL: no exported model.bin.gz found under $W/{models,rejectedmodels,modelstobetested}" >&2
  echo "      the probe requires the smoke cycle-1 candidate (a REAL net)" >&2
  exit 3
fi
MODEL_NAME="$(basename "$(dirname "$MODEL_SRC")")"
echo "  model      = $MODEL_SRC  (name $MODEL_NAME)"

rm -rf "$WP/selfplay" "$WP/models" "$WP/logs"
mkdir -p "$WP/selfplay" "$WP/models/$MODEL_NAME" "$WP/logs"
# A file symlink, not a directory symlink: LoadModel::findLatestModel uses
# recursive_directory_iterator (which does not descend into symlinked dirs) with
# is_regular_file (which does follow a symlinked file) -- loadmodel.cpp:65-68.
ln -sfn "$MODEL_SRC" "$WP/models/$MODEL_NAME/model.bin.gz"

OVERRIDES='logSearchInfo=true,logGamesEvery=1,reduceVisits=false,normalAsymmetricPlayoutProb=0.0,handicapAsymmetricPlayoutProb=0.0,estimateLeadProb=0.0'
LOG="$WP/logs/probe_search.log"

echo "  overrides  = $OVERRIDES"
echo "  running selfplay ..."
T0=$(date +%s)
"$KATAGO_BIN" selfplay \
  -config "$SP_CFG" \
  -models-dir "$WP/models" \
  -output-dir "$WP/selfplay" \
  -max-games-total "$NGAMES" \
  -override-config "$OVERRIDES" > "$LOG" 2>&1
RC=$?
T1=$(date +%s)
echo "  selfplay exit_code = $RC   elapsed_s = $((T1 - T0))   log_bytes = $(stat -c %s "$LOG" 2>/dev/null || echo 0)"
echo "  --- last 8 log lines:"
tail -n 8 "$LOG" | sed 's/^/    /'
if [ "$RC" -ne 0 ]; then
  echo "FAIL: probe selfplay exited $RC" >&2
  exit "$RC"
fi

echo
python3 "$KTG_CODES/eval/probe_search_9x9.py" "$WP/selfplay" "$LOG" --json "$WP/probe_search.json"
PYRC=$?

# section 13: never keep the logSearchInfo log.
LOGBYTES=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
head -n 400 "$LOG" > "$WP/logs/probe_search_head.txt" 2>/dev/null || true
rm -f "$LOG"
echo "  deleted $LOG ($LOGBYTES bytes); kept the first 400 lines at $WP/logs/probe_search_head.txt"

exit "$PYRC"
