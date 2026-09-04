# progress — `loop_resume_under_walltime`

Node `arxiv-1902.10565::loop_resume_under_walltime`, wave 1. Static-verification node:
it authors the Slurm chain wrapper and the two mission loop copies, and submits nothing
(task file §13). Evidence lives under
`results/ktg/paper_1902.10565/evidence/loop_resume_under_walltime/`.

## Landed

| phase | files | outcome |
|---|---|---|
| 1 loop copy | `codes/loop/synchronous_loop_9x9.sh`, `codes/loop/export_model_for_selfplay_9x9.sh` | `bash -n` clean on both; the three upstream defects repaired; four refusal paths exercised on the login node |
| 2 wrapper | `codes/loop/loop.sbatch` | §2 closing check exits 0 on all six conjuncts |

## Closing check

`EXIT=0`. Conjuncts: `bash -n loop.sbatch` clean · `afterany` 4 · `failcount` 14 ·
`cpp/build/katago` 5 · `cpp/katago"` 0 · `check.sh --gpus 1 --cpus 24 --partition b200`
exit 0. Verbatim output in `evidence/loop_resume_under_walltime/verification.txt`.

## Why each upstream change exists

- `synchronous_loop.sh:81` copies a binary from a path the CMake build never produces
  (`env.sh:20-22` puts it at `cpp/build/katago`); under `#!/bin/bash -eu` that `cp` kills
  cycle 1 before any work happens — `o17`.
- `:70-71` point at the mixed-board-size `selfplay1.cfg` / `gatekeeper1.cfg` — `o13`.
- `export_model_for_selfplay.sh` removes the source checkpoint at `:89` *before* the
  rename at `:108`; a kill in that window destroys the only copy and leaves a
  `<NAME>.exported` marker that `:54-56` skips forever — `o09`. The mission copy renames
  first and removes second, sweeps stale markers on startup, and completes an interrupted
  rename on the next pass.

## Executed without a job

`KTG_STAGE_ONLY=1` is a dry-run hook in the loop copy: it stages the dated archive and runs
the startup sweeps, then stops before the first engine stage. On the login node, from the
scratch clone, it exits 0 and shows the staged `bin/katago` byte-identical to `$KATAGO_BIN`,
the staged `selfplay.cfg` byte-identical to `codes/cfg/selfplay_9x9.cfg` (`dataBoardLen = 9`),
and the staged `train_9x9.sh` at `-pos-len 9`. That turns `o17` and the config half of `o13`
from grep assertions into executed facts at zero GPU cost. One archive costs 28 MB, which is
the number `data_budget` needs for `[OPEN] dated-archive-growth`; `loop.sbatch` keeps only the
newest `KTG_KEEP_ARCHIVES` (default 3). Evidence: `stage_dryrun.txt`; the dry-run BASEDIR was
deleted afterwards.

`cfg_9x9_override` landed `codes/cfg/{selfplay,gatekeeper}_9x9.cfg` and `codes/loop/train_9x9.sh`
while this node was working, on exactly the paths the loop copy references. No duplicate config
was authored, so there is no merge obligation.

## Ledger

- error ledger trial (worker, appended):
  `86d02063585027e5e342ae071886f9657715c766415a56d27b2daea43c654a66` — pass, 6/6 conjuncts.
- result / knowledge / claim-transition rows are **candidates only**, staged at
  `results/ktg/paper_1902.10565/evidence/loop_resume/candidate_rows.json` for an
  independent validator. The worker appended none of them.

## Open

- `[OPEN] o13_loop_config_paths` — config resolution and the scratch-clone requirement are
  executed; the knob derivation from measured rows/game (`derive_cycle_knobs_9x9`) is not.
- `[OPEN] o04_scratch_budget` — guard authored here, thresholds owned by `data_budget`.
- `[OPEN] scratch-budget-propagation` — `mission.json` `decisions[]` says 500 GiB;
  `o04`/`DESIGN.md` §5/`tasks/data_budget` still say 200/180 GiB. The wrapper keeps the
  old literals as overridable defaults because §2 greps for `193273528320`.
- `[OPEN] chain-runaway` — depth cap, breaker and minimum-runtime penalty are coded but
  unexecuted; `loop_failure_circuit_breaker` owns the proof.
- `[OPEN] production-knobs` — the ten-variable block defaults are expected-value
  arithmetic at ~22 rows/game, not a measurement.
- `[OPEN] executed-resume-proof` — `c07` and `c08` need `synchronous_loop_smoke` and
  `verify_preemption_resume`; this node deliberately submitted no job.

## Scope note

The work packet's framing anticipated two consecutive GPU jobs on one base directory as
this node's resume test. The task file forbids exactly that here (§13: the executed
kill/resume proof belongs to `verify_preemption_resume`, the executed breaker proof to
`loop_failure_circuit_breaker`), so no job was submitted and the compute-budget check was
run as a policy pre-flight rather than ahead of an `sbatch`.
