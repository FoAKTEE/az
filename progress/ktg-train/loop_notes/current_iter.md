# current_iter — ktg-train (iteration 4 / wave 3: pre-launch repairs, the L40S decision, the production-chain launch, and the 7x7 convergence test)

1. **Paper anchor** — iteration 4 closes wave 3: the six pre-launch repairs planned at
   iteration 3 (o39 32-CPU wiring, in-link stage monitor, o02 pos_len-9 refusal, o41
   missing-key strictness, o40 export-ramp model, o38 full-search re-binning) all land
   and are cross-model admitted; the human authorizes L40S for the production chain,
   which is measured runnable and then used; the first 9x9 production chain link
   launches and is RUNNING; and, on a separate human directive, a converged 7x7 test
   run launches, learns visibly, and is switched from a time cap to a measured-plateau
   stopping rule. `logic.md` moves: `playout_cap_randomization` preliminary→**solid**
   (the re-binned full-search fraction, 0.2516, sits inside [0.20, 0.30] on two
   independent instruments and an independent second run); one new node,
   `converged_test_7x7`, enters at **hypothesis**. Knowledge status mix is now
   solid=7, preliminary=14, hypothesis=17, future=1 (39 nodes; was solid=6/
   preliminary=15/hypothesis=16/future=1/38 nodes at iteration 3). Every other
   production-chain node (`selfplay_stage`, `shuffle_stage`, `train_stage`,
   `export_stage`, `gatekeeper_stage`, `bootstrap_accepted_model`,
   `verify_preemption_resume`, `loop_failure_circuit_breaker`,
   `measure_stage_throughput`, `count_gatekeeper_acceptances`) stays hypothesis —
   the chain has run one cycle, not the twenty-plus needed to settle them.

2. **What shipped this iter** — 30 commits `ce56fbb..fd09b92` (chronological, grouped):

   **Planning** (`ce56fbb`) — `tasks/wave3_prelaunch_repairs/implementation.md`
   (R1–R6) and `tasks/production_chain_9x9/implementation.md` (P1–P12, the launch
   command, abort rules, link-3 decision table) authored against the ledger-computed
   frontier (`data_budget`, `verify_preemption_resume`, `loop_failure_circuit_breaker`
   READY).

   **Six pre-launch repairs, all `[SOLID]`** — `fb94bac` R1: `loop.sbatch` declares 32
   CPUs (was 24), reads `knobs_9x9.env` at `set -a` source, refuses to chain on an
   unresolved `REQ_CPUS`, adds three exit-2 pre-flight failures (granted CPUs
   mismatch, `numGameThreads` mismatch, a knob file that tries to retune the breaker).
   `56f2979` R6: `stage_monitor.sh` now runs inside every chain link (root pid = the
   wrapper's own pid, phase-retagged per cycle), not just the smoke wrapper — the
   thread/GPU measurement o03/o39(c)/c09 all need. `633b80b` R5: `check_pos_len(),`
   a ~1 ms/file zip-header read, refuses to shuffle any npz that is not `dataBoardLen
   9` before every shuffle stage, closing o02's discard clause. `e2d258a` R3:
   `derive_knobs.py` raises `SystemExit` naming any missing measured key instead of
   substituting a hard-coded constant (closes o41 — a validator break attempt had
   shown `check_knobs_9x9.py` could PASS on deleted rate keys via a silent `nan`).
   `e4bf9bf` R2: the export-ramp model is corrected — cycles 1–4 are one-epoch
   random-net cycles (`-quit-if-no-data` exits clean on an empty epoch), so **the
   first candidate exports at cycle 5**, gated at cycle 6, not "exactly one per
   cycle from cycle 13" as iteration 3 had it (o40). `272b887` R4: the full-search
   discriminator in `probe_search_9x9.py` moves from `Root visits > cheapSearchVisits`
   to `Root visits == maxVisits` — cheap searches on a reused MCTS subtree inherit
   visits and were mis-binned as full (667 of 7401 on the smoke's real-net probe),
   turning the false 0.3417 refutation of the [0.20, 0.30] band back into 0.2516,
   inside it (closes o38).

   **Validation** (`3a3532c`) — cross-model admission of all six repairs under the
   validator's own shim harness (46-link regression + 51-link seed matrix, byte-
   identical dry runs); the R2 ramp is independently re-derived from `train.py`'s
   whole-shuffled-file consumption and shown to hold beyond cycle 5 too (exports at
   ≈5, 10, 15, 19, 22 — "exactly one per cycle" is unreachable, not just mis-dated).
   `r_loop_resume_under_walltime_static` and `r_cycle_knobs_9x9_derived` amended;
   `r_smoke_full_frac_rebinned` admitted new; `playout_cap_randomization` → solid;
   **o39, o02, o41, o38 discharged**; o40 stays open, narrowed and **non-blocking**
   ((c), the executed first-export cycle, is now the chain's to close); **o42, o43
   opened** (both non-blocking: a knob file whose sourcing can abort the wrapper
   before its resubmit/EXIT trap; four typed constants `derive_knobs.py` still
   carries that a job, not `check_knobs_9x9.py`, could supply).

   **First chain-launch attempt and re-linking** — `6e4117d` submits job 299366 (1
   GPU / 32 CPUs / 3 links × 2-23:30:00 on B200; 8/8 pre-flight PASS); its backfill
   estimate (~31 h, shared by every ≥1-day b200 request) shows a 71.5 h ask cannot
   backfill, so `d01f6f2` re-links into **nine 23.5 h links** (`SBATCH_TIMELIMIT`
   propagated by `--export=ALL`, no script edited) as job 299461 — same estimate
   persists (`55083ec`, bounded wait, still PENDING).

   **The L40S decision** — `d04b144` records the human's 2026-09-04 decision (b200
   or l40s, whichever frees first) in `mission.json`; `65372a0` holds the
   re-submission on two measured blockers (no sm_89 image in the built binary by
   `cuobjdump`; `resubmit()`'s `--partition` argv beats `SBATCH_TIMELIMIT`'s
   environment-variable path, so a multi-partition link 1 would still pin links 2–9
   to b300/b200). `4db08ae` **settles the first blocker**: job 300987 on gl111 runs
   the mission binary natively on an L40S (sm_86 cubin loads under CUDA's
   minor-version rule) — `runtests` clean, benchmark 2401.88 visits/s vs. the B200's
   2322.17, zero "no kernel image" diagnostics, binary sha256 unchanged. `4c30b00`
   **settles the second**: `pick_partition()` now reads its candidate list from
   `KTG_PARTITIONS` (comma-joined sets summed correctly by `sinfo`), fixing o44.
   `05ebce1` re-submits as job **301099** across `b200,l40s` — start estimate moves
   from 2026-09-06T21:57 to **2026-09-04T21:54**, about two days sooner; a finding,
   not a tuning, that on l40s the 32-CPU request is what waits, not the GPU. `7ff4794`
   cross-model admits the partition-inheritance repair (70/70 fixture cells, 22-link
   whole-wrapper propagation, live-cluster cross-check) and the L40S row as
   `runnable`, not yet production-characterised; **o44 opened and discharged; o45
   opened and discharged; a04_b200_fallback restated**. `ea9a0e0` finds one residual
   risk — a successor queued when it evaluates `pick_partition()` can pin to a
   momentarily-free b300 and never re-evaluate — not live before link 3 (gb301 is
   reserved to 2026-09-07), carried as a **monitoring rule**, no code change,
   proposed action countermanded. `fb3651b` closes the bounded wait, still queued.

   **The chain runs** — `fd09b92`: job **301099 is RUNNING on gl111 (l40s) since
   2026-09-04T18:52:13**. Cycle 1: selfplay 87 s, shuffle 17 s (train running at
   read time); every P-row read is within tolerance (31.170 rows/game vs. derived
   31.675; nlwp_max 22/4/12 all ≤ 32; scratch guard OK twice). Random-net selfplay
   runs 41 380 games/h on l40s — 7.4× the smoke's 5569.5 — because
   `logSearchInfo=false` in production vs. `true` in every smoke probe, not a
   mystery. Successor **305318** is correctly queued (`afterany:301099`,
   `b200,l40s`, `23:30:00`) but the wrapper's own log wrongly reports "chain not
   extended": `resubmit()`'s `out=$(sbatch ... 2>&1)` folds the site's two-line
   STDERR "BILLING" banner into the captured string, failing the `^[0-9]+$` test
   though `sbatch` succeeded. Chain continuity, the breaker and the STOP brake are
   all unaffected (each has an independent enforcement path); `cancel_successor()`
   is dead (`SUCCESSOR` is always empty) and every link's log will misreport —
   **a one-line fix, not yet landed**, expected before link 1's TIMEOUT
   (~2026-09-05T18:22) so link 2 picks it up automatically.

   **Phase-0 readers** (`959b3ed`) — `chain_status.sh`, `throughput_report.py`,
   `check_metrics.py`, `freeze_baseline.py`, `declare.py`, `match_first_latest_9.cfg`
   + `match.sbatch` authored and dry-run verified against the smoke tree; these are
   what every P-row in `production_chain_9x9` reads.

   **The 7x7 convergence test** — `b250b68` records the human's directive (a short
   1-GPU run while the 9x9 chain queues, produce a loss curve — the 9x9 smoke's own
   `metrics_train.json` was 0 rows, `train.py`'s 100-batch print interval never
   firing on an 8-batch epoch). `9e77d0d` parameterises the loop by board length and
   loss interval (three `${VAR:-default}` additions, 9x9 behavior byte-for-byte
   unchanged, 10/10 checks) and authors the 7x7 cfgs/scripts. `01ffdf8` submits job
   301063; `3df0fe6` finds `train.py`'s 1/20 warmup would have held the whole 6 h run
   at LR/20 (the 250 k–2 M-sample horizon is calibrated for 19x19-scale runs, not a
   150 k-sample test) and adds `-lr-scale-auto` (upstream's own 8.0/20 = 0.4×
   multiplier) via a new passthrough variable; resubmitted as 301092. `2c89107`
   finds the deferral was a **reservation**, not GPU scarcity (gb301 free but
   claimed at 23:00 local); trims the request to 5:15:00 to fit before it —
   job **301096 starts in 2 s on gb207 (B200)**. `3719a6e` records cycle 1: p0loss
   3.9209→3.4905 (already below the uniform baseline ln(50)=3.9120), vloss
   1.2977→0.9239, a dense per-batch loss log (46 rows in one cycle, closing the
   defect this node exists to fix), and finds the logged loss is an EMA (decay
   0.999/batch) that lags the instantaneous value — every threshold in the task
   file is conservative, not optimistic. `93d6e07` drafts (not appends) the two
   candidate result rows and records the first gatekeeper acceptance (40.5–34.5,
   75 games). `c6dd8d0` records the human's second directive — no hard time cap,
   train to a measured plateau. `3d86b7f` implements it: `plateau_check.py` (FLAT =
   both p0loss and vloss trailing-window deltas < 1%; PLATEAU = FLAT twice AND no
   gatekeeper acceptance in 15 cycles; DIVERGING = p0loss rose > 5%), a continuation
   `.sbatch` chaining same-BASEDIR segments by `afterany`, `PLATEAU`/`ABORT` marker
   files, and a re-initialisation assertion. Continuation segment **301186** is
   queued (`Dependency=afterany:301096`, unfulfilled), 12-segment safety cap ≈ 4
   GPU-days — a bound, not a target.

   **As of this note's close (2026-09-04T19:02 local / 23:02Z)**, from
   `evidence/converged_7x7/status_log.txt` (worker-written, live): job 301096 has
   completed **46 cycles**, ~1,190,208 samples, p0loss 3.9209→**1.551** (min 1.551),
   vloss 0.9239→**0.565** (min 0.5249), **43 accepted / 2 rejected** exports — the
   loss curve is still falling steeply, well short of a plateau. Job 301099 (9x9
   chain link 1) has run **00:11** on l40s past cycle-1 selfplay/shuffle, train
   stage in progress.

   Net this iter: **2 new results admitted** (13→15: `r_smoke_full_frac_rebinned`,
   `r_env_l40s`, both empirical), **obligations 42→46** (23→29 discharged / 17→15
   open / 2 waived; discharged this iter: o02, o38, o39, o41, o44, o45; opened this
   iter: o42, o43, o44, o45 — o44/o45 opened and discharged the same iter), claims
   unchanged at 16 (5 admitted / 3 in_progress / 6 open / 2 refuted — no claim
   status moved this wave, only obligations and results), assumptions unchanged at
   12 (11 active / 1 retired — a04 restated in place, not renumbered), error-ledger
   trials 40→61.

3. **Next-3 roadmap** (checked against `crash-triage`):
   (a) **land the `resubmit()` successor-id fix** (non-blocking, chain healthy
   without it) — `crash-triage --task loop_resume_under_walltime` →
   `escalation` (3 consecutive `uncategorized_numerical` fails on the raw
   sequence: this is the same caveat as iterations 2–3 — the task also produced
   two admitted-pass repair rows this iteration (o44/o45), so the verdict reads as
   "the next change should be structural" (a proper `$()`-capture fix, not a
   grep tweak), not "the task is stuck." Land before link 1's TIMEOUT
   (~2026-09-05T18:22) so link 2 self-corrects. (b) **keep the chain monitoring
   cadence** — `crash-triage --task production_chain_9x9` → `fix_and_retry`
   (first failure on the task — the wrapper's own log-line bug, not a chain
   defect); read 2 at ~3 h, then every 3 h through the first 24 h, section-C
   boundary check at link 1's TIMEOUT, watch link ≥3 boundaries for the b300-
   pinning stall per `ea9a0e0`'s monitoring rule. (c) **keep the 7x7 plateau
   watch** — `crash-triage --task converged_test_7x7` → `no_action` (no
   failing rows yet); read `plateau_check.py`'s verdict after every cycle;
   segment 301186 already queued behind 301096, no action needed unless a
   `PLATEAU`/`ABORT` marker fires or the segment cap (12) is reached. No new
   allocation is planned for `data_budget`, `verify_preemption_resume` or
   `loop_failure_circuit_breaker` — the running chain's own cycle-1 guard log and
   link-1 walltime end are their evidence, as decided at iteration 3.

4. **Simplification flag**: **seven** tasks now carry `simplification-status:
   required` simultaneously — three carried from iteration 3
   (`data_budget` best_iteration 8 `guard_exit_contract_cases_matched=25`;
   `loop_resume_under_walltime` best_iteration 8
   `partition_scenarios_resolving_and_propagating_as_claimed=59`;
   `synchronous_loop_smoke` best_iteration 3 `core_candidate_rows_admitted=4`;
   `derive_cycle_knobs_9x9` best_iteration 2 `checks_passed_of_16=16`) and three
   opened this wave (`wave3_prelaunch_repairs` best_iteration 6
   `full_frac_rebinned_at_max_visits=0.2516`; `production_chain_9x9` best_iteration
   6 `rows_per_game_random_net=31.17`; `converged_test_7x7` best_iteration 2
   `effective_lr_multiplier_over_the_run=0.4`). None has yet been resolved by a
   qualifying `change_type=refactor` commit that holds its metric — this is
   recorded verbatim per the observer cadence, not acted on: every task above is
   mid-execution against a live allocation, and a `refactor`-only commit against a
   running chain's own scripts is forbidden by `production_chain_9x9` §13 while
   the chain is up.

5. **Verifier output** (verbatim, re-run this iter):

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py progress --paper arxiv-1902.10565`
   → 39 nodes; status histogram **solid=7, preliminary=14, hypothesis=17, future=1**.
   Full output (39 rows) reproduced by re-running the command; representative rows:
   ```json
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::playout_cap_randomization", "status": "solid", "n_knowledge": 4, "n_trials": 1, "pass": 1, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::converged_test_7x7", "status": "hypothesis", "n_knowledge": 1, "n_trials": 2, "pass": 1, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::derive_cycle_knobs_9x9", "status": "preliminary", "n_knowledge": 4, "n_trials": 5, "pass": 3, "fail": 2}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::loop_resume_under_walltime", "status": "preliminary", "n_knowledge": 4, "n_trials": 20, "pass": 13, "fail": 4}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::selfplay_stage", "status": "hypothesis", "n_knowledge": 2, "n_trials": 5, "pass": 4, "fail": 1}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::measure_stage_throughput", "status": "hypothesis", "n_knowledge": 1, "n_trials": 1, "pass": 1, "fail": 0}
   ```

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py duplicates --paper arxiv-1902.10565` → `[]`

   `python3 phys-agentic-loop/_common/loop_gate.py status`:
   ```json
   {
     "decision": {"decision": "continue", "reason": "iteration 0/1000; progress solid=7 results=12 discharged=0; no_progress 0/8, stuck 0/3", "iteration": 0, "max_iterations": 1000, "no_progress_streak": 0, "no_progress_limit": 8, "stuck_streak": 0, "stuck_counter_limit": 3, "signal": {"solid_nodes": 7, "pass_rows": 40, "admitted_results": 12, "discharged_results": 0, "total_trials": 61, "max_ledger_iteration": 8}},
     "gate_state": {"last_progress": [7, 12, 0], "last_iteration": 0, "no_progress_streak": 0, "stuck_streak": 0, "last_decision": "continue"},
     "state_file": "/weka/home/schmidt/ssci-haiyangw/az/.claude/ralph-loop.local.md",
     "loop_active": null
   }
   ```
   (As at iteration 3, the gate's own `admitted_results`/`pass_rows` counters read a
   subset of ledger admission events, not the 15-distinct-result_id / 25-row totals
   this note computes directly from `results.jsonl` — both readings are internally
   consistent with `dag_mermaid.py progress`'s 7 solid nodes.) No-progress 0/8,
   stuck 0/3, decision `continue` — the gate does not block iteration 5.

   `crash-triage --task production_chain_9x9 --domain numerical`:
   `{"recommendation": "fix_and_retry", "reason": "first failure on this task — debug and retry", "last_failure_mode": "uncategorized_numerical"}`
   `crash-triage --task converged_test_7x7 --domain numerical`:
   `{"recommendation": "no_action", "reason": "no failing rows for this task"}`
   `crash-triage --task loop_resume_under_walltime --domain numerical`:
   `{"recommendation": "escalation", "reason": "3 consecutive failures with failure_mode='uncategorized_numerical'; alignment.md §0 + §3 — switch methodology entirely", "consecutive_same_mode": 3}`
   **Caveat** (same shape as iterations 2–3's for other tasks): the `escalation`
   verdict on `loop_resume_under_walltime` reads the failing-row subsequence only;
   the same task landed two admitted repair rows (o44, o45) this iteration. Read as
   "the next fix should be structural" (proper subshell/`$()` output capture), not
   as an unproductive loop.
