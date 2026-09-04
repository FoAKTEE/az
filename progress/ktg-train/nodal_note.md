# nodal_note — ktg-train (window: iterations 1–10, so far iterations 1–4)

## 10-iter window

- **error-DB pass/fail counts** (`results/ledgers/error/paper_arxiv-1902.10565/trials.jsonl`,
  **61 rows total** across 13+ task_ids, up from 40 rows at iteration 3): the
  iteration-3 counts (`acquire` 2/2 pass; `env_build` 1 fail→1 pass;
  `cfg_9x9_override` 1/1 pass; `tiny_model_export_smoke` 2/2 pass;
  `paper_code_map_{,search,training}` 1 each; `loop_resume_under_walltime` 13 rows
  7 pass/3 fail/3 amended; `data_budget` 9 rows 4 pass/5 fail-or-partial;
  `synchronous_loop_smoke` 6 rows 2 pass/4 fail-or-refuted; `derive_cycle_knobs_9x9`
  2 rows 1 pass/1 fail) all carry forward. **This window's delta (+21 rows)**:
  `loop_resume_under_walltime` grew 13→20 (three more repair rounds: R1 CPU-assert,
  R6 in-link monitor, the partition-inheritance fix — 7 new rows, net pass 7→13,
  fail 3→4, one more amendment); `derive_cycle_knobs_9x9` grew 2→5 (R2 ramp repair,
  R3 missing-key repair — 3 new rows, 1 pass/1 fail added net); a new task
  `production_chain_9x9` opens with rows for the launch/re-link/L40S-block/L40S-run
  sequence and the successor-id-lost defect; a new task `converged_test_7x7` opens
  with the board-length parameterisation probe and the LR-fix probe (2 rows, 1
  pass). **synchronous_loop_smoke is unchanged this window** (still 6/2/4 — no
  commit touched that task's own files, only consumed its evidence). Aggregate
  across the full window: pass/fail/partial/amended counts are best read per-task
  above; the DAG-level pass/fail per node is `dag_mermaid.py progress`'s own
  `n_trials`/`pass`/`fail` columns (verbatim in `current_iter.md` §5).
- **`logic.md` node coverage delta**: 38 → 39 (one new node,
  `converged_test_7x7`, opened at iteration 4 on the human's 7x7 test-run
  directive — outside the 9x9-only scope by design, a05 deliberately stepped
  around). Status mix iteration 1 → 2 → 3 → 4: `solid` 2→2→6→**7** (+1:
  `playout_cap_randomization`, on the re-binned full-search fraction 0.2516),
  `preliminary` 14→17→15→**14** (−1: the one promotion out to solid, no new
  preliminary entries this window), `hypothesis` 21→18→16→**17** (+1: the new
  `converged_test_7x7` node enters at hypothesis), `future` 1→1→1→1 (unchanged).
- **Simplification cycles consumed**: **zero** — no task closed a qualifying
  `change_type=refactor` commit against a held metric this window. The count of
  simultaneously-open `status: required` flags grew from 4 (iteration 3:
  `data_budget`, `loop_resume_under_walltime`, `synchronous_loop_smoke`,
  `derive_cycle_knobs_9x9`) to **7** at iteration 4 (three more:
  `wave3_prelaunch_repairs` best_iteration 6 metric
  `full_frac_rebinned_at_max_visits=0.2516`; `production_chain_9x9` best_iteration
  6 metric `rows_per_game_random_net=31.17`; `converged_test_7x7` best_iteration 2
  metric `effective_lr_multiplier_over_the_run=0.4`). This is read, not acted on:
  `production_chain_9x9` §13 forbids editing the chain's own scripts while it
  runs, so a `refactor` row against a live task's files is structurally deferred
  until its allocation ends — consistent with iteration 3's reading of the
  `pivot_structural` crash-triage verdict on `loop_resume_under_walltime`.
- **Strategic redirects**: (1) the first chain submission (299366, 3 links × 71.5 h)
  was **re-linked to nine 23.5 h links** (299461) purely on backfill-estimate
  evidence — every ≥1-day b200 request shared one identical multi-day estimate
  while sub-day requests started same-day; no script was edited, only the
  successor walltime, propagated by environment variable precedence over the
  `#SBATCH` header; (2) the human's multi-partition decision (b200 or l40s,
  whichever frees first) was **held for one iteration** on two measured blockers —
  no sm_89 image in the built binary, and `resubmit()`'s argv `--partition`
  overriding the environment-variable path that carries every other successor
  knob — both closed by measurement (job 300987; `KTG_PARTITIONS` repair) before
  the chain actually used l40s; (3) admitting l40s **moved the chain's start
  estimate two days earlier** (2026-09-06T21:57 → 2026-09-04T21:54) and revealed a
  new, unplanned-for bottleneck on that partition — CPUs bind before GPUs do; (4)
  the chain is now **running on the partition the human's decision exists for**,
  and produced its own first, unplanned finding within the first cycle: random-net
  selfplay on l40s runs 7.4× the smoke's rate because production disables
  `logSearchInfo`, which every smoke probe had left on — not a partition-speed
  effect; (5) the 7x7 test run's stopping rule was **replaced mid-run** by human
  directive — from a single 6 h time-capped allocation to open-ended
  same-BASEDIR continuation segments gated on a measured plateau (two consecutive
  FLAT evaluations AND no gatekeeper acceptance in 15 cycles), a genuine scope
  change to the node's own success criterion, recorded as two separate
  `mission.json` decisions (index 4: authorize the 7x7 test; index 5: replace its
  time cap with the plateau rule) rather than folded silently into the original
  directive. `mission.json.decisions[]` holds **6** entries at this note's close
  (indices 0–5); the multi-partition L40S decision is index 3.

## Logic-DAG snapshot

Canonical source: `results/ktg/paper_1902.10565/decomposition/logic.md` (39 nodes) and the
merged `results/ktg/GLOBAL_DAG.md` (regenerated this wave — was stale at 38 nodes/
pre-promotion badges since commit 570ad6b). This table mirrors `dag_mermaid.py
progress`, re-run this iteration.

| Status | Count | Nodes |
|---|---|---|
| `[SOLID]` ● | 7 | `env_build`, `engine_ffn_swiglu_constraint`, `transformer_trunk_b7c96h3tfrs`, `head_gpool_degeneracy_9x9`, `data_format_pos_len`, `train_resume_semantics` (all carried from iteration 3) + **new this window**: `playout_cap_randomization` |
| `[PRELIMINARY]` ◐ | 14 | `root_explore_and_target_pruning`, `loss_targets_metrics`, `score_utility_search`, `train_optimizer_schedule`, `selfplay_search_params`, `game_randomization_9x9`, `gating_rule`, `training_window_shuffle`, `select_transformer_ladder`, `cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime`, `synchronous_loop_smoke`, `derive_cycle_knobs_9x9` |
| `[HYPOTHESIS]` ○ | 17 | `data_budget`, `verify_preemption_resume`, `loop_failure_circuit_breaker`, `selfplay_stage`, `shuffle_stage`, `train_stage`, `export_stage`, `gatekeeper_stage`, `bootstrap_accepted_model`, `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first`, `eval_improvement`, `scale_data_window`, `scale_search_budget`, `scale_up` + **new this window**: `converged_test_7x7` |
| `[FUTURE]` □ | 1 | `async_multi_gpu_layout` |

**External dependencies**: unchanged (cuDNN pip wheel + `cmake-sm100.diff`). A
second architecture question — sm_89 image coverage for l40s — was opened and
closed within this window (`o45`, discharged): the mission binary needs no sm_89
image; the sm_86 cubin loads under CUDA's minor-version compatibility rule,
measured on job 300987, not inferred from documentation.

**Open obligations** (46 total in the claim ledger: 29 discharged / 15 open / 2
waived, up from 42/23/17/2 at iteration 3 — net +4 total, +6 discharged, −2 open):
- Discharged this window: `o02`, `o38`, `o39`, `o41` (the four repairs blocking
  launch) and `o44`, `o45` (opened and discharged the same iteration — the
  partition-propagation repair and the L40S architecture-image question).
- Opened this window: `o42_knob_file_sourcing_and_stale_sampler_pids`,
  `o43_derive_knobs_typed_size_and_thread_constants`, `o44` (discharged same
  window), `o45` (discharged same window).
- **Open blocking (before/during the chain)**: `o03_thread_budget_24cpu`,
  `o25_chain_breaker_executed_proof` — 2 total, down from the 4 named at
  iteration 3 (`o02`, `o03`, `o25`, `o39` — `o02`/`o39` discharged this window;
  `o40` is re-confirmed **non-blocking** in the ledger, correcting iteration 3's
  note which had it among the four).
- **Open non-blocking**: `o05`, `o11`, `o12`, `o15`, `o20`, `o21`, `o29`, `o32`,
  `o33`, `o36`, `o40`, `o42`, `o43` — 13 total.

## Accepted-results snapshot

| Claim | Evidence type | Verifier output path | Status |
|---|---|---|---|
| `env-toolchain-b200` | numerical_simulation | `evidence/env/smoke.txt` | empirical, admitted (iter 1) |
| `r_loop_resume_under_walltime_static` | existence_only | `evidence/loop_resume/{validation_repair4,validation_repair5}.md` | existence_only, admitted; amended twice more this window (R1/R6 qualifications, then the partition-inheritance qualifications) |
| `data-budget-guard-500gib` | empirical_measurement | `evidence/data_budget/repair_o28.txt` | conditional, admitted (iter 2); unchanged this window |
| `r_tiny_model_export_smoke_b7c96h3tfrs` | numerical_simulation | `evidence/tiny_smoke/verification.txt` | empirical, admitted (iter 2) |
| `cfg-9x9-override` | numerical_simulation | `evidence/cfg_9x9/check_cfg_9x9-298359.txt` | empirical, admitted (iter 2) |
| `r_synchronous_loop_smoke` | numerical_simulation | `evidence/smoke/validation_core.md` | empirical, admitted (iter 3) |
| `r_smoke_threads_realnet` | numerical_simulation | `evidence/smoke/validation_core.md` | refuted (iter 3), unchanged |
| `r_smoke_throughput_tiny` | numerical_simulation | `evidence/smoke/validation_core.md` | empirical, admitted (iter 3) |
| `r_smoke_probe_training` | numerical_simulation | `evidence/smoke/validation_probes.md` | empirical, admitted (iter 3) |
| `r_smoke_probe_search` | numerical_simulation+probe | `evidence/smoke/validation_probes.md` | empirical, admitted (iter 3); re-scoped this window by the full_frac re-bin |
| `r_smoke_full_frac_binning` | probe | `evidence/smoke/validation_probes.md` | `unchecked` (iter 3), unchanged |
| `r_smoke_c10_bytes_per_game` | numerical_simulation | `evidence/smoke/validation_probes.md` | refuted as written (iter 3), unchanged |
| `r_cycle_knobs_9x9_derived` | symbolic_derivation+analytic | `evidence/derive_cycle_knobs/validation.md` | conditional, admitted (iter 3); **amended this window** — the R2 ramp correction is now cross-model re-derived independently, not just worker-proposed |
| `r_smoke_full_frac_rebinned` | empirical_measurement | `evidence/wave3_prelaunch_repairs/validation.md` | **new this window** — empirical, admitted; discriminator = `Root visits == maxVisits`, 0.2516 in [0.20, 0.30] on two instruments + an independent second run |
| `r_env_l40s` | empirical_measurement | `evidence/env/l40s-300987.txt` | **new this window** — empirical, admitted as `runnable`; production-regime throughput/VRAM left `[OPEN]` |

Full generated block: `python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565`
(well over the 10 KB `RESEARCH_STATE.md` cap on its own; one-line pointers kept
there, reproducible verbatim by re-running the command).

## Simplification cycle

- **Trigger**: 7 flags now open across 7 tasks (4 carried from iteration 3 +
  3 opened this window: `wave3_prelaunch_repairs`, `production_chain_9x9`,
  `converged_test_7x7`).
- **Input → output metric** (new flags this window only; carried flags unchanged
  from iteration 3's note): `wave3_prelaunch_repairs` —
  `full_frac_rebinned_at_max_visits` best 0.2516 at iteration 6 (the R4 re-bin,
  inside the [0.20, 0.30] band). `production_chain_9x9` — `rows_per_game_random_net`
  best 31.17 at iteration 6 (read 1 of link 1, against the derived 31.675, lower90
  28.134). `converged_test_7x7` — `effective_lr_multiplier_over_the_run` best 0.4
  at iteration 2 (the `-lr-scale-auto` fix, upstream's own from-scratch constant).
- **Code-edit delta**: six repair commits this window, one file class each — the
  Slurm wrapper (`loop.sbatch`: CPU declaration/assertion, in-link monitor,
  partition list from `KTG_PARTITIONS`), the loop script
  (`synchronous_loop_9x9.sh`: pre-shuffle pos_len guard), the knob deriver
  (`derive_knobs.py`/`check_knobs_9x9.py`: strict missing-key raise, corrected
  ramp simulation), and the search probe (`probe_search_9x9.py`: full-search
  discriminator). The 7x7 packet added net-new files (cfgs, `t7_cycle.sh`,
  `converged_7x7.sbatch`/`t7_continue.sbatch`, `plateau_check.py`) rather than
  editing 9x9 files, with three narrow, defaulted passthrough variables added to
  shared files (`train_9x9.sh`, `check_pos_len_npz.py`) that leave every 9x9
  invocation byte-identical when unset — verified explicitly at every repair.
- **Lessons**: two genuine refute-then-correct cycles this window, both the
  sharpest form of alignment.md §0 cross-checking: the R4 full-search re-bin
  (a worker-flagged instrument bug, corrected and independently re-derived by the
  validator on two instruments) and the R2 export-ramp model (the validator's own
  independent read of `train.py`/`shuffle.py` extended the worker's fix beyond
  what the worker had checked, finding the "exactly one per cycle" claim
  unreachable at ANY cycle, not just mis-dated to cycle 13). A new lesson this
  window: a site-specific Slurm wrapper's STDERR banner ("BILLING") silently broke
  `resubmit()`'s job-id capture — the same class of defect as iteration 2's o34 and
  iteration 3's o37 (behavior silently depending on an unchecked execution
  environment), now three occurrences across three iterations, worth watching as
  its own pattern.

## Failure-mode drift

No new `failure_mode` enum value this window — every fail-or-partial row on
`loop_resume_under_walltime` and `derive_cycle_knobs_9x9` this window classifies
under the existing `uncategorized_numerical` (wrapper/knob repairs) or
`assumption_too_broad` (carried from iteration 3, unchanged count). The
`production_chain_9x9` and `converged_test_7x7` tasks opened this window carry
**zero fail rows** each to date — every trial recorded against them so far is a
pass or a finding, not a failure; `crash-triage` accordingly reports
`fix_and_retry` (first-ever finding, the successor-id log bug) and `no_action`
respectively (`current_iter.md` §5). Amended rows: the result-DB amendments to
`r_loop_resume_under_walltime_static` (twice this window) and
`r_cycle_knobs_9x9_derived` (once) are result-ledger, not error-ledger,
amendments — each documents a superseded/corrected verdict per
`note_discipline.md`, none a backfilled wrong verdict.
