#!/bin/bash
# Validator re-verification, link 1 -> link 2 boundary (2026-09-05). Persistent sources only:
# the link-2 wrapper log, the trainer's own stdout, and the committed per-net rows/game table.
set -eu
L=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/loop-305318.log
T=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/p1/train/t9/stdout.txt
RPG=results/ktg/paper_1902.10565/evidence/production_chain/rows_per_game.txt
# (i) option C sourced by link 2, and 1800 games in effect
grep -q 'loop knobs .* (sha256 ba7f1bf7e1bc166d)' "$L"
n1800=$(grep -c 'katago selfplay -max-games-total 1800' "$L")
[ "$n1800" -ge 1 ]
# (ii) the first link-2 cycle trained two whole shuffle files, then exited on the file count
grep -q "This subepoch, using files: \['.*/shuffleddata/20260905-183427/train/data0_0.npz'\]" "$T"
grep -q "This subepoch, using files: \['.*/shuffleddata/20260905-183427/train/data1_0.npz'\]" "$T"
awk '/20260905-183427\/train\/data1_0.npz/{f=1} f && /Not enough data files to fill a subepoch/{ok=1; exit} END{exit !ok}' "$T"
# (iii) marginal rows/game over the three complete real-net directories named in the claim
r=$(awk '/t9-s17045760-d2821985|t9-s17345664-d2855966|t9-s17645440-d2906849/ {
      for(i=1;i<=NF;i++){ if($i ~ /^games=/){split($i,a,"=");g+=a[2]} if($i ~ /^rows=/){split($i,b,"=");w+=b[2]} } }
      END{ if(g!=7000||w!=118361) exit 1; printf "%.4f", w/g }' "$RPG")
[ "$r" = "16.9087" ]
python3 - "$r" <<'PY'
import sys
r=float(sys.argv[1]); G=1800; E=16000; keep=120000
rows=G*r; assert abs(rows-30435.7)<0.1, rows
assert abs(100*(rows/(1.2*E)-1)-58.52)<0.01
assert abs(keep/rows-3.943)<0.001
print("OPTION_C_EXECUTED_LINK2: sha ba7f1bf7e1bc166d, -max-games-total 1800, whole-file epochs (2 files), r=%.4f rows/cycle=%.1f T1=+%.2f%% rho=%.3f" % (r, rows, 100*(rows/(1.2*E)-1), keep/rows))
PY
