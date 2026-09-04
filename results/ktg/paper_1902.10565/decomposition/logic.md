# Equation DAG — paper_arxiv-1902.10565

26 nodes. Legend: ● solid · ◐ preliminary · ○ hypothesis · ✗ blocking · □ future · △ concept-advance. Node badge `k<N>` = knowledge records under the node, `t<N>✗<F>` = trials (F failed). Dashed edge = predecessor outside scope.

```mermaid
flowchart TD
  n_arxiv_1902_10565__transformer_trunk_b5c48h3tfr["◐ <b>transformer_trunk_b5c48h3tfr</b> △ · k1<br/>b5c48h3tfr (modelconfigs.py:986-1006): version 17, 5 x (a…"]:::preliminary
  n_arxiv_1902_10565__playout_cap_randomization["◐ <b>playout_cap_randomization</b> · k1<br/>Playout cap randomization as coded: play.cpp:1132-1150 pi… <br/><i>paper l.96-97</i>"]:::preliminary
  n_arxiv_1902_10565__root_explore_and_target_pruning["◐ <b>root_explore_and_target_pruning</b> · k1<br/>Forced root exploration (searchexplorehelpers.cpp:166-169… <br/><i>eq:l105, paper l.109</i>"]:::preliminary
  n_arxiv_1902_10565__loss_targets_metrics["◐ <b>loss_targets_metrics</b> · k1<br/>Loss as coded in metrics_pytorch.py:856-882: policy 0.930… <br/><i>eq:l546, eq:l550, eq:l554, eq:l558…</i>"]:::preliminary
  n_arxiv_1902_10565__score_utility_search["◐ <b>score_utility_search</b> · k1<br/>Score utility u = c * (2/pi) atan((x - x0)/(dynamicScoreC… <br/><i>eq:l689, eq:l691, eq:l702</i>"]:::preliminary
  n_arxiv_1902_10565__head_gpool_degeneracy_9x9["◐ <b>head_gpool_degeneracy_9x9</b> △ · k1<br/>Global pooling survives only in the policy head (KataGPoo… <br/><i>paper l.398-404</i>"]:::preliminary
  n_arxiv_1902_10565__train_optimizer_schedule["◐ <b>train_optimizer_schedule</b> · k1<br/>train.py defaults: SGD momentum 0.9 (opt-in AdamW/Muon/No…"]:::preliminary
  n_arxiv_1902_10565__selfplay_search_params["◐ <b>selfplay_search_params</b> · k1<br/>Search/thread keys of selfplay1_maxsize9.cfg and gatekeep…"]:::preliminary
  n_arxiv_1902_10565__game_randomization_9x9["◐ <b>game_randomization_9x9</b> · k1<br/>Game-init keys in v1.18.2 selfplay cfg: bSizes/bSizeRelPr…"]:::preliminary
  n_arxiv_1902_10565__gating_rule["◐ <b>gating_rule</b> · k1<br/>Gating in v1.18.2: numGamesPerGating 200 (cfg), -required…"]:::preliminary
  n_arxiv_1902_10565__train_resume_semantics["◐ <b>train_resume_semantics</b> · k1<br/>train.py resumes unconditionally from <traindir>/checkpoi…"]:::preliminary
  n_arxiv_1902_10565__data_format_pos_len["◐ <b>data_format_pos_len</b> · k1<br/>Training-row layout at posLen L: binaryInputNCHWPacked 22…"]:::preliminary
  n_arxiv_1902_10565__training_window_shuffle["◐ <b>training_window_shuffle</b> · k1<br/>shuffle.py window: -keep-target-rows (required; loop pass…"]:::preliminary
  n_arxiv_1902_10565__env_build["○ <b>env_build</b> · k1<br/>venv (torch 2.11.0+cu128, numpy, packaging, psutil, nvidi…"]:::hypothesis
  n_arxiv_1902_10565__cfg_9x9_override["○ <b>cfg_9x9_override</b> · k1<br/>Mission-owned selfplay_9x9.cfg / gatekeeper_9x9.cfg / tra…"]:::hypothesis
  n_arxiv_1902_10565__tiny_model_export_smoke["○ <b>tiny_model_export_smoke</b> · k1<br/>export_model_pytorch.py -export-random-initialized-model …"]:::hypothesis
  n_arxiv_1902_10565__synchronous_loop_smoke["○ <b>synchronous_loop_smoke</b> · k1<br/>One full cycle of a mission-owned copy of python/selfplay…"]:::hypothesis
  n_arxiv_1902_10565__loop_resume_under_walltime["○ <b>loop_resume_under_walltime</b> · k1<br/>Slurm wrapper that re-submits itself under the 3-day MaxT…"]:::hypothesis
  n_arxiv_1902_10565__selfplay_stage["○ <b>selfplay_stage</b> · k1<br/>katago selfplay at production knobs on 9x9 (maxVisits 600…"]:::hypothesis
  n_arxiv_1902_10565__shuffle_stage["○ <b>shuffle_stage</b> · k1<br/>shuffle.py over selfplay/*/tdata at pos_len 9 with -keep-…"]:::hypothesis
  n_arxiv_1902_10565__train_stage["○ <b>train_stage</b> · k1<br/>train.py -model-kind b5c48h3tfr -pos-len 9 on 1 GPU with …"]:::hypothesis
  n_arxiv_1902_10565__export_stage["○ <b>export_stage</b> · k1<br/>export_model_for_selfplay.sh (mission copy calling export…"]:::hypothesis
  n_arxiv_1902_10565__gatekeeper_stage["○ <b>gatekeeper_stage</b> · k1<br/>katago gatekeeper with gatekeeper_9x9.cfg (numGamesPerGat…"]:::hypothesis
  n_arxiv_1902_10565__eval_improvement["○ <b>eval_improvement</b> △ · k1<br/>Measurable success criterion for 9x9: (a) >= 2 gatekeeper…"]:::hypothesis
  n_arxiv_1902_10565__data_budget["○ <b>data_budget</b> · k1<br/>Scratch budget for the mission at 94% group usage: measur…"]:::hypothesis
  n_arxiv_1902_10565__scale_up["○ <b>scale_up</b> · k1<br/>Second configuration within caps: larger tf-family net (b…"]:::hypothesis
  n_arxiv_1902_10565__transformer_trunk_b5c48h3tfr --> n_arxiv_1902_10565__loss_targets_metrics
  n_arxiv_1902_10565__transformer_trunk_b5c48h3tfr --> n_arxiv_1902_10565__head_gpool_degeneracy_9x9
  n_arxiv_1902_10565__transformer_trunk_b5c48h3tfr --> n_arxiv_1902_10565__train_optimizer_schedule
  n_arxiv_1902_10565__selfplay_search_params --> n_arxiv_1902_10565__cfg_9x9_override
  n_arxiv_1902_10565__game_randomization_9x9 --> n_arxiv_1902_10565__cfg_9x9_override
  n_arxiv_1902_10565__gating_rule --> n_arxiv_1902_10565__cfg_9x9_override
  n_arxiv_1902_10565__data_format_pos_len --> n_arxiv_1902_10565__cfg_9x9_override
  n_arxiv_1902_10565__env_build --> n_arxiv_1902_10565__tiny_model_export_smoke
  n_arxiv_1902_10565__transformer_trunk_b5c48h3tfr --> n_arxiv_1902_10565__tiny_model_export_smoke
  n_arxiv_1902_10565__cfg_9x9_override --> n_arxiv_1902_10565__tiny_model_export_smoke
  n_arxiv_1902_10565__tiny_model_export_smoke --> n_arxiv_1902_10565__synchronous_loop_smoke
  n_arxiv_1902_10565__cfg_9x9_override --> n_arxiv_1902_10565__synchronous_loop_smoke
  n_arxiv_1902_10565__loop_resume_under_walltime --> n_arxiv_1902_10565__synchronous_loop_smoke
  n_arxiv_1902_10565__train_resume_semantics --> n_arxiv_1902_10565__loop_resume_under_walltime
  n_arxiv_1902_10565__synchronous_loop_smoke --> n_arxiv_1902_10565__selfplay_stage
  n_arxiv_1902_10565__selfplay_search_params --> n_arxiv_1902_10565__selfplay_stage
  n_arxiv_1902_10565__playout_cap_randomization --> n_arxiv_1902_10565__selfplay_stage
  n_arxiv_1902_10565__root_explore_and_target_pruning --> n_arxiv_1902_10565__selfplay_stage
  n_arxiv_1902_10565__score_utility_search --> n_arxiv_1902_10565__selfplay_stage
  n_arxiv_1902_10565__selfplay_stage --> n_arxiv_1902_10565__shuffle_stage
  n_arxiv_1902_10565__training_window_shuffle --> n_arxiv_1902_10565__shuffle_stage
  n_arxiv_1902_10565__data_format_pos_len --> n_arxiv_1902_10565__shuffle_stage
  n_arxiv_1902_10565__shuffle_stage --> n_arxiv_1902_10565__train_stage
  n_arxiv_1902_10565__loss_targets_metrics --> n_arxiv_1902_10565__train_stage
  n_arxiv_1902_10565__transformer_trunk_b5c48h3tfr --> n_arxiv_1902_10565__train_stage
  n_arxiv_1902_10565__train_resume_semantics --> n_arxiv_1902_10565__train_stage
  n_arxiv_1902_10565__train_optimizer_schedule --> n_arxiv_1902_10565__train_stage
  n_arxiv_1902_10565__train_stage --> n_arxiv_1902_10565__export_stage
  n_arxiv_1902_10565__tiny_model_export_smoke --> n_arxiv_1902_10565__export_stage
  n_arxiv_1902_10565__export_stage --> n_arxiv_1902_10565__gatekeeper_stage
  n_arxiv_1902_10565__gating_rule --> n_arxiv_1902_10565__gatekeeper_stage
  n_arxiv_1902_10565__gatekeeper_stage --> n_arxiv_1902_10565__eval_improvement
  n_arxiv_1902_10565__synchronous_loop_smoke --> n_arxiv_1902_10565__data_budget
  n_arxiv_1902_10565__data_format_pos_len --> n_arxiv_1902_10565__data_budget
  n_arxiv_1902_10565__eval_improvement --> n_arxiv_1902_10565__scale_up
  n_arxiv_1902_10565__data_budget --> n_arxiv_1902_10565__scale_up
  n_arxiv_1902_10565__transformer_trunk_b5c48h3tfr --> n_arxiv_1902_10565__scale_up
  n_arxiv_1902_10565__head_gpool_degeneracy_9x9 --> n_arxiv_1902_10565__scale_up
  classDef solid fill:#e6ffed,stroke:#28a745,color:#000;
  classDef preliminary fill:#fff8e1,stroke:#d4a017,color:#000;
  classDef hypothesis fill:#e7f0ff,stroke:#4977c7,color:#000;
  classDef blocking fill:#ffe3e3,stroke:#d33,color:#000;
  classDef future fill:#f2f2f2,stroke:#999,color:#555;
  classDef amended fill:#f0f0f0,stroke:#aaa,color:#888;
```
