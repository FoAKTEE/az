# Evidence — paper ideas vs. v1.18.2 code, for the 9x9 transformer `b5c48h3tfr` (read-only audit)

Paper `ref-paper/arxiv-1902.10565/src/Accelerating_Self_Play_Learning_In_Go_2020.tex` (`l.NNN`); code mirror
`ref-code/lightvector-KataGo/` @ v1.18.2 (paths relative). Evidence type: literature grounding (code reading).
Produced by the decompose-stage worker audit, 2026-09-03; consumed by knowledge nodes
`playout_cap_randomization`, `root_explore_and_target_pruning`, `loss_targets_metrics`, `score_utility_search`,
`transformer_trunk_b5c48h3tfr`, `head_gpool_degeneracy_9x9`, `train_optimizer_schedule`.

Config anchor: `python/katago/train/modelconfigs.py:986-1006` — `b5c48h3tfr`: version 17, norm_kind fixup, trunk_num_channels 48,
transformer_heads 3, transformer_kv_heads 3, transformer_ffn_channels 128, gpool_num_channels 32, block_kind = 5 x [attn attnrope, ffn ffng],
p1/g1/v1_num_channels 16, sbv2 32, num_scorebeliefs 4, v2_size 48; no `predict_q_values` => 6 policy outputs (`model_pytorch.py:2622-2626`), q losses zeroed (`metrics_pytorch.py:838-841`).

## 1. Playout cap randomization (paper l.96-97: p=0.25, (N,n)=(600,100)->(1000,200))
Code: `cpp/program/play.cpp:1132-1150`; visits `min(maxVisits, cheapSearchVisits)` :1141-1142; `targetWeight *= cheapSearchTargetWeight` :1143; root noise removed only if weight <= 0 :1146-1149; params `cpp/program/playsettings.h:44-46`, `playsettings.cpp:98-100` (defaults 0 :11). Cfg `selfplay1_maxsize9.cfg:60-62` cheapSearchProb 0.75 / cheapSearchVisits 100 / cheapSearchTargetWeight 0.0, maxVisits 600 (:115) => p=0.25, (600,100) = paper initial. Extras: halved cheapSearchProb for 6 turns after hint/fork (:1127-1129); `forceFullSearch` (:1113). Board/arch independent.

## 2. Forced root exploration + policy target pruning (paper l.105-109, k=2)
`cpp/search/searchexplorehelpers.cpp:166-169`: `childWeight < sqrt(nnPolicyProb * totalChildWeight * rootDesiredPerChildVisitsCoeff)` => return 1e20 (root only, :153). Param `searchparams.h:69`, default 0.0 (`searchparams.cpp:54`); cfg `rootDesiredPerChildVisitsCoeff = 2` (:148) = paper k. Pruning: `Search::getReducedPlaySelectionWeight` `searchexplorehelpers.cpp:229-263` (inverse PUCT at the best child's explore value, :257-262), applied at the root in `cpp/search/searchresults.cpp:142-195`; single-playout prune via `chosenMovePrune=1` (cfg :142; `searchresults.cpp:318-328`), `chosenMoveSubtract=0` (:141). Target write: `cpp/program/play.cpp:810-845` -> `trainingwrite.cpp:552-553`. A second pruner `pruneNoiseWeight` (`searchupdatehelpers.cpp:495-539`) is gated by `useNoisePruning`, false for SETUP_FOR_OTHER (`setup.cpp:578`; `selfplay.cpp:110,172`). At 9x9/600 visits the prune floor is min(1, maxValue/64) = 1.

## 3. Global pooling (paper l.129, l.398-404: mean, mean*(b-14)/10, max; value head mean*((b-14)^2-10)/100)
Code `python/katago/train/model_pytorch.py`: `mask_sum_hw_sqrt_offset = sqrt(mask_sum_hw) - 14.0` :505/:534; pool2 = mean*offset/10 :514/:539; pool3 = max :515 (trunk/policy) or mean*(off^2/100 - 0.1) :540 (value; 0.1 = sigma^2/100, sigma^2 = 10 exact). Classes `KataGPool` :492-518, `KataValueHeadGPool` :521-543, `KataConvAndGPool` :545-609.
**b5c48h3tfr trunk has no gpool**: trunk gpool only for block kinds ending in "gpool" (:3157-3160); `attnrope` (:3231-3239) and `ffng` (:3278-3285) take no `c_gpool`; `gpool_num_channels` is dead config. Policy head gpool unconditional (:2647, :2711, :2649-2655); value head gpool unconditional (:2745, :2855).
At strictly 9x9 (mask_sum_hw = 81, off = -5): policy pool2 = -0.5*pool1 (pool3 = max independent); value head pool2 = -0.5*pool1, pool3 = +0.15*pool1 => value-head pooled vector collinear (48 columns carry 16 dof). Masked today only by `bSizes 7,8,9` + `allowRectangleProb 0.50`. No literal 19 in the pooling path; constants are the paper's [9,19] calibration, mirrored by the C++ backends (re-centering not evaluated).

## 4. Auxiliary opponent-policy target (paper l.159-160, w_opp 0.15)
`metrics_pytorch.py:84-88` `0.15 * global_weight * weight * loss` (exact); head channel `model_pytorch.py:2630`, consumed `metrics_pytorch.py:618-623`; target from next turn `trainingwrite.cpp:1174`, written :562; row weight `target_global_nc[:,28]` (:559); summed at :858. Not in paper: soft policy x2 with `-soft-policy-weight-scale` 8.0 (`train.py:143`, :859-860); long/short optimistic policy 0.100/0.200 and main policy scale 0.930 for version 17 (:603-607, :857,861-862).

## 5. Loss function — paper vs. `metrics_pytorch.py` (assembly :856-882)
| term | paper | code constant | flag multiplier (train.py) | effective |
|---|---|---|---|---|
| policy | 1.0 (l.550) | - | policy_opt_loss_scale 0.930 (:605) | 0.930 |
| opponent policy | 0.15 | 0.15 (:88) | 1 | 0.15 |
| soft policy x2 | - | - | -soft-policy-weight-scale 8.0 (train.py:143) | 8.0 each |
| long/short opt policy | - | - | 0.100 / 0.200 (:600-601) | |
| game outcome value | 1.5 (l.547) | 1.20 (:127) | -value-loss-scale 0.6 (train.py:146) | 0.72 |
| TD value x3 | - | 1.20 (:136) | -td-value-loss-scales 0.6,0.6,0.6 (train.py:147) | 0.72 each |
| TD score | - | 0.0004 (:143) | 1 | 0.0004 |
| ownership | 1.5/b^2 (l.559) | 1.5 * sum(BCE*mask)/mask_sum_hw (:157-161) | 1 | 1.5/b^2 exact |
| scoring (area) | - | 0.25 (:869), /mask_sum_hw, 4(sqrt(l/2+1)-1) (:171-173) | 1 | 0.25 |
| futurepos | - | 0.25 (:194), steps [1.0,0.25] (:192), /sqrt(mask_sum_hw) (:193) | 1 | 0.25 |
| seki | - | sign + 0.5 neutral, /mask_sum_hw (:245-246); adaptive scale (:222,224) | -seki-loss-scale 1.0 (train.py:148) | adaptive |
| score belief pdf / cdf | 0.02 / 0.02 (l.563,567) | 0.020 (:273) / 0.020 (:267) | 1 | 0.02 / 0.02 |
| score mean self-pred | 0.004, Huber d=10 (l.570) | 0.0015, Huber d=12, target = data scoremean (:257-258) | 1 | 0.0015 |
| score stdev self-pred | 0.004, d=10 (l.578) | 0.001, d=10, self-belief target (:281-288) | 1 | 0.001 |
| score-belief scaling penalty | 0.0005 gamma^2 (l.584) | absent | | 0 |
| lead | - | 0.0060, d=8 (:297-298) | 1 | 0.006 |
| variance-time | ~0 (l.593) | 0.0003, d=50 (:304-305) | -variance-time-loss-scale 1.0 (train.py:149) | 0.0003 |
| shortterm value / score error | - | 2.0, d=0.4 (:314-315) / 0.00002, d=100 (:322-323) | 1 | |
| q-value winloss / score | - | 1.5 / 0.0008 (:118) | | 0 for b5c48h3tfr |
| L2 | 3e-5 ||theta||^2 (l.589) | decoupled weight decay in optimizer `train.py:632-750`: SGD 0.00125 * wd_scaling * (lr_scale*warmup)^0.75 * group factor (:733, :698-700); groups normal 1.0, normal_attn 0.5 (:711-712), normal_gamma 0.125 (:724), heads/noreg 1e-6 (:741,:743) | | structural |
`scorebelief_len = 2*(pos_len^2 + EXTRA_SCORE_DISTR_RADIUS)` (`metrics_pytorch.py:35`; `model_pytorch.py:2759-2760`): 842 at 19, 282 at 9. All terms parametric in pos_len / mask_sum_hw (asserts :151-153,166-168,187-189,200-203).

## 6. Score utility (paper l.689-691, l.701-703)
`cpp/neuralnet/nninputs.cpp:56` `atan(adjustedScore / (scale * sqrtBoardArea)) * twoOverPi` (:40); tables :113-159, lookup :161-190 (built at MAX_BOARD_LEN :100, rescaled :164). c_score = static + dynamic (`searchhelpers.cpp:277-278`). Center: `search.cpp:1137-1166`, `recentScoreCenter = expectedScore*(1-dynamicScoreCenterZeroWeight)` :1160, clamp +-sqrt(area)*dynamicScoreCenterScale :1161-1165. Params `searchparams.h:14-17`. Cfg `selfplay1_maxsize9.cfg:157-163`: winLossUtilityFactor 1.0, staticScoreUtilityFactor 0.00, dynamicScoreUtilityFactor 0.40, dynamicScoreCenterZeroWeight 0.25, dynamicScoreCenterScale 0.50; gatekeeper :85-88 dynamicScoreUtilityFactor 0.25. Deviations: denominator 0.5*sqrt(area) = 4.5 at 9x9 (paper: b); x0 pulled 25 % toward 0.

## 7. Game randomization (paper l.644-666) — cfg `selfplay1_maxsize9.cfg`
Rules keys :89-93. Board: bSizes 7,8,9 / bSizeRelProbs 1,1,8 / allowRectangleProb 0.50 (:95-97) — the only diff vs selfplay1.cfg. Komi: komiAuto True :99, komiStdev 1.0 :101, komiBigStdevProb 0.06 :102, komiBigStdev 12.0 :103; parse `play.cpp:189-204`; draw `playutils.cpp:24-65`, truncation 3 sigma :97; **`stdevToUse *= sqrtBoardArea/19.0` (:42)** => 0.474 / 5.68 at 9x9. Handicap: handicapProb 0.10 :105, handicapCompensateKomiProb 0.50 :106; `getDefaultMaxExtraBlack` (`playutils.cpp:10-22`) = 0 for sqrt(area) <= 10 => **handicap off at 9x9**. Opening: initGamesWithPolicy true :55, policyInitAreaProp 0.04 :56 (`play.cpp:1681-1693`, `playutils.cpp:234-268`, mean 3.24 at 9x9). Temperature: chosenMoveTemperatureEarly 0.75 :138, chosenMoveTemperature 0.15 :140, **chosenMoveTemperatureHalflife 19 :139 — correct, `searchhelpers.cpp:541-545` multiplies by 19/sqrt(area) => 9-turn effective halflife at 9x9; do not change**. Side positions sidePositionProb 0.020 :58 (`play.cpp:974-982`). Forks: earlyForkGameProb 0.04 :26, earlyForkGameExpectedMoveProp 0.025 :27, forkGameProb 0.01 :28, forkGameMinChoices 3 :29, earlyForkGameMaxChoices 12 :30, forkGameMaxChoices 36 :31, sekiForkHackProb 0.02 :33 (`play.cpp:2446`). Reduce visits: reduceVisits true :64, reduceVisitsThreshold 0.9 :65, lookback 3 :66, reducedVisitsMin 100 :67, reducedVisitsWeight 0.1 :68 (`play.cpp:1151-1187`, quadratic :1178). Extras not in paper: policySurpriseDataWeight 0.5 / valueSurpriseDataWeight 0.1 (:75-76), asymmetric playouts (:70-73), estimateLeadProb 0.05 (:78), switchNetsMidGame (:79), fancyKomiVarying (:80), drawRandRadius 0.5 (:110), rootNumSymmetriesToSample 4 (:149), subtreeValueBiasFactor 0.30 (:180), useGraphSearch true (:183).

## 8. Gating (paper l.669-678)
`numGamesPerGating` read `cpp/command/gatekeeper.cpp:108`; cfg `gatekeeper1_maxsize9.cfg:20` = 200. `requiredCandidateWinProp` member :64, CLI default 0.5 (:271, :290, :326, :378, :451); early accept :184, early reject :188, final :580; draws :138, no-result :162. maxVisits 150 (:49). Board keys :38-40 as selfplay; komiAuto True :42, no komiStdev => 0 (`play.cpp:195`); handicapProb 0.0 :44; no fork/side keys; no initGamesWithPolicy; chosenMoveTemperatureEarly 0.5 :72, Temperature 0.2 :74, Halflife 19 :73; no rootNoise / rootDesiredPerChildVisitsCoeff / cheapSearch; fpuReductionMax 0.2 :97, rootFpuReductionMax 0.1 :98; allowResignation true :22, resignThreshold -0.90 :23, resignConsecTurns 5 :24.
`USEGATING=0` (`export_model_for_selfplay.sh:115-120`) exports straight into `models/`, bypassing `modelstobetested/`; also pre-creates `selfplay/$NAME/{sgfs,tdata}` (:96-103).

## 9. Training details (paper l.635-639)
Batch: `-batch-size` required (`train.py:80`); loop uses 128 (`synchronous_loop.sh:62`). LR: `per_sample_lr = 0.00003 * get_effective_lr_scale` (`train.py:1094`; AdamW/Muon 1.33x :1087,1092; sqrt(batch*world/256) :1141); warmup ramp 1/20 -> 1 over 2M samples (:1059-1079; `-no-lr-warmup` :132); `-lr-scale` :83, `-lr-scale-auto` :84, `-lr-scale-auto2` :85 (:523-554), `-lr-schedule` :86 (:170-182, :556-564); `-head-lr-factor` 0.5 :87. **Default optimizer SGD momentum 0.9** (`train.py:844,942`; name :374); opt-in `-use-adamw` :101, `-use-muon` :102 (`python/muon/muon.py`, `train.py:39`, :840-842), `-use-normuon` :103, `-use-aurora` :104. Lookahead on by default k=6 (:97), alpha=0.5 (:98; :1046-1052, :1133-1134). SWA `-swa-period-samples`/`-swa-scale` :95-96. `-multi-gpus` :110 (DDP), `-use-fp16`/`-use-bf16` :111-112, `-no-compile` :113, `-use-tf32-matmul` :114. Transformer knobs: `-attn-logit-penalty-cap` None :140, `-attn-logit-penalty-coeff` 1e-3 :141, `-normal-attn-wd-factor` 1.0 :92; export guard `compute_attn_logit_dataless_bounds` (`model_pytorch.py:3010`) with `-attn-logit-bound-limit` 2.5e4 (`export_model_pytorch.py:42`), override `-ignore-attn-logit-bound` :43.
Window: `shuffle.py:414-435` `compute_desired_num_rows` is algebraically the paper's N_window when taper_window_scale = min_rows; `shuffle.sh:44-45,63-64,79-80` uses `-expand-window-per-row 0.4` (beta) and `-taper-window-exponent 0.65` (paper 0.75); loop passes min-rows 100000 and taper-window-scale 50000 (`synchronous_loop.sh:63,65,105`), keep-target-rows 600000 (:66).

## 10. Transformer trunk and the pos_len contract (code only)
`attnrope` -> `TransformerAttentionBlock(pos_len=pos_len, use_rope=True)` (`model_pytorch.py:3231-3239`); `ffng` positionwise (:3278-3285). Non-learnable RoPE (:2149): `rope_theta` 100.0 (:2167), `assert rope_theta > pos_len*2` (:2168; 100 > 18), tables `precompute_freqs_cos_sin_2d(q_head_dim, pos_len, theta)` (:2169-2171, persistent=False; builder :1252-1271); `apply_rotary_emb` (:1273-1290) requires seq_len == pos_len^2 (:1284-1285); `q_head_dim` 16 (:2108), `% 4 == 0` (:2112, :1256). Literal 19 in model_pytorch.py only as the global-feature count (:3103, :3111); spatial `[22, pos_len, pos_len]` (:3110).
pos_len sources: `train.py -pos-len` required (:79), consumed :340 -> `Model(model_config, pos_len)` :803,852 -> loader :1516,1773; **`train.sh:88` hard-codes 19**; assert `data_processing_pytorch.py:91` (:92-95); selfplay `dataBoardLen` (`selfplay.cpp:97,220,143`; buffers `trainingwrite.cpp:294-298`); **both selfplay cfgs set dataBoardLen 19 (:16)** with the warning comment :11-15. Export: `load_model(checkpoint, use_swa, device="cpu")` (`export_model_pytorch.py:90`) uses `load_model.py:62` default pos_len=19 (:77); random-init branch :84. Safe for b5c48h3tfr because RoPE tables and score-belief vectors are non-persistent buffers (:2170-2171, :2770-2784) and nothing pos_len-shaped is written to model.bin; C++ serializes only `ropeTheta` (`desc.cpp:1242-1250`) and recomputes RoPE at board size (`eigenbackend.cpp:1363-1365`).
Consistent-9x9 checklist: dataBoardLen 19 -> 9 (`selfplay1_maxsize9.cfg:16`); `-pos-len` 19 -> 9 (`train.sh:88`); bSizes <= 9 already; gatekeeper needs no dataBoardLen; export pos_len benign unless learnable_rope. Mismatch fires the assert (loud); **both left at 19 silently trains a 361-token model on 81 real tokens (~20x attention FLOPs, 842-wide score head)** — the most expensive silent misconfiguration; data at different dataBoardLen cannot be shuffled together.

## Divergence summary (severity)
HIGH dataBoardLen/-pos-len 19 (silent 20x waste); HIGH trunk has no gpool (heads only); MED value-head gpool collinear at strict 9x9; MED handicap silently off at 9x9; MED komi sigma scaled by sqrt(area)/19; MED LR 3e-5 + warmup ramp, SGD+Lookahead; MED value loss 0.72 vs 1.5, policy 0.93, no gamma penalty; LOW score-utility denominator 0.5*sqrt(area) and x0 shrink; LOW halflife 19 is correct; LOW useNoisePruning off; LOW window alpha 0.65 and taper != min-rows; INFO attn-logit export guard; INFO USEGATING=0 bypass.

## `[OPEN]` (not confirmed by reading)
gpool constant re-centering vs C++ compatibility; cost of rootNumSymmetriesToSample=4 with RoPE (not rotation-equivariant); muon.py internals; persistent pos_len-shaped tensors in other configs.
