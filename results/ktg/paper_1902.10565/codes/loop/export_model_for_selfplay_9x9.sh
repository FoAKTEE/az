#!/bin/bash -eu
set -eu -o pipefail
{
# Mission copy of python/selfplay/export_model_for_selfplay.sh
#   upstream: lightvector/KataGo v1.18.2 @ fd0723fdbc0e9d82cf269c9630af8c27c57c07c4
#   node    : arxiv-1902.10565::loop_resume_under_walltime
#
# Copied verbatim except:
#   A  obligation o09 -- upstream removes the source checkpoint directory at
#      :89 BEFORE renaming the temp export into place at :108. A kill in that window destroys the
#      only copy of the checkpoint and leaves a <NAME>.exported directory that
#      upstream :54-56 skips forever. Here the rename happens FIRST and the
#      source is removed only after the target is in place, so every kill point
#      leaves either (a) SRC intact and at most a partial .exported temp that
#      the startup sweep clears, or (b) TARGET complete and SRC still present,
#      which case B below finishes on the next pass.
#   B  the "already exists" branch (upstream :65-71) now completes an
#      interrupted rename instead of leaving SRC in torchmodels_toexport forever.
#   C  obligation o15 -- the exporter and checkpoint-cleaner exit codes are
#      captured explicitly rather than relying on `-e` inside a pipeline
#      subshell, and a failure leaves SRC untouched for the next cycle to retry.
#   D  obligation o34 -- `set -eu` is repeated in the BODY, not left on the
#      shebang alone. synchronous_loop_9x9.sh runs this file as
#      ./export_model_for_selfplay_9x9.sh, so the shebang does apply today and
#      the line changes nothing; it is here so that invoking the script as
#      `bash export_model_for_selfplay_9x9.sh` -- the form that silently dropped
#      -eu from the loop script (loop.sbatch's `bash "$LOOP_SH"` launch) --
#      cannot drop it here either.
#
# Takes any models in torchmodels_toexport/ and outputs a cuda-runnable model file to modelstobetested/
# Takes any models in torchmodels_toexport_extra/ and outputs a cuda-runnable model file to models_extra/
# Should be run periodically.

if [[ $# -ne 3 ]]
then
    echo "Usage: $0 NAMEPREFIX BASEDIR USEGATING"
    # CHANGE D (obligation o08): upstream's usage string names the TensorFlow-era
    # exporter, a file that does not exist at v1.18.2. The exporter this script
    # actually invokes below is export_model_pytorch.py, so the message names it.
    echo "Currently expects to be run from within the 'python' directory of the KataGo repo, or otherwise in the same dir as export_model_pytorch.py."
    echo "NAMEPREFIX string prefix for this training run, try to pick something globally unique. Will be displayed to users when KataGo loads the model."
    echo "BASEDIR containing selfplay data and models and related directories"
    echo "USEGATING = 1 to use gatekeeper, 0 to not use gatekeeper and output directly to models/"
    exit 0
fi
NAMEPREFIX="$1"
shift
BASEDIR="$1"
shift
USEGATING="$1"
shift

#------------------------------------------------------------------------------

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
else
  PYTHON=python
fi

mkdir -p "$BASEDIR"/torchmodels_toexport
mkdir -p "$BASEDIR"/torchmodels_toexport_extra
mkdir -p "$BASEDIR"/modelstobetested
mkdir -p "$BASEDIR"/models_extra
mkdir -p "$BASEDIR"/models

function exportStuff() {
    FROMDIR="$1"
    TODIR="$2"

    # Sort by timestamp so that we process in order of oldest to newest if there are multiple
    $PYTHON -W ignore "$(dirname "$0")/list_by_mtime.py" "$BASEDIR/$FROMDIR" | while read -r FILEPATH
    do
        #Make sure to skip tmp directories that are transiently there by the training,
        #they are probably in the process of being written
        if [ -z "$FILEPATH" ]
        then
            continue
        fi
        if [ "${FILEPATH: -4}" == ".tmp" ]
        then
            echo "Skipping tmp file:" "$FILEPATH"
        elif [ "${FILEPATH: -9}" == ".exported" ]
        then
            echo "Skipping self tmp file:" "$FILEPATH"
        else
            echo "Found model to export:" "$FILEPATH"
            NAME="$(basename "$FILEPATH")"

            SRC="$BASEDIR/$FROMDIR/$NAME"
            TMPDST="$BASEDIR/$FROMDIR/$NAME.exported"
            TARGET="$BASEDIR/$TODIR/$NAME"

            if [ -d "$BASEDIR"/modelstobetested/"$NAME" ] ||  \
               [ -d "$BASEDIR"/rejectedmodels/"$NAME" ] || \
               [ -d "$BASEDIR"/models/"$NAME" ] || \
               [ -d "$BASEDIR"/models_extra/"$NAME" ] || \
               [ -d "$BASEDIR"/modelsuploaded/"$NAME" ]
            then
                # CHANGE B: with mv-before-rm, a kill between the rename and the
                # source removal leaves both the exported model and SRC on disk.
                # Finish that interrupted move here instead of re-listing SRC
                # every cycle.
                #
                # The completed export is looked for in EVERY final location,
                # not only in $TARGET: by the time the next link reaches this
                # line the gatekeeper has usually already moved the candidate
                # out of modelstobetested/ into models/ or rejectedmodels/, so a
                # $TARGET-only test falls through to "already exists" and the
                # source lingers in torchmodels_toexport/ forever
                # (validation.md F4). A directory counts as a completed export
                # only once it holds model.bin.gz -- the last file written
                # before the rename -- so a half-written destination never
                # authorises deleting a checkpoint.
                EXPORTED_AT=""
                for FINALDIR in modelstobetested rejectedmodels models models_extra modelsuploaded
                do
                    if [ -f "$BASEDIR/$FINALDIR/$NAME/model.bin.gz" ]
                    then
                        EXPORTED_AT="$BASEDIR/$FINALDIR/$NAME"
                        break
                    fi
                done
                if [ -n "$EXPORTED_AT" ] && [ -d "$SRC" ]
                then
                    echo "Completing interrupted export of" "$NAME" "-- exported model present at" "$EXPORTED_AT" "-- removing source:" "$SRC"
                    rm -rf "$TMPDST"
                    rm -rf "$SRC"
                else
                    echo "Model with same name already exists but no completed export was found, so skipping:" "$SRC"
                fi
            else
                rm -rf "$TMPDST"
                mkdir "$TMPDST"

                # CHANGE C: capture the exporter exit codes. On failure SRC is
                # left untouched so the next cycle retries from the checkpoint.
                set -x
                set +e
                $PYTHON ./export_model_pytorch.py \
                        -checkpoint "$SRC/model.ckpt" \
                        -export-dir "$TMPDST" \
                        -model-name "$NAMEPREFIX-$NAME" \
                        -filename-prefix model \
                        -use-swa
                EXPORT_RC=$?
                set -e
                set +x
                if [ "$EXPORT_RC" -ne 0 ]
                then
                    echo "export_model_pytorch.py failed with exit $EXPORT_RC for" "$SRC" "-- leaving source intact" >&2
                    rm -rf "$TMPDST"
                    exit "$EXPORT_RC"
                fi

                set -x
                set +e
                $PYTHON ./clean_checkpoint.py \
                        -checkpoint "$SRC/model.ckpt" \
                        -output "$TMPDST/model.ckpt"
                CLEAN_RC=$?
                set -e
                set +x
                if [ "$CLEAN_RC" -ne 0 ]
                then
                    echo "clean_checkpoint.py failed with exit $CLEAN_RC for" "$SRC" "-- leaving source intact" >&2
                    rm -rf "$TMPDST"
                    exit "$CLEAN_RC"
                fi

                gzip "$TMPDST"/model.bin

                #Make a bunch of the directories that selfplay will need so that there isn't a race on the selfplay
                #machines to concurrently make it, since sometimes concurrent making of the same directory can corrupt
                #a filesystem
                #Only when not gating. When gating, gatekeeper is responsible.
                if [ "$USEGATING" -eq 0 ]
                then
                    if [ "$TODIR" != "models_extra" ]
                    then
                        mkdir -p "$BASEDIR/selfplay/$NAME/sgfs"
                        mkdir -p "$BASEDIR/selfplay/$NAME/tdata"
                    fi
                fi

                #Sleep a little to allow some tolerance on the filesystem
                sleep 5

                # CHANGE A (obligation o09): rename FIRST, remove the source only
                # once the target is in place. Upstream does these in the other
                # order (:89 then :108) and loses the checkpoint on a kill.
                mv "$TMPDST" "$TARGET"
                rm -r "$SRC"
                echo "Done exporting:" "$NAME" "to" "$TARGET"
            fi
        fi
    done
}

if [ "$USEGATING" -eq 0 ]
then
    exportStuff "torchmodels_toexport" "models"
else
    exportStuff "torchmodels_toexport" "modelstobetested"
fi
exportStuff "torchmodels_toexport_extra" "models_extra"

exit 0
}
