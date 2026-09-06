# Validation -- worker packet o50 / o51 / SGF archive (refuter, then judge)

Candidates: worker commits `8eae6e2` (o50, wrapper SIGTERM forwarding), `5b9c419` (o51, per-net rows/game record),
`ec1e7ae` (SGF archive step, default off); candidate rows in `evidence/production_chain/candidate_rows_o50_o51_archive.json`;
worker harnesses in `evidence/production_chain/o50_term_forwarding/` and `/scratch/.../work/o50_o51`.
Validator: cross-model, `CHANDRA_ROLE=validator`, login node, CPU only, no job, no allocation; `runs/p1`, `logs/`, `sacct`,
`scontrol` READ only; jobs 305318 (link 2, RUNNING) and 314831 (link 3, PENDING) never signalled; every execution under
`/scratch/.../work/o50_o51_validator` (copies of the worker's stubs and shims). `mission.json` `compute.policyCheck` not
invoked because no allocation is requested. Clock at start 2026-09-05 20:00 EDT. Validator execution evidence:
`evidence/production_chain/validation_o50_o51_archive/` (harness re-run, link-3 replica logs + drivers, new-wrapper
scenarios, seed/tree checks, pruner plan, wekafs hard-link test).

## 0. Link-3-affecting findings FIRST: nothing in 8eae6e2 / 5b9c419 / ec1e7ae harms link 3. No revert is required.

Link 3 (314831) will run the wrapper Slurm stored at submission (`scontrol write batch_script 314831`, sha256
`9e64864df848...` = `git show cc06834:codes/loop/loop.sbatch`, the PRE-o50 foreground wrapper) but will source the
knob file and the loop script from the repo at its start (~2026-09-06 17:53 EDT): `knobs_9x9.env` sha `78121713b3056309`
and `synchronous_loop_9x9.sh` sha `57306e0d27802033`, and it will run `prune_retention.py` and `scratch_guard.sh` from
the repo too. Established BY EXECUTION on a replica (`link3_replica.txt`, driver `link3_replica_drive.sh`): the stored
wrapper + the HEAD knob file + the loop script at cc06834 (OLD) vs at HEAD (NEW), stub katago, scheduler shims.

| check | OLD loop | NEW loop | verdict |
|---|---|---|---|
| `KTG_STAGE_ONLY=1` dry run | exit 0, staged | exit 0, staged | same (log diff = paths only) |
| one stub cycle (`KTG_ONE_CYCLE=1`) | wrapper 0, .failcount 0, .cycles_completed 1 | same | same |
| one-cycle tree, sha256 of every file (version.txt, monitor pid/samples excluded) | 19 files | 19 files | BYTE-IDENTICAL |
| stage sinks selfplay/stdout.txt, gatekeepersgf/stdout.txt, logs/outshuffle.txt, logs/outexport.txt | | | BYTE-IDENTICAL (cmp) |
| link log | 87 lines | 96 lines | +9 xtrace lines/cycle: `+ tee_through_term`, `+ trap '' TERM`, `+ exec tee -a` for 4 stages, `+ '[' 0 = 1 ']'` for the archive guard; no reader of the link log greps for `tee` (grep over codes/) |
| SIGTERM to the WRAPPER PID ONLY mid-selfplay (the site's form, section 1) | deferred behind the foreground loop; classified after the loop ends | identical | same as links 1-2: link 3 WILL end in a SIGKILL (0:9) at KillWait |
| SIGTERM to the whole process group | `tee` dies ("Terminated"), pipefail 143, classified | engine logs `Exited cleanly after signal`, loop abandons at 143, classified | new is better; both keep the successor |
| group SIGTERM with an engine ignoring it | `tee` dies, loop exits 143 while the engine still runs | loop waits for the engine, then abandons at 143 (no shuffle/train on a cut cycle) | new is better |
| knob file sourced with `set -a` (env diff cc06834 -> HEAD) | | | exactly one line added: `KTG_ARCHIVE_SGF=0`; the old wrapper's classification-knob grep (`KTG_MAX_FAILS|KTG_MAX_CHAIN|KTG_MIN_RUNTIME_SECONDS`) does not match it |
| `prune_retention.py` dry run against `runs/p1`, cc06834 vs HEAD | | | plans IDENTICAL (`prune_plan_head_dryrun.txt`): 1 shuffleddata dir + 4 selfplay generations `t9-s15847040..t9-s17045760` would be removed at link 3's start; all 4 are complete records in the o51 history |
| `check_knobs_9x9.py --knobs codes/loop/knobs_9x9.env --rows-file evidence/production_chain/rows_per_game_history.jsonl --marginal-nets 3 --trend-nets 9 --horizon-nets 10` (acceptance throughput) | | | `CHECK_KNOBS_9X9: PASS`, exit 0 |
| old link-2 verifier `verify_optionc_boundary_1_2.sh` | | | `OPTION_C_EXECUTED_LINK2: sha ba7f1bf7e1bc166d, -max-games-total 1800, whole-file epochs (2 files), r=16.9087 rows/cycle=30435.7 T1=+58.52% rho=3.943`, rc 0 |
| `codes/data_budget/tests/run_guard_tests.sh` | | | `== 25 passed, 0 failed ==` |

Consequence for the chain: link 3 behaves exactly like link 2 at its walltime (SIGKILL, no classification, buffered
tdata rows of the cut cycle lost); o50's fix is first carried by link 4 (submitted by link 3 at its start) and first
observable at the link-4 -> link-5 boundary. Nothing needs to happen before 17:53 tomorrow.

## 1. o50 -- the refutation attempt, and why the result is CONDITIONAL, not empirical

Worker harness re-run at HEAD ec1e7ae: `o50 harness: 47 passed, 0 failed` (`harness_rerun_validator.txt`). Validator
scenarios against the NEW wrapper, SIGTERM to the wrapper pid only (`new_wrapper_scenarios.txt`): TERM during the
GATEKEEPER, during TRAIN (a python child under a `tee`), during SHUFFLE (a subshell pipeline) -- all abandon the cycle
at 143, `scheduler termination at walltime ... successor continues, failcount left at 0`, `.cycles_completed` not
written, 0 leftover processes; an engine that ignores TERM under the DEFAULT 15 s grace: `escalating to SIGKILL` at
+15 s, `loop exited rc=137`, wrapper gone 19.5 s after the signal (10.5 s inside the 30 s KillWait); a second TERM
0.5 s after the first: `SIGTERM not sent: the loop (pid N) has already ended` -- the `LOOP_RC_SET` / `kill -0` guard
works and the end is counted once. `set -m` gives the background loop pgid == pid with no controlling terminal
(`setsid`, stdin `/dev/null`), i.e. under batch-step conditions. The group kill names `-$LOOP_PGID` only when
`LOOP_PGID == LOOP_PID`, a pid forked after the wrapper's own group existed, so it can never name the wrapper's group
or a sibling step; the stage_monitor samplers are the wrapper's children and are stopped by finalize.

Residuals (on the row): pid recycling between the `wait` return and `LOOP_RC_SET=1` is a microsecond window and
confined to this user's processes; a TERM landing between `LOOP_STARTED=1` and `LOOP_PID=$!` is not forwarded (the
old failure mode, microseconds wide); `codes/loop/train_9x9.sh:120` still uses a plain `tee -a`.

The assumption the fix rests on -- slurmstepd sends SIGTERM to the batch script's own pid at the time limit -- is
UNTESTED on a walltime end but supported on this site by `sacct`: `301096.batch` (7x7, trap-less shell, scancel)
`CANCELLED 0:15` one second after the cancel, so the shell WAS sent TERM; `301099.batch` (link 1, time limit)
`CANCELLED 0:9` at KillWait+0 with katago -- same process group as the shell -- never signalled (`Started 780 .. 860
games` through the 29 s, 0 x `Exited cleanly after signal`, `cpp/command/selfplay.cpp:264` confirmed: no game starts
after `shouldStop`). Delivery to the shell's pid, not its group, is exactly Scenario B. Conjunct (iii) of o50 -- one
real boundary logging the two lines -- is not met and cannot be before link 4 -> link 5. Hence: result ADMITTED
`conditional` (not the proposed `empirical`); o50 stays OPEN, amended. The worker's candidate claim row proposed
status `conditional`, which is not an obligation status (open/discharged/waived) -- appended as `open`.
Fallback recorded on o50: `#SBATCH --signal=B:TERM@<t>` if the walltime path does not deliver TERM to the shell.

## 2. o51 -- reproduced; the marginal is a read-time quantity

`verify_o51.sh`: `RECORDS=46 GAPS=1 TAIL_RUN=8` / `O51_ROWS_HISTORY_VERIFIED`; `test_rows_history: 6/6 passed`.
Seed reproduction (`seed_and_tree_checks.txt`): 44 git-derived records IDENTICAL field-by-field to the committed
record; re-append of the 7 versions onto a copy: `appended 0 record(s), skipped 132 already present`, file
byte-identical. Disk check (venv numpy): all 8 recorded nets still in the tree match (games, rows) exactly. models/
index: 61 nets; 37 = `t9-s11352064-d2008893`, 38 = `t9-s11651712-d2059673` (one INCOMPLETE observation, 908 games),
39..50 unrecorded, 51 = `t9-s15847040-d2653436` -> 13 accepted nets without a complete record (the boundary
validator's 12 counted only nets with NO observation). Gap refusal message reproduced verbatim by `check_knobs_9x9`.

Definition the row carries: marginal r = sum(rows)/sum(games) over the 3 NEWEST COMPLETE real-net directories at the
read time of the source (COMPLETE = no longer the newest). All three quoted values are correct under it:
16.9087 = 118361/7000 (boundary read; t9-s17045760, t9-s17345664, t9-s17645440), 16.0361 = 189916/11843 (worker
19:29; t9-s17645440, t9-s17945216, t9-s18225024), 16.2636 = 247906/15243 (validator 20:08; t9-s17945216,
t9-s18225024, t9-s18522368-d443329 5400/91487 -- complete since the worker's read, enters the record at the next read).
Narrowings: N1 the record `t9-s17945216-d2940346` = 6243 games / 94787 rows = 15.183 rows/game embeds the link-1
SIGKILL (its 843 link-1 sgf lines had their buffered tdata rows only partly flushed; the link-2 games in the same
directory run at ~17.2), a fact about the data on disk (right for T1) that depresses the 8-record slope (-0.0871) with
no flag on the record; N2 rows can still lag at the moment a directory stops being the newest -- tolerated by
`latest_by_net` supersession if one more read happens before the prune. Result ADMITTED `empirical`; o51 DISCHARGED;
residual carried by o53 (window 8 of 9) and on the row.

## 3. SGF archive -- byte-neutral at 0 for the tree and the sinks, hard links work on wekafs, decision open

`verify_archive.sh` exit 0. Section 0 gives the at-0 replica (tree and sinks byte-identical; the link log is NOT
byte-identical: +9 xtrace lines/cycle, of which 1 is the archive guard). At 1 on the same wekafs mount as `runs/p1`
(`archive_weka_hardlink.txt`): archived entry same inode (link count 2), `du -sb` delta 0 B, an append to the live
file visible through the archive, second pass `linked=0 already-linked=2`, after `rm -rf` of the generation the
archive holds the last link at full size, `prune_retention.py` prints `PROTECT <basedir>/archive`, `extract_games`
de-duplicates by (source, net, file) (worker harness 6a). scratch_guard measures the mission root, so the archive is
inside the cap and costs blocks only after the original is pruned. Result ADMITTED `conditional` (flag 0; never run
inside a production link); o52 opened for the human: at link 3's start 4 more generations' game records go.

## 4. Rows appended (all `actor_role: validator`, gate exit 0 on every verifier)

| ledger | id | status | row_hash | evidence_sha256 |
|---|---|---|---|---|
| result | r_wrapper_term_forwarding | conditional | `a63ab47e980a5af0...` | `77c69ece458558b2...` (harness_output.txt) |
| result | r_rows_per_game_history | empirical | `9bf55fe0edf3cfc8...` | `b4a7168b3357bda5...` (check_knobs_acceptance.txt) |
| result | r_sgf_archive_available_off | conditional | `9e66a68e1bc1cfc1...` | `e947016b4e61a864...` (archive_output.txt) |
| claim | o50_wrapper_term_not_forwarded_to_loop | open (amended, blocking) | `625df58f20080007...` | |
| claim | o51_persist_per_net_rows_record | discharged by r_rows_per_game_history | `773264430e9b3433...` | |
| claim | o52_sgf_archive_human_decision | open (owner human) | `4ac2233e7449332d...` | |
| claim | o53_trend_window_narrowed_by_the_pre_o51_gap | open | `c38b0b919836d17f...` | |

Verifier outputs, verbatim: `O50_TERM_FORWARDING_VERIFIED: loop launched in its own process group and reaped; SIGTERM
forwarded to that group; katago exits via 'Exited cleanly after signal'; loop exits 143; finalize runs, failcount
untouched, successor kept; no SIGKILL needed (harness 47/47)` / `RECORDS=46 GAPS=1 TAIL_RUN=8` +
`O51_ROWS_HISTORY_VERIFIED: the append-only record carries the pruned nets, names its one gap, never fits across it,
and check_knobs_9x9 reads it and PASSes` / `SGF_ARCHIVE_VERIFIED: KTG_ARCHIVE_SGF=0 in the committed knob file; at 0
nothing is spawned and the KTG_STAGE_ONLY staged tree is byte-identical to HEAD's; at 1 the archiver hard-links, is
idempotent, outlives the prune, and the pruner protects it`. Views re-rendered: `decomposition/results.md`,
`decomposition/{claims,obligations,assumptions}.md`. No error-ledger row: no candidate failed a gate; the o50 claim
row's status was re-shaped, not rejected.
