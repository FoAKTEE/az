# Validation -- c14 matches and the retention-60 preparation (refuter, then judge)

Candidates: worker commits `3c3b5dc` (c14, job 317503; `evidence/production_chain/c14_match_9x9/`, candidate row
`candidate_result_row_c14.json`, error row `d8c9fb6f...`) and `07a0933` (retention 60 prepared, not applied;
`evidence/production_chain/retention_60/`, error row `a7ebc72c...` refuting `knobs_9x9.env:198/226`). Context:
`vloss_escalation_memo.md` sections 3.5 and 6.
Validator: cross-model, `CHANDRA_ROLE=validator`, login node, CPU only, no job, no allocation (`mission.json`
`compute.policyCheck` not invoked because none was requested); `runs/p1`, `runtime/matches`, `logs/`, `sacct`,
`scontrol` READ only; jobs 305318 (link 2, RUNNING on gl111) and 314831 (link 3, PENDING afterany) never signalled;
the retention patch was NOT applied; every execution under the validator's scratchpad (constants copies, stub trees) or
under `runtime/guard_tests.*` (the guard test suite's own scratch). Clock 2026-09-06 10:58-11:15 EDT, HEAD `3c3b5dc`.

## 0. Anything that would make applying KEEP=60 before link 2 ends unsafe: NOTHING FOUND. Two things to know.

1. **The deadline is "before job 305318 ends", not "before 17:53:21".** 314831 starts on `afterany:305318`, so it
   starts immediately if link 2 dies early too. Link 2 is healthy (`.failcount 0`, 239 cycles completed, cycle 82 of
   the link done at 11:01), so the walltime end 17:53:21 EDT is the expected time; apply as soon as the decision is
   made rather than near the deadline.
2. **The edit reaches link 3 through the repo working tree, not through Slurm.** The wrapper Slurm stored for 314831
   is sha256 `9e64864df8482805` (the pre-o50 wrapper of commit `b1e25d9`, as the previous validation record found);
   it resolves `PRUNE_RETENTION` from `KTG_CODES = $AZ_ROOT/results/ktg/paper_1902.10565/codes` (stored script :64,
   :77, :754) and the pruner reads `budget.env` beside itself. An uncommitted edit is therefore already live for the
   next link; commit it in the same step so the log and the chain agree (`apply_c1.sh` says so).

Checked by execution, all negative for harm at 51 <= 60 generations:

| what could differ at 60 | check | result |
|---|---|---|
| ordering (`entries()` sorts by mtime) | stub C, mtime scrambled | plan 0 at 60 (45 at 3); the keep-N slice `sp_gens[:len-60]` is empty |
| min-age | shuffleddata rule only; plan identical at 3 and 60 in A, B, C and on `runs/p1` | identical |
| protect list | live tree: 18 entries at 3 and at 60, `diff` empty | identical |
| shuffle-window guard (`oldest retained shuffle window`) | never reached at 60 (empty slice); still in the code path | not bypassed |
| `scratch_guard.sh` | `run_guard_tests.sh` on a KEEP=60 constants copy | `== 25 passed, 0 failed ==` |
| `cleanup_old_dirs.py` (shuffleddata, after every shuffle) | untouched; the pruner's identical rule finds nothing | no change |
| wrapper / loop / knob checks consuming the constant | `grep KEEP_` over loop.sbatch (HEAD and the stored 314831 copy), synchronous_loop_9x9.sh, knobs_9x9.env, derive_knobs.py, check_knobs_9x9.py | none; `derive_knobs.py:510-513` read only the four other KEEP_ constants |
| `check_knobs_9x9.py` default / production evidence | before the edit | `PASS`, exit 0 / `PASS`, exit 0 (unchanged by construction) |
| `apply_c1.sh` without `--yes` | run | exit 3, "REFUSING ... Nothing was changed", `budget.env:55` still `=3` |
| `git apply --check apply_c1.diff` on HEAD 3c3b5dc | run | OK |
| shuffle cost | window 509k rows vs 422k at link 2's end; `shuffle.py` loads the window, not the tree | same regime |

## 1. c14 -- ADMIT, `empirical` (row `r_c14_latest_beats_best_by_loss_9x9`, hash `ef5cfeebdc87ef36...`)

Refutation attempts, all failed:

- **Recount from the raw records with an independent parser** (SGF property extraction over the 36 `.sgfs` files, not
  the worker's regex). All 36 sha256 / line counts / byte sizes match `sgfs_manifest.txt`; the scratch copies under
  `runtime/matches/2026-09-06/<arm>/match-317503/` are byte-identical to the evidence copies. Arm A: 400 games,
  W 282 / L 89 / D 29, score 296.5, p 0.74125, se 0.021897, CI [0.6983, 0.7842], Elo +182.8; latest as Black
  w129 l59 d12 (135/200 = 0.6750 [0.6101, 0.7399], Elo +127.0), as White w153 l30 d17 (161.5/200 = 0.8075
  [0.7529, 0.8621], Elo +249.1); White pooled 226.5/400 = 0.5663; RE kinds B+ 159 / W+ 212 / draw 29; every game
  `SZ[9] KM[7] HA[0]`. Arm B: 400/400, 200/200 by colour, RE B+ 200 / W+ 200. Clopper-Pearson (bisection, checked
  against `(0.025)^(1/400) = 0.9908` at k = n): arm A decisive 371 -> [0.7133, 0.8027], Elo [+158.4, +243.7]; arm B
  [0.9908, 1.0000], Elo > +813.3. Every recorded field reproduced.
- **Nets pinned by content.** sha256 of the three snapshot `model.bin.gz` == `runs/p1/models` (read-only):
  `d207dfb0...` latest, `c5893238...` s20919936, `859c58d6...` s143744. The match logs' `nnModelFile0/1` lines name
  the snapshot paths; the job log re-verified both baselines (`job-317503.out:11`, `:250`). The `armB_check` manifest
  written by `freeze_baseline.py` agrees with the hand-written arm-B manifest (same first_model, sha256).
- **Config.** 19 keys diffed across `match_first_latest_9.cfg`, `selfplay_9x9.cfg`, `gatekeeper_9x9.cfg`: the rule
  block is identical in all three; `komiAuto false / komiMean 7`, `handicapProb 0.0` and `maxVisits 150` are the
  documented differences (selfplay: komiAuto True, komiStdev 1.0, handicap 0.10, 600 visits; the gate: 150 visits).
- **Policy check genuine.** `policy_check.txt` timestamp 10:25:21; `sacct` Submit 10:25:27, Start 10:37:53, End
  10:44:44, `b200`, `gb203`, `cpu=32,gres/gpu=1,mem=64G`, COMPLETED 0:0, Elapsed 00:06:51.
- **Best-by-loss net.** From `metrics_train.json` (last row <= export samples) the best p0loss (1.484822) and best
  pacc1 (0.545048) both sit at export t9-s20919936; 21 accepted exports follow it at the validator's read (the
  candidate's "19" counted from the memo's export, plus one rejected export).

Confounds, carried on the row as caveats (an `empirical` row, none hidden): one measurement at 150 visits, transfer to
selfplay's 600 untested; arm B saturated (bounds, does not measure); komi-7 White edge 0.566 pooled, symmetric by the
200/200 pairing; the bot called `first` in arm A's SGF headers is t9-s20919936. Evidence type (statistical inference
from hashed records) matches the claim; no circular evidence (records, manifests, model hashes and sacct are independent
of the worker's analysis code). Verifier at append: `verify_c14.sh` exit 0, tail `C14_VERIFIED: p(latest vs
t9-s20919936) = 0.7412 >= 0.60`.

## 2. Retention 60 -- ADMIT, `conditional` (row `r_retention60_prepared_not_applied`, hash `d97611abbcf5479f...`)

Reproduced by execution (own copies of `prune_retention.py` sha `c07bc668...` + `budget.env` at 3 and 60):

- **Prune plans on the live `runs/p1` at 11:01:** KEEP=3 -> 33 paths / 1,207,468,520 B (worker at 10:28: 32 /
  1,131,433,908 B; one more generation completed since); KEEP=60 -> 0 paths / 0 B; 18-entry protected sets
  path-identical.
- **Stub trees** (script relocated to the scratchpad, same geometry): A 46 -> 0, B 90 -> 35 (exactly 60 survive),
  C 45 -> 0 -- the worker's numbers exactly. **Scenario D differs**: on the local scratchpad both constants files prune
  to 4 survivors with `cannot reach 1000000 B` (the worker's wekafs run gave 48 at 60). The difference is `du -sb`
  directory accounting on different filesystems against a 1 MB target; it does not touch link 3 (the loop never passes
  `--target-bytes`) but it shows that KEEP is not a floor inside rolling mode.
- **Window formula:** the transcription of `shuffle.py:414-435` reproduces **82 of 82** `Desired num rows` lines of
  `loop-305318.log` (321,499 -> 2,786,448 rows on disk; the worker checked 9). Projection: window(3,788,433) = 509,034;
  window(3,788,433 - 46 x 79,961) = 52,976 (the worker's 110-125k band assumes 5 survivors of 360-440k rows; both are far
  below KEEPROWS). `synchronous_loop_9x9.sh:506` passes `-min-rows 25000 -keep-target-rows 120000 -taper-window-scale
  50000`; no `-max-rows`, no `-add-to-data-rows`.
- **Scratch from the live tree:** 30 complete link-2 generations average 38,819,988 B (tdata 23,103,948 + sgfs
  15,716,040), 4,620 games, 3,402 B/game (worker: 39,150,047 B, 4,655 games, 3,402 B/game); 31 accepted nets over
  15.63 h = 1.92/h; 30,431 rows/cycle; projected 51.1 generations at 17:53. The worker's 2.01 GiB / 7.32 % of cap
  stands (`scratch_guard_now.txt` 6.88 % measured at 10:30).
- **Knob-file refutation** (`verify_keeprows_refutation.sh`): exit 0, first three link-2 windows 109,442 / 112,661 /
  115,719 < 120,000. Both comments at `knobs_9x9.env:198` and `:226` are still in the file, unedited.

Narrowings written into the row:

- **The closing condition's vloss leg is sharpened.** Consecutive `metrics_train.json` rows never differ by more than
  0.0034 even across the last boundary, so "no vloss step > 0.005" read row-to-row would have PASSED the defect it is
  meant to catch. Read as the excursion of the first 6 link-3 rows over the last link-2 row it discriminates: last
  boundary +0.0117 (12 rows: +0.0144); link-2 steady state after 19 M samples, 580 windows, max 0.0038, zero above
  0.005. Closing condition: (a) `loop-314831.log` prune block removes no `selfplay/t9-*`; (b) the first two link-3
  metrics rows show window >= 380,000 (last boundary: 238,185 and 109,660); (c) max vloss over the first 6 link-3 rows
  minus the last link-2 row <= 0.005.
- **Link-4 residual, not on the worker's page:** at KEEP=60 the link-4 boundary deletes ~35 of ~95 generations and
  the window steps ~781,584 -> ~593,914 rows (-24 %). KEEPROWS still binds there (keep_prob ~0.20), so the
  keep_prob-1.0 over-training signature cannot recur; the step is a distribution change the link-3 -> link-4 read
  must report.
- **The memo's `check_knobs_9x9.py --marginal-nets 3 --trend-nets 9 --horizon-nets 10` exits 1 today**, before any edit
  (`--rows-per-game-lower 17.0278 is above --rows-per-game 17.0278`): rows/game turned upward and `derive_knobs.py`
  refuses a carried lower bound above the measurement. It is an o48/o53 item, not this patch's.

Verifier at append: `verify_retention60.sh` exit 0, tail `RETENTION60_VERIFIED: patch applies and is NOT applied
(budget.env:55 = 3); ... +2.01 GiB, 7.32 % of the 500 GiB cap`.

## 3. Claim-ledger transitions (all `open`, validator-appended)

| entry | hash | what changed |
|---|---|---|
| `o52_sgf_archive_human_decision` | `3322fbd1bdecac3e...` | amended with the quantities: at KEEP=3 link 3 deletes ~46 generations / ~203k games / ~659 MiB of records (33 generations already deletable at 11:01); at KEEP=60 it deletes 0 but the link-4 boundary deletes ~35 / ~163k games / ~530 MiB -- deferral, not archive |
| `o54_models_dir_unbounded` | `64789499bf709bd9...` | new: `models/` has no retention rule (854.6 MB / 89 nets, ~18 MiB/h); any rule must keep the directory names, which are o51's accepted-net index |
| `o55_knobs_comment_keeprows_correction` | `2097ddfcb58475bf...` | new: the `knobs_9x9.env:198/226` correction, to land with the retention decision, no knob value may change |
| `o56_plateau_rule_against_match` | `ca74838f88f7b64e...` | new: the 9x9 stall rule to be written against a periodic match, not p0loss/pacc1 |

The c14 row's two other `[OPEN]` items (arm-B ladder, 600-visit repeat) stay on the row; each is one more 1-GPU job
under the compute policy and neither is owed before link 3.

## 4. Verbatim verifier output

```
$ bash results/ktg/paper_1902.10565/evidence/production_chain/c14_match_9x9/verify_c14.sh
armA_vs_s20919936: 296.5/400  p=0.7412  se=0.0219  CI=[0.6983,0.7842]  Elo=+182.8
   colour split verified 200 B / 200 W; every field reproduced
armB_vs_first: 400/400  p=1.0000  se=0.0000  CI=[1.0000,1.0000]  Elo=inf
   colour split verified 200 B / 200 W; every field reproduced

C14_VERIFIED: p(latest vs t9-s20919936) = 0.7412 >= 0.60 -- the 19-export loss stall is NOT a strength stall; memo option (b) LR x0.5 is NOT triggered
EXIT=0

$ bash results/ktg/paper_1902.10565/evidence/production_chain/retention_60/verify_retention60.sh
projection.json: keep60 boundary step 0 rows; keep3 step -398871..-383735; KEEP=60 peak 7.32 % of the 500 GiB cap; delta 2.01 GiB
RETENTION60_VERIFIED: patch applies and is NOT applied (budget.env:55 = 3); prune plan
  32 paths / 1131433908 B at keep 3 vs 0 paths / 0 B at keep 60 with an identical
  18-entry protected set; stub 46->0 at the link-3 geometry and 90->35 (60 survivors)
  at the link-4 geometry; window formula reproduces all 9 log points; boundary step 0
  rows at keep 60 against -384k..-399k at keep 3; +2.01 GiB, 7.32 % of the 500 GiB cap
EXIT=0

$ sacct -n -j 317503 -o JobID,Partition,State,ExitCode,Elapsed,AllocTRES,NodeList,Submit,Start,End -P
317503|b200|COMPLETED|0:0|00:06:51|billing=32,cpu=32,gres/gpu=1,mem=64G,node=1|gb203|2026-09-06T10:25:27|2026-09-06T10:37:53|2026-09-06T10:44:44

$ bash .../retention_60/apply_c1.sh          (no --yes)
REFUSING: option c1 is PREPARED, not applied. The human has not decided.
Re-run with --yes (or KTG_C1_CONFIRM=1) once the decision is made. Nothing was changed.
EXIT=3
$ git apply --check .../retention_60/apply_c1.diff    (HEAD 3c3b5dc)  -> OK
$ bash tests/run_guard_tests.sh   (KEEP=60 constants copy)   -> == 25 passed, 0 failed ==
```
