# Validation — `arxiv-1902.10565::loop_resume_under_walltime`

Role: validator (refuter, then judge). Cross-model relative to the worker that produced the
candidate. Inputs received: the task file (`tasks/loop_resume_under_walltime/implementation.md`,
claim §1 and §2 verification command), `evidence/loop_resume/candidate_rows.json`, the evidence
directory `evidence/loop_resume_under_walltime/`, the three artifacts under `codes/loop/`, their
upstream originals in `ref-code/lightvector-KataGo/python/selfplay/`, the worker's error-ledger row
`86d02063…`, and the ledger schemas. Host: login03 (no job submitted, no GPU touched).
Date: 2026-09-04 (UTC); 2026-09-03 evening local.

## 1. Refutation attempt — re-run the §2 verification command

Run from the az root, verbatim command from the task file §2:

```
bash -n results/ktg/paper_1902.10565/codes/loop/loop.sbatch && grep -q afterany results/ktg/paper_1902.10565/codes/loop/loop.sbatch && grep -q failcount results/ktg/paper_1902.10565/codes/loop/loop.sbatch && grep -q 'cpp/build/katago' results/ktg/paper_1902.10565/codes/loop/synchronous_loop_9x9.sh && ! grep -q 'cpp/katago"' results/ktg/paper_1902.10565/codes/loop/synchronous_loop_9x9.sh && bash "$(python3 -c 'import json;print(json.load(open("mission.json"))["compute"]["policyCheck"])')" --gpus 1 --cpus 24 --partition b200
```

Output:

```
== compute-budget self-check  2026-09-03T23:56:13-04:00 ==
my jobs      : gpus=2 cpus=32  (2 jobs)
partition b200 : free_gpus=0/128 (excludes reserved/drained nodes)
partition b300 : free_gpus=0/8 (excludes reserved/drained nodes)
reservations : 8 defined (6 active) — scontrol show reservation
quota        : | /home/ssci-haiyangw/ | 3.39 GB  | 100.00 GB |  3.39%   |
quota        : | /scratch/ssci-anima/ | 37.61 TB |  40.00 TB |   94%    |
OK           : request gpus=1 cpus=24 part=b200 within policy (gpu<=4, no cpu cap)
EXIT=0
```

Per-conjunct, measured independently (bash 5.1.8 on login03):

```
loop.sbatch bash -n exit=0
synchronous_loop_9x9.sh bash -n exit=0
export_model_for_selfplay_9x9.sh bash -n exit=0
train_9x9.sh bash -n exit=0            (owned by cfg_9x9_override; parsed only)
grep -c afterany loop.sbatch                     4
grep -c failcount loop.sbatch                   14
grep -c 'cpp/build/katago' synchronous_loop_9x9.sh   5
grep -c 'cpp/katago"' synchronous_loop_9x9.sh        0
```

Matches the worker's `conjuncts.txt` (4 / 14 / 5 / 0, check.sh exit 0). The refutation fails: the
static gate passes.

## 2. Refutation attempt — diff each copy against upstream

Upstream mirror at `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4` (v1.18.2), clean apart from the
untracked `PROVENANCE.md`. `diff -u` re-run by the validator against both copies; every hunk was
classified:

| Deviation | Where | Justified by |
|---|---|---|
| `SELFPLAY_CONFIG` / `GATING_CONFIG` → `codes/cfg/*_9x9.cfg` | sync :125-126 vs upstream :70-71 | task §10 (o13); upstream lines confirmed |
| binary copy from `${KATAGO_BIN:-$GITROOTDIR/cpp/build/katago}` + `-x` guard | sync :153-159 vs upstream :81 | task §10 (o17); upstream :81 confirmed `cp "$GITROOTDIR"/cpp/katago` |
| `./train_9x9.sh` in place of `./train.sh` | sync :245 vs upstream :109 | task §10 (train wrapper row) |
| `./export_model_for_selfplay_9x9.sh` in place of upstream :113 | sync :251 | task §10 (export helper row) |
| `-epochs-per-export N -max-epochs-this-instance N` | sync :121, :245 | task §10 (one candidate per cycle) |
| `MODELKIND` `*tfrs|*tflrs` assertion, exit 2 | sync :56-63 | task §10 (`MODELKIND` assertion row) |
| `USEGATING -ne 1` refusal | sync :66-70 | task §13 ("never set USEGATING=0") |
| git-root == `$KATAGO_SRC` assertion | sync :79-88 | task §11 (read-only-mirror risk) |
| startup `.exported` / `shuffleddata/*.tmp` sweep | sync :177-182, sbatch :178-180 | task §10 (startup cleanup row; o09) |
| per-cycle `du -sb` soft-cap guard, `STOP` check | sync :210-227 | task §10 (scratch guard, stop guard) |
| `KTG_ONE_CYCLE=1` one-cycle exit | sync :256-261 | header change 8; consumed by `synchronous_loop_smoke` |
| knob block made `${VAR:-default}` with 9x9 production defaults | sync :107-116 | task §10 (production knobs `[HYPOTHESIS]`) |
| export: `mv "$TMPDST" "$TARGET"` (:161) before `rm -r "$SRC"` (:162) | vs upstream :89 then :108 | task §10 (o09); upstream order confirmed |
| export: exit codes of `export_model_pytorch.py` / `clean_checkpoint.py` captured, `TMPDST` removed, `SRC` kept on failure | export :105-138 | task §10 (o15 mention) |
| export: "already exists" branch completes an interrupted move when `TARGET` and `SRC` both exist | export :90-100 | header change B (see finding F3) |

Deviations NOT listed in the task file's §10 table (all inside the `[HYPOTHESIS]` knob block or
harmless): `NUM_TRAIN_SAMPLES_PER_SWA` 80000 → 40000 (sync :111); `mkdir -p torchmodels_toexport`
(sync :99); the `KTG_STAGE_ONLY=1` dry-run hook (sync :197-202), which exits before any engine
stage. None changes the cycle order or a stage's arguments beyond the listed rows. Recorded here so
the §5 "every deviation is one row" rule is auditable; not a gate failure.

## 3. Refutation attempt — reproduce the executed dry run independently

The worker's `stage_dryrun.txt` was reproduced with a fresh `BASEDIR` (deleted afterwards):

```
KATAGO_SRC=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/build/KataGo KATAGO_BIN=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/build/KataGo/cpp/build/katago
KTG_STAGE_ONLY=1 -- archive staged at /weka/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/loop_valdryrun/scripts/dated/20260903-235942, no cycle run.
-rwxr-xr-x 1 ssci-haiyangw users 27273864 Sep  3 23:59 .../loop_valdryrun/scripts/dated/20260903-235942/bin/katago
-rwxr-xr-x 1 ssci-haiyangw users     7283 Sep  3 23:59 .../export_model_for_selfplay_9x9.sh
-rw-r--r-- 1 ssci-haiyangw users     4704 Sep  3 23:59 .../gatekeeper.cfg
-rw-r--r-- 1 ssci-haiyangw users     9786 Sep  3 23:59 .../selfplay.cfg
-rwxr-xr-x 1 ssci-haiyangw users     3965 Sep  3 23:59 .../train_9x9.sh
dryrun exit=0
cmp katago: identical
cmp selfplay.cfg: identical
cmp gatekeeper.cfg: identical
28:dataBoardLen = 9
98:     -pos-len 9 \
161:                mv "$TMPDST" "$TARGET"
162:                rm -r "$SRC"
28M	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/loop_valdryrun
--- cleanup
ls: cannot access '/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/loop_valdryrun': No such file or directory
```

The worker's dry-run directory (`loop_stagedryrun`) and probe directory (`guardprobe`) are absent
from the mission root, as claimed. `$KTG_ROOT/env.sh` is byte-identical to `codes/env/env.sh` and
exports `KATAGO_SRC`, `KATAGO_BIN` (:20-22). `$KTG_ROOT/logs` exists (needed by `#SBATCH --output`
before the first job can write anything).

## 4. Claim-level check

- The ledger enum has no `static_verification`; the artifact exists, parses, and greps as claimed,
  and nothing was executed on a GPU. `existence_only` / `existence_only` is the honest pair.
  `checked` is excluded by gate 7 (open obligations under the node) and `empirical` /
  `numerical_simulation` by the absence of any run. The worker's `_validator_decision_point` was
  read and agreed with; no upgrade.
- Knowledge status `preliminary`: `solid` is excluded twice over — the node's own claims
  `c07` / `c08` need `numerical_simulation` evidence that does not exist yet, and predecessor
  `train_resume_semantics` is `preliminary`, so a `solid` chain cannot rest on it.
- Dependencies `arxiv-1902.10565::env_build` (solid) and `arxiv-1902.10565::train_resume_semantics`
  (preliminary) resolve in the knowledge ledger. All five evidence files exist. No `checked` /
  `solid` anywhere in the candidate rows.

## 5. Scratch-budget constants — honest, but the stated reason is wrong

The wrapper keeps `214748364800` / `193273528320` (200 / 180 GiB) at `loop.sbatch:74-75`
(`:195` hard-codes the soft literal into the log line even when the variable is overridden) and
`synchronous_loop_9x9.sh:190-191`, while `mission.json` `decisions[]` (human, 2026-09-03) sets
500 GiB. The worker flagged this as `[OPEN] scratch-budget-propagation` — visible, not hidden —
but with an incorrect justification:

- The worker wrote that "this node's closing check greps for the literal 193273528320". It does
  not: the §2 command greps `afterany`, `failcount`, `cpp/build/katago`, `cpp/katago"` only. A
  repo-wide grep finds the literal in the stale task-file prose, the worker's own comment, and the
  two scripts — in no verification command. `data_budget`'s §2 greps `budget.env` for
  `KTG_SCRATCH_HARD_BYTES=536870912000`, the 500 GiB figure.
- The worker wrote that `o04` still says 200 / 180 GiB. The claim ledger's latest `o04` row
  (appended 2026-09-04T03:56Z, four minutes after the candidate was staged, so the worker could not
  have seen it) already carries the 500 GiB cap and requires the loop wrapper to call
  `codes/data_budget/scratch_guard.sh` before every cycle; its notes name `loop.sbatch:74-75` as the
  unmet conjunct and `loop_resume_under_walltime` as the node that must change it.
  `codes/data_budget/{scratch_guard.sh,budget.env}` exist (staged, uncommitted by that worker).

Consequence: the discrepancy stays an [OPEN] repair obligation, re-stated with the correct facts
and the correct owner (`o27_scratch_guard_reconcile_500gib`, owner `loop_resume_under_walltime`,
blocking). It does not fail a gate for an `existence_only` row whose claim text does not assert the
threshold; the worker's wrong rationale is not copied into the ledger.

## 6. Refutation attempt — Slurm chain logic, by reading

Checked and holding: `--dependency=afterany:$SLURM_JOB_ID` issued at the top of the body
(`:157`), successor named by absolute path `$SELF` (`:46`, `:148`) — the `$0` correction is right,
inside a batch job `$0` is the spool copy; `--parsable` output is matched by `^[0-9]+$`, which is
correct on this cluster (`ClusterName=skipjack`, `FederationParameters=(null)` → plain job id);
`.failcount` read once at the top (`:98`) and rewritten at the tail (`:223`, `:235`), so the
resubmit decision in link N uses the count written by link N-1 — three plain failures give three
executed links and a cancelled fourth, a fast-failure crash loop trips on the second link
(`:231-234`); the compute-policy pre-flight runs before every `sbatch` (`:143`) and a missing
`mission.json` refuses to chain rather than skipping the check (`:140`); the depth cap increments per
link and never resets (`:99-100`, `:131`); `STOP` is honoured before the resubmit (`:124`), at entry
(`:204`) and at the top of every cycle (sync `:210`); the scratch-cap exit path cancels the queued
successor (`:199`).

Holes found:

- **F1 (reproduced, § 7 B/C) — early exits bypass the breaker and leave the successor queued.**
  Every `exit` between `resubmit` (`:157`) and the breaker section (`:221`) skips the failcount
  update and the `scancel`: `:209` (`missing $LOOP_SH`, exit 2), `:213` (`cd` failure, exit 2), and
  any `set -u` abort — in particular `$KATAGO_SRC` at `:213` is defined only by `env.sh`, so a
  missing or unreadable `env.sh` aborts with `KATAGO_SRC: unbound variable`. Each such link ends in
  seconds with `.failcount` unchanged and its successor already queued; the next link repeats. The
  only bound is `KTG_MAX_CHAIN=200`.
- **F2 (reproduced, § 7 A3) — a successor that starts after the breaker tripped still runs the
  loop once.** `resubmit()` returns without queueing (`:127-130`) but the script continues into
  `:216`; if the `scancel` at `:242` raced or failed, the breaker at 3 yields four executed attempts.
- **F3 — Slurm-level kills are invisible to the counter.** TIMEOUT, cgroup OOM and node failure
  kill the bash tail before `:221`, so `.failcount` never increments. Correct for the walltime
  design, but a deterministic OOM (120G exceeded in the trainer) would recur on every link until
  depth 200. The successor does not consult `sacct` on its predecessor's state.
- **F4 — export change B is narrower than described.** `:93` completes the interrupted move only
  while `TARGET` is still in `modelstobetested/`. In the realistic kill-between-`mv`-and-`rm`
  case the next link's gatekeeper runs first and moves the candidate to `models/` or
  `rejectedmodels/`, so `TARGET` is gone, the branch falls through to "already exists, skipping",
  and `SRC` lingers in `torchmodels_toexport/` forever. Harmless leak (one checkpoint dir per such
  kill; names never recur), but "completes an interrupted rename on the next pass" holds only in
  the narrow case. The `o09` disjunction itself is satisfied regardless.
- **F5 — pre-flight over-counts.** Inside the running job `check.sh` counts this job's own GPU in
  `my_gpus` and adds the successor's request, although the successor only runs after this job
  frees its GPU. With three other GPUs busy the chain silently ends (a chain break, the opposite
  failure to a runaway).
- **F6 — misleading log line.** `:195` prints `soft 193273528320` regardless of
  `KTG_SCRATCH_SOFT_BYTES`.
- **F7 — operational.** After a trip, a manual resubmit reads `.failcount >= 3`, does not chain,
  runs once, and if it succeeds resets the count with no successor queued; the operator must delete
  `.failcount` / `.breaker_tripped` to restart the chain. `KTG_KEEP_ARCHIVES` pruning is safe only
  under one chain per `BASEDIR`.

F1 and F2 go into repair obligation `o26_wrapper_early_exit_bypasses_breaker` (owner
`loop_resume_under_walltime`, blocking). F3 goes into the executed-proof obligation
`o25_chain_breaker_executed_proof` (owner `loop_failure_circuit_breaker`), since only a run can
show how the chain behaves under a scheduler kill. F4-F7 are recorded in the result row notes.

## 7. Refutation attempt — offline chain simulation (no Slurm, no GPU)

`loop.sbatch` was run directly on the login node with `PATH` shims for `sbatch` (logs its
arguments, prints `424242`), `scancel` (logs), and `sinfo` / `scontrol` / `squeue` (exit 0);
`KTG_ROOT`, `KTG_CODES`, `KTG_LOOP_SBATCH`, `BASEDIR` pointed into a scratchpad directory; a stub
`env.sh` exporting `KATAGO_SRC`; a fake `synchronous_loop_9x9.sh` that exits 1 immediately. The
real `mission.json` and `check.sh` were used. `$SIM` below abbreviates the scratchpad path; the
rest is verbatim (timestamps stripped from the `say` lines).

```
########## Scenario A: crash loop (fake loop exits 1 in <1 s) -- breaker arithmetic
----- link: A1
=== chain depth 1/200, failcount 0/3 ===
=== successor queued: 424242 (partition b200, dependency afterany:1001) ===
=== loop exited rc=1 after 1s ===
=== fast failure: 1s < 600s -- counting it twice ===
=== failure -- failcount now 2/3 ===
=== chain continues, 1 attempt(s) left before the breaker ===
.failcount=2  .chain_depth=1  breaker_tripped=no
----- link: A2
=== chain depth 2/200, failcount 2/3 ===
=== successor queued: 424242 (partition b200, dependency afterany:1002) ===
=== loop exited rc=1 after 1s ===
=== fast failure: 1s < 600s -- counting it twice ===
=== failure -- failcount now 4/3 ===
=== circuit breaker tripped after 4 consecutive failures (last ran 1s) ===
=== cancelling queued successor 424242 ===
.failcount=4  .chain_depth=2  breaker_tripped=yes
----- link: A3   (a successor that starts anyway, e.g. the scancel raced)
=== chain depth 3/200, failcount 4/3 ===
=== circuit breaker: failcount 4 >= 3 -- not resubmitting ===
=== starting the loop: $SIM/codes/loop/synchronous_loop_9x9.sh ktg9 $SIM/ktg/loop t9 b7c96h3tfrs 1 ===
=== loop exited rc=1 after 1s ===
.failcount=6  .chain_depth=3  breaker_tripped=yes
--- scheduler shim log
SBATCH --parsable --partition=b200 --dependency=afterany:1001 $SIM/loop.sbatch
SBATCH --parsable --partition=b200 --dependency=afterany:1002 $SIM/loop.sbatch
SCANCEL 424242

########## Scenario B: env.sh missing -> early exit before the breaker section
----- link: B1
=== chain depth 1/200, failcount 0/3 ===
=== successor queued: 424242 (partition b200, dependency afterany:2001) ===
$SIM/loop.sbatch: line 162: $SIM/ktg/env.sh: No such file or directory
$SIM/loop.sbatch: line 213: KATAGO_SRC: unbound variable
.failcount=0  .chain_depth=1  breaker_tripped=no
----- link: B2
=== chain depth 2/200, failcount 0/3 ===
=== successor queued: 424242 (partition b200, dependency afterany:2002) ===
$SIM/loop.sbatch: line 213: KATAGO_SRC: unbound variable
.failcount=0  .chain_depth=2  breaker_tripped=no
--- scheduler shim log
SBATCH --parsable --partition=b200 --dependency=afterany:2001 $SIM/loop.sbatch
SBATCH --parsable --partition=b200 --dependency=afterany:2002 $SIM/loop.sbatch
(no SCANCEL)

########## Scenario C: LOOP_SH missing -> exit 2 before the breaker section
----- link: C1
=== successor queued: 424242 (partition b200, dependency afterany:3001) ===
=== missing $SIM/codes/loop/synchronous_loop_9x9.sh ===
.failcount=0  .chain_depth=1  breaker_tripped=no
----- link: C2
=== successor queued: 424242 (partition b200, dependency afterany:3002) ===
=== missing $SIM/codes/loop/synchronous_loop_9x9.sh ===
.failcount=0  .chain_depth=2  breaker_tripped=no
--- scheduler shim log
SBATCH --parsable --partition=b200 --dependency=afterany:3001 $SIM/loop.sbatch
SBATCH --parsable --partition=b200 --dependency=afterany:3002 $SIM/loop.sbatch
(no SCANCEL)
```

Scenario A confirms the claimed breaker arithmetic and the minimum-runtime penalty. Scenarios B
and C confirm F1; link A3 confirms F2.

## 8. Other checks

- No AI tool or model name appears in the artifacts, the evidence directory, the task file, or this
  file (checked with a case-insensitive grep over the usual vendor and model names).
- `codes/cfg/*_9x9.cfg` and `codes/loop/train_9x9.sh`, which the loop copy requires at `:132-139`,
  exist in the working tree but are untracked (owned by `cfg_9x9_override`, not yet committed).
  The §2 check does not depend on them; the dry run does. Recorded as a caveat, not a gate.
- The worker appended only its error-ledger trial (`86d02063…`, pass, 6/6 conjuncts); no result,
  knowledge or claim row was appended by the worker, as it stated.

## 9. Verdict

**Admit** at `existence_only` (result) / `preliminary` (knowledge). No admission gate fails: the
static verifier passes on re-run, every deviation from upstream is justified by the task file or an
obligation, the executed dry run reproduces, the evidence type matches the claim level, the
dependencies resolve, and every discrepancy is an [OPEN] obligation, not a hidden one. The findings
above sharpen the open items into three named obligations (o25, o26, o27) rather than overturning a
verified fact. `o09_export_kill_window` and `o17_loop_katago_bin_path` are discharged by the
admitted result row; `o13`, `c07`, `c08` stay open. The ad-hoc names the worker used
(`chain-runaway`, `scratch-budget-propagation`, `production-knobs`) map to `o25`/`o26`, `o27`, and
the existing `o24_cycle_knobs_derived`.

Rows appended are listed in § 10 (filled in after the appends).

## 10. Rows appended (`CHANDRA_ROLE=validator`, no bypass flags on any row)

| Ledger | Entry | Status | row_hash |
|---|---|---|---|
| result | `r_loop_resume_under_walltime_static` | `existence_only` / `existence_only`, verifier exit 0, `evidence_sha256 64c7d132…` | `7df3425fc2927058deb39c4ef967b6318a9cdaec6beb46c804ed21ef73e56155` |
| knowledge | `arxiv-1902.10565::loop_resume_under_walltime` (node_seq 4) | `preliminary`, verification re-run exit 0 | `de2aeca80104cf31eb2e63ce9a232db26eff0c51667cae8ef691df27f89882b6` |
| claim | `o09_export_kill_window` | `discharged` by `r_loop_resume_under_walltime_static` | `e2d889fd8e4e40181f39058e6ca707f0fd58f2cfff6715af38c42d84bd619adf` |
| claim | `o17_loop_katago_bin_path` | `discharged` by `r_loop_resume_under_walltime_static` | `bfba72a589739d7d7e7e3e4659fb65bd0db509515ae61d83846eb81f3c4967e1` |
| claim | `o13_loop_config_paths` | `open` (2/3 conjuncts executed; knobs await o24) | `7edac62a1dc10d2f2b6e4b50cad54dd0e2edc3f28eaebdd0bfbbe6a6b648bcaf` |
| claim | `c07_loop_cycle_completes` | `open` | `8c215221168d2ef9b120ab9c2e7ea0853c3df72109539f615e0dbe0054e08cbd` |
| claim | `c08_resume_no_loss` | `open` | `3e8e5ae3a549d0d587e3c3fbec71cf75ee1e5efc30f98c59346f0f28cb594fbe` |
| claim | `o25_chain_breaker_executed_proof` | `open`, blocking, owner `loop_failure_circuit_breaker` | `ab5ee1aacd8fcece296a65e8645793be80d385306a721bade3715030dafa7732` |
| claim | `o26_wrapper_early_exit_bypasses_breaker` | `open`, blocking, owner `loop_resume_under_walltime` | `bdcf0229707df53702c6b1242efbb693ec0391670766d3831955c3c97134cd1e` |
| claim | `o27_scratch_guard_reconcile_500gib` | `open`, blocking, owner `loop_resume_under_walltime` | `b4cfaf6a76b3803d109afbe4e3a2f1a8affc326c049b64430bb2c437819b1ecf` |

Views re-rendered from the ledgers: `decomposition/{claims,obligations,assumptions}.md` and
`decomposition/results.md`. `o04_scratch_budget` was not re-appended: its latest row (data_budget,
2026-09-04T03:56Z) already states the 500 GiB / `scratch_guard.sh` contract and names the wrapper
literal as the unmet conjunct; `o27` is the wrapper-side repair that closes it.
