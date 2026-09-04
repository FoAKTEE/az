#!/bin/bash -l
# ^ the -l matters: without a login shell, `module` is undefined on compute nodes
#SBATCH --job-name=ktg-match
#SBATCH --account=ssci-anima
#SBATCH --partition=b200
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/ktg-match-%j.log
#
# match.sbatch -- mission ktg-train, node arxiv-1902.10565::match_latest_against_first.
#
# P11 of tasks/production_chain_9x9: the ONE extra 1-GPU job the packet allows, run only
# when P7 >= 1 (at least one candidate accepted). 400 games of the LATEST accepted net
# against the FROZEN FIRST accepted net at 9x9, komi 7, maxVisits 150, one search thread,
# 18 game threads, both colour orderings -- then summarize_sgfs.py over the games it wrote.
#
# NOT SUBMITTED BY THIS PACKET. Phase 0 authors it; Phase 3 submits it, and only after
#   bash .claude/skills/compute-budget/check.sh --gpus 1 --cpus 32 --partition b200
# (mission.json compute.policyCheck) exits 0. With the chain running that check reports
# my_gpus(1) + 1 <= 4. Task section 5: nothing else on a GPU, ever, in this packet.
#
# usage (from the az root):
#   sbatch results/ktg/paper_1902.10565/codes/eval/match.sbatch
#   BASEDIR=... EVALDIR=... sbatch results/ktg/paper_1902.10565/codes/eval/match.sbatch
#
# Environment it reads (all optional; the defaults are the packet's paths):
#   KTG_ROOT   /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
#   BASEDIR    $KTG_ROOT/runs/p1                the chain's run directory
#   EVALDIR    $KTG_ROOT/eval                   manifest.json in, match/ + summary out
#   NUM_GAMES  400                              -override-config numGamesTotal
#
# Sizing rationale (cluster-job skill, "ask for the fewest GPUs the work needs"): one
# B200, 32 CPUs, 32 G. 18 game threads x 1 search thread plus one NN server thread is
# well inside 32 CPUs; the two nets are b7c96h3tfrs, a few GiB of VRAM together, so 32 G
# of host memory is generous and the walltime is the honest one -- the same 400 games at
# 150 visits took the gatekeeper's 200-game match minutes, not hours (task section 10:
# "approximately 10-20 min on one B200").

set -uo pipefail

KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
BASEDIR="${BASEDIR:-$KTG_ROOT/runs/p1}"
EVALDIR="${EVALDIR:-$KTG_ROOT/eval}"
NUM_GAMES="${NUM_GAMES:-400}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAPER="$(cd "$HERE/../.." && pwd)"
CFG="$PAPER/codes/cfg/match_first_latest_9.cfg"

TAG="${SLURM_JOB_ID:-manual}"
SGF_DIR="$EVALDIR/match-$TAG"
SUMMARY="$EVALDIR/match_summary-$TAG.txt"
MATCH_LOG="$EVALDIR/match-$TAG.log"
MANIFEST="$EVALDIR/manifest.json"

say() { echo "=== [$(date -Is)] $* ==="; }

say "match.sbatch start   job=$TAG host=$(hostname -s)"
say "BASEDIR=$BASEDIR  EVALDIR=$EVALDIR  NUM_GAMES=$NUM_GAMES"
say "config=$CFG"

# ---------------------------------------------------------------- preconditions
for f in "$CFG" "$MANIFEST"; do
  if [ ! -f "$f" ]; then
    say "missing required input: $f"
    [ "$f" = "$MANIFEST" ] && say "run codes/eval/freeze_baseline.py $BASEDIR first (P6)"
    exit 2
  fi
done

# The frozen first net comes from the manifest, never from a fresh directory scan: P6
# says the baseline is written once and never rewritten, and the whole point of the
# match is that both sides of the comparison are pinned by content.
read -r FIRST_PATH FIRST_SHA FIRST_NAME <<EOF
$(python3 - "$MANIFEST" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print(m.get("first_model_path", ""), m.get("first_model_sha256", ""), m.get("first_model", ""))
PY
)
EOF

if [ -z "${FIRST_PATH:-}" ] || [ ! -f "$FIRST_PATH" ]; then
  say "the manifest's first_model_path is missing or does not exist: '${FIRST_PATH:-}'"
  exit 2
fi
NOW_SHA="$(sha256sum "$FIRST_PATH" | cut -d' ' -f1)"
if [ "$NOW_SHA" != "$FIRST_SHA" ]; then
  say "REFUSING: $FIRST_PATH hashes $NOW_SHA but the manifest froze $FIRST_SHA."
  say "The frozen baseline changed underneath its hash; escalate, do not re-freeze."
  exit 2
fi
say "frozen first net : $FIRST_NAME  ($FIRST_PATH)"
say "                   sha256 $FIRST_SHA (re-verified)"

# The latest accepted net: the largest s<samples> in $BASEDIR/models.
LATEST_PATH="$(ls -1d "$BASEDIR"/models/*/ 2>/dev/null \
  | sed 's:/$::' \
  | awk -F'-s' 'NF>1 { split($NF, a, "-d"); print a[1] "\t" $0 }' \
  | sort -n -k1,1 | tail -1 | cut -f2)"
if [ -z "${LATEST_PATH:-}" ]; then
  say "no accepted net in $BASEDIR/models -- P11 runs only when P7 >= 1. Nothing to do."
  exit 2
fi
LATEST_PATH="$LATEST_PATH/model.bin.gz"
if [ ! -f "$LATEST_PATH" ]; then
  say "the latest accepted directory holds no model.bin.gz: $LATEST_PATH"
  exit 2
fi
LATEST_NAME="$(basename "$(dirname "$LATEST_PATH")")"
say "latest accepted  : $LATEST_NAME  ($LATEST_PATH)"
say "                   sha256 $(sha256sum "$LATEST_PATH" | cut -d' ' -f1)"

if [ "$LATEST_PATH" = "$FIRST_PATH" ]; then
  say "the latest accepted net IS the frozen first net -- there is nothing to compare."
  say "P11 needs a second acceptance; run this after one exists."
  exit 2
fi

# ---------------------------------------------------------------- toolchain
module load cuda/12.8.1
# shellcheck disable=SC1091
. "$KTG_ROOT/env.sh"
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader || true

mkdir -p "$SGF_DIR" "$EVALDIR"

# ---------------------------------------------------------------- the match
say "katago match: $NUM_GAMES games, 9x9, komi 7, maxVisits 150, 1 search thread, 18 game threads"
"$KATAGO_BIN" match \
  -config "$CFG" \
  -override-config "nnModelFile0=$FIRST_PATH,nnModelFile1=$LATEST_PATH,numGamesTotal=$NUM_GAMES" \
  -sgf-output-dir "$SGF_DIR" \
  -log-file "$MATCH_LOG"
MATCH_RC=$?
say "katago match exit=$MATCH_RC"

GAMES="$(cat "$SGF_DIR"/*.sgfs 2>/dev/null | grep -c . || echo 0)"
SZ_OTHER="$(cat "$SGF_DIR"/*.sgfs 2>/dev/null | grep -cv 'SZ\[9\]' || echo 0)"
say "sgf lines written: $GAMES   (not SZ[9]: $SZ_OTHER)"

# ---------------------------------------------------------------- summary
if [ "$GAMES" -gt 0 ]; then
  say "summarize_sgfs.py over $SGF_DIR"
  python3 "$KATAGO_SRC/python/summarize_sgfs.py" "$SGF_DIR" -recursive \
    2>&1 | tee "$SUMMARY"
  say "wrote $SUMMARY"
  say "next (login node, CPU): python3 codes/eval/declare.py $EVALDIR \\"
  say "        --match-sgfs $SGF_DIR --match-summary $SUMMARY \\"
  say "        --require-acceptances 1 --ci 0.95 --target-p 0.60"
else
  say "no games written -- nothing to summarize"
fi

exit "$MATCH_RC"
