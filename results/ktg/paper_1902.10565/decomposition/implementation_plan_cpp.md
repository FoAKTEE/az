# Implementation plan — C++ / engine · mission `ktg-train` (paper_arxiv-1902.10565)

Partitioned by `logic.md` DAG node. **CODE-FIRST**: the v1.18.2 mirror
`ref-code/lightvector-KataGo/` @ `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4` is the source of
truth; `path:line` anchors are relative to it unless prefixed `codes/`
(= `results/ktg/paper_1902.10565/codes/`).

**No patch is applied to the engine.** Mission C++-side work is configs and one build-time
CMake change to the *scratch build clone only* (`codes/env/cmake-sm100.diff`, kernel §4 keeps
the mirror read-only). Nothing here has been executed.

Every job launch is preceded by
`bash "$POLICY_CHECK" --gpus 1 --cpus 24 --partition b200`.

---

## env_build

Predecessors: none.

| item | value |
|---|---|
| files (already exist) | `codes/env/env_build.sbatch`, `codes/env/env.sh`, `codes/env/cmake-sm100.diff` |
| cmake invocation | `cmake .. -DCMAKE_BUILD_TYPE=Release -DUSE_BACKEND=CUDA -DCUDNN_ROOT_DIR=$CUDNN_DIR -DCUDNN_INCLUDE_DIR=$CUDNN_DIR/include -DCUDNN_LIBRARY=$CUDNN_DIR/lib/libcudnn.so` (`env_build.sbatch:159-166`) |
| why `-DCUDNN_LIBRARY` must be an absolute path | `cpp/CMakeLists.txt:1128` searches `PATH_SUFFIXES lib64`; the `nvidia-cudnn-cu12` wheel ships `lib/` only, and only `libcudnn.so.9` — the job also symlinks `libcudnn.so` (`env_build.sbatch:113-115`) |
| other build anchors | `USE_BACKEND` option `CMakeLists.txt:583-585`; CUDA block `:717-782`; `find_package(CUDAToolkit REQUIRED)` `:1123`; cuDNN header search `:1124-1127`; link `:1143`; libzip required for training-data writing `:1884-1892`; `BUILD_DISTRIBUTED` stays 0 `:582` |
| sm_100 | `CMakeLists.txt:761` (CUDA ≥12.8 branch) sets `50 52 53 60 61 62 70 72 75 80 86 87 90 120` — **no 100**, and the plain `set()` shadows any `-DCMAKE_CUDA_ARCHITECTURES`. The ≥13.0 branch `:757-758` already has 100. Mission fix: `codes/env/cmake-sm100.diff` inserts `100` into the `:761` list, applied to the scratch clone at `env_build.sbatch:137-146` (a recorded diff rather than an inline `sed`; equivalent and reviewable). Alternative accepted by design: build under `cuda/13.0.2` |
| cuobjdump check | `cuobjdump --list-elf $KATAGO_BIN \| grep -c sm_100` must be > 0 (`env_build.sbatch:216-221`) |
| cuDNN SDPA gate | `cpp/neuralnet/cudabackend.cpp:13` compiles the SDPA path only when `CUDNN_VERSION >= 8903 && !NO_CUDNN_SDPA`; record the linked version (`ldd` + `cudnn_version.h`, `env_build.sbatch:117-122`) — obligation `o05_cudnn_version_sdpa` |
| verification command | `katago version`; `katago runtests`; the cuobjdump check; `katago benchmark -boardsize 9`; `torch_smoke.py` (`env_build.sbatch:196-289`) |
| metric + tolerance | every smoke stage exits 0 (`SMOKE RESULT: PASS`, `env_build.sbatch:293-296`); `sm_100` count ≥1; benchmark visits/s > 0 |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/env/smoke-<jobid>.txt` |

`[OPEN] env-build-outcome` — the build job was submitted by another worker (Slurm 297952,
gb205) and its result is not on record here. Closes when `evidence/env/smoke-<jobid>.txt` exists
and reads `SMOKE RESULT: PASS`.

---

## cfg_9x9_override

Predecessors: `selfplay_search_params`, `game_randomization_9x9`, `gating_rule`,
`data_format_pos_len`.

Two mission-owned cfg files, each a copy of its upstream preset with **only** the keys listed
below changed. Everything not listed is byte-identical to the preset.

### `codes/cfg/selfplay_9x9.cfg` ← `cpp/configs/training/selfplay1_maxsize9.cfg`

| key | preset value | preset line | mission value | reason |
|---|---|---|---|---|
| `dataBoardLen` | `19` | `:16` | `9` | must equal `-pos-len` (`data_processing_pytorch.py:91`); left at 19 the engine writes 19×19-shaped rows for 9×9 games — ≈20× attention FLOPs (`(361/81)²`) |
| `numGameThreads` | `128` | `:84` | `18` | 24-CPU cap: 18 game + 1 nnServer + 1 dataWrite + 1 modelLoad + main = 22 (+2 transient during a net switch) |
| `bSizes` | `7,8,9` | `:95` | `9` | 9x9-only (assumption `a05_9x9_only`) |
| `bSizeRelProbs` | `1,1,8` | `:96` | `1` | arity must match `bSizes` |
| `allowRectangleProb` | `0.50` | `:97` | `0.0` | otherwise half the games are non-square |
| `handicapProb` | `0.10` | `:105` | `0.0` | already a no-op at 9x9 (`cpp/program/playutils.cpp:10-22`: `getDefaultMaxExtraBlack` = 0 for `sqrt(area) ≤ 10`); set explicitly so the cfg states it |

Deliberately **left at the preset value** (each was checked, not overlooked):
`maxVisits 600` `:115` · `cheapSearchProb/Visits/TargetWeight 0.75/100/0.0` `:60-62` ·
`numSearchThreads 1` `:116` · `nnMaxBatchSize 128` `:120` · `nnCacheSizePowerOfTwo 21` /
`nnMutexPoolSizePowerOfTwo 15` `:121-122` · `numNNServerThreadsPerModel 1` `:123` ·
`rootDesiredPerChildVisitsCoeff 2` `:148` · `chosenMoveSubtract 0` / `chosenMovePrune 1`
`:141-142` · `komiAuto True` / `komiStdev 1.0` / `komiBigStdevProb 0.06` / `komiBigStdev 12.0`
`:99-103` (σ is already rescaled by `sqrt(area)/19` at `cpp/program/playutils.cpp:42`) ·
`maxRowsPerTrainFile 10000` `:19` · `cudaDeviceToUse*` commented out `:127-131`.

**`chosenMoveTemperatureHalflife = 19` `:139` stays 19.** `cpp/search/searchhelpers.cpp:541-544`
computes `halflives = turn/halflife × 19/sqrt(area)`, so 19 already yields a 9-turn effective
halflife at 9x9; changing it to 9 would halve it. `[SOLID] halflife-resolved` (convention.md §10 corrected to keep 19 in commit 3549a8c) —
`decomposition/convention.md` §10 lists `9` as the mission value, which contradicts
`searchhelpers.cpp:541-544`. Closes when `convention.md` is amended via its ledger; this plan
follows the code.

### `codes/cfg/gatekeeper_9x9.cfg` ← `cpp/configs/training/gatekeeper1_maxsize9.cfg`

| key | preset value | preset line | mission value | reason |
|---|---|---|---|---|
| `numGameThreads` | `128` | `:18` | `20` | 24-CPU cap: 20 game + 2 nnServer (two models) + 1 main = 23 |
| `bSizes` | `7,8,9` | `:38` | `9` | 9x9-only |
| `bSizeRelProbs` | `1,1,8` | `:39` | `1` | arity |
| `allowRectangleProb` | `0.50` | `:40` | `0.0` | 9x9-only |

Left at the preset: `numGamesPerGating 200` `:20` · `maxVisits 150` `:49` ·
`numSearchThreads 1` `:50` · `nnMaxBatchSize 128` `:54` · `numNNServerThreadsPerModel 1` `:57` ·
`handicapProb 0.0` / `handicapCompensateKomiProb 1.0` `:44-45` · `komiAuto True` `:42` (no
`komiStdev` ⇒ 0, `cpp/program/play.cpp:195`) · `allowResignation true` / `resignThreshold -0.90`
/ `resignConsecTurns 5` `:22-24` · `chosenMoveTemperatureHalflife 19` `:73` · `dynamicScore
UtilityFactor 0.25` `:85-88`. `gatekeeper` needs no `dataBoardLen` (it writes no training rows).

| verification | value |
|---|---|
| command | `diff <(sed -n p cpp/configs/training/selfplay1_maxsize9.cfg) codes/cfg/selfplay_9x9.cfg` (and the gatekeeper pair) — the diff must contain exactly the rows above; then a parse-only run `katago benchmark -config codes/cfg/selfplay_9x9.cfg -model <smoke net> -boardsize 9 -v 1 -t 1` |
| metric + tolerance | diff line count matches the table exactly (6 keys selfplay, 4 keys gatekeeper); engine parses with no `warnUnusedKeys` complaint for a mission-added key; `ps -o nlwp` on the live process ≤24 |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/cfg_9x9_override/` |

---

## selfplay_stage

Predecessors: `synchronous_loop_smoke`, `selfplay_search_params`, `playout_cap_randomization`,
`root_explore_and_target_pruning`, `score_utility_search`.

| item | value |
|---|---|
| files to create | none (config only — `codes/cfg/selfplay_9x9.cfg`); invoked from `codes/loop/synchronous_loop_9x9.sh` |
| exact command | `katago selfplay -max-games-total $NUM_GAMES_PER_CYCLE -output-dir $BASEDIR/selfplay -models-dir $BASEDIR/models -config $DATED_ARCHIVE/selfplay.cfg` (`python/selfplay/synchronous_loop.sh:99`) |
| arg definitions | `-models-dir` `cpp/command/selfplay.cpp:51` (required) · `-output-dir` `:52` (required) · `-max-games-total` `:53`; config arg `:49`; `maxGamesTotal` is per-process `:45`,`:243`,`:292-293` |
| outputs | `selfplay/<model>/sgfs/<hex>.sgfs` and `.../tdata/<hex>.npz` (`selfplay.cpp:176-178,186-188,224`; `cpp/dataio/trainingwrite.cpp:1092`), flushed at 10000 rows with a short first file (`trainingwrite.cpp:1039`), written `.npz.tmp` → rename (`:1093-1096`) |
| bootstrap | empty `models/` ⇒ `findLatestModel` returns name `random`, file `/dev/null` (`cpp/dataio/loadmodel.cpp:77-80`) ⇒ `debugSkipNeuralNet` (`cpp/program/setup.cpp:126-130`) plays random games into `selfplay/random/` — accepted as the standard bootstrap (assumption `a10_random_bootstrap_ok`, obligation `o10_random_net_bootstrap`) |
| new-net pickup | polled every 20 s (`selfplay.cpp:350`, thread `:364`) |
| thread accounting | `numGameThreads` OS threads `selfplay.cpp:360-361`; search spawns `numThreads-1` (`cpp/search/searchmultithreadhelpers.cpp:40,50-52`, = 0 at `numSearchThreads 1`); `numNNServerThreadsPerModel` per model (`setup.cpp:194,203`); 1 dataWriteLoop per model (`cpp/program/selfplaymanager.cpp:156`); 1 modelLoadLoop (`selfplay.cpp:364`); main ⇒ 22 |
| verification command | `ps -o nlwp= -p $(pgrep -f 'katago selfplay')`; `grep -L 'SZ\[9\]' $BASEDIR/selfplay/*/sgfs/*.sgfs`; `python codes/eval/rows_per_game.py --basedir $BASEDIR` |
| metric + tolerance | thread count ≤24 (claim `c06_threads_le_24`); zero SGF files lacking `SZ[9]` (claim `c04_9x9_only_games`); games/hour and moves/game recorded (claim `c09_selfplay_rate`, no target value — it is the measurement) |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/selfplay_stage/` |

---

## gatekeeper_stage

Predecessors: `export_stage`, `gating_rule`.

| item | value |
|---|---|
| files to create | none (config only — `codes/cfg/gatekeeper_9x9.cfg`) |
| exact command | `katago gatekeeper -rejected-models-dir $BASEDIR/rejectedmodels -accepted-models-dir $BASEDIR/models/ -sgf-output-dir $BASEDIR/gatekeepersgf/ -test-models-dir $BASEDIR/modelstobetested/ -config $DATED_ARCHIVE/gatekeeper.cfg -quit-if-no-nets-to-test` (`python/selfplay/synchronous_loop.sh:96`) |
| arg definitions | `cpp/command/gatekeeper.cpp:266-273` (all four dirs required, `:296-301` non-empty check); `-required-candidate-win-prop` `:271` default **0.5**, *not passed* by the loop; `-quit-if-no-nets-to-test` `:273` |
| accept/reject flow | early accept `:184`, early reject `:188`, final `:580`; draws counted `:138`, no-result `:162`; rename into accepted/rejected `:591-598`, `:623-630`; `shouldStop` → return 0 `:524-525`, `:640-648` |
| cycle-1 behaviour | returns 0 immediately when `accepted-models-dir` is empty (`:399-402`), so the first cycle skips gating without failing the `-eu` loop |
| threads | `numGameThreads` at `gatekeeper.cpp:551-552`; 2 models ⇒ 2 nnServer threads ⇒ 20+2+1 = 23 |
| `USEGATING` | `1` for the smoke and first production run (obligation `o16_usegating_decision`); `USEGATING=0` would route exports straight to `models/` (`python/selfplay/export_model_for_selfplay.sh:115-120`) |
| verification command | `ls -d $BASEDIR/models/*/ \| wc -l`; `ls $BASEDIR/gatekeepersgf/`; `ps -o nlwp=` on the live process |
| metric + tolerance | ≥2 acceptances after the first exported net ⇒ ≥3 subdirs in `models/` (claim `c13_gatekeeper_accepts`); thread count ≤24; exit code 0 on every cycle including cycle 1 |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/gatekeeper_stage/` |

---

## eval_improvement (C++ half — the match run)

Predecessors: `gatekeeper_stage`. The analysis script is in the Python plan.

| item | value |
|---|---|
| file to create | `codes/cfg/match_9x9.cfg` ← `cpp/configs/match_example.cfg` |
| exact command | `katago match -config codes/cfg/match_9x9.cfg -sgf-output-dir $BASEDIR/eval/match_sgfs -log-file $BASEDIR/eval/match.log` |
| arg definitions | subcommand `cpp/main.cpp:103-104`; config arg `cpp/command/match.cpp:40`; `-log-file` `:42`; `-sgf-output-dir` `:43`; `-override-config` `:49` |

Keys of `codes/cfg/match_9x9.cfg` that differ from `cpp/configs/match_example.cfg`:

| key | example value | example line | mission value | reason |
|---|---|---|---|---|
| `numBots` | `1` | `:53` | `2` | candidate vs. baseline; read at `match.cpp:73`,`:126` |
| `botName` → `botName0` / `botName1` | `FOO` | `:54` | `latest_accepted` / `first_exported` | per-bot names required when `numBots > 1` (`match.cpp:132-137`) |
| `nnModelFile` → `nnModelFile0` / `nnModelFile1` | `PATH_TO_MODEL` | `:55` | abs paths to the two `model.bin.gz` | `match.cpp:141-144` |
| `numGameThreads` | `8` | `:70` | `20` | 24-CPU cap; read at `match.cpp:177`, threads spawned `:341-342` |
| `numGamesTotal` | `1000000` | `:72` | `400` | claim `c14_elo_vs_first_net`; read at `match.cpp:224` |
| `maxMovesPerGame` | `1200` | `:73` | `1600` | matches the training presets (`selfplay1_maxsize9.cfg:85`, `gatekeeper1_maxsize9.cfg:19`) |
| `bSizes` | `19,13,9` | `:88` | `9` | 9x9-only |
| `bSizeRelProbs` | `90,5,5` | `:89` | `1` | arity |
| `komiAuto` | `True` | `:96` | **removed** | `cpp/program/play.cpp:189-192` forbids both `komiAuto=True` and `komiMean`; exactly one must be set |
| `komiMean` | commented `7.5` | `:97` | `7` | fixed komi 7 per the design; parsed `play.cpp:194`, `komiStdev` defaults to 0 `:195` |
| `maxVisits` | `500` | `:107` | `150` | same visit budget as gating (`gatekeeper1_maxsize9.cfg:49`) |
| `nnMutexPoolSizePowerOfTwo` | `17` | `:117` | `15` | matches the training presets `:122`/`:56` |
| `nnMaxBatchSize` | `32` | `:115` | `128` | matches the training presets `:120`/`:54` |

Left at the example value: `numSearchThreads 1` `:111` · `nnCacheSizePowerOfTwo 21` `:116` ·
`numNNServerThreadsPerModel 1` `:126` · `handicapProb 0.0` / `handicapCompensateKomiProb 1.0`
`:101-102` · `logGamesEvery 50` `:46`.

Colour balance is automatic: `match.cpp:104-105` emplaces both `(i,j)` and `(j,i)` per round, so
each net plays black in half the games without an `extraPairs` entry.

| verification | value |
|---|---|
| command | the `katago match` line above, then `python codes/eval/match_winrate.py --sgf-dir $BASEDIR/eval/match_sgfs` |
| metric + tolerance | 400 games completed; candidate win rate ≥ 0.60 with a Wilson 95% lower bound > 0.5 (SE 0.025 at n=400) |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/eval_improvement/` |

`[OPEN] match-rules-randomization` — `match_example.cfg:82-86` randomizes
`koRules`/`scoringRules`/`taxRules`/`multiStoneSuicideLegals`/`hasButtons`; the mission has not
decided whether to fix them for a lower-variance A/B. Closes when the rule keys of
`match_9x9.cfg` are pinned (or the randomization is explicitly accepted) with the choice recorded.

`[OPEN] match-resignation-bias` — `match_example.cfg:75-77` sets `allowResignation true`,
`resignThreshold -0.95`, `resignConsecTurns 6`; the effect on a 9x9 win-rate estimate at komi 7
is not evaluated. Closes when the setting is fixed against a short pilot or disabled.

---

## Code-reading nodes — no code, verification only

No file under `codes/` and no engine patch. Each is confirmed by re-grepping the mirror and by
one runtime observation, then recorded.

| node | claim being verified | anchors | verification command | tolerance |
|---|---|---|---|---|
| `selfplay_search_params` | the 24-CPU thread arithmetic is real, not computed | `selfplay1_maxsize9.cfg:84,115-124`; `gatekeeper1_maxsize9.cfg:18,49-57`; `cpp/command/selfplay.cpp:360-364`; `cpp/search/searchmultithreadhelpers.cpp:40-52`; `cpp/program/setup.cpp:194,203`; `cpp/program/selfplaymanager.cpp:156` | `ps -o nlwp= -p <pid>` on a live selfplay and on a live gatekeeper | selfplay ≤24 (expect 22, +2 transient), gatekeeper ≤24 (expect 23) |
| `game_randomization_9x9` | the randomization actually applied at 9x9 matches the read | `selfplay1_maxsize9.cfg:26-33,55-58,64-68,95-108,138-142`; `cpp/program/playutils.cpp:10-22` (handicap 0 at ≤10), `:24-65` + `:42` (komi σ × `sqrt(area)/19`), `:234-268` (policy init); `cpp/program/play.cpp:189-204,974-982,1681-1693,2446`; `cpp/search/searchhelpers.cpp:541-544` (halflife rescale) | over one cycle's SGFs: every `SZ[9]`; komi histogram σ ≈ 0.474; zero handicap games (`AB[]` absent) | 100 % `SZ[9]`; measured komi σ within ±20 % of 0.474; 0 handicap games |
| `gating_rule` | gating is the 200-game / 0.5-win-prop rule with the CLI default in force | `cpp/command/gatekeeper.cpp:108,271,399-402,516-525,591-598,623-648`; `gatekeeper1_maxsize9.cfg:20-24,44-45,49` | `grep -c 'required-candidate-win-prop' codes/loop/synchronous_loop_9x9.sh` = 0 (default 0.5 is intended); gatekeeper log shows 200 games per candidate | grep = 0; per-candidate game count = 200 unless early-accepted/rejected (`:184`,`:188`) |
| `playout_cap_randomization` | p = 0.25 full search, (N,n) = (600,100), cheap turns write no rows | `cpp/program/play.cpp:1113,1127-1150` (`:1141-1142` visits, `:1143` target weight, `:1146-1149` noise); `cpp/program/playsettings.h:44-46`; `selfplay1_maxsize9.cfg:60-62,115` | measured rows/turn from `codes/eval/rows_per_game.py`, compared with `(1−0.75)+0.02` ≈ 0.27 | measured rows/turn ∈ [0.15, 0.44] (the [12,35] rows/game band of `c10` at ~80 turns) |
| `root_explore_and_target_pruning` | forced root exploration with k = 2 and target pruning are on, noise pruning is off | `cpp/search/searchexplorehelpers.cpp:153,166-169,229-263`; `cpp/search/searchresults.cpp:142-195,318-328`; `cpp/program/setup.cpp:578,645-647,671-676`; `selfplay1_maxsize9.cfg:141-142,148` | `grep -n 'rootDesiredPerChildVisitsCoeff\|chosenMovePrune\|chosenMoveSubtract' codes/cfg/selfplay_9x9.cfg` | values exactly `2`, `1`, `0`; `useNoisePruning` absent (false for `SETUP_FOR_OTHER`, `setup.cpp:578`) |
| `score_utility_search` | score utility uses the atan form with the 9x9 denominator 4.5 | `cpp/neuralnet/nninputs.cpp:40,56-69,100,113-190`; `cpp/search/search.cpp:1137-1166`; `cpp/search/searchhelpers.cpp:277-278`; `cpp/search/searchparams.h:14-17`; `selfplay1_maxsize9.cfg:157-163`; `gatekeeper1_maxsize9.cfg:85-88` | `grep -n 'staticScoreUtilityFactor\|dynamicScoreUtilityFactor\|dynamicScoreCenterZeroWeight\|dynamicScoreCenterScale' codes/cfg/*.cfg` | selfplay `0.00 / 0.40 / 0.25 / 0.50`; gatekeeper `dynamicScoreUtilityFactor 0.25`; denominator `0.50 × sqrt(81)` = 4.5 |

`[OPEN] rope-symmetry-cost` — `selfplay1_maxsize9.cfg:149` sets `rootNumSymmetriesToSample 4`,
but RoPE attention is not rotation-equivariant (carried from `audit_paper_code_map.md`). Closes
when the symmetry sampling is either measured to be harmless at 9x9 or set to 1 with the
decision recorded.

---
`POLICY_CHECK` = the value of `compute.policyCheck` in `mission.json` (the compute-budget skill check script), resolved relative to the `az` root.
