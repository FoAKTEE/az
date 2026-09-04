# Implementation — `data_budget`

## 0. Header

**Task ID:** `data_budget`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::data_budget`
**Language:** bash (`du`, `df`, quota) + Python (retention pruning)
**Method class:** simulation / empirical measurement (thresholds set from code constants, enforced by the loop wrapper)

## 1. Claim

> The whole mission root `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` — venv, build and loop data together — stays under a hard cap of 200 GiB (`214748364800` B), starts no new cycle at or above 180 GiB (`193273528320` B), and holds a bounded retention set with a logged protected set, enforced by the loop wrapper rather than by convention (claim `c11_scratch_budget`; obligation `o04_scratch_budget`).

## 2. Success Criterion

- **Needed evidence type:** `empirical_measurement` (a live `du -sb` plus the enforcing greps)
- **Done when:** the guard is present in the loop wrapper and the mission root is under the hard cap.
- **Verification command:**
  `grep -q 'du -sb' results/ktg/paper_1902.10565/codes/loop/loop.sbatch && grep -q quotas.py results/ktg/paper_1902.10565/codes/loop/loop.sbatch && grep -q 193273528320 results/ktg/paper_1902.10565/codes/loop/loop.sbatch && test $(du -sb /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train | cut -f1) -le 214748364800`
- **Measured tolerance / metric:** all three greps hit (count `>= 1` each); `du -sb` on the mission root `<= 214748364800` B. Exact byte integers, no tolerance band — a guard written in decimal GB or scoped to `BASEDIR` instead of the mission root fails the greps.
- **Open obligations before start:** `o04_scratch_budget`. The wrapper file itself is authored by `loop_resume_under_walltime`; this node owns the thresholds, the retention policy and the closing measurement.
- **Reduction-to-baseline test:** NA

Scope is the **mission root**, not `BASEDIR`: the venv and the KataGo build already occupy ~7.5 GB before any loop data exists, and the group filesystem is the shared resource. Bytes/row calibration on real data is **not** this node's — it belongs to `measure_stage_throughput`, which re-measures after 100k rows.

## 3. Motivation

Group scratch was at **37.71 TB of 40.00 TB (94 %)** when this task was written (`python3 /apps/helpers/quotas.py`, 2026-09-03T22:01) — `docs/cluster-manual.md` §4 trap 1 warns that writes then start failing for the whole group, not just this mission. Nothing upstream prunes `selfplay/<model>/tdata|sgfs`, `models/`, `rejectedmodels/`, `train/<name>/longterm_checkpoints/` or `scripts/dated/` (`audit_loop_scripts_configs.md` §F "Footprint growth"), and `cleanup_old_dirs.py` never touches orphan `.tmp` directories. The cap must therefore be enforced by the mission's own wrapper, before each cycle.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §1 `dataBoardLen`, `maxRowsPerTrainFile`; §5 shuffler flags |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §4 rows/game and bytes/row arithmetic |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | `data_budget`: single predecessor `data_format_pos_len`; successors `synchronous_loop_smoke`, `selfplay_stage`, `scale_data_window`, `scale_up` |
| implementation_plan | `results/ktg/paper_1902.10565/decomposition/implementation_plan_python.md` | `rows_per_game.py`, `prune_checkpoints.py` |
| ref | `results/ktg/paper_1902.10565/decomposition/ref.md` | v1.18.2 provenance |
| assumptions | `results/ktg/paper_1902.10565/decomposition/assumptions.md` | `a07_moves_per_game_80`, `a05_9x9_only` |
| claims | `results/ktg/paper_1902.10565/decomposition/claims.md` | `c11`, background `c10` |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | `o04` |
| result_seed | `results/ktg/paper_1902.10565/decomposition/result_seed.md` | initial status and dependencies |

**Upstream task outputs:** none required — the single predecessor `data_format_pos_len` is a read-only code-map node (`cpp/dataio/trainingwrite.cpp:288-334`). The edge from `synchronous_loop_smoke` is removed: the guard must exist **before** the first cycle runs, not after it.
**Evidence pack:** `evidence/decomposition/audit_loop_scripts_configs.md` §F (per-row byte table, footprint growth), §A (loop cycle constants).

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- Two-stage discipline: the code-constant budget is admitted as `approximate`; only the measured cap check is admitted as `empirical`.
- Never let the guard be advisory — the loop wrapper calls it *before* each cycle and refuses to start above 180 GiB.
- Every retention rule names its protected set explicitly and logs it; nothing is deleted implicitly.
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference paper | `ref-paper/arxiv-1902.10565/` |
| Reference code | `ref-code/lightvector-KataGo/` |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/eval/`, thresholds consumed by `codes/loop/loop.sbatch` |
| Plot / figure output | `results/ktg/paper_1902.10565/plots/` |
| Loop notes | `results/ktg/paper_1902.10565/loop_note/` |
| Progress dir | `progress/paper_1902.10565/data_budget/` |
| Git branch | `ssci` |
| Mission root (capped) | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` |
| `BASEDIR` (loop data) | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/loop` |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/eval/
├── scratch_cap.sh      # node data_budget - du -sb / df -B1 / quotas.py triple on the mission root; exit 1 at >= 180 GiB
├── prune_retention.py  # node data_budget - bounded retention with a logged protected set
└── rows_per_game.py    # node data_budget - planning-only rows/game + bytes/game reporter (calibration is measure_stage_throughput's)
```

`codes/loop/loop.sbatch` (authored by `loop_resume_under_walltime`) calls `scratch_cap.sh` at the top of each cycle and logs its triple once per cycle. This node owns the two byte constants that appear there.

## 8. Phase Plan

### Phase 1 - `guard`
- **Nodes:** `data_budget`
- **Files:** `scratch_cap.sh`, plus the two byte constants in `codes/loop/loop.sbatch`
- **Test:** the §2 verification command; `scratch_cap.sh` exits 0 today and exits 1 when `KTG_SCRATCH_SOFT_BYTES` is lowered below the current usage.
- **Estimate:** `0.5` h

### Phase 2 - `retention`
- **Nodes:** `data_budget`
- **Files:** `prune_retention.py`, `rows_per_game.py`
- **Test:** on a synthetic tree, `longterm_checkpoints` is left with `<= 6` files, `rejectedmodels` with `<= 10` dirs, zero stale `shuffleddata/*.tmp`, and every path in the protected set survives and is printed.
- **Estimate:** `0.5` h

## 9. Quick-Win Path

1. `Phase 1` — run `scratch_cap.sh` now; record `du -sb`, `df -B1` and `quotas.py` as the baseline row.
2. `Phase 2` — exercise `prune_retention.py` on a synthetic tree; no loop data is needed.
3. **Smoke check:** the §2 command exits 0 from the repo root on a login node.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| hard cap (mission root) | `214748364800` B = 200 GiB | `c11_scratch_budget`; mission design decision, binary GiB |
| soft cap (no new cycle) | `193273528320` B = 180 GiB | leaves one full cycle of headroom above the hard cap |
| capped path | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` | venv + build + loop data; **not** `BASEDIR` alone |
| per-cycle log triple | `du -sb <root>`, `df -B1 <root>`, `python3 /apps/helpers/quotas.py` | one line per cycle in the wrapper log; the group figure is the escalation trigger |
| `longterm_checkpoints` retention | `<= 6` | written every 12 h and never pruned upstream (`python/train.py:1884-1889`) |
| `rejectedmodels` retention | `<= 10` dirs | `export_model_for_selfplay.sh` / gatekeeper move rejects here; nothing prunes them |
| stale `shuffleddata/*.tmp` | removed on startup | `shuffle.sh:105` renames only on success; `cleanup_old_dirs.py:19,24` skips `.tmp` |
| protected set (never pruned, always logged) | frozen baseline (first dir in `models/`), latest accepted net, `checkpoint.ckpt` + `checkpoint_prev0.ckpt`, everything under `evidence/` | node `bootstrap_accepted_model` owns the baseline |
| shuffleddata retention | newest 3 older than 2 h | `python/selfplay/cleanup_old_dirs.py:13,19,24` (upstream default, unchanged) |
| short-term checkpoints | `4` | `python/train.py:578` (`checkpoint.ckpt` + `checkpoint_prev{0,1,2}.ckpt`) |
| `maxRowsPerTrainFile` | `10000` | `selfplay1_maxsize9.cfg:19`; first file short via `firstFileRandMinProp = 0.15` (`:20`) |
| bytes/row uncompressed at `pos_len 9` | `2145` **[HYPOTHESIS]** | `cpp/dataio/trainingwrite.cpp:292-299`: 242+76+328+320+282+405+492; 19x19 constants `5503`/`2172` cross-checked at `python/shuffle.py:39-40` |
| on-disk compression fraction | `0.12` | `python/shuffle.py:45` (`COMPRESSED_FRACTION_LARGE_FILE`) |
| bytes on disk per row | `~257` | 2145 x 0.12 |
| rows per game (planning) | `~22` **[HYPOTHESIS]** | `0.25*80 + 0.02*80` from `cheapSearchProb = 0.75` (`selfplay1_maxsize9.cfg:60`), `sidePositionProb = 0.020` (`:58`), and `a07_moves_per_game_80` |
| bytes/game on disk (planning) | `~5.7 KB` | 22 x 2145 x 0.12; `derivation.md` §4 |
| baseline `du -sb` (2026-09-03) | `7556587851` B (~7.56 GB) at the mission root | measured; almost all venv + build, before any loop data |
| group scratch usage | `37.71 TB / 40.00 TB (94 %)` | `python3 /apps/helpers/quotas.py`, 2026-09-03T22:01 |

Projected footprint at the pilot scale (500 games/cycle, `SHUFFLE_KEEPROWS = 300000`): ~2.9 MB of `tdata` per cycle plus ~77 MB of `shuffleddata` per cycle with 3 retained — the shuffle scratch, not the self-play data, dominates early. All of it is conditional on the two `[HYPOTHESIS]` rows above until `measure_stage_throughput` re-measures bytes/row on real 9x9 `tdata`.

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| Group scratch fills (94 % already) | `No space left on device` mid-cycle, in any group member's job | `scratch_cap.sh` before every cycle; `quotas.py` recorded on every cycle row; escalate above 95 % |
| Guard scoped to `BASEDIR` only | `du` reads a few GB while the root is near the cap because venv + build are excluded | the closing check greps the wrapper for the exact byte constants and the mission-root path |
| Cap written in decimal GB | `2.0e11` instead of `214748364800`; the guard is 7 % looser than stated | integers only, both constants grep-asserted |
| Unbounded `longterm_checkpoints` | `du` on `train/<name>/longterm_checkpoints` grows every 12 h forever | `prune_retention.py` caps at 6 and logs what it removed |
| Orphan `shuffleddata/*.tmp` | dirs the cleanup never removes (`cleanup_old_dirs.py:19,24`) | startup sweep in the wrapper; the cap script reports the largest 10 subdirs so orphans stay visible |
| `scripts/dated/<ts>` per restart | one archive per resubmit, each with a `katago` binary | counted by the cap script; pruned to the newest few |
| Pruning deletes a protected artifact | the frozen baseline or the latest accepted net disappears from `models/` | the protected set is computed first, printed, and excluded by path before any `rmtree` |
| Deleting `tdata` still inside the shuffle window | training window silently shrinks; `shuffle.py` reports fewer rows than expected | never prune `selfplay/*/tdata` while a `shuffleddata` dir referencing it is retained |
| `du -sb` slow on Weka | the cap check itself costs minutes | once per cycle, not per stage |

## 12. Current State

- `[SOLID]` Baseline measured: `du -sb /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` = `7556587851` B; `quotas.py` reports `/scratch/ssci-anima/ 37.71 TB / 40.00 TB (94 %)` and `/home/ssci-haiyangw/ 3.37 GB / 100.00 GB`. The mission root is far under both caps, so the closing check's `du` conjunct passes today.
- `[SOLID]` Per-row byte table read from `cpp/dataio/trainingwrite.cpp:292-299` and cross-checked against `python/shuffle.py:39-40`; footprint-growth inventory read from the loop scripts (`audit_loop_scripts_configs.md` §F). `cleanup_old_dirs.py` keeps the newest 3 dirs older than 2 h and never touches `.tmp` (`python/selfplay/cleanup_old_dirs.py:13,19,24`).
- `[PRELIMINARY]` The two thresholds (200 GiB / 180 GiB) and the retention bounds (6 / 10) are mission design decisions, not measurements; nothing enforces them yet because `codes/loop/loop.sbatch` does not exist.
- `[OPEN]` `o04_scratch_budget` — closes when (a) `quotas.py` output is stored under `evidence/data_budget/`, (b) `loop.sbatch` calls the guard before each cycle and refuses at `>= 193273528320` B, (c) `prune_retention.py` enforces `longterm_checkpoints <= 6`, `rejectedmodels <= 10` and the `.tmp` sweep with a logged protected set, (d) the per-cycle `du -sb` / `df -B1` / quota triple appears in the wrapper log.
- `[OPEN]` `codes/eval/scratch_cap.sh`, `codes/eval/prune_retention.py` and `codes/eval/rows_per_game.py` are not written yet (`codes/` = `env` only).
- `[HYPOTHESIS]` `2145` B/row and `~22` rows/game are arithmetic over code constants times `a07_moves_per_game_80`. They are planning inputs here; the calibration on real 9x9 `tdata` belongs to `measure_stage_throughput` after 100k rows, and this node must not claim it.
- `[SOLID]` `transformer_trunk_b5c48h3tfr` is superseded and is not a live node; the model choice does not affect the row size, which depends only on `dataBoardLen` (`trainingwrite.cpp:288-299`). Nothing in this task is blocked by the model switch.

## 13. Forbidden Actions

- Never edit `ref-code/lightvector-KataGo/`.
- Never raise the 200 GiB cap without re-reading `quotas.py` and recording the group figure in the same row — the group, not this mission, owns the 40 TB.
- Never scope the guard to `BASEDIR`: the cap is on the mission root, venv and build included.
- Never write either threshold in decimal GB or as a float; the two integers are `214748364800` and `193273528320`.
- Never point the mission root at `/tmp` (node-local; invisible afterwards) or at `/home` (100 GB quota).
- Never treat the cap check as advisory: the wrapper must exit non-zero above the soft cap.
- Never prune without printing the protected set first, and never delete `selfplay/*/tdata` while a retained shuffle window still references those rows.
- Never claim a measured bytes/row here — that admission belongs to `measure_stage_throughput`.
- Never exceed 24 CPUs / 1 GPU for the accounting job, and never run more than 2 parallel `du -sb` on scratch from a login node (5 GB / 14-core cgroup, `docs/cluster-manual.md` §2).

## 14. Promise Tag

- **Promise format:** `<promise>data_budget DU_MISSION_ROOT WITHIN <=214748364800 AND GUARD_GREPS ==3</promise>`
- **Required in commit body:** verbatim `scratch_cap.sh` output (the `du -sb` / `df -B1` / quota triple), the three grep hits from `loop.sbatch`, the `prune_retention.py` dry-run listing with its protected set, evidence path under `evidence/data_budget/`, claim `c11`, evidence type `empirical_measurement`.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions:
- Per-substage commit: Phase 1 (guard + constants) and Phase 2 (retention) commit separately; Phase 1's row is `empirical`, the planning constants stay `approximate`.
- Joint progress file: `progress/paper_1902.10565/data_budget/progress.md`.
- Loop notes: `results/ktg/paper_1902.10565/loop_note/note_session_{id}_loop_{n}.md` before compaction.
- State-note sync: every `du -sb` and `quotas.py` reading goes into `${RESEARCH_STATE}`; a group figure above 95 % is escalated immediately.

## 16. Termination Checklist

- [ ] Verification command ran and output is pasted.
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] Metrics are within the thresholds in §2.
- [ ] Reduction-to-baseline test passed when relevant (NA).
- [ ] No `[BLOCKING]`, `[OPEN]`, or `[UNCHECKED]` markers remain for this checked claim — the `[HYPOTHESIS]` planning constants stay open by design and belong to `measure_stage_throughput`.
- [ ] No silent scope expansion: guard + retention only; the wrapper file itself is `loop_resume_under_walltime`'s.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
