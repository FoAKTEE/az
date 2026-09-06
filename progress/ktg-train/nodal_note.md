# nodal_note — ktg-train (window: iterations 1–10, closed FINAL at iteration 6)

## 10-iter window (final: iterations 5–6 folded in; iterations 1–4 summarized, see git log for
that window's own full nodal_note)

- **error-DB pass/fail counts** (`results/ledgers/error/paper_arxiv-1902.10565/trials.jsonl`,
  **96 rows total**, up from 78 at iteration 5 / 61 at iteration 4): this window's delta (+18
  rows) is concentrated in `production_chain_9x9` (reads 9–14, the c14 match job, the
  retention-60 preparation and its validation) and the terminal stop sequence. No task closed
  with a net-new failure classification; every new row this window is a pass, a finding, or
  an admitted/conditional result.
- **`logic.md` node coverage**: 39 → **40** (one new: an unclassified node surfaced by the
  render tool, `[OPEN]` for a future wave to name — not investigated further, the mission is
  closing). Status mix iteration 4 → 5 → 6: `solid` 7→7→**7** (unchanged — no new solid
  promotion this window), `preliminary` 14→15→**15** (unchanged since iteration 5),
  `hypothesis` 17→16→**16** (unchanged since iteration 5), `future` 1→1→**1**.
- **Simplification cycles consumed**: zero this window, same reading as every prior window —
  `production_chain_9x9` §13 forbids mid-run script edits against a live allocation, and now
  the allocation is stopped entirely rather than merely live, so the flag is moot rather than
  overdue.
- **Failure-mode drift**: no new `failure_mode` enum value. `crash-triage` verdicts on
  `production_chain_9x9` and `loop_resume_under_walltime` are unchanged (`escalation`, 3
  consecutive `uncategorized_numerical`) — read, as at every prior window, as "the next
  change should be structural," except there is no next change: the mission stopped on human
  order, not on any of these signals.
- **Strategic redirects, this window**: (1) the value-loss escalation memo (brain role,
  read-only) diagnosed the 0.62 raw-`vloss` flag as measuring draw-share, not fit, and
  replaced it with a match-based plateau rule (o56) — a genuine methodology correction to how
  the run's own health was being read, not a knob change; (2) the c14 match settled the
  19-export loss stall as NOT a strength stall (+183 Elo over the same span), so the
  pre-registered LR-halving option (b) was never triggered; (3) the retention-60 fix was
  prepared and validated safe but deliberately left unapplied at the human's discretion
  (o52 open); (4) the terminal redirect: **the human ended the mission outright** on
  2026-09-06 at 12:57 EDT, superseding every open node/obligation/simplification flag in this
  note — none of them was the reason for the stop.

## Logic-DAG snapshot

Canonical source: `results/ktg/paper_1902.10565/decomposition/logic.md` (40 nodes) and
`results/ktg/GLOBAL_DAG.md` (regenerated this wave). Status counts unchanged from iteration 5:
`solid` 7, `preliminary` 15, `hypothesis` 16, `future` 1, +1 unclassified.

**Open obligations** at close (from the claim ledger, `describe-domain`): o48
(rows/game slope-aware rederivation, never fired — marginal never crossed 13.0/11.733 at any
read through read 14) and o49 (`[FUTURE]`, untried `-approx-rows-per-out-file` lever) carry
forward unresolved, moot with the chain stopped. o50–o53 opened and discharged this window
(SIGTERM forwarding, per-net history, SGF archive flag decision deferred to o52, retention-60
prepared). **o52 (SGF archiving before deletion) and o54 (models dir unbounded) and o55 (knob
comment correction) and o56 (match-based plateau rule) remain open** — informational only now;
none blocks anything with training stopped.

## Accepted-results snapshot (this window's additions only; 1–15 unchanged from iteration 5,
full list: `python3 phys-agentic-loop/_common/result_database.py render-state --paper
arxiv-1902.10565`)

| Claim | Evidence type | Verifier output path | Status |
|---|---|---|---|
| c14 match (latest vs loss-record net, vs first net) | empirical_measurement | `evidence/production_chain/c14_match_9x9/` (job 317503) | empirical, admitted — p 0.7412 [+183 Elo], 400/400 |
| retention-60 preparation | empirical_measurement + code_check | `evidence/production_chain/retention_60/` | conditional, admitted — staged, not applied |
| read-14 best-on-both-metrics | empirical_measurement | `status_log.txt` READ 14 | empirical, admitted — p0loss 1.468828, pacc1 0.546105, both run bests |
| chain stop, checkpoint | existence_only | `evidence/production_chain/CHECKPOINTS.md`, `MANIFEST.sha256` | admitted — sha256sum -c exits 0, 10 956 OK |

## Simplification cycle

- **Trigger**: unchanged at 8 tasks carrying `simplification-status: required` since
  iteration 5; none newly opened or closed this window.
- **Code-edit delta**: this window's edits were the value-loss memo (read-only, no code
  touched), the c14 match driver (`c14_match.sbatch`, a driver script, not a loop/knob edit),
  the retention-60 patch (staged as a `.diff`, never applied to the working tree), and the
  stop sequence itself (`touch runs/p1/STOP`, `scancel 314831` — operational commands, not
  source edits). No `codes/loop/*.sh`, `codes/loop/*.sbatch`, or `codes/data_budget/*.env`
  file changed on disk this window.
- **Lessons**: the memo's central lesson — a monitoring threshold (raw `vloss` vs 0.62) can be
  measuring an artifact of the data distribution rather than the quantity it was designed to
  flag — generalizes past this run: any single scalar threshold on a self-play system needs a
  distribution-invariance check before it is trusted as an escalation trigger. The c14 match
  is the concrete instance of the broader principle in `alignment.md` §0: when a monitored
  metric and a direct strength measurement disagree, the direct measurement wins and the
  metric's interpretation is corrected, not the measurement.

## Failure-mode drift

No new `failure_mode` enum value this window. `production_chain_9x9` and
`loop_resume_under_walltime` remain at `escalation`/`uncategorized_numerical`
(3 consecutive), unchanged since iteration 4; `scale_data_window` remains `no_action`;
`converged_test_7x7` remains `fix_and_retry` (unchanged, the 7x7 run has been stopped since
2026-09-04 and carries no new rows). This window's amendments are result-ledger admissions
(c14, retention-60, read-14 best), not error-ledger backfills — each is a new finding, none a
corrected verdict on a prior row.

## Closing note

This is the final nodal_note for the mission as currently scoped. It closes at iteration 6,
short of the 10-iteration window it was opened for, because the mission itself was closed by
human order (`status_log.txt`, STOPPED block) rather than by the window running out. If the
mission is ever resumed, a new nodal_note should open at iteration 7 with the same 10-iteration
cadence and should read this file plus `RESEARCH_STATE.md`'s "Training status" section as its
starting state, not the DAG/ledger counts alone — those counts are informational, not the
resumption blocker list (which lives in `status_log.txt` §7 of the STOPPED block and in
`CHECKPOINTS.md`'s "Resuming from it" section).
