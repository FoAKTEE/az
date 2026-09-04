# Validation of the third repair packet — `arxiv-1902.10565::loop_resume_under_walltime` (o34 / o33)

Role: validator (refuter, then judge), cross-model relative to the worker. Inputs received: the
candidate transitions `evidence/loop_resume/candidate_rows_repair3.json` (o34 → discharged; o33
amended, still open; amended `existence_only` result row), the worker's evidence
`evidence/loop_resume/repair_o34.txt` (sha256 `7827857e…`, matches the candidate), the three
artifacts at HEAD `6b83dc0` (`synchronous_loop_9x9.sh` `7d53df27…`, `loop.sbatch` `86248d31…`,
`export_model_for_selfplay_9x9.sh` `a1277ecb…`; `codes/` working tree == HEAD; `smoke_loop.sbatch`
identical at `2efa1b5` and HEAD and not touched here — job 298712 stayed PENDING throughout), the
task file § 2, the worker's error rows `65eff50a…`, `7b765d92…`, `a417b03b…`, the second record
`validation_repair2.md`, and the ledger schemas. Host: login03, CPU only, no Slurm job, no GPU.
Date: 2026-09-04 (UTC).

Verbatim transcript: `evidence/loop_resume/validation_repair3_harness.txt` (sha256 `105c9512…`),
three parts plus their sources. Part A: static checks, a header probe on a copy of the REAL loop
script, fault injection through `bash <script>` on the REAL loop script against a stand-in git tree
with dummy stages (pre-repair copies from `git show 2efa1b5:…` for every BEFORE column), one full
stand-in cycle through the REAL script, the `KTG_STAGE_ONLY=1` dry run from the real scratch clone
before and after, and the closing checks. Part B: the wrapper under the validator's own PATH shims
(`sbatch`, `scancel`, `sinfo`, `sacct`, `scontrol`, `squeue`, `nvidia-smi`) with stand-in loops —
the regression set, the o33 probes, P3–P6, and new attacks on the counter logic. Part C: scenario
(iii)-e re-run after Part B's probe anchor matched twice. The real `mission.json`, the real
`check.sh` and the real `codes/data_budget/` tools were used unmodified. The validator's temporary
directories are printed as `$SIM`, `$RT`, `$VALTMP`.

## 1. Reproductions — the repair holds

**Header probe (o34's first closing condition).** A copy of the real script with one line after
the opening brace, reading `$-` and `$SHELLOPTS` in the running shell (no command substitution):

```
[before] bash hdr_before.sh: HDRPROBE $-=hB    SHELLOPTS=braceexpand:hashall:interactive-comments:pipefail
[before] ./hdr_before.sh:    HDRPROBE $-=ehuB  SHELLOPTS=braceexpand:errexit:hashall:interactive-comments:nounset:pipefail
[after]  bash hdr_after.sh:  HDRPROBE $-=ehuB  SHELLOPTS=braceexpand:errexit:hashall:interactive-comments:nounset:pipefail
[after]  ./hdr_after.sh:     HDRPROBE $-=ehuB  ...
```

`sed -n 2p` shows `set -eu -o pipefail` on both mission scripts (`O34_LINE2_EXIT=0`); `bash -n`
clean on all three; errexit stays on inside the brace group (probe 1.2, `NOT REACHED` absent,
exit 1); the wrapper still launches the loop as `bash "$LOOP_SH"` (:539), now harmless.

**Fault injection through `bash <script>` on the real loop script** (stand-in tree: `git init`,
`python/{a,b}.py`, `python/selfplay/{s.py,shuffle.sh}`, `python/katago`, `python/muon`,
`cpp/build/katago` dummy; dummy train/export wrappers via the existing `TRAIN_WRAPPER` /
`EXPORT_WRAPPER` knobs; real `codes/cfg`):

| Case | BEFORE (`2efa1b5`) | AFTER (`6b83dc0`) |
|---|---|---|
| R1a `python/*.py` absent, `KTG_STAGE_ONLY=1` | exit 0, 12 files staged | **exit 1, 2 files** (the `mkdir`'d `bin/` only), nothing else staged |
| R1b same, no `KTG_STAGE_ONLY` | a whole dummy cycle ran out of the broken archive (`Gatekeeper` reached, exit 0) | **exit 1 before the cycle** |
| R2a config missing | exit 2 (explicit check) | exit 2 (explicit check) |
| R2b config present, `chmod 000`, **complete tree** | exit 0, archive without `selfplay.cfg` | **exit 1 at :200**, python files already staged |
| R3 `scripts/dated` unwritable | — | exit 1 at the `mkdir` (:177) |
| R4 tree not a git repo, `KATAGO_SRC` unset | exit 0, 8 files staged from `GITROOTDIR=''` (`cp: cannot stat '/python/*.py'`) | **exit 128 at `git rev-parse`** (:100) |
| R6 `BASEDIR` parent missing | — | exit 1 at `realpath` (:99) |

R2b is the one case the worker's evidence did not isolate: its R2b tree also lacked `python/`, so
its "exit 1 at the cp" came from :178, not from the config copy at :200. Here the tree is
complete and the failure is provably at :200 (archive listing shows `a.py b.py … shuffle.sh
train_9x9.sh` and no `selfplay.cfg`). o34's closing condition "unreadable config … exits 2
(explicit check)" is met by R2a as written (the check is `-f`, so a present-but-unreadable file is
caught by the `cp` under `-e`, exit 1, which is what the obligation's intent requires).

**Staging-section audit** (:57-231), repeated independently: no `(( ))`, `let`, `grep -c`, `read`,
`local x=$(…)`, `|| true` or `&&` list; the only pipeline-looking hit is the `case` pattern
`*tfrs|*tflrs)`; the five command substitutions are assignment right-hand sides or a test
operand (:99, :100, :108, :109, :175), so their status propagates. `rm -rf` on a non-matching
glob exits 0. The `set +e` / `set -e` pair at :253-256 encloses only the guard call and
`GUARD_RC=$?`; a probe line inserted after :256 during a stand-in cycle prints `$-=ehuB`. No
missed case was found in the staging section. One pre-existing oddity outside errexit (R5):
`[ "$USEGATING" -ne 1 ]` returns 2 for a non-integer and the `if` treats that as false, so
`USEGATING=abc` passes the guard (`integer expression expected` on stderr, exit 0 under
`KTG_STAGE_ONLY`); the wrapper hard-codes `USEGATING=1`, the gatekeeper stage runs regardless,
noted only.

**R7 — the real script through a stand-in cycle** (dummy stages, real scratch guard, then the
fast guard): `cycle 1 complete -- 1 cycle(s) recorded`, a second run records 2. This executes
CHANGE 10's writer for the first time; the worker's out-of-ledger marker
`cycles_completed_counter_is_untested_against_the_real_loop` is absorbed into o33's amendment
(the executed run with real stages is c07's).

**Real scratch clone, `KTG_STAGE_ONLY=1`, `bash <script>` form**, before and after:
`STAGE_EXIT=0` both; 80 files / 28 702 024 B each; sha256 manifest `diff` exit 0; `cmp
bin/katago $KATAGO_BIN` exit 0 (27 273 864 B); staged `selfplay.cfg` identical to
`codes/cfg/selfplay_9x9.cfg`, `dataBoardLen = 9`. Archives removed afterwards.

**§ 2 closing check**, clean environment, real `sbatch` on PATH:

```
OK           : request gpus=1 cpus=24 part=b200 within policy (gpu<=4, no cpu cap)
SECTION2_EXIT=0
grep -c afterany=8 failcount=30 cpp/build/katago=5 cpp/katago"=0
```

Literal grep (o27 pattern): exit 1 over `loop.sbatch` + `synchronous_loop_9x9.sh`; over all of
`codes/loop/` it hits `smoke_loop.sbatch:63` only (another node's informational line, as the
second record already noted). `o08` grep exit 1. Nothing in `codes/loop/` removes `STOP` or
`.cycles_completed`.

**Wrapper regression** (Part B; `KTG_MIN_RUNTIME_SECONDS` default unless stated): A `2 → 4`,
breaker on link 2, link 3 exits 0 without the loop; B, B2a (raw `KATAGO_SRC: unbound variable`),
C: pre-flight failures `2 → 4` with SCANCEL each; D/E guard 1/2 → `deliberate chain stop (rc=3)`,
STOP, SCANCEL, count 0; F guard 3 → counted, SCANCEL; G `2 → 0`; H STOP at entry leaves 2; J one
accounting line. K1–K3 pgrp SIGTERM ×3 → `scheduler termination … failcount left at 0` ×3, three
SBATCH, no SCANCEL; K4 (child+loop, loop-only, child-only; stand-in with `set -eu -o pipefail` in
the body) → `loop status 143, this wrapper not signalled` ×3; K5 wrapper only → loop finishes rc 0
after 10 s, scheduler termination; K6 count 2 survives; M SIGKILL → exit 137, nothing written,
successor kept; L1a/L1b exit 3 without STOP → `1/3` (floor 1) and `2/3` (default); L2 → deliberate
stop, SCANCEL; N → scheduler termination with STOP present, successor exits 0 at entry; O with a
loop that records nothing → `1, 1, 1, 2, 2, 3`, breaker on link 6 (unchanged, as the candidate
states).

**o33's closed items, reproduced.** (i)-b, wrapper-only SIGTERM during a 12 s stand-in guard:

```
=== SIGTERM received -- scheduler termination (walltime or scancel); the queued successor is the resume path ===
=== SIGTERM already received during the pre-flight -- not starting the loop; the queued successor is the resume path ===
=== scheduler termination at walltime after 13s (SIGTERM to this wrapper) -- successor continues, failcount left at 0 ===
wrapper exit=143  .failcount=0  ...
```

(`LOOP RAN AFTER THE SIGNAL` absent.) (iii)-c and (iii)-d (loop exit 1, wrapper SIGTERM in a 6 s
window before the final exit / inside `finalize`): `the loop had already exited rc=1 when the
SIGTERM arrived -- counting the failure, not the signal`, `failcount now 1/3`; (iii)-f the same
for exit 3 without STOP; (iii)-g (loop 143 past the floor, then wrapper SIGTERM) stays a scheduler
kill. P3 (fail, TERM+cycle, TERM+cycle, fail, TERM+cycle, fail) → `1, 0, 0, 1, 0, 1`,
`.cycles_completed` 3, no trip, with `… 1 cycle(s) completed, so failcount 1 is cleared` on the
TERM links; P4 → `old count 2 dropped`, `2 → 1`; P5 at the default floor → `2, 2, 2` (r4).

**o33's residuals, reproduced as stated.** (ii)-c 143 after the floor waved through (r1); (i)-c
signal then a deterministic pre-flight failure booked as a scheduler termination, the successor
counts it `1/3` and cancels its own successor (r2); (iii)-e, a 6 s window between `RC=$?` and
`LOOP_RC=…` with the loop having exited 1 → `scheduler termination … failcount left at 0` (r3);
P5 (r4). (ii)-a/b/d unchanged (fast 143 counted twice; `KTG_MIN_RUNTIME_SECONDS=0` waves it
through; `KTG_RC_SIGTERM` env override inert). (iv)-a/b unchanged.

## 2. Attempts to break the new counter logic — what they found

**S1 stale count from a previous chain** (`.cycles_completed=6`, `.failcount=2`, failing loop):
entry 6, exit 6, delta 0 → `2 → 4`, breaker, SCANCEL. A stale absolute value cannot clear
anything; only the per-link delta counts. **S2 counter deleted mid-link** then the loop writes 1
(entry 6 → now 1): negative delta clamped to 0, not credited, `2 → 4`. Safe direction.

**S3 a12 violated** — a second writer bumps 6 → 7 while this link's loop (`sleep 8; exit 1`)
runs, `.failcount=2`: `this link completed 1 cycle(s) before failing -- the run of consecutive
failures restarts, old count 2 dropped`, `failcount now 1/3`, no breaker. Exactly the consequence
a12 already names for the other state files; a12 is amended to list `.cycles_completed` and this
scenario. Not a gate failure (the candidate says the counter inherits a12).

**S4 non-integer counters at entry** (`.failcount=2`, failing loop, default floor): `abc`, `''`,
`-1`, `1e3`, `0x10`, `99999999999999999999` all read as 0 → `2 → 4`, breaker, SCANCEL; `007` reads
as octal 7, harmless. **`08` breaks it**:

```
=== chain depth 1/200, failcount 2/3, cycles completed so far 08 ===
$AZ/results/ktg/paper_1902.10565/codes/loop/loop.sbatch: line 233: 08: value too great for base (error token is "08")
wrapper exit=1  .failcount=2  .chain_depth=1  .cycles_completed=08  breaker_tripped=no  STOP=no
--- scheduler shim log
SBATCH[800001] ...            (no SCANCEL)
```

The `''|*[!0-9]*` guard admits a leading-zero digit string, bash arithmetic reads it as an octal
literal and rejects 8/9, and an arithmetic-expansion error in a non-interactive bash discards the
enclosing command list — here the whole `finalize` body (harness 1.9 shows the fact in
isolation). `.failcount` stays 2 instead of 4, no `.breaker_tripped`, the queued successor is not
cancelled: the o26 class, and since the successor meets the same file, the count never advances
and the crash loop is bounded only by `KTG_MAX_CHAIN=200`. **S5** (same seed, cycle-recording
loop) also kills the loop's own CHANGE 10 line, and **R7c** shows it on the REAL script: `line
311: 08: value too great for base`, exit 1 after a completed cycle, file left at `08` — the loop
dies after every cycle and never records progress. **S6** (pre-existing, first packet):
`.failcount=abc` → `line 311: abc: unbound variable` inside `finalize`, no count written,
successor queued.

This falsifies the candidate's note "a missing or corrupt counter reads as 0, which restores the
pre-repair behaviour rather than aborting a link". It is outside o34's statement (errexit under
`bash`) and outside o33's classification residuals, and it needs a hand-edited or foreign-written
file (only the loop writes `.cycles_completed`, only `finalize` writes `.failcount`, neither with
a leading zero; the restart instruction says `rm`, not edit). Opened as **o35**, non-blocking,
with a one-token fix shape (`10#` at :233 and :311-312, or strip leading zeros in the guard; a
plain-decimal check on `.failcount` at :139). The result row's claim carries the qualification.

**P6** (cycle completed, then exit 3 with STOP, `.failcount=2`): the deliberate-stop branch wins,
count left at 2, SCANCEL. Correct — the chain stops either way.

Not a gate failure but recorded: the worker's evidence (PART 2 R2b) and candidate text describe
R2b as "exit 1 at the cp" of the config; the worker's tree also lacked `python/`, so that run
exited at :178. The isolated case above confirms the intended behaviour, so o34's discharge is not
affected.

## 3. Verdict

| Item | Verdict | Gate |
|---|---|---|
| `o34_loop_script_errexit_lost_under_bash_invocation` | **Admit** — discharged | both closing conditions reproduced with the validator's own probe copies and stand-in tree; the staging section stops at every injected fault (R1a, R1b, R2b isolated, R3, R4, R6); dry run byte-identical; § 2 exit 0 |
| amended result row `r_loop_resume_under_walltime_static` | **Admit** at `existence_only`, claim carries one validator qualification (o35) | § 2 verifier exit 0 at append; no bypass flags |
| `o33_wrapper_classification_residuals` | **Admit** the amendment — open, non-blocking | (a), (b), (c) closed and reproduced; r1–r4 reproduced; candidate note on corrupt counters corrected, marker absorbed |
| `o35_chain_state_files_unvalidated` | **opened**, non-blocking | § 2 S4/S5/S6/R7c |
| `a12_single_chain_per_basedir` | **amended** (active) | S3 |

Evidence type and status: `existence_only` is right — nothing ran on a GPU or under a real
scheduler; the executed stand-in cycle used dummy stages; c07/c08 still need
`numerical_simulation`. Knowledge status stays `preliminary`; no knowledge row was appended.

No AI tool or model name appears in the artifacts, the evidence files, the candidate rows, the
appended rows, the transcript or this record (case-insensitive sweep; the validator's scratch
path is printed as `$VALTMP` and the sweep pattern is redacted from the listed source for the
same reason).

## 4. Rows appended (`CHANDRA_ROLE=validator`, no admission flags on any row)

| Ledger | Entry | Status | row_hash |
|---|---|---|---|
| result | `r_loop_resume_under_walltime_static` (amends `d0f87ded…`) | `existence_only`, verifier exit 0 at append, `evidence_sha256 7827857e…` | `72ba1567d038435600eeb1d09165be2c2882928ae355270cae2a600ffc3a5e34` |
| claim | `o34_loop_script_errexit_lost_under_bash_invocation` | `discharged` by `r_loop_resume_under_walltime_static` (amends `f8bc0de2…`) | `a7e5bc64152f35baa10813866528fcdd1f896b1348fb0663274af2f4aa72a835` |
| claim | `o33_wrapper_classification_residuals` | `open`, non-blocking, amended (amends `b1849cad…`) | `78c2c16765e7d288a7b0bbbb8fdef0f84dfc7fb9d31d8b6d683e7e78bc21702b` |
| claim | `o35_chain_state_files_unvalidated` | `open`, non-blocking, owner `loop_resume_under_walltime` | `14fe758db56b80bbbf6f506895a3f5a86a5275fee4964b1b098d499417d575f0` |
| claim | `a12_single_chain_per_basedir` | `active`, amended (amends `2d39b7d3…`) | `0c19103d3c4a04a615746f510d3286df30ab5f817bb3fe9d46ecca48150a97a2` |
| error | validation trial, iteration 5, `partial` (19/19 candidate paths reproduced; one candidate note refuted) | node_seq 11 | `2dbc88342865275228f5d8e31d83d04e0120cf29b6d1061b9062c2014ae5e144` |

Views re-rendered from the ledgers: `decomposition/{claims,obligations,assumptions}.md`,
`decomposition/results.md`. Remaining `[OPEN]` under this node: `o25` (executed breaker proof,
owner `loop_failure_circuit_breaker`), `o33` (non-blocking) and `o35` (non-blocking, owner
`loop_resume_under_walltime`), `o13` / `o24` (knobs), `c07` / `c08` (need
`numerical_simulation`). No blocking obligation remains on this node's artifact pair.
