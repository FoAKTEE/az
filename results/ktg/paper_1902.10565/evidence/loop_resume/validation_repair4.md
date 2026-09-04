# Validation of the fourth repair packet — `arxiv-1902.10565::loop_resume_under_walltime` (o35)

Role: validator (refuter, then judge), cross-model relative to the worker. Inputs received: the
candidate transitions `evidence/loop_resume/candidate_rows_repair4.json` (o35 → discharged; amended
`existence_only` result row), the worker's evidence `evidence/loop_resume/repair_o35.txt` (sha256
`b2f991b2…`, matches the candidate), the two artifacts at HEAD `0c6d38d` (`loop.sbatch` `8d997ef5…`,
`synchronous_loop_9x9.sh` `f344ec06…`; `codes/` working tree == HEAD; `smoke_loop.sbatch`
`ba30b8b9…` identical at `cd6cbf2` and HEAD and not touched — job 298712 stayed PENDING throughout),
the worker's error row `82aa17b3…`, the task file § 2, the third record `validation_repair3.md`, and
the ledger schemas. Host: login03, bash 5.1.8, CPU only, no Slurm job, no GPU. Date: 2026-09-04 (UTC).

Verbatim transcript: `evidence/loop_resume/validation_repair4_harness.txt` (sha256 `c9bb4311…`),
three parts plus the sources of every harness file. Part A: static audit, `read_counter()` extracted
from HEAD with `sed` and probed in isolation, a differential run of the loop's inline writer parse
against `read_counter`, the REAL loop script with seeded counters through a stand-in git tree with
dummy stages (BEFORE column from `git show cd6cbf2:…`), the `KTG_STAGE_ONLY=1` dry run from the real
scratch clone before and after, and the closing checks. Part B1: the wrapper under the validator's
own PATH shims (`sbatch`, `scancel`, `sinfo`, `sacct`, `scontrol`, `squeue`, `nvidia-smi`) with
stand-in loops — the seed matrix for the three state files, the o35 crash-loop seed end to end, and
new attacks (X1–X12). Part B2: the regression set. The cycle-recording stand-in embeds the loop's
CHANGE 10 writer block verbatim (`:317-323`), so the real writer code ran inside the wrapper. The real
`mission.json`, `check.sh` and `codes/data_budget/` tools were used unmodified. Temporary directories
are printed as `$RT`, `$SIM`.

## 1. Reproductions — the repair holds

**`read_counter()` in isolation** (Part A 1.6; function extracted verbatim, 27 seeds): rc 0 and a
plain decimal every time. `08`→8, `09`→9, `007`→7, `' 5'`/`'5 '`/`'\t5\t'`/`'5\r'`/`'5\r\n'`→5, 18
nines accepted, `1000000000000000000` (19 digits)→0, `0000000000000000001` (19 chars)→0,
`000000000000000001` (18 chars)→1, `abc`/`''`/`-1`/`1e3`/`0x10`/`+7`/20 nines/`'5\n6'`/`'  '`/`*`/
`[0-9]`/`9223372036854775807`/non-ASCII digit/`'5 5'`→0. A NUL byte is dropped by `$(cat)` before the
function sees it (bash warning on stderr): `'5\0'`→5, `'5\0' '7'`→57.

**Differential** (Part A 1.7): the loop's inline parse `:317-322` and `read_counter` agree on all 27
seeds (0 disagreements), so the wrapper and the writer read the same number from the same file.

**Seed matrix through the whole wrapper** (Part B1, seeds `08 09 007 abc '' missing newline space
-1 1e3 0x10 +7 99999999999999999999 ' 5' '5 '`, BEFORE column from `cd6cbf2` for `08`, `abc`, `+7`,
`' 5'`; every AFTER link checked automatically for "finalize reached its last statement" and
"SCANCEL iff the breaker tripped"):

| File (T) | AFTER, every seed | BEFORE, where it differed |
|---|---|---|
| `.cycles_completed` (T1; `.failcount=2`, failing loop) | `failcount now 4/3`, breaker, SCANCEL, `finalize_end=yes` ×15 | `08`: `line 233: 08: value too great for base`, count left at 2, no `.breaker_tripped`, successor queued, `finalize_end=NO` |
| `.failcount` (T2; failing loop) | WARNING line whenever raw ≠ read; `08`/`09`/`007`/`' 5'`/`'5 '` read 8/9/7/5/5 → post-trip guard at entry (exit 0, no sbatch); the rest read 0 or 2 → written as 2 or 4; `finalize_end=yes` ×15 | `abc`: `line 311: abc: unbound variable`, nothing written, successor queued; `+7`: accepted by `test(1)` as 7, post-trip guard |
| `.chain_depth` (T3; +`199`, 18 nines) | WARNING iff raw ≠ read; depth = read+1 written; `199`→200 and 18 nines refuse to resubmit; `finalize_end=yes` ×17 | `08`: `line 141: … value too great for base`, `line 142: chaindepth: unbound variable`, no sbatch at all; `abc` the same |

**T4** (the o35 seed end to end, `08` + a loop that records a cycle with the real writer block then
fails, `.failcount=2`): BEFORE the wrapper died at `:233` with the cycle uncounted; AFTER `FAKE LOOP
recorded a cycle: 9`, `this link completed 1 cycle(s) before failing -- the run of consecutive
failures restarts, old count 2 dropped`, `failcount now 2/3`. **T5** (three links seeded `08`,
failing loop): 2, 4 + breaker + SCANCEL, link 3 exits 0 at the post-trip guard.

**The REAL loop script** (Part A W2, `KTG_ONE_CYCLE=1`, 22 seeds, fast guard, BEFORE then AFTER):
AFTER `08`→9, `09`→10, `007`→8, `' 5'`/`'5 '`/CRLF/newline/NUL→6, `5\0` `7`→58, every rejected seed→1
(including 20 nines, 19 digits and `0000000000000000001`), exit 0 throughout; BEFORE `08`/`09` died at
`:311` with the file left at `08`/`09`, 20 nines wrapped to `7766279631452241920`. W1: two clean
cycles on a fresh BASEDIR (real guard, then fast guard) record 1 then 2.

**Real scratch clone, `KTG_STAGE_ONLY=1`, `bash <script>` form**, BEFORE and AFTER: `STAGE_EXIT=0`
both; 80 files / 28 702 024 B each; sha256 manifest `diff` exit 0; `cmp bin/katago $KATAGO_BIN` exit
0; staged `selfplay.cfg` identical, `dataBoardLen = 9`. Archives removed afterwards.

**§ 2 closing check**, clean environment, real `sbatch` on PATH:

```
OK           : request gpus=1 cpus=24 part=b200 within policy (gpu<=4, no cpu cap)
SECTION2_EXIT=0
grep -c afterany=8 failcount=35 cpp/build/katago=5 cpp/katago"=0
```

`bash -n` clean on all four files in `codes/loop/`. Literal grep (o27): exit 1 over the two files;
over `codes/loop/` only `smoke_loop.sbatch:63` (another node's line, as before). `o08` exit 1. No
padded-integer writer under `codes/` (`printf %0Nd`, `seq -w`: grep exit 1). Nothing removes `STOP` or
`.cycles_completed`. Name sweep over the artifacts, evidence, candidate and this transcript: clean.
Queue: 298712 PENDING at start and end.

**Regression set** (Part B2), every outcome as in `validation_repair3.md` § 1: A `2 → 4`, breaker on
link 2, link 3 exits 0; B, B2a, C pre-flight failures `2 → 4` with SCANCEL; D/E deliberate stop, STOP,
SCANCEL, count 0; F counted, SCANCEL; G `2 → 0`; H leaves 2; J one accounting line; K1–K3 `scheduler
termination … failcount left at 0` ×3, no SCANCEL; K4 ×3 orderings `loop status 143, this wrapper not
signalled`; K5 loop finishes rc 0 after the wrapper's signal; K6 count 2 survives; M exit 137,
nothing written; L1a `1/3`, L1b `2/3`; L2 deliberate stop; N successor exits 0 at entry; O `1, 1, 1,
2, 2, 3` trip on link 6; P3 `1, 0, 0, 1, 0, 1` with `1 cycle(s) completed, so failcount 1 is cleared`;
P4 `old count 2 dropped`, `2 → 1`; P5 `2, 2, 2` (r4).

## 2. Attempts to break the repair — what they found

**X1 width boundary.** `.failcount` = 18 nines is accepted and stops the chain at entry; 19 digits,
and the valid-but-19-character `0000000000000000001`, read as 0 with a WARNING (one forgiven attempt,
bounded — see X8); `000000000000000001` reads as 1 and trips on the next fast failure (`3/3`). X1b:
`.cycles_completed` = 18 nines at entry, the real writer records `1000000000000000000` (19 digits),
finalize reads it as 0, the delta is negative and clamped, the cycle is not credited — harmless at
10^18 cycles, noted only. X1c: `0000000000000000001` at entry reads 0, the writer also reads 0 and
writes 1, the delta is 1 and the cycle is credited: the two parsers agree, so no false credit.

**X2 CRLF / NUL.** `2\r\n` in `.failcount` reads 2 (WARNING prints the raw value) → `4/3`, trip. A
trailing NUL reads correctly (bash warning). `5<NUL>7` reads 57 (the NUL vanishes in `$(cat)`), which
stops the chain at entry — the safe direction for `.failcount`; for `.cycles_completed` both readers
see the same 57/58. Not a gate: an embedded NUL is not a value an editor produces.

**X8 / X8b / X9 — is "unparsable `.failcount` → 0 with a WARNING" the right failure direction?**
Seeded `abc` and a crash loop: link 1 reads 0 (WARNING), writes 2; link 2 reads the clean 2, writes 4,
trips, SCANCEL. At the slow-failure floor (`KTG_MIN_RUNTIME_SECONDS=1`) it is 1, 2, 3 and trips on
link 3 — the nominal budget from a fresh count. The corrupt value persists only across links the
scheduler ends (X9: `abc` survives a walltime link with a WARNING and `failcount left at 0`; the next
failure writes 1). So for VALUES the forgiving direction costs at most one extra link, because
`finalize()` overwrites the file with a plain decimal on the next failure, and the alternative —
tripping on corruption — would cancel a healthy three-day chain on a CRLF left by an editor. The
validator judges the direction right for values, and the candidate's "unparsable value reads as 0"
sentence is admitted.

**X3 / X4 / X5 / X6 / X7 — the same direction on WRITES is wrong.** `.failcount` as a directory, chmod
000, or read-only with content 0: every failing link reads 0 (`cat` fails → `echo 0`, which is a
plain decimal, so no WARNING), prints `line 363: … Is a directory` / `Permission denied`, `failcount
now 2/3`, `chain continues`, and queues its successor — three links, three SBATCH, no SCANCEL, no
`.breaker_tripped`. The count never advances: the o26 class, a crash loop bounded only by
`KTG_MAX_CHAIN=200`. X6 (`.chain_depth` read-only): `line 184: Permission denied`, depth stays 1 —
with both files unwritable there is no bound at all. X5b shows that a read-only file holding 2 still
trips (the in-memory 4 is compared), so the exposure is specifically a count that cannot advance
across links. X7 (`chmod 555 BASEDIR`, existing files writable): the count still advances and the
breaker trips on link 2 with `touch: cannot touch '…/.breaker_tripped'`, successor cancelled — the
marker is not load-bearing. Part A 1.10: no state-file write in either script is checked.

**X10 — the operator knobs.** `KTG_MAX_FAILS=08`: the count is written, then `line 375: 08: value too
great for base` aborts finalize's last line (the worker's residual, one missing log line).
`KTG_MAX_FAILS=abc`: `line 366/414/457: [: abc: integer expression expected` — every `-ge` test is
false, so the breaker never trips: `2, 4, 6` over three links with a successor each time, then
`line 375: abc: unbound variable`. `KTG_MAX_CHAIN=abc`: `line 418: integer expression expected`, the
depth bound is gone. Slurm's default `--export=ALL` carries such a value down the whole chain (o33 d).

**X11** `.cycles_completed` as a directory with a cycle-recording loop: the real writer's redirect
fails under `set -e`, the loop exits 1 after the completed cycle (`Is a directory`), the wrapper counts
it (`4/3`, trip). Same on the real script (Part A W2, before and after). The a12 / hand-edit class,
not this obligation's. **X12** whitespace-only and two-line values read 0 with a WARNING.

None of X3–X7 or X10 is inside o35's statement (values consumed by arithmetic without a
plain-decimal check) or its closing conditions, and the candidate's claim does not assert that a
write succeeds; it is opened as **o36** (non-blocking) with the direction named — a count that cannot
be persisted and a threshold that cannot be compared must both fail CLOSED — and one qualification
is added to the result row's claim. The worker's own flag on `:375` is absorbed into o36.

Harness note: the shim log is per scenario, so the harness's `cancel_iff_trip` line reads VIOLATED
on the last link of T5, X7 and X8 (the SCANCEL belongs to the previous link); the wrapper lines are
the evidence. The D/E accounting line is hidden by the guard-output filter, as in the third record;
their state lines (`exit 3`, `STOP=yes`, SCANCEL) are unfiltered.

## 3. Verdict

| Item | Verdict | Gate |
|---|---|---|
| `o35_chain_state_files_unvalidated` | **Admit** — discharged | every closing condition reproduced with the validator's own shims, seeds and stand-in tree; finalize reaches its last statement for all 47 seeded links; the real loop script records 9 for `08`; dry run byte-identical; § 2 exit 0 |
| amended result row `r_loop_resume_under_walltime_static` | **Admit** at `existence_only`, claim carries one validator qualification (o36) | § 2 verifier exit 0 at append; no bypass flags |
| `o36_wrapper_fails_open_on_unwritable_state_and_bad_knobs` | **opened**, non-blocking | § 2 X3–X7, X10 |

Evidence type and status: `existence_only` is right — nothing ran on a GPU or under a real scheduler;
every executed cycle used dummy stages; c07/c08 still need `numerical_simulation`. Knowledge status
stays `preliminary`; no knowledge row was appended.

No AI tool or model name appears in the artifacts, the evidence files, the candidate rows, the
appended rows, the transcript or this record (case-insensitive sweep; the pattern file is not listed).

## 4. Rows appended (`CHANDRA_ROLE=validator`, no admission flags on any row)

| Ledger | Entry | Status | row_hash |
|---|---|---|---|
| result | `r_loop_resume_under_walltime_static` (amends `72ba1567…`) | `existence_only`, verifier exit 0 at append, `evidence_sha256 b2f991b2…` | `ff8a6553f58666d1ca748269543d4e3f779fd04d9c52e04f9d86ed49558117e9` |
| claim | `o35_chain_state_files_unvalidated` | `discharged` by `r_loop_resume_under_walltime_static` (amends `14fe758d…`) | `70066866fd8646729d89799580657230afefe10f32bc7b248a7becb77547bf89` |
| claim | `o36_wrapper_fails_open_on_unwritable_state_and_bad_knobs` | `open`, non-blocking, owner `loop_resume_under_walltime` | `e62e8bcb541e3bb782e2118da50a0875c59e76c620cf32b463ac63b096619175` |
| error | validation trial, iteration 6, `partial` (47/47 seeded links reach the end of finalize; the every-seed sentence admitted with a qualification) | node_seq 13 | `61648eb74190aa4d0167c83464c03abb5081ae2697f104c411901eb6ad6496fd` |

Views re-rendered from the ledgers: `decomposition/{claims,obligations,assumptions}.md`,
`decomposition/results.md`. Remaining `[OPEN]` under this node: `o25` (executed breaker proof, owner
`loop_failure_circuit_breaker`), `o33` (non-blocking) and `o36` (non-blocking, owner
`loop_resume_under_walltime`), `o13` / `o24` (knobs), `c07` / `c08` (need `numerical_simulation`). No
blocking obligation remains on this node's artifact pair.
