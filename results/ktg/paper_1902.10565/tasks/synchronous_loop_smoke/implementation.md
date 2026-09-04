# Implementation — `synchronous_loop_smoke`

## 0. Header

**Task ID:** `synchronous_loop_smoke`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::synchronous_loop_smoke` (own node). Sub-results produced in the same allocation for: `::cfg_9x9_override` (o30), the six `paper_code_map_search` nodes and seven `paper_code_map_training` nodes (their § 2 probes), `::derive_cycle_knobs_9x9` and `::measure_stage_throughput` (input measurements only — those nodes are not closed here).
**Language:** bash / Slurm (one job) + C++ engine runs + Python (PyTorch, numpy audit)
**Method class:** simulation (one executed end-to-end cycle pair, plus in-allocation probes)
**Scheduling policy (wave 2, stated once):** a `preliminary` predecessor is usable for an `empirical` / `conditional` admission of this node at `preliminary`; `solid` still requires `solid` predecessors (admission gate). Predecessor `data_budget` is `hypothesis` in the knowledge ledger (result `data-budget-guard-500gib` is `conditional`; its o28 repair is under validation) — the job is submitted now because the queue wait (~20 h) exceeds that validation; the node's own row is capped at `preliminary` and names `data_budget` as the hypothesis predecessor.

## 1. Claim

> Two consecutive cycles of the mission loop (`codes/loop/synchronous_loop_9x9.sh`: gatekeeper → selfplay → shuffle → train → export) complete on 1 B200 GPU with `b7c96h3tfrs`, `USEGATING=1` and tiny knobs; cycle 1 trains from random-net rows and exports one candidate, cycle 2 gates it against the random baseline and trains from `checkpoint.ckpt`; the artifacts are 9x9 throughout (npz spatial 81 / policy 82, `SZ[9]` only, checkpoint `pos_len 9`) — claim `c07_loop_cycle_completes`, obligation `o19`; and the same allocation yields the executed measurements owed by `o30`, `o03`, `c10`, `c05` and the two code-map probe packets.

## 2. Success Criterion

- **Needed evidence type:** `numerical_simulation` (own node); `empirical_measurement` for the throughput/thread sub-results
- **Done when:** the job exits 0 with every leg marker present and the audit's assertions all hold on the produced artifacts.
- **Verification command (node closing check, CPU-only, gate-executable on the login node):**
  `python3 results/ktg/paper_1902.10565/codes/eval/audit_smoke.py /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/smoke --evidence results/ktg/paper_1902.10565/evidence/smoke && test -s results/ktg/paper_1902.10565/evidence/smoke/rows_per_game.txt`
  The executed GPU legs are witnessed by the content-hashed job transcript `evidence/smoke/smoke-<jobid>.txt` plus `sacct`, exactly as `env-toolchain-b200` and `r_tiny_model_export_smoke_b7c96h3tfrs` were. The ledger row's `closing_check` (`smoke_one_cycle.sh && audit_smoke.py … && test -s rows_per_game.txt`) is re-appended with `bash codes/loop/smoke_one_cycle.sh` replaced by the transcript witness, so the gate never re-runs a GPU cycle at append time.
- **Measured tolerance / metric (one line per sub-result; each names what it settles):**
  | # | metric (audit key) | tolerance | settles |
  |---|---|---|---|
  | S1 | `cycles_completed` (two `KTG_ONE_CYCLE=1 -- one cycle done` lines) | `== 2` | `c07` |
  | S2 | `candidate_exported` (`modelstobetested/<n>` or `models/<n>` or `rejectedmodels/<n>` with `model.bin.gz`, created by cycle 1) and `candidate_gated` (`Candidate (won|lost) match` count in `gatekeepersgf/stdout.txt`) | `>= 1` each | `c07`, `o19` (with S3) |
  | S3 | `gate_random` = `grep -c 'Loaded accepted neural net random' gatekeepersgf/stdout.txt` | `>= 1` | `o19`; probe (d) of `paper_code_map_search` (`gating_rule`) |
  | S4 | `sz_other` over `selfplay/*/sgfs/*.sgfs` and `gatekeepersgf/*/*.sgfs` | `== 0` | `c04` re-check; probe (c) of `paper_code_map_search` |
  | S5 | raw npz `binaryInputNCHWPacked.shape[1:] == (22, 11)`, `policyTargetsNCMove.shape[2] == 82`, shuffled npz same; row bytes `== 2145` | exact | `c05` (with S6), `o02` (measurement half: no pos_len-19 row exists), assertion 3 of `paper_code_map_training` |
  | S6 | `checkpoint.ckpt` `train_state["global_step_samples"]` cycle 2 `>` cycle 1, `metrics_train.json` all terms finite, no `Initializing new model!` in the cycle-2 train log | exact | `c05`, `train_resume_semantics` half of assertion 4 |
  | S7 | `full_frac` from `probe_search_9x9.py` on the real-net probe run | `[0.20, 0.30]` | probes (a) of `paper_code_map_search` |
  | S8 | `rows_per_game_real` (pooled real-net games: probe run + cycle-2 selfplay if the accepted net was real) → `evidence/smoke/rows_per_game.txt`; `rows_per_game_random` recorded alongside | `[12, 35]` (c10 band; outside the band is a recorded finding, not a job failure) | `c10` first measurement; input of `derive_cycle_knobs_9x9` (o24) |
  | S9 | `nlwp_max` per stage from `stage_monitor.sh` on real-net processes: selfplay, gatekeeper, `train.py`, `shuffle.py` | each `<= 24` (= `SLURM_CPUS_PER_TASK`) | `o03`, `c06` (real-net clause; CUDA context present) |
  | S10 | `check_cfg_9x9` re-append: `knowledge_database.py append` of the `cfg_9x9_override` row inside the allocation, gate output `verification_run.exit_code == 0`, no `admission_flags` | exact | `o30` |
  | S11 | `trunk_gpool_count == 0`, `max|pool2 + 0.5*pool1| < 1e-5`, `max|pool3 - 0.15*pool1| < 1e-5` (`probe_train_9x9.py`) | exact / `< 1e-5` | assertions 1-2 of `paper_code_map_training` |
  | S12 | synthetic kill/resume: `global_step_samples_after > global_step_samples_at_kill`, no `Initializing new model!` (`probe_resume_9x9.sh`) | exact | assertion 4 of `paper_code_map_training` (`train_resume_semantics`) |
  | S13 | throughput record `throughput_smoke.json`: games/h and rows/h per selfplay run (random, real), train samples/s, peak VRAM (`nvidia-smi` MiB), peak RSS per stage (`ps rss`), bytes/row on disk (`du -sb tdata` / rows), GPU util samples | recorded, no threshold | inputs of `measure_stage_throughput` (`[PRELIMINARY]`: tiny counts) and `data_budget` calibration |
- **Open obligations before start:** `o30` (closed by S10), `o13` (knob conjunct → `derive_cycle_knobs_9x9`), `o02` (wiring half stays with `shuffle_stage`), `o28` repair (landed `989f337`, validation pending) and `o26`/`o31` (wrapper SIGTERM classification, `loop.sbatch` only) — none blocks a smoke that never runs under `loop.sbatch`; `o27` is discharged (`0f83f04`), so the loop copy calls `scratch_guard.sh` with the 500 GiB constants.
- **Reduction-to-baseline test:** NA

## 3. Motivation

Every wave-1 node is static or single-stage. The DAG's next 14 nodes all hang off one executed cycle (`logic.md`: `synchronous_loop_smoke → {derive_cycle_knobs_9x9, verify_preemption_resume, loop_failure_circuit_breaker} → selfplay_stage`), and 14 code-map nodes stay `preliminary` only for want of executed probes. With `free_gpus=0/128` and a ~20 h backfill estimate per 1-GPU job, one allocation must produce every candidate row the frontier can absorb.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §4 trainer flags, §5 shuffler flags, §10 substitutions |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §4 rows/game arithmetic |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | predecessors `cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime` (all `preliminary`), `data_budget` (`hypothesis`) |
| DESIGN | `results/ktg/paper_1902.10565/decomposition/DESIGN.md` | §2 (bucket arithmetic, S2 row), §4 (idempotency), §8 R10/R14 |
| claims / obligations | `decomposition/claims.md`, `obligations.md` | `c04`-`c07`, `c10`, `c15`; `o02`, `o03`, `o13`, `o19`, `o24`, `o30` |
| result_seed | `results/ktg/paper_1902.10565/decomposition/result_seed.md` | initial status |

**Upstream task outputs:** `tasks/cfg_9x9_override` (`codes/cfg/*_9x9.cfg`, `codes/loop/train_9x9.sh`, `codes/eval/check_cfg_9x9.sh`), `tasks/tiny_model_export_smoke` (`codes/eval/check_export_blocks.py`; b7 exports and loads), `tasks/loop_resume_under_walltime` (`codes/loop/{synchronous_loop_9x9.sh,export_model_for_selfplay_9x9.sh}`, `KTG_ONE_CYCLE`, `${VAR:-default}` knob block), `tasks/data_budget` (`codes/data_budget/scratch_guard.sh`), `tasks/paper_code_map_{search,training}` § 2 (probe definitions — this job executes them).

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- Run the compute-policy script named by `mission.json compute.policyCheck` with `--gpus 1 --cpus 24 --partition b200` before `sbatch`; paste its output into the commit body.
- ONE job. Nothing else is submitted for this node or for the two probe packets. If the job is killed, resubmit the same script: every leg writes `$W/markers/<leg>.done` and is skipped when present.
- The worker appends only: the error-ledger trial(s) and the S10 re-append of `cfg_9x9_override` (`CHANDRA_ROLE=worker`, inside the allocation, no `--skip-exec`). All other rows are staged in `evidence/smoke/candidate_rows.json` for the validator.
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference code | `ref-code/lightvector-KataGo/` |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/{loop,eval}/` |
| Evidence | `results/ktg/paper_1902.10565/evidence/smoke/` |
| Progress dir | `progress/paper_1902.10565/synchronous_loop_smoke/` |
| Git branch | `main` (az) |
| `BASEDIR` = `$W` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/smoke` |
| probe workdirs | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/smoke_probe/{search,train}` |
| job log | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/ktg-smoke-<jobid>.out` |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/
├── loop/smoke_loop.sbatch          # node synchronous_loop_smoke - THE job: legs A-E below, per-leg .done markers
├── loop/smoke_one_cycle.sh         # node synchronous_loop_smoke - env.sh, cd $KATAGO_SRC, smoke knobs, KTG_ONE_CYCLE=1 synchronous_loop_9x9.sh
├── eval/stage_monitor.sh           # o03 / measure_stage_throughput - ps -o nlwp,rss per stage at 0.2 s; nvidia-smi util/VRAM at 2 s
├── eval/audit_smoke.py             # node synchronous_loop_smoke - S1-S6, S8, S13 -> evidence/smoke/{audit.json,rows_per_game.txt,throughput_smoke.json}
├── eval/check_pos_len_npz.py       # o02 - asserts every tdata npz is (N,22,11)/(N,2,82); reused later by shuffle_stage as the pre-shuffle guard
├── eval/probe_search_9x9.sh/.py    # paper_code_map_search § 2 - 20 real-net games with logSearchInfo overrides -> full_frac, rows/game, sz_other
├── eval/probe_train_9x9.sh/.py     # paper_code_map_training § 2 - trunk gpool count, gpool residuals, row bytes on a REAL cycle-1 npz
└── eval/probe_resume_9x9.sh        # paper_code_map_training § 2 - synthetic 2-epoch train, SIGKILL, resume
```

## 8. Phase Plan

### Phase 1 - `job legs` (one allocation: `--gres=gpu:1 --cpus-per-task=24 --mem=64G --time=03:00:00 --partition=b200 --account=ssci-anima`, `#!/bin/bash -l`, output under `$KTG_ROOT/logs/`)
- **Leg A** (`o30`, ~1 min): `source $KTG_ROOT/env.sh`; `cd $AZ_ROOT`; `CHANDRA_ROLE=worker python3 phys-agentic-loop/_common/knowledge_database.py append --row-file evidence/smoke/cfg_9x9_reappend_row.json` — the row is the seq-3 row (`row_hash 32f53697…`) with the same `verification.command` (`check_cfg_9x9.sh && -pos-len 9 count 1 && ^numGameThreads = 18`) and notes stating the job id; the gate executes the checker inside the allocation (`SLURM_CPUS_PER_TASK=24`). Use `--force` only if the dedup skips; never `--skip-exec`.
- **Leg B** (cycle 1, 10-25 min incl. `torch.compile`): `stage_monitor.sh start`; `bash codes/loop/smoke_one_cycle.sh` (knobs § 10). Expect `selfplay/random/`, one shuffle window, one epoch, `SAVING MODEL FOR EXPORT`, `modelstobetested/<n>/model.bin.gz`.
- **Leg C** (cycle 2, 10-25 min): `smoke_one_cycle.sh` again (the loop copy re-stages an archive; fine). Gatekeeper: 200 games at 150 visits, candidate vs `random` → `Loaded accepted neural net random`, `Candidate (won|lost) match`; selfplay 40 games with the accepted net (real if accepted, random again if rejected — both are valid trials); shuffle; train resumes from `checkpoint.ckpt` (bucket gain `new_rows × 8 ≥ 0.99 × 256`); export a second candidate.
- **Leg D1** (`paper_code_map_search`, ~5 min): `probe_search_9x9.sh 20` with `-models-dir` = a dir holding a symlink to the cycle-1 candidate (`models/<n>` or `rejectedmodels/<n>`) so the probe runs a REAL net whatever the gate decided; then `probe_search_9x9.py` (S7, real-net rows/game, sz_other). Delete the `logSearchInfo` log after extraction.
- **Leg D2** (`paper_code_map_training`, 10-30 min): `probe_train_9x9.sh` → `probe_train_9x9.py` on a real `$W/selfplay/random/tdata/*.npz` (S11, row bytes) and `probe_resume_9x9.sh` in `$KTG_ROOT/runs/smoke_probe/train` (S12); `OMP_NUM_THREADS=MKL_NUM_THREADS=4`.
- **Leg E** (audit, ~1 min): `stage_monitor.sh stop`; `audit_smoke.py $W --evidence evidence/smoke`; copy the transcript to `evidence/smoke/smoke-$SLURM_JOB_ID.txt`; `sacct -j $SLURM_JOB_ID -X -n -o JobID,State,ExitCode,Elapsed,NodeList,AllocTRES%50,MaxRSS` appended after the job by the worker.
- **Test:** every S-row of § 2; job `sacct` state `COMPLETED 0:0`.
- **Estimate:** wall 0.7-1.5 h; queue ~20 h.

### Phase 2 - `candidate rows` (login node, CPU)
- **Files:** `evidence/smoke/candidate_rows.json` — one result row per settled group (`r_synchronous_loop_smoke` [c07, o19], `r_smoke_threads_realnet` [o03/c06], `r_smoke_probe_search` [c15 search half, c04, c10 → promotes 6 nodes], `r_smoke_probe_training` [c05 preconditions, c15 training half → promotes 7 nodes], `r_smoke_throughput_tiny` [inputs of o24, measure_stage_throughput]), the knowledge rows they support, and claim transitions; error-ledger trial appended by the worker.
- **Test:** each candidate row's `verification.command` is CPU-only and exits 0 on the login node.
- **Estimate:** `1.0` h

## 9. Quick-Win Path

1. Author `smoke_one_cycle.sh` + `smoke_loop.sbatch`; `bash -n` both; dry run `KTG_STAGE_ONLY=1 bash codes/loop/smoke_one_cycle.sh` on the login node (stages the archive, no engine stage).
2. `sbatch codes/loop/smoke_loop.sbatch` after the policy check; while it queues, author the probes and `audit_smoke.py` against `evidence/cfg_9x9` artifacts (the archived job-298359 sgfs/npz) for a CPU dry run.
3. **Smoke check:** `grep -c 'one cycle done' $W/logs/*.txt` `== 2` and `ls $W/*/*/model.bin.gz` non-empty.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| `NUM_GAMES_PER_CYCLE` | `40` | 36 random-net games took 6 s in job 298359; at the c10 lower bound 12 rows/game this still yields 480 rows ≥ `samples_per_epoch` (see next rows). DESIGN §2 S2 said 20 — revised here, see § 12 |
| `NUM_TRAIN_SAMPLES_PER_EPOCH` | `256` | `train.py:1303-1346`: `get_files_for_subepoch` returns `None` (→ `-quit-if-no-data` exits 0, **no export**) unless the shuffled files hold `≥ round(samples_per_epoch/batch)` batches; 256 = 8 batches of 32 ≤ 480/32 = 15. DESIGN's 2000 would have produced no candidate |
| `BATCHSIZE` | `32` | S2 row; probe-scale |
| `MAX_TRAIN_PER_DATA` | `8` | `synchronous_loop.sh:60`; cycle-2 gain 480×8 = 3840 ≥ 0.99×256 (`train.py:1434`) |
| `MAX_TRAIN_SAMPLES_PER_CYCLE` / `SHUFFLE_KEEPROWS` | `4000` / `5000` | keep > cap (`synchronous_loop.sh:66` rule); cap = `max(4000, 256)` (`train.py:1257`) |
| `SHUFFLE_MINROWS` / `TAPER_WINDOW_SCALE` | `200` / `200` | reachable at 5 rows/game; random rows counted toward the window only up to `min_rows` (`shuffle.py:1077`), but `range[1]` = all rows (`:1331`) feeds the bucket |
| `NUM_TRAIN_SAMPLES_PER_SWA` | `128` | `= samples_per_epoch/2`, the `train.py:441` default made explicit |
| `EPOCHS_PER_EXPORT` | `1` | one epoch per cycle at this scale → one candidate (`train.py:1831`); production value is `derive_cycle_knobs_9x9`'s |
| cycle 1 bucket | `= samples_per_epoch` | `train.py:971-972` — a fresh run always trains one epoch |
| `KTG_ONE_CYCLE` | `1`, invoked twice | `synchronous_loop_9x9.sh` CHANGE 8 |
| `--cpus-per-task` / `--mem` / `--time` | `24` / `64G` / `03:00:00` | 22 threads + 2 (DESIGN §1); 64G sufficed for job 298359 and 298358; short `--time` = earlier backfill (`docs/cluster-manual.md` §6) |
| chaining | none | `loop.sbatch` queues an `afterany` successor at its top and would re-run a cycle 20 h later; a ≤ 3 h job needs no chain. Resumability = per-leg `.done` markers + manual resubmit |
| probe overrides (D1) | `logSearchInfo=true,logGamesEvery=1,reduceVisits=false,normalAsymmetricPlayoutProb=0.0,handicapAsymmetricPlayoutProb=0.0,estimateLeadProb=0.0` | `tasks/paper_code_map_search` § 2; measured keys (`cheapSearchProb`, `cheapSearchVisits`, `maxVisits`, `rootDesiredPerChildVisitsCoeff`) untouched |
| probe_resume (D2) | `-pos-len 9 -model-kind b7c96h3tfrs -batch-size 32 -samples-per-epoch 2048` on synthetic npz, `SIGKILL` after epoch 2 | `tasks/paper_code_map_training` § 2 assertion 4 |
| monitor | `ps -o pid=,nlwp=,rss=,args=` every 0.2 s over `katago selfplay|katago gatekeeper|train.py|shuffle.py`; `nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader -l 2` | per-stage max nlwp / max rss / stage wall time; peak VRAM |
| thread expectation | selfplay 22, gatekeeper 22 (random side still gets an NN server thread, `nneval.cpp:433-441`), train ≤ 24 with OMP 4, shuffle 8 procs | DESIGN §1 table; measured, never asserted |

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| training quits before export | `Not enough data files to fill a subepoch! Quitting.` in `train/t9/stdout.txt`, no `SAVING MODEL FOR EXPORT` | knobs above (256 ≤ rows); if rows/game < 7 (random games pathologically short), the leg records the failure row and re-runs cycle 1 once with `NUM_GAMES_PER_CYCLE=120` |
| `torch.compile` stall (R10) | minutes at 100 % CPU, no GPU util at epoch start | expected; budget 15 min per train start; `-no-compile` only if > 15 min, recorded |
| candidate rejected in cycle 2 | `Candidate lost match`, `rejectedmodels/<n>` | not a failure (c13 belongs to `gatekeeper_stage`); D1 symlinks the rejected net for the real-net probe; cycle-2 selfplay is then a second random-net trial |
| attention-logit export refusal (R3, o15) | export exit ≠ 0, bound > 2.5e4 | leave as failure row for `export_stage`; do not add `-ignore-attn-logit-bound` |
| `scratch_guard.sh` refuses (group free < 1 TiB at 94 % usage) | `scratch_guard exit 2`, loop exit 3 | deliberate stop; record, escalate — never bypass the guard |
| real-net selfplay thread count differs from the random-net 22 | `nlwp_max` 23-24 (CUDA runtime threads) | still ≤ 24 passes; > 24 is a finding that reopens `--cpus-per-task` (DESIGN §1 `[OPEN]`), not something to hide |
| `logSearchInfo` log floods scratch | multi-GB `$W_probe/logs` | 20 games; delete after extraction |
| 20-game probe too noisy for `full_frac` | outside `[0.20, 0.30]` with < 500 searched turns | print searched-turn count; re-run D1 with 60 games inside the same job if < 500 |
| job killed mid-leg | partial `$W` | per-leg `.done` markers; resubmit; cycle re-run adds games (ratios unaffected) — recorded in the audit as `resumed_from_leg` |
| in-allocation ledger append fails (git or lock) | non-zero from `knowledge_database.py` | retry once after 10 s; if still failing, stage the row and leave `o30` open with the transcript as evidence — never `--skip-exec` |

## 12. Current State

- `[SOLID]` Predecessor artifacts exist and are admitted: `cfg-9x9-override` (empirical), `r_tiny_model_export_smoke_b7c96h3tfrs` (empirical), `r_loop_resume_under_walltime_static` (existence_only), `data-budget-guard-500gib` (conditional); the loop copy calls `scratch_guard.sh` and honours `KTG_ONE_CYCLE`/knob overrides (`codes/loop/synchronous_loop_9x9.sh:107-121,256-261`).
- `[SOLID]` The DESIGN §2 S2 knob set (20 games, 2000 samples/epoch) cannot export a candidate: `train.py:1303-1346` needs ≥ 63 batches of 32 in the shuffled files, i.e. ≥ 2016 rows, from ~440. Fixed here to 40 games / 256 samples; DESIGN §2 S2 and the node summary are updated by the worker's candidate knowledge row and an in-place DESIGN edit citing this file.
- `[PRELIMINARY]` Expected rows/game ≈ 22 (random-net games may differ); expected `full_frac` 0.25; expected threads 22/22.
- `[OPEN]` `o30` — closes at leg A. `o03`/`c06` real-net clause — S9. `o19` — S3. `c07` — S1/S2 (wording "models/<name>" holds only on acceptance; validator may narrow). `c10`, `c05` — S8, S5/S6. `o02` wiring half (a pre-shuffle call of `check_pos_len_npz.py` in the loop copy) — `shuffle_stage`, after the o26/o31 wrapper repair lands, to avoid concurrent edits under `codes/loop/`.
- `[OPEN]` `o29` — the cycle-2 gatekeeper and leg D1 run the exported b7 under `codes/cfg/selfplay_9x9.cfg` / `gatekeeper_9x9.cfg`; the validator decides whether that settles c03's mission-cfg conjunct or amends its tool wording.
- `[OPEN]` gatekeeper with two REAL nets (2 nnServer threads for two CUDA nets) is not measured here — first at `gatekeeper_stage` cycle 3+.
- `[FUTURE]` throughput at production knobs — `measure_stage_throughput`; S13 numbers are tiny-count inputs only.

## 13. Forbidden Actions

- Never submit more than this one job for this node or for the two probe packets; never request > 1 GPU or a partition other than `b200`/`b300`.
- Never run the smoke under `loop.sbatch` (its `afterany` successor would run a further cycle after a 20 h wait) and never `touch STOP` to defeat it — use `smoke_loop.sbatch`.
- Never set `USEGATING=0`, never edit `ref-code/`, never change `cheapSearchProb`/`cheapSearchVisits`/`maxVisits`/`rootDesiredPerChildVisitsCoeff`, never raise `numGameThreads` above 18 or `--cpus-per-task` above 24 without raising both together after a measurement.
- Never append the knowledge row for `cfg_9x9_override` with `--skip-exec`; never promote a code-map node to `solid` from anything but this job's logs/npz.
- Never edit `codes/loop/synchronous_loop_9x9.sh` or `loop.sbatch` in this task (o26/o31 wrapper repair is open under `loop_resume_under_walltime`); knobs go through the environment.
- Never keep the `logSearchInfo=true` log; never write anything outside `$KTG_ROOT/runs/smoke*` and `evidence/smoke/`.
- Never report c13 (acceptance) from this job; one gate on a 256-sample net is not evidence of improvement.

## 14. Promise Tag

- **Promise format:** `<promise>synchronous_loop_smoke CYCLES ==2 AND CANDIDATE_GATED >=1 AND GATE_RANDOM >=1 AND SZ_OTHER ==0 AND ROW_BYTES ==2145 AND NLWP_MAX <=24 AND FULL_FRAC WITHIN 0.25+-0.05</promise>`
- **Required in commit body:** verbatim `audit_smoke.py` output, `rows_per_game.txt`, per-stage `nlwp_max`, the leg-A gate output (`appended: true`, no `admission_flags`), `sacct` line, evidence paths under `evidence/smoke/`, claims and obligations touched, evidence types.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions: one commit for the authored scripts (`feat(smoke,ktg)`), one for the run (`exp(smoke,ktg)`), one per validated group later; joint progress file `progress/paper_1902.10565/synchronous_loop_smoke/progress.md`; `${RESEARCH_STATE}` gets every S-row outcome and each `[OPEN]` above.

## 16. Termination Checklist

- [ ] Verification command ran and output is pasted.
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] Every S-row of § 2 is within tolerance or recorded as a finding with its own error-ledger row.
- [ ] Leg A's re-append shows `verification_run.exit_code 0` and no `admission_flags`.
- [ ] No silent scope expansion: one job, the legs above, nothing else submitted.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
