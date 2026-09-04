# nodal_note — ktg-train (window: iterations 1–10, so far iterations 1–3)

## 10-iter window

- **error-DB pass/fail counts** (`results/ledgers/error/paper_arxiv-1902.10565/trials.jsonl`,
  **40 rows total** across 11 task_ids, up from 30/9 at iteration 2): `acquire` 2/2
  pass; `env_build` 1 fail→1 pass; `cfg_9x9_override` 1/1 pass;
  `tiny_model_export_smoke` 2/2 pass; `paper_code_map`/`_search`/`_training` 1
  each; `loop_resume_under_walltime` 13 rows (7 pass / 3 fail / 3 amended — five
  repair rounds now: o26/o27/o08 → o31/o26 → o33/o34/o35 → this window's o35
  discharge/o36 open); `data_budget` 9 rows (4 pass / 5 fail-or-partial, unchanged
  this window — no `data_budget`-file commit landed in iteration 3);
  `synchronous_loop_smoke` **6 rows, new this window** (2 pass / 4 fail-or-refuted:
  c06 refuted, c10 refuted, `r_smoke_threads_realnet` refuted, the withdrawn
  full_frac refutation); `derive_cycle_knobs_9x9` **2 rows, new this window** (1
  pass / 1 fail — the task file's own defective §2 command). **23 pass / 8
  partial / 6 fail / 3 amended** across the full window (iteration-3 delta: +10
  rows, all on the two newly-executing tasks). Neither `synchronous_loop_smoke`
  nor `derive_cycle_knobs_9x9` is a same-idea retry loop despite crossing
  crash-triage's 3-strike counter on `synchronous_loop_smoke` (`escalation` on
  the raw failing-row subsequence) — see `current_iter.md` §5 for the caveat
  that the same two jobs also produced 8 admitted results this iteration.
- **`logic.md` node coverage delta**: 38 → 38 (no new nodes this window).
  Status mix iteration 1 → 2 → 3: `solid` 2→2→**6**, `preliminary` 14→17→**15**
  (net -2 despite +3 promotions this window — `cfg_9x9_override`,
  `tiny_model_export_smoke`, `loop_resume_under_walltime` stay preliminary;
  `synchronous_loop_smoke` and `derive_cycle_knobs_9x9` newly enter preliminary;
  `transformer_trunk_b7c96h3tfrs` LEAVES preliminary for solid, and 3 more solid
  promotions — `head_gpool_degeneracy_9x9`, `data_format_pos_len`,
  `train_resume_semantics` — were already preliminary, not hypothesis, so the
  arithmetic is preliminary 17 + 2 new − 4 promoted-to-solid = 15), `hypothesis`
  21→18→**16** (−2: the two promoted-in nodes), `future` 1→1→1. `data_budget`
  stays `hypothesis` (unchanged this window; result still `conditional`).
- **Simplification cycles consumed**: the two flags opened at iteration 2
  (`data_budget`, `loop_resume_under_walltime`) carry unresolved into iteration 3
  — neither task's commit this window (`0c6d38d`/`9fdeb6b`, the o35/o36 pair) was
  a `refactor`-tagged row satisfying either flag, because `loop_resume_under_walltime`
  is still blocked from a `refactor` row by its own `pivot_structural` crash-triage
  verdict (unchanged). **Two new flags opened this window**:
  `synchronous_loop_smoke` (`best_iteration=3`, `core_candidate_rows_admitted=4`)
  and `derive_cycle_knobs_9x9` (`best_iteration=2`, `checks_passed_of_16=16`) —
  both `status: required`, both carried into iteration 4. Four simplification
  flags are now open simultaneously across three tasks; none has yet produced a
  qualifying `refactor` row.
- **Strategic redirects**: (1) the smoke job ran in **two attempts inside one
  three-attempt budget** (298712 COMPLETED, 299259 FAILED 1:0 correctly reporting
  what attempt 1's driver defect could not) — both are read as one execution unit
  for `synchronous_loop_smoke`, not two independent trials of the same idea; (2)
  the worker's own `full_frac` and c10 refutation claims (`98d6c42`) were
  **themselves refuted by the validator** (`97b44ba`) as a probe-instrument
  binning artefact (cheap searches inheriting visits into a reused MCTS subtree,
  not a physical excess of full searches) — a genuine two-round refute-the-
  refutation cycle, the deepest cross-check chain so far in this mission; the
  band is left `[UNCHECKED]`, not re-admitted at a new value; (3) c06 and c10 are
  **refuted only as literally written**, not as pipelines — c06's non-CUDA-context
  clauses (selfplay random-net 22, train 14, shuffle 4+8) all hold, only the
  CUDA-context real-net clause overruns by 1 thread (25 vs. 24 declared); c10's
  rows/game clause holds, only the on-disk-bytes/game clause overruns by 9-20%;
  both refutations are read as "the declared bound needs raising by a known
  amount," which `derive_cycle_knobs_9x9` already used as an input; (4) the
  worker's own derived-knobs claim was **narrowed, not rejected**, on
  cross-model validation (`c5d3c32`): every arithmetic check re-derives
  independently and 9 break attempts fail as they must, but the export-ramp
  timeline the worker wrote ("exactly one per cycle from cycle 13") does not
  survive `-no-repeat-files`/`-quit-if-no-data` — the validator's own
  independent read of `train.py`/`training_data_generator.py` puts the first
  candidate export at cycle 5, not a moved knob but a corrected claim about
  which cycle the SAME knobs first bind.

## Logic-DAG snapshot

Canonical source: `results/ktg/paper_1902.10565/decomposition/logic.md` (38 nodes) and the
merged `results/ktg/GLOBAL_DAG.md`. This table mirrors per-node status as of
`dag_mermaid.py progress` re-run this iteration.

| Status | Count | Nodes |
|---|---|---|
| `[SOLID]` ● | 6 | `env_build`, `engine_ffn_swiglu_constraint` (from iter 1-2) + **new this window**: `transformer_trunk_b7c96h3tfrs`, `head_gpool_degeneracy_9x9`, `data_format_pos_len`, `train_resume_semantics` |
| `[PRELIMINARY]` ◐ | 15 | 13 carried (`playout_cap_randomization`, `root_explore_and_target_pruning`, `loss_targets_metrics`, `score_utility_search`, `train_optimizer_schedule`, `selfplay_search_params`, `game_randomization_9x9`, `gating_rule`, `train_resume_semantics`→now solid so 12 actually carried, `training_window_shuffle`, `select_transformer_ladder`, `cfg_9x9_override`, `tiny_model_export_smoke`) + `loop_resume_under_walltime` + **new this window**: `synchronous_loop_smoke`, `derive_cycle_knobs_9x9` |
| `[HYPOTHESIS]` ○ | 16 | `data_budget`, `verify_preemption_resume`, `loop_failure_circuit_breaker`, `selfplay_stage`, `shuffle_stage`, `train_stage`, `export_stage`, `gatekeeper_stage`, `bootstrap_accepted_model`, `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first`, `eval_improvement`, `scale_data_window`, `scale_search_budget`, `scale_up` |
| `[FUTURE]` □ | 1 | `async_multi_gpu_layout` |
| retired (`amended`) | 1 | `transformer_trunk_b5c48h3tfr` (unchanged) |

**External dependencies**: unchanged (cuDNN pip wheel + `cmake-sm100.diff`). No
external dependency currently blocks a solid node; the smoke allocation's b200
queue wait is resolved (both jobs ran).

**Open obligations** (42 total in the claim ledger: 23 discharged / 17 open / 2
waived, up from 36/17/17/2 at iteration 2 — net +6 total, +6 discharged, 0 open
delta despite 6 discharges because 6 new were opened):
- Discharged this window: `o13`, `o19`, `o24`, `o30`, `o35`, `o37` (o37 opened
  and discharged inside this same window — instrument bug found and repaired
  between attempts 1 and 2).
- Opened this window: `o02_databoardlen_poslen_9`, `o36_wrapper_fails_open_...`,
  `o38_full_frac_discriminator_reused_tree`, `o39_cpus_per_task_wiring`,
  `o40_export_ramp_first_candidate_cycle5`, `o41_check_knobs_silent_fallback_constants`.
- **Open blocking (before P1)**: `o02`, `o03` (re-opened with the 25-vs-24
  measurement), `o25_chain_breaker_executed_proof`, `o39` — 4 total, down from
  the 7-item set named at iteration 2 (`o02`,`o03`,`o13`,`o24`,`o30`,`o33`,`o35`
  — `o13`/`o24`/`o30`/`o35` discharged this window; `o33` is open but its
  `blocking` field reads `no` in the ledger, corrected from iteration 2's note
  which listed it blocking).
- **Open non-blocking**: `o05`, `o11`, `o12`, `o15`, `o20`, `o21`, `o29`, `o32`,
  `o33`, `o36`, `o38`, `o40`, `o41` — 13 total.

## Accepted-results snapshot

| Claim | Evidence type | Verifier output path | Status |
|---|---|---|---|
| `env-toolchain-b200` | numerical_simulation | `evidence/env/smoke.txt` | empirical, admitted (iter 1) |
| `r_loop_resume_under_walltime_static` | existence_only | `evidence/loop_resume/repair_o35.txt` | existence_only, admitted; amended this window (o36 qualification); o33/o36 open non-blocking |
| `data-budget-guard-500gib` | empirical_measurement | `evidence/data_budget/repair_o28.txt` | conditional, admitted (iter 2); node stays hypothesis; o32 open non-blocking |
| `r_tiny_model_export_smoke_b7c96h3tfrs` | numerical_simulation | `evidence/tiny_smoke/verification.txt` | empirical, admitted (iter 2) |
| `cfg-9x9-override` | numerical_simulation | `evidence/cfg_9x9/check_cfg_9x9-298359.txt` | empirical, admitted (iter 2); node preliminary |
| `r_synchronous_loop_smoke` | numerical_simulation | `evidence/smoke/validation_core.md` | empirical, admitted — 2 cycles, c07 proved |
| `r_smoke_threads_realnet` | numerical_simulation | `evidence/smoke/validation_core.md` | **refuted** — 25 threads measured vs. 24 declared, real-net/CUDA-context clause |
| `r_smoke_throughput_tiny` | numerical_simulation | `evidence/smoke/validation_core.md` | empirical, admitted |
| `r_smoke_probe_training` | numerical_simulation | `evidence/smoke/validation_probes.md` | empirical, admitted — trunk_gpool 0, resume 4992→14976 |
| `r_smoke_probe_search` | numerical_simulation+probe | `evidence/smoke/validation_probes.md` | empirical, admitted (re-scoped); full_frac band left `[UNCHECKED]`, o38 open |
| `r_smoke_full_frac_binning` | probe | `evidence/smoke/validation_probes.md` | `unchecked` — worker's refutation rejected as an instrument artefact |
| `r_smoke_c10_bytes_per_game` | numerical_simulation | `evidence/smoke/validation_probes.md` | **refuted as written** — 10.944-12.06 KiB/game vs. ≤10 KiB bound; rows/game clause holds |
| `r_cycle_knobs_9x9_derived` | symbolic_derivation+analytic | `evidence/derive_cycle_knobs/validation.md` | conditional, admitted; claim narrowed on export ramp (first candidate cycle 5, not 13); o39/o40/o41 open |

Full generated block: `python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565`.

## Simplification cycle

- **Trigger**: 4 flags now open across 3 tasks (`data_budget`,
  `loop_resume_under_walltime` carried from iteration 2; `synchronous_loop_smoke`,
  `derive_cycle_knobs_9x9` opened this window).
- **Input → output metric**: `synchronous_loop_smoke` — `core_candidate_rows_admitted`
  best 4 at iteration 3 (its own opening iteration: `r_synchronous_loop_smoke`,
  `r_smoke_throughput_tiny`, `r_smoke_probe_training`, `r_smoke_probe_search`, of
  the 6 candidate groups proposed — the 2 refuted/1 unchecked don't count toward
  the metric). `derive_cycle_knobs_9x9` — `checks_passed_of_16` best 16 at
  iteration 2, i.e. the first `check_knobs_9x9.py` run (all 16 constraint checks
  pass at both the point measurement and its 90% lower bound).
- **Code-edit delta**: `loop_resume_under_walltime` — `read_counter()` added at
  `loop.sbatch:160-167`, consumed at 4 call sites (`.failcount`, `.chain_depth`,
  `.cycles_completed` ×2); `synchronous_loop_9x9.sh:308-324` given the matching
  inline guard for its own writer. `synchronous_loop_smoke` — `stage_monitor.sh`
  now writes per-job-id files instead of an appended shared table;
  `audit_smoke.py` selects one attempt's table and computes both c10 conjuncts;
  `probe_resume_9x9.sh` scoped its `rm -rf` to its own subdirectory only.
  `derive_cycle_knobs_9x9` — `derive_knobs.py`/`check_knobs_9x9.py` written new
  this window (not an edit of an existing file).
- **Lessons**: the o37 instrument bug (a monitor file silently APPENDED across
  Slurm resubmissions, changing its own column count and disabling a
  foreign-pid filter) is the same class of failure as iteration 2's o34 lesson —
  a script's behavior silently depends on invocation/execution history it
  doesn't check. The `full_frac` refute-then-reject cycle is the window's
  sharpest illustration of alignment.md §0: the worker's own claim of a
  refutation was not taken as final — cross-model validation re-derived the
  histogram from the engine's own log and found the worker's binning rule, not
  the pipeline, was wrong.

## Failure-mode drift

**One new value this window**: `assumption_too_broad` (1 row,
`derive_cycle_knobs_9x9`'s single fail — the task file's own §2 verification
command, which hard-codes a refuted 500-game pilot and an unquoted
`$(cat ...)` interpolation). All 13 fail-or-partial rows on
`loop_resume_under_walltime`/`data_budget`/`synchronous_loop_smoke` still use
`uncategorized_numerical`. 3 `amended` rows total in the window (all on
`loop_resume_under_walltime`, carried from iteration 2 — no new amendment
landed this iteration beyond the result-ledger amendment to
`r_loop_resume_under_walltime_static`, which is a result-DB not an error-DB
row) — each documents a superseded/corrected row per `note_discipline.md`,
none is a backfilled wrong verdict.
