# HUMAN_DIGEST — ktg-train

**Status:** training is on. The 9x9 production chain is running link 2 of 9, under the knob change you
authorized (option C). Nothing is blocked. One decision is worth your attention: whether to archive game
records before the loop's own cleanup deletes most of them.

## What landed today (2026-09-05)

- **You chose knob option C, and it is now running on link 2.** Monitoring found the amount of fresh
  training data per game declining as the run progressed (from roughly 18 rows/game toward 15), which would
  eventually have made the trainer reuse each game's data too many times. Three fixes were prepared; you
  picked the one that raises games-per-cycle from 1000 to 1800 and lowers the epoch/SWA sizing to match. The
  worker also found, while preparing this, that an "epoch" in this trainer is really one whole shuffled data
  file, not the sample count the knob names suggest — a correction to how several numbers in this pipeline
  should be read, not just a tuning choice.
- **Link 1 finished on its own time limit, cleanly for training purposes.** Job 301099 ran 157 cycles, with
  58 of 60 candidate networks accepted by the gatekeeper (the first two rejections of the whole run, and
  both were close matches, which is expected as the network gets stronger, not a fault). The very last two
  monitoring reads before it ended showed a mild reversal of the trend that motivated the knob change: the
  data-per-game decline stalled and ticked back up, and a training-quality number (value loss) that had been
  drifting the wrong way also turned back down. That reversal was noticed only after option C was already
  decided; it does not undo the reasoning, but it is worth knowing the picture improved on its own too.
- **Link 2 started immediately and confirmed the new knobs are working as intended** — its first training
  cycle matches every number the change was designed to produce.
- **A loop-monitoring detail needs a decision, not a fix**: the tool that checks the data-decline trend needs
  nine recent batches of self-play games to compute its slope, but the loop's own housekeeping deletes most
  older game batches to save disk space, so only six of the nine survive by the time link 2 starts. The
  check still ran and did not raise an alarm, but this piece of it cannot be trusted long-term without a
  change — see "Decisions needed" below.
- One earlier logging bug (the loop wrongly claiming "chain not extended" after a successful submission) was
  already fixed, but link 2 is running the version of the script from just before that fix landed, so its
  log still shows the old wrong message. The chain itself is fine; the next link picks up the fix
  automatically.

## What is live / blocked / open

- **Live, healthy, unattended**: the 9x9 chain, now on link 2 of 9. **The separate 7x7 test run is no
  longer live** — you stopped it on 2026-09-05 to redirect effort to the GUI; it ended with a flattening
  loss curve (88 cycles, policy loss down to 1.26, value loss down to 0.52, 76 of 87 candidates accepted)
  but never formally reached the plateau rule, and its closing strength match was waived by your stop, so
  no playing-strength claim is being made from it.
- **Nothing is blocked.**
- **One monitoring gap, not yet a fault**: the data-decline drift check's longer-range leg cannot compute
  this read because its input history gets partly deleted by routine cleanup (see decision below).
- **Eight tasks carry an open "simplify before the next commit" flag** (one more than last wave), all
  deferred by design while their allocations are live.
- **Nothing blocks the mission's own progress gate** — continue, no-progress 0/8, stuck 0/3.

## Decisions needed from you

- **Should game records be archived before the loop's routine cleanup deletes them?** Right now, cleanup
  removes roughly three-quarters of a link's self-play games within the same day, to keep disk usage and
  the monitoring window small. Two things depend on having the full history: the "watch all the games"
  viewer pages, and the drift-monitoring tool's longer-range check (mentioned above), which is already
  missing three of the nine batches it wants. If you want either of those to reflect the complete run rather
  than only the most recent slice, we would need to add a place to keep older game batches — costing some
  extra disk space (not yet sized) and a small addition to the loop's own script. If you are fine with only
  the newest games being viewable/checkable at any time, no change is needed and the note below can be
  closed as accepted behavior rather than a gap.
- No other decision is pending — the knob-change decision this wave (option C) is fully applied and
  confirmed working.

## Pointers

Loss curve: https://claude.ai/code/artifact/b7a554d2-fff8-49e0-8c9b-020c7ac906bb . Games viewer, cycles
1–50 / 51–107 / 81–157: see orchestrator message. `progress/ktg-train/RESEARCH_STATE.md` (mission
through-line) · `progress/ktg-train/nodal_note.md` (10-iteration window, last full rewrite at iteration 4) ·
`progress/ktg-train/loop_notes/current_iter.md` (this wave's verbatim verifier + crash-triage output) ·
`results/ktg/paper_1902.10565/decomposition/{logic,DESIGN,claims,obligations}.md` ·
`results/ktg/GLOBAL_DAG.md` (regenerated this wave) ·
`results/ktg/paper_1902.10565/evidence/production_chain/{preflight,launch.json,status_log.txt}` ·
`results/ktg/paper_1902.10565/evidence/scale_data_window/` (the option-C knob-change record).
