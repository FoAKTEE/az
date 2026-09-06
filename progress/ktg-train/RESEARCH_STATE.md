# RESEARCH_STATE — ktg-train

**Mission.** Train a 9×9 transformer-trunk KataGo net end-to-end (self-play → shuffle → train → export →
gatekeeper) on the Schmidt B200/B300/L40S cluster within the compute policy (≤4 GPUs total, no CPU cap,
b300 preferred / b200,l40s fallback, per-link walltime 23:30:00). **Phase.** wave 3: production chain
**STOPPED by human order on 2026-09-06 at 13:03 EDT**, cycle 249 (157 link 1 + 92 link 2), job 305318
COMPLETED rc=0, successor 314831 cancelled. Not a plateau, not a gate condition — a human decision, final.
A separate 7x7 convergence test was likewise **stopped by human decision on 2026-09-04**; no plateau there
either.
**Branch.** az `main` (consumer), framework submodule `ssci`. **Namespace (ledger label only).**
`arxiv-1902.10565` — code-first (`ref-code/lightvector-KataGo` primary; paper background only). **Layout.**
consumer artifacts at the `az` root: `results/`, `progress/`, `ref-code/`, `ref-paper/`, `mission.json`;
tools run as `python3 phys-agentic-loop/_common/...` from `az`. **Runtime.**
`/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/`.

## Training status — FINAL (for the human)

**The stop.** Order 2026-09-06 12:57 EDT: "this is good enough already, save all necessary checkpoints
and stop." Executed 12:59–13:03: successor 314831 cancelled first, `STOP` brake touched, loop exited
clean (`rc=0`, `finalize()` ran in full, `.failcount` reset to 0) at 13:03:06/10, job 305318 ended
13:03:11. No successor resubmitted; queue empty. Detail: `evidence/production_chain/status_log.txt`,
the `STOPPED BY HUMAN 2026-09-06` block.

**What the run reached.** 249 cycles (157×1000 + 92×1800 games/cycle), 322 600 self-play games,
28 950 784 samples trained, 93 accepted / 3 rejected exports. **Best net** (latest, and best on both
learned metrics over all 93 exports): `t9-s28711040-d3032547`, p0loss **1.468345**, pacc1 **0.546604**,
sha256 `4cbedf24…897f49c` — reached in the last three exports, not a plateau. The 19-export loss stall
(reads 9–13) was resolved by read 14 as a genuine new best, and independently shown NOT to be a strength
stall by the c14 match: latest-at-the-time vs the then loss-record net, 400 games, **p 0.7412, +183 Elo
[+146,+224]**; vs the frozen first net, 400/400 exact CI [0.991,1.000]. Raw `vloss` is **not** a strength
ranking (memo, §1: it tracks selfplay draw-share, r=0.835; the 0.62 flag is retired, replaced by
`tdvloss1`/ownership-loss/held-out triggers, none of which fired, plus the match-based rule o56).

**The checkpoint.** `/home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop` — 7 683 842 860 B
(7.2 GB), 10 957 files, `sha256sum -c MANIFEST.sha256` exits 0 (10 956 OK). Contains `p1/` (models,
rejectedmodels, train/t9 checkpoint, selfplay in full, shuffleddata, gatekeepersgf, logs, dot-state incl.
`STOP`), `t7/` (7x7 run in full), `code_snapshot/` (scripts, configs, env diffs, katago binary sha256),
`pages/` (16 game viewers + loss curves), `README.md` (stop record + resume procedure). Not saved: venv/
CUDA build/binary (rebuildable, sha256 recorded); empty dirs. Pointer + verify command:
`results/ktg/paper_1902.10565/evidence/production_chain/CHECKPOINTS.md`.

**Open items a resumption would inherit** (none blocks the stop itself — `status_log.txt` §7):
`budget.env:55` still `KTG_KEEP_SELFPLAY_GENERATIONS=3`; retention-60 fix (o52-adjacent) is **staged,
not applied** (`evidence/production_chain/retention_60/`, `apply_c1.sh --yes` not run); its vloss-
stability half was also not met on the last measured data (max |step| 0.006765 > 0.005 stated). No
validation split exists (`metrics_val.json` is 0 bytes). o48's r_lo leg never became computable
(`prune_retention.py` deletes its own input at every link boundary) and o48 itself never fired (marginal
17.12 vs 13.0 target at the last read). o54 (models dir unbounded, no prune rule) and o55 (a `!`
correction to `knobs_9x9.env:198`'s stale comment) remain open, informational only.

**7x7 test (job 301096), STOPPED 2026-09-04, unchanged since iteration 4-5**: 88 cycles, p0loss min
1.2641, vloss min 0.5249, 76/87 accepted. Flattening, never met two-consecutive-FLAT; closing match S5
waived by human decision — training-behaviour claim only, no strength claim.

**Human-facing pages**: loss curve https://claude.ai/code/artifact/b7a554d2-fff8-49e0-8c9b-020c7ac906bb ;
games viewer link 1 cycles 1–50/51–107/81–157, link 2 cycles 1–40/41–90 — see `HUMAN_DIGEST.md`.

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
| loop (production) | **STOPPED** by human order at cycle 249, clean rc=0 exit | terminal; `o03` closed by the chain |
| cycle knobs | option C in force through the stop; rho settled ~3.9 of cap 8 | **empirical** (worker-asserted, not cross-checked before stop) |
| value-loss diagnostic | raw `vloss` flag retired; match-based rule (o56) is the successor | `[SOLID]`-reasoning, cross-model memo; not yet a ledger row |
| c14 strength match | latest vs loss-record net +183 Elo; vs first net saturated | **empirical, admitted** |
| 7x7 test | stopped by human decision 2026-09-04, loss curve flattening | `[PRELIMINARY]`; no strength claim (S5 waived) |
| retention-60 | prepared, validated safe, **not applied** — human discretion | conditional, admitted; `o52` open |
| data budget | scratch guard: 500 GiB root cap; 2.9% used at stop | `[HYPOTHESIS]`, conditional; `o32`,`o54` open non-blocking |
| build | CUDA+cuDNN 9.19, `cmake-sm100.diff`; `env_build` solid | `[SOLID]` |

## Active Claims (`results/ledgers/claim/paper_arxiv-1902.10565/`: 16 claims [≥6 admitted/2 in_progress/
6 open/2 refuted], obligations o01–o56 [most discharged; o48,o49,o52,o54,o55,o56 open, non-blocking with
the chain stopped], assumptions unchanged ~12)

| Claim | Status | Notes |
|---|---|---|
| c01/c02 env_build; c04 SGFs SZ[9]; c05 pos_len-9 pipeline; c07 loop cycle; c14 CI excludes 0.5 | admitted | c14 closed by the 400-game match, p=0.7412 |
| c06 threads ≤24 | **refuted** | superseded by 32-CPU knob |
| c10 rows/game ≤10 KiB/game | **refuted as written** | rows/game clause holds |
| c03 export loads; c11 scratch ≤500 GiB | in_progress | last measured OK; frozen at the stop |
| c08 kill/resume; c09 selfplay rate; c12 loss decreases; c13 ≥1 gate accept; c16 scale-up | open | last measurements favorable; not further pursued — mission stopped |

## Accepted Results Log

<!-- python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565 -->
<!-- 18 distinct result_id at close; full block far over the 10240 B cap — pointers kept here,
     reproducible verbatim by re-running the command. -->
1–15. unchanged since iteration 5 (env toolchain, loop-resume-static, data-budget guard, tiny export
smoke, cfg-9x9-override, synchronous-loop smoke, threads-realnet [refuted], throughput-tiny,
probe-training, probe-search, full-frac-binning [unchecked], c10-bytes-per-game [refuted-as-written],
`r_cycle_knobs_9x9_derived` [empirical, worker-asserted], full-frac-rebinned, env-l40s).
16. c14 match — empirical, admitted: p 0.7412 [+183 Elo], 400/400 vs first net.
17. retention-60 preparation — conditional, admitted: staged, not applied.
18. read-14 best-on-both-metrics — empirical, admitted: p0loss 1.468828, pacc1 0.546105 (both run
    bests; superseded in-band by the final export's 1.468345/0.546604, same net family, no new row).

## Next Work Steps

- **NONE pending mission action** — stopped by human order. If ever resumed (human decision only):
  `[OPEN]` apply-or-discard the staged retention-60 edit before restarting link 3; `[OPEN] o52` decide
  SGF archiving (`KTG_ARCHIVE_SGF=0` today) before further pruning; `[OPEN] o48/o49` rows/game drift
  check never fired / untried lever, structural r_lo gap unresolved; `[OPEN] o54/o55` models-dir prune
  rule, knob-comment correction. Resume procedure: `CHECKPOINTS.md` "Resuming from it" /
  checkpoint `README.md` §7.

## Decisions needed from the human

**NONE outstanding.** The one open decision from iteration 5 (SGF/game-record archiving before
`prune_retention.py` runs) is superseded by the stop — no further pruning will occur unless the mission
is resumed, at which point it becomes live again (`o52`).

## Audit references

Ledgers `results/ledgers/{error,knowledge,claim,result}/paper_arxiv-1902.10565/` · DAG
`decomposition/logic.md`, `results/ktg/GLOBAL_DAG.md` · design `decomposition/DESIGN.md` · knobs
`codes/loop/knobs_9x9.env` (sha `ba7f1bf7e1bc166d`) · production evidence
`evidence/production_chain/{status_log.txt,CHECKPOINTS.md,c14_match_9x9/,retention_60/,
vloss_escalation_memo.md,validation_c14_retention60.md}` · checkpoint
`/home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop` · 7x7 evidence
`evidence/converged_7x7/{status_log.txt,summary-301096.json,candidate_rows.json}` · digest
`progress/ktg-train/HUMAN_DIGEST.md` · commit grammar
`phys-agentic-loop/_common/contracts/commit_template.md`.
