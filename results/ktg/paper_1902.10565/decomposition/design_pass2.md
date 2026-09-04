# Design: one-node 9x9 transformer KataGo training

## 1. Outcome and invariants

Build a reproducible v1.18.2 path from random 9x9 self-play through shuffle, PyTorch training, current-format export, gatekeeper promotion, and a fixed-budget match against the first network. The 2019 paper is background vocabulary only. The source of truth is the current code, especially the five-stage loop at `ref-code/lightvector-KataGo/python/selfplay/synchronous_loop.sh:91-116`. Unless a different root is written explicitly, shortened code anchors below resolve under `ref-code/lightvector-KataGo/`.

Hard invariants:

- One Slurm node; at most 4 GPUs, 24 allocated CPUs, and `3-00:00:00`. Request b300 first; submit the identical manifest to b200 (B200 GPUs with 180 GB each) only if b300 cannot start. Exact module/constraint strings are `[OPEN]` cluster facts.
- All mutable state lives below one mission run directory; shuffle temporary data gets a separate child path on the same scratch filesystem. No training data enters the repository.
- Every job revalidates its effective config, device count, free bytes, and last checkpoint before starting work.
- Every stage is bounded so the job can finish or checkpoint by hour 60, reserving 12 hours for a slow final epoch, export, gate, and clean exit.

## 2. Environment and build

Create the virtual environment inside the run directory. Install `torch==2.11.0+cu128` from the PyTorch cu128 index and `nvidia-cudnn-cu12>=9.8` from PyPI, plus NumPy and psutil. The exact compatible Python/module combination is `[OPEN]` until the node smoke. A concrete environment seed is:

```bash
python -m venv "$RUN/venv"
"$RUN/venv/bin/python" -m pip install --upgrade pip
"$RUN/venv/bin/python" -m pip install --index-url https://download.pytorch.org/whl/cu128 'torch==2.11.0+cu128'
"$RUN/venv/bin/python" -m pip install 'nvidia-cudnn-cu12>=9.8' numpy psutil
```

Validate exact Torch/CUDA versions, `torch.cuda.is_available()`, and cuDNN integer version ≥90800 before building.

The C++ build is out of tree with `USE_BACKEND=CUDA`, `USE_TCMALLOC=1`, and `NO_GIT_REVISION=1`. The latter avoids build-time VCS inspection. The pip cuDNN wheel commonly stores headers under `nvidia/cudnn/include` and libraries under `nvidia/cudnn/lib`; discover that path with `importlib.metadata.distribution("nvidia-cudnn-cu12").locate_file("nvidia/cudnn")`, then pass `CUDNN_INCLUDE_DIR` and `CUDNN_LIBRARY` explicitly. KataGo's CMake lookup is at `ref-code/lightvector-KataGo/cpp/CMakeLists.txt:1120-1143`; required build dependencies are at `ref-code/lightvector-KataGo/Compiling.md:31-53`. Export the wheel library directory through `LD_LIBRARY_PATH` for runtime.

The environment gate is:

```bash
python -c 'import torch; assert torch.__version__=="2.11.0+cu128"; assert torch.version.cuda=="12.8"; assert torch.cuda.is_available(); assert torch.backends.cudnn.version()>=90800'
nvcc --version
"$RUN/build/katago" version
```

## 3. Smoke-first order

1. Export a random `b5c48h3tfr` with `python/export_model_pytorch.py -export-random-initialized-model ...`; these flags and their mutual exclusion are defined at `python/export_model_pytorch.py:33-43,57-60,78-87`.
2. Load it through `katago benchmarknn -boardsize 9 -require-exact-nnlen -batch-size 2 -warmup 1 -iterations 2 -json`. This crosses the Python exporter/C++ descriptor boundary (`cpp/neuralnet/desc.cpp:1480-1557`; `cpp/command/benchmarknn.cpp:49-92`).
3. Run a disposable finite copy of one synchronous cycle. Use 4 games, `maxVisits=8`, `cheapSearchVisits=2`, batch 8, shuffle minimum 1, keep 256, 64 samples/epoch, 64 samples/SWA, and at most 128 train samples. These values are `[OPEN]` smoke settings, not strength settings.
4. Require raw and shuffled NPZs, a resumable checkpoint, an SWA export loadable by C++, and only `SZ[9]` SGFs. Any failure stops production.

The upstream loop is infinite and performs archival VCS commands (`python/selfplay/synchronous_loop.sh:73-93`). The mission-owned smoke wrapper preserves the exact gatekeeper, self-play, shuffle, train, and export commands at lines 95-113, but executes one cycle and records a manifest without running those archival commands.

## 4. Model ladder

Start and complete the first end-to-end run with `b5c48h3tfr`: model version 17, five repeated `attnrope`/`ffng` pairs, 48 trunk channels, three heads, and a 128-channel FFN (`python/katago/train/modelconfigs.py:986-1006`). It is the smallest registered tf-family member, so it minimizes memory and iteration cost while testing every transformer-specific serialization and training path. The PyTorch attention/FFN implementation and block dispatch are at `python/katago/train/model_pytorch.py:2079-2129,2502-2536,3231-3285`.

Scale only after b5 has produced an accepted successor and a measured baseline match:

1. b5: establish correctness, throughput, data-window behavior, and Elo/GPU-hour.
2. b7c96h3tfrs: first width/depth and SwiGLU increase (`modelconfigs.py:1008-1028`).
3. b8c96h3tfrs: add one block at the same width (`modelconfigs.py:1057-1077`).
4. `b14c192h6tfrs`, then optionally its learnable-RoPE variant, only if the smaller run leaves ≥10% VRAM headroom and its projected cycle is ≤60 hours (`modelconfigs.py:1873-1898`). A later NBT-family branch is separate and `[OPEN]`.

Each architecture is a fresh run with its own first net. A different model config is never resumed from a b5 checkpoint. Admit a larger model only when export/load smoke passes, its largest stable batch is known, and accepted Elo gain per GPU-hour improves.

## 5. Strict 9x9 enforcement

Create mission-owned config copies; never edit the mirror presets.

Self-play derives from `cpp/configs/training/selfplay1_maxsize9.cfg`, but that preset allocates length 19 and samples 7, 8, and 9 (`:11-16,95-97`). Override:

```text
dataBoardLen = 9
bSizes = 9
bSizeRelProbs = 1
allowRectangleProb = 0
```

Gatekeeper derives from `gatekeeper1_maxsize9.cfg`, which also mixes 7/8/9 (`:38-40`). Give it the last three values above. Retain `numGamesPerGating=200`, `maxVisits=150`, and one search thread (`:18-20,49-50`).

Training uses a mission-owned copy of `python/selfplay/train.sh` with its hard-coded `-pos-len 19` changed to `-pos-len 9` (`:83-93`). Do not rely on a forwarded duplicate flag. The smoke audit checks spatial tensor length 81, policy length 82, checkpoint `pos_len=9`, and every SGF root `SZ[9]`. The fixed evaluation match likewise sets only size 9 and disables rectangles.

## 6. Search and learning knobs

Keep target semantics fixed while changing scale:

- Playout Cap Randomization: the preset uses `cheapSearchProb=0.75`, `cheapSearchVisits=100`, `cheapSearchTargetWeight=0`, and main `maxVisits=600` (`selfplay1_maxsize9.cfg:60-68,115`). For pilot cycles use `[OPEN]` 128/32, then 300/64, then 600/100. Keep probability and target weight unchanged.
- Forced playouts: keep `rootDesiredPerChildVisitsCoeff=2` (`selfplay1_maxsize9.cfg:148`); current code allocates desired child visits proportional to the square root of policy mass (`cpp/search/searchexplorehelpers.cpp:165-169`).
- Policy target pruning: make inherited defaults explicit with `useNoisePruning=true`, `noisePruneUtilityScale=0.15`, and its existing cap. The implementation downweights excessive child visits according to raw policy share and utility gap (`cpp/search/searchupdatehelpers.cpp:495-538`; defaults `cpp/program/setup.cpp:576-584`).
- Data-side auxiliary sampling: retain `policySurpriseDataWeight=0.5`, `valueSurpriseDataWeight=0.1`, and `estimateLeadProb=0.05` (`selfplay1_maxsize9.cfg:75-78`).
- Train-side auxiliary losses: begin with code defaults `soft-policy-weight-scale=8`, value loss 0.6, TD value loss 0.6/0.6/0.6, seki 1, and variance-time 1 (`python/train.py:140-152`). Monitor every component; policy, soft-policy, optimistic-policy, value/TD, ownership, scoring, future-position, seki, score, and score-belief losses are composed at `python/katago/train/metrics_pytorch.py:531-608,735-882`.
- Learning-rate warm-up: the default schedule does not reach full scale until 2 million samples (`python/train.py:1056-1079`), and AdamW/Muon additionally scale with the square root of global batch (`python/train.py:1138-1142`). Treat the tiny and first 200k-sample passes as pipeline verification; do not claim strength until the b5 run has crossed 2 million samples, unless an explicit alternative schedule is separately validated `[OPEN]`.

No target coefficient changes in the same experiment as a visits/model-size change. Since b5 does not request Q-value prediction, pass `-exclude-qvalues` to the shuffler and verify training input compatibility; the flag is defined at `python/shuffle.py:800-801`.

## 7. GPU/CPU allocation

Default smoke and pilot request 2 GPUs and 24 CPUs. Stages time-share the allocation:

| stage | GPUs | CPU budget | effective settings |
|---|---:|---:|---|
| self-play | 2 | 16 game + 2 NN + 6 orchestration/I/O margin | `numGameThreads=16`, `numSearchThreads=1`, two NN server threads mapped one/GPU, batch tuned from 32 |
| shuffle | 0 | 8 workers + margin | wrapper positional `NTHREADS=8`; `-num-processes` is wired at `python/selfplay/shuffle.sh:39-54` |
| train | 2 | ≤16 worker threads + margin | `-multi-gpus 0,1`, bf16, `OMP_NUM_THREADS=8`, `MKL_NUM_THREADS=8`, prefetch depth 1 |
| export | 0 | 2 | one exporter process, then gzip |
| gatekeeper | 2 | 12 game + 2 NN/model + margin | `numGameThreads=12`, `numSearchThreads=1`; both models get identical GPU opportunity |

The preset's `numGameThreads=128` is deliberately high for larger machines (`selfplay1_maxsize9.cfg:84`); it is not compatible with this job's CPU cap. Count actual task/thread usage with `sstat` and process metrics, not merely configuration integers.

Only after stage timing, a 4-GPU steady-state variant may allocate 3 GPUs/14 CPUs to self-play (11 game threads, 3 NN threads), 1 GPU/6 CPUs to training, and reserve 4 CPUs for shuffle/export/control. This 3:1 ratio is below the documentation's broad 4x–40x self-play/training compute guidance (`SelfplayTraining.md:29-32`) and is therefore `[OPEN]`. Use disjoint `CUDA_VISIBLE_DEVICES` masks. Pause self-play while shuffle is CPU-active; pause training and lend its GPU during gatekeeper. Keep the 2-GPU synchronous plan if concurrency lowers games/hour, samples/s, or checkpoint reliability.

## 8. Pipeline and data windows

Use each v1.18.2 stage as implemented:

- self-play: `katago selfplay -max-games-total N -output-dir "$RUN/selfplay" -models-dir "$RUN/models" -config "$CFG/selfplay9.cfg"` (`synchronous_loop.sh:98-99`).
- shuffle: `SKIP_VALIDATE=1 ./shuffle.sh "$RUN" "$SHUFFLE_TMP" 8 -min-rows M -keep-target-rows K -taper-window-scale S -exclude-qvalues` (`synchronous_loop.sh:101-105`; `shuffle.sh:39-54`). The wrapper already sets expand 0.4 and taper exponent 0.65.
- train: mission `train9.sh` plus `-samples-per-epoch`, `-swa-period-samples`, `-quit-if-no-data`, `-stop-when-train-bucket-limited`, `-no-repeat-files`, `-max-train-bucket-per-new-data`, and `-max-train-bucket-size` exactly as the loop does (`synchronous_loop.sh:108-109`).
- export: `./export_model_for_selfplay.sh ktg9 "$RUN" USEGATING`; internally this invokes `export_model_pytorch.py -checkpoint ... -use-swa` (`export_model_for_selfplay.sh:77-90`). Use `USEGATING=0` exactly once for the first accepted net, then 1.
- gate: exact directory CLI at `synchronous_loop.sh:95-96`; acceptance arithmetic is in `cpp/command/gatekeeper.cpp:579-630`.

Pilot at 500 games/cycle, minimum 50k rows, keep 300k, 50k samples/epoch, maximum reuse 4, and maximum 200k train samples/cycle. For the bootstrap train, set `-max-epochs-this-instance 4 -epochs-per-export 4` so `USEGATING=0` admits exactly one first network; export cadence defaults to every epoch otherwise (`python/train.py:434-443,1827-1862`). If random play produces fewer than 50k rows, add games rather than bypassing the minimum. After two clean cycles, move to the loop's 100k minimum, 600k kept rows, 100k samples/epoch, and 500k cap (`synchronous_loop.sh:57-66`). Kept rows must exceed the train cap. The rolling window grows with expand 0.4 and exponent 0.65; its exact formula is `python/shuffle.py:414-435,718-747`.

Advance games, window, and visits one axis at a time. Require projected completion by hour 60, reuse≤4, no-data waiting<10%, GPU duty cycle≥70%, and no loss/invalid-game regression. All thresholds in this paragraph are `[OPEN]` operating gates.

## 9. Checkpoint and 72-hour restart

`train.py` atomically writes `checkpoint.ckpt`, preserves previous/short-term copies, resumes model/optimizer/SWA/global counters, and makes long-term checkpoints every 12 hours (`python/train.py:573-623,779-796,943-982,1827-1889`). Each Slurm instance adds `-max-epochs-this-instance` and/or `-max-training-samples` so normal termination occurs before hour 60. The outer runner handles `SIGTERM`: stop starting games, send `SIGINT` to training, wait for the checkpoint, export only a fully written checkpoint, record state, and exit.

Resubmission uses the same run directory and same model kind/pos_len. A smoke-only interruption test must show monotonic global samples/SWA count and no duplicate export. `-no-repeat-files` protects the within-shuffle data stream; new atomic shuffle directories are selected only after completion (`python/train.py:1185-1281`).

## 10. Scratch budget

Scratch is about 94% of 40 TB full, leaving about 2.4 TB nominally free `[OPEN]`; this mission may consume at most 200 GiB and may not start a new cycle above 180 GiB.

For 9x9, adapting the array layout documented at `python/shuffle.py:25-45` gives an uncompressed estimate of about 1,653 bytes/required row and 492 additional Q-value bytes `[OPEN]`. The code's 0.12 compression factor was measured only for 19x19, so planning uses a much more conservative 1 KiB per stored 9x9 row and then measures real bytes/row after 100k rows.

| allocation | cap |
|---|---:|
| raw self-play, including old cycles | 80 GiB |
| latest two shuffled generations | 40 GiB |
| shuffle temporary shards/waves | 20 GiB |
| checkpoints, SWA exports, accepted/rejected models | 20 GiB |
| SGFs, logs, environment, build | 10 GiB |
| recovery contingency | 30 GiB |
| total | 200 GiB |

At 1 KiB/row, 80 GiB represents roughly 83.9 million rows. Record `du -sb` and `df -B1` before/after every stage. Stop at 180 GiB, preserve the final 20 GiB for atomic checkpoint/export recovery, and archive/delete nothing automatically. Use `shuffle.py -dry-run-print-resource-cost` only as a 19x19 upper-comparison, not a calibrated 9x9 answer (`:459-480,762-790`).

## 11. Evaluation

Gatekeeper uses 200 strict-9x9 games and required candidate win proportion 0.5; current code gives ties to the candidate (`cpp/command/gatekeeper.cpp:247-306,579-630`). Operational improvement is the number of accepted model directories beyond the frozen first network, reconciled against logged `Candidate won match` decisions. Required minimum: at least one accepted successor.

Strength improvement is a separate `[OPEN]` 400-game, color-balanced match between the latest accepted and first network. The mission match config fixes 9x9, rectangles off, equal 150 visits, one search thread, and 12 game threads. Invoke `katago match -config ... -log-file ... -sgf-output-dir ...` as in `cpp/configs/match_example.cfg:1-15`. Report W/L/D and `p=(W+0.5D)/N`, `Elo=400 log10(p/(1-p))`, plus a 95% interval. “Improves under self-play” requires both at least one gate acceptance and positive point Elo; label it statistically supported only when the interval excludes zero.

## 12. Top five risks and detection signatures

1. **9x9 leakage.** Signature: any `SZ` other than 9, policy length other than 82, spatial length other than 81, or checkpoint `pos_len!=9`. Stop before training/gating.
2. **Python/C++ CUDA-cuDNN incompatibility.** Signature: cuDNN version assertion fails, CMake cannot resolve `cudnn.h`/`libcudnn.so.9`, exporter output raises unknown transformer block, or benchmark falls back from CUDA. Detect in the two export/load smokes.
3. **CPU oversubscription or starved GPU batching.** Signature: throttling/context switching, load far above 24, low GPU duty cycle, growing NN queue, or games/hour falling when threads rise. Reduce game/OMP workers; compare 2-GPU synchronous against the `[OPEN]` 3:1 split.
4. **Scratch exhaustion during shuffle.** Signature: run size >180 GiB before a cycle, free space crossing the 200-GiB mission reserve, shard count/temp estimate spike, `.tmp` output, or `ENOSPC`. Do not begin the stage; reduce kept rows or use more waves after measurement.
5. **False progress or corrupt resume.** Signature: zero accepted successors, latest-vs-first Elo≤0, 95% interval spanning 0, global sample/SWA counters regress, repeated input files, duplicate candidate name, NaN loss, or a gate with fewer than 200 attributable `SZ[9]` games. Report “not demonstrated”; restore an atomic previous checkpoint and do not advance scale.
