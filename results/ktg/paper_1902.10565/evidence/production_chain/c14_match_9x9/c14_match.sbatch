#!/bin/bash -l
# ^ the -l matters: without a login shell, `module` is undefined on compute nodes
#SBATCH --job-name=ktg-c14
#SBATCH --account=ssci-anima
#SBATCH --partition=b200,l40s
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/matches/2026-09-06/logs/ktg-c14-%j.out
#SBATCH --error=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/matches/2026-09-06/logs/ktg-c14-%j.err
#
# c14_match.sbatch -- mission ktg-train, memo option (h): the cheap discriminator between
# "the loss stalled" and "the net stopped getting stronger".
#
# It is a DRIVER ONLY. The match itself is codes/eval/match.sbatch, run unmodified as a
# plain bash script, once per arm. Everything that differs between the arms is carried by
# the two environment variables match.sbatch already documents (BASEDIR, EVALDIR), so the
# audited script, its config and its refusal checks are the ones that run.
#
#   arm A   latest  vs  t9-s20919936-d1053205   (best by p0loss / pacc1, 19 exports back)
#   arm B   latest  vs  t9-s143744-d157367      (the frozen first accepted net)
#
# WHY ONE JOB AND NOT TWO. The compute policy caps the mission at 4 GPUs across running
# and pending jobs; the chain holds 1 running (305318) + 1 dependency-pending (314831).
# One 1-GPU job keeps the footprint at 3. The two arms run sequentially on that GPU.
#
# WHY A SNAPSHOT BASEDIR. runs/p1/models grows while the chain runs (a new accepted net
# roughly every 19 min), so match.sbatch's "largest s in BASEDIR/models" would not resolve
# to the same net in both arms. BASEDIR is therefore a frozen copy of exactly the three
# nets under test, taken on the login node at 2026-09-06T10:23 EDT and verified
# byte-identical by sha256. Nothing under runs/p1 is read or written by this job.
#
# WHY A PER-ARM MANIFEST. match.sbatch pins the fixed opponent by CONTENT out of
# $EVALDIR/manifest.json and refuses to start if the file's sha256 has moved. Arm B's
# manifest is the one codes/eval/freeze_baseline.py itself writes over the snapshot; arm
# A's is the same schema with the baseline pinned to the best-by-loss net instead, which
# is the comparison the memo's decision rule is written against.

set -uo pipefail

R=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
D=$R/runtime/matches/2026-09-06
SNAP=$D/snapshot
MATCH=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/eval/match.sbatch

echo "=== c14 driver start $(date -Is) host=$(hostname -s) job=${SLURM_JOB_ID:-manual} ==="
echo "=== partition=${SLURM_JOB_PARTITION:-?}  gpus=${SLURM_GPUS_ON_NODE:-?}  cpus=${SLURM_CPUS_PER_TASK:-?} ==="
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader || true
echo "=== pinned latest: $(cat "$D/LATEST_PINNED") ==="

rcA=99; rcB=99

echo; echo "######## ARM A: latest vs t9-s20919936-d1053205 ########"
BASEDIR="$SNAP" EVALDIR="$D/armA_vs_s20919936" NUM_GAMES=400 bash "$MATCH"
rcA=$?
echo "######## ARM A exit=$rcA ########"

echo; echo "######## ARM B: latest vs t9-s143744-d157367 (first net) ########"
BASEDIR="$SNAP" EVALDIR="$D/armB_vs_first" NUM_GAMES=400 bash "$MATCH"
rcB=$?
echo "######## ARM B exit=$rcB ########"

echo "=== c14 driver end $(date -Is)  armA=$rcA armB=$rcB ==="
[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ]
