# HUMAN_DIGEST — ktg-train

**Status:** wave 1 (execution) + wave-2 planning closed (iteration 2); smoke job submitted and queued; wave 3 pending its result.

## What landed

- **Five results admitted** since the wave-0 close: `env-toolchain-b200` (carried over,
  empirical), `cfg-9x9-override` (empirical; the 9x9-only selfplay/gatekeeper configs and
  train wrapper — every produced SGF is `SZ[9]`, thread peak 22/24 CPUs), `r_tiny_model_export_smoke_b7c96h3tfrs`
  (empirical; exported block histogram matches exactly, engine loads and serves it, and
  correctly refuses the retired `b5c48h3tfr`), `r_loop_resume_under_walltime_static`
  (existence_only, after three repair rounds on the Slurm chain wrapper's SIGTERM-vs-failure
  classification), and `data-budget-guard-500gib` (conditional; the scratch guard's exit-code
  contract is measured at 25/25 on synthetic fixtures, but no production cycle has exercised
  it yet — that's what keeps it at `conditional` rather than `empirical`).
- **14 code-map nodes re-affirmed `preliminary`** with executed verification (search-side +
  training-side anchors re-read against the v1.18.2 mirror).
- **Obligation ledger**: 17 discharged, 2 waived, 17 open (36 total, up from 24 at the wave-0
  close). Two SIGTERM-classification obligations (o33, o35) and one guard-hardening
  obligation (o32) are open non-blocking; four (`o02`, `o03`, `o13`, `o24`) plus `o30`, `o33`,
  `o35` are blocking-before-P1.
- **Wave-2 plan committed**: one task packet (`synchronous_loop_smoke`) collapses 13
  previously-separate probe/measurement sub-results onto a single 1-GPU b200 allocation
  (two loop cycles, gate-vs-random baseline, 14 code-map probes, throughput record) plus a
  CPU-only follow-on task (`derive_cycle_knobs_9x9`). **Job 298712 is submitted and PENDING**
  on b200, queue estimate ~21:00 today.
- **The iteration-1 CPU/scratch-policy propagation gap is now fully closed**: `DESIGN.md`,
  `tasks/data_budget/implementation.md`, and `codes/loop/loop.sbatch` all read the 500 GiB
  cap / no-CPU-cap live from `budget.env`/`mission.json`; the corresponding claim-ledger rows
  (`a11` retired, `o22` waived, `o04` discharged) are closed. No action needed here.
- **Housekeeping**: `results/ktg/GLOBAL_DAG.md` had drifted from the ledger (two node
  statuses and both `data_budget`/`loop_resume_under_walltime` trial counts were stale) —
  regenerated, no topology change. `decomposition/convention.md` §10's
  `-attn-logit-penalty-cap` row still named the retired `b5c48h3tfr` as its closing
  condition — corrected to name `b7c96h3tfrs` (whose random-init export already passes
  without the flag) and to require a *trained* export for closure.

## What is blocked / open

- **Nothing blocks wave 3** — the loop gate reports `continue` (no-progress 0/8, stuck 0/3).
- **Waiting on compute**: job 298712 is queued on b200 (~20h estimated wait). See decision
  below — this is the concrete instance of the queue pressure.
- **A genuine methodology tension for whoever repairs the loop-resume wrapper next**
  (`o33`/`o35`): the crash-triage tool says the next change to that task must be
  `change_type='structural'` (2 consecutive same-mode failures in its history), while the
  simplification-status tool independently says the next change should be `change_type='refactor'`
  to hold a metric. A `refactor` row is blocked by crash-triage; a `structural` row satisfies
  crash-triage but isn't what simplification-status asked for. Not resolved by this note —
  flagged for the next worker on that task (`progress/ktg-train/current_iter.md` §3(b)).
- **`o32` (data-budget guard hardening, non-blocking)**: the raw crash-triage read is
  `escalation` (3 same-mode failures among the task's failing-row history), but that reads
  only failing rows — the task's actual latest attempt passed and the result was admitted.
  Not currently stuck; just flagging that its next repair should default to a stronger
  (structural) fix rather than another guard-constant tweak.

## Decisions needed from you

- **L40S while B200 is saturated?** `sinfo -p b200` currently shows 15/16 nodes allocated (1
  idle); the smoke job queued ~20h on b200. `docs/cluster-manual.md` documents `l40s` as
  `AllowAccounts=ALL` — genuinely open to us, not scavenger, not JHU-restricted — and
  `sinfo -p l40s` shows some headroom (5/6 nodes mixed-use). It is **not** in
  `mission.json.compute.partitions` and the compute-budget check script hard-rejects any
  partition besides b200/b300. Should smoke-sized (1-GPU, non-production-training) jobs be
  allowed to run on l40s while B200 stays saturated, to cut queue time on measurement-only
  allocations? If yes: needs a `mission.json` decision entry, a `compute.partitions` /
  `check.sh` allow-list change, and a note on whether any B200-only claims (the sm_100 SASS
  clause of `env-toolchain-b200`) need an L40S-specific counterpart or should stay
  B200-scoped by design.
- No other decisions pending — the three raised at wave 0 (CPU policy, scratch budget, b200
  vs b300) are fully landed and propagated.

## Pointers

`progress/ktg-train/RESEARCH_STATE.md` (mission through-line, ≤10 KB) · `progress/ktg-train/nodal_note.md`
(10-iter window: DAG snapshot, accepted results, simplification cycle, failure-mode drift) ·
`progress/ktg-train/loop_notes/current_iter.md` (this wave's verbatim verifier + crash-triage
output) · `results/ktg/paper_1902.10565/decomposition/{logic,DESIGN,convention}.md` ·
`results/ktg/GLOBAL_DAG.md` · `results/ktg/paper_1902.10565/tasks/synchronous_loop_smoke/`.
