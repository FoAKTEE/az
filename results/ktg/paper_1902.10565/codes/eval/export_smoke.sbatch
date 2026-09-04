#!/bin/bash -l
#SBATCH --job-name=ktg-export-smoke
#SBATCH --account=ssci-anima
#SBATCH --partition=b200
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=00:30:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/export-smoke-%j.log
#
# Runner for node arxiv-1902.10565::tiny_model_export_smoke. All the science is
# in export_smoke.sh; this only supplies a GPU, the toolchain, and a transcript.
# Sizing: compute-budget SKILL.md "Debug / build / data prep" preset.

set -uo pipefail

R=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
HERE=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/eval
KIND=${KIND:-b7c96h3tfrs}

export KTG_ROOT="$R"
export W="$R/runtime/smoke/x"
export W_NEG="$R/runtime/smoke/x_ffng"

mkdir -p "$R/logs" "$R/evidence/tiny_smoke"
TRANSCRIPT="$R/evidence/tiny_smoke/export_smoke-${SLURM_JOB_ID:-manual}.txt"

# shellcheck disable=SC1091
. "$R/env.sh"

bash "$HERE/export_smoke.sh" "$KIND" 2>&1 | tee "$TRANSCRIPT"
RC=${PIPESTATUS[0]}
echo "export_smoke.sh exit=$RC" | tee -a "$TRANSCRIPT"
echo "transcript: $TRANSCRIPT"
exit "$RC"
