# current_iter — ktg-train (iteration 1 / wave 0 close)

1. **Paper anchor** — no `logic.md` node advances by execution this iter except `env_build`
   (hypothesis → **solid**, result `env-toolchain-b200`) and `engine_ffn_swiglu_constraint`
   (discovered **solid** as a build-failure side-effect). The rest of wave 0 is stage
   `0-acquire` + stage `1-decompose` (`pipelines/0-acquire`, `pipelines/1-decompose`) —
   building the 38-node DAG that every later iteration will advance node-by-node.

2. **What shipped this iter** — commits (`git log --oneline`, `main` unless noted):
   - `17ce80a` — consumer tree opened: `phys-agentic-loop` submodule (branch `ssci`), `ref-code/lightvector-KataGo` @ v1.18.2 `fd0723fd`, `ref-paper/arxiv-1902.10565` tex mirror, `mission.json`, `.delegation-policy strict`. (stage 0-acquire)
   - `e03261b` — cluster manual + job-submission/compute-budget skills + four role definitions, verified live on skipjack.
   - `8ed4505` — pass-1 code-first decomposition: 26 knowledge nodes, 43 claim-ledger rows, `logic.md`/`GLOBAL_DAG.md` rendered, `duplicates` → `[]`.
   - `3549a8c` — corrected 3 pass-1 rows (halflife, head-gpool constants, handicap no-op) against the paper-to-code audit.
   - `9484917` — `DESIGN.md` (182 lines): compute split, 9x9 keys, resume table, scratch numbers, 12 risks.
   - `8661516` — env_build attempt 1 (job 297952): smoke fails 2/5 steps — `b5c48h3tfr` (`ffng`) throws `Non-SwiGLU transformer FFN is not yet supported` in every CUDA/ROCm backend; `CMakeLists.txt:761` omits `sm_100` for CUDA 12.8 (`cuobjdump … | grep -c sm_100` = 0). `cmake-sm100.diff` authored.
   - `ba7917a` — cluster-manual note: cuDNN wheel soname symlink + sm_100 verification recipe.
   - `c33dc37` — env_build attempt 2 (job 298018, b200/gb205, 00:02:10): all six smoke steps exit 0 on `b7c96h3tfrs`; `sm_100` SASS count 2; torch 2.11.0+cu128 fwd+bwd at pos_len 9. Result row **`env-toolchain-b200`** (empirical, evidence sha256 `6573236…`) admitted.
   - `87bb402` — implementation plans (python/cpp/bash) + `result_seed.md`; +2 obligations (`o17` loop binary path, `o18` smoke-model mismatch).
   - `fadcc5c` — six `pipelines/2-work` task packets for the READY nodes.
   - `915b4f7` — task files corrected: `b5c48h3tfr` refusal marked resolved history after the switch to `b7c96h3tfrs`.
   - `696123e` (seat A, 38 nodes) / `a678b10` (seat B, 39 nodes) — two independent DAG-review adjudications (PROMPT.md two-model review requirement); seat B run by the external reviewer per `mission.json.externalReviewers`.
   - `ba7917a`… `60b2db3` — **framework fix**: submodule `phys-agentic-loop` bumped `ssci` → `959a4cd` (`infra(ledger,dag)!: retire a node when its latest knowledge row is amended`) after `062e8b4` found `latest_per_node`/`latest_status`/`_latest_non_amended` failed to retire a superseded node on an `amended` row; `python3 -m pytest -q tests` → 173 passed; `dag_mermaid render` → 38 nodes (was 39 with the ghost).
   - `9ea4166`! — canonical 38-node DAG appended (`knowledge append-batch --force` → `{"appended": 39, "skipped": 0}`; re-append of `loop_resume_under_walltime` → `{"appended": 1, "skipped": 0}`; `duplicates` → `[]`; render → 38 nodes, 74 edges). BREAKING CHANGE: gatekeeper `numGameThreads` 20→18, cycle-1 gating not skipped (gates vs. random baseline), `transformer_trunk_b5c48h3tfr` retired.
   - `e7159cb` — c01/c02 admitted on `env-toolchain-b200`; claims append-batch → `{"appended": 25, "skipped": 0}`; obligations `o07/o10/o14/o16` discharged; new `o19–o24` opened.
   - `062e8b4` — seat A/B reconciliation table (30/38 concepts agree, 8 adjudicated).
   - `6a97895`! — `DESIGN.md` conflicts resolved in place (BREAKING CHANGE: thread/scratch/gating defaults overturned, see commit body).
   - `a9461b6` — 7 task packets rewritten for the reconciled READY frontier (`cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime`, `data_budget`, `env_build`, 2 code-map probes).
   - `ec35ff8` — `RESEARCH_STATE.md` revised in place after reconciliation; `wc -c` = 8775 (≤ 10240).
   - `ace9d0c` — **human decisions landed**: `infra(policy,ktg): withdraw the CPU cap and set a 500 GiB scratch budget` — `mission.json` `compute.cpuCapPerJob=null`, `compute.scratchBudgetGiB=500`, `decisions[]` log (no CPU usage limit; 500 GiB scratch; run on `b200` while `b300` is reserved); `compute-budget` `check.sh` reports CPUs without enforcing (verified: `check.sh --gpus 1 --cpus 60 --partition b200` → OK, `--gpus 8 --partition h100` still exits 1). Affects obligation `o22_cpu_policy_scope`, assumption `a11_cpu_policy_summed`, node `data_budget` / obligation `o04_scratch_budget`.
   - **Caveat `[OPEN]`**: the decisions are landed in `mission.json` (`ace9d0c`) but **not yet propagated downstream**: `DESIGN.md` §5 and `tasks/data_budget/implementation.md` still hard-code the 200 GiB hard cap / 180 GiB guard (`214748364800` / `193273528320` B) superseded by the 500 GiB decision, and claim-ledger rows `o22_cpu_policy_scope` (open), `a11_cpu_policy_summed` (active), `o04_scratch_budget` (open, still states 200/180 GiB) have not been waived/relaxed/amended to match. This observer note records the decisions and the gap only; discharging the ledger rows is a worker/brain append (executable admission, `discharged_by`/`reduction_obligation` references), not an observer append, and is queued as a wave-1 item for the `data_budget` worker (see Next-3 below).
   - **Wave 1 in flight (uncommitted at time of this note)**: untracked working-tree content under `results/ktg/paper_1902.10565/codes/{cfg,data_budget,eval,loop}/` and `evidence/{data_budget,paper_code_map_search,paper_code_map_training}/` — the dispatched wave-1 workers (`cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime`, `data_budget`, code-map probes) are actively producing artifacts. Left untouched by this observer commit per scope (`git add` restricted to `progress/ktg-train` and `results/ktg/GLOBAL_DAG.md`).

3. **Next-3 roadmap** (wave 1, already dispatched per `HUMAN_DIGEST.md`) — checked against `crash-triage`: no prior trial exists for any of these four nodes (`error_database` has 4 rows total: 2 `acquire`, 2 `env_build`), so none is a same-mode repeat; crash-triage n/a for all three.
   (a) `cfg_9x9_override` + `tiny_model_export_smoke` in parallel (independent predecessors: `env_build` only) — write `codes/cfg/{selfplay,gatekeeper}_9x9.cfg`, `codes/loop/train_9x9.sh`, `check_cfg_9x9.sh`; export `b7c96h3tfrs` → block histogram {7,7} → `benchmarknn -require-exact-nnlen -json` + gtp.
   (b) `loop_resume_under_walltime` — `codes/loop/loop.sbatch` + `synchronous_loop_9x9.sh` + reordered exporter; static checks only this wave (`bash -n`, `afterany`, failcount, `check.sh --gpus 1 --cpus 24`).
   (c) `data_budget` — **must reconcile the 200/180 GiB constants against the new 500 GiB human decision before writing `loop.sbatch`'s guard greps**; this is new information since `a9461b6` shipped the task file at 200/180 GiB. Flagging so the wave-1 worker does not ship a stale guard.

4. **Simplification flag** — `python3 phys-agentic-loop/_common/loop_policy.py simplification-status --paper arxiv-1902.10565 --task env_build`:
   ```
   {
     "status": "required",
     "best_iteration": 2,
     "best_metric_value": 6,
     "metric_name": "smoke_steps_passed",
     "recommendation": "before the next promise-tag commit, append a change_type='refactor' row that maintains the metric; revert if it drops."
   }
   ```
   `status == required` → the next `env_build`-adjacent commit (env-side changes touched by `data_budget`'s scratch-constant fix, or any future `env_build` re-run) MUST carry `change_type=refactor`, not another `structural`/`exploratory` change, until this clears.

5. **Verifier output** (verbatim, re-run this iter):

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py progress --paper arxiv-1902.10565` → 38 rows; status histogram **solid=2** (`env_build`, `engine_ffn_swiglu_constraint`), **preliminary=14**, **hypothesis=21**, **future=1**; `n_trials=0` on every row (no per-node executed trial yet — the two executed error rows are stage-scoped `acquire`/`env_build`, not yet re-attached to a DAG `node_id`). Full JSON (38 objects) reproduced by re-running the command above; representative rows:
   ```json
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::env_build", "status": "solid", "n_knowledge": 2, "n_trials": 0, "pass": 0, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::engine_ffn_swiglu_constraint", "status": "solid", "n_knowledge": 1, "n_trials": 0, "pass": 0, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::cfg_9x9_override", "status": "hypothesis", "n_knowledge": 2, "n_trials": 0, "pass": 0, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::data_budget", "status": "hypothesis", "n_knowledge": 2, "n_trials": 0, "pass": 0, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::loop_resume_under_walltime", "status": "hypothesis", "n_knowledge": 3, "n_trials": 0, "pass": 0, "fail": 0}
   ```
   (37 more rows omitted here for length; identical to a fresh `progress` run — none amended since `logic.md`/`GLOBAL_DAG.md` were last rendered.)

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py duplicates --paper arxiv-1902.10565` → `[]`

   `python3 phys-agentic-loop/_common/loop_gate.py status` (no `--paper` flag — v1 solo-loop CLI; this v2 orchestrator mission has no `.claude/ralph-loop.local.md`, so `loop_active: null`, but the ledger-derived signal is live):
   ```json
   {
     "decision": {"decision": "continue", "reason": "iteration 0/1000; progress solid=2 results=1 discharged=0; no_progress 0/8, stuck 0/3", "iteration": 0, "max_iterations": 1000, "no_progress_streak": 0, "no_progress_limit": 8, "stuck_streak": 0, "stuck_counter_limit": 3, "signal": {"solid_nodes": 2, "pass_rows": 3, "admitted_results": 1, "discharged_results": 0, "total_trials": 4, "max_ledger_iteration": 2}},
     "gate_state": {"last_progress": [2, 1, 0], "last_iteration": 0, "no_progress_streak": 0, "stuck_streak": 0, "last_decision": "continue"},
     "state_file": "/weka/home/schmidt/ssci-haiyangw/az/.claude/ralph-loop.local.md",
     "loop_active": null
   }
   ```
   No-progress streak 0/8, stuck 0/3, decision `continue` — the gate does not block wave 1.
