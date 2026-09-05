# RESEARCH_STATE — ktg-train

**Mission.** Train a 9×9 transformer-trunk KataGo net end-to-end (self-play → shuffle → train → export →
gatekeeper) on the Schmidt B200/B300/L40S cluster within the compute policy (≤4 GPUs total, no CPU cap,
b300 preferred / b200,l40s fallback, per-link walltime 23:30:00). **Phase.** wave 3: production chain
**executing, link 2 of 9**. The six pre-launch repairs are cross-model admitted; link 1 ran to its walltime
TIMEOUT (SIGKILL) at 157 cycles; the human chose **knob option C** for link 2 onward on a monitored
rows/game drift; link 2 is running under it and its first cycle already meets the upgrade clause. A
separate 7x7 convergence test ran to a flattening loss curve and was **stopped by human decision on
2026-09-05** ("stop 7x7 run now and work on GUI"); no plateau was declared.
**Branch.** az `main` (consumer), framework submodule `ssci`. **Namespace (ledger label only).**
`arxiv-1902.10565` — code-first (`ref-code/lightvector-KataGo` primary; paper background only). **Layout.**
consumer artifacts at the `az` root: `results/`, `progress/`, `ref-code/`, `ref-paper/`, `mission.json`;
tools run as `python3 phys-agentic-loop/_common/...` from `az`. **Runtime.**
`/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/`.

## Training status (for the human)

**Link 1 (job 301099, l40s/gl111) ENDED 2026-09-05T18:22:24**, TIMEOUT at 23:30:11, 157 cycles, **58
accepted / 2 rejected** (first rejections of the run, both narrow: 92.5–100.5, 96.5–100.5). The BATCH step
was SIGKILLed, so finalize/TERM-trap never ran — a documented, non-defective boundary (`o25` residue):
nothing lost, successor simply runs, but P9's classification half and `.failcount`'s proof are
undemonstrated here; two more chain boundaries could settle them. Link 1's last two reads (7, 8) show the
rows/game decline that motivated the knob change below **stalled and reversed** (marginal 16.6266→16.9406)
and **value loss's drift also reversed** (peaked 0.6026, back under 0.60) — noted, not a conclusion: the
knob change was already committed before this reversal was read.

**Link 2 (job 305318) is RUNNING on the same l40s node since 18:23:21**, chain depth 2/9, resumed
losslessly from link 1's last net, under the human-selected **knob option C** (`NUM_GAMES_PER_CYCLE`
1000→1800, `NUM_TRAIN_SAMPLES_PER_EPOCH` 20000→16000, `NUM_TRAIN_SAMPLES_PER_SWA` 10000→8000,
`MAX_TRAIN_SAMPLES_PER_CYCLE` 100000→80000; sha `ba7f1bf7e1bc166d`) after a worker re-derivation
established that **an epoch trains one whole shuffled output file** (`SHUFFLE_KEEPROWS` split two ways),
not `NUM_TRAIN_SAMPLES_PER_EPOCH` — the loop's real reuse quantity rho = `SHUFFLE_KEEPROWS`/(games·rows_
per_game), roughly halved by option C from link 1's 7.08 (89% of its cap of 8) toward ~3.9–4.0. Link 2's
first cycle confirms this from the trainer's own log (109 442 rows vs E=16 000); result
`r_cycle_knobs_9x9_derived` amended conditional→**empirical** by the worker, **pending validator
cross-check**. Successor 314831 correctly queued. Residual: link 2's own script copy predates the
successor-id-parse fix (o46, landed for the next resubmission), so its log still misreports "chain not
extended" though the chain is intact. o48 does not fire; its `r_lo` leg is **not computable this read** —
`prune_retention.py` deletes selfplay history at link start, leaving only 6 of the 9 needed directories
(structural, to reword — not a one-off).

**Loss curve** (human-facing artifact): https://claude.ai/code/artifact/b7a554d2-fff8-49e0-8c9b-020c7ac906bb .
**Games viewer, cycles 1–50 / 51–107 / 81–157**: see orchestrator message.

**7x7 test (job 301096) is STOPPED, not running.** `sacct`: CANCELLED 2026-09-04T20:23:54 local
(2026-09-05T00:23:54Z), elapsed 3:09:19; continuation segment 301186 CANCELLED same instant, never started.
Human stop ("stop 7x7 run now and work on GUI"), not the plateau rule (`converged=false` in
`summary-301096.json`) and not an abort. Final: 88 cycles, 2,449,536 samples, p0loss min **1.2641** (from
3.9209, baseline ln50=3.912), vloss min **0.5249** (from 1.2977), **76 accepted / 11 rejected**. Loss was
flattening but never met two-consecutive-FLAT; closing match S5 **waived by human decision**, so no
strength claim, training-behaviour only. Candidate rows staged unappended in
`evidence/converged_7x7/candidate_rows.json`, marked `"STOPPED BY HUMAN DECISION ... not a plateau, not
an abort"`.

## Source Library

| ID | Source | Status | Notes |
|---|---|---|---|
| `code` | `ref-code/lightvector-KataGo/` @ v1.18.2 `fd0723fd` | `[SOLID]` | primary (code-first) |
| `paper` | `ref-paper/arxiv-1902.10565/` | `[SOLID]` | background |
| `cluster` | `docs/cluster-manual.md` | `[SOLID]` | b200/b300/l40s notes |
| `reviews` | `evidence/decomposition/dag_reconciliation.md` | `[SOLID]` | canonical DAG |

## Working Context (detail: `nodal_note.md`, `decomposition/DESIGN.md`)

| Name | Meaning | Status |
|---|---|---|
| board/trunk | 9×9; trunk `b7c96h3tfrs` (SwiGLU FFN) | `[SOLID]` |
| loop (production) | link 1 ended TIMEOUT/SIGKILL (o25 residue); link 2 running under option C | `[PRELIMINARY]`; `o03` open blocking, closed by the chain |
| cycle knobs | option C in force from link 2; samples/cycle = SHUFFLE_KEEPROWS (whole-file epochs), not E | **empirical** (worker-asserted); `o48` open blocking, `o49` `[FUTURE]` |
| scale_data_window | rows/game drift monitor; hypothesis→preliminary this wave | `[PRELIMINARY]`; o48's r_lo leg at risk under retention pruning |
| 7x7 test | separate short-cycle loop; stopped by human decision 2026-09-05 at 88 cycles, loss curve flattening | `[PRELIMINARY]`; training-behaviour claim supportable, no strength claim (S5 match waived) |
| data budget | scratch guard: 500 GiB root cap; unchanged this wave | `[HYPOTHESIS]`, conditional; `o32` open non-blocking |
| build | CUDA+cuDNN 9.19, `cmake-sm100.diff`; `env_build` solid | `[SOLID]` |

## Active Claims (`results/ledgers/claim/paper_arxiv-1902.10565/`: 16 claims [5 admitted/3 in_progress/
6 open/2 refuted], 50 obligations [31 discharged/17 open/2 waived], 12 assumptions [11 active/1 retired])

| Claim | Status | Notes |
|---|---|---|
| c01/c02 env_build; c04 SGFs SZ[9]; c05 pos_len-9 pipeline; c07 loop cycle | admitted | closed |
| c06 threads ≤24 | **refuted** | superseded by 32-CPU knob |
| c10 rows/game ≤10 KiB/game | **refuted as written** | rows/game clause holds |
| c03 export loads; c11 scratch ≤500 GiB; c15 paper↔code | in_progress | chain settling these |
| c08 kill/resume; c09 selfplay rate; c12 loss decreases; c13 ≥1 gate accept; c14 CI excludes 0.5; c16 scale-up | open | needs the chain further |

## Accepted Results Log

<!-- python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565 -->
<!-- Re-run this wave: 15 distinct result_id, 29 rows incl. amendments; full block far over the 10240 B
     cap, one-line pointers kept here, reproducible verbatim by re-running the command. -->
1–12. unchanged since iteration 4 (`git log` on this file for the full list: env toolchain, loop-resume-
static, data-budget guard, tiny export smoke, cfg-9x9-override, synchronous-loop smoke, threads-realnet
[refuted], throughput-tiny, probe-training, probe-search, full-frac-binning [unchecked], c10-bytes-per-game
[refuted-as-written]).
13. `r_cycle_knobs_9x9_derived` — **amended conditional→empirical this wave**, worker-asserted on link 2's
    first cycle; cross-model validation pending.
14. `r_smoke_full_frac_rebinned` — empirical, admitted.
15. `r_env_l40s` — empirical, admitted as `runnable`.

## Next Work Steps

- `[BLOCKING]` `o48_rows_per_game_drift_rederive_at_13` — slope-aware drift check, monitored every link-2
  read; `r_lo` leg **not computable** while `prune_retention.py` deletes selfplay history at link start
  (6 of 9 dirs survive). Reword (drop, or source the fit window from a retention-surviving record).
- **Monitor link 2** to its boundary (successor 314831); confirm o46's fix lands on 314831's resubmission
  (link 2's copy predates it); state link-2 P8 rates once several cycles complete.
- `[OPEN] o49_out_file_size_makes_epoch_operative` — `[FUTURE]`, untried lever
  (`shuffle.sh -approx-rows-per-out-file`) that would make E operative for the export cadence.
- `[OPEN]` `converged_test_7x7` stopped, not closed: candidate rows staged (S1-S4 settled, S5 waived) for
  a validator to admit.
- `[OPEN] non-blocking`: `o05,o11,o12,o15,o20,o21,o29,o32,o33,o36,o40,o42,o43`. `[FUTURE]`:
  `async_multi_gpu_layout`, nbt family, `o25` trip-under-sbatch (deliberate injection, not planned).
- **Eight tasks carry `simplification-status: required`**, unresolved (deferred while allocations run —
  `production_chain_9x9` §13 forbids mid-run script edits): the seven from iteration 4 plus
  `production_chain_9x9` newly required this wave.

## Decisions needed from the human

- **`[OPEN]` SGF/game-record archiving before `prune_retention.py` runs.** Retention deletes roughly 75%
  of a link's selfplay games within the day, keeping only the newest generations. The per-cycle-range "all
  games" viewer (link 1: cycles 1–50 / 51–107 / 81–157) is complete only since the last prune, not for the
  chain's full history. Cost of archiving: extra scratch/off-scratch storage per link (not yet sized) plus
  one more write path in the loop wrapper; cost of not archiving: the viewer's "all games" claim narrows
  every prune, and o48's `r_lo` fit loses its input window. No action taken pending the human's choice.

## Audit references

Ledgers `results/ledgers/{error,knowledge,claim,result}/paper_arxiv-1902.10565/` · DAG
`decomposition/logic.md`, `results/ktg/GLOBAL_DAG.md` · design `decomposition/DESIGN.md` · knobs
`codes/loop/knobs_9x9.env` (sha `ba7f1bf7e1bc166d`) · production evidence
`evidence/production_chain/{preflight,launch.json,status_log.txt}` · knob-change evidence
`evidence/scale_data_window/` · 7x7 evidence `evidence/converged_7x7/{status_log.txt,summary-301096.json,
candidate_rows.json}` · digest `progress/ktg-train/HUMAN_DIGEST.md` · commit grammar
`phys-agentic-loop/_common/contracts/commit_template.md`.
