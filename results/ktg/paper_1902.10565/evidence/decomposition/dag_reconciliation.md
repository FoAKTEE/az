# DAG reconciliation — seat A (38) × seat B (39) → canonical 38-node DAG, mission `ktg-train`

Role: reformulation (pipelines/1-decompose/spec.md, Unified DAG step 3). Inputs: pass 1 (`decomposition/logic.md`, 27 ledger
nodes), pass 2 (`decomposition/logic_pass2.md`, 32 nodes, `design_pass2.md`), the two independent adjudications
`dag_review_a.md` (seat A, 38-node merge) and `dag_review_b.md` (seat B, 39-node merge), result row `env-toolchain-b200`,
`evidence/env/smoke.txt` / `smoke-297952-fail.txt`, the error-ledger trials for `env_build`. Ground truth for every anchor:
`ref-code/lightvector-KataGo` @ `fd0723fd` (v1.18.2); shortened paths resolve under it. Every anchor in the "anchor re-checked"
column was re-read with `sed -n` / `grep` in this pass before the ledger was touched; the 16 code-map/infra verification commands
below were then EXECUTED by the admission gate at append (exit 0 recorded in `verification_run`). Tags per `markers.md`; each
claim carries a `verify:` line. Rule applied throughout: identical derivations collapse to one node; pass-1 ids are kept where
the concept matches so ledger / task references stay valid; ≤ 40 nodes.

## 0. Decisions that changed the ladder (both seats agree; re-verified here)

- [SOLID] `ffng` configs are engine-unservable: every backend throws `Non-SwiGLU transformer FFN is not yet supported` at
  `TransformerFFNBlock` construction (`cpp/neuralnet/cudaandrocmbackend.inc:3307-3308`, `eigenbackend.cpp:1634`,
  `openclbackend.cpp:2729`, `metalbackend.cpp`, `onnxmodelbuilder.cpp`); the exporter writes `1 if block.use_swiglu else 0`
  (`export_model_pytorch.py:461`); `b5c48h3tfr` is the only `ffng` tf config (`modelconfigs.py:999,1886 "no swiglu"`). Observed:
  job 297952 exit 134 with exactly that string (`smoke-297952-fail.txt:26-27`). New solid node `engine_ffn_swiglu_constraint`.
  verify: `grep -l 'Non-SwiGLU transformer FFN is not yet supported' ref-code/lightvector-KataGo/cpp/neuralnet/{cudaandrocmbackend.inc,eigenbackend.cpp,openclbackend.cpp,metalbackend.cpp,onnxmodelbuilder.cpp} | wc -l` ≥ 3; `grep -c Non-SwiGLU results/ktg/paper_1902.10565/evidence/env/smoke-297952-fail.txt` = 2.
- [SOLID] Start config `b7c96h3tfrs` (7 × attnrope+ffnsg, `modelconfigs.py:1008-1029`, registered `:1887`); ladder b8c96h3tfrs
  (`:1057-1077`, `:1889`) → b14c192h6tfrs (`:1453`, `:1894`), each a fresh run because `train.py:850` takes the config from the
  checkpoint. Seat B's request to narrow the b5 claim to "serialization only" is satisfied by retiring the b5 node instead.
  verify: node `select_transformer_ladder` verification (executed at append).
- [SOLID] Empty `models/` ⇒ the gatekeeper gates the first candidate against a random-play baseline; it neither skips (pass 1, o10)
  nor requires an accepted model (pass 2): `LoadModel::findLatestModel` returns `true` unconditionally with `modelName="random"`,
  `modelFile="/dev/null"` (`loadmodel.cpp:77-93`); `setup.cpp:126` maps `/dev/null` to `debugSkipNeuralNet`; the
  `if(!foundModel)` branch at `gatekeeper.cpp:398-402` is unreachable. Seat A's reading adopted; seat B's "USEGATING=0 once"
  is harmless but unnecessary → USEGATING=1 throughout.
  verify: node `gating_rule` verification (executed at append); runtime line `Loaded accepted neural net random` in the smoke gatekeeper log (obligation o19).
- [SOLID] Gatekeeper thread count: `numGameThreads + 2 nnServer + 1 dataWrite (gatekeeper.cpp:548) + main`; pass 1's 20 gave 24 (no
  margin) → 18 (22 threads). Both seats.
  verify: `sed -n 548p ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp | grep -c 'dataWriteLoopProtected'` = 1.
- [SOLID] Process gap fixed: 0 of 27 pass-1 rows carried a `verification` object; every live node now has predecessors and either an
  executed `verification` (16 nodes) or a `runtime_metadata.closing_check` + `notes` closing check (22 nodes) — the latter are
  deliberately NOT in `verification` because the gate executes that field at append and the scripts do not exist yet.
  verify: `python3 -c "import json;rows=[json.loads(l) for l in open('results/ledgers/knowledge/paper_arxiv-1902.10565/nodes.jsonl')];L={};[L.__setitem__(r['node_id'],r) for r in rows];live=[v for v in L.values() if v['status']!='amended'];print(len(live),sum(1 for v in live if v.get('verification_run')),sum(1 for v in live if v.get('runtime_metadata',{}).get('closing_check')))"` → `38 16 22`.

## 1. Adjudication table (union of pass 1 ∪ pass 2; A / B verdicts → final)

Namespace `arxiv-1902.10565::`. Status = ledger status after this pass. "anchor re-checked" = lines re-read in this pass.

| # | node (final id) | seat A | seat B | final | reason (one line) | anchor re-checked |
|---|---|---|---|---|---|---|
| 1 | `transformer_trunk_b7c96h3tfrs` (preliminary) | keep b5 node (amend: ffng torch-only) | merge b5 → `select_transformer_ladder`; merge the b7 record too | **keep b7 as the trunk code-map node; retire b5 (amended)** | b5 and b7 share every architecture fact (attnrope, RoPE θ 100, no trunk gpool, export block kinds) → one node; b7 is the one the mission runs and the one claims a06/o07 already cite | `modelconfigs.py:1008-1029,1887`; `model_pytorch.py:3269-3284`; `export_model_pytorch.py:461` |
| 2 | `engine_ffn_swiglu_constraint` (solid) | add (missing from both passes) | `cuda_ffn_backend_compatibility` add, [OPEN] until a controlled re-run | **add as A; B's re-run becomes obligation o23 (non-blocking)** | the cause is isolated by the throw site (construction time, before any kernel) + 5 anchors + the recorded abort; a re-run is confirmatory | `cudaandrocmbackend.inc:3303-3310`; `smoke-297952-fail.txt:26-27` |
| 3 | `select_transformer_ladder` (preliminary) | add-from-pass2 (amended) | merge-into (b5 + ladder) | **add**; preds trunk b7 + engine constraint | decision node both seats want; b7 → b8 → b14 fresh runs | `modelconfigs.py:1886-1895`; `train.py:850` |
| 4 | `playout_cap_randomization` | keep | keep | keep | identical derivation in both passes | `play.cpp:1141-1143`; `selfplay1_maxsize9.cfg:60-62,115` |
| 5 | `root_explore_and_target_pruning` | keep; drop `useNoisePruning=true` | keep; drop `useNoisePruning=true` | keep, sub-item dropped | default false for `SETUP_FOR_OTHER` (selfplay); enabling is a behaviour change | `setup.cpp:576-578`; `selfplay.cpp:110`; `searchexplorehelpers.cpp:165-169` |
| 6 | `score_utility_search` | keep | keep | keep | no counterpart in pass 2; needed by selfplay + gatekeeper | `nninputs.cpp:54-57`; `selfplay1_maxsize9.cfg:157-161` |
| 7 | `loss_targets_metrics` | keep (pred trunk) | keep (pred ladder) | keep, pred = trunk b7 | q losses ≡ 0 depends on the concrete config, not the ladder | `metrics_pytorch.py:856-882` |
| 8 | `head_gpool_degeneracy_9x9` | keep | keep | keep, pred = trunk b7; arithmetic half verified at append | pool2 = −0.5·pool1, pool3 = 0.15·pool1 at 81 points is exact | `model_pytorch.py:534-540` |
| 9 | `train_optimizer_schedule` | keep (pred trunk) + 2M warm-up fact | keep, root | keep, **root** (B) + warm-up fact (A) | train.py defaults are trunk-independent | `train.py:1074-1079` |
| 10 | `selfplay_search_params` | keep; gatekeeper 20 → 18 | merge `assign_node_resources`; gatekeeper 18 | keep (amended 18; thread model incl. data-write) | both seats | `gatekeeper.cpp:548-553`; `selfplaymanager.cpp:156`; `selfplay.cpp:359-364` |
| 11 | `game_randomization_9x9` | keep | keep | keep | identical | `selfplay1_maxsize9.cfg:16,95-97` |
| 12 | `gating_rule` | keep (amend: random baseline) | keep (amend: empty-baseline behaviour) | keep, amended per §0 | both seats; pass-1 text was wrong | `loadmodel.cpp:77-93`; `setup.cpp:126`; `gatekeeper.cpp:398-402,580` |
| 13 | `train_resume_semantics` | keep | keep | keep | identical | `train.py:780,850,1884` |
| 14 | `data_format_pos_len` | keep + edge → `train_stage` | keep | keep + edge | the assert fires in training | `data_processing_pytorch.py:91`; `train.sh:88` |
| 15 | `training_window_shuffle` | keep + random-row cap | keep (pred `data_format_pos_len`) | keep + cap + keep>cap rule; root | the cap matters for the random bootstrap; the shuffler reads raw npz, no pos_len dependence to encode | `shuffle.py:1058,1077,801`; `synchronous_loop.sh:66` |
| 16 | `env_build` (solid) | keep, merge provision + build | split into env / `build_cuda_backend` / `cuda_arch_sm100_gate` | **keep merged** (A); sm_100 check is its verification | one sbatch, one result row; a three-way split would not advance work (bidirectional criterion) | `CMakeLists.txt:761`; `smoke.txt:40,159`; `toolchain-298018.txt` |
| 17 | `cfg_9x9_override` | keep, merge 4 pass-2 nodes; + pred `env_build` | keep; + pred `freeze_run_contract` | keep (A); preds 10, 11, 12, 14, 16 | the parse run needs the binary; the run contract is not a node (§2) | `selfplay1_maxsize9.cfg:16,84,95-97`; `gatekeeper1_maxsize9.cfg:18-20` |
| 18 | `tiny_model_export_smoke` | keep, merge export + load; preds ladder, env, cfg | split export / `tiny_model_load_smoke`; preds env, ladder | **keep merged**; preds env_build, ladder (B's edge set) | one job; export-vs-load failure modes are told apart by the error ledger; dropping the cfg edge lets the two READY nodes run in parallel (DESIGN §6) | `desc.cpp:1521,1542`; `benchmarknn.cpp:65-78` |
| 19 | `synchronous_loop_smoke` | keep, merge cycle + audit | split cycle / `audit_smoke_artifacts` | **keep merged**; + pred `data_budget` (B) | the audit IS the node's verification; "commands returned 0" is never admitted without it | `synchronous_loop.sh:93-116`; `train.py:1210` |
| 20 | `loop_resume_under_walltime` | split: wrapper here, executed test → `verify_preemption_resume`; absorbs `freeze_run_contract` | keep as the restart trial after smoke → audit → breaker | **A's split**: wrapper (static) precedes the smoke; the executed test follows it | resolves B's ordering concern (a working smoke precedes interruption testing) without a cycle | `export_model_for_selfplay.sh:89,108`; `synchronous_loop.sh:1-2,81` |
| 21 | `verify_preemption_resume` | add-from-pass2 | (inside 20) | add; preds 13, 19; → `selfplay_stage` | claim c08 needs an executed successor | `train.py:573-623,780-796` |
| 22 | `loop_failure_circuit_breaker` | (inside 20: `.failcount`) | add | **add** (B); preds 20, 19; → `selfplay_stage` | a failure-injection test is distinct evidence from a wrapper audit and needs no GPU | `synchronous_loop.sh:1-2` |
| 23 | `data_budget` | keep; preds 14, smoke; → `selfplay_stage` | keep; preds contract, 14; → smoke | keep; **pred 14 only**; → smoke, selfplay, scale_data_window (B ordering); calibration → node 30 | the guard must be armed before the first write; measuring bytes/row is a throughput fact | `shuffle.py:36-47`; `cleanup_old_dirs.py:22-24` |
| 24 | `derive_cycle_knobs_9x9` | add (missing from both passes) | — | **add**; preds 13, 14, 15, 19 | pass 2's knobs starve training from cycle 2; pass 1's export 4 gated candidates/cycle | `train.py:438-439,1256-1259,1433-1445`; `synchronous_loop.sh:57-66` |
| 25 | `selfplay_stage` | keep, merge seed + successor | keep, merge | keep; preds 4, 5, 6, 10, 17, 23, 24, 21, 22 | cycle-1 random net vs accepted net = two trials under one node | `selfplay.cpp:45-53`; `loadmodel.cpp:77-78` |
| 26 | `shuffle_stage` | keep, merge | keep, merge | keep; preds 25, 15, 14 | identical | `shuffle.sh:39-54,105` |
| 27 | `train_stage` | keep, merge; drop DDP; + pred 14 | keep, merge; preds + ladder, cfg, budget | keep; preds 26, 7, 3, 13, 9, 14, 17 | DDP dropped (both); budget edge is transitive via 25 | `train.py:434-443,1256-1262` |
| 28 | `export_stage` | keep, merge | keep, merge | keep; preds 27, 18 | identical | `export_model_for_selfplay.sh:77-121` |
| 29 | `gatekeeper_stage` | keep + random-baseline fact | keep + preds cfg, baseline | keep; preds 28, 12, 17 | the baseline node follows the gatekeeper (first accepted net appears after gating) | `gatekeeper.cpp:271,524-525,579-630` |
| 30 | `bootstrap_accepted_model` | add (amended precondition) | add | add; preds 12, 28, 29 | first dir in `models/` is the frozen baseline under USEGATING=1 | `gatekeeper.cpp:386-402` |
| 31 | `measure_stage_throughput` | add | add | add; preds 29, 21 | every scaling gate needs it | `benchmarknn.cpp:180-181` |
| 32 | `count_gatekeeper_acceptances` | add | add | add; preds 29, 30 | measurement ≠ statistics ≠ declaration | `gatekeeper.cpp:579-630` |
| 33 | `match_latest_against_first` | add | add | add; preds 30, 32 | 400-game fixed-budget match; `summarize_sgfs.py` for the CI | `match_example.cfg:30-36`; `python/summarize_sgfs.py` |
| 34 | `eval_improvement` | keep as declaration; + pred 9 | keep as declaration | keep; preds 32, 33, 9 | must report samples vs 2M warm-up | `train.py:1074-1079` |
| 35 | `scale_data_window` | add; preds 24, 31 | add; preds 31, 23, 15 | add; preds 24, 31, 23 | one axis at a time | `synchronous_loop.sh:57-66` |
| 36 | `scale_search_budget` | add; pred 35 | add; pred 35 | add | identical | `selfplay1_maxsize9.cfg:60-68,115` |
| 37 | `scale_up` | keep, re-target b8 → b14 | keep for fresh-run scaling | keep; preds 3, 8, 23, 34, 36, 31 | both seats | `modelconfigs.py:1057-1077,1453` |
| 38 | `async_multi_gpu_layout` (future) | add [FUTURE] | (design text: 4-GPU split deferred) | add [FUTURE]; preds 31, 37 | queue + starved GPU; needs a concurrent-state design | `docs/cluster-manual.md` §6 |

## 2. Not adopted as nodes (with reason)

| proposed | by | disposition | reason |
|---|---|---|---|
| `freeze_run_contract` | pass 2, seat B | merged into `loop_resume_under_walltime` | limits live in `mission.json` `compute` + the compute-budget check script; a standalone node would not advance work |
| `build_cuda_backend`, `cuda_arch_sm100_gate` | pass 2, seat B | merged into `env_build` | executed as one sbatch with one result row; the sm_100 count is `env_build`'s executed verification |
| `tiny_model_load_smoke` | pass 2, seat B | merged into `tiny_model_export_smoke` | one job; failure mode recorded per trial in the error ledger |
| `audit_smoke_artifacts` | pass 2, seat B | merged into `synchronous_loop_smoke` | the audit is the node's verification |
| `port_ffng_to_cuda` | seat A [FUTURE] | dropped | engine patch (design: none); b7 works; resolving it would not advance the mission (bidirectional criterion) |
| `transformer_trunk_b5c48h3tfr` | pass 1 | **retired** (`status=amended`, node_seq 3) | facts merged into nodes 1 and 2; kept as negative fixture (o23) |
| `useNoisePruning=true`, 2-GPU default + `-multi-gpus 0,1` | pass 2 | dropped sub-items | both seats |

Count: 15 code-map + 23 infra/exec = **38 live nodes** (2 solid, 14 preliminary, 21 hypothesis, 1 future) ≤ 40. [SOLID]
verify: `python3 phys-agentic-loop/_common/visualization/dag_mermaid.py progress --papers arxiv-1902.10565 | python3 -c "import json,sys;print(len(json.load(sys.stdin)))"` → `38`; `duplicates` → `[]` (§5).

## 3. Edge corrections applied (vs pass 1 `logic.md`)

- added `env_build → cfg_9x9_override`; removed `cfg_9x9_override → tiny_model_export_smoke`; `tiny_model_export_smoke` preds = `env_build`, `select_transformer_ladder`. [SOLID] verify: `logic.md` edges.
- added `data_format_pos_len → train_stage`, `cfg_9x9_override → {train_stage, gatekeeper_stage, selfplay_stage}`. [SOLID]
- `data_budget`: pred `synchronous_loop_smoke` removed; pred `data_format_pos_len` kept; successors `synchronous_loop_smoke`, `selfplay_stage`, `scale_data_window`, `scale_up`. [SOLID]
- `loop_resume_under_walltime → synchronous_loop_smoke` kept; new `synchronous_loop_smoke → {derive_cycle_knobs_9x9, verify_preemption_resume, loop_failure_circuit_breaker} → selfplay_stage`. [PRELIMINARY] verify: production waits for both executed tests (DESIGN §4).
- `transformer_trunk_b5c48h3tfr → *` edges gone (node retired); `transformer_trunk_b7c96h3tfrs → {loss_targets_metrics, head_gpool_degeneracy_9x9, select_transformer_ladder}`; `select_transformer_ladder → {tiny_model_export_smoke, train_stage, scale_up}`; `train_optimizer_schedule` is a root and feeds `train_stage`, `eval_improvement`. [SOLID]
- `gatekeeper_stage → eval_improvement` replaced by `gatekeeper_stage → count_gatekeeper_acceptances`, `bootstrap_accepted_model → match_latest_against_first`, both → `eval_improvement`. [SOLID]
- `scale_up` fan-in replaced by `measure_stage_throughput → scale_data_window → scale_search_budget → scale_up`; `measure_stage_throughput → async_multi_gpu_layout`. [SOLID]
- No cycles: the recurrent loop is a state machine; stages are admitted once and cycle behaviour lives in trials (seat B §3). verify: Mermaid render has 74 solid edges, 0 dashed (no predecessor outside scope).

## 4. Design conflicts resolved (recorded in `DESIGN.md`, revised in place)

| topic | pass 1 | pass 2 | resolution | tag / verify |
|---|---|---|---|---|
| start config | b5c48h3tfr | b5c48h3tfr | **b7c96h3tfrs**; b8 → b14 fresh runs | [SOLID] §0 |
| GPU split | 1 GPU, 24 CPUs, sequential | 2 GPUs default, 3:1 four-GPU later | **1 GPU**; multi-GPU = `async_multi_gpu_layout` [FUTURE] after measured saturation (duty > 70 %) | [PRELIMINARY] verify: `measure_stage_throughput`; queue evidence `cluster-manual.md` §6 |
| threads | 18 / 20 / 8 / OMP 4 | 16 / 12 / 8 / OMP 8 (2-GPU) | **18 / 18 / 8 / OMP 4**, prefetch 1; admitted from `ps -o nlwp` | [PRELIMINARY] verify: c06, o03 |
| cycle knobs | 500 games, reuse 8, 20k/epoch, MINROWS 10k, KEEPROWS 300k, cap 500k | 500 games, reuse 4, 50k/epoch, MINROWS 50k, cap 200k | **derived** by `derive_cycle_knobs_9x9` from measured rows/game; pilot hypothesis = pass-1 set with KEEPROWS 300k > cap 200k and `-epochs-per-export 4 -max-epochs-this-instance 4` | [PRELIMINARY] verify: o24; `train.py:1256-1259,1433-1445`; `synchronous_loop.sh:66` |
| data windows | keep 300k / cap 500k (violates keep > cap) | keep > cap; tiny smoke scale | keep > cap always; random rows capped at min_rows | [SOLID] verify: `shuffle.py:1077`, `synchronous_loop.sh:66` |
| scratch | 200 GB decimal on BASEDIR, auto-prune | 200 GiB mission root, stop at 180 GiB, no auto-delete | **200 GiB whole root, 180 GiB guard, quota check, bounded retention with a logged protected set**; bytes/row calibrated by `measure_stage_throughput` | [PRELIMINARY] verify: o04, c11, node `data_budget` |
| gatekeeper bootstrap | skipped in cycle 1 | needs an accepted model; USEGATING=0 once | **gates vs random baseline; USEGATING=1 throughout**; first dir in `models/` frozen | [SOLID] §0; o10/o16 discharged; o19 |
| evaluation | ≥ 2 acceptances; p ≥ 0.60 | ≥ 1 acceptance; CI excludes 0.5 | **≥ 1 (target 2) AND CI excludes 0.5; target p ≥ 0.60**; draws 0.5; `summarize_sgfs.py` | [PRELIMINARY] verify: c13, c14 |
| build options | none | `-DUSE_TCMALLOC=1 -DNO_GIT_REVISION=1` | executed build has neither; TCMalloc = o20 (monitor RSS, rebuild only if it grows) | [OPEN] verify: `ldd katago | grep -c tcmalloc` = 0; `sstat MaxRSS` per cycle |
| CPU policy scope | [HOLE] | — | assumption a11 (summed; one job at a time) + obligation o22 (human) | [HOLE] verify: the compute-budget check script sums `squeue -u $USER` CPUs |

## 5. Ledger application (verbatim tool output)

- knowledge `append-batch --force` (39 rows: 38 live + 1 amended; 16 `verification` executed): `{"appended": 39, "skipped": 0, "papers": ["arxiv-1902.10565"]}`; one re-append of `loop_resume_under_walltime` (policy-check path referenced via `mission.json`): `{"appended": 1, "skipped": 0, "papers": ["arxiv-1902.10565"]}`.
- claims `append-batch` (10 claims re-appended incl. c01/c02 admitted on `env-toolchain-b200`; 12 obligations: o03/o04 amended, o07/o10/o14/o16 discharged, o19–o24 new; 3 assumptions: a02/a10 amended, a11 new): `{"appended": 25, "skipped": 0, "papers": ["arxiv-1902.10565"]}`; `render-md` → `claims.md`, `obligations.md`, `assumptions.md`.
- `dag_mermaid.py duplicates` → `[]`.
- **Framework finding** [SOLID]: the spec retires collapsed nodes with `status=amended`, but `latest_per_node`, `knowledge_database.latest_status` and `admission._latest_non_amended` skipped amended rows, so the retired `transformer_trunk_b5c48h3tfr` resurfaced as `blocking` (39 nodes in the first render). Fixed in the framework submodule (`ssci`): a latest amended row retires the node; regression tests added; full suite green.
  verify: `cd phys-agentic-loop && python3 -m pytest -q tests` → 173 passed; render now 38 nodes.
- **READY frontier** (all predecessors solid/preliminary): `cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime`, `data_budget`. Task files exist for each (`../../tasks/<node>/implementation.md`); probe tasks `paper_code_map_search` / `paper_code_map_training` promote the 15 code-map nodes.
  verify: the frontier script in §6 output (predecessor statuses listed).

## 6. `dag_mermaid.py progress --papers arxiv-1902.10565` (after the fix)

```json
[
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::async_multi_gpu_layout",
    "status": "future",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::bootstrap_accepted_model",
    "status": "hypothesis",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::cfg_9x9_override",
    "status": "hypothesis",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::count_gatekeeper_acceptances",
    "status": "hypothesis",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::data_budget",
    "status": "hypothesis",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::data_format_pos_len",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::derive_cycle_knobs_9x9",
    "status": "hypothesis",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::engine_ffn_swiglu_constraint",
    "status": "solid",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::env_build",
    "status": "solid",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::eval_improvement",
    "status": "hypothesis",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::export_stage",
    "status": "hypothesis",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::game_randomization_9x9",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::gatekeeper_stage",
    "status": "hypothesis",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::gating_rule",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::head_gpool_degeneracy_9x9",
    "status": "preliminary",
    "n_knowledge": 3,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::loop_failure_circuit_breaker",
    "status": "hypothesis",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::loop_resume_under_walltime",
    "status": "hypothesis",
    "n_knowledge": 3,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::loss_targets_metrics",
    "status": "preliminary",
    "n_knowledge": 3,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::match_latest_against_first",
    "status": "hypothesis",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::measure_stage_throughput",
    "status": "hypothesis",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::playout_cap_randomization",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::root_explore_and_target_pruning",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::scale_data_window",
    "status": "hypothesis",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::scale_search_budget",
    "status": "hypothesis",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::scale_up",
    "status": "hypothesis",
    "n_knowledge": 3,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::score_utility_search",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::select_transformer_ladder",
    "status": "preliminary",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::selfplay_search_params",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::selfplay_stage",
    "status": "hypothesis",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::shuffle_stage",
    "status": "hypothesis",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::synchronous_loop_smoke",
    "status": "hypothesis",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::tiny_model_export_smoke",
    "status": "hypothesis",
    "n_knowledge": 3,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::train_optimizer_schedule",
    "status": "preliminary",
    "n_knowledge": 3,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::train_resume_semantics",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::train_stage",
    "status": "hypothesis",
    "n_knowledge": 3,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::training_window_shuffle",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::transformer_trunk_b7c96h3tfrs",
    "status": "preliminary",
    "n_knowledge": 2,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  },
  {
    "paper": "arxiv-1902.10565",
    "node_id": "arxiv-1902.10565::verify_preemption_resume",
    "status": "hypothesis",
    "n_knowledge": 1,
    "n_trials": 0,
    "pass": 0,
    "fail": 0
  }
]
```

`dag_mermaid.py duplicates` → `[]`

### READY frontier (hypothesis nodes whose predecessors are all solid/preliminary; computed from the ledger)

```
READY cfg_9x9_override <- selfplay_search_params(preliminary), game_randomization_9x9(preliminary), gating_rule(preliminary), data_format_pos_len(preliminary), env_build(solid)
READY tiny_model_export_smoke <- env_build(solid), select_transformer_ladder(preliminary)
READY loop_resume_under_walltime <- train_resume_semantics(preliminary), env_build(solid)
READY data_budget <- data_format_pos_len(preliminary)
```

## 7. Open items carried forward

- `[BLOCKING]` before P1: o01, o02, o03 (cfg bundle), o04 (scratch guard), o13, o17 (loop copy), o24 (derived knobs) — owners: the frontier / smoke workers.
- `[OPEN]` non-blocking: o05 (SDPA compile flag), o12 (requirements.txt), o19 (random-baseline gate observed), o20 (TCMalloc RSS), o21 (`-exclude-qvalues`), o22 (CPU-policy scope — human), o23 (b5 negative fixture).
- `[FUTURE]`: `async_multi_gpu_layout`, nbt family, external 9x9 reference net.
- `[HOLE]` per-job vs summed CPU policy (assumption a11 until the human answers o22).
