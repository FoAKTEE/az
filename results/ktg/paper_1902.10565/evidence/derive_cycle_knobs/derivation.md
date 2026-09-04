# Derivation record — `arxiv-1902.10565::derive_cycle_knobs_9x9`

Task file: `tasks/derive_cycle_knobs_9x9/implementation.md`. Obligations closed here:
`o24_cycle_knobs_derived`, the knob conjunct of `o13_loop_config_paths`; the `o03` /
`c06` thread statement is settled as a *decision* here and re-measured elsewhere.
CPU only, login node, no Slurm allocation, no GPU. Verbatim script output:
`../knobs/derivation.txt` (six blocks) and `closing_check.txt` (block 5 alone).

Deliverables: `codes/loop/knobs_9x9.env` (the knob set, one derivation comment per knob),
`codes/eval/derive_knobs.py` (the arithmetic + the K1–K7 checks + `--self-test` +
`--assert-loop-defaults`), `codes/eval/check_knobs_9x9.py` (the closing check that re-derives
from the measured JSON and asserts the four mission tolerances), and the rewritten
`${VAR:-default}` block of `codes/loop/synchronous_loop_9x9.sh:128-156` (CHANGE 9 only).

## 1. Inputs, and which copy of each was read

Every measured number comes from Slurm job 298712 (attempt 1) or 299259 (attempt 2).
**The unsuffixed evidence names are mutable and were overwritten at 09:58:41Z by attempt 2;
obligation `o37` records that the audit run over the resulting mixed 6-/7-column
`ps_samples.tsv` re-admits three foreign pids and reports `train nlwp 36`, which is a sampler
defect, not a measurement.** The job-suffixed copies are content-hashed and immutable
(`evidence/smoke/validation_core.md` finding 8), and are what this derivation reads:
attempt 2's own `audit-299259.json` / `throughput_smoke-299259.json` were written by the
ppid-filtered sampler with `foreign_pids_excluded: []` and do report `train nlwp 14`.
`derive_knobs.py` and `check_knobs_9x9.py` prefer the suffixed names and refuse to silently
use an unsuffixed one when a suffixed one exists.

| input | file | sha256 | value used |
|---|---|---|---|
| rows/game, real net | `evidence/smoke/rows_per_game-298712.txt` | `daed88ef…3828` | `r = 32.3` (646 rows / 20 games, leg-D1 probe) |
| rows/game, random net | same | same | `r0 = 31.675` (2534 rows / 80 games) |
| bytes/row on disk | `evidence/smoke/throughput_smoke-298712.json` | `927fb04c…2947` | `353.8` (896 536 B / 2534 rows) |
| train samples/s (all-in) | same | same | `14.243` (2528 samples / 177.49 s, `torch.compile` included) |
| real-net selfplay | same, `probe_search` + `per_phase_stage` | same | 20 games in 30.75 s → `2341.5` games/h |
| real-net selfplay, attempt 2 | `evidence/smoke/throughput_smoke-299259.json` | `d91e7920…b9ff` | 80 games in 141.75 s → `2031.7` games/h — **the one used**, being the slower of the two |
| train samples/s, attempt 2 | same | same | `17.202`; `14.243` from 298712 is the slower and is the one used |
| rows/game, attempt 2 | `evidence/smoke/rows_per_game-299259.txt`, `probe_search{,_nofork}-299259.json` | `e983720a…b7c7` | `31.95` (639/20) and `34.4` (2064/60); sensitivity block 4 |
| audits cited by name | `evidence/smoke/audit-298712.json`, `evidence/smoke/audit-299259.json` | `646e4ef1…f282` / `6968eb12…6eea` | the two S13 blocks the rows above come from |
| gatekeeper | same, `cycle2/gatekeeper` | same | 156 games in 70.19 s, one real net |
| peak VRAM | same | same | `4094` MiB at batch 32 |
| thread counts | `evidence/smoke/nlwp_max-298712.txt` | `c1538342…42d3` | selfplay 22 random / 25 real-net, gate 25 (one real net), train 14, shuffle 4+8 |
| storage constants | `codes/data_budget/budget.env` | `6f38681e…1f62` | `KTG_SCRATCH_HARD_BYTES=536870912000`, retention bounds |
| reference code | `ref-code/lightvector-KataGo` @ `fd0723fd` (v1.18.2) | — | every `path:line` below |

Statistical treatment. `r` rests on 20 games, so every **binding** inequality is evaluated a
second time at the task file § 11 lower bound
`r_lo = r·(1 − 1/√n) = 32.3·(1 − 1/√20) = 25.0775` and `r0_lo = 31.675·(1 − 1/√80) = 28.1336`,
and must hold at both. `[OPEN]` `r` is re-measured by `measure_stage_throughput`; re-run
`check_knobs_9x9.py` then.

## 2. The constraints, read out of the code

| # | constraint | where |
|---|---|---|
| C0 | an epoch must hold ≥ `print_train_loss_every_batches = 100` batches, or `metrics_train.json` is never written — the smoke's file was 0 bytes at 38 batches | `train.py:1379`, `:1661`, `:1694` |
| C1 | `train_bucket_level += new_rows × MAX_TRAIN_PER_DATA`, clamped at `cap_eff = max(MAX_TRAIN_SAMPLES_PER_CYCLE, E)`; an epoch runs only while `bucket > 0.99·E`, else `-stop-when-train-bucket-limited` breaks | `train.py:1256-1259`, `:1434-1445` |
| C2 | a fresh run's bucket starts at `E`, so the first epoch is free | `train.py:972` |
| C3 | `get_files_for_subepoch` returns `None` unless the shuffled files hold `round(E/batch)` batches; with `-quit-if-no-data` the trainer then exits **0 with no export** | `train.py:1303-1346`, `:1487-1488` |
| C4 | `export_cycle_counter` is *persistent* in `train_state` and exports at `>= epochs_per_export`; `max_epochs_this_instance` bounds the epochs of one invocation | `train.py:871,975,1743,1831`, `:1423` |
| C5 | shuffle window `desired_num_rows = min_rows + expand·f(usable − min_rows; taper, exponent)` with `expand 0.4`, `exponent 0.65` | `shuffle.py:414-435`, `shuffle.sh:44-45` |
| C6 | random-net rows count toward the window only up to `min_rows`, so **cycle 1's window IS `min_rows`** | `shuffle.py:1058,1077` |
| C7 | the shuffler exits 0 and produces nothing while total rows `< min_rows` | `shuffle.py:1090-1092` |
| C8 | `keep-target-rows` subsamples the window; `SHUFFLE_KEEPROWS` must exceed `MAX_TRAIN_SAMPLES_PER_CYCLE` | `shuffle.py:890,1158-1159`; `synchronous_loop.sh:66` comment |
| C9 | `swa_period_samples` defaults to `E // 2` | `train.py:441` |
| C10 | declared `--cpus-per-task` ≥ live OS threads (the only surviving CPU rule; the 20 % clause was withdrawn) | `mission.json` `decisions[0]`, `compute.cpuCapPerJob = null` |
| C11 | mission-root bytes < 500 GiB, projection-based | `codes/data_budget/budget.env` |

## 3. Solving, cheapest knob first

**E = `NUM_TRAIN_SAMPLES_PER_EPOCH` = 20000.** C0 with `batch = 128` gives `E ≥ 100·128 = 12800`;
20000 is that rounded up and is DESIGN § 2's pilot value, giving `round(20000/128) = 156`
batches/epoch. Upstream's 100000 (`synchronous_loop.sh:59`) is a 19x19 number.

**batch = 128, `MAX_TRAIN_PER_DATA` = 8, `NUM_THREADS_FOR_SHUFFLING` = 8, `TAPER_WINDOW_SCALE` = 50000** —
upstream `:62,:60,:58,:65` unchanged, because no measured constraint binds them: peak VRAM was
4094 MiB at batch 32 on a 180 GB B200 (≈40× headroom at 128); 8 is the reuse cap the task file
§ 13 forbids raising; the shuffler measured 4 + 8 = 12 threads; and the taper only decides where
window growth turns sublinear, which at 9x9 scale is past cycle 20.

**`SHUFFLE_MINROWS` = 25000 = 1.25·E.** By C6 the cycle-1 window equals `min_rows` exactly, so
`min_rows` alone decides whether the first production cycle can fill an epoch at all (C3) —
this is the third failure mode the smoke exposed. 25000 rows = 195 batches against the 156 an
epoch needs, a 1.25 margin that the conservative K4 does not have to borrow from
`-approx-rows-per-out-file 70000` file granularity (`shuffle.sh:48`).

**`NUM_GAMES_PER_CYCLE` = 1000.** Two lower bounds, both evaluated at the conservative rows/game:

- freshness (the mission tolerance T1): `G·r_lo ≥ 1.2·E` → `G ≥ 24000/25.0775 = 957.0`;
- bootstrap (C7 + C6, check K5): `G·r0_lo ≥ min_rows` → `G ≥ 25000/28.1336 = 888.6`.

`G = max(957.0, 888.6)` rounded up to 1000. **Upstream's 500 (`:57`) fails both** —
`500·32.3 = 16150 < 24000`, and `500·31.675 = 15838 < 25000` — which is the finding that
retires DESIGN § 2's 500-game pilot hypothesis. The § 2 verification command's literal
parameters are that hypothesis, and `derivation.txt` block 2 records them failing.

**`MAX_TRAIN_SAMPLES_PER_CYCLE` = 100000 = 5·E**, keeping upstream's own cap/epoch ratio
(`:64` 500000 / `:59` 100000 = 5). By C1 this knob is what fixes the epochs a cycle may run,
and the ratio survives the measurement: `5·E = 100000 ≤ (8/2)·G·r_lo = 100310`, i.e. even at
*half* the reuse cap and at the conservative `r` the cycle's own new rows pay for all five
epochs. Realised reuse is `100000/32300 = 3.10` (3.99 at `r_lo`), so a 2× error in `r` still
cannot cross 8.

**`SHUFFLE_KEEPROWS` = 120000 = 1.2·cap**, keeping upstream's keep/cap ratio
(`:66` 600000 / `:64` 500000). Satisfies C8's `keep > cap` and holds a whole cycle's draw
(`5·E = 100000` rows) with 20 % margin.

**`EPOCHS_PER_EXPORT` = 5** = `floor(min(gain, cap_eff)/E)` with `gain = G·r·8 = 258400`
(200620 at `r_lo`) and `cap_eff = 100000` — the same integer at `r` and at `r_lo`. Passed as
**both** `-epochs-per-export` and `-max-epochs-this-instance`, so by C4 the persistent counter
advances by at most 5 per cycle and **never more than one candidate is exported per cycle**.

**`NUM_TRAIN_SAMPLES_PER_SWA` = 10000** = `E // 2`, C9's own default made explicit (K6).

### The export ramp — stated, not smoothed

`[PRELIMINARY]` "Exactly one candidate per cycle" holds from the cycle where the shuffled
window first holds `5·E = 100000` rows. Evaluating C5 at `r_lo` cycle by cycle (block 3 of
`derivation.txt`) that is **cycle 13**; cycles 1–12 are window-limited to 1–4 epochs and the
persistent counter carries the remainder forward, so the export *slips* rather than
duplicating. Upstream behaves the same way and the invariant that matters — at most one gated
candidate per cycle, which is what DESIGN § 2 and pass 1's four-candidate defect are about —
holds from cycle 1. Making it *exactly* one from cycle 1 would need `min_rows ≥ 5·E = 100000`
and therefore ≥ 3554 random games in the bootstrap cycle, which then re-enters the `G`
derivation and diverges; the ramp is the cheaper honest answer.

## 4. The thread / CPU coupling — DESIGN § 1's `[BLOCKING]`

Measured (`nlwp_max-298712.txt`): every random-net selfplay 22 (four independent
measurements), **25 on both real-net stages** — the leg-D1 selfplay probe (pid 332406) and the
cycle-2 gatekeeper running one exported net against the random baseline (pid 328662) — train
14, shuffle 4 + 8. The +3 is the CUDA runtime/driver block that `debugSkipNeuralNet` never
creates (`cpp/program/setup.cpp:126`). `25 > 24` broke the "declared ≥ used" rule.

DESIGN § 1 left two admissible repairs to this node. **Chosen: raise the declaration, keep
`numGameThreads = 18`.** With the CPU cap withdrawn (`mission.json` `decisions[0]`,
`compute.cpuCapPerJob = null`) a larger declaration costs nothing, while cutting game threads
would lower the NN queue depth that § 1 already blames for the 21.5 % mean GPU duty cycle.

| stage | threads | source |
|---|---|---|
| gatekeeper, two real nets | 18 game + 2 nnServer + 1 dataWrite + 1 main + 2×3 CUDA = **29** | `gatekeeper.cpp:548-553`, `setup.cpp:126,193-203`; `[OPEN]`, arithmetic on the one-net measurement of 25 |
| selfplay, real net, mid-run net switch | 18 + 1 nnServer + 1 dataWrite + 1 modelLoad + 1 main + 3 CUDA = 25 (**measured**) + 2 transient = **27** | `selfplay.cpp:359-364`, `selfplaymanager.cpp:156`; measured |
| train | **14** (measured, `OMP_NUM_THREADS=MKL_NUM_THREADS=4`) | measured |
| shuffle | 4-thread parent + 8 worker processes = **12** (measured) | `shuffle.py:791` |

`KTG_CPUS_PER_TASK = 32` ≥ 29, headroom 3. A node has 124 CPUs and there is no cap.

`[OPEN]` `o38` (proposed): `codes/loop/loop.sbatch` still carries `#SBATCH --cpus-per-task=24`
and `REQ_CPUS=24`, and the two cfgs carry `numGameThreads = 18`. Wiring `KTG_CPUS_PER_TASK`
into them belongs to `loop_resume_under_walltime` / `cfg_9x9_override`; this node's task file
§ 13 forbids touching anything outside the loop's knob block. Closes when both files carry 32
and a real-net cycle re-measures `nlwp_max ≤ --cpus-per-task`.

## 5. Projections that ship with the set

`[PRELIMINARY]` — tiny-count inputs; `measure_stage_throughput` owns the real bound (K7).

Cycle wall = 3544 s selfplay (1000 games at a 0.5×-derated **2031.7** games/h — the slower of
the two jobs' real-net measurements) + 7021 s train (100000 samples at the all-in **14.243**
samples/s, again the slower of the two, and it already contains two `torch.compile` starts)
+ 180 s gate + 377 s shuffle + 60 s export = **11182 s = 3.11 h**, so **23 whole cycles fit one
`2-23:30:00` chain link** and no cycle is remotely close to the 60 h bound.

Storage = 16.11 MiB/cycle monotonic (tdata `32300 × 353.8 B` = 10.90 MiB, sgfs 2.34 MiB, one
export 2.87 MiB; equivalently 11.16 KiB/game at the real-net `r`) + 553 MiB bounded steady state
(3 shuffle dirs × 120000 rows, 10 rejected models, 10 checkpoints, 3 dated archives) + a 20 GiB
venv/build allowance = **20.90 GiB after a full 23-cycle link** against the 500 GiB cap; **30480 cycles** would fit before the cap. The
per-cycle write is also 300× under the guard's default 20 GiB projection, so `scratch_guard.sh`
never refuses a cycle on this set.

`[OPEN]` real-net games/hour rests on 100 probe games across the two jobs (298712: 20 in
30.75 s; 299259: 20 in 44.41 s and 60 in 96.24 s), every one of them writing a multi-MB
`logSearchInfo` log and none of them inside a real production cycle. The 0.5× derate is a
planning allowance, not a measurement; `measure_stage_throughput` owns the real bound.

## 5b. Delta after smoke attempt 2 (job 299259, commit `98d6c42`)

Attempt 2 landed while this derivation was being written. Three of its findings touch this
node, and none of them moves a knob:

1. **`full_frac = 0.342 ± 0.006`** over three runs (fork and fork-free), not the
   `1 − cheapSearchProb = 0.25` that `decomposition/derivation.md` § 4 predicts, so the
   `(1 − 0.75)·80 + 0.02·80 ≈ 22` rows/game chain and assumption `a07_moves_per_game_80` are
   both suspect. **This derivation never uses either.** Every row count above is the
   *measured* rows/game; `cheapSearchProb`, `maxVisits` and moves/game appear nowhere in
   `derive_knobs.py`. The `~22 rows/game` planning figure that DESIGN § 2 and the task file
   § 10 carried is what the 500-game pilot rested on, and it is exactly the figure the
   measurement replaced — the reason the pilot's `NUM_GAMES 500` fails T1 here.
   `[OPEN]` `a07` needs its own transition; `paper_code_map_search` owns it.
2. **Bytes per game.** `353.8` B/row is unchanged between the two jobs, giving `10.94` KiB/game
   at the random-net `r0` and `11.16` KiB/game at the real-net `r` — both above c10's second
   conjunct of `≤ 10 KiB/game`, which 299259 refuted. The storage projection in § 5 is built
   from B/row × rows/cycle, never from a KiB/game figure, so the refutation changes the
   *claim* but not this arithmetic; at 16.11 MiB/cycle the 500 GiB cap is 30 480 cycles away.
3. **Threads.** 299259 reproduced `25` at `numGameThreads = 18` for any CUDA-context process
   and `14` for train with a **ppid-filtered sampler and no foreign pids at all**
   (`audit-299259.json` `S13_throughput.ps_scope`, `foreign_pids_excluded: []`). That removes
   the o37 doubt from the numbers § 4 is built on — attempt 1's node-wide sampler had to argue
   the three 36-thread pids away, attempt 2 never saw them. The coordinator's floor is
   `--cpus-per-task ≥ 25`, or 28 with the net-switch allowance; **32 clears it**, the extra 4
   being the still-unmeasured second CUDA context of a two-real-net gatekeeper.

The only number that moved is the cycle-wall projection: `check_knobs_9x9.py` now reads both
jobs' rates and takes the **slower** of each pair (2031.7 games/h from 299259, 14.243 samples/s
from 298712), so the projected cycle went from 2.98 h to **3.11 h**, 23 whole cycles per chain
link instead of 24. § 5 carries the updated numbers.

## 6. Sensitivity, and why the set does not move

`derivation.txt` block 4 re-runs the derived set at every rows/game the smoke produced —
31.95 (attempt-2 20-game probe), 32.3 (admitted 20-game probe), 34.4 (attempt-2 60-game
`nofork` probe). All three `PASS` with `EPOCHS_PER_EXPORT = 5` and reuse 3.10 ± 0.2, so the
o37 evidence overwrite does not change a single knob. The set first fails only if the true
`r` falls below `24000/1000 = 24.0` rows/game — below the § 11 lower bound of the measurement
and near the bottom of the c10 band `[12, 35]`.

## 7. What the § 2 verification command did

`derivation.txt` block 2 is the task file § 2 command run **verbatim**, both invocations.
It exits 1, for three reasons that are findings rather than defects of this node:

1. Its literal `--games 500` is DESIGN § 2's pilot hypothesis, and the measured `r` refutes it
   (T1 `0.799 < 1.2`; and with the derived `min_rows` it would also miss K5). Task file § 9
   Quick-Win step 2 anticipates exactly this and directs raising `games` first.
2. Its `--min-rows` default of 10000 (task file § 10) makes the cycle-1 window 10000 rows =
   78 batches against the 156 an epoch needs — K4 fails from the very first cycle.
3. It interpolates `evidence/smoke/rows_per_game.txt` with an unquoted `$(cat …)`, which
   word-splits a prose file into 79 argv tokens, and it names the **mutable** copy that o37
   records as overwritten. `derive_knobs.py` re-joins the blob and extracts
   `rows_per_game_real` so the command still runs as written, and prints which file it read.

Proposed replacement `closing_check` for the ledger row (`derivation.txt` block 5, exit 0):
`python3 results/ktg/paper_1902.10565/codes/eval/check_knobs_9x9.py`. It takes no parameters
at all — knobs from `knobs_9x9.env`, measurements from the admitted `-298712` evidence,
storage constants from `budget.env` — so it cannot be made to pass by choosing arguments, and
it re-runs whenever any of those four files changes.

## 8. Open items

- `[OPEN]` `o38` — wire `KTG_CPUS_PER_TASK = 32` into `loop.sbatch` (`--cpus-per-task`,
  `REQ_CPUS`); owner `loop_resume_under_walltime`. Until then DESIGN § 1's thread finding is
  *decided* but not *wired*.
- `[OPEN]` two-real-net gatekeeper threads: 29 is arithmetic, 25 is the one-net measurement.
  First measurable at `gatekeeper_stage`, cycle 3 or later (claim `c13`).
- `[OPEN]` real-net games/hour (n = 20) and train samples/s at batch 128 —
  `measure_stage_throughput`; re-run `check_knobs_9x9.py` after it.
- `[OPEN]` `o37` — until the sampler defect is fixed, the unsuffixed evidence names cannot be
  used as this node's inputs.
- `[OPEN]` the export ramp of § 3: exactly one candidate per cycle only from cycle 13.
  `scale_data_window` may shorten it by raising `min_rows` once a real bootstrap is measured.
- `[FUTURE]` `shuffle.py -exclude-qvalues` (`o21`) would cut 492 B of the 2145 B row and with
  it the storage line; not adopted here.
