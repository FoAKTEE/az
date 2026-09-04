#!/bin/bash -eu
set -o pipefail
# train_9x9.sh -- mission ktg-train, node arxiv-1902.10565::cfg_9x9_override
# Copy of ref-code/lightvector-KataGo/python/selfplay/train.sh at v1.18.2
# (fd0723fdbc0e9d82cf269c9630af8c27c57c07c4) with exactly one change: the board
# length argument handed to train.py on line 88 upstream is 9, not 19, so that it
# matches dataBoardLen in codes/cfg/selfplay_9x9.cfg (obligation o02). Leaving the
# two independent is silent: python/data_processing_pytorch.py:91 only asserts when
# the written rows and the trainer disagree, and 19/19 on 81 real points costs
# ~(361/81)^2 attention FLOPs for nothing.
#
# That 9 is now written as ${KTG_POS_LEN:-9} (node converged_test_7x7): the same
# variable that codes/eval/check_pos_len_npz.py reads, so one export sets the board
# length of the trainer AND of the pre-shuffle guard and they cannot drift apart.
# With KTG_POS_LEN unset the expansion is the literal 9 and this wrapper behaves
# exactly as it did before -- the 9x9 production chain sets nothing.
#
# The same node adds $KTG_TRAIN_EXTRA_ARGS, EMPTY BY DEFAULT: extra train.py flags a
# caller needs that the loop's fixed invocation cannot supply. It is expanded UNQUOTED,
# exactly like the $EXTRAFLAG on the line above it, so it word-splits on spaces and
# disappears entirely when unset. The 9x9 chain sets nothing and the command line it
# builds is byte-identical to the one this wrapper built before.
# Positional interface is unchanged: BASEDIR TRAININGNAME MODELKIND BATCHSIZE EXPORTMODE
# Called by the mission loop copy in place of upstream ./train.sh.
{
# Runs training in $BASEDIR/train/$TRAININGNAME
# Should be run once per persistent training process.
# Outputs results in torchmodels_toexport/ in an ongoing basis (EXPORTMODE == "main").
# Or, to torchmodels_toexport_extra/ (EXPORTMODE == "extra").
# Or just trains without exporting (EXPORTMODE == "trainonly").

if [[ $# -lt 5 ]]
then
    echo "Usage: $0 BASEDIR TRAININGNAME MODELKIND BATCHSIZE EXPORTMODE OTHERARGS"
    echo "BASEDIR containing selfplay data and models and related directories"
    echo "TRAININGNAME name to prefix models with, specific to this training daemon"
    echo "MODELKIND what size model to train, like b10c128, see ../modelconfigs.py"
    echo "BATCHSIZE number of samples to concat together per batch for training, must match shuffle"
    echo "EXPORTMODE 'main': train and export for selfplay. 'extra': train and export extra non-selfplay model. 'trainonly': train without export"
    exit 0
fi
# Extra train.py arguments, empty by default (node converged_test_7x7). Read here so
# that `set -u` never sees it unset, and expanded unquoted below.
KTG_TRAIN_EXTRA_ARGS="${KTG_TRAIN_EXTRA_ARGS:-}"

BASEDIR="$1"
shift
TRAININGNAME="$1"
shift
MODELKIND="$1"
shift
BATCHSIZE="$1"
shift
EXPORTMODE="$1"
shift

#------------------------------------------------------------------------------

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
else
  PYTHON=python
fi

set -x

mkdir -p "$BASEDIR"/train/"$TRAININGNAME"

if [[ -n $(pwd | grep "^$BASEDIR/scripts/") ]]
then
    echo "Already running out of snapshotted scripts directory, not snapshotting again"
else
    GITROOTDIR="$(git rev-parse --show-toplevel)"

    git show --no-patch --no-color > "$BASEDIR"/train/"$TRAININGNAME"/version.txt
    git diff --no-color > "$BASEDIR"/train/"$TRAININGNAME"/diff.txt
    git diff --staged --no-color > "$BASEDIR"/train/"$TRAININGNAME"/diffstaged.txt

    # For archival and logging purposes - you can look back and see exactly the python code on a particular date
    DATE_FOR_FILENAME=$(date "+%Y%m%d-%H%M%S")
    DATED_ARCHIVE="$BASEDIR"/scripts/train/dated/"$DATE_FOR_FILENAME"
    mkdir -p "$DATED_ARCHIVE"
    cp "$GITROOTDIR"/python/*.py "$GITROOTDIR"/python/selfplay/train.sh "$DATED_ARCHIVE"
    cp -r "$GITROOTDIR"/python/katago "$DATED_ARCHIVE"
    cp -r "$GITROOTDIR"/python/muon "$DATED_ARCHIVE"
    git show --no-patch --no-color > "$DATED_ARCHIVE"/version.txt
    git diff --no-color > "$DATED_ARCHIVE"/diff.txt
    git diff --staged --no-color > "$DATED_ARCHIVE"/diffstaged.txt
    cd "$DATED_ARCHIVE"
fi

if [ "$EXPORTMODE" == "main" ]
then
    EXPORT_SUBDIR=torchmodels_toexport
    EXTRAFLAG=""
elif [ "$EXPORTMODE" == "extra" ]
then
    EXPORT_SUBDIR=torchmodels_toexport_extra
    EXTRAFLAG=""
elif [ "$EXPORTMODE" == "trainonly" ]
then
    EXPORT_SUBDIR=torchmodels_toexport_extra
    EXTRAFLAG="-no-export"
else
    echo "EXPORTMODE was not 'main' or 'extra' or 'trainonly', run with no arguments for usage"
    exit 1
fi

time $PYTHON ./train.py \
     -traindir "$BASEDIR"/train/"$TRAININGNAME" \
     -latestdatadir "$BASEDIR"/shuffleddata/ \
     -exportdir "$BASEDIR"/"$EXPORT_SUBDIR" \
     -exportprefix "$TRAININGNAME" \
     -pos-len "${KTG_POS_LEN:-9}" \
     -batch-size "$BATCHSIZE" \
     -model-kind "$MODELKIND" \
     $EXTRAFLAG \
     $KTG_TRAIN_EXTRA_ARGS \
     "$@" \
     2>&1 | tee -a "$BASEDIR"/train/"$TRAININGNAME"/stdout.txt

exit 0
}
