# DESIGN.md — mission `ktg-train`: 9x9 transformer KataGo self-play loop on skipjack

Scope: what the loop is, how it fits ≤4 GPUs / the CPUs each job declares / 3-day walltime / 94 %-full scratch, and in
what order it is proven. Source of truth is the v1.18.2 code mirror (human redirect 2026-09-03); the
2019 paper is background. Every claim carries `[SOLID|PRELIMINARY|HOLE|FUTURE]` and a `verify:` line.
`[SOLID]` here means read in code with path:line or measured in a recorded run; the only GPU execution so
far is `env_build` (jobs 297952 FAILED, 298018 PASSED; result row `env-toolchain-b200`).
Evidence files: `../evidence/decomposition/audit_loop_scripts_configs.md`, `audit_paper_code_map.md`,
`dag_review_a.md` / `dag_review_b.md` (seat A / seat B) and their adjudication `dag_reconciliation.md`.
DAG: `logic.md` (38 nodes, reconciled 2026-09-04). Ledger views: `claims.md`, `obligations.md`, `assumptions.md`.

## 0. What is being built

The unmodified v1.18.2 five-stage loop — `katago gatekeeper` → `katago selfplay` → `shuffle.py` →
`train.py` → `export_model_pytorch.py` — driven by a mission copy of `python/selfplay/synchronous_loop.sh`,
on one node, with mission-owned configs that make it 9x9-only, and a Slurm wrapper that survives the 3-day
ceiling. Model: **`b7c96h3tfrs`** (7 × attnrope+ffnsg, 96 ch, 3 heads, 825 837 params) for smoke and first
production; `b8c96h3tfrs` → `b14c192h6tfrs` for scale-up, each a fresh run. `b5c48h3tfr` (ffng) is
**excluded**: every C++ backend throws "Non-SwiGLU transformer FFN is not yet supported"
(`cudaandrocmbackend.inc:3307-3308`, `eigenbackend.cpp:1634`, `openclbackend.cpp:2729`); job 297952 failed
exactly there (exit 134), job 298018 passed with `b7c96h3tfrs`. No engine patches; the one edit outside this
repo is `codes/env/cmake-sm100.diff` adding `100` to the CUDA-12.8 arch list in the *scratch* build clone.
- [SOLID] Every stage's entry point, argument list and file contract is known.
  verify: `audit_loop_scripts_configs.md` §A–C (`synchronous_loop.sh:93-116`, `train.sh:83-93`, `export_model_pytorch.py:34-42`).
- [SOLID] `b7c96h3tfrs` exports to the C++ engine and plays 9x9 on a B200 (benchmark 2322 visits/s + gtp genmove + torch fwd/bwd).
  verify: `../evidence/env/smoke.txt` ("SMOKE RESULT: PASS", `grep -c sm_100 = 2`); result row `env-toolchain-b200`; knowledge node `env_build` = solid.
- [SOLID] `b5c48h3tfr` is trainable but unplayable (non-SwiGLU FFN refused by all backends) — never a `MODELKIND`; it survives only as the negative export fixture (`o23`).
  verify: knowledge node `engine_ffn_swiglu_constraint` (solid; `../evidence/env/smoke-297952-fail.txt:26-27`); `export_model_pytorch.py:461` writes `use_swiglu`.
- [SOLID] Ladder steps are fresh runs: `train.py:850` takes the model config from `checkpoint.ckpt`, so a b7 checkpoint is never resumed into b8.
  verify: `sed -n 850p ref-code/lightvector-KataGo/python/train.py`; node `select_transformer_ladder`.

## 1. GPU / CPU split — why the declared CPU request, not the GPU, bounds the thread budget

Paper regime (background): 16→24 V100 self-play : 2 gating : 1 training (l.603), i.e. 16–24× more GPU
on self-play than training; upstream docs say 4–40×. On a *synchronous* single-node loop this ratio is
not a GPU-allocation decision at all: the GPU is time-shared and the ratio is enforced by data
accounting — `train.py -max-train-bucket-per-new-data 8` lets each new row be trained on at most 8 times
(`train.py:121,1256`; loop default `synchronous_loop.sh:60`), and `-max-train-bucket-size` caps a cycle's
training (`:64`). Training can never outrun self-play; it can only idle.
- [SOLID] The selfplay:train balance is set by `MAX_TRAIN_PER_DATA`/`MAX_TRAIN_SAMPLES_PER_CYCLE`/`NUM_GAMES_PER_CYCLE`, not by GPU count.
  verify: `synchronous_loop.sh:57-66,109`; `train.py:1433-1445` (`-stop-when-train-bucket-limited` exits when the bucket drains).
- [PRELIMINARY] With `b7c96h3tfrs` a B200 is starved by NN inference of this size: 2322 nnEvals/s at batch 1
  (`smoke.txt:103`), and with ≤18 game threads × 1 search thread the NN queue depth is ≤18, so a second GPU cannot be
  fed; DDP for an 825 k-param net at 81 tokens adds sync cost with no throughput need. Pass 2's 2-GPU default and
  `-multi-gpus 0,1` are dropped; its 4-GPU 3:1 layout is `async_multi_gpu_layout` `[FUTURE]`.
  verify: node `measure_stage_throughput` must show GPU duty cycle (`nvidia-smi dmon -s u`) and `nnBatches`/`nnEvals` before any GPU is added; claim `c09`.
- [SOLID] Cluster state at design time: b200 `free_gpus=2/128`, b300 `0/8` (gb301 reserved until 2026-09-04 15:00);
  a 1-GPU job started immediately, a 2-GPU request projected a multi-week wait on 2026-09-03.
  verify: `docs/cluster-manual.md` §6 ("Queue waits scale sharply with GPU count"); `scontrol show reservation`; compute-budget `check.sh` output 2026-09-03T21:49:50-04:00.

Design: **one job, one GPU, `--cpus-per-task=32`, all five stages sequential**, partition b300 preferred
→ b200 fallback (b200 while gb301 is reserved). GPU is shared trivially (one process at a time).
`--mem=120G` (shuffle buckets + train prefetch). The declaration was 24 through the smoke; it is 32 from
`derive_cycle_knobs_9x9` on, because a real net costs three CUDA threads the 24 never budgeted (below).

The number is no longer a cap handed down by policy. The "no more than 20 % of all CPUs" clause was
**withdrawn by the human on 2026-09-03** (`mission.json` `decisions[]` entry 1, `compute.cpuCapPerJob = null`,
`compute.cpuPolicy`); what survives is the weaker and purely local rule that a job must *declare*
`--cpus-per-task` honestly and must not spawn more OS threads than it declared. So the derivation runs the
other way now: pick the thread counts the stage needs, sum every live thread, and request at least that many
CPUs. On a random net the stages sum to 22 (table below), and 24 — 22 plus the two transient threads of a
mid-run net switch — is what `loop.sbatch` and the `cfg_9x9_override` validation job (Slurm 298359,
`--cpus-per-task=24`) asked for. Job 298712 then measured 25 on every stage holding a CUDA context, and
`derive_cycle_knobs_9x9` re-ran the sum with that block included: worst stage 29, declaration 32. Nothing
forbids a larger request on a 124-core node; a larger one still has to be *earned* by a measurement, which is
what the 25 is.
- [SOLID] There is no CPU cap; the constraint is "declared ≥ used", and `check.sh` passes any CPU count.
  verify: `mission.json` `compute.cpuCapPerJob` = `null` and `decisions[0].decision` = "no CPU usage limit; the 20% clause in PROMPT.md is withdrawn"; the check script named by `mission.json` `compute.policyCheck`, invoked with `--gpus 1 --cpus 24 --partition b200` → `OK : request gpus=1 cpus=24 part=b200 within policy (gpu<=4, no cpu cap)`, exit 0.

Split of the 24 declared CPUs per stage (only one stage runs at a time, so each stage may use the whole
request):

| stage | OS threads / processes | how | evidence |
|---|---|---|---|
| selfplay | 18 game + 1 nnServer + 1 dataWrite + 1 modelLoad + 1 main = 22 (+2 transient at net switch); **measured 22 random-net, 25 real-net** | `numGameThreads=18`, `numSearchThreads=1`, `numNNServerThreadsPerModel=1` | `selfplay.cpp:359-364`, `setup.cpp:193-203`, `selfplaymanager.cpp:156`; measured `../evidence/smoke/nlwp_max-298712.txt`, `audit-299259.json` |
| gatekeeper | 18 game + 2 nnServer (2 models) + 1 dataWrite + 1 main = 22; **measured 25** with one real net vs the random baseline | `numGameThreads=18` (pass 1's 20 gave 24 — the data-write thread was uncounted, leaving no margin under a 24-CPU request) | `gatekeeper.cpp:548-553`; measured `../evidence/smoke/nlwp_max-298712.txt`, `audit-299259.json` |
| shuffle | 8 worker processes; **measured 8 workers x 1 thread + a 4-thread parent = 12** | `-num-processes 8` | `synchronous_loop.sh:58`, `shuffle.py:791`; measured `../evidence/smoke/nlwp_max-298712.txt`, `audit-299259.json` |
| train | 1 process, `OMP_NUM_THREADS=MKL_NUM_THREADS=4`, prefetch depth 1; **measured 14 threads** | env vars + `-data-prefetch-depth` default | `train.py:126`; obligation `o11`; measured `../evidence/smoke/nlwp_max-298712.txt`, `audit-299259.json` |
| export | 1 process | — | — |
- [SOLID] Shipped defaults (`numGameThreads=128`) would spawn ~132 threads against a 24-CPU request — a
  declaration that is false by more than 5x, and 128 game threads × 1 search thread each on one node oversubscribes
  the cores regardless of any policy. The mission configs must override the key whatever the policy says.
  verify: `selfplay1_maxsize9.cfg:84`, `gatekeeper1_maxsize9.cfg:18`; arithmetic in `audit_loop_scripts_configs.md` §D; node `selfplay_search_params`.
- [SOLID] Selfplay's row is measured, not asserted, and lands exactly on the arithmetic: **22 live threads**
  against the 24 declared, 52 samples of `ps -o nlwp=` at 50 ms on the live `katago selfplay` pid inside job 298359
  (`--cpus-per-task=24`, `-max-games-total 36` so all 18 game threads are simultaneously busy — with 1 game total
  17 of them break at once, `selfplay.cpp:291-293`). Headroom 2 = the mid-run net-switch allowance, unconsumed here
  because one model was loaded and never switched.
  verify: `../evidence/cfg_9x9/check_cfg_9x9-298359.txt` lines `NLWP_SAMPLES = 52`, `NLWP_MAX     = 22`, `CPU_BUDGET   = 24`, `ok   NLWP_MAX 22 <= CPU_BUDGET 24`; claim `c06` (selfplay clause), obligation `o03`.
- [SOLID] The gatekeeper, shuffle and train rows are now measured, on the live processes of Slurm job 298712
  (`--cpus-per-task=24`, `ps -o nlwp=` at 0.2 s, per-pid attribution). Random-net **selfplay lands exactly on the
  arithmetic a third and fourth time: 22** (pids 324406, 330480). **shuffle** confirms the table's
  8 worker processes (pids 324712-324719 in cycle 1, 330794-330801 in cycle 2) at 1 thread each behind a 4-thread
  parent, i.e. 12 concurrent threads for the stage. **train 14** threads with `OMP_NUM_THREADS=MKL_NUM_THREADS=4`
  (pids 325065, 331077), comfortably inside 24. Note the metric's shape: `nlwp_max` is a per-PROCESS peak, so the
  "declared >= used" comparison for a multi-process stage is the SUM over its concurrent pids (shuffle: 4 + 8 = 12);
  for selfplay, the gatekeeper and train, one process is the whole stage and the two coincide.
  verify: `../evidence/smoke/nlwp_max-298712.txt` and `ps_samples-298712.tsv`; claim `c06`, obligation `o03`.
- [SOLID] **A CUDA context costs three threads the 24-CPU declaration never budgeted — resolved by the knobs at
  32 CPUs / 18 game threads.** Job 298712 measured `nlwp_max = 25` on both real-net stages — the leg-D1 selfplay
  probe running the exported `t9-s1216-d1221` (pid 332406) and the cycle-2 gatekeeper running that candidate against
  the random baseline (pid 328662) — against the 22 that every random-net selfplay in the same job measured. The +3
  is the CUDA runtime/driver threads that `debugSkipNeuralNet` never creates (`cpp/program/setup.cpp:126`), so the
  24 was false by one and c06's real-net clause is refuted. Of the two admissible repairs `derive_cycle_knobs_9x9`
  took the first — **raise the declaration, keep `numGameThreads = 18`** — because with the CPU cap withdrawn a
  larger declaration is free, while cutting game threads would lower the very NN queue depth this section already
  blames for the 21.5 % mean GPU duty cycle. The re-summed budget, worst stage first: gatekeeper with two real nets
  18 + 2 nnServer + 1 dataWrite + 1 main + 2x3 CUDA = 28; selfplay real-net 25 measured + 2 net-switch transient = 27;
  train 14; shuffle 4 + 8 = 12. Declaration **32**, headroom 4, on a 124-core node. (The 29 printed here before
  2026-09-04 mis-added the same gatekeeper terms; obligation `o40`. Nothing downstream moves — the declaration was
  already 32 and T4 asserts worst <= 32.)
  verify: `../evidence/smoke/nlwp_max-298712.txt` rows `probe_search/selfplay nlwp_max=25` and `cycle2/gatekeeper
  nlwp_max=25` against `cpus_per_task = 24`; `codes/loop/knobs_9x9.env` `KTG_CPUS_PER_TASK=32` /
  `KTG_NUM_GAME_THREADS=18`; `python3 codes/eval/check_knobs_9x9.py` line `T4_threads_le_cpus  worst stage 28 <=
  KTG_CPUS_PER_TASK 32`, exit 0; obligation `o03`, claim `c06` (real-net clause, refuted).
- [SOLID] The 32 is now *wired* (`o39`, 2026-09-04): `codes/loop/loop.sbatch` declares `#SBATCH --cpus-per-task=32`
  and no longer types a CPU count at all — `REQ_CPUS` is read from `codes/loop/knobs_9x9.env`'s `KTG_CPUS_PER_TASK`,
  and the pre-flight refuses (exit 2) a link whose granted `SLURM_CPUS_PER_TASK` disagrees with it or whose engine
  configs declare a `numGameThreads` other than `KTG_NUM_GAME_THREADS`.
  verify: `grep -n 'cpus-per-task=\|REQ_CPUS' codes/loop/loop.sbatch`; the check script named by `mission.json`
  `compute.policyCheck` at `--gpus 1 --cpus 32 --partition b200`, exit 0;
  `../evidence/wave3_prelaunch_repairs/repair_R1.txt`.
- [OPEN] `o39`'s third conjunct: one executed real-net production cycle must re-measure `nlwp_max <= 32` with a
  ppid-filtered sampler. Shared with `o03`; owned by `tasks/production_chain_9x9`. The sampler now runs inside the
  link (`loop.sbatch` starts `codes/eval/stage_monitor.sh`, the loop retags each cycle), so the link produces the
  measurement it needs.
  verify: node `selfplay_stage` re-measurement; `$BASEDIR/monitor/ps_samples-<jobid>.tsv`;
  `../evidence/wave3_prelaunch_repairs/repair_R6.txt`.
- [OPEN] The 28 for a **two**-real-net gatekeeper is arithmetic on a one-net measurement, not a measurement. Job
  298712's gate ran one exported net against the random baseline, so only one CUDA context existed; 25 is a lower
  bound for the two-net case and 28 the projection the declaration is sized against. First measurable at
  `gatekeeper_stage`, cycle 3 or later, once a candidate has been accepted into `models/`.
  verify: node `gatekeeper_stage`; claim `c13`.
- [OPEN] The unsuffixed smoke evidence names (`nlwp_max.txt`, `throughput_smoke.json`, `rows_per_game.txt`) were
  overwritten by attempt-2 job 299259, whose audit re-admits three foreign pids and reports `train nlwp 36` — a
  sampler defect (`o37`), not a measurement. Every number in this section and in the knob derivation reads the
  frozen, content-hashed `-298712` copies instead. Closes with `o37`.
  verify: `../evidence/smoke/validation_core.md` findings 2 and 8; sha256 table in
  `../evidence/derive_cycle_knobs/derivation.md` § 1.
- [SOLID] Assumption `a11` (the 20 % policy applies to the *sum* over concurrent jobs) and obligation `o22`
  (per-job vs summed) are both moot: the human withdrew the percentage clause outright on 2026-09-03, so there is
  no quantity to apportion and a second concurrent job no longer needs an answer before it may run. `check.sh`
  still prints the summed `my jobs gpus=…  cpus=…` line, but only the GPU half of it now gates anything.
  verify: `mission.json` `decisions[0].affects` names `compute.cpuCapPerJob`, `obligation o22`, `assumption a11` and "thread budgets in DESIGN.md"; `check.sh` prints `no cpu cap` in its OK line. [OPEN] the claim-ledger transitions for `a11` and `o22` are not appended by this node's worker; they belong with the validator that admits `cfg_9x9_override`.
- [OPEN] With the cap gone, `numGameThreads` is a throughput knob rather than a budget knob, and 18 is still only a
  lower bound justified by §1's queue-depth argument: a B200 fed by ≤18 concurrent 9x9 evaluations at batch 1 is
  idle most of the time (measured 21.5 % mean duty, 80 % peak). `derive_cycle_knobs_9x9` kept 18 and moved the
  declaration instead, which resolves the budget question without settling the throughput one. Raising it is still
  the cheapest way to lift GPU duty cycle, and must not be guessed. Closes when `measure_stage_throughput` reports
  GPU duty cycle and games/hour at 18 game threads and at one larger setting, and `derive_cycle_knobs_9x9` is
  re-run on the winner. Until then the configs stay at 18 and the loop declares 32 CPUs.
  verify: node `measure_stage_throughput` (`nvidia-smi dmon -s u`, `nnBatches`/`nnEvals`); claim `c09`;
  `codes/loop/knobs_9x9.env` `KTG_NUM_GAME_THREADS=18`.

## 2. Starting configuration and scaling path

| phase | model | GPUs | knobs (mission `synchronous_loop_9x9.sh`) | exit criterion |
|---|---|---|---|---|
| S0 env_build (PASSED, job 298018) | random-init b7c96h3tfrs | 1 | `katago runtests`, `benchmark -boardsize 9`, gtp genmove, torch fwd/bwd | result row `env-toolchain-b200`; c01, c02 admitted |
| S1 tiny export + cfg (parallel) | b7c96h3tfrs | 1 | export → block-kind scan → `benchmarknn -require-exact-nnlen -json` + gtp; b5 negative fixture; cfg key-diff + 1-game parse | claims c03, c04; o23 |
| S2 loop smoke | b7c96h3tfrs | 1 | NUM_GAMES_PER_CYCLE 40, NUM_TRAIN_SAMPLES_PER_EPOCH 256, BATCHSIZE 32, MAX_TRAIN_PER_DATA 8, NUM_TRAIN_SAMPLES_PER_SWA 128, EPOCHS_PER_EXPORT 1, SHUFFLE_MINROWS 200, TAPER_WINDOW_SCALE 200, SHUFFLE_KEEPROWS 5000 > MAX_TRAIN_SAMPLES_PER_CYCLE 4000, USEGATING 1, **two** cycles (`KTG_ONE_CYCLE=1` twice) + audit; records rows/game. Revised in place from the 20 games / 2000 samples-per-epoch of the first pass, which cannot export a candidate: `train.py:1303-1346` returns `None` from `get_files_for_subepoch` (so `-quit-if-no-data` exits 0 with no `SAVING MODEL FOR EXPORT`) unless the shuffled files hold `round(samples_per_epoch/batch)` batches, i.e. >= 2016 rows, and ~40 random-net games yield ~1130 (28.3 rows/game measured in job 298359). 256 = 8 batches of 32; cycle-2 bucket gain `new_rows x 8` clears `0.99 x 256` (`train.py:1434`). Source and full justification per knob: `tasks/synchronous_loop_smoke/implementation.md` sections 10 and 12 | c07, o19, plus o30, o03/c06, c04, c05, c10 and the two code-map probe packets in the same allocation; then `verify_preemption_resume` (c08) and `loop_failure_circuit_breaker` |
| P1 production-1 | b7c96h3tfrs | 1 | derived set (below): NUM_GAMES_PER_CYCLE 1000, NUM_TRAIN_SAMPLES_PER_EPOCH 20 000, BATCHSIZE 128, MAX_TRAIN_PER_DATA 8, NUM_TRAIN_SAMPLES_PER_SWA 10 000, EPOCHS_PER_EXPORT 5, SHUFFLE_MINROWS 25 000, TAPER_WINDOW_SCALE 50 000, SHUFFLE_KEEPROWS 120 000 > MAX_TRAIN_SAMPLES_PER_CYCLE 100 000, USEGATING 1, `--cpus-per-task` 32 at `numGameThreads` 18; at most one candidate per cycle | c13 (≥ 1 acceptance, target 2), c14 (CI excludes 0.5, target p ≥ 0.60) |
| P2 scale_up | b8c96h3tfrs, then b14c192h6tfrs | 1 | same loop, fresh run per config; GPUs added only via `async_multi_gpu_layout` `[FUTURE]` | c16 |
- [SOLID] Bucket arithmetic that the knobs must satisfy: `train_bucket_level += new_rows × MAX_TRAIN_PER_DATA`, capped at
  `max(MAX_TRAIN_SAMPLES_PER_CYCLE, samples_per_epoch)` (`train.py:1256-1259`); an epoch runs only if the bucket exceeds
  `0.99 × samples_per_epoch`, else `-stop-when-train-bucket-limited` exits (`:1433-1445`); `-epochs-per-export` defaults
  to 1 (`:438-439`), so without `-epochs-per-export N -max-epochs-this-instance N` every epoch exports a gated candidate.
  verify: cited lines; node `derive_cycle_knobs_9x9`, obligation `o24`.
- [SOLID] The knobs are derived, and the 500-game pilot hypothesis is retired. At the measured **32.3 rows/game**
  (real net, 646 rows / 20 games; random net 31.675 over 80) the pilot's 500 games yields 16 150 rows/cycle, which
  clears the bucket rule (gain 129 k ≥ 19.8 k) but fails two constraints the pilot never checked: a cycle must produce
  more new rows than an epoch draws (16 150 < 1.2 × 20 000), and cycle 1's shuffle window IS `SHUFFLE_MINROWS`
  (`shuffle.py:1077`, then `:414-435` returns exactly `min_rows`), so 10 000 gives 78 batches against the 156 an epoch
  needs and cycle 1 exports nothing — the same `train.py:1303-1346` defect the smoke hit, one scale up. The derived
  set solves both, cheapest knob first: **NUM_GAMES 1000** = ceil of max(1.2·E/r_lo, 1.25·E/r0_lo) = max(957, 889) at
  the § 11 lower bounds r_lo 25.08 / r0_lo 28.13; **MINROWS 25 000** = 1.25·E; **cap 100 000** = 5·E, upstream's own
  cap/epoch ratio (`:64`/`:59`), which the measurement supports (5·E ≤ half the reuse cap × 1000 × r_lo = 100 310);
  **KEEPROWS 120 000** = 1.2·cap, upstream's keep/cap ratio; **EPOCHS_PER_EXPORT 5** = floor(min(gain, cap_eff)/E),
  the same integer at r and at r_lo; **SWA 10 000** = E/2 (`train.py:441`); epoch 20 000 ≥ 100 batches so
  `metrics_train.json` is written at all (`train.py:1379`). Realised reuse 3.10 (3.99 at r_lo), well inside the cap of 8.
  Pass 2's set (reuse 4, 50 k samples/epoch, min 50 k) starves from cycle 2 (gain 44 k < 49.5 k) and pass 1's exported
  up to 4 gated candidates per cycle; both are reproduced as negative cases by `derive_knobs.py --self-test`.
  verify: `python3 codes/eval/check_knobs_9x9.py` exits 0 with `CHECK_KNOBS_9X9: PASS` (K1-K7 plus the four mission
  tolerances, and the loop copy's `${VAR:-default}` block equal to the derived set); full trace
  `../evidence/derive_cycle_knobs/derivation.md`, verbatim output `../evidence/knobs/derivation.txt`; obligation `o24`.
- [PRELIMINARY] The export ramp (corrected 2026-09-04, obligation `o40`): **the first candidate exports at cycle 5 and
  is gated at cycle 6**, and exactly one candidate per cycle begins at **cycle 16** if that first candidate is accepted
  (later for each rejection). `-epochs-per-export 5 -max-epochs-this-instance 5` makes train.py's persistent
  `export_cycle_counter` (`:871,975,1743,1831`) advance by at most 5 per cycle, so **at most** one candidate per cycle
  holds from cycle 1. But while `models/` is empty every cycle is random-net and `shuffle.py:1077` caps its usable rows
  at MINROWS, so the window is pinned at 25 000 rows = one epoch per cycle (`-no-repeat-files`,
  `katago/utils/training_data_generator.py:35`; `-quit-if-no-data` exits 0 with no export, `train.py:1487-1489`): five
  such cycles are needed to reach the counter's 5. Real-net rows therefore cannot exist before the cycle whose gate
  accepts, and the window reaches 5 × 20 000 = 100 000 rows only at cycle 17. The earlier reading — "exactly one from
  cycle 13, cycles 1-12 window-limited to 1-4 epochs" — assumed real-net rows from cycle 2 and is withdrawn. Forcing
  exactly one from cycle 1 would need MINROWS ≥ 100 000 and therefore ≥ 3554 random bootstrap games, which re-enters the
  NUM_GAMES derivation and diverges. `scale_data_window` may shorten the ramp once a real bootstrap is measured.
  verify: `python3 codes/eval/derive_knobs.py … ` prints `first_export_cycle = 5` and `first_exactly_one_cycle = 16`
  (cycle-by-cycle table under EXPORT RAMP BY CYCLE, reproduced in `../evidence/knobs/derivation.txt`); the executed
  first-export cycle is `o40 (c)`, owned by `train_stage` / `export_stage`.
- [SOLID] Random-play rows are capped at `min_rows` by the shuffler (`shuffle.py:1058,1077`), so the random bootstrap cannot flood the window.
  verify: `sed -n 1077p ref-code/lightvector-KataGo/python/shuffle.py`; node `training_window_shuffle`.
- [FUTURE] Asynchronous layout (selfplay and train as concurrent processes on 2–4 GPUs with disjoint device masks) is how upstream
  reaches 4–40×; deferred until `measure_stage_throughput` shows single-GPU duty > 70 % and the queue accepts > 1 GPU.
  verify: node `async_multi_gpu_layout`; `docs/cluster-manual.md` §6.
- [SOLID] Family choice: `tf` (interleaved, SwiGLU `ffnsg` only) for all phases; `nbt` fused family is exportable too
  (`export_model_pytorch.py:495-502`) but is a `[FUTURE]` comparison; `ffng` configs are excluded (o07, o18 discharged).
  verify: `modelconfigs.py:1886-1895` registration list; node `select_transformer_ladder`.
- [OPEN] `shuffle.py -exclude-qvalues` (`:801`) would drop the 492 B/row of zero q targets for b7 (no `predict_q_values`); adopt only after one epoch confirms `train.py` accepts npz without `qValueTargetsNCMove`.
  verify: obligation `o21`.

## 3. 9x9 enforcement — five keys, changed together

| # | key / flag | ships as | mission | where enforced |
|---|---|---|---|---|
| 1 | `bSizes` / `bSizeRelProbs` | `7,8,9` / `1,1,8` | `9` / `1` | `codes/cfg/selfplay_9x9.cfg`, `gatekeeper_9x9.cfg` |
| 2 | `allowRectangleProb` | `0.50` | `0` | same (half the games would be rectangles otherwise) |
| 3 | `dataBoardLen` | `19` (`selfplay1_maxsize9.cfg:16`) | `9` | selfplay cfg |
| 4 | `train.py -pos-len` | `19` hard-coded (`train.sh:88`) | `9` | mission `codes/loop/train_9x9.sh` |
| 5 | export `pos_len` | `load_model.py:62` default 19 | leave | benign: RoPE/score buffers non-persistent (`model_pytorch.py:2170-2171,2770-2784`) |
- [SOLID] 3 and 4 must be equal or `data_processing_pytorch.py:91` asserts (loud) — in *training*, so `data_format_pos_len` feeds
  `train_stage` directly. Leaving *both* at 19 is silent and trains a 361-token model on 81 real tokens: attention cost (361/81)² ≈ 20×.
  verify: `audit_paper_code_map.md` §10; task `paper_code_map_training` (npz row = 2145 B; arithmetic verified at ledger append) and c05.
- [SOLID] Data at different `dataBoardLen` cannot be shuffled together — the switch happens before any data exists.
  verify: `selfplay1_maxsize9.cfg:10-14` comment; `shuffle.py` has no re-shaping.
- [SOLID] `chosenMoveTemperatureHalflife = 19` stays 19: `searchhelpers.cpp:541-545` rescales by 19/√area → 9 turns at 9x9.
  verify: cited lines; do not "fix" it.
- [SOLID] `useNoisePruning` stays unset: `setup.cpp:578` defaults it to false for `SETUP_FOR_OTHER` (selfplay, `selfplay.cpp:110`); pass 2's `useNoisePruning=true` was a behaviour change, dropped by both seats.
  verify: node `root_explore_and_target_pruning` verification (executed at append).
- [PRELIMINARY] Side effects at 9x9 accepted as-is: komi σ scaled to 0.474 (`playutils.cpp:42`), handicap silently
  off (`playutils.cpp:10-22`), value-head gpool collinear (pool2 = −0.5·pool1, pool3 = 0.15·pool1 at 81 points, `model_pytorch.py:534-540`).
  verify: probe in task `paper_code_map_training`; the arithmetic half already passes at append (node `head_gpool_degeneracy_9x9`).
- [SOLID] The five keys are set and executed, not planned: `codes/cfg/selfplay_9x9.cfg` and
  `codes/cfg/gatekeeper_9x9.cfg` are line-for-line copies of the two `maxsize9` presets whose only differing
  significant lines carry the whitelisted keys, and `codes/loop/train_9x9.sh` differs from upstream `train.sh`
  in exactly one line. Rows 3 and 4 land in one commit, as `o02` requires.
  verify: `codes/eval/check_cfg_9x9.sh` checks 1-2 (`OUT_OF_SET_KEYS = 0` on both diffs); `diff <(tail -n +3 ref-code/lightvector-KataGo/python/selfplay/train.sh) <(tail -n +13 results/ktg/paper_1902.10565/codes/loop/train_9x9.sh)` shows only line 86 of the tail.
- [SOLID] Acceptance test for this section passed: every SGF has `SZ[9]` (claim c04). `codes/eval/check_cfg_9x9.sh`
  check 4 counts `n9 == n_all == 37` over both parse runs, `SZ9_FRACTION = 1.000`, with rectangular games
  (`SZ[x:y]`, `sgf.cpp:2015`) counted separately at `n_rectangular = 0`.
  verify: `../evidence/cfg_9x9/check_cfg_9x9-298359.txt` lines `n_all = 37`, `n9    = 37`, `SZ9_FRACTION = 1.000`, `n_rectangular = 0`, `CHECK_CFG_9X9: PASS`.

## 4. Checkpoint / resume under the 3-day walltime

Wrapper `codes/loop/loop.sbatch` (node `loop_resume_under_walltime`): `#!/bin/bash -l`, `--time=2-23:30:00`, `--gres=gpu:1`,
`--cpus-per-task=24`, `--mem=120G`, output on `/scratch`, `check.sh --gpus 1 --cpus 24` before every `sbatch`, resubmits itself
(`sbatch --dependency=afterany:$SLURM_JOB_ID`) so the chain continues after a kill or a drain, stops on `BASEDIR/STOP` or
`BASEDIR/.failcount` = 3. The loop copy `codes/loop/synchronous_loop_9x9.sh` copies `cpp/build/katago` (upstream `:81` copies
`cpp/katago`, which the mission build never produces — o17) and points `SELFPLAY_CONFIG`/`GATING_CONFIG` at the 9x9 cfgs (o13).
Per-stage idempotency the wrapper relies on:

| stage | on kill | mission action |
|---|---|---|
| gatekeeper | restarts candidate from scratch; returns 0 when nothing to test | none |
| selfplay | completed `.npz` kept (atomic rename `trainingwrite.cpp:1093-1096`); in-RAM ≤10k rows lost; game counter restarts | accept loss |
| shuffle | `.tmp` dir never promoted; `train.py:1210` skips it | wrapper deletes stale `shuffleddata/*.tmp` |
| train | auto-resume from `checkpoint.ckpt` (`train.py:780-796`), config from checkpoint (`:850`), shuffle order in train_state | none |
| export | **rm-before-mv window** (`export_model_for_selfplay.sh:89` vs `:108`) can orphan `<NAME>.exported` | mission copy moves `rm` after `mv`; wrapper removes `*.exported` whose target is missing |
- [SOLID] The upstream export ordering is a real data-loss hazard.
  verify: cited lines; executed check = node `verify_preemption_resume` (kill mid-train and mid-export, resume, no orphan; c08).
- [SOLID] `synchronous_loop.sh` is `bash -eu -o pipefail`: any stage error kills the loop and the job ends early;
  the resubmit chain restarts it, so a *deterministic* failure (e.g. export refusal, §8) would loop forever.
  verify: `synchronous_loop.sh:1-2`; node `loop_failure_circuit_breaker` injects the same non-zero stage exit 3× and requires no 4th submission (alignment §2).
- [PRELIMINARY] The wrapper is static evidence only (`bash -n`, greps, policy check); production self-play waits for both executed tests.
  verify: `logic.md` edges `verify_preemption_resume → selfplay_stage`, `loop_failure_circuit_breaker → selfplay_stage`.

## 5. Scratch budget (group at 37.80 / 40 TB = 94 %)

| item | size basis | P1 estimate |
|---|---|---|
| selfplay rows | **measured** 353.8 B/row on disk × **measured** 32.3 rows/game = 11.16 KiB/game (10.94 at the random net) — above c10's ≤ 10 KiB/game, which the smoke refuted | derived cycle of 1000 games ≈ 10.90 MiB tdata + 2.3 MiB SGFs |
| shuffleddata | ≤ `SHUFFLE_KEEPROWS` × 353.8 B per cycle; newest 3 kept (`cleanup_old_dirs.py:22-24`) | 120k rows → 40.5 MiB × 3 |
| train checkpoints | ~8e5 params × (weights + momentum) ≈ 6 MB; 4 short-term + 1 long-term / 12 h | < 1 GB / month even at b14c192 (~50 MB each) |
| models / modelstobetested / rejectedmodels | model.bin.gz + model.ckpt + metadata per export, never pruned upstream | ~2 MB × cycles |
| `scripts/dated/<ts>` | copy of `python/` + `katago` binary per loop (re)start | ~0.1 GB × restarts |
| venv + build (same root) | torch wheel, cuDNN wheel, CUTLASS, build tree | O(10 GB), counted from now on |
- [SOLID] The P1 write rate is now derived, not estimated: **16.11 MiB per cycle monotonic** (tdata 10.90 +
  SGFs 2.34 + one 2.87 MiB export) plus **553 MiB of bounded steady state** (3 shuffle dirs, 10 rejected models,
  10 checkpoints, 3 dated archives). With a 20 GiB venv/build allowance that is **20.90 GiB after a whole
  23-cycle chain link**, and **30 480 cycles** would fit before the cap — so storage is not a P1 constraint at
  these knobs, and the per-cycle write is 300× under the guard's default 20 GiB projection, which means
  `scratch_guard.sh` never refuses a cycle on this set.
  verify: `python3 codes/eval/check_knobs_9x9.py` line `T3_storage_projection_under_budget  20.90… GiB after one
  23-cycle link < 500 GiB`, exit 0; the arithmetic and its inputs in `../evidence/derive_cycle_knobs/derivation.md` § 5.
- [PRELIMINARY] Total well under 50 GiB for P1; hard cap **500 GiB = 536 870 912 000 B on the whole mission root**
  (`/scratch/…/ktg-train`, venv + build included; human decision 2026-09-03, `mission.json` `decisions[]`). The guard is
  projection-based rather than a second fixed threshold: a cycle declares the bytes it expects to write and is refused when
  `du -sb` + that projection would cross the cap, so with the default 20 GiB per-cycle projection no new cycle starts at
  ≥ 480 GiB = 515 396 075 520 B. The group quota (`python3 /apps/helpers/quotas.py`, cross-checked against `df -B1` and the
  smaller of the two taken) is checked too because `du` of the mission root cannot see group exhaustion: **the guard also
  refuses below 1 TiB = 1 099 511 627 776 B of group free space** — twice the mission's entire budget, so spending the whole
  budget can never be what fills the shared 40 TB pool — and warns below 1.5 TiB. One `du -sb` / `df -B1` / quota triple is
  logged per cycle. Retention is bounded by a logged policy that protects the frozen
  baseline, latest accepted net, current + previous checkpoints and evidence: `longterm_checkpoints` ≤ 6, `rejectedmodels` ≤ 10,
  stale `shuffleddata/*.tmp`, and an over-budget rolling mode that never goes below one shuffle window plus one selfplay
  generation. Bytes/row is calibrated after 100 k rows by `measure_stage_throughput` (pass 2's 1 KiB/row planning number is a 19x19 upper bound).
  verify: node `data_budget` closing check (`codes/data_budget/tests/run_guard_tests.sh`, 11/11; `du -sb $KTG ≤ 536870912000`); claims c10, c11; obligation o04.
- [SOLID] Nothing upstream prunes `selfplay/*/tdata`; growth is monotonic.
  verify: grep of `python/selfplay/*.sh` and `cleanup_old_dirs.py` (audit §F).

## 6. Smoke-first ordering (topological, one packet per row)

1. `env_build` **solid** (result row `env-toolchain-b200`) → 2. READY now, in parallel: `cfg_9x9_override`, `tiny_model_export_smoke`
(no longer waits for the cfg), `loop_resume_under_walltime` (static wrapper), `data_budget` (guard constants) →
3. `synchronous_loop_smoke` (+ audit; measures rows/game) → 4. `derive_cycle_knobs_9x9` **done** (knob set in
`codes/loop/knobs_9x9.env`, wired into the loop copy's CHANGE 9 block; o24 and o13's knob conjunct closed),
`verify_preemption_resume`, `loop_failure_circuit_breaker` → 5. P1: `selfplay_stage`, `shuffle_stage`, `train_stage`, `export_stage`, `gatekeeper_stage`,
`bootstrap_accepted_model` → 6. `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first` →
`eval_improvement` → 7. `scale_data_window` → `scale_search_budget` → `scale_up` (b8 → b14); `async_multi_gpu_layout` `[FUTURE]`.
Code-map nodes (15, `preliminary`) are promoted to solid by the two probe **tasks** `paper_code_map_search` / `paper_code_map_training`
(task files, not DAG nodes); `engine_ffn_swiglu_constraint` is already solid on the recorded abort.
- [SOLID] READY frontier (all predecessors solid/preliminary): `cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime`, `data_budget`.
  verify: `python3 phys-agentic-loop/_common/knowledge_database.py query --paper arxiv-1902.10565` + predecessor walk (recorded in `dag_reconciliation.md` §5); task files in `../tasks/<node>/implementation.md`.
- [OPEN] Row 4 does not fully release row 5. `derive_cycle_knobs_9x9` decided `--cpus-per-task = 32` but its task
  file § 13 forbids it editing `codes/loop/loop.sbatch`, which still declares 24; `selfplay_stage` must not start
  before that edit lands (obligation `o38`, owner `loop_resume_under_walltime`), or the first real-net cycle
  re-runs the same "declared < used" defect the smoke found. `verify_preemption_resume` and
  `loop_failure_circuit_breaker` are unaffected and can run in parallel with it.
  verify: `grep -n 'cpus-per-task\|REQ_CPUS' codes/loop/loop.sbatch` = 32; obligation `o38`.

## 7. Evaluation criterion (replaces the paper's 19x19 Elo)

- `count_gatekeeper_acceptances` (c13): ≥ 1 gate-accepted successor after the frozen first net (`numGamesPerGating` 200,
  `-required-candidate-win-prop` 0.5 default, ties to the candidate `gatekeeper.cpp:580`, `maxVisits` 150); ≥ 2 is the stretch target.
- `match_latest_against_first` (c14): `katago match`, 9x9, komi 7 (draws count 0.5), `maxVisits` 150, 1 search thread, 400 games,
  colours alternated, latest accepted vs frozen first net; `p = (W + 0.5 D)/N`, `Elo = 400·log10(p/(1−p))`, 95 % CI from
  `python/summarize_sgfs.py`. Required: CI excludes 0.5; effect-size target p ≥ 0.60 (≈ +70 Elo; SE 0.025 at n = 400).
- `eval_improvement`: declared iff both hold; reports samples trained vs the 2 M-sample warm-up (`train.py:1074-1079`), GPU-hours, hashes.
- [SOLID] Gating alone is a weak filter: at equal strength P(≥100/200) ≈ 0.53.
  verify: binomial arithmetic; hence the separate 400-game match.
- [SOLID] Bootstrap semantics: with `USEGATING=1` and empty `models/` the gatekeeper does **not** skip — `findLatestModel` returns
  true with `/dev/null` (`loadmodel.cpp:77-93`), `setup.cpp:126` makes that a random-play net, so the first candidate is gated
  against random; the first dir in `models/` is the frozen baseline (`bootstrap_accepted_model`). Pass 1's "gating skipped" and
  pass 2's "requires an accepted model / USEGATING=0 once" were both wrong; USEGATING=0 for the first export is optional, unused.
  verify: node `gating_rule` verification (executed at append); runtime line "Loaded accepted neural net random" in the smoke gatekeeper log (o19).
- [HOLE] No external 9x9 reference net is available on the cluster; strength is only relative to the run's own first net.
  verify: none possible offline; `[FUTURE]` compare against a public KataGo 9x9-capable net if one is downloaded (acquire stage).

## 8. Top risks — detection signature → response

| # | risk | signature | response |
|---|---|---|---|
| R1 | no sm_100 SASS (`CMakeLists.txt:761`) — **closed**: `codes/env/cmake-sm100.diff` applied at env_build stage 2b, `smoke.txt:40` count = 2 | `cuobjdump --list-elf katago \| grep -c sm_100` = 0 | re-apply the diff after any re-clone |
| R2 | pos_len 19 left in place | npz row 7675 B not 2145; `train.py` log `pos_len 19`; attention memory ~20× | fix §3 keys before any data; discard data |
| R3 | attention-logit export refusal | export stage exit ≠ 0 with bound > 2.5e4 (`export_model_pytorch.py:42`); loop dies each cycle | enable `-attn-logit-penalty-cap` in train wrapper; record fail row (o15) |
| R4 | job uses more CPUs than it declared (no cap exists, but the declaration must be true) — **fired** in job 298712 at 25 > 24 on both real-net stages | `ps -o nlwp -p <pid>` > `SLURM_CPUS_PER_TASK`; `seff` CPU > allocated cores | resolved by `derive_cycle_knobs_9x9`: `KTG_CPUS_PER_TASK=32` at `numGameThreads=18` (`codes/loop/knobs_9x9.env`), worst stage 29; `[OPEN]` `o38` wires it into `loop.sbatch`. Still raise the declaration *and* the config together, never one alone |
| R5 | scratch full (group) | `quotas.py` ≥ 99 %; `OSError: No space left` in shuffle | 500 GiB projected-write guard + 1 TiB group free-space floor + bounded retention; stop loop |
| R6 | queue wait / b300 reserved | `PENDING (Priority|ReqNodeNotAvail)` > 30 min | 1 GPU on b200; never request 2 GPUs before `async_multi_gpu_layout` |
| R7 | random-net bootstrap | `selfplay/random/` appears; cycle 1 trains on random-play rows; first candidate gated vs random | accepted (a10); rows capped at `min_rows` by the shuffler |
| R8 | export kill-window orphan | `torchmodels_toexport/<NAME>.exported` with no `models/<NAME>` | wrapper cleanup + reordered mission exporter |
| R9 | value-head gpool collinearity | probe: pool2/pool1 = −0.5 exactly | accepted; no code change |
| R10 | `torch.compile` first-epoch stall | minutes of 100 % CPU at epoch start, no GPU util | expected; `-no-compile` only if it exceeds 15 min |
| R11 | RoPE + `rootNumSymmetriesToSample=4` inconsistency | root value variance across symmetries in `logSearchInfo` | `[FUTURE]` measure; set to 1 if harmful |
| R12 | deterministic stage failure + resubmit chain | same error in 3 consecutive job logs | `.failcount` stop at 3 (`loop_failure_circuit_breaker`), escalate (alignment §2) |
| R13 | non-SwiGLU config slips into MODELKIND | NN server thread fails at startup: "Non-SwiGLU transformer FFN is not yet supported" | wrapper asserts MODELKIND matches `*tfrs|*tflrs` |
| R14 | training starves from cycle 2 | `Exceeding train bucket, not enough new data rows` every cycle; zero epochs | closed by the derived set: bucket gain 258 400/cycle (200 620 at r_lo) against a 100 000 draw, ratio 12.9 (10.0). Re-run `codes/eval/check_knobs_9x9.py` after any re-measurement of rows/game; never hand-pick a knob (o24) |
| R16 | a cycle's shuffle window is smaller than one epoch, so `train.py:1303-1346` returns `None` and `-quit-if-no-data` exits **0 with no export** — silent, no error line | `Not enough data files to fill a subepoch! Quitting.` and no `SAVING MODEL FOR EXPORT`; the smoke hit this at 2000 samples/epoch on ~440 rows | `SHUFFLE_MINROWS = 1.25 × samples-per-epoch`, because cycle 1's window IS `min_rows` (`shuffle.py:1077`); checked at every cycle by K4 in `check_knobs_9x9.py`, worst case cycle 1 at 195 batches vs 156 needed |
| R17 | evidence files that a later job overwrites are cited as measurements | two runs disagree on a number that should be immutable; `foreign pids excluded: none` where a rule should have fired | cite only job-suffixed copies (`*-298712.*`, `*-299259.*`); `derive_knobs.py` / `check_knobs_9x9.py` prefer them by name (o37) |
| R15 | glibc fragmentation in self-play (no TCMalloc) | selfplay `MaxRSS` grows across cycles | rebuild with `-DUSE_TCMALLOC=1` (o20) |

## 9. Decisions recorded (owner: brain design; reconciled by the reformulation pass 2026-09-04)

- Code-first: v1.18.2 is authoritative; paper values (lr 6e-5, c_value 1.5, S = 421, 300-node gating) are not targets. [SOLID] verify: assumption `a09`; `derivation.md` §3.
- Start config `b7c96h3tfrs`; ladder b8 → b14 as fresh runs; `b5c48h3tfr` excluded (unservable), kept as negative fixture. [SOLID] verify: nodes `engine_ffn_swiglu_constraint` (solid), `select_transformer_ladder`; jobs 297952 (FAILED 1:0) vs 298018 (COMPLETED 0:0); a06, o07/o18 discharged.
- One GPU, `--cpus-per-task=32`, five stages sequential; multi-GPU only as `async_multi_gpu_layout` after measured saturation. The 24 held through the smoke and was falsified by it (25 measured on every CUDA-context stage); `derive_cycle_knobs_9x9` raised the declaration rather than cutting `numGameThreads`, because with the CPU cap withdrawn the declaration is the free side of the trade and the game threads are what feed the GPU. [SOLID] verify: §1; `codes/loop/knobs_9x9.env` `KTG_CPUS_PER_TASK=32`; a02 amended; wired into `loop.sbatch` (`#SBATCH --cpus-per-task=32`, `REQ_CPUS` read from the knob file, granted-CPU assert) by `o39`.
- No CPU usage limit (human, 2026-09-03): the 20 % clause is withdrawn, so 24 CPUs is a derived honest declaration (22 live threads + 2 transient), not a ceiling; `a11` and `o22` are moot and `o03`'s "24-CPU cap" wording is superseded by "declared ≥ measured". [SOLID] verify: `mission.json` `decisions[0]`, `compute.cpuCapPerJob = null`, `compute.cpuPolicy`; §1 `NLWP_MAX` measurement.
- Threads: selfplay 18 / gatekeeper 18 game threads (data-write thread counted), shuffle 8, train OMP 4. All four rows are now measured, in two jobs: random-net selfplay 22, **any CUDA-context stage 25**, train 14, shuffle 4 + 8 = 12; job 299259 reproduced 25 / 14 with a ppid-filtered sampler and no foreign pids at all. Only the two-real-net gatekeeper is still arithmetic: 18 game + 2 nnServer + 1 dataWrite + 1 main + 2 × 3 CUDA = **28**, headroom 4 against the declared 32 (the 29 printed before 2026-09-04 mis-summed the same terms, o40). [SOLID] verify: `../evidence/smoke/nlwp_max-298712.txt`, `audit-299259.json` `S13_throughput.nlwp_max_per_stage`; `../evidence/cfg_9x9/check_cfg_9x9-298359.txt`; c06 (real-net clause refuted), o03; the two-net row at `gatekeeper_stage`.
- USEGATING = 1 throughout; cycle 1 gates the first candidate against the random baseline; first dir in `models/` is the frozen baseline. [SOLID] verify: `gating_rule` node; o10, o16 discharged; o19 runtime confirmation.
- Cycle knobs are derived from measured rows/game (32.3 real, 31.675 random), never hand-picked: NUM_GAMES 1000, epoch 20 000, batch 128, reuse 8, SWA 10 000, EPOCHS_PER_EXPORT 5, MINROWS 25 000, TAPER 50 000, KEEPROWS 120 000 > cap 100 000. **At most** one exported candidate per cycle from cycle 1 (`-epochs-per-export` = `-max-epochs-this-instance`); the first candidate is exported at cycle 5 and gated at cycle 6, and exactly one per cycle begins at cycle 16 under acceptance at 6 (o40 — the window is pinned at MINROWS while `models/` is empty). The §2 500-game pilot set is refuted: it produces fewer new rows per cycle than an epoch draws, and its 10 000 MINROWS gives cycle 1 a 78-batch window against 156. [SOLID] verify: o24; `python3 codes/eval/check_knobs_9x9.py` exit 0; `codes/loop/knobs_9x9.env`; `../evidence/derive_cycle_knobs/derivation.md`; smoke `rows_per_game-298712.txt`.
- Data windows: KEEPROWS > MAX_TRAIN_SAMPLES_PER_CYCLE always; random rows capped at `min_rows`, which makes SHUFFLE_MINROWS — not the game count — the knob that decides whether cycle 1 can train at all. [SOLID] verify: `synchronous_loop.sh:66`, `shuffle.py:1077`, `:414-435`; K3/K4 in `codes/eval/check_knobs_9x9.py`.
- Cycle-wall and storage projections ride with the knob set and are re-derived whenever a rate is re-measured: 3.11 h/cycle → 23 cycles per chain link, 16.11 MiB/cycle → 30 480 cycles before the 500 GiB cap. Both take the SLOWER of the two smoke jobs’ rates. [PRELIMINARY] verify: K7 and T3 in `codes/eval/check_knobs_9x9.py`; node `measure_stage_throughput` owns the real bound.
- Scratch: 500 GiB cap on the whole mission root, projected-write pre-cycle guard, 1 TiB group free-space floor, logged bounded retention. [PRELIMINARY] verify: o04, c11; node `data_budget`.
- Keep gpool constants (14, 0.1) for C++ compatibility; accept 9x9 redundancy. [SOLID] verify: o14 discharged by node `head_gpool_degeneracy_9x9`.
- CUDA backend, cuDNN 9.19 wheel (SDPA path on since `CUDNN_VERSION >= 8903`, `cudabackend.cpp:13`); TensorRT deferred; no TCMalloc yet. [SOLID] verify: result row `env-toolchain-b200`; a08, o05, o20.
- Evaluation: ≥ 1 acceptance (target 2) AND 400-game CI excluding 0.5 (target p ≥ 0.60). [PRELIMINARY] verify: c13, c14; nodes `count_gatekeeper_acceptances`, `match_latest_against_first`, `eval_improvement`.
