# RESEARCH_STATE — ktg-train

**Mission.** Train a 9×9 transformer-trunk KataGo net end-to-end (self-play → shuffle → train → export →
gatekeeper) on the Schmidt B200/B300/L40S cluster within the compute policy (≤4 GPUs total, no CPU cap,
b300 preferred / b200,l40s fallback, per-link walltime 23:30:00). **Phase.** wave 3: production chain
**executing, link 2 of 9**. The six pre-launch repairs are cross-model admitted; link 1 ran to its walltime
TIMEOUT (SIGKILL) at 157 cycles; the human chose **knob option C** for link 2 onward on a monitored
rows/game drift; link 2 is running under it and its first cycle already meets the upgrade clause. A
separate, human-directed 7x7 convergence test is training to a measured plateau in parallel.
**Branch.** az `main` (consumer), framework submodule `ssci`. **Namespace (ledger label only).**
`arxiv-1902.10565` — code-first (`ref-code/lightvector-KataGo` primary; paper background only). **Layout.**
consumer artifacts at the `az` root: `results/`, `progress/`, `ref-code/`, `ref-paper/`, `mission.json`;
tools run as `python3 phys-agentic-loop/_common/...` from `az`. **Runtime.**
`/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/`.

## Training status (for the human)

**Link 1 (job 301099, l40s/gl111) ENDED 2026-09-05T18:22:24**, TIMEOUT at 23:30:11, 157 cycles, **58
accepted / 2 rejected** (the first rejections of the run, both narrow: 92.5–100.5, 96.5–100.5). The BATCH
step was SIGKILLed, so its own finalize/TERM-trap logic never ran — a documented, non-defective boundary
(`o25` residue): nothing is lost, the queued successor simply runs, but P9's classification half and
`.failcount`'s proof are undemonstrated on this boundary; two more chain boundaries remain that could
settle them. During link 1's last two monitoring reads (7, 8) the rows/game decline that motivated a knob
change **stalled and reversed** (marginal 16.6266→16.9406, first rise of the series) and **value loss's
drift also reversed** (peaked 0.6026, back under 0.60) — recorded as a finding, not yet a conclusion: the
knob change (below) was already committed before this reversal was read.

**Link 2 (job 305318) is RUNNING on the same l40s node since 18:23:21**, chain depth 2/9, resumed
losslessly from link 1's last net. It runs under the human-selected **knob option C**
(`NUM_GAMES_PER_CYCLE` 1000→1800, `NUM_TRAIN_SAMPLES_PER_EPOCH` 20000→16000, `NUM_TRAIN_SAMPLES_PER_SWA`
10000→8000, `MAX_TRAIN_SAMPLES_PER_CYCLE` 100000→80000; sha256 `ba7f1bf7e1bc166d`) after a worker
re-derivation established that **an epoch trains one whole shuffled output file** (`SHUFFLE_KEEPROWS`
split two ways), not `NUM_TRAIN_SAMPLES_PER_EPOCH` — the loop's real reuse quantity is
rho = `SHUFFLE_KEEPROWS`/(games·rows_per_game), which option C roughly halves from link 1's 7.08 (89% of
its cap of 8) toward ~3.9–4.0. Link 2's first cycle confirms this directly from the trainer's log
(109 442 rows against E=16 000) and meets the option's own upgrade clause; result `r_cycle_knobs_9x9_derived`
is amended conditional→**empirical** by the worker, **pending independent validator cross-check**. A
successor (job 314831) is correctly queued. One residual defect: link 2's own script copy predates the
successor-id-parse fix (o46, already landed for the next resubmission), so its log still misreports "chain
not extended" though the chain is intact. The o48 slope-aware drift check does not fire; its `r_lo` leg is
**not computable this read** — `prune_retention.py` deletes selfplay history at every link start, leaving
only 6 of the 9 directories the trend fit needs (a structural gap to reword, not a one-off).

**Loss curve** (human-facing artifact): https://claude.ai/code/artifact/b7a554d2-fff8-49e0-8c9b-020c7ac906bb .
**Games viewer, cycles 1–50 / 51–107 / 81–157**: see orchestrator message.

A separate 7x7 convergence test (job 301096/continuation) trains to a human-authorized measured-plateau
stop; unchanged in mechanism this wave — see `nodal_note.md` for its window detail.

## Source Library

| ID | Source | Status | Notes |
|---|---|---|---|
| `code` | `ref-code/lightvector-KataGo/` @ v1.18.2 `fd0723fd` | `[SOLID]` | primary source of truth (code-first) |
| `paper` | `ref-paper/arxiv-1902.10565/` | `[SOLID]` | background only |
| `cluster` | `docs/cluster-manual.md` | `[SOLID]` | b200/b300/l40s partition notes |
| `reviews` | `evidence/decomposition/dag_reconciliation.md` | `[SOLID]` | canonical 39-node DAG |

## Working Context (detail: `nodal_note.md`, `decomposition/DESIGN.md`)

| Name | Meaning | Status |
|---|---|---|
| board/trunk | 9×9 only; trunk `b7c96h3tfrs` (SwiGLU FFN) | `[SOLID]` |
| loop (production) | link 1 ended (TIMEOUT/SIGKILL, o25 residue); link 2 running under option C | `[PRELIMINARY]`; `o03` open blocking, closed by the chain itself |
| cycle knobs | option C in force from link 2; samples/cycle = SHUFFLE_KEEPROWS (whole-file epochs), not E | result **empirical** (worker-asserted); `o48` open blocking (slope-aware), `o49` `[FUTURE]` |
| scale_data_window | rows/game drift monitor; moved hypothesis→preliminary this wave | `[PRELIMINARY]`; o48's r_lo leg structurally at risk under retention pruning |
| 7x7 test | separate short-cycle loop; converging to a measured plateau | `[HYPOTHESIS]`; no terminal claim yet |
| data budget | scratch guard: 500 GiB mission-root cap; unchanged this wave | `[HYPOTHESIS]`, conditional; `o32` open non-blocking |
| build | CUDA + cuDNN 9.19, `cmake-sm100.diff`; `env_build` solid | `[SOLID]` |

## Active Claims (ledger `results/ledgers/claim/paper_arxiv-1902.10565/`: 16 claims [5 admitted/3
in_progress/6 open/2 refuted], 50 obligations [31 discharged/17 open/2 waived, up from 46/29/15/2], 12
assumptions [11 active/1 retired])

| Claim | Status | Notes |
|---|---|---|
| c01/c02 env_build; c04 SGFs SZ[9]; c05 pos_len-9 pipeline; c07 loop cycle | admitted | closed |
| c06 threads ≤24 | **refuted** | superseded by the 32-CPU knob |
| c10 rows/game ≤10 KiB/game on disk | **refuted as written** | rows/game clause holds |
| c03 export loads; c11 scratch ≤500 GiB; c15 paper↔code | in_progress | production chain settling these |
| c08 kill/resume; c09 selfplay rate; c12 loss decreases; c13 ≥1 gate accept; c14 CI excludes 0.5; c16 scale-up | open | needs the chain to progress further |

## Accepted Results Log

<!-- python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565 -->
<!-- Re-run this wave: 15 distinct result_id, 29 rows incl. amendments; full block far over the 10240 B
     cap, one-line pointers kept here, reproducible verbatim by re-running the command. -->
1–12. unchanged since iteration 4 (see prior `git log` revision of this file for the full list: env
toolchain, loop-resume-static, data-budget guard, tiny export smoke, cfg-9x9-override, synchronous-loop
smoke, threads-realnet [refuted], throughput-tiny, probe-training, probe-search, full-frac-binning
[unchecked], c10-bytes-per-game [refuted-as-written]).
13. `r_cycle_knobs_9x9_derived` — **amended conditional→empirical this wave**, worker-asserted on link 2's
    first cycle (whole-file epoch confirmed from the trainer's own log); cross-model validation pending.
14. `r_smoke_full_frac_rebinned` — empirical, admitted (playout_cap_randomization solid).
15. `r_env_l40s` — empirical, admitted as `runnable`.

## Next Work Steps

- `[BLOCKING]` `o48_rows_per_game_drift_rederive_at_13` — slope-aware drift check, monitored every link-2
  read; its `r_lo` leg is **not computable** while `prune_retention.py` deletes selfplay history at link
  start (6 of 9 directories survive). Reword the leg (drop it, or source the fit window from a
  retention-surviving record) before the next read that needs it.
- **Monitor link 2** to its own boundary (successor 314831); confirm the o46 fix lands on 314831's own
  resubmission (link 2's copy predates it); state link-2 P8 rates once several complete cycles exist.
- `[OPEN] o49_out_file_size_makes_epoch_operative` — `[FUTURE]`, untried structural lever
  (`shuffle.sh -approx-rows-per-out-file`) that would make E operative again for the export cadence.
- `[OPEN] non-blocking`: `o05,o11,o12,o15,o20,o21,o29,o32,o33,o36,o40,o42,o43`. `[FUTURE]`:
  `async_multi_gpu_layout`, nbt family, `o25` trip-under-sbatch (deliberate injection, not planned).
- **Eight tasks carry `simplification-status: required`**, unresolved (deferred while allocations run —
  `production_chain_9x9` §13 forbids mid-run script edits): the seven from iteration 4 plus
  `production_chain_9x9` newly required this wave.

## Decisions needed from the human

- **`[OPEN]` SGF/game-record archiving before `prune_retention.py` runs.** Retention currently deletes
  roughly 75% of a link's selfplay games within the day (it keeps only the newest generations needed for
  the drift fit and the storage cap). The per-cycle-range "all games" viewer (link 1: cycles 1–50 / 51–107
  / 81–157) is complete only for games written since the last prune, not for the chain's full history.
  Cost of archiving: extra scratch or off-scratch storage per link (not yet sized) and one more write path
  in the loop wrapper; cost of not archiving: the viewer's "all games" claim silently narrows every time
  retention runs, and the o48 `r_lo` trend fit loses its input window (see Next Work Steps). No action
  taken pending the human's choice.

## Audit references

Ledgers `results/ledgers/{error,knowledge,claim,result}/paper_arxiv-1902.10565/` · DAG `decomposition/logic.md`,
`results/ktg/GLOBAL_DAG.md` (regenerated this wave) · design `decomposition/DESIGN.md` · knobs
`codes/loop/knobs_9x9.env` (sha `ba7f1bf7e1bc166d`) · production evidence
`evidence/production_chain/{preflight,launch.json,status_log.txt}` · knob-change evidence
`evidence/scale_data_window/{apply_C.diff,boundary_check.txt,validation_apply_C.md}` · 7x7 evidence
`evidence/converged_7x7/` · digest `progress/ktg-train/HUMAN_DIGEST.md` · commit grammar
`phys-agentic-loop/_common/contracts/commit_template.md`.
