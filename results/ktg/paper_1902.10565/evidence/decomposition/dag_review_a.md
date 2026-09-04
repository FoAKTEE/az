# DAG review A — adjudication of pass 1 (26 nodes) vs pass 2 (32 nodes), mission `ktg-train`

Seat: review A (brain role). Inputs: `decomposition/logic.md` + `DESIGN.md` + `claims.md`/`obligations.md`/`assumptions.md` +
`results/ledgers/knowledge/paper_arxiv-1902.10565/nodes.jsonl` (pass 1); `decomposition/logic_pass2.md` + `design_pass2.md` (pass 2);
`evidence/decomposition/audit_*.md`; `results/ktg/GLOBAL_DAG.md`; the two env_build logs and `evidence/env/smoke-{297952,298018}.txt`;
result-ledger row `env-toolchain-b200`; error-ledger trial for `env_build` (2026-09-04T02:00:27Z).
Ground truth for every anchor: `ref-code/lightvector-KataGo` @ `fd0723fd` (`v1.18.2`, `cpp/main.cpp:245`); shortened paths resolve under it.
Every anchor below was re-read with `sed -n`/`grep` in this seat; `[OPEN]` marks the ones I could not confirm. Nothing was executed on a GPU
by this seat; no ledger was touched.

Tags: `[SOLID]` read in code at path:line or measured in a recorded run · `[PRELIMINARY]` code-read but not executed, or one run only ·
`[HOLE]` gap that blocks a node · `[FUTURE]` deferred deliberately. Verdicts: keep · merge-into · add-from-pass2 · drop · split.

## 0. Execution fact that changes the ladder (fold-in first)

- [SOLID] `b5c48h3tfr` cannot be loaded by any C++ GPU/CPU backend. `TransformerFFNBlock` constructors throw
  `"Non-SwiGLU transformer FFN is not yet supported in <backend> backend"` when `useSwiGLU == 0`: CUDA/ROCm
  `cpp/neuralnet/cudaandrocmbackend.inc:3307-3309`, Eigen `eigenbackend.cpp:1633-1634`, OpenCL `openclbackend.cpp:2728-2729`,
  Metal `metalbackend.cpp:270-271`, ONNX/TensorRT builder `onnxmodelbuilder.cpp:704-705,719-720`. The exporter writes the flag as
  `1 if block.use_swiglu else 0` (`python/export_model_pytorch.py:461`); `ffng` builds the block with `use_swiglu=False`
  (`python/katago/train/model_pytorch.py:3278-3284`), `ffnsg` with `True` (`:3269-3276`).
  Observed: gtp log `runtime/smoke/gtp_logs/20260903-215545-0ED5F752.log` → `ERROR: NN server thread failed: Non-SwiGLU transformer FFN is not
  yet supported in CUDA backend`, exit 134 for both `benchmark` and `gtp` in job 297952; job 298018 with `b7c96h3tfrs` passed
  (`benchmark` 2322.17 visits/s at 1 thread, 9x9; `gtp` `= H7`; torch fwd/bwd 825,837 params).
  verify: `grep -n "Non-SwiGLU" ref-code/lightvector-KataGo/cpp/neuralnet/{cudaandrocmbackend.inc,eigenbackend.cpp,openclbackend.cpp,metalbackend.cpp,onnxmodelbuilder.cpp}` (5 files hit) and `grep -c "Non-SwiGLU" /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/gtp_logs/20260903-215545-0ED5F752.log` (≥1).
- [SOLID] The two runs differed in TWO variables (sm_100 patch AND model), so the pass/fail pair alone does not isolate the cause; the
  cause is isolated by the error string above (thrown at net construction, before any kernel launch). Run 297952 had no `stage 2b` and no
  `sm_100` check; run 298018 had both and `cuobjdump --list-elf | grep -c sm_100 = 2`.
  verify: `grep -c "stage 2b" $KTG/logs/env_build-297952.log` = 0; `grep -n "grep -c sm_100 = 2" $KTG/evidence/env/smoke-298018.txt`.
- [SOLID] `b5c48h3tfr` is the ONLY `ffng` entry in the registered tf family; the smallest engine-loadable tf config is `b7c96h3tfrs`
  (7×(attnrope, ffnsg), 96 ch, 3 heads, ffn 256; `modelconfigs.py:1008-1028`, registration `:1886-1891`). Next: `b8c96h3tfrs` (`:1057-1077`),
  `b14c192h6tfrs`/`tflrs` (`:1894-1895`). The nbt family (`b5c192h3nbttfrs`, `:1890`) is a separate `[FUTURE]` branch.
  verify: `grep -n '"ffng"\|"ffnsg"' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py | awk -F: '$1<1080'`.
- Consequence for the ladder: every node that names `b5c48h3tfr` as smoke/start config (pass 1: `tiny_model_export_smoke`, `train_stage`,
  `synchronous_loop_smoke`, DESIGN §0/§2; pass 2: `select_transformer_ladder`, `export_tiny_transformer_smoke`, `run_tiny_synchronous_cycle`,
  `train_first_network`, design_pass2 §3/§4) is re-targeted to `b7c96h3tfrs`. `b5c48h3tfr` survives only as a torch-side code-map record and
  as the `[FUTURE]` "port ffng to CUDA" option (§2). Error-ledger note: the trial row calls `ffng` a "gpool FFN"; it is the non-gated FFN using
  the model activation (`model_pytorch.py:2530`), not a pooling block — amend the wording when the row is next touched. [PRELIMINARY]
  verify: `sed -n 2526,2531p ref-code/lightvector-KataGo/python/katago/train/model_pytorch.py`.

## 1. Node-by-node adjudication (union of both passes)

Pass-1 ids are bare names under namespace `arxiv-1902.10565::`; pass-2 ids likewise. "Anchor" = the line(s) I re-read for the verdict.

| canonical id (keep) | pass-2 id(s) mapped | verdict | reason (one line) | anchor re-verified |
|---|---|---|---|---|
| `transformer_trunk_b5c48h3tfr` | `select_transformer_ladder` (code-map half) | keep (amend) | Facts about attnrope/ffng/RoPE/no-trunk-gpool stay valid; amend summary: `ffng` is torch-only (§0). | `modelconfigs.py:986-1006`; `model_pytorch.py:2079-2130,3231-3239,3278-3284` |
| `playout_cap_randomization` | `freeze_search_and_auxiliary_targets` (PCR part) | keep | Identical derivation: cheap search 0.75/100, target weight 0, maxVisits 600. | `play.cpp:1132-1150`; `selfplay1_maxsize9.cfg:60-62,115` |
| `root_explore_and_target_pruning` | `freeze_search_and_auxiliary_targets` (forced playouts + pruning part) | keep | Same mechanism (`rootDesiredPerChildVisitsCoeff=2`, 1e20 return). Pass 2's `useNoisePruning=true` item is DROPPED — it is a behaviour change, not an explicit default: selfplay loads `SETUP_FOR_OTHER` where the default is false. | `searchexplorehelpers.cpp:165-169`; `setup.cpp:576-578`; `selfplay.cpp:110,172`; `selfplay1_maxsize9.cfg:148` |
| `score_utility_search` | — | keep | Pass 2 has no counterpart; still needed for the search-side code map. | `nninputs.cpp:40,56` (`atan(adjustedScore/(scale*sqrtBoardArea))*twoOverPi`); `selfplay1_maxsize9.cfg:158-161` |
| `loss_targets_metrics` | `freeze_search_and_auxiliary_targets` (aux-loss part) | keep | Loss assembly and flag multipliers identical in both passes. | `metrics_pytorch.py:856-882,603-607`; `train.py:140-152` |
| `head_gpool_degeneracy_9x9` | — | keep | Value-head pool2 = −0.5·pool1, pool3 = +0.15·pool1 at 81 points; still a `[PRELIMINARY]` probe target. | `model_pytorch.py:534-540,3157-3160` |
| `train_optimizer_schedule` | (design_pass2 §6 warm-up remark) | keep (amend) | Add pass 2's fact: warm-up reaches 1.0 only at 2M samples; AdamW/Muon LR scales √(batch/256). | `train.py:1059-1079,1139-1141,942` |
| `selfplay_search_params` | `assign_node_resources` (thread half) | keep (amend) | Thread model confirmed; pass-1 gatekeeper count (20+2+1=23) omits the data-write thread → 24, at cap. Set gatekeeper `numGameThreads=18`. | `selfplay.cpp:359-364`; `gatekeeper.cpp:548-553`; `selfplaymanager.cpp:156`; `setup.cpp:193-203` |
| `game_randomization_9x9` | `author_9x9_selfplay_config` (key list) | keep | bSizes/bSizeRelProbs/allowRectangleProb/dataBoardLen facts identical. | `selfplay1_maxsize9.cfg:16,95-97`; `playutils.cpp:10-22,42`; `searchhelpers.cpp:541-545` |
| `gating_rule` | `gate_candidate` (rule half) | keep (amend) | BOTH passes misread the empty-`models/` case: `findLatestModel` returns `true` unconditionally with `modelFile="/dev/null"`, so the gatekeeper does NOT skip (pass 1 o10) and does NOT require an accepted model (pass 2) — it loads a random-play baseline (`debugSkipNeuralNet` default) and gates the first candidate against it. | `loadmodel.cpp:58-93` (`return true;` at :93); `gatekeeper.cpp:386-402`; `setup.cpp:126-130`; ties `gatekeeper.cpp:579` |
| `train_resume_semantics` | `resume_transformer_training` (semantics half) | keep | Atomic `os.replace`, 4 short-term ckpts, config from checkpoint, 12 h long-term. | `train.py:573-623,779-796,850,1884-1889`; `:1206-1213` |
| `data_format_pos_len` | `author_9x9_train_wrapper` (assert half) | keep | 2145 B/row at L=9; `data_processing_pytorch.py:91` is the loud assert; `train.sh:88` hard-codes 19. | `data_processing_pytorch.py:91`; `train.sh:88`; `shuffle.py:36-41` |
| `training_window_shuffle` | `shuffle_rolling_window` (formula half) | keep (amend) | Add: random-play rows are capped at `min_rows` inside shuffle (`num_random_rows_capped`), which neither pass states; matters for the random bootstrap. | `shuffle.py:414-435,1058-1077`; `shuffle.sh:44-45` |
| `env_build` | `provision_cuda_environment`, `build_cuda_backend` | keep (merge both) | Executed as one sbatch; result row `env-toolchain-b200` (empirical). Adds: cuDNN 9.19 wheel, `-DCUDNN_LIBRARY` explicit (CMake hints `lib64`, wheel ships `lib`), CUTLASS fused FFN on, sm_100 patch. `[OPEN]` no `USE_TCMALLOC` (Compiling.md recommends it for selfplay). | `CMakeLists.txt:761,1124-1128,733-741`; `cudabackend.cpp:13`; `codes/env/env_build.sbatch` cmake block; `Compiling.md:38` |
| `cfg_9x9_override` | `author_9x9_selfplay_config`, `author_9x9_gatekeeper_config`, `author_9x9_train_wrapper`, `assign_node_resources` (thread keys) | keep (merge four) | One authoring node, three files + thread keys; adopt pass 2's per-file assertions as the verification. | `selfplay1_maxsize9.cfg:16,84,95-97`; `gatekeeper1_maxsize9.cfg:18-20,38-40,49-50`; `train.sh:83-93` |
| `tiny_model_export_smoke` | `export_tiny_transformer_smoke`, `load_tiny_transformer_smoke` | keep (merge two, re-target b7c96h3tfrs) | Export+engine-load is one gate; already exercised for b7 by env_build (benchmark/gtp) but not the `benchmarknn -require-exact-nnlen -boardsize 9 -json` form nor the block-kind scan. | `export_model_pytorch.py:34-43,57-60,78-87,461,491-494`; `desc.cpp:1521-1557`; `benchmarknn.cpp:48-92` |
| `synchronous_loop_smoke` | `run_tiny_synchronous_cycle`, `audit_smoke_artifacts` | keep (merge two) | Same one-cycle disposable run; pass 2's audit assertions (81/82 lengths, `pos_len=9`, only `SZ[9]`) become its verification. | `synchronous_loop.sh:1-2,35,73-89,93-115`; `train.py:1210` |
| `loop_resume_under_walltime` | `freeze_run_contract`, `verify_preemption_resume` | split | Pass 1 conflates "wrapper exists" with "resume proven". Keep this id for the Slurm wrapper (absorbs `freeze_run_contract`: ≤4 GPU/≤24 CPU/≤72 h/b300→b200, `.failcount` stop); add `verify_preemption_resume` as the executed test. | `cluster-manual.md` §3 (MaxTime 3-00:00:00), §6; `check.sh` policy block; `SelfplayTraining.md:80` |
| `selfplay_stage` | `generate_seed_selfplay`, `generate_successor_selfplay` | keep (merge two) | Same CLI both cycles; cycle 1 with empty `models/` plays the random net into `selfplay/random/` — a sub-criterion, not a node. | `synchronous_loop.sh:99`; `loadmodel.cpp:78-80`; `SelfplayTraining.md:47`; `selfplay.cpp:51-53` |
| `shuffle_stage` | `shuffle_seed_window`, `shuffle_rolling_window` | keep (merge two) | Same wrapper and flags; window growth is the cycle count, not a new node. `-exclude-qvalues` (pass 2) adopted as `[OPEN]` sub-check. | `shuffle.sh:39-54,105`; `shuffle.py:800-801,1330-1335` |
| `train_stage` | `train_first_network`, `resume_transformer_training` | keep (merge two; drop DDP) | Same `train9.sh` invocation; pass 2's `-multi-gpus 0,1` bf16 DDP on a 0.8 M-param net is dropped (§4.1). Adopt `-max-epochs-this-instance`/`-epochs-per-export` from pass 2. | `synchronous_loop.sh:109`; `train.py:434-443,1256-1262,1433-1445,1827-1862` |
| `export_stage` | `export_first_network`, `export_swa_candidate` | keep (merge two) | `USEGATING` only selects the target dir; rm-before-mv window and attn-logit refusal (o09/o15) stay here. | `export_model_for_selfplay.sh:77-90,108,115-121`; `export_model_pytorch.py:42-43` |
| `gatekeeper_stage` | `gate_candidate` | keep (merge) | Same CLI; amend with the random-baseline fact from `gating_rule`. | `synchronous_loop.sh:96`; `gatekeeper.cpp:271,524-525,579-630` |
| `eval_improvement` | `count_gatekeeper_acceptances`, `match_latest_against_first`, `declare_selfplay_improvement` | split | Counting acceptances, the 400-game match, and the declaration are three different evidence types (measurement / statistical inference / synthesis). Keep this id as the declaration; add the two pass-2 nodes. | `match_example.cfg:33-36,52-56,88-90,107-111`; `README.txt:71-73`; `python/summarize_sgfs.py` exists |
| `data_budget` | `enforce_storage_budget` | keep (merge) | Same 200 GiB cap; adopt pass 2's 180 GiB pre-cycle guard + `du -sb`/`df -B1` logging; keep pass 1's measured-bytes calibration and group-quota check (`quotas.py`). | `shuffle.py:36-47,459-480`; `cleanup_old_dirs.py:13,24`; `check.sh` quota block |
| `scale_up` | `scale_transformer_family` | keep (amend) | With b7 as the start, this node's content becomes b8c96h3tfrs → b14c192h6tfrs (fresh runs, never checkpoint-resume across configs). | `modelconfigs.py:1057-1077,1894-1895`; `train.py:850` (config from checkpoint) |
| — | `select_transformer_ladder` | add-from-pass2 (amended) | Decision node the DAG needs; ladder starts at b7c96h3tfrs, b5 marked torch-only. | §0 anchors |
| — | `bootstrap_accepted_model` | add-from-pass2 (amended) | Freezing the first accepted net (name + SHA-256) is required by the match; its precondition is corrected: the first candidate IS gated (vs random) when `USEGATING=1`, so `USEGATING=0` for the first export is optional, not required. | `gatekeeper.cpp:386-402`; `loadmodel.cpp:93`; `export_model_for_selfplay.sh:115-121` |
| — | `verify_preemption_resume` | add-from-pass2 | Executed kill/resume test (pass 1 claim c08 had no node of its own). | `train.py:573-623`; `export_model_for_selfplay.sh:54-56,89,108` |
| — | `measure_stage_throughput` | add-from-pass2 | Pass 1 scales without a measurement node; every scaling gate below needs games/h, samples/s, GPU duty, bytes/row. | `SelfplayTraining.md:29-32`; `benchmarknn.cpp:180-181` (JSON fields) |
| — | `count_gatekeeper_acceptances` | add-from-pass2 | Directory count reconciled with `Candidate won match` log lines. | `gatekeeper.cpp:579-630` |
| — | `match_latest_against_first` | add-from-pass2 | 400-game fixed-budget match, 9x9 only; use `summarize_sgfs.py` for Elo/CI rather than a hand formula. | `match_example.cfg:52-56,88-90,107-111`; `match.cpp:141-144,224` |
| — | `scale_data_window` | add-from-pass2 | One axis at a time; gated on reuse ≤ cap, kept rows > train cap, disk guard. | `synchronous_loop.sh:57-66`; `train.py:1256-1262` |
| — | `scale_search_budget` | add-from-pass2 | 128/32 → 300/64 → 600/100 pilot visits; coefficients fixed. | `selfplay1_maxsize9.cfg:60-68,115` |
| — | `freeze_run_contract` | merge-into `loop_resume_under_walltime` | Limits live in the wrapper + `check.sh`; a standalone node would not advance work (bidirectional criterion). | `check.sh` CPU_CAP/GPU_CAP block; `mission.json` compute block |
| — | `freeze_search_and_auxiliary_targets` | merge-into three code-map nodes | See rows above; the `useNoisePruning=true` sub-item is dropped. | `setup.cpp:578` |
| — | `assign_node_resources` | merge-into `cfg_9x9_override` (threads) + `async_multi_gpu_layout` `[FUTURE]` (4-GPU 3:1 split) | Thread keys are config keys; the 4-GPU asynchronous layout is deferred (§4.1). | `cluster-manual.md` §6 queue-wait paragraph |

Counts: pass 1 — 24 keep (10 with amendments), 2 split, 0 drop. Pass 2 — 8 add-from-pass2, 24 merge-into, 0 whole-node drops; 2 sub-items dropped (`useNoisePruning=true`; 2-GPU DDP default), 1 sub-item corrected in both passes (empty-`models/` gating). New nodes from this review: 4 (§2). Merged total: 38.

## 2. Missing nodes (in neither pass)

Note: "measure throughput", "latest-vs-first match", "preemption/resume test", "storage guard" from the brief ARE present in pass 2
(`measure_stage_throughput`, `match_latest_against_first`, `verify_preemption_resume`, `enforce_storage_budget`) and are adopted above.
Genuinely absent from both:

1. `engine_ffn_swiglu_constraint` — [SOLID] code-map node: every engine backend requires `useSwiGLU=1`; `ffng` configs are torch-only.
   Predecessors: `transformer_trunk_b5c48h3tfr`. Evidence type: numerical simulation (observed abort) + literature grounding (5 anchors).
   verify: `grep -q "Non-SwiGLU transformer FFN is not yet supported" ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc && grep -q "Non-SwiGLU" /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/gtp_logs/20260903-215545-0ED5F752.log`.
2. `derive_cycle_knobs_9x9` — [HOLE] neither pass derives the loop knobs from measured rows/game; pass 2's pilot set is internally
   inconsistent (§4.4) and pass 1's set is asserted, not derived. Inputs: measured rows/game (smoke), `MAX_TRAIN_PER_DATA`,
   `NUM_TRAIN_SAMPLES_PER_EPOCH`, `-epochs-per-export`, `SHUFFLE_MINROWS`, `SHUFFLE_KEEPROWS` ≥ `MAX_TRAIN_SAMPLES_PER_CYCLE`.
   Predecessors: `synchronous_loop_smoke`, `training_window_shuffle`, `train_resume_semantics`, `data_format_pos_len`.
   Rule to encode: `NUM_GAMES_PER_CYCLE × rows_per_game × MAX_TRAIN_PER_DATA ≥ 0.99 × NUM_TRAIN_SAMPLES_PER_EPOCH` (else `train.py:1433-1445`
   exits with zero epochs after cycle 1) and `epochs_per_export = floor(bucket / samples_per_epoch)` so one candidate per cycle.
   verify: `python3 codes/eval/derive_knobs.py --rows-per-game <measured> --reuse 8 --samples-per-epoch <N>` prints a knob set and exits 0 iff the inequality holds (script to be written by the worker; the inequality is the acceptance test).
3. `port_ffng_to_cuda` — [FUTURE] implement the non-gated FFN path in `cudaandrocmbackend.inc` (~`:3307-3361`) to make `b5c48h3tfr`
   engine-loadable. Not preferred: it is an engine patch (design says none), gains ~6× fewer params than b7 but no throughput benefit on a
   GPU that is already batch-starved at 0.8 M params; only worth it if b7 proves too slow to train on 24 CPUs of self-play.
   Predecessors: `engine_ffn_swiglu_constraint`. verify: `katago benchmark -model <b5.bin.gz> -boardsize 9` exits 0 on the patched build.
4. `async_multi_gpu_layout` — [FUTURE] pass 2 §7's 3 self-play GPUs / 1 training GPU concurrent layout (with `CUDA_VISIBLE_DEVICES` masks and
   `cudaDeviceToUseModel0Thread{k}`); deferred until `measure_stage_throughput` shows single-GPU duty cycle > 70 % and the queue accepts
   > 1 GPU. Predecessors: `measure_stage_throughput`, `scale_up`. verify: `sacct -j <id> -o AllocTRES` shows `gres/gpu=N≤4` and `nvidia-smi dmon` logs nonzero utilisation on every allocated GPU.

Process gaps (not DAG nodes): (a) pass-1 knowledge rows carry no `verification` object (0 of 26 have one) — the admission gate has nothing to
execute; the merged list supplies one per node. [SOLID] verify: `python3 -c "import json;print(sum(1 for l in open('results/ledgers/knowledge/paper_arxiv-1902.10565/nodes.jsonl') if json.loads(l).get('verification')))"` → `0`.
(b) The b5 abort is in the error ledger (trial 2026-09-04T02:00:27Z, `task_id=env_build`) with root cause and fix — good; its `root_cause`
text mislabels `ffng` as "gpool FFN" (§0). (c) `env-toolchain-b200` lists three `[OPEN]` obligations; the first two are exactly
`cfg_9x9_override` and `synchronous_loop_smoke` — link them as `dependencies` when those rows land.

## 3. Edge corrections to pass 1 (`logic.md` / ledger `predecessors`)

- add `env_build → cfg_9x9_override`: the node's verification (1-game parse run, task file §2) needs the built binary; today the node has
  only code-map predecessors. [SOLID] verify: `tasks/cfg_9x9_override/implementation.md` §2 item 3 calls `$KATAGO_BIN`.
- add `data_format_pos_len → train_stage`: the pos_len assert (`data_processing_pytorch.py:91`) fires in training, not in shuffle; pass 1
  routes it only through `shuffle_stage`. [SOLID] verify: `sed -n 91p ref-code/lightvector-KataGo/python/katago/train/data_processing_pytorch.py`.
- add `data_budget → selfplay_stage`: the storage guard must be armed before the first production self-play writes monotonic `tdata/`;
  pass 1 has `data_budget` only feeding `scale_up`. [PRELIMINARY] verify: audit §F "never pruned".
- split `loop_resume_under_walltime` (wrapper) and add `verify_preemption_resume` with predecessors `synchronous_loop_smoke`,
  `train_resume_semantics`, `export_stage`-semantics (o09); make `verify_preemption_resume → selfplay_stage` so production waits for the
  resume proof (claim c08 currently hangs off the wrapper node with no executed successor). [PRELIMINARY]
- add `engine_ffn_swiglu_constraint → select_transformer_ladder → {tiny_model_export_smoke, train_stage, scale_up}` and
  `transformer_trunk_b5c48h3tfr → engine_ffn_swiglu_constraint`. [SOLID] (§0)
- add `train_optimizer_schedule → eval_improvement`: the declaration must state whether the run crossed the 2 M-sample warm-up
  (`train.py:1059-1079`); strength before that is pipeline verification. [PRELIMINARY]
- add `gating_rule → bootstrap_accepted_model` (random-baseline gate semantics decide what "first accepted" means). [SOLID] (§1 gating row)
- add `measure_stage_throughput` between `gatekeeper_stage`/`verify_preemption_resume` and every `scale_*` node; today `scale_up` has no
  measurement predecessor. [PRELIMINARY]
- `loop_resume_under_walltime → synchronous_loop_smoke` stays (the smoke runs under the wrapper); `tiny_model_export_smoke → export_stage`
  stays (the exporter/loader boundary is proven once). No pass-1 edge is wrong per se; the gaps are the missing ones above.

## 4. Design conflicts: `DESIGN.md` (pass 1) vs `design_pass2.md` (pass 2)

### 4.1 GPU split — recommend pass 1 (one GPU, 24 CPUs, five stages sequential); 2-GPU and 4-GPU layouts deferred
- [SOLID] Queue: a 1-GPU job started immediately, a 2-GPU job projected > 2 months on 2026-09-03 (`docs/cluster-manual.md` §6 "Queue waits
  scale sharply with GPU count"); b300 is a single node (`gb301`, §3) and was reserved (DESIGN §1, `scontrol show reservation`).
  verify: `sed -n 178,186p docs/cluster-manual.md`; `bash "$POLICY_CHECK" --gpus 1 --cpus 24 --partition b200` where `POLICY_CHECK=$(python3 -c 'import json;print(json.load(open("mission.json"))["compute"]["policyCheck"])')`.
- [PRELIMINARY] Utilisation: b7c96h3tfrs evaluates 2322 nnEvals/s at batch 1 on one B200 (`smoke-298018.txt`); with ≤18 game threads the
  NN queue depth is ≤18, so a second GPU cannot be fed; DDP for an 825 k-param model at 81 tokens adds sync cost with no throughput need.
  Pass 2's default 2-GPU request and `-multi-gpus 0,1` are dropped; its 4-GPU 3:1 split becomes `async_multi_gpu_layout` `[FUTURE]`.
  verify: `measure_stage_throughput` must show GPU duty cycle (`nvidia-smi dmon -s u`) and NN batch size (`nnBatches`/`nnEvals` in the selfplay log) before any GPU is added.
- [HOLE] Whether the 24-CPU policy is per job or summed over concurrent jobs (DESIGN §1 [HOLE]) — `check.sh` sums `squeue -u $USER` CPUs,
  so the design must assume the sum. verify: `check.sh` lines computing `my_cpus`.

### 4.2 Starting configuration — recommend `b7c96h3tfrs`; both passes wrong
- [SOLID] §0. Ladder: b7c96h3tfrs → b8c96h3tfrs → b14c192h6tfrs (→ `tflrs`, nbt as `[FUTURE]`). Each is a fresh run (`train.py:850` takes the
  config from the checkpoint; never load a b7 checkpoint into b8).
  verify: `grep -n "Non-SwiGLU" ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc`; `sed -n 848,851p ref-code/lightvector-KataGo/python/train.py`.
- [PRELIMINARY] Memory/throughput for b7 at pos_len 9, batch 128: torch smoke used 162 MB at batch 4; training batch 128 is O(5 GB) — no
  headroom issue on 180 GB. verify: `train_stage` logs `torch.cuda.max_memory_allocated()`.

### 4.3 Thread counts — recommend pass 1's table with one correction (gatekeeper 20 → 18)
- [SOLID] Thread model: selfplay = `numGameThreads` + `numNNServerThreadsPerModel` + 1 data-write/model + 1 model-load + main
  (`selfplay.cpp:359-364`, `setup.cpp:193-203`, `selfplaymanager.cpp:156`); gatekeeper = `numGameThreads` + 2×NN + 1 data-write + main
  (`gatekeeper.cpp:548-553`). Pass 1: selfplay 18 → 22 (+2 transient at net switch) ✓; gatekeeper 20 → 24, at the cap with no margin →
  use 18 (22). Pass 2's 16 game + 2 NN (two GPUs) and gatekeeper 12 are consistent only with its 2-GPU plan; with one GPU they under-use
  the CPU budget. Train: `OMP_NUM_THREADS=4`, `MKL_NUM_THREADS=4`, `-data-prefetch-depth 1` (pass 1) rather than pass 2's 8/8/16.
  verify: `ps -o nlwp= -p $(pgrep -f 'katago selfplay')` ≤ 24 and the same for `katago gatekeeper` during `synchronous_loop_smoke` (claim c06).
- [PRELIMINARY] Shuffle `-num-processes 8` in both passes; fine within 24 while no other stage runs.

### 4.4 Data windows / cycle knobs — recommend pass 1's scaled-down set, re-derived from measured rows/game; pass 2's pilot set is inconsistent
- [SOLID] Bucket arithmetic: `train_bucket_level += new_rows × max_train_bucket_per_new_data` (`train.py:1256-1262`); an epoch runs only if
  `bucket > 0.99 × samples_per_epoch`, else `-stop-when-train-bucket-limited` exits (`:1433-1445`); the first epoch is free
  (`train_bucket_level = samples_per_epoch` at `:966-967`).
- [PRELIMINARY] At ~22 rows/game (audit §F; assumption a07) 500 games ≈ 11 k rows/cycle. Pass 2 pilot (reuse 4, 50 k samples/epoch): bucket
  gain 44 k < 49.5 k → from cycle 2 on, training exits with zero epochs every cycle; also `-min-rows 50000` needs ~2300 random games before the
  first shuffle. Pass 1 (reuse 8, 20 k samples/epoch, MINROWS 10 k): gain 88 k → 4 epochs/cycle ✓, but default `-epochs-per-export 1`
  (`train.py:438-439`) exports up to 4 candidates per cycle, each gated with 200 games at 150 visits — comparable to the cycle's own
  self-play cost. Recommend pass 1 knobs + `-epochs-per-export 4 -max-epochs-this-instance 4` (pass 2's bootstrap flags) so one candidate
  per cycle, all re-derived in `derive_cycle_knobs_9x9` after the smoke measures rows/game.
  verify: smoke log lines `Fill per data`, `New rows in bucket`, `Exceeding train bucket` (train.py:1257-1262,1441) and count of `SAVING MODEL FOR EXPORT` per cycle.
- [SOLID] Random-play rows are capped at `min_rows` by the shuffler (`shuffle.py:1058,1077`), so a long random bootstrap cannot flood the
  window; both passes may keep the random cycle(s) (assumption a10). verify: `sed -n 1058p;1077p` of `shuffle.py`.
- [PRELIMINARY] `-exclude-qvalues` (pass 2): valid since b7c96h3tfrs has no `predict_q_values`; `[OPEN]` confirm `train.py` accepts npz without
  `qValueTargetsNCMove` before adopting. verify: smoke run with the flag exits 0 through one epoch.

### 4.5 Scratch budget — merge: pass 2's guards + pass 1's calibration; the group quota is the binding constraint
- [PRELIMINARY] Both cap the mission at 200 GiB. Adopt pass 2's 180 GiB pre-cycle guard and per-stage `du -sb`/`df -B1` records; adopt
  pass 1's calibration (2145 B/row × ~0.12 compression ≈ 260 B/row at L=9, to be measured after 100 k rows) instead of pass 2's 1 KiB/row
  planning number; add the group-quota check (`python3 /apps/helpers/quotas.py`, `check.sh`) to the guard because the filesystem is at 94 %
  for the whole group, so `du` of `BASEDIR` alone cannot detect exhaustion. Prune `longterm_checkpoints` (≤6), `rejectedmodels` (≤10),
  stale `shuffleddata/*.tmp`. Uncounted: venv + build under the same root (DESIGN §5 [HOLE]) — include them in the guard's `du`.
  verify: wrapper log has one `du -sb`/`df -B1`/quota triple per cycle; `du -sb $KTG` ≤ 214748364800.

### 4.6 USEGATING and bootstrap — recommend `USEGATING=1` throughout, with the random-baseline fact recorded (either pass's choice works)
- [SOLID] With empty `models/` the gatekeeper gates the first candidate against the random net (§1 `gating_rule`). Pass 1's "gating skipped"
  and pass 2's "requires an accepted model" are both wrong; pass 2's `USEGATING=0`-once is harmless and saves 200 games; pass 1's
  `USEGATING=1` yields a free sanity check (first net must beat random) and one code path. The frozen baseline for the match is the first
  directory that appears in `models/` in either scheme (`bootstrap_accepted_model`).
  verify: gatekeeper log contains `Loaded accepted neural net random from: /dev/null` in cycle 1 (or, with `USEGATING=0`, `models/` gains exactly one dir with no gate).

### 4.7 Evaluation criterion — merge: pass 2's statistical form with pass 1's effect-size target
- [PRELIMINARY] Declare "improves under self-play" iff ≥1 gate-accepted successor (pass 2 minimum; pass 1 asked ≥2 — keep ≥2 as the
  stretch target) AND the 400-game latest-vs-first match (9x9 only, `komiAuto`/komi 7, 150 visits, 1 search thread, colours alternated,
  `numGamesTotal=400`) has `p=(W+0.5D)/N` with 95 % CI excluding 0.5; report `Elo=400·log10(p/(1−p))`; pass 1's p ≥ 0.60 (~+70 Elo) is the
  effect-size target. Use `python/summarize_sgfs.py` (exists; `katago/utils/elo.py`) for the interval. External reference net: `[FUTURE]`.
  verify: `katago match -config codes/cfg/match_first_latest_9.cfg -log-file $EVAL/match.log -sgf-output-dir $EVAL/sgfs` then `python summarize_sgfs.py $EVAL/sgfs`.

### 4.8 Build options — record, no conflict to resolve
- [PRELIMINARY] Pass 2 asks for `-DUSE_TCMALLOC=1 -DNO_GIT_REVISION=1`; the executed build used neither (git revision embedded, binary reports
  `-dirty` because of the arch patch — noted in `env-toolchain-b200` open obligations). TCMalloc is upstream's recommendation against
  fragmentation with many game threads (`Compiling.md:38`); at 18 threads on a 1.5 TB node the risk is low → `[OPEN]` monitor selfplay RSS in
  the smoke; rebuild with TCMalloc only if RSS grows across cycles. verify: `ldd $KATAGO_BIN | grep -c tcmalloc` (currently 0) and `sstat -j <id> -o MaxRSS` per cycle.

## 5. Proposed merged node list (38 nodes) — for the reformulation agent

Namespace `arxiv-1902.10565::`. `$KTG=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train`, `$REF=ref-code/lightvector-KataGo`,
`$CODES=results/ktg/paper_1902.10565/codes`, `$POLICY_CHECK` = the compute-budget check script named by `mission.json` `compute.policyCheck`. Status column = proposed ledger status after this review (before any new execution).
Evidence types use the admission-contract vocabulary. Pass-1 rows that change content are appended as new rows on the same `node_id`
(prior row → `amended`), never edited.

| # | node_id | summary | predecessors | evidence type | verification command | status |
|---|---|---|---|---|---|---|
| 1 | `transformer_trunk_b5c48h3tfr` | tf-family trunk code map (attnrope + ffng/ffnsg, RoPE θ=100 non-persistent, no trunk gpool, exporter block kinds); amended: `ffng` is torch-only | — | literature grounding | `grep -n '"ffng"\|"ffnsg"' $REF/python/katago/train/model_pytorch.py \| grep -q 3269 && sed -n 986,1006p $REF/python/katago/train/modelconfigs.py \| grep -q ffng` | preliminary |
| 2 | `engine_ffn_swiglu_constraint` | Every C++ backend throws on `useSwiGLU=0`; ffng configs cannot be loaded by the engine (observed exit 134, job 297952) | 1 | numerical simulation + literature grounding | `grep -q "Non-SwiGLU transformer FFN is not yet supported" $REF/cpp/neuralnet/cudaandrocmbackend.inc && grep -q "Non-SwiGLU" $KTG/runtime/smoke/gtp_logs/20260903-215545-0ED5F752.log` | solid |
| 3 | `select_transformer_ladder` | Ladder b7c96h3tfrs → b8c96h3tfrs → b14c192h6tfrs (fresh runs each); b5 excluded; nbt `[FUTURE]` | 2 | literature grounding | `cd $REF/python && python -c 'from katago.train.modelconfigs import config_of_name as c; assert all(k[1]=="ffnsg" for k in c["b7c96h3tfrs"]["block_kind"] if k[0].startswith("ffn"))'` | preliminary |
| 4 | `playout_cap_randomization` | as pass 1 | — | literature grounding | `sed -n 60,62p $REF/cpp/configs/training/selfplay1_maxsize9.cfg \| grep -q "cheapSearchProb = 0.75" && sed -n 1143p $REF/cpp/program/play.cpp \| grep -q cheapSearchTargetWeight` | preliminary |
| 5 | `root_explore_and_target_pruning` | as pass 1; note `useNoisePruning` default false for selfplay (SETUP_FOR_OTHER) — do not set it | — | literature grounding | `sed -n 578p $REF/cpp/program/setup.cpp \| grep -q SETUP_FOR_OTHER && sed -n 110p $REF/cpp/command/selfplay.cpp \| grep -q SETUP_FOR_OTHER` | preliminary |
| 6 | `score_utility_search` | as pass 1 | — | literature grounding | `sed -n 56p $REF/cpp/neuralnet/nninputs.cpp \| grep -q "twoOverPi" && sed -n 159p $REF/cpp/configs/training/selfplay1_maxsize9.cfg \| grep -q "dynamicScoreUtilityFactor = 0.40"` | preliminary |
| 7 | `loss_targets_metrics` | as pass 1 | 1 | literature grounding | `sed -n 856,882p $REF/python/katago/train/metrics_pytorch.py \| grep -q "loss_policy_player \* policy_opt_loss_scale"` | preliminary |
| 8 | `head_gpool_degeneracy_9x9` | as pass 1 | 1 | literature grounding → numerical simulation (probe) | `bash $CODES/eval/probe_train_9x9.sh` assertion 2 (pool2 = −0.5·pool1, pool3 = 0.15·pool1) | preliminary |
| 9 | `train_optimizer_schedule` | as pass 1 + warm-up reaches 1.0 at 2 M samples; AdamW/Muon √batch scaling | 1 | literature grounding | `sed -n 1076,1079p $REF/python/train.py \| grep -q 2000000` | preliminary |
| 10 | `selfplay_search_params` | as pass 1 + thread model incl. data-write threads; gatekeeper `numGameThreads=18` | — | literature grounding | `sed -n 548p $REF/cpp/command/gatekeeper.cpp \| grep -q "std::thread newThread(dataWriteLoopProtected)"` | preliminary |
| 11 | `game_randomization_9x9` | as pass 1 | — | literature grounding | `sed -n 95,97p $REF/cpp/configs/training/selfplay1_maxsize9.cfg \| grep -q "bSizes = 7,8,9"` | preliminary |
| 12 | `gating_rule` | as pass 1 + empty `models/` ⇒ random baseline (`findLatestModel` always true, `/dev/null` ⇒ `debugSkipNeuralNet`); ties to candidate | — | literature grounding | `sed -n 93p $REF/cpp/dataio/loadmodel.cpp \| grep -q "return true" && sed -n 126p $REF/cpp/program/setup.cpp \| grep -q '/dev/null'` | preliminary |
| 13 | `train_resume_semantics` | as pass 1 | — | literature grounding | `sed -n 780p $REF/python/train.py \| grep -q get_checkpoint_path && sed -n 1884p $REF/python/train.py \| grep -q "hours=12"` | preliminary |
| 14 | `data_format_pos_len` | as pass 1 (2145 B/row at L=9; assert at data_processing_pytorch.py:91; train.sh:88 hard-codes 19) | — | literature grounding → numerical simulation | `sed -n 88p $REF/python/selfplay/train.sh \| grep -q -- "-pos-len 19" && bash $CODES/eval/probe_train_9x9.sh` assertion 3 | preliminary |
| 15 | `training_window_shuffle` | as pass 1 + random rows capped at `min_rows` | — | literature grounding | `sed -n 1077p $REF/python/shuffle.py \| grep -q "min(num_random_rows_capped + num_rows, min_rows)"` | preliminary |
| 16 | `env_build` | venv (torch 2.11.0+cu128, cuDNN 9.19 wheel) + CUDA build with sm_100 patch, CUTLASS fused FFN; `[OPEN]` TCMalloc | — | numerical simulation | `test -x $KTG/build/KataGo/cpp/build/katago && grep -q "SMOKE RESULT: PASS" $KTG/evidence/env/smoke.txt && grep -q "grep -c sm_100 = 2" $KTG/evidence/env/smoke-298018.txt` | preliminary |
| 17 | `cfg_9x9_override` | mission `selfplay_9x9.cfg`/`gatekeeper_9x9.cfg`/`train_9x9.sh`: dataBoardLen 9, bSizes 9, bSizeRelProbs 1, allowRectangleProb 0, `-pos-len 9`, threads 18/18/1/1, shuffle 8, OMP 4 | 10, 11, 12, 14, 16 | exact proof (key diff) + numerical simulation (1-game run) | `bash $CODES/eval/check_cfg_9x9.sh` (key-diff whitelist + 1 game, all `SZ[9]`) and `grep -c -- '-pos-len 9' $CODES/loop/train_9x9.sh` = 1 | hypothesis |
| 18 | `tiny_model_export_smoke` | random-init **b7c96h3tfrs** export → block-kind scan → `benchmarknn -boardsize 9 -require-exact-nnlen -batch-size 2 -json` on CUDA | 3, 16, 17 | numerical simulation | `cd $REF/python && python export_model_pytorch.py -export-random-initialized-model b7c96h3tfrs -export-dir $KTG/runtime/smoke/x -model-name x -filename-prefix model && grep -c "transformer_ffn_block" $KTG/runtime/smoke/x/model.bin` = 7 `&& $KTG/build/KataGo/cpp/build/katago benchmarknn -model $KTG/runtime/smoke/x/model.bin -config $CODES/cfg/benchmark9.cfg -boardsize 9 -require-exact-nnlen -batch-size 2 -warmup 1 -iterations 2 -json \| python -m json.tool` | preliminary (b7 benchmark/gtp already pass) |
| 19 | `loop_resume_under_walltime` | Slurm wrapper: `--time 2-23:30:00 --gres gpu:1 --cpus-per-task 24`, self-resubmit `afterany`, `.failcount` stop at 3, stale `*.tmp`/`*.exported` cleanup, `check.sh` before `sbatch`; encodes the run contract (≤4 GPU/≤24 CPU/≤72 h, b300→b200) | 13, 16 | exact proof (script audit) | `bash -n $CODES/loop/loop.sbatch && grep -q "afterany" $CODES/loop/loop.sbatch && grep -q "failcount" $CODES/loop/loop.sbatch && bash "$POLICY_CHECK" --gpus 1 --cpus 24 --partition b200` | hypothesis |
| 20 | `data_budget` | 200 GiB cap, 180 GiB pre-cycle guard, group-quota check, per-stage `du`/`df`; measured bytes/row after 100 k rows; prune ckpts/rejected | 14, 22 | dimensional consistency → empirical measurement | `grep -q "du -sb" $CODES/loop/loop.sbatch && grep -q quotas.py $CODES/loop/loop.sbatch && test $(du -sb $KTG \| cut -f1) -le 214748364800` | hypothesis |
| 21 | `derive_cycle_knobs_9x9` | Turn measured rows/game into NUM_GAMES/MINROWS/KEEPROWS/samples-per-epoch/epochs-per-export satisfying the bucket inequality (§4.4) | 13, 14, 15, 22 | dimensional consistency | `python3 $CODES/eval/derive_knobs.py --rows-per-game $(cat $KTG/evidence/smoke/rows_per_game.txt) --reuse 8` exits 0 and prints a knob set with `games*rows*reuse >= 0.99*samples_per_epoch` | hypothesis |
| 22 | `synchronous_loop_smoke` | one disposable cycle gatekeeper→selfplay→shuffle→train→export with b7c96h3tfrs, tiny knobs, `USEGATING=1`; audit: raw+shuffled npz spatial 81 / policy 82, ckpt `pos_len=9`, only `SZ[9]`, exported `model.bin.gz` loads; records rows/game | 17, 18, 19 | numerical simulation | `bash $CODES/loop/smoke_one_cycle.sh && python3 $CODES/eval/audit_smoke.py $KTG/runs/smoke` (asserts above; writes `rows_per_game.txt`) | hypothesis |
| 23 | `verify_preemption_resume` | kill mid-train and mid-export, resubmit same BASEDIR: `global_step_samples` non-decreasing, no npz lost, no orphan `*.exported`, no `.tmp` dir selected | 13, 22 | empirical measurement | `bash $CODES/eval/kill_resume_test.sh $KTG/runs/smoke` (exit 0 iff the four assertions hold) | hypothesis |
| 24 | `selfplay_stage` | `katago selfplay -max-games-total N ... -config selfplay_9x9.cfg` at production knobs; cycle 1 random net; records games/h, rows/game | 4, 5, 6, 10, 20, 21, 23 | numerical simulation → empirical measurement | `grep -L 'SZ\[9\]' $KTG/runs/p1/selfplay/*/sgfs/*.sgfs \| wc -l` = 0 and `ps -o nlwp= -p $(pgrep -f 'katago selfplay')` ≤ 24 | hypothesis |
| 25 | `shuffle_stage` | `SKIP_VALIDATE=1 ./shuffle.sh BASEDIR TMP 8 -min-rows M -keep-target-rows K -taper-window-scale S [-exclude-qvalues]`; atomic dir + `.json` range | 14, 15, 24 | numerical simulation | `test -f $(ls -d $KTG/runs/p1/shuffleddata/*[!p] \| tail -1).json && ! ls -d $KTG/runs/p1/shuffleddata/*.tmp` | hypothesis |
| 26 | `train_stage` | `train_9x9.sh ... b7c96h3tfrs 128 main -samples-per-epoch E -swa-period-samples S -epochs-per-export k -max-epochs-this-instance k -quit-if-no-data -stop-when-train-bucket-limited -no-repeat-files -max-train-bucket-per-new-data 8 -max-train-bucket-size C`, 1 GPU, OMP 4; finite losses, policy loss ↓ over 10 epochs | 1, 7, 9, 13, 14, 25 | numerical simulation → empirical measurement | `python3 $CODES/eval/check_metrics.py $KTG/runs/p1/train/ktg9/metrics_train.json` (finite, epoch-10 policy loss < epoch-1) | hypothesis |
| 27 | `export_stage` | mission `export_model_for_selfplay.sh` (rm after mv), `export_model_pytorch.py -use-swa`; attn-logit refusal detected (exit ≠ 0 → error row) | 18, 26 | numerical simulation | `grep -c "Done exporting:" $KTG/runs/p1/logs/outexport.txt` ≥ 1 and `! ls $KTG/runs/p1/torchmodels_toexport/*.exported` | hypothesis |
| 28 | `gatekeeper_stage` | `katago gatekeeper ... -config gatekeeper_9x9.cfg -quit-if-no-nets-to-test`; 200 games, 150 visits, win-prop 0.5, ties to candidate; cycle-1 baseline = random | 12, 27 | empirical measurement | `grep -E "Candidate (won\|lost) match" $KTG/runs/p1/gatekeepersgf/stdout.txt \| wc -l` ≥ 1 and `grep -L 'SZ\[9\]' $KTG/runs/p1/gatekeepersgf/*/*.sgfs \| wc -l` = 0 | hypothesis |
| 29 | `bootstrap_accepted_model` | first dir in `models/` frozen as baseline: name + SHA-256 in the run manifest; never deleted | 12, 27, 28 | exact proof | `test -f $KTG/runs/p1/manifest.json && python3 -c 'import json;m=json.load(open("'$KTG'/runs/p1/manifest.json"));assert m["first_model_sha256"]'` and `sha256sum` of `models/<first>/model.bin.gz` matches | hypothesis |
| 30 | `measure_stage_throughput` | per-stage JSON: games/h, rows/h, shuffled rows/h, samples/s, GPU duty (`nvidia-smi dmon`), peak VRAM/RSS, bytes/row, on b200 (and b300 when free); projected cycle ≤ 60 h | 23, 28 | empirical measurement | `python3 $CODES/eval/throughput_report.py $KTG/runs/p1 --out $KTG/evidence/throughput.json && python3 -c 'import json;d=json.load(open("'$KTG'/evidence/throughput.json"));assert d["projected_cycle_h"]<=60'` | hypothesis |
| 31 | `count_gatekeeper_acceptances` | accepted successors = `models/` dirs − 1 = parsed `Candidate won match` lines ≥ 1 (target ≥ 2) | 28, 29 | empirical measurement | `test $(( $(find $KTG/runs/p1/models -mindepth 1 -maxdepth 1 -type d \| wc -l) - 1 )) -eq $(grep -c "Candidate won match" $KTG/runs/p1/gatekeepersgf/stdout.txt)` | hypothesis |
| 32 | `match_latest_against_first` | `katago match` 400 games, 9x9 only, 150 visits, 1 search thread, latest accepted vs frozen first; W/L/D, p, Elo, 95 % CI via `summarize_sgfs.py` | 29, 31 | statistical inference | `$KTG/build/KataGo/cpp/build/katago match -config $CODES/cfg/match_first_latest_9.cfg -log-file $KTG/eval/match.log -sgf-output-dir $KTG/eval/sgfs && cd $REF/python && python summarize_sgfs.py $KTG/eval/sgfs` (400 games, all `SZ[9]`) | hypothesis |
| 33 | `eval_improvement` | declare improvement iff ≥ 1 acceptance AND CI excludes 0.5 (target p ≥ 0.60); report samples vs 2 M warm-up, GPU-hours, hashes | 9, 31, 32 | statistical inference | `python3 $CODES/eval/declare.py $KTG/eval --require-acceptances 1 --ci 0.95` exits 0 iff both metrics pass; prints "not demonstrated" otherwise | hypothesis |
| 34 | `scale_data_window` | raise games/cycle and window one axis at a time; gates: reuse ≤ 8, kept rows > train cap, no-data wait < 10 %, disk < 180 GiB | 21, 30 | controlled approximation | two artifact-complete cycles + `throughput_report.py` shows `train_bucket_used/new_rows<=8` and projected disk < 193273528320 | hypothesis |
| 35 | `scale_search_budget` | visits 128/32 → 300/64 → 600/100; coefficients fixed; advance only if projected cycle ≤ 60 h and GPU duty ≥ 70 % | 34 | controlled approximation | `throughput_report.py` at each step records games/h; gate arithmetic in `declare.py --scaling` | hypothesis |
| 36 | `scale_up` | next architecture (b8c96h3tfrs, then b14c192h6tfrs) as a fresh run after b7 closes an end-to-end gated run; admit only if export/load smoke passes, batch fits with ≥ 10 % VRAM headroom, Elo/GPU-h ≥ b7 | 3, 8, 20, 33, 35 | conjecture → numerical simulation | re-run nodes 18, 22 with the new `MODELKIND`; `grep -c transformer_ffn_block model.bin` = 8 (b8) | hypothesis |
| 37 | `port_ffng_to_cuda` | implement non-gated FFN in the CUDA backend so b5c48h3tfr loads; engine patch — not preferred | 2 | numerical simulation | `katago benchmark -model <b5>.bin.gz -config gtp_example.cfg -boardsize 9 -v 80 -t 1` exits 0 on the patched build | future |
| 38 | `async_multi_gpu_layout` | concurrent selfplay/train on 2–4 GPUs with disjoint device masks; only after node 30 shows single-GPU saturation and the queue accepts > 1 GPU | 30, 36 | controlled approximation | `sacct -o AllocTRES` ≤ 4 GPUs and `nvidia-smi dmon` nonzero on every GPU; games/h and samples/s both ≥ the 1-GPU baseline | future |

Rendering note: nodes 1–15 form the code-map layer (all `preliminary` until the two probe tasks `paper_code_map_search` /
`paper_code_map_training` run — these are task files, not DAG nodes; DESIGN §6 calls them nodes, which should be reworded). Node 2 is the
only row proposed `solid` at append time: its evidence is an existing artifact (the gtp log) plus five grep-able anchors, and it has a
`solid`-eligible predecessor only after node 1 is promoted — append node 2 as `preliminary` if the gate rejects `solid` with a
`preliminary` predecessor, then promote both together after the probe. [PRELIMINARY] verify: `python3 phys-agentic-loop/_common/knowledge_database.py describe-fields` (solid requires solid predecessors, per `admission.py`).

## 6. Summary of judgements (for the coordinator)

- Verdicts: pass 1 — 24 keep / 2 split / 0 drop; pass 2 — 8 add / 24 merge-into / 0 drop; 4 new (2 of them `future`); merged 38 ≤ 40.
- Top corrections: (1) start config `b5c48h3tfr` → `b7c96h3tfrs`, every engine backend rejects `ffng` [SOLID]; (2) empty `models/` ⇒ the
  gatekeeper gates against a random baseline, not "skip"/"require" as both passes wrote [SOLID]; (3) pass 2's pilot knobs starve training
  from cycle 2 (bucket 44 k < 49.5 k) and pass 1 exports up to 4 gated candidates per cycle — derive knobs from measured rows/game and set
  `-epochs-per-export` [PRELIMINARY]; (4) drop pass 2's `useNoisePruning=true` (behaviour change) and its 2-GPU/DDP default (queue + starved
  GPU) [SOLID/PRELIMINARY]; (5) pass-1 ledger rows have no `verification` object and the gatekeeper thread count misses the data-write thread
  — fixed in the merged list [SOLID].
- `[OPEN]` carried forward: `-exclude-qvalues` compatibility with `train.py`; TCMalloc (RSS growth across cycles); whether the 20 % CPU
  policy is per job or summed over concurrent jobs; external 9x9 reference net (`[FUTURE]`).
