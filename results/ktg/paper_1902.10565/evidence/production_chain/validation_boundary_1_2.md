# Validation -- link 1 -> link 2 boundary of the 9x9 production chain (refuter, then judge)

Candidates (worker commit `ebbc623`, evidence `evidence/production_chain/status_log.txt` sha256 `262d9c80...`,
worker verifier `$KTG_ROOT/runtime/verify_optionc.sh`):
(a) result `r_cycle_knobs_9x9_derived` amended conditional -> empirical by the WORKER, row_hash `284ec0e8d41f4a2a...`;
(b) error row P9 `arxiv-1902.10565::verify_preemption_resume` pass_fail partial, row_hash `7d0abe7d57bf44b1...`.
Validator: cross-model, `CHANDRA_ROLE=validator`, login node, CPU only, no job, no allocation; `runs/p1` and
`logs/loop-30{1099,5318}.log` READ and never written; `mission.json` `compute.policyCheck` not invoked because no
allocation is requested. Clock at start 2026-09-05 18:45 EDT; link 2 (305318) RUNNING on gl111/l40s, 314831 PENDING.
Every number below was recomputed from the raw logs, `sacct`, `scontrol`, the selfplay tree and the reference code.

## 0. Link-2 / link-3-affecting findings FIRST

1. **The wrapper's TERM trap cannot run on the walltime path -- by construction, on every link (o50, BLOCKING).**
   Slurm's notice landed at 18:22:24.034; the batch step ended at 18:22:53 (sacct `301099.batch CANCELLED 0:9`,
   `KillWait = 30 sec`). In those 29 s katago logged `Started 780 ... 860 games` at its unchanged 3 s cadence and
   never `Exited cleanly after signal` (`cpp/command/selfplay.cpp:26-32,264,396-397`). So the SIGTERM did not reach
   the loop's foreground pipeline (`synchronous_loop_9x9.sh:380`, `time katago ... | tee`). The wrapper runs
   `bash "$LOOP_SH"` in the FOREGROUND (`loop.sbatch:820`) and bash defers a trap until the foreground command
   returns (the wrapper's own header, `:324-328`, says so and assumes the loop dies of the same signal). Whether the
   wrapper bash got the TERM is undecidable from the log and immaterial: `on_term`/`finalize` could only run after
   the loop died, and the loop died at the SIGKILL that killed the wrapper too. Nothing was written; `say` is an
   unbuffered echo, so "fired and failed to write" is excluded. Link 3 (314831) stores the same wiring.
   Consequence: the worker's P9 attribution ("documented o25 residue, no fix owed, two boundaries remain to settle
   it") is wrong -- the residue is the only path this wiring admits.
2. **Successor-id parse defect: fixed from link 3, not link 2.** `scontrol write batch_script`:
   305318 stores sha256 `8e394116...` = `git show 4c30b00:...loop.sbatch` (pre-o46; submitted by link 1 at
   2026-09-04T18:52:22, before the fix `b1e25d9` at 19:41:50) -- hence link 2's `sbatch did not return a job id --
   chain not extended: [BILLING] loaded!` at 18:23:23 while 314831 existed, and `SUCCESSOR=""` in link 2 (its
   `cancel_successor()` cannot fire either). 314831 stores `9e64864d...` = repo HEAD = `b1e25d9`;
   `sacct -n -j 314831 -o SubmitLine`: `sbatch --parsable --partition=b200,l40s --dependency=afterany:305318
   /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/loop/loop.sbatch`, Submit 2026-09-05T18:23:23.
   General rule recorded: Slurm snapshots the script at submission, so a fix committed during link N is carried by
   link N+2 at the earliest (link N+1 is already stored). No `runs/p1/scripts/dated/*/loop.sbatch` copy exists.
3. **o48's r_lo leg: not computable from the live tree, computable from a persisted record (o48 amended, o51 new).**
   See section 4.

## 1. Re-verification of the result candidate (a)

| conjunct | worker | validator (source) | verdict |
|---|---|---|---|
| knobs sha logged by link 2 | ba7f1bf7e1bc166d | `loop-305318.log:3` same; link 1 logged 5ae5358791974ae1 (`loop-301099.log:7`) | confirmed |
| `-max-games-total 1800` | yes | 2 occurrences in link 2 (lines 225, 1045); link 1: 158 x `1000` | confirmed |
| epoch = whole files | 2 files, 54390 + 55052 | `train/t9/stdout.txt:35786-35821` two `This subepoch, using files: [...183427/train/data{0,1}_0.npz]`, then `Not enough data files to fill a subepoch! Quitting.`; numpy `shape[0]` 54390, 55052 (109442); cycle 2 repeats on `...184548` | confirmed, cycle 2 adds a second instance |
| shuffle window | 109.4K | `loop-305318.log:656` 109.4K; cycle 2 `:1476` 112.7K | confirmed |
| marginal r | 16.9087 | (33981+50883+33497)/(2000+3000+2000) = 118361/7000 = 16.9087 from `rows_per_game.txt` | confirmed |
| rows/cycle, T1 margin | 30435.7, +58.52 % | 1800 x 16.9087 = 30435.7; /19200 - 1 = +58.52 % | confirmed |
| rho | 3.943 | 120000/30435.7 = 3.943 | confirmed |
| link-1 rho "7.084" | 7.084 | 120000/(1000 x 16.9087) = 7.097 at the same marginal; 7.084 is read 8's marginal | imprecise, 0.2 %, narrowed N2 |
| cycle wall | 0.212 h | 18:23:21 -> `cycle 1 complete` (18:36:07, worker poll) = 0.212 h; cycle 2 -> `.cycles_completed` mtime 18:47:00 = 0.181 h | confirmed |
| "2763 = 860 partial + 1800" | 2763 | sgfs files: `B03ACEAE...` 843 lines (link 1, mtime 18:22:53; 860 started, 17 in flight lost), `8A105E00...` 1800 (cycle 1), `2979CDFF...` 1800 (cycle 2), `47F2783F...` in progress; 2763 = 843 + 1800 + ~120 of cycle 2 at counting time | arithmetic inconsistent in the narrative, not in the row; N3 |
| export cadence | "left open" | 0 exports in 2 link-2 cycles; `torchmodels_toexport/` empty; `models/` 58 | NOT MET -- the conditional row's upgrade clause named it |
| worker verifier | exit 0 | `bash .../runtime/verify_optionc.sh` -> `OPTION_C_IN_FORCE_ON_LINK2: sha ba7f1bf7e1bc166d, 1800 games, whole-file epochs`, exit 0 | confirmed |

Gates: evidence type (empirical measurement) matches; units/regime consistent; dependencies resolve; no circular
evidence (the verifier reads the link log and trainer stdout, not the status log). Two failures against the WORKER
ROW: (G-role) the status promotion was appended under `actor_role: worker` -- under the admission contract ("the
agent proposes; the verifier admits") and spec 2-work ("the judge admits by running the ledger append") the promotion
is the validator's append, and every prior row of this result_id (28 rows) was validator-appended; the worker's row
is therefore a candidate that landed in the canonical ledger, not an admission. (G-scope) the claim says "meets the
conditions the conditional row named" while one named condition (export cadence) is unmet. Neither defeats the
measured substance, so the outcome is **ADMIT, narrowed** by the validator's own append:
row_hash `6cf5454dd5c950f1...`, timestamp 2026-09-05T22:57:22Z, status empirical, verifier
`evidence/production_chain/verify_optionc_boundary_1_2.sh` (persistent sources only: link log, trainer stdout,
committed `rows_per_game.txt`), output
`OPTION_C_EXECUTED_LINK2: sha ba7f1bf7e1bc166d, -max-games-total 1800, whole-file epochs (2 files), r=16.9087
rows/cycle=30435.7 T1=+58.52% rho=3.943`, exit 0, evidence_sha256 `0f9708e80e18aaf2...`.
Narrowings: N1 export cadence stays conditional/open; N2 rho comparison 7.097; N3 sgf-line decomposition corrected.

## 2. Re-verification of the P9 candidate (b)

Numbers: ALL confirmed (see the error row `51a9800e08e3a0e3...` observed field): sacct TIMEOUT 23:30:11 / batch 0:9;
0/0/0/0/0 classification strings; last selfplay line 18:22:53; resume half -- `chain depth 2/9, failcount 0/3,
cycles completed so far 157`, 0 re-init, 0 `No preexisting checkpoint`, 0 `*.tmp`, 0 orphan `*.exported`, models 58,
rejected 2, tobetested 0, `.chain_depth` 2, `.failcount` 0, STOP/`.breaker_tripped` absent, monitor files rewritten
at 18:23; kill in selfplay of cycle 158 at 860 started / 843 completed; gate rejections 92.5-100.5 in 193 games
(14:28:21, t9-s14348544-d2433175) and 96.5-100.5 in 197 games (16:47:39, t9-s16446720-d2737483), 58 accepted.
Attribution: FAILS (kernel section 1, fact-driven attribution) -- see section 0.1. Outcome **FAIL**: validator
error row `51a9800e08e3a0e3...` (2026-09-05T22:59:20Z, node_seq 2, pass_fail fail, metric
`P9_root_cause_supported_by_evidence` 0/1), obligation **o50** opened (blocking; owner loop_resume_under_walltime;
earliest carrier link 4). Chain continuity is not at risk: the afterany successor is queued first and ran.

## 3. Successor-id defect -- see section 0.2. o46 stays discharged; effective from link 3 (314831).

## 4. o48 trend leg

`prune_retention.py` (KTG_KEEP_SELFPLAY_GENERATIONS=3 plus the shuffle-window guard) removed 52 selfplay
generations (1393149275 B) at link-2 start; 7 directories remain, 6 complete. `rows_per_game.txt` is regenerated
from the tree, so the 9-net fit had 6 points. The quantity is NOT undefined: from the 7 committed versions of
`rows_per_game.txt` the validator recovered 46 per-net records (45 complete); 12 accepted nets
(t9-s11951360-d2093144 .. t9-s15547392-d2603142) have no record anywhere. With the accepted-net index taken from
`models/` (58 entries, never pruned), the last 9 recorded complete nets (indices 36-38, 52-57: 17.091, 16.736,
16.927, 16.947, 16.727, 17.007, 16.991, 16.961, 16.748) give slope -0.0017 rows/game per accepted net, marginal
16.9087, r_lo 16.892 against the 11.733 trigger -- reported, not relied on, because it spans a 13-net gap.
Decision: the leg is REWORDED, not dropped (it is the leg that fires first at any |slope| >= 0.2333):
**o48 amended** (row `579b670b4ff32eef...`) -- slope and r_lo from the persisted record, marginal from the tree, and
a read that cannot compute the leg says so; **o51 opened** (row `27d8f796a2f0685d...`, blocking for o48's leg) --
measure_stage_throughput appends an append-only per-net history seeded from git, check_knobs reads it and refuses
to fit across a gap.

## 5. Fact for the human (no change made): retention deletes the SGF game records

`selfplay/<net>/sgfs/*.sgfs` are removed with the generation directory (link 2's prune removed `random`,
`t9-s143744-d157367`, ... 52 generations). `gatekeepersgf/` is not a pruning target (222 dirs, 24.4 MB, intact).
Measured 77386206 B / 22648 games = 3.42 kB per selfplay game on disk. Per link: 157 cycles x 1000 games = 0.54 GB
(link 1); a 1800-game link of ~110 cycles = 0.68 GB; a nine-link chain about 5.5 GB = 1.1 % of the 500 GiB budget
if the sgfs were archived before pruning. The viewer snapshots under `runtime/games_viewer/p1` hold `games.json`
(link 1 cycles 1-63, 65k games, 9.2 MiB; further cycle-range pages), not the SGFs; link-1 cycles whose generation
was pruned are recoverable only from those pages.

## 6. Rows appended (all `actor_role: validator`)

| ledger | id | row_hash | outcome |
|---|---|---|---|
| result | r_cycle_knobs_9x9_derived (empirical) | 6cf5454dd5c950f1... | ADMIT, narrowed N1-N3 |
| error | verify_preemption_resume, node_seq 2, fail | 51a9800e08e3a0e3... | FAIL (attribution) |
| claim | o48 amended (open, blocking) | 579b670b4ff32eef... | r_lo leg reworded |
| claim | o50 new (open, blocking) | 1d817c8c64ef7e4c... | wrapper TERM wiring |
| claim | o51 new (open, blocking) | 27d8f796a2f0685d... | persisted per-net record |

Views re-rendered: `decomposition/results.md`, `decomposition/{claims,obligations,assumptions}.md`.
