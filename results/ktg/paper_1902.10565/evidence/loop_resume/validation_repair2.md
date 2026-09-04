# Validation of the second repair packet — `arxiv-1902.10565::loop_resume_under_walltime` (o31 / o26)

Role: validator (refuter, then judge), cross-model relative to the worker. Inputs received: the
candidate transitions `evidence/loop_resume/candidate_rows_repair2.json` (o31, o26 → discharged;
amended `existence_only` result row), the worker's evidence `evidence/loop_resume/repair_o31.txt`
(sha256 `906cec83…`, matches the candidate), the artifact `codes/loop/loop.sbatch` at commit
`7cd6f36` (sha256 `fd498f39…`, matches the candidate's "after" hash; `codes/loop/` working tree ==
HEAD), `codes/loop/synchronous_loop_9x9.sh` (`20a7f5b3…`, unchanged), the task file § 2, the
worker's error-ledger row `b8f1bb5c…`, the first-packet record `validation_repair.md` and its
harness, and the ledger schemas. Host: login03, CPU only, no Slurm job submitted, no GPU. Date:
2026-09-04 (UTC). During this validation `az` HEAD moved from `7cd6f36` to `bcb1805` (node
`synchronous_loop_smoke`'s files); nothing under test changed.

Verbatim transcript: `evidence/loop_resume/validation_repair2_harness.txt` — Part 1 the main run
(47 wrapper invocations), Parts 2–3 the K4 supplement (3 + 3), then both harness sources. The
harness is the validator's own, written for this run: `sbatch`, `scancel`, `sinfo`, `sacct`,
`scontrol`, `squeue`, `nvidia-smi` are PATH shims; the real `mission.json`, the real compute-policy
`check.sh` and the real `codes/data_budget/` tools were used unmodified (the pruner removed 0 paths
in every link). The loop is a stand-in in every scenario — a script that sleeps, exits with the
code the scenario needs, or writes STOP — so the real `synchronous_loop_9x9.sh` never ran; its
error semantics were copied into the stand-in for K4 (§ 3 explains why that mattered). Probe (i)
points `KTG_SCRATCH_GUARD`, an existing knob, at a 12 s stand-in guard. Cluster facts re-read:
`KillWait = 30 sec`, `OverTimeLimit = 0 min`.

## 1. Reproductions — the repair holds

Static. `bash -n` clean on all three files. `KTG_RC_SIGTERM=143` and `KTG_RC_SCRATCH_STOP=3`
are hard-coded (loop.sbatch:94, :98); `KTG_MIN_RUNTIME_SECONDS`, `KTG_MAX_FAILS`, `KTG_MAX_CHAIN`
read the environment (:85-87, as before this repair). Writers of `.failcount`: :118 (initialise
when absent), :232 and :249 (both in `finalize`). Nothing in `codes/loop/` removes STOP. `SCHED_TERM`
is not consulted anywhere between the trap (:168) and the loop launch (:455).

§ 2 closing check, verbatim, clean environment, real `sbatch` on PATH:

```
OK           : request gpus=1 cpus=24 part=b200 within policy (gpu<=4, no cpu cap)
SECTION2_EXIT=0
grep -c afterany=7 failcount=23 cpp/build/katago=5 cpp/katago"=0
```

Literal grep. The worker's pattern over `codes/loop/` now exits 0: `smoke_loop.sbatch:63`
(`python3 /apps/helpers/quotas.py 2>/dev/null || true`, informational) and `:233-234` (`du -sh` of
its own work directory). That file belongs to node `synchronous_loop_smoke` (commit `bcb1805`,
after the worker's run), carries no threshold, and is not one of the two files o27's statement
names; the candidate's "additional gate" wording is stale as of HEAD, o27's discharge is not
affected. Over `loop.sbatch` and `synchronous_loop_9x9.sh` the pattern still exits 1.

Regression set, each line as the first record states it (`KTG_MIN_RUNTIME_SECONDS` at its default):

| Scenario | Validator's run |
|---|---|
| A crash loop, 3 links | 2 → 4, `circuit breaker tripped after 4`, `SCANCEL 700002`; link 3 exits 0 without the loop, count stays 4 |
| B env.sh missing ×2 | `PRE-FLIGHT FAILURE rc=2`, 2 → 4, SCANCEL after each link |
| B2a explicit checks deleted | raw `KATAGO_SRC: unbound variable` → `PRE-FLIGHT FAILURE rc=1`, 2, SCANCEL |
| C loop script missing ×2 | 2 → 4, SCANCEL each |
| D / E guard exit 1 / 2 (in-tree fixtures) | `deliberate chain stop (rc=3)`, STOP, SCANCEL, count 0 |
| F guard exit 3 | `PRE-FLIGHT FAILURE rc=2`, 2, SCANCEL |
| G clean cycle after a failure | 2 → 0 |
| H STOP at entry | `exit 0 before the loop started`, count left at 2 |
| J trap probes (probe copy) | one accounting line, second `finalize` a no-op |

o31's closing scenarios (`KTG_MIN_RUNTIME_SECONDS=1` where a signal is involved, so the
fast-failure penalty cannot mask anything; a real link runs ~3 days):

```
----- link: K1   (signal mode=pgrp, ...)
=== SIGTERM received -- scheduler termination (walltime or scancel); the queued successor is the resume path ===
=== scheduler termination at walltime after 7s (SIGTERM to this wrapper) -- successor continues, failcount left at 0 ===
wrapper exit=143  .failcount=0  .chain_depth=1  breaker_tripped=no  STOP=no
   (K2, K3 identical: 3 of 3; shim log: SBATCH 700001, 700002, 700003, no SCANCEL)
----- link: K4b  (loop bash only signalled, wrapper never signalled)
=== loop exited rc=143 after 6s ===
=== scheduler termination at walltime after 6s (loop status 143, this wrapper not signalled) -- successor continues, failcount left at 0 ===
   (K4a child+loop and K4c child-only, stand-in with set -eu -o pipefail: identical)
----- link: K5   (wrapper only signalled; stand-in sleeps 6 s then exits 0)
=== SIGTERM received ... ===
=== loop exited rc=0 after 11s ===
=== scheduler termination at walltime after 11s (SIGTERM to this wrapper) -- successor continues, failcount left at 0 ===
----- link: K6   (pgrp SIGTERM, .failcount=2 at entry)
=== scheduler termination at walltime after 6s (SIGTERM to this wrapper) -- successor continues, failcount left at 2 ===
wrapper exit=143  .failcount=2  ...
----- link: M1   (SIGKILL to the process group)
wrapper exit=137  .failcount=0  ...      accounting lines: 0      shim log: SBATCH 700001 only
----- link: L1a  (exit 3, no STOP, floor 1)        -> not a storage refusal, counting it as a failure -- failcount now 1/3, chain continues
----- link: L1b  (exit 3, no STOP, default floor)  -> fast failure: 5s < 600s -- counting it twice -- failcount now 2/3, chain continues
----- link: L2   (touch STOP; exit 3)              -> the loop stopped on the storage guard -- deliberate chain stop, SCANCEL 700001, count 0
```

Scenario N (pgrp SIGTERM after the loop wrote STOP but before its `exit 3`): booked as a scheduler
termination with STOP present, successor kept; the successor link then exits 0 at entry (`STOP
present -- not resubmitting`, `exit 0 before the loop started`). Correct in both links.

Every closing condition o31 named, and every conjunct o26 named, is therefore reproduced against
the committed file with shims and stand-ins the worker never saw. The K4 supplement is stricter
than the worker's "child-first" (which also signalled the wrapper 0.5 s later): here the wrapper is
never signalled, in three orderings.

## 2. Attempts to break the new logic — what they found

**(i) SIGTERM during the pre-flight.** (a) Process group signalled during the guard: the guard dies
143, the wrapper takes the `*)` branch (`exit 2`), `finalize` sees `SCHED_TERM=1` and books a
scheduler termination — a signal-induced pre-flight failure treated as the signal it was; successor
kept. (b) Wrapper only signalled during the guard: the handler runs when the guard returns and the
script **continues into the loop** (`LOOP RAN AFTER THE SIGNAL`); offline the stand-in ran to
completion and the link was booked as a scheduler termination. On the cluster SIGKILL follows 30 s
later, so nothing is written and the successor resumes — but the wrapper does not consult
`SCHED_TERM` before :455. (c) Wrapper only signalled, then a deterministic pre-flight failure (loop
script missing): booked as a scheduler termination, count untouched, successor kept — the
classification the question feared. The successor then hits the same failure, counts it (`1/3` at
floor 1; `2/3` at the default) and cancels its own successor: self-correcting in one extra link.
Not a gate failure — the claim says "SIGTERM to this wrapper → scheduler termination" and that is
what happens — but the precedence of `SCHED_TERM` over a pre-flight failure is a design weakness.
Recorded in o33.

**(ii) Loop status 143 without a signal to the wrapper.** Fast 143 at the default floor: `fast
failure: 5s < 600s -- counting it twice -- failcount now 2/3` — counted, as the third class
requires. `KTG_MIN_RUNTIME_SECONDS=0` in the environment: a 4 s crash is waved through as a
scheduler termination. 143 after the floor (`KTG_MIN_RUNTIME_SECONDS=3`, stand-in kills itself
after 4 s): waved through — the residual the worker itself lists as `[OPEN]` in
`open_after_repair`, which was not in any ledger; it is now part of o33. `KTG_RC_SIGTERM=1` in the
environment: no effect (hard-coded), a loop exit 1 is still a failure.

**(iii) SIGTERM after the loop has finished, before `finalize`.** Probe copies insert a 6 s sleep
either between the loop's return and the final `exit` or inside `finalize` before the
classification. Clean loop end: booked as a scheduler termination, count left rather than reset,
one accounting line — no double-booking (`FINALIZED` guard) and no harm. **Failed loop (rc 1) then
SIGTERM**: booked as a scheduler termination, `failcount left at 0`, successor kept — a failure
waved through. In the unmodified file the window is the `date` call between :456 and :482, and on
the cluster the wrapper-only ordering is followed by SIGKILL in 30 s, so the exposure is
microseconds wide; recorded in o33 all the same, because the fix is one comparison (a non-zero
status recorded before the signal should outrank it).

**(iv) Stale or manual STOP with an exit 3.** STOP created by hand while the loop runs, loop exits
3 for a non-storage reason: `the loop stopped on the storage guard ... deliberate chain stop`,
uncounted, `SCANCEL`. The label is wrong, the outcome is right: the human asked the chain to stop
and it stops; had it been counted instead, the successor would have exited 0 at entry on the same
STOP. Stale STOP from a previous chain: `STOP present at entry -- nothing to do`, exit 0 before the
loop, count left. The wrapper never removes STOP (grep) and the real loop exits 0 at the top of the
next cycle when it appears (`synchronous_loop_9x9.sh:215-219`), so a stale STOP cannot coexist
with a running loop. Benign; no obligation.

**(v) Environment overrides.** `KTG_RC_SIGTERM` and `KTG_RC_SCRATCH_STOP` cannot be overridden.
`KTG_MIN_RUNTIME_SECONDS`, `KTG_MAX_FAILS`, `KTG_MAX_CHAIN` can, as before this repair, and
`resubmit()`'s `sbatch` passes no `--export`, so Slurm's default `--export=ALL` carries the
submitting shell's values down the whole chain (a left-over `KTG_MIN_RUNTIME_SECONDS=1` from a test
shell would ride along). Not new, not a gate failure; noted in o33.

**Scenario O — the count never decays.** fail, TERM, TERM, fail, TERM, fail at floor 1 gives
`1, 1, 1, 2, 2, 3` and the breaker trips on the third failure across six links. A healthy
production link never exits 0 (the loop is open-ended; only STOP or `KTG_ONE_CYCLE` end it
cleanly), so the reset at :232 never fires in production and `KTG_MAX_FAILS=3` means three
failures over the chain's lifetime, not the "three consecutive" of the header (:36-37). This is the
direct consequence of o31's own fix shape ("leave the count"), which the previous validator
prescribed to stop a walltime kill wiping a real count; it is the right trade for now and a design
decision to make visible. Recorded in o33.

## 3. New finding — errexit is lost under the wrapper's invocation (o34)

The first K4 pass used a stand-in whose only error semantics were in its shebang
(`#!/bin/bash -eu`, `set -o pipefail` on line 2 — exactly the real script's header). With its
children killed it **returned 0** (`sleep 30 | cat` died, the script fell through to `exit 0`),
and the wrapper booked `clean exit -- failcount reset to 0`. The cause is not the wrapper's
classification: `loop.sbatch:455` runs `bash "$LOOP_SH" ...`, and options on a shebang line are
ignored when a script is launched that way. Probe, outside the wrapper:

```
--- executed directly (./shebang_probe.sh):
exit=1
--- launched as 'bash shebang_probe.sh' (the wrapper's form, loop.sbatch:455):
reached after false: errexit=off nounset=off
exit=0
```

In the real `synchronous_loop_9x9.sh`, `-e` is therefore switched on for the first time at :232
(`set -e` after the first cycle's guard call) and `-u` never. Stage failures inside the `while`
loop still stop the loop — :232 is reached before the first stage — so the wrapper's failure classes
are reached in the common case, and every explicit `exit 2` check (:64, :72, :89, :145, :165)
works. What runs unguarded is the archive-staging section :44-228: `realpath`, `git rev-parse`,
the `cp` of `python/*.py`, `python/katago`, `python/muon`, the engine binary, the two wrappers and
the two configs into `$DATED_ARCHIVE`, `git show`/`diff` into `version.txt`, the sweeps and
`cd "$DATED_ARCHIVE"`. A failed copy or `cd` there is followed by cycle 1 out of a wrong or
incomplete archive, not by the `exit 2` the header comment (:11-12, "`-eu` + `set -o pipefail`
are kept so any stage failure still stops the loop") and the o17 comment (:157-159, "under bash
-eu the stock copy kills cycle 1") promise. With the stand-in carrying `set -eu -o pipefail` in
its body, all three K4 orderings classify correctly (§ 1).

This is outside o26's and o31's statements (both concern `finalize()`), so it does not block their
discharge; it is inside this node's artifact pair and directly under the claim "a loop failure
counts" — a failure that does not end the loop is never counted. Opened as o34, blocking for any
promotion of the node beyond preliminary. Fix shape: `set -eu -o pipefail` at :2 (upstream relies
on the shebang because it executes the script directly), or exec the script directly from the
wrapper. `smoke_loop.sbatch` does not launch `synchronous_loop_9x9.sh`, so the smoke job is
unaffected.

## 4. Verdict

| Obligation | Verdict | Gate |
|---|---|---|
| `o31_wrapper_scheduler_termination_classification` | **Admit** — discharged | every closing scenario (K1–K3, K4 ×3 orderings, K5, K6, L1, L2, M control) reproduced independently; no misclassification inside the statement |
| `o26_wrapper_early_exit_bypasses_breaker` | **Admit** — discharged | its conjuncts (A–J) reproduced again; the dominant path is now classified (o31) |
| amended result row `r_loop_resume_under_walltime_static` | **Admit** at `existence_only`, claim carries four validator qualifications | § 2 verifier exit 0 at append; no bypass flags |
| `o33_wrapper_classification_residuals` | **opened**, non-blocking | § 2 findings (i)–(iii), (v), scenario O |
| `o34_loop_script_errexit_lost_under_bash_invocation` | **opened**, blocking | § 3 |

Not a gate failure but recorded: the candidate's "no storage literal in `codes/loop/`" additional
gate is stale as of HEAD `bcb1805` (another node's informational `quotas.py` / `du -sh` lines).
The worker's `open_after_repair` item `loop_exit_143_after_a_long_run_is_read_as_a_scheduler_termination`
was an `[OPEN]` marker outside any ledger; it is now o33 (b).

No AI tool or model name appears in the artifacts, the evidence files, the candidate rows, the
transcript or this record (case-insensitive sweep over the usual vendor and model names; the
validator's temporary directory is printed as `$VALTMP` in the transcript for the same reason).

## 5. Rows appended (`CHANDRA_ROLE=validator`, no admission flags on any row)

| Ledger | Entry | Status | row_hash |
|---|---|---|---|
| result | `r_loop_resume_under_walltime_static` (amends `6227934b…`) | `existence_only`, verifier exit 0 at append, `evidence_sha256 906cec83…` | `d0f87ded00581ae309379e64f38b6ff7cb98a31b7f2ba218d0cd6e81af58a3d8` |
| claim | `o34_loop_script_errexit_lost_under_bash_invocation` | `open`, blocking, owner `loop_resume_under_walltime` | `f8bc0de2a7283af6aac96303207c2e50ba515577d3575f995a61d847e5561fb4` |
| claim | `o33_wrapper_classification_residuals` | `open`, non-blocking, owner `loop_resume_under_walltime` | `b1849cade4419c3320ae5ba03eebeab248cf36b594f0ecdf03b28821222bf853` |
| claim | `o31_wrapper_scheduler_termination_classification` | `discharged` by `r_loop_resume_under_walltime_static` (amends `9263ab65…`) | `b160a5429ec0b83561b89ffed7f44fff6bc139b295b03daa810849b95e3b7bae` |
| claim | `o26_wrapper_early_exit_bypasses_breaker` | `discharged` by `r_loop_resume_under_walltime_static` (amends `d2e081aa…`) | `acf1a67a19c424629b9707ebf1939cb790e2b1933cec65164ace26214c4f4413` |
| error | validation trial, iteration 4, `pass`, metric 11/11 termination classes | node_seq 7 | `92a3c81b0209817b69bf925900bbfa86d59502870f6d5e2b9ac0711970a848cd` |

Views re-rendered from the ledgers: `decomposition/{claims,obligations,assumptions}.md`,
`decomposition/results.md`. Remaining `[OPEN]` under this node: `o25` (executed breaker proof,
owner `loop_failure_circuit_breaker`), `o33` (non-blocking) and `o34` (blocking, owner
`loop_resume_under_walltime`), `o13` / `o24` (knobs), `c07` / `c08` (need `numerical_simulation`).
Knowledge status stays `preliminary`; no knowledge row was appended.
