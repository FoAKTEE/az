# Validation — `arxiv-1902.10565::derive_cycle_knobs_9x9`, re-derivation from PRODUCTION (refuter, then judge)

Candidate: `evidence/derive_cycle_knobs/candidate_rows_rederive.json` (sha256 `e94b7f90…`) at worker commit
`63ff7f7` (`fix(knobs,ktg)!`), evidence `rederive_check.txt` (sha256 `36bfa631…`) and `derivation.md` § 9.
Validator: cross-model, `CHANDRA_ROLE=validator`, login node, CPU only, no job, no allocation; `runs/p1` was READ
(rows, games, sizes) and never written. Authority for the value: `mission.json` `decisions[6]` (human, 2026-09-05).
Everything below was recomputed from the selfplay directories, the throughput JSON and the code; nothing was taken
from the worker's numbers on trust. Clock at the start of the review: 2026-09-05 04:02 EDT; link 1 (job 301099)
RUNNING on gl111, END 18:22:13; link 2 (job 305318) PENDING afterany:301099.

## 0. Link-2 safety — FIRST

No defect was found that would harm link 2. Checked:

* `scontrol show job 305318`: `Command=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/loop/loop.sbatch`,
  `WorkDir=/weka/home/schmidt/ssci-haiyangw/az`; `loop.sbatch:64` `KTG_CODES=$AZ_ROOT/results/ktg/paper_1902.10565/codes`,
  `:170` `KNOBS_ENV=…/knobs_9x9.env`, `:186-190` `set -a; . "$KNOBS_ENV"; set +a` — sourced ONCE, before the cycle loop.
  The working tree at HEAD `63ff7f7` carries `NUM_GAMES_PER_CYCLE=1500` (`knobs_9x9.env:110`) and
  `${NUM_GAMES_PER_CYCLE:-1500}` (`synchronous_loop_9x9.sh:147`); `git status` on `results/` was clean before the
  ledger appends. Link 1 logged `knobs … sha256 5ae5358791974ae1` at 18:52:13 (the 1000 file) and holds it in memory.
* `grep -rn NUM_GAMES_PER_CYCLE codes/` → executable readers are exactly `knobs_9x9.env:110` and
  `synchronous_loop_9x9.sh:147,372` (`-max-games-total`); `smoke_one_cycle.sh:48` (40) and `t7_cycle.sh:113` (7x7) are
  other runs; `codes/data_budget/`, `codes/eval/check_metrics.py` and `chain_status` read no game count.
* `synchronous_loop_9x9.sh` has no time-remaining logic; the last cycle of a link is cut by SIGTERM and resumed by the
  successor exactly as at 1000 games (a03). `.cycles_completed` (50 at the review), `.chain_depth`, `.failcount`, `STOP`
  carry no game count — no run-state migration.
* The knob file the queued link will source was not edited by this validation (only ledgers, views and this file).
* `synchronous_loop_9x9.sh` is mode 0755 at HEAD; the running link's bash holds the pre-rename inode.

Not a hazard but a projection-input error (N2 below): both links are granted `TimeLimit=23:30:00` (QOS `scavenger`),
not the declared `2-23:30:00`; `status_log.txt` read 1 line 172 already records it.

## 1. Inputs re-hashed

```
36bfa6315c110e9993e50688e15626159a89e201b17ed408847a99d97e4527b2  evidence/derive_cycle_knobs/rederive_check.txt
e94b7f90b822aa86862e980e3011bec8b6fc609fe20f3472ef220e73cffca1ac  evidence/derive_cycle_knobs/candidate_rows_rederive.json
a032d0e34cd4c471eb942b54bedc65054d31c5ff95c13f82febc1ebe2490f259  evidence/production_chain/throughput.json
de12c9bba1ffe7753d444367cbc871f2304efcbabf40d40422b12dd028e92403  evidence/production_chain/rows_per_game.txt
3504a8ea9c9d0bfa941dc8084e4fbaa75fc601a66141feee06daa4fc136fae3e  codes/loop/knobs_9x9.env
06c99d37cc8172da1200a7a85e9869266516832ff18a1f9203693da602378d6c  codes/loop/synchronous_loop_9x9.sh
04c8a076ceed3fbff8056108f3aa2ad2ea2e2408232253b6f3be523246787abd  codes/eval/check_knobs_9x9.py
d9ff5a014ac8a3010f6aa116fed5c1fff9c62211b220c8843b2d7ba59e6c517e  codes/eval/derive_knobs.py
```
The four hashes `check_knobs_9x9.py` prints in block 3 (`rows_per_game.txt de12c9bb…`, `throughput.json a032d0e3…`,
`audit-298712.json 646e4ef1…`, `knobs_9x9.env 3504a8ea…`) reproduce.

## 2. Refutation attempts

### 2.1 Recount of rows and games from the selfplay directories (not from the JSON)

Pure-Python recount over `runs/p1/selfplay/<net>/`: rows = Σ `binaryInputNCHWPacked.shape[0]` read from each npz's
`.npy` header; games = sgf lines; moves = `;B[`/`;W[` per line; resignations = `RE[?+R]`. At the review the chain had
17 accepted nets and 50 cycles (the worker's snapshot had 13 and 41):

```
net                      games   rows   rows/game  moves/game  resign
random                    5000  157367   31.473     118.7      0.0%
t9-s143744-d157367        5000  171673   34.335     130.8      0.0%
t9-s448640-d329040        5000  126065   25.213      96.1      0.0%
t9-s879232-d455105        2000   43628   21.814      85.4      0.0%
t9-s1166208-d498733       3000   58693   19.564      77.7      0.0%
t9-s1462912-d557426       2000   38108   19.054      77.4      0.0%
t9-s1762560-d595534       3000   58859   19.620      78.7      0.0%
t9-s2062208-d654393       2000   39806   19.903      82.0      0.0%
t9-s2361984-d694199       3000   57867   19.289      81.7      0.0%
t9-s2661376-d752066       2000   38227   19.113      82.1      0.0%
t9-s2961408-d790293       3000   56212   18.737      81.6      0.0%
t9-s3260800-d846505       2000   36934   18.467      80.7      0.0%
t9-s3560832-d883439       3000   55053   18.351      80.9      0.0%
t9-s3860608-d938492       2000   36763   18.381      81.4      0.0%   <- was the worker's "incomplete" dir (1040 / 1136 games)
t9-s4160128-d975255       3000   54928   18.309      81.1      0.0%   <- accepted after the snapshot
t9-s4460160-d1030183      2000   36667   18.334      82.2      0.0%   <- accepted after the snapshot
t9-s4759680-d1066850      3000   54210   18.070      80.9      0.0%   <- accepted after the snapshot
t9-s5059328-d1121060       459       0    —          81.7      0.0%   <- newest, still playing (npz lag the sgfs)
```
Every figure for the 13 directories the worker used reproduces EXACTLY (rows, games, rows/game, moves/game, 0.0 %
resignations). Marginal over the last three complete (s2961408, s3260800, s3560832) = 148199 / 8000 = **18.5249**
(worker 18.5249). Sensitivity: 2 nets 18.397, 4 nets 18.643 — a 1.3 % swing that moves no knob (worker's claim confirmed).
Random r0 = 31.4734, r0_lo = 31.028; `1.2E/r = 1295.6`, `1.2E/r_lo = 1412.0`, `min_rows/r0_lo = 805.7` → ceil → 1500.

**"Newest directory is incomplete" criterion.** Confirmed as sound in both directions: a directory is complete iff its
net has been superseded (the selfplay process exits at every cycle end and flushes its npz files; the gate runs before
selfplay, so a directory only grows while its net is the latest). `t9-s3860608` — 15.88 rows/game at 1136 games and
17.34 at 1040 in the two partial snapshots — now reads **18.381 over 2000 games**, in line with its neighbours: the
partial readings were artefacts, as claimed. The newest directory today has 459 sgf lines and 0 npz files.

### 2.2 The drift bound — slope, horizon, and an OUT-OF-SAMPLE test

Least-squares slope over the nine complete post-transition directories (s1166208 … s3560832): **−0.1528** rows/game
per accepted net (worker −0.1528; mean first-to-last step −0.1517). Over all 12 complete real nets it would be −0.907,
which spans the one-time moves/game collapse (130.8 → 96.1 → 85.4 → 77.7) — the worker was right to exclude it.
`r_lo(10 nets) = 18.5249 − 1.528 = 16.9968` (worker 16.9968). **`r_lo(20 nets) = 15.469 < 16.0`** — at the fitted
slope, 1500 is NOT robust to twenty more accepted nets.

Out of sample — the four nets accepted after the snapshot, against the worker's construction (marginal carried
forward at −0.1528 per net):

```
net            actual   linear from marginal   linear from last net
t9-s3860608    18.381        18.372                  18.198
t9-s4160128    18.309        18.219                  18.045
t9-s4460160    18.334        18.066                  17.893
t9-s4759680    18.070        17.914                  17.740
```
All four sit at or above the bound: the bound HELD. Refit slopes: last 9 complete (s2062208 … s4759680) **−0.136**,
all 13 post-transition **−0.137**, last 4 **−0.091**; per-net steps −0.116, +0.030, −0.072, +0.024, −0.264 — the drift
is decelerating and noisy but has NOT stopped (18.070 is the lowest complete reading yet). New marginal over the last
three complete (s4160128, s4460160, s4759680) = 145805 / 8000 = **18.2256** → 1500 × r = 27338 rows, **+13.9 %** on
24000 (the 1000-game set would read −24.1 %). Nets to reach 16.0 from 18.2256: 14.6 at −0.1528, 16.3–16.4 at −0.136.
Acceptance cadence: 17 in 50 cycles = one per 2.9 cycles → ~47 cycles → 14–19 h at 0.29–0.39 h/cycle, i.e. **inside
link 2's 23.5 h** under the linear model. Verdict on the "10 accepted nets forward" bound: **defensible** (it held out
of sample and the refit slope is shallower) but **not a resting point** — the re-derivation trigger at 17.0 is a
link-2 monitoring obligation, hence o47 is opened BLOCKING for `scale_data_window`. The sampling term over 8000 games
is 1.12 %, as stated; drift is the binding uncertainty.

### 2.3 Every inequality at r = 18.5249, r_lo = 16.9968 and the new marginal 18.2256 (validator arithmetic)

```
r=18.5249  rows/cycle=27787.3 (+15.78 %)  gain=222299 (11.11x E)  epochs=5  reuse=3.60
r=16.9968  rows/cycle=25495.2 ( +6.23 %)  gain=203962 (10.20x E)  epochs=5  reuse=3.92
r=18.2256  rows/cycle=27338.4 (+13.91 %)  gain=218708 (10.94x E)  epochs=5  reuse=3.66
K3 120000 > 100000 >= 5*20000;  K4 min(25000,120000)/128 = 195 batches >= 156;  K5 1500*31.028 = 46542 >= 25000
K6 swa 10000 = E//2;  T4 worst 28 (measured 24) <= 32;  T1 survives any r >= 24000/1500 = 16.0
```
All reproduce the candidate's inequality table to the printed digit. K2 stays 5 because `min(gain, cap_eff)/E =
100000/20000` — `MAX_TRAIN_SAMPLES_PER_CYCLE` fixes it, as claimed.

### 2.4 Cycle-time composition and the 5520 games/h figure

From `throughput.json per_phase_stage`: 37 cycle selfplay phases from cycle 6 (the first gate) on sum to 23504.35 s
over 36040 real-net games → **5520.0 games/h** (worker 5520.0); the 5 bootstrap phases sum to 424.78 s for 5000
random games; all-net 41040 / 23929.13 s = 6174.2, as the file says. Per-cycle selfplay fell from 1185 s (cycle 6) to
446 s (cycle 41) for 1000 games; the last ten cycles average 474 s → ~7600 games/h, so 5520 is a conservative mean.
Model terms at G = 1500: selfplay 1500 × 3600 / 5520 = 978.3 s; train 5 × 20000 / 1964.646 = 50.9 s; gate
`2.0 × 200 × (938.11 / 1573) = 238.6 s` (**`derive_knobs.py:474` doubles the per-game seconds for the two-real-net
gate** — the worker's prose "200 games" is the game count before that factor; production averaged 121 games and
62.5 s per gate, one gate per 2.9 cycles, so the term is ~10x conservative); shuffle 60 + 4.26 × 120000 / 22774.5 =
82.4 s; export 60 s; total **1410.2 s = 0.392 h** (worker 1410 s). Measured full-stage production cycles: mean 716.8 s
= 0.199 h (14 cycles), max 1307 s.

**Cycles per link (N2).** `derive_knobs.py` divides `walltime_seconds = 257400` (the declared `2-23:30:00`) → 182.
Slurm granted `TimeLimit=23:30:00` to 301099 and 305318 (QOS `scavenger`; partitions allow 3-00:00:00) — 84600 s →
**60 whole cycles** at the model, ~80 at the measured rate. Already noted at `status_log.txt` read 1 ("A 23:30:00
link fits ~98 cycles, not the 23"). Harmless to the run (a03 chains links, `KTG_MAX_CHAIN` 200) and it makes T3
smaller; recorded as a projection-input obligation for `loop_resume_under_walltime`.

### 2.5 Storage: the "2.6x under-count" is real but mis-attributed (N3)

`du -sb --apparent-size` over `runs/p1` at 50 cycles: selfplay 620.6 MB (tdata 409.4 + sgfs 213.3 + logs), models
164.8 MB (17 × 9.7 MB), gatekeepersgf 6.5 MB, train 53.0 MB, **shuffleddata 902.4 MB in 16 windows of ~55 MB**,
total 1778.0 MB. Monotonic per cycle = (409.4 + 213.3 + 164.8 + 6.5) / 50 = **15.9 MB/cycle** — the model's
15.89 MiB (16.66 MB) is confirmed within 5 %, so the per-cycle term is NOT under-counted. The miss is the BOUNDED
term: `budget.env` `KTG_KEEP_SHUFFLEDDATA=3` with `KTG_SHUFFLEDDATA_MIN_AGE_S=7200` keeps every window younger than
2 h (`prune_retention.py:41-48`, mirroring upstream `cleanup_old_dirs.py:13,24`), so at ~10 min/cycle 16 windows
stay, and a shuffled window is 55 MB (461 B/row) not 120000 × 366.27 = 44 MB. Model books 3 × 44 = 132 MB; reality
902 MB. Bounded at roughly (7200 / cycle_s + 3) windows — fewer at 1500 games — and under 1 GB, so T3 is unaffected
(mission root 13.8 GB of 500 GiB). Owned by `data_budget`; the candidate's wording is corrected in the admitted row.

### 2.6 The checker, run by the validator (verbatim tails)

Production command (`--marginal-nets 3 --trend-nets 9 --horizon-nets 10`), exit **0**:
```
  marginal r    = 18.5249   aggregate over the last 3 COMPLETE real-net selfplay directories (t9-s2961408-d790293, t9-s3260800-d846505, t9-s3560832-d883439): 148199 rows / 8000 games
  lower bound   = 16.9968   18.5249 carried 10 accepted nets forward at the least-squares slope of rows/game over the last 9 complete directories, -0.1528 rows/game per accepted net (NOT the sampling formula: over 8000 games its 90 % term is 1.12 %, while the binding uncertainty is drift as the net trains)
REAL-NET SELFPLAY games/h: 5520.0 -- 36040 real-net games over the 37 cycle selfplay phase(s) from cycle 6 (the first gate) on, 23504.35 s; the 5 bootstrap cycle(s) before it played 5000 random-net games, 1000 games/cycle, and are excluded
  ok   T1_no_train_starvation             rows_per_cycle 27787.3 (lower90 25495.2) >= 1.2*E = 24000.0
  ok   T2_bucket_holds_batches            worst cycle 1 has 195 batches >= 156 needed; per-cycle bucket gain 222299 (lower90 203962) >= epochs*E = 100000
  ok   T3_storage_projection_under_budget 23.369 GiB after one 182-cycle link < 500 GiB (KTG_SCRATCH_HARD_BYTES)
  ok   T4_threads_le_cpus                 worst stage 28 <= KTG_CPUS_PER_TASK 32
CHECK_KNOBS_9X9: PASS
```

Negative control — the same command with `--knobs` on a G = 1000 copy of the knob file (written to the scratchpad, the live file untouched), exit **1**:
```
KNOB FILE UNDER TEST: <validator scratch copy>/knobs_prior_1000.env (not the live knobs_9x9.env; the loop-default assertion is skipped)
  FAIL T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 18524.9 (lower90 16996.8) vs 1.2*E = 24000.0; ratio 0.926 (lower90 0.850)
  FAIL T1_no_train_starvation             rows_per_cycle 18524.9 (lower90 16996.8) >= 1.2*E = 24000.0
CHECK_KNOBS_9X9: FAIL ['T1_freshness_rows_per_cycle_ge_1p2_E', 'T1_no_train_starvation']
```

Unchanged control — the admitted parameter-free invocation on the frozen smoke evidence, exit **0**:
```
  ok   K7_cycle_wall_under_bound              projected cycle = 12954 s = 3.60 h <= 60 h bound, and 19 whole cycles fit the 257400 s chain link. [PRELIMINARY] tiny-count throughput inputs.
CHECK_KNOBS_9X9: PASS
```

`derive_knobs.py --self-test`, exit **0**, all seven o41 missing-key cases raise `SystemExit` naming the key:
```
    dropped train_samples_per_second   -> SystemExit naming it: True
    dropped bytes_per_row_on_disk      -> SystemExit naming it: True
    dropped selfplay_games_per_hour    -> SystemExit naming it: True
    dropped gatekeeper_games_total     -> SystemExit naming it: True
    dropped selfplay_rows_total        -> SystemExit naming it: True
    dropped cycle2/gatekeeper          -> SystemExit naming it: True
    dropped cycle2/shuffle             -> SystemExit naming it: True
    every key present            -> derives, no exit
SELF-TEST: PASS  (3 knob cases: 2 negative, 1 executed-smoke; 2 o40 ramp cases; 7 o41 missing-key cases plus a positive control)
```

Note on block 4 of `rederive_check.txt`: its heading (and the commit's `verify:` object) says "same 11182 s = 3.11 h cycle and 23
cycles per link as the 2026-09-04 record", but the printed body — and the validator's re-run — reads `12954 s = 3.60 h` /
`19 whole cycles`. The difference is exactly the selfplay term at the NEW knob: 1500 × 3600 / (0.5 × 2031.7) = 5316 s against
3544 s at 1000 games, +1772 s. So the repair did leave the smoke path's behaviour unchanged, but the heading's numbers are
the G = 1000 record, not what block 4 printed. A heading slip in the worker's evidence file, not a verdict change (PASS
either way); recorded here, not corrected in place.

### 2.7 Code review of the repair (o41 must still hold)

`check_knobs_9x9.py` diff read in full. `cycle_phases` / `resolve_phase_elapsed` locate a stage by NAME (preferred
`cycle2/*` when present, else the earliest) and return `(None, None)` when the file records none → the caller appends
the key to `missing` and `SystemExit`s; `resolve_gate_measurement` pairs `gatekeeper_games_total` with
`stage_elapsed_s['gatekeeper']` (production) or one gate phase with the audit's `S4_gatekeeper_sgfs.lines` (smoke),
else `(None, None, None)`; `resolve_real_net_rate` splits the selfplay phases at the first gate cycle and returns
`None` unless `random_games % bootstrap_cycles == 0` (5000 / 5 = 1000 ✓); `selfplay_rows_total` is divided by the
count of cycle selfplay phases the file records (42). No constant was introduced; `derive_knobs.py` refuses
`--rows-per-game-lower` above the measurement. The three new flags choose HOW MANY directories to aggregate / fit —
they take no rows/game value — and the tool prints the whole per-net table, the marginal, the slope and the bound.
`--knobs FILE` disables the loop-default assertion for a non-live file and says so. Self-test 14/14 (block 2 reproduced).

### 2.8 Commit grammar: `!` / BREAKING CHANGE

`fix(knobs,ktg)!:` with a `BREAKING CHANGE:` footer naming what is invalid (NUM_GAMES_PER_CYCLE = 1000, r = 32.3,
the 3.11 h / 23-cycle / 16.11 MiB / 353.8 B projections). `commit_template.md` § 8 reserves `!` for a change that
overturns a previously committed claim/default or changes a default that changes output — both apply. Pairing
warranted. Body objects are from the § 5 enum; footers `Iter/Refs/Verify/Claim` present. No AI tool or model name
appears in the commit, the evidence files or the ledger rows.

### 2.9 Other checks

* DESIGN.md §§ 2/6/8/9 diff read: R18 row added, R14 re-numbered at production rates, § 9 names the re-entry edge.
  **N5:** § 2's "~52 cycles (~6 h of link 2 at the projected 0.39 h/cycle)" is an arithmetic slip — 52 × 0.39 h ≈ 20 h.
  Hand-authored design doc; recorded as an obligation note, not edited by the validator.
* `resolve_real_net_rate(tput, knob_games)`: the `knob_games` argument is accepted and unused (the games/cycle
  cross-check uses `random_games // len(boot)`); cosmetic.
* Error-ledger rows `26b1ede9…` (iteration 3, fail, `assumption_too_narrow`) and `c3c098c8…` (iteration 4, pass) read;
  expected / observed / root_cause / fix_hypothesis are consistent with the code diff.
* DAG: `derive_cycle_knobs_9x9` is already a transitive ancestor of `measure_stage_throughput`
  (`knowledge_database.py predecessors --transitive`), so the candidate's suggested predecessor edge would be a cycle;
  not added. `measure_stage_throughput` stays a RESULT dependency (its file is the input) — not circular evidence,
  because the measured rows/game does not depend on the truth of the knob claim.
* `evidence_type` in the candidate row (`symbolic_derivation_over_empirical_measurement_with_executed_numerical_check`)
  is not in the ledger enum; admitted as `symbolic_derivation` with the measured inputs stated in the working context.
* Compute: no job, no allocation; the policy script named by `mission.json` `compute.policyCheck` was therefore not
  required and not run.

## 3. Verdict — ADMIT, status `conditional` (agreed, with narrowings)

No gate fails. Gates 3–6 (validator's brief): the evidence (an executed arithmetic check over measured production
inputs, reproduced independently) matches a `symbolic_derivation` claim over measurements; units/regimes are
consistent (rows/game per accepted net, games/h over real-net phases only, seconds granted vs declared); the
protocol, checks, uncertainty (drift, not sampling) and artifacts are stated; the one modelling choice (the drift
bound) is explicit, printed by the tool, and survived an out-of-sample test. `conditional` is the honest status: no
cycle has run at 1500, and the claim is conditional on the marginal staying above 16.0, which the linear model
crosses inside link 2. The admitted claim carries five validator narrowings: N1 drift horizon (defensible, not robust
to 20 nets; re-crossing inside link 2), N2 cycles-per-link against the granted 84600 s, N3 storage — monotonic term
confirmed, bounded term mis-booked (shuffleddata by age), N4 gate term is 2 × 200 games, N5 DESIGN.md § 2 arithmetic.

Rows appended (`CHANDRA_ROLE=validator`, gate re-ran the production checker, exit 0, output sha256 `278a4981…`):

| ledger | id | status | row_hash |
|---|---|---|---|
| result | `r_cycle_knobs_9x9_derived` (amends `0a885526…`) | conditional | `bd012841bb604f1587bc5b77b7d2d30cf4e91c8d1311841246c20d47ef1e796c` |
| knowledge | `arxiv-1902.10565::derive_cycle_knobs_9x9` (amends `81cb9b12…`, node_seq 5) | preliminary | `a2637b04c55c26004def8a2f5d5b508c69fb2cb1cf02cd5880a61f63e4e92ee5` |
| claim | `o47_rows_per_game_drift_rederive_at_17` (NEW, blocking, owner scale_data_window) | open | `6ad9fe1d01a85830be4c17241618bd9c7f20752662bf977156847ebca9df6979` |
| claim | `o24_cycle_knobs_derived` (statement: re-derive at the MARGINAL rate whenever it moves) | discharged | `cb14e541fed71934cb50e4778925527612c11bdb517fcc98d629c4523496ad58` |
| claim | `c10_rows_per_game` (notes: rows/game is a moving quantity; status unchanged) | refuted | `4aff3cc79785b2da6bc51aa50fd655fa7a746b47d48d6c20e4cf0cd7d19a2349` |

Not transitioned (outside this candidate's evidence or owned elsewhere): o03 (two-real-net gatekeeper measured 24 —
owner closes), o40 (b)(c)(d), o43. Views re-rendered: `decomposition/{claims,obligations,assumptions,results}.md`.

## 4. Remaining `[OPEN]`

1. **o47** — re-run the `--marginal-nets` command at every link-2 read; re-derive when the marginal crosses 17.0
   (linear model: 16.0 in ~16 accepted nets ≈ 47 cycles ≈ 14–19 h of link 2). Structural fix at `scale_data_window`
   (lower E toward 12800, or raise MINROWS).
2. Promotion to `empirical` needs one measured link-2 cycle at 1500 games.
3. `data_budget`: model the bounded shuffleddata term by age (≈ 7200 / cycle_s + 3 windows × ~55 MB).
4. `loop_resume_under_walltime`: `walltime_seconds` in the projection should be the granted 84600 s.
5. `measure_stage_throughput`: emit `selfplay_games_per_hour_real_net`.
6. `derive_cycle_knobs_9x9`: DESIGN.md § 2 "~6 h" → ~20 h; `rederive_check.txt` block 4 heading (3.11 h / 23) vs body
   (3.60 h / 19).
7. o03, o40 (b)(c)(d), o43 unchanged.
