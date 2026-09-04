# Implementation — `paper_code_map_training`

## 0. Header

**Task ID:** `paper_code_map_training`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::loss_targets_metrics`, `::train_optimizer_schedule`, `::transformer_trunk_b7c96h3tfrs`, `::head_gpool_degeneracy_9x9`, `::data_format_pos_len`, `::training_window_shuffle`, `::train_resume_semantics`
**Language:** Python (PyTorch) — probe script + a real `train.py` run
**Method class:** simulation (executed probe promoting seven read-only code-map nodes from `preliminary` to `solid`)
**Node status:** this file is a task, not a DAG node. It carries no node of its own; it promotes the seven listed above.

## 1. Claim

> Instantiated at `pos_len = 9`, the `b7c96h3tfrs` trunk contains no global-pooling block, its value-head pooled vector is exactly collinear, a training row occupies 2145 bytes, and `train.py` resumes from `checkpoint.ckpt` with its row/sample counters continuing (claims `c05_pos_len_9_pipeline`, `c08_resume_no_loss`, the training half of `c15_paper_ideas_in_code`).

## 2. Success Criterion

- **Needed evidence type:** `numerical_simulation`
- **Done when:** the four assertions below all pass in one recorded GPU-node run.
- **Where the run happens (wave 2):** leg D2 of the `synchronous_loop_smoke` job (`codes/loop/smoke_loop.sbatch`) — **no separate GPU job for this packet.** Assertion 3 reads a REAL `dataBoardLen = 9` npz written by that job's cycle-1 selfplay (`runs/smoke/selfplay/random/tdata/*.npz`), which also settles the measurement half of `o02`; the resume half of assertion 4 is additionally observed on the smoke's own cycle-2 `train.py` start (S6 of that task).
- **Verification command:**
  `bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/eval/probe_train_9x9.sh`
  which sources `$KTG_ROOT/env.sh` and then runs `python codes/eval/probe_train_9x9.py`, asserting:
  1. **no trunk gpool** — `Model(modelconfigs.config_of_name["b7c96h3tfrs"], pos_len=9)`; `sum(1 for m in model.trunk.modules() if type(m).__name__ == "KataConvAndGPool") == 0`;
  2. **value-head gpool degeneracy** — feed `x` random `N=4, C=32, 9, 9` (`C = v1_num_channels`, `modelconfigs.py:1024`), `mask` all-ones, `mask_sum_hw = 81`; `max|pool2 + 0.5*pool1| < 1e-5` and `max|pool3 - 0.15*pool1| < 1e-5`;
  3. **row bytes** — for a real `tdata/*.npz` at `dataBoardLen = 9`, `sum(a.dtype.itemsize * prod(a.shape[1:]) for a in the 7 written arrays) == 2145` (unchanged by the model switch — see §10 and §11);
  4. **resume** — run `train.py -pos-len 9 -model-kind b7c96h3tfrs -batch-size 32 -samples-per-epoch 2048` for 2 epochs on synthetic data, `SIGKILL` it, re-run the identical command, and assert the reloaded `checkpoint.ckpt`'s `train_state["global_step_samples"]` is `>= ` the pre-kill value and strictly increases afterwards, and `train_state["total_num_data_rows"]` is unchanged for the same data dir.
- **Measured tolerance / metric:** (1) count `== 0`; (2) both residuals `< 1e-5`; (3) exact equality `== 2145`; (4) `global_step_samples_after_resume > global_step_samples_at_kill` and no re-initialisation message (`"Initializing new model!"`, `train.py:798`) in the resumed log. Exit 0 only if all four hold.
- **Open obligations before start:** the smoke job's cycle 1 must have written `runs/smoke/selfplay/random/tdata/*.npz` (assertion 3's real npz; `o02` measurement half), `o11_torch_threads_cap` (the driver exports `OMP_NUM_THREADS=MKL_NUM_THREADS=4`; the smoke's `stage_monitor.sh` records the train PID's `nlwp`).
- **Reduction-to-baseline test:** NA

Assertions 1, 2 and 4 need no self-play data (4 runs on synthetic npz written by the probe in the shuffled-data layout: `<datadir>/train/data0.npz` plus `<datadir>/train.json` carrying `{"range": [start, end]}`, `python/train.py:1226,1240-1242,1273`, matching `python/shuffle.py:1330-1335`).

## 3. Motivation

`audit_paper_code_map.md` divergence summary flags two HIGH items on the training side: `dataBoardLen`/`-pos-len` left at 19 (a silent ~20x attention-FLOP waste) and "trunk has no gpool (heads only)". Both are currently `preliminary` — read, never executed. `head_gpool_degeneracy_9x9` is a concept-advance node and its whole content is an algebraic claim that a 3-line numerical check settles. This file is a probe task; it does not itself appear in the DAG.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §3 trunk-config fields (amended to `b7c96h3tfrs`), §4 trainer flags, §7 loss coefficients, §8 hard-coded constants |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §1 rows 5-7, 12-14; §2 loss-weight table; §4 bytes/row |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | the seven nodes (roots, except `loss_targets_metrics` and `head_gpool_degeneracy_9x9`, whose sole predecessor is `transformer_trunk_b7c96h3tfrs`) and their edges into `cfg_9x9_override`, `train_stage`, `shuffle_stage`, `select_transformer_ladder` |
| implementation_plan | `results/ktg/paper_1902.10565/decomposition/implementation_plan_python.md` | trainer flags and optimizer defaults |
| ref | `results/ktg/paper_1902.10565/decomposition/ref.md` | tex anchors l.398-404, l.547-593, l.635-639 |
| assumptions | `results/ktg/paper_1902.10565/decomposition/assumptions.md` | `a05_9x9_only`, `a06_tf_family`, `a09_code_first` |
| claims | `results/ktg/paper_1902.10565/decomposition/claims.md` | `c05`, `c08`, `c12`, `c15` |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | `o02`, `o11`, `o14` (discharged), `o15` |
| result_seed | `results/ktg/paper_1902.10565/decomposition/result_seed.md` | initial status and dependencies |

**Upstream task outputs:** `tasks/env_build/implementation.md` (venv + torch); `tasks/cfg_9x9_override/implementation.md` (for assertion 3's real npz).
**Evidence packs:** `evidence/decomposition/audit_paper_code_map.md` §3, §5, §9, §10; `audit_loop_scripts_configs.md` §B, §F.

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- One cluster only: training-side nodes. Search-side nodes are `paper_code_map_search`.
- Export `OMP_NUM_THREADS=4` and `MKL_NUM_THREADS=4` before every python leg (`o11_torch_threads_cap`).
- Submit nothing: the probes run as leg D2 of `tasks/synchronous_loop_smoke/implementation.md` § 8 (one 1-GPU b200 job for the smoke and both probe packets). Stage candidate rows in `evidence/smoke/candidate_rows.json` under the group `r_smoke_probe_training`; the validator promotes the seven nodes from that job's artifacts.
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference paper | `ref-paper/arxiv-1902.10565/` |
| Reference code | `ref-code/lightvector-KataGo/` |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/eval/` |
| Plot / figure output | `results/ktg/paper_1902.10565/plots/` |
| Loop notes | `results/ktg/paper_1902.10565/loop_note/` |
| Progress dir | `progress/paper_1902.10565/paper_code_map_training/` |
| Git branch | `main` (az) |
| Scratch workdir `$W` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/smoke_probe/train` (inside the smoke job; real npz from `…/runs/smoke/selfplay/random/tdata/`) |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/eval/
├── probe_train_9x9.py     # nodes transformer_trunk_b7c96h3tfrs, head_gpool_degeneracy_9x9, data_format_pos_len - asserts 1-3
├── probe_resume_9x9.sh    # nodes train_resume_semantics, train_optimizer_schedule - assert 4 (2 epochs, kill, resume)
└── probe_train_9x9.sh     # driver: sources env.sh, caps threads, runs both, exits non-zero on any failure
```

## 8. Phase Plan

### Phase 1 - `architecture + row layout`
- **Nodes:** `transformer_trunk_b7c96h3tfrs`, `head_gpool_degeneracy_9x9`, `data_format_pos_len`, `loss_targets_metrics`
- **Files:** `probe_train_9x9.py`
- **Test:** assertions 1, 2, 3 of §2 pass; additionally `metrics_pytorch.scorebelief_len == 282` at `pos_len = 9` (`python/katago/train/metrics_pytorch.py:35`).
- **Estimate:** `1.0` h

### Phase 2 - `train + kill + resume`
- **Nodes:** `train_resume_semantics`, `train_optimizer_schedule`, `training_window_shuffle`
- **Files:** `probe_resume_9x9.sh`
- **Test:** assertion 4 of §2; and `shuffle.py`'s `compute_desired_num_rows` (`python/shuffle.py:414-435`) reproduces the paper's `N_window` (l.638) to `1e-9` relative when `taper_window_scale == min_rows`.
- **Estimate:** `1.5` h

## 9. Quick-Win Path

1. `Phase 1` — leg D2 of the smoke job; model instantiation and the gpool algebra take seconds; assertion 3 on the job's own cycle-1 npz.
2. `Phase 2` — same leg: synthetic npz, 2 epochs at batch 32, kill, resume (`probe_resume_9x9.sh`).
3. **Smoke check:** the resumed log prints the checkpoint path rather than `Initializing new model!`.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| `-model-kind` | `b7c96h3tfrs` | `python/katago/train/modelconfigs.py:1008-1029`; registered at `:1887`. Fixed by node `select_transformer_ladder` (start and first production model; ladder b7 -> b8 `:1889` -> b14 `:1894`) |
| `block_kind` | `7 x [attnrope, ffnsg]` | `modelconfigs.py:1021`; trunk gpool exists only for kinds ending in `gpool` (`model_pytorch.py:3157-3160`), so the count stays 0 |
| trunk / mid / FFN channels, heads | `96` / `96` / `256`, `3` (kv `3`) | `modelconfigs.py:1015,1016,1018,1019-1020`; head dim `96/3 = 32`, satisfies `q_head_dim % 4 == 0` (`model_pytorch.py:2112`) and `rope_theta 100 > 2*pos_len` (`:2167-2168`) |
| `p1` / `g1` / `v1` / `sbv2` / `v2_size` | `32` / `32` / `32` / `48` / `64` | `modelconfigs.py:1022-1027`; `v1_num_channels = 32` is the gpool input width in assertion 2 |
| `predict_q_values` | **not set** | absent from `modelconfigs.py:1008-1029`: 6 policy outputs (`model_pytorch.py:2621-2626`) and q losses zeroed (`metrics_pytorch.py:838-841`). It does **not** change the npz row size |
| `-pos-len` | `9` | `train.py:79` (required); upstream `python/selfplay/train.sh:88` hard-codes 19 -> mission wrapper overrides |
| `mask_sum_hw` | `81` -> offset `sqrt(81) - 14 = -5` | `model_pytorch.py:534` |
| expected `pool2/pool1` | `-5/10 = -0.5` | `model_pytorch.py:539` |
| expected `pool3/pool1` | `25/100 - 0.1 = 0.15` | `model_pytorch.py:540` (`0.1 = sigma^2/100`, paper l.404) |
| row bytes at `pos_len 9` | `242+76+328+320+282+405+492 = 2145` | `cpp/dataio/trainingwrite.cpp:292-299`; `qValueTargetsNCMove` is written **unconditionally** (`:880-882`; only `metadataInputNC` is guarded, `:883`), so the row is 2145 regardless of `predict_q_values`. The 1653 "required subtotal" would apply only to a writer that omitted q values, which v1.18.2 never does. Cross-check the 19x19 constants `5503`/`2172` at `python/shuffle.py:39-40` |
| `scorebelief_len` | `2*(81+60) = 282` | `metrics_pytorch.py:35`, `EXTRA_SCORE_DISTR_RADIUS = 60` (`model_pytorch.py:26`) |
| `-batch-size` | `32` | probe-only; loop default is 128 (`python/selfplay/synchronous_loop.sh:62`) |
| `-samples-per-epoch` | `2048` | probe-only; loop default 100000 (`synchronous_loop.sh:59`) |
| optimizer | SGD `lr=1.0`, `momentum=0.9`, Lookahead `k=6`, `alpha=0.5` | `train.py:844,942`, `:97-98`; paper l.77-80 |
| per-sample lr | `3e-5 * effective_lr_scale`, warmup 1/20 -> 1 over 2M samples | `train.py:1094`, `:1059-1079` (paper l.635-636 uses 6e-5) |
| `OMP_NUM_THREADS` / `MKL_NUM_THREADS` | `4` | `o11_torch_threads_cap`; 24-CPU cap (`compute-budget/SKILL.md`) |
| `-data-prefetch-depth` | default `1` | `train.py:126`; do not raise |
| checkpoint path | `<traindir>/checkpoint.ckpt` | `train.py:573-574`, existence check `:780`, load `:796`, keep 4 (`:578`) |
| resume counters | `train_state["global_step_samples"]`, `["total_num_data_rows"]` | `train.py:976`, `:979-980`; the latter is refreshed from `train.json` `range[1]` at `:1242` |
| `--gres` / `--cpus-per-task` / `--mem` | `gpu:1` / `24` / `64G` | inherited from the smoke job (`tasks/synchronous_loop_smoke` § 10); no job of its own |

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| Confusing the head gpool with a trunk gpool | assertion 1 finds `KataConvAndGPool` instances | scope the module walk to `model.trunk` only; the policy head (`model_pytorch.py:2647`) and value head (`:2745`) gpools are unconditional and expected |
| `mask_sum_hw` not exactly 81 | residuals ~1e-3 instead of <1e-5 | build the mask as all-ones float32 and pass `mask_sum_hw = 81.0` explicitly; float32 mean of 81 ones is exact |
| Expecting 1653 B/row because the model has no `predict_q_values` | assertion 3 written against the wrong constant and failing at `2145` | the model flag and the writer are independent: `b7c96h3tfrs` sets no `predict_q_values` (`modelconfigs.py:1008-1029`) so the *model* zeroes q losses (`metrics_pytorch.py:838-841`), but selfplay **always** writes `qValueTargetsNCMove` (`trainingwrite.cpp:292-299`, `:880-882`; `hasMetadataInput=false` `:1030`). Assert `== 2145` and record the per-array breakdown |
| Resume silently reinitialises | log line `Initializing new model!` (`train.py:798`) and `global_step_samples` back to 0 | assertion 4 greps for that line and fails on it |
| `-model-kind` ignored on resume | model kind comes from the checkpoint (`train.py:850`), not the flag | expected; the probe asserts the reloaded config name equals `b7c96h3tfrs`. The same fact makes every ladder step a **fresh run**, never a resume (node `select_transformer_ladder`) |
| Stray `checkpoint_prev*.ckpt` without `checkpoint.ckpt` | `Exception: ... something is wrong with the training dir` (`train.py:783-784`) | the probe uses a fresh `$W/train/<name>` per run |
| torch grabs all 128 cores | `ps -o nlwp` > 24 on the train PID | export the two thread env vars in `probe_train_9x9.sh` before python starts |
| Attention-logit export guard trips later | export stage exits non-zero, `compute_attn_logit_dataless_bounds` (`model_pytorch.py:3010`) over `2.5e4` | out of scope here; recorded as `o15_attn_logit_export_guard` for `export_stage` |

## 12. Current State

- `[SOLID]` `b7c96h3tfrs` instantiates and trains **in PyTorch** at `pos_len = 9` on a B200: `[OK] torch cuda forward/backward (b7c96h3tfrs, pos_len 9)` with a finite non-zero gradient norm and 825837 parameters — evidence `results/ktg/paper_1902.10565/evidence/env/smoke.txt`. Node `env_build` is `solid` (result row `env-toolchain-b200`).
- `[PRELIMINARY]` All seven nodes are `preliminary`; every constant is read at a `path:line` in `evidence/decomposition/audit_paper_code_map.md`, nothing is executed.
- `[PRELIMINARY]` The gpool collinearity (`pool2 = -0.5*pool1`, `pool3 = 0.15*pool1` at `mask_sum_hw = 81`) is hand-derived from `model_pytorch.py:534,539-540`; assertion 2 is what promotes it.
- `[PRELIMINARY]` `2145 B/row` is arithmetic over `trainingwrite.cpp:292-299` plus the unconditional q-value write at `:880-882`; no npz at `dataBoardLen = 9` exists yet.
- `[OPEN]` `o02_databoardlen_poslen_9` — assertion 3 runs on the smoke job's real cycle-1 npz (`runs/smoke/selfplay/random/tdata/*.npz`); until that job runs, nothing here is executed. The wiring half of `o02` (a pre-shuffle guard in the loop copy, `codes/eval/check_pos_len_npz.py`) stays with `shuffle_stage`.
- `[OPEN]` `o11_torch_threads_cap` — closes with a recorded `ps -o nlwp` <= 24 on the train PID.
- `[OPEN]` `training_window_shuffle` is only partially promoted here (the `N_window` algebra); the real window behaviour needs `shuffle_stage` over actual selfplay dirs.
- `[OPEN]` `loss_targets_metrics` is promoted only to "all terms finite and parametric in `pos_len`"; the loss-decrease claim `c12_loss_decreases` belongs to `train_stage`.
- `[SOLID]` Model selection is settled outside this probe: node `engine_ffn_swiglu_constraint` (`solid`) holds the rule that every C++ backend refuses a non-SwiGLU transformer FFN (`cpp/neuralnet/cudaandrocmbackend.inc:3307-3308`), node `transformer_trunk_b7c96h3tfrs` holds the architecture, and node `select_transformer_ladder` holds the b7 -> b8 -> b14 progression with each step as a fresh run (`train.py:850`). `transformer_trunk_b5c48h3tfr` is superseded and is not a live node; `b5c48h3tfr` appears in the mission only as the negative fixture of `tiny_model_export_smoke`. `head_gpool_degeneracy_9x9` and the 2145 B row are config-independent.
- `[SOLID]` Wave-3 settlement map (2026-09-04, `tasks/production_chain_9x9` P-rows): `transformer_trunk_b7c96h3tfrs`, `head_gpool_degeneracy_9x9`, `data_format_pos_len`, `train_resume_semantics` are already `solid` (job 299259); `loss_targets_metrics` is executed by P3 (c12: every `metrics_train.json` term finite and `p0loss` at epoch 10 below epoch 1 -- the file is non-empty at 156 batches/epoch, unlike the smoke's 38); `train_optimizer_schedule`'s lr / weight-decay half by P3's production train log (`train.py:844,942,1059-1094` values as printed per epoch) beside the resume half already executed; `training_window_shuffle` by P2 (cycle-1 window = 25 000 rows, growth after the first acceptance per `shuffle.py:414-435`); o11 by P1's monitor (train `nlwp_max` <= 32 at `OMP_NUM_THREADS=4`). o02's wiring half is decided and landed by `tasks/wave3_prelaunch_repairs` R5, not here.

## 13. Forbidden Actions

- Never edit `ref-code/lightvector-KataGo/`; the probe imports `katago.train.*` through `PYTHONPATH` set by `env.sh`.
- Never set `dataBoardLen` and `-pos-len` independently — one obligation (`o02`); a mismatch is caught only by `python/katago/train/data_processing_pytorch.py:91`.
- Never call `train.py` through upstream `python/selfplay/train.sh` (it hard-codes `-pos-len 19` at `:88`).
- Never use an `ffng` (non-SwiGLU) config name for `MODELKIND` or `-model-kind` in this probe or in the loop; the single sanctioned use of `b5c48h3tfr` is the negative fixture inside `codes/eval/export_smoke.sh` (`tiny_model_export_smoke`).
- Never change `mask_sum_hw_sqrt_offset = 14.0` (`model_pytorch.py:505,534`) to "fix" the degeneracy — that forks the mirror and breaks the C++ backends' matching constants.
- Never run the probe without `OMP_NUM_THREADS`/`MKL_NUM_THREADS` <= 4, and never submit a separate job for it (it is leg D2 of the smoke job: 1 GPU, 24 CPUs).
- Never raise `-data-prefetch-depth` above its default 1.
- Never delete `$W/train/<name>` between the kill and the resume — the resume is the measurement.
- Never report the resume as passing on `global_step_samples` alone if `Initializing new model!` appears in the log.

## 14. Promise Tag

- **Promise format:** `<promise>paper_code_map_training GPOOL_COLLINEARITY_RESIDUAL WITHIN 1e-5 AND ROW_BYTES ==2145 AND TRUNK_GPOOL_COUNT ==0 AND RESUME_CONTINUES</promise>`
- **Required in commit body:** verbatim probe output (all four assertions with numbers), the pre-kill and post-resume `global_step_samples`, evidence path `evidence/smoke/probe_train.txt` (plus the smoke job id), claims `c05`/`c08`, evidence type `numerical_simulation`, and the node ids promoted.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions:
- Per-substage commit: Phase 1 and Phase 2 commit separately with their metrics.
- Joint progress file: `progress/paper_1902.10565/paper_code_map_training/progress.md`.
- Loop notes: `results/ktg/paper_1902.10565/loop_note/note_session_{id}_loop_{n}.md` before compaction.
- State-note sync: promotions go into `${RESEARCH_STATE}`; the SwiGLU rule is recorded there under node `engine_ffn_swiglu_constraint` and the model choice under `select_transformer_ladder`.

## 16. Termination Checklist

- [ ] Verification command ran and output is pasted.
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] All four metrics are within the thresholds in §2.
- [ ] Reduction-to-baseline test passed when relevant (NA).
- [ ] No `[BLOCKING]`, `[OPEN]`, or `[UNCHECKED]` markers remain for the nodes actually promoted (`training_window_shuffle` and `loss_targets_metrics` stay partial by design).
- [ ] No silent scope expansion: no search-side node touched here.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
