# DAG adjudication B — 9x9 transformer-trunk KataGo

Scope: independent adjudication of pass 1 and pass 2 against the v1.18.2 mirror, the admission contract, and the two B200 environment runs. The mirror is authoritative; the 2019 paper is background only. Runtime observations below remain `[PRELIMINARY]` because they have not entered the ledgers.

The immediate operational decision is `[PRELIMINARY]`: do not use `b5c48h3tfr` for any CUDA-backed self-play loop. Its Python export and Torch forward/backward succeeded, but both C++ benchmark and GTP aborted with exit 134; the engine log names unsupported non-SwiGLU transformer FFN, and the mirror throws on `!useSwiGLU`. Use `b7c96h3tfrs` as the smallest currently demonstrated end-to-end configuration, keep b5 only as a negative compatibility fixture, and make b8 the first scale-up.

verify: `rg -n 'Non-SwiGLU transformer FFN|if\(!useSwiGLU\)' ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/gtp_logs/*.log && rg -n 'benchmark.*b5|gtp genmove.*b5|torch cuda forward/backward.*b5|benchmark.*b7|gtp genmove.*b7|torch cuda forward/backward.*b7|SMOKE RESULT' /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/env_build-297952.log /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/env_build-298018.log`

## 1. Union adjudication

Every pass-1 node is represented below, and every pass-2 node is mapped at least once. All unqualified ids in the `pass 1:` and `pass 2:` fields expand under `arxiv-1902.10565::`. A pass-2 composite may map to several retained pass-1 concepts when its implementation/evidence types need to be separated. `[SOLID]`

verify: `for id in $(rg -o 'arxiv-1902\.10565::[a-z0-9_]+' results/ktg/paper_1902.10565/decomposition/logic_pass2.md | sed 's/.*:://' | sort -u); do rg -q "$id" results/ktg/paper_1902.10565/evidence/decomposition/dag_review_b.md || exit 1; done; for id in $(rg -o '<b>[a-z0-9_]+' results/ktg/paper_1902.10565/decomposition/logic.md | sed 's/<b>//' | sort -u); do rg -q "$id" results/ktg/paper_1902.10565/evidence/decomposition/dag_review_b.md || exit 1; done`.

1. **Canonical `arxiv-1902.10565::freeze_run_contract`**; pass 1: none; pass 2: `freeze_run_contract`; verdict **add-from-pass2**. `[SOLID]` The resource, placement, walltime, and path manifest is an independent admission gate and must precede environment or storage work; exact live partition/module availability remains `[OPEN]`. Anchor: `python/selfplay/synchronous_loop.sh:12-45` for the loop path contract; scheduler policy has no mirror anchor.

   verify: `rg -n 'NAMEPREFIX|BASEDIR|TRAININGNAME|MODELKIND|USEGATING|mkdir -p' ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh`; at execution, `scontrol show job "$SLURM_JOB_ID"` must show one node, `NumCPUs<=24`, GPUs `<=4`, and `TimeLimit<=3-00:00:00`.

2. **Canonical `arxiv-1902.10565::env_build`**; pass 1: `env_build`; pass 2: `provision_cuda_environment`; verdict **split**. `[PRELIMINARY]` Keep this id for the Python/CUDA/cuDNN environment only; compilation and engine execution have different failure modes and evidence. Anchor: `cpp/CMakeLists.txt:1120-1143`, `cpp/neuralnet/cudabackend.cpp:13`.

   verify: `rg -n 'CUDNN_INCLUDE_DIR|CUDNN_LIBRARY|CUDNN_VERSION' ref-code/lightvector-KataGo/cpp/CMakeLists.txt ref-code/lightvector-KataGo/cpp/neuralnet/cudabackend.cpp && rg -n 'torch +2.11.0\+cu128|CUDNN_(MAJOR|MINOR|PATCHLEVEL)' /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/env_build-297952.log`.

3. **Canonical `arxiv-1902.10565::build_cuda_backend`**; pass 1: build slice of `env_build`; pass 2: `build_cuda_backend`; verdict **add-from-pass2**. `[PRELIMINARY]` A successful compile/version/runtests gate does not imply that an exported transformer can execute, as job 297952 demonstrated. Anchor: `cpp/CMakeLists.txt:717-782,1120-1143`.

   verify: `rg -n 'USE_BACKEND STREQUAL "CUDA"|NEURALNET_BACKEND_SOURCES|find_package\(CUDAToolkit|find_path\(CUDNN|find_library\(CUDNN' ref-code/lightvector-KataGo/cpp/CMakeLists.txt && rg -n '\[OK\] katago version|\[OK\] katago runtests|SMOKE RESULT' /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/env_build-297952.log`.

4. **Canonical `arxiv-1902.10565::select_transformer_ladder`**; pass 1: `transformer_trunk_b5c48h3tfr`; pass 2: `select_transformer_ladder`; verdict **merge-into**. `[PRELIMINARY]` The pass-1 id is too narrow and its claim “exportable to the C++ engine” must be narrowed to serialization/parser compatibility: b5 uses `ffng`, which the CUDA backend rejects; revise the ladder to b7 start, b8 scale, b14 future. If the post-snapshot `transformer_trunk_b7c96h3tfrs` record is present, merge that architecture-only record here as well rather than retaining a second ladder derivation. Anchors: `python/katago/train/modelconfigs.py:986-1021,1057-1070,1453-1466,1886-1895`; `cpp/neuralnet/cudaandrocmbackend.inc:3299-3308`.

   verify: `rg -n 'b5c48h3tfr|b7c96h3tfrs|b8c96h3tfrs|b14c192h6tfrs|no swiglu' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py && rg -n 'useSwiGLU|Non-SwiGLU transformer FFN' ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc`.

5. **Canonical `arxiv-1902.10565::playout_cap_randomization`**; pass 1: same; pass 2: `freeze_search_and_auxiliary_targets` (playout-cap slice); verdict **keep**. `[SOLID]` It is a distinct code-current search/data derivation, independent of network size. Anchor: `cpp/program/play.cpp:1113,1128,1132-1150`; `cpp/configs/training/selfplay1_maxsize9.cfg:60-62,115`.

   verify: `rg -n 'cheapSearchProb|cheapSearchVisits|cheapSearchTargetWeight|numAlterVisits|targetWeight \*=' ref-code/lightvector-KataGo/cpp/program/play.cpp ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg`.

6. **Canonical `arxiv-1902.10565::root_explore_and_target_pruning`**; pass 1: same; pass 2: `freeze_search_and_auxiliary_targets` (forced-playout/pruning slice); verdict **keep**. `[SOLID]` Forced root visits and policy-target pruning are separate from generic knob freezing and have their own proof anchors. Do not carry pass 2's proposed `useNoisePruning=true` into the baseline: the maxsize9 preset omits it and self-play uses `SETUP_FOR_OTHER`, whose default is false; enabling it would be a separate `[FUTURE]` experiment. Anchor: `cpp/search/searchexplorehelpers.cpp:166-169,229-263`; `cpp/search/searchresults.cpp:142-195,318-328`; `cpp/program/setup.cpp:576-578`; `cpp/command/selfplay.cpp:110`.

   verify: `rg -n 'rootDesiredPerChildVisitsCoeff|getReducedPlaySelectionWeight|amountToSubtract|amountToPrune' ref-code/lightvector-KataGo/cpp/search/searchexplorehelpers.cpp ref-code/lightvector-KataGo/cpp/search/searchresults.cpp && rg -n 'useNoisePruning' ref-code/lightvector-KataGo/cpp/program/setup.cpp && rg -n 'SETUP_FOR_OTHER' ref-code/lightvector-KataGo/cpp/command/selfplay.cpp && ! rg -n '^useNoisePruning' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg`.

7. **Canonical `arxiv-1902.10565::loss_targets_metrics`**; pass 1: same; pass 2: `freeze_search_and_auxiliary_targets` (auxiliary-loss slice); verdict **keep**. `[SOLID]` Loss assembly is a training derivation, not a self-play config task; its old b5 predecessor must become the selected runnable configuration. Anchor: `python/katago/train/metrics_pytorch.py:589-607,856-882`; `python/train.py:140-152`.

   verify: `rg -n 'policy_opt_loss_scale|loss_sum =|loss_policy_player_soft|loss_td_value|loss_ownership|loss_scorebelief' ref-code/lightvector-KataGo/python/katago/train/metrics_pytorch.py && rg -n 'soft-policy-weight-scale|value-loss-scale|td-value-loss-scales|seki-loss-scale|variance-time-loss-scale' ref-code/lightvector-KataGo/python/train.py`.

8. **Canonical `arxiv-1902.10565::score_utility_search`**; pass 1: same; pass 2: `freeze_search_and_auxiliary_targets` (score-utility slice); verdict **keep**. `[SOLID]` This is an independent search utility derivation used by self-play and gatekeeper. Anchor: `cpp/search/search.cpp:1160-1165`; `cpp/search/searchhelpers.cpp:277-278`; both maxsize9 configs at `:157-163` and `:85-88`.

   verify: `rg -n 'recentScoreCenter|dynamicScoreCenterScale|dynamicScoreUtilityFactor' ref-code/lightvector-KataGo/cpp/search/search.cpp ref-code/lightvector-KataGo/cpp/search/searchhelpers.cpp ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg ref-code/lightvector-KataGo/cpp/configs/training/gatekeeper1_maxsize9.cfg`.

9. **Canonical `arxiv-1902.10565::head_gpool_degeneracy_9x9`**; pass 1: same; pass 2: no node; verdict **keep**. `[SOLID]` It is a genuine strict-9x9 architectural consequence and remains true for the selected b7 head layout; it is not a blocker. Anchor: `python/katago/train/model_pytorch.py:492-543,2647,2711,2745,2855`.

   verify: `rg -n 'class KataGPool|class KataValueHeadGPool|mask_sum_hw_sqrt_offset|self.gpool' ref-code/lightvector-KataGo/python/katago/train/model_pytorch.py`.

10. **Canonical `arxiv-1902.10565::train_optimizer_schedule`**; pass 1: same; pass 2: no DAG node (design-only discussion); verdict **keep**. `[SOLID]` Optimizer, warm-up, SWA, precision, and attention-bound controls are load-bearing training semantics and should not depend specifically on b5. Anchor: `python/train.py:83-114,132,140-143,632-750,840-844,1046-1141`.

    verify: `rg -n 'use-adamw|use-muon|use-bf16|attn-logit-penalty-cap|torch.optim.SGD|momentum=0.9|global_step_samples.*2000000|swa-period-samples' ref-code/lightvector-KataGo/python/train.py`.

11. **Canonical `arxiv-1902.10565::selfplay_search_params`**; pass 1: same; pass 2: `assign_node_resources`; verdict **merge-into**. `[SOLID]` Retain the pass-1 id but broaden it to the measured one-node resource map; static thread arithmetic alone does not admit compliance. Anchor: `cpp/command/selfplay.cpp:359-364`; `cpp/command/gatekeeper.cpp:548-552`; `cpp/program/setup.cpp:193-203`; `cpp/program/selfplaymanager.cpp:153-156`.

    verify: `rg -n 'numGameThreads|modelLoadLoopThread|numNNServerThreadsPerModel|std::thread newThread' ref-code/lightvector-KataGo/cpp/command/selfplay.cpp ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp ref-code/lightvector-KataGo/cpp/program/setup.cpp ref-code/lightvector-KataGo/cpp/program/selfplaymanager.cpp`; runtime criterion: `ps -o nlwp= -p "$PID"` and allocated CPUs `<=24`.

12. **Canonical `arxiv-1902.10565::game_randomization_9x9`**; pass 1: same; pass 2: `author_9x9_selfplay_config` (source-policy slice); verdict **keep**. `[SOLID]` The upstream randomization behavior is evidence for, but not identical to, authoring the mission override. Anchor: `cpp/configs/training/selfplay1_maxsize9.cfg:37,45,95-108,138-142`; `cpp/program/playutils.cpp:10-65`.

    verify: `rg -n 'bSizes|bSizeRelProbs|allowRectangleProb|komiStdev|handicapProb|chosenMoveTemperature' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg && rg -n 'getDefaultMaxExtraBlack|stdevToUse' ref-code/lightvector-KataGo/cpp/program/playutils.cpp`.

13. **Canonical `arxiv-1902.10565::gating_rule`**; pass 1: same; pass 2: `author_9x9_gatekeeper_config` (rule slice); verdict **keep**. `[SOLID]` Candidate scoring/renaming/empty-baseline behavior is a reusable code fact, separate from the config-writing task. Anchor: `cpp/command/gatekeeper.cpp:108,184-188,271,398-402,579-630`; `gatekeeper1_maxsize9.cfg:20,49`.

    verify: `rg -n 'numGamesPerGating|requiredCandidateWinProp|No accepted model|Candidate won match|Moving .* to' ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp && rg -n 'numGamesPerGating|maxVisits' ref-code/lightvector-KataGo/cpp/configs/training/gatekeeper1_maxsize9.cfg`.

14. **Canonical `arxiv-1902.10565::train_resume_semantics`**; pass 1: same; pass 2: `resume_transformer_training` (semantic slice); verdict **keep**. `[SOLID]` Checkpoint selection, atomic save, restored state, and data-file tracking are source facts distinct from executing a restart test. Anchor: `python/train.py:573-623,780-796,850,1185-1281,1827-1889`.

    verify: `rg -n 'checkpoint.ckpt|checkpoint_prev|torch.save\(state_dict, path \+ ".tmp"\)|os.replace|global_step_samples|longterm_checkpoints|no_repeat_files' ref-code/lightvector-KataGo/python/train.py`.

15. **Canonical `arxiv-1902.10565::data_format_pos_len`**; pass 1: same; pass 2: `author_9x9_train_wrapper` and `audit_smoke_artifacts` (shape slices); verdict **keep**. `[SOLID]` The binary row layout and `dataBoardLen == pos_len` contract are a derivation shared by config, shuffle, audit, and budget nodes. Anchor: `cpp/dataio/trainingwrite.cpp:288-298`; `python/katago/train/data_processing_pytorch.py:89-95`; `python/selfplay/train.sh:88`.

    verify: `rg -n 'binaryInputNCHWPacked|policyTargetsNCMove|scoreDistrN|valueTargetsNCHW|qValueTargetsNCMove' ref-code/lightvector-KataGo/cpp/dataio/trainingwrite.cpp && rg -n 'assert binaryInputNCHW.shape' ref-code/lightvector-KataGo/python/katago/train/data_processing_pytorch.py && rg -n -- '-pos-len 19' ref-code/lightvector-KataGo/python/selfplay/train.sh`.

16. **Canonical `arxiv-1902.10565::training_window_shuffle`**; pass 1: same; pass 2: `shuffle_seed_window`, `shuffle_rolling_window`, and `scale_data_window` (common derivation); verdict **keep**. `[SOLID]` These pass-2 nodes reuse one window derivation; execution trials may vary parameters without duplicating it. Anchor: `python/shuffle.py:414-435,718-747,777-791`; `python/selfplay/shuffle.sh:39-54`.

    verify: `rg -n 'def compute_desired_num_rows|expand-window-per-row|taper-window-exponent|taper-window-scale|keep-target-rows|min-rows|num-processes' ref-code/lightvector-KataGo/python/shuffle.py ref-code/lightvector-KataGo/python/selfplay/shuffle.sh`.

17. **Canonical `arxiv-1902.10565::cfg_9x9_override`**; pass 1: same; pass 2: `author_9x9_selfplay_config`, `author_9x9_gatekeeper_config`, `author_9x9_train_wrapper`; verdict **keep**. `[SOLID]` One atomic mission-owned config bundle is sufficient because all three files must change together before any data is admitted. Anchor: `selfplay1_maxsize9.cfg:16,84,95-97,116,123`; `gatekeeper1_maxsize9.cfg:18,20,38-40,50,57`; `python/selfplay/train.sh:88`.

    verify: `rg -n 'dataBoardLen|numGameThreads|bSizes|bSizeRelProbs|allowRectangleProb|numSearchThreads|numNNServerThreadsPerModel' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg ref-code/lightvector-KataGo/cpp/configs/training/gatekeeper1_maxsize9.cfg && rg -n -- '-pos-len' ref-code/lightvector-KataGo/python/selfplay/train.sh`.

18. **Canonical `arxiv-1902.10565::tiny_model_export_smoke`**; pass 1: same; pass 2: `export_tiny_transformer_smoke`; verdict **split**. `[PRELIMINARY]` Keep this id for Python serialization and attention-bound checks only: b5 export succeeded even though C++ execution failed, proving export and load/run cannot remain one node. Anchor: `python/export_model_pytorch.py:33-43,57-60,119-123,408-494`.

    verify: `rg -n 'export-random-initialized-model|attn-logit-bound-limit|Writing model|transformer_attention_block|transformer_ffn_block' ref-code/lightvector-KataGo/python/export_model_pytorch.py && rg -n 'Writing model|model.bin' /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/env_build-297952.log /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/env_build-298018.log`.

19. **Canonical `arxiv-1902.10565::tiny_model_load_smoke`**; pass 1: load/run slice of `tiny_model_export_smoke`; pass 2: `load_tiny_transformer_smoke`; verdict **add-from-pass2**. `[PRELIMINARY]` C++ descriptor acceptance and actual CUDA execution need a separate gate; b7 passed benchmark and GTP once, while b5 aborted. Anchor: `cpp/neuralnet/desc.cpp:1521-1542`; `cpp/command/benchmarknn.cpp:33-119`.

    verify: `rg -n 'transformer_attention_block|transformer_ffn_block' ref-code/lightvector-KataGo/cpp/neuralnet/desc.cpp && rg -n 'batch-size|boardsize|require-exact-nnlen|iterations|json' ref-code/lightvector-KataGo/cpp/command/benchmarknn.cpp && rg -n 'benchmark.*b7|gtp genmove.*b7' /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/env_build-298018.log`.

20. **Canonical `arxiv-1902.10565::synchronous_loop_smoke`**; pass 1: same; pass 2: `run_tiny_synchronous_cycle`; verdict **split**. `[SOLID]` Retain the execution node, but make artifact validation a successor so “commands returned zero” is not conflated with correct shapes/lineage. Anchor: `python/selfplay/synchronous_loop.sh:93-116`.

    verify: `rg -n 'while true|katago gatekeeper|katago selfplay|shuffle.sh|train.sh|export_model_for_selfplay.sh' ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh`.

21. **Canonical `arxiv-1902.10565::audit_smoke_artifacts`**; pass 1: audit slice of `synchronous_loop_smoke`; pass 2: `audit_smoke_artifacts`; verdict **add-from-pass2**. `[SOLID]` NPZ shapes, checkpoint readability, exported-network execution, SGF size, and lineage form a separate empirical admission gate. Anchor: `python/shuffle.py:146-149`; `python/train.py:573-623,1852-1862`; `cpp/dataio/trainingwrite.cpp:1093-1096`.

    verify: `rg -n 'np.savez_compressed' ref-code/lightvector-KataGo/python/shuffle.py && rg -n 'torch.save|os.replace|savepathtmp|os.rename' ref-code/lightvector-KataGo/python/train.py && rg -n 'tmpFilename|FileUtils::rename' ref-code/lightvector-KataGo/cpp/dataio/trainingwrite.cpp`.

22. **Canonical `arxiv-1902.10565::loop_resume_under_walltime`**; pass 1: same; pass 2: `verify_preemption_resume`; verdict **keep**. `[SOLID]` The restart trial is distinct from static checkpoint semantics, but the pass-1 predecessor direction must be corrected: a working audited smoke loop precedes interruption testing. Anchor: `python/train.py:611-622,780-796`; `python/selfplay/shuffle.sh:33,105`; `python/selfplay/export_model_for_selfplay.sh:54-89,108`.

    verify: `rg -n 'checkpoint.ckpt|os.replace' ref-code/lightvector-KataGo/python/train.py && rg -n '\.tmp|mv ' ref-code/lightvector-KataGo/python/selfplay/shuffle.sh && rg -n '\.exported|rm -r|mv ' ref-code/lightvector-KataGo/python/selfplay/export_model_for_selfplay.sh`.

23. **Canonical `arxiv-1902.10565::selfplay_stage`**; pass 1: same; pass 2: `generate_seed_selfplay`, `generate_successor_selfplay`; verdict **keep**. `[SOLID]` The executable stage is identical; empty-model and accepted-model behavior are two verified modes/trials under one node, not duplicate derivations. Anchor: `cpp/command/selfplay.cpp:45-53,243,292-293`; `cpp/dataio/loadmodel.cpp:58,77-80`.

    verify: `rg -n 'max-games-total|models-dir|output-dir' ref-code/lightvector-KataGo/cpp/command/selfplay.cpp && rg -n 'modelName = "random"|modelFile = "/dev/null"' ref-code/lightvector-KataGo/cpp/dataio/loadmodel.cpp`.

24. **Canonical `arxiv-1902.10565::shuffle_stage`**; pass 1: same; pass 2: `shuffle_seed_window`, `shuffle_rolling_window`; verdict **keep**. `[SOLID]` Seed and rolling invocations share the same implementation and artifact contract; parameter changes belong to trials and `scale_data_window`. Anchor: `python/selfplay/shuffle.sh:39-105`; `python/shuffle.py:1079-1083,1330-1335`.

    verify: `rg -n 'expand-window-per-row|taper-window-exponent|keep-target-rows|out-dir|mv ' ref-code/lightvector-KataGo/python/selfplay/shuffle.sh && rg -n 'non-empty|json.dump|data.*npz' ref-code/lightvector-KataGo/python/shuffle.py`.

25. **Canonical `arxiv-1902.10565::train_stage`**; pass 1: same; pass 2: `train_first_network`, `resume_transformer_training`; verdict **keep**. `[SOLID]` Fresh and resumed training are two modes of the same implementation block; change its operational configuration from b5 to b7 and retain resume as a source predecessor. Anchor: `python/train.py:79-130,780-850,1422-1452`; `python/selfplay/train.sh:83-93`.

    verify: `rg -n 'pos-len|model-kind|multi-gpus|use-bf16|max-train-bucket|stop-when-train-bucket-limited' ref-code/lightvector-KataGo/python/train.py ref-code/lightvector-KataGo/python/selfplay/train.sh`.

26. **Canonical `arxiv-1902.10565::export_stage`**; pass 1: same; pass 2: `export_first_network`, `export_swa_candidate`; verdict **keep**. `[SOLID]` Both use the same exporter helper; `USEGATING=0/1` is a mode that changes the destination, not a different derivation. Anchor: `python/selfplay/export_model_for_selfplay.sh:42-90,96-121`.

    verify: `rg -n 'USEGATING|export_model_pytorch.py|use-swa|torchmodels_toexport|modelstobetested|models' ref-code/lightvector-KataGo/python/selfplay/export_model_for_selfplay.sh`.

27. **Canonical `arxiv-1902.10565::bootstrap_accepted_model`**; pass 1: bootstrap assumption inside `synchronous_loop_smoke`; pass 2: `bootstrap_accepted_model`; verdict **add-from-pass2**. `[SOLID]` Freezing the first exported network and hash is required before a successor gate or latest-vs-first match and is not equivalent to random-net self-play. Anchor: `cpp/command/gatekeeper.cpp:394-402`; `python/selfplay/export_model_for_selfplay.sh:96-120`.

    verify: `rg -n 'findLatestModel|No accepted model' ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp && rg -n 'USEGATING|models|modelstobetested' ref-code/lightvector-KataGo/python/selfplay/export_model_for_selfplay.sh`.

28. **Canonical `arxiv-1902.10565::gatekeeper_stage`**; pass 1: same; pass 2: `gate_candidate`; verdict **keep**. `[SOLID]` The pass-1 execution node already has the correct stage boundary, but must additionally depend on strict-9x9 config and an accepted baseline. Anchor: `cpp/command/gatekeeper.cpp:268-300,516-525,579-630`.

    verify: `rg -n 'accepted-models-dir|test-models-dir|required-candidate-win-prop|quit-if-no-nets-to-test|Candidate won match' ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp`.

29. **Canonical `arxiv-1902.10565::count_gatekeeper_acceptances`**; pass 1: count slice of `eval_improvement`; pass 2: `count_gatekeeper_acceptances`; verdict **split**. `[SOLID]` Directory/log reconciliation is an empirical result, distinct from match statistics and the final conclusion. Anchor: `cpp/command/gatekeeper.cpp:579-630`.

    verify: `rg -n 'Candidate won match|accepting candidate|rejecting candidate|moveModel' ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp`; execution criterion: accepted directories beyond the frozen baseline equal parsed accept decisions.

30. **Canonical `arxiv-1902.10565::match_latest_against_first`**; pass 1: match slice of `eval_improvement`; pass 2: `match_latest_against_first`; verdict **split**. `[SOLID]` A fixed, color-balanced match and interval calculation is a separate statistical evidence block. Anchor: `cpp/main.cpp:43,103-104`; `cpp/configs/match_example.cfg:1-19`.

    verify: `rg -n 'match :|MainCmds::match' ref-code/lightvector-KataGo/cpp/main.cpp && rg -n 'katago match|fixed numbers of visits' ref-code/lightvector-KataGo/cpp/configs/match_example.cfg`.

31. **Canonical `arxiv-1902.10565::eval_improvement`**; pass 1: same; pass 2: `declare_selfplay_improvement`; verdict **split**. `[SOLID]` Retain the pass-1 id only as the terminal conclusion depending on acceptance reconciliation and the fixed match; do not embed either experiment in it. Anchor: no single mirror line proves improvement; `[OPEN]` until both measurements exist.

    verify: require nonzero accepted successors plus reported W/L/D/N, score, Elo, 95% interval, network hashes, 9x9 audit, visits, hardware, and GPU-hours; otherwise emit “not demonstrated.”

32. **Canonical `arxiv-1902.10565::data_budget`**; pass 1: same; pass 2: `enforce_storage_budget`; verdict **keep**. `[SOLID]` Keep the pass-1 id but adopt pass 2's whole-mission-root scope and recovery reserve; the old `BASEDIR`-only cap omits environment/build bytes. Anchor: `python/shuffle.py:39-47,476-480,790`; `python/train.py:1889`; `python/selfplay/cleanup_old_dirs.py:3`.

    verify: `rg -n 'UNCOMPRESSED_BYTES_PER_ROW|COMPRESSED_FRACTION|Assumes 19x19' ref-code/lightvector-KataGo/python/shuffle.py && rg -n 'longterm_checkpoints' ref-code/lightvector-KataGo/python/train.py && rg -n 'most recent 3' ref-code/lightvector-KataGo/python/selfplay/cleanup_old_dirs.py`; runtime: `du -sb "$MISSION_ROOT"; df -B1 "$MISSION_ROOT"`.

33. **Canonical `arxiv-1902.10565::measure_stage_throughput`**; pass 1: measurement clauses inside `selfplay_stage`, `train_stage`, and `data_budget`; pass 2: `measure_stage_throughput`; verdict **add-from-pass2**. `[SOLID]` A common profile record must precede every data/search/network/GPU scaling decision. Anchor: `cpp/command/benchmarknn.cpp:33-202`; stage-specific runtime metrics are `[OPEN]`.

    verify: `rg -n 'benchmarknn|iterations|batch-size|boardsize|json|timed iterations' ref-code/lightvector-KataGo/cpp/command/benchmarknn.cpp`; record per-stage elapsed time, games/rows/samples per second, GPU duty, peak VRAM/RAM, threads, and bytes/row.

34. **Canonical `arxiv-1902.10565::scale_data_window`**; pass 1: data-window slice of `scale_up`; pass 2: `scale_data_window`; verdict **split**. `[SOLID]` Data reuse/window growth has its own controlled-approximation gate and must not be coupled to search or architecture changes. Anchor: `python/shuffle.py:414-435`; `python/train.py:121,1254-1257`.

    verify: `rg -n 'def compute_desired_num_rows' ref-code/lightvector-KataGo/python/shuffle.py && rg -n 'max-train-bucket-per-new-data|train_bucket_level|new_row_count' ref-code/lightvector-KataGo/python/train.py`.

35. **Canonical `arxiv-1902.10565::scale_search_budget`**; pass 1: search slice of `scale_up`; pass 2: `scale_search_budget`; verdict **split**. `[SOLID]` Visits should advance independently after throughput/data gates while target semantics remain fixed. Anchor: `selfplay1_maxsize9.cfg:60-62,115,141-148`.

    verify: `rg -n 'cheapSearchProb|cheapSearchVisits|cheapSearchTargetWeight|maxVisits|chosenMoveSubtract|chosenMovePrune|rootDesiredPerChildVisitsCoeff' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg`.

36. **Canonical `arxiv-1902.10565::scale_up`**; pass 1: same; pass 2: `scale_transformer_family`; verdict **split**. `[PRELIMINARY]` Retain this id only for fresh-run architecture scaling. With b7 now the start, its first candidate is b8; b5 is not a scale baseline for the CUDA loop. Anchor: `modelconfigs.py:1008-1021,1057-1070,1453-1466,1887-1895`.

    verify: `rg -n 'b7c96h3tfrs|b8c96h3tfrs|b14c192h6tfrs' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py`; each candidate must pass export/load, memory, cycle-time, and Elo/GPU-hour gates in a fresh run.

## 2. Missing nodes in both passes

1. **Propose `arxiv-1902.10565::cuda_arch_sm100_gate`**, predecessors: `build_cuda_backend`. `[PRELIMINARY]` Both DAGs buried a load-bearing build mutation inside environment prose. CUDA 12.8 selects an architecture list that omits 100 at `cpp/CMakeLists.txt:761`; job 298018 patched that line, rebuilt, and found sm_100 SASS. The gate must preserve the patch as a run-local diff and prove the binary contains the target image; this does not establish network compatibility.

   verify: `rg -n 'CMAKE_CUDA_ARCHITECTURES' ref-code/lightvector-KataGo/cpp/CMakeLists.txt && cuobjdump --list-elf "$KATAGO_BIN" | rg 'sm_100' && test -s "$RUN_MANIFEST_DIR/cmake-sm100.patch"`.

2. **Propose `arxiv-1902.10565::cuda_ffn_backend_compatibility`**, predecessors: `env_build`, `cuda_arch_sm100_gate`. `[PRELIMINARY] [OPEN]` The leading proximate explanation is exact: b5 maps `ffng` to `use_swiglu=False`, and the CUDA backend throws on non-SwiGLU FFN; b7 maps `ffnsg` to `use_swiglu=True`. Causal closure still requires rerunning both exports on the same patched binary because job 297952 used b5 before the sm_100 patch and job 298018 used b7 after it.

   verify: `rg -n 'b5c48h3tfr|b7c96h3tfrs|ffng|ffnsg' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py ref-code/lightvector-KataGo/python/katago/train/model_pytorch.py && rg -n 'if\(!useSwiGLU\)|Non-SwiGLU transformer FFN' ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc`; controlled criterion: with one patched binary and identical 9x9 benchmark/GTP config, b5 must reproduce the exact diagnostic and b7 must exit 0, with both Torch forward/backward controls exiting 0.

3. **Propose `arxiv-1902.10565::loop_failure_circuit_breaker`**, predecessors: `synchronous_loop_smoke`, `cuda_ffn_backend_compatibility`. `[HOLE]` The upstream loop exits on any deterministic stage error and an outer `afterany` resubmission can repeat forever; neither DAG admits the pass-1 design's three-strike stop as a node. Anchor: `python/selfplay/synchronous_loop.sh:1-2,93-116`; circuit-breaker implementation is `[OPEN]`.

   verify: `head -n 2 ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh && rg -n 'while true|gatekeeper|selfplay|shuffle.sh|train.sh|export_model_for_selfplay.sh' ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh`; inject the same harmless nonzero stage exit three times and require no fourth submission plus a recorded error-ledger-ready signature.

## 3. Edge corrections to pass 1

The recurrent production loop is a state machine, but the unified artifact must remain acyclic. The corrected DAG therefore admits each reusable stage once, records seed/successor and gating modes as trials, and uses edges for capability/evidence dependencies rather than drawing `gatekeeper_stage -> selfplay_stage` back-edges. `[SOLID]`

verify: `rg -n 'while true|katago gatekeeper|katago selfplay|shuffle.sh|train.sh|export_model_for_selfplay.sh' ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh`.

1. **Split `env_build`.** `[SOLID]` Replace the single root with `freeze_run_contract -> env_build -> build_cuda_backend -> cuda_arch_sm100_gate`; add `env_build,cuda_arch_sm100_gate -> cuda_ffn_backend_compatibility -> select_transformer_ladder`.

   verify: `rg -n 'USE_BACKEND STREQUAL "CUDA"|CMAKE_CUDA_ARCHITECTURES|find_path\(CUDNN|find_library\(CUDNN' ref-code/lightvector-KataGo/cpp/CMakeLists.txt && rg -n 'Non-SwiGLU transformer FFN' ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc`.

2. **Replace b5-only architecture edges.** `[PRELIMINARY]` Remove `transformer_trunk_b5c48h3tfr -> {loss_targets_metrics,head_gpool_degeneracy_9x9,train_optimizer_schedule,tiny_model_export_smoke,train_stage,scale_up}`. Add `select_transformer_ladder -> {loss_targets_metrics,head_gpool_degeneracy_9x9,tiny_model_export_smoke,train_stage,scale_up}`; `train_optimizer_schedule` is a source root and needs no network predecessor.

   verify: `rg -n 'b5c48h3tfr|b7c96h3tfrs|no swiglu' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py && rg -n 'Non-SwiGLU transformer FFN' ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc`.

3. **Split export from C++ load/run.** `[SOLID]` Change `env_build,transformer_trunk_b5c48h3tfr,cfg_9x9_override -> tiny_model_export_smoke` to `env_build,select_transformer_ladder -> tiny_model_export_smoke` and add `build_cuda_backend,cuda_arch_sm100_gate,tiny_model_export_smoke -> tiny_model_load_smoke`; config becomes a load-smoke input only if benchmark/GTP uses it.

   verify: `rg -n 'export-random-initialized-model|transformer_ffn_block' ref-code/lightvector-KataGo/python/export_model_pytorch.py && rg -n 'transformer_ffn_block' ref-code/lightvector-KataGo/cpp/neuralnet/desc.cpp`.

4. **Reverse the smoke/resume dependency.** `[SOLID]` Remove `loop_resume_under_walltime -> synchronous_loop_smoke`. Add `tiny_model_load_smoke,cfg_9x9_override,data_budget,selfplay_search_params,playout_cap_randomization,root_explore_and_target_pruning,loss_targets_metrics,train_optimizer_schedule -> synchronous_loop_smoke -> audit_smoke_artifacts -> loop_failure_circuit_breaker -> loop_resume_under_walltime`, with `train_resume_semantics -> loop_resume_under_walltime` retained.

   verify: `rg -n 'while true|gatekeeper|selfplay|shuffle.sh|train.sh|export_model_for_selfplay.sh' ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh && rg -n 'checkpoint.ckpt|os.replace' ref-code/lightvector-KataGo/python/train.py`.

5. **Move the storage guard before compute.** `[SOLID]` Remove `synchronous_loop_smoke -> data_budget`; add `freeze_run_contract,data_format_pos_len -> data_budget -> synchronous_loop_smoke`. Put post-run calibration under `measure_stage_throughput -> scale_data_window`, avoiding a cycle back into the guard.

   verify: `rg -n 'UNCOMPRESSED_BYTES_PER_ROW|COMPRESSED_FRACTION|Assumes 19x19' ref-code/lightvector-KataGo/python/shuffle.py`; runtime guard: `test "$(du -sb "$MISSION_ROOT" | awk '{print $1}')" -lt 193273528320` before starting a new cycle.

6. **Correct production self-play prerequisites.** `[PRELIMINARY]` Add `audit_smoke_artifacts,cfg_9x9_override,select_transformer_ladder -> selfplay_stage`; retain the search-method predecessors. Record empty-model seed and accepted-model successor as separate trials rather than adding a cyclic baseline predecessor.

   verify: `rg -n 'models-dir|max-games-total' ref-code/lightvector-KataGo/cpp/command/selfplay.cpp && rg -n 'modelName = "random"|findLatestModel' ref-code/lightvector-KataGo/cpp/dataio/loadmodel.cpp`.

7. **Make every data stage obey the guard/config.** `[SOLID]` Add `data_budget -> {shuffle_stage,train_stage,export_stage}` and `cfg_9x9_override -> train_stage`; replace the b5 predecessor of `train_stage` with `select_transformer_ladder`.

   verify: `rg -n 'dataBoardLen' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg && rg -n -- '-pos-len 19' ref-code/lightvector-KataGo/python/selfplay/train.sh && rg -n 'max-train-bucket-size' ref-code/lightvector-KataGo/python/train.py`.

8. **Insert the accepted-baseline transition.** `[SOLID]` Add `export_stage -> bootstrap_accepted_model`; add `bootstrap_accepted_model,cfg_9x9_override,export_stage,gating_rule -> gatekeeper_stage`. The first export uses `USEGATING=0`; later candidates use `1`.

   verify: `rg -n 'USEGATING|models|modelstobetested' ref-code/lightvector-KataGo/python/selfplay/export_model_for_selfplay.sh && rg -n 'No accepted model|acceptedModelsDir' ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp`.

9. **Split evaluation evidence.** `[SOLID]` Replace `gatekeeper_stage -> eval_improvement` with `gatekeeper_stage -> count_gatekeeper_acceptances`, `bootstrap_accepted_model,gatekeeper_stage -> match_latest_against_first`, and both new nodes `-> eval_improvement`.

   verify: `rg -n 'Candidate won match|accepting candidate' ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp && rg -n 'MainCmds::match' ref-code/lightvector-KataGo/cpp/main.cpp`.

10. **Split scale-up.** `[SOLID]` Replace the broad pass-1 fan-in with `gatekeeper_stage,loop_resume_under_walltime -> measure_stage_throughput -> scale_data_window -> scale_search_budget`; make `eval_improvement,measure_stage_throughput,scale_data_window,scale_search_budget,select_transformer_ladder,data_budget -> scale_up`.

    verify: `rg -n 'def compute_desired_num_rows' ref-code/lightvector-KataGo/python/shuffle.py && rg -n 'maxVisits|cheapSearchVisits' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg && rg -n 'b7c96h3tfrs|b8c96h3tfrs' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py`.

11. **Keep export safety attached to export/resume.** `[SOLID]` Add `loop_failure_circuit_breaker -> export_stage`; retain `train_stage,tiny_model_export_smoke -> export_stage` and make the attention-logit refusal an explicit failed trial rather than an implicit resubmission trigger.

    verify: `rg -n 'attn-logit-bound-limit|ignore-attn-logit-bound' ref-code/lightvector-KataGo/python/export_model_pytorch.py && rg -n '\.exported|rm -r|mv ' ref-code/lightvector-KataGo/python/selfplay/export_model_for_selfplay.sh`.

## 4. Design conflicts and recommendations

### GPU split

Pass 1 chooses one GPU and 24 CPUs with sequential stage time-sharing; pass 2 starts with two GPUs and proposes a later 3:1 asynchronous four-GPU layout. `[PRELIMINARY]` Recommend one GPU for smoke and first b7 pilot, b300 preferred and b200 fallback, because the only execution evidence is single-GPU B200 and the small 9x9 network may be CPU/batching limited. Permit two GPUs only after `measure_stage_throughput` proves higher end-to-end rows/GPU-hour or shorter safe cycle time. Keep the four-GPU asynchronous split `[FUTURE]` until an explicit concurrent-state/resume design exists.

verify: `rg -n 'numGameThreads|numNNServerThreadsPerModel|cudaDeviceToUse' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg && rg -n 'multi-gpus' ref-code/lightvector-KataGo/python/train.py`; runtime compare one- versus two-GPU complete pilot manifests under identical data/search settings.

### Starting configuration

Both designs start with b5. `[PRELIMINARY]` That is no longer admissible for a CUDA full loop: b5 is `ffng`, its export and Torch path pass, but C++ CUDA aborts; b7 is `ffnsg` and passed benchmark/GTP/Torch after the sm_100 build. Start smoke and first production with b7, retain b5 as a negative regression case, scale next to b8, and defer b14. Amend the later ledger views for the b5 assumptions/claims rather than treating this review as admission.

verify: `rg -n 'b5c48h3tfr|b7c96h3tfrs|b8c96h3tfrs|no swiglu' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py && rg -n 'Non-SwiGLU transformer FFN' ref-code/lightvector-KataGo/cpp/neuralnet/cudaandrocmbackend.inc /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/gtp_logs/*.log`.

### Thread counts

Pass 1 proposes self-play 18, gatekeeper 20, shuffle 8, and train OMP 4; pass 2 proposes two-GPU self-play 16, gatekeeper 12, shuffle 8, and train OMP 8. `[PRELIMINARY]` For the one-GPU start use self-play 18, gatekeeper **18** (not 20), shuffle 8, and `OMP_NUM_THREADS=MKL_NUM_THREADS=4`. Gatekeeper has game threads, two networks' server threads, a data-write thread, and the main thread, so pass 1's “20+2+1=23” omits at least one live thread from its prose. Admit counts only from `ps -o nlwp`, `sstat`, and the 24-CPU allocation; tune downward if auxiliary library threads appear.

verify: `rg -n 'numGameThreads|dataWriteLoop|threads.reserve' ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp && rg -n 'numNNServerThreadsPerModel' ref-code/lightvector-KataGo/cpp/program/setup.cpp && rg -n 'modelLoadLoopThread' ref-code/lightvector-KataGo/cpp/command/selfplay.cpp`; runtime: `ps -o pid=,nlwp=,comm= -p "$PID"`.

### Data windows

Pass 1's production `keep=300000` with a `500000` train cap violates the shipped comment that kept rows must exceed the cap; pass 2's 500-game/50k-min bootstrap is inconsistent with the current ~22 rows/game planning estimate unless games are raised. `[PRELIMINARY]` Use pass 2's tiny disposable smoke scale (4 games, min 1, keep 256, 64 samples/epoch, cap 128), then a 500-game pilot with min 10k, keep 300k, taper scale 50k, 20k samples/epoch, maximum reuse 4, and cap 200k. These are operating hypotheses. After measured rows/game and two clean cycles, scale one axis at a time toward min 100k, keep 600k, 100k samples/epoch, cap 500k; always require `keep > cap`.

verify: `rg -n 'SHUFFLE_MINROWS|MAX_TRAIN_SAMPLES_PER_CYCLE|SHUFFLE_KEEPROWS|Needs to be larger' ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh && rg -n 'keep-target-rows|min-rows|taper-window-scale' ref-code/lightvector-KataGo/python/shuffle.py`; after each cycle compute actual rows/game and `train_bucket_used/new_rows`.

### Scratch budget

Pass 1 uses a decimal 200 GB `BASEDIR` cap and automatic checkpoint/rejected-network pruning but excludes the environment/build; pass 2 uses 200 GiB over the mission root, stops new cycles at 180 GiB, reserves 20 GiB, and does not delete automatically. `[SOLID]` Adopt the pass-2 scope and binary units: total mission root `<=200 GiB`, no new stage/cycle at `>=180 GiB`, 20 GiB recovery reserve. Add pass 1's bounded retention only through an explicit logged policy that protects the frozen baseline, latest accepted network, current/previous checkpoints, and evidence; include raw self-play, shuffles, environment, build, caches, logs, and temp shards in every measurement.

verify: `rg -n 'Assumes 19x19|COMPRESSED_FRACTION|UNCOMPRESSED_BYTES_PER_ROW' ref-code/lightvector-KataGo/python/shuffle.py && rg -n 'longterm_checkpoints' ref-code/lightvector-KataGo/python/train.py && rg -n 'most recent 3' ref-code/lightvector-KataGo/python/selfplay/cleanup_old_dirs.py`; runtime: `du -sb "$MISSION_ROOT"; df -B1 "$MISSION_ROOT"` before and after every stage.

## 5. Proposed final merged node list (39 nodes)

Identical stage derivations are collapsed; seed/successor and first/resumed behavior are trials under the shared stage node. Status is the proposed ledger status, while the bracketed tag is this review's judgment of the node boundary/evidence currently available. `[SOLID]`

verify: `test "$(awk '/^## 5\./{f=1;next} f && /^[0-9]+\. \*\*\`arxiv-1902\.10565::/{n++} END{print n+0}' results/ktg/paper_1902.10565/evidence/decomposition/dag_review_b.md)" -le 40 && test "$(rg -c '^2[3-9]\. |^3[0-2]\. ' results/ktg/paper_1902.10565/evidence/decomposition/dag_review_b.md)" -gt 0`.

1. **`arxiv-1902.10565::freeze_run_contract` |** Freeze one-node paths, b300→b200 placement, `<=4` GPUs, `<=24` CPUs/job, and `<=72 h` | predecessors: — | evidence: literature grounding + empirical measurement | status: preliminary `[PRELIMINARY]`.

   verify: `scontrol show job "$SLURM_JOB_ID"` plus the run manifest must satisfy all limits and resolve every path.

2. **`arxiv-1902.10565::env_build` |** Provision and pin Python, Torch CUDA 12.8, cuDNN 9.x, NumPy, packaging, and psutil | predecessors: `freeze_run_contract` | evidence: unchecked external step | status: preliminary `[PRELIMINARY]`.

   verify: `python -c 'import torch; assert torch.__version__=="2.11.0+cu128"; assert torch.version.cuda=="12.8"; assert torch.cuda.is_available(); assert torch.backends.cudnn.version()>=90800'`.

3. **`arxiv-1902.10565::build_cuda_backend` |** Configure and compile the v1.18.2 CUDA backend against the pinned cuDNN and required libzip | predecessors: `env_build` | evidence: numerical simulation | status: preliminary `[PRELIMINARY]`.

   verify: `"$KATAGO_BIN" version && "$KATAGO_BIN" runtests`; also `ldd "$KATAGO_BIN" | rg 'libcudnn.so.9|libzip'`.

4. **`arxiv-1902.10565::cuda_arch_sm100_gate` |** Preserve the run-local CUDA-12.8 sm_100 patch, rebuild, and prove sm_100 SASS | predecessors: `build_cuda_backend` | evidence: numerical simulation | status: preliminary `[PRELIMINARY]`.

   verify: `cuobjdump --list-elf "$KATAGO_BIN" | rg 'sm_100' && test -s "$RUN_MANIFEST_DIR/cmake-sm100.patch"`.

5. **`arxiv-1902.10565::cuda_ffn_backend_compatibility` |** Isolate the b5 non-SwiGLU C++ abort from architecture/toolchain changes and confirm the runnable FFN family | predecessors: `env_build`, `cuda_arch_sm100_gate` | evidence: counterexample + numerical simulation | status: preliminary `[PRELIMINARY] [OPEN]`.

   verify: use the same patched binary to run identical b5 and b7 export, `benchmarknn`, GTP genmove, and Torch forward/backward controls; require the source diagnostic and record all exits/logs.

6. **`arxiv-1902.10565::select_transformer_ladder` |** Select b7 as start, b8 as first scale candidate, b14 as future; retain b5 only as a negative fixture | predecessors: `cuda_ffn_backend_compatibility` | evidence: controlled approximation | status: preliminary `[PRELIMINARY]`.

   verify: `rg -n 'b5c48h3tfr|b7c96h3tfrs|b8c96h3tfrs|b14c192h6tfrs' ref-code/lightvector-KataGo/python/katago/train/modelconfigs.py` plus per-candidate export/load results.

7. **`arxiv-1902.10565::playout_cap_randomization` |** Fix cheap/full search sampling and target weighting | predecessors: — | evidence: literature grounding | status: preliminary `[SOLID]`.

   verify: `rg -n 'cheapSearchProb|cheapSearchVisits|cheapSearchTargetWeight|targetWeight \*=' ref-code/lightvector-KataGo/cpp/program/play.cpp ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg`.

8. **`arxiv-1902.10565::root_explore_and_target_pruning` |** Fix forced-root exploration and target-pruning semantics | predecessors: — | evidence: literature grounding | status: preliminary `[SOLID]`.

   verify: `rg -n 'rootDesiredPerChildVisitsCoeff|getReducedPlaySelectionWeight|amountToPrune' ref-code/lightvector-KataGo/cpp/search/searchexplorehelpers.cpp ref-code/lightvector-KataGo/cpp/search/searchresults.cpp`.

9. **`arxiv-1902.10565::loss_targets_metrics` |** Freeze version-17 head targets, weights, and finite-loss observables for the selected configuration | predecessors: `select_transformer_ladder` | evidence: literature grounding | status: preliminary `[SOLID]`.

   verify: `rg -n 'loss_sum =|policy_opt_loss_scale|loss_td_value|loss_ownership|loss_scorebelief' ref-code/lightvector-KataGo/python/katago/train/metrics_pytorch.py`.

10. **`arxiv-1902.10565::score_utility_search` |** Freeze current score-utility center/scale/factors | predecessors: — | evidence: literature grounding | status: preliminary `[SOLID]`.

    verify: `rg -n 'recentScoreCenter|dynamicScoreCenterScale|dynamicScoreUtilityFactor' ref-code/lightvector-KataGo/cpp/search/search.cpp ref-code/lightvector-KataGo/cpp/search/searchhelpers.cpp`.

11. **`arxiv-1902.10565::head_gpool_degeneracy_9x9` |** Record strict-9x9 pooling collinearity and retain compatible constants | predecessors: `select_transformer_ladder` | evidence: symbolic derivation | status: preliminary `[SOLID]`.

    verify: run the existing 9x9 pooling probe and require `pool2=-0.5*pool1`, value `pool3=0.15*pool1`; source: `model_pytorch.py:492-543`.

12. **`arxiv-1902.10565::train_optimizer_schedule` |** Freeze optimizer, warm-up, SWA, bf16, thread, and attention-bound policy | predecessors: — | evidence: literature grounding | status: preliminary `[SOLID]`.

    verify: `rg -n 'torch.optim.SGD|momentum=0.9|global_step_samples.*2000000|swa-period-samples|attn-logit-penalty-cap' ref-code/lightvector-KataGo/python/train.py`.

13. **`arxiv-1902.10565::selfplay_search_params` |** Define one-node GPU mapping and conservative per-stage thread/process budgets | predecessors: `freeze_run_contract` | evidence: controlled approximation + empirical measurement | status: hypothesis `[HOLE]`.

    verify: during every stage require allocation `<=24` CPUs, `ps -o nlwp` within the declared plan, GPUs `<=4`, and no unintended device use.

14. **`arxiv-1902.10565::game_randomization_9x9` |** Record retained 9x9 game-init, komi, handicap, fork, and temperature behavior | predecessors: — | evidence: literature grounding | status: preliminary `[SOLID]`.

    verify: `rg -n 'bSizes|allowRectangleProb|komiStdev|handicapProb|chosenMoveTemperature' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg`.

15. **`arxiv-1902.10565::gating_rule` |** Record 200-game/0.5 scoring, move destinations, and empty-baseline behavior | predecessors: — | evidence: literature grounding | status: preliminary `[SOLID]`.

    verify: `rg -n 'numGamesPerGating|requiredCandidateWinProp|No accepted model|Candidate won match' ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp`.

16. **`arxiv-1902.10565::train_resume_semantics` |** Record atomic checkpoints, restored optimizer/SWA/global counters, and no-repeat data state | predecessors: — | evidence: literature grounding | status: preliminary `[SOLID]`.

    verify: `rg -n 'checkpoint.ckpt|torch.save.*\.tmp|os.replace|global_step_samples|no_repeat_files' ref-code/lightvector-KataGo/python/train.py`.

17. **`arxiv-1902.10565::data_format_pos_len` |** Define the pos_len-9 row layout and dataBoardLen/pos_len equality | predecessors: — | evidence: symbolic derivation | status: preliminary `[SOLID]`.

    verify: load a raw NPZ and assert spatial length 81, policy length 82, and expected array widths; run the `data_processing_pytorch.py:91` assertion at `pos_len=9`.

18. **`arxiv-1902.10565::training_window_shuffle` |** Define the rolling-window formula, keep/min/taper controls, and output contract | predecessors: `data_format_pos_len` | evidence: symbolic derivation | status: preliminary `[SOLID]`.

    verify: `rg -n 'def compute_desired_num_rows|keep-target-rows|taper-window|expand-window-per-row' ref-code/lightvector-KataGo/python/shuffle.py`.

19. **`arxiv-1902.10565::cfg_9x9_override` |** Author and lint the strict self-play, gatekeeper, and train-wrapper bundle | predecessors: `freeze_run_contract`, `selfplay_search_params`, `game_randomization_9x9`, `gating_rule`, `data_format_pos_len` | evidence: exact proof + numerical simulation | status: hypothesis `[HOLE]`.

    verify: parse effective configs and assert `dataBoardLen=9`, only `bSizes=9`, rectangles off, intended thread counts, and exactly one `-pos-len 9`; require only `SZ[9]` in smoke SGFs.

20. **`arxiv-1902.10565::data_budget` |** Enforce 180-GiB start/200-GiB total whole-root guards and protected retention | predecessors: `freeze_run_contract`, `data_format_pos_len` | evidence: dimensional consistency + empirical measurement | status: hypothesis `[HOLE]`.

    verify: `du -sb "$MISSION_ROOT"; df -B1 "$MISSION_ROOT"` before/after every stage; abort starts at `>=193273528320` bytes and never exceed `214748364800`.

21. **`arxiv-1902.10565::tiny_model_export_smoke` |** Export random b7, check block serialization and attention-logit bound | predecessors: `env_build`, `select_transformer_ladder` | evidence: numerical simulation | status: preliminary `[PRELIMINARY]`.

    verify: run `export_model_pytorch.py -export-random-initialized-model b7c96h3tfrs ...`; require nonempty `model.bin`, metadata/log, and only supported transformer block kinds.

22. **`arxiv-1902.10565::tiny_model_load_smoke` |** Load and execute exported b7 through C++ benchmark and 9x9 GTP | predecessors: `cuda_arch_sm100_gate`, `tiny_model_export_smoke` | evidence: numerical simulation | status: preliminary `[PRELIMINARY]`.

    verify: `"$KATAGO_BIN" benchmarknn -model "$MODEL" -config "$CFG" -boardsize 9 -require-exact-nnlen -batch-size 2 -warmup 1 -iterations 2 -json` plus a 9x9 GTP genmove, both exit 0.

23. **`arxiv-1902.10565::synchronous_loop_smoke` |** Run one finite disposable gatekeeper→self-play→shuffle→train→export cycle with b7 | predecessors: `tiny_model_load_smoke`, `cfg_9x9_override`, `data_budget`, `playout_cap_randomization`, `root_explore_and_target_pruning`, `loss_targets_metrics`, `train_optimizer_schedule`, `selfplay_search_params` | evidence: numerical simulation | status: hypothesis `[HOLE]`.

    verify: one bounded job returns five zero stage exits and produces raw data, shuffle, checkpoint, and export without NaN/OOM or repository data writes.

24. **`arxiv-1902.10565::audit_smoke_artifacts` |** Check 9x9 shapes/SGFs, checkpoint state, export load, and artifact lineage | predecessors: `synchronous_loop_smoke` | evidence: empirical measurement | status: hypothesis `[HOLE]`.

    verify: assert NPZ spatial 81/policy 82, checkpoint `pos_len=9`, all SGFs `SZ[9]`, model load exit 0, and manifest hashes connect raw→shuffle→checkpoint→export.

25. **`arxiv-1902.10565::loop_failure_circuit_breaker` |** Stop an outer resubmission chain after three identical deterministic failures | predecessors: `synchronous_loop_smoke`, `cuda_ffn_backend_compatibility` | evidence: controlled failure injection | status: hypothesis `[HOLE]`.

    verify: inject the same nonzero stage exit three times; require no fourth submission and one complete expected/observed/signature/fix-hypothesis record.

26. **`arxiv-1902.10565::loop_resume_under_walltime` |** Prove signal-safe checkpoint/restart and close shuffle/export orphan windows under `<72 h` jobs | predecessors: `audit_smoke_artifacts`, `loop_failure_circuit_breaker`, `train_resume_semantics` | evidence: empirical measurement | status: hypothesis `[HOLE]`.

    verify: interrupt smoke during train and export, restart the same root, and require monotonic samples/SWA, no corrupt checkpoint, no duplicate export, no selected `.tmp`, and no orphan `.exported` marker.

27. **`arxiv-1902.10565::selfplay_stage` |** Generate strict-9x9 seed and successor data under the same bounded executable stage | predecessors: `audit_smoke_artifacts`, `cfg_9x9_override`, `select_transformer_ladder`, `playout_cap_randomization`, `root_explore_and_target_pruning`, `score_utility_search` | evidence: numerical simulation + empirical measurement | status: hypothesis `[HOLE]`.

    verify: bounded self-play exits 0; record network name, games/hour, rows/game, invalid/aborted count, bytes/game, threads, GPU duty, and only `SZ[9]`.

28. **`arxiv-1902.10565::shuffle_stage` |** Materialize atomic seed/rolling windows at pos_len 9 | predecessors: `selfplay_stage`, `training_window_shuffle`, `data_format_pos_len`, `data_budget` | evidence: numerical simulation | status: hypothesis `[HOLE]`.

    verify: shuffle exits 0, final directory is atomic/nonempty, JSON row range advances, shapes are 9x9, and kept rows exceed the train cap.

29. **`arxiv-1902.10565::train_stage` |** Train/resume b7 with finite losses, bounded reuse, checkpoints, and export-ready SWA | predecessors: `shuffle_stage`, `select_transformer_ladder`, `loss_targets_metrics`, `train_resume_semantics`, `train_optimizer_schedule`, `cfg_9x9_override`, `data_budget` | evidence: numerical simulation + empirical measurement | status: hypothesis `[HOLE]`.

    verify: train exits at its bound, all loss terms are finite, global samples rise, checkpoint/SWA exist, `pos_len=9`, and actual threads/resources remain within contract.

30. **`arxiv-1902.10565::export_stage` |** Export first accepted or gated SWA network safely with current helper | predecessors: `train_stage`, `tiny_model_export_smoke`, `data_budget`, `loop_failure_circuit_breaker` | evidence: numerical simulation | status: hypothesis `[HOLE]`.

    verify: exporter exit 0 yields exactly one uniquely named loadable `model.bin.gz` with matching metadata/checkpoint and no orphan marker; attention-bound refusal is recorded as failure.

31. **`arxiv-1902.10565::bootstrap_accepted_model` |** Freeze the first exported b7 network name/hash as the run baseline | predecessors: `export_stage` | evidence: exact proof | status: hypothesis `[HOLE]`.

    verify: `models/` contains exactly the baseline before gating, `modelstobetested/` is empty, and manifest SHA-256 matches the on-disk export.

32. **`arxiv-1902.10565::gatekeeper_stage` |** Test later candidates for 200 strict-9x9 games and move each exactly once | predecessors: `export_stage`, `bootstrap_accepted_model`, `gating_rule`, `cfg_9x9_override` | evidence: empirical measurement | status: hypothesis `[HOLE]`.

    verify: each candidate ends in accepted or rejected, all 200 attributable games are `SZ[9]`, score arithmetic matches logs, and the process exits 0.

33. **`arxiv-1902.10565::measure_stage_throughput` |** Profile time, throughput, memory, threads, disk, and GPU duty per stage/node type | predecessors: `gatekeeper_stage`, `loop_resume_under_walltime` | evidence: empirical measurement | status: hypothesis `[HOLE]`.

    verify: emit one complete machine-readable record per stage for at least a full pilot cycle; no extrapolated cycle may exceed 60 h.

34. **`arxiv-1902.10565::scale_data_window` |** Increase games/window/reuse only from measured row and storage rates | predecessors: `measure_stage_throughput`, `data_budget`, `training_window_shuffle` | evidence: controlled approximation | status: hypothesis `[HOLE]`.

    verify: two artifact-complete cycles per change, reuse `<=4`, kept rows greater than train cap, no-data wait `<10%`, and projected pre-cycle disk `<180 GiB`.

35. **`arxiv-1902.10565::scale_search_budget` |** Raise visits one axis at a time without changing target coefficients | predecessors: `scale_data_window` | evidence: controlled approximation | status: hypothesis `[HOLE]`.

    verify: for 128/32→300/64→600/100, record games/hour and require projected cycle `<=60 h`, stable losses/invalid games, and no fixed-budget evaluation regression.

36. **`arxiv-1902.10565::count_gatekeeper_acceptances` |** Reconcile accepted successors beyond the frozen baseline | predecessors: `gatekeeper_stage` | evidence: empirical measurement | status: hypothesis `[HOLE]`.

    verify: accepted-directory count minus one equals parsed accept decisions; report attempts, accepts, rejects, and fraction.

37. **`arxiv-1902.10565::match_latest_against_first` |** Run and analyze the fixed 400-game color-balanced 9x9 baseline match | predecessors: `bootstrap_accepted_model`, `gatekeeper_stage` | evidence: statistical inference | status: hypothesis `[HOLE]`.

    verify: report hashes, W/L/D/N, `p=(W+0.5D)/N`, `Elo=400*log10(p/(1-p))`, and a 95% interval under identical 150-visit settings.

38. **`arxiv-1902.10565::eval_improvement` |** Declare improvement only from acceptance plus fixed-match evidence | predecessors: `count_gatekeeper_acceptances`, `match_latest_against_first` | evidence: statistical inference | status: hypothesis `[HOLE]`.

    verify: require at least one accepted successor and positive point Elo; call it statistically supported only if the 95% interval excludes zero, else report “not demonstrated.”

39. **`arxiv-1902.10565::scale_up` |** Start a fresh isolated b8 run, then consider b14, only when measured value/GPU-hour improves | predecessors: `eval_improvement`, `measure_stage_throughput`, `scale_data_window`, `scale_search_budget`, `select_transformer_ladder`, `data_budget` | evidence: conjecture followed by numerical simulation | status: hypothesis `[FUTURE]`.

    verify: each fresh candidate must pass export/load, show `>=10%` VRAM headroom, project `<=60 h` per cycle, obey CPU/GPU/storage caps, and beat b7 accepted-Elo gain per GPU-hour; never resume a b7 checkpoint into another configuration.
