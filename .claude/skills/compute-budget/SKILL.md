---
name: compute-budget
description: Recurring self-check of the project's compute-usage policy before launching, scaling, or re-queuing ANY GPU/CPU job on the Schmidt cluster (sbatch, srun, interact, self-play loops, training). Enforces: <=20% of node CPUs, <=4 GPUs total, b200/b300 partitions only, take fewer GPUs when the cluster is scarce. Run it every time a job is about to be submitted and whenever a running workload is about to be scaled up.
---

# Compute budget — policy self-check

Source of the policy: `progress/prompt/ktg-train.md` § Computation Usage.

| Resource | Policy text | Concrete cap on skipjack |
|---|---|---|
| CPU | "no more than 20% of all CPUs" | **≤ 24 CPUs** per job (124 schedulable × 0.20) · on the login node keep parallelism ≤ 2 (14 cores, 5 GB RAM cgroup) |
| GPU | "at most only use the last 4 GPUs (B200 or B300)" | **≤ 4 GPUs total across all my running+pending jobs**, `--partition=b200` or `b300` only. Slurm assigns GPU indices; "last 4" is realised as a count cap, not indices. |
| GPU scarcity | "if GPUs are occupied, use maximal available GPUs" | Read the free-GPU count from the check; request `min(4, free, what the job actually needs)`. Never queue a 4-GPU request when only 1–2 are free and the job can run smaller. |
| Target | "1-2 B300" | Prefer `b300` (1 node, `gb301`) with 1–2 GPUs. It is often fully reserved — fall back to `b200` at the same GPU count. |

## The check (run before every submission)

```bash
bash .claude/skills/compute-budget/check.sh --gpus N --cpus M --partition b200|b300
```

Exit 0 → within policy. Exit 1 → the printed `VIOLATION` line says what to change.
Run with no arguments to just see current footprint, free GPUs, reservations, and quota.

Paste the check's output into the job's commit body as a `- verify:` object (the
commit template requires real verification evidence, and this is it).

## Sizing table (policy-compliant presets)

| Intent | Flags |
|---|---|
| Debug / build / data prep | `--gres=gpu:1 --cpus-per-task=8 --mem=64G` |
| Single-GPU training | `--gres=gpu:1 --cpus-per-task=12 --mem=120G` |
| 2-GPU training (the "1-2 B300" target) | `--gres=gpu:2 --cpus-per-task=24 --mem=240G` |
| Max allowed | `--gres=gpu:4 --cpus-per-task=24 --mem=480G` (CPU stays at 24 — the 20% cap binds before the GPU cap) |

Self-play (KataGo `selfplay`) is CPU-hungry for MCTS; with the 24-CPU cap, keep
`numSearchThreads`/`numGameThreads` sized so total threads ≤ 24, and let the GPU batch.

## Recurring cadence

- Before **every** `sbatch` / `srun` / `interact`.
- Before changing `--gres`, `--cpus-per-task`, or the number of concurrent jobs.
- When a job has been `PENDING (Resources)` > 30 min: re-run, and shrink to the free count.
- After any job finishes, before launching the next stage of a pipeline.

Related: `cluster-job` skill (how to submit), `docs/cluster-manual.md` (why the numbers are what they are).
