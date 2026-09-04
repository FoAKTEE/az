# Validation record — code-map re-affirmation packets `paper_code_map_search` (6 nodes) and `paper_code_map_training` (8 nodes)

This single file covers BOTH probe packets; there is no separate `evidence/paper_code_map_training/validation.md`.

Role: Chandra VALIDATOR (refuter, then judge), cross-model from the worker. Host `login03`, CPU only, no GPU job. cwd `/home/schmidt/ssci-haiyangw/az`.
Inputs received: `evidence/paper_code_map_search/candidate_rows.json` (6), `evidence/paper_code_map_training/candidate_rows.json` (8), both `anchor_reverification.md` files, `tasks/paper_code_map_search/implementation.md`, `tasks/paper_code_map_training/implementation.md`, the ledger schemas.

## Verdict

**ADMIT all 14 rows as honest re-affirmations at `preliminary`.** No row over-claims; none proposes `solid`. Appended with `knowledge_database.py append-batch --force` (the dedup would otherwise skip them because status and summary are unchanged — the value added is the executed `verification_run` and the new `evidence_sha256` on each node's history). Gate output: `{"appended": 14, "skipped": 0, "papers": ["arxiv-1902.10565"]}`.

Gates checked:
- Evidence type vs claim: each row's evidence is an executed `path:line` anchor check against the pinned mirror (`ref-code/lightvector-KataGo` @ `v1.18.2` = `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4`, verified with `git rev-parse HEAD` / `describe --tags`). That supports "the summary has not drifted from the code" — exactly `preliminary`. Both task files' § 2 require executed GPU probes for `solid` and § 13 forbid promotion from a code re-read; no row attempts it (`promotion_to_solid_proposed: false` on all 14; `proposed_status: preliminary` on all 14).
- Consistency with the ledger: for every node the candidate's `prior_row_hash` equals the current latest row's `row_hash`, and the candidate `summary`, `predecessors`, `equation_labels`, `paper_anchor`, `risk_tier`, `concept_advance`, `task_id`, `domain` are identical to the current row (checked field by field).
- The one node without a task file, `select_transformer_ladder` (`task_id select_transformer_ladder`; `results/ktg/paper_1902.10565/tasks/` has no such directory): flagged `[OPEN]` in its appended row's `notes` ("no task file exists ...; its promotion criterion is unstated, so this row re-affirms preliminary only") rather than silently promoted. Its predecessors (`transformer_trunk_b7c96h3tfrs` preliminary, `engine_ffn_swiglu_constraint` solid) resolve.
- Hidden `[OPEN]` items: each row's `notes` carries verbatim the worker's `what_it_does_not_establish` (the GPU probe assertions still owed), so the open work is visible on the ledger row.

## 1. Validator re-execution of all 14 verification commands (verbatim)

Executed from the az root with `bash -c <verification.command>`; output sha `e3b0c442...` is the empty string (every command is `grep -q` / `assert`, silent on success), identical to the worker's transcripts.

```
rows: 14
playout_cap_randomization                exit=0 0.091s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
root_explore_and_target_pruning          exit=0 0.118s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
score_utility_search                     exit=0 0.071s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
selfplay_search_params                   exit=0 0.119s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
game_randomization_9x9                   exit=0 0.094s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
gating_rule                              exit=0 0.142s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
loss_targets_metrics                     exit=0 0.051s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
head_gpool_degeneracy_9x9                exit=0 0.117s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
train_optimizer_schedule                 exit=0 0.071s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
train_resume_semantics                   exit=0 0.098s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
data_format_pos_len                      exit=0 0.108s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
training_window_shuffle                  exit=0 0.094s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
transformer_trunk_b7c96h3tfrs            exit=0 0.116s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
select_transformer_ladder                exit=0 0.176s proposed=preliminary solid_proposed=False out_sha=e3b0c44298fc
exit0: 14 / 14
any solid proposed: False
```

## 2. Appended rows (all `status preliminary`, `actor_role validator`, gate `verification_run.exit_code 0`, evidence hashed)

| node | node_seq | evidence sha256 (prefix) | row_hash |
|---|---|---|---|
| playout_cap_randomization | 3 | 1649a20cbf59 | 7e781005904759d9fa91dcbe4a901c333ec83b84a014f0b9c7636cbb9829c099 |
| root_explore_and_target_pruning | 3 | 1649a20cbf59 | d92df506ff5c1bca3fb2e44fa33dab24e95df52701974f81b40eff4b8a6100bf |
| score_utility_search | 3 | 1649a20cbf59 | 88907aa62914b9c8dfa3feb47da2fe26f425d9b92f05f8aa8708f1c82c79fad3 |
| selfplay_search_params | 3 | 1649a20cbf59 | 9b23b7439c2487525aa0ddc40991e558d82cd18dae23006ca87b3302711afab0 |
| game_randomization_9x9 | 3 | 1649a20cbf59 | 39eaa00a8c331e063a45615d4b072d4c7359bf498548787fe330a7f4804851d1 |
| gating_rule | 3 | 1649a20cbf59 | a40ddf94bdfd357eb35d6b7b4854a7a1e224d6a9a3e567cf8c06a7ed743b581b |
| loss_targets_metrics | 4 | 5086576c9e9a | 9260cb98fa568f71f98c01e69ef7816bb890218f01cd379b3969561acfc39054 |
| head_gpool_degeneracy_9x9 | 4 | 5086576c9e9a | ddf36d0daddb8e175a92592a9afe1d199430c8895c36b5a6c457e104145336fa |
| train_optimizer_schedule | 4 | 5086576c9e9a | 9aa761a7313b54d8a0cc6ef944aefa5172106a6c449f6385b64ab23ec0252d9c |
| train_resume_semantics | 3 | 5086576c9e9a | 2987e2a3d2de69e8d5a65701b882b34276cf25cda8a6e448d1f0aa450974df21 |
| data_format_pos_len | 3 | 5086576c9e9a | 375668265daa98ffab2c5b41e1f5500edf4c4482aebaf6f38c31c26cf75c033b |
| training_window_shuffle | 3 | 5086576c9e9a | 3e74cf2e6174443f629792214a4e32eaaf498070c714d1c7b091cda01737c468 |
| transformer_trunk_b7c96h3tfrs | 3 | 5086576c9e9a | b9623b9b24469d6aa1b7ec5f09ebe58a94a1da54de6bbfbb7b847f5ae1e7503f |
| select_transformer_ladder | 2 | 5086576c9e9a | f54c1676316404f23b271289305b114602e4b23424789334ff31d327cbec21ca |

(`1649a20cbf59…` = `evidence/paper_code_map_search/anchor_reverification.md`; `5086576c9e9a…` = `evidence/paper_code_map_training/anchor_reverification.md`.)

Error-ledger validation row (pass): `task_id paper_code_map`, stage `validation`, metric `verification_commands_exit_zero 14/14`, row hash `7ff1350ec198b425112c33c73dcda7128c221760de6933b2d18ec2d5833893c7`.

## 3. Claim transitions

None proposed by the worker and none made: `c15_paper_ideas_in_code` (literature_grounding) stays `open` — an anchor check shows the code text is where the map says it is, not that the idea is live in a run. The promotions to `solid` remain owed to the GPU probes `probe_search_9x9.sh` / `probe_gate_9x9.sh` and `probe_train_9x9.sh`, which wait on `cfg_9x9_override` (o01, o02).

## 4. Remaining [OPEN]

1. All 14 nodes stay `preliminary` until the § 2 probes of the two task files run on a GPU node (`full_frac` in [0.20,0.30], `rows_per_game` in [12,35], `sz_other == 0`, `gate_random >= 1`; trunk gpool count 0, gpool residuals < 1e-5, row bytes 2145 from a real `dataBoardLen = 9` npz, kill/resume with `global_step_samples` continuing).
2. `select_transformer_ladder` has no task file and no stated promotion criterion.
3. `score_utility_search`, `gating_rule`, `training_window_shuffle`, `loss_targets_metrics` are partial-by-design even after the probes (per their task files' § 12).
