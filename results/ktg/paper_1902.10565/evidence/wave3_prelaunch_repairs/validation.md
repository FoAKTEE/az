# Validation of the wave-3 pre-launch repairs (R1–R6) — `loop_resume_under_walltime`, `derive_cycle_knobs_9x9`, `playout_cap_randomization`

Role: validator (refuter, then judge), cross-model relative to the worker. Inputs received: the
candidate rows `evidence/wave3_prelaunch_repairs/candidate_rows.json`, the six worker transcripts
`repair_R1..R6.txt` (sha256 as listed in the candidate file, all matching), the artifacts at HEAD
`272b887` (`loop.sbatch` `0a03fbb2…`, `synchronous_loop_9x9.sh` `b5acb1d8…`, `knobs_9x9.env`
`5ae53587…`, `stage_monitor.sh` `c28ce544…`, `derive_knobs.py` `30b5ac19…`, `check_knobs_9x9.py`
`53589578…`, `probe_search_9x9.py` `f25088a9…`, `audit_smoke.py` `df5f5740…`, `DESIGN.md`
`d07bf485…` — every hash equal to the candidate's `artifacts` map), the task file § 2, the prior
validator records (`evidence/derive_cycle_knobs/validation.md` § 2.7, `evidence/smoke/validation_probes.md`
item 2 with `root_visits_hist-v299259.json`, `evidence/loop_resume/validation_repair4.md` + harness), the
surviving engine log on scratch (read-only), the reference code at `v1.18.2`, and the ledger schemas.
Host login03, CPU only, no Slurm job, no GPU. The chain worker committed `6e4117d` (evidence only,
`codes/` untouched) while this ran; chain job **299366 was PENDING (Priority) on b200 throughout**,
submitted with `KTG_MAX_CHAIN=3`, `CPUs/Task=32`, `BASEDIR=runs/p1`.

Verbatim transcript: `evidence/wave3_prelaunch_repairs/validation_harness.txt` (sha256
`ea2d9813f95348e570b236a012b446e964072bc2ab1ff04324d872b3fa82ebe2`), sections A (static), F (re-bin),
D (R2 model and the validator's file-count ramp), E (R3 replay), G (real-clone dry run), V1 (R1 attacks),
V5 (R5 guard), V6 (R6 sampler), V2 (regression set), V3 (seed matrix), plus every harness source. The
harness is the validator's own: PATH shims for `sbatch scancel sinfo sacct scontrol squeue nvidia-smi`,
stand-in loops, a copy of the real knob file, symlinks to the real `codes/cfg`, `codes/eval`,
`codes/data_budget`, the real `mission.json` and policy script. `/usr/bin` was put ahead on PATH so the
wrapper's own `grep` calls ran GNU grep as on a compute node (the login shell's interactive `grep` is a
different tool that reads `${` differently; it made the task-file R1 command *appear* to fail once —
under GNU grep, which the admission gate's subprocess also uses, it passes).

## 0. Chain safety — read first

**No defect was found that would corrupt the state of the running chain (job 299366) or its
successors.** Every hole found needs an operator edit of `knobs_9x9.env` (V1g, V1j), a hand-populated or
resumed BASEDIR with old mtimes or a skewed clock (V5e, V5f), or a SIGKILLed link *followed by* a
deterministic pre-flight failure (V6g). The knob file at HEAD has every non-comment line of the form
`NAME=digits` and no `$`; `runs/p1` is fresh; the pre-flight failures that would trigger V6g are all
config errors that do not arise mid-chain. Two things the coordinator should know now, neither a
corruption: (i) the R2 ramp beyond cycle 5 is wrong (§ 3) — at these knobs the trainer runs ONE epoch
per instance through cycle 17 and at most TWO ever, so "exactly one candidate per cycle from cycle 16"
will not be observed and must not be read as a chain failure; the first export at cycle 5 stands;
(ii) the stale-pid hazard of V6g should be closed (o42) before a chain that can be SIGKILLed on a shared
node is left unattended for long — fix named in o42: run `stop` from `finalize()` only when this link
started the sampler, and make `stop` kill a listed pid only if its command line is a
`stage_monitor.sh start` of the same directory.

## 1. Reproductions

**R1 static (A).** Task-file command exit 0; policy line `OK : request gpus=1 cpus=32 part=b200 within
policy (gpu<=4, no cpu cap)`; `bash -n` clean on all seven files; stray classification knobs in the knob
file: 0; `SLURM_CPUS_PER_TASK` IS set in a batch environment on this cluster (job 298359 printed
`SLURM_CPUS_PER_TASK = 24`; both smoke jobs printed `cpus_per_task = 24` from it; 299366 shows
`CPUs/Task=32`), so the compare is live in a real link and the unset case (V1c) is the offline path only.

**R1 links (V1a–q).** `SLURM_CPUS_PER_TASK=24` → `declared CPUs 24 != KTG_CPUS_PER_TASK 32 -- pre-flight
failure`, `PRE-FLIGHT FAILURE rc=2`, `failcount now 2/3`, `SCANCEL 800001`; `=32` → `cpus granted 32 ==
KTG_CPUS_PER_TASK 32`, `cfg numGameThreads = 18 on both engine configs`, loop starts, successor line
`cpus=32`, no `--cpus-per-task` on the sbatch line (the `#SBATCH` 32 governs); unreadable knob file /
`KTG_MAX_FAILS=99` / tab-indented `KTG_MAX_FAILS=1 # …` / `KTG_CPUS_PER_TASK=abc` → refused before
sourcing, `REQ_CPUS unresolved … refusing to chain`, no sbatch at all, exit 2 counted; `KTG_CPUS_PER_TASK=24`
with 32 granted → refused (equality), successor cancelled; gatekeeper cfg at 24 → `cfg numGameThreads '24'
!= KTG_NUM_GAME_THREADS '18' in …gatekeeper_9x9.cfg`; a commented-out `# numGameThreads = 64` before the
real line is ignored (sed anchors `^numGameThreads`); a cfg with the key twice passes the sed on the first
value, but KataGo's parser refuses a duplicate key (`config_parser.cpp:298,305`), so it is not a hole; the
eleven knobs exported by `set -a` equal the CHANGE 9 defaults 11/11.

**R6 (V6a–j).** Under the wrapper the stand-in `exec -a "katago selfplay" sleep 3` is sampled with root pid =
the wrapper pid, rows tagged `selfplay`, ppid = the stand-in loop; `stage_monitor: started (ps pid … every
1s, gpu pid … every 5s)` and, in finalize, `stage_monitor: stopped; 2 ps samples`; the sampler's own
`ps/awk/sleep` never appear; `monitor.run` and `monitor.pids` removed; 0 processes left. Alone, unset
intervals mean 0.2 s / 2 s and `=1` means 1 s. A process-group SIGTERM (walltime form) ends the samplers
with the link (0 alive, stop line reached); a wrapper-only SIGTERM leaves them to finalize's stop (35
samples, 0 alive after); a SIGKILL leaves `monitor.run` behind but the samplers exit on `kill -0` of the
dead root within one interval (0 alive after 3 s). A pre-flight failure after start (missing
`prune_retention.py`) still runs stop. The REAL loop's phase call prints `stage_monitor: phase = cycle1`
only when `monitor.run` exists and creates no monitor dir otherwise (dry-run / smoke path untouched).
Cost: one `ps -eo` sweep is 90 ms over 1751 processes on the login node, ten `ps|awk` sweeps 640 ms →
about 6 % of one core at 1 s; the sampler shells' own cputime over 20 s rounds to 0.

**R5 (V5-0, V5a–l).** Checker: good npz PASS (1313 rows), synthetic `(22, 21)` npz FAIL naming
`binaryInputNCHWPacked trailing shape (22, 21) != (22, 11)` and `row bytes 2365 != 2145`, exit 1; no
argument exit 2; empty dir exit 1. Guard in the REAL loop (`KTG_STAGE_ONLY=1`): 0 npz clean skip and no
marker; the smoke's two npz symlinked in → `pos_len check: 2 npz`, PASS over 2534 rows, marker touched;
second run → 0 npz; bad npz with a current mtime → refused by name before any stage, exit 1; missing
checker → `refusing to shuffle unverified training data`. The REAL loop under the REAL wrapper with dummy
stages, `KTG_ONE_CYCLE=1`: a dummy selfplay dropping a good npz → `pos_len check: 1 npz (cycle 1
pre-shuffle)`, PASS, Shuffle/Train/Export run, `cycle 1 complete`, `.cycles_completed=1`; dropping a bad
npz → FAIL, `pre-shuffle pos_len guard refused the data cycle 1 wrote (obligation o02)`, loop exit 1 before
any of Shuffle/Train/Export (0/0/0), `.cycles_completed` unchanged, `failure rc=1 -- failcount now 2/3`;
the successor link → refused at `loop start` before the gatekeeper (0 gatekeeper runs), breaker on the
second failure. Cost: 400 npz through the guard's own `find | xargs` form in 0.53 s.

**R3 (E).** Literal grep for `14.243|353.8|70.19|3.35|2534` on code lines: exit 1. B3 replayed on a
scratch copy with `train_samples_per_second` and `bytes_per_row_on_disk` deleted from both throughput
JSONs: `check_knobs_9x9: … is missing the measured key(s) train_samples_per_second, bytes_per_row_on_disk
… no fallback constants (obligation o41)`, exit 1, stdout free of 14.243 / 353.8 / nan; the same copy with
both rates passed explicitly derives (`RESULT: PASS`); the original passes. Dropping `selfplay_rows_total`
alone exits 1 naming it; dropping `selfplay_games_per_hour` alone still derives — legitimately, from the
mixed-stage `probe_search.games / per_phase_stage elapsed` form, a second measured source, not a constant.

**R2 (D).** `--self-test` exit 0 (3 knob cases, 2 ramp cases, 7 missing-key cases + control);
`check_knobs_9x9.py` exit 0, `CHECK_KNOBS_9X9: PASS`, the same eleven values, `T4 … worst stage 28 <= 32,
headroom 4`, `first_export_cycle = 5`, cycles 1–5 one epoch each, `first_exactly_one_cycle = 16`;
`--first-accept-cycle 9` → 19. The two-net sum 18 + 2 + 1 + 1 + 2 × 3 = 28 is right.

**R4 (F).** Engine log sha256 `59e2574e…`, 11 985 614 B. awk over the 7401 `Root visits:` lines:
`full600=1862 cheap100=4872 between=667 outside=0 distinct=289 full_frac=0.251588 legacy_gt100=0.341711`
(287 distinct values strictly between). The sgf `v=` annotations of the same 60 games give the identical
histogram; per game, **0 of 667 between values follow a 100, 533 follow a 600, 134 a between, 0 open a
game**. The loop's 80 random-net sgfs: 9211 turns, 2311 full = 0.250896, 6309 cheap, 543 between, 48
outside; 0 of 543 follow a 100, 1 opens a game. `probe_search_9x9.py` re-run verbatim reproduces the
committed json (`PROBE_SEARCH_9X9: PASS`, `a2_sgf_v_instrument_agrees` True). z against p = 0.25:
+0.32 (n = 7401), +0.20 (n = 9211).

**Regression set (V2) and seed matrix (V3).** Every outcome line-for-line as `validation_repair4.md` § 1:
A `2 → 4`, breaker on link 2, link 3 exits 0; B, B2a, C pre-flight failures `2 → 4` with SCANCEL; D/E
deliberate stop, STOP, SCANCEL, count 0; F counted, SCANCEL; G `2 → 0`; H leaves 2; J one accounting line;
K1–K3 `scheduler termination … failcount left at 0` ×3, no SCANCEL, 0 processes left; K4 ×3 `loop status
143, this wrapper not signalled`; K5 loop finishes rc 0 after the wrapper's signal; K6 count 2 survives;
M exit 137, nothing written; L1a `1/3`, L1b `2/3`; L2 deliberate stop; N successor exits 0 at entry;
O `1, 1, 1, 2, 2, 3` trip on link 6; P3 `1, 0, 0, 1, 0, 1` with `1 cycle(s) completed, so failcount 1 is
cleared`; P4 `old count 2 dropped`, `2 → 1`; P5 `2, 2, 2`. T1: every seed `failcount now 4/3`, breaker,
SCANCEL, `finalize_end=yes`; T2: WARNING iff raw ≠ read, `08/09/007/' 5'/'5 '` → post-trip guard, the rest
read 0 or 2 → written 2 or 4; T3: WARNING iff raw ≠ read, depth = read + 1, `199` and 18 nines refuse to
resubmit; T4 `FAKE LOOP recorded a cycle: 9`, `old count 2 dropped`, `2/3`; T5 `2`, `4` + breaker, link 3
exits 0.

**Real-clone dry run (G).** `KTG_STAGE_ONLY=1` from `$KATAGO_SRC` (git `fd0723fd`, binary 27 273 864 B),
BEFORE = `ce56fbb` loop copy, AFTER = HEAD: `STAGE_EXIT=0` both, **87 files / 28 880 227 B each**, manifest
diff exit 0, `cmp bin/katago` exit 0, `dataBoardLen = 9`, no monitor dir, no marker, `pos_len check: 0 npz
(loop start)`. The task file's "80 files / 28 702 024 B" is stale: the clone's `python/katago` and
`python/muon` now hold 13 `__pycache__` files (mtime 2026-09-03 21:55) that upstream's `cp -r` copies
into every dated archive; the worker's own transcripts already record 87 / 28 835 171 (the byte count
drifts with the pyc files). Not a defect of the repairs.

## 2. Attempts to break the repairs — what they found

**V1g — `export KTG_MAX_FAILS=1` in the knob file is sourced.** The guard is `grep -c -E
'^[[:space:]]*(KTG_MAX_FAILS|…)='`; the `export` spelling passes it, the file is sourced, and the link
runs with `failcount 0/1`: the breaker trips on the first failure and the successor is cancelled. The
candidate's "a knob file that carries KTG_MAX_FAILS … is not sourced at all" is therefore narrowed to the
plain `NAME=` spelling on the row. `: "${KTG_MAX_FAILS:=1}"` (V1h) is harmless only because the wrapper
assigns its defaults before sourcing.

**V1j — an unset-variable reference in the knob file kills the link before the trap.** `Q=$NOT_SET…` →
`knobs_9x9.env: line 178: NOT_SET_ANYWHERE_XYZ: unbound variable`, wrapper exit 1, `.failcount` and
`.chain_depth` never written, no sbatch, no accounting line — the o26 class the wrapper's own comment at
:162-166 says the section must avoid. A syntax error (V1k) only truncates the file at the error (the knob
lines above it take effect, the link ran and exited 0).

**V6g — stale `monitor.pids` after a SIGKILL.** With `monitor.run`/`monitor.pids` left by a SIGKILLed link
(the V6e residue) and a successor that fails its pre-flight before its own `start` (env.sh hidden),
finalize's `stop` killed the pid listed — an unrelated `sleep` of this user. A successor that reaches
`start` overwrites both files first, so the window is SIGKILL + deterministic pre-flight failure + pid
reuse by a same-user process on that node.

**V5e / V5f — the marker is an mtime test.** A bad npz with a 2020 mtime on a tree whose marker exists is
skipped (`0 npz … nothing new to verify`) and refused only once the marker is removed; a marker dated one
day ahead makes every later file "old". **V5k** — a file dropped between the pre-shuffle check and the
shuffle is shuffled unguarded that cycle and refused at the next link's loop-start check. The guard is
what it says: a check on files newer than the last pass.

**V1o/V1p, V1d** — no holes: commented-out keys are skipped; duplicate keys are refused by the engine;
`SLURM_CPUS_PER_TASK=032` would be refused by the string compare but Slurm never emits it.

All four holes are carried as validator qualifications on `r_loop_resume_under_walltime_static` and as
**o42** (non-blocking). Two harness-side mistakes are recorded in the transcript so they are not mistaken
for artifact behaviour: the first V5h–l run pointed `KATAGO_BIN` at the wrong path (rc 2 before the guard;
re-run as v5b), and the first V6 run hung at V6b because the harness piped `stage_monitor.sh start` into
`sed` and the background samplers held the pipe open (no analogue in the wrapper, which writes to the job
log; re-run as v6b with the output written to a file).

## 3. The R2 ramp does not survive the reference code

The candidate reproduces the prior validator's § 2.7 model: epochs per instance = floor(min(window,
keep) / E), hence exports at cycles [5, 8, 10, 12, 14, 16, 17, …] and "exactly one per cycle from cycle 16".
Re-deriving from the code:

- `train.py:1303-1346` (`get_files_for_subepoch`) pops WHOLE shuffled files until they hold
  `round(E / batch) = 156` batches; one file of ≥ 156 batches is a subepoch. `train.py:1511` then iterates
  every row of the files taken. The smoke shows it: E = 256, yet the cycle-1 export is `t9-s1216` =
  38 batches × 32 = the whole 1221-row file (`S6 global_step_samples_cycle1 = 1216`; cycle 2 `s2528` = +41 ×
  32, the whole 1313-row file).
- With `-no-repeat-files` the next subepoch finds no file and `-quit-if-no-data` exits, so **epochs per
  instance = number of shuffled out files** (each ≥ 156 batches), capped at `-max-epochs-this-instance 5`.
- `shuffle.py:406-412`: `num_buckets = max(round(rows / approx_rows_per_bucket), 1)`, files per bucket =
  bucket // out-file, and `shuffle.py:788` defaults the bucket to `-approx-rows-per-out-file 70000`
  (`shuffle.sh:48`), `-num-waves` default 1 (`:789`). So out files = `max(1, round(rows_written / 70000))`
  with `rows_written ≤ -keep-target-rows 120000` (the loop's `SHUFFLE_KEEPROWS`, last on the command line):
  **at most 2 files, at most 2 epochs per instance, an export at most every third cycle.**
- Validator ramp with the candidate's own window column (harness D): cycles 1–17 one epoch (window
  < 105 000 rows), 18 on two epochs; exports at **[5, 10, 15, 19, 22, …]**; one export per cycle would need
  ≥ 5 out files, i.e. `rows_written ≥ 315 000 > keep`. Whole-file INPUT selection at
  `maxRowsPerTrainFile 10000` can add up to 9 999 rows to a window and pull the two-file threshold one cycle
  earlier; it cannot reach five files.
- What stands: at most one export per cycle from cycle 1 (structural); cycles 1–5 one epoch each and the
  FIRST candidate at cycle 5, gated at cycle 6 (a 25 000-row window is one file under either count); every
  K1–K7 / T1–T4 inequality (evaluated at cycle 1's window). Consequence for the projections, not asserted:
  an instance trains min(window, keep) rows, not epochs × E — about 120 000 samples (8 425 s at 14.243 /s)
  at steady state, effective reuse 120000/32300 = 3.7 ≤ 8, cycle ≈ 3.5 h, 21 per link; K7's 60 h bound
  and T1–T3 are unaffected.

The same row-count error is in the prior validator record's § 2.7 ("about cycle 16"); this record corrects
it. Verdict on R2: the amendment is admitted **narrowed** — the exactly-one conjunct rejected (error-ledger
fail row), o40 (a) closed, (b) re-opened (the four prose sites now carry the wrong ramp), (d) added, (c)
unchanged.

## 4. R4 settlements

- "322 distinct" (validation_probes.md item 2 and `r_smoke_full_frac_binning`) is wrong; the JSON's
  `distinct_values = 289` is right (287 strictly between 100 and 600). Corrected on the new row.
- The loop run's 48 out-of-band values are `64` (×40) and `818` (×8): asymmetric-playout turns
  (`selfplay_9x9.cfg:83-84` `normalAsymmetricPlayoutProb 0.01`, `maxAsymmetricRatio 8`; `play.cpp:624-635`
  draws doublings per game and scales one side's cap), which the probe run's override set to 0.
  `reduceVisits` (cfg:76) lowers a cap and cannot exceed `maxVisits`; the candidate's attribution is
  withdrawn on the row. Counting the 8 scaled full searches as full gives 2319/9211 = 0.2518.
- `playout_cap_randomization` → **solid**: the packet criterion of `tasks/paper_code_map_search` § 2 is met on
  executed runs — (a) 0.2516 in [0.20, 0.30] over 7401 ≥ 500 turns under the discriminator o38 prescribes,
  (b) 34.4 in [12, 35], (c) 0, (d) `gate_random ≥ 1` — with a verification command over committed,
  content-hashed files; predecessors none (the solid-predecessor rule is vacuous). Caveats on the row: two
  runs of one configuration on one net pair; the two 20-game rows stay [UNCHECKED]; the task file's own
  line still spells the defective `N > 100` rule and is superseded by o38 (the band is unchanged, not
  re-tuned).

## 5. Verdicts and rows appended (no `admission_flags` on any row; every gate re-executed its command, exit 0)

| item | verdict | row |
|---|---|---|
| R1 (o39) | Admit, two qualifications (V1g, V1j → o42) | result `r_loop_resume_under_walltime_static` existence_only `d71a81725d379d536931e246b5f04f246d7f6a66d4b15f6bfa8d0157a95f72a5` (amends `ff8a6553…`) |
| R6 (monitor) | Admit, one qualification (V6g → o42) | same row |
| R5 (o02) | Admit, one qualification (V5e/V5f/V5k) | same row |
| R2 (o40) | Admit NARROWED: first export at cycle 5 stands; exactly-one-per-cycle rejected | result `r_cycle_knobs_9x9_derived` conditional `0a88552679f7732078c3b504a497c10962d672fb4a018b0d96c03bc0a77ff1b5` (amends `5f9cc4ed…`) |
| R3 (o41) | Admit as written; residual o43 | same row |
| R4 (o38) | Admit, two corrections (289 distinct; asymmetric playouts) | result `r_smoke_full_frac_rebinned` empirical `84f405044941cf0f2c6dbde1fd2ba98d1fd125001307653ff0dec028191e5899` |
| `playout_cap_randomization` | preliminary → solid | knowledge seq 4 `5fd3d46aa5a3b05331bd7a6dca063af3e32febaa7753dcfffee7c13e1d8fbe44` |
| o39 | discharged (conjunct 3 is o03's, with the chain) | `2d217461f76766fcfbaf77ffc924b8f3a956ee100ddd78f453d0116ad7cc3bb5` |
| o02 | discharged | `f4b9c912c009bd1730ac57c753cb2bc665dd07e24e5e84f0b8f4327be2e6499e` |
| o41 | discharged | `eae601f3e99cddeda1ca78c68d0d326a836cb3cf1f376bac3a9661f266fce17b` |
| o38 | discharged | `a788be4d256f75e5e3e549ca1c13ac0fff4aa9dad77e93a49b74529797680670` |
| o40 | open, amended: (a) closed, (b) re-opened, (c) unchanged, (d) file-count model | `152df871f4e6cb1ef443c7c942e140d0a444d8ebf514776c13f9761cf36345bb` |
| o42 (new) | open, non-blocking: knob-file sourcing holes + stale sampler pids | `16b16040f9d145b8bf4330306d22070980b96da09c361cba2b3f00801123a90a` |
| o43 (new) | open, non-blocking: typed size/thread constants in derive_knobs.py | `20c8cd327d4a24795b258e490edc0f83960b80bc3fbd72935b60da4b4d83e7ad` |
| error ledger | validation partial (5 of 6 as proposed) | `35b22540441cb047845fbd53af6eafbd73aaaf6ea080c421a91fc308dccb0ac4` |
| error ledger | validation fail (R2 exactly-one conjunct) | `4012cfe02793b4f0385e85ac0de8fd46b5ceb5a8831c62e11288e6b1d4e59d53` |

Not admitted: nothing else was proposed. Remaining `[OPEN]`: o40 (b)(c)(d), o42, o43, o03 (the executed
`nlwp_max ≤ 32` conjunct handed over from o39), o33, o36, o25, c07, c08.

## 6. Closing check in a clean environment (real PATH)

`bash -n codes/loop/loop.sbatch && grep -q '^#SBATCH --cpus-per-task=32$' … && grep -q
'REQ_CPUS="${KTG_CPUS_PER_TASK' … && ! grep -n 'cpus-per-task=24\|REQ_CPUS=24' … && bash "$(python3 -c
'…["compute"]["policyCheck"]')" --gpus 1 --cpus 32 --partition b200` → `OK : request gpus=1 cpus=32
part=b200 within policy (gpu<=4, no cpu cap)`, exit 0 (as the admission gate re-ran it on the wrapper row).
Name sweep over the transcript, this record and every appended row: clean. Queue: 299366 PENDING at start
and at the end of this validation.
