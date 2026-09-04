#!/bin/bash -eu
set -eu -o pipefail
{

# Mission copy of python/selfplay/synchronous_loop.sh
#   upstream: lightvector/KataGo v1.18.2 @ fd0723fdbc0e9d82cf269c9630af8c27c57c07c4
#   node    : arxiv-1902.10565::loop_resume_under_walltime
#
# Copied verbatim except for the numbered changes below; positional args and the
# cycle order (gatekeeper -> selfplay -> shuffle -> train -> export, upstream
# :93-116) are unchanged, and errexit + nounset + pipefail are in force from the
# first line of the body so any stage failure still stops the loop.
#
# Obligation o34. Upstream carries -eu on the shebang alone (upstream :1) and
# relies on the script being EXECUTED, which is how upstream's own
# synchronous_loop.sh is started. loop.sbatch launches this file from its
# `bash "$LOOP_SH" ...` line instead, and a shebang -- options included -- is
# ignored when a script is handed to an interpreter that way: -e and -u were
# both off for the whole staging section below, so a failed cp, git or cd was
# followed by cycle 1 out of a wrong or incomplete archive. `set -eu` on line 2
# is therefore part of the body, not of the shebang, and holds however the file
# is invoked. The shebang keeps its -eu so a direct ./synchronous_loop_9x9.sh is
# identical.
#
# Every command of the staging section -- everything between the positional
# assignments below and the `while true` -- was audited against errexit: the
# only places that may legitimately return non-zero are the `if` / `case` / `for`
# tests (a condition is exempt from -e), the `rm -rf ... /*.exported` and
# `/*.tmp` sweeps (`rm -f` on a non-matching glob exits 0), and the scratch-guard
# call, which is already bracketed by `set +e` / `set -e` at the top of the cycle
# so its exit code can be read. Every shell variable that is not a positional
# argument is read through `${VAR:-default}`, so -u adds no new abort path; the
# positional five are guarded by the `$# -lt 5` check below.
#
#   1  upstream :70  SELFPLAY_CONFIG  -> codes/cfg/selfplay_9x9.cfg     (o13)
#   2  upstream :71  GATING_CONFIG    -> codes/cfg/gatekeeper_9x9.cfg   (o13)
#   3  upstream :81  binary copy      -> "$KATAGO_BIN" (cpp/build/katago) (o17)
#   4  upstream :109 ./train.sh       -> ./train_9x9.sh  (-pos-len 9; owned by
#                                       node cfg_9x9_override, referenced here)
#   5  upstream :113 ./export_model_for_selfplay.sh -> ./export_model_for_selfplay_9x9.sh
#                                       (mv before rm; o09)
#   6  new, before the while loop      stale torchmodels_toexport/*.exported sweep (o09)
#   7  new, top of the while body      call codes/data_budget/scratch_guard.sh and
#                                       abort on any non-zero exit; every storage
#                                       threshold lives in budget.env, none here
#                                       (node data_budget; o04, o27)
#   8  new, top/end of the while body  KTG_ONE_CYCLE=1 runs exactly one cycle
#   9  upstream :57-66 knob block      one override-able variable block, 9x9 sized
#  10  new, end of the while body       $BASEDIR/.cycles_completed progress
#                                       counter, read by loop.sbatch's breaker
#                                       (o33)
#
# The script keeps upstream's GITROOTDIR="$(git rev-parse --show-toplevel)" (:35)
# and the git show/diff calls (:84-86), so it MUST be run from inside the scratch
# clone $KATAGO_SRC, never from the read-only mirror ref-code/lightvector-KataGo.

if [[ $# -lt 5 ]]
then
    echo "Usage: $0 NAMEPREFIX BASEDIR TRAININGNAME MODELKIND USEGATING"
    echo "Assumes katago is already built and the executable is present at \$KATAGO_BIN (cpp/build/katago)."
    echo "NAMEPREFIX string prefix for this training run, try to pick something globally unique. Will be displayed to users when KataGo loads the model."
    echo "BASEDIR containing selfplay data and models and related directories"
    echo "TRANINGNAME name to prefix models with, specific to this training daemon"
    echo "MODELKIND what size model to train, like 'b7c96h3tfrs', see ../modelconfigs.py"
    echo "USEGATING = 1 to use gatekeeper, 0 to not use gatekeeper"
    exit 0
fi
NAMEPREFIX="$1"
shift
BASEDIRRAW="$1"
shift
TRAININGNAME="$1"
shift
MODELKIND="$1"
shift
USEGATING="$1"
shift

# --- mission guard: engine refuses a non-SwiGLU transformer FFN ---------------
# cpp/neuralnet/cudaandrocmbackend.inc:3307-3308 aborts on a transformer trunk
# whose FFN is not SwiGLU, and it does so only after a full cycle of selfplay.
# Node engine_ffn_swiglu_constraint.
case "$MODELKIND" in
    *tfrs|*tflrs) ;;
    *)
        echo "MODELKIND '$MODELKIND' is not a SwiGLU transformer kind (*tfrs / *tflrs);" >&2
        echo "the CUDA backend refuses it (cudaandrocmbackend.inc:3307-3308). Refusing to start." >&2
        exit 2
        ;;
esac

# --- mission guard: gating is on for every cycle, including the first ---------
if [ "$USEGATING" -ne 1 ]
then
    echo "USEGATING must be 1 for this mission (node gating_rule); got '$USEGATING'." >&2
    exit 2
fi

BASEDIR="$(realpath "$BASEDIRRAW")"
GITROOTDIR="$(git rev-parse --show-toplevel)"
LOGSDIR="$BASEDIR"/logs
SCRATCHDIR="$BASEDIR"/shufflescratch

# --- mission guard: never run out of the read-only mirror ---------------------
# upstream :35 and :84-86 execute git in whatever tree the script lands in.
if [ -n "${KATAGO_SRC:-}" ]
then
    KATAGO_SRC_REAL="$(realpath "$KATAGO_SRC")"
    if [ "$(realpath "$GITROOTDIR")" != "$KATAGO_SRC_REAL" ]
    then
        echo "git root '$GITROOTDIR' != \$KATAGO_SRC '$KATAGO_SRC_REAL';" >&2
        echo "run the loop from the scratch clone, not from the read-only mirror." >&2
        exit 2
    fi
fi

# Mission code root in the az repo (configs, train wrapper, export wrapper).
KTG_CODES="${KTG_CODES:-/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes}"

# Create all the directories we need
mkdir -p "$BASEDIR"
mkdir -p "$LOGSDIR"
mkdir -p "$SCRATCHDIR"
mkdir -p "$BASEDIR"/selfplay
mkdir -p "$BASEDIR"/gatekeepersgf
mkdir -p "$BASEDIR"/torchmodels_toexport

# Parameters for the training run.
# CHANGE 9: one override-able block. `derive_cycle_knobs_9x9` edits the defaults
# here and nowhere else; smoke_loop.sbatch (node synchronous_loop_smoke)
# overrides them in the environment.
#
# The defaults below are DERIVED, no longer a hypothesis: every one is the
# solution of a constraint read out of train.py / shuffle.py at path:line,
# evaluated at the rows/game Slurm job 298712 measured (r = 32.3 real net,
# 31.675 random net). The derivation, one comment per knob, lives in
# codes/loop/knobs_9x9.env; the full trace is
# evidence/derive_cycle_knobs/derivation.md; the arithmetic is re-run by
# codes/eval/derive_knobs.py, and `--assert-loop-defaults <this file>` fails if
# any default below drifts from it. Obligations o24, o13 (knob conjunct).
NUM_GAMES_PER_CYCLE="${NUM_GAMES_PER_CYCLE:-1000}"          # upstream :57 = 500; >= max(1.2*E/r_lo, 1.25*MINROWS/r0_lo)
NUM_THREADS_FOR_SHUFFLING="${NUM_THREADS_FOR_SHUFFLING:-8}" # upstream :58 = 8, unchanged (measured 4+8 = 12 threads)
NUM_TRAIN_SAMPLES_PER_EPOCH="${NUM_TRAIN_SAMPLES_PER_EPOCH:-20000}"   # upstream :59 = 100000; >= 100*BATCHSIZE (train.py:1379)
MAX_TRAIN_PER_DATA="${MAX_TRAIN_PER_DATA:-8}"               # upstream :60 = 8, the reuse cap; never raised
NUM_TRAIN_SAMPLES_PER_SWA="${NUM_TRAIN_SAMPLES_PER_SWA:-10000}"       # upstream :61 = 80000; = E//2, train.py:441's own default
BATCHSIZE="${BATCHSIZE:-128}"                               # upstream :62 = 128, unchanged (peak VRAM 4094 MiB at batch 32)
SHUFFLE_MINROWS="${SHUFFLE_MINROWS:-25000}"                 # upstream :63 = 100000; = 1.25*E, and cycle 1's window IS min_rows
MAX_TRAIN_SAMPLES_PER_CYCLE="${MAX_TRAIN_SAMPLES_PER_CYCLE:-100000}"  # upstream :64 = 500000; = 5*E, upstream's own cap/epoch ratio
TAPER_WINDOW_SCALE="${TAPER_WINDOW_SCALE:-50000}"           # upstream :65 = 50000, unchanged (no constraint binds it)
SHUFFLE_KEEPROWS="${SHUFFLE_KEEPROWS:-120000}"              # upstream :66 = 600000; = 1.2*cap, upstream's own keep/cap ratio

# At most one exported candidate per cycle: without the pair the trainer keeps
# exporting inside one cycle (train.py:116 -epochs-per-export, :118
# -max-epochs-this-instance). 5 = floor(min(games*r*reuse, max(cap,E)) / E), the
# same at r and at the conservative r_lo.
EPOCHS_PER_EXPORT="${EPOCHS_PER_EXPORT:-5}"

# CHANGE 1 + 2: mission 9x9 configs. Upstream :70-71 default to the
# mixed-board-size selfplay1.cfg / gatekeeper1.cfg. Obligation o13.
SELFPLAY_CONFIG="${SELFPLAY_CONFIG:-$KTG_CODES/cfg/selfplay_9x9.cfg}"
GATING_CONFIG="${GATING_CONFIG:-$KTG_CODES/cfg/gatekeeper_9x9.cfg}"

# The two wrappers this loop calls in place of upstream's (changes 4 and 5).
TRAIN_WRAPPER="${TRAIN_WRAPPER:-$KTG_CODES/loop/train_9x9.sh}"
EXPORT_WRAPPER="${EXPORT_WRAPPER:-$KTG_CODES/loop/export_model_for_selfplay_9x9.sh}"

# CHANGE 7 (node data_budget, obligations o04 / o27): the storage guard. Every
# threshold lives in codes/data_budget/budget.env, which the guard reads; this
# script holds no storage number of its own.
SCRATCH_GUARD="${KTG_SCRATCH_GUARD:-$KTG_CODES/data_budget/scratch_guard.sh}"

# CHANGE 12 (obligations o03 / c06): the stage sampler's phase label. The sampler itself is
# started and stopped by codes/loop/loop.sbatch, which owns the link; this loop only retags
# the samples with the cycle they belong to, so audit_smoke.py can report nlwp_max and GPU
# duty per (phase, stage) instead of per stage over a whole three-day link. The call is
# guarded on the run file, so smoke_loop.sbatch (which starts its own monitor with its own
# phase labels) and the KTG_STAGE_ONLY dry run are unaffected, and it is never fatal.
STAGE_MONITOR="${KTG_STAGE_MONITOR:-$KTG_CODES/eval/stage_monitor.sh}"
MONITOR_DIR="${KTG_MONITOR_DIR:-$BASEDIR/monitor}"

for f in "$SELFPLAY_CONFIG" "$GATING_CONFIG" "$TRAIN_WRAPPER" "$EXPORT_WRAPPER" "$SCRATCH_GUARD"
do
    if [ ! -f "$f" ]
    then
        echo "required mission file missing: $f" >&2
        exit 2
    fi
done

# Copy all the relevant scripts and configs and the katago executable to a dated directory.
# For archival and logging purposes - you can look back and see exactly the python code on a particular date
DATE_FOR_FILENAME=$(date "+%Y%m%d-%H%M%S")
DATED_ARCHIVE="$BASEDIR"/scripts/dated/"$DATE_FOR_FILENAME"
mkdir -p "$DATED_ARCHIVE"/bin
cp "$GITROOTDIR"/python/*.py "$GITROOTDIR"/python/selfplay/*.py "$GITROOTDIR"/python/selfplay/*.sh "$DATED_ARCHIVE"
cp -r "$GITROOTDIR"/python/katago "$DATED_ARCHIVE"
cp -r "$GITROOTDIR"/python/muon "$DATED_ARCHIVE"

# CHANGE 3 (obligation o17): upstream :81 copies $GITROOTDIR/cpp/katago -- a path
# the CMake build never produces. env.sh:20-22 puts the binary at cpp/build/katago,
# so under bash -eu the stock copy kills cycle 1 before any work happens.
KATAGO_BIN_PATH="${KATAGO_BIN:-$GITROOTDIR/cpp/build/katago}"
if [ ! -x "$KATAGO_BIN_PATH" ]
then
    echo "katago binary not executable at '$KATAGO_BIN_PATH' (expected cpp/build/katago); source env.sh first." >&2
    exit 2
fi
cp "$KATAGO_BIN_PATH" "$DATED_ARCHIVE"/bin/katago

# CHANGE 4 + 5: the mission train and export wrappers ride into the archive
# alongside upstream's python/selfplay/*.sh (copied above), because the loop
# runs out of the archive (upstream :88-89).
cp "$TRAIN_WRAPPER" "$DATED_ARCHIVE"/train_9x9.sh
cp "$EXPORT_WRAPPER" "$DATED_ARCHIVE"/export_model_for_selfplay_9x9.sh
chmod +x "$DATED_ARCHIVE"/train_9x9.sh "$DATED_ARCHIVE"/export_model_for_selfplay_9x9.sh

cp "$SELFPLAY_CONFIG" "$DATED_ARCHIVE"/selfplay.cfg
cp "$GATING_CONFIG" "$DATED_ARCHIVE"/gatekeeper.cfg
git show --no-patch --no-color > "$DATED_ARCHIVE"/version.txt
git diff --no-color > "$DATED_ARCHIVE"/diff.txt
git diff --staged --no-color > "$DATED_ARCHIVE"/diffstaged.txt

# CHANGE 6 (obligation o09): a killed export leaves a <NAME>.exported directory
# that upstream export_model_for_selfplay.sh:54-56 skips forever. Belt-and-braces
# with the same sweep in loop.sbatch: clear stale markers before the first cycle.
rm -rf "$BASEDIR"/torchmodels_toexport/*.exported
rm -rf "$BASEDIR"/torchmodels_toexport_extra/*.exported
# shuffle.sh:105 renames shuffleddata/<ts>.tmp at the end; a kill mid-shuffle
# leaves the .tmp behind and cleanup_old_dirs.py:24 never prunes it. train.py
# :1206-1210 ignores .tmp, so these are pure dead weight against the scratch cap.
rm -rf "$BASEDIR"/shuffleddata/*.tmp

# Also run the code out of the archive, so that we don't unexpectedly crash or change behavior if the local repo changes.
cd "$DATED_ARCHIVE"

# Cycle counter, used only to label the per-cycle scratch_guard log triple.
CYCLE_INDEX=0

# Dry-run hook: KTG_STAGE_ONLY=1 stops here, after the archive is staged and the
# startup sweeps have run but before any engine or trainer stage. It exists so
# the o17 binary-copy fix and the o13 config resolution can be EXECUTED without
# a GPU and without a Slurm job; the cycle itself never runs under it.
if [ "${KTG_STAGE_ONLY:-0}" = "1" ]
then
    echo "KTG_STAGE_ONLY=1 -- archive staged at $DATED_ARCHIVE, no cycle run."
    ls -l "$DATED_ARCHIVE"/bin/katago "$DATED_ARCHIVE"/selfplay.cfg "$DATED_ARCHIVE"/gatekeeper.cfg "$DATED_ARCHIVE"/train_9x9.sh "$DATED_ARCHIVE"/export_model_for_selfplay_9x9.sh
    exit 0
fi

# Begin cycling forever, running each step in order.
set -x
while true
do
    # CHANGE 8: manual brake, checked at the top of every cycle. data_budget's
    # cap guard and loop.sbatch's chain guard both use the same file.
    if [ -e "$BASEDIR"/STOP ]
    then
        set +x
        echo "STOP file present at $BASEDIR/STOP -- exiting the loop cleanly."
        exit 0
    fi

    # CHANGE 7: per-cycle scratch accounting and cap, delegated in full to node
    # data_budget's guard. It prints the du -sb / df -B1 / quotas.py triple that
    # o04 requires and decides by exit code; it is never advisory:
    #   0 within budget / 1 mission-root hard cap / 2 group free floor /
    #   3 could not measure.
    CYCLE_INDEX=$((CYCLE_INDEX + 1))
    set +x
    # CHANGE 12: retag the link's samples with this cycle. Only when loop.sbatch's monitor
    # is actually running -- smoke_loop.sbatch drives its own phases and the dry run has
    # none -- and never fatal.
    if [ -e "$MONITOR_DIR"/monitor.run ] && [ -f "$STAGE_MONITOR" ]
    then
        bash "$STAGE_MONITOR" phase "$MONITOR_DIR" "cycle$CYCLE_INDEX" || true
    fi
    set +e
    bash "$SCRATCH_GUARD" --label "cycle $CYCLE_INDEX pre-gatekeeper"
    GUARD_RC=$?
    set -e
    if [ "$GUARD_RC" -ne 0 ]
    then
        case "$GUARD_RC" in
            1) echo "scratch_guard exit 1: projected mission-root usage crosses the hard cap -- no new cycle." ;;
            2) echo "scratch_guard exit 2: group scratch free space below the safety floor -- no new cycle." ;;
            *) echo "scratch_guard exit $GUARD_RC: could not measure the budget -- refusing to start a cycle." ;;
        esac
        # 1 and 2 are deliberate storage refusals: brake the whole chain so the
        # queued successor does not retry into the same full filesystem. 3 is a
        # measurement failure and is reported as one, without the brake.
        if [ "$GUARD_RC" -eq 1 ] || [ "$GUARD_RC" -eq 2 ]
        then
            touch "$BASEDIR"/STOP
            exit 3
        fi
        exit 2
    fi
    set -x

    echo "Gatekeeper"
    time ./bin/katago gatekeeper -rejected-models-dir "$BASEDIR"/rejectedmodels -accepted-models-dir "$BASEDIR"/models/ -sgf-output-dir "$BASEDIR"/gatekeepersgf/ -test-models-dir "$BASEDIR"/modelstobetested/ -config "$DATED_ARCHIVE"/gatekeeper.cfg -quit-if-no-nets-to-test | tee -a "$BASEDIR"/gatekeepersgf/stdout.txt

    echo "Selfplay"
    time ./bin/katago selfplay -max-games-total "$NUM_GAMES_PER_CYCLE" -output-dir "$BASEDIR"/selfplay -models-dir "$BASEDIR"/models -config "$DATED_ARCHIVE"/selfplay.cfg | tee -a "$BASEDIR"/selfplay/stdout.txt

    echo "Shuffle"
    (
        # Skip validate since peeling off 5% of data is actually a bit too chunky and discrete when running at a small scale, and validation data
        # doesn't actually add much to debugging a fast-changing RL training.
        time SKIP_VALIDATE=1 ./shuffle.sh "$BASEDIR" "$SCRATCHDIR" "$NUM_THREADS_FOR_SHUFFLING" -min-rows "$SHUFFLE_MINROWS" -keep-target-rows "$SHUFFLE_KEEPROWS" -taper-window-scale "$TAPER_WINDOW_SCALE" | tee -a "$BASEDIR"/logs/outshuffle.txt
    )

    echo "Train"
    # CHANGE 4: ./train_9x9.sh in place of upstream :109 ./train.sh (train.sh:88
    # hard-codes -pos-len 19). Owned by node cfg_9x9_override.
    time ./train_9x9.sh "$BASEDIR" "$TRAININGNAME" "$MODELKIND" "$BATCHSIZE" main -samples-per-epoch "$NUM_TRAIN_SAMPLES_PER_EPOCH" -swa-period-samples "$NUM_TRAIN_SAMPLES_PER_SWA" -epochs-per-export "$EPOCHS_PER_EXPORT" -max-epochs-this-instance "$EPOCHS_PER_EXPORT" -quit-if-no-data -stop-when-train-bucket-limited -no-repeat-files -max-train-bucket-per-new-data "$MAX_TRAIN_PER_DATA" -max-train-bucket-size "$MAX_TRAIN_SAMPLES_PER_CYCLE"

    echo "Export"
    # CHANGE 5: ./export_model_for_selfplay_9x9.sh in place of upstream :113
    # (mv before rm, plus a captured exporter exit code). Obligations o09, o15.
    (
        time ./export_model_for_selfplay_9x9.sh "$NAMEPREFIX" "$BASEDIR" "$USEGATING" | tee -a "$BASEDIR"/logs/outexport.txt
    )

    # CHANGE 10 (obligation o33): progress marker. All five stages of this cycle
    # returned 0, so the link has demonstrably made progress. loop.sbatch reads
    # the counter at entry and again in finalize, and a link that advanced it
    # restarts the failure run -- without it the breaker counts three failures
    # over the whole lifetime of the chain rather than three in a row, because a
    # healthy production link never exits 0 and so never reaches the reset. One
    # writer (this loop), one reader (the wrapper), same $BASEDIR.
    set +x
    # Obligation o35: read the counter back in base 10. The `*[!0-9]*` guard
    # below admits a leading-zero "08", and to $(( )) that is an octal literal
    # with a digit octal does not have -- the expansion aborts, and under the
    # `set -e` this script now really runs with (o34) the loop dies after every
    # completed cycle without ever recording one. `10#` pins the base; the
    # whitespace trim covers a hand-edited file and the width test keeps the
    # value clear of the 2^63 wrap. Anything else still reads as 0, so a stray
    # byte costs at most one cycle of accounting, never the cycle itself.
    CYCLES_DONE=$(cat "$BASEDIR"/.cycles_completed 2>/dev/null || echo 0)
    CYCLES_DONE="${CYCLES_DONE#"${CYCLES_DONE%%[![:space:]]*}"}"
    CYCLES_DONE="${CYCLES_DONE%"${CYCLES_DONE##*[![:space:]]}"}"
    case "$CYCLES_DONE" in ''|*[!0-9]*) CYCLES_DONE=0 ;; esac
    [ "${#CYCLES_DONE}" -le 18 ] || CYCLES_DONE=0
    CYCLES_DONE=$(( 10#$CYCLES_DONE + 1 ))
    echo "$CYCLES_DONE" > "$BASEDIR"/.cycles_completed
    echo "cycle $CYCLE_INDEX complete -- $CYCLES_DONE cycle(s) recorded in $BASEDIR/.cycles_completed"
    set -x

    # CHANGE 8: smoke_loop.sbatch (node synchronous_loop_smoke) sets this to run
    # exactly one cycle and exit 0.
    if [ "${KTG_ONE_CYCLE:-0}" = "1" ]
    then
        set +x
        echo "KTG_ONE_CYCLE=1 -- one cycle done, exiting 0."
        exit 0
    fi
done

exit 0
}
