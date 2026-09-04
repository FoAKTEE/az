# Validation — `arxiv-1902.10565::derive_cycle_knobs_9x9` (refuter, then judge)

Candidate: `evidence/derive_cycle_knobs/candidate_rows.json` at commit `375cfc0`, produced by a
worker on a different model. Validator: cross-model, `CHANDRA_ROLE=validator`, login node, CPU only,
no job. Everything below was recomputed from the measured JSON and the cited upstream lines with the
validator's own arithmetic; nothing was taken from the worker's numbers on trust.

## 1. Inputs re-hashed

`sha256sum` on the login node reproduces every hash in `candidate_rows.json.measured_inputs_read`
(`rows_per_game-298712.txt daed88ef…`, `throughput_smoke-298712.json 927fb04c…`,
`nlwp_max-298712.txt c1538342…`, `audit-298712.json 646e4ef1…`, `throughput_smoke-299259.json d91e7920…`,
`audit-299259.json 6968eb12…`, `budget.env 6f38681e…`). Deliverables at HEAD:
`knobs_9x9.env b6d9102f…`, `synchronous_loop_9x9.sh 3967fd93…`, `evidence/knobs/derivation.txt 2e3722f5…`,
`evidence/derive_cycle_knobs/derivation.md e4cbbf7a…`.

## 2. Refutation attempts

### 2.1 Every upstream citation re-read (v1.18.2 @ fd0723fd)

All resolve to what the derivation says they say: `train.py:441` (swa default `E//2`), `:972`
(fresh bucket = `E`), `:1256-1259` (bucket fill and `cap = max(max_train_bucket_size, E)`), `:1303-1346`
(`get_files_for_subepoch` returns `None` below `round(E/batch)` batches), `:1379`
(`print_train_loss_every_batches = 100`), `:1423` (`max_epochs_this_instance`), `:1434-1445`
(epoch gated on `bucket > 0.99 E`, `-stop-when-train-bucket-limited` breaks), `:1487-1488`
(`-quit-if-no-data` -> `safe_exit(0)`, no export), `:871/:975/:1743/:1831` (persistent
`export_cycle_counter`); `shuffle.py:414-435` (window), `:1058/:1077` (random rows capped at
`min_rows`), `:1090` (exit 0 below `min_rows`), `:1331` (`range` = all rows incl. random, which is what
`train.py:1241-1249` turns into bucket fill); `shuffle.sh:44-45,48`; `synchronous_loop.sh:57-66`;
`setup.cpp:126`, `gatekeeper.cpp:548-553`, `selfplay.cpp:359-364`, `selfplaymanager.cpp:156`. The loop
copy passes `-epochs-per-export "$EPOCHS_PER_EXPORT" -max-epochs-this-instance "$EPOCHS_PER_EXPORT"
-quit-if-no-data -stop-when-train-bucket-limited -no-repeat-files` (`synchronous_loop_9x9.sh:300`).

### 2.2 Independent arithmetic (validator's own script, no import of `derive_knobs.py`)

```
r=32.3000 r_lo=25.0775 r0=31.6750 r0_lo=28.1336
r:    rows/cycle=32300.0 gain=258400.0 gain/E=12.920 fresh 1.615 epochs=5 reuse=3.096
r_lo: rows/cycle=25077.5 gain=200620.0 gain/E=10.031 fresh 1.254 epochs=5 reuse=3.988
E/batch = 156.25 -> 156 batches >= 100 ; floor E for 100 batches = 12800
keep>cap True ; keep>=5E True
bootstrap G*r0=31675.0 G*r0_lo=28133.6 >= 25000 True True ; G lower bounds: fresh 957.0, boot 888.6
cycle-1 window (usable=min_rows) = 25000 rows = 195 batches >= 156
B/row = 353.80 ; per-cycle monotonic 16.11 MiB ; bounded 552.90 MiB ; after 23 cycles 20.902 GiB ; 30480 cycles to 500 GiB
gph=2031.7 (slower of 2341.5 / 2031.7) sps=14.243 (slower of 14.243 / 17.202)
selfplay=3544 train=7021 gate=180 shuffle=377 export=60 total=11182 s = 3.106 h ; 23 cycles/link
T1 fails below r = 24.0 at G = 1000
```
Every knob, ratio and projection in the candidate row reproduces to the printed precision. The 3.11 h is
composed of 1000 games at a 0.5x-derated 2031.7 games/h (3544 s) + FIVE epochs x 20000 samples at
14.243 samples/s (7021 s; a single epoch would be 1404 s) + a 200-game two-net gate scaled 2x from the
measured one-net 70.19 s / 156 games (180 s) + shuffle (377 s) + export (60 s). The games/hour figure is
real-net: 299259's whole selfplay stage was the real-net probe (80 games / 141.75 s; the file's own
`selfplay_games_per_hour`), and 298712's is the leg-D1 probe pid (20 games / 30.75 s), NOT the file's
random-net 5569.5. Storage uses 353.8 B/row for tdata and for the 3 retained shuffled copies, 2048 B/game
for selfplay + gate sgfs, and one 2.87 MiB export per cycle.

### 2.3 Executed checks

`python3 results/ktg/paper_1902.10565/codes/eval/check_knobs_9x9.py` -> exit 0, `CHECK_KNOBS_9X9: PASS`,
16/16 conjuncts, same lines as `evidence/knobs/derivation.txt` block 5.
`derive_knobs.py --self-test` -> exit 0. `bash -n synchronous_loop_9x9.sh` -> exit 0.
The task-file section 2 command run verbatim -> exit 1 (T1 0.799, K2b 7.51/9.68, K4 78 < 156 batches),
reading 31.95 from the MUTABLE `rows_per_game.txt`; the worker's account of it is correct.

### 2.4 Break attempts on a scratch copy of the code tree (paths preserved)

| # | mutation | exit | what failed |
|---|---|---|---|
| B1 | `NUM_GAMES_PER_CYCLE=500` in `knobs_9x9.env` | 1 | T1 (16150 < 24000), K5 (15838 < 25000), loop wiring |
| B2 | `SHUFFLE_MINROWS=10000` | 1 | K4 (78 < 156 batches), T2, loop wiring |
| B3 | `train_samples_per_second`, `bytes_per_row_on_disk`, `probe_search`, `selfplay_games_per_hour` removed from BOTH throughput JSONs | 1 | K7 only: games/h -> nan. **train samples/s and B/row silently fell back to the hard-coded 14.243 / 353.8 in `derive_knobs.py:320-321`**; with only those two keys missing the check would still pass on baked-in constants |
| B4 | `rows_per_game_real = 20.0` in the rows file | 1 | T1 |
| B5 | rows file replaced by garbage | 1 | `could not read rows_per_game_real` |
| B6 | loop default `EPOCHS_PER_EXPORT:-4` | 1 | loop wiring |
| B7 | `SHUFFLE_KEEPROWS` line deleted from the env | 1 | `KeyError` (loud) |
| B8 | only the unsuffixed `rows_per_game.txt` present | 0 | falls back to the mutable name and prints its hash (documented behaviour) |
| B9 | `MAX_TRAIN_PER_DATA=9` | 1 | loop wiring (and reuse is never raised by the derivation) |

Verdict on the check: it cannot be made to pass by an argument (it takes none) or by moving a knob or a
measured rows/game; its only soft spot is B3's silent fallback, which touches the `[PRELIMINARY]`
projections K7/T3 only (57 h and 479 GiB of headroom) -> recorded as obligation `o41_check_knobs_silent_fallback_constants`, not a rejection.

### 2.5 No knob derives from `cheapSearchProb` / a07

`grep -n cheapSearch|a07|moves_per_game|maxVisits codes/eval/derive_knobs.py codes/eval/check_knobs_9x9.py
codes/loop/knobs_9x9.env` hits only the env-file comment saying they are not used. Every row count is the
measured rows/game. Confirmed.

### 2.6 Thread coupling 32 / 18 against the measured 25

`nlwp_max-298712.txt`: 25 on `probe_search/selfplay` (pid 332406) and `cycle2/gatekeeper` (pid 328662,
one real net vs the `/dev/null` baseline), 22 on every random-net selfplay, 14 train, 4 + 8 shuffle;
`nlwp_max-299259.txt` reproduces 25 / 14 with a ppid-filtered sampler and no foreign pids. Both cfgs
carry `numGameThreads = 18`. The policy script named by `mission.json compute.policyCheck` at
`--gpus 1 --cpus 32 --partition b200` prints `OK : request gpus=1 cpus=32 part=b200 within policy
(gpu<=4, no cpu cap)`, exit 0.

The two-real-net gatekeeper number is arithmetic, not a measurement, and the worker's own formula
does not sum to what it prints: `18 game + 2 nnServer + 1 dataWrite + 1 main + 2x3 CUDA` = **28**, not 29
(`derive_knobs.py:300` adds a fifth non-game thread the one-net formula at `:299` does not have; the
one-net gate already has two nnServer threads, one per model, and measured 22 + 3 = 25). The CUDA runtime
helper threads are per process, so the honest two-net projection is 25..28; the code's 29 is one thread
over, in the safe direction (headroom 4, not 3). Recorded in the row; not a rejection.

### 2.7 The export ramp — the one statement that does not survive

The candidate claims "'exactly one exported candidate per cycle' holds only from cycle 13; cycles 1-12
are window-limited to 1-4 epochs". Re-deriving from the code:

- `-no-repeat-files` is passed, and `katago/utils/training_data_generator.py:35` documents it: "When
  training data runs out, stop. peek()/pop() return None." So a shuffled window of 25000 rows (195
  batches) feeds exactly ONE 156-batch epoch; the second epoch's `get_files_for_subepoch` returns
  `None` and `-quit-if-no-data` exits 0 (`train.py:1487-1489`) with `export_cycle_counter = 1 < 5`:
  **cycle 1 exports nothing** (the candidate's own K2c says the counter carries over).
- With nothing exported, `models/` stays empty, cycle 2's selfplay plays the random net again, its rows
  land in `random/tdata/` and are capped at `min_rows` (`shuffle.py:1077`): the window is pinned at
  25000 rows, one epoch per cycle, until the counter reaches 5. **The first candidate exports at cycle 5,
  is gated at cycle 6, and real-net rows cannot exist before cycle 6.** The worker's usable-rows model
  `min_rows + (c-1)*G*r_lo for c >= 2` assumes real-net rows from cycle 2, which is unreachable.
- Validator simulation (persistent counter, window-capped epochs, bucket refilled by `range[1]`
  which counts random rows in full, first candidate ACCEPTED at cycle 6 — the optimistic case):
  ```
  c= 1..5  usable=25000 window=25000 epochs=1 each  -> counter 1,2,3,4,5 ; export at cycle 5
  c= 6 usable=50077  window=34305  epochs=1  c=7 42561/2  c=8 50116/2 export  c=9 57156/2
  c=10 63794/3 export  c=11 70107/3  c=12 76149/3 export  c=13 81960/4  c=14 87570/4 export
  c=15 93004/4  c=16 98282/4 export  c=17 103419/5 export  c=18.. 5 epochs, export every cycle
  exports at cycles [5, 8, 10, 12, 14, 16, 17, 18, 19, 20, ...] -> exactly one per cycle from cycle 16
  ```
  If the first candidate (trained on 100000 samples of random-play rows) is rejected, the loop stays in
  the one-epoch / one-export-per-five-cycles regime until a candidate is accepted.
- What DOES hold from cycle 1, structurally: at most one export per cycle (`-epochs-per-export` =
  `-max-epochs-this-instance` = 5). Every K1-K7/T1-T4 inequality is unaffected: cycle 1 is still the
  binding window case and a random-net cycle never goes below it, so K4's conservatism runs in the safe
  direction everywhere.

Consequence: the knob set is admitted; the claim is NARROWED in the admitted row (no "cycle 13", no
"1-4 epochs in cycles 1-12"), o24's discharge carries the narrowed wording, and the ramp is opened as
obligation `o40_export_ramp_first_candidate_cycle5` (correct `derive_knobs.py`'s window-by-cycle model; owners `scale_data_window` /
`bootstrap_accepted_model`; first measurable at `train_stage`/`export_stage`).

### 2.8 Claim / status honesty

`conditional` is right: inputs measured, nothing measured at the derived point. The candidate's
`evidence_type` value `symbolic_derivation_with_executed_numerical_check` is not in the ledger enum and
would have been refused; the admitted row uses `symbolic_derivation` (the task file's own type). Two
`open_obligations` names in the candidate do not resolve to ledger ids: `o03_thread_budget` is
`o03_thread_budget_24cpu`, `o37_mutable_smoke_evidence` is
`o37_smoke_monitor_append_and_evidence_overwrite`; corrected in the admitted row.

### 2.9 o13 / o24 / o39 references

- o13: conjunct (i) `SELFPLAY_CONFIG`/`GATING_CONFIG` default to the mission cfgs
  (`synchronous_loop_9x9.sh:160-161`); (ii) the `KATAGO_SRC` git-root guard (`:100-111`); both were
  executed by the validator of `r_loop_resume_under_walltime_static` (row `7edac62a…`); (iii) the knob
  conjunct is now met by measurement (this node). Discharged.
- o24: every derivation conjunct met and executed; the "exactly one per cycle" conjunct is narrowed to
  "at most one per cycle from cycle 1, exactly one once the shuffled window holds 5 x E rows" (section 2.7).
  Discharged with the amended statement; the residual is o40_export_ramp_first_candidate_cycle5.
- o39_cpus_per_task_wiring (the worker proposed it as o38; o38 was taken by o38_full_frac_discriminator_reused_tree in 97b44ba): `codes/loop/loop.sbatch:8` `#SBATCH --cpus-per-task=24` and `:90` `REQ_CPUS=24` — read and
  confirmed. The candidate's statement also says the compute-budget skill's sizing table "lists 24 for
  single-GPU training": it does not — `SKILL.md:33` lists 12 for single-GPU and `:35` 24 for 2-GPU; both
  presets are below the measured 25 and the table is documentation, not wiring. o39 is opened with the
  loop.sbatch facts only and the SKILL.md note as a non-binding remark.

### 2.10 Substitution of the closing check

The task file's section 2 command is defective as the worker says (hard-coded refuted pilot `--games 500`,
`--min-rows` default 10000 fails K4 from cycle 1 at any r, unquoted `$(cat …)` over a prose file naming
the mutable copy). Adopted as `verification.command` on the admitted rows:
`python3 results/ktg/paper_1902.10565/codes/eval/check_knobs_9x9.py` (parameterless; exit 0 required and
re-run by the gate at append). The substitution is recorded on the result row's `provenance` and `notes`.

## 3. Verdict

**ADMIT, narrowed.** Result `r_cycle_knobs_9x9_derived` at `conditional` with the ramp statement replaced
by the section 2.7 finding and the thread sum corrected; knowledge node `derive_cycle_knobs_9x9` at
`preliminary` (predecessor `synchronous_loop_smoke` is preliminary, `data_budget` is hypothesis; no cycle
has executed at the set). Claim ledger: o24 discharged (amended wording), o13 discharged, o03 re-appended
open with the 32/18 decision recorded, o39_cpus_per_task_wiring opened (loop.sbatch wiring), o40_export_ramp_first_candidate_cycle5 opened (export ramp / first
export at cycle 5), o41_check_knobs_silent_fallback_constants opened (silent fallbacks in `derive_knobs.py:320-321`). Row hashes and the exact
appended commands are in the commit body.
