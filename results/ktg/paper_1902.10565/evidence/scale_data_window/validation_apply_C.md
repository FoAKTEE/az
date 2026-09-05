# Validation — `arxiv-1902.10565::scale_data_window` / `derive_cycle_knobs_9x9`, knob option C APPLIED (refuter, then judge)

Candidate: `evidence/scale_data_window/candidate_rows_apply_C.json` at worker commit `ff5d0eb` (`fix(knobs,ktg)!`),
knob file `codes/loop/knobs_9x9.env` sha256 `ba7f1bf7e1bc166d…`, loop script `synchronous_loop_9x9.sh` sha256
`10d195ff6ef764c1…`. Authority for the VALUES: `mission.json` `decisions[-1]` (human, 2026-09-05, "link 2 onward runs
knob option C"). Validator: cross-model, `CHANDRA_ROLE=validator`, login node, CPU only, no job, no allocation;
`runs/p1` and `logs/loop-301099.log` were READ and never written; the `KTG_STAGE_ONLY=1` dry runs staged into the
validator's scratchpad, not into `runs/p1` (its `scripts/dated/` still holds only `20260904-185225`). Clock at the
start: 2026-09-05 06:36 EDT; link 1 (job 301099) RUNNING on gl111, 11:38 left; link 2 (job 305318) PENDING
`afterany:301099`, TimeLimit 23:30:00. `mission.json` `compute.policyCheck` (the policy script named there)
is not invoked: no allocation is requested by this validation.

Every number below was recomputed from the per-net table, the selfplay directories, the production log and the
reference code; nothing was taken from the worker's figures on trust.

## 0. Link-2 safety — FIRST

**No defect was found that would harm link 2.** Checked, each by execution:

* `loop.sbatch:170` `KNOBS_ENV="${KTG_KNOBS_ENV:-$KTG_CODES/loop/knobs_9x9.env}"`, `:176-179` counts stray
  classification knobs (`KTG_MAX_FAILS|KTG_MAX_CHAIN|KTG_MIN_RUNTIME_SECONDS` → **0** in the new file), `:186-192`
  hashes and sources it ONCE with `set -a; . "$KNOBS_ENV"`, before the cycle loop and before `bash "$LOOP_SH"` at `:820`.
  There is no second sourcing; `synchronous_loop_9x9.sh` reads the eleven knobs only through its `${VAR:-default}`
  block (`:155-170`) and the two consumers `:380` (`-max-games-total`) and `:404` (`-samples-per-epoch`,
  `-swa-period-samples`, `-max-train-bucket-size`). `resubmit()` passes no `--export`, so Slurm's `--export=ALL`
  carries link 1's exported 1000-game values into link 2's environment — harmless, because `:189` re-sources the file
  and overrides them at link start.
* Link 1 logged `loop knobs … (sha256 5ae5358791974ae1)` at `loop-301099.log:7`; the file is now `ba7f1bf7e1bc166d`.
  The running bash holds the old values in memory and the pre-rename inode of the loop script; nothing it reads again
  changed. `squeue`: 301099 RUNNING, 305318 PENDING afterany.
* `bash -n codes/loop/synchronous_loop_9x9.sh` → exit 0; `bash -n codes/loop/loop.sbatch` → exit 0; mode `755`.
* `git diff ff5d0eb^ ff5d0eb -- synchronous_loop_9x9.sh` touches only the `${VAR:-default}` lines of the four moved
  knobs (1500→1800, 20000→16000, 10000→8000, 100000→80000) and comments; no control flow changed.
* `KTG_STAGE_ONLY=1` dry run from the REAL scratch clone (`$KATAGO_SRC` = `…/build/KataGo` @ `fd0723fd`), `bash <script>`
  form, once with the pre-commit script (`git show ff5d0eb^:…/synchronous_loop_9x9.sh`) and once with HEAD:
  both `STAGE_EXIT=0`, both stage 87 files / 28 882 815 bytes, and the two sha256 manifests are **byte-identical**
  (`diff manifest_before manifest_after` exit 0). The knob values are not part of the staged archive, so identical
  staging is the expected outcome and the only behavioural difference between the two scripts is the four values.
* Resume semantics at the new values, read from `train.py`: the bucket cap becomes `max(80000, 16000)` (`:1257`) and
  an over-full level is clipped to it; `swa_sample_accum` persists in `train_state` (`:981`) and is compared against
  the new `swa_period_samples` 8000 (`:1725`) — a one-time early SWA snap at most; `export_cycle_counter` and
  `EPOCHS_PER_EXPORT` are unchanged; no run-state file carries a game count or an epoch size. Nothing migrates.

## 1. Inputs re-hashed

All fourteen `evidence_files` entries of `candidate_rows_apply_C.json` re-hash to the recorded sha256 (0 mismatches).
Validator transcripts: `check_live_validator.txt` sha256 `4e184507bce18309…` — **byte-identical to the worker's
`check_applied_C_live.txt`** (same hash), `check_smoke_validator.txt` `6aee93135aaecc82…` (identical to
`check_applied_C_smoke.txt`), `check_control_1500.txt` `bbec909ceeb43231…`. Tools: `check_knobs_9x9.py`
`04c8a076ceed3fbf…`, `derive_knobs.py` `d9ff5a014ac8a301…` (both unchanged since the previous validation).

## 2. Refutation attempts

### 2.1 The whole-file epoch claim (task item 1) — CONFIRMED from code and from the live log

`train.py:1306-1345` `get_files_for_subepoch`: `num_batches_per_subepoch = round(E/128)/sub_epochs`; the loop peeks a
file, and the only way to take LESS than a whole file is the probabilistic skip at `:1332`, guarded by
`batches_to_use_so_far > 0`. With `batches_to_use_so_far == 0` the first file is always popped whole (`:1337-1339`)
and, since 467 ≥ 125 (or 156), `found_enough` is set at `:1343`. So an epoch = one whole output file whenever a file
holds more batches than `round(E/128)`. `shuffle.py:406-412` `compute_buckets_and_out_files`:
`num_buckets = max(round(approx_rows/approx_rows_per_bucket),1)` with `shuffle.sh:48 -approx-rows-per-out-file 70000`
→ `round(120000/70000) = 2` files. Measured in `shuffleddata/20260905-055426/train/`: `{"num_rows": 60136}` +
`{"num_rows": 59864}` = 120 000 = `SHUFFLE_KEEPROWS` exactly (worker's transcript; directory since pruned by age).

Live log `logs/loop-301099.log` (58 052 lines at the read; link 1 at 69 cycles):
```
Global step: 7156736 -> 7216384 -> 7276672 samples     (= 59648 = 466 batches; 60288 = 471 batches)
Global step: 7276672 -> 7336448 -> 7396480 samples     (= 59776 = 467 batches; 60032 = 469 batches)
Consuming 20000 rows from train bucket (100000 -> 80000) / (80000 -> 60000) / (60000 -> 40000)   x3 per cycle
BEGINNING NEXT EPOCH: 189   Not enough data files to fill a subepoch! Quitting.: 67   SAVING MODEL FOR EXPORT: 24
Exceeding train bucket, not enough new data rows, terminating: 1   (line 712, the ramp)
swa_period_samples 10000.0   (train.py:1003, every train instance of link 1)
```
Three bucket debits of E per cycle, two completed epochs of ~60 000 samples each, the third exits 0 on the file
check — exactly the worker's reading (his 174/62/22 have grown to 189/67/24 with the seven further cycles). So
**samples/cycle = SHUFFLE_KEEPROWS = 120 000, and ρ = KEEPROWS/(G·r), E cancels.** Recomputed at the read-6 marginal
17.1736: ρ = **6.99** at G = 1000 (link 1), 4.66 at 1500, **3.88** at 1800; at the 10-net bound 15.4318: 7.78 / 5.18 /
4.32. Samples drawn per game over its window residence = KEEPROWS/G = 120 / 80 / 66.7. All reproduce.

### 2.2 Marginal, slope, every K/T inequality, and the 1500 control (task item 2) — REPRODUCED; control FAILS as claimed

From `throughput.json` `per_net`, complete real-net directories sorted by training step, newest excluded:
marginal over the last three = (52080 + 34466 + 50843) / 8000 = **17.1736**; least-squares slope over the last nine =
**−0.1742** rows/game per accepted net; r_lo = 17.1736 − 1.742 = **15.4318**. Independent arithmetic (validator's own
Python, not the tool):

| set | rows/cycle at r | vs 1.2·E | at r_lo | vs 1.2·E | ρ (ρ at r_lo) |
|---|---|---|---|---|---|
| link 1, G 1000, E 20 000 | 17 173.6 | −28.44 % | 15 431.8 | −35.70 % | 6.99 (7.78) |
| staged, G 1500, E 20 000 | 25 760.4 | +7.34 % | 23 147.6 | **−3.55 % FAILS** | 4.66 (5.18) |
| applied, G 1800, E 16 000 | 30 912.5 | +61.00 % | 27 777.2 | +44.67 % | 3.88 (4.32) |

Tool runs from the az root:
```
$ python3 …/check_knobs_9x9.py --throughput …/throughput.json --rows-file …/rows_per_game.txt --marginal-nets 3 --trend-nets 9 --horizon-nets 10
  marginal r    = 17.1736   … 137389 rows / 8000 games
  lower bound   = 15.4318   … -0.1742 rows/game per accepted net
  ok   K1 … gain 247300.2 (222217.4) vs 0.99*E = 15840.0
  ok   T1_freshness … 30912.5 (27777.2) vs 1.2*E = 19200.0; ratio 1.932 (1.736)
  ok   K2 … epochs 5 (5); cap_eff 80000; effective reuse 2.59 (2.88) <= 8.0     ok K2b  ok K3 120000 > 80000 and >= 80000
  ok   K5 … 56652.1 (55850.9) >= 25000     ok K4 … 25000 rows = 195 batches >= 125     ok K2c     ok K6 swa 8000
  ok   T4 … 28 <= 32     ok K7 … 1384 s = 0.38 h, 185 cycles / 257400 s     ok T3 … 23.63 GiB of 500 GiB
  ok   T1_no_train_starvation  ok T2_bucket_holds_batches  ok T3  ok T4
  LOOP DEFAULT WIRING: 11/11 ok, incl. NUM_GAMES_PER_CYCLE 1800 == 1800, NUM_TRAIN_SAMPLES_PER_EPOCH 16000 == 16000,
                       NUM_TRAIN_SAMPLES_PER_SWA 8000 == 8000, MAX_TRAIN_SAMPLES_PER_CYCLE 80000 == 80000
  CHECK_KNOBS_9X9: PASS                                                                            exit 0
$ … same arguments, --knobs <git show ff5d0eb^:…/knobs_9x9.env>   (sha256 3504a8ea… = the staged 1500 file)
  FAIL T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 25760.4 (lower90 23147.6) vs 1.2*E = 24000.0
  FAIL T1_no_train_starvation
  CHECK_KNOBS_9X9: FAIL ['T1_freshness_rows_per_cycle_ge_1p2_E', 'T1_no_train_starvation']                exit 1
$ python3 …/check_knobs_9x9.py            -> CHECK_KNOBS_9X9: PASS   exit 0   (frozen smoke evidence)
$ python3 …/derive_knobs.py --self-test   -> SELF-TEST: PASS         exit 0
```
The worker's statement "the 1500/20000 set fails T1 at the horizon" is confirmed by the tool itself, and the PASS at
option C is confirmed with the wiring block asserting all eleven loop defaults.

**Out of sample.** Recounted read-only from `runs/p1/selfplay/<net>/` (npz header shape × sgf lines) at 06:41 EDT,
one net accepted since read 6: `t9-s6857216-d1384386` 2000 games / 34 075 rows = **17.0375** against the
linear-from-marginal prediction 17.1736 − 0.1742 = 16.9994 — above it by 0.038. New marginal (s6257664, s6557440,
s6857216) = 17.0549; refit 9-net slope **−0.1828** (steeper again, +5 %); r_lo 15.2267 → option C still clears T1 at
r_lo by 1800 × 15.2267 = 27 408 ≥ 19 200 (+42.8 %). The newest directory `t9-s7156736` reads 11.93 over 1857 games
with its npz lagging its sgfs — the reason the newest directory is excluded, again confirmed.

### 2.3 Honesty of "+61 %" and the operative effect of E (task item 3) — DECOMPOSITION CORRECT; ONE NARROWING

The decomposition reproduces: at the unchanged 24 000 threshold, G 1000→1800 moves the margin −28.44 % → +28.80 %;
E 20 000→16 000 moves the threshold to 19 200 and the margin to +61.00 %. Against the link-1 baseline the threshold
share is 32.2 of 89.4 points (36 %); against the staged 1500 set (+7.34 %) it is 32.2 of 53.7 points (**60 %**). "About
half" is a fair one-word summary of both; the rows carry the exact numbers and the candidate never uses +61 % without
the decomposition. Accepted.

Operative effect of E under whole-file consumption, from the code: (i) epoch size — none (467 ≥ 125, §2.1); (ii)
metrics floor — none (`floor(467/100)` = 4 lines per epoch either way; `train.py:1379,1661`); (iii) bucket — none
(3 × 16 000 = 48 000 debited from an 80 000 cap refilled by 247 300/cycle; never limits, one "Exceeding" line in 69
cycles, at the ramp); (iv) **SWA/EMA horizon — the ONLY operative effect**: `swa_period_samples = E//2 = 8000`
(`:441`), `ema_avg` with factor 1/8 (`:816-818`), snap every 8000 samples (`:1725-1728`) → the exported net averages
over ~8 × 8000 = 64 000 samples where link 1 averages over 80 000. **Narrowing N1:** the candidate justifies the E half
"by the SWA horizon and the metrics floor". The metrics floor is inert (ii), and the SWA argument only explains why
16 000 was preferred over 12 800 (64 000 vs 51 200) — the move 20 000 → 16 000 itself SHORTENS the EMA horizon by 20 %,
i.e. in the direction the worker's own value-head reasoning calls unfavourable. The admitted row states this plainly:
the E change is a tolerance re-statement plus a 20 % shorter export EMA, nothing more; it changes neither samples/cycle
nor ρ nor the export cadence. Not a link-2 hazard (a 64 000-sample EMA is still 6.4 × the swa_scale minimum and 4 × E).

### 2.4 The o48 trigger (task item 4) — THE SLOPE-RECOMPUTE WORDING IS PRESENT; THE FIXED 13.0 IS NOT SUFFICIENT ALONE

The candidate's o48 statement does say, in clause (a), that "its marginal, SLOPE and verdict are recorded … the SLOPE
explicitly, because a re-armed trigger computed from a stale slope is worthless" — verified verbatim. But the trigger in
clause (b) is the fixed threshold 13.0, chosen as "above the 12.409 failure point". The failure point is
`1.2·E/G + 10·|slope|` = 10.667 + 10·|slope|, so it MOVES with the slope: 12.409 at −0.1742 (read 6), 12.495 at −0.1828
(this recount), and it reaches **13.0 at |slope| = 0.2333** — a further 28 % steepening from today's slope, when the
slope has already steepened 63 % (reads 5→6) and 5 % (read 6→now) in consecutive reads. A fixed 13.0 therefore fires
BEFORE the failure only while |slope| < 0.2333, which nothing guarantees. **Narrowing N2 (wording amended by the
validator):** o48(b) fires at the FIRST monitoring read where EITHER the marginal ≤ 13.0 OR the refit 10-net lower
bound `r_lo = r + 10·slope` ≤ 1.1 × 1.2·E/G = 11.733 (T1 lower-bound margin below +10 %), whichever comes first, the
slope refit at that read. At today's slope the second condition fires at r ≤ 13.56, i.e. before 13.0; at any slope
steeper than −0.2333 it is the only condition that fires in time. ρ reaches the cap 8 at r = 120000/(8·1800) = 8.33,
below both triggers, so the ρ watch is a reporting duty, not a second trigger.

### 2.5 Scripts, mode, dry run, sourcing (task item 5) — ALL CONFIRMED (details in §0)

`bash -n` exit 0; mode 0755; dry run exit 0 with byte-identical staging before/after; `loop.sbatch` sources the file
once at link start with 0 stray classification knobs.

### 2.6 Things looked for and NOT found

* Circular evidence: the result row's verification command reads `throughput.json` / `rows_per_game.txt` produced by
  `measure_stage_throughput` and the knob file produced by this node; the checker itself is unchanged since the prior
  admission (hash above). No row cites itself.
* Hidden `[OPEN]` items promoted: the candidate result stays `conditional` (no cycle has run at C) — correct; the
  knowledge rows are appended `preliminary`, not `solid`.
* A 20-net horizon: r − 20·0.1742 = 13.69 > 10.667 — option C survives it (the 1500 set did not survive 10).
* DESIGN.md §§ 2/6/8/9 read for stale 1500 statements: § 2 carries the 1800/16 000 set with the decomposition, § 8 adds
  R19 with its signature and the `[FUTURE]` lever, § 9 records the decision; the "1500" occurrences are historical
  ("supersedes the 1500 set") — none is a live claim.

## 3. Verdict — ADMIT (conditional), with narrowings N1-N2 and one new obligation

No gate fails. Gate 3 (evidence matches type): symbolic derivation over production measurements + executed arithmetic
check, status `conditional` — matched. Gate 4 (units/regimes): the horizon is stated per accepted net, the marginal per
8000 games, ρ dimensionless — consistent. Gate 6 (protocol/artifacts): commands, hashes and transcripts recorded; the
uncertainty is stated as a drift horizon, not a sampling bound. Gate 7: no `[OPEN]` on a checked path (nothing is
`checked`).

Appended with `CHANDRA_ROLE=validator`:
* result `r_cycle_knobs_9x9_derived` AMENDED (iteration 5, `conditional`), verification = the production checker, gate
  exit 0 required at append;
* claim ledger: `o47_rows_per_game_drift_rederive_at_17` → **discharged** by `r_cycle_knobs_9x9_derived` — its clause (b)
  (re-derive before link 2 sources the file, every K/T re-checked at the new marginal and drift bound) is met
  pre-emptively at 17.17, before the 17.0 crossing (now 0.05 away); its clauses (a) and (c) cannot be met before link 2
  runs and (c) names a 1500-game set that no longer exists, so both are carried VERBATIM in intent into o48;
  `o48_rows_per_game_drift_rederive_at_13` opened (blocking) with the N2 slope-aware trigger;
  `o49_out_file_size_makes_epoch_operative` opened (non-blocking, `scale_data_window`) for the untried structural lever
  `shuffle.sh:48 -approx-rows-per-out-file` with `SHUFFLE_KEEPROWS`;
* knowledge nodes `derive_cycle_knobs_9x9` and `scale_data_window` re-appended `preliminary`;
* error ledger: one `validation` / `pass` trial row for this review;
* views `decomposition/{claims,obligations,assumptions,results}.md` re-rendered from the ledgers.

## 4. Remaining `[OPEN]` after this admission

* o48 — every link-2 monitoring read: marginal, refit SLOPE, verdict, ρ; re-derive on the N2 trigger.
* o49 — the structural lever (out-file size) that would make E operative and set the export cadence deliberately.
* r_cycle_knobs_9x9_derived stays `conditional` until the first link-2 read measures a cycle at 1800 / 16 000 (rows/
  cycle, ρ, cycle wall, export cadence, and the log line `loop knobs … (sha256 ba7f1bf7e1bc166d)`).
* The c10 restatement (a band on the MARGINAL with a drift clause) is still owed; not transitioned here.
* Storage model under-count (29.2 vs 17.12 MiB/cycle) — `data_budget` / `measure_stage_throughput`; T3 unaffected.

## 5. Rows appended (all `actor_role: validator`, no admission flags; gate ran the checker at append, exit 0)

```
result    r_cycle_knobs_9x9_derived (iteration 5, conditional)   e7b6a14a5646b818c6480be93e0bd4fcd5d6afe1ffff528c706ce4ba21252f56
claim     o47_rows_per_game_drift_rederive_at_17  discharged     cdf2a533cb73be5f4e1a0026b33327e3787d7b67d5238ce4e7e61251d309b40d
claim     o48_rows_per_game_drift_rederive_at_13  open           049b10806b0034c158a6170c6bd0160bd02e091c454952e8e0b2afdca6b81dcc
claim     o49_out_file_size_makes_epoch_operative open           80bbc3a8d0e247313522078c88fcf66c795b161283b41af9ba13006bc778b638
knowledge arxiv-1902.10565::derive_cycle_knobs_9x9 preliminary   a00b9bccd1f863291173d9123b42d713b32e289db89565395cf4ab9e31db3250  (node_seq 6)
knowledge arxiv-1902.10565::scale_data_window      preliminary   a7070604f717210946046bbcb186ef8e927769177dfcf5598477fd3cf087019e  (node_seq 2)
error     scale_data_window iteration 3, validation, pass         261cb6643429eb1bdcfe716afab580efab895a0971f62df085ff51983254bd38
```
