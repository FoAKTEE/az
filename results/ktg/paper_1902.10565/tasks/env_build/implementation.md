# Implementation — `env_build`

## 0. Header

**Task ID:** `env_build`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: mirror `ref-code/lightvector-KataGo/` @ `v1.18.2` / `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4`, `cpp/main.cpp:245`)
**Logic-graph nodes covered:** `arxiv-1902.10565::env_build`
**Language:** C++ build (CMake/CUDA) + Python venv — bash driver
**Method class:** simulation (executable toolchain smoke)

## 1. Claim

> A KataGo v1.18.2 CUDA-backend binary with sm_100 SASS, plus a torch 2.11.0+cu128 venv, builds and passes `runtests` + a 9x9 transformer benchmark on one B200 node (claim `c01_env_build_runs`, `c02_sm100_sass_or_jit`).

## 2. Success Criterion

- **Needed evidence type:** `numerical_simulation` (executed toolchain smoke)
- **Done when:** `evidence/env/smoke.txt` ends in `SMOKE RESULT: PASS` and the built binary carries at least one sm_100 ELF image.
- **Verification command:**
  `bash -c 'grep -q "SMOKE RESULT: PASS" /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/evidence/env/smoke.txt && cuobjdump --list-elf /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/build/KataGo/cpp/build/katago | grep -c sm_100'`
  (`cuobjdump` needs `module load cuda/12.8.1`, `docs/cluster-manual.md` §8.)
- **Measured tolerance / metric:** `PASS` present **and** `grep -c sm_100` >= 1. If the count is 0, the fail row is recorded and the sub-step below runs, then the command is re-run.
- **Open obligations before start:** `o05_cudnn_version_sdpa`, `o06_sm100_arch`, `o12_pydeps_pin`.
- **Reduction-to-baseline test:** NA

**Executed 2026-09-03T22:0x (this task file):** output `2`, exit `0` -> metric within tolerance.
Evidence: `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/evidence/env/smoke-298018.txt`.

### Sub-step (fail branch, already exercised)

Arch list at `ref-code/lightvector-KataGo/cpp/CMakeLists.txt:761` (CUDA >= 12.8, < 13.0 branch) is
`50 52 53 60 61 62 70 72 75 80 86 87 90 120` — **no 100**, and the plain `set()` shadows any
`-DCMAKE_CUDA_ARCHITECTURES` (audit_loop_scripts_configs.md §G). The one allowed edit outside the repo
adds `100` in the **scratch build clone only**, via
`results/ktg/paper_1902.10565/codes/env/cmake-sm100.diff` applied at `codes/env/env_build.sbatch` stage 2b,
which also deletes the `build` stamp to force a rebuild. The mirror is never touched.

## 3. Motivation

Every other node needs a running `katago` and a torch that can instantiate the model. Node `env_build`
is the sole root of `tiny_model_export_smoke -> synchronous_loop_smoke -> ...` in `decomposition/logic.md`.
Blackwell (compute cap 10.0) needs CUDA >= 12.8 SASS or every kernel launch JITs (`docs/cluster-manual.md` §8).

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §4 trainer flags, §6 exporter flags |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §3 superseded-trunk row (transformer family) |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | node `env_build` and its out-edges |
| implementation_plan | not produced at stage 1 | — `[OPEN] no implementation_plan_{lang}.md exists` |
| ref | `results/ktg/paper_1902.10565/decomposition/ref.md` | v1.18.2 provenance |
| assumptions | `results/ktg/paper_1902.10565/decomposition/assumptions.md` | `a04_b200_fallback`, `a08_cuda_backend` |
| claims | `results/ktg/paper_1902.10565/decomposition/claims.md` | `c01`, `c02` |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | `o05`, `o06`, `o12` |
| result_seed | not produced at stage 1 | — `[OPEN]` |

**Upstream task outputs:** none (root node).
**Evidence packs:** `results/ktg/paper_1902.10565/evidence/decomposition/audit_loop_scripts_configs.md` §G (build), §H (python deps).

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- One node only: build + smoke. No loop wiring, no cfg authoring here.
- Re-runs are idempotent: `$R/.stamps/{venv,clone,build,smoke}` gate every stage (`env_build.sbatch:31-35`).
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference paper | `ref-paper/arxiv-1902.10565/` |
| Reference code | `ref-code/lightvector-KataGo/` (read-only mirror) |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/env/` |
| Plot / figure output | `results/ktg/paper_1902.10565/plots/` |
| Loop notes | `results/ktg/paper_1902.10565/loop_note/` |
| Progress dir | `progress/paper_1902.10565/env_build/` |
| Git branch | `ssci` |
| Scratch root `R` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/env/
├── env_build.sbatch      # node env_build - 6 stamped stages: modules, venv, clone, sm100 patch, build, smoke
├── cmake-sm100.diff      # node env_build - adds 100 to CMAKE_CUDA_ARCHITECTURES in the SCRATCH clone only
└── env.sh                # node env_build - reusable env (modules, venv, LD_LIBRARY_PATH, KATAGO_BIN, PYTHONPATH)
```

## 8. Phase Plan

### Phase 1 - `toolchain`
- **Nodes:** `env_build`
- **Files:** `env_build.sbatch` stages 0-4, `env.sh`
- **Test:** `katago version` prints `KataGo v1.18.2` and `Using CUDA backend`; `$GOT_SHA == fd0723fd...`.
- **Estimate:** `1.0` h (build with `-j16`)

### Phase 2 - `smoke + arch proof`
- **Nodes:** `env_build`
- **Files:** `env_build.sbatch` stage 5-6, `runtime/smoke/torch_smoke.py`
- **Test:** the §2 verification command.
- **Estimate:** `0.3` h

## 9. Quick-Win Path

1. `Phase 1` — `sbatch codes/env/env_build.sbatch` (b200, 1 GPU, 16 CPUs, 3 h).
2. `Phase 2` — read `evidence/env/smoke-$JOBID.txt`.
3. **Smoke check:** `katago runtests` exits 0 and `torch.cuda.is_available()` is True.

## 10. First Test Parameters

| Parameter | Value | Notes |
|---|---|---|
| `--partition` | `b200` | `a04_b200_fallback`; gb301/b300 reserved (`docs/cluster-manual.md` §3, §9) |
| `--gres` | `gpu:1` | compute-budget `SKILL.md` sizing table "Debug / build / data prep" |
| `--cpus-per-task` | `16` | <= 24 cap (124 x 0.20), `SKILL.md`; `NPROC` at `env_build.sbatch:29` |
| `--mem` | `96G` | `docs/cluster-manual.md` §7 (always pass `--mem`) |
| `--time` | `03:00:00` | backfill favours short jobs, `docs/cluster-manual.md` §6 |
| modules | `gcc/12.3.0 cmake/3.30.2 cuda/12.8.1 python/3.11.9` | `env.sh:9`; CUDA >= 12.8 for Blackwell (`docs/cluster-manual.md` §8) |
| `USE_BACKEND` | `CUDA` | `cpp/CMakeLists.txt:583-585`; `a08_cuda_backend` |
| `CUDNN_LIBRARY` | `$CUDNN_DIR/lib/libcudnn.so` | `cpp/CMakeLists.txt:1128` searches `lib64`, the wheel ships `lib/` -> explicit `-D` + `libcudnn.so -> libcudnn.so.9` symlink (`env_build.sbatch:76-79`) |
| cuDNN | `nvidia-cudnn-cu12>=9.8,<10` -> `91900` | SDPA gate `cpp/neuralnet/cudabackend.cpp:13` needs `CUDNN_VERSION >= 8903`; measured `cudnn 91900` (`smoke.txt:131`) |
| torch | `2.11.0+cu128` | floors: `torch.amp.GradScaler` `python/train.py:37`, flex_attention `trainloop_helpers.py:154-157` (audit §H) |
| `CMAKE_CUDA_ARCHITECTURES` | `... 90 100 120` | patched from `cpp/CMakeLists.txt:761` by `cmake-sm100.diff` |
| smoke `MODEL_KIND` | `b7c96h3tfrs` (`modelconfigs.py:1008-1029`) | `env_build.sbatch:26`; **not** `b5c48h3tfr` (unservable, see §12) |
| smoke `POS_LEN` | `9` | `env_build.sbatch:27`; `a05_9x9_only` |

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| No sm_100 SASS -> PTX JIT | `cuobjdump --list-elf \| grep -c sm_100` returns `0`; first kernel launch slow or `no kernel image` | apply `cmake-sm100.diff` to the scratch clone, delete `.stamps/build`, rebuild (stage 2b) |
| cuDNN not found by CMake | `FATAL` at `cpp/CMakeLists.txt:1125-1127` or `CUDNN_LIBRARY-NOTFOUND` | pass all three `-DCUDNN_*`; create the `libcudnn.so` symlink first |
| libzip missing -> no training data | CMake warning + `NO_LIBZIP` (`cpp/CMakeLists.txt:1891-1892`) "selfplay ... not be possible" | `env_build.sbatch:60` dies if `/usr/include/zip.h` is absent |
| Non-SwiGLU FFN model aborts the engine | `ERROR: NN server thread failed: Non-SwiGLU transformer FFN is not yet supported in CUDA backend`, exit 134 | see §12; smoke model kept in the `ffnsg` family |
| Log written to node-local `/tmp` and lost | job `COMPLETED`, `--output` file missing | `--output` points at `/scratch/.../logs/` (`env_build.sbatch:11`), per `docs/cluster-manual.md` §4 trap 2 |
| Scratch full (94 % group usage) | `No space left on device` mid-build | `python3 /apps/helpers/quotas.py` before submit; see task `data_budget` |

## 12. Current State

- `[SOLID]` Toolchain built and smoke-passed on `gb205`, job `298018`: `SMOKE RESULT: PASS`; `cuobjdump --list-elf | grep -c sm_100 = 2`; arch set observed `sm_100 sm_120 sm_50 ... sm_90`. Evidence `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/evidence/env/smoke-298018.txt` (lines 34-37, 143) and `.../smoke.txt`. Verification command re-run here: output `2`, exit `0`.
- `[SOLID]` `katago version` = `KataGo v1.18.2`, git `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4-dirty` (the `-dirty` is exactly `cmake-sm100.diff`), `Using CUDA backend`; `katago runtests` `[OK]`; GPU `NVIDIA B200, 10.0`.
- `[SOLID]` `o05_cudnn_version_sdpa` discharged: `cudnn 91900` >= 8903 (`smoke.txt:131`), so `KATAGO_CUDA_HAS_SDPA` is compiled in (`cpp/neuralnet/cudabackend.cpp:13`).
- `[SOLID]` `o06_sm100_arch` discharged by the patch + rebuild (stamp `.stamps/build` @ 22:03).
- `[SOLID]` resolved history: `b5c48h3tfr` (ffng) is refused by every v1.18.2 backend (`cpp/neuralnet/cudaandrocmbackend.inc:3307-3308`, `eigenbackend.cpp:1634`, `openclbackend.cpp:2729`; job 297952 FAILED 1:0, `smoke-297952.txt`). The mission model is `b7c96h3tfrs` (job 298018 COMPLETED 0:0, `smoke-298018.txt` PASS); ledger: node `transformer_trunk_b7c96h3tfrs`, `a06`/`o07`/`c03`/`c16` amended, `o18` discharged (commit ee47dd9). Nothing in this task is blocked by it.
- `[OPEN]` `o12_pydeps_pin`: `codes/env/requirements.txt` with pinned `torch==2.11.0+cu128`, `numpy`, `scipy`, `psutil`, `packaging`, `sgfmill`, `nvidia-cudnn-cu12>=9.8,<10` plus a captured `pip freeze` is not written yet. Closes when both files exist under `codes/env/` and `pip freeze` is stored under `evidence/env/`.
- `[SOLID]` `decomposition/implementation_plan_{python,cpp,bash}.md` and `decomposition/result_seed.md` exist (commit 87bb402); the §4 rows resolve.

## 13. Forbidden Actions

- Never edit anything under `ref-code/lightvector-KataGo/` — the sm_100 change goes only into `$R/build/KataGo` via `cmake-sm100.diff`.
- Never re-point `--output`/`--error`/`--chdir` at `/tmp` (node-local; the log vanishes).
- Never request `--cpus-per-task` > 24 or more than 1 GPU for this build job.
- Never submit to `b200`/`b300` without `--gres=gpu:N` (rejected by `job_submit.lua`).
- Never claim sm_100 coverage from the `cmake` log alone; only `cuobjdump --list-elf` output counts.
- Never delete `$R/.stamps` wholesale to "force a clean run" without recording the rebuild in the error ledger.
- Never install a system-wide cuDNN or a different torch channel; cuDNN comes from the pip wheel inside `$R/venv`.

## 14. Promise Tag

- **Promise format:** `<promise>env_build SM100_ELF_COUNT WITHIN >=1 AND SMOKE=PASS</promise>`
- **Required in commit body:** the verification command's verbatim output (`2`), the measured metric, evidence path `evidence/env/smoke-298018.txt`, claim `c01`/`c02`, evidence type `numerical_simulation`.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions:
- Per-substage commit: venv, clone+patch, build, smoke each get their own commit when the user requests commits.
- Joint progress file: `progress/paper_1902.10565/env_build/progress.md`.
- Loop notes: `results/ktg/paper_1902.10565/loop_note/note_session_{id}_loop_{n}.md` before compaction.
- State-note sync: the SwiGLU finding is already in `${RESEARCH_STATE}` (trunk row) and the ledger (`a06_tf_family` amended, commit ee47dd9).

## 16. Termination Checklist

- [x] Verification command ran and output is pasted (`2`, exit 0).
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [x] Metric is within the threshold in §2.
- [ ] Reduction-to-baseline test passed when relevant (NA).
- [ ] No `[BLOCKING]`, `[OPEN]`, or `[UNCHECKED]` markers remain — the SwiGLU blocker and `o12` are open, so `c01` admits as `checked` only for `b7c96h3tfrs`, not for `b5c48h3tfr`.
- [x] No silent scope expansion.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
