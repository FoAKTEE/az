---
name: cluster-job
description: Submit, monitor, and debug Slurm jobs on the Schmidt Sciences B200/B300 cluster (skipjack) at JHU ARCH. Use whenever the task involves running work on GPUs here — sbatch scripts, srun/interactive sessions, multi-GPU or multi-node training, checking queue status, diagnosing a job that failed, was rejected at submission, or produced no output. Also use when choosing a partition, GPU count, walltime, or memory request on this cluster.
---

# Job submission on `skipjack` (Schmidt B200/B300)

Full background: `docs/cluster-manual.md`. This skill is the operational path.

## Fixed facts — do not re-derive

| | |
|---|---|
| User / account | `ssci-haiyangw` / `ssci-anima` |
| Our partitions | `b200` (16 nodes, 8×B200 180 GB), `b300` (1 node, 8×B300), `l40s` (6 nodes, 8×L40S 48 GB) |
| Closed to us | `h100`, `h200`, `a100`, `med` — all `AllowAccounts=jhu` |
| Max walltime | `3-00:00:00`, every partition |
| Per GPU node | 124 schedulable CPUs, 1547 GB RAM, ~1 TB `/dev/shm`, 16 IB verbs devices |
| Billing | **Free.** `ssci-` prefix is exempt. Never add `ACCEPT_COST=1`. |
| QOS | Default `scavenger`. QOS has zero effect on priority here — don't set it. |

## Hard rules

1. **Every `b200`/`b300` job must request a GPU.** `job_submit.lua` rejects it otherwise:
   `Alert: partition 'b200' is a GPU partition but this job requests no GPU`.
   The CPU partitions its error message suggests are JHU-only — we have no CPU-only option.
2. **Always set `--mem`.** `DefMemPerNode=UNLIMITED` with `CR_CORE_MEMORY` selection means
   an unspecified job can take the whole node and block co-scheduling.
3. **Never write job output to `/tmp`.** It is node-local; the job reports `COMPLETED` and
   the log does not exist anywhere. Use `/home/schmidt/ssci-haiyangw` or
   `/scratch/schmidt/ssci-anima`. This includes the agent scratchpad under `/tmp`.
4. **Check scratch quota before any run that writes checkpoints** —
   `python3 /apps/helpers/quotas.py`. The group's 40 TB is ~94 % full and shared.
5. **Nothing heavy on the login node.** Sessions are cgroup-capped at 5 GB RAM.
   Builds, installs, and preprocessing go in a job or an `interact` session.
6. **Walltime must be honest.** Backfill scheduling means an accurate short `--time` starts
   sooner than a padded one. Never request more than 3 days — it will not be accepted.
7. **Ask for the fewest GPUs the work needs.** Queue wait scales sharply: a 1-GPU job
   started instantly on 2026-09-03 while a 2-GPU job sat pending behind higher-priority
   work. Validate a pipeline on 1 GPU before requesting a full node.

## Batch template

Scale `--gres`, `--cpus-per-task`, and `--mem` together: one node is 8 GPUs, 124 CPUs,
1547 GB, so budget roughly **15 CPUs and 180 GB per GPU**.

```bash
#!/bin/bash -l
# ^ the -l matters: without a login shell, `module` is undefined on compute nodes
#SBATCH --job-name=NAME
#SBATCH --account=ssci-anima
#SBATCH --partition=b200
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:8
#SBATCH --cpus-per-task=120
#SBATCH --mem=1400G
#SBATCH --time=1-00:00:00
#SBATCH --output=/scratch/schmidt/ssci-anima/<you>/logs/%x-%j.out
#SBATCH --error=/scratch/schmidt/ssci-anima/<you>/logs/%x-%j.err

set -euo pipefail
module load cuda/12.8.1          # 12.8+ required for Blackwell (sm_100)
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader
srun python train.py
```

Submit plainly — no `--export`, no `ACCEPT_COST`:

```bash
sbatch job.sh
```

`[BILLING] loaded!` and `[BILLING] Re-emitting cost at job start!` on stderr are normal and
mean nothing for us.

## Multi-node

InfiniBand RDMA is present (16 verbs devices per node), `MpiDefault=pmix_v3`.

```bash
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=8        # one task per GPU
#SBATCH --gres=gpu:8
#SBATCH --cpus-per-task=15
#SBATCH --mem=1400G

export MASTER_ADDR=$(scontrol show hostnames "$SLURM_JOB_NODELIST" | head -n1)
export MASTER_PORT=29500
srun python train.py
```

Multi-node queues far longer than single-node — 4–8 of the 16 B200 nodes are usually held
by other groups' reservations. Check `scontrol show reservation` before assuming the
scheduler is stuck.

## Interactive

```bash
interact -p b200 -g 1 -n 8 -m 64G -t 2:00:00      # debugging, builds, installs
interact -p l40s -g 1 -n 8 -m 64G -t 2:00:00      # when b200 is congested
```

`interact -l` lists partitions with your accounts and QOS.

## Choosing a partition

- **`b200`** — default for training. 16 nodes, most capacity.
- **`b300`** — 1 node only, frequently reserved. Use only if you specifically need B300.
- **`l40s`** — 48 GB GPUs, open to all accounts. Good for small models, inference, data
  pipeline debugging, and anything that does not fit the B200 queue wait. The old guidance
  "always use b200 or b300" predates this partition being opened up.

## Monitoring

```bash
sqme                                          # your active jobs
squeue -j <jobid> -o "%.8i %.8T %.10M %.10L %R"
sbrief                                        # cluster-wide load
scontrol show job <jobid>                     # full detail incl. pending reason
sacct -j <jobid> -o JobID,Partition,AllocTRES%50,Elapsed,State,ExitCode
seff <jobid>                                  # efficiency after completion
sbalance                                      # GPU-hours used vs 200k allocation
```

Waiting on a job non-interactively — poll, never a bare `sleep`:

```bash
until sacct -j <jobid> -X -h -o State | grep -qE "COMPLETED|FAILED|CANCELLED|TIMEOUT"; do
  sleep 15
done
```

## Debugging a failure

| Symptom | Cause |
|---|---|
| Rejected: `GPU partition but this job requests no GPU` | Add `--gres=gpu:N`. |
| Rejected: invalid account / association | Use `--account=ssci-anima`; verify with `sassoc`. |
| Rejected: time limit | Over 3 days. Reduce and checkpoint instead. |
| `COMPLETED` but no output file | Output path was on `/tmp`. Rewrite to `/home` or `/scratch`. |
| Pending `(Resources)` / `(Priority)` | Genuinely queued — fairshare weight 20000 dominates. Shrink the job or the walltime. |
| Pending `(ReqNodeNotAvail, May be reserved…)` | A reservation holds the node. `scontrol show reservation`. |
| Pending `(AssocGrpBillingMinutes)` etc. | Should not happen — we have no caps. Re-check `sassoc`. |
| Write errors mid-run | Scratch full. `python3 /apps/helpers/quotas.py`. |
| CUDA arch / kernel image errors on B200 | Toolkit older than 12.8. `module load cuda/12.8.1`. |
| `nvcc: command not found` inside a job although `module load` ran | Script lacks `#!/bin/bash -l`; `module` was a no-op. |
| `zip.h` / `libzip` missing while building | You are on the login node; it exists only on compute nodes — build inside a job. |
| `No module named pip` after `module load python/3.11.9` | Expected. `python3 -m venv V && V/bin/python -m ensurepip --upgrade`. |
| DataLoader shared-memory crash | Raise `--mem`; `/dev/shm` is ~1 TB, the cgroup limit is what binds. |

## Before reporting a job as working

Confirm all three:

1. `sacct -j <jobid>` shows `COMPLETED` with `ExitCode 0:0`.
2. The output file exists on shared storage and contains what you expect.
3. `seff <jobid>` shows the GPUs and memory were actually used, not idle.
