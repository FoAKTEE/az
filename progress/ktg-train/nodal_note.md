# nodal_note — ktg-train (window: iterations 1–10, so far only iteration 1 / wave 0)

## 10-iter window

- **error-DB pass/fail counts** (`results/ledgers/error/paper_arxiv-1902.10565/trials.jsonl`, 4 rows total): `acquire/source_import` 2/2 pass (paper mirror sha-match, code mirror sha-match); `env_build/implementation` 1 fail (iter 1: `Non-SwiGLU transformer FFN is not yet supported`, `failure_mode=uncategorized_numerical`) → 1 pass (iter 2, job 298018, all 6 smoke steps). **3 pass / 1 fail**, one same-task retry (not a same-mode loop: root cause diagnosed and fixed between attempts — `cmake-sm100.diff` + model swap — so `crash-triage`'s 3-cycle rule never engaged).
- **`logic.md` node coverage delta**: 0 → 38 live nodes (pass-1 decomposition landed 26; two-seat review + reconciliation added `select_transformer_ladder`, `derive_cycle_knobs_9x9`, `verify_preemption_resume`, `loop_failure_circuit_breaker`, `bootstrap_accepted_model`, `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first`, `scale_data_window`, `scale_search_budget`, `async_multi_gpu_layout`; retired `transformer_trunk_b5c48h3tfr` as `amended`, net +11). Status mix: **solid 2** (`env_build`, `engine_ffn_swiglu_constraint`), **preliminary 14**, **hypothesis 21**, **future 1**.
- **Simplification cycles consumed**: 0 landed this window; `loop_policy.py simplification-status --task env_build` → `status: required` (`best_metric_value=6` smoke steps at iteration 2) — the obligation carries into the next `env_build`-adjacent commit (wave 1's `data_budget` scratch-constant fix touches the same environment; must ship as `change_type=refactor`).
- **Strategic redirects**: (1) smoke/production trunk switched `b5c48h3tfr` → `b7c96h3tfrs` after the CUDA backend refused every non-SwiGLU FFN block (`ffng`) — `engine_ffn_swiglu_constraint` promoted straight to solid; (2) source priority fixed to code-first (v1.18.2 mirror decides nodes/claims/plans, the 2019 paper is background) per human redirect recorded in `mission.json.sourcePriority`; (3) human decisions (`ace9d0c`) withdrew the 20% CPU cap and raised the scratch budget 200→500 GiB — not yet propagated into `DESIGN.md`/`data_budget` task/ledger (tracked as a wave-1 `[OPEN]` item, see `current_iter.md`).

## Logic-DAG snapshot

Canonical source: `results/ktg/paper_1902.10565/decomposition/logic.md` (38 nodes, rendered Mermaid) and the merged `results/ktg/GLOBAL_DAG.md` — this table mirrors their per-node status; render either file for the full flowchart rather than duplicating 38 Mermaid node lines here.

| Status | Count | Nodes |
|---|---|---|
| `[SOLID]` ● | 2 | `env_build`, `engine_ffn_swiglu_constraint` |
| `[PRELIMINARY]` ◐ | 14 | `playout_cap_randomization`, `root_explore_and_target_pruning`, `loss_targets_metrics`, `score_utility_search`, `head_gpool_degeneracy_9x9` △, `train_optimizer_schedule`, `selfplay_search_params`, `game_randomization_9x9`, `gating_rule`, `train_resume_semantics`, `data_format_pos_len`, `training_window_shuffle`, `select_transformer_ladder`, `transformer_trunk_b7c96h3tfrs` |
| `[HYPOTHESIS]` ○ | 21 | `cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime`, `data_budget`, `synchronous_loop_smoke`, `derive_cycle_knobs_9x9`, `verify_preemption_resume`, `loop_failure_circuit_breaker`, `selfplay_stage`, `shuffle_stage`, `train_stage`, `export_stage`, `gatekeeper_stage`, `bootstrap_accepted_model`, `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first`, `eval_improvement`, `scale_data_window`, `scale_search_budget`, `scale_up` |
| `[FUTURE]` □ | 1 | `async_multi_gpu_layout` |
| retired (`amended`) | 1 | `transformer_trunk_b5c48h3tfr` (superseded by `transformer_trunk_b7c96h3tfrs`; ffng block kind unservable in the CUDA backend) |

**External dependencies**: `env_build` node's `env-toolchain-b200` result depends on the `nvidia-cudnn-cu12` pip wheel (soname symlink workaround, `docs/cluster-manual.md`) and the `cmake-sm100.diff` patch applied only to the scratch clone (never the read-only `ref-code/` mirror, per alignment §4). No external dependency currently blocks a solid node.

**Open obligations** (24 total in the claim ledger, 6 discharged / 18 open): blocking-before-P1 = `o01`, `o02`, `o03` (thread budget 24 CPU), `o04` (scratch — see redirect above), `o13`, `o17` (loop binary path `cpp/build/katago`), `o24` (derived cycle knobs); non-blocking open = `o05` (cuDNN SDPA compile flag), `o12` (requirements.txt), `o19` (random-baseline gate observed), `o20` (TCMalloc RSS), `o21` (`-exclude-qvalues`), `o22` (CPU-policy scope — human decision landed `ace9d0c`, ledger row not yet marked `waived`), `o23` (b5 negative fixture).

## Accepted-results snapshot

| Claim | Evidence type | Verifier output path | Assumptions / deps | Status |
|---|---|---|---|---|
| `env-toolchain-b200` (c01 `env_build_runs`, c02 `sm100_sass_or_jit`) | `numerical_simulation` | `results/ktg/paper_1902.10565/evidence/env/smoke.txt` (PASS), job 298018 `sacct` COMPLETED 0:0 | randomly-initialized net (no playing-strength claim); `b7c96h3tfrs` stands in for the eventual 9x9 architecture; cuDNN via pip wheel on `LD_LIBRARY_PATH` | `empirical`, admitted |

`[OPEN]` items on this row (from `render-state`): 9x9 selfplay/train node must still set `selfplay1_maxsize9.cfg:16 dataBoardLen` and `train.sh:88 -pos-len` to 9 together; no shuffle/train run yet; engine binary reports `...-dirty` from `cmake-sm100.diff`, re-verify if the clone is re-pinned.

## Simplification cycle

- **Trigger**: `loop_policy.py simplification-status --task env_build` → `required` (2 attempts recorded, `smoke_steps_passed` best = 6/6 at iteration 2).
- **Input metric**: iteration 1, 4/6 smoke steps pass (SwiGLU refusal + missing sm_100 SASS both fail). **Output metric**: iteration 2, 6/6 smoke steps pass.
- **Code-edit delta**: `cmake-sm100.diff` (1 line, adds `100` to the CUDA-12.8 `CMAKE_CUDA_ARCHITECTURES` list, applied to the scratch clone only) + smoke-net swap `b5c48h3tfr` → `b7c96h3tfrs` in `env_build.sbatch`.
- **Lessons**: `CMakeLists.txt:761`'s plain `set()` silently shadows a `-DCMAKE_CUDA_ARCHITECTURES` override — the failure was architecture-silent (binary built and ran, just without B200 SASS) until `cuobjdump` was checked explicitly; the framework's own simplification gate is what forces a `refactor`-tagged follow-up before the next `env_build`-adjacent commit lands, which is why the scratch-budget fix due in wave 1 must carry `change_type=refactor`.

## Failure-mode drift

None yet — the sole `fail` row (`env_build` iter 1) used the existing `uncategorized_numerical` enum value; no new `failure_mode` extension was needed and no `pass_fail: "amended"` backfill occurred this window. One ledger-mechanics fix landed in the *framework* (not `failure_mode` enum): `phys-agentic-loop` `ssci` `959a4cd` made a `status=amended` knowledge row retire its node in `latest_per_node`/`latest_status`/`_latest_non_amended` (previously the pre-amendment `blocking` row could resurface); this is a DAG-collapse bugfix, tracked here because it changed how this window's node count renders (39 → 38), not a research failure-mode.
