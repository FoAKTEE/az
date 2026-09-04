# Thread budget re-derived without a CPU cap — node `arxiv-1902.10565::cfg_9x9_override`

Why this file exists: `decomposition/DESIGN.md` §1 and obligation `o03_thread_budget_24cpu`
both derived the mission thread counts from a policy ceiling — "no more than 20 % of all
CPUs", read as 24 of the 124 schedulable CPUs on a node. That ceiling no longer exists.

- [SOLID] The human withdrew the clause on 2026-09-03. `mission.json` records it three ways:
  `compute.cpuCapPerJob = null`, `compute.cpuPolicy = "no CPU usage limit (human decision
  2026-09-03); jobs still declare --cpus-per-task honestly"`, and `decisions[0]` whose
  `affects` list names `compute.cpuCapPerJob`, `obligation o22`, `assumption a11` and
  "thread budgets in DESIGN.md" — i.e. exactly this derivation.
  verify: `python3 -c "import json;m=json.load(open('mission.json'));print(m['compute']['cpuCapPerJob'], m['decisions'][0]['decision'])"` → `None no CPU usage limit; the 20% clause in PROMPT.md is withdrawn`
- [SOLID] The compute-policy script agrees: it prints `no cpu cap` and exits 0 for the
  request this node made.
  verify: `evidence/cfg_9x9/compute_budget_check.txt`, line `OK : request gpus=1 cpus=24 part=b200 within policy (gpu<=4, no cpu cap)`, exit 0.

## 1. What replaces the cap

The surviving rule is local and weaker: **a job must declare `--cpus-per-task` honestly and
must not run more OS threads than it declared.** That inverts the derivation.

| | old (capped) | new (declared) |
|---|---|---|
| given | 24 CPUs, immovable | the thread counts the stage needs |
| derived | `numGameThreads` ≤ 18 so the sum fits 24 | `--cpus-per-task` ≥ the summed live threads |
| failure mode | policy breach | a false declaration to the scheduler / oversubscribed cores |
| admitted from | arithmetic | `ps -o nlwp=` on the live process vs `SLURM_CPUS_PER_TASK` |

The number the measurement is compared against is therefore no longer a constant in a
document; `codes/eval/check_cfg_9x9.sh` reads it from the allocation itself
(`CPU_BUDGET` ← `SLURM_CPUS_PER_TASK` ← `SLURM_CPUS_ON_NODE` ← 24 only as a last-resort
fallback when no Slurm allocation is visible), and prints which source it used.

## 2. This node's declaration

The `cfg_9x9_override` validation job asked for:

```
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=24
#SBATCH --mem=64G
#SBATCH --partition=b200
#SBATCH --time=01:00:00
```

24 is derived, not inherited:

| source of a thread | count | anchor |
|---|---|---|
| game loop threads | `numGameThreads` = 18 | `cpp/command/selfplay.cpp:359-362` spawns one per `numGameThreads`; `codes/cfg/selfplay_9x9.cfg:96` (`:84` upstream) |
| search threads inside each game thread | 0 extra | `numSearchThreads = 1`; search spawns `numThreads - 1` helpers (`cpp/search/searchmultithreadhelpers.cpp:39-41,49-53` (`numThreads - 1` = 0)) |
| NN server threads | 1 | `numNNServerThreadsPerModel = 1`, one model loaded |
| data-write thread | 1 | `cpp/program/selfplaymanager.cpp:156` (detached `dataWriteLoop`) |
| model-load loop thread | 1 | `cpp/command/selfplay.cpp:364` (`modelLoadLoopThread`) |
| main thread | 1 | — |
| **sum** | **22** | |
| transient extra during a net switch | +2 | a second model's server + write thread live briefly while the old one drains |
| **declaration** | **24** | 22 + 2 |

The gatekeeper reaches the same 22 by a different route — 18 game + 2 NN-server threads
(two models under test) + 1 data-write (`cpp/command/gatekeeper.cpp:548-549`) + 1 main — which
is why `numGameThreads` is 18 there too and not the 20 of decomposition pass 1: 20 would put
it at exactly 24 with no margin for the transient.

## 3. Measurement

`ps -o nlwp=` sampled every 50 ms on the live `katago selfplay` pid, inside the allocation,
with `-max-games-total 36` (2 games per game thread) so that all 18 game threads are
simultaneously busy. The spec'd 1-game parse run cannot support this measurement: 17 of the
18 threads take a `gameIdx >= maxGamesTotal` and break immediately
(`cpp/command/selfplay.cpp:291-293,312-322`), so the peak would be a startup race. Both runs
are executed; the 1-game run proves the config parses and plays, the 36-game run measures
threads, and check 4 counts `SZ[9]` over the SGFs of both.

| quantity | value | source |
|---|---|---|
| `SLURM_CPUS_PER_TASK` | 24 | job 298359 |
| `CPU_BUDGET` source | `SLURM_CPUS_PER_TASK` | `check_cfg_9x9.sh` |
| `NLWP_SAMPLES` | 52 | `check_cfg_9x9.sh` check 5 |
| `NLWP_MAX` | **22** | `check_cfg_9x9.sh` check 5 |
| headroom | 2 | `CPU_BUDGET - NLWP_MAX` |

Verbatim output: `evidence/cfg_9x9/check_cfg_9x9-298359.txt`.

## 4. Consequences for the ledger wording

- `o03_thread_budget_24cpu` — the numbers it names (selfplay ≤ 18, gatekeeper ≤ 18,
  `numSearchThreads = 1`, `numNNServerThreadsPerModel = 1` per GPU, shuffle ≤ 8, train
  `OMP_NUM_THREADS = MKL_NUM_THREADS ≤ 4`) are all still what the mission configs set, so the
  obligation's *content* is discharged unchanged by the measurement. Only its *justification*
  moves, from "fits the 24-CPU cap" to "matches the 24 CPUs the job declares". The id keeps
  the now-misleading `_24cpu` suffix; renaming it would break the ledger's references.
  [OPEN] the claim-ledger amendment restating `o03`'s text is the validator's to append, not
  this worker's.
- `c06_threads_le_24` — the threshold 24 is now the job's declaration rather than a policy
  constant. The claim is admitted for **selfplay only** by this node; its gatekeeper and
  `train.py` clauses stay open until `gatekeeper_stage` and `train_stage` measure their own
  processes. [OPEN]
- `a11_cpu_policy_summed` (the 20 % policy applies to the sum over concurrent jobs) and
  `o22_cpu_policy_scope` (per-job or summed? — owner: human) are **moot**: there is no
  percentage left to apportion, so a second concurrent job no longer waits on an answer.
  `check.sh` still sums `squeue -u $USER`, but only its GPU half (≤ 4) gates anything now.
  [OPEN] both ledger transitions belong to the validator.
- [OPEN] `numGameThreads` is now a throughput knob, not a budget knob. 18 is a floor
  justified by DESIGN §1's queue-depth argument (a B200 fed ≤ 18 concurrent 9x9 evaluations
  at batch 1 is idle most of the time), not a ceiling. Raising it — with `--cpus-per-task`
  raised in the same edit, one node has 124 — is the cheapest available lift in GPU duty
  cycle, but it must be measured, not guessed. Closes when `measure_stage_throughput`
  reports duty cycle and games/hour at 18 game threads and at one larger setting.
  verify: node `measure_stage_throughput`; claim `c09`.

- [SOLID] The measurement lands exactly on the arithmetic: 22 live threads, which is
  18 game + 1 nnServer + 1 dataWrite + 1 modelLoad + 1 main with nothing unaccounted for.
  52 samples over a 6 s run, all 18 game threads busy. Headroom to the declaration is 2,
  which is the mid-run net-switch allowance and was never consumed here (one model, no switch).
  verify: `evidence/cfg_9x9/check_cfg_9x9-298359.txt`, lines `NLWP_SAMPLES = 52`, `NLWP_MAX     = 22`, `CPU_BUDGET   = 24`, `ok   NLWP_MAX 22 <= CPU_BUDGET 24`.
- [OPEN] `seff 298359` reports CPU efficiency 11.57 % (25 s CPU over 3:36 core-walltime).
  That is an artifact of the measurement, not a finding: the job ran 9 s wall of which ~8 s
  was two short selfplay processes, and the 24 cores were idle for the module loads and the
  static checks. It says nothing about the production loop's efficiency, which
  `measure_stage_throughput` measures on a real cycle.
  verify: `evidence/cfg_9x9/check_cfg_9x9-298359.txt`, appended `seff 298359` block.
