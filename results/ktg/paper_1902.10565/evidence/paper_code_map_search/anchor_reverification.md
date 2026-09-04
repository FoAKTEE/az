# Anchor re-verification transcript - `paper_code_map_search`

Mirror: `ref-code/lightvector-KataGo` @ `v1.18.2` = `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4` (verified with `git -C ref-code/lightvector-KataGo rev-parse HEAD` / `describe --tags`).
Host: `login03` (CPU only, no GPU job). Working directory: `/home/schmidt/ssci-haiyangw/az`.

Each block below is the knowledge-ledger row's own `verification.command`, executed VERBATIM,
followed by the same command with `grep -q` replaced by `grep -n` so the matched source lines are
visible. The `grep -n` form is a derived transcript for human reading; the admission evidence is the
verbatim run and its exit code.

Nodes covered: 6. All exited 0.

## `arxiv-1902.10565::playout_cap_randomization`

- ledger `task_id`: `paper_code_map`
- prior row hash: `306600d0f43691b3bbca4cb2bcb047d15a56be7298ea490e25f5964606b0cfbe` (status `preliminary`)
- `paper_anchor`: `cpp/program/play.cpp:1113,1127-1150; cpp/program/playsettings.h:44-46; cpp/configs/training/selfplay1_maxsize9.cfg:60-62,115`

Verbatim command:

```
sed -n 60,62p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -q 'cheapSearchProb = 0.75' && sed -n 1143p ref-code/lightvector-KataGo/cpp/program/play.cpp | grep -q 'cheapSearchTargetWeight' && sed -n 115p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -q 'maxVisits = 600'
```

Result: exit `0`, 0.094 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:21+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 60,62p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -n 'cheapSearchProb = 0.75' && sed -n 1143p ref-code/lightvector-KataGo/cpp/program/play.cpp | grep -n 'cheapSearchTargetWeight' && sed -n 115p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -n 'maxVisits = 600'
--- stdout ---
1:cheapSearchProb = 0.75  # Do cheap searches with this probaiblity
1:    targetWeight *= playSettings.cheapSearchTargetWeight;
1:maxVisits = 600
exit 0
```

## `arxiv-1902.10565::root_explore_and_target_pruning`

- ledger `task_id`: `paper_code_map`
- prior row hash: `490d504ecf05b74bb0b47952d89152424a5237fa358d801aff4b3c91c80a0859` (status `preliminary`)
- `paper_anchor`: `cpp/search/searchexplorehelpers.cpp:153-169,229-263; cpp/search/searchresults.cpp:142-195,318-328; cpp/program/setup.cpp:578,645-647,671-676; selfplay1_maxsize9.cfg:141-142,148`

Verbatim command:

```
sed -n 167p ref-code/lightvector-KataGo/cpp/search/searchexplorehelpers.cpp | grep -q rootDesiredPerChildVisitsCoeff && sed -n 578p ref-code/lightvector-KataGo/cpp/program/setup.cpp | grep -q SETUP_FOR_OTHER && sed -n 110p ref-code/lightvector-KataGo/cpp/command/selfplay.cpp | grep -q SETUP_FOR_OTHER && ! grep -q '^useNoisePruning' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg
```

Result: exit `0`, 0.129 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 167p ref-code/lightvector-KataGo/cpp/search/searchexplorehelpers.cpp | grep -n rootDesiredPerChildVisitsCoeff && sed -n 578p ref-code/lightvector-KataGo/cpp/program/setup.cpp | grep -n SETUP_FOR_OTHER && sed -n 110p ref-code/lightvector-KataGo/cpp/command/selfplay.cpp | grep -n SETUP_FOR_OTHER && ! grep -n '^useNoisePruning' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg
--- stdout ---
1:      if(nnPolicyProb > 0 && childWeight < sqrt(nnPolicyProb * totalChildWeight * searchParams.rootDesiredPerChildVisitsCoeff)) {
1:    else                                       params.useNoisePruning = (setupFor != SETUP_FOR_DISTRIBUTED && setupFor != SETUP_FOR_OTHER);
1:  const SearchParams baseParams = Setup::loadSingleParams(cfg,Setup::SETUP_FOR_OTHER);
exit 0
```

## `arxiv-1902.10565::score_utility_search`

- ledger `task_id`: `paper_code_map`
- prior row hash: `01e3842e5068cb1931d676b28ffe23f76dd1059f9323a1203a111f187bbc6b97` (status `preliminary`)
- `paper_anchor`: `cpp/neuralnet/nninputs.cpp:40,56-69,100,113-190; cpp/search/search.cpp:1137-1166; cpp/search/searchhelpers.cpp:277-278; cpp/search/searchparams.h:14-17; selfplay1_maxsize9.cfg:157-163; gatekeeper1_maxsize9.cfg:85-88`

Verbatim command:

```
sed -n 56p ref-code/lightvector-KataGo/cpp/neuralnet/nninputs.cpp | grep -q twoOverPi && sed -n 159p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -q 'dynamicScoreUtilityFactor = 0.40'
```

Result: exit `0`, 0.071 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 56p ref-code/lightvector-KataGo/cpp/neuralnet/nninputs.cpp | grep -n twoOverPi && sed -n 159p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -n 'dynamicScoreUtilityFactor = 0.40'
--- stdout ---
1:  return atan(adjustedScore / (scale * sqrtBoardArea)) * twoOverPi;
1:dynamicScoreUtilityFactor = 0.40
exit 0
```

## `arxiv-1902.10565::selfplay_search_params`

- ledger `task_id`: `paper_code_map`
- prior row hash: `161709c27363e5324ed36144c5a3d8993ee6fc5c93f911d2942d0480d019e770` (status `preliminary`)
- `paper_anchor`: `cpp/configs/training/selfplay1_maxsize9.cfg:84,115-124; gatekeeper1_maxsize9.cfg:18,49-57; cpp/command/selfplay.cpp:360-364; cpp/search/searchmultithreadhelpers.cpp:40-52; cpp/program/setup.cpp:194,203; cpp/program/selfplaymanager.cpp:156`

Verbatim command:

```
sed -n 548p ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp | grep -q 'std::thread newThread(dataWriteLoopProtected)' && sed -n 156p ref-code/lightvector-KataGo/cpp/program/selfplaymanager.cpp | grep -q 'std::thread newThread(dataWriteLoop' && sed -n 84p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -q 'numGameThreads = 128' && sed -n 364p ref-code/lightvector-KataGo/cpp/command/selfplay.cpp | grep -q modelLoadLoopThread
```

Result: exit `0`, 0.125 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 548p ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp | grep -n 'std::thread newThread(dataWriteLoopProtected)' && sed -n 156p ref-code/lightvector-KataGo/cpp/program/selfplaymanager.cpp | grep -n 'std::thread newThread(dataWriteLoop' && sed -n 84p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -n 'numGameThreads = 128' && sed -n 364p ref-code/lightvector-KataGo/cpp/command/selfplay.cpp | grep -n modelLoadLoopThread
--- stdout ---
1:    std::thread newThread(dataWriteLoopProtected);
1:  std::thread newThread(dataWriteLoop,this,newModel);
1:numGameThreads = 128
1:  std::thread modelLoadLoopThread(modelLoadLoopProtected);
exit 0
```

## `arxiv-1902.10565::game_randomization_9x9`

- ledger `task_id`: `paper_code_map`
- prior row hash: `7f58aa1a5e2e003597dbeff991627ce342eb9b3a38d87db2a9fcc79946d0a619` (status `preliminary`)
- `paper_anchor`: `cpp/configs/training/selfplay1_maxsize9.cfg:37,45,95-108,138-142; paper l.644-665 (background)`

Verbatim command:

```
sed -n 95,97p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -q 'bSizes = 7,8,9' && sed -n 97p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -q 'allowRectangleProb = 0.50' && sed -n 16p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -q 'dataBoardLen = 19'
```

Result: exit `0`, 0.092 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 95,97p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -n 'bSizes = 7,8,9' && sed -n 97p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -n 'allowRectangleProb = 0.50' && sed -n 16p ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg | grep -n 'dataBoardLen = 19'
--- stdout ---
1:bSizes = 7,8,9
1:allowRectangleProb = 0.50
1:dataBoardLen = 19
exit 0
```

## `arxiv-1902.10565::gating_rule`

- ledger `task_id`: `paper_code_map`
- prior row hash: `fb3e2a965f0d2b39190e2b3c333e538d34284e2ea394f505bd29dac0ced6b9f0` (status `preliminary`)
- `paper_anchor`: `cpp/command/gatekeeper.cpp:271,399-402,516-525,591-598,623-648; cpp/configs/training/gatekeeper1_maxsize9.cfg:18-24,44-45,49; paper l.667-681 (background: 100/200 rule)`

Verbatim command:

```
sed -n 93p ref-code/lightvector-KataGo/cpp/dataio/loadmodel.cpp | grep -q 'return true' && sed -n 77,78p ref-code/lightvector-KataGo/cpp/dataio/loadmodel.cpp | grep -q '/dev/null' && sed -n 126p ref-code/lightvector-KataGo/cpp/program/setup.cpp | grep -q '/dev/null' && sed -n 20p ref-code/lightvector-KataGo/cpp/configs/training/gatekeeper1_maxsize9.cfg | grep -q 'numGamesPerGating = 200' && sed -n 580p ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp | grep -q requiredCandidateWinProp
```

Result: exit `0`, 0.142 s, stdout+stderr empty (`sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), ran at `2026-09-04T03:40:22+00:00`.

Matched source lines (`grep -q` -> `grep -n`):

```
sed -n 93p ref-code/lightvector-KataGo/cpp/dataio/loadmodel.cpp | grep -n 'return true' && sed -n 77,78p ref-code/lightvector-KataGo/cpp/dataio/loadmodel.cpp | grep -n '/dev/null' && sed -n 126p ref-code/lightvector-KataGo/cpp/program/setup.cpp | grep -n '/dev/null' && sed -n 20p ref-code/lightvector-KataGo/cpp/configs/training/gatekeeper1_maxsize9.cfg | grep -n 'numGamesPerGating = 200' && sed -n 580p ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp | grep -n requiredCandidateWinProp
--- stdout ---
1:  return true;
2:  modelFile = "/dev/null";
1:    bool debugSkipNeuralNetDefault = (nnModelFile == "/dev/null");
1:numGamesPerGating = 200
1:    if(netAndStuff->numCandidateWinPoints + 1e-10 < requiredCandidateWinProp * netAndStuff->numGamesTallied) {
exit 0
```

