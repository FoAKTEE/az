# Validation of the sixth repair packet (o46, successor id past the site's stderr banner) — `loop_resume_under_walltime`

Role: validator (refuter, then judge), cross-model relative to the worker. Inputs received: the candidate rows
`evidence/loop_resume/candidate_rows_repair6.json`, the worker transcript `evidence/loop_resume/repair_sbatch_id.txt`
(sha256 `86428fc3…`, 1941 lines, equal to the candidate file's hash), the artifacts under test `codes/loop/loop.sbatch`
at `9e64864d…` and `codes/eval/chain_status.sh` at `b43c8a49…` (commit `b1e25d9`; the pre-repair files `8e394116…` /
`557f7fe9…` re-read from `git show b1e25d9^:`), `mission.json` (`compute.policyCheck`), the task file § 2, the contracts
and the ledger schemas. Host login03, CPU only, **no Slurm job submitted, none cancelled**; the one live `sbatch` call
below is `--test-only`, which validates and estimates and queues nothing (Slurm 25.11.2 man page; the queue was read
before and after and is unchanged).

**Production context.** Link 1 of the chain (job 301099, gl111, l40s) is RUNNING on the *pre-repair* file `8e394116…`
(the log carries the defect line at `loop-301099.log:17-19`). Its successor 305318 is PENDING with
`afterany:301099(unfulfilled)`. Link 2 re-reads `$SELF` from the repo when it starts (about 2026-09-05T18:22) and will
run the file validated here — so this validation is about tomorrow's link.

Verbatim transcript: `evidence/loop_resume/validation_repair6_harness.txt` (sections 0–9, every harness source
included). The harness is the validator's own: a mode-selectable `sbatch` / `squeue` shim pair written from what the
*real* `sbatch --test-only` and `squeue` printed on this cluster this evening (section 1 of the transcript), layered on
the wave-3 validator's verbatim `w3v_common.sh` (`7d91e5ba…`) for the whole-wrapper runs; the wave-3 regression set and
seed matrix were re-run with the recorded `v2_regress.sh` / `v3_seeds.sh` (`9d4648ab…` / `02199feb…`) and the
fifth-repair validator's `norm3.sed`, `my_stage.sh`, `rowcmd.sh`, all extracted from the records and hash-checked.

## 0. Chain safety — read first

**No defect was found that reaches link 2 of the production chain.** Specifically:

- The mechanism the repair assumes is the one the site has. `sbatch --test-only --parsable` of a one-line script
  printed **nothing on stdout** and, on **stderr**, `[BILLING] loaded!`, `[BILLING] Re-emitting cost at job start!` and
  the start estimate (transcript § 1, `cat -A`). So on a real submission `--parsable` leaves the id alone on stdout and
  the repaired parse reads it; the pre-repair `2>&1` capture is exactly why link 1 logged the banner and the id on one
  "did not return a job id" line while 305318 was correctly queued.
- The fallback lookup matches the real queue's shape: `squeue -h -u $USER -n ktg-loop -t PENDING -o '%i|%E'` — the
  command as `resubmit()` issues it — printed exactly `305318|afterany:301099(unfulfilled)$` and nothing on stderr
  (§ 1). The repaired `grep -F "afterany:301099" | cut -d'|' -f1` would yield 305318.
- Under the banner the successor id is now held: on a pre-flight failure (V12), a breaker trip (V13) and a storage stop
  (V14) the captured successor is `scancel`led (shim log `SCANCEL 800001` / `800002`; the wave-3 invariant
  `cancel_iff_trip=ok` where the pre-repair file read `VIOLATED (scancel=0 trip=1)`). Chain continuity was never at
  stake — the successor was queued in both files — but the three cuts that exist to stop a deterministic crash loop are
  live again.
- The repair cannot suppress a submission: with `$BASEDIR` read-only (V19) the stderr redirection fails, `sb_err`
  falls back to `/dev/null`, `sbatch` still runs and the id is still read.
- `chain_status.sh` on the live link-1 log (9 guard invocations, 8 per-cycle, 9 `OK`) no longer raises the false P10
  NOTICE; on a fixture whose cycle-2 guard ends `no usable measurement` and on one whose last guard has no verdict at
  all (link ended inside the call) the NOTICE fires where the old counter was silent (§ 4).

Three things the chain reader should know, none a corruption and none reaching tomorrow's link:

1. **The fallback lookup matches by substring** (`grep -F "afterany:$SLURM_JOB_ID"`). A pending same-name row whose
   dependency is a *longer* id that has this job's id as a prefix is taken as the successor and, on a cut path,
   cancelled (V15: job 3302 adopted and cancelled 800701, which depended on `afterany:33027`). Reachable only when
   `sbatch` exits 0 without a parsable id — which the measured site behaviour does not produce — and only once ids of
   different lengths coexist (six digits here). A hardening for the next scheduled edit: match `afterany:<id>(` or
   anchor the field. Recorded as validator qualification (xi) on the row and on the o46 discharge.
2. **A duplicate successor** (two pending rows depending on this job, outside assumption a12) resolves to the *last* row
   and only that one is cancelled (V16).
3. **Read-only BASEDIR plus a failing sbatch** logs `sbatch wrote nothing to stderr` where stderr was in fact discarded
   to `/dev/null` (V19). A misstatement in a diagnostic line, not a lost successor; the `: >` fallback is the documented
   trade.

## 1. Refutation attempts — the wrapper (o46)

Each attempt names what would have rejected, what was run, and the outcome. Transcript section in brackets.

- **R1. Is the banner really on stderr, or did the worker guess?** Live `sbatch --test-only --parsable`: stdout empty,
  stderr = the two `[BILLING]` lines plus the estimate. **Not refuted.** And if the assumption were wrong it would not
  matter: with the banner on *stdout* (V3) the last-matching-line rule still reads the id. [1, 5]
- **R2. Site behaviour → successor captured.** V1 (`site`) pre vs post: pre `sbatch did not return a job id -- chain
  not extended: [BILLING] loaded!`; post `successor queued: 800001 (partition b200, dependency afterany:1002)` and
  `sbatch wrote to stderr and still succeeded -- verbatim: [BILLING] loaded! [BILLING] Re-emitting cost at job start!`.
  V2 federated `800001;skipjack`: same. V4 chatter before the id and an empty line after it: same. **Not refuted.** [5]
- **R3. Do the cuts reach the successor?** V12 pre-flight failure, V13 breaker on link 2 (`failcount now 4/3`), V14
  storage stop (`deliberate chain stop (rc=3 …)`): each logs `cancelling queued successor <id> (…)` with the matching
  `SCANCEL` in the shim log; the pre-repair V12 logs `no queued successor to cancel` and `cancel_iff_trip=VIOLATED`.
  **Not refuted.** [6]
- **R4. sbatch refuses.** V8 exit 1: `sbatch failed (exit 1) -- chain not extended; stdout: '<empty>'` and
  `sbatch stderr, verbatim: [BILLING] loaded! [BILLING] Re-emitting cost at job start! sbatch: error: …`. V10 sbatch
  dies by SIGTERM (143): `chain not extended`, `sbatch wrote nothing to stderr`. No `squeue` call in either. **Not
  refuted.** [5]
- **R5. Exit 0 without an id.** V5 (`Submitted batch job N`, `--parsable` ignored) + squeue hit: WARNING, then
  `successor queued: 800001 … -- id recovered from squeue, not from sbatch stdout`. V6 silent + empty queue: three
  `squeue lookup attempt k/3` lines five seconds apart and the closing WARNING; **`chain not extended` appears 0 times**;
  wall 25 s for the link. V11 queue answers on the third attempt only: recovered on attempt 3. **Not refuted.** [5]
- **R6. Can the lookup pick a job that is not ours?** Filters seen in the shim log: `-h -u ssci-haiyangw -n ktg-loop
  -t PENDING -o %i|%E` — this user, this job name, pending only, then `afterany:<this id>`. V17 (rows for
  `afterany:<other>`, `(null)`, `afterok:<this>` around ours): only ours taken. V18 (banner on squeue's stderr): fine.
  **Refuted in one corner:** V15 prefix collision, V16 duplicate → § 0 items 1–2. Not chain-affecting by the reasons
  given there; recorded, not blocking. [6]
- **R7. Stream and shape attacks on the id line.** V7 trailing space after the id: no parse, falls to the squeue path
  (WARNING, never "chain not extended"). V9 id on stdout *and* exit 1: read as a success (`still succeeded -- verbatim:
  sbatch: error: late failure`). Both are edge misreadings that keep the safe direction (the id, when printed, is
  real); recorded as qualification (xiv). [5]
- **R8. The stderr temp file.** `.resubmit_stderr.<jobid>` left behind in **0** of 27 links; with `$BASEDIR` read-only
  the redirection fails, `sb_err=/dev/null`, submission proceeds (V19). Diagnostic lost, chain not. [5, 6]
- **R9. Environment edges.** `USER` unset → `-u ssci-haiyangw` from `id -un` (V20); `SLURM_JOB_NAME=ktg-loop-alt` →
  `-n ktg-loop-alt` (V21); STOP at entry → no `sbatch`, no `squeue` (V22); wave-3 clean shim → pre and post identical
  modulo job id (V23). A SIGTERM to the wrapper *during* the lookup (V24) is deferred by bash until the running
  `squeue`/`sleep` returns, the three attempts complete, and the link ends as `scheduler termination at walltime …
  successor continues` (exit 143, `.failcount` 0). **Not refuted.** [6]
- **R10. Regression set + seed matrix unchanged.** `v2_regress.sh` (46 links) and `v3_seeds.sh` (51 links) run unmodified against `9e64864d…` and diffed against the recorded 631 / 420-line reference blocks: raw diffs 151 / 34 lines, all of them elapsed-seconds and pid values plus one placement of bash's job-control `Terminated`; under the fifth-repair validator's `norm3.sed` (9 rules, `35b4d275…`, the same copy the worker used) **V2_NORM3_DIFF_EXIT=0 (616/616 normalised lines) and V3_NORM3_DIFF_EXIT=0 (420/420)**; the accounting lines compared alone are IDENTICAL (217 / 231); `successor queued:` 43 / 43; `did not return a job id`, `chain not extended` and `WARNING: sbatch` appear 0 times in the new run. Note: the first pass of my diff section is void and is left in the transcript as such — my `norm3.sed` extraction carried trailing record lines past its 9 rules and `sed` aborted; the link outputs were untouched and the re-run (`r6v_rediff.sh`) is what the numbers above cite. **Not refuted.** [7]
- **R11. § 2 closing check and the row's verification command.** Both exit 0 in a clean non-interactive bash with
  GNU grep (`afterany` 12, `failcount` 35, `cpp/build/katago` 5, `cpp/katago"` 0; policy `OK : request gpus=1 cpus=32
  part=b200 within policy`). The final conjunct is a *live* compute-budget check; at append time it read `my jobs :
  gpus=2 … (4 jobs incl. 2 dependency-pending, not counted)` (az `91e6399`). [3]
- **R12. `KTG_STAGE_ONLY=1` dry run byte-identical.** Twice from the real scratch clone: 87 files each, manifest diff
  exit 0, `cmp bin/katago` 0, `dataBoardLen = 9`; 28882815 B (the clone's `python/` tree carries 13 `__pycache__` files
  that move the byte total between reads — not this repair's). [8]
- **R13. Static / confinement.** `bash -n` clean on every script of `codes/loop` and `codes/eval`; the commit's two code
  hunks are both inside `resubmit()` (`@@ … resubmit() {`) and section E of `chain_status.sh`; 44 non-comment lines
  changed in `loop.sbatch`; the 7x7 files and `synchronous_loop_9x9.sh` untouched (`git diff b1e25d9^ HEAD` empty);
  working tree == HEAD for both artifacts; the "2>&1 on the sbatch substitution" grep is 0. [2]

## 2. Refutation attempts — the reader (P10)

- **R14. The false NOTICE on a healthy link.** Live log: pre `NOTICE: P10: 8 guard blocks but 9 'scratch_guard: OK'
  lines`; post none, `guard invocations: 9  'scratch_guard: OK': 9  of which [cycle N pre-gatekeeper]: 8`. Healthy
  fixture (1 pre-flight + 2 per-cycle): pre NOTICE, post none. **Not refuted.** [4]
- **R15. Silence on a real defect.** Fixture whose cycle-2 guard ends WARNING + `no usable measurement -- exit 3`: pre
  silent (2 == 2), post `NOTICE: P10: 3 scratch_guard invocations but 2 'scratch_guard: OK' lines`. Fixture whose last
  guard has a header and no verdict: same. **Not refuted.** Note: the second case means a link the scheduler ends inside
  a guard call will carry one NOTICE — correct, but worth knowing when reading a TIMEOUT link. [4]
- **R16. Anything else changed in the report?** Outside section E and the P10 line the live report differs only in live
  counters (elapsed, sample count, games) between the two reads. The task file's own P10 wording (per-cycle headers ==
  `OK` lines) is the predicate that cannot hold on a real link; the worker left that file to node
  `production_chain_9x9` and recorded it as `[OPEN]` — it stays visible on the candidate's `open_after_this_packet`. [4]

## 3. Gate check on the candidate rows

- Evidence type / status: `existence_only` is kept; nothing ran under a real scheduler. Gate 3 satisfied for what is
  claimed (offline injection + static). The claim's closing sentence "whose dependency names this job id" is matched
  loosely by the implementation (substring) — qualification (xi) narrows it on the row rather than rejecting a
  statement whose production reach is nil.
- Circularity: the discharge cites `r_loop_resume_under_walltime_static`, the row it amends; that is the o44 precedent
  and the row's `verification.command` is independent of the obligation text. No `[OPEN]` hidden: the seven
  `open_obligations` are carried unchanged; P9's executed proof is still ahead and is written on the row's notes.
- Evidence hash: `repair_sbatch_id.txt` sha256 `86428fc3…` equals the candidate's recorded hash; the two artifact
  hashes equal the candidate's `after_this_repair` values.
- Name sweep (vendor / model / assistant terms, case-insensitive) over this file, the harness transcript and the three
  row files: 0 matches other than the tracked repository path named by `mission.json compute.policyCheck`.

## 4. Verdict

**ADMIT.** No gate fails. Appended with `CHANDRA_ROLE=validator`:

- result row `r_loop_resume_under_walltime_static`, iteration 9, `existence_only`, row_hash `2e274b87179032fac5811e6f40a56cb08a8edd6da88641eeba291e1fb0c349a8` (amends `423b1bdf…`; gate ran the verification command at 2026-09-05T00:12:33Z, exit 0, 3.5 s, policy line `OK : request gpus=1 cpus=32 part=b200 within policy`; evidence `repair_sbatch_id.txt` sha256 `86428fc3…`).
- claim ledger `o46_successor_id_parse_billing_banner` **open**, row_hash `871c2c9ae4022fae90f933e8e791eee9bd4f0f5c710fd0a1452ecdb4852be090`.
- claim ledger `o46_successor_id_parse_billing_banner` **discharged** by `r_loop_resume_under_walltime_static`, row_hash `85661348888d792848aceb63f33d0e91c2b7463eb3f74e4df26e22e7547a833e` (validator qualifications (a)–(f) on its notes).
- harness transcript `validation_repair6_harness.txt` sha256 `23277884658b2f909c58fb6a9027aca65f3748cdc2763609d2f81fd8bb68391f`.

Views re-rendered: `decomposition/{claims,obligations,assumptions}.md`, `decomposition/results.md`.

## 5. Remaining `[OPEN]`, visible

- (xi) substring match in the squeue fallback — hardening for the next scheduled edit of `loop.sbatch` (not a chain
  risk on this cluster's six-digit ids while `sbatch --parsable` prints the id).
- P9's executed proof: the first `successor queued:` line on a real link boundary comes from link 2 (305318); the chain
  reader keeps reading the successor from `squeue`/`sacct` until then.
- `tasks/production_chain_9x9/implementation.md:34` still states P10 as the per-cycle equality; owned by that node.
- The candidate's `open_obligations` (o25, o33, o36, o42, o03 executed conjunct, c07, c08) unchanged.
