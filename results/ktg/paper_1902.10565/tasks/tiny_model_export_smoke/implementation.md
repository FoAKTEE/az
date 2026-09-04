# Implementation — `tiny_model_export_smoke`

## 0. Header

**Task ID:** `tiny_model_export_smoke`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::tiny_model_export_smoke`
**Language:** Python exporter + C++ engine `benchmarknn` / `gtp`
**Method class:** simulation (end-to-end exporter -> `desc.cpp` -> GPU forward pass, plus a negative fixture)

## 1. Claim

> A random-initialized `b7c96h3tfrs` exported by `python/export_model_pytorch.py` lowers to exactly 7 `transformer_attention_block` + 7 `transformer_ffn_block` entries, is accepted by the C++ model reader, and serves >0 nnEval/s on a 9x9 board — while the same binary refuses a `b5c48h3tfr` export with the exact SwiGLU diagnostic (claim `c03_tf_export_loads`; obligation `o23_ffn_negative_fixture`).

## 2. Success Criterion

- **Needed evidence type:** `numerical_simulation`
- **Done when:** the positive legs and the negative fixture all pass on one recorded run.
- **Verification command:**
  `bash results/ktg/paper_1902.10565/codes/eval/export_smoke.sh b7c96h3tfrs && python3 results/ktg/paper_1902.10565/codes/eval/check_export_blocks.py /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/x/model.bin`
  with `$W = /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/x`. `export_smoke.sh <kind>` runs, in order:
  1. `python $KATAGO_SRC/python/export_model_pytorch.py -export-random-initialized-model <kind> -export-dir $W -model-name ktg-smoke-<kind> -filename-prefix model`, then `gzip -kf $W/model.bin`;
  2. `python3 codes/eval/check_export_blocks.py $W/model.bin` — prints the block-kind histogram and exits non-zero unless it is exactly `{"transformer_attention_block": 7, "transformer_ffn_block": 7}` with no other block kind present;
  3. `$KATAGO_BIN benchmarknn -model $W/model.bin.gz -config $KATAGO_SRC/cpp/configs/gtp_example.cfg -boardsize 9 -require-exact-nnlen -batch-size 2 -warmup 1 -iterations 2 -json` — exit 0 and `sumMedianNNEvalsPerSec > 0` parsed from the JSON object;
  4. a 9x9 GTP leg: `printf 'boardsize 9\nkomi 7.0\nclear_board\ngenmove b\nquit\n' | $KATAGO_BIN gtp -model $W/model.bin.gz -config $KATAGO_SRC/cpp/configs/gtp_example.cfg` — exit 0 and the `genmove` response is a legal 9x9 vertex (`= [A-J][1-9]` or `= pass`);
  5. **negative fixture** (`o23_ffn_negative_fixture`): export `b5c48h3tfr` into `$W_neg` on the **same** patched binary and run leg 3 against it; require exit code `!= 0` and the exact string `Non-SwiGLU transformer FFN is not yet supported in CUDA backend` on stdout+stderr.
- **Measured tolerance / metric:** histogram equality is exact (`7` and `7`, nothing else); `benchmarknn` exit `== 0` and `sumMedianNNEvalsPerSec > 0`; GTP exit `== 0` with a legal vertex; negative fixture exit `!= 0` **and** diagnostic string count `== 1` — a non-zero exit without that exact string is a FAIL, not a pass.
- **Open obligations before start:** none blocking. `env_build` is `[SOLID]` (result row `env-toolchain-b200`, evidence `results/ktg/paper_1902.10565/evidence/env/smoke.txt`); `select_transformer_ladder` fixes the start model at `b7c96h3tfrs`. Carried: `o08_exporter_name`, `o15_attn_logit_export_guard`, `o23_ffn_negative_fixture`.
- **Reduction-to-baseline test:** NA

Block kinds are literal lines written by `write_block` (`python/export_model_pytorch.py:469-505`): `TransformerAttentionBlock -> transformer_attention_block` (`:491-492 -> :420`), `TransformerFFNBlock -> transformer_ffn_block` (`:493-494 -> :457`); any other class hits `assert False` at `:504-505`. `b7c96h3tfrs` has `block_kind = 7 x [attnrope, ffnsg]` (`python/katago/train/modelconfigs.py:1021`), hence 7 + 7. The reader accepts exactly those two kinds at `cpp/neuralnet/desc.cpp:1521` and `:1542` and throws `found unknown block kind` at `:1557` otherwise.

This node does **not** depend on `cfg_9x9_override`: legs 3-5 use the upstream `cpp/configs/gtp_example.cfg`, the same config `codes/env/env_build.sbatch` used for its own benchmark and GTP legs. The two frontier nodes therefore run in parallel.

## 3. Motivation

`tiny_model_export_smoke` is the gate between the toolchain and the loop: `env_build` and `select_transformer_ladder` route into it, and it feeds `synchronous_loop_smoke` and `export_stage`. It is the cheapest place to discover exporter/reader incompatibilities before a multi-day loop is queued, and the only place where the mission deliberately reproduces the engine refusal it must otherwise never trigger.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §3 trunk-config fields, §6 exporter flags |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §3 transformer-family row (FFN variant, exportability) |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | node `tiny_model_export_smoke`: predecessors `env_build`, `select_transformer_ladder` (the `cfg_9x9_override` edge is removed); successors `synchronous_loop_smoke`, `export_stage` |
| implementation_plan | `results/ktg/paper_1902.10565/decomposition/implementation_plan_python.md` | exporter invocation and block-count table |
| ref | `results/ktg/paper_1902.10565/decomposition/ref.md` | v1.18.2 provenance |
| assumptions | `results/ktg/paper_1902.10565/decomposition/assumptions.md` | `a06_tf_family`, `a08_cuda_backend` |
| claims | `results/ktg/paper_1902.10565/decomposition/claims.md` | `c03` |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | `o08`, `o15`, `o23` |
| result_seed | `results/ktg/paper_1902.10565/decomposition/result_seed.md` | initial status and dependencies |

**Upstream task outputs:** `tasks/env_build/implementation.md` (`[SOLID]` — binary + venv + `env.sh`); node `select_transformer_ladder` (start model `b7c96h3tfrs`, `*tfrs|*tflrs` rule).
**Evidence packs:** `evidence/decomposition/audit_loop_scripts_configs.md` §C (exporter CLI and block lowering), §E (engine CLIs); `evidence/env/smoke-297952-fail.txt` (the diagnostic the negative fixture must reproduce).

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- Export via `python/export_model_pytorch.py` only; `grep -rn 'export_model\.py' codes/` must return nothing (`o08_exporter_name`).
- One node only: export + load + `benchmarknn` + GTP + the negative fixture. No loop wiring, no gating, no 9x9 selfplay config.
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
| Scratch workdir `$W` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/x` |
| Negative-fixture dir `$W_neg` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/x_ffng` |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/eval/
├── export_smoke.sh           # node tiny_model_export_smoke - legs 1-5 of §2, exits non-zero on any failure
└── check_export_blocks.py    # node tiny_model_export_smoke - block-kind histogram over model.bin, exact-match assert
```

`check_export_blocks.py` reads `model.bin` as text up to each `@BIN@` float section (`export_model_pytorch.py:220-226`) and counts standalone block-kind lines from the closed set `{ordinary_block, gpool_block, nested_bottleneck_block, transformer_attention_block, transformer_ffn_block}`. It takes the `model.bin` path as its single positional argument so the closing check can call it directly.

## 8. Phase Plan

### Phase 1 - `export + histogram`
- **Nodes:** `tiny_model_export_smoke`
- **Files:** `export_smoke.sh` legs 1-2, `check_export_blocks.py`
- **Test:** histogram `== {transformer_attention_block: 7, transformer_ffn_block: 7}`; `model.bin`, `metadata.json`, `log.txt` all written (`export_model_pytorch.py:120-122, 682, 70`).
- **Estimate:** `0.5` h

### Phase 2 - `engine load + throughput + negative fixture`
- **Nodes:** `tiny_model_export_smoke`
- **Files:** `export_smoke.sh` legs 3-5
- **Test:** `benchmarknn` exits 0 with `sumMedianNNEvalsPerSec > 0` and no `found unknown block kind` from `cpp/neuralnet/desc.cpp:1557`; GTP returns a legal 9x9 vertex; the `b5c48h3tfr` leg exits non-zero with the exact SwiGLU diagnostic.
- **Estimate:** `0.5` h

## 9. Quick-Win Path

1. `Phase 1` — CPU-only export inside a 1-GPU b200 job (`export_model_pytorch.py:90` loads on `cpu`).
2. `Phase 2` — `benchmarknn`, GTP and the negative fixture in the same job.
3. **Smoke check:** the JSON line parses and `sumMedianNNEvalsPerSec` is finite and positive.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| model kind (positive) | `b7c96h3tfrs` | `modelconfigs.py:1008-1029`, registered `:1887`; start and first production model per node `select_transformer_ladder` |
| model kind (negative fixture) | `b5c48h3tfr` | `modelconfigs.py:1886` `"b5c48h3tfr": b5c48h3tfr,  # no swiglu`; exported with `use_swiglu=0` (`export_model_pytorch.py:461`) — used **only** here |
| expected attention blocks | `7` | `modelconfigs.py:1021` -> `write_block` `export_model_pytorch.py:491-492` |
| expected FFN blocks | `7` | `modelconfigs.py:1021` (`ffnsg` -> SwiGLU) -> `export_model_pytorch.py:493-494` |
| trunk width / FFN width / heads | `96` / `256` / `3` (kv 3) | `modelconfigs.py:1015,1018,1019-1020`; head dim `96/3 = 32`, satisfies `q_head_dim % 4 == 0` (`model_pytorch.py:2112`) |
| `-export-random-initialized-model` | set (mutually exclusive with `-checkpoint`) | `export_model_pytorch.py:34-35`, `:57-58`, random branch `:84` |
| `-attn-logit-bound-limit` | default `2.5e4` | `export_model_pytorch.py:42`; guard `model_pytorch.py:3010`; `o15` |
| exporter pos_len at load | `19` (benign) | random branch `export_model_pytorch.py:84` builds `Model(cfg, pos_len=19)`; checkpoint branch `python/katago/train/load_model.py:62,77`; RoPE tables and score-belief vectors are non-persistent buffers (`model_pytorch.py:2170-2171, 2770-2784`); only `ropeTheta` is serialised (`cpp/neuralnet/desc.cpp:1242-1250`) |
| `-config` (legs 3-5) | `$KATAGO_SRC/cpp/configs/gtp_example.cfg` | the config `codes/env/env_build.sbatch` already used; `benchmarknn` declares it as its default config file name (`cpp/command/benchmarknn.cpp:54`). **Not** `codes/cfg/selfplay_9x9.cfg` — this node has no edge to `cfg_9x9_override` |
| `-boardsize` | `9` | `benchmarknn.cpp:68-73`; a single size is mandatory with `-require-exact-nnlen` (`:112`) |
| `-require-exact-nnlen` | set | `benchmarknn.cpp:74-77`; makes the NN buffer exactly 9x9, so the smoke measures the shape the loop will actually serve |
| `-batch-size` | `2` | `benchmarknn.cpp:64-67`; overrides `nnMaxBatchSize` from the config |
| `-warmup` / `-iterations` | `1` / `2` | `benchmarknn.cpp:56-63`; defaults are 20/200, far more than a smoke needs |
| `-json` | set | `benchmarknn.cpp:78`; logs move to stderr (`:121-123`) so stdout is one parseable object |
| metric key | `sumMedianNNEvalsPerSec` | `benchmarknn.cpp:179`; the assert is `> 0` |
| GTP leg | `boardsize 9`, `komi 7.0`, `genmove b` | same script shape as `codes/env/env_build.sbatch` stage 5(b) |
| `--gres` / `--cpus-per-task` / `--mem` / `--time` | `gpu:1` / `8` / `64G` / `00:30:00` | compute-budget `SKILL.md` "Debug / build / data prep" |

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| Negative fixture passes for the wrong reason | non-zero exit with a missing-file or CLI error instead of the SwiGLU throw | assert the exact string `Non-SwiGLU transformer FFN is not yet supported in CUDA backend` **and** a non-zero exit; a bare non-zero exit fails the leg |
| Negative fixture leaks into the loop | `b5c48h3tfr` appears in a `MODELKIND` or `-model-kind` outside `export_smoke.sh` | `grep -rn 'b5c48h3tfr' codes/ \| grep -v eval/export_smoke.sh` must return nothing; `synchronous_loop_9x9.sh` asserts `*tfrs\|*tflrs` |
| Unsupported block silently exported | `assert False, "This kind of block is not supported..."` (`export_model_pytorch.py:504-505`) | Phase 1 fails loudly before any GPU time is used |
| Extra/unexpected block kinds | histogram has `ordinary_block` or `nested_bottleneck_block` entries | exact-match assert, not a `>=` check |
| Attention-logit guard refuses export | exporter exits non-zero citing the `2.5e4` bound | random init is far below the bound; for trained checkpoints record the refusal (`o15`) rather than bypassing it |
| Wrong exporter used | `grep -rn 'export_model\.py' codes/` returns a hit | `o08_exporter_name`; only `export_model_pytorch.py` is allowed |
| `.bin` vs `.bin.gz` mix-up | engine reports a bad model file | `export_model_for_selfplay.sh:90` makes the `.gz`; the smoke gzips explicitly, feeds the `.gz` to the engine and the `.bin` to the histogram |
| `benchmarknn` prints 0 nnEval/s without erroring | parsed `sumMedianNNEvalsPerSec <= 0` | the parse-and-assert is part of leg 3, not eyeballed |
| `-json` output polluted by backend warnings | JSON parse failure | `benchmarknn.cpp:121-123` routes logs to stderr under `-json`; parse stdout only |

## 12. Current State

- `[SOLID]` The exporter path works and the C++ reader accepts a transformer net: job `298018` exported a random-initialized `b7c96h3tfrs`, and `katago benchmark` at 9x9 plus a 9x9 GTP `genmove` both returned `[OK]` (`SMOKE RESULT: PASS`). Evidence `results/ktg/paper_1902.10565/evidence/env/smoke.txt`.
- `[SOLID]` Predecessor `env_build` is `solid` (result row `env-toolchain-b200`, `sm_100` ELF count 2, cuDNN 9.19.0). Predecessor `select_transformer_ladder` fixes the start model at `b7c96h3tfrs` and the `*tfrs|*tflrs` rule.
- `[SOLID]` The negative fixture's expected behaviour is already recorded once: job `297952` aborted with exit 134 and `Non-SwiGLU transformer FFN is not yet supported in CUDA backend` (`evidence/env/smoke-297952-fail.txt:26-27`), the `throw` at `cpp/neuralnet/cudaandrocmbackend.inc:3307-3308`. This node re-runs it as a controlled, asserted fixture on the current binary — node `engine_ffn_swiglu_constraint` owns the fact.
- `[SOLID]` `transformer_trunk_b5c48h3tfr` is superseded and is not a live node; `b5c48h3tfr` exists in the mission only as this task's negative fixture.
- `[PRELIMINARY]` Leg 1 is known to pass for both kinds (job `297952` wrote `model.bin` 505183 B / `model.bin.gz` 462127 B for `b5c48h3tfr`; job `298018` did the same for `b7c96h3tfrs`). Legs 2-5 have never been run in this asserted form.
- `[OPEN]` `codes/eval/export_smoke.sh` and `codes/eval/check_export_blocks.py` are not written yet (`codes/` = `env` only).
- `[OPEN]` `o23_ffn_negative_fixture` — closes when leg 5 runs on the current binary and both the non-zero exit and the exact diagnostic are recorded under `evidence/export_smoke/`.
- `[OPEN]` `o15_attn_logit_export_guard` — untested for a *trained* checkpoint; random init says nothing about it. Closes in `export_stage`.

## 13. Forbidden Actions

- Never edit `ref-code/lightvector-KataGo/`; the exporter is invoked from `$KATAGO_SRC` via `PYTHONPATH` set by `env.sh`.
- Never call `python/export_model.py` (the TensorFlow-era name) — only `export_model_pytorch.py` (`o08_exporter_name`).
- Never pass `-ignore-attn-logit-bound` to make an export succeed; record the refusal instead.
- Never accept a partial histogram match (`>= 7`): the assert is exact equality with no other block kind.
- Never use `b5c48h3tfr` anywhere except leg 5 of `export_smoke.sh`; it must never reach `MODELKIND`, `-model-kind`, or any loop script.
- Never mark the negative fixture as passing on a non-zero exit alone — the exact diagnostic string is the evidence.
- Never point legs 3-5 at `codes/cfg/selfplay_9x9.cfg`: this node has no edge to `cfg_9x9_override` and must stay runnable in parallel with it.
- Never substitute `benchmark` for `benchmarknn`: search-level visits/s does not isolate the raw forward pass, and only `benchmarknn` offers `-require-exact-nnlen`.
- Never exceed 1 GPU / 24 CPUs for this smoke, and never point `--output` at `/tmp`.

## 14. Promise Tag

- **Promise format:** `<promise>tiny_model_export_smoke BLOCK_HISTOGRAM WITHIN EXACT{attn:7,ffn:7} AND SUM_MEDIAN_NNEVALS_PER_S WITHIN >0 AND FFNG_FIXTURE=REFUSED</promise>`
- **Required in commit body:** verbatim `check_export_blocks.py` histogram, the `benchmarknn` JSON object, the GTP `genmove` response, the negative fixture's exit code and diagnostic line, evidence path under `evidence/export_smoke/`, claim `c03`, evidence type `numerical_simulation`.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions:
- Per-substage commit: Phase 1 (histogram) and Phase 2 (engine legs + fixture) commit separately.
- Joint progress file: `progress/paper_1902.10565/tiny_model_export_smoke/progress.md`.
- Loop notes: `results/ktg/paper_1902.10565/loop_note/note_session_{id}_loop_{n}.md` before compaction.
- State-note sync: `o23` and `o15` transitions go into `${RESEARCH_STATE}`; the SwiGLU constraint itself is recorded there under node `engine_ffn_swiglu_constraint`.

## 16. Termination Checklist

- [ ] Verification command ran and output is pasted.
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] Metrics are within the thresholds in §2, negative fixture included.
- [ ] Reduction-to-baseline test passed when relevant (NA).
- [ ] No `[BLOCKING]`, `[OPEN]`, or `[UNCHECKED]` markers remain for this checked claim — `o15` stays open by design and belongs to `export_stage`.
- [ ] No silent scope expansion: export + load + `benchmarknn` + GTP + negative fixture only.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
