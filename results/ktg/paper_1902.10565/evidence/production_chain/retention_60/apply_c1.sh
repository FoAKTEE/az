#!/bin/bash -l
# apply_c1.sh -- memo option (c1): KTG_KEEP_SELFPLAY_GENERATIONS 3 -> 60.
#
# PREPARED, NOT APPLIED. The human has not decided. This script refuses to touch anything
# without an explicit --yes (or KTG_C1_CONFIRM=1), and it never signals, edits or reads any
# file a running job owns.
#
# WHAT IT DOES, in order:
#   1  refuses unless --yes                                  (the human's decision gate)
#   2  asserts budget.env:55 currently reads =3               (nothing else has moved it)
#   3  applies apply_c1.diff -- one line, one file
#   4  asserts budget.env:55 now reads =60
#   5  runs codes/eval/check_knobs_9x9.py twice: with the frozen smoke evidence (its
#      documented default) and with the production evidence. Both exit 0 BEFORE the edit;
#      both must still exit 0 after it. The retention count is not an input to any of
#      derive_knobs.py's checks -- T3's storage projection treats every cycle's selfplay
#      write as MONOTONIC within a link (derive_knobs.py:519-523 reads KEEP_SHUFFLEDDATA,
#      KEEP_REJECTED_MODELS, KEEP_LONGTERM_CHECKPOINTS, KEEP_DATED_SCRIPTS and NOT
#      KEEP_SELFPLAY_GENERATIONS) -- so an unchanged verdict is the expected result and a
#      changed one is the signal to stop.
#   6  runs codes/data_budget/tests/run_guard_tests.sh -- the exit-code contract for
#      scratch_guard.sh and prune_retention.py, against the edited constants file
#   7  prints the prune plan the NEXT link start would execute, as a dry run
#
# WHEN IT TAKES EFFECT. loop.sbatch:876 runs `prune_retention.py --basedir $BASEDIR --apply`
# once, at the START of a chain link, and prune_retention.py reads budget.env from the repo
# at that moment. So the edit is picked up by the next link that STARTS after it lands, and
# by nothing else: no running job re-reads the file, and no signal is sent to one. To reach
# link 3 the commit has to be on disk before job 305318's walltime ends (2026-09-06T17:53:21
# EDT), because 314831 starts immediately on the afterany dependency.
#
# usage:
#   bash apply_c1.sh                       # refuses, prints what it would do
#   bash apply_c1.sh --yes                 # applies to the az repo this file lives in
#   bash apply_c1.sh --yes --paper DIR     # applies to another copy of the paper tree
#   bash apply_c1.sh --revert --yes        # puts budget.env:55 back to 3

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DIFF="$HERE/apply_c1.diff"
PAPER="$(cd -- "$HERE/../../.." && pwd -P)"      # results/ktg/paper_1902.10565
CONFIRM="${KTG_C1_CONFIRM:-0}"
REVERT=0
BASEDIR="${BASEDIR:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/p1}"

while [ $# -gt 0 ]; do
  case "$1" in
    --yes)     CONFIRM=1; shift ;;
    --revert)  REVERT=1; shift ;;
    --paper)   PAPER="$(cd -- "$2" && pwd -P)"; shift 2 ;;
    --basedir) BASEDIR="$2"; shift 2 ;;
    *) echo "apply_c1: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

BUDGET="$PAPER/codes/data_budget/budget.env"
REPO="$(cd -- "$PAPER/../../.." && pwd -P)"      # the az root that holds results/
RC=0

say() { printf '=== %s ===\n' "$*"; }

say "apply_c1.sh $(date -Is)"
echo "paper    : $PAPER"
echo "repo     : $REPO"
echo "budget   : $BUDGET"
echo "diff     : $DIFF"
echo "basedir  : $BASEDIR   (dry-run prune target; never written)"
echo "line 55  : $(sed -n '55p' "$BUDGET")"

if [ "$CONFIRM" != "1" ]; then
  cat <<'MSG'

REFUSING: option c1 is PREPARED, not applied. The human has not decided.
Re-run with --yes (or KTG_C1_CONFIRM=1) once the decision is made. Nothing was changed.
MSG
  exit 3
fi

# ---------------------------------------------------------------- 1/2 precondition
WANT_FROM="KTG_KEEP_SELFPLAY_GENERATIONS=3"
WANT_TO="KTG_KEEP_SELFPLAY_GENERATIONS=60"
[ "$REVERT" = "1" ] && { WANT_FROM="KTG_KEEP_SELFPLAY_GENERATIONS=60"; WANT_TO="KTG_KEEP_SELFPLAY_GENERATIONS=3"; }
GOT="$(sed -n '55p' "$BUDGET")"
if [ "$GOT" != "$WANT_FROM" ]; then
  echo "REFUSING: budget.env:55 is '$GOT', expected '$WANT_FROM'. Something else moved it." >&2
  exit 4
fi

# ---------------------------------------------------------------- 3 apply
say "applying the one-line patch"
if [ "$REVERT" = "1" ]; then
  ( cd "$REPO" && git apply -R --verbose "$DIFF" ) || {
    echo "git apply -R failed" >&2; exit 5; }
else
  ( cd "$REPO" && git apply --verbose "$DIFF" ) || {
    echo "git apply failed" >&2; exit 5; }
fi

# ---------------------------------------------------------------- 4 postcondition
GOT="$(sed -n '55p' "$BUDGET")"
if [ "$GOT" != "$WANT_TO" ]; then
  echo "REFUSING: after the patch budget.env:55 is '$GOT', expected '$WANT_TO'." >&2
  exit 6
fi
say "budget.env:55 is now: $GOT"

# ---------------------------------------------------------------- 5 knob checks
say "check_knobs_9x9.py -- frozen smoke evidence (documented default)"
( cd "$PAPER" && python3 codes/eval/check_knobs_9x9.py ) ; K1=$?
echo "check_knobs_9x9.py (default evidence) EXIT=$K1   (expected 0)"
[ "$K1" -eq 0 ] || RC=1

say "check_knobs_9x9.py -- production evidence"
( cd "$PAPER" && python3 codes/eval/check_knobs_9x9.py \
    --throughput evidence/production_chain/throughput.json \
    --rows-file evidence/production_chain/rows_per_game.txt ) ; K2=$?
echo "check_knobs_9x9.py (production evidence) EXIT=$K2   (expected 0)"
[ "$K2" -eq 0 ] || RC=1

say "check_knobs_9x9.py -- the memo's --marginal/--trend/--horizon variant (KNOWN-FAILING CONTROL)"
echo "This variant exits 1 BEFORE any edit as well: rows/game has turned upward"
echo "(+0.0356 rows/game per accepted net over the last 9 complete directories), so the"
echo "carried-forward lower bound lands ABOVE the measurement and derive_knobs.py refuses"
echo "it. That is an open item about the trend arguments, not about this patch."
( cd "$PAPER" && python3 codes/eval/check_knobs_9x9.py \
    --throughput evidence/production_chain/throughput.json \
    --rows-file evidence/production_chain/rows_per_game.txt \
    --marginal-nets 3 --trend-nets 9 --horizon-nets 10 ) 2>&1 | tail -3 ; K3="${PIPESTATUS[0]}"
echo "check_knobs_9x9.py (memo variant) EXIT=$K3   (1 before AND after the edit)"

# ---------------------------------------------------------------- 6 guard tests
say "run_guard_tests.sh -- the exit-code contract, against the edited constants file"
bash "$PAPER/codes/data_budget/tests/run_guard_tests.sh" ; G=$?
echo "run_guard_tests.sh EXIT=$G   (expected 0)"
[ "$G" -eq 0 ] || RC=1

# ---------------------------------------------------------------- 7 the resulting plan
say "prune_retention.py DRY RUN with the edited constants (this is what the next link start would do)"
python3 "$PAPER/codes/data_budget/prune_retention.py" --basedir "$BASEDIR" \
  | grep -E '^== |^constants|^root|^basedir|^-- |WOULD-REMOVE' | head -40
echo

say "apply_c1.sh done   overall RC=$RC"
echo "budget.env:55 = $(sed -n '55p' "$BUDGET")"
echo "COMMIT IT: the loop reads budget.env from the repo working tree at link start"
echo "(loop.sbatch:81,876), so an uncommitted edit is already live for the next link --"
echo "commit it in the same breath so the chain and the log agree."
exit "$RC"
