# RESEARCH_STATE — ktg-train

**Mission.** Train a 9×9 transformer-trunk KataGo net end-to-end (self-play → shuffle → train → export →
gatekeeper) on the Schmidt B200/B300/L40S cluster within the compute policy (≤4 GPUs total, no CPU cap,
b300 preferred / b200,l40s fallback, per-link walltime 23:30:00). **Phase.** wave 3: production chain
**executing** — the six pre-launch repairs (o39/o02/o41/o40/o38 + monitor) are cross-model admitted, the
human authorized L40S and it is measured runnable, and the first 9x9 chain link is RUNNING; a second,
human-directed converged 7x7 test run is executing in parallel to a measured-plateau stop, not a time cap.
**Branch.** az `main` (consumer), framework submodule `ssci`. **Namespace (ledger label only).**
`arxiv-1902.10565` — code-first (`ref-code/lightvector-KataGo` is the primary source; the paper is
background, cited only where the current code still implements the idea). **Layout.** consumer artifacts at
the `az` root: `results/`, `progress/`, `ref-code/`, `ref-paper/`, `mission.json`; tools run as
`python3 phys-agentic-loop/_common/...` from `az`. **Runtime.** `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/`.

## Training status (for the human)

**Two GPU jobs are live right now.** (1) The 9x9 production chain, link 1 of 9 — job **301099**, RUNNING on
an **L40S** (node gl111) since 2026-09-04T18:52. Cycle 1: selfplay and shuffle done, train stage running;
every read so far is within tolerance (31.17 rows/game vs. derived 31.68; thread counts 22/4/12 ≤ the 32-CPU
cap). Random-net selfplay runs 41 380 games/h here — 7.4× the smoke's rate — because production disables
`logSearchInfo`, a finding, not a fault. A successor (job 305318) is correctly queued (`afterany`, same
partition set) but the wrapper's own log wrongly claims "chain not extended": a site STDERR banner breaks
its job-id capture. Chain continuity, the breaker and the STOP brake are unaffected; the fix is one line, not
yet landed, expected to land before link 1's TIMEOUT (~2026-09-05T18:22) so link 2 self-corrects. **The
first real export is expected at cycle 5**, gated at cycle 6 (the trainer's whole-shuffled-file consumption
model, cross-model re-derived); no export before cycle 5, or none by cycle 8, is the abort signal — not a
normal gap. (2) A **7x7 convergence test**, run separately from the 9x9 mission (`a05_9x9_only` deliberately
stepped outside — this is evidence the training loop works, not that the 9x9 configuration does) — job
**301096**, RUNNING on a B200 (gb207) since 17:14. As of this note: 46 cycles, ~1.19M samples, policy loss
3.9209 → **1.55** (min; uniform baseline ln(50) = 3.912), value loss 0.924 → **0.565** (min 0.525), **43
accepted / 2 rejected** gatekeeper decisions — still falling steeply, nowhere near flat. The human replaced
its original 6 h time cap with a **plateau rule** mid-run: it now trains in same-directory continuation
segments (next segment 301186 already queued) until two consecutive evaluations show both policy and value
loss flat (<1% trailing-window change) AND no gatekeeper acceptance in 15 cycles, or diverges, or hits a
12-segment (~4 GPU-day) safety cap — then runs its closing 200-game match. Neither run has moved a knob.

## Source Library

| ID | Source | Status | Notes |
|---|---|---|---|
| `code` | `ref-code/lightvector-KataGo/` @ v1.18.2 `fd0723fd` | `[SOLID]` | primary source of truth (code-first). `results/ktg/sources/code_lightvector-KataGo.md` |
| `paper` | `ref-paper/arxiv-1902.10565/` | `[SOLID]` | background only |
| `cluster` | `docs/cluster-manual.md` | `[SOLID]` | b200/b300/l40s partition notes; l40s CPUs bind before its GPUs do (found this wave) |
| `reviews` | `evidence/decomposition/dag_reconciliation.md` | `[SOLID]` | canonical 39-node DAG |

## Working Context (detail: `nodal_note.md`, `decomposition/DESIGN.md`)

| Name | Meaning | Status |
|---|---|---|
| board/trunk | 9×9 only; trunk `b7c96h3tfrs` (SwiGLU FFN) | `[SOLID]` |
| loop (production) | asserts 32 CPUs, samples threads+GPU in-link, refuses non-pos_len-9 npz, reads `KTG_PARTITIONS`; running link 1 | `[PRELIMINARY]`; `o03`/`o25` open blocking, both settled by the chain itself |
| cycle knobs | derived + validated; export ramp cross-model re-derived (first candidate cycle 5, exports ≈5/10/15/19/22) | `[PRELIMINARY]`, result `conditional`; `o40` open non-blocking |
| L40S runnability | binary runs natively on sm_89 with no sm_89 image (sm_86 JIT-compat, measured); chain now uses it | empirical result; production-regime throughput `[OPEN]` |
| 7x7 test | separate short-cycle loop, parameterised behind defaulted vars; converging visibly; stops on a measured plateau | `[HYPOTHESIS]` (new); no terminal claim yet |
| data budget | scratch guard: 500 GiB mission-root cap; unchanged this wave | `[HYPOTHESIS]`, result `conditional`; `o32` open non-blocking |
| build | CUDA + cuDNN 9.19, `cmake-sm100.diff`; `env_build` solid | `[SOLID]` |

## Active Claims (ledger `results/ledgers/claim/paper_arxiv-1902.10565/`, 74 entries: 16 claims (5 admitted/3 in_progress/6 open/2 refuted), 46 obligations (29 discharged/15 open/2 waived), 12 assumptions (11 active/1 retired))

| Claim | Status | Notes |
|---|---|---|
| c01/c02 env_build; c04 SGFs SZ[9]; c05 pos_len-9 pipeline; c07 loop cycle | admitted | closed |
| c06 threads ≤24 | **refuted** | real-net/CUDA-context clause only; superseded by the 32-CPU knob |
| c10 rows/game ≤10 KiB/game on disk | **refuted as written** | rows/game clause holds; bytes/game 9-20% over |
| c03 export loads; c11 scratch ≤500 GiB; c15 paper↔code | in_progress | production chain settling these now |
| c08 kill/resume; c09 selfplay rate; c12 loss decreases; c13 ≥1 gate accept; c14 CI excludes 0.5; c16 scale-up | open | needs the running chain to progress further |

## Accepted Results Log

<!-- Pointer to the GENERATED block: python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565 -->
<!-- Re-run this wave (2026-09-04): 15 distinct result_id, 25 rows incl. amendments — the full BEGIN/END
     block is well over the 10240 B cap; one-line summaries kept here, full rows in nodal_note.md
     `## Accepted-results snapshot`, reproducible verbatim by re-running the command. -->
1. `env-toolchain-b200` — empirical, admitted.
2. `r_loop_resume_under_walltime_static` — existence_only, admitted; amended twice more this wave.
3. `data-budget-guard-500gib` — conditional, admitted; node hypothesis; o32 open non-blocking.
4. `r_tiny_model_export_smoke_b7c96h3tfrs` — empirical, admitted.
5. `cfg-9x9-override` — empirical, admitted; node preliminary.
6. `r_synchronous_loop_smoke` — empirical, admitted; c07 proved.
7. `r_smoke_threads_realnet` — **refuted**; 25 threads meas. vs. 24 declared (superseded by the 32-CPU knob).
8. `r_smoke_throughput_tiny` — empirical, admitted.
9. `r_smoke_probe_training` — empirical, admitted.
10. `r_smoke_probe_search` — empirical, admitted; re-scoped by the full_frac re-bin.
11. `r_smoke_full_frac_binning` — `unchecked`; worker's refutation was a binning artefact.
12. `r_smoke_c10_bytes_per_game` — **refuted as written**.
13. `r_cycle_knobs_9x9_derived` — conditional, admitted; export ramp cross-model re-derived this wave.
14. `r_smoke_full_frac_rebinned` — **new**: empirical, admitted; 0.2516 in [0.20, 0.30], two instruments.
15. `r_env_l40s` — **new**: empirical, admitted as `runnable`; production-regime throughput `[OPEN]`.

## Next Work Steps — wave-3 executing (ledger-computed 2026-09-04)

- `[BLOCKING, non-halting]` land the `resubmit()` successor-id fix (`loop.sbatch:554-560` — capture only the
  numeric id, not the site's STDERR BILLING banner); chain/breaker/STOP unaffected without it, but
  `cancel_successor()` is dead until it lands. Target: before link 1's TIMEOUT (~2026-09-05T18:22).
- **Monitor the 9x9 chain**: read 2 at ~3 h, then every 3 h through 24 h; boundary check at each link end;
  from link 3 on watch for the b300-pinning stall (`ea9a0e0` — escalate, don't tune). Settles P1-P12: first
  export (cycle 5), first gate (cycle 6), `nlwp_max` ≤ 32 on real/two-real-net stages (o03), breaker walltime
  half (o25), ≥1 acceptance by cycle 20 (c13), then one 400-game match (c14) → `eval_improvement`.
- **Monitor the 7x7 test to its plateau**: read `plateau_check.py`'s verdict every cycle; act only on
  `PLATEAU`/`ABORT` or the 12-segment cap; candidate rows staged in `evidence/converged_7x7/candidate_rows.json`
  for a refuter once terminal — not appended by a worker.
- `[OPEN] non-blocking`: `o05`,`o11`,`o12`,`o15`,`o20`,`o21`,`o29`,`o32`,`o33`,`o36`,`o40`,`o42`,`o43`.
  `[FUTURE]`: `async_multi_gpu_layout`, nbt family, o25 trip-under-sbatch (deliberate injection, not planned).
- **Seven tasks carry an open `simplification-status: required` flag**, unresolved (deferred while their
  allocations run — `production_chain_9x9` §13 forbids mid-run script edits): `data_budget`,
  `loop_resume_under_walltime`, `synchronous_loop_smoke`, `derive_cycle_knobs_9x9`, `wave3_prelaunch_repairs`,
  `production_chain_9x9`, `converged_test_7x7`.

## Decisions needed from the human

**None pending.** The L40S question open at iteration 3 is resolved (decisions[3]: allow whichever of
b200/l40s frees first; measured runnable, job 300987, chain is using it). The 7x7 stop-rule question is
also resolved (decisions[4]/[5]). `mission.json.decisions[]` holds 6 entries, all propagated.

## Audit references

Ledgers `results/ledgers/{error,knowledge,claim,result}/paper_arxiv-1902.10565/` · DAG `decomposition/logic.md`,
`results/ktg/GLOBAL_DAG.md` (regenerated this wave) · design `decomposition/DESIGN.md` · knobs
`codes/loop/knobs_9x9.env` · production evidence `evidence/production_chain/{preflight,launch.json,status_log.txt}`
· 7x7 evidence `evidence/converged_7x7/{status_log.txt,summary-301096.json,candidate_rows.json}` · digest
`progress/ktg-train/HUMAN_DIGEST.md` · commit grammar `phys-agentic-loop/_common/contracts/commit_template.md`.
