#!/bin/bash -l
#SBATCH --job-name=ktg-cfg9x9
#SBATCH --account=ssci-anima
#SBATCH --partition=b200
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=24
#SBATCH --mem=64G
#SBATCH --time=01:00:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/%x-%j.out
#SBATCH --error=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/%x-%j.err

# Node arxiv-1902.10565::cfg_9x9_override, phase 2: parse run, SZ[9] proof and the
# ps -o nlwp thread measurement, all inside one real allocation so that CPU_BUDGET
# is an allocated number and not a login-node guess.
set -u
set -o pipefail

REPO=/home/schmidt/ssci-haiyangw/az
OUT=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/cfgcheck/check-${SLURM_JOB_ID}.txt

source /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/env.sh

{
  echo "slurm_job_id        = ${SLURM_JOB_ID}"
  echo "slurm_node          = $(hostname)"
  echo "slurm_partition     = ${SLURM_JOB_PARTITION}"
  echo "SLURM_CPUS_PER_TASK = ${SLURM_CPUS_PER_TASK}"
  echo "SLURM_MEM_PER_NODE  = ${SLURM_MEM_PER_NODE:-unset}"
  echo "gres                = ${SLURM_JOB_GPUS:-${SLURM_STEP_GPUS:-unset}}"
  echo "katago              = $KATAGO_BIN"
  "$KATAGO_BIN" version
  echo
  bash "$REPO/results/ktg/paper_1902.10565/codes/eval/check_cfg_9x9.sh"
  echo "CHECKER_EXIT=$?"
} 2>&1 | tee "$OUT"

grep -q 'CHECK_CFG_9X9: PASS' "$OUT"
