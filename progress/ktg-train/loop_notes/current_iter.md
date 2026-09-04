# current_iter — ktg-train (iteration 3 / wave 2: smoke job + knobs)

1. **Paper anchor** — iteration 3 executes the wave-2 plan committed at iteration 2:
   the smoke allocation (`synchronous_loop_smoke`, job 298712 + attempt-2 job 299259)
   and its CPU-only follow-on (`derive_cycle_knobs_9x9`). Three `logic.md` nodes move:
   `synchronous_loop_smoke` hypothesis→**preliminary** (6 trials, 2 pass / 4 fail),
   `derive_cycle_knobs_9x9` hypothesis→**preliminary** (2 trials, 1 pass / 1 fail),
   `loop_resume_under_walltime` gains its fifth repair round (o35 base-10 fix, o36
   opened) and stays preliminary (13 trials, 7 pass / 3 fail / amended). Four more
   nodes promote to **solid**: `transformer_trunk_b7c96h3tfrs`, `head_gpool_degeneracy_9x9`,
   `data_format_pos_len` (compression corrected to 353.8 B/row), `train_resume_semantics`.
   Knowledge status mix is now solid=6, preliminary=15, hypothesis=16, future=1 (38
   nodes; was solid=2/preliminary=17/hypothesis=18/future=1 at iteration 2).

2. **What shipped this iter** — 8 commits `cde419c..HEAD` (chronological):
   `0c6d38d` **fix**: every chain-state file (`.cycles_completed`, `.failcount`,
   `.chain_depth`) now reads through a base-10 `read_counter()` guard — bash's
   leading-zero-as-octal bug (`08`/`09` aborting the enclosing `finalize()` list, the
   o26 failure class) is closed → `9fdeb6b` validator admits **o35 discharged**
   (existence_only, 15 seeds × 3 state files reach `finalize()`), amends
   `r_loop_resume_under_walltime_static`, opens **o36** non-blocking (writes and
   operator knobs still fail open: an unwritable `.failcount` or `KTG_MAX_FAILS=abc`
   lets a crash loop run unbounded to `KTG_MAX_CHAIN=200`) → `5bb85ad` **smoke job
   298712 runs** (b200 gb207, COMPLETED 0:0, 00:05:53): all six legs execute, 2 loop
   cycles complete (`t9-s1216-d1221`, `t9-s2528-d2534`), o30 discharged in-allocation,
   real-net selfplay/gatekeeper measure **25 OS threads against 24 declared** (+3
   CUDA-runtime threads `debugSkipNeuralNet` never creates), 5 instrument/accounting
   defects found and repaired (env.sh not sourced in the job's own shell,
   node-wide `ps -e` sweeping foreign pids, `Model.trunk`→`Model.blocks` AttributeError,
   missing npz sidecars, `run_leg` swallowing soft-leg failure) → `0fab404` validator
   admits the job-298712-only groups: `r_synchronous_loop_smoke` empirical, **c07
   admitted** (narrowed to `modelstobetested/<name>`), o19 discharged, **c06 refuted**
   for the real-net clause (`r_smoke_threads_realnet`), `r_smoke_throughput_tiny`
   empirical, o03 re-opened with the measurement, **o37 opened** (monitor
   append + evidence-overwrite bug corrupting attempt-2's audit) → `98d6c42`
   **attempt-2 job 299259 runs** (resumes at leg D1, sacct FAILED 1:0 — correctly, the
   thing attempt 1 couldn't report): S11/S12 probes PASS 4/4 and 6/6 (kill-and-resume
   4992→14976 samples, 0 re-initialisations); worker's own read of the data claims
   the `full_frac` band (0.342 vs. predicted 0.25) and c10's byte bound (10.944
   KiB/game > 10 KiB) are both refuted, o37's worker-half repaired (per-job-id
   evidence files, ppid-chain-filtered sampler) → `375cfc0` **feat**: `derive_knobs.py`
   + `check_knobs_9x9.py` authored, the 9x9 production-cycle knobs derived from the
   measured 32.3 rows/game (shuffle window, not the train bucket, is what binds at
   9x9 scale), candidate `r_cycle_knobs_9x9_derived` proposed conditional, DESIGN
   §1 `[BLOCKING]`→`[SOLID]` → `97b44ba` validator **rejects the full_frac
   refutation** as a binning artefact (cheap searches inherit visits into a reused
   subtree, `play.cpp:1147`/`search.cpp:509,579-580` — 667/7401 values sit strictly
   between 100 and 600; `> cheapSearchVisits` reproduces 0.34171, `== maxVisits`
   gives 0.2516; the band is left **unchecked**, not admitted or refuted), **admits
   c10 refuted as written** (10.944/12.06 KiB per game on disk), promotes the 4
   nodes above to solid, admits c05/re-admits c04, o02 opened, o37 discharged,
   **o38 opened** (worker: fix the discriminator, re-propose the band) →
   `c5d3c32` validator **admits `r_cycle_knobs_9x9_derived` conditional** (every
   knob re-derives independently, 9 break attempts fail as they must) with the
   claim **narrowed on the export ramp**: the worker's "exactly one export per
   cycle from cycle 13" does not survive `-no-repeat-files`/`-quit-if-no-data`
   (`training_data_generator.py:35`, `train.py:1487-1489`) — cycles 1-4 export
   nothing, **the first candidate exports at cycle 5** and is gated at cycle 6;
   exactly-one-per-cycle only once the window holds 5×samples-per-epoch rows
   (about cycle 16 if cycle 6 is accepted). o24/o13 discharged, o03 re-opened,
   **o39/o40/o41 opened**.
   Net this iter: **8 new results admitted** (5→13 total: 7 empirical, 2
   conditional, 2 refuted, 1 existence_only, 1 unchecked), **obligations 36→42**
   (23 discharged / 17 open / 2 waived; discharged this iter: o13, o19, o24, o30,
   o35, o37 — o37 opened then discharged same iter; opened this iter: o02, o36,
   o38, o39, o40, o41), claims 16 total now 5 admitted / 3 in_progress / 6 open /
   **2 refuted** (c06, c10 — both refuted *as written*, not the underlying pipeline:
   c06's selfplay/train/shuffle clauses hold, only the real-net-CUDA-context
   clause overruns; c10's rows/game clause holds, only the on-disk-bytes clause
   overruns by 9-20%).

3. **Next-3 roadmap** (checked against `crash-triage`):
   (a) **o39_cpus_per_task_wiring** (blocking before `selfplay_stage`) —
   `loop.sbatch` still declares `--cpus-per-task=24`/`REQ_CPUS=24` against the
   derived 32; owner is `loop_resume_under_walltime` (`derive_cycle_knobs_9x9`'s
   task file forbids it touching that file). `crash-triage --task
   loop_resume_under_walltime` → `pivot_structural` still holds from iteration 2
   (unchanged this iter, no new failing row on that task) — o39's repair should
   land as a `structural` change, not a bare constant edit, consistent with that
   verdict. (b) **o40_export_ramp_first_candidate_cycle5** — correct
   `derive_knobs.py`'s `window_by_cycle` model (it still assumes real-net rows
   from cycle 2, which is unreachable before a candidate is accepted) plus the
   four prose sites (`derivation.md` §3, `knobs_9x9.env` comment,
   `check_knobs_9x9.py` output already correct, `DESIGN.md` §§1/9) that still say
   "cycle 13"; `crash-triage --task derive_cycle_knobs_9x9` → `fix_and_retry`
   (below, first failure on this task) — a direct debug-and-retry, not a pivot.
   (c) **o38_full_frac_discriminator_reused_tree** (non-blocking,
   `paper_code_map_search`) — switch `probe_search_9x9.py`'s full-search rule to
   `Root visits == maxVisits`, keep the histogram, re-bin the surviving 60-game
   run and re-propose assertion (a); no allocation needed. In parallel:
   `o02_databoardlen_poslen_9` (newly blocking, opened this iter) and
   `o03_thread_budget_24cpu` (blocking, re-opened) both gate `shuffle_stage` /
   `selfplay_stage` and are unresolved by anything landed this iter.

4. **Simplification flag** (both tasks touched this iter):
   `python3 phys-agentic-loop/_common/loop_policy.py simplification-status --paper arxiv-1902.10565 --task synchronous_loop_smoke`:
   ```json
   {"status": "required", "best_iteration": 3, "best_metric_value": 4,
    "metric_name": "core_candidate_rows_admitted",
    "recommendation": "before the next promise-tag commit, append a change_type='refactor' row that maintains the metric; revert if it drops."}
   ```
   `python3 phys-agentic-loop/_common/loop_policy.py simplification-status --paper arxiv-1902.10565 --task derive_cycle_knobs_9x9`:
   ```json
   {"status": "required", "best_iteration": 2, "best_metric_value": 16,
    "metric_name": "checks_passed_of_16",
    "recommendation": "before the next promise-tag commit, append a change_type='refactor' row that maintains the metric; revert if it drops."}
   ```
   Both `status == required` → the next promise-tag commit on either task must
   carry `change_type=refactor` and hold its metric (4 core rows / 16 checks) or
   revert. `data_budget` and `loop_resume_under_walltime`'s iteration-2
   `required` flags are unchanged (no commit against either task's own files
   landed this iter beyond `loop_resume_under_walltime`'s o35/o36 repair, which
   is a distinct task from `data_budget`).

5. **Verifier output** (verbatim, re-run this iter):

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py progress --paper arxiv-1902.10565` →
   38 rows; status histogram **solid=6, preliminary=15, hypothesis=16, future=1**.
   Representative rows:
   ```json
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::synchronous_loop_smoke", "status": "preliminary", "n_knowledge": 4, "n_trials": 6, "pass": 2, "fail": 4}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::derive_cycle_knobs_9x9", "status": "preliminary", "n_knowledge": 4, "n_trials": 2, "pass": 1, "fail": 1}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::loop_resume_under_walltime", "status": "preliminary", "n_knowledge": 4, "n_trials": 13, "pass": 7, "fail": 3}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::transformer_trunk_b7c96h3tfrs", "status": "solid", "n_knowledge": 4, "n_trials": 1, "pass": 1, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::data_format_pos_len", "status": "solid", "n_knowledge": 4, "n_trials": 0, "pass": 0, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::data_budget", "status": "hypothesis", "n_knowledge": 2, "n_trials": 9, "pass": 4, "fail": 5}
   ```

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py duplicates --paper arxiv-1902.10565` → `[]`

   `python3 phys-agentic-loop/_common/loop_gate.py status`:
   ```json
   {
     "decision": {"decision": "continue", "reason": "iteration 0/1000; progress solid=6 results=10 discharged=0; no_progress 0/8, stuck 0/3", "iteration": 0, "max_iterations": 1000, "no_progress_streak": 0, "no_progress_limit": 8, "stuck_streak": 0, "stuck_counter_limit": 3, "signal": {"solid_nodes": 6, "pass_rows": 23, "admitted_results": 10, "discharged_results": 0, "total_trials": 40, "max_ledger_iteration": 8}},
     "gate_state": {"last_progress": [6, 10, 0], "last_iteration": 0, "no_progress_streak": 0, "stuck_streak": 0, "last_decision": "continue"},
     "state_file": "/weka/home/schmidt/ssci-haiyangw/az/.claude/ralph-loop.local.md",
     "loop_active": null
   }
   ```
   (The gate's own `admitted_results`/`pass_rows` counters read a subset of the
   ledger's admission events, not the 13-distinct-result_id / 20-row totals this
   note computed directly from `results.jsonl` — both are internally consistent
   with `dag_mermaid.py progress`'s 6 solid nodes.) No-progress 0/8, stuck 0/3,
   decision `continue` — the gate does not block wave 3.

   `python3 phys-agentic-loop/_common/loop_policy.py crash-triage --paper arxiv-1902.10565 --task synchronous_loop_smoke --domain numerical`:
   ```json
   {"recommendation": "escalation", "reason": "3 consecutive failures with failure_mode='uncategorized_numerical'; alignment.md §0 + §3 — switch methodology entirely", "last_failure_mode": "uncategorized_numerical", "consecutive_same_mode": 3, "domain_hint": "switch numerical method — implicit ↔ explicit integrator, FD ↔ spectral, direct mode-sum ↔ contour deformation. Pure mesh / tolerance / step-size changes do not count as structural."}
   ```
   `python3 phys-agentic-loop/_common/loop_policy.py crash-triage --paper arxiv-1902.10565 --task derive_cycle_knobs_9x9 --domain numerical`:
   ```json
   {"recommendation": "fix_and_retry", "reason": "first failure on this task — debug and retry", "last_failure_mode": "assumption_too_broad"}
   ```
   **Caveat** (same shape as iteration 2's for `data_budget`): `crash-triage`
   reads only the failing-row subsequence. `synchronous_loop_smoke`'s 4
   fail-or-refuted rows (c06 refuted, c10 refuted, `r_smoke_threads_realnet`
   refuted, the withdrawn full_frac refutation) sit alongside 2 admitted-pass
   candidate groups (`r_synchronous_loop_smoke`, `r_smoke_probe_training`/
   `r_smoke_probe_search` empirical) from the SAME two jobs — the node is not
   stuck, it produced 8 admitted results this iteration. The literal
   `escalation` verdict is recorded verbatim per the observer cadence; whoever
   next touches `synchronous_loop_smoke` (o38's discriminator fix) should read
   it as "the next change should be structural, not a threshold nudge" rather
   than "the task has failed three times in a row unproductively."
   `derive_cycle_knobs_9x9`'s `fix_and_retry` is unambiguous — its one fail row
   is the task file's own defective §2 command (documented, not yet repaired;
   `check_knobs_9x9.py` is the adopted replacement).
