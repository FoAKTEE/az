# Implementation — converged_test_7x7

## 0. Header

**Task ID:** `converged_test_7x7`
**Paper:** `arxiv-1902.10565` — Wu, *Accelerating Self-Play Learning in Go* (background; `ref-code/lightvector-KataGo` @ v1.18.2 is the source of truth)
**Logic-graph nodes covered:** `arxiv-1902.10565::converged_test_7x7` (new; appended as `hypothesis`, predecessors `env_build`, `cfg_9x9_override`, `synchronous_loop_smoke` — a brain has not planned it, the human authorised it directly, mission.json `decisions[4]` 2026-09-04)
**Language:** bash + Python (KataGo C++ engine, PyTorch trainer)
**Method class:** simulation

## 1. Claim

> A self-play loop on a **7×7** board with `b7c96h3tfrs`, run inside ONE ≤ 6 h single-GPU allocation with the existing 9×9 machinery parameterised (not forked), CONVERGES visibly: the policy loss falls clearly below the uniform baseline `ln(50) = 3.912` to under 2.5, the value loss falls, at least two successive candidates are accepted by the gatekeeper, and the latest accepted net beats the run's first exported net at fixed visits — with a DENSE per-batch loss log from which a loss curve can be plotted.

## 2. Success Criterion

- **Needed evidence type:** `numerical simulation` (empirical measurement of a training run)
- **Done when:** the summary JSON `evidence/converged_7x7/summary-<jobid>.json` reports `converged: true`, i.e. all four conjuncts below hold on artefacts the loop itself wrote.
- **Verification command:**
  `bash results/ktg/paper_1902.10565/codes/eval/check_board_param.sh` (the parameterisation claim, login-node executable, PASSES today) and, once the job is terminal,
  `python3 results/ktg/paper_1902.10565/codes/eval/summarize_7x7_run.py <BASEDIR> --out <summary>`
- **Measured tolerance / metric:**

| # | Criterion | Threshold | Tolerance / how it is read |
|---|---|---|---|
| S1 | policy loss below the uniform baseline | `min p0loss < ln(7·7+1) = 3.912` | `loss_log.min_p0loss` over `metrics_train.json`; the baseline is exact, no tolerance |
| S2 | policy loss below target | `min p0loss < 2.5` | same series. A value in `[2.5, 3.912)` is reported as PARTIAL, never as converged |
| S3 | value loss falling | `min vloss < first logged vloss` | same series; a monotone-decreasing claim is NOT made — only that the minimum is below the first row |
| S4 | gatekeeper acceptances | `len(models/) >= 2` | one directory per accepted candidate; the `Candidate won match` lines are recorded alongside |
| S5 | fixed-visit match, positive score | Wilson 95 % lower bound on the score fraction `> 0.5` | 200 games, balanced colours by construction, 100 visits, latest accepted vs first exported |
| S6 | dense loss log | `loss_log.rows >= 20` | one JSON row per `KTG_PRINT_EVERY = 8` batches |

- **Open obligations before start:** none blocking. `o02_pos_len_matches_databoardlen` is *extended* by this node from a constant to a parameter and re-verified in both directions (C2–C5 of the verifier).
- **Reduction-to-baseline test:** the 9×9 behaviour of every shared file with the new variables UNSET must be unchanged. Verifier checks C1, C2, C4, C6, C7, C9 and C11 are exactly that test, and they pass.

## 3. Motivation

Nothing in this mission has yet shown the loop *learning*. `synchronous_loop_smoke` proved the five stages run and hand off (two cycles, one export, one gatekeeper decision) but at 256 samples/epoch it could not learn, and — decisively — its `metrics_train.json` is **empty (0 lines, verified)**, because `train.py:1379` hard-codes a 100-batch print interval and the smoke ran 8 batches per epoch. There is no loss curve anywhere in the mission. 7×7 is the smallest board on which the full pipeline (`bSizes`, `dataBoardLen`, `-pos-len`, the gate, the match) is exercised unchanged while a convergence signal fits in one short allocation, so it is the cheapest possible answer to "does this loop actually learn?" — run while the 9×9 production chain (job 299461) waits in the queue.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | predecessor nodes `env_build`, `cfg_9x9_override`, `synchronous_loop_smoke` |
| result_seed | `.../decomposition/result_seed.md` | loop stages and their status |
| assumptions | `.../decomposition/assumptions.md` | `a05_9x9_only` — this node deliberately runs OUTSIDE it, on 7×7, as a test run; it advances no 9×9 claim |
| obligations | `.../decomposition/obligations.md` | `o02` (pos_len == dataBoardLen), `o04` (scratch budget), `o13` (mission configs) |

**Upstream task outputs:** `tasks/env_build` (toolchain + engine at `$KTG_ROOT`), `tasks/cfg_9x9_override` (the 9×9 configs and the train wrapper), `tasks/synchronous_loop_smoke` (`evidence/smoke/` — rows/game 31.7–32.0 at 9×9, peak VRAM 4094 MiB at batch 32, the empty `metrics_train.json`), `tasks/derive_cycle_knobs_9x9` (the knob-derivation method reused here).

## 5. Execution Rules

- Build on what exists: the loop, the export wrapper, the storage guard, the pos_len guard and the match runner are **reused unchanged**. Only three shared files gained a defaulted variable; nothing was forked.
- The `train.py` change lives in the **scratch build clone only**, saved as `codes/env/train-print-every.diff`. `ref-code/lightvector-KataGo` is never edited (kernel §4; verifier C7).
- No knob is retuned inside the allocation except the one the brief requires: games/cycle, re-derived once from the rows/game the run itself measures in cycle 1.
- If an abort rule fires, the job stops cycling and reports. It does not tune and retry.

## 6. Files And Links

| Slot | Path |
|---|---|
| Reference code | `ref-code/lightvector-KataGo` @ v1.18.2 (read-only) |
| Scratch build clone (patched) | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/build/KataGo` |
| Run directory | `$KTG_ROOT/runs/t7` |
| Code output | `results/ktg/paper_1902.10565/codes/{cfg,loop,eval,env}/` |
| Evidence | `results/ktg/paper_1902.10565/evidence/converged_7x7/` |
| Git branch | `az: main` |

## 7. Architecture

```text
codes/cfg/selfplay_7x7.cfg          6 keys off selfplay_9x9.cfg
codes/cfg/gatekeeper_7x7.cfg        4 keys off gatekeeper_9x9.cfg
codes/cfg/match_first_latest_7.cfg  5 keys off match_first_latest_9.cfg
codes/loop/t7_cycle.sh              exports KTG_POS_LEN=7 + the knob set, one cycle
codes/loop/converged_7x7.sbatch     the ONE allocation: preflight, cycles, match, summary
codes/eval/summarize_7x7_run.py     loss log + exports + gate + match -> summary JSON
codes/eval/check_board_param.sh     the verifier (11 checks, both directions)
codes/env/train-print-every.diff    the mission-owned one-line train.py patch
--- parameterised, NOT forked -------------------------------------------------
codes/loop/train_9x9.sh             -pos-len "${KTG_POS_LEN:-9}" + $KTG_TRAIN_EXTRA_ARGS
codes/eval/check_pos_len_npz.py     shapes and row bytes derived from KTG_POS_LEN (def. 9)
codes/loop/synchronous_loop_9x9.sh  UNCHANGED (its knobs and configs were already ${VAR:-})
```

## 8. Phase Plan

### Phase 1 — parameterise + patch (DONE, verified)
- **Files:** the eight above. **Test:** `check_board_param.sh` → `CHECK_BOARD_PARAM: PASS`, 11/11.
### Phase 2 — the allocation
- 1 GPU, 16 CPUs, 96 G, `--time=06:00:00`, `--partition=b200,l40s` (L40S admitted: `evidence/env/l40s-300987.txt` `L40S PROBE RESULT: PASS`, engine runs natively on sm_89 at 2401.88 visits/s).
- **Test:** cycle 1 completes and `metrics_train.json` gains ≥ 1 row. **PASSED** — job 301096, gb207, cycle 1 exit 0 in ≈ 5 min, 46 rows.
### Phase 3 — cycles to the deadline, then the match, then the summary
- **Test:** the six criteria of § 2.

## 9. Quick-Win Path

1. Cycle 1 completes → `metrics_train.json` is non-empty → the loss curve exists at all (the smoke's blocking defect is closed).
2. Cycle 2's gatekeeper produces the first `Candidate won/lost match` line at 7×7.
3. **Smoke check:** `min p0loss < 3.912` (below uniform) by 15 000 samples.

## 10. First Test Parameters

`E` = `NUM_TRAIN_SAMPLES_PER_EPOCH`. Every value is a ratio off `E` that is either upstream's own or a constraint read out of the source; the 9×9 smoke measurements are the inputs.

| Knob | Value | Justification |
|---|---|---|
| `BATCHSIZE` | 32 | the smoke measured peak VRAM 4094 MiB at batch 32 on one GPU with this model kind; 32 gives 156 optimiser steps per cycle, which is what makes the curve dense |
| `NUM_TRAIN_SAMPLES_PER_EPOCH` | 5000 | 156 batches ≥ the 100-batch floor `train.py:1379`'s stock interval imposes even before the patch, so at least one row lands per cycle regardless |
| `NUM_TRAIN_SAMPLES_PER_SWA` | 2500 | `E//2`, `train.py:441`'s own default relation |
| `MAX_TRAIN_PER_DATA` | 8 | upstream's reuse cap; never raised |
| `SHUFFLE_MINROWS` | 6000 | `1.2·E`. `train.py:1303-1346` returns None (→ `-quit-if-no-data`, no export) below `round(E/batch)=157` batches; `shuffle.py:1058,1076` caps `random/tdata/` rows at `min_rows`, so cycle 1's window **is** `min_rows`. 6000 rows = 187 batches |
| `MAX_TRAIN_SAMPLES_PER_CYCLE` | 25000 | `5·E`, upstream's own cap/epoch ratio (500000/100000) |
| `SHUFFLE_KEEPROWS` | 30000 | `1.2·cap`, upstream's own keep/cap ratio (600000/500000) |
| `TAPER_WINDOW_SCALE` | 12000 | `2·min_rows`, the 9×9 knob set's own ratio (50000/25000) |
| `EPOCHS_PER_EXPORT` | 1 | one candidate per cycle; paired with `-max-epochs-this-instance 1` so the trainer cannot export twice inside one cycle |
| `NUM_GAMES_PER_CYCLE` | 600 in cycle 1, then `ceil(1.2·E/r)` clamped to [200, 1500] | rows/cycle ≥ `1.2·E` = 6000 at the rows/game `r` the run MEASURES in cycle 1. 9×9 measured 31.7–32.0 rows/game; area scales 49/81 so ~19 is the prior and 12 the conservative floor (claim c10) — 600 games clears 6000 rows even at 10 |
| `maxVisits` / `cheapSearchVisits` | 100 / 25 | fast search, upstream's 1:4 cheap:full ratio kept (600:100 → 100:25) so `cheapSearchProb = 0.75` still means what it meant. Every mechanism stays on: root Dirichlet noise, LCB, graph search, subtree value bias, uncertainty, forks, side positions, surprise weighting, komi variation |
| `reducedVisitsMin` | 25 | upstream ties it to `cheapSearchVisits`; a floor above the cheap branch would be backwards |
| `numGamesPerGating` | 80 | `gatekeeper.cpp:184,188` stops early on decision, so N sets both the noise floor and the worst-case gate cost. 80 → ≥ 40 games to accept, ~half a cycle's selfplay. `requiredCandidateWinProp` keeps upstream's 0.5 |
| gate `maxVisits` | 100 | the visit count selfplay trains under. Scaling upstream's 150/600 ratio would gate at 25 visits, where a 7×7 result is mostly root noise |
| `numGameThreads` | 12 | 16 CPUs requested (the l40s partition is CPU-tight — coordinator, 2026-09-04): 12 game threads + 1 NN server thread + the shuffler |
| `KTG_PRINT_EVERY` | 8 | ~19 loss rows per 156-batch cycle; the brief's 5–10 |
| `-lr-scale-auto` | on | `train.py:1060-1078` multiplies the LR by **1/20** below 250 000 samples; this run trains ~150 000, so at the stock `lr_scale = 1.0` *every* batch would sit at 1/20 of the mature rate and could not converge in one allocation — that warmup horizon is calibrated for a 19×19 run of billions of samples. `-lr-scale-auto` (`train.py:84,504-512`) is a **constant 8.0** below 550 M samples, so the effective multiplier across the whole run is `8.0 × 1/20 = 0.4` — exactly what upstream itself runs at the start of a from-scratch run. Warmup is left ON; `-no-lr-warmup` would hand a randomly initialised net 20× that rate. Travels through `$KTG_TRAIN_EXTRA_ARGS`, empty for the 9×9 chain |
| match | 200 games, 100 visits, komi 9 | 7×7 area scoring is B+9 at perfect play; colours are balanced by construction (`match.cpp:99-110`), so komi moves variance, not bias |

## 11. Risk Mitigation / Abort Rules

| Risk | Signature | Action |
|---|---|---|
| **A1** the window never fills, nothing exports | `export_count == 0` at the end of cycle 6 | STOP the cycle loop, write the summary, exit non-zero. Report. Do not retune |
| **A2** it does not learn | 15 000 samples trained and `min p0loss >= 3.5` | same: STOP, summarise, report as measured |
| a cycle fails | `t7_cycle.sh` exit ≠ 0 | STOP, record the exit code and the cycle log path in `abort` |
| rows/game far off the 7×7 prior | cycle-1 measurement | games/cycle re-derived ONCE from the measurement (this is the brief, not a silent tune); recorded in `rows_per_game-<jobid>.json` |
| the run is slower than budgeted | fewer cycles before the deadline | the loop is time-budgeted, not cycle-count-budgeted; the match still runs in the reserved 35 min |
| the 9×9 chain is disturbed | staged config or `-pos-len` changes | verifier C1/C2/C4/C6/C7/C9 — all pass with the variables unset |
| scratch fills | `scratch_guard.sh` exit 1/2 | the loop already brakes on it; run adds ≤ ~2 GiB |

## 12. Current State

- `[SOLID]` the parameterisation and the patch: `evidence/converged_7x7/check_board_param.txt`, `CHECK_BOARD_PARAM: PASS`, 11/11 checks executed.
- `[SOLID]` **rows/game at 7×7 = 19.73** (11 838 rows over 600 games, cycle 1 of job 301096) — the ~19 prior from area scaling was right; games/cycle re-derived to 305 by the job itself (`evidence/converged_7x7/rows_per_game-301096.json`).
- `[SOLID]` **the dense loss log exists** — 46 rows in cycle 1 alone, one per 8 batches, where the 9×9 smoke's file had 0. The blocking defect § 3 names is closed.
- `[PRELIMINARY]` **the loop learns.** Cycle 1, job 301096 on gb207: `p0loss` 3.9209 → **3.4905**, already below the uniform baseline 3.9120; `vloss` 1.2977 → **0.9239**; top-1 policy accuracy `pacc1` 0.027 → 0.095; one candidate exported (`t7-s11808-d11838`, frozen as the match baseline). Cycle wall time ≈ 5 min. S1, S3 and S6 are met; S2, S4, S5 are still open.
- `[PRELIMINARY]` **one cycle trains ~11 800 samples, not the 5 000 § 10 derives.** With `-no-repeat-files` an instance's single epoch consumes the whole *fresh* window rather than `samples-per-epoch` rows, so cycle 1 trained 11 808 samples over its 11 838 new rows. From cycle 2 the window gains ~6 000 fresh rows per cycle (305 games × 19.73), so ~6 000 samples/cycle. Consequence for reading the summary: **`per_cycle_losses` buckets the log by 5 000 samples, which is NOT 1:1 with cycles.** The authoritative series is `loss_rows` / `metrics_train-<jobid>.json`; plot `p0loss` against `nsamp`.
- `[OPEN]` S2 (`min p0loss < 2.5`), S4 (≥ 2 acceptances), S5 (positive match score) until `summary-301096.json` is final. Closing evidence: that file plus `metrics_train-301096.json`.
- `[OPEN]` the logged `p0loss` is an **exponential moving average** (`metrics_logging.py:10-25`, decay 0.999 per batch ⇒ ~1 000-batch memory), so it LAGS the instantaneous loss by roughly two cycles. Every threshold in § 2 and § 11 is therefore conservative: the true loss is below the plotted curve, never above it. Cycle 1's own numbers already clear abort rule A2 (3.4905 < 3.5 at 11 776 samples), so A2 cannot fire spuriously on the lag.

## 13. Forbidden Actions

- Never edit `ref-code/lightvector-KataGo` (the patch is scratch-clone-only).
- Never edit `codes/loop/loop.sbatch` — another worker owns it.
- Never change a 9×9 default in place; only add a `${VAR:-<old value>}` around it.
- Never raise `MAX_TRAIN_PER_DATA` above 8 or set `USEGATING=0`.
- Never retune a knob after an abort rule fires; report the measurement.
- Never claim convergence from a partial criterion set.

## 14. Promise Tag

- **Promise format:** `<promise>converged_test_7x7 MIN_P0LOSS WITHIN 2.5</promise>` — committed only after the summary JSON reports it.

## 15. Progress Update Principles

Per-milestone commits (`feat(7x7,ktg): …`, `exp(7x7,ktg): …`) with a `- run:` job id and verbatim `- verify:` output. `evidence/converged_7x7/status_log.txt` gains one line every 30 min from inside the allocation; `metrics_train-<jobid>.json` and `running_metrics-<jobid>.json` are refreshed every 10 min so the curve can be plotted mid-run.

## 16. Termination Checklist

- [x] Verification command ran and output is pasted (`check_board_param.sh`, PASS).
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] Metrics within the § 2 thresholds.
- [x] Reduction-to-baseline test passed (9×9 behaviour with the variables unset).
- [ ] No `[BLOCKING]` / `[OPEN]` markers remain.
- [x] No silent scope expansion.
