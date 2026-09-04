# nodal_note — ktg-train (window: iterations 1–10, so far iterations 1–2)

## 10-iter window

- **error-DB pass/fail counts** (`results/ledgers/error/paper_arxiv-1902.10565/trials.jsonl`,
  30 rows total across 9 task_ids): `acquire` 2/2 pass; `env_build` 1 fail → 1 pass (iter 1);
  `cfg_9x9_override` 1/1 pass; `tiny_model_export_smoke` 2/2 pass;
  `loop_resume_under_walltime` 6 pass / 2 fail / 3 amended (11 rows, three repair rounds:
  o26/o27/o08 → o31/o26 rejected-then-discharged → o33/o34/o35); `data_budget` 4 pass / 5
  fail-or-partial (9 rows, two repair rounds: o28 attempt-1 fail chain then a successful
  retry-with-backoff repair); `paper_code_map{,_search,_training}` pass rows for the 14
  re-verified code-map nodes. **19 pass / 9 fail-or-partial / 3 amended** across the window
  (iteration-1 total was 3 pass / 1 fail). No same-mode 3-cycle loop went undetected: two
  tasks now sit past the crash-triage threshold on their *failing-row* subsequence
  (`loop_resume_under_walltime` → `pivot_structural`, `data_budget` → `escalation`) — see
  `current_iter.md` §3 for the verbatim outputs and the caveat that both tasks' most recent
  actual attempts passed and got results admitted.
- **`logic.md` node coverage delta**: 38 → 38 (no new nodes this window; wave 1 promoted
  existing nodes). Status mix iteration 1 → iteration 2: `solid` 2→2, `preliminary` 14→17
  (`cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime` promoted from
  `hypothesis`), `hypothesis` 21→18, `future` 1→1. `data_budget` stays `hypothesis` (result
  `conditional`, not yet `preliminary`).
- **Simplification cycles consumed**: 1 landed this window (`env_build`'s iteration-1
  `required` flag implicitly cleared — no `env_build`-adjacent commit landed in wave 1/2, so
  the obligation carried but was never violated). 2 new `required` flags opened this window:
  `data_budget` (`best_iteration=8`, `guard_exit_contract_cases_matched=25`) and
  `loop_resume_under_walltime` (`best_iteration=5`,
  `loop_and_wrapper_failure_paths_that_stop_the_link_as_specified_offline=19`) — both carry
  into wave 3 and both collide with their own task's `pivot_structural`/`escalation`
  crash-triage verdict (refactor recommended by simplification-status, blocked by
  crash-triage; structural satisfies crash-triage but isn't what simplification-status
  asked for). Recorded as an open tension, not resolved by this observer note.
- **Strategic redirects**: (1) `cfg_9x9_override`'s knowledge row admitted `preliminary`
  under a visible `skip_exec` admission-gate bypass (`497fbbc`) — the row is flagged, not
  hidden, and carries `o30_cfg_9x9_knowledge_verify_in_allocation` to close the bypass with
  an in-allocation re-append (planned as smoke-job leg A, S10 in
  `tasks/synchronous_loop_smoke/`); (2) `loop_resume_under_walltime`'s SIGTERM-vs-failure
  classification went through three repair rounds (o26 rejected once on the SIGTERM path
  before being redesigned and discharged; o33/o34/o35 opened/discharged/opened in sequence)
  — each round is a distinct validator refutation, not a same-idea retry, so crash-triage's
  3-strike rule tracks it as `pivot_structural` (2 consecutive same-mode) rather than
  `escalation`; (3) wave-2 planning collapsed 14 previously-separate probe/measurement nodes
  onto **one** smoke allocation (`synchronous_loop_smoke`, job 298712) because b200 queue
  wait (~20h/job) made per-node jobs prohibitive — `tasks/synchronous_loop_smoke/` §2 lists
  13 sub-results (S1-S13) landing from the one job; (4) the iteration-1 CPU/scratch
  propagation gap is now fully closed (`DESIGN.md`, `tasks/data_budget/implementation.md`,
  `codes/loop/loop.sbatch` all read 500 GiB / no-cap from `budget.env`/`mission.json`;
  `a11_cpu_policy_summed` retired, `o22_cpu_policy_scope` waived).

## Logic-DAG snapshot

Canonical source: `results/ktg/paper_1902.10565/decomposition/logic.md` (38 nodes) and the
merged `results/ktg/GLOBAL_DAG.md` (regenerated this iter — was stale against the ledger by
two node-status transitions and both tasks' latest trial counts; `dag_mermaid.py merge`
re-run, no topology change). This table mirrors per-node status.

| Status | Count | Nodes |
|---|---|---|
| `[SOLID]` ● | 2 | `env_build`, `engine_ffn_swiglu_constraint` |
| `[PRELIMINARY]` ◐ | 17 | the 14 carried from iteration 1 (`playout_cap_randomization`, `root_explore_and_target_pruning`, `loss_targets_metrics`, `score_utility_search`, `head_gpool_degeneracy_9x9`, `train_optimizer_schedule`, `selfplay_search_params`, `game_randomization_9x9`, `gating_rule`, `train_resume_semantics`, `data_format_pos_len`, `training_window_shuffle`, `select_transformer_ladder`, `transformer_trunk_b7c96h3tfrs`) + 3 new: `cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime` |
| `[HYPOTHESIS]` ○ | 18 | `data_budget`, `synchronous_loop_smoke`, `derive_cycle_knobs_9x9`, `verify_preemption_resume`, `loop_failure_circuit_breaker`, `selfplay_stage`, `shuffle_stage`, `train_stage`, `export_stage`, `gatekeeper_stage`, `bootstrap_accepted_model`, `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first`, `eval_improvement`, `scale_data_window`, `scale_search_budget`, `scale_up` |
| `[FUTURE]` □ | 1 | `async_multi_gpu_layout` |
| retired (`amended`) | 1 | `transformer_trunk_b5c48h3tfr` (unchanged from iteration 1) |

**External dependencies**: unchanged from iteration 1 (cuDNN pip wheel + `cmake-sm100.diff`
scratch-clone patch). The smoke job additionally depends on b200 queue availability (job
298712 PENDING, ~20h estimate) — no external dependency currently blocks a solid node.

**Open obligations** (36 total in the claim ledger: 17 discharged / 17 open / 2 waived, up
from 24 total / 6 discharged / 18 open at iteration 1):
- Discharged this window: `o01`, `o08`, `o23`, `o26` (net: rejected once then re-admitted
  discharged on redesign), `o27`, `o28`, `o31`, `o34`.
- Waived this window: `o22_cpu_policy_scope`.
- Opened this window: `o30_cfg_9x9_knowledge_verify_in_allocation` (skip_exec closure),
  `o32_data_budget_guard_hardening` (non-blocking), `o33_wrapper_classification_residuals`,
  `o35_chain_state_files_unvalidated`.
- Still open blocking-before-P1: `o02`, `o03`, `o04`→discharged (was blocking, now closed),
  `o13`, `o17`→discharged, `o24`. Effective blocking set: `o02`, `o03`, `o13`, `o24`, plus
  wave-3 items `o30`, `o33`, `o35`.
- Still open non-blocking: `o05`, `o12`, `o19`, `o20`, `o21`, `o29`, `o32`.

## Accepted-results snapshot

| Claim | Evidence type | Verifier output path | Assumptions / deps | Status |
|---|---|---|---|---|
| `env-toolchain-b200` (c01, c02) | numerical_simulation | `evidence/env/smoke.txt` (PASS), job 298018 | randomly-initialized net; `b7c96h3tfrs` stands in for the 9x9 arch | `empirical`, admitted |
| `r_loop_resume_under_walltime_static` | existence_only | `evidence/loop_resume/repair_o34.txt` (pass) | a01-a04, a12; deps on `env_build`, `train_resume_semantics`, `data_budget` | `existence_only`, admitted; `o33`/`o35` open non-blocking |
| `data-budget-guard-500gib` | empirical_measurement | `evidence/data_budget/repair_o28.txt` (pass) | a05, a07; 20 GiB default projection is a placeholder pending `measure_stage_throughput` | `conditional`, admitted; node stays `hypothesis`; `o32` open non-blocking |
| `r_tiny_model_export_smoke_b7c96h3tfrs` | numerical_simulation | `evidence/tiny_smoke/verification.txt` (pass) | a06, a08; deps on `env_build`, `select_transformer_ladder`, `engine_ffn_swiglu_constraint` | `empirical`, admitted |
| `cfg-9x9-override` | numerical_simulation | `evidence/cfg_9x9/check_cfg_9x9-298359.txt` (pass) | a05, a10; knowledge row under a visible `skip_exec` bypass (`o30` closes it) | `empirical`, admitted; node `preliminary` |

Full generated block: `python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565`.

## Simplification cycle

- **Trigger**: two new `required` flags this window (`data_budget`, `loop_resume_under_walltime`)
  — see 10-iter-window bullet above for the metric values and the structural/refactor tension.
- **Input → output metric**: `data_budget` guard-exit-contract cases matched: iteration-1
  window start unmeasured → best 25/25 at iteration 8 (after the o28 repair). `loop_resume`
  wrapper failure-paths-specified-offline: best 19 at iteration 5 (o26/o27/o08 repair
  packet), unchanged through the later o31/o33/o34/o35 rounds (those rounds fixed
  classification edge cases, not the enumerated path count).
- **Code-edit delta**: `data_budget` — `scratch_guard.sh`/`prune_retention.py` constants
  pinned to a trusted-directory FILE (`989f337`), `du -sb` retry-with-backoff added.
  `loop_resume_under_walltime` — `finalize()` gained a third outcome class for scheduler
  termination (o31 repair), `set -eu -o pipefail` moved into the wrapper body (o34 repair,
  `6b83dc0`) after the earlier form lost `errexit` under `bash script.sh` invocation.
- **Lessons**: the o34 repair (errexit lost under a `bash` wrapper invocation vs. direct
  execution) is the same class of "architecture-silent" failure the iteration-1
  `cmake-sm100.diff` lesson flagged — a shell option set at the top of a script file is not
  guaranteed to hold under every invocation form, and this only surfaced because the
  validator's refutation pass exercised both invocation forms explicitly.

## Failure-mode drift

No new `failure_mode` enum value was needed this window — all 9 fail/partial rows across
`data_budget` and `loop_resume_under_walltime` used the existing `uncategorized_numerical`
value. 3 `amended` rows landed (2 on `loop_resume_under_walltime` iter-5 hash corrections, 1
implicit via the `transformer_trunk_b5c48h3tfr` retirement carried from iteration 1) — none
was a `pass_fail: "amended"` backfill of a prior wrong verdict; each documents a
superseded/corrected row per `note_discipline.md` (revise in place, don't delete).
