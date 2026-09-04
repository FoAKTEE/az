# Evidence — code-path audit of the v1.18.2 self-play loop, configs, build, data (read-only)

Mirror `ref-code/lightvector-KataGo/` @ `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4` (`v1.18.2`, `cpp/main.cpp:245`).
Evidence type: literature grounding (code reading). Nothing executed. Paths relative to the mirror.
Produced by the decompose-stage worker audit, 2026-09-03; consumed by knowledge nodes
`selfplay_search_params`, `game_randomization_9x9`, `gating_rule`, `train_resume_semantics`,
`data_format_pos_len`, `training_window_shuffle`.

## A. `python/selfplay/synchronous_loop.sh`

Positional args (`:12-32`): `NAMEPREFIX BASEDIR TRAININGNAME MODELKIND USEGATING`, all required. `MODELKIND` enters at `:109`.

| var | value | line | consumer |
|---|---|---|---|
| NUM_GAMES_PER_CYCLE | 500 | :57 | `selfplay -max-games-total` :99 |
| NUM_THREADS_FOR_SHUFFLING | 8 | :58 | shuffle.sh arg 3 -> `-num-processes` :105 |
| NUM_TRAIN_SAMPLES_PER_EPOCH | 100000 | :59 | `-samples-per-epoch` :109 |
| MAX_TRAIN_PER_DATA | 8 | :60 | `-max-train-bucket-per-new-data` :109 |
| NUM_TRAIN_SAMPLES_PER_SWA | 80000 | :61 | `-swa-period-samples` :109 |
| BATCHSIZE | 128 | :62 | train.sh arg 4 |
| SHUFFLE_MINROWS | 100000 | :63 | `-min-rows` :105 |
| MAX_TRAIN_SAMPLES_PER_CYCLE | 500000 | :64 | `-max-train-bucket-size` :109 |
| TAPER_WINDOW_SCALE | 50000 | :65 | `-taper-window-scale` :105 |
| SHUFFLE_KEEPROWS | 600000 | :66 | `-keep-target-rows` :105 (overrides shuffle.sh:50 default 20000000) |

Cycle (`while true`, :93-116): gatekeeper -> selfplay -> shuffle -> train -> export. `#!/bin/bash -eu` + `set -o pipefail` (:1-2): any stage failure kills the loop.
Dirs: BASEDIR, logs, shufflescratch, selfplay, gatekeepersgf (:40-44); `scripts/dated/<ts>/bin` (:77). Configs copied from `cpp/configs/training/selfplay1.cfg` (:70) and `gatekeeper1.cfg` (:71) into the dated archive (:82-83). Needs a git worktree: `GITROOTDIR=$(git rev-parse --show-toplevel)` (:35), `git show/diff` (:84-86); runs from the dated snapshot (:75-89).
Invocations: gatekeeper :96 (`-rejected-models-dir … -accepted-models-dir … -sgf-output-dir … -test-models-dir … -config … -quit-if-no-nets-to-test`); selfplay :99 (`-max-games-total … -output-dir …/selfplay -models-dir …/models -config …`). `USEGATING` only reaches the exporter (:113); gatekeeper runs every cycle.

Resume after a mid-cycle kill:
- gatekeeper: restarts; candidate stays in `modelstobetested/` until rename `cpp/command/gatekeeper.cpp:591-598`/`:623-630`; `-quit-if-no-nets-to-test` -> `shouldStop` :524-525 -> return 0 :640-648; **also returns 0 when accepted-models-dir is empty** :399-402.
- selfplay: completed npz persist (`.npz.tmp` -> rename, `cpp/dataio/trainingwrite.cpp:1093-1096`); in-memory buffer (<= maxRowsPerTrainFile 10000) lost; `maxGamesTotal` is per-process (`cpp/command/selfplay.cpp:45,243,292-293`).
- shuffle: writes `shuffleddata/<ts>.tmp`, mv at `shuffle.sh:105`; train skips `.tmp` (`train.py:1210`); orphan `.tmp` never cleaned (`cleanup_old_dirs.py:12,18,22-24` keeps newest 3 older than 2 h).
- train: automatic (section B).
- export: **hazard** — `export_model_for_selfplay.sh:89` `rm -r "$SRC"` before gzip :90 and `mv "$TMPDST" "$TARGET"` :108; a kill in between leaves `<NAME>.exported` which the next run skips (:54-56).

## B. `train.sh` / `shuffle.sh` / `export_model_for_selfplay.sh` / `train.py`

Signatures: `train.sh BASEDIR TRAININGNAME MODELKIND BATCHSIZE EXPORTMODE [OTHERARGS]` (:10-29, :66-81); `shuffle.sh BASEDIR TMPDIR NTHREADS [OTHERARGS]`, env `SKIP_VALIDATE` (:7-21, :39); `export_model_for_selfplay.sh NAMEPREFIX BASEDIR USEGATING` (:8-22).
`train.sh:83-93` fixed flags: `-traindir`, `-latestdatadir`, `-exportdir`, `-exportprefix`, **`-pos-len 19` (hard-coded :88)**, `-batch-size`, `-model-kind`.
`-model-kind` used only without a checkpoint: `train.py:800-801`; on resume config comes from the checkpoint `train.py:850`.
Resume: `train.py:780` checks `checkpoint.ckpt` (`:573-574`), loads at `:796`; guard `:782-785`; shuffle-order state inside train_state (`python/katago/utils/training_data_generator.py:12-20`).

| flag | semantics | line |
|---|---|---|
| -samples-per-epoch | default 1000000 | train.py:81, :434-435 |
| -max-train-bucket-size | default 1e30 | :122, :436-437 |
| -max-train-bucket-per-new-data | bucket fill rate | :121, :1256 |
| -stop-when-train-bucket-limited | exit instead of sleep(300) | :124, :1440-1451 |
| -quit-if-no-data | exit 0 if no data | :130, :1219-1232 |

Files: `checkpoint.ckpt` + `checkpoint_prev{0,1,2}.ckpt` once per epoch (`:1875`, `:614-622`, keep 4 `:578`); `<exportdir>/<prefix>-s<samples>-d<rows>/model.ckpt` every `epochs_per_export` (default 1, `:1845-1861`, `:438-439`); `longterm_checkpoints/<ts>.ckpt` every 12 h (`:1884-1889`); `metrics_train.json`/`metrics_val.json` (`:1350-1351`). **No TensorBoard** anywhere in python/. Latest data dir by mtime excluding `*.tmp` (`:1206-1213`).

## C. `python/export_model_pytorch.py`

CLI (:34-42): `-checkpoint` | `-export-random-initialized-model` (exactly one, :57-58), `-export-dir`, `-model-name`, `-filename-prefix` (required), `-use-swa`, `-export-14-as-15`, `-export-15-or-16-as-17`, `-attn-logit-bound-limit` (default 2.5e4), `-ignore-attn-logit-bound`. Emits `<prefix>.bin` (:120-122, `@BIN@` floats :220-226), `metadata.json` (:682), `log.txt` (:70); `.bin.gz` is made by `export_model_for_selfplay.sh:90`; `model.ckpt` by clean_checkpoint.py (:84-86).
Block lowering `write_block` :469-504: ResBlock -> `ordinary_block`/`gpool_block` (:470-478); NestedBottleneckResBlock -> `nested_bottleneck_block` (:482-490); TransformerAttentionBlock -> `transformer_attention_block` (:491-492 -> :420); TransformerFFNBlock -> `transformer_ffn_block` (:493-494 -> :457); **NestedBottleneckTransformerBlock -> `nested_bottleneck_block` with `2*internal_length` then its blockstack** (:495-502; blockstack built at `model_pytorch.py:1958-1977`); else assert (:503-504). Refuses QK-norm/GAB/TAB/registers (:409-418) and FFN depthwise conv (:450-455). Kind->class: `attnrope` `model_pytorch.py:3231-3239`, `ffng` :3278-3284, `ffnsg` :3269-3276, `bottlenest2transformerrope*` :3286+. => `[OPEN] nbt-export` closed; `b5c48h3tfr` is exportable.

## D. Training configs (`selfplay1_maxsize9.cfg` differs from `selfplay1.cfg` only at :95-97; gatekeeper pair only at :38-40)

| key | selfplay1_maxsize9 | line | gatekeeper1_maxsize9 | line |
|---|---|---|---|---|
| numGameThreads | 128 | :84 | 128 | :18 |
| numSearchThreads | 1 | :116 | 1 | :50 |
| nnMaxBatchSize | 128 | :120 | 128 | :54 |
| nnCacheSizePowerOfTwo / nnMutexPoolSizePowerOfTwo | 21 / 15 | :121-122 | 21 / 15 | :55-56 |
| numNNServerThreadsPerModel | 1 | :123 | 1 | :57 |
| nnRandomize | true | :124 | true | :58 |
| maxVisits | 600 | :115 | 150 | :49 |
| cheapSearchProb / cheapSearchVisits / cheapSearchTargetWeight | 0.75 / 100 / 0.0 | :60-62 | absent | |
| rootPolicyTemperatureEarly / rootPolicyTemperature | 1.25 / 1.1 | :168-169 | absent | |
| rootNoiseEnabled; rootDirichletNoiseTotalConcentration / Weight | true; 10.83 / 0.25 | :144-146 | absent | |
| rootDesiredPerChildVisitsCoeff | 2 | :148 | absent (0.0) | |
| chosenMoveSubtract / chosenMovePrune | 0 / 1 | :141-142 | 0 / 1 | :75-76 |
| chosenMoveTemperature / Early / Halflife | 0.15 / 0.75 / 19 | :138-140 | 0.2 / 0.5 / 19 | :72-74 |
| estimateLeadProb | 0.05 | :78 | absent | |
| komiAuto / komiStdev / komiBigStdevProb / komiBigStdev | True / 1.0 / 0.06 / 12.0 | :99-103 | True | :42 |
| handicapProb / handicapCompensateKomiProb | 0.10 / 0.50 | :105-106 | 0.0 / 1.0 | :44-45 |
| forkCompensateKomiProb / sgfCompensateKomiProb | 0.80 / 0.90 | :107-108 | absent | |
| startPosesProb / hintPosesProb | commented out | :37, :45 | commented out | :11 |
| maxMovesPerGame | 1600 | :85 | 1600 | :19 |
| allowResignation / resignThreshold / resignConsecTurns | absent | | true / -0.90 / 5 | :22-24 |
| bSizes / bSizeRelProbs / allowRectangleProb | 7,8,9 / 1,1,8 / 0.50 | :95-97 | 7,8,9 / 1,1,8 / 0.50 | :38-40 |
| switchNetsMidGame | true | :79 | absent | |
| dataBoardLen | **19** | :16 | n/a | |
| maxRowsPerTrainFile / firstFileRandMinProp / maxDataQueueSize | 10000 / 0.15 / 2000 | :19 / :20 / :18 | n/a | |
| cudaDeviceToUse* | all commented out | :127-131 | same | :61-65 |
| numGamesPerGating | | | 200 | :20 |
| required win prop | | | CLI `-required-candidate-win-prop`, default 0.5 (`cpp/command/gatekeeper.cpp:271`), not passed by synchronous_loop.sh | |

No `forcedPlayouts` key exists; the mechanism is `rootDesiredPerChildVisitsCoeff` (`cpp/program/setup.cpp:645-647`; `cpp/search/searchexplorehelpers.cpp:167-169` returns 1e20). Target pruning: `chosenMoveSubtract`/`chosenMovePrune` (`setup.cpp:671-676`; caps `searchupdatehelpers.cpp:224-225`, `searchresults.cpp:318-319`). `useNoisePruning` false for `SETUP_FOR_OTHER` (`setup.cpp:578`; `selfplay.cpp:110`).

Thread model: `numGameThreads` OS threads (`selfplay.cpp:360-361`; gatekeeper `:551-552`); search spawns numThreads-1 (`searchmultithreadhelpers.cpp:40,50-52`); `numNNServerThreadsPerModel` per model (`setup.cpp:194,203`); 1 dataWriteLoop per model (`selfplaymanager.cpp:156`); 1 modelLoadLoop (`selfplay.cpp:364`); main.

| job | default OS threads | value for <= 24 |
|---|---|---|
| selfplay 1 GPU | 128+1+1+1+1 ≈ 132 (134 during net switch) | numGameThreads 18, numSearchThreads 1, numNNServerThreadsPerModel 1 -> 22 (+2 transient) |
| selfplay 4 GPUs | | numGameThreads 14, numNNServerThreadsPerModel 4 -> 21 (+3) |
| gatekeeper (2 models) | 128+2+1 ≈ 131 | numGameThreads 20 -> 23 |
| shuffle | 8 processes (`synchronous_loop.sh:58` -> `shuffle.py:791`) | <= 8 |
| train | 1 proc/GPU + `-data-prefetch-depth` 1 (`train.py:126`); torch intra-op default nproc | set OMP_NUM_THREADS explicitly |

## E. `benchmark`, `genconfig`, selfplay model discovery

`katago benchmark` (`cpp/command/benchmark.cpp:174`, args :191-234): `-config`, `-model`, `-v/-visits` (800 default), `-t/-threads` ("" = sweep, :267-268), `-n/-numpositions` 10, `-sgf`, **`-boardsize` 7..19 (:199-206, exclusive with -sgf :249-250)**, `-s/-tune`, `-i/-time` 5.0, `-fixed-batch-size`, `-half-batch-size`, `-no-server-thread-test`, `-no-half-batch-size-test`, `-override-config`. Overrides maxVisits/maxPlayouts from -visits (:316-317), maxTime=1e20 (:318), ignores numSearchThreads (:331) and nnMaxBatchSize (:332-333).
`katago genconfig` lives in `benchmark.cpp:922`, flags `-model` :931, `-output` :933; **interactive** (getline loop :946-969; throws on closed stdin :967).
`katago selfplay` requires `-config` :48, `-models-dir` :51, `-output-dir` :52; `-max-games-total` :53. Model discovery `cpp/dataio/loadmodel.cpp:58` `findLatestModel`: recursive any depth (:65), suffixes `.bin.gz`/`.bin`/`model.txt.gz`/`model.txt` (:20-25,:67), latest by mtime (:68-73), name = parent dir for generic filenames (:26-48,:84-89). **Empty dir => modelName "random", modelFile /dev/null (:77-80)**, `debugSkipNeuralNet` (`setup.cpp:126-130`) -> random-net games into `selfplay/random/`. New-net poll 20 s (`selfplay.cpp:350`, thread :364).

## F. Data volume

Outputs `selfplay/<model>/sgfs/<hex>.sgfs`, `selfplay/<model>/tdata/<hex>.npz` (`selfplay.cpp:176-178,186-188,224`; `trainingwrite.cpp:1092`); flush at 10000 rows, first file short (`firstFileRandMinProp`, `trainingwrite.cpp:1039`).
Per-row bytes (arrays `trainingwrite.cpp:292-299`; packing :288, :314-334; `hasMetadataInput=false` :1030):

| array | posLen 19 | posLen 9 |
|---|---|---|
| binaryInputNCHWPacked u8 22*ceil(L^2/8) | 1012 | 242 |
| globalInputNC f32 19*4 | 76 | 76 |
| policyTargetsNCMove i16 2*(L^2+1)*2 | 1448 | 328 |
| globalTargetsNC f32 80*4 | 320 | 320 |
| scoreDistrN i8 2L^2+120 | 842 | 282 |
| valueTargetsNCHW i8 5*L^2 | 1805 | 405 |
| required subtotal | 5503 | 1653 |
| qValueTargetsNCMove i16 3*(L^2+1)*2 | 2172 | 492 |
| total | 7675 | 2145 |

Cross-check `shuffle.py:39-41` (`UNCOMPRESSED_BYTES_PER_ROW_REQUIRED_19 = 5503`, `_QVALUES_19 = 2172`), compressed fraction 0.12 (`shuffle.py:47`).
Rows per turn = floor(w) + Bernoulli(frac(w)) (`trainingwrite.cpp:1206-1251`), w = 0 on cheap-search turns (`play.cpp:1143`) => ~75 % of turns yield no row; side positions `sidePositionProb=0.020` (`play.cpp:2206`). Assuming ~80 moves/game: ~22 rows/game => ~47 KB uncompressed / ~5.7 KB on disk per game at posLen 9 (169 KB / 20 KB at posLen 19).
`dataBoardLen=19` at `selfplay1_maxsize9.cfg:16` with the comment :10-14 saying it must match `-pos-len`; enforced at `python/katago/train/data_processing_pytorch.py:91`.
`shuffle.py` defaults: `-keep-target-rows` required (:779, "all" :812-815), `-expand-window-per-row` 1.0 (:780), `-taper-window-exponent` 1.0 (:781), `-taper-window-scale` None->min_rows (:782, :420-421), `-min-rows` None->250000 (:777, :865-867), `-approx-rows-per-out-file` 70000 (:787), `-num-processes` required (:791), `-out-tmp-dir` (:862-863). Output `np.savez_compressed` (:146-149) `out-dir/data<b>_<i>.npz` + `<out-dir>.json` range (:1330-1335) read by `train.py:1226-1241`; refuses non-empty out-dir (:1079-1083); tmp buckets rmtree'd (:1213-1216, :1239, :377-380).

Footprint growth: `selfplay/<model>/tdata|sgfs` monotonic, never pruned; `shuffleddata/<ts>` ≈ keep-target-rows x row bytes x 0.12 per cycle, newest 3 kept; `train/<name>/` 4 short-term ckpts + `longterm_checkpoints` every 12 h never pruned (`train.py:578,1884-1889`); `models/`, `modelstobetested/`, `rejectedmodels/` one dir per net, never pruned; `scripts/dated/<ts>/` one archive per loop restart (`synchronous_loop.sh:78-81`).

## G. Build (`cpp/CMakeLists.txt`)

`USE_BACKEND=CUDA` option :583-585, block :717-782 (sources :724-728); `find_package(CUDAToolkit REQUIRED)` :1123; cuDNN header `find_path(... HINTS ${CUDNN_ROOT_DIR} ... PATH_SUFFIXES include)` :1124 (FATAL :1125-1127); library `find_library(CUDNN_LIBRARY cudnn HINTS ${CUDNN_ROOT_DIR} ... PATH_SUFFIXES lib64)` :1128 — the pip wheel ships `lib/`, so `-DCUDNN_LIBRARY=<abs>/libcudnn.so` must be explicit; link :1143.
**Arch list :760-762 for CUDA >= 12.8 (< 13.0): `set(CMAKE_CUDA_ARCHITECTURES 50 52 53 60 61 62 70 72 75 80 86 87 90 120)` — sm_100 absent; only the >= 13.0 branch (:757-758) has 100. The set() is unconditional (shadows -D).**
Options: `BUILD_DISTRIBUTED` 0 :582; `USE_AVX2` 0 :589 (Eigen only :823-825); `USE_CACHE_TENSORRT_PLAN` 0 :592; `NO_CUTLASS_FUSED_FFN` 0 :598 (auto-enables with external/cutlass + CUDA >= 11.4, :732-747); `NO_CUDNN_SDPA` 0 :599-601.
cuDNN gates: `cpp/neuralnet/cudabackend.cpp:13` `#if CUDNN_VERSION >= 8903 && !defined(NO_CUDNN_SDPA)` (else `KATAGO_CUDA_HAS_SDPA 0` :22); `cudaandrocmbackend.inc:918,1039,1047,1057,1124,1189` `CUDNN_MAJOR >= 8`. Vendored cudnn-frontend :1130 (json include-order note :9-12).
zlib :1823-1826; libzip :1884-1886, missing => warning + `NO_LIBZIP` (:1891-1892) "selfplay for writing training data will not be possible" => required here.

## H. Python dependencies (no requirements/pyproject/setup upstream)

torch (`train.py:33,37`; `export_model_pytorch.py:17-19`), numpy (`export_model_pytorch.py:13`), packaging (`load_model.py:7-8`, `model_pytorch.py:10-11`; gates :13 `> 2.4.0`, :77 `> 1.6.0`), psutil (`shuffle.py:14,109`), scipy only in `katago/utils/elo.py:5-6` via `summarize_sgfs.py:2-3`. Torch floor: `torch.amp.GradScaler` (`train.py:37`, >= 2.3), `torch.compile` / flex_attention (`trainloop_helpers.py:129,154-157,184,219`, >= 2.5). `torch==2.11.0+cu128` satisfies all.

## `[OPEN]` raised by this audit

cuda-arch-sm100 (blocking), cudnn-wheel-layout, export-kill-window, selfplay-random-net, torch-threads, pos-len-9; closed: nbt-export; narrowed: cfg-audit, pydeps (candidate set above).
