# current_iter — ktg-train (iteration 6 / wave 3, FINAL: chain stopped by human order)

1. **Paper anchor** — this iteration closes the mission. Human order, 2026-09-06 12:57 EDT:
   "this is good enough already, save all necessary checkpoints and stop." The chain (job
   305318, link 2 of 9) exited cleanly at cycle 249 (157 link 1 + 92 link 2) via the manual
   `STOP` brake, `rc=0`, `finalize()` ran in full, `.failcount` reset to 0. Successor 314831
   (link 3, PENDING) was cancelled first so nothing queued behind the stop. No plateau was
   declared and no gate/DAG node forces the stop — it is a human decision, terminal to the
   mission regardless of any node's status. DAG status mix: solid=7, preliminary=15,
   hypothesis=16, future=1 (40 nodes incl. 1 unclassified `None`; unchanged in count from
   iteration 5 — no new node opened this wave).

2. **What shipped this iter** — commits `65bf353..456379f` since iteration 5 closed at
   `ebbc623`:

   **Reads 9–13** (folded into `4963393` and predecessors) tracked link 2 through a 19-export
   stall on `p0loss`/`pacc1` while the gatekeeper kept accepting — o48 never fired (marginal
   stayed 16.6–17.6 against the 13.0 target across every read; rho climbed to 3.894 of the
   cap of 8, +60% over the 19200 baseline). The value-loss escalation memo (brain role,
   read-only, no ledger row, written before read 13) showed raw `vloss`'s rise tracks the
   selfplay window's draw share (r=0.835) and is not a fit signal; it retired the 0.62 flag
   and replaced it with `tdvloss1`/ownership-loss/held-out triggers (none fire) and a
   match-based plateau rule (o56).

   **c14 matches** (`3c3b5dc`, job 317503) settled the memo's question 2 empirically: latest
   net vs the then loss-record net, 400 games, **p 0.7412, +183 Elo [+146,+224]** — the
   stall was a loss-metric artifact, not a strength stall (decision rule threshold 0.60 met);
   latest vs the frozen first net, 400/400, exact CI [0.991, 1.000].

   **Retention-60 prepared, not applied** (`07a0933`/`4daf708`) — `apply_c1.sh` staged the
   `KTG_KEEP_SELFPLAY_GENERATIONS 3→60` edit (cost 2.01 GiB / 0.40% of the 500 GiB cap,
   removes the 75–78% window collapse at link boundaries) but was never run with `--yes`;
   `budget.env` still reads `=3`. Cross-model validation (`4daf708`) found nothing unsafe at
   51≤60 generations (ordering, min-age, protect-list, scratch-guard all checked by execution)
   and opened o54 (models dir unbounded, no rule in `prune_retention.py`), o55 (a `!`-tagged
   correction to `knobs_9x9.env:198`'s stale comment), o56 (the match-based plateau rule).

   **Read 14** (`4963393`) — the 19-export stall ended: **new best on both p0loss (1.468828)
   and pacc1 (0.546105)** at `t9-s28711040-d3032547`, resetting the exports-since-best counter
   to 0. This is the net the run leaves behind.

   **The stop** (`456379f`) — human order executed: successor 314831 cancelled (12:59:09),
   `STOP` file touched (12:59:50), loop exited clean at 13:03:06/13:03:10 (rc=0, 67185s
   elapsed), job 305318 COMPLETED at 13:03:11. Checkpoint written to
   `/home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop`: 7 683 842 860 B (7.2 GB),
   10 957 files, `sha256sum -c MANIFEST.sha256` exits 0 (10 956 OK). Pointer:
   `results/ktg/paper_1902.10565/evidence/production_chain/CHECKPOINTS.md`.

   Net this iter: 3 new admitted results (c14 match, retention-60 conditional, read-14 best-
   both-metrics), 0 amendments, obligations open o48/o49 carried unresolved (never fired /
   never tried — moot now the chain is stopped), o50–o56 opened across the window (o50–o53
   discharged as repairs landed; o54/o55/o56 remain open, non-blocking, informational only
   with the chain stopped), error-ledger trials 78→96.

3. **Next-3 roadmap** — **NONE. The mission is stopped by human order, not by a gate or DAG
   condition.** If resumed in the future (a human decision, not implied by anything here):
   (a) apply or discard the staged retention-60 edit before restarting link 3 (`apply_c1.sh
   --yes` or drop it — it is still only staged); (b) decide o52 (SGF archiving via
   `archive_sgf.sh`, `KTG_ARCHIVE_SGF=0` today) before further pruning discards more game
   history; (c) settle o48's r_lo leg (structural — deletes its own input at every link
   boundary) if the drift check is ever needed again. None of these blocks anything now;
   they are the open items a resumption would inherit, listed in
   `results/ktg/paper_1902.10565/evidence/production_chain/status_log.txt` §7 of the STOPPED
   block.

4. **Simplification flag**: moot. `production_chain_9x9`'s flag (`simplification-status:
   required`, unresolved since iteration 4) cannot be acted on now — the task's own files are
   frozen with the run. Recorded, not acted on, per the same reading as every prior wave
   (§13 of the task forbade mid-run edits; now there is no run to edit against).

5. **Verifier output** (verbatim, re-run this iter):

   `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py progress --paper arxiv-1902.10565`
   → 40 nodes; status histogram **solid=7, preliminary=15, hypothesis=16, future=1** (+1
   unclassified). Unchanged from iteration 5's mix.

   `python3 phys-agentic-loop/_common/loop/loop_gate.py status`:
   ```json
   {"decision": {"decision": "continue", "reason": "iteration 0/1000; progress solid=7 results=17 discharged=0; no_progress 0/8, stuck 0/3", "signal": {"solid_nodes": 7, "pass_rows": 60, "admitted_results": 17, "discharged_results": 0, "total_trials": 96, "max_ledger_iteration": 22}}, "loop_active": null}
   ```
   The gate reads `continue` — it has no concept of a human stop. The mission is closed by
   the human order recorded in `status_log.txt`'s STOPPED block, not by this signal.

   `crash-triage --task production_chain_9x9` → `escalation` (3 consecutive
   `uncategorized_numerical`); `crash-triage --task scale_data_window` → `no_action`;
   `crash-triage --task converged_test_7x7` → `fix_and_retry`; `crash-triage --task
   loop_resume_under_walltime` → `escalation`. Unchanged verdicts from iteration 5 — read as
   before: structural residue, not an unproductive task; moot with the run stopped.

   Checkpoint verification (verbatim, `results/.../CHECKPOINTS.md`): `sha256sum -c
   MANIFEST.sha256` → exit 0, 10 956 `OK`, 0 failures.
