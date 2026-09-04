# Result seed — mission `ktg-train` (paper_arxiv-1902.10565)

Initial result-log entries, one row per claim in `claims.md` (`c01`…`c16`). Statuses use the
result-ledger vocabulary of `_common/contracts/research_admission_contract.md` (§Accepted Result
Schema): `checked`, `conditional`, `approximate`, `empirical`, `conjectural`, `refuted`,
`unchecked`, `existence_only`, plus the `[OPEN]` marker of `_common/contracts/markers.md`.

**Nothing in this table has been executed.** No mission job has produced evidence that has been
admitted here; every row is therefore `unchecked` (verification command fully specified, not yet
run) or `[OPEN]` (the claim is not yet a testable proposition). There are **no** `checked`,
`conditional`, `approximate`, `empirical`, `conjectural`, `refuted` or `existence_only` rows, and
none will exist until a verifier admits one. Status is advanced only by a ledger append that runs
the row's verification command — never by editing this view.

Artifact paths are relative to the repo root; `<node>` directories are created on first write.

| id | claim (short) | initial status | evidence type needed | dependency node | evidence artifact path |
|---|---|---|---|---|---|
| c01 | KataGo v1.18.2 CUDA build + torch 2.11.0+cu128 venv passes `runtests` and a `b5c48h3tfr` benchmark at `-boardsize 9` on a B200 node | `unchecked` | numerical simulation | `env_build` | `results/ktg/paper_1902.10565/evidence/env/smoke-<jobid>.txt` |
| c02 | The built binary either carries `sm_100` SASS or runs every kernel correctly via `compute_90` PTX JIT with no launch failures | `[OPEN]` | numerical simulation | `env_build` | `results/ktg/paper_1902.10565/evidence/env/cuobjdump_arch.txt` |
| c03 | A random-init `b5c48h3tfr` export contains only `transformer_attention_block` / `transformer_ffn_block`, is accepted by `desc.cpp`, and benchmarks > 0 visits/s at 9x9 | `unchecked` | numerical simulation | `tiny_model_export_smoke` | `results/ktg/paper_1902.10565/evidence/tiny_model_export_smoke/block_scan.txt` |
| c04 | With `bSizes=9` / `bSizeRelProbs=1` / `allowRectangleProb=0` every selfplay SGF carries `SZ[9]` | `unchecked` | numerical simulation | `cfg_9x9_override` | `results/ktg/paper_1902.10565/evidence/cfg_9x9_override/sgf_size_scan.txt` |
| c05 | With `dataBoardLen=9` and `-pos-len 9` one shuffle + one training epoch complete and the npz row size is 2145 B uncompressed | `unchecked` | numerical simulation | `shuffle_stage` (also `train_stage`, `data_format_pos_len`) | `results/ktg/paper_1902.10565/evidence/shuffle_stage/pos_len_9_run.txt` |
| c06 | Selfplay ≤24 OS threads at `numGameThreads=18`; gatekeeper ≤24 at `20`; train ≤24 with `OMP_NUM_THREADS=4` | `unchecked` | empirical measurement | `selfplay_search_params` (verified in `selfplay_stage`) | `results/ktg/paper_1902.10565/evidence/selfplay_stage/nlwp.txt` |
| c07 | One full loop cycle (gatekeeper → selfplay → shuffle → train → export) completes on 1 GPU with tiny knobs and leaves a loadable `model.bin.gz` | `unchecked` | numerical simulation | `synchronous_loop_smoke` | `results/ktg/paper_1902.10565/evidence/synchronous_loop_smoke/cycle1.txt` |
| c08 | Killing the loop mid-train and mid-export and resubmitting resumes with no lost npz and no orphan `*.exported` | `unchecked` | numerical simulation | `loop_resume_under_walltime` | `results/ktg/paper_1902.10565/evidence/loop_resume_under_walltime/kill_resume.txt` |
| c09 | Selfplay at production knobs sustains a recorded games/hour and moves/game on one B200; the selfplay:train ratio is re-derived from the measured train samples/s | `unchecked` | empirical measurement | `selfplay_stage` | `results/ktg/paper_1902.10565/evidence/selfplay_stage/rate.json` |
| c10 | Training rows per 9x9 game ∈ [12, 35] and on-disk bytes per game ≤ 10 KB at `pos_len 9` | `unchecked` | empirical measurement | `data_format_pos_len`, `playout_cap_randomization` (measured in `data_budget`) | `results/ktg/paper_1902.10565/evidence/data_budget/rows_per_game.json` |
| c11 | The whole run fits a 200 GB scratch budget: `du -sb BASEDIR` < 2.0e11 throughout, ≤4 short-term + ≤6 long-term checkpoints | `unchecked` | empirical measurement | `data_budget` | `results/ktg/paper_1902.10565/evidence/data_budget/du_timeline.txt` |
| c12 | Over the first 10 epochs every `metrics_train.json` term is finite and `p0loss` at epoch 10 < epoch 1 | `unchecked` | empirical measurement | `train_stage`, `loss_targets_metrics` | `results/ktg/paper_1902.10565/evidence/train_stage/metrics_train_first10.json` |
| c13 | The gatekeeper (200 games, win prop 0.5, 150 visits, 9x9) accepts ≥2 candidates after the first exported net | `unchecked` | empirical measurement | `gatekeeper_stage`, `gating_rule` | `results/ktg/paper_1902.10565/evidence/gatekeeper_stage/acceptances.txt` |
| c14 | In a 400-game 9x9 match (komi 7, 150 visits, colours alternated) the latest accepted net beats the first exported net with win rate ≥ 0.60, 95 % CI excluding 0.5 | `unchecked` | statistical inference | `eval_improvement` | `results/ktg/paper_1902.10565/evidence/eval_improvement/match_winrate.json` |
| c15 | v1.18.2 still implements the paper's playout cap randomization, forced root exploration + target pruning, auxiliary targets, score utility and lightweight gating under the cited keys; the CNN trunk, N_window formula and 19x19 evaluation are superseded | `unchecked` | literature grounding | `playout_cap_randomization`, `root_explore_and_target_pruning`, `loss_targets_metrics`, `score_utility_search` | `results/ktg/paper_1902.10565/evidence/decomposition/audit_paper_code_map.md` |
| c16 | A second configuration (`b7c96h3tfrs` / `b8c96h3tfrs`) trains and exports in the same loop within ≤2 GPUs and 24 CPUs, with selfplay games/hour within 2× of the smoke config | `unchecked` | numerical simulation | `scale_up` | `results/ktg/paper_1902.10565/evidence/scale_up/second_config.txt` |

## Why each row sits where it does

| id | note |
|---|---|
| c01 | A build job was submitted by another worker (Slurm 297952, gb205) before this decomposition was written; **no evidence file is on record here**, so the claim stays `unchecked`. It promotes to `checked` when `evidence/env/smoke-<jobid>.txt` exists, hashes, and reads `SMOKE RESULT: PASS` (`codes/env/env_build.sbatch:293-296`). |
| c02 | `[OPEN] sm100-or-jit` — the first branch is testable now (`cuobjdump --list-elf \| grep -c sm_100 > 0`, `codes/env/env_build.sbatch:216-221`), but the fallback branch ("runs correctly via `compute_90` PTX JIT") names no test that could fail. **Closes when** the claim is split into a testable pair: (a) `sm_100` count ≥1 after `codes/env/cmake-sm100.diff` is applied to `cpp/CMakeLists.txt:761`, or (b) a defined kernel-correctness run (`katago runtests` + one selfplay cycle) with a stated pass condition. Until then no status other than `[OPEN]` is admissible. |
| c03 | Carries `[OPEN] block-scan-false-positive` (the scan counts tokens across `@BIN@` float payloads, `export_model_pytorch.py:224-226`) and `[OPEN] smoke-model-mismatch` (`codes/env/env_build.sbatch:32` exports `b7c96h3tfrs`, the design fixes the smoke net at `b5c48h3tfr`). Neither blocks the measurement; both must be resolved before the row is `checked`. |
| c05 | Depends on `codes/cfg/selfplay_9x9.cfg` setting `dataBoardLen = 9` and `codes/loop/train_9x9.sh` passing `-pos-len 9` **together** (obligation `o02_databoardlen_poslen_9`); any `pos_len 19` data written before the switch must be discarded, or the assert at `python/katago/train/data_processing_pytorch.py:91` will fire. |
| c06 | The thread totals in `audit_loop_scripts_configs.md` §D are *computed* from `cpp/command/selfplay.cpp:360-364`, `cpp/program/setup.cpp:194,203` and `cpp/program/selfplaymanager.cpp:156`, not measured; `ps -o nlwp` on a live process is what turns them into `empirical`. |
| c09 | This claim has no target number — the measurement *is* the result. It becomes `empirical` once the rate is recorded; the derived selfplay:train ratio is a second, dependent statement and is not part of this row's admission. |
| c10 | The ≈22 rows/game expectation rests on assumption `a07_moves_per_game_80` (~80 moves per 9x9 game). If the measured moves/game differs materially, the [12, 35] band is re-derived rather than the claim refuted. |
| c11 | Carries `[OPEN] tdata-retention` (nothing upstream prunes `selfplay/<model>/tdata\|sgfs`) and `[OPEN] dated-archive-growth` (one `scripts/dated/<ts>` archive with a full `python/` copy and the `katago` binary per resubmit, `python/selfplay/synchronous_loop.sh:75-81`). Both must be closed before a multi-week chain can be claimed to fit 200 GB. |
| c12 | `p0loss` is the logged name: `metrics_pytorch.py:893` emits `p0loss_sum`, and `python/katago/train/metrics_logging.py:31-33` strips the `_sum` suffix before writing the JSON line to `metrics_train.json` (`train.py:1350`). |
| c13 | Cycle 1 produces no acceptance: the gatekeeper returns 0 immediately when `accepted-models-dir` is empty (`cpp/command/gatekeeper.cpp:399-402`). The count of ≥2 starts after the first exported net reaches `models/`. |
| c14 | Carries `[OPEN] draw-handling` (integer komi 7 permits draws; `match.cpp` has no gating-style half-point tally, unlike `gatekeeper.cpp:138`), `[OPEN] match-rules-randomization` (`match_example.cfg:82-86`) and `[OPEN] match-resignation-bias` (`match_example.cfg:75-77`). The win-rate estimator is not admissible until the draw convention is fixed. |
| c15 | Evidence already exists as the read-only code audit `evidence/decomposition/audit_paper_code_map.md` (evidence type: literature grounding, i.e. code reading, nothing executed). It stays `unchecked` because no verifier has run over it in this mission; it promotes to `conditional` at best — a code-reading claim cannot become `checked` on execution evidence it does not have. |
| c16 | Carries `[OPEN] production-knobs` — the production knob column in `implementation_plan_bash.md` is arithmetic from the *expected* rows/game, not from `c09`/`c10`. Also gated on assumption `a02_gpu_cap_start_at_1`: the second GPU is requested only after `c14` passes. |

## Assumptions every row is conditional on

`a01_single_node`, `a02_gpu_cap_start_at_1`, `a03_walltime_resume`, `a04_b200_fallback`,
`a05_9x9_only`, `a06_tf_family`, `a07_moves_per_game_80`, `a08_cuda_backend`, `a09_code_first`,
`a10_random_bootstrap_ok` (all `active` in `assumptions.md`). Any row promoted past `unchecked`
inherits these as `conditional` qualifiers unless the specific assumption is discharged first.

## Decomposition-level `[OPEN]` items not owned by a single claim

| marker | statement | closes when |
|---|---|---|
| `[SOLID] halflife-resolved` (convention.md §10 corrected to keep 19 in commit 3549a8c) | `convention.md` §10 lists `chosenMoveTemperatureHalflife = 9` as the mission value, but `cpp/search/searchhelpers.cpp:541-544` rescales by `19/sqrt(area)`, so the preset `19` already gives a 9-turn effective halflife at 9x9 | `convention.md` is amended via its ledger; the implementation plans follow the code and keep `19` |
| `[OPEN] chain-runaway` | `loop.sbatch` resubmits itself at job start; a job that dies immediately would chain forever | a `STOP`-file guard, a chain-depth cap and a minimum-runtime guard are coded and exercised once |
| `[OPEN] lr-scale-9x9` | no 9x9-specific `-lr-scale` is derived; `train.py:1094` + warmup `:1059-1079` defaults are used | the first 10 epochs' `p0loss` curve is on record and a scale is chosen or the default kept |
| `[OPEN] shuffle-window-alpha` | `shuffle.sh:44-45` hard-codes `-expand-window-per-row 0.4` and `-taper-window-exponent 0.65`, neither 9x9-derived | a measured rows/game feeds a recorded choice |
| `[OPEN] rope-symmetry-cost` | `selfplay1_maxsize9.cfg:149` samples 4 root symmetries, but RoPE attention is not rotation-equivariant | the cost is measured at 9x9 or the value is set to 1 with the decision recorded |
| `[OPEN] gpool-recenter` | whether re-centering the `14.0` / σ²=10 pooling constants (`model_pytorch.py:505,534,540`) is worth forking the C++ backends is not evaluated | deferred `[FUTURE]`; opens only if a measured head-capacity loss justifies it |
| `[OPEN] env-build-outcome` | the env build ran outside this decomposition and its smoke result is not on record | `evidence/env/smoke-<jobid>.txt` exists and reads `SMOKE RESULT: PASS` |
