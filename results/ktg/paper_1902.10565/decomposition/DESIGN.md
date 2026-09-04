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

Design: **one job, one GPU, `--cpus-per-task=24`, all five stages sequential**, partition b300 preferred
→ b200 fallback (b200 while gb301 is reserved). GPU is shared trivially (one process at a time).
`--mem=120G` (shuffle buckets + train prefetch).

The 24 is no longer a cap handed down by policy. The "no more than 20 % of all CPUs" clause was
**withdrawn by the human on 2026-09-03** (`mission.json` `decisions[]` entry 1, `compute.cpuCapPerJob = null`,
`compute.cpuPolicy`); what survives is the weaker and purely local rule that a job must *declare*
`--cpus-per-task` honestly and must not spawn more OS threads than it declared. So the derivation runs the
other way now: pick the thread counts the stage needs, sum every live thread, and request at least that many
CPUs. The mission's stages sum to 22 threads (table below), so the honest request is 24 — 22 plus the two
transient threads of a mid-run net switch — and 24 also happens to be what `loop.sbatch` and the
`cfg_9x9_override` validation job (Slurm 298359, `--cpus-per-task=24`) actually asked for, which is the number
`ps -o nlwp=` is compared against. Nothing forbids a larger request; a larger one has to be *earned* by a
measurement, not assumed (see the `[OPEN]` item below).
- [SOLID] There is no CPU cap; the constraint is "declared ≥ used", and `check.sh` passes any CPU count.
  verify: `mission.json` `compute.cpuCapPerJob` = `null` and `decisions[0].decision` = "no CPU usage limit; the 20% clause in PROMPT.md is withdrawn"; the check script named by `mission.json` `compute.policyCheck`, invoked with `--gpus 1 --cpus 24 --partition b200` → `OK : request gpus=1 cpus=24 part=b200 within policy (gpu<=4, no cpu cap)`, exit 0.

Split of the 24 declared CPUs per stage (only one stage runs at a time, so each stage may use the whole
request):

| stage | OS threads / processes | how | evidence |
|---|---|---|---|
| selfplay | 18 game + 1 nnServer + 1 dataWrite + 1 modelLoad + 1 main = 22 (+2 transient at net switch) | `numGameThreads=18`, `numSearchThreads=1`, `numNNServerThreadsPerModel=1` | `selfplay.cpp:359-364`, `setup.cpp:193-203`, `selfplaymanager.cpp:156` |
| gatekeeper | 18 game + 2 nnServer (2 models) + 1 dataWrite + 1 main = 22 | `numGameThreads=18` (pass 1's 20 gave 24 — the data-write thread was uncounted, leaving no margin under a 24-CPU request) | `gatekeeper.cpp:548-553` |
| shuffle | 8 worker processes | `-num-processes 8` | `synchronous_loop.sh:58`, `shuffle.py:791` |
| train | 1 process, `OMP_NUM_THREADS=MKL_NUM_THREADS=4`, prefetch depth 1 | env vars + `-data-prefetch-depth` default | `train.py:126`; obligation `o11` |
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
- [PRELIMINARY] The gatekeeper, shuffle and train rows of the table are still computed, not measured; they are
  admitted only from `ps -o nlwp=` on those live processes when their nodes run.
  verify: claim `c06` for `gatekeeper_stage` / `train_stage`; obligation `o03`.
- [SOLID] Assumption `a11` (the 20 % policy applies to the *sum* over concurrent jobs) and obligation `o22`
  (per-job vs summed) are both moot: the human withdrew the percentage clause outright on 2026-09-03, so there is
  no quantity to apportion and a second concurrent job no longer needs an answer before it may run. `check.sh`
  still prints the summed `my jobs gpus=…  cpus=…` line, but only the GPU half of it now gates anything.
  verify: `mission.json` `decisions[0].affects` names `compute.cpuCapPerJob`, `obligation o22`, `assumption a11` and "thread budgets in DESIGN.md"; `check.sh` prints `no cpu cap` in its OK line. [OPEN] the claim-ledger transitions for `a11` and `o22` are not appended by this node's worker; they belong with the validator that admits `cfg_9x9_override`.
- [OPEN] With the cap gone, `numGameThreads` is a throughput knob rather than a budget knob, and 18 is now only a
  lower bound justified by §1's queue-depth argument: a B200 fed by ≤18 concurrent 9x9 evaluations at batch 1 is
  idle most of the time. Raising it (and `--cpus-per-task` with it, one node has 124) is the cheapest way to lift
  GPU duty cycle, but must not be guessed. Closes when `measure_stage_throughput` reports GPU duty cycle and
  games/hour at 18 game threads and at one larger setting, and `derive_cycle_knobs_9x9` re-derives the cycle knobs
  from the winner. Until then the configs stay at 18 and the loop declares 24 CPUs.
  verify: node `measure_stage_throughput` (`nvidia-smi dmon -s u`, `nnBatches`/`nnEvals`); claim `c09`.

## 2. Starting configuration and scaling path

| phase | model | GPUs | knobs (mission `synchronous_loop_9x9.sh`) | exit criterion |
|---|---|---|---|---|
| S0 env_build (PASSED, job 298018) | random-init b7c96h3tfrs | 1 | `katago runtests`, `benchmark -boardsize 9`, gtp genmove, torch fwd/bwd | result row `env-toolchain-b200`; c01, c02 admitted |
| S1 tiny export + cfg (parallel) | b7c96h3tfrs | 1 | export → block-kind scan → `benchmarknn -require-exact-nnlen -json` + gtp; b5 negative fixture; cfg key-diff + 1-game parse | claims c03, c04; o23 |
| S2 loop smoke | b7c96h3tfrs | 1 | NUM_GAMES_PER_CYCLE 20, SHUFFLE_MINROWS 200, KEEPROWS 5000, samples-per-epoch 2000, batch 32, USEGATING 1, 1 cycle + audit; records rows/game | c07, o19; then `verify_preemption_resume` (c08) and `loop_failure_circuit_breaker` |
| P1 production-1 | b7c96h3tfrs | 1 | knobs from `derive_cycle_knobs_9x9` (pilot hypothesis below), USEGATING 1, one candidate per cycle | c13 (≥ 1 acceptance, target 2), c14 (CI excludes 0.5, target p ≥ 0.60) |
| P2 scale_up | b8c96h3tfrs, then b14c192h6tfrs | 1 | same loop, fresh run per config; GPUs added only via `async_multi_gpu_layout` `[FUTURE]` | c16 |
- [SOLID] Bucket arithmetic that the knobs must satisfy: `train_bucket_level += new_rows × MAX_TRAIN_PER_DATA`, capped at
  `max(MAX_TRAIN_SAMPLES_PER_CYCLE, samples_per_epoch)` (`train.py:1256-1259`); an epoch runs only if the bucket exceeds
  `0.99 × samples_per_epoch`, else `-stop-when-train-bucket-limited` exits (`:1433-1445`); `-epochs-per-export` defaults
  to 1 (`:438-439`), so without `-epochs-per-export N -max-epochs-this-instance N` every epoch exports a gated candidate.
  verify: cited lines; node `derive_cycle_knobs_9x9`, obligation `o24`.
- [PRELIMINARY] Pilot knob hypothesis at ~22 rows/game (500 games ≈ 11 k rows/cycle): reuse 8 → bucket gain 88 k ≥ 0.99 × 20 000 ✓
  (4 epochs), so NUM_GAMES 500, MAX_TRAIN_PER_DATA 8, samples-per-epoch 20 000, `-epochs-per-export 4 -max-epochs-this-instance 4`,
  SHUFFLE_MINROWS 10 000, KEEPROWS 300 000 > MAX_TRAIN_SAMPLES_PER_CYCLE 200 000 (`synchronous_loop.sh:66` rule), TAPER 50 000, batch 128.
  Pass 2's set (reuse 4, 50 k samples/epoch, min 50 k) starves training from cycle 2 (gain 44 k < 49.5 k) and needs ~2300
  random games before the first shuffle; pass 1's set exported up to 4 gated candidates per cycle. All re-derived after S2.
  verify: `codes/eval/derive_knobs.py --rows-per-game <measured> --reuse 8 --samples-per-epoch 20000 --games 500 --keep 300000 --cap 200000` exits 0; smoke log lines `Fill per data`, `New rows in bucket`, `Exceeding train bucket`, count of `SAVING MODEL FOR EXPORT` per cycle.
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
| selfplay rows | 2145 B/row × ~0.12 compressed × ~22 rows/game ≈ 5.7 KB/game | 1e6 games ≈ 5.7 GB (+ SGFs ≈ 1–2 KB/game) |
| shuffleddata | ≤ keep-target-rows × 2145 × 0.12 per cycle; newest 3 kept (`cleanup_old_dirs.py:22-24`) | 300k rows → 77 MB × 3 |
| train checkpoints | ~8e5 params × (weights + momentum) ≈ 6 MB; 4 short-term + 1 long-term / 12 h | < 1 GB / month even at b14c192 (~50 MB each) |
| models / modelstobetested / rejectedmodels | model.bin.gz + model.ckpt + metadata per export, never pruned upstream | ~2 MB × cycles |
| `scripts/dated/<ts>` | copy of `python/` + `katago` binary per loop (re)start | ~0.1 GB × restarts |
| venv + build (same root) | torch wheel, cuDNN wheel, CUTLASS, build tree | O(10 GB), counted from now on |
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
3. `synchronous_loop_smoke` (+ audit; measures rows/game) → 4. `derive_cycle_knobs_9x9`, `verify_preemption_resume`,
`loop_failure_circuit_breaker` → 5. P1: `selfplay_stage`, `shuffle_stage`, `train_stage`, `export_stage`, `gatekeeper_stage`,
`bootstrap_accepted_model` → 6. `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first` →
`eval_improvement` → 7. `scale_data_window` → `scale_search_budget` → `scale_up` (b8 → b14); `async_multi_gpu_layout` `[FUTURE]`.
Code-map nodes (15, `preliminary`) are promoted to solid by the two probe **tasks** `paper_code_map_search` / `paper_code_map_training`
(task files, not DAG nodes); `engine_ffn_swiglu_constraint` is already solid on the recorded abort.
- [SOLID] READY frontier (all predecessors solid/preliminary): `cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime`, `data_budget`.
  verify: `python3 phys-agentic-loop/_common/knowledge_database.py query --paper arxiv-1902.10565` + predecessor walk (recorded in `dag_reconciliation.md` §5); task files in `../tasks/<node>/implementation.md`.

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
| R4 | job uses more CPUs than it declared (no cap exists, but the declaration must be true) | `ps -o nlwp -p <pid>` > `SLURM_CPUS_PER_TASK`; `seff` CPU > allocated cores | thread table §1 (gatekeeper 18); raise `--cpus-per-task` *and* the config together, never one alone |
| R5 | scratch full (group) | `quotas.py` ≥ 99 %; `OSError: No space left` in shuffle | 500 GiB projected-write guard + 1 TiB group free-space floor + bounded retention; stop loop |
| R6 | queue wait / b300 reserved | `PENDING (Priority|ReqNodeNotAvail)` > 30 min | 1 GPU on b200; never request 2 GPUs before `async_multi_gpu_layout` |
| R7 | random-net bootstrap | `selfplay/random/` appears; cycle 1 trains on random-play rows; first candidate gated vs random | accepted (a10); rows capped at `min_rows` by the shuffler |
| R8 | export kill-window orphan | `torchmodels_toexport/<NAME>.exported` with no `models/<NAME>` | wrapper cleanup + reordered mission exporter |
| R9 | value-head gpool collinearity | probe: pool2/pool1 = −0.5 exactly | accepted; no code change |
| R10 | `torch.compile` first-epoch stall | minutes of 100 % CPU at epoch start, no GPU util | expected; `-no-compile` only if it exceeds 15 min |
| R11 | RoPE + `rootNumSymmetriesToSample=4` inconsistency | root value variance across symmetries in `logSearchInfo` | `[FUTURE]` measure; set to 1 if harmful |
| R12 | deterministic stage failure + resubmit chain | same error in 3 consecutive job logs | `.failcount` stop at 3 (`loop_failure_circuit_breaker`), escalate (alignment §2) |
| R13 | non-SwiGLU config slips into MODELKIND | NN server thread fails at startup: "Non-SwiGLU transformer FFN is not yet supported" | wrapper asserts MODELKIND matches `*tfrs|*tflrs` |
| R14 | training starves from cycle 2 | `Exceeding train bucket, not enough new data rows` every cycle; zero epochs | knobs from `derive_cycle_knobs_9x9` (o24), never hand-picked |
| R15 | glibc fragmentation in self-play (no TCMalloc) | selfplay `MaxRSS` grows across cycles | rebuild with `-DUSE_TCMALLOC=1` (o20) |

## 9. Decisions recorded (owner: brain design; reconciled by the reformulation pass 2026-09-04)

- Code-first: v1.18.2 is authoritative; paper values (lr 6e-5, c_value 1.5, S = 421, 300-node gating) are not targets. [SOLID] verify: assumption `a09`; `derivation.md` §3.
- Start config `b7c96h3tfrs`; ladder b8 → b14 as fresh runs; `b5c48h3tfr` excluded (unservable), kept as negative fixture. [SOLID] verify: nodes `engine_ffn_swiglu_constraint` (solid), `select_transformer_ladder`; jobs 297952 (FAILED 1:0) vs 298018 (COMPLETED 0:0); a06, o07/o18 discharged.
- One GPU, `--cpus-per-task=24`, five stages sequential; multi-GPU only as `async_multi_gpu_layout` after measured saturation. [PRELIMINARY] verify: §1; a02 amended.
- No CPU usage limit (human, 2026-09-03): the 20 % clause is withdrawn, so 24 CPUs is a derived honest declaration (22 live threads + 2 transient), not a ceiling; `a11` and `o22` are moot and `o03`'s "24-CPU cap" wording is superseded by "declared ≥ measured". [SOLID] verify: `mission.json` `decisions[0]`, `compute.cpuCapPerJob = null`, `compute.cpuPolicy`; §1 `NLWP_MAX` measurement.
- Threads: selfplay 18 / gatekeeper 18 game threads (data-write thread counted), shuffle 8, train OMP 4; selfplay's 22 live threads are measured, the other three rows are still arithmetic. [PRELIMINARY] verify: c06 via `ps -o nlwp` — selfplay `NLWP_MAX` in `../evidence/cfg_9x9/check_cfg_9x9-298359.txt`, the rest at `gatekeeper_stage` / `shuffle_stage` / `train_stage`; o03.
- USEGATING = 1 throughout; cycle 1 gates the first candidate against the random baseline; first dir in `models/` is the frozen baseline. [SOLID] verify: `gating_rule` node; o10, o16 discharged; o19 runtime confirmation.
- Cycle knobs are derived from measured rows/game (`derive_cycle_knobs_9x9`), one exported candidate per cycle; the §2 pilot set is a hypothesis. [PRELIMINARY] verify: o24; smoke `rows_per_game.txt`.
- Data windows: KEEPROWS > MAX_TRAIN_SAMPLES_PER_CYCLE always; random rows capped at `min_rows`. [SOLID] verify: `synchronous_loop.sh:66`, `shuffle.py:1077`.
- Scratch: 500 GiB cap on the whole mission root, projected-write pre-cycle guard, 1 TiB group free-space floor, logged bounded retention. [PRELIMINARY] verify: o04, c11; node `data_budget`.
- Keep gpool constants (14, 0.1) for C++ compatibility; accept 9x9 redundancy. [SOLID] verify: o14 discharged by node `head_gpool_degeneracy_9x9`.
- CUDA backend, cuDNN 9.19 wheel (SDPA path on since `CUDNN_VERSION >= 8903`, `cudabackend.cpp:13`); TensorRT deferred; no TCMalloc yet. [SOLID] verify: result row `env-toolchain-b200`; a08, o05, o20.
- Evaluation: ≥ 1 acceptance (target 2) AND 400-game CI excluding 0.5 (target p ≥ 0.60). [PRELIMINARY] verify: c13, c14; nodes `count_gatekeeper_acceptances`, `match_latest_against_first`, `eval_improvement`.
