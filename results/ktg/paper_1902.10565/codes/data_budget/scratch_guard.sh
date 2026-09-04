#!/bin/bash -l
# node data_budget - storage guard for the 500 GiB mission scratch budget.
#
# Callable from any loop script. It is NEVER advisory: it exits non-zero and the caller
# must abort the cycle.
#
#   usage: scratch_guard.sh [--projected-bytes N] [--root DIR] [--label TEXT] [--quiet]
#
#   --projected-bytes N  bytes the next cycle is expected to write. Default
#                        $KTG_CYCLE_PROJECTED_BYTES (20 GiB) from budget.env.
#   --root DIR           mission root to measure. Default $KTG_SCRATCH_ROOT.
#   --label TEXT         tag echoed on the log triple, e.g. "cycle 7 pre-selfplay".
#   --quiet              suppress the quotas.py table (the parsed numbers still print).
#
# The thresholds come from budget.env next to this script, or from $KTG_BUDGET_ENV if set.
#
# exit 0  within budget and above the group free-space floor
# exit 1  PROJECTED mission-root usage would cross the 500 GiB hard cap
# exit 2  group scratch free space is below the safety floor
# exit 3  the guard could not measure (missing root, du failed, no usable free-space source)
#
# Every run prints the per-cycle triple required by o04_scratch_budget:
#   du -sb <root> | df -B1 <root> | python3 /apps/helpers/quotas.py
#
# Calling this guard from a loop script (the contract the loop wrapper implements):
#
#   GUARD=results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh
#   PRUNE=results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py
#
#   # once at startup: sweep orphan .tmp dirs and the unbounded trees
#   python3 "$PRUNE" --apply
#
#   # at the top of EVERY cycle, before selfplay writes anything
#   if ! bash "$GUARD" --projected-bytes "$CYCLE_BYTES" --label "cycle $N pre-selfplay"; then
#     rc=$?
#     if [ "$rc" -eq 1 ]; then
#       # over the mission budget: prune back under it, then re-check ONCE
#       python3 "$PRUNE" --apply --target-bytes 536870912000
#       bash "$GUARD" --projected-bytes "$CYCLE_BYTES" --label "cycle $N post-prune" || exit "$?"
#     else
#       exit "$rc"      # rc 2 = group scratch floor, rc 3 = cannot measure. Never continue.
#     fi
#   fi
#
# The guard is never advisory: on a non-zero exit the cycle must not start.

set -u
set -o pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# The caps are read from a constants FILE, never from loose environment variables: a stray
# KTG_SCRATCH_HARD_BYTES in a job script must not be able to loosen the guard. A caller that
# genuinely needs different constants (only the negative tests do) points KTG_BUDGET_ENV at
# an alternate file, and the guard prints which file it used.
BUDGET_ENV="${KTG_BUDGET_ENV:-$HERE/budget.env}"
if [ ! -r "$BUDGET_ENV" ]; then
  echo "scratch_guard: constants file not readable: $BUDGET_ENV" >&2
  exit 3
fi
# shellcheck source=budget.env
. "$BUDGET_ENV"

QUOTAS_BIN="${KTG_QUOTAS_BIN:-/apps/helpers/quotas.py}"
PROJECTED="$KTG_CYCLE_PROJECTED_BYTES"
ROOT="$KTG_SCRATCH_ROOT"
LABEL=""
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --projected-bytes) PROJECTED="${2:-}"; shift 2 ;;
    --root)            ROOT="${2:-}";      shift 2 ;;
    --label)           LABEL="${2:-}";     shift 2 ;;
    --quiet)           QUIET=1;            shift ;;
    -h|--help)         sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "scratch_guard: unknown argument '$1'" >&2; exit 3 ;;
  esac
done

case "$PROJECTED" in
  ''|*[!0-9]*) echo "scratch_guard: --projected-bytes must be a non-negative integer, got '$PROJECTED'" >&2; exit 3 ;;
esac

STAMP="$(date -Iseconds)"
echo "== scratch_guard $STAMP ${LABEL:+[$LABEL]} =="
echo "constants            : $BUDGET_ENV"
echo "root                 : $ROOT"

if [ ! -d "$ROOT" ]; then
  echo "scratch_guard: mission root does not exist: $ROOT" >&2
  exit 3
fi

# --- 1. mission-root usage ---------------------------------------------------
DU_LINE="$(du -sb "$ROOT" 2>/dev/null)" || { echo "scratch_guard: du -sb failed on $ROOT" >&2; exit 3; }
USED="$(printf '%s' "$DU_LINE" | cut -f1)"
case "$USED" in
  ''|*[!0-9]*) echo "scratch_guard: could not parse du output: '$DU_LINE'" >&2; exit 3 ;;
esac
echo "du -sb               : $DU_LINE"

# --- 2. filesystem free space (df) ------------------------------------------
DF_TABLE="$(df -B1 "$ROOT" 2>/dev/null)" || DF_TABLE=""
DF_FREE="$(printf '%s\n' "$DF_TABLE" | awk 'NR==2 {print $4}')"
case "${DF_FREE:-x}" in ''|*[!0-9]*) DF_FREE="" ;; esac
echo "df -B1               : $(printf '%s\n' "$DF_TABLE" | tail -n +2 | tr -s ' ')"

# --- 3. group quota (quotas.py) ---------------------------------------------
QUOTA_RAW=""
if [ -r "$QUOTAS_BIN" ]; then
  QUOTA_RAW="$(python3 "$QUOTAS_BIN" 2>/dev/null)" || QUOTA_RAW=""
fi
QUOTA_FREE="$(printf '%s' "$QUOTA_RAW" | python3 -c '
import re, sys
# quotas.py prints an ANSI-coloured table:
#   | /scratch/ssci-anima/ | 37.61 TB | 40.00 TB |   94%    |
# Sizes are DECIMAL (40.00 TB == the 40000000000000 B pool df reports).
txt = re.sub(r"\x1b\[[0-9;]*m", "", sys.stdin.read())
mult = {"B":1, "KB":10**3, "MB":10**6, "GB":10**9, "TB":10**12, "PB":10**15}
for line in txt.splitlines():
    if "/scratch/" not in line:
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 3:
        continue
    try:
        used  = float(cells[1].split()[0]) * mult[cells[1].split()[1].upper()]
        quota = float(cells[2].split()[0]) * mult[cells[2].split()[1].upper()]
    except (ValueError, KeyError, IndexError):
        continue
    print(int(max(0.0, quota - used)))
    break
' 2>/dev/null)"
case "${QUOTA_FREE:-x}" in ''|*[!0-9]*) QUOTA_FREE="" ;; esac

if [ "$QUIET" -eq 0 ] && [ -n "$QUOTA_RAW" ]; then
  printf '%s\n' "$QUOTA_RAW" | sed 's/^/quotas.py            | /'
fi

# The two sources measure the same pool. quotas.py is the authority named by the mission,
# but it is rounded to 0.01 TB and refreshed hourly, while df is exact and live. Take the
# MINIMUM so neither staleness nor rounding can hide a shortage.
if [ -n "$QUOTA_FREE" ] && [ -n "$DF_FREE" ]; then
  if [ "$QUOTA_FREE" -le "$DF_FREE" ]; then GROUP_FREE="$QUOTA_FREE"; FREE_SRC="quotas.py"; else GROUP_FREE="$DF_FREE"; FREE_SRC="df"; fi
elif [ -n "$QUOTA_FREE" ]; then
  GROUP_FREE="$QUOTA_FREE"; FREE_SRC="quotas.py (df unavailable)"
elif [ -n "$DF_FREE" ]; then
  GROUP_FREE="$DF_FREE";    FREE_SRC="df (quotas.py unavailable)"
  echo "scratch_guard: WARNING quotas.py unreadable or unparseable at $QUOTAS_BIN; using df -B1 on the same pool" >&2
else
  echo "scratch_guard: no usable free-space source (both quotas.py and df failed)" >&2
  exit 3
fi

PROJECTED_TOTAL=$(( USED + PROJECTED ))

echo "projected write      : $PROJECTED B"
echo "projected root total : $PROJECTED_TOTAL B   (hard cap $KTG_SCRATCH_HARD_BYTES B = 500 GiB)"
echo "group scratch free   : $GROUP_FREE B   (source: $FREE_SRC; fail floor $KTG_GROUP_FREE_FAIL_BYTES B, warn floor $KTG_GROUP_FREE_WARN_BYTES B)"

# --- 4. verdicts -------------------------------------------------------------
RC=0

if [ "$PROJECTED_TOTAL" -gt "$KTG_SCRATCH_HARD_BYTES" ]; then
  echo "VIOLATION: projected mission-root usage $PROJECTED_TOTAL B exceeds the mission-root budget (hard cap $KTG_SCRATCH_HARD_BYTES B)." >&2
  echo "           current $USED B + projected $PROJECTED B. Run prune_retention.py --apply --target-bytes $KTG_SCRATCH_HARD_BYTES before retrying." >&2
  RC=1
fi

if [ "$GROUP_FREE" -lt "$KTG_GROUP_FREE_FAIL_BYTES" ]; then
  echo "VIOLATION: group scratch free space $GROUP_FREE B is below the $KTG_GROUP_FREE_FAIL_BYTES B safety floor." >&2
  echo "           The pool is shared by the whole group; do not start a cycle. Escalate." >&2
  [ "$RC" -eq 0 ] && RC=2
elif [ "$GROUP_FREE" -lt "$KTG_GROUP_FREE_WARN_BYTES" ]; then
  echo "scratch_guard: WARNING group scratch free space $GROUP_FREE B is below the $KTG_GROUP_FREE_WARN_BYTES B warn floor; one mission budget of headroom left." >&2
fi

if [ "$RC" -eq 0 ]; then
  echo "scratch_guard: OK  used=$USED B  projected_total=$PROJECTED_TOTAL B  group_free=$GROUP_FREE B"
fi
exit "$RC"
