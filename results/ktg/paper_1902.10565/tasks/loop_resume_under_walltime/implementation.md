# Implementation — `loop_resume_under_walltime`

## 0. Header

**Task ID:** `loop_resume_under_walltime`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::loop_resume_under_walltime`
**Language:** bash / Slurm
**Method class:** refactor (mission-owned wrapper + loop copy; static verification only)

## 1. Claim

> A mission Slurm wrapper `codes/loop/loop.sbatch` plus a mission copy `codes/loop/synchronous_loop_9x9.sh` encode the run contract (1 GPU, 24 CPUs, `--time 2-23:30:00`, `b300` preferred / `b200` fallback, self-resubmit with `--dependency=afterany`) and repair the three upstream defects that make the stock loop unrunnable or lossy here — the `cpp/katago` copy path, the 19x19 configs, and the `rm`-before-`mv` export window (claims `c07_loop_cycle_completes` and the static half of `c08_resume_no_loss`; obligations `o09`, `o13`, `o17`).

## 2. Success Criterion

- **Needed evidence type:** `static_verification` (bash parse + grep over the authored files, plus the live compute-policy check)
- **Done when:** the node's closing check exits 0 with all six conjuncts satisfied.
- **Verification command:**
  `bash -n results/ktg/paper_1902.10565/codes/loop/loop.sbatch && grep -q afterany results/ktg/paper_1902.10565/codes/loop/loop.sbatch && grep -q failcount results/ktg/paper_1902.10565/codes/loop/loop.sbatch && grep -q 'cpp/build/katago' results/ktg/paper_1902.10565/codes/loop/synchronous_loop_9x9.sh && ! grep -q 'cpp/katago"' results/ktg/paper_1902.10565/codes/loop/synchronous_loop_9x9.sh && bash "$(python3 -c 'import json;print(json.load(open("mission.json"))["compute"]["policyCheck"])')" --gpus 1 --cpus 24 --partition b200`
- **Measured tolerance / metric:** exit code `== 0`; every conjunct is exact — `bash -n` clean, `afterany` count `>= 1`, `failcount` count `>= 1`, `cpp/build/katago` count `>= 1`, `cpp/katago"` count `== 0`, `check.sh` exit `0` for `gpus=1 cpus=24 part=b200`. No tolerance band: this is a parse/grep gate, not a measurement.
- **Open obligations before start:** `o09_export_kill_window`, `o13_loop_config_paths`, `o17_katago_binary_path`, `o04_scratch_budget` (the `du -sb` / `quotas.py` / 180 GiB guard is authored here but owned by `data_budget`).
- **Reduction-to-baseline test:** NA

The scratch guard that `data_budget` greps for (`du -sb`, `quotas.py`, `193273528320`) is authored inside `loop.sbatch` by this task; `data_budget` owns its thresholds and its own closing check.

## 3. Motivation

The cluster's `MaxTime` is 3 days and the loop is open-ended, so the run only survives as a chain of resubmitting jobs. Three upstream facts make the stock `python/selfplay/synchronous_loop.sh` unusable unchanged: `:81` copies `"$GITROOTDIR"/cpp/katago`, a path the CMake build never produces (the binary is at `cpp/build/katago`, `codes/env/env.sh:22`), and under `#!/bin/bash -eu` (`:1`) that `cp` kills cycle 1; `:70-71` point at the mixed-board-size `selfplay1.cfg` / `gatekeeper1.cfg`; and `python/selfplay/export_model_for_selfplay.sh` runs `rm -r "$SRC"` at `:89` **before** `mv "$TMPDST" "$TARGET"` at `:108`, so a kill inside that window destroys the checkpoint and leaves a `<NAME>.exported` directory the next run skips (`:54-56`).

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §4 trainer flags, §5 shuffler flags |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §4 rows/game arithmetic (the smoke knob sizing) |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | node `loop_resume_under_walltime`: predecessors `train_resume_semantics`, `env_build`; successors `synchronous_loop_smoke`, `loop_failure_circuit_breaker` |
| implementation_plan | `results/ktg/paper_1902.10565/decomposition/implementation_plan_bash.md` | `loop.sbatch` directive table, the 9-row change table for `synchronous_loop_9x9.sh` |
| ref | `results/ktg/paper_1902.10565/decomposition/ref.md` | v1.18.2 provenance |
| assumptions | `results/ktg/paper_1902.10565/decomposition/assumptions.md` | `a01_single_node`, `a02_gpu_cap_start_at_1`, `a03_walltime_resume`, `a04_b200_fallback` |
| claims | `results/ktg/paper_1902.10565/decomposition/claims.md` | `c07`, `c08` |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | `o09`, `o13`, `o17`, `o04` |
| result_seed | `results/ktg/paper_1902.10565/decomposition/result_seed.md` | initial status and dependencies |

**Upstream task outputs:** `tasks/env_build/implementation.md` (`[SOLID]` — `$KATAGO_BIN`, `$KTG_ROOT/env.sh`, the scratch git clone the loop must run from); `train_resume_semantics` (read-only node: `train.py:573-574,780-796,850`).
**Evidence pack:** `evidence/decomposition/audit_loop_scripts_configs.md` §A (loop cycle constants), §F (footprint growth).

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- Author files only; submit nothing. The executed proof belongs to two other nodes (§13).
- Every deviation from upstream is one row in the §10 table with an upstream `path:line`.
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference paper | `ref-paper/arxiv-1902.10565/` |
| Reference code | `ref-code/lightvector-KataGo/` |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/loop/` |
| Plot / figure output | `results/ktg/paper_1902.10565/plots/` |
| Loop notes | `results/ktg/paper_1902.10565/loop_note/` |
| Progress dir | `progress/paper_1902.10565/loop_resume_under_walltime/` |
| Git branch | `ssci` |
| `BASEDIR` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/loop` |
| Mission root (capped) | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/loop/
├── loop.sbatch                        # node loop_resume_under_walltime - Slurm wrapper: contract, self-resubmit, breaker, scratch guard
├── synchronous_loop_9x9.sh            # node loop_resume_under_walltime - mission copy of python/selfplay/synchronous_loop.sh
├── export_model_for_selfplay_9x9.sh   # node loop_resume_under_walltime - mission copy with mv-before-rm and an exporter exit-code guard
└── train_9x9.sh                       # OWNED BY cfg_9x9_override (-pos-len 9); referenced here, never authored here
```

`synchronous_loop_9x9.sh` invokes `./train_9x9.sh` and `./export_model_for_selfplay_9x9.sh` from `$DATED_ARCHIVE` (upstream copies `python/selfplay/*.sh` into it at `:78`), so both mission scripts must be copied alongside. `train_9x9.sh` is authored by `cfg_9x9_override`; this task only asserts its presence and that `MODELKIND` reaches it.

## 8. Phase Plan

### Phase 1 - `loop copy`
- **Nodes:** `loop_resume_under_walltime`
- **Files:** `synchronous_loop_9x9.sh`, `export_model_for_selfplay_9x9.sh`
- **Test:** `bash -n` clean on both; `grep -c 'cpp/build/katago'` `>= 1` and `grep -c 'cpp/katago"'` `== 0`; both `SELFPLAY_CONFIG`/`GATING_CONFIG` resolve under `codes/cfg/`; in the export copy the `mv "$TMPDST" "$TARGET"` line precedes `rm -r "$SRC"`.
- **Estimate:** `1.0` h

### Phase 2 - `wrapper`
- **Nodes:** `loop_resume_under_walltime`
- **Files:** `loop.sbatch`
- **Test:** the §2 verification command.
- **Estimate:** `1.0` h

## 9. Quick-Win Path

1. `Phase 1` — copy the two upstream scripts into `codes/loop/`, apply the §10 change table, `bash -n` both.
2. `Phase 2` — write `loop.sbatch`, run the §2 command from the repo root on a login node (no job, no GPU).
3. **Smoke check:** `bash -n` on all three files plus `check.sh --gpus 1 --cpus 24 --partition b200` exit 0.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| `--time` | `2-23:30:00` | 30 min inside the 3-day `MaxTime` (`mission.json` `compute.maxWalltime`); `a03_walltime_resume` |
| `--gres` / `--cpus-per-task` / `--mem` | `gpu:1` / `24` / `120G` | `a02_gpu_cap_start_at_1`; CPU cap 24 = 20 % of 124 (`<mission.json compute.policyCheck>:23-25`) |
| `--partition` | `b300`, fallback `b200` | `mission.json` `compute.partitions`; the wrapper picks `b300` when `sinfo` shows free GPUs there, else `b200` |
| pre-flight | `bash <mission.json compute.policyCheck> --gpus 1 --cpus 24` before **every** `sbatch` | `check.sh:8-9`; the self-resubmit runs it too and refuses to chain on non-zero |
| self-resubmit | `sbatch --dependency=afterany:$SLURM_JOB_ID $0`, issued at the top of the body | survives OOM, node failure and hard walltime kill |
| circuit breaker | `$BASEDIR/.failcount`, stop at `3` consecutive failures | reset to 0 after a cycle that exits 0; the wrapper refuses to resubmit at 3 |
| stop guard | `$BASEDIR/STOP` present -> no resubmit, exit 0 | manual kill switch, checked before the resubmit and at the top of each cycle |
| startup cleanup | `rm -rf "$BASEDIR"/shuffleddata/*.tmp` and `"$BASEDIR"/torchmodels_toexport/*.exported` | `shuffle.sh:105` renames `.tmp` at the end and `cleanup_old_dirs.py:24` never prunes `.tmp`; `.exported` markers are skipped forever at `export_model_for_selfplay.sh:54-56` |
| scratch guard (owned by `data_budget`) | `du -sb` on the mission root, hard cap `214748364800` B (200 GiB), no new cycle at `>= 193273528320` B (180 GiB), plus `python3 /apps/helpers/quotas.py` and `df -B1`; the triple is logged once per cycle | `data_budget` §2 |
| loop args | `synchronous_loop_9x9.sh ktg9 "$BASEDIR" t9 b7c96h3tfrs 1` | arg order `NAMEPREFIX BASEDIR TRAININGNAME MODELKIND USEGATING` (`synchronous_loop.sh:12-32`); `USEGATING=1` throughout |
| `MODELKIND` assertion | `[[ "$MODELKIND" == *tfrs || "$MODELKIND" == *tflrs ]]` else exit non-zero | every C++ backend refuses a non-SwiGLU transformer FFN (`cudaandrocmbackend.inc:3307-3308`); node `engine_ffn_swiglu_constraint` |
| binary copy | `cp "$KATAGO_BIN" "$DATED_ARCHIVE"/bin/katago` | upstream `:81` copies `"$GITROOTDIR"/cpp/katago`, which the CMake build never produces — `o17` |
| `SELFPLAY_CONFIG` / `GATING_CONFIG` | `codes/cfg/selfplay_9x9.cfg` / `codes/cfg/gatekeeper_9x9.cfg` | upstream `:70-71` point at the mixed-size presets — `o13` |
| train wrapper | `./train_9x9.sh` in place of `./train.sh` (`:109`) | upstream `train.sh:88` hard-codes `-pos-len 19`; the wrapper is `cfg_9x9_override`'s deliverable |
| export helper | `./export_model_for_selfplay_9x9.sh` in place of `:113` | `mv` before `rm` and a captured exporter exit code — `o09`, `o15` |
| `NUM_THREADS_FOR_SHUFFLING` | `8` | `synchronous_loop.sh:58` -> `shuffle.sh:49` `-num-processes` |
| `OMP_NUM_THREADS` / `MKL_NUM_THREADS` | `4` | exported by the wrapper before the train stage; 24-CPU cap |
| smoke knobs | `NUM_GAMES_PER_CYCLE 20`, `SHUFFLE_MINROWS 200`, `SHUFFLE_KEEPROWS 5000`, `NUM_TRAIN_SAMPLES_PER_EPOCH 2000`, `BATCHSIZE 32` | `synchronous_loop.sh:57,59,62,63,66`; consumed by `synchronous_loop_smoke` |
| production knobs | `[HYPOTHESIS]` 500 games, `MAX_TRAIN_PER_DATA 8`, 20000 samples/epoch, `SHUFFLE_MINROWS 10000`, `SHUFFLE_KEEPROWS 300000`, `MAX_TRAIN_SAMPLES_PER_CYCLE 200000`, `TAPER_WINDOW_SCALE 50000`, `-epochs-per-export 4` | pilot values at ~22 rows/game; **derived, not fixed, by `derive_cycle_knobs_9x9`** after the smoke measures rows/game |
| one candidate per cycle | `-epochs-per-export N -max-epochs-this-instance N` | `train.py:116,118`; without the pair the trainer keeps exporting inside one cycle |

Mid-cycle-kill idempotence, which is what makes the resubmit safe: completed selfplay rows persist because `trainingwrite.cpp:1093-1096` writes `<name>.npz.tmp` and renames; the shuffler writes `shuffleddata/<ts>.tmp` and renames at `shuffle.sh:105` while `train.py:1206-1210` skips `.tmp`; the trainer reloads `checkpoint.ckpt` (`train.py:573-574`, existence check `:780`, load `:796`) and takes its model config from the checkpoint (`:850`); the gatekeeper leaves the candidate in `modelstobetested/` until its own rename.

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| Chain runaway: a job dying in seconds spawns a successor immediately | many `ktg-loop` jobs in `sacct` within one minute, `.failcount` climbing | `.failcount` stop at 3 plus a minimum-runtime guard before the resubmit; `STOP` file as the manual brake. `[OPEN] chain-runaway` — closes when `loop_failure_circuit_breaker` injects failures and counts the chain |
| `-eu` aborts cycle 1 on the binary copy | `cp: cannot stat '.../cpp/katago'` in the first cycle log | `o17` change; the closing check greps both the presence of `cpp/build/katago` and the absence of `cpp/katago"` |
| Loop run from the read-only mirror | `git rev-parse --show-toplevel` (`:35`) resolves into `ref-code/`, and `git diff` (`:84-86`) writes there | the wrapper `cd`s into `$KATAGO_SRC` (the scratch clone) and asserts `$GITROOTDIR == $KATAGO_SRC` before the loop starts |
| Export kill window loses a checkpoint | a `<NAME>.exported` dir in `torchmodels_toexport/` and no matching dir under `modelstobetested/` | `mv` before `rm` in the mission copy, plus the startup `.exported` sweep |
| Orphan `shuffleddata/*.tmp` accumulate | `du` on `shuffleddata/` grows monotonically; `cleanup_old_dirs.py:24` never touches them | startup sweep in the wrapper; counted in the per-cycle `du -sb` line |
| `scripts/dated/<ts>` archive per restart | one archive per resubmit, each holding a `katago` binary | prune to the newest few in the startup sweep; counted by `data_budget` |
| Non-SwiGLU `MODELKIND` reaches the loop | `Non-SwiGLU transformer FFN is not yet supported in CUDA backend`, exit 134, after a full cycle of selfplay | the `*tfrs|*tflrs` assertion fires before the first stage |
| `b300` full, wrapper hard-codes it | job `PENDING (Resources)` for hours | partition selection reads `sinfo`; `b200` fallback is the default |

## 12. Current State

- `[SOLID]` The three upstream defects are read at `path:line` in the read-only mirror: `synchronous_loop.sh:81` (`cpp/katago`), `:70-71` (mixed-size configs), `export_model_for_selfplay.sh:89` vs `:108` (`rm` before `mv`), skip markers `:54-56`.
- `[SOLID]` Predecessor `env_build` is `solid` — job `298018`, `SMOKE RESULT: PASS`, `sm_100` ELF count 2, evidence `results/ktg/paper_1902.10565/evidence/env/smoke.txt`. `$KATAGO_BIN` and the scratch git clone the loop needs both exist.
- `[SOLID]` The resume mechanics of `train.py` are read: `:573-574`, `:780`, `:796`, `:850`, `:1206-1210`; `trainingwrite.cpp:1093-1096`; `shuffle.sh:105`.
- `[PRELIMINARY]` All three files are authored and the §2 closing check exits 0: `bash -n` clean on `loop.sbatch`, `afterany` 4, `failcount` 14, `cpp/build/katago` 5, `cpp/katago"` 0, `check.sh --gpus 1 --cpus 24 --partition b200` exit 0. Verbatim output: `evidence/loop_resume_under_walltime/verification.txt`; per-conjunct counts `conjuncts.txt`; refusal paths `guard_probes.txt`; full upstream diff `upstream_diff.txt`. Error-ledger trial `row_hash 86d02063585027e5e342ae071886f9657715c766415a56d27b2daea43c654a66`. Candidate result / knowledge / claim-transition rows are staged for an independent validator at `evidence/loop_resume/candidate_rows.json` — this worker appended none of them.
- `[SOLID]` `o17_loop_katago_bin_path` discharged, and executed rather than only grepped: the grep pair in §2 passes 5 / 0, and a `KTG_STAGE_ONLY=1` dry run (no GPU, no Slurm job, login node) staged a dated archive from the real scratch clone whose `bin/katago` is byte-identical to `$KATAGO_BIN` (`cmp` exit 0, 27 273 864 B) — `evidence/loop_resume_under_walltime/stage_dryrun.txt`.
- `[SOLID]` The same dry run settles the config half of `o13`: the staged `selfplay.cfg` is byte-identical to `codes/cfg/selfplay_9x9.cfg` with `dataBoardLen = 9` at `:28`, `gatekeeper.cfg` comes from `codes/cfg/gatekeeper_9x9.cfg`, and the staged `train_9x9.sh` is at `-pos-len 9`. `cfg_9x9_override` landed all three of those files while this node was working, so no duplicate config was authored here and there is no merge obligation. One staged archive costs 28 MB — a number `data_budget` needs for `[OPEN] dated-archive-growth`; `loop.sbatch` keeps only the newest `KTG_KEEP_ARCHIVES` (default 3).
- `[SOLID]` `o09_export_kill_window` discharged: `export_model_for_selfplay_9x9.sh:161-162` renames the temp into the target *before* removing the source (upstream does `:89` then `:108`), the startup `.exported` sweep is in `loop.sbatch` and repeated in the loop copy, and the "model already exists" branch now completes an interrupted rename instead of stranding the source. Verified by file ordering only — an executed kill still belongs to `verify_preemption_resume`.
- `[OPEN]` `o13_loop_config_paths` — two of its three conjuncts are executed (config resolution above; the read-only-mirror refusal, `guard_probes.txt` probe 3, exit 2). The third is not: the ten-variable knob block is sized from the *expected* ~22 rows/game, not a measurement, so it closes only when `derive_cycle_knobs_9x9` re-derives it.
- `[OPEN]` `chain-runaway` — the three guards are coded (`KTG_MAX_CHAIN` depth cap, `.failcount` breaker at 3 that `scancel`s the queued successor when it trips, and a minimum-runtime penalty: a failure faster than `KTG_MIN_RUNTIME_SECONDS`=600 costs two of the three attempts, so a crash loop trips on the second link). Nothing is executed — `loop_failure_circuit_breaker` owns the proof.
- `[OPEN]` `scratch-budget-propagation` (raised here, owned by `data_budget`) — `mission.json` `decisions[]` raised the scratch budget to 500 GiB (536870912000 B) on 2026-09-03, but `o04`, `DESIGN.md` §5 and `tasks/data_budget` still say 200 GiB / 180 GiB. `loop.sbatch` keeps `214748364800` / `193273528320` as its defaults because §2 greps for the literal `193273528320`, and makes both environment-overridable so `data_budget` rewrites one line.
- `[OPEN]` Production knobs stay `[HYPOTHESIS]` until `derive_cycle_knobs_9x9` derives them from measured rows/game; the loop copy reads all ten from one `${VAR:-default}` block so the derivation edits one place and `smoke_loop.sbatch` overrides them in the environment.
- `[SOLID]` Two authoring corrections, recorded because a reader of the plan would repeat them: `sbatch --dependency=afterany:$SLURM_JOB_ID $0` cannot use `$0` — inside a batch job that is the scheduler's spool copy, not the script — so the successor is submitted by absolute path (`$SELF`); and the "already exists" branch of the export copy uses `rm -rf` so the literal `rm -r "$SRC"` occurs only after the `mv`.
- `[SOLID]` Superseded history: `transformer_trunk_b5c48h3tfr` is amended out of the live DAG. The engine refusal it recorded now lives in `engine_ffn_swiglu_constraint` (`solid`), the architecture facts in `transformer_trunk_b7c96h3tfrs`, and the b7 -> b8 -> b14 progression in `select_transformer_ladder`. The wrapper's `MODELKIND` assertion is the operational form of that constraint.

## 13. Forbidden Actions

- Never submit a job from this task: it authors static files. The executed kill/resume proof — `scancel` mid-train and mid-export, then checking that the successor starts and `checkpoint.ckpt`, `shuffleddata/` and `models/` are consistent — belongs to `verify_preemption_resume`.
- Never inject a failure to exercise `.failcount` here: the breaker's executed test belongs to `loop_failure_circuit_breaker`.
- Never author `codes/loop/train_9x9.sh` in this task — it is `cfg_9x9_override`'s deliverable (`-pos-len 9`); this task only references it.
- Never edit `ref-code/lightvector-KataGo/python/selfplay/*.sh`; the mission owns copies under `codes/loop/`.
- Never leave upstream's `cp "$GITROOTDIR"/cpp/katago` in the copy, and never "fix" it by symlinking `cpp/katago` in the scratch clone — the copy path is what the closing check greps.
- Never run the loop from the read-only mirror: `:35`, `:84-86` execute `git` in whatever tree they land in.
- Never resubmit without the compute-budget check, and never raise `--gres` above `gpu:1` or `--cpus-per-task` above 24 in this wrapper (a second GPU is `[FUTURE]`, node `async_multi_gpu_layout`).
- Never set `USEGATING=0`: gating is on for every cycle, including the first (`gating_rule`).
- Never treat the scratch guard as advisory — above 180 GiB the wrapper must refuse to start a new cycle.

## 14. Promise Tag

- **Promise format:** `<promise>loop_resume_under_walltime STATIC_WRAPPER_CHECKS WITHIN ALL_PASS AND POLICY_CHECK ==0</promise>`
- **Required in commit body:** verbatim output of the §2 command (including the `check.sh` block), the three grep counts, evidence path under `evidence/loop_resume_under_walltime/`, claims `c07`/`c08`, evidence type `static_verification`.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions:
- Per-substage commit: Phase 1 (loop copy + export copy) and Phase 2 (wrapper) commit separately.
- Joint progress file: `progress/paper_1902.10565/loop_resume_under_walltime/progress.md`.
- Loop notes: `results/ktg/paper_1902.10565/loop_note/note_session_{id}_loop_{n}.md` before compaction.
- State-note sync: `o09`, `o13`, `o17` transitions and the `[OPEN] chain-runaway` marker go into `${RESEARCH_STATE}`.

## 16. Termination Checklist

- [x] Verification command ran and output is pasted (`evidence/loop_resume_under_walltime/verification.txt`, `EXIT=0`).
- [x] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations — staged as a CANDIDATE row at `evidence/loop_resume/candidate_rows.json`; an independent validator admits or refutes it. The worker appended only the error-ledger trial.
- [x] Metric is within the threshold in §2 (exit 0, all six conjuncts).
- [x] Reduction-to-baseline test passed when relevant (NA).
- [x] No `[BLOCKING]`, `[OPEN]`, or `[UNCHECKED]` markers remain for this checked claim — the candidate row is proposed as `existence_only`, not `checked`, precisely because `o13`, `o04`, `chain-runaway`, `scratch-budget-propagation` and the production knobs stay open under named successor nodes.
- [x] No silent scope expansion: three files authored, no job submitted, `train_9x9.sh` untouched.
- [x] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected (no sub-agents were spawned for this node).
