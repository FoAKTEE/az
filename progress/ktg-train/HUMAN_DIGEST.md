# HUMAN_DIGEST — ktg-train

**Status:** wave 2 (smoke job + knobs) closed (iteration 3); wave 3 (production chain) is next, gated on
one wiring obligation (o39) plus two carried-over blocking gaps (o02, o03).

## What landed

- **The smoke allocation ran, twice, inside its 3-attempt budget.** Job 298712 (b200, COMPLETED) ran two
  full loop cycles end to end: selfplay → shuffle → train → export → gatekeeper. Cycle 1's candidate
  (`t9-s1216-d1221`) was gated against the random baseline and **rejected**, 55.5 to 100.5 in 156 games —
  expected for a near-random-init net, not a bug. `global_step_samples` went 1216 → 2528 across the two
  cycles with zero re-initialisations. Attempt 2 (job 299259) resumed cleanly from job 1's markers and ran
  the training-side and search-side architecture probes: kill-and-resume passed 6/6 (SIGKILL at sample
  4992, resumed to 14976, rows unchanged), the training probe passed 4/4.
- **Eight new results admitted** (13 total now, up from 5): the loop-cycle execution itself, the tiny
  throughput record, both architecture probes, and the derived cycle knobs — all empirical or conditional.
  **Two results refuted, both narrowly, as literally written**: the 24-CPU thread bound (real-net stages
  measure 25 threads, one more than declared — every other clause of that bound holds) and the ≤10 KiB/game
  disk-bytes bound (rows/game clause holds; bytes/game runs 9-20% over). Neither refutation threatens the
  pipeline — both fed directly into the next node's derivation.
- **A worker-proposed refutation was itself refuted.** The worker read the smoke data as disproving the
  paper's cheap-search fraction (0.342 measured vs. 0.25 predicted) and the byte bound. Cross-model
  validation traced the fraction discrepancy to a probe-instrument bug — cheap MCTS searches reuse a
  subtree and inherit visit counts, so the worker's binning rule mis-classified 667 of 7401 searches. The
  band is left explicitly **unchecked** (neither refuted nor re-admitted at a new value); a follow-on
  obligation (o38) fixes the discriminator with no further compute needed.
- **The 9x9 production-cycle knobs are derived and admitted `conditional`** (1000 games/cycle, 20000
  samples/epoch, min_rows 25000, keep 120000 > cap 100000, 5 epochs/export, 32 CPUs / 18 game threads,
  ~3.11 h/cycle measured, ~20.9 GiB per 23-cycle chain link). Every arithmetic check re-derives
  independently on validation (16/16 pass at the measurement and its 90% lower bound; 9 deliberate
  break-attempts fail as they must). The one correction: the worker's claimed export timeline ("exactly one
  candidate per cycle from cycle 13") does not survive the trainer's own exit-on-empty-epoch behavior — the
  validator's read says **the first real candidate exports at cycle 5**, gated at cycle 6; "exactly one per
  cycle" doesn't hold reliably until roughly cycle 16. This is a corrected reading of the same knobs, not a
  knob change — nothing needs re-deriving.
- **Four more nodes promoted to solid** on this wave's validation: the transformer trunk architecture, the
  policy-head global-pooling design, the training row data format, and train.py's resume semantics.
- **A fifth repair round closed on the Slurm chain wrapper** (`loop_resume_under_walltime`): every
  chain-state counter file now reads through a base-10 guard, closing a bash bug where a leading-zero value
  (e.g. "08") aborted the wrapper's failure-accounting logic entirely. A residual — the wrapper still fails
  *open* (doesn't stop the chain) if a state file becomes unwritable, or if an operator sets a malformed
  `KTG_MAX_FAILS` — is tracked as a new, explicitly non-blocking obligation (o36).

## What is blocked / open

- **One wiring obligation blocks the first real chain launch (o39):** `loop.sbatch` still declares 24 CPUs
  where the derived knobs need 32. This is a one-line-class fix but belongs to the wrapper's owner task
  (`loop_resume_under_walltime`), not to the knobs task, by task-boundary convention.
- **Two carried-over blocking gaps, untouched this wave:** `o02` (propagating the 9x9 pos_len override into
  `shuffle_stage`) and `o03` (re-measuring real-net thread counts at the new 32-CPU declaration, not the
  smoke's 24). A fourth blocking item, `o25`, needs an executed proof that the failure-circuit-breaker trips
  under a real Slurm TIMEOUT/CANCELLED/FAILED, not just a simulated one.
- **The crash-triage / simplification-status tension flagged at iteration 2 persists, unchanged**, for
  `loop_resume_under_walltime`: crash-triage still says its next change must be `change_type=structural`;
  simplification-status still independently wants a `refactor` row holding its metric. Two more tasks
  (`synchronous_loop_smoke`, `derive_cycle_knobs_9x9`) opened their own `simplification-status: required`
  flags this wave — four such flags are now open at once across three tasks, none yet resolved by a
  qualifying commit.
- **Nothing blocks the loop gate itself** — `continue`, no-progress 0/8, stuck 0/3.

## Decisions needed from you

- **L40S while B200 is saturated? Still open, unchanged from last wave.** Both smoke jobs did eventually run
  on b200 without a decision here, so nothing was blocked — but the next launch is a **multi-day production
  chain**, not a 6-minute smoke job, and it is gated behind `o39` (an easy fix) rather than compute
  availability today. If B200 queue pressure returns before that chain launches, the L40S question (open,
  `AllowAccounts=ALL`, not currently in `mission.json.compute.partitions` or the compute-budget
  allow-list) becomes relevant again. No urgency this wave; flagging so it isn't lost.
- No other decisions pending — prior wave-0 decisions (CPU policy, scratch budget, b200 vs b300) remain
  fully landed.

## Pointers

`progress/ktg-train/RESEARCH_STATE.md` (mission through-line, incl. a Training-status paragraph) ·
`progress/ktg-train/nodal_note.md` (10-iter window: DAG snapshot, accepted results, simplification cycle,
failure-mode drift) · `progress/ktg-train/loop_notes/current_iter.md` (this wave's verbatim verifier +
crash-triage output) · `results/ktg/paper_1902.10565/decomposition/{logic,DESIGN,claims,obligations}.md` ·
`results/ktg/GLOBAL_DAG.md` · `results/ktg/paper_1902.10565/codes/loop/knobs_9x9.env` ·
`results/ktg/paper_1902.10565/evidence/{smoke,derive_cycle_knobs,loop_resume}/`.
