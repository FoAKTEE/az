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

### The export ramp — amended 2026-09-04 (o40)

`[PRELIMINARY]` **The first candidate exports at cycle 5, is gated at cycle 6, and exactly one
candidate per cycle begins at cycle 16 if that first candidate is accepted** (later for each
rejection). Three code facts fix the ramp, and the earlier reading missed the third:

1. `-epochs-per-export` = `-max-epochs-this-instance` = 5, and the export counter is
   PERSISTENT across trainer instances (`train.py:871,975,1743,1831`) — so five epochs in
   TOTAL, not per cycle, produce the first candidate.
2. `-no-repeat-files` stops a trainer instance when the shuffled files run out
   (`katago/utils/training_data_generator.py:35`) and `-quit-if-no-data` then exits 0 with no
   export (`train.py:1487-1489`) — so a cycle runs `floor(window / E)` epochs, capped at 5.
3. While `models/` is empty every cycle plays the RANDOM net, and `shuffle.py:1077` caps the
   usable random rows at `min_rows` — so the window is pinned at 25000 rows = 195 batches =
   ONE epoch, cycle after cycle, and post-random rows cannot appear before the cycle whose
   gatekeeper ACCEPTS. The withdrawn model (`usable = min_rows + (c-1)·G·r_lo` from cycle 2)
   assumed real-net rows one cycle after the start, which is unreachable.

Simulated at `r_lo` with acceptance at cycle 6 (the optimistic case;
`codes/eval/derive_knobs.py`, table `EXPORT RAMP BY CYCLE`, reproduced in `derivation.txt`):

```
c 1-5   random, window 25000, 1 epoch each -> counter 1,2,3,4,5 ; EXPORT at cycle 5
c 6     real,   usable 50077  window 34305  1 epoch
c 7     42561/2   c 8 50116/2 EXPORT   c 9 57156/2   c10 63794/3 EXPORT
c11     70107/3   c12 76149/3 EXPORT   c13 81960/4   c14 87570/4 EXPORT
c15     93004/4   c16 98282/4 EXPORT   c17 103419/5 EXPORT   c18.. 5 epochs, every cycle
exports at cycles [5, 8, 10, 12, 14, 16, 17, 18, ...] -> exactly one per cycle from 16
```

`[SOLID]` What holds from cycle 1 regardless: **at most** one gated candidate per cycle, which
is what DESIGN § 2 and pass 1's four-candidate defect are about. No knob moves: every
K1–K7/T1–T4 inequality is evaluated at cycle 1's window (25000 rows), which a random-net cycle
never goes below, so the conservatism runs in the safe direction. Making the export *exactly*
one from cycle 1 would need `min_rows ≥ 5·E = 100000` and therefore ≥ 3554 random games in the
bootstrap cycle, which re-enters the `G` derivation and diverges; the ramp is the cheaper
honest answer. Planning consequence: the first gate happens after ~5 × (selfplay + a
one-epoch train + shuffle/export), not after one cycle.

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

- `[CLOSED 2026-09-04]` `o39` — `KTG_CPUS_PER_TASK = 32` is wired into `loop.sbatch`
  (`#SBATCH --cpus-per-task=32`, `REQ_CPUS` read from this node's knob file, and a pre-flight
  that refuses a link whose granted `SLURM_CPUS_PER_TASK` or whose cfg `numGameThreads`
  disagrees). Only o39's third conjunct — one executed real-net cycle re-measuring
  `nlwp_max ≤ 32` — is still open, with `o03` and the production chain.
- `[OPEN]` two-real-net gatekeeper threads: 28 is arithmetic, 25 is the one-net measurement.
  First measurable at `gatekeeper_stage`, cycle 3 or later (claim `c13`).
- `[OPEN]` real-net games/hour (n = 20) and train samples/s at batch 128 —
  `measure_stage_throughput`; re-run `check_knobs_9x9.py` after it.
- `[OPEN]` `o37` — until the sampler defect is fixed, the unsuffixed evidence names cannot be
  used as this node's inputs.
- `[OPEN]` the export ramp of § 3 (amended, o40): first candidate at cycle 5, gated at 6,
  exactly one per cycle from 16 under acceptance at 6. The EXECUTED first-export cycle is
  o40 (c), owned by `train_stage` / `export_stage`; `scale_data_window` may shorten the ramp
  by raising `min_rows` once a real bootstrap is measured.
- `[FUTURE]` `shuffle.py -exclude-qvalues` (`o21`) would cut 492 B of the 2145 B row and with
  it the storage line; not adopted here.

## 9. Re-derivation from PRODUCTION — 2026-09-05 (`NUM_GAMES_PER_CYCLE` 1000 → 1500)

> **SUPERSEDED THE SAME DAY BY § 10.** The 1500 set derived here was staged at monitoring
> read 5 and replaced at read 6, before any link consumed it: the fitted drift steepened
> from −0.1070 to −0.1742 rows/game per accepted net and 1500 no longer cleared T1 ten
> accepted nets out. Everything below stands as the record of that step — the method is
> unchanged and § 10 reuses it — but the *values* it derives are not the live set.

Authorised by `mission.json` `decisions[6]` (human, 2026-09-05): *raise NUM_GAMES_PER_CYCLE
1000 -> 1500 for the 9x9 chain from link 2 on*. Recorded here and, for the structural fix,
against node `scale_data_window`. CPU only, login node, no allocation, no job. Verbatim
output: `rederive_check.txt` (five blocks). Chain link 1 (job 301099) was NOT touched: it
sourced its knobs at link start and keeps `NUM_GAMES_PER_CYCLE = 1000` to its end.

### 9.1 What the 20-game probe could not see

§ 1 read `r = 32.3` rows/game from a 20-game probe against the smoke's barely-trained net,
and § 6 concluded that the set "first fails only if the true `r` falls below 24.0". It did.
Forty production cycles measured (`evidence/production_chain/{throughput,rows_per_game}.json/txt`,
`status_log.txt` reads 1–4):

| read | real-net games | r | T1 margin at G = 1000 |
|---|---|---|---|
| 2 | 18 016 | 25.397 | +5.82 % |
| 3 | 18 515 | 25.079 | +4.50 % |
| 4 | 36 040 | **22.174** | **−7.61 %** |

and the **marginal** rate — the last three complete net directories, 8000 games — is
**18.525**, i.e. `1000 × 18.525 = 18 525` new rows against an epoch's own 20 000 draw.
The aggregate flatters the situation because it averages in the early, long-game nets;
the marginal is what the next cycle gets.

The mechanism is measured, not inferred. `RE[…+R]` is **0.0 % in every net directory**, so
this is not resignation. Two separable effects (read-4 per-net table):

1. **Game length collapsed once, then stabilised.** moves/game 130.8 → ~81 between the
   first and third accepted net, and 80–82 for every net since. A one-time transition,
   already over.
2. **Rows per move drifts down on top of it**, 0.2518 (`t9-s1166208`) → 0.2268
   (`t9-s3560832`); the per-step drops are themselves shrinking (−0.0066 → −0.0020), so
   effect 2 is decelerating but has not stopped.

`derive_knobs.py` never consumed `cheapSearchProb` or `a07_moves_per_game_80` (§ 5b), so
nothing in the method fails here — only its **input** was measured in the wrong regime.

### 9.2 The lower bound is no longer a sampling bound

§ 1 evaluated every binding inequality at `r_lo = r·(1 − 1/√n)`. Over the 8000 games the
marginal rests on, that term is **1.12 %** — it bounds sampling error, and sampling error
is no longer the binding uncertainty. **Drift is.** So `r_lo` is taken from the observed
per-net trend instead:

* fit the nine **complete** post-transition real-net directories (`t9-s1166208` …
  `t9-s3560832`); least-squares slope **−0.1528 rows/game per accepted net** (the mean
  first-to-last step is −0.1517, so the fit is not leaning on one point);
* the newest directory `t9-s3860608` is **excluded from every fit as incomplete** — it is
  the net still playing and its npz files lag its own sgfs, which is exactly why the same
  18 035 rows read as 15.88 rows/game in the read-4 table (1136 games) and 17.34 in
  `rows_per_game.txt` (1040 games). Neither is a measurement of that net;
* carry the marginal **ten accepted nets forward**: `18.525 − 10 × 0.1528 = 16.997`.

Ten accepted nets is ≈ 31 cycles at the measured acceptance cadence (13 acceptances in 41
cycles) — several times the demonstrated monitoring interval (reads 1–4 spanned 7.7 h).
The horizon is a stated choice, not a hidden one, and the tool prints it.

### 9.3 Solving, at the marginal r and at r_lo

`E = 20 000`, `MAX_TRAIN_PER_DATA = 8`, `cap = 100 000`, `keep = 120 000`,
`min_rows = 25 000`, `batch = 128`, `r = 18.525`, `r_lo = 16.997`, `r0 = 31.4734`
(5000 production random-net games), `r0_lo = 31.028`.

* freshness (T1) `G ≥ 1.2·E/r = 1295.6` and `G ≥ 1.2·E/r_lo = **1412.0**` ← binding
* bootstrap (K5) `G ≥ min_rows/r0_lo = 805.7`

`G = ceil(1412.0)` → **1500**. At 1500: `27 787` rows/cycle, **+15.78 %** on `1.2·E`; at
`r_lo`, `25 495`, **+6.23 %**. The set survives any `r ≥ 24 000/1500 = 16.0`.

Every dependent inequality re-checked at both rates (`rederive_check.txt` block 3):

| # | constraint | at r = 18.525 | at r_lo = 16.997 | verdict |
|---|---|---|---|---|
| T1 | `G·r ≥ 1.2·E` | 27 787 vs 24 000 (+15.8 %) | 25 495 vs 24 000 (+6.2 %) | ok |
| K1 | bucket gain `≥ 0.99·E` | 222 299 (11.1 × E) | 203 962 (10.2 × E) | ok |
| K2 | `epochs = floor(min(gain, cap_eff)/E)` | **5** (gain 222 299 > cap_eff 100 000) | **5** | ok, unchanged |
| K2b | realised reuse `≤ 8` | 100 000/27 787 = **3.60** (was 5.40 at G = 1000) | 3.92 | ok |
| K3 | `keep > cap`, `keep ≥ epochs·E` | 120 000 > 100 000 ≥ 100 000 | same | ok, r-independent |
| K4 | window ≥ one epoch, every cycle | worst 25 000 rows = 195 batches vs 156 | same | ok |
| K5 | `G·r0_lo ≥ min_rows` | 47 210 ≥ 25 000 | 46 542 ≥ 25 000 | ok |
| K6 | `SWA = E//2` | 10 000 | 10 000 | ok, r-independent |
| K7 | cycle wall | 1410 s = 0.39 h, 182 cycles/link | same | ok |
| T3 | storage after one link | 23.37 GiB of 500 GiB | same | ok |
| T4 | threads ≤ CPUs | 28 ≤ 32 (measured `nlwp_max` 24) | same | ok, r-independent |

**`SHUFFLE_MINROWS` 25 000 is unchanged, and is not even consulted at link 2.** K4/K5 are
about the *first* cycle, whose window IS `min_rows` because `shuffle.py:1077` caps the
usable random rows there. Link 2 resumes an existing `BASEDIR` with 13 accepted nets and
956 527 rows on disk, so its shuffle window is **mature** — pinned at the
`SHUFFLE_KEEPROWS` ceiling of 120 000 rows, five times `min_rows`. `min_rows` is carried
through the check only because the check evaluates the whole ramp from cycle 1; it binds
nothing that link 2 does.

**`EPOCHS_PER_EXPORT` stays 5, and the formula is not what changed.** `floor(min(gain,
cap_eff)/E)` is 5 at both rates because `gain = G·r·8 = 222 299` clears `cap_eff = 100 000`
by 2.2×; `MAX_TRAIN_SAMPLES_PER_CYCLE` is what fixes it, not `G`. What DOES change is the
**realised export cadence**, which the window sets, not this formula: production ran 13
exports in 41 cycles (one per **3.15** cycles) with `Not enough data files to fill a
subepoch` in 40 of 41 cycles — the trainer is data-limited, not bucket-limited (`Exceeding
train bucket` fired once, longest run 1, against the R14 threshold of 3). Feeding 1.5× the
rows per cycle drives the window to the `keep` ceiling sooner; the simulated ramp reaches
one export per cycle at cycle 16 instead of 20. The steady state is the same at either
game count and is set by `keep`, not by `G`: a mature window is pinned at
`SHUFFLE_KEEPROWS = 120 000` rows = `floor(120 000/20 000) = 6` epochs' worth, capped at
`-max-epochs-this-instance = 5`, so a mature cycle runs five epochs and exports **exactly
once** — the K2c ceiling, reached sooner. `[OPEN]` the realised cadence at G = 1500 is a
prediction; the next monitoring read measures it.

**CPU / thread coupling unchanged**: `KTG_CPUS_PER_TASK = 32`, `KTG_NUM_GAME_THREADS = 18`.
Production measured `nlwp_max` 24 on gatekeeper AND selfplay (ppid-filtered, 40 cycles),
13 on train, 4 on shuffle — below the 25/28 § 4 projected and well inside 32. Game count
per cycle does not enter the thread budget: it is `-max-games-total`, a loop bound, not a
concurrency knob. This also settles § 8's second `[OPEN]`: the two-real-net gatekeeper
measures **24**, not the 28 the arithmetic projected.

### 9.4 Rates and projections, now from production

Measured over 41 cycles on l40s node gl111 (`throughput.json`):

| quantity | value | how it is formed |
|---|---|---|
| real-net selfplay | **5520.0 games/h** | 36 040 real-net games over the 37 cycle selfplay phases from cycle 6 (the first gate) on, 23 504.35 s |
| all-net selfplay | 6174.2 games/h | 41 040 games / 23 929.13 s — **not used**: it credits the 5 random-bootstrap cycles, which ran 1000 games in ~85 s each; every cycle from link 2 on is real-net |
| train | **1964.646 samples/s** | 3 860 608 samples / 1965.04 s |
| gate | **0.59638 s per gate game** | `stage_elapsed_s['gatekeeper']` 938.11 s / `gatekeeper_games_total` 1573 |
| shuffle | 4.26 s per cycle at 22 774 rows | `per_phase_stage['cycle2/shuffle']`, `selfplay_rows_total` over 42 cycle phases |
| bytes/row on disk | **366.27 B** | 350 347 842 B / 956 527 rows (the smoke's 353.8 was 3.5 % optimistic) |

Cycle wall at G = 1500: `978.3 s` selfplay + `50.9 s` train + `238.6 s` gate + `82.4 s`
shuffle + `60 s` export = **1410 s = 0.392 h**, so **182 whole cycles** fit one
`2-23:30:00` link (257 400 s). The directly measured production cycle is **0.199 h** at
G = 1000, and scaling only its selfplay term to 1500 games gives ~0.29 h; the model is
deliberately the more pessimistic of the two, because its gate term charges **every** cycle
for a two-real-net gate at the planning figure of 200 games, where production gates every
~2.8 cycles at ~121 games. The 0.5× planning derate of § 5 is **retired for a production
rate**: it was an allowance for a 20-game probe writing a multi-MB `logSearchInfo` log
outside a real cycle, and this rate is 37 real production cycles.

Storage at 366.27 B/row: per-cycle monotonic write **15.89 MiB** (tdata 9.70 + sgfs 3.33 +
one export 2.87), bounded steady state 557 MiB, so **23.37 GiB after a full 182-cycle
link** against `KTG_SCRATCH_HARD_BYTES = 500 GiB`, with 30 893 cycles of headroom.
`[OPEN]` the model under-counts: production actually grew `runs/p1` to 1 688 046 145 B in
41 cycles = **41.2 MiB/cycle**, 2.6× the model, and the mission root is 13.82 GB (2.6 % of
the cap). Even at 1.5× that rate a full link adds ~11 GB, so T3 holds by three orders of
magnitude either way; the discrepancy is a defect of the *model*, not a budget risk, and
belongs to `data_budget` / `measure_stage_throughput`.

### 9.5 The tooling gap read 4 hit, and its repair

Read 4 could not run the prescribed re-check at all:

```
$ python3 codes/eval/check_knobs_9x9.py --throughput $EV/throughput.json --rows-file $EV/rows_per_game.txt
check_knobs_9x9: .../throughput.json is missing the measured key(s)
per_phase_stage['cycle2/gatekeeper'].elapsed_s. …
exit 1
```

The key is absent because **under the admitted export ramp (o40) cycle 2 has no gatekeeper
stage** — the first candidate exports at cycle 5 and the first gate runs at cycle 6, which
production confirmed exactly. The checker had the smoke's cycle layout written into it as
a literal key name. That is a **structurally absent stage**, not a missing measurement, and
o41 was never about cycle numbers: it forbids substituting a *constant* for a number no job
produced. Repair, in `codes/eval/check_knobs_9x9.py`:

* `resolve_phase_elapsed()` / `cycle_phases()` — a stage is located by NAME across whatever
  cycles the file records: the preferred cycle when the file has it (so a smoke file reads
  exactly as before), else the earliest cycle it does have. A file with **no** such stage
  still exits naming the key.
* `resolve_gate_measurement()` — the gate needs a *consistent pair*, seconds and games over
  the SAME gates, or the s/game it feeds the projection is meaningless. Two layouts give
  one: `gatekeeper_games_total` with `stage_elapsed_s['gatekeeper']` (production, 1573
  games), or the smoke's single gate phase with the audit's `S4_gatekeeper_sgfs.lines`
  (156). Neither introduces a constant, and the older pairing — one gate phase's seconds
  against a game count from a different file — is now impossible to form by accident.
* `resolve_real_net_rate()` — a production file has no probe and its own
  `selfplay_games_per_hour` is all-net, which `derive_knobs.py` correctly refuses. The
  real-net rate is nevertheless in the file: the bootstrap cycles are the ones **before the
  first gate** (while `models/` is empty every cycle plays the random net, o40), and the
  split is cross-checked against the file itself — `random_games` ÷ bootstrap cycles must
  be a whole number of games per cycle, and it is (5000/5 = 1000, the games/cycle link 1
  ran). If it is not, the branch returns nothing and o41 exits.
* `selfplay_rows_total` is divided by the number of cycle selfplay phases the file records
  rather than by the smoke's hard-coded 2.
* `--marginal-nets K --trend-nets M --horizon-nets N` re-derive rows/game and its lower
  bound from the file's own `per_net` table (§ 9.1, § 9.2). Nothing is typed: the flags
  choose how many net directories to use, and the table, the marginal, the slope and the
  bound are all printed.
* `--knobs FILE` puts a candidate knob set under test without editing the file a queued
  chain link will source. The loop-default assertion is skipped for a non-live file and
  says so.
* `derive_knobs.py` gains `--rows-per-game-lower` / `--rows-lower-source`, refuses a bound
  above the measurement, and prints the bound's provenance on every run.

The **default, parameter-free** invocation is byte-for-byte unchanged in behaviour
(`rederive_check.txt` block 4: the frozen `-298712` / `-299259` evidence still gives a
3.11 h cycle and 23 cycles per link), and `derive_knobs.py --self-test` still passes all
14 cases including the seven o41 missing-key cases (block 2).

The repair is load-bearing, not cosmetic: with it, the checker **evaluates** the failure it
used to refuse. Block 5 runs the same production command against a `G = 1000` knob file and
exits 1 on `T1_freshness_rows_per_cycle_ge_1p2_E` / `T1_no_train_starvation` — the
arithmetic read 4 had to do by hand is now the tool's.

### 9.6 What does NOT move, and what is now open

Unchanged and re-asserted: `NUM_TRAIN_SAMPLES_PER_EPOCH` 20 000, `MAX_TRAIN_PER_DATA` 8,
`NUM_TRAIN_SAMPLES_PER_SWA` 10 000, `BATCHSIZE` 128, `SHUFFLE_MINROWS` 25 000,
`MAX_TRAIN_SAMPLES_PER_CYCLE` 100 000, `TAPER_WINDOW_SCALE` 50 000, `SHUFFLE_KEEPROWS`
120 000, `EPOCHS_PER_EXPORT` 5, `NUM_THREADS_FOR_SHUFFLING` 8, `KTG_CPUS_PER_TASK` 32,
`KTG_NUM_GAME_THREADS` 18.

- `[OPEN]` **the drift has not stopped.** At −0.1528 rows/game per accepted net the marginal
  reaches 16.0 — where T1 fails again at 1500 games — after ~16.5 further accepted nets,
  ~52 cycles. 1500 buys a *monitored horizon*, not a settled answer. Re-run the
  `--marginal-nets` command at every monitoring read; re-derive when the marginal crosses
  ~17.0. Buying freshness with ever more games is a treadmill, and the structural fix —
  lower `E`, or raise `min_rows` and let the window carry the freshness — belongs to
  `scale_data_window`, which this section is also recorded against.
- `[OPEN]` the realised export cadence at G = 1500 (predicted better than one per 3.15
  cycles, bounded by 5/6 per cycle) is measured at the next read.
- `[OPEN]` the storage model under-counts production by 2.6× (§ 9.4). Not a budget risk;
  owned by `data_budget` / `measure_stage_throughput`.
- `[CLOSED 2026-09-05]` § 8's two-real-net gatekeeper thread count: measured 24 over 15 gate
  stages, against the 28 the arithmetic projected. `[CLOSED 2026-09-05]` § 8's real-net
  games/hour and train samples/s: 5520.0 and 1964.646 over 41 production cycles, replacing
  the 100-probe-game and single-probe figures.
- `[OPEN]` link 1 (job 301099) keeps `NUM_GAMES_PER_CYCLE = 1000` to its end — it sourced
  `knobs_9x9.env` once at link start (`loop.sbatch:170-193`, `set -a`). The new value takes
  effect when link 2 (job 305318, `PENDING afterany:301099`) sources the same file. Nothing
  in the loop reads the game count from run state, so there is no migration: the count is
  passed straight to `katago selfplay -max-games-total`
  (`synchronous_loop_9x9.sh:372`), and `.cycles_completed` / `.chain_depth` / `.failcount` /
  `STOP` carry no per-cycle game count. The `${VAR:-default}` fallback in
  `synchronous_loop_9x9.sh:147` was moved 1000 → 1500 in the same commit so the two stay
  equal (`check_knobs_9x9.py` asserts it); the substitution is byte-length neutral and was
  applied by writing a new file and renaming, so the running link's open descriptor is
  untouched.


## 10. Second re-derivation the same day — OPTION C, 2026-09-05 (`NUM_GAMES_PER_CYCLE` 1500 → 1800, `NUM_TRAIN_SAMPLES_PER_EPOCH` 20 000 → 16 000)

Authorised by `mission.json` `decisions` (human, 2026-09-05): *link 2 onward runs OPTION C*.
The options were prepared under node `scale_data_window`
(`../scale_data_window/o47_options.md`, obligation `o47_rows_per_game_drift_rederive_at_17`)
and this section records the application. CPU only, login node, no allocation, no job.
Verbatim output: `../scale_data_window/check_applied_C_live.txt` (production inputs),
`../scale_data_window/check_applied_C_smoke.txt` (the parameter-free run against the frozen
smoke evidence), `../scale_data_window/derive_knobs_self_test.txt`,
`../scale_data_window/boundary_check.txt`. Chain link 1 (job 301099) was NOT touched.

### 10.1 Why the 1500 set did not survive the day

Two further monitoring reads measured the marginal and, crucially, re-fitted the SLOPE:

| read | cycles | marginal r | fitted slope /accepted net | 10-net bound r_lo |
|---|---|---|---|---|
| 4 | 41 | 18.525 | −0.1528 | 16.997 |
| 5 | 61 | 17.7235 | −0.1070 | 16.6532 |
| 6 | 65 | 17.1736 | **−0.1742** | 15.4318 |

The marginal fell 17.7235 → 17.1736 in ~33 minutes (two accepted nets) and the slope
steepened 1.6×. At read 6's bound the staged set fails the tolerance it was derived to
satisfy:

| set | rows/cycle at r | vs 1.2·E | at r_lo | vs 1.2·E |
|---|---|---|---|---|
| link 1, G = 1000, E = 20 000 | 17 173.6 | −28.44 % | 15 431.8 | −35.70 % |
| staged, G = 1500, E = 20 000 | 25 760.4 | +7.33 % | 23 147.7 | **−3.55 % FAILS** |
| option C, G = 1800, E = 16 000 | 30 912.5 | +61.00 % | 27 777.2 | +44.67 % |

### 10.2 The whole-file epoch measurement, and what it does to the reading of T1

`../scale_data_window/epoch_granularity.txt`, read out of `logs/loop-301099.log` and the
live `shuffleddata` directory:

* the shuffle writes the kept sample as `round(SHUFFLE_KEEPROWS/70000)` = 2 output files
  (`shuffle.sh:48 -approx-rows-per-out-file 70000`, `shuffle.py:406-412`); measured
  60 136 + 59 864 = 120 000 rows exactly;
* `get_files_for_subepoch` (`train.py:1306-1345`) takes WHOLE files — its probabilistic skip
  at `:1332` requires `batches_to_use_so_far > 0`, which a first file of 467 batches never
  allows — so an epoch trains one whole file: measured `Global step` 6 557 440 → 6 617 216 →
  6 677 248, i.e. 467 and 469 batches against the nominal `round(E/128)` = 156;
* the third epoch of each cycle finds no unused file (`-no-repeat-files`,
  `training_data_generator.py:35`) and exits 0 (`train.py:1487-1489`). 174 epochs started,
  62 aborted there, 22 exports in 62 cycles.

Therefore **samples per cycle = `SHUFFLE_KEEPROWS`**, not `EPOCHS_PER_EXPORT × E`, and the
reuse the loop really applies is

    rho = SHUFFLE_KEEPROWS / (G · r)          — E cancels out of it

At the read-6 marginal: 6.99 at link 1's G = 1000 (**87 % of the `MAX_TRAIN_PER_DATA` cap of
8**, and 7.78 at its own 10-net bound), 4.66 at G = 1500, **3.88** at G = 1800. This is the
measured mechanism behind the value-loss drift reported from read 5 (vloss 0.568837 →
0.592790 while `p0loss` 3.603458 → 1.844065): the value target is per GAME, so the samples
drawn from one game over its window residence are `SHUFFLE_KEEPROWS / G`, independent of r —
120 through all of link 1, 80 at G = 1500, 66.7 at G = 1800. Lowering E does not enter it.

Honest decomposition of option C's +61.00 %: raising G moves the NUMERATOR
(−28.44 % → +28.80 % against the unchanged 24 000 threshold) and lowering E moves the
THRESHOLD (24 000 → 19 200, +28.80 % → +61.00 %). About half the headline gain is the test
getting easier, not the run getting more data. The E half is justified elsewhere — the SWA
horizon and the metrics floor, § 10.3 — not by T1.

### 10.3 The four values, and why the other seven do not move

| knob | old | new | why |
|---|---|---|---|
| `NUM_GAMES_PER_CYCLE` | 1500 | **1800** | smallest hundred with `G·r_lo ≥ 1.2·(1.2·E_old)` = 28 800 at read 5's bound 16.6532 — a bound stated against the OLD epoch so it constrains data per cycle, i.e. `rho ≤ 120000/28800 = 4.167`, not tolerance headroom |
| `NUM_TRAIN_SAMPLES_PER_EPOCH` | 20 000 | **16 000** | = 125·`BATCHSIZE`; keeps 25 batches (20 %) over the 100-batch metrics floor (`train.py:1379`, `:1661`), where 12 800 keeps none |
| `NUM_TRAIN_SAMPLES_PER_SWA` | 10 000 | **8 000** | `= E//2` (`train.py:441`) — mechanical. With `swa_scale` 8 (`:443`) the export is an EMA over ~4·E samples: 80 000 → 64 000. Taking E to 12 800 would have cut it to 51 200, i.e. less regularisation on the head that is drifting — the reason 12 800 was rejected |
| `MAX_TRAIN_SAMPLES_PER_CYCLE` | 100 000 | **80 000** | `= 5·E`, upstream's own cap/epoch ratio (`:64`/`:59`) — mechanical |
| `SHUFFLE_KEEPROWS` | 120 000 | 120 000 | deliberately NOT scaled with the cap. `K3` needs only `keep > cap` and `keep ≥ epochs·E` (120 000 > 80 000 ≥ 80 000), and by § 10.2 this knob is what a cycle actually trains: lowering it would cut training volume and, below ~98 000, collapse the sample to one output file and halve the export cadence |
| `SHUFFLE_MINROWS` | 25 000 | 25 000 | binds only a cycle-1 random bootstrap. The requirement is `min_rows/batch ≥ round(E/batch)`: 195 ≥ 125, ratio 1.56 (it was 1.25). Tracking it to 1.25·E = 20 000 would only shrink a margin nothing needs |
| `EPOCHS_PER_EXPORT` | 5 | 5 | `floor(min(gain, cap_eff)/E)` = `floor(min(247 300, 80 000)/16 000)` = 5 at r and at r_lo |
| `MAX_TRAIN_PER_DATA`, `BATCHSIZE`, `NUM_THREADS_FOR_SHUFFLING`, `TAPER_WINDOW_SCALE`, `KTG_CPUS_PER_TASK`, `KTG_NUM_GAME_THREADS` | — | unchanged | no constraint on them moved |

### 10.4 Projections at the read-6 rates

Measured over 65 cycles, job 301099 on l40s/gl111: real-net selfplay 6429.7 games/h
(60 904 games over 61 real-net cycle phases, 34 100.39 s), train 2119.650 samples/s
(6 857 216 samples / 3235.07 s), gate 0.48678 s per gate game (1541.13 s / 3166 games),
350.92 B/row.

* cycle wall = 1008 s selfplay + 38 s train + 195 s gate + 84 s shuffle + 60 s export
  = **1384 s = 0.385 h** → 185 whole cycles inside the declared 257 400 s, 61 inside the
  granted 84 600 s of link 2. `[PRELIMINARY]` The directly measured cycle is 0.1758 h at
  G = 1000; the measured-basis extrapolation to this set,
  `3600·1800/6429.7 + 120000/2119.65 + 109.8` = 1174 s = 0.326 h, is the optimistic bound and
  the truth lies between the two.
* storage = 17.12 MiB/cycle monotonic + 551.9 MiB bounded → 23.63 GiB after a full
  185-cycle link against the 500 GiB cap; 28 682 cycles of headroom.

### 10.5 Verification actually run

    python3 codes/eval/check_knobs_9x9.py \
      --throughput evidence/production_chain/throughput.json \
      --rows-file  evidence/production_chain/rows_per_game.txt \
      --marginal-nets 3 --trend-nets 9 --horizon-nets 10        -> CHECK_KNOBS_9X9: PASS, exit 0
    python3 codes/eval/check_knobs_9x9.py                        -> CHECK_KNOBS_9X9: PASS, exit 0
    python3 codes/eval/derive_knobs.py --self-test               -> SELF-TEST: PASS, exit 0

The first run's `LOOP DEFAULT WIRING` block asserts all eleven `${VAR:-default}` values of
`synchronous_loop_9x9.sh` against the knob file, including
`NUM_GAMES_PER_CYCLE loop default 1800 == derived 1800` and
`NUM_TRAIN_SAMPLES_PER_EPOCH loop default 16000 == derived 16000`.

### 10.6 Open items after this move

- `[OPEN]` **the slope is not stable** — it went −0.1070 → −0.1742 in one read. Obligation
  `o48_rows_per_game_drift_rederive_at_13` re-arms at marginal r = 13.0, which is above the
  12.409 at which this set's own 10-net bound stops clearing `1.2·E/G` = 10.667, so the
  trigger fires with margin. That is 24.0 accepted nets at read 6's slope, 39.0 at read 5's.
  Every monitoring read must recompute the SLOPE, not only the marginal.
- `[OPEN]` `[FUTURE]` the untried structural lever is `shuffle.sh:48
  -approx-rows-per-out-file` together with `SHUFFLE_KEEPROWS`: a smaller out file would make
  `NUM_TRAIN_SAMPLES_PER_EPOCH` operative again and let the export cadence be set
  deliberately instead of falling out of a file count. Owner `scale_data_window`; it changes
  a shipped script, not a knob, so it needs its own packet.
- `[OPEN]` the realised cycle wall and export cadence at G = 1800 / E = 16 000 are measured
  at the first link-2 monitoring read, which also verifies that the log line reads
  `loop knobs … (sha256 ba7f1bf7e1bc166d)` — neither `5ae53587` (link 1) nor `3504a8ea` (the
  staged 1500 file that no link consumed).
- `[OPEN]` the storage model still under-counts production (29.2 MiB/cycle measured against
  17.12 projected). Not a budget risk; owned by `data_budget` / `measure_stage_throughput`.
- `[CLOSED 2026-09-05]` `o47_rows_per_game_drift_rederive_at_17` — the trigger response is
  applied here.
- `[OPEN]` link 1 (job 301099) keeps `NUM_GAMES_PER_CYCLE = 1000` to its end, for the reason
  in § 9's last bullet. Both files were changed by writing a new file and renaming, so the
  running link's open descriptors are untouched; `synchronous_loop_9x9.sh` kept mode 0755.
