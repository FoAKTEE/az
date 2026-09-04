#!/bin/bash -l
# node data_budget - storage guard for the 500 GiB mission scratch budget.
#
# Callable from any loop script. It is NEVER advisory: it exits non-zero and the caller
# must abort the cycle.
#
#   usage: scratch_guard.sh [--projected-bytes N] [--root DIR] [--label TEXT] [--quiet]
#
#   --projected-bytes N  bytes the next cycle is expected to write. Default: the value in
#                        the constants file ($KTG_CYCLE_PROJECTED_BYTES, 20 GiB).
#   --root DIR           mission root to measure. Default: the constants file's
#                        $KTG_SCRATCH_ROOT. A different root is announced with a NOTE line.
#   --label TEXT         tag echoed on the log triple, e.g. "cycle 7 pre-selfplay".
#   --quiet              suppress the quotas.py table (the parsed numbers still print).
#
# --------------------------------------------------------------------------------------
# WHAT IS PINNED AND WHAT IS CALLER CONTROL (obligation o28; contract cases A-T)
# --------------------------------------------------------------------------------------
# PINNED - no environment variable can change these:
#
#   * every byte threshold (KTG_SCRATCH_HARD_BYTES, KTG_GROUP_FREE_FAIL_BYTES,
#     KTG_GROUP_FREE_WARN_BYTES) comes only from the constants FILE the guard prints.
#     A stray KTG_SCRATCH_HARD_BYTES in a job script is overwritten when the file is
#     sourced and cannot loosen the cap.                                  [case C]
#   * the constants FILE itself. $KTG_BUDGET_ENV is honoured only when it resolves
#     inside this script's own directory (the committed budget.env and tests/ fixtures).
#     Any path outside that subtree is REFUSED with exit 3 - a loose constants file
#     dropped on scratch can no longer raise the cap.                     [cases N1/N2]
#   * the constants file must hold LITERAL values. A file whose KTG_* assignments contain
#     a ${...} indirection is refused with exit 3, so the file cannot be written in a form
#     that re-opens an environment channel.                               [case O]
#   * the measured root and the default projection, therefore, cannot be set from the
#     environment: exporting KTG_SCRATCH_ROOT or KTG_CYCLE_PROJECTED_BYTES=0 has no
#     effect on this guard.                                               [cases L, P]
#
# CALLER CONTROL, by design, and stated here so the claim does not overreach:
#
#   * --projected-bytes N  the caller declares the bytes the cycle will write; that IS
#     the guard's input and the wrapper is expected to pass an honest figure. Passing
#     --projected-bytes 0 makes the projection 0.                         [case M]
#   * --root DIR  the caller may measure a different tree (the negative tests do). The
#     guard prints "NOTE  measuring an OVERRIDDEN root" naming the constants file's root
#     whenever they differ, so a re-scoped run cannot pass unremarked in a cycle log.
#     The task file forbids the wrapper from scoping the guard to BASEDIR.  [case Q]
#   * KTG_QUOTAS_BIN  selects the quota reporter (the df-fallback test uses it). It cannot
#     LOOSEN the free-space check: the guard takes min(quotas.py, df -B1), so a reporter
#     that overstates free space is discarded in favour of live df.       [cases K, R]
#   * KTG_DU_ATTEMPTS / KTG_DU_RETRY_SLEEP  how often a non-zero `du -sb` is retried before
#     the guard gives up (default 3, 2 s apart). Both must be integers or the guard exits 3,
#     and neither can loosen anything: fewer attempts only make the guard refuse sooner, and
#     a partial du total is discarded however many attempts are made.     [case T]
#
# Not pinned, not claimed: the guard measures; it does not stop a caller who never calls
# it. That conjunct belongs to the loop wrapper (o27_scratch_guard_reconcile_500gib).
# --------------------------------------------------------------------------------------
#
# exit 0  within budget and above the group free-space floor
# exit 1  PROJECTED mission-root usage would cross the 500 GiB hard cap
# exit 2  group scratch free space is below the safety floor
# exit 3  the guard could not measure (missing root, du -sb non-zero on every attempt, no
#         usable free-space source) OR the constants file is missing, out of tree, or not
#         literal. A non-zero du is retried $KTG_DU_ATTEMPTS times (default 3, 2 s apart)
#         because entries vanishing mid-walk are normal on a live root; its partial total
#         is NEVER used, because a partial total under-counts.
#
# Every run prints the per-cycle triple required by o04_scratch_budget:
#   du -sb <root> | df -B1 <root> | python3 /apps/helpers/quotas.py
#
# Calling this guard from a loop script (the contract the loop wrapper implements).
# This is the exact contract exercised by tests/run_guard_tests.sh cases A and S1:
#
#   GUARD=results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh
#   PRUNE=results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py
#
#   # once at startup: sweep orphan .tmp dirs and the unbounded trees.
#   # No --root: the pruner reads KTG_SCRATCH_ROOT from budget.env next to it, exactly
#   # as the guard does. (Before o28 this silently exited 3 and pruned nothing.)
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
# The wrapper passes neither --root nor KTG_BUDGET_ENV: both are pinned to this directory.
# Omitting --projected-bytes is safe - the projection then falls back to the file's
# 20 GiB, which no environment variable can lower.
#
# The guard is never advisory: on a non-zero exit the cycle must not start.

set -u
set -o pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# The caps are read from a constants FILE, never from loose environment variables: a stray
# KTG_SCRATCH_HARD_BYTES in a job script must not be able to loosen the guard.
#
# o28: the FILE is pinned too. $KTG_BUDGET_ENV is honoured only for a file that resolves
# inside this script's own directory - budget.env itself and the committed tests/ fixtures,
# which are the only callers that legitimately need different constants. A constants file
# anywhere else (a loose one dropped on scratch, say) is refused, because honouring it
# would let any writer choose the cap.
BUDGET_ENV="${KTG_BUDGET_ENV:-$HERE/budget.env}"
BUDGET_ENV_REAL="$(realpath -m -- "$BUDGET_ENV" 2>/dev/null)" || BUDGET_ENV_REAL=""
case "${BUDGET_ENV_REAL:-/dev/null}" in
  "$HERE"/*) : ;;
  *) echo "scratch_guard: refusing an out-of-tree constants file: $BUDGET_ENV" >&2
     echo "               only files under $HERE/ may set the byte thresholds." >&2
     exit 3 ;;
esac
if [ ! -r "$BUDGET_ENV" ]; then
  echo "scratch_guard: constants file not readable: $BUDGET_ENV" >&2
  exit 3
fi
# The file must hold LITERAL values. `KTG_X="${KTG_X:-default}"` would re-open exactly the
# environment channel this guard closes, so such a file is refused rather than sourced.
if grep -Eq '^[[:space:]]*KTG_[A-Z0-9_]+=[^#]*\$\{' -- "$BUDGET_ENV"; then
  echo "scratch_guard: constants file is not literal: $BUDGET_ENV" >&2
  echo "               a KTG_* assignment contains a \${...} indirection; write byte" >&2
  echo "               integers and the root path literally." >&2
  exit 3
fi
# shellcheck source=budget.env
. "$BUDGET_ENV"
# Sourcing overwrites any same-named environment variable, so from here on the thresholds,
# the default projection and the default root are the FILE's, whatever the caller exported.
FILE_ROOT="$KTG_SCRATCH_ROOT"
FILE_PROJECTED="$KTG_CYCLE_PROJECTED_BYTES"
for _v in KTG_SCRATCH_HARD_BYTES KTG_CYCLE_PROJECTED_BYTES KTG_GROUP_FREE_FAIL_BYTES \
          KTG_GROUP_FREE_WARN_BYTES; do
  eval "_val=\${$_v-}"
  case "${_val:-}" in
    ''|*[!0-9]*) echo "scratch_guard: $_v is not a byte integer in $BUDGET_ENV: '${_val:-}'" >&2
                 exit 3 ;;
  esac
done
case "$FILE_ROOT" in
  /*) : ;;
  *)  echo "scratch_guard: KTG_SCRATCH_ROOT in $BUDGET_ENV is not an absolute path: '$FILE_ROOT'" >&2
      exit 3 ;;
esac

QUOTAS_BIN="${KTG_QUOTAS_BIN:-/apps/helpers/quotas.py}"
# Defaults come from the file and from nowhere else; only an explicit argument moves them.
PROJECTED="$FILE_PROJECTED"
ROOT="$FILE_ROOT"
ROOT_EXPLICIT=0
LABEL=""
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --projected-bytes) PROJECTED="${2:-}"; shift 2 ;;
    --root)            ROOT="${2:-}"; ROOT_EXPLICIT=1; shift 2 ;;
    --label)           LABEL="${2:-}";     shift 2 ;;
    --quiet)           QUIET=1;            shift ;;
    -h|--help)         sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed -n '/^#/p'; exit 0 ;;
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
# A re-scoped run must never pass unremarked in a cycle log: --root is caller control, but
# it is announced next to the root the constants file names.
if [ "$ROOT_EXPLICIT" -eq 1 ] && [ "$ROOT" != "$FILE_ROOT" ]; then
  echo "NOTE  measuring an OVERRIDDEN root: --root $ROOT (constants file root: $FILE_ROOT)"
fi

if [ ! -d "$ROOT" ]; then
  echo "scratch_guard: mission root does not exist: $ROOT" >&2
  exit 3
fi

# --- 1. mission-root usage ---------------------------------------------------
# `du -sb` exits non-zero when an entry disappears from under it, which happens routinely on
# a live mission root (a shuffle renaming its .tmp, a job unlinking a scratch file). One such
# sample used to be read as "cannot measure", so the guard exited 3 and a healthy cycle was
# aborted - observed here as an intermittent failure of contract case D, root-caused to
# "du -sb failed on <root>" with no other change to the tree.
#
# The retry does NOT soften the measurement. A non-zero du is never trusted, not even when
# it printed a partial total: a partial total is an UNDER-count (a directory it could not
# read is simply missing from the sum) and accepting one would let an unreadable subtree
# hide usage from the cap. Only an exit-0 du is used. A root that keeps failing still
# exits 3, exactly as before - contract case T holds an unreadable subdirectory, so du
# fails on every attempt AND prints a partial total, and the guard must still refuse.
DU_ATTEMPTS="${KTG_DU_ATTEMPTS:-3}"
DU_RETRY_SLEEP="${KTG_DU_RETRY_SLEEP:-2}"
case "$DU_ATTEMPTS" in ''|*[!0-9]*|0) echo "scratch_guard: KTG_DU_ATTEMPTS must be a positive integer, got '$DU_ATTEMPTS'" >&2; exit 3 ;; esac
case "$DU_RETRY_SLEEP" in ''|*[!0-9]*) echo "scratch_guard: KTG_DU_RETRY_SLEEP must be a non-negative integer, got '$DU_RETRY_SLEEP'" >&2; exit 3 ;; esac
DU_LINE=""
DU_ERR=""
DU_OK=0
DU_N=0
while [ "$DU_N" -lt "$DU_ATTEMPTS" ]; do
  DU_N=$((DU_N + 1))
  DU_ERRFILE="$(mktemp)" || { echo "scratch_guard: cannot create a temp file" >&2; exit 3; }
  if DU_LINE="$(du -sb "$ROOT" 2>"$DU_ERRFILE")"; then DU_OK=1; fi
  DU_ERR="$(tr '\n' ' ' < "$DU_ERRFILE" | cut -c1-300)"
  rm -f -- "$DU_ERRFILE"
  [ "$DU_OK" -eq 1 ] && break
  DU_LINE=""
  echo "scratch_guard: WARNING du -sb attempt $DU_N/$DU_ATTEMPTS on $ROOT exited non-zero; its partial total is discarded${DU_ERR:+ ($DU_ERR)}" >&2
  if [ "$DU_N" -lt "$DU_ATTEMPTS" ]; then sleep "$DU_RETRY_SLEEP"; fi
done
if [ "$DU_OK" -ne 1 ]; then
  echo "scratch_guard: du -sb failed on $ROOT after $DU_ATTEMPTS attempts${DU_ERR:+: $DU_ERR}" >&2
  exit 3
fi
if [ "$DU_N" -gt 1 ]; then
  echo "scratch_guard: NOTE du -sb succeeded on attempt $DU_N/$DU_ATTEMPTS (entries were changing under the walk)"
fi
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
