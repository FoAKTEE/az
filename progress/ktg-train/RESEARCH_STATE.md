# RESEARCH_STATE — ktg-train

**Mission.** Train a 9×9 transformer-trunk KataGo net end-to-end (self-play → shuffle → train → export →
gatekeeper) on the Schmidt B200/B300 cluster within the compute policy (≤4 GPUs total, no CPU cap, b300
preferred / b200 fallback, 3-day walltime). **Phase.** wave 3: production chain — the smoke allocation
(jobs 298712, 299259) executed and validated, the 9x9 cycle knobs are derived and admitted conditional;
next is wiring the knobs into `loop.sbatch` (o39) and launching the first real chain. **Branch.** az `main`
(consumer), framework submodule `ssci`. **Paper id (ledger label only).** `arxiv-1902.10565`.
**Layout.** consumer artifacts at the `az` root: `results/`, `progress/`, `ref-code/`, `ref-paper/`, `mission.json`;
tools run as `python3 phys-agentic-loop/_common/...` from `az`. **Runtime.** `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/`.

## Training status (for the human)

Nothing has trained under the derived production knobs yet — only the **smoke-scale** exploratory run
has: 2 loop cycles at `games=80`/cycle on job 298712, `global_step_samples` 1216→2528, 0 re-initialisations.
Cycle 1's candidate (`t9-s1216-d1221`) was **gated against the random baseline and REJECTED**, 55.5 to
100.5 in 156 games — expected for a ~256-sample net, not a failure. No real-net-vs-real-net gate has run.
The derived production knobs (1000 games/cycle, 20000 samples/epoch, min_rows 25000, cap 100000/keep
120000, 5 epochs/export, 32 CPUs / 18 game threads, ~3.11 h/cycle measured, ~20.9 GiB per 23-cycle chain
link) are admitted `conditional` — nothing has run at them. The validator corrected the export-ramp model:
cycles 1-4 export nothing (`-quit-if-no-data` exits clean with an empty epoch), **the first real candidate
exports at cycle 5** and is gated at cycle 6; "exactly one export per cycle" only holds once the shuffled
window holds 5×samples-per-epoch rows, ≈cycle 16 if cycle 6's candidate is accepted, later per rejection
(o40 tracks correcting this in the prose/derivation code, not the knobs). Before that chain can launch,
`loop.sbatch` still declares 24 CPUs against the knobs' 32 (`o39`, blocking) and two more blocking gaps
remain open (`o02` pos_len-9 propagation, `o03` thread re-measurement at 32).

## Source Library

| ID | Source | Status | Notes |
|---|---|---|---|
| `code` | `ref-code/lightvector-KataGo/` @ v1.18.2 `fd0723fd` | `[SOLID]` | primary source of truth (code-first). `results/ktg/sources/code_lightvector-KataGo.md` |
| `paper` | `ref-paper/arxiv-1902.10565/` | `[SOLID]` | background only |
| `cluster` | `docs/cluster-manual.md` | `[SOLID]` | b200/l40s partition notes; l40s still not in `mission.json.compute.partitions` |
| `reviews` | `evidence/decomposition/dag_reconciliation.md` | `[SOLID]` | canonical 38-node DAG |

## Working Context (detail: `nodal_note.md`, `decomposition/DESIGN.md`)

| Name | Meaning | Status |
|---|---|---|
| board/trunk | 9×9 only; trunk `b7c96h3tfrs` (SwiGLU FFN) — now `[SOLID]` (was preliminary) | `[SOLID]` |
| loop (smoke-validated) | 2 cycles executed end to end (c07 proved); real-net/CUDA-context stages measure 25 OS threads vs. 24 declared (c06 refuted for that clause only) | `[PRELIMINARY]`; `o02`,`o03`,`o39` open blocking |
| cycle knobs | derived from measured 32.3 rows/game; 16/16 checks pass at measurement and its 90% lower bound; export-ramp claim narrowed (first candidate cycle 5, not 13) | `[PRELIMINARY]` node, result `conditional`; `o39`/`o40`/`o41` open |
| data budget | scratch guard: 500 GiB mission-root cap, constants in `budget.env`; unchanged this wave | `[HYPOTHESIS]` node, result `conditional`; `o32` open non-blocking |
| build | CUDA + cuDNN 9.19, `cmake-sm100.diff`; `env_build` solid | `[SOLID]` |

## Active Claims (ledger `results/ledgers/claim/paper_arxiv-1902.10565/`, 70 entries: 16 claims (5 admitted/3 in_progress/6 open/2 refuted), 42 obligations (23 discharged/17 open/2 waived), 12 assumptions (11 active/1 retired))

| Claim | Status | Notes |
|---|---|---|
| c01/c02 env_build; c04 SGFs SZ[9]; c05 pos_len-9 pipeline; c07 loop cycle | admitted | closed |
| c06 threads ≤24 | **refuted** | real-net/CUDA-context clause only (25 meas.); other clauses hold |
| c10 rows/game ≤10 KiB/game on disk | **refuted as written** | rows/game clause holds; bytes/game 9-20% over |
| c03 export loads; c11 scratch ≤500 GiB; c15 paper↔code | in_progress | wave 3 |
| c08 kill/resume; c09 selfplay rate; c12 loss decreases; c13 ≥1 gate accept; c14 CI excludes 0.5; c16 scale-up | open | needs a real chain |

## Accepted Results Log

<!-- Pointer to the GENERATED block: python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565 -->
<!-- Re-run this wave (2026-09-04): 13 distinct result_id, 20 rows incl. amendments — full BEGIN/END block
     is well over the 10240 B cap on its own; one-line summaries kept here, full rows in nodal_note.md
     `## Accepted-results snapshot`, reproducible verbatim by re-running the command. -->
1. `env-toolchain-b200` — empirical, admitted.
2. `r_loop_resume_under_walltime_static` — existence_only, admitted; amended (o36 qualification); o33/o36 open.
3. `data-budget-guard-500gib` — conditional, admitted; node hypothesis; o32 open non-blocking.
4. `r_tiny_model_export_smoke_b7c96h3tfrs` — empirical, admitted.
5. `cfg-9x9-override` — empirical, admitted; node preliminary.
6. `r_synchronous_loop_smoke` — empirical, admitted; c07 proved.
7. `r_smoke_threads_realnet` — **refuted**; 25 threads meas. vs. 24 declared.
8. `r_smoke_throughput_tiny` — empirical, admitted.
9. `r_smoke_probe_training` — empirical, admitted.
10. `r_smoke_probe_search` — empirical, admitted (re-scoped); full_frac band `[UNCHECKED]`, o38 open.
11. `r_smoke_full_frac_binning` — `unchecked`; worker's refutation rejected as a binning artefact.
12. `r_smoke_c10_bytes_per_game` — **refuted as written**.
13. `r_cycle_knobs_9x9_derived` — conditional, admitted; narrowed on export ramp; o39/o40/o41 open.

## Next Work Steps — wave-3 frontier (ledger-computed 2026-09-04: READY = `data_budget`, `verify_preemption_resume`, `loop_failure_circuit_breaker`; `selfplay_stage` waits on exactly those three)

- `[BLOCKING]` **`tasks/wave3_prelaunch_repairs`** (CPU, one worker, one commit per repair): R1 o39 (`loop.sbatch`
  declares 32 CPUs read from `knobs_9x9.env`, asserted at pre-flight), R6 stage monitor wired into every link (needed
  for o03/c09), R5 o02 wiring DECIDED — wire `check_pos_len_npz.py` before every shuffle; R2 o40 (ramp model: first
  export at cycle 5, exactly-one ≈ 16), R3 o41 (a missing measured key raises), R4 o38 (re-bin at `== maxVisits` →
  0.2516 in band, promotes `playout_cap_randomization`). R1/R5/R6 gate the launch; R2–R4 before cycle 5 is read.
- **`tasks/production_chain_9x9`** — the launch: `BASEDIR=$KTG_ROOT/runs/p1 KTG_MAX_CHAIN=3 sbatch codes/loop/loop.sbatch`
  (1 GPU, 32 CPUs, 2-23:30:00 per link, 3 links ≈ 9 GPU-days; the 12 ledger closing checks already name `runs/p1`).
  Settles P1–P12: the five stage nodes, `bootstrap_accepted_model`, `data_budget` (cycle-1 guard log → c11 empirical),
  `measure_stage_throughput` (c09), `verify_preemption_resume` + the walltime half of o25 (sacct `TIMEOUT` + successor
  at links 1→2, 2→3; mid-export half by a CPU kill test), o03/o39(c) (`nlwp_max` ≤ 32), o40(c) (first export cycle
  == 5), `count_gatekeeper_acceptances` (c13 ≥ 1 by cycle 20), then ONE match job (c14, 400 games) → `eval_improvement`.
  Expectations: first export ≈ 4–5 h in (bound 15.5 h), first gate ≈ 5–6 h (bound 18.6 h), link end 71.5 h. Abort →
  escalate with data, never tune: breaker/STOP, no export by cycle 8, no acceptance by cycle 20, `nlwp` > 32, bucket
  starvation ≥ 3 cycles. The human decides scale-up at the end of link 3 from the § 10 decision table.
- `[OPEN]` o25's breaker-trip-under-sbatch conjunct proposed `[FUTURE]` (walltime half executed by the chain); o33/o36
  non-blocking, R1 is their structural vehicle; `root_explore_and_target_pruning` / `score_utility_search` stay partial
  (optional CPU follow-up on the surviving 60-game `logSearchInfo` log).
- `[OPEN] non-blocking`: `o05`,`o11`,`o12`,`o15`,`o20`,`o21`,`o29`,`o32`,`o33`,`o36`. `[FUTURE]`: `async_multi_gpu_layout`,
  nbt family, o25 trip-under-sbatch.

## GPU queue / decisions needed from the human

- **L40S while B200 is saturated? Still open, unchanged.** Both smoke jobs did eventually run on b200
  (298712 completed, 299259 resumed and ran), so the queue pressure did not block this wave, but
  `sinfo -p b200` saturation and `l40s`'s `AllowAccounts=ALL` status are unchanged facts.
  `mission.json.compute.partitions` is still `["b300","b200"]` and `check.sh` still hard-rejects l40s.
  **Decision needed**: allow l40s for smoke-sized (1-GPU, non-production) jobs? The first real production
  chain (multi-day, `o39`-gated) will make queue time matter more than the smoke did.
- Prior decisions (2026-09-03) remain fully propagated; no action needed there.

## Audit references

Ledgers `results/ledgers/{error,knowledge,claim,result}/paper_arxiv-1902.10565/` · DAG `decomposition/logic.md`,
`results/ktg/GLOBAL_DAG.md` · design `decomposition/DESIGN.md` · knobs `codes/loop/knobs_9x9.env`,
`evidence/derive_cycle_knobs/derived_knobs.json` (ramp model stale pending o40) · digest
`progress/ktg-train/HUMAN_DIGEST.md` · commit grammar `phys-agentic-loop/_common/contracts/commit_template.md`.
