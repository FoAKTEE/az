# Validation of the repair packet — `arxiv-1902.10565::loop_resume_under_walltime` (o26 / o27 / o08)

Role: validator (refuter, then judge), cross-model relative to the worker. Inputs received: the
candidate transitions `evidence/loop_resume/candidate_rows_repair.json`, the worker's evidence
`evidence/loop_resume/repair_o26_o27.txt` (sha256 `4a100f18…`), the three artifacts under
`codes/loop/`, the guard they call under `codes/data_budget/` (working tree, uncommitted by its
owning node and changing during this session), the task file § 2, the worker's error-ledger rows
`d49f3d1f…`, `fbc80e02…`, `1e058596…` (the last corrects "15 of 15" to 19 wrapper invocations in
10 scenario groups), the previous validation `evidence/loop_resume/validation.md`, and the ledger
schemas. Host: login03, CPU only, no Slurm job submitted, no GPU. Date: 2026-09-04 (UTC).

Verbatim transcript of everything below: `evidence/loop_resume/validation_repair_harness.txt`
(the run, then the harness source). The harness is the validator's own — its `sbatch`, `scancel`,
`sinfo`, `sacct`, `scontrol`, `squeue`, `nvidia-smi` are PATH shims written for this run under
`/scratch/…/ktg-train/runtime/validate_repair/` (deleted afterwards); the real `mission.json`, the
real compute-policy script and the real `codes/data_budget/` tools were used unmodified.

Files under test at run time (sha256): `loop.sbatch 4485f6ea…`, `synchronous_loop_9x9.sh 20a7f5b3…`,
`export_model_for_selfplay_9x9.sh e616f260…` (the worker's header lists `38b824b4…`, the pre-o08
version; § 4 of its evidence post-dates the header), `scratch_guard.sh 361ad2c0…` (worker:
`aa147a41…`), `budget.env 6f38681e…`, `prune_retention.py 32d27040…`. The wrapper depends on the
guard only through its exit-code contract (0/1/2/3), which the guard header pins.

## 1. Refutation attempts that failed (the repair holds here)

Static. `bash -n` clean on all three files. The worker's grep pattern
(`214748364800|193273528320|536870912000|1099511627776|du -sb "|/apps/helpers/quotas.py`) over
`codes/loop/` exits 1. `grep -rn 'export_model\.py'` over all of `codes/` exits 1 (o08). The
§ 2 closing check, verbatim, in a clean environment with the real PATH:

```
OK           : request gpus=1 cpus=24 part=b200 within policy (gpu<=4, no cpu cap)
SECTION2_EXIT=0
grep -c afterany=6 failcount=22 cpp/build/katago=5 cpp/katago"=0
```

Offline injection, each line as the worker recorded it (fake loop exits in seconds, so the
600 s minimum-runtime penalty counts each failure twice):

| Scenario | Result (validator's run) |
|---|---|
| A crash loop, 3 links | failcount 2 → 4, `circuit breaker tripped after 4`, `SCANCEL 700002`; link 3: `breaker already tripped … exits without running the loop`, count stays 4 |
| B env.sh missing, 2 links | `PRE-FLIGHT FAILURE rc=2`, failcount 2 → 4, `SCANCEL` after each link |
| B2 explicit env.sh checks deleted | raw `KATAGO_SRC: unbound variable` → `PRE-FLIGHT FAILURE rc=1`, failcount 2, `SCANCEL` |
| C loop script missing, 2 links | failcount 2 → 4, `SCANCEL` after each link |
| D guard exit 1 (`tests/fixture_tinycap.env`) | `deliberate chain stop (rc=3)`, STOP written, `SCANCEL`, failcount 0 |
| E guard exit 2 (`tests/fixture_failfloor.env`) | same shape, failcount 0 |
| F guard exit 3 (out-of-tree constants file) | `PRE-FLIGHT FAILURE rc=2`, failcount 2, `SCANCEL` |
| G clean cycle after a failure | `clean exit -- failcount reset to 0` (2 → 0) |
| H STOP at entry after a failure | `exit 0 before the loop started -- failcount left at 2` |
| J trap probes (copy with `( exit 7 ); $(exit 4); ( sleep 0 ) & wait` after the trap and `finalize "$RC"; finalize "$RC"` before the final exit) | one accounting line, failcount 2: subshell exits do not fire the trap, the `FINALIZED` guard makes a second call a no-op |

Fixture injection is legitimate: the guard honours `KTG_BUDGET_ENV` for any file that resolves
inside its own directory (`scratch_guard.sh` `case "$BUDGET_ENV_REAL" in "$HERE"/*`), and the
committed `tests/fixture_*.env` files are inside it, so scenarios D and E use the guard's own
allow-list, not a bypass. The pruner accepts the same fixture (it prints `constants : …/tests/fixture_tinycap.env`)
and its deletion plan stays confined to `--basedir` (0 paths removed in every run).

Writers of `.failcount`: `loop.sbatch:172` and `:189`, both inside `finalize()`, plus `:104`
(`[ -f … ] || echo 0 >`), an initialise-to-0 when the file is absent — not an accounting write,
and the documented restart (`rm .failcount .breaker_tripped`) relies on it. The candidate's
"exactly one place" is therefore true of accounting writes only.

F7 (one chain per `BASEDIR`) is recorded, not hidden: it is in the candidate result row's
`assumptions` and `open_after_repair`; this validation adds it to the claim ledger as
`a12_single_chain_per_basedir` so it appears in the assumptions view.

## 2. Refutation that succeeded — the chain's normal end is misclassified (o26)

The candidate's o26 discharge says "every termination path between the resubmit and the end of
the script updates the count … and cancels the queued successor". The worker's injection run has
no signal scenario. Two facts, both checked here:

- `scontrol show config` → `KillWait = 30 sec`; partition `MaxTime=3-00:00:00`, `OverTimeLimit=NONE`.
  Every healthy link of this chain ends at `--time 2-23:30:00` with SIGTERM to the job's
  processes, then SIGKILL after 30 s; `scancel` follows the same path.
- bash 5.1.8 runs the EXIT trap on SIGTERM. Probe outside the wrapper: child terminated first →
  `EXIT trap ran, rc=143`; bash signalled alone → `EXIT trap ran, rc=0` (bash does not wait for the
  child); SIGKILL → no trap.

Scenario K drives `loop.sbatch` with a fake loop that sleeps, waits for `starting the loop`, and
sends SIGTERM the way slurmstepd does, to the link's whole process group. `KTG_MIN_RUNTIME_SECONDS=1`
so the fast-failure penalty plays no part (a real link runs ~3 days):

```
----- link: K1   (SIGTERM, mode=pgrp)
=== starting the loop: $SIM/codes/loop/synchronous_loop_9x9.sh ktg9 $SIM/ktg/loop t9 b7c96h3tfrs 1 ===
FAKE LOOP ran: ktg9 $SIM/ktg/loop t9 b7c96h3tfrs 1
Terminated
=== clean exit -- failcount reset to 0 ===
wrapper exit=143  .failcount=0  .chain_depth=1  breaker_tripped=no  STOP=no
   (K2, K3 identical: 3 of 3 runs)
----- link: K4   (SIGTERM, mode=child-first)
=== loop exited rc=143 after 6s ===
=== failure rc=143 -- failcount now 1/3 ===
=== chain continues, 2 attempt(s) left before the breaker ===
wrapper exit=143  .failcount=1  .chain_depth=1  breaker_tripped=no  STOP=no
----- link: K5   (SIGTERM, mode=bash-only)
=== clean exit -- failcount reset to 0 ===
wrapper exit=143  .failcount=0  .chain_depth=1  breaker_tripped=no  STOP=no
```

`finalize` has no branch for a scheduler termination. Depending on which process sees the signal
first it books the link as a clean cycle (reset to 0 — on a link whose loop was killed mid-cycle,
and the log line says "clean exit") or as a failure (+1, successor kept). Three links of the second
kind trip the breaker and `scancel` a healthy chain; the previous validation's F3 ("a Slurm-level
kill ends the bash tail before the breaker section, so `.failcount` never increments") described the
pre-repair wrapper, which had no trap. SIGKILL still runs no trap and stays o25's territory.

Scenario L, a second classification hole in the same function: the loop exits 3 for any reason
other than the storage guard (STOP not written):

```
=== loop exited rc=3 after 5s ===
=== the loop stopped on the storage guard -- treating as a deliberate chain stop ===
=== cancelling queued successor 700001 (storage guard stopped the chain) ===
wrapper exit=3  .failcount=0  .chain_depth=1  breaker_tripped=no  STOP=no
```

`loop.sbatch:403` keys on `RC == 3` alone; the loop script writes STOP before its `exit 3`
(`synchronous_loop_9x9.sh:245`), so the file is available as the discriminator and is not used.

Failed gate, in plain language (spec § Validation gates 3 and 6): the evidence type offered is
"offline injection of every termination path", and the path every healthy link takes is absent
from it; exercised, the repaired code classifies it wrongly. o26 is therefore not discharged. The
process-internal early exits it was raised for are fixed (§ 1), so it is kept open with a dependency
on the new blocking obligation `o31_wrapper_scheduler_termination_classification`, whose statement
carries the fix shape (a TERM trap setting a flag before the loop; `finalize` treats the flag or a
128+15 status as "scheduler termination: leave the count, keep the successor"; `RC == 3` counts as
a storage stop only with STOP present) and the closing scenarios.

## 3. o27 and o08 — admitted

o27's closing condition: literals replaced by the guard call plus `prune_retention.py` at startup,
§ 2 exit 0, data_budget's closing check passes against the wrapper. The first two are reproduced
in § 1 (D, E, F show the exit-code contract honoured; no `--root` is passed to either tool). The
third: data_budget's § 2 command tests the guard, not the wrapper — the conjunct exists only in
the form "the wrapper honours the contract the guard header states", which is what D/E/F show.
One imprecision recorded: the candidate's "a grep for … du -sb and quotas.py returns nothing" holds
for the worker's anchored pattern; the unanchored words survive in one comment
(`synchronous_loop_9x9.sh:223`, describing what the guard prints). No executable `du`/`df`/`quotas`
call remains. Not a gate failure.

o08: the last hit was a usage string; the invocation has always been `./export_model_pytorch.py`
(`:133`). The unescaped regex in the obligation text matches every correct `export_model_pytorch.py`
mention (`.` matches `_`, then `py`), so the escaped form is the meaningful test and it exits 1.

`discharged_by` must resolve to a result row or knowledge node (`claims_database.py describe-fields`),
so the amended result row was appended first and both obligations cite `r_loop_resume_under_walltime_static`.
The amended row's claim was narrowed by the validator to what was verified — the SIGTERM path and
the exit-3 collision are excluded and listed under `open_obligations` as o31 — and its
`verifier_result.detail` figure "15 scenarios" is replaced by the record of 19 invocations / 10 groups.

## 4. Verdict

| Obligation | Verdict | Gate |
|---|---|---|
| `o26_wrapper_early_exit_bypasses_breaker` | **Reject** (kept open, now depends on o31) | evidence omits the dominant termination path; exercised, the code misclassifies it |
| `o27_scratch_guard_reconcile_500gib` | **Admit** — discharged | all conjuncts reproduced |
| `o08_exporter_name` | **Admit** — discharged | grep exits 1, invocation correct |
| amended result row `r_loop_resume_under_walltime_static` | **Admit** at `existence_only`, claim narrowed | § 2 verifier exit 0 at append; no bypass flags |

No AI tool or model name appears in the artifacts, the evidence files or this record (checked
with a case-insensitive grep over the usual vendor and model names).

## 5. Rows appended (`CHANDRA_ROLE=validator`, no admission flags on any row)

| Ledger | Entry | Status | row_hash |
|---|---|---|---|
| claim | `a12_single_chain_per_basedir` | assumption, `active` (F7) | `2d39b7d3d0965c8127ff35f623ba7718fabbbe050ae8a37880ef5408843c60c4` |
| claim | `o31_wrapper_scheduler_termination_classification` | `open`, blocking, owner `loop_resume_under_walltime` | `9263ab65ac3db72d0b2bfad63b3a304c6f62a4f8ed077a12d828f0b07405629c` |
| result | `r_loop_resume_under_walltime_static` (amends `7df3425f…`) | `existence_only`, verifier exit 0, `evidence_sha256 4a100f18…` | `6227934bca847e8d5eb0d3a62d050158de2e04f8a2f854d3e9480231ed3db8c8` |
| claim | `o27_scratch_guard_reconcile_500gib` | `discharged` by `r_loop_resume_under_walltime_static` | `914f6cf9c7f012765ec80c62bba64979a9b0db32117a3ef8be9454f7f4924aff` |
| claim | `o08_exporter_name` | `discharged` by `r_loop_resume_under_walltime_static` | `5af48e8f74b58517625226ded9a3cd6854bceccd09080fa4d2223dce00d2427b` |
| claim | `o26_wrapper_early_exit_bypasses_breaker` | `open` (amends `bdcf0229…`) | `d2e081aaa3cd3c4ec754fb55b9049dec4531d06c84d0510af236450802a940e8` |
| error | validation trial, iteration 5, `fail`, metric 9/11 termination classes | `uncategorized_numerical` (candidate tag noted in the row) | `b7a065685391f8820143024797c202b0f044dc5638dbf0b929a6d59c2195b4bf` |

Views re-rendered from the ledgers: `decomposition/{claims,obligations,assumptions}.md`,
`decomposition/results.md`. Remaining `[OPEN]` under this node: `o25` (executed breaker proof,
owner `loop_failure_circuit_breaker`), `o26` + `o31` (owner `loop_resume_under_walltime`), `o13`
/ `o24` (knobs), `c07` / `c08` (need `numerical_simulation`). Knowledge status stays `preliminary`;
no knowledge row was appended.
