#!/bin/bash
# smoke_one_cycle.sh -- mission ktg-train, node arxiv-1902.10565::synchronous_loop_smoke
#
# Runs EXACTLY ONE cycle of the mission loop (gatekeeper -> selfplay -> shuffle ->
# train -> export) by exporting the smoke knob set and KTG_ONE_CYCLE=1 into
# codes/loop/synchronous_loop_9x9.sh, which is NOT edited here: CHANGE 9 of that
# script makes every knob `${VAR:-default}` and CHANGE 8 makes KTG_ONE_CYCLE=1 exit 0
# after one cycle. Called twice by codes/loop/smoke_loop.sbatch (legs B and C).
#
#   usage: smoke_one_cycle.sh <cycle-label>
#
# env in:  KTG_ROOT   (default /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
#          KTG_SMOKE_BASEDIR = $W (default $KTG_ROOT/runs/smoke)
#          KTG_STAGE_ONLY=1 -> the loop stages the dated archive and stops before any
#                              engine stage (login-node dry run, no GPU)
#
# Knob values and their justification are tasks/synchronous_loop_smoke/implementation.md
# section 10. The two that matter for whether a candidate is exported at all:
#   NUM_TRAIN_SAMPLES_PER_EPOCH 256 = 8 batches of 32; train.py:1303-1346 returns None
#     (-> -quit-if-no-data exits 0 with NO export) unless the shuffled files hold at
#     least round(samples_per_epoch/batch) batches. DESIGN section 2's 2000 needed
#     >= 2016 rows from ~40 games and would have exported nothing.
#   NUM_GAMES_PER_CYCLE 40 -> >= 480 rows at the c10 lower bound of 12 rows/game.

set -e
set -o pipefail

CYCLE_LABEL="${1:-cycle}"

KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
export KTG_ROOT
AZ_ROOT="${AZ_ROOT:-/home/schmidt/ssci-haiyangw/az}"
KTG_CODES="${KTG_CODES:-$AZ_ROOT/results/ktg/paper_1902.10565/codes}"
export KTG_CODES
W="${KTG_SMOKE_BASEDIR:-$KTG_ROOT/runs/smoke}"

# env.sh sources the venv activate script, which is not written for `set -u`.
set +u
# shellcheck disable=SC1091
source "$KTG_ROOT/env.sh"
set -u

# o11_torch_threads_cap: the trainer and the shuffler both honour these.
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4

# ---- smoke knob set (section 10 of the task file) ---------------------------
export NUM_GAMES_PER_CYCLE=40
export NUM_THREADS_FOR_SHUFFLING=8
export NUM_TRAIN_SAMPLES_PER_EPOCH=256
export MAX_TRAIN_PER_DATA=8
export NUM_TRAIN_SAMPLES_PER_SWA=128
export BATCHSIZE=32
export SHUFFLE_MINROWS=200
export MAX_TRAIN_SAMPLES_PER_CYCLE=4000
export TAPER_WINDOW_SCALE=200
export SHUFFLE_KEEPROWS=5000
export EPOCHS_PER_EXPORT=1
export KTG_ONE_CYCLE=1

NAMEPREFIX="${KTG_SMOKE_NAMEPREFIX:-ktgsmoke9}"
TRAININGNAME="${KTG_SMOKE_TRAININGNAME:-t9}"
MODELKIND="${KTG_SMOKE_MODELKIND:-b7c96h3tfrs}"
USEGATING=1     # never 0: node gating_rule, section 13 of the task file

mkdir -p "$W/logs"
CYCLE_LOG="$W/logs/smoke_${CYCLE_LABEL}.txt"

echo "smoke_one_cycle: label=$CYCLE_LABEL basedir=$W"
echo "smoke_one_cycle: katago=$KATAGO_BIN src=$KATAGO_SRC"
echo "smoke_one_cycle: knobs games=$NUM_GAMES_PER_CYCLE samples_per_epoch=$NUM_TRAIN_SAMPLES_PER_EPOCH batch=$BATCHSIZE reuse=$MAX_TRAIN_PER_DATA minrows=$SHUFFLE_MINROWS keeprows=$SHUFFLE_KEEPROWS cap=$MAX_TRAIN_SAMPLES_PER_CYCLE taper=$TAPER_WINDOW_SCALE swa=$NUM_TRAIN_SAMPLES_PER_SWA epochs_per_export=$EPOCHS_PER_EXPORT"
echo "smoke_one_cycle: cycle log -> $CYCLE_LOG"

# The loop copy runs `git rev-parse --show-toplevel` and refuses to run anywhere but
# the scratch clone (its own guard at :82-91), so cd there first.
cd "$KATAGO_SRC"

set +e
bash "$KTG_CODES/loop/synchronous_loop_9x9.sh" \
     "$NAMEPREFIX" "$W" "$TRAININGNAME" "$MODELKIND" "$USEGATING" 2>&1 | tee -a "$CYCLE_LOG"
RC="${PIPESTATUS[0]}"
set -e

echo "smoke_one_cycle: label=$CYCLE_LABEL loop exit=$RC"
exit "$RC"
