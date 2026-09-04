# DESIGN.md — mission `ktg-train`: 9x9 transformer KataGo self-play loop on skipjack

Scope: what the loop is, how it fits ≤4 GPUs / ≤24 CPUs / 3-day walltime / 94 %-full scratch, and in
what order it is proven. Source of truth is the v1.18.2 code mirror (human redirect 2026-09-03); the
2019 paper is background. Every claim carries `[SOLID|PRELIMINARY|HOLE|FUTURE]` and a `verify:` line.
`[SOLID]` here means read in code with path:line or measured live on the cluster; nothing in this
document has been executed on a GPU yet except the env_build job now running (297952).
Evidence files: `../evidence/decomposition/audit_loop_scripts_configs.md`, `audit_paper_code_map.md`.
DAG: `logic.md` (26 nodes). Ledger views: `claims.md`, `obligations.md`, `assumptions.md`.

## 0. What is being built

The unmodified v1.18.2 five-stage loop — `katago gatekeeper` → `katago selfplay` → `shuffle.py` →
`train.py` → `export_model_pytorch.py` — driven by a mission copy of `python/selfplay/synchronous_loop.sh`,
on one node, with mission-owned configs that make it 9x9-only, and a Slurm wrapper that survives the 3-day
ceiling. Model: **`b7c96h3tfrs`** (7 × attnrope+ffnsg, 96 ch, 3 heads) for smoke and first production;
`b8c96h3tfrs`/`b14c192h6tfrs` for scale-up. `b5c48h3tfr` (ffng) is **excluded**: every C++ backend throws
"Non-SwiGLU transformer FFN is not yet supported" (`cudaandrocmbackend.inc:3307-3308`, `eigenbackend.cpp:1634`,
`openclbackend.cpp:2729`); job 297952 failed exactly there (exit 134), job 298018 passed with `b7c96h3tfrs`. No engine patches; the one edit outside this repo is a `sed`
adding `100` to the CUDA-12.8 arch list in the *scratch* build clone.
- [SOLID] Every stage's entry point, argument list and file contract is known.
  verify: `audit_loop_scripts_configs.md` §A–C (`synchronous_loop.sh:93-116`, `train.sh:83-93`, `export_model_pytorch.py:34-42`).
- [SOLID] `b7c96h3tfrs` exports to the C++ engine and plays 9x9 on a B200 (benchmark + gtp genmove + torch fwd/bwd).
  verify: `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/evidence/env/smoke-298018.txt:90,126,142-143` ("SMOKE RESULT: PASS"); `export_model_pytorch.py:491-494`.
- [SOLID] `b5c48h3tfr` is trainable but unplayable (non-SwiGLU FFN refused by all backends) — do not use it anywhere.
  verify: `cpp/neuralnet/cudaandrocmbackend.inc:3307-3308`; `smoke-297952.txt` (exit 134, "Non-SwiGLU transformer FFN is not yet supported in CUDA backend").

## 1. GPU / CPU split — why the 24-CPU cap, not the GPU, is the binding constraint

Paper regime (background): 16→24 V100 self-play : 2 gating : 1 training (l.603), i.e. 16–24× more GPU
on self-play than training; upstream docs say 4–40×. On a *synchronous* single-node loop this ratio is
not a GPU-allocation decision at all: the GPU is time-shared and the ratio is enforced by data
accounting — `train.py -max-train-bucket-per-new-data 8` lets each new row be trained on at most 8 times
(`train.py:121,1256`; loop default `synchronous_loop.sh:60`), and `-max-train-bucket-size 500000` caps
a cycle's training (`:64`). Training can never outrun self-play; it can only idle.
- [SOLID] The selfplay:train balance is set by `MAX_TRAIN_PER_DATA`/`MAX_TRAIN_SAMPLES_PER_CYCLE`/`NUM_GAMES_PER_CYCLE`, not by GPU count.
  verify: `synchronous_loop.sh:57-66,109`; `train.py:1440-1451` (`-stop-when-train-bucket-limited` exits when the bucket drains).
- [PRELIMINARY] With `b7c96h3tfrs` (~8e5 parameters: 7 × (4·96² + 3·96·256) ≈ 7.7e5 trunk + heads) a B200 is
  still starved by NN inference of this size; self-play throughput is bounded by `numGameThreads` × 1 search thread,
  i.e. by the 18 CPU game threads, and training a batch of 128 at pos_len 9 (81 tokens) is ms-scale.
  Consequence: a second GPU adds nothing until the model is ≥ `b14c192h6tfrs` or CPU is co-scaled.
  verify: measured in task `selfplay_stage` (games/h, GPU util via `nvidia-smi dmon`) and `train_stage` (samples/s); claim `c09`.
- [SOLID] Cluster state at design time: my footprint gpus=1 cpus=16; b200 `free_gpus=2/128`, b300 `0/8`
  (gb301 reserved until 2026-09-04 15:00); a 2-GPU request projected a multi-week wait on 2026-09-03.
  verify: `the compute-budget skill check (mission.json policyCheck)` output 2026-09-03T21:49:50-04:00; `scontrol show reservation`; `docs/cluster-manual.md` §6.

Design: **one job, one GPU, 24 CPUs, all five stages sequential.** GPU is shared trivially (one
process at a time). `--mem=120G` (shuffle buckets + train prefetch; `/dev/shm` unused).
Split of the 24 CPUs per stage (only one stage runs at a time, so each stage may use the whole budget):

| stage | OS threads / processes | how | evidence |
|---|---|---|---|
| selfplay | 18 game + 1 nnServer + 1 dataWrite + 1 modelLoad + 1 main = 22 (+2 transient at net switch) | `numGameThreads=18`, `numSearchThreads=1`, `numNNServerThreadsPerModel=1` | `selfplay.cpp:360-364`, `setup.cpp:194,203`, `selfplaymanager.cpp:156` |
| gatekeeper | 20 game + 2 nnServer (2 models) + 1 main = 23 | `numGameThreads=20` | `gatekeeper.cpp:551-552` |
| shuffle | 8 worker processes | `-num-processes 8` | `synchronous_loop.sh:58`, `shuffle.py:791` |
| train | 1 process, `OMP_NUM_THREADS=4`, prefetch depth 1 | env var + `-data-prefetch-depth` default | `train.py:126`; obligation `o11` |
| export | 1 process | — | — |
- [SOLID] Shipped defaults (`numGameThreads=128`) would spawn ~132 threads and violate the cap.
  verify: `selfplay1_maxsize9.cfg:84`; arithmetic in `audit_loop_scripts_configs.md` §D.
- [HOLE] Whether the 20 % policy is per job or summed over my concurrent jobs is not written down; the check
  script sums (`my jobs: cpus=16`). Design assumes the *sum* ≤ 24, so no second concurrent GPU job.
  verify: the compute-budget skill `check.sh` (path: mission.json `policyCheck`) semantics; ask the human before any 2-job layout.

## 2. Starting configuration and scaling path

| phase | model | GPUs | knobs (mission `synchronous_loop_9x9.sh`) | exit criterion |
|---|---|---|---|---|
| S0 env_build (PASSED, job 298018) | random-init b7c96h3tfrs | 1 | `katago runtests`, `benchmark -boardsize 9`, torch fwd/bwd | `SMOKE RESULT: PASS` + `cuobjdump` shows sm_100 (or JIT accepted) |
| S1 tiny export + cfg | b7c96h3tfrs | 1 | export → block-kind scan → benchmark with mission cfg | claims c03, c04 |
| S2 loop smoke | b7c96h3tfrs | 1 | NUM_GAMES_PER_CYCLE 20, SHUFFLE_MINROWS 200, KEEPROWS 5000, samples-per-epoch 2000, batch 32, 1 cycle | c07; then kill/resume test c08 |
| P1 production-1 | b7c96h3tfrs | 1 | NUM_GAMES_PER_CYCLE 500, MINROWS 10000, KEEPROWS 300000, TAPER 5000, samples-per-epoch 20000, MAX_TRAIN_PER_DATA 8, batch 128, USEGATING 1 | c13 (≥2 acceptances), c14 (≥60 % vs first net) |
| P2 scale_up | b8c96h3tfrs or b14c192h6tfrs | 1→2 | same loop; 2nd GPU only via `numNNServerThreadsPerModel=2` + `cudaDeviceToUseModel0Thread{0,1}` and `train.py -multi-gpus 0,1` | c16 |
- [PRELIMINARY] P1 knob scaling: upstream defaults assume mixed sizes up to 19x19 (~100+ rows/game); at 9x9
  ~22 rows/game (`play.cpp:1143`, `trainingwrite.cpp:1206-1251`), so 500 games ≈ 11k rows/cycle and
  `samples-per-epoch` is scaled down ×5 to keep ≥1 epoch per cycle within the ×8 bucket.
  verify: rows/game measured in S2 (`codes/eval/rows_per_game.py`), then knobs re-derived; claim `c10`.
- [FUTURE] Asynchronous layout (selfplay and train as separate concurrent processes) is how upstream
  reaches 4–40×; it needs two jobs or a CPU/GPU split inside one job and is deferred to P2.
  verify: not applicable yet; revisit with measured GPU utilisation from P1.
- [SOLID] Family choice: `tf` (interleaved, SwiGLU `ffnsg` only) for all phases; `nbt` fused family is exportable too
  (`export_model_pytorch.py:495-502`) but is a `[FUTURE]` comparison (obligation `o07`); `ffng` configs are excluded (o18 discharged).
  verify: `modelconfigs.py:1886-1942` registration list; `model_pytorch.py:1958-1977`.

## 3. 9x9 enforcement — five keys, changed together

| # | key / flag | ships as | mission | where enforced |
|---|---|---|---|---|
| 1 | `bSizes` / `bSizeRelProbs` | `7,8,9` / `1,1,8` | `9` / `1` | `codes/cfg/selfplay_9x9.cfg`, `gatekeeper_9x9.cfg` |
| 2 | `allowRectangleProb` | `0.50` | `0` | same (half the games would be rectangles otherwise) |
| 3 | `dataBoardLen` | `19` (`selfplay1_maxsize9.cfg:16`) | `9` | selfplay cfg |
| 4 | `train.py -pos-len` | `19` hard-coded (`train.sh:88`) | `9` | mission `codes/loop/train_9x9.sh` |
| 5 | export `pos_len` | `load_model.py:62` default 19 | leave | benign: RoPE/score buffers non-persistent (`model_pytorch.py:2170-2171,2770-2784`) |
- [SOLID] 3 and 4 must be equal or `data_processing_pytorch.py:91` asserts (loud). Leaving *both* at 19 is
  silent and trains a 361-token model on 81 real tokens: attention cost (361/81)² ≈ 20×, score head 842 vs 282 bins.
  verify: `audit_paper_code_map.md` §10; executed check = task `paper_code_map_training` (npz row = 2145 B) and c05.
- [SOLID] Data at different `dataBoardLen` cannot be shuffled together — the switch happens before any data exists.
  verify: `selfplay1_maxsize9.cfg:10-14` comment; `shuffle.py` has no re-shaping.
- [SOLID] `chosenMoveTemperatureHalflife = 19` stays 19: `searchhelpers.cpp:541-545` rescales by 19/√area → 9 turns at 9x9.
  verify: cited lines; do not "fix" it.
- [PRELIMINARY] Side effects at 9x9 accepted as-is: komi σ scaled to 0.474 (`playutils.cpp:42`), handicap silently
  off (`playutils.cpp:10-22`), value-head gpool collinear (`model_pytorch.py:534-540`). None blocks training.
  verify: probe in task `paper_code_map_training` (pool2 = −0.5·pool1, pool3 = 0.15·pool1 at a full 9x9 mask).
- Acceptance test for this section: every SGF has `SZ[9]` (claim c04).

## 4. Checkpoint / resume under the 3-day walltime

Wrapper `codes/loop/loop.sbatch`: `#!/bin/bash -l`, `--time=2-23:30:00`, `--gres=gpu:1`, `--cpus-per-task=24`,
`--mem=120G`, output on `/scratch`, resubmits itself first (`sbatch --dependency=afterany:$SLURM_JOB_ID`)
so the chain continues after a kill or a drain; `compute-budget/check.sh` before every `sbatch`.
Per-stage idempotency the wrapper relies on:

| stage | on kill | mission action |
|---|---|---|
| gatekeeper | restarts candidate from scratch; returns 0 when nothing to test | none |
| selfplay | completed `.npz` kept (atomic rename `trainingwrite.cpp:1093-1096`); in-RAM ≤10k rows lost; game counter restarts | accept loss |
| shuffle | `.tmp` dir never promoted; `train.py:1210` skips it | wrapper deletes stale `shuffleddata/*.tmp` |
| train | auto-resume from `checkpoint.ckpt` (`train.py:780-796`), config from checkpoint (`:850`), shuffle order in train_state | none |
| export | **rm-before-mv window** (`export_model_for_selfplay.sh:89` vs `:108`) can orphan `<NAME>.exported` | mission copy moves `rm` after `mv`; wrapper removes `*.exported` whose target is missing |
- [SOLID] The upstream export ordering is a real data-loss hazard.
  verify: cited lines; executed check = c08 (kill mid-export, resume, no orphan).
- [SOLID] `synchronous_loop.sh` is `bash -eu -o pipefail`: any stage error kills the loop and the job ends early;
  the resubmit chain restarts it, so a *deterministic* failure (e.g. export refusal, §8) would loop forever.
  verify: `synchronous_loop.sh:1-2`; wrapper counts consecutive failures in `BASEDIR/.failcount` and stops at 3 (alignment §2).

## 5. Scratch budget (group at 37.80 / 40 TB = 94 %)

| item | size basis | P1 estimate |
|---|---|---|
| selfplay rows | 2145 B/row × 0.12 compressed × ~22 rows/game ≈ 5.7 KB/game | 1e6 games ≈ 5.7 GB (+ SGFs ≈ 1–2 KB/game) |
| shuffleddata | ≤ keep-target-rows × 2145 × 0.12 per cycle; newest 3 kept (`cleanup_old_dirs.py:22-24`) | 300k rows → 77 MB × 3 |
| train checkpoints | ~8e5 params × (weights + momentum) ≈ 6 MB; 4 short-term + 1 long-term / 12 h | < 1 GB / month even at b14c192 (~50 MB each) |
| models / modelstobetested / rejectedmodels | model.bin.gz + model.ckpt + metadata per export, never pruned | ~2 MB × cycles |
| `scripts/dated/<ts>` | copy of `python/` + `katago` binary per loop (re)start | ~0.1 GB × restarts |
- [PRELIMINARY] Total well under 50 GB for P1; hard cap **200 GB** on `BASEDIR` enforced by the wrapper
  (`du -sb` before each cycle), pruning `longterm_checkpoints` to 6 and `rejectedmodels` to 10.
  verify: `codes/eval/rows_per_game.py` after S2 gives bytes/game; `du -sb` logged per cycle; claims c10, c11.
- [SOLID] Nothing upstream prunes `selfplay/*/tdata`; growth is monotonic.
  verify: grep of `python/selfplay/*.sh` and `cleanup_old_dirs.py` (audit §F).
- [HOLE] The env job's `pip install` cache and the KataGo build (~GBs) sit under the same scratch root but
  outside `BASEDIR`; they are not counted by the cap. verify: `du -sh /scratch/…/ktg-train/{venv,build}` after env_build.

## 6. Smoke-first ordering (topological, one packet per row)

1. `env_build` (PASSED, job 298018; ledger promotion owned by its worker) → 2. `tiny_model_export_smoke` + `cfg_9x9_override` (parallel) →
3. `synchronous_loop_smoke` (+ `loop_resume_under_walltime` kill/resume test) → 4. `data_budget` (measure) →
5. P1: `selfplay_stage`, `shuffle_stage`, `train_stage`, `export_stage`, `gatekeeper_stage` (one loop, five nodes) →
6. `eval_improvement` → 7. `scale_up`. Code-reading nodes (`paper_code_map_*`) are promoted to solid by two probes
that can run as soon as env_build lands.
- [SOLID] READY now: `env_build`, `cfg_9x9_override`, `paper_code_map_search`, `paper_code_map_training`,
  `data_budget` (constants half), and `tiny_model_export_smoke` as soon as env_build reports PASS.
  verify: `logic.md` predecessor edges; task files in `../tasks/<node>/implementation.md`.

## 7. Evaluation criterion (replaces the paper's 19x19 Elo)

- c13: ≥ 2 gatekeeper acceptances after the first exported net (`numGamesPerGating` 200, `-required-candidate-win-prop` 0.5, `maxVisits` 150).
- c14: `katago match`, 9x9, komi 7, `maxVisits` 150, 400 games, colours alternated: latest accepted net vs first exported net wins ≥ 60 %
  (SE 0.025 at n = 400; 95 % CI excludes 0.5; ≈ +70 Elo).
- [SOLID] Gating alone is a weak filter: at equal strength P(≥100/200) ≈ 0.53.
  verify: binomial arithmetic; hence the separate 400-game match.
- [HOLE] No external 9x9 reference net is available on the cluster; strength is only relative to the run's own first net.
  verify: none possible offline; `[FUTURE]` compare against a public KataGo 9x9-capable net if one is downloaded (acquire stage).

## 8. Top risks — detection signature → response

| # | risk | signature | response |
|---|---|---|---|
| R1 | no sm_100 SASS (`CMakeLists.txt:761`) — **closed**: `codes/env/cmake-sm100.diff` applied at env_build stage 2b, `smoke-298018.txt:35` count = 2 | `cuobjdump --list-elf katago \| grep -c sm_100` = 0 | re-apply the diff after any re-clone |
| R2 | pos_len 19 left in place | npz row 7675 B not 2145; `train.py` log `pos_len 19`; attention memory ~20× | fix §3 keys before any data; discard data |
| R3 | attention-logit export refusal | export stage exit ≠ 0 with bound > 2.5e4 (`export_model_pytorch.py:42`); loop dies each cycle | enable `-attn-logit-penalty-cap` in train wrapper; record fail row |
| R4 | CPU cap breach | `ps -o nlwp -p <pid>` > 24; `seff` CPU > 24 cores | thread table §1 |
| R5 | scratch full (group) | `quotas.py` ≥ 99 %; `OSError: No space left` in shuffle | wrapper cap + prune; stop loop |
| R6 | queue wait / b300 reserved | `PENDING (Priority|ReqNodeNotAvail)` > 30 min | 1 GPU on b200; never request 2 GPUs before P2 |
| R7 | random-net bootstrap | `selfplay/random/` appears; cycle 1 trains on random-play rows | accepted (assumption a10); document |
| R8 | export kill-window orphan | `torchmodels_toexport/<NAME>.exported` with no `models/<NAME>` | wrapper cleanup + reordered mission exporter |
| R9 | value-head gpool collinearity | probe: pool2/pool1 = −0.5 exactly | accepted; no code change |
| R10 | `torch.compile` first-epoch stall | minutes of 100 % CPU at epoch start, no GPU util | expected; `-no-compile` only if it exceeds 15 min |
| R11 | RoPE + `rootNumSymmetriesToSample=4` inconsistency | root value variance across symmetries in `logSearchInfo` | `[FUTURE]` measure; set to 1 if harmful |
| R13 | non-SwiGLU config slips into MODELKIND | NN server thread fails at startup: "Non-SwiGLU transformer FFN is not yet supported" | only `*tfrs`/`*tflrs` names (ffnsg) allowed; wrapper asserts MODELKIND ends in `s` |
| R12 | deterministic stage failure + resubmit chain | same error in 3 consecutive job logs | `.failcount` stop at 3, escalate (alignment §2) |

## 9. Decisions recorded (owner: brain design)

- Code-first: v1.18.2 is authoritative; paper values (lr 6e-5, c_value 1.5, S = 421, 300-node gating) are not targets. [SOLID] verify: assumption `a09`; `derivation.md` §3.
- USEGATING = 1 for S2/P1 (needed to count acceptances); revisit at P2. [PRELIMINARY] verify: obligation `o16`.
- Keep gpool constants (14, 0.1) for C++ compatibility; accept 9x9 redundancy. [SOLID] verify: obligation `o14` discharged by node `head_gpool_degeneracy_9x9`.
- CUDA backend, cuDNN 9.x wheel (SDPA path on since `CUDNN_VERSION >= 8903`, `cudabackend.cpp:13`); TensorRT deferred. [SOLID] verify: assumption `a08`, obligation `o05`.
- Random-net bootstrap accepted. [PRELIMINARY] verify: obligation `o10`, assumption `a10`.
- Smoke/first model = `b7c96h3tfrs`, not `b5c48h3tfr` (unservable). [SOLID] verify: `cudaandrocmbackend.inc:3307-3308`; jobs 297952 (FAILED 1:0) vs 298018 (COMPLETED 0:0), `sacct`; assumption `a06`, obligation `o18` discharged.
