#!/bin/bash
# t7_cycle.sh -- mission ktg-train, node arxiv-1902.10565::converged_test_7x7
#
# Runs EXACTLY ONE cycle of the mission loop (gatekeeper -> selfplay -> shuffle ->
# train -> export) on a 7x7 board, by exporting the 7x7 knob set, KTG_POS_LEN=7,
# KTG_PRINT_EVERY and KTG_ONE_CYCLE=1 into codes/loop/synchronous_loop_9x9.sh.
#
# THE LOOP SCRIPT IS NOT EDITED AND NOT FORKED. Its CHANGE 9 makes every knob
# `${VAR:-default}`, its CHANGE 8 makes KTG_ONE_CYCLE=1 exit 0 after one cycle, and
# SELFPLAY_CONFIG / GATING_CONFIG / TRAIN_WRAPPER are already `${VAR:-...}`. The two
# places that carried a hard 9 are now `${KTG_POS_LEN:-9}`:
#   codes/loop/train_9x9.sh   -pos-len
#   codes/eval/check_pos_len_npz.py   EXPECTED_SHAPES / EXPECTED_ROW_BYTES
# so with KTG_POS_LEN unset the 9x9 production chain sees byte-identical behaviour.
#
#   usage: t7_cycle.sh <cycle-label> [games-this-cycle]
#
# env in:  KTG_ROOT         default /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
#          KTG_T7_BASEDIR   default $KTG_ROOT/runs/t7
#          KTG_PRINT_EVERY  default 8   (loss rows every 8 batches; see
#                                        codes/env/train-print-every.diff)
#          KTG_T7_GAMES     default 600 (overridden by the positional arg)
#          KTG_STAGE_ONLY=1 -> stage the dated archive and stop before any engine stage
#
# KNOBS AND THEIR DERIVATION (tasks/converged_test_7x7/implementation.md section 10).
# E = NUM_TRAIN_SAMPLES_PER_EPOCH is the pivot; every other number is a ratio off it,
# and every ratio is either upstream's own or a constraint read out of the source:
#
#   BATCHSIZE 32                 the smoke measured peak VRAM 4094 MiB at batch 32 on one
#                                GPU with a b7c96h3tfrs; 32 keeps 156 optimiser steps per
#                                cycle, which is what makes the loss curve dense.
#   E = 5000                     156 batches per epoch, comfortably over the 100-batch
#                                floor that train.py:1379's stock print interval imposes
#                                even BEFORE the KTG_PRINT_EVERY patch, so the run logs
#                                at least one row per cycle even if the patch were absent.
#   SWA = 2500                   E//2, which is train.py:441's own default relation.
#   MAX_TRAIN_PER_DATA 8         upstream's reuse cap; never raised.
#   SHUFFLE_MINROWS 6000         = 1.2*E. Two constraints meet here: train.py:1303-1346
#                                returns None (-> -quit-if-no-data exits with NO export)
#                                unless the shuffled window holds round(E/batch) = 157
#                                batches, and shuffle.py:1058,1076 caps rows coming from
#                                random/tdata/ at min_rows, so cycle 1's window IS
#                                min_rows. 6000 rows = 187 batches > 157.
#   MAX_TRAIN_SAMPLES_PER_CYCLE  = 5*E = 25000, upstream's own cap/epoch ratio
#                                (500000/100000).
#   SHUFFLE_KEEPROWS 30000       = 1.2*cap, upstream's own keep/cap ratio (600000/500000).
#   TAPER_WINDOW_SCALE 12000     = 2*min_rows, the 9x9 knob set's own ratio (50000/25000).
#   EPOCHS_PER_EXPORT 1          one candidate per cycle, so every cycle can export once
#                                the window fills; paired with -max-epochs-this-instance 1
#                                so the trainer cannot export twice inside one cycle.
#   NUM_GAMES_PER_CYCLE          sized so rows/cycle >= 1.2*E = 6000. rows/game at 7x7 is
#                                MEASURED in cycle 1 (the 9x9 smoke measured 31.7-32.0
#                                rows/game; area scales 49/81, so ~19 is the prior and 12
#                                is the conservative floor from claim c10). 600 games in
#                                cycle 1 clears 6000 rows even at 10 rows/game; the caller
#                                re-derives ceil(1.2*E/r) from the measurement afterwards.
#   NUM_THREADS_FOR_SHUFFLING 8  unchanged from the 9x9 knob set and from upstream.

set -e
set -o pipefail

CYCLE_LABEL="${1:-cycle}"
GAMES_THIS_CYCLE="${2:-${KTG_T7_GAMES:-600}}"

KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
export KTG_ROOT
AZ_ROOT="${AZ_ROOT:-/home/schmidt/ssci-haiyangw/az}"
KTG_CODES="${KTG_CODES:-$AZ_ROOT/results/ktg/paper_1902.10565/codes}"
export KTG_CODES
W="${KTG_T7_BASEDIR:-$KTG_ROOT/runs/t7}"

# env.sh sources the venv activate script, which is not written for `set -u`.
set +u
# shellcheck disable=SC1091
source "$KTG_ROOT/env.sh"
set -u

# o11_torch_threads_cap: the trainer and the shuffler both honour these.
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4

# ---- the board length, in ONE place ----------------------------------------
export KTG_POS_LEN=7

# ---- dense loss logging (codes/env/train-print-every.diff) ------------------
export KTG_PRINT_EVERY="${KTG_PRINT_EVERY:-8}"

# ---- 7x7 configs -----------------------------------------------------------
export SELFPLAY_CONFIG="$KTG_CODES/cfg/selfplay_7x7.cfg"
export GATING_CONFIG="$KTG_CODES/cfg/gatekeeper_7x7.cfg"

# ---- knob set --------------------------------------------------------------
export NUM_GAMES_PER_CYCLE="$GAMES_THIS_CYCLE"
export NUM_THREADS_FOR_SHUFFLING=8
export NUM_TRAIN_SAMPLES_PER_EPOCH="${NUM_TRAIN_SAMPLES_PER_EPOCH:-5000}"
export MAX_TRAIN_PER_DATA=8
export NUM_TRAIN_SAMPLES_PER_SWA="${NUM_TRAIN_SAMPLES_PER_SWA:-2500}"
export BATCHSIZE="${BATCHSIZE:-32}"
export SHUFFLE_MINROWS="${SHUFFLE_MINROWS:-6000}"
export MAX_TRAIN_SAMPLES_PER_CYCLE="${MAX_TRAIN_SAMPLES_PER_CYCLE:-25000}"
export TAPER_WINDOW_SCALE="${TAPER_WINDOW_SCALE:-12000}"
export SHUFFLE_KEEPROWS="${SHUFFLE_KEEPROWS:-30000}"
export EPOCHS_PER_EXPORT=1
export KTG_ONE_CYCLE=1

NAMEPREFIX="${KTG_T7_NAMEPREFIX:-ktgt7}"
TRAININGNAME="${KTG_T7_TRAININGNAME:-t7}"
MODELKIND="${KTG_T7_MODELKIND:-b7c96h3tfrs}"
USEGATING=1     # never 0: node gating_rule

mkdir -p "$W/logs"
CYCLE_LOG="$W/logs/t7_${CYCLE_LABEL}.txt"

echo "t7_cycle: label=$CYCLE_LABEL basedir=$W pos_len=$KTG_POS_LEN print_every=$KTG_PRINT_EVERY"
echo "t7_cycle: katago=$KATAGO_BIN src=$KATAGO_SRC"
echo "t7_cycle: cfg selfplay=$SELFPLAY_CONFIG gate=$GATING_CONFIG"
echo "t7_cycle: knobs games=$NUM_GAMES_PER_CYCLE samples_per_epoch=$NUM_TRAIN_SAMPLES_PER_EPOCH batch=$BATCHSIZE reuse=$MAX_TRAIN_PER_DATA minrows=$SHUFFLE_MINROWS keeprows=$SHUFFLE_KEEPROWS cap=$MAX_TRAIN_SAMPLES_PER_CYCLE taper=$TAPER_WINDOW_SCALE swa=$NUM_TRAIN_SAMPLES_PER_SWA epochs_per_export=$EPOCHS_PER_EXPORT"
echo "t7_cycle: cycle log -> $CYCLE_LOG"

# The loop copy runs `git rev-parse --show-toplevel` and refuses to run anywhere but the
# scratch clone (its own guard), so cd there first.
cd "$KATAGO_SRC"

set +e
bash "$KTG_CODES/loop/synchronous_loop_9x9.sh" \
     "$NAMEPREFIX" "$W" "$TRAININGNAME" "$MODELKIND" "$USEGATING" 2>&1 | tee -a "$CYCLE_LOG"
RC="${PIPESTATUS[0]}"
set -e

echo "t7_cycle: label=$CYCLE_LABEL loop exit=$RC"
exit "$RC"
