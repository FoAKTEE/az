#!/bin/bash
# node data_budget - archive the self-play SGF game records before retention deletes them.
#
# DISABLED BY DEFAULT AND NOT YET DECIDED. The switch is KTG_ARCHIVE_SGF in
# codes/loop/knobs_9x9.env, committed at 0; at 0 nothing here runs and no caller
# even spawns this script, so the loop's byte behaviour is exactly what it was.
# Turning it to 1 is a HUMAN decision about ~5.5 GB of the 500 GiB budget, and it
# takes effect at the next link start, which is when the knob file is sourced.
#
# WHAT IS AT STAKE (validation_boundary_1_2.md section 5, measured, not modelled).
# `prune_retention.py` removes a selfplay generation directory whole, and
# `sgfs/*.sgfs` -- the actual game records -- go with it: 52 generations, 1.39 GB,
# were deleted at the link-1 -> link-2 boundary alone. `gatekeepersgf/` is not a
# pruning target and survives; the SELF-PLAY games do not. The viewer snapshots
# under runtime/games_viewer hold a parsed games.json, not the SGFs, so a pruned
# generation is recoverable only from whatever page happened to cover it.
#
# COST, at the measured 3.42 kB per selfplay game on disk (77386206 B / 22648
# games): 0.68 GB for a 1800-game link of ~110 cycles, about 5.5 GB over a
# nine-link chain = 1.1 % of the 500 GiB cap in codes/data_budget/budget.env.
#
# HARD LINKS, not copies, wherever the filesystem allows it. A hard link costs one
# directory entry and no data blocks, and `du -sb` counts an inode ONCE per
# traversal, so while the generation still exists scratch_guard.sh measures no
# growth at all; the bytes only start counting once retention removes the original
# and the archive holds the last link to the inode. That is the honest accounting:
# the archive does not add storage, it declines to give storage back.
#
#   usage: archive_sgf.sh <BASEDIR> [--label TEXT] [--quiet]
#   exit 0  archived (or disabled, or nothing to do)
#   exit 2  BASEDIR unusable
#
# The archive tree is $BASEDIR/archive/sgf/<net>/<file>.sgfs. It is never a
# deletion candidate: prune_retention.py protects it explicitly.

set -u

BASEDIR="${1:-}"
shift 2>/dev/null || true
LABEL=""
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) shift ;;
  esac
done

# The switch. Read from the environment because codes/loop/loop.sbatch sources
# codes/loop/knobs_9x9.env with `set -a` before it calls anything, so the knob
# file IS the single source of truth for it, exactly like the eleven loop knobs.
if [ "${KTG_ARCHIVE_SGF:-0}" != "1" ]; then
  exit 0
fi

if [ -z "$BASEDIR" ] || [ ! -d "$BASEDIR" ]; then
  echo "archive_sgf: BASEDIR missing or not a directory: '${BASEDIR:-}'" >&2
  exit 2
fi

SRC_ROOT="$BASEDIR/selfplay"
DST_ROOT="$BASEDIR/archive/sgf"
[ -d "$SRC_ROOT" ] || exit 0
mkdir -p "$DST_ROOT" || exit 2

linked=0; copied=0; kept=0; failed=0; bytes=0
for net_dir in "$SRC_ROOT"/*; do
  [ -d "$net_dir/sgfs" ] || continue
  net=$(basename "$net_dir")
  out="$DST_ROOT/$net"
  mkdir -p "$out" || { failed=$(( failed + 1 )); continue; }
  for f in "$net_dir"/sgfs/*.sgfs; do
    [ -f "$f" ] || continue
    t="$out/$(basename "$f")"
    # Already the same inode: the hard link is live and grows with the original,
    # so there is nothing to do. This is what makes the pass idempotent and cheap
    # enough to run before every prune.
    if [ -e "$t" ] && [ "$t" -ef "$f" ]; then
      kept=$(( kept + 1 ))
      continue
    fi
    if ln -f "$f" "$t" 2>/dev/null; then
      linked=$(( linked + 1 ))
    elif cp -p "$f" "$t" 2>/dev/null; then
      copied=$(( copied + 1 ))
    else
      echo "archive_sgf: could not archive $f" >&2
      failed=$(( failed + 1 ))
      continue
    fi
    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
    bytes=$(( bytes + sz ))
  done
done

if [ "$QUIET" -eq 0 ]; then
  echo "== archive_sgf $(date -Is)${LABEL:+ [$LABEL]} =="
  echo "archive_sgf: $DST_ROOT  linked=$linked copied=$copied already-linked=$kept failed=$failed newly-referenced-bytes=$bytes"
  echo "archive_sgf: hard links add no blocks while the generation lives; scratch_guard.sh measures the mission root, so the archive is inside the 500 GiB cap either way"
fi
exit 0
