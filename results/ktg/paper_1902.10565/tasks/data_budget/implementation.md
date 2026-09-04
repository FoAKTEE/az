# Implementation — `data_budget`

## 0. Header

**Task ID:** `data_budget`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::data_budget`
**Language:** Python (npz/SGF accounting) + bash (`du`)
**Method class:** simulation / empirical measurement (budget derived from code constants, then measured)

## 1. Claim

> At `dataBoardLen = 9` the loop writes 12-35 training rows and <= 10 KB on disk per self-play game, and the whole mission stays under a 200 GB scratch cap at `BASEDIR` (claims `c10_rows_per_game`, `c11_scratch_budget`).

## 2. Success Criterion

- **Needed evidence type:** `empirical_measurement` (bootstrapped from code constants, finalised after the first smoke)
- **Done when:** the row/byte accounting is inside tolerance on real `tdata` and the cap check passes.
- **Verification command:**
  `python /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/eval/rows_per_game.py <tdata dir> && bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/eval/scratch_cap.sh`
  - `rows_per_game.py` walks `<selfplay-model-dir>/tdata/*.npz` and the sibling `sgfs/*.sgfs`, printing `rows`, `games`, `rows_per_game`, `bytes_on_disk_per_game`, `bytes_uncompressed_per_row`; exits non-zero outside tolerance.
  - `scratch_cap.sh` runs `du -sb /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/loop` and exits non-zero at or above `2.0e11` bytes; it also prints `python3 /apps/helpers/quotas.py`.
- **Measured tolerance / metric:** `rows_per_game` in `[12, 35]`; `bytes_on_disk_per_game <= 10240`; `du -sb BASEDIR < 2.0e11`. Additionally `bytes_uncompressed_per_row == 2145` (exact, cross-check of `data_format_pos_len`).
- **Open obligations before start:** `o04_scratch_budget` (record `quotas.py`, set the cap in the loop wrapper, decide `tdata` retention). None blocking the *bootstrap* half — the code-constant budget can be written today.
- **Reduction-to-baseline test:** NA

`games` is defined as the `.sgfs` line count (one SGF per line, `cpp/program/selfplaymanager.cpp:377-378`); `rows` is the sum of `npz["binaryInputNCHWPacked"].shape[0]`.

## 3. Motivation

Group scratch was at **37.71 TB of 40.00 TB (94 %)** when this task was written (`python3 /apps/helpers/quotas.py`, 2026-09-03T22:01) — `docs/cluster-manual.md` §4 trap 1 warns that writes then start failing for the whole group, not just this mission. Nothing upstream prunes `selfplay/<model>/tdata|sgfs`, `models/`, `rejectedmodels/`, `longterm_checkpoints/` or `scripts/dated/` (`audit_loop_scripts_configs.md` §F "Footprint growth"), so the cap must be enforced by the mission's own wrapper.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §1 `dataBoardLen`, `maxRowsPerTrainFile`; §5 shuffler flags |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §4 rows/game and bytes/row arithmetic |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | `data_budget` predecessors `synchronous_loop_smoke`, `data_format_pos_len`; successor `scale_up` |
| implementation_plan | not produced at stage 1 | `[OPEN]` |
| ref | `results/ktg/paper_1902.10565/decomposition/ref.md` | v1.18.2 provenance |
| assumptions | `results/ktg/paper_1902.10565/decomposition/assumptions.md` | `a07_moves_per_game_80`, `a05_9x9_only` |
| claims | `results/ktg/paper_1902.10565/decomposition/claims.md` | `c10`, `c11` |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | `o04` |
| result_seed | not produced at stage 1 | `[OPEN]` |

**Upstream task outputs:** none required for the bootstrap; `tasks/cfg_9x9_override/implementation.md` and one selfplay run are required to finalise.
**Evidence pack:** `evidence/decomposition/audit_loop_scripts_configs.md` §F (per-row byte table, footprint growth), §A (loop cycle constants).

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- Two-stage discipline: the code-constant budget is admitted as `approximate`; only the measured version is admitted as `empirical`.
- Never let the cap script be advisory — the loop wrapper calls it *before* each cycle and refuses to start above the cap.
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference paper | `ref-paper/arxiv-1902.10565/` |
| Reference code | `ref-code/lightvector-KataGo/` |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/eval/` |
| Plot / figure output | `results/ktg/paper_1902.10565/plots/` |
| Loop notes | `results/ktg/paper_1902.10565/loop_note/` |
| Progress dir | `progress/paper_1902.10565/data_budget/` |
| Git branch | `ssci` |
| `BASEDIR` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/loop` |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/eval/
├── rows_per_game.py    # node data_budget - rows/game, bytes/game, bytes/row over a tdata+sgfs pair
└── scratch_cap.sh      # node data_budget - du -sb BASEDIR vs the 200 GB cap; prints quotas.py; exit 1 when over
```

## 8. Phase Plan

### Phase 1 - `bootstrap budget from code constants`
- **Nodes:** `data_budget`
- **Files:** `rows_per_game.py` (constants path), `scratch_cap.sh`
- **Test:** `scratch_cap.sh` exits 0 today; the projected footprint table below is written into the task's evidence file.
- **Estimate:** `0.5` h

### Phase 2 - `finalise on measured data`
- **Nodes:** `data_budget`
- **Files:** `rows_per_game.py` (measurement path)
- **Test:** `rows_per_game` in `[12, 35]` and `bytes_on_disk_per_game <= 10240` on the first real `tdata` dir.
- **Estimate:** `0.5` h

## 9. Quick-Win Path

1. `Phase 1` — run `scratch_cap.sh` now; record `du -sb` and `quotas.py` as the baseline row.
2. `Phase 2` — point `rows_per_game.py` at the `paper_code_map_search` probe's `$W/selfplay/*/tdata`.
3. **Smoke check:** `bytes_uncompressed_per_row == 2145` on the first real npz.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| bytes/row uncompressed at `pos_len 9` | `2145` | `cpp/dataio/trainingwrite.cpp:292-299`: 242+76+328+320+282+405+492; 19x19 value 7675 cross-checked at `python/shuffle.py:39-41` (5503 + 2172) |
| on-disk compression fraction | `0.12` | `python/shuffle.py:47` |
| bytes on disk per row | `~257` | 2145 x 0.12 |
| rows per turn | `floor(w) + Bernoulli(frac(w))` | `cpp/dataio/trainingwrite.cpp:1206-1251`; `w = 0` on cheap turns (`cpp/program/play.cpp:1143`) |
| cheap-search fraction | `0.75` | `selfplay1_maxsize9.cfg:60` -> ~25 % of turns write a row |
| side positions | `0.020` | `:58` (`play.cpp:2206`, `:974-982`) |
| moves per game (prior) | `~80` | `a07_moves_per_game_80` — **assumption, replaced by measurement** |
| expected rows/game | `~22` = `0.25*80 + 0.02*80` | `derivation.md` §4 |
| expected bytes/game on disk | `~5.7 KB` = 22 x 2145 x 0.12 | `derivation.md` §4; tolerance ceiling 10 KB |
| tolerance rows/game | `[12, 35]` | `c10_rows_per_game` |
| scratch cap | `2.0e11` B (200 GB) | `c11_scratch_budget`; design decision for this mission |
| `maxRowsPerTrainFile` | `10000` | `selfplay1_maxsize9.cfg:19`; first file short via `firstFileRandMinProp = 0.15` (`:20`, `trainingwrite.cpp:1039`) |
| `SHUFFLE_KEEPROWS` | `600000` | `python/selfplay/synchronous_loop.sh:66` -> shuffleddata dir ~ 600000 x 2145 x 0.12 = **~154 MB/cycle** at pos_len 9 |
| shuffleddata retention | newest 3 | `python/katago/utils/cleanup_old_dirs.py:12,18,22-24` (keeps newest 3 older than 2 h); orphan `.tmp` never cleaned |
| short-term checkpoints | `4` | `python/train.py:578` (`checkpoint.ckpt` + `checkpoint_prev{0,1,2}.ckpt`) |
| long-term checkpoints | every 12 h, **never pruned** | `train.py:1884-1889`; `o04` caps them at 6 |
| baseline `du -sb` (2026-09-03) | `7556587851` B (~7.56 GB) at `$KTG_ROOT` | measured; almost all of it is `venv` + `build`, before any `loop/` data |
| group scratch usage | `37.71 TB / 40.00 TB (94 %)` | `python3 /apps/helpers/quotas.py`, 2026-09-03T22:01 |

Projected footprint at the smoke scale (`NUM_GAMES_PER_CYCLE = 500`, `synchronous_loop.sh:57`): ~2.9 MB of `tdata` per cycle plus ~154 MB of `shuffleddata` per cycle with 3 retained, i.e. the shuffle scratch, not the self-play data, dominates early. At 1e6 games the `tdata` reaches ~5.7 GB, well inside `c11`'s "< 20 GB per 1e6 games".

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| Group scratch fills (94 % already) | `No space left on device` mid-cycle, in any group member's job | `scratch_cap.sh` before every cycle; `quotas.py` recorded on every run row |
| `rows_per_game` below 12 | random-net or resigned games far shorter than 80 moves | report `moves/game` too; if `moves/game << 80`, refute `a07_moves_per_game_80` explicitly instead of widening the band |
| `rows_per_game` above 35 | forks/side positions or `cheapSearchProb` misconfigured | cross-check `full_frac` from `paper_code_map_search`; a wrong `cheapSearchProb` shows up in both |
| bytes/game >> 10 KB | `dataBoardLen` still 19 -> 7675 B/row instead of 2145 | `bytes_uncompressed_per_row == 2145` is an exact assert, so this fails loudly |
| Unbounded `longterm_checkpoints` | `du` on `train/<name>/longterm_checkpoints` grows every 12 h forever | prune to <= 6 in the loop wrapper (`o04`) |
| Orphan `shuffleddata/*.tmp` | dirs the cleanup never removes (`cleanup_old_dirs.py` skips them; `train.py:1210` ignores them) | the cap script reports the largest 10 subdirs so orphans are visible |
| `scripts/dated/<ts>` per restart | one archive per loop restart (`synchronous_loop.sh:78-81`), many under a resubmit-driven design | count them in the cap script; prune all but the newest few |
| `du -sb` slow on Weka | the cap check itself costs minutes | run it once per cycle, not per stage |

## 12. Current State

- `[SOLID]` Baseline measured today: `du -sb /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` = `7556587851` B; `quotas.py` reports `/scratch/ssci-anima/ 37.71 TB / 40.00 TB (94 %)` and `/home/ssci-haiyangw/ 3.37 GB / 100.00 GB`. `BASEDIR` (`.../ktg-train/loop`) does not exist yet, so the cap check trivially passes at 0 B.
- `[SOLID]` Per-row byte table read from `cpp/dataio/trainingwrite.cpp:292-299` and cross-checked against `python/shuffle.py:39-41`; footprint-growth inventory read from the loop scripts (`audit_loop_scripts_configs.md` §F).
- `[PRELIMINARY]` `rows/game ~ 22` and `bytes/game ~ 5.7 KB` are derived from code constants times `a07_moves_per_game_80`; no self-play data exists at `dataBoardLen = 9`.
- `[OPEN]` `o04_scratch_budget` — closes when (a) `quotas.py` output is stored under `evidence/data_budget/`, (b) the loop wrapper calls `scratch_cap.sh` before each cycle and refuses above 2.0e11 B, (c) `longterm_checkpoints` pruning to <= 6 and `rejectedmodels` pruning are implemented, (d) a `tdata` retention policy is written down.
- `[OPEN]` `codes/eval/rows_per_game.py` and `codes/eval/scratch_cap.sh` are not written yet (`codes/` contains only `env/`).
- `[OPEN]` `a07_moves_per_game_80` is an unmeasured assumption; every derived number above is conditional on it until Phase 2 runs.
- `[BLOCKING]` inherited: the first real `tdata` at `dataBoardLen = 9` requires a self-play run, and production self-play requires a servable net — currently blocked by the SwiGLU refusal recorded in `tasks/tiny_model_export_smoke/implementation.md` §12. The random-net bootstrap (`cpp/dataio/loadmodel.cpp:77-80`) still produces usable `tdata` for Phase 2, so this blocks the *production* budget, not the measurement.

## 13. Forbidden Actions

- Never edit `ref-code/lightvector-KataGo/`.
- Never raise the 200 GB cap without re-reading `quotas.py` and recording the group figure in the same row — the group, not this mission, owns the 40 TB.
- Never point `BASEDIR` at `/tmp` (node-local; invisible afterwards) or at `/home` (100 GB quota).
- Never treat the cap check as advisory: the loop wrapper must exit non-zero above the cap.
- Never delete `selfplay/*/tdata` to make the cap pass while a shuffle window still references those rows.
- Never compute bytes/game from `ls -l` on `.npz` alone: the metric pairs `tdata` bytes with the sibling `sgfs` line count.
- Never exceed 24 CPUs / 1 GPU for the accounting job, and never run `du -sb` on scratch from the login node in parallel beyond 2 processes (5 GB / 14-core cgroup, `docs/cluster-manual.md` §2).

## 14. Promise Tag

- **Promise format:** `<promise>data_budget ROWS_PER_GAME WITHIN [12,35] AND BYTES_PER_GAME WITHIN <=10240 AND DU_BASEDIR WITHIN <2.0e11</promise>`
- **Required in commit body:** verbatim `rows_per_game.py` and `scratch_cap.sh` output, the `quotas.py` snapshot, evidence path under `evidence/data_budget/`, claims `c10`/`c11`, evidence type `empirical_measurement`.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions:
- Per-substage commit: Phase 1 (bootstrap + cap script) and Phase 2 (measured rows/game) commit separately; Phase 1's row is `approximate`, Phase 2's is `empirical`.
- Joint progress file: `progress/paper_1902.10565/data_budget/progress.md`.
- Loop notes: `results/ktg/paper_1902.10565/loop_note/note_session_{id}_loop_{n}.md` before compaction.
- State-note sync: every `du -sb` and `quotas.py` reading goes into `${RESEARCH_STATE}`; a group figure above 95 % is escalated immediately.

## 16. Termination Checklist

- [ ] Verification command ran and output is pasted.
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] Metrics are within the thresholds in §2.
- [ ] Reduction-to-baseline test passed when relevant (NA).
- [ ] No `[BLOCKING]`, `[OPEN]`, or `[UNCHECKED]` markers remain for this checked claim — `a07_moves_per_game_80` must be measured, not assumed, before `c10` is admitted as `empirical`.
- [ ] No silent scope expansion: accounting and the cap check only; pruning *implementation* lives in the loop wrapper task.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
