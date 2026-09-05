# current_iter — ktg-train (iteration 5 / wave 3: option C knob change, link 1 -> link 2 boundary)

1. **Paper anchor** — iteration 5 closes on the chain link-1/link-2 boundary. Node
   `scale_data_window` moves hypothesis → **preliminary** (its first two results: the
   whole-file-epoch measurement and the option-C application/boundary confirmation).
   `derive_cycle_knobs_9x9` stays preliminary; its result `r_cycle_knobs_9x9_derived`
   is amended conditional → **empirical** by the worker (commit 35f567f's timestamp,
   landed in ebbc623), **pending independent validator cross-check** — record this as
   worker-asserted, not yet cross-model admitted. DAG status mix: solid=7,
   preliminary=**15** (+1), hypothesis=**16** (−1), future=1 (39 nodes; was
   solid=7/preliminary=14/hypothesis=17/future=1 at iteration 4).

2. **What shipped this iter** — commits `65bf353..ebbc623` (chronological):

   **Read 6** (`65bf353`) finds the rows/game drift on link 1 (G=1000) steepening:
   marginal 17.7235→17.1736 in ~33 min, least-squares slope over the last 9 complete
   real-net directories −0.1070→−0.1742 (1.6x). The staged 1500/20000 knob set would
   have FAILED its own T1 tolerance at the 10-net bound (−3.55%) — caught before any
   link consumed it.

   **Option prep + apply** (`655b3ac`, `9227d09`, `ff5d0eb`) — three knob options
   drafted under o47; the human decision (`mission.json.decisions[-1]`) selects
   **option C**: `NUM_GAMES_PER_CYCLE` 1500→**1800**, `NUM_TRAIN_SAMPLES_PER_EPOCH`
   20000→**16000**, `NUM_TRAIN_SAMPLES_PER_SWA` 10000→**8000** (=E//2),
   `MAX_TRAIN_SAMPLES_PER_CYCLE` 100000→**80000** (=5*E), for link 2 onward
   (sha256 `ba7f1bf7e1bc166d`). The worker's own re-derivation of `train.py`'s
   subepoch consumption (`get_files_for_subepoch`, `:1306-1345`) establishes
   **samples/cycle = SHUFFLE_KEEPROWS, not NUM_TRAIN_SAMPLES_PER_EPOCH** — an epoch
   trains one whole shuffled output file (measured 60136+59864=120000 rows exactly;
   global-step deltas of 467/469 batches, not the nominal round(E/128)=156). The
   loop's real reuse quantity is **rho = SHUFFLE_KEEPROWS/(G·r)**, from which E
   cancels; rho at read 6 is 6.99 (link 1, G=1000, 87% of the `MAX_TRAIN_PER_DATA`
   cap of 8), falling to 4.66/3.88 at G=1500/1800.

   **Validation** (`1596b5b`) — cross-model admits option C **conditional**
   (production checker PASS, byte-identical transcript, refit slope steeper again
   out of sample: −0.1828). Narrows two worker claims: the "SWA horizon" framing of
   E's role is corrected to "E's only operative effect is the export EMA horizon
   64000, 20% shorter than link 1's"; the o48 successor's fixed 13.0 trigger is
   qualified to fire on **marginal ≤ 13.0 OR r_lo ≤ 11.733**, slope refit each read.
   **o47 discharged** (clause (b) pre-emptively met before the 17.0 crossing); **o48**
   (slope-aware rederivation at 13) and **o49** (`[FUTURE]`, the `-approx-rows-per-
   out-file` structural lever) opened.

   **Reads 7–8** (`691bc18`, `35f567f`) — o48 does not fire at either read (read 7:
   marginal 16.6266, r_lo 15.9512; read 8: marginal 16.9406, r_lo 16.7922). **The
   rows/game decline stalled and reversed** at read 8 — first rise of the series
   (+0.314) — interpreted (not measured) as the one-time game-length collapse
   (130.8→~81 moves/game, read 4) being finished, with the residual drift also
   levelling; rho eased 7.217→7.084 (was climbing toward the cap of 8). **Value loss
   drift reversed**: peaked at 0.602579 then turned down to 0.599702 (0.0203 clear of
   the 0.62 flag), while policy loss and pacc1 kept improving monotonically (pacc1
   crossed 0.50 at read 8). Gate margins tightened across both reads (closest:
   100.0–97.0 in 197 games) but no rejection yet through 39/39 accepted.

   **Link 1 → 2 boundary** (`ebbc623`) — link 1 (job 301099) ended **TIMEOUT at
   23:30:11, 157 cycles, 58 accepted / 2 rejected** (the first rejections of the
   run: 92.5–100.5 and 96.5–100.5) — but the BATCH step was **SIGKILLed** (ExitCode
   0:9), so `finalize()`/the TERM trap never ran: `.failcount`'s 0 is correct but
   unproven, and **P9's classification half is undemonstrated** on this boundary
   (documented o25 residue, not a defect — `loop.sbatch`'s own header states a
   SIGKILL end writes nothing and lets the queued successor run). Link 2 (job
   305318) started 18:23:21 on the same l40s node, chain depth 2/9, resumed
   losslessly from `t9-s17945216-d2940346` (P9's RESUME half passes in full — 0
   `Initializing new model!`, 0 stray checkpoints). **Option C is confirmed IN
   FORCE**: knob sha `ba7f1bf7e1bc166d`, `-max-games-total 1800`, cycle wall
   0.212h, and the trainer's own log confirms whole-file epochs directly (two
   subepochs, 109442 rows total against E=16000, then clean exit on "Not enough
   data files"). `r_cycle_knobs_9x9_derived` amended conditional→**empirical** on
   this evidence (worker-asserted, cross-check pending). o48 does not fire at the
   first link-2 read (marginal 16.9087); its **r_lo leg is not computable** — a
   structural finding, not a one-off: `prune_retention.py` removes selfplay history
   at every link start (only 6 of the 9 directories the trend fit needs survive),
   so the leg needs rewording (drop it, or source the fit window from a record that
   survives pruning) rather than being read as a transient gap. The successor-id
   parse defect (o46, fixed by an earlier commit `b1e25d9`) is **still visible on
   this boundary** — link 2's log still reads "chain not extended" — because job
   305318's own script copy predates the fix; the fix is effective from job
   314831's own resubmission onward, not retroactively. P8 rates for link 2 are
   deliberately not reported (13 minutes elapsed, artefact throughput numbers).

   Net this iter: 0 new admitted results (15 distinct `result_id` unchanged), 1
   amendment (`r_cycle_knobs_9x9_derived`, conditional→empirical, worker-asserted),
   obligations 46→**50** (29→**31** discharged: +o46,+o47; 15→**17** open: +o48,+o49;
   2 waived unchanged), claims unchanged at 16, assumptions unchanged at 12,
   error-ledger trials 61→**78**.

3. **Next-3 roadmap** (checked against `crash-triage --paper arxiv-1902.10565`):
   (a) **section-C boundary monitoring continues on link 2** — confirm the o46 fix
   lands on job 314831's own resubmission (not link 2's, which runs the pre-fix
   copy); state link-2 P8 rates once several complete cycles exist; keep tracking
   o48 (slope-aware) every read. `crash-triage --task production_chain_9x9` →
   `escalation` (3 consecutive `uncategorized_numerical`-tagged rows) — **read as
   iterations 2–4 read the same verdict on `loop_resume_under_walltime`**: this
   window landed a SOLID amendment (empirical promotion) and two admitted findings
   (the stall/reversal, the r_lo structural gap), so the next production-chain
   change should be structural (fix the r_lo leg's data source) rather than the
   task being unproductive. (b) **reword or drop the o48 r_lo leg** before the next
   read that needs it — `crash-triage --task scale_data_window` → `no_action` (no
   failing rows), so this is scheduled, not forced. (c) **decide and, if approved,
   implement SGF/game-record archiving ahead of `prune_retention.py`** so the "all
   games" viewer stays complete across a long chain — flagged to the human in
   `HUMAN_DIGEST.md`, not started; `converged_test_7x7` → `crash-triage`
   `fix_and_retry` (unchanged reading).

4. **Simplification flag**: **eight** tasks now carry `simplification-status:
   required` simultaneously — the seven carried from iteration 4 plus
   `production_chain_9x9` (best_iteration 13, metric
   `o48_marginal_rows_per_game_3net=16.9406`) newly required this iter (was
   `rows_per_game_random_net` at iteration 4; the metric name itself changed with
   the o48 protocol). None resolved by a qualifying `change_type=refactor` commit —
   `production_chain_9x9` §13 still forbids mid-run script edits against a live
   allocation; recorded verbatim, not acted on.

5. **Verifier output** (verbatim, re-run this iter):

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py progress --paper arxiv-1902.10565`
   → 39 nodes; status histogram **solid=7, preliminary=15, hypothesis=16, future=1**.
   ```json
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::scale_data_window", "status": "preliminary", "n_knowledge": 2, "n_trials": 0, "pass": 0, "fail": 0}
   {"paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::derive_cycle_knobs_9x9", "status": "preliminary", "n_knowledge": 4, "n_trials": 5, "pass": 3, "fail": 2}
   ```
   `dag_mermaid.py duplicates --paper arxiv-1902.10565` → `[]`

   `python3 phys-agentic-loop/_common/loop_gate.py status`:
   ```json
   {"decision": {"decision": "continue", "reason": "iteration 0/1000; progress solid=7 results=12 discharged=0; no_progress 0/8, stuck 0/3", "signal": {"solid_nodes": 7, "pass_rows": 51, "admitted_results": 12, "discharged_results": 0, "total_trials": 78, "max_ledger_iteration": 15}}, "gate_state": {"last_decision": "continue"}, "loop_active": null}
   ```
   No-progress 0/8, stuck 0/3, decision `continue` — gate does not block iteration 6.
   (As at prior iterations, the gate's own counters read a subset of ledger
   admission events, not the 15-distinct-result_id / 29-row totals computed
   directly from `results.jsonl`; both readings agree on 7 solid nodes.)

   `crash-triage --task production_chain_9x9` → `escalation` (3 consecutive
   `uncategorized_numerical`); `crash-triage --task scale_data_window` →
   `no_action`; `crash-triage --task converged_test_7x7` → `fix_and_retry`;
   `crash-triage --task loop_resume_under_walltime` → `escalation` (unchanged).
   **Caveat**, same shape as every prior iteration's for other tasks: read the
   `escalation` verdicts as "the next change should be structural," not "the task
   is stuck" — each landed admitted/SOLID rows this window.
