# Implementation — `derive_cycle_knobs_9x9`

## 0. Header

**Task ID:** `derive_cycle_knobs_9x9`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::derive_cycle_knobs_9x9`
**Language:** Python (CPU only; no job, no GPU)
**Method class:** symbolic (closed-form derivation over the measured rows/game, checked by an executable script)
**Scheduling policy (wave 2):** `preliminary` predecessors (`train_resume_semantics`, `data_format_pos_len`, `training_window_shuffle`) are usable for an `empirical`/`conditional` admission at `preliminary`; the fourth predecessor `synchronous_loop_smoke` supplies the measurement and must have landed (its `evidence/smoke/rows_per_game.txt` exists and is admitted) before this node runs. `solid` still needs `solid` predecessors.

## 1. Claim

> Given the measured real-net rows/game `r` from the smoke, the production knob set `(NUM_GAMES_PER_CYCLE, MAX_TRAIN_PER_DATA, NUM_TRAIN_SAMPLES_PER_EPOCH, EPOCHS_PER_EXPORT, SHUFFLE_MINROWS, SHUFFLE_KEEPROWS, MAX_TRAIN_SAMPLES_PER_CYCLE, TAPER_WINDOW_SCALE)` satisfies every constraint `train.py` and `shuffle.py` impose — one epoch per cycle from cycle 2 on, exactly one exported candidate per cycle, a shuffle window that always holds the epoch, and a random bootstrap that reaches `min_rows` in cycle 1 — and is written into the `${VAR:-default}` block of `codes/loop/synchronous_loop_9x9.sh` (obligations `o24_cycle_knobs_derived`, `o13_loop_config_paths` knob conjunct).

## 2. Success Criterion

- **Needed evidence type:** `symbolic derivation` with an executed check (`numerical_simulation` of the arithmetic, no engine run)
- **Done when:** `derive_knobs.py` exits 0 on the measured `r` and the loop copy's defaults equal its output.
- **Verification command (the ledger row's `closing_check`, kept verbatim):**
  `python3 results/ktg/paper_1902.10565/codes/eval/derive_knobs.py --rows-per-game $(cat results/ktg/paper_1902.10565/evidence/smoke/rows_per_game.txt) --reuse 8 --samples-per-epoch 20000 --games 500 --keep 300000 --cap 200000`
  followed by the wiring check
  `python3 results/ktg/paper_1902.10565/codes/eval/derive_knobs.py --rows-per-game $(cat results/ktg/paper_1902.10565/evidence/smoke/rows_per_game.txt) --reuse 8 --samples-per-epoch 20000 --games 500 --keep 300000 --cap 200000 --assert-loop-defaults results/ktg/paper_1902.10565/codes/loop/synchronous_loop_9x9.sh`
- **Measured tolerance / metric:** the script asserts, printing every intermediate number:
  (K1) `gain = games × r × reuse ≥ 0.99 × samples_per_epoch` (`train.py:1256,1434`), reported as the ratio `gain / samples_per_epoch` `≥ 1.0` (0.99 is the code's own margin);
  (K2) `epochs_per_export = max_epochs_this_instance = floor(min(gain, cap_eff) / samples_per_epoch)` with `cap_eff = max(cap, samples_per_epoch)` (`train.py:1257-1259`), `≥ 1` — exactly one export per cycle (`train.py:1831`);
  (K3) `keep > cap` (`synchronous_loop.sh:66` rule) and `keep ≥ epochs_per_export × samples_per_epoch`;
  (K4) window feasibility: the shuffled files must hold `≥ round(samples_per_epoch / batch)` batches (`train.py:1303-1346`, the defect the smoke exposed), i.e. `min(desired_window_rows, keep) ≥ samples_per_epoch`, where `desired_window_rows` is `shuffle.py:414-435` evaluated at `num_usable_rows = min_rows + games × r` with `-expand-window-per-row 0.4 -taper-window-exponent 0.65` (`shuffle.sh:44-45`);
  (K5) bootstrap: `games × r_random ≥ min_rows` in cycle 1 (random rows count toward `range[1]` in full, `shuffle.py:1331`; toward the window only up to `min_rows`, `:1077`), and cycle 2's `gain` uses `r` (real net) — both rows/game values come from the smoke's `audit.json`;
  (K6) `SWA period = samples_per_epoch / 2` (`train.py:441` default made explicit);
  (K7) cycle wall projection `≤ 60 h` from the smoke's `throughput_smoke.json` (games/h real net, train samples/s): `games / games_per_h + epochs × samples_per_epoch / samples_per_s + gate_h` — `[PRELIMINARY]`, tiny-count inputs; the bound is `measure_stage_throughput`'s, only echoed here.
  With `--assert-loop-defaults`, every derived value must equal the corresponding `${VAR:-default}` in the loop copy (exit 1 otherwise).
- **Open obligations before start:** `o24` (this node), `o13` knob conjunct (this node), smoke admitted (`rows_per_game.txt` content-hashed on the smoke's result row).
- **Reduction-to-baseline test:** NA

## 3. Motivation

DESIGN.md §2 records that pass 2's knob set starves training from cycle 2 (gain 44 k < 49.5 k) and pass 1's exported up to four gated candidates per cycle; the smoke exposed a third failure mode — an epoch larger than the shuffled window exports nothing at all (`train.py:1303-1346`). All three are arithmetic over one measured number, so the knobs are derived by a script that is re-run whenever `r` is re-measured (`measure_stage_throughput`, `scale_data_window`), never hand-picked (DESIGN §8 R14).

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §4 trainer flags, §5 shuffler flags |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §4 rows/game arithmetic (`(1-0.75)×80 + 0.02×80 ≈ 22`) |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | predecessors `train_resume_semantics`, `data_format_pos_len`, `training_window_shuffle`, `synchronous_loop_smoke`; successors `selfplay_stage`, `train_stage`, `scale_data_window` |
| DESIGN | `results/ktg/paper_1902.10565/decomposition/DESIGN.md` | §2 bucket arithmetic and the pilot hypothesis (500 games, reuse 8, 20 k/epoch, MINROWS 10 k, KEEPROWS 300 k, cap 200 k, taper 50 k, 4 epochs/export) |
| claims / obligations | `decomposition/claims.md`, `obligations.md` | `c09`, `c10`; `o13`, `o24` |

**Upstream task outputs:** `tasks/synchronous_loop_smoke` → `evidence/smoke/{rows_per_game.txt,audit.json,throughput_smoke.json}`; `tasks/loop_resume_under_walltime` → the knob block `codes/loop/synchronous_loop_9x9.sh:107-121`.

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- CPU only, login node; no `sbatch`, no `srun`.
- Edit only the `${VAR:-default}` block of `codes/loop/synchronous_loop_9x9.sh` (CHANGE 9) — and only after the o26/o31 wrapper repair under `codes/loop/` has landed (check `git log -1 -- results/ktg/paper_1902.10565/codes/loop/` and `obligations.md`), to avoid a concurrent edit.
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference code | `ref-code/lightvector-KataGo/` (`python/train.py`, `python/shuffle.py`, `python/selfplay/{shuffle.sh,synchronous_loop.sh}`) |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/eval/derive_knobs.py`, edit of `codes/loop/synchronous_loop_9x9.sh:107-121` |
| Evidence | `results/ktg/paper_1902.10565/evidence/knobs/derivation.txt` (verbatim script output) |
| Progress dir | `progress/paper_1902.10565/derive_cycle_knobs_9x9/` |
| Git branch | `main` (az) |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/
├── eval/derive_knobs.py            # node derive_cycle_knobs_9x9 - K1-K7; --assert-loop-defaults compares against the loop copy
└── loop/synchronous_loop_9x9.sh    # (owned by loop_resume_under_walltime) knob block :107-121 rewritten to the derived values
```

`derive_knobs.py` CLI: `--rows-per-game R [--rows-per-game-random R0] --reuse M --samples-per-epoch E --games G --keep K --cap C [--min-rows m] [--taper t] [--batch 128] [--throughput evidence/smoke/throughput_smoke.json] [--assert-loop-defaults FILE] [--emit-env]`. `--emit-env` prints the ten `VAR=value` lines for the loop block; `--assert-loop-defaults` parses `${VAR:-default}` with a regex and compares.

## 8. Phase Plan

### Phase 1 - `derivation`
- **Nodes:** `derive_cycle_knobs_9x9`
- **Files:** `codes/eval/derive_knobs.py`, `evidence/knobs/derivation.txt`
- **Test:** the § 2 command exits 0 on the measured `r`; K1-K6 printed; unit self-test `derive_knobs.py --self-test` reproduces DESIGN §2's two negative cases (pass 2: gain 44 000 < 49 500 → exit 1; pass 1 keep 300 k / cap 500 k → exit 1) and the smoke's positive case (40 games, 256/epoch, reuse 8 → 1 epoch).
- **Estimate:** `1.0` h

### Phase 2 - `wiring`
- **Nodes:** `derive_cycle_knobs_9x9`
- **Files:** `codes/loop/synchronous_loop_9x9.sh:107-121`
- **Test:** `--assert-loop-defaults` exits 0; `bash -n` clean; the loop_resume §2 check still exits 0.
- **Estimate:** `0.5` h

## 9. Quick-Win Path

1. `Phase 1` — implement K1-K4 first; run against `r = 22` (the derivation's expectation) to confirm the DESIGN pilot set passes (gain 88 000 ≥ 19 800; 4 epochs; 300 k > 200 k; window ≥ 20 000).
2. `Phase 1` — re-run on the measured `r`; if it fails, change `games` first (cheapest knob), never `reuse` above 8.
3. **Smoke check:** exit 0 with `epochs_per_export ≥ 1`.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| `r` (rows/game, real net) | `cat evidence/smoke/rows_per_game.txt` | measured by the smoke (S8); expected ~22 (`derivation.md` §4); c10 band `[12, 35]` |
| `r_random` | from `audit.json` | cycle-1 bootstrap check (K5) |
| `--games` | `500` | DESIGN §2 pilot; raise if K1 fails at the measured `r` |
| `--reuse` | `8` | `synchronous_loop.sh:60`; upstream default, never exceeded |
| `--samples-per-epoch` | `20000` | DESIGN §2 pilot (pass 2's 50 000 fails K1 at `r = 22`) |
| `--keep` / `--cap` | `300000` / `200000` | keep > cap (`synchronous_loop.sh:66`) |
| `--min-rows` / `--taper` | `10000` / `50000` | reachable by 500 random games at `r_random ≥ 20`; `taper_window_scale` default = `min_rows` (`shuffle.py:421`) |
| `--batch` | `128` | `synchronous_loop.sh:62`; K4 uses it |
| expected output at `r = 22` | `epochs_per_export = 4`, gain 88 000, ratio 4.4 | equals the DESIGN §2 pilot hypothesis, which this node either confirms or replaces |

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| `r` from 20-60 tiny-scale games is noisy | `derivation.txt` ratio within 10 % of 1.0 | K1 uses the lower 90 % bound of `r` (binomial-free: `r × (1 - 1/sqrt(games_measured))`) and prints both; re-derive after `measure_stage_throughput` |
| random-net `r_random` differs strongly from `r` | K5 fails though K1 passes | cycle 1 uses `r_random`; raise `games` for cycle 1 only via `NUM_GAMES_PER_CYCLE` override in the first link, recorded |
| loop file edited concurrently (o26/o31 repair) | merge conflict on `synchronous_loop_9x9.sh` | Phase 2 waits for that validation's commit; the script's `--emit-env` output is the deliverable meanwhile |
| projected cycle > 60 h (K7) | `throughput_smoke.json` games/h too low | report, do not tune here — `scale_search_budget` / `measure_stage_throughput` own it |

## 12. Current State

- `[SOLID]` The constraints are read at `path:line`: `train.py:971-972,1256-1259,1303-1346,1434,1831`, `shuffle.py:414-435,1077,1331`, `shuffle.sh:44-45`, `synchronous_loop.sh:57-66`.
- `[SOLID]` Negative cases exist: pass 2 (44 000 < 49 500), pass 1 (keep 300 k / cap 500 k), and DESIGN S2 (2000-sample epoch on ~440 rows → no export).
- `[OPEN]` `r` not yet measured — waits for `synchronous_loop_smoke`. Until then the DESIGN §2 pilot set stays `[HYPOTHESIS]` in the loop copy.
- `[OPEN]` `o13` knob conjunct and `o24` close together when Phase 2 lands and the § 2 command exits 0.

## 13. Forbidden Actions

- Never hand-pick a knob: every value in the loop block must be the script's output (DESIGN §8 R14).
- Never set `keep ≤ cap`, never raise `reuse` above 8, never set `epochs_per_export ≠ max_epochs_this_instance`.
- Never submit a job here; never touch anything in `synchronous_loop_9x9.sh` outside the knob block.
- Never use the random-net rows/game for K1 (production cycles play real nets).

## 14. Promise Tag

- **Promise format:** `<promise>derive_cycle_knobs_9x9 GAIN_RATIO >=1.0 AND EPOCHS_PER_EXPORT >=1 AND KEEP >CAP AND WINDOW >=SAMPLES_PER_EPOCH AND LOOP_DEFAULTS ==DERIVED</promise>`
- **Required in commit body:** verbatim `derive_knobs.py` output (both invocations), the measured `r`, the derived ten values, evidence path `evidence/knobs/derivation.txt`, obligations `o24`/`o13`, evidence type.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions: one commit per phase; joint progress file `progress/paper_1902.10565/derive_cycle_knobs_9x9/progress.md`; `${RESEARCH_STATE}` "knobs" row moves from `[PRELIMINARY]` to the derived set.

## 16. Termination Checklist

- [ ] Verification command ran and output is pasted.
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] K1-K6 within tolerance; K7 recorded.
- [ ] No silent scope expansion: only the knob block changed.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
