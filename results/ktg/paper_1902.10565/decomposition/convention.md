# Convention — mission `ktg-train` (code-first)

Stage 1-decompose artifact. Output contract: `pipelines/1-decompose/spec.md` § Output contract.
Markers per `_common/contracts/markers.md`.

**Source of truth = the code mirror** `ref-code/lightvector-KataGo` @ `v1.18.2` (`fd0723fd`).
arXiv:1902.10565 (2019/2020) is background: its symbols appear only where the current code
still has the idea; the paper column is blank (`—`) otherwise. `l.NNN` = line in
`ref-paper/arxiv-1902.10565/src/Accelerating_Self_Play_Learning_In_Go_2020.tex`.
Every code row was read directly from the mirror (read-only) at the cited `path:line`.
Config paths are relative to `ref-code/lightvector-KataGo/`; `sp9` =
`cpp/configs/training/selfplay1_maxsize9.cfg`, `gk9` =
`cpp/configs/training/gatekeeper1_maxsize9.cfg`.

## 1. Self-play engine — `sp9` (`katago selfplay`, `cpp/main.cpp:105`)

| code key (`path:line`) | meaning | maxsize9 value | paper symbol, l.NNN |
|---|---|---|---|
| `dataBoardLen` (`sp9:16`) | **edge length of every written training row**; read at `cpp/command/selfplay.cpp:97` (range 3..`Board::MAX_LEN`), passed as `dataXLen`/`dataYLen` to `TrainingDataWriter` (`:220`) | `19` | — (paper has no fixed row size) |
| `earlyForkGameProb` (`sp9:26`) | fork for opening variety | `0.04` | 5% branched games, l.655 |
| `earlyForkGameExpectedMoveProp` (`sp9:27`) | fork within `boardArea * this` moves | `0.025` | `Exp(mean 0.025 b^2)`, l.655 |
| `forkGameProb` (`sp9:28`) | mid-game fork to a crazy move | `0.01` | l.654 |
| `initGamesWithPolicy` (`sp9:55`) | play opening moves from raw policy | `true` | l.653 |
| `policyInitAreaProp` (`sp9:56`) | mean opening moves as a fraction of board area | `0.04` | `r ~ Exp(0.04 b^2)`, l.653 |
| `sidePositionProb` (`sp9:58`) | train on refuting alternative moves | `0.020` | 2.5% side positions, l.654 |
| `cheapSearchProb` (`sp9:60`) | **1 − p**: probability a turn gets the cheap search | `0.75` | `p = 0.25`, l.96 |
| `cheapSearchVisits` (`sp9:61`) | cheap visit cap | `100` | `n`, l.96 |
| `cheapSearchTargetWeight` (`sp9:62`) | training weight of cheap turns | `0.0` | "only full searches recorded", l.96 |
| `reduceVisits` / `reduceVisitsThreshold` / `reduceVisitsThresholdLookback` / `reducedVisitsMin` / `reducedVisitsWeight` (`sp9:64-68`) | taper visits + sample weight once one side is winning, instead of resigning | `true`, `0.9`, `3`, `100`, `0.1` | `lambda = p/0.05`, weight `0.1+0.9λ`, l.660 (paper: 5 turns at <5%) |
| `policySurpriseDataWeight` (`sp9:75`) | concentrate training weight on surprising moves | `0.5` | — |
| `valueSurpriseDataWeight` (`sp9:76`) | same for surprising results | `0.1` | — |
| `estimateLeadProb` (`sp9:78`) | spend extra visits to train a lead target | `0.05` | — |
| `numGameThreads` (`sp9:84`) | **concurrent self-play games (CPU/GPU load driver)** | `128` | — |
| `maxMovesPerGame` (`sp9:85`) | hard move cap | `1600` | — |
| `koRules` / `scoringRules` / `taxRules` / `multiStoneSuicideLegals` / `hasButtons` (`sp9:89-93`) | randomized rule axes | `SIMPLE,POSITIONAL,SITUATIONAL` / `AREA,TERRITORY` / `NONE,NONE,SEKI,SEKI,ALL` / `false,true` / `false,false,true` | ko + suicide randomization, l.649; Tromp-Taylor base, l.81 |
| `bSizes` (`sp9:95`) | board widths sampled | `7,8,9` | 9…19 mixture, l.650 |
| `bSizeRelProbs` (`sp9:96`) | relative weights for `bSizes` | `1,1,8` | 37.5→50% on 19×19, triangular rest, l.650 |
| `allowRectangleProb` (`sp9:97`) | probability of a non-square board | `0.50` | — (paper trains square boards only) |
| `komiAuto` (`sp9:99`) | set komi to the net's fair estimate on the empty board | `True` | mean-7 normal draw, l.651 |
| `komiStdev` (`sp9:101`) | komi jitter | `1.0` | sd 1, l.651 |
| `komiBigStdevProb` / `komiBigStdev` (`sp9:102-103`) | rare wide komi jitter | `0.06`, `12.0` | 5% at sd 10, l.651 |
| `handicapProb` (`sp9:105`) | handicap-game rate | `0.10` | 5%, l.652 |
| `handicapCompensateKomiProb` / `forkCompensateKomiProb` / `sgfCompensateKomiProb` (`sp9:106-108`) | komi fairness after handicap/fork/sgf start | `0.50`, `0.80`, `0.90` | 90% of handicap games, l.652 |
| `maxVisits` (`sp9:115`) | **full-search visit cap** | `600` | `N`, l.96 |
| `numSearchThreads` (`sp9:116`) | threads per game's search | `1` | — |
| `chosenMoveTemperatureEarly` / `chosenMoveTemperatureHalflife` / `chosenMoveTemperature` (`sp9:138-140`) | move-selection temperature schedule | `0.75`, `19`, `0.15` | `T` 0.8→0.2, halflife `b`, l.653 |
| `chosenMoveSubtract` / `chosenMovePrune` (`sp9:141-142`) | subtract/prune visits before move choice | `0`, `1` | "prune children reduced to one playout", l.108 |
| `rootNoiseEnabled` (`sp9:144`) | Dirichlet noise at the root | `true` | l.67 |
| `rootDirichletNoiseTotalConcentration` (`sp9:145`) | total Dirichlet concentration | `10.83` = `0.03*19^2` | `alpha = 0.03*19^2/N`, l.69 |
| `rootDirichletNoiseWeight` (`sp9:146`) | noise mixing weight | `0.25` | `0.75 P_raw + 0.25 eta`, l.68 |
| `rootDesiredPerChildVisitsCoeff` (`sp9:148`) | **forced playouts**: urgency → `1e20` while `childWeight < sqrt(policy * total * coeff)` (`cpp/search/searchexplorehelpers.cpp:166-169`) | `2` | `k = 2`, `n_forced = (k P sum N)^{1/2}`, l.105-106 |
| `useLcbForSelection` / `lcbStdevs` / `minVisitPropForLCB` (`sp9:151-153`) | lower-confidence-bound move choice | `true`, `5.0`, `0.15` | LCB used for *evaluation* only, l.240 |
| `winLossUtilityFactor` (`sp9:157`) | weight on `u_win` | `1.0` | `u_win = sign(x)`, l.687 |
| `staticScoreUtilityFactor` (`sp9:158`) | score utility centred at 0 | `0.00` | — |
| `dynamicScoreUtilityFactor` (`sp9:159`) | **`c_score`**: score utility centred on the net's own mean | `0.40` | `c_score` 0.5→0.4, l.690, l.705 |
| `dynamicScoreCenterZeroWeight` / `dynamicScoreCenterScale` (`sp9:160-161`) | how `x0` is re-centred each search | `0.25`, `0.50` | `x0 = mu_s_hat`, l.701 |
| `rootEndingBonusPoints` / `rootPruneUselessMoves` (`sp9:165-166`) | pass bias and dead-move pruning at the root | `0.5`, `true` | pass-favouring optimizations, l.218 |
| `rootPolicyTemperatureEarly` / `rootPolicyTemperature` (`sp9:168-169`) | softmax temperature on the root prior | `1.25`, `1.1` | 1.03, l.69 |
| `cpuctExploration` (`sp9:171`) | **`c_PUCT`** | `1.1` | `c_PUCT = 1.1`, l.59 |
| `fpuReductionMax` / `rootFpuReductionMax` (`sp9:173-174`) | **`c_FPU`** and its root override | `0.2`, `0.0` | `c_FPU = 0.2`, 0 at root, l.63-64 |
| `useNonBuggyLcb` / `useGraphSearch` (`sp9:182-183`) | LCB fix; DAG (transposition) search | `true`, `true` | — (paper's MCTS is a tree, l.57) |
| `fpuParentWeightByVisitedPolicy` / `...Pow` (`sp9:184-185`) | FPU blended by explored policy mass | `true`, `2.0` | `P_explored`, l.64 |

## 2. Gatekeeper — `gk9` (`katago gatekeeper`, `cpp/main.cpp:95`)

Keys shared with `sp9` are omitted; only gate-specific or differing ones are listed.

| code key (`path:line`) | meaning | maxsize9 value | paper symbol, l.NNN |
|---|---|---|---|
| `numGamesPerGating` (`gk9:20`) | games per gating match | `200` | 200 games, l.79, l.669 |
| `-required-candidate-win-prop` (`cpp/command/gatekeeper.cpp:271`) | CLI flag, default accept threshold | `0.5` → 100/200 | ≥100 of 200, l.669 |
| `allowResignation` / `resignThreshold` / `resignConsecTurns` (`gk9:22-24`) | resignation in gate games | `true`, `-0.90`, `5` | enabled, 5 turns <5%, l.678 |
| `bSizes` / `bSizeRelProbs` / `allowRectangleProb` (`gk9:38-40`) | gate board sizes | `7,8,9` / `1,1,8` / `0.50` | sizes still randomized, l.672 |
| `komiAuto` (`gk9:42`) | komi from the net's fair estimate | `True` | komi **fixed at 7.5**, l.672 — code differs |
| `handicapProb` / `handicapCompensateKomiProb` (`gk9:44-45`) | handicap in gate games | `0.0`, `1.0` | handicap disabled, l.673 |
| `maxVisits` (`gk9:49`) | gate visit cap | `150` | 300 → 400, l.669 |
| `chosenMoveTemperatureEarly` / `Halflife` / `chosenMoveTemperature` (`gk9:72-74`) | gate move temperature | `0.5`, `19`, `0.2` | starts at 0.5, l.675 |
| *(absent)* `rootNoiseEnabled`, `rootDesiredPerChildVisitsCoeff`, `cheapSearch*` | noise, forced playouts, visit-cap oscillation off in gating | not set | disabled, l.676 |
| `dynamicScoreUtilityFactor` (`gk9:86`) | score utility in gate games | `0.25` | — |
| `rootFpuReductionMax` (`gk9:98`) | root FPU equals tree FPU | `0.1` | root uses `c_FPU = 0.2`, l.677 |
| `useUncertainty` / `uncertaintyExponent` / `uncertaintyCoeff` (`gk9:108-110`) | uncertainty-weighted search | `true`, `1.0`, `0.25` | — (paper's `rv_hat_i` head had ~0 weight, l.593) |

## 3. Model config `b5c48h3tfr` — `python/katago/train/modelconfigs.py:986-1006`

> **Superseded for execution (2026-09-03).** `b5c48h3tfr` uses `ffng` (non-SwiGLU FFN) and every v1.18.2 C++ backend refuses it at NN-server construction — `cpp/neuralnet/cudaandrocmbackend.inc:3307-3308`, `eigenbackend.cpp:1634`, `openclbackend.cpp:2729` (job 297952 failed with exactly this message). The mission model is **`b7c96h3tfrs`** (`modelconfigs.py:1008-1029`, registered `:1887`): 7 × (`attnrope`, `ffnsg`), 96 trunk channels, 3 heads; env smoke PASS in job 298018. The rows below stay as the code-reading record of the `tf` family; all shape/pos_len facts apply to `b7c96h3tfrs` unchanged.

| field (`path:line`) | meaning | value | paper symbol, l.NNN |
|---|---|---|---|
| `version` (`:987`) | model format; 17 introduced transformers (`modelconfigs.py:43`) | `17` | — |
| `norm_kind` (`:988`) | normalization scheme | `"fixup"` | batch norm, l.421 |
| `initial_conv_1x1` (`:991`) | 1×1 instead of 5×5 stem | `False` | 5×5 stem conv, l.418 |
| `trunk_num_channels` (`:993`) | **`c`**: trunk width | `48` | `c` = 96…256, l.71, l.526 |
| `gpool_num_channels` (`:995`) | **`c_pool`**: channels pooled in the heads | `32` | `c_pool` = 32…64, l.434, l.527 |
| `transformer_ffn_channels` (`:996`) | FFN hidden width | `128` | — |
| `transformer_heads` / `transformer_kv_heads` (`:997-998`) | attention heads / KV heads | `3`, `3` | — |
| `block_kind` (`:999`) | **trunk**: 5 × (`attnrope`, `ffng`); no gpool block, no residual conv block | 10 blocks | `n` = 6…20 residual blocks, l.419, l.525 |
| `p1_num_channels` / `g1_num_channels` (`:1000-1001`) | policy-head `P` / `G` widths | `16`, `16` | `c_head`, l.447 |
| `v1_num_channels` (`:1002`) | value-head conv width | `16` | `c_head`, l.459 |
| `sbv2_num_channels` (`:1003`) | score-belief hidden width | `32` | `c_val`, l.502 |
| `num_scorebeliefs` (`:1004`) | mixture components in the score head | `4` | single distribution, l.506 |
| `v2_size` (`:1005`) | **`c_val`**: value-head hidden width | `48` | `c_val` = 48…96, l.464, l.529 |
| registration (`:1886`) | `"b5c48h3tfr": b5c48h3tfr,  # no swiglu` | uses `ffng`, **not** `ffnsg` | — |

## 4. Trainer — `python/train.py` (driver `python/selfplay/train.sh`)

| flag (`path:line`) | meaning | value / default | paper symbol, l.NNN |
|---|---|---|---|
| `-pos-len` (`train.py:79`, required) | **spatial edge length of expected training data** | `train.sh:88` hard-codes `19` | board width `b`, l.360 |
| `-batch-size` (`train.py:80`, required) | per-GPU batch | `$BATCHSIZE` (`train.sh:89`) | 256, l.77, l.635 |
| `-model-kind` (`train.py:82`) | model config name | `$MODELKIND` (`train.sh:90`) | `(b,c)` sizes, l.71 |
| `-samples-per-epoch` (`train.py:81`) | samples per epoch | set by `synchronous_loop.sh:109` | — |
| `-lr-scale` / `-lr-scale-auto` / `-lr-scale-auto2` / `-lr-schedule` (`train.py:83-86`) | LR multiplier on the built-in schedule | none set by default | 6e-5/sample, 2e-5 warmup, 6e-6 late, l.77, l.635 |
| `-input-wd-factor` / `-normal-wd-factor` / `-normal-attn-wd-factor` (`train.py:90-92`) | weight-decay **scaling** on a decoupled optimizer-side base of `0.00125 * wd_scaling * (lr_scale*warmup)^0.75 * group_factor` (`train.py:733`, `:698-700`; groups normal 1.0, normal_attn 0.5 `:711-712`, normal_gamma 0.125 `:724`, heads/noreg 1e-6 `:741,743`) | `1.0` each | `c_L2 = 3e-5`, l.589 |
| `-swa-period-samples` / `-swa-scale` (`train.py:95-96`) | SWA snapshot period / averaging span | `samples_per_epoch//2`, `8` (`:440-443`) | every 250k, EMA decay 0.75 over 4, l.79 |
| `-use-adamw` / `-use-muon` / `-use-normuon` / `-use-aurora` (`train.py:101-104`) | optimizer choice; default with all off is `torch.optim.SGD(lr=1.0, momentum=0.9)` (`train.py:844,942`; name resolution `:374`) wrapped in Lookahead k=6 / alpha=0.5 (`:97-98`) | all off | SGD, momentum 0.9, l.77 |
| `-max-train-bucket-size` / `-stop-when-train-bucket-limited` (`train.py:122,124`) | cap training against data supply | set by `synchronous_loop.sh:109` | — |
| `-attn-logit-penalty-cap` / `-coeff` / `-batch-frac` (`train.py:140-142`) | **transformer-only**: penalize large attention logits | `None` (off), `1e-3`, `1.0` | — |
| `-value-loss-scale` (`train.py:146`) | extra multiplier on the value loss | `0.6` | `c_value = 1.5`, l.547 |

## 5. Shuffler — `python/shuffle.py` (driver `python/selfplay/shuffle.sh`)

| flag (`path:line`) | meaning | default | paper symbol, l.NNN |
|---|---|---|---|
| `-min-rows` (`shuffle.py:777`) | window floor | `250k` | `c = 250,000`, l.639 |
| `-max-rows` (`shuffle.py:778`) | window ceiling | unbounded | ~22M by run end, l.77 |
| `-keep-target-rows` (`shuffle.py:779`, required) | rows actually written per shuffle | — | — |
| `-expand-window-per-row` (`shuffle.py:780`) | **`beta`** | `1.0` (upstream advice `0.4`, `:734`) | `beta = 0.4`, l.639 |
| `-taper-window-exponent` (`shuffle.py:781`) | **`alpha`** | `1.0` (upstream advice `0.65-0.675`, `:733`) | `alpha = 0.75`, l.639 |
| `-taper-window-scale` (`shuffle.py:782`) | power-law anchor | `-min-rows` | `c`, l.639 |
| `-num-processes` (`shuffle.py:791`, required) | shuffling parallelism (**CPU budget**) | — | — |
| window formula `compute_desired_num_rows` (`shuffle.py:414-430`) | `N_window` | — | `N_window`, l.638 |

## 6. Exporter — `python/export_model_pytorch.py` (driver `export_model_for_selfplay.sh:77`)

| flag (`path:line`) | meaning | default | paper symbol, l.NNN |
|---|---|---|---|
| `-checkpoint` / `-export-dir` / `-model-name` / `-filename-prefix` (`:34,36,37,38`) | source ckpt and destination | required (set at `export_model_for_selfplay.sh:77-83`) | — |
| `-use-swa` (`:39`) | export the SWA-averaged weights | passed by the driver | SWA candidate nets, l.79 |
| `-attn-logit-bound-limit` (`:42`) | **refuses to export** if any attention layer's data-free logit bound exceeds this | `2.5e4` | — |
| `-ignore-attn-logit-bound` (`:43`) | export anyway | off | — |

## 7. Loss coefficients — `python/katago/train/metrics_pytorch.py` (not config-settable)

| identifier (`path:line`) | meaning | value | paper symbol, l.NNN |
|---|---|---|---|
| `loss_policy_player_samplewise` (`:78-82`) | main policy cross-entropy | `1.0` | policy loss, l.550 |
| `loss_policy_opponent_samplewise` (`:84-88`) | opponent-reply policy | `0.15` | `w_opp = 0.15`, l.555 |
| `loss_value_samplewise` (`:121-127`) | game-outcome value | `1.20` (× `-value-loss-scale` `0.6`) | `c_value = 1.5`, l.547 |
| `loss_ownership_samplewise` (`:146-161`) | per-point ownership, mean over on-board points | `1.5` | `w_o = 1.5/b^2`, l.559 |
| `loss_scoremean_samplewise` (`:250-253`) | score-mean self-prediction, Huber `delta = 12.0` | `0.0015` | `w_sbreg = 0.004`, `delta = 10.0`, l.570-571 |
| `loss_scorebelief_cdf_samplewise` (`:260-267`) | squared-CDF score belief | `0.020` | `w_scdf = 0.02`, l.567 |
| `loss_scorebelief_pdf_samplewise` (`:269-273`) | cross-entropy score belief | `0.020` | `w_spdf = 0.02`, l.563 |
| `loss_qvalues_samplewise` (`:90-118`) | per-move Q-value targets (win/loss, score) | `1.5`, `0.0008` | — |
| `loss_shortterm_value_error_samplewise` / `..._score_..._` (`:308,317`) | short-term error self-prediction | — | `rv_hat_i`, ~0 weight, l.471, l.593 |
| `scorebelief_len` (`:35`) | `2 * (pos_len^2 + 60)` | `842` at `pos_len=19` | `2S`, `S = 19*19+60`, l.497, l.512 |

## 8. Hard-coded architecture constants — `python/katago/train/model_pytorch.py`

| identifier (`path:line`) | meaning | value | paper symbol, l.NNN |
|---|---|---|---|
| `EXTRA_SCORE_DISTR_RADIUS` (`:26`; C++ `cpp/neuralnet/nninputs.h:19`) | score-head margin beyond board area | `60` | the "+60" in `S`, l.512 |
| `scorebelief_mid` (`:2759`) | `pos_len*pos_len + EXTRA_SCORE_DISTR_RADIUS` | `421` at `pos_len=19` | `S`, l.497 |
| `mask_sum_hw_sqrt_offset` (`:505`, `:534`) | `sqrt(on-board points) − 14.0` | **`14.0` hard-coded** | `b_avg = 0.5(9+19) = 14`, l.404 |
| `KataGPool.forward` (`:512-517`) | mean, `mean*(offset/10)`, max → `3c` | — | global pooling layer, l.398-402 |
| `KataValueHeadGPool.forward` (`:539-540`) | third channel `mean*((offset^2)/100 − 0.1)` | **`0.1` = `sigma^2/100`** | `sigma^2 = 10`, l.404 |
| `PolicyHead.gpool` (`:2647`) / `ValueHead.gpool` (`:2745`) | global pooling in the heads, **unconditional** | always on | policy/value head gpool, l.448, l.460 |
| `score_belief_offset_vector` / `..._bias_` / `..._parity_` (`:2771,2776,2781`) | score axis, `0.05*s`, parity feature | — | `s`, `0.05*s`, `Parity(s)`, l.496-501 |
| `conv_ownership` (`:2803`) | ownership head, tanh output | — | `o_hat`, l.484 |

## 9. Paper symbol collisions (relevant only when reading the tex)

- `b` = residual-block count at l.71 but **board width** at l.185, l.360, l.404, l.690;
  Appendix A renames the block count `n` (l.419, l.525). Code has no such collision:
  width is `pos_len`/`dataBoardLen`, depth is `len(block_kind)`.
- `n` = cheap visit cap (l.96) vs block count (l.419) → code: `cheapSearchVisits` vs `block_kind`.
- `N` = child playouts (l.59), full visit cap (l.96), legal-move count (l.69), `N_window`/`N_total` (l.638).
- `c` = trunk channels (l.71), L2 coefficient (l.588), window anchor 250,000 (l.639), a search child (l.58).
- `sigma^2` = board-width variance 10 (l.404) vs score-belief stdev `sigma_s` (l.470).

## 10. 9×9-only substitutions — what the mission must set

Each row: code key/flag → the value a strict 9×9 run requires. Every flag below was confirmed
present by `grep` at the cited `path:line`. Mission-chosen values are `[ASSUMPTION]`.

| code key / flag | preset value | mission value | note |
|---|---|---|---|
| `bSizes` (`sp9:95`, `gk9:38`) | `7,8,9` | `9` | `[ASSUMPTION] mission-9only` — no 9-only preset exists upstream; requires a mission-owned copy (mirror is read-only, kernel §4) |
| `bSizeRelProbs` (`sp9:96`, `gk9:39`) | `1,1,8` | `1` | must have the same arity as `bSizes` |
| `allowRectangleProb` (`sp9:97`, `gk9:40`) | `0.50` | `0.0` | otherwise half of all games are non-square, not 9×9 |
| `dataBoardLen` (`sp9:16`) | **`19`** | `9` | **confirmed**: read at `cpp/command/selfplay.cpp:97`, becomes `dataXLen`/`dataYLen` (`:220`). Left at 19 the selfplay engine writes 19×19-shaped rows for 9×9 games |
| `-pos-len` (`train.py:79`; `train.sh:88`) | **`19` hard-coded** | `9` | **confirmed present**. Must equal `dataBoardLen` or the trainer's expected row shape mismatches the data. Sets `scorebelief_len = 2*(81+60) = 282` (`metrics_pytorch.py:35`) |
| `handicapProb` (`sp9:105`) | `0.10` | `0.10` (unchanged, no-op) | `getDefaultMaxExtraBlack` returns 0 for sqrt(area) <= 10 (`cpp/program/playutils.cpp:10-22`, gate `:46`), so handicap games never occur at 9×9 whatever the key says; setting 0.0 is equivalent |
| `chosenMoveTemperatureHalflife` (`sp9:139`, `gk9:73`) | `19` | `19` (**must stay 19**) | `cpp/search/searchhelpers.cpp:541-545` multiplies `turn/halflife` by `19.0/sqrt(area)`, so the effective halflife is already `19*9/19 = 9` turns at 9×9 — exactly the paper's board-width rule (l.653). Setting 9 would give 4.3 turns |
| `policyInitAreaProp` (`sp9:56`) | `0.04` | `0.04` (unchanged) | scales with board area automatically → mean 3.24 opening moves at 9×9 |
| `maxVisits` (`sp9:115`) / `cheapSearchVisits` (`sp9:61`) / `cheapSearchProb` (`sp9:60`) | `600` / `100` / `0.75` | unchanged for S2/P1 | `[ASSUMPTION]` keep upstream caps (they equal the paper's initial p=0.25, (600,100), l.97); revisit after `c09` measures games/h (DESIGN.md §2) |
| `numGameThreads` (`sp9:84`, `gk9:18`) | `128` | `18` selfplay / `18` gatekeeper | with `numSearchThreads=1`, `numNNServerThreadsPerModel=1`: selfplay 18 game + 1 nnServer + 1 dataWrite + 1 modelLoad + main = 22 (+2 transient at net switch); gatekeeper 18 game + 2 nnServer + 1 dataWrite (`gatekeeper.cpp:548`, uncounted by the pass-1 value 20, which gave 24 with no margin) + main = 22 (`cpp/command/selfplay.cpp:359-364`, `gatekeeper.cpp:548-553`, `setup.cpp:194,203`, `selfplaymanager.cpp:156`); reconciled 2026-09-04 (`dag_reconciliation.md` §0); obligation `o03`, claim `c06`. verify: `sed -n 548p ref-code/lightvector-KataGo/cpp/command/gatekeeper.cpp \| grep -c dataWriteLoopProtected` = 1; `grep -c '^numGameThreads = 18' results/ktg/paper_1902.10565/codes/cfg/gatekeeper_9x9.cfg` = 1; selfplay measured `NLWP_MAX = 22` in `evidence/cfg_9x9/check_cfg_9x9-298359.txt` |
| `maxVisits` (`gk9:49`) | `150` | `150` (unchanged) | `[ASSUMPTION]` upstream gating cap kept; the paper's 300→400 (l.669) is not a target (code-first); obligation `o16` records the USEGATING decision |
| `rootDirichletNoiseTotalConcentration` (`sp9:145`) | `10.83` | `10.83` (unchanged) | `[HYPOTHESIS] noise-9x9` — spread over ≤82 moves instead of ≤362, per-move concentration rises ~4.4× |
| `mask_sum_hw_sqrt_offset` = `14.0` (`model_pytorch.py:505,534`) | `14.0` | unchanged | `[ASSUMPTION] bavg-keep` — at `b=9` the offset is `-5`, so the scaled-mean pool channel is `-0.5 x mean` (`:514,:539`) and the value-head third channel is `(25/100 - 0.1) = 0.15 x mean` (`:540`): collinear with the mean, i.e. redundant columns, not constants. Changing the constants would break C++ backend compatibility (obligation `o14`, discharged) |
| `-attn-logit-penalty-cap` (`train.py:140`) | `None` | `[OPEN] attn-logit` | the exporter refuses models whose attention logit bound exceeds `2.5e4` (`export_model_pytorch.py:42`). `b5c48h3tfr` is superseded for execution (§3 above; `ffng` unservable). A random-init `b7c96h3tfrs` export already succeeds without the flag (`r_tiny_model_export_smoke_b7c96h3tfrs`, empirical, `evidence/tiny_smoke/verification.txt`); that export carries no trained attention weights, so it does not exercise the `2.5e4` bound. **Closes when** a *trained* `b7c96h3tfrs` export passes the bound, or the penalty is enabled to keep it down — tracked at `export_stage` (cfg-9x9-override result row, obligation thread) |
| all paper Elo figures (l.240, l.293, Table l.332-338) | 19×19 | not applicable | replaced by claims `c13` (>= 2 gatekeeper acceptances) and `c14` (latest vs first net >= 60 % over 400 games at 150 visits, 9×9, komi 7) — `claims.md`, `DESIGN.md` §7 |
