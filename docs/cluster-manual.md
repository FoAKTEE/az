# Schmidt Sciences GPU Cluster — Configuration Manual

Cluster `skipjack` — NVIDIA Blackwell (B200/B300) allocation hosted at Johns Hopkins ARCH.

Everything below was verified live on `login03` on 2026-09-03. Where the ARCH portal
documentation or the Schmidt announcement emails disagree with the running system, this
manual follows the running system and says so explicitly.

---

## 1. Identity

| | |
|---|---|
| Cluster name | `skipjack` |
| Your username | `ssci-haiyangw` |
| Slurm account | `ssci-anima` (PI: Anima) |
| Account tree | `root` → `Schmidt` → `pi-ssci-anima` → `ssci-anima` |
| QOS available | `all`, `scavenger`, `ssci` |
| Default QOS | `scavenger` |
| Unix groups | `users`, `ssci-anima` (gid 30023) |
| OS | Rocky Linux 9.6, Slurm 25.11.2 |

Check any of this yourself:

```bash
sassoc          # your account / QOS / fairshare
stree           # your account hierarchy and share value
sbalance        # core-hour and GPU-hour usage vs allocation
```

## 2. Access

```bash
ssh -l ssci-haiyangw login03.schmidtsciences.jhu.edu   # 162.129.223.41
ssh -l ssci-haiyangw login04.schmidtsciences.jhu.edu   # 162.129.223.42
ssh -l ssci-haiyangw login05.schmidtsciences.jhu.edu   # 162.129.223.38
```

Login is **password + TOTP**, prompted on two separate lines. Enroll your authenticator in
the Schmidt Sciences Portal (ColdFront/ARCH) before first use; you cannot connect until ToS
is accepted and MFA is enrolled.

There is no load balancer — pick a login node by hand. `login01`/`login02` are retired.

### Login nodes are small and capped

14 cores, and **your session is limited to 5 GB RAM by cgroup** (`memory.max` on the user
slice). This is the safeguard added after the July 2026 login-node outage. A large build,
a `pip install` of a heavy wheel, or a data-munging one-liner will be OOM-killed rather
than slowing the node down.

Do compilation, dataset preprocessing, and anything memory-hungry inside a job:

```bash
interact -p b200 -g 1 -n 8 -m 64G -t 2:00:00
```

## 3. Hardware and partitions

| Partition | Nodes | GPUs/node | GPU memory | CPUs usable | RAM | Access for us |
|---|---|---|---|---|---|---|
| `b200` | 16 (`gb201`–`gb216`) | 8 × B200 | ~180 GB (183359 MiB) | 124 | 1547 GB | **Yes** |
| `b300` | 1 (`gb301`) | 8 × B300 | ~180 GB | 124 | 1547 GB | **Yes** |
| `l40s` | 6 (`gl105-107,110-112`) | 8 × L40S | 48 GB | 124 | 773 GB | **Yes** (`AllowAccounts=ALL`) |
| `h100` | 32 (`gh101`–`gh132`) | 4 × H100 | 80 GB* | 124 | 1547 GB | No — `AllowAccounts=jhu` |
| `h200` | 6 (`gh201`–`gh206`) | 4 × H200 | 141 GB* | 124 | 1547 GB | No — `AllowAccounts=jhu` |
| `a100` | 15 (`ga129`–`ga143`) | 8 × A100 | 80 GB* | 88 | 1031 GB | No — `AllowAccounts=jhu` |
| `med` | 80 (`csr048`–`csr127`) | — (CPU) | — | 108 | 515 GB | No — `AllowAccounts=jhu` |

Notes that matter:

- **`b200` and `b300` are set to `AllowAccounts=schmidt`.** Our account sits under the
  `Schmidt` root, so we inherit access. The JHU partitions are genuinely closed to us —
  submitting there fails at the association check, it does not silently queue forever.
- **`l40s` is open to everyone** (`AllowAccounts=ALL`). The announcement emails told
  Schmidt users to "always specify b200 or b300"; that is no longer the whole story. L40S
  is a real fallback for small jobs, debugging, and inference when `b200` is congested.
- There is **no `scavenger` partition** on this cluster. `scavenger` exists only as a QOS.
  Portal docs that reference a scavenger partition are describing a different ARCH cluster.
- Node names are `gb2xx` (GPU) — the old `b2xx` names are gone.
- B200 driver version 595.71.05. Each node exposes 16 InfiniBand verbs devices
  (`uverbs0`–`uverbs15`) — full RDMA fabric for multi-node NCCL.
- Slurm reserves 4 cores per GPU node for the system (`CoreSpecCount=4`), so 124 of 128
  CPUs are schedulable.
- B200 memory and driver were read off a live job. Values marked `*` are nominal vendor
  specs for partitions we cannot submit to and were not measured here.

### Max walltime is 3 days

`MaxTime=3-00:00:00` on every partition, reduced from 7 days because of kernel-patch
reboots. Design training runs around **checkpoint + resume**, not a single long job. Longer
runtimes are negotiable case-by-case with `compute@schmidtsciences.org`.

## 4. Storage

| Path | Backing | Quota | Notes |
|---|---|---|---|
| `/home/schmidt/ssci-haiyangw` | WekaFS (`/weka/home`) | **100 GB** | Shared, backed up. Code and configs only. |
| `/scratch/schmidt/ssci-anima` | WekaFS (`/weka/scratch`) | **40 TB** (shared by the whole group) | Shared across nodes. Datasets, checkpoints. |
| `/dev/shm` | RAM | ~1 TB on GPU nodes | Use for PyTorch DataLoader shared memory. |
| `/tmp`, `/` | Node-local NVMe | ~394 GB free | **Node-local. Not visible from the login node or other nodes.** |

Check quota at any time:

```bash
python3 /apps/helpers/quotas.py
```

### Two storage traps

1. **Scratch is nearly full.** As of 2026-09-03 the group is at **37.89 TB of 40 TB (94 %)**.
   Writes will start failing for everyone in the group, not just you. Check before starting
   a run that produces checkpoints, and clean up old artifacts.

2. **Never point `--output`, `--error`, or `--chdir` at `/tmp`.** It is node-local, so the
   file is written on the compute node and is unreachable afterwards — the job reports
   `COMPLETED` and the log simply does not exist. Submit from, and write to, `/home` or
   `/scratch`. (This is a real failure we reproduced: job 295657 completed with no output
   file anywhere.)

`/home` and `/scratch` are symlinks into `/weka`, so both spellings work.

## 5. Billing — we are not billed

The ColdFront portal is full of cost estimates, weekly spend caps, `ACCEPT_COST=1`, and
`[y/N]` confirmation prompts. **None of it applies to this account.** From the live
scheduler config `/etc/slurm/qos_config.lua`:

```lua
free_qos              = { all = true, scavenger = true, ssci = true },
free_account_prefixes = { "ssci-", "ext-" },
show_billing_on_free_part = false,
```

Our account is `ssci-anima`, matching the `ssci-` prefix, and every QOS we hold is a free
QOS. `show_billing_on_free_part = false` puts us on the silent path: no cost estimate, no
prompt, no confirmation.

Practical consequence: **you do not need `--export=ALL,ACCEPT_COST=1`.** Plain `sbatch`
works. Verified by submitting job 296281 with no such flag — it was accepted immediately.

The only billing output you will see is two harmless lines on stderr:

```
[BILLING] loaded!
[BILLING] Re-emitting cost at job start!
```

Usage is still *metered* against the grant even though it is not invoiced. `sbalance` shows
the group at roughly 69,266 of 200,000 GPU-hours for the current quarter.

## 6. Scheduling and priority

```
PriorityType            = priority/multifactor
PriorityWeightFairShare = 20000     ← dominant
PriorityWeightAge       = 5000
PriorityWeightJobSize   = 5000
PriorityWeightQOS       = 0         ← QOS does not affect priority
SchedulerType           = sched/backfill
PreemptType             = preempt/partition_prio
```

Two things follow, and both contradict the portal's description:

- **QOS choice does not change your priority.** `PriorityWeightQOS = 0`, and all QOS
  entries have `Priority=0` with no limits, no `MaxWall`, and no `UsageFactor` difference.
  Picking `--qos=ssci` over the default `scavenger` buys you nothing here.
- **Nothing is actually preemptible.** Preemption is `partition_prio`, and every partition
  is `PriorityTier=1`, so no partition can preempt another. The "scavenger jobs may be
  killed" warning in the portal docs does not apply on this cluster. Jobs we ran under the
  default `scavenger` QOS were not at risk.

Fairshare dominating means the more the group has recently used, the lower your queue
priority. Backfill scheduling means **short, small, well-specified jobs start much sooner** —
an accurate `--time` is the single most effective thing you can do to reduce queue wait.

The queue is genuinely busy: ~316 running and ~1282 pending jobs cluster-wide at the time
of writing. Check with `sbrief`.

**Queue waits scale sharply with GPU count.** Measured on 2026-09-03: a 1-GPU job started
immediately, while a 2-GPU 5-minute job sat `PENDING (Priority)` and `sbatch --test-only`
projected a start over two months out. `--test-only` is a worst-case estimate and not a
promise, but the direction is real — ask for the fewest GPUs the work actually needs, and
expect whole-node and multi-node requests to wait.

## 7. Job submission rules enforced by the cluster

A `job_submit.lua` plugin rejects some jobs at submission. The one that will bite you:

```
error: Alert: partition 'b200' is a GPU partition but this job requests no GPU.
       Add --gres=gpu:N (or --gpus=N) to use the GPU, or resubmit CPU-only work
       to a CPU partition (med, premium, scavenger).
```

**Every `b200`/`b300` job must request at least one GPU.** The suggested CPU partitions in
that message are JHU-only, so we have no CPU-only option — run small CPU work inside a
1-GPU job, or on the login node within the 5 GB cap.

Other enforced settings: `AccountingStorageEnforce = associations,limits,qos` (no
association, no submission), `EnforcePartLimits = ANY`, `MaxArraySize = 10000`,
`MaxJobCount = 100000`, `MpiDefault = pmix_v3`, `SelectType = cons_tres/CR_CORE_MEMORY`.

Because selection is `CR_CORE_MEMORY` and `DefMemPerNode = UNLIMITED`, **always pass
`--mem`**. Omitting it can hand your job the whole node's memory and block co-scheduling.

## 8. Software environment

Lmod, ~355 modules, built on `gcc/12.3.0`.

```bash
module avail                  # what is loadable now
module spider cuda            # search everything
module load cuda/12.8.1
```

Available versions worth knowing:

- `cuda/11.1.0`, `11.2.0`, `11.5.0`, `11.8.0`, `12.3.0`, `12.6.3`, `12.8.1`, `13.0.2`
- `python/3.11.9`, `python-venv/1.0`
- `gcc/8.5.0`, `9.3.0`, `12.3.0`, `GCC/13.2.0`
- `openmpi/5.0.10`, `cmake/3.30.2`, `llvm/17.0.6`

For B200 (compute capability 10.0) use **CUDA 12.8 or newer**; older toolkits do not emit
Blackwell SASS and will fall back to JIT or fail outright.

### Batch scripts must be login shells

`module` is a shell function exported by `/etc/profile.d/zz-dsai_lmod.sh`. It resolves in
interactive shells but **not** in a plain `#!/bin/bash` sbatch script on a compute node —
`module load cuda/12.8.1` silently does nothing and `nvcc` is "command not found"
(reproduced in job 297912). Start every job script with `#!/bin/bash -l`, or
`source /etc/profile.d/zz-dsai_lmod.sh` before the first `module` call.

### Login node vs compute node differences (verified 2026-09-03)

| | login03 | gb205 (compute) |
|---|---|---|
| Internet (github, pypi, pytorch wheels) | yes | **yes** |
| `libzip.so` + `/usr/include/zip.h` | no | **yes** |
| cuDNN / TensorRT headers or libs | no | no |
| conda / mamba / micromamba | no | no |
| `python/3.11.9` module has `pip` | no — use `python3 -m venv` then `venv/bin/python -m ensurepip` | same |
| RAM available to you | 5 GB cgroup | whatever `--mem` asked |

Build C++ that needs `libzip` on a compute node. cuDNN for CUDA 12 is available as the pip
wheel `nvidia-cudnn-cu12` (9.x); TensorRT as `tensorrt-cu12`. The cuDNN wheel ships only the
versioned soname — add `ln -s libcudnn.so.9 libcudnn.so` in `site-packages/nvidia/cudnn/lib`
before pointing CMake at it, and put that `lib/` on `LD_LIBRARY_PATH` at runtime. Check any
CMake project's hard-coded `CMAKE_CUDA_ARCHITECTURES` list includes `100` for B200/B300 —
verify with `cuobjdump --list-elf <binary> | grep -c sm_100` (0 means PTX-JIT only). PyTorch for this CUDA:
`torch==2.11.0+cu128` from `https://download.pytorch.org/whl/cu128` (cp311 wheel confirmed).

No `apptainer`/`singularity`/`docker`/`podman` on the login node `PATH`. There is a
bind-helper at `/apps/helpers/apptainer.sh` that wires InfiniBand libraries into a
container, which implies apptainer is available inside jobs or via a module — check with
`module spider apptainer` from a compute node before planning a container workflow.

Other helpers in `/apps/helpers/`: `jupyterlab.sh`, `r-studio-server.sh`, `jobstats`,
`quotas.py`.

## 9. Reservations

Nodes are frequently reserved for individual Schmidt groups, which is a common reason for
`(ReqNodeNotAvail, May be reserved for other job)` in `squeue`.

```bash
scontrol show reservation
```

Active examples at time of writing: `ssci-adamgleave-aug2026` (gb211-212, 215-216),
`ssci-aganeshram-sep2026` (gb201, gb210), `ssci-yejinc-b200-sep2026` (gb208),
`ssci-ssci-yejinc-sep2026` (gb301). With 4–8 of 16 B200 nodes reserved at once, effective
free capacity is well below what `sinfo` node counts suggest.

## 10. Command reference

ARCH helper tools, in `/apps/helpers` (already on `PATH`). All accept `-M <cluster>`.

| Command | Purpose |
|---|---|
| `sbalance` | Core-hour / GPU-hour usage vs allocation |
| `sbalance --week` | Weekly spend cap status (not applicable to us) |
| `stree`, `stree --full` | Account hierarchy, with user associations |
| `sassoc`, `sassoc --tree account=X` | Associations: account, QOS, fairshare |
| `sqos all`, `sqos <user>` | QOS definitions and assignments |
| `sfeatures`, `sfeatures -p b200` | Nodes with CPUs, memory, GRES, state |
| `sbrief`, `sbrief -u $USER` | Job counts by state |
| `sqme` | Your active jobs (formatted `squeue`) |
| `seff <jobid>` | CPU/memory efficiency of a finished job |
| `interact -l` | List partitions with your accounts and QOS |
| `jobstats` | Per-job resource statistics |

Standard Slurm:

```bash
sinfo -o "%20P %5a %10l %15F %10m %25G %N"     # partition overview
squeue -u $USER
squeue -p b200 -o "%.8i %.12a %.10u %.8T %.10M %.6D %R"
scontrol show partition b200
scontrol show node gb202
sacct -j <jobid> -o JobID,Partition,QOS,AllocTRES%50,Elapsed,State,ExitCode
sacct -A ssci-anima --starttime=now-7days -X
```

Old names `slurmtree`, `slurmqos`, `slurmassoc` still work as symlinks.

## 11. Web portal

The Schmidt Sciences Portal runs ColdFront (`Version 1.1.7 - CLOACK V.0.3`) and provides
MFA enrollment, ToS acceptance, help-desk tickets, job metrics, and a web job-submission
form. Account creation, quota increases, and PI upgrades are **not** self-serve for Schmidt
users yet — email `compute@schmidtsciences.org` or use the Slack help channel.

A REST job-submission API exists (`POST /api/v1/jobs/estimate/`, `POST /api/v1/jobs/submit/`)
using a personal token from the User Profile page. For free allocations like ours the
`accept_cost` confirmation is skipped.

## 12. Gotcha checklist

- [ ] `--gres=gpu:N` on every `b200`/`b300` job — submission is rejected without it.
- [ ] `--mem` always set; `DefMemPerNode` is unlimited.
- [ ] `--time` ≤ `3-00:00:00`, and honest — backfill rewards short accurate estimates.
- [ ] `--account=ssci-anima` if your default ever changes.
- [ ] Output paths on `/home` or `/scratch`, never `/tmp`.
- [ ] Check `python3 /apps/helpers/quotas.py` — scratch is at 94 %.
- [ ] Nothing heavy on the login node; 5 GB cgroup cap will kill it.
- [ ] `ACCEPT_COST=1` is not needed; ignore portal billing docs.
- [ ] Checkpoint and resume — 3-day ceiling, and nodes get drained for kernel patches.
- [ ] `scontrol show reservation` before blaming the scheduler for a long queue wait.
