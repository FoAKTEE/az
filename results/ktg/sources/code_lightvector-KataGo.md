# Source — `lightvector/KataGo` @ `v1.18.2`

Stage 0-acquire declaration. Output contract: `pipelines/0-acquire/spec.md` § Output contract.
Markers per `_common/contracts/markers.md`. Every table row below was confirmed by
`grep`/`ls` against the pinned mirror; unconfirmed items are `[OPEN]`.

## Identifier

| field | value |
|---|---|
| source_id | `code_lightvector-KataGo` |
| repository | https://github.com/lightvector/KataGo |
| tag / commit | `v1.18.2` / `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4` |
| SHA vs `mission.json` | match |
| mirror | `ref-code/lightvector-KataGo/` (+ `PROVENANCE.md`) |
| license | MIT |
| default evidence type | literature grounding (code reading), promoted only by execution |

## Relevance

The executable artifact the mission actually runs. It is the only place the
**transformer trunk** exists — the seed paper has no attention architecture — and it
supplies the five-process self-play loop, the board-size config keys the mission
narrows to 9×9, and the build requirements for the B200/B300 nodes.

## Expected role

**Baseline / implementation** (primary). The mission runs this code essentially
unmodified; any divergence is a config, not a patch. Also serves as **reference**
for paper claims whose implementation detail the paper omits.

## Confirmed declarations (file paths verified in the mirror)

### 1. Transformer config family — `python/katago/train/modelconfigs.py`

| item | path:line | verbatim evidence |
|---|---|---|
| model version introducing transformers | `python/katago/train/modelconfigs.py:43` | `# version = 17 # V7 features, Q value predictions made optional (config "predict_q_values"), introduced transformers and added guards to unused params` |
| `b5c48h3tfr` definition | `python/katago/train/modelconfigs.py:986-1006` | `"version":17`, `"trunk_num_channels":48`, `"transformer_ffn_channels":128`, `"transformer_heads":3`, `"transformer_kv_heads":3` |
| `b5c48h3tfr` block kinds | `python/katago/train/modelconfigs.py:999` | `"block_kind": [item for i in range(1,6) for item in [[f"attn{i}","attnrope"],[f"ffn{i}","ffng"]]]` |
| `b5c48h3tfr` registration | `python/katago/train/modelconfigs.py:1886` | `"b5c48h3tfr": b5c48h3tfr,  # no swiglu` |
| naming convention comment | `python/katago/train/modelconfigs.py:1879` | `# "b14c192h6tfrs" as an example:` |

Registered `tf` family members (`modelconfigs.py:1886-1942`): `b5c48h3tfr`,
`b7c96h3tfrs`, `b8c96h3tfrs`, `b14c192h6tfrs`, `b14c192h6tflrs`, `b16c256h8tfrs`,
`b22c192h6tfrs`, `b21c384h12tfrs`, `b21c384h12tflrs`, `b30c512h16tflrs`,
`b45c384h12tflrs`. `b5c48h3tfr` is the smallest — the mission's smoke config.

**Correction to the working context.** `b5c48h3tfr` uses block kind **`ffng`**, not
`ffnsg`; the registration comment `# no swiglu` states why. `ffnsg` (SwiGLU) is used by
every larger member, e.g. `modelconfigs.py:1021`
(`[[f"attn{i}","attnrope"],[f"ffn{i}","ffnsg"]]`). Both are real block kinds:
`python/katago/train/model_pytorch.py:2970` (`"ffnsg"`), `:2971` (`"ffng"`),
with the dispatch at `model_pytorch.py:3270` and `:3278`.

Attention block kinds, `model_pytorch.py:2966-2969` — `attnrope` (`:2966`), `attngab`
(`:2967`), `attnropegab` (`:2968`), `attnropetab` (`:2969`); dispatch at `:3231`, `:3250`,
`:3260`. Defaults list at `model_pytorch.py:3002-3003` is `attnrope` / `ffnsg`.

**Two distinct transformer trunk families exist — this matters for config choice.**

*(a) Interleaved family* (`tf` suffix, e.g. `b5c48h3tfr`): separate alternating blocks,
one `attn*` then one `ffn*` per layer. This is what `RESEARCH_STATE.md` selects.

*(b) Fused nested-bottleneck family* (`nbt` + `tf` suffix): a single block kind that fuses
a nested-bottleneck residual stage with attention and FFN. Confirmed at
`model_pytorch.py:2972-2978`:

| block kind | line |
|---|---|
| `bottlenest2transformerrope` | `:2972` |
| `bottlenest2transformerropesg` | `:2973` |
| `bottlenest3transformerropesg` | `:2974` |
| `bottlenest2transformergabsg` | `:2975` |
| `bottlenest2transformerropegabsg` | `:2976` |
| `bottlenest2transformertabsg` | `:2977` |
| `bottlenest2transformerropetabsg` | `:2978` |

Dispatch at `model_pytorch.py:3286`, `:3298`, `:3310`, `:3322`, `:3335`, `:3348`, `:3361`;
defaults list at `:3004-3006`. Used by the `nbt` configs, e.g.
`modelconfigs.py:1191` (`"block_kind": [[f"block{i}","bottlenest2transformerropesg"] for i
in range(1,6)]`) and registered names `b5c192h3nbttfrs` (`:1890`), `b4c256h4nbttflrs`
(`:1891`), `b5c384h6nbttflrs` (`:1896`), `b10c384h6nbttflrs` (`:1909`),
`b15c512h8nbttflrs` (`:1916`), `b10c512h8nbt3tflrs` (`:1917`), `b13c1024h16nbttflrs`
(`:1945`), among ~25 others.

Plain `bottlenest2` / `bottlenest2gpool` (no `transformer`) are the *pre-transformer*
residual bottleneck kinds — `modelconfigs.py:86`, `:209-213`, `:234-241`,
`model_pytorch.py:2963`, `:2965` — and are unrelated to attention.

**The `bottlenest*transformer*` names are Python-side only.** `grep -rn
"bottlenest[0-9]*transformer" cpp/ --include=*.cpp --include=*.h` returns **nothing**:
the fused blocks are decomposed at export into the C++ primitives
`transformer_attention_block` / `transformer_ffn_block` plus the nested-bottleneck block
(`NESTED_BOTTLENECK_BLOCK_KIND`, `cpp/neuralnet/desc.cpp:1519`). The C++ never sees the
fused name. See `[OPEN] nbt-export`.

### 2. C++ block-kind parsing — `cpp/neuralnet/desc.cpp`

| block kind | path:line | constant emitted |
|---|---|---|
| `transformer_attention_block` | `cpp/neuralnet/desc.cpp:1521` | `TRANSFORMER_ATTENTION_BLOCK_KIND` (`desc.cpp:1540`), parses `TransformerAttentionDesc`, checks `qProj.inChannels == trunkNumChannels` and `outProj.outChannels == trunkNumChannels` |
| `transformer_ffn_block` | `cpp/neuralnet/desc.cpp:1542` | `TRANSFORMER_FFN_BLOCK_KIND` (`desc.cpp:1554`), parses `TransformerFFNDesc`, checks `numChannels == trunkNumChannels` |
| unknown-kind guard | `cpp/neuralnet/desc.cpp:1557` | `throw StringError(name + ": found unknown block kind: " + kind);` |

Second parser (CoreML export path, not used on this cluster):
`cpp/external/katagocoreml/src/parser/KataGoParser.cpp:695` and `:708`.

### 3. Self-play loop pieces

The five processes, as the upstream docs enumerate them
(`SelfplayTraining.md:6-10`) — with the **actual** file the mirror ships:

| # | role | doc says (`SelfplayTraining.md`) | actual artifact in mirror | status |
|---|---|---|---|---|
| 1 | Selfplay engine | `cpp/katago selfplay` (l.6) | `cpp/main.cpp:105` → `MainCmds::selfplay` | confirmed |
| 2 | Shuffler | `python/shuffle.py` (l.7) | `python/shuffle.py` (present); driver `python/selfplay/shuffle.sh:42,61,78` invokes `$PYTHON ./shuffle.py` | confirmed |
| 3 | Training | `python/train.py` (l.8) | `python/train.py` (present); driver `python/selfplay/train.sh:83` invokes `time $PYTHON ./train.py` | confirmed |
| 4 | Exporter | `python/export_model.py` (l.9) | **`python/export_model_pytorch.py`** — driver `python/selfplay/export_model_for_selfplay.sh:77` invokes `$PYTHON ./export_model_pytorch.py` | **doc is stale**, see below |
| 5 | Gatekeeper | `cpp/katago gatekeeper` (l.10) | `cpp/main.cpp:95` → `MainCmds::gatekeeper` | confirmed |

**Stale upstream reference.** `python/export_model.py` **does not exist** at `v1.18.2`
(`ls python/export_model*.py` → `python/export_model_pytorch.py` only). Two upstream
docs still name the old path — `SelfplayTraining.md:9` and `python/README.md:13` — as
does a comment in `python/selfplay/export_model_for_selfplay.sh:11`. The executable
path in that same script (`:77`) is correct. Any mission script must call
`export_model_pytorch.py`.

Orchestrator — `python/selfplay/synchronous_loop.sh` (6311 B), one cycle:

| step | `synchronous_loop.sh` line | invocation |
|---|---|---|
| gatekeeper | `:96` | `./bin/katago gatekeeper -rejected-models-dir … -accepted-models-dir … -test-models-dir … -config …/gatekeeper.cfg -quit-if-no-nets-to-test` |
| selfplay | `:99` | `./bin/katago selfplay -max-games-total "$NUM_GAMES_PER_CYCLE" -output-dir …/selfplay -models-dir …/models -config …/selfplay.cfg` |
| shuffle | `:105` | `SKIP_VALIDATE=1 ./shuffle.sh "$BASEDIR" "$SCRATCHDIR" "$NUM_THREADS_FOR_SHUFFLING" -min-rows … -keep-target-rows … -taper-window-scale …` |
| train | `:109` | `./train.sh "$BASEDIR" "$TRAININGNAME" "$MODELKIND" "$BATCHSIZE" main -samples-per-epoch … -stop-when-train-bucket-limited -max-train-bucket-size …` |
| export | `:113` | `./export_model_for_selfplay.sh "$NAMEPREFIX" "$BASEDIR" "$USEGATING"` |

Config paths it defaults to: `synchronous_loop.sh:70` `SELFPLAY_CONFIG=…/cpp/configs/training/selfplay1.cfg`,
`:71` `GATING_CONFIG=…/cpp/configs/training/gatekeeper1.cfg`. `USEGATING` is arg-controlled (`:20`).
`$MODELKIND` (`:109`) is where the `b5c48h3tfr` config name enters the loop.

`katago` subcommand dispatch, `cpp/main.cpp`: `analysis`:85, `benchmark`:87,
`benchmarknn`:89, `contribute`:91, `evalsgf`:93, `gatekeeper`:95, `genconfig`:97,
`gtp`:99, `tuner`:101, `match`:103, `selfplay`:105, `testgpuerror`:107.

### 4. Board-size config keys — `cpp/configs/training/`

`bSizes` / `bSizeRelProbs` are present in 10 of the 15 files in that directory:

| config | line | `bSizes` | `bSizeRelProbs` |
|---|---|---|---|
| `selfplay1_maxsize9.cfg` | `:95-96` | `7,8,9` | `1,1,8` |
| `gatekeeper1_maxsize9.cfg` | `:38-39` | `7,8,9` | `1,1,8` |
| `selfplay1.cfg` | `:95-96` | `7,9,11,13,15,17,19,  8,10,12,14,16,18` | `1,4,3,10,7,9,35, 1,2,4,6,8,10` |
| `gatekeeper1.cfg` | `:38-39` | `9,11,13,15,17,19,  10,12,14,16,18` | `2,3,10,7,9,35, 2,4,6,8,10` |
| `selfplay2.cfg` | `:74-75` | mixed 7…19 | `1,4,3,10,7,9,35, …` |
| `gatekeeper2a.cfg` | `:38-39` | mixed 9…19 | `2,3,10,7,9,35, …` |
| `gatekeeper2b.cfg`, `gatekeeper2bfaster.cfg` | `:38-39` | mixed 9…19 | `2,3,10,7,9,60, …` |
| `selfplay8a.cfg` | `:74-75` | mixed 7…19 | `1,4,3,10,7,9,35, …` |
| `selfplay8b20.cfg` | `:74-75` | mixed 7…19 | `1,4,3,10,7,9,60, …` |
| `selfplay8mainb18.cfg`, `selfplay8midrun.cfg` | `:76-77` | mixed 7…19 | `1,4,3,10,7,9,75, …` |

**Key finding for the mission.** `selfplay1_maxsize9.cfg` / `gatekeeper1_maxsize9.cfg`
already exist as small-board presets, but they are `7,8,9` — **not** 9-only. A strict
9×9 run must override to `bSizes = 9` / `bSizeRelProbs = 1` (per
`RESEARCH_STATE.md` working context) in a mission-owned copy, since the mirror is
read-only (kernel §4). Full contents were not read line-by-line beyond these keys —
see `[OPEN] cfg-audit`.

### 5. Python dependency declarations

**There is no machine-readable dependency file.** Verified:
`find . -maxdepth 3 \( -iname "requirements*.txt" -o -iname "pyproject.toml" -o -iname
"setup.py" \)` (excluding `.git/`) returns **nothing**; `ls python/requirements*.txt
python/setup.py python/pyproject.toml` → all "No such file or directory".

Dependencies are declared in prose only, `SelfplayTraining.md:3`:
> "you must have [Python3](https://www.python.org/) and [Pytorch](https://pytorch.org/) installed"

No pinned version of Python, PyTorch, or NumPy is stated anywhere in the mirror's docs.
Runtime imports (`python/train.py`, `python/shuffle.py`, `python/katago/train/*.py`,
`python/muon/`) are the only remaining source of truth. See `[OPEN] pydeps`.

### 6. Build requirements — `Compiling.md`

| requirement | `Compiling.md` line |
|---|---|
| C++14-capable `g++` (Linux/OSX); MSVC 15 (2017)+ or MinGW on Windows | `:3` |
| CMake **≥ 3.18.2** | `:31` (also `cpp/CMakeLists.txt:1` `cmake_minimum_required(VERSION 3.18.2)`) |
| CUDA backend: **CUDA 11 or later** + a compatible cuDNN | `:34` |
| TensorRT backend: compatible CUDA Toolkit + **TensorRT ≥ 10** (older unsupported since v1.17.0) | `:35` |
| Eigen backend: Eigen3 (`libeigen3-dev`) | `:37` |
| **zlib, libzip** (`zlib1g-dev`, `libzip-dev`) | `:38` |
| backend selection | `:45` — `cmake . -DUSE_BACKEND=OPENCL\|CUDA\|TENSORRT\|EIGEN\|ROCM` |
| transformer models (version 17+) supported on all ROCm archs via built-in kernel | `:88-89` |

Cluster fit: B200/B300 are `sm_100`, so the `cluster-job` skill's `cuda/12.8.1` satisfies
the "CUDA 11 or later" floor with margin. `-DUSE_BACKEND=CUDA` is the path
`RESEARCH_STATE.md` selects; TensorRT is deferred there and needs TensorRT ≥ 10 if revived.

## `[OPEN]` items

- `[OPEN] nbt-export` — the fused `bottlenest*transformer*` kinds have no C++ string; the
  Python→C++ lowering to `transformer_attention_block` / `transformer_ffn_block` /
  `NESTED_BOTTLENECK_BLOCK_KIND` was inferred from the absence of the fused name in `cpp/`,
  not read in `python/export_model_pytorch.py`. **Closes when** the export path is read (or
  an `nbt` config is exported and the emitted block-kind strings dumped) and the mapping
  recorded. Only blocking if the mission switches from the `tf` family to the `nbt` family.
- `[OPEN] family-choice` — the mission's smoke config `b5c48h3tfr` is from the interleaved
  `tf` family; the `nbt` family is the one upstream's largest/most recent nets use. No
  measurement here says which is better at 9×9 and ≤4 GPUs. **Closes when** an empirical
  comparison is run, or the choice is recorded as a deliberate scope limit.
- `[OPEN] pydeps` — no pinned Python/PyTorch/NumPy versions exist upstream. **Closes when**
  the mission's own pinned `requirements.txt` is written under `results/ktg/` and a venv
  built from it imports `katago.train.model_pytorch` (exit 0) on a GPU node.
- `[OPEN] cfg-audit` — only `bSizes`/`bSizeRelProbs` were read out of the training configs.
  Search params, `numGameThreads`, `numSearchThreads`, table sizes, and `maxVisits` are
  unaudited and must respect the ≤24-CPU cap (`compute-budget` skill). **Closes when** the
  mission's 9×9 selfplay/gatekeeper configs are written with every thread count justified.
- `[OPEN] build-unverified` — no compile, no `katago benchmark`, no import of the training
  package has been executed. Everything above is code reading only (evidence type:
  literature grounding). **Closes when** `env_build` runs on a GPU node and exits 0.
- `[OPEN] export-name` — the mission must not copy the upstream doc string
  `python/export_model.py`; the real entry point is `python/export_model_pytorch.py`.
  **Closes when** the mission's loop scripts are written and grepped for the stale name.

## Verifier status

- **V1 acquisition** — PASS. `git rev-parse HEAD` = `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4`,
  equal to the SHA pinned in `mission.json`; `git describe --tags` = `v1.18.2`;
  `git status --short` empty. Recorded in `ref-code/lightvector-KataGo/PROVENANCE.md`.
- **V2 source import** — PASS. Declarations above; six residual gaps carry `[OPEN]`.
- **V3 decomposition** — not attempted at this stage (`pipelines/1-decompose`).

_Acquired 2026-09-04T01:34:19Z._
