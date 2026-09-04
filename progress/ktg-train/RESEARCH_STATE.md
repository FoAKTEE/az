# RESEARCH_STATE — ktg-train

**Mission.** Train a 9×9 transformer-trunk KataGo net end-to-end (self-play → shuffle → train → export →
gatekeeper) on the Schmidt B200/B300 cluster within the compute policy (≤4 GPUs total, no CPU cap, b300
preferred / b200 fallback, 3-day walltime). **Phase.** 2-work wave 2 closed (4 nodes executed +14 code-map
re-affirmed; wave-2 plan committed, smoke job 298712 submitted) → wave 3 pending the smoke result. **Branch.**
az `main` (consumer), framework submodule `ssci`. **Paper id (ledger label only).** `arxiv-1902.10565`.
**Layout.** consumer artifacts at the `az` root: `results/`, `progress/`, `ref-code/`, `ref-paper/`, `mission.json`;
tools run as `python3 phys-agentic-loop/_common/...` from `az`. **Runtime.** `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/`.

## Source Library

| ID | Source | Status | Notes |
|---|---|---|---|
| `code` | `ref-code/lightvector-KataGo/` @ v1.18.2 `fd0723fd` | `[SOLID]` | primary source of truth (code-first). `results/ktg/sources/code_lightvector-KataGo.md` |
| `paper` | `ref-paper/arxiv-1902.10565/` | `[SOLID]` | background only |
| `cluster` | `docs/cluster-manual.md` | `[SOLID]` | b200 15/16 nodes allocated (1 idle), l40s 5/6 mixed-use, `AllowAccounts=ALL` — not in `mission.json.compute.partitions` or `check.sh`'s allow-list |
| `reviews` | `evidence/decomposition/dag_reconciliation.md` | `[SOLID]` | canonical 38-node DAG |

## Working Context (detail: `nodal_note.md`, `decomposition/DESIGN.md`)

| Name | Meaning | Status |
|---|---|---|
| board/trunk | 9×9 only; trunk `b7c96h3tfrs` (SwiGLU FFN — `b5c48h3tfr`'s `ffng` unservable in CUDA) | `[SOLID]`/`[PRELIMINARY]` |
| loop | mission copy of `synchronous_loop_9x9.sh` + `loop.sbatch` chain wrapper; USEGATING=1, cycle 1 gates vs. random baseline; threads selfplay 18/gatekeeper 18 game (22 OS threads measured) | `[PRELIMINARY]`; `o02`,`o03`,`o13` open |
| data budget | scratch guard: 500 GiB mission-root cap / 1 TiB group-free floor, constants in `budget.env`, `loop.sbatch` fully delegates (no inline literals) | `[HYPOTHESIS]` node, result `conditional`; `o32` open non-blocking |
| build | CUDA + cuDNN 9.19, `cmake-sm100.diff`; `env_build` solid | `[SOLID]` |
| CPU/scratch policy | fully propagated this wave: `a11` retired, `o22` waived, `o04` discharged; `DESIGN.md`/`implementation.md`/`loop.sbatch` all read 500 GiB / no-cap live | `[SOLID]` (closed) |

## Active Claims (ledger `results/ledgers/claim/paper_arxiv-1902.10565/`, 64 entries: 16 claims (3 admitted/3 in_progress/10 open), 36 obligations (17 discharged/17 open/2 waived), 12 assumptions (11 active/1 retired))

| Claim | Needed evidence | Priority |
|---|---|---|
| c01/c02 env_build; c04 all SGFs SZ[9] | admitted | closed |
| c03 b7 export loads; c05 pos_len-9 shuffle+train; c07 one loop cycle; c10 rows/game | numerical/empirical | **wave 3: smoke job 298712** |
| c06 threads ≤24 (partial: selfplay clause only); c08 kill/resume; c11 mission root ≤500 GiB | empirical | wave 3 |
| c13 ≥1 gatekeeper acceptance; c14 400-game CI excludes 0.5 (p≥0.60) | statistical_inference | P1 exit |
| c15 paper ideas present in code | literature_grounding | 14 code-map nodes re-affirmed preliminary |

## Accepted Results Log

<!-- Pointer to the GENERATED block: python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565 -->
<!-- Re-run this wave (2026-09-04): 5 admitted rows, full BEGIN/END block ~13 KB — over the 10240 B cap on its own,
     so only the pointer + one-line summaries are kept here; full rows in nodal_note.md `## Accepted-results snapshot`
     and reproducible verbatim by re-running the command. -->
1. `env-toolchain-b200` — empirical, admitted (job 298018).
2. `r_loop_resume_under_walltime_static` — existence_only, admitted; o33/o35 open non-blocking.
3. `data-budget-guard-500gib` — conditional, admitted; node stays hypothesis, o32 open non-blocking.
4. `r_tiny_model_export_smoke_b7c96h3tfrs` — empirical, admitted.
5. `cfg-9x9-override` — empirical, admitted; knowledge row preliminary under a visible `skip_exec` bypass, o30 open blocking-before-smoke-closure.

## Next Work Steps — wave-3 READY frontier

- `[OPEN] synchronous_loop_smoke` — job **298712 submitted, PENDING** (b200, 1 GPU/24 CPU/64G/3h, queue est. ~21:00 2026-09-04). Legs A-E land 13 sub-results (S1-S13, see `tasks/synchronous_loop_smoke/`): o30 in-allocation re-verify, 2 loop cycles (c07), gate-vs-random (o19), SZ[9]/pos_len-9 pipeline (c04,c05), 14 code-map probes, throughput record (`measure_stage_throughput` input), rows/game (c10, `derive_cycle_knobs_9x9` input).
- `[OPEN] o33/o35` (`loop_resume_under_walltime` wrapper residuals) — CPU, not needed by the smoke. **Constraint**: `crash-triage` → `pivot_structural` (next row must be `change_type=structural`); `simplification-status` independently wants a `refactor` row. `check-pivot --change-type refactor` → blocked; `--change-type structural` → ok. Open tension, not resolved by this note — see `current_iter.md` §3(b).
- `[OPEN] o32_data_budget_guard_hardening` (non-blocking) — `crash-triage` → `escalation` on the failing-row subsequence (iters 5-7), though the task's actual last attempt (iter 8) passed and the result was admitted; treat as "next repair should be structural/escalated, not a scalar guard tweak" rather than "task is stuck."
- `[OPEN] after the smoke lands` — `derive_cycle_knobs_9x9` (CPU, `derive_knobs.py` K1-K7, closes o24+o13) → `verify_preemption_resume` (c08), `loop_failure_circuit_breaker` (o25) → P1 five stages → `bootstrap_accepted_model` → `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first` → `eval_improvement` → `scale_*` → `scale_up`.
- `[BLOCKING]` before P1: `o02`, `o03`, `o13`, `o24`, `o30`, `o33`, `o35`. `[OPEN]` non-blocking: `o05`,`o12`,`o19`,`o20`,`o21`,`o29`,`o32`. `[FUTURE]`: `async_multi_gpu_layout`, nbt family.

## GPU queue / decisions needed from the human

- **B200 is near-saturated**: `sinfo -p b200` → 15/16 nodes allocated, 1 idle; job 298712 (1 GPU) queued ~20h. **L40S is `AllowAccounts=ALL`** (open to us, `docs/cluster-manual.md` §3), `sinfo -p l40s` shows 5/6 nodes mixed-use (some headroom), but is **not** in `mission.json.compute.partitions` (`["b300","b200"]`) and `.claude/skills/compute-budget/check.sh` hard-**VIOLATION**s any partition other than b200/b300. **`[OPEN]` decision needed**: allow l40s for smoke-sized (1-GPU, non-production) jobs while B200 is saturated? Affects `mission.json.compute.partitions`, `check.sh`'s allow-list, and whether B200-only results (e.g. `env-toolchain-b200`'s sm_100-specific SASS claim) need an L40S-specific counterpart or stay B200-only by design.
- Prior decisions (2026-09-03, `mission.json.decisions[]`, landed `ace9d0c`) are now **fully propagated**: no CPU limit, 500 GiB scratch, b200-while-b300-reserved — closed this wave (`a11` retired, `o22` waived, `o04` discharged, all files consistent). No action needed.

## Audit references

Ledgers `results/ledgers/{error,knowledge,claim,result}/paper_arxiv-1902.10565/` · DAG `decomposition/logic.md`,
`results/ktg/GLOBAL_DAG.md` (regenerated 2026-09-04) · design `decomposition/DESIGN.md` · digest
`progress/ktg-train/HUMAN_DIGEST.md` · commit grammar `phys-agentic-loop/_common/contracts/commit_template.md`.
