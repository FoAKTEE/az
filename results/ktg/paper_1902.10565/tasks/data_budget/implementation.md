# Implementation — `data_budget`

## 0. Header

**Task ID:** `data_budget`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::data_budget`
**Language:** bash (`du`, `df`, quota) + Python (retention pruning)
**Method class:** simulation / empirical measurement (thresholds set from code constants, enforced by the loop wrapper)

## 1. Claim

> The whole mission root `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` — venv, build and loop data together — stays under a hard cap of 500 GiB (`536870912000` B, human decision 2026-09-03 in `mission.json` `decisions[]`); a cycle that declares the bytes it will write is refused when `du -sb` plus that projection would cross the cap, and is refused independently when group scratch free space falls below 1 TiB (`1099511627776` B); retention is bounded with a logged protected set. All of it is enforced by an executable guard the loop wrapper calls, not by convention (claim `c11_scratch_budget`; obligation `o04_scratch_budget`).

## 2. Success Criterion

- **Needed evidence type:** `empirical_measurement` (a live `du -sb` plus the executed exit-code contract)
- **Done when:** the guard exists, refuses on every threshold branch, and the mission root is under the hard cap.
- **Verification command:**
  `bash results/ktg/paper_1902.10565/codes/data_budget/tests/run_guard_tests.sh >/dev/null && bash results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet >/dev/null && grep -q 'KTG_SCRATCH_HARD_BYTES=536870912000' results/ktg/paper_1902.10565/codes/data_budget/budget.env && grep -q 'KTG_GROUP_FREE_FAIL_BYTES=1099511627776' results/ktg/paper_1902.10565/codes/data_budget/budget.env && grep -q 'du -sb' results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh && grep -q 'quotas.py' results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh && python3 results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train >/dev/null && test $(du -sb /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train | cut -f1) -le 536870912000`
- **Measured tolerance / metric:** the exit-code contract is `11/11` cases matched; both grep conjuncts hit (count `>= 1` each); `du -sb` on the mission root `<= 536870912000` B. Exact byte integers, no tolerance band — a guard written in decimal GB or scoped to `BASEDIR` instead of the mission root fails the greps. The guard reads its constants from a FILE (`budget.env`, or `$KTG_BUDGET_ENV`), never from loose environment variables, so a stray `KTG_SCRATCH_HARD_BYTES` in a job script cannot loosen it (contract case C).
- **Open obligations before start:** `o04_scratch_budget`. The wrapper file itself is authored by `loop_resume_under_walltime`; this node owns the thresholds, the guard, the retention policy and the closing measurement.
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
- Never let the guard be advisory — the loop wrapper calls it *before* each cycle and aborts the cycle on any non-zero exit.
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
results/ktg/paper_1902.10565/codes/data_budget/
├── budget.env             # node data_budget - the byte constants, single source of truth, read as a FILE not as env vars
├── scratch_guard.sh       # node data_budget - du -sb / df -B1 / quotas.py triple; exit 1 over the projected cap, 2 under the group floor, 3 when it cannot measure
├── prune_retention.py     # node data_budget - bounded rolling retention with a logged protected set; dry-run unless --apply
└── tests/
    ├── fixture_tinycap.env    # forces the over-cap branch
    ├── fixture_failfloor.env  # forces the group free-space branch
    ├── fixture_warnfloor.env  # forces the warn-only branch
    └── run_guard_tests.sh     # the 11-case exit-code contract
```

`codes/loop/loop.sbatch` (authored by `loop_resume_under_walltime`) calls `scratch_guard.sh` at the top of each cycle and logs its triple once per cycle; the call contract, including what to do on each exit code, is written out in the header of `scratch_guard.sh`. This node owns the byte constants, which live only in `budget.env`.

## 8. Phase Plan

### Phase 1 - `guard`
- **Nodes:** `data_budget`
- **Files:** `budget.env`, `scratch_guard.sh`, `tests/run_guard_tests.sh` + the three fixtures
- **Test:** the §2 verification command; the guard exits 0 today and exits 1 / 2 / 3 on every refusal branch under a committed constants fixture.
- **Estimate:** `0.5` h

### Phase 2 - `retention`
- **Nodes:** `data_budget`
- **Files:** `prune_retention.py`
- **Test:** on a synthetic tree, `longterm_checkpoints` is left with `<= 6` files, `rejectedmodels` with `<= 10` dirs, zero stale `shuffleddata/*.tmp`, and every path in the protected set survives and is printed; a second `--apply` removes nothing.
- **Estimate:** `0.5` h

## 9. Quick-Win Path

1. `Phase 1` — run `scratch_guard.sh` now; record `du -sb`, `df -B1` and `quotas.py` as the baseline row.
2. `Phase 2` — exercise `prune_retention.py` on a synthetic tree; no loop data is needed.
3. **Smoke check:** the §2 command exits 0 from the repo root on a login node.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| hard cap (mission root) | `536870912000` B = 500 GiB | `c11_scratch_budget`; human decision 2026-09-03 (`mission.json` `decisions[]`), binary GiB |
| default per-cycle projection | `21474836480` B = 20 GiB | the bytes a cycle is assumed to write when the caller passes no `--projected-bytes`; gives an effective soft cap of `515396075520` B = 480 GiB |
| group free-space FAIL floor | `1099511627776` B = 1 TiB | 2x the mission's entire budget: spending the whole budget can never be what fills the shared 40 TB pool, and an equal share stays free for the rest of the group |
| group free-space WARN floor | `1649267441664` B = 1.5 TiB | FAIL floor + one whole mission budget, so the warning arrives a full budget of headroom early |
| group free-space source | `min(quotas.py, df -B1)` | `quotas.py` is the mission's named authority but is rounded to 0.01 TB and refreshed hourly; `df -B1` on the same pool is exact and live. Taking the smaller means neither staleness nor rounding can hide a shortage |
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
| baseline `du -sb` (2026-09-03T23:50) | `7558580421` B (~7.04 GiB) at the mission root | measured; almost all venv + build, before any loop data |
| group scratch usage | `37.61 TB / 40.00 TB (94 %)`; `df` free `2373954203648` B | `python3 /apps/helpers/quotas.py` and `df -B1`, 2026-09-03T23:50 |

Projected footprint at the pilot scale (500 games/cycle, `SHUFFLE_KEEPROWS = 300000`): ~2.9 MB of `tdata` per cycle plus ~77 MB of `shuffleddata` per cycle with 3 retained — the shuffle scratch, not the self-play data, dominates early. All of it is conditional on the two `[HYPOTHESIS]` rows above until `measure_stage_throughput` re-measures bytes/row on real 9x9 `tdata`.

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| Group scratch fills (94 % already) | `No space left on device` mid-cycle, in any group member's job | `scratch_guard.sh` before every cycle refuses at exit 2 below the 1 TiB floor; `quotas.py` recorded on every cycle row; escalate at the 1.5 TiB warn |
| Guard scoped to `BASEDIR` only | `du` reads a few GB while the root is near the cap because venv + build are excluded | the closing check greps the wrapper for the exact byte constants and the mission-root path |
| Cap written in decimal GB | `5.0e11` instead of `536870912000`; the guard is 7 % looser than stated | integers only, the constants grep-asserted in §2 |
| Unbounded `longterm_checkpoints` | `du` on `train/<name>/longterm_checkpoints` grows every 12 h forever | `prune_retention.py` caps at 6 and logs what it removed |
| Orphan `shuffleddata/*.tmp` | an orphan competes for one of the three retained slots and evicts a GOOD shuffle dir: `cleanup_old_dirs.py:15-20` applies NO name filter, it tests only `is_dir` and `st_mtime` | explicit `.tmp` sweep in `prune_retention.py`, once the orphan is older than the age threshold |
| `scripts/dated/<ts>` per restart | one archive per resubmit, each with a `katago` binary | counted by the cap script; pruned to the newest few |
| Pruning deletes a protected artifact | the frozen baseline or the latest accepted net disappears from `models/` | the protected set is computed first, printed, and excluded by path before any `rmtree` |
| Deleting `tdata` still inside the shuffle window | training window silently shrinks; `shuffle.py` reports fewer rows than expected | a selfplay generation is deletable only when it is older than the OLDEST retained `shuffleddata` dir, recomputed after every planned window deletion; rolling mode additionally never drops below one window plus one generation |
| `du -sb` slow on Weka | the cap check itself costs minutes | once per cycle, not per stage; measured 3 s on the 7 GiB mission root from the login node |

## 12. Current State

- `[SOLID]` Closing measurement 2026-09-03T23:50 on `login03`: `du -sb /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` = `7558580421` B; `df -B1` free `2373954203648` B; `quotas.py` reports `/scratch/ssci-anima/ 37.61 TB / 40.00 TB (94 %)` and `/home/ssci-haiyangw/ 3.39 GB / 100.00 GB`. The mission root is far under the 500 GiB cap and group free space is far above the 1 TiB floor, so the guard exits 0 today. Evidence `results/ktg/paper_1902.10565/evidence/data_budget/closing_measurement.txt`.
- `[SOLID]` Per-row byte table read from `cpp/dataio/trainingwrite.cpp:292-299` and cross-checked against `python/shuffle.py:39-40`; footprint-growth inventory read from the loop scripts (`audit_loop_scripts_configs.md` §F). `cleanup_old_dirs.py` keeps the newest 3 dirs older than 2 h and never touches `.tmp` (`python/selfplay/cleanup_old_dirs.py:13,19,24`).
- `[SOLID]` The guard exists and refuses on every branch: `codes/data_budget/tests/run_guard_tests.sh` matched all `11` expected exit codes (0 in budget, 1 over the projected cap, 1 when a stray `KTG_SCRATCH_HARD_BYTES` tries to loosen it, 1 already over a lowered cap, 2 under the group free-space floor, 0-with-warning under the warn floor, 3 on a missing root / malformed projection / unknown flag / missing constants file, 0-with-warning on the `quotas.py` fallback to `df`). Evidence `evidence/data_budget/guard_exit_contract.txt`.
- `[SOLID]` Retention verified on a synthetic tree: `longterm_checkpoints` 9 -> 6, `rejectedmodels` 14 -> 10, `selfplay` 5 -> 3 generations, `scripts/dated` 6 -> 3, the stale `.tmp` removed and the young `.tmp` kept, all 8 protected paths printed and surviving, and a second `--apply` removing nothing. Evidence `evidence/data_budget/retention_synthetic_test.txt`.
- `[PRELIMINARY]` The 500 GiB cap is a human decision (`mission.json` `decisions[]` 2026-09-03), and the 20 GiB default projection, the 1 TiB / 1.5 TiB group floors and the retention bounds (6 / 10 / 3 / 3) are design choices justified in `budget.env`, not measurements. Each is re-openable once `measure_stage_throughput` reports real bytes/row.
- `[SOLID]` Divergence found while writing the retention policy, and it corrects an earlier reading in this file: upstream `python/selfplay/cleanup_old_dirs.py:15-20` applies **no name filter** — it tests only `is_dir(follow_symlinks=False)` and `st_mtime`. An orphan `shuffleddata/<ts>.tmp` (left when `shuffle.sh:105` never reached its rename) is therefore not skipped: it competes for one of the three retained slots and can evict a good shuffle window. `prune_retention.py` sweeps `.tmp` explicitly for this reason.
- `[OPEN]` `o04_scratch_budget` — (a) `quotas.py` output is stored under `evidence/data_budget/` DONE, (c) `prune_retention.py` enforces `longterm_checkpoints <= 6`, `rejectedmodels <= 10` and the `.tmp` sweep with a logged protected set DONE, (d) the guard prints the per-cycle `du -sb` / `df -B1` / quota triple DONE. Remaining: (b) `loop.sbatch` must actually call `scratch_guard.sh`.
- `[BLOCKING]` `codes/loop/loop.sbatch` (owned by node `loop_resume_under_walltime`, in flight in the same wave) still carries its own inline guard with the superseded literals `KTG_SCRATCH_CAP_BYTES=214748364800` / `KTG_SCRATCH_SOFT_BYTES=193273528320` (`loop.sbatch:74-75`) and its own `du`/`quotas.py` block (`:192-197`). Owner: the `loop_resume_under_walltime` worker. Unblocked by replacing that block with the call contract in the header of `scratch_guard.sh`; what would close it is a `loop.sbatch` whose only storage literals come from `codes/data_budget/budget.env`. This file did not edit `loop.sbatch` because another worker holds it in the same wave.
- `[FUTURE]` `rows_per_game.py` (planning-only rows/game + bytes/game reporter) is not written: it reports the `[HYPOTHESIS]` arithmetic below, and the number that matters is the measured one, which belongs to `measure_stage_throughput`. Dropped from this node's scope rather than shipped as a restatement of constants already tabulated in §10.
- `[HYPOTHESIS]` `2145` B/row and `~22` rows/game are arithmetic over code constants times `a07_moves_per_game_80`. They are planning inputs here; the calibration on real 9x9 `tdata` belongs to `measure_stage_throughput` after 100k rows, and this node must not claim it.
- `[SOLID]` `transformer_trunk_b5c48h3tfr` is superseded and is not a live node; the model choice does not affect the row size, which depends only on `dataBoardLen` (`trainingwrite.cpp:288-299`). Nothing in this task is blocked by the model switch.

## 13. Forbidden Actions

- Never edit `ref-code/lightvector-KataGo/`.
- Never raise the 500 GiB cap without re-reading `quotas.py` and recording the group figure in the same row — the group, not this mission, owns the 40 TB. The cap is a human decision; changing it needs a new one.
- Never scope the guard to `BASEDIR`: the cap is on the mission root, venv and build included.
- Never write any threshold in decimal GB or as a float; the integers are `536870912000` (cap), `21474836480` (default projection), `1099511627776` and `1649267441664` (group floors).
- Never point the mission root at `/tmp` (node-local; invisible afterwards) or at `/home` (100 GB quota).
- Never treat the cap check as advisory: the wrapper must abort the cycle on any non-zero guard exit. Never let the constants come from a loose environment variable — only from `budget.env` or an explicit `$KTG_BUDGET_ENV` file.
- Never prune without printing the protected set first, and never delete `selfplay/*/tdata` while a retained shuffle window still references those rows.
- Never claim a measured bytes/row here — that admission belongs to `measure_stage_throughput`.
- Never exceed 24 CPUs / 1 GPU for the accounting job, and never run more than 2 parallel `du -sb` on scratch from a login node (5 GB / 14-core cgroup, `docs/cluster-manual.md` §2).

## 14. Promise Tag

- **Promise format:** `<promise>data_budget DU_MISSION_ROOT WITHIN <=536870912000 AND GUARD_EXIT_CONTRACT ==11/11</promise>`
- **Required in commit body:** verbatim `scratch_guard.sh` output (the `du -sb` / `df -B1` / quota triple), the exit-code contract summary, the `prune_retention.py` dry-run listing with its protected set, evidence path under `evidence/data_budget/`, claim `c11`, evidence type `empirical_measurement`.

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
