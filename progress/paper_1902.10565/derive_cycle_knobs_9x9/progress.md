# progress — `derive_cycle_knobs_9x9`

Wave 2. Login node, CPU only, no Slurm allocation, no GPU.

## State

`[SOLID]` Both phases landed. Phase 1 (`codes/eval/derive_knobs.py` + `check_knobs_9x9.py`,
`evidence/knobs/derivation.txt`) and phase 2 (the CHANGE 9 block of
`codes/loop/synchronous_loop_9x9.sh`, matched 11/11 by `--assert-loop-defaults`).

Derived set, at the measured `r = 32.3` rows/game and at its 90 % lower bound `r_lo = 25.08`:

| knob | value | binding constraint |
|---|---|---|
| `NUM_GAMES_PER_CYCLE` | 1000 | freshness `G·r_lo ≥ 1.2·E` (957) and bootstrap `G·r0_lo ≥ min_rows` (889) |
| `NUM_TRAIN_SAMPLES_PER_EPOCH` | 20000 | `E/batch ≥ 100` batches or `metrics_train.json` is never written (`train.py:1379`) |
| `SHUFFLE_MINROWS` | 25000 | `= 1.25·E`; cycle 1's window IS `min_rows` (`shuffle.py:1077`, `:414-435`) |
| `MAX_TRAIN_SAMPLES_PER_CYCLE` | 100000 | `= 5·E`, upstream's own cap/epoch ratio; `≤ (8/2)·G·r_lo = 100310` |
| `SHUFFLE_KEEPROWS` | 120000 | `= 1.2·cap`, upstream's keep/cap ratio; `> cap` (`synchronous_loop.sh:66`) |
| `EPOCHS_PER_EXPORT` | 5 | `floor(min(gain, cap_eff)/E)`, same integer at `r` and `r_lo` |
| `NUM_TRAIN_SAMPLES_PER_SWA` | 10000 | `= E//2` (`train.py:441`) |
| `BATCHSIZE` / `MAX_TRAIN_PER_DATA` / `NUM_THREADS_FOR_SHUFFLING` / `TAPER_WINDOW_SCALE` | 128 / 8 / 8 / 50000 | upstream `:62,:60,:58,:65` — no measured constraint binds them |
| `KTG_CPUS_PER_TASK` / `KTG_NUM_GAME_THREADS` | 32 / 18 | worst stage 29 threads (two-real-net gate) ≤ 32 |

## Findings beyond the values

1. The constraint that binds at 9x9 is **not** the train bucket (gain clears the epoch by
   12.9×) but `shuffle.py:1077` + `:414-435`: random rows count toward the window only up to
   `min_rows`, so cycle 1's shuffle window **is** `SHUFFLE_MINROWS`, and that knob — not the
   game count — decides whether the first production cycle can train at all. Recorded as
   DESIGN § 8 R16.
2. "Exactly one candidate per cycle" is not reachable from cycle 1 without a ≥ 3554-game
   bootstrap. What holds from cycle 1 is **at most** one, structurally; exactly one from
   cycle 13. The claim was narrowed rather than the knob bent.
3. DESIGN § 1's `[BLOCKING]` is resolved by decision: raise the declaration to 32, keep
   `numGameThreads = 18`, because with the CPU cap withdrawn the declaration is the free
   side of the trade.

## Open

- `[BLOCKING]` the task file's § 2 command exits 1 (it encodes the refuted 500-game pilot);
  a validator must adopt the parameterless `check_knobs_9x9.py` as the `closing_check`.
- `[OPEN]` `o38` — `loop.sbatch` still declares 24 CPUs; owner `loop_resume_under_walltime`.
  `selfplay_stage` must not start before it lands.
- `[OPEN]` `o03` stays open: its closing condition is a real-net re-measurement at 32.
- `[OPEN]` real-net games/hour (100 probe games) and train samples/s at batch 128 —
  `measure_stage_throughput`; `check_knobs_9x9.py` re-runs on its output.
- `[OPEN]` `o37` — only the job-suffixed evidence copies are usable as inputs.

## Ledger

Error rows appended by this worker (nothing else):
`f3377f43658fc8251a7e5e6b1a75cba6a723f7028b2ae41bd0a9ad79380e71e6` (iter 1, fail — § 2
verbatim) and `8cf75777099d1e5430c1632db7ba03d72ba4c1d48d9eb000b746037e76a51c44` (iter 2,
pass — the derived set). Result / knowledge / claim candidates are in
`results/ktg/paper_1902.10565/evidence/derive_cycle_knobs/candidate_rows.json` for a validator.
