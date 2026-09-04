# current_iter — ktg-train (iteration 2 / wave 1 execution + wave-2 planning close)

1. **Paper anchor** — wave 1 advanced four `logic.md` nodes by execution
   (`cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime`,
   `data_budget`) plus 14 code-map nodes re-affirmed `preliminary` with executed
   verification (`bb144d2`, `f092373`). Wave-2 planning wrote the task packets for
   `synchronous_loop_smoke` and `derive_cycle_knobs_9x9` and submitted the smoke
   job (298712) that will move `synchronous_loop_smoke`, `derive_cycle_knobs_9x9`,
   `measure_stage_throughput` and the 14 code-map nodes toward `preliminary`/`solid`.

2. **What shipped this iter** — 28 commits `bafd117..HEAD` (chronological):
   `fa76172`/`befb3b1` loop wrapper + Slurm chain (walltime resume, 6/6 checks) →
   `f092373`/`bb144d2` code-map re-verification (14 nodes) → `598413e` scratch
   guard v1 → `f2f16df` **`r_loop_resume_under_walltime_static` admitted
   existence_only** → `a6dd902` **`data-budget-guard-500gib` admitted
   conditional** (14 code-map nodes re-affirmed same commit) → `3c5df88`/`b3fed83`
   export-smoke legs → `cec918f`/`978f746`/`0fdf38f` (sacct `-n` not `-h` doc
   fix) → `4fd3302`/`f5df1a4` 9x9 cfg proof on b200 (22/24 threads) →
   `e56b240`/`0b13877` → `deb3d19` **`r_tiny_model_export_smoke_b7c96h3tfrs`
   admitted empirical**, o23 discharged → `497fbbc` **`cfg-9x9-override`
   admitted empirical**, knowledge row `preliminary` under a visible
   `skip_exec` bypass, c04 admitted, o01 discharged, o30 opened → `989f337`
   guard-constant pinning / pruner fix → `0f83f04` o26 **rejected** on the
   SIGTERM path, o27/o08 discharged, o31 opened → `55cbcf9`/`741beca`
   **wave-2 plan**: `synchronous_loop_smoke` + `derive_cycle_knobs_9x9` task
   files, probe tasks (`paper_code_map_{search,training}`) rewired to the
   smoke job, 18-thread gatekeeper frontier documented → `83fae52` o28 repair
   admitted, **o28/o04 discharged, o32 opened** (data_budget knowledge row
   stays `hypothesis`; result is `conditional`, not yet `preliminary`) →
   `7cd6f36`/`bcb1805` **smoke job authored and submitted (298712, PENDING,
   b200, ~20h queue est.)** → `2efa1b5` o31/o26 discharges re-admitted, o33
   opened (residuals), o34 opened (errexit loss under bash invocation) →
   `6b83dc0` errexit fix → `cd6cbf2` **o34 discharged**, o33 amended-open,
   **o35 opened** (chain-state files unvalidated leading-zero exposure).
   Net: **5 results admitted** (env-toolchain-b200 carried over from
   iteration 1 + 4 new this wave), **17 obligations discharged / 17 open / 2
   waived** (36 total, up from 24 at iteration 1), knowledge status mix
   `solid=2 preliminary=17 hypothesis=18 future=1` (38 nodes). The iteration-1
   propagation gap (500 GiB scratch cap, no-CPU-cap) is now fully closed:
   `DESIGN.md`, `tasks/data_budget/implementation.md` and `codes/loop/loop.sbatch`
   all read `536870912000`/no-cap from `budget.env`/`mission.json`; ledger
   `a11_cpu_policy_summed` retired, `o22_cpu_policy_scope` waived, `o04`
   discharged. `results/ktg/GLOBAL_DAG.md` was stale against the ledger
   (`cfg_9x9_override`/`tiny_model_export_smoke` still rendered `hypothesis`,
   trial counts short by the last two repair rounds) — regenerated this iter
   (`dag_mermaid.py merge`, 4-line node-label diff, no topology change).
   `convention.md` §10's `-attn-logit-penalty-cap` row still named the
   retired `b5c48h3tfr` as the closing condition; corrected in place to name
   `b7c96h3tfrs` (whose random-init export already passed without the flag)
   and to require a *trained* export for closure — see commit body `verify:`.
   **Two workers may still be committing** (an `o35` counter-fix under
   `codes/loop/`, `evidence/loop_resume/`) — this note does not touch those
   paths; only `progress/ktg-train`, `results/ktg/GLOBAL_DAG.md` and
   `decomposition/convention.md` are in this commit's scope.

3. **Next-3 roadmap** (wave 3, checked against `crash-triage`):
   (a) **Wait on smoke job 298712** (b200, PENDING, queue est. ~21:00 today)
   then run the closing check (`audit_smoke.py` + `rows_per_game.txt`) and
   the S1-S13 sub-result table in `tasks/synchronous_loop_smoke/`. No prior
   trials for `synchronous_loop_smoke` or `derive_cycle_knobs_9x9`
   (`crash-triage` → `no_action`, "no failing rows") — neither is a repeat.
   (b) **`o33_wrapper_classification_residuals` / `o35_chain_state_files_unvalidated`**
   (loop_resume_under_walltime wrapper): `crash-triage --task
   loop_resume_under_walltime` → `pivot_structural`, "2 consecutive failures
   with same failure_mode 'uncategorized_numerical'; next row must be
   change_type='structural'" (verbatim below). `check-pivot --change-type
   refactor` → **`blocked`** on that same reason; `check-pivot --change-type
   structural` → `ok` ("the escape hatch"). **Tension**: `simplification-status
   --task loop_resume_under_walltime` (below) independently says `status:
   required`, recommending a `refactor`-tagged row to hold the metric. A
   `refactor` row is blocked by crash-triage; a `structural` row satisfies
   crash-triage but is not what simplification-status asked for. Flagging
   this conflict for whoever repairs o33/o35 rather than resolving it here —
   an observer append cannot discharge or waive either obligation.
   (c) **`o32_data_budget_guard_hardening`** (non-blocking): `crash-triage
   --task data_budget` → `escalation`, "3 consecutive failures with
   failure_mode='uncategorized_numerical'" (verbatim below). **Caveat**: this
   reads only the failing-row subsequence (fail/crash/partial), so it counts
   iterations 5-7 (all failing, same mode) and is blind to iteration 8's two
   `pass` rows that followed and got `data-budget-guard-500gib` admitted
   conditional — the node is not currently stuck. Recorded verbatim per the
   observer cadence; the literal tool output is `escalation`, so o32's next
   repair should default to `change_type='structural'` (or escalate per
   alignment.md §3) rather than a `scalar`/`refactor` guard tweak, even
   though the task is not blocked today.

4. **Simplification flag**:
   `python3 phys-agentic-loop/_common/loop_policy.py simplification-status --paper arxiv-1902.10565 --task data_budget`:
   ```json
   {"status": "required", "best_iteration": 8, "best_metric_value": 25,
    "metric_name": "guard_exit_contract_cases_matched",
    "recommendation": "before the next promise-tag commit, append a change_type='refactor' row that maintains the metric; revert if it drops."}
   ```
   `python3 phys-agentic-loop/_common/loop_policy.py simplification-status --paper arxiv-1902.10565 --task loop_resume_under_walltime`:
   ```json
   {"status": "required", "best_iteration": 5, "best_metric_value": 19,
    "metric_name": "loop_and_wrapper_failure_paths_that_stop_the_link_as_specified_offline",
    "recommendation": "before the next promise-tag commit, append a change_type='refactor' row that maintains the metric; revert if it drops."}
   ```
   Both `status == required` — see the structural/refactor tension under
   Next-3(b) above. `env_build`'s iteration-1 `required` flag was cleared by
   this wave's non-`env_build` commits (no `env_build`-adjacent commit landed).

5. **Verifier output** (verbatim, re-run this iter):

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py progress --paper arxiv-1902.10565` →
   38 rows; status histogram **solid=2, preliminary=17, hypothesis=18, future=1**.
   Representative rows (full 38-object JSON reproducible verbatim by re-running):
   ```json
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::cfg_9x9_override", "status": "preliminary", "n_knowledge": 3, "n_trials": 1, "pass": 1, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::tiny_model_export_smoke", "status": "preliminary", "n_knowledge": 4, "n_trials": 2, "pass": 2, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::loop_resume_under_walltime", "status": "preliminary", "n_knowledge": 4, "n_trials": 11, "pass": 6, "fail": 2}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::data_budget", "status": "hypothesis", "n_knowledge": 2, "n_trials": 9, "pass": 4, "fail": 5}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::synchronous_loop_smoke", "status": "hypothesis", "n_knowledge": 2, "n_trials": 0, "pass": 0, "fail": 0}
   ```

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py duplicates --paper arxiv-1902.10565` → `[]`

   `python3 phys-agentic-loop/_common/loop_gate.py status`:
   ```json
   {
     "decision": {"decision": "continue", "reason": "iteration 0/1000; progress solid=2 results=5 discharged=0; no_progress 0/8, stuck 0/3", "iteration": 0, "max_iterations": 1000, "no_progress_streak": 0, "no_progress_limit": 8, "stuck_streak": 0, "stuck_counter_limit": 3, "signal": {"solid_nodes": 2, "pass_rows": 19, "admitted_results": 5, "discharged_results": 0, "total_trials": 30, "max_ledger_iteration": 8}},
     "gate_state": {"last_progress": [2, 5, 0], "last_iteration": 0, "no_progress_streak": 0, "stuck_streak": 0, "last_decision": "continue"},
     "state_file": "/weka/home/schmidt/ssci-haiyangw/az/.claude/ralph-loop.local.md",
     "loop_active": null
   }
   ```
   No-progress 0/8, stuck 0/3, decision `continue` — the gate does not block wave 3.

   `python3 phys-agentic-loop/_common/loop_policy.py crash-triage --paper arxiv-1902.10565 --task loop_resume_under_walltime --domain numerical`:
   ```json
   {"recommendation": "pivot_structural", "reason": "2 consecutive failures with same failure_mode 'uncategorized_numerical'; next row must be change_type='structural'", "last_failure_mode": "uncategorized_numerical", "consecutive_same_mode": 2, "domain_hint": "switch numerical method — implicit ↔ explicit integrator, FD ↔ spectral, direct mode-sum ↔ contour deformation. Pure mesh / tolerance / step-size changes do not count as structural."}
   ```
   `python3 phys-agentic-loop/_common/loop_policy.py crash-triage --paper arxiv-1902.10565 --task data_budget --domain numerical`:
   ```json
   {"recommendation": "escalation", "reason": "3 consecutive failures with failure_mode='uncategorized_numerical'; alignment.md §0 + §3 — switch methodology entirely", "last_failure_mode": "uncategorized_numerical", "consecutive_same_mode": 3, "domain_hint": "switch numerical method — implicit ↔ explicit integrator, FD ↔ spectral, direct mode-sum ↔ contour deformation. Pure mesh / tolerance / step-size changes do not count as structural."}
   ```
   (`synchronous_loop_smoke` / `derive_cycle_knobs_9x9` both → `{"recommendation": "no_action", "reason": "no failing rows for this task"}`.)
