# Implementation — `tiny_model_export_smoke`

## 0. Header

**Task ID:** `tiny_model_export_smoke`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::tiny_model_export_smoke` (model dependency re-pointed to `arxiv-1902.10565::transformer_trunk_b7c96h3tfrs`)
**Language:** Python exporter + C++ engine benchmark
**Method class:** simulation (end-to-end exporter -> `desc.cpp` -> GPU inference smoke)

## 1. Claim

> A random-initialized `b7c96h3tfrs` exported by `python/export_model_pytorch.py` lowers to exactly 7 `transformer_attention_block` + 7 `transformer_ffn_block` entries, is accepted by the C++ model reader, and benchmarks at >0 visits/s on a 9x9 board (claim `c03_tf_export_loads`).

## 2. Success Criterion

- **Needed evidence type:** `numerical_simulation`
- **Done when:** both legs below pass on one recorded run.
- **Verification command:**
  `bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/eval/export_smoke.sh b7c96h3tfrs`
  which runs, in order:
  1. `python $KATAGO_SRC/python/export_model_pytorch.py -export-random-initialized-model b7c96h3tfrs -export-dir $W/model -model-name ktg-smoke-b7c96h3tfrs -filename-prefix model` then `gzip -kf $W/model/model.bin`;
  2. `python codes/eval/check_export_blocks.py $W/model/model.bin` — prints the block-kind histogram and exits non-zero unless it is exactly `{"transformer_attention_block": 7, "transformer_ffn_block": 7}` with no other block kind present;
  3. `$KATAGO_BIN benchmark -model $W/model/model.bin.gz -config codes/cfg/selfplay_9x9.cfg -boardsize 9 -v 200 -t 4 -n 2` — exit 0, and the reported visits/s parsed from stdout is `> 0`.
- **Measured tolerance / metric:** histogram equality is exact (`7` and `7`, nothing else); benchmark exit code `== 0`; `visits/s > 0`.
- **Open obligations before start:** **`env_build` has landed — job `298018` COMPLETED `0:0` with `SMOKE RESULT: PASS` and `sm_100` ELF count 2 — but its result row has not yet been appended to the ledger by its owner, so this task's predecessor is satisfied on disk and `[OPEN]` in the ledger.** Also `o08_exporter_name`; `o06_sm100_arch` and `o18` are discharged.
- **Reduction-to-baseline test:** NA

Block kinds are literal lines written by `write_block` (`python/export_model_pytorch.py:469-504`): `TransformerAttentionBlock -> transformer_attention_block` (`:491-492 -> :420`), `TransformerFFNBlock -> transformer_ffn_block` (`:493-494 -> :457`); any other class hits `assert False` at `:503-504`. `b7c96h3tfrs` has `block_kind = 7 x [attnrope, ffnsg]` (`python/katago/train/modelconfigs.py:1021`), hence 7 + 7. The superseded `b5c48h3tfr` had `5 x [attnrope, ffng]` (`:999`) and hence 5 + 5.

## 3. Motivation

`tiny_model_export_smoke` is the single gate between the toolchain and the loop: `logic.md` routes `env_build`, `transformer_trunk_b7c96h3tfrs` (re-pointed from the superseded `transformer_trunk_b5c48h3tfr`) and `cfg_9x9_override` into it, and it feeds `synchronous_loop_smoke` and `export_stage`. It is also the cheapest place to discover exporter/reader incompatibilities before a multi-day loop is queued.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §3 trunk-config fields (amended to `b7c96h3tfrs`), §6 exporter flags |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §3 superseded-trunk row (transformer family, exportability) |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | node `tiny_model_export_smoke` and its three predecessors |
| implementation_plan | not produced at stage 1 | `[OPEN]` |
| ref | `results/ktg/paper_1902.10565/decomposition/ref.md` | v1.18.2 provenance |
| assumptions | `results/ktg/paper_1902.10565/decomposition/assumptions.md` | `a06_tf_family`, `a08_cuda_backend` |
| claims | `results/ktg/paper_1902.10565/decomposition/claims.md` | `c03` |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | `o06`, `o08`, `o15` |
| result_seed | not produced at stage 1 | `[OPEN]` |

**Upstream task outputs:** `tasks/env_build/implementation.md` (binary + venv), `tasks/cfg_9x9_override/implementation.md` (the `-config` argument).
**Evidence packs:** `evidence/decomposition/audit_loop_scripts_configs.md` §C (exporter CLI and block lowering), §E (benchmark CLI).

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- Export via `python/export_model_pytorch.py` only; `grep -rn 'export_model.py' codes/` must return nothing (`o08_exporter_name`).
- One node only: export + load + benchmark. No loop wiring, no gating.
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference paper | `ref-paper/arxiv-1902.10565/` |
| Reference code | `ref-code/lightvector-KataGo/` |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/eval/` |
| Plot / figure output | `results/ktg/paper_1902.10565/plots/` |
| Loop notes | `results/ktg/paper_1902.10565/loop_note/` |
| Progress dir | `progress/paper_1902.10565/tiny_model_export_smoke/` |
| Git branch | `ssci` |
| Scratch workdir `$W` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/export_smoke` |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/eval/
├── export_smoke.sh           # node tiny_model_export_smoke - the 3 legs of §2, exits non-zero on any failure
└── check_export_blocks.py    # node tiny_model_export_smoke - block-kind histogram over model.bin, exact-match assert
```

`check_export_blocks.py` reads `model.bin` as text up to each `@BIN@` float section (`export_model_pytorch.py:220-226`) and counts standalone block-kind lines from the closed set `{ordinary_block, gpool_block, nested_bottleneck_block, transformer_attention_block, transformer_ffn_block}`.

## 8. Phase Plan

### Phase 1 - `export + histogram`
- **Nodes:** `tiny_model_export_smoke`
- **Files:** `export_smoke.sh` legs 1-2, `check_export_blocks.py`
- **Test:** histogram `== {transformer_attention_block: 5, transformer_ffn_block: 5}`; `model.bin`, `metadata.json`, `log.txt` all written (`export_model_pytorch.py:120-122, 682, 70`).
- **Estimate:** `0.5` h

### Phase 2 - `engine load + benchmark`
- **Nodes:** `tiny_model_export_smoke`
- **Files:** `export_smoke.sh` leg 3
- **Test:** benchmark exits 0, no `unknown block kind` from `cpp/neuralnet/desc.cpp`, visits/s `> 0`.
- **Estimate:** `0.3` h

## 9. Quick-Win Path

1. `Phase 1` — CPU-only export inside a 1-GPU b200 job (`export_model_pytorch.py:90` loads on `cpu`).
2. `Phase 2` — benchmark in the same job.
3. **Smoke check:** the benchmark log line `Model name: ... (transformer, N params)` appears before any error.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| model kind | `b7c96h3tfrs` | `modelconfigs.py:1008-1028`, registered `:1887`; mission model per the amended `a06_tf_family` / `o07_family_choice_tf_vs_nbt`. Supersedes `b5c48h3tfr` (`:986-1006`, registered `:1886` "no swiglu") — see §12 |
| expected attention blocks | `7` | `modelconfigs.py:1021` -> `write_block` `export_model_pytorch.py:491-492` |
| expected FFN blocks | `7` | `modelconfigs.py:1021` (`ffnsg` -> SwiGLU, `use_swiglu` true) -> `export_model_pytorch.py:493-494` |
| trunk width / FFN width / heads | `96` / `256` / `3` (kv 3) | `modelconfigs.py:1015,1018,1019-1020`; head dim `96/3 = 32`, satisfies `q_head_dim % 4 == 0` (`model_pytorch.py:2112`) |
| `-export-random-initialized-model` | set (mutually exclusive with `-checkpoint`) | `export_model_pytorch.py:34-35`, `:57-58`, random branch `:84` |
| `-attn-logit-bound-limit` | default `2.5e4` | `export_model_pytorch.py:42`; guard `model_pytorch.py:3010`; `o15` |
| exporter pos_len at load | default `19` (benign) | `python/katago/train/load_model.py:62,77`; RoPE tables and score-belief vectors are non-persistent buffers (`model_pytorch.py:2170-2171, 2770-2784`); only `ropeTheta` is serialised (`cpp/neuralnet/desc.cpp:1242-1250`) |
| `-boardsize` | `9` | `cpp/command/benchmark.cpp:199-206` (range 7..19, exclusive with `-sgf` `:249-250`) |
| `-v` / `-visits` | `200` | `benchmark.cpp:191-234`; overrides `maxVisits`/`maxPlayouts` at `:316-317` |
| `-t` / `-threads` | `4` | benchmark ignores the config's `numSearchThreads` (`:331`); 4 << 24-CPU cap |
| `-n` / `-numpositions` | `2` | default is 10 (`benchmark.cpp`); 2 keeps the smoke short |
| `-config` | `codes/cfg/selfplay_9x9.cfg` | unused selfplay keys produce only `WARNING: Config had unused keys!` (`cpp/core/config_parser.cpp:459-464`), not an error |
| `--gres` / `--cpus-per-task` / `--mem` / `--time` | `gpu:1` / `8` / `64G` / `00:30:00` | compute-budget `SKILL.md` "Debug / build / data prep" |

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| A non-SwiGLU (`ffng`) config name reaches `MODELKIND` | `ERROR: NN server thread failed: Non-SwiGLU transformer FFN is not yet supported in CUDA backend`, `terminate called ... StringError`, exit `134` | resolved by the model switch (§12); `export_smoke.sh` rejects any model kind whose `block_kind` contains `ffng` before spending GPU time |
| Unsupported block silently exported | `assert False, "This kind of block is not supported..."` (`export_model_pytorch.py:503-504`) | Phase 1 fails loudly before any GPU time is used |
| Extra/unexpected block kinds | histogram has `ordinary_block` or `nested_bottleneck_block` entries | exact-match assert, not a `>=` check |
| Attention-logit guard refuses export | exporter exits non-zero citing the `2.5e4` bound | random init is far below the bound; for trained checkpoints enable `-attn-logit-penalty-cap` (`train.py:140`) or record the refusal (`o15`) |
| Wrong exporter used | `grep -rn 'export_model.py' codes/` returns a hit | `o08_exporter_name`; only `export_model_pytorch.py` is allowed |
| `.bin` vs `.bin.gz` mix-up | engine reports a bad model file | `export_model_for_selfplay.sh:90` makes the `.gz`; the smoke gzips explicitly and benchmarks the `.gz` |
| Benchmark reports 0 visits/s without erroring | parsed rate `<= 0` | the parse-and-assert is part of leg 3, not eyeballed |

## 12. Current State

- `[SOLID]` The exporter path works and the C++ reader accepts a transformer net: job `298018` exported a random-initialized `b7c96h3tfrs`, and `katago benchmark (... 9x9 board, 80 visits, 1 thread)` plus a 9x9 GTP `genmove` both returned `[OK]`. Evidence `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/evidence/env/smoke-298018.txt` (lines 90, 126, 143).
- `[SOLID]` The exporter succeeds for both configs: job `297952` wrote `model.bin` (505183 B) and `model.bin.gz` (462127 B) for `b5c48h3tfr` — evidence `evidence/env/smoke-297952.txt:34-38`; job `298018` did the same for `b7c96h3tfrs`. Leg 1 of §2 is therefore already known to pass; leg 2 has not been run for either.
- `[SOLID]` **Resolved history — `b5c48h3tfr` is unservable; the mission model is now `b7c96h3tfrs`.** Job `297952` ran exactly this smoke against `b5c48h3tfr` and aborted with exit `134` (`sacct` `FAILED 1:0`): `ERROR: NN server thread failed: Non-SwiGLU transformer FFN is not yet supported in CUDA backend` — evidence `evidence/env/smoke-297952.txt:68-80`. Root cause: `cpp/neuralnet/cudaandrocmbackend.inc:3306-3309` throws when `!useSwiGLU`; the same refusal is in `cpp/neuralnet/eigenbackend.cpp:1634` and `cpp/neuralnet/openclbackend.cpp:2729`, so no v1.18.2 backend can serve an `ffng` config (`modelconfigs.py:999`, registration comment `:1886` "no swiglu"). The mission model was switched to `b7c96h3tfrs` (`modelconfigs.py:1008-1028`, registered `:1887`), which job `298018` proved servable end to end (`sacct` `COMPLETED 0:0`, `SMOKE RESULT: PASS`) — evidence `evidence/env/smoke-298018.txt` lines 90, 126, 143. Ledger: node `arxiv-1902.10565::transformer_trunk_b7c96h3tfrs` added, `::transformer_trunk_b5c48h3tfr` set to `blocking`, successors re-pointed; `a06`, `o07`, `c03`, `c16` amended; `o18` and `o06` discharged.
- `[OPEN]` `env_build` has landed on disk (job `298018`, 2026-09-03T22:03, `SMOKE RESULT: PASS`, `.stamps/{venv,clone,build,smoke}` all present) but its result row has not yet been appended to the ledger by its owner. Closes when that row lands.
- `[OPEN]` `codes/cfg/selfplay_9x9.cfg` does not exist yet (only `codes/env/` exists), so leg 3's `-config` argument is unavailable. Closes with `cfg_9x9_override`.
- `[OPEN]` `codes/eval/check_export_blocks.py` and `export_smoke.sh` are not written yet.
- `[OPEN]` `o15_attn_logit_export_guard` — untested for a *trained* checkpoint; random init says nothing about it.

## 13. Forbidden Actions

- Never edit `ref-code/lightvector-KataGo/`; the exporter is invoked from `$KATAGO_SRC` via `PYTHONPATH` set by `env.sh`.
- Never call `python/export_model.py` (the TensorFlow-era name) — only `export_model_pytorch.py` (`o08_exporter_name`).
- Never pass `-ignore-attn-logit-bound` to make an export succeed; record the refusal instead.
- Never accept a partial histogram match (`>= 5`): the assert is exact equality with no other block kind.
- Never use an `ffng` (non-SwiGLU) config name for `MODELKIND` anywhere in the mission — `b5c48h3tfr` included; only `ffnsg` configs are servable.
- Never re-run leg 3 for a non-SwiGLU config hoping for a different result — the refusal is a hard `throw` at model-construction time, not a flaky failure.
- Never exceed `-t 4` threads / 1 GPU / 24 CPUs for this smoke.
- Never point `--output` at `/tmp`.

## 14. Promise Tag

- **Promise format:** `<promise>tiny_model_export_smoke BLOCK_HISTOGRAM WITHIN EXACT{attn:7,ffn:7} AND BENCHMARK_VISITS_PER_S WITHIN >0</promise>`
- **Required in commit body:** verbatim `check_export_blocks.py` histogram, the benchmark's visits/s line, exit codes, evidence path under `evidence/export_smoke/`, claim `c03`, evidence type `numerical_simulation`.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions:
- Per-substage commit: Phase 1 (histogram) and Phase 2 (benchmark) commit separately.
- Joint progress file: `progress/paper_1902.10565/tiny_model_export_smoke/progress.md`.
- Loop notes: `results/ktg/paper_1902.10565/loop_note/note_session_{id}_loop_{n}.md` before compaction.
- State-note sync: the SwiGLU finding is recorded in `${RESEARCH_STATE}` as resolved history — `a06_tf_family` amended to `b7c96h3tfrs`, which unblocks `selfplay_stage`, `gatekeeper_stage` and `synchronous_loop_smoke`.

## 16. Termination Checklist

- [ ] Verification command ran and output is pasted.
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] Metrics are within the thresholds in §2.
- [ ] Reduction-to-baseline test passed when relevant (NA).
- [ ] No `[BLOCKING]`, `[OPEN]`, or `[UNCHECKED]` markers remain for this checked claim — currently false: the cfg files, the two scripts and the `env_build` ledger row are still `[OPEN]`.
- [ ] No silent scope expansion: export + load + benchmark only.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
