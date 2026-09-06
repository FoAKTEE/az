# Validation -- the human stop of the 9x9 chain, 2026-09-06 (refuter, then judge)

Candidate: worker candidate `evidence/production_chain/candidate_rows_stop.json` (result id
`r_production_chain_9x9_stopped_by_human`, proposed `empirical`), with `CHECKPOINTS.md`, `verify_stop.sh`, the
`STOPPED BY HUMAN 2026-09-06` block of `status_log.txt`, error-ledger trial `d3cab5b5...` (iteration 22, pass),
and the checkpoint itself at `/home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop` (`README.md`,
`MANIFEST.sha256`).
Validator: cross-model, `CHANDRA_ROLE=validator`, login node, CPU only, no job, no allocation (no policy check
needed: nothing was submitted); `runs/p1`, `runs/t7`, both checkpoint copies, `sacct`, `squeue` READ only. The only
files written are this record, the two ledger rows and the rendered views. Clock 2026-09-06 13:27-13:45 EDT,
HEAD `0e39ba9` at the start.

## 0. Verdict: ADMIT, `empirical` (row `3e4ed3c10a8bb1c1...`), with four wording corrections; o57 opened `[FUTURE]`

Every number in the candidate reproduces from the primary artefacts. Four statements in the candidate's prose were
wrong or stale and are corrected on the admitted row (section 3); none of them moves a claimed figure. The
"single unreplicated copy" residual the candidate listed is not opened as an obligation because a second copy
already exists and verifies (section 2.7).

## 1. The verifier, re-run in full

`bash results/ktg/paper_1902.10565/evidence/production_chain/verify_stop.sh` -- 20 `PASS`, 0 `FAIL`, exit 0,
real 39.7 s (validator's own run) and 34.3 s (the result gate's run at append, output sha256 `22e9f486...`).
The `sha256sum -c MANIFEST.sha256` step is the full 10 956-entry check, not a sample; no sampling was needed.

    PASS  successor 314831 cancelled without running (CANCELLED+ 00:00:00)
    PASS  job 305318 COMPLETED|18:39:50|0:0
    PASS  log: STOP file present at /weka/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/p1/STOP -- exiting the loop cleanly.
    PASS  log: loop exited rc=0 after 67185s
    PASS  log: clean exit -- failcount reset to 0
    PASS  log: cycle 92 complete -- 249 cycle(s) recorded
    PASS  log ends on the finalize line -- nothing ran after it
    PASS  no ktg-loop job in the queue
    PASS  .cycles_completed = 249
    PASS  .failcount = 0
    PASS  STOP present
    PASS  .breaker_tripped absent
    PASS  93 accepted exports
    PASS  checkpoint dir /home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop
    PASS  checkpoint size 7683842860 B
    PASS  10956 files under the manifest
    PASS  MANIFEST.sha256 sha256 ef75ba6c3155593a687daaf70e0b3ef5f0c705af6ec17974e8f12bc0a7efc4d2
    PASS  manifest lists 10956 files
    PASS  sha256sum -c: all 10956 files OK
    PASS  t9-s28711040-d3032547 model.bin.gz sha256 4cbedf24ac86f97f1d15ec69706161e7ac98c3f3a2fddadb543d40bea897f49c

    STOP_VERIFIED: chain stopped clean at cycle 249; 10956 files (7683842860 B) saved and hash-verified at /home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop; best/latest net t9-s28711040-d3032547

## 2. Refutation attempts, by execution -- all failed

### 2.1 Accounting and queue (`sacct -X -n -P`, `squeue -u`)

    301099|ktg-loop|l40s|TIMEOUT|23:30:11|0:0|2026-09-04T18:52:13|2026-09-05T18:22:24|gl111
    305318|ktg-loop|l40s|COMPLETED|18:39:50|0:0|2026-09-05T18:23:21|2026-09-06T13:03:11|gl111
    314831|ktg-loop|b200,l40s|CANCELLED by 30154|00:00:00|0:0|None|2026-09-06T12:59:09|None assigned
    314831 Submit 2026-09-05T18:23:23  Start None  End 2026-09-06T12:59:09

`squeue -u ssci-haiyangw` prints nothing. 23:30:11 + 18:39:50 = 42 h 10 m 01 s, the claimed wall time.

### 2.2 The wrapper log and the dot-state

`loop-305318.log` (6 400 711 B, mtime 13:03) lines 89001-89009 are, in order, `cycle 92 complete -- 249 cycle(s)
recorded`, the `set -x` STOP test, `STOP file present ... exiting the loop cleanly.`,
`=== [2026-09-06T13:03:06-04:00] loop exited rc=0 after 67185s ===`, `stage_monitor: stopped; 64137 ps samples,
13342 gpu samples`, `=== [2026-09-06T13:03:10-04:00] clean exit -- failcount reset to 0 ===`; the file ends there.
Dot-state under `runs/p1` with mtimes: `STOP` 12:59:50.249 (empty), `.cycles_completed` 13:03:06.834 = 249,
`.failcount` 13:03:10.483 = 0, `.chain_depth` 2 (18:23:21 the day before, i.e. link 2's start), `.pos_len_checked`
13:01:56, `.breaker_tripped` absent. `models/` 93, `rejectedmodels/` 3, `modelstobetested/` and
`torchmodels_toexport/` empty. The ordering claimed (cancel 12:59:09 -> brake 12:59:50 -> exit 13:03:06 -> job end
13:03:11) is the ordering of the accounting record and the file mtimes. `train/t9/stdout.txt:57009` `Global step:
28950784 samples`, then `:57020` `Not enough data files to fill a subepoch! Quitting.` -- the cycle-92 trainer exit
without export, 239 744 samples past the last export at 28 711 040. Last `metrics_train.json` row nsamp 28 942 080,
1937 rows.

### 2.3 Source-to-destination parity, every copied component (`du -sb`, `find -type f | wc -l`)

    models             src    903245548 B   372 f | ckpt    903245548 B   372 f  MATCH
    rejectedmodels     src     29159343 B    12 f | ckpt     29159343 B    12 f  MATCH
    modelstobetested   src            0 B     0 f | ckpt            0 B     0 f  MATCH
    train/t9           src     65512917 B     9 f | ckpt     65512917 B     9 f  MATCH
    selfplay           src   1549242381 B   883 f | ckpt   1549242381 B   883 f  MATCH
    shuffleddata       src    657058250 B    78 f | ckpt    657058250 B    78 f  MATCH
    gatekeepersgf      src     38622359 B   443 f | ckpt     38622359 B   443 f  MATCH
    monitor            src     10611451 B     6 f | ckpt     10611451 B     6 f  MATCH
    logs               src      1984452 B     2 f | ckpt      1984452 B     2 f  MATCH
    runs/t7            src   4284227815 B  9100 f | ckpt   4284227815 B  9100 f  MATCH

`cmp` of `wrapper_logs/loop-301099.log` and `loop-305318.log` against `logs/` and of the five dot files against
`runs/p1`: identical. Checkpoint total `du -sb` 7 683 842 860 B, `find -type f` 10 957 (p1 3 271 623 662 B,
t7 4 284 227 815 B, pages 126 394 351 B, code_snapshot 202 364 B, MANIFEST 1 377 406 B, README 17 262 B).
`gatekeepersgf/` 347 entries; t7: job 301096 `CANCELLED by 30154|03:09:19|0:0|2026-09-04T17:14:35|2026-09-04T20:23:54`,
77 accepted / 11 rejected, latest `t7-s2449568-d319559` -- every README figure for t7 reproduced.

### 2.4 Games

Per-cycle maxima of the `Started N games with <net>` counter, reset at each `cycle N complete` line, over the two
saved wrapper logs: link 1, 157 completed cycles, distinct maxima {1000}, 157 000 games, trailing partial (walltime
kill) 860; link 2, 92 completed cycles, distinct maxima {1800}, 165 600 games, trailing partial 0. Sum 322 600.
`cat p1/selfplay/*/sgfs/*.sgfs | wc -l` = 183 443 over 110 files (42 selfplay net directories, not the 38 the
candidate carried from the retention-60 read).

### 2.5 The export-to-metrics join and the best-net claim -- the one substantive correction

`metrics_train.json` rows have nsamp values that are NOT multiples of 12 800 (1915 of 1937 are not) and **no export's
sample count coincides with any row's nsamp (0 of 93)**. The candidate's "matched exactly for 93 of 93 exports at the
same nsamp ... no interpolation or nearest-neighbour fallback" is therefore false as stated. What the worker's figures
actually are: the LAST row with nsamp <= the export's sample count (for `t9-s28711040` that is row 28 702 208, gap
8 832; max gap over the 93 exports 9 088; 93 distinct rows). Under that rule, and identically under the nearest-row
rule:

    latest     t9-s28711040-d3032547  p0loss 1.468345  pacc1 0.546604  vloss 0.605518
    min p0loss t9-s28711040-d3032547  1.468345          (strict, all 92 others higher)
    max pacc1  t9-s28711040-d3032547  0.546604          (strict, all 92 others lower)
    min vloss  t9-s1762560-d595534    0.569050  with p0loss 2.734, pacc1 0.362

so the best-net claim and the raw-vloss counterexample both stand; the admitted row states the join as it was done.
The export's own `metadata.json` (`global_step_samples` 28711040, cumulative sums) is what read 14 used
(p0loss 1.468828, pacc1 0.546105); it ranks the top net the same way.

Record history under the metric-row join: the p0loss record fell at exports 90, 91, 92 (1.484135, 1.477058,
1.468345); the pacc1 record stood at `t9-s20919936` (0.545048) until export 92 (0.546604). The candidate's "both
records broken on each of the last three exports" and README section 3's "both records" label on `t9-s28411648`
(whose metric-row pacc1 is 0.544421) hold only under the metadata reading (0.545393 at read 14); the admitted row
says which is which. Gate figures in the README table (93.5, 77.0, 64.5, 73.0, 65.5) reproduce from the wrapper log
(`Candidate won match, score 100.500 to 65.500 in 166 games, accepting candidate t9-s28711040-d3032547` etc.); they
are the incumbent's points at the 100.5 acceptance threshold, not "out of 100 games" -- units line corrected.

### 2.6 README consistency with the wrapper, and the knob caveat

README section 7 against `loop.sbatch` (working tree = commit ec1e7ae's copy in `code_snapshot/`): resume from
`.cycles_completed` and the newest `models/` directory (`CYCLES_FILE`, loop.sbatch:228; selfplay loads the newest
accepted net); `rm STOP` required because `resubmit()` refuses on `STOP` (loop.sbatch:630-631) and the loop exits at
the top of its first cycle (`synchronous_loop_9x9.sh:426-429`); `.chain_depth` against `KTG_MAX_CHAIN=200`
(loop.sbatch:135, 638-640) so resetting it to 0 is optional, as the README says; the compute-policy check resolved from
`mission.json compute.policyCheck` (loop.sbatch:107, 651-660) with `--gpus 1 --cpus 32 --partition b200,l40s`;
`sbatch --partition=b200,l40s codes/loop/loop.sbatch` from the repo root; the clean-exit branch (loop.sbatch:560-563)
indeed does not cancel the successor. Consistent throughout. Knob caveat: the wrapper log line 3 reads
`knobs_9x9.env (sha256 ba7f1bf7e1bc166d)` = `git show ff5d0eb:...knobs_9x9.env`; the checkpoint copy and the working
tree are `78121713b3056309...` = commit ec1e7ae; `git diff ff5d0eb ec1e7ae` on that file has exactly one non-comment
line, `+KTG_ARCHIVE_SGF=0`.

### 2.7 A second copy exists and verifies

`/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/checkpoints/2026-09-06_stop`: 10 957 files, `du -sb`
7 683 842 860, `MANIFEST.sha256` byte-identical to the /home copy (`cmp`), `sha256sum -c` in that directory 10 956 OK
/ 0 not OK (36.4 s), `README.md` identical, no file newer than 13:25 EDT. So the candidate's "single copy" residual is
already met in the sense of a second manifest-verified copy. Both copies are on the same weka cluster
(`wekafs1/homessci` and `wekafs1/scratchssci`); there is no off-cluster copy, and that is what the admitted row's last
open item now says. No obligation is opened for it.

### 2.8 Names

`grep -i` for AI tool / model / vendor names over the checkpoint `README.md`, `code_snapshot/`, `CHECKPOINTS.md`,
`verify_stop.sh` and `candidate_rows_stop.json`: no match.

## 3. What the admitted row changes relative to the candidate

1. The join statement (section 2.5): preceding-row join, 0 of 93 exact, gap 0-9088 samples.
2. The record-history sentence in the first open obligation: p0loss record on each of the last three exports,
   pacc1 on the last (metric-row join).
3. 42 selfplay net directories at the stop (38 was the retention-60 read).
4. The gate units line in `working_context.units`.
5. The replication residual restated as "two copies, both on wekafs1, none off-cluster".

## 4. Rows appended (`CHANDRA_ROLE=validator`)

- result `r_production_chain_9x9_stopped_by_human`, `empirical`, row hash `3e4ed3c10a8bb1c13216265170499cee35a7969e90c546bf83f4648b2f9fe91a`,
  evidence sha256 `a61fde1403d3d050016e9d2dbfd3fc5cc23831edf9debb7ec9c54c87b6d7aa64` (`CHECKPOINTS.md`), no admission flags,
  gate re-ran `verify_stop.sh` exit 0.
- obligation `o57_final_net_match_latest_vs_c14_challenger`, open, `[FUTURE]`, row hash
  `643dc1218bd18612bc74caf4b616a4e3fee94a1bed8d8c17733f9bed28657e80`: 400 games, 200 per colour, 150 visits,
  `t9-s28711040-d3032547` vs `t9-s27212800-d2664932` from the checkpoint copy, one 1-GPU job after the policy check.

The worker's candidate row was never appended; the error-ledger trial `d3cab5b5...` stands as the worker's record of
the stop. Nothing in `runs/p1`, `runs/t7` or either checkpoint copy was modified.

## 5. Validator scripts (recorded, not tracked)

Join: read every line of `p1/train/t9/metrics_train.json`, sort by `nsamp`; for each `p1/models/t9-s<S>-d<D>` take
the row at `bisect_right(nsamp, S) - 1`; rank by `p0loss`, `pacc1`, `vloss`; repeat with the nearest row. Counter:
stream each wrapper log, track `max` of `Started (\d+) games with`, emit and reset at
`^cycle \d+ complete -- \d+ cycle\(s\) recorded`.
