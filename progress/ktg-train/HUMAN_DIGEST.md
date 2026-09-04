# HUMAN_DIGEST — ktg-train

**Status:** wave 3 (production chain) is **executing**. The first 9x9 production chain link is running on
an L40S; a second, separately-authorized 7x7 convergence test is running on a B200 and converging visibly.
Nothing is blocked; one non-blocking wrapper defect is being repaired while the chain keeps running.

## What landed

- **All six pre-launch repairs landed and were cross-model admitted.** The Slurm wrapper now declares and
  asserts the 32 CPUs the derived knobs need (was 24), samples thread counts and GPU utilization for the
  whole length of every chain link (not just the smoke), and refuses to shuffle any data file that is not a
  9x9 row set before every shuffle stage. The knob deriver now raises by name on any missing measured input
  instead of silently substituting a stale constant. The export-ramp model was corrected twice — first by
  the worker, then independently re-derived by the validator from the trainer's own file-consumption
  behavior — landing on: the first real candidate exports at **cycle 5**, is gated at cycle 6, and "exactly
  one export per cycle" never actually holds at these knobs (exports fall at roughly cycles 5, 10, 15, 19,
  22 instead). And the full-search-fraction probe was fixed — a subtle instrument bug had cheap searches on
  a reused tree miscounted as full searches — re-establishing the measured fraction (0.2516) inside the
  paper's expected band and promoting `playout_cap_randomization` to solid on two independent instruments.
- **You authorized L40S for the production chain, and it measures out runnable.** A dedicated 1-GPU probe
  (job 300987) ran the mission's engine binary on an L40S with zero "no kernel image available" errors and
  a benchmark rate essentially matching a B200 (2401.88 vs. 2322.17 visits/s) — the binary carries no sm_89
  image, but the next-oldest architecture's compiled kernels load and run correctly under CUDA's own
  compatibility rule, measured rather than assumed. A second defect (the chain wrapper's successor-partition
  list was hard-coded and would have pinned links 2-9 to b200/b300 only) was found and fixed before it could
  bite. Admitting l40s moved the chain's earliest start estimate from **2026-09-06** to **2026-09-04**, about
  two days sooner.
- **The first 9x9 production chain link is running.** Job 301099 has been RUNNING on an L40S (node gl111)
  since 2026-09-04 18:52. Its first cycle is healthy: selfplay and shuffle are done, training is in progress,
  every measurement taken so far (rows per game, thread counts, storage guard) is within the tolerances
  derived at wave 2. A useful surprise: production self-play runs 7.4× faster than the earlier smoke test on
  this same hardware, traced to a logging flag the smoke left on and production correctly turns off — not a
  partition-speed effect. One non-blocking wrapper bug was found in this first read: a site-specific Slurm
  banner on stderr breaks the wrapper's own successor-job-id bookkeeping, so its log wrongly claims "chain
  not extended" even though the successor was created correctly and is queued. The chain itself, its crash
  breaker, and its stop mechanism are all unaffected — only a log line and one safety fast-path are wrong.
  The fix is a one-line change, not yet landed; it will self-apply to link 2 once committed, since the chain
  re-reads its own script from the repository at the start of every link.
- **The separately-authorized 7x7 convergence test is running and learning.** After you asked for a short
  test run with a real loss curve, the worker found the 9x9 smoke had never actually produced one (a logging
  interval mismatch), fixed that generically, and also found that KataGo's own from-scratch learning-rate
  warmup — calibrated for a much longer 19x19-scale run — would have held a short 7x7 test at 1/20 the
  intended rate for its entire duration; both were corrected before the run that matters started. Job 301096
  has been running on a B200 since 17:14 and is converging clearly: as of this note, 46 cycles and about
  1.19 million training samples in, policy loss has fallen from 3.92 to 1.55 (well below the random-guessing
  baseline of 3.91), value loss from 0.92 to 0.57, with 43 of 45 candidate nets accepted by the gatekeeper.
- **You changed the 7x7 test's stopping rule mid-run**, from a fixed 6-hour cap to training until the loss
  curve visibly stops improving. That is now implemented as a measured-plateau rule (two consecutive
  evaluations with both policy and value loss essentially flat AND no new gatekeeper acceptance in the last
  15 cycles), running in same-directory continuation segments with a 12-segment safety bound — a backstop,
  not a target, since the run is still improving steeply and nowhere near it.

## What is live / blocked / open

- **Live, unattended, healthy**: the 9x9 chain (link 1 of 9, L40S) and the 7x7 test (B200), both progressing
  without any knob having moved since launch. Neither is blocked.
- **One non-blocking repair in flight**: the wrapper's successor-job-id capture (above); does not affect the
  chain's correctness or safety, only its own logging and one dead fast-path; targeted before link 1 ends.
- **One monitoring watch, not a repair**: from link 3 onward, a successor could in principle get pinned to a
  momentarily-free B300 GPU and stall if a reservation lands on it afterward. This cannot happen before link
  3 (the relevant node is reserved through 2026-09-07), and the response if it does fire is to escalate with
  data and ask for authorization to resubmit that one link — not to silently retune anything.
- **Seven tasks carry an open "simplify before the next commit" flag**, none yet resolved — three carried
  over from the prior wave, three opened by this wave's new tasks. All are deferred by design while their
  allocations are live: editing a running chain's own scripts mid-run is forbidden by its own task rules.
- **Nothing blocks the mission's own progress gate** — `continue`, no-progress 0/8, stuck 0/3.

## Decisions needed from you

**None pending.** Both open items from the last wave are resolved: the L40S question (you decided to allow
whichever of b200/l40s frees first, and it now measures out runnable and is in production use), and the 7x7
test's stopping rule (you replaced the time cap with the plateau rule, now implemented and running). If
anything, the one item worth a glance is informational rather than decision-needed: the wrapper's log line
about "chain not extended" is misleading until its one-line fix lands — the chain itself is fine.

## Pointers

`progress/ktg-train/RESEARCH_STATE.md` (mission through-line, incl. the Training-status paragraph) ·
`progress/ktg-train/nodal_note.md` (iterations 1-4 window: DAG snapshot, accepted results, simplification
cycle, failure-mode drift) · `progress/ktg-train/loop_notes/current_iter.md` (this wave's verbatim verifier +
crash-triage output) · `results/ktg/paper_1902.10565/decomposition/{logic,DESIGN,claims,obligations}.md` ·
`results/ktg/GLOBAL_DAG.md` (regenerated this wave) · `results/ktg/paper_1902.10565/codes/loop/knobs_9x9.env` ·
`results/ktg/paper_1902.10565/evidence/production_chain/{preflight.txt,launch.json,status_log.txt}` ·
`results/ktg/paper_1902.10565/evidence/converged_7x7/{status_log.txt,summary-301096.json}`.
