# Convention — arXiv:1902.10565 (*Accelerating Self-Play Learning in Go*)

Stage 1-decompose artifact. Output contract: `pipelines/1-decompose/spec.md` § Output contract.
Markers per `_common/contracts/markers.md`.

`l.NNN` = line in `ref-paper/arxiv-1902.10565/src/Accelerating_Self_Play_Learning_In_Go_2020.tex`.
The **code** column names the key/identifier that realizes the symbol in the pinned mirror
`ref-code/lightvector-KataGo` @ `v1.18.2` (`fd0723fd`); every entry there was confirmed by
`grep` against the mirror (read-only) or taken from
`results/ktg/sources/code_lightvector-KataGo.md`. `[OPEN]` = not located; not guessed.
Where the mirror's value differs from the paper's, both are given — the mirror is the
artifact the mission runs, the paper is 2019/2020 prose.

## 1. Search (MCTS / PUCT)

| symbol | meaning | units / range | tex | code (`v1.18.2`) |
|---|---|---|---|---|
| `PUCT(c)` | selection score for child `c` at each node | real | l.58 | `Search::getExploreSelectionValue`, `cpp/search/searchexplorehelpers.cpp` |
| `V(c)` | average predicted utility over `c`'s subtree | `[-1,1]`+score utility | l.59 | node `utilityAvg`, `cpp/search/` |
| `P(c)` | policy prior for `c` (noised at root) | prob., sums to 1 | l.59, l.68 | `policyProbs` |
| `P_raw(c)` | un-noised net policy prior | prob. | l.68 | `nnOutput->policyProbs` |
| `N(c)` | playouts previously sent through `c` | count ≥0 | l.59 | `childVisits` / `childWeight` |
| `c_PUCT` | PUCT exploration constant = 1.1 | dimensionless | l.59 | `cpuctExploration = 1.1` (`selfplay1.cfg:171`) |
| `c_FPU` | first-play-urgency reduction = 0.2; 0 at root with noise | dimensionless | l.63-64 | `fpuReductionMax = 0.2`, `rootFpuReductionMax = 0.0` (`selfplay1.cfg:173-174`) |
| `P_explored` | total prior of children with `N>0` | `[0,1]` | l.64 | `fpuParentWeightByVisitedPolicy = true` (`selfplay1.cfg:184`) |
| `eta` | Dirichlet noise draw added to root prior, weight 0.25 | prob. vector | l.68 | `rootDirichletNoiseWeight = 0.25` (`selfplay1.cfg:146`) |
| `alpha` | Dirichlet parameter `0.03*19^2/N`, `N` = #legal moves | conc. | l.69 | `rootDirichletNoiseTotalConcentration = 10.83` = `0.03*361` (`selfplay1.cfg:145`) |
| root softmax temperature | 1.03 applied to root policy | dimensionless | l.69 | `rootPolicyTemperature = 1.1`, `rootPolicyTemperatureEarly = 1.25` (`selfplay1.cfg:168-169`) — mirror ≠ paper |
| `n_forced(c)` | forced-playout floor `(k P(c) sum_c' N(c'))^{1/2}` | count | l.105 | `sqrt(nnPolicyProb*totalChildWeight*coeff)` → urgency `1e20`, `cpp/search/searchexplorehelpers.cpp:166-169` |
| `k` | forced-playout constant = 2 | dimensionless | l.106 | `rootDesiredPerChildVisitsCoeff = 2` (`selfplay1.cfg:148`; semantics `cpp/search/searchparams.h:69`) |
| `c*` | root child with the most playouts; pruning reference | — | l.108 | `Search::pruneNoiseWeight`, `cpp/search/searchupdatehelpers.cpp:495` |
| `u_win(x)` | win/loss utility `sign(x)` | `{-1,1}` | l.687 | `winLossUtilityFactor = 1.0` (`selfplay1.cfg:157`) |
| `u_score(x)` | score utility `c_score * f((x-x0)/b)` | `(-c_score,c_score)` | l.689 | `dynamicScoreUtilityFactor = 0.40` (`selfplay1.cfg:159`); `staticScoreUtilityFactor = 0.00` |
| `c_score` | score-utility weight; 0.5 → 0.4 after 2 days | dimensionless | l.690, l.705 | `dynamicScoreUtilityFactor = 0.40` |
| `x0` | utility centering, reset to `mu_s` each search | points | l.690, l.701 | `dynamicScoreCenterZeroWeight = 0.25`, `dynamicScoreCenterScale = 0.50` (`selfplay1.cfg:160-161`) |
| `f(x)` | `(2/pi) arctan(x)` | `(-1,1)` | l.691 | `[OPEN] score-util-fn` |
| `x` | final score difference of a game | points | l.686 | — |

## 2. Self-play data generation

| symbol | meaning | units / range | tex | code (`v1.18.2`) |
|---|---|---|---|---|
| `p` | probability a turn gets a **full** search = 0.25 | prob. | l.96 | `cheapSearchProb = 0.75` = `1-p` (`selfplay1.cfg:60`) |
| `N` | full-search visit cap; 600 → 1000 after 2 days | visits | l.96 | `maxVisits = 600` (`selfplay1.cfg:115`) |
| `n` | cheap-search visit cap; 100 → 200 | visits | l.96 | `cheapSearchVisits = 100` (`selfplay1.cfg:61`) |
| — | cheap searches contribute no training weight | weight | l.96 | `cheapSearchTargetWeight = 0.0` (`selfplay1.cfg:62`) |
| `lambda` | `p/0.05`, visit-cap taper when losing side <5% for 5 turns | `[0,1]` | l.660 | `reduceVisits`, `reduceVisitsThreshold = 0.9`, `reduceVisitsThresholdLookback = 3`, `reducedVisitsMin = 100`, `reducedVisitsWeight = 0.1` (`selfplay1.cfg:64-68`) — mirror ≠ paper (3 vs 5 turns) |
| `komi` | White's compensation; 7.5 standard | points (half-int) | l.180, l.240 | `komiAuto = True` (`selfplay1.cfg:99`) |
| komi randomization | `N(mean 7, sd 1)`, truncated 3σ, rounded; 5% use sd 10 | points | l.651 | `komiStdev = 1.0`, `komiBigStdevProb = 0.06`, `komiBigStdev = 12.0` (`selfplay1.cfg:101-103`) — mirror ≠ paper |
| handicap rate | 5% of games; free Black moves 0/1/2/3 by board size | prob. | l.652 | `handicapProb = 0.10`, `handicapCompensateKomiProb = 0.50` (`selfplay1.cfg:105-106`) — mirror ≠ paper |
| `r` | number of raw-policy opening moves, `Exp(mean 0.04 b^2)` | turns | l.653 | `initGamesWithPolicy = true` (`selfplay1.cfg:55`), `compensateAfterPolicyInitProb = 0.2` (`:57`) |
| `T` | move-selection temperature, 0.8 → 0.2, halflife `b` turns | dimensionless | l.653 | `chosenMoveTemperatureEarly = 0.75`, `chosenMoveTemperature = 0.15`, `chosenMoveTemperatureHalflife = 19` (`selfplay1.cfg:138-140`) |
| branch rate | 2.5% of positions forked to an alternative move | prob. | l.654 | `forkCompensateKomiProb = 0.80` (`selfplay1.cfg:107`) |
| unusual-opening rate | 5% of games branched after `Exp(mean 0.025 b^2)` turns | prob. | l.655 | `[OPEN] fork-keys` |
| board-size distribution | 37.5→50% on 19×19; rest triangular 9…18 weights 1..10 | prob. | l.650 | `bSizes` / `bSizeRelProbs` (`selfplay1.cfg:95-96`) |
| rules | Tromp-Taylor, pass-alive modified; ko/suicide randomized | categorical | l.81, l.649 | `[OPEN] rules-keys` |

## 3. Neural net architecture

| symbol | meaning | units / range | tex | code (`v1.18.2`) |
|---|---|---|---|---|
| `b` (§Overview) | number of residual blocks in the trunk | count | l.71 | see §7 collision |
| `b` (appendices) | **board width** | `[b_min,b_max]=[9,19]` | l.185, l.360, l.690 | `pos_len` (`python/train.py:79`); per-sample `mask_sum_hw` |
| `b_min`, `b_max` | min/max board width = 9, 19 | width | l.360 | `bSizes` range; `-pos-len` |
| `n` (appendix A) | number of residual blocks = 6/10/15/20 | count | l.419, l.525 | `block_kind` list length (`modelconfigs.py`) |
| `c` (arch) | trunk channels = 96/128/192/256 | count | l.71, l.526 | `trunk_num_channels` (`modelconfigs.py:993` for `b5c48h3tfr`: 48) |
| `c_pool` | channels pooled inside a gpool residual block = 32/32/64/64 | count | l.434, l.527 | `gpool_num_channels` (`modelconfigs.py:995`: 32) |
| `c_head` | policy/value head channels = 32/32/32/48 | count | l.447, l.528 | `p1_num_channels`, `g1_num_channels`, `v1_num_channels` (`modelconfigs.py:1001-1003`: 16/16/16) |
| `c_val` | value-head hidden width = 48/64/80/96 | count | l.464, l.529 | `v2_size` (`modelconfigs.py:1005`: 48); `sbv2_num_channels` = 32 |
| `X`, `G` | gpool-bias input tensors, shapes `b×b×c_X`, `b×b×c_G` | tensor | l.131, l.406 | `KataConvAndGPool`, `python/katago/train/model_pytorch.py:543+` |
| `b_avg` | `0.5(b_min+b_max) = 14`, gpool mean-scaling offset | width | l.401, l.404 | hard-coded `14.0` (`model_pytorch.py:505`, `:534`) |
| `sigma^2` | `(1/11) sum_{b'=9..19}(b'-b_avg)^2 = 10`, value-head pool offset | width² | l.404 | hard-coded via `/100.0 - 0.1` (`model_pytorch.py:540`) |
| `3c` | gpool layer output width (mean, scaled mean, max) | count | l.129, l.398-402 | `KataGPool.forward` returns `cat(pool1,pool2,pool3)` (`model_pytorch.py:517`) |
| `pi_hat`, `pi_hat_opp` | predicted own / opponent-next-turn policy | prob. | l.451 | `PolicyHead` 2-channel output (`model_pytorch.py:2610`) |
| `z_hat` | softmax over {win, loss, no-result} | prob. | l.468 | value head first 3 logits |
| `mu_s_hat` | predicted mean final score (net output × 20) | points | l.469 | `scoremean_multiplier` (`metrics_pytorch.py`) |
| `sigma_s_hat` | predicted stdev of final score (softplus × 20) | points | l.470 | value head 5th output |
| `rv_hat_i` | predicted MCTS root-value variance, 4 playout counts; ~0 weight | var | l.471, l.593 | `[OPEN] rv-head` |
| `o(l,p)`, `o_hat` | final ownership of point `l` by player `p`; prediction | `{0,0.5,1}` / `[-1,1]` | l.185, l.484 | `conv_ownership` (`model_pytorch.py:2803`) |
| `s` | a possible final score value, half-integers in `(-S,S)` | points | l.496 | `score_belief_offset_vector` (`model_pytorch.py:2771`) |
| `S` | score-head half-width = `19*19 + 60` = 421 | points | l.497, l.512 | `pos_len*pos_len + EXTRA_SCORE_DISTR_RADIUS`, `EXTRA_SCORE_DISTR_RADIUS = 60` (`model_pytorch.py:26`, `:2759`) |
| `2S` | score-belief output length | count | l.506 | `scorebelief_len = 2*(pos_len^2+60)` (`metrics_pytorch.py:35`) |
| `Parity(s)` | indicator that `s` is parity-consistent with board size + komi | `{-0.5,0.5}` | l.501 | `score_belief_parity_vector` (`model_pytorch.py:2781`) |
| `gamma` | learned scaling of the score-belief logits | real | l.493, l.584 | `linear_s3` output / `num_scorebeliefs = 4` (`modelconfigs.py:1004`) |
| `p_s`, `p_s_hat` | one-hot final score difference; predicted distribution | prob. | l.189 | `scorebelief` logits |

## 4. Loss function (Appendix B, l.541-591)

| symbol | meaning | paper value | tex | code (`v1.18.2`) |
|---|---|---|---|---|
| `L` | total training loss (sum of the terms below + L2) | — | l.74, l.543 | `Metrics.loss_*_samplewise` (`metrics_pytorch.py`) |
| `c_g` = `c_value` | game-outcome value loss weight | 1.5 | l.75, l.547 | `1.20` (`metrics_pytorch.py:127`) — mirror ≠ paper |
| — | policy loss weight (reference scale) | 1.0 | l.550 | `1.0` (`metrics_pytorch.py:82`) |
| `w_opp` | auxiliary opponent-policy loss weight | 0.15 | l.160, l.555 | `0.15` (`metrics_pytorch.py:88`) |
| `w_o` | ownership loss weight `1.5/b^2` (i.e. 1.5 per-point mean) | `1.5/b^2` | l.185, l.559 | `1.5` × mean over on-board points (`metrics_pytorch.py:161`) |
| `w_spdf` | score-belief pdf (cross-entropy) weight | 0.02 | l.189, l.563 | `0.020` (`metrics_pytorch.py:273`) |
| `w_scdf` | score-belief cdf (squared-CDF) weight | 0.02 | l.193, l.567 | `0.020` (`metrics_pytorch.py:267`) |
| `w_sbreg` | self-prediction (Huber) weight for `mu_s_hat`, `sigma_s_hat` | 0.004 | l.571 | `0.0015` (`metrics_pytorch.py:253`) — mirror ≠ paper |
| `delta` | Huber transition point | 10.0 | l.570 | `12.0` (`metrics_pytorch.py:252`) — mirror ≠ paper |
| `mu_s`, `sigma_s` | mean / stdev implied by the net's own score belief | points | l.572, l.580 | `expected_score_from_belief`, `stdev_of_belief` (`metrics_pytorch.py:277+`) |
| `w_scale` | penalty weight on `gamma^2` | 0.0005 | l.585 | `[OPEN] gamma-penalty` |
| `c_L2` | L2 penalty on `theta` | 3e-5 | l.75, l.589 | `[OPEN] l2-key` (optimizer weight decay in `python/train.py`) |
| `theta` | model parameters | — | l.75, l.588 | — |

## 5. Training schedule (Appendix C, l.601-639)

| symbol | meaning | paper value | tex | code (`v1.18.2`) |
|---|---|---|---|---|
| batch size | SGD minibatch | 256 | l.77, l.635 | `$BATCHSIZE` arg (`python/selfplay/train.sh`) |
| momentum | SGD momentum decay | 0.9 | l.77 | `[OPEN] optimizer-key` |
| per-sample LR | learning rate per sample | 6e-5 (2e-5 first 5M; 6e-6 late) | l.77, l.635 | `-lr-scale` / `-lr-schedule` (`python/train.py:83-86`) |
| SWA | snapshot every ~250k samples, EMA decay 0.75 over 4 | — | l.79 | `-swa-period-samples`, `-swa-scale` (default 8) (`python/train.py:95-96`, `:440-443`) |
| `N_window` | sampling-window size `c(1 + beta((N_total/c)^alpha - 1)/alpha)` | samples | l.638 | `compute_desired_num_rows` (`python/shuffle.py:414-430`) |
| `N_total` | cumulative self-play samples generated so far | samples | l.638 | `num_usable_rows` |
| `c` (window) | window anchor constant | 250,000 | l.639 | `-min-rows` / `-taper-window-scale` |
| `alpha` (window) | window power-law exponent | 0.75 | l.639 | `-taper-window-exponent` (upstream advice 0.65-0.675) |
| `beta` (window) | window slope at the anchor | 0.4 | l.639 | `-expand-window-per-row 0.4` (`shuffle.py:734`) |

## 6. Evaluation and gating

| symbol | meaning | value | tex | code (`v1.18.2`) |
|---|---|---|---|---|
| gate win requirement | candidate must win ≥100 of 200 | 0.5 | l.79, l.669 | `numGamesPerGating = 200` (`gatekeeper1.cfg:20`); `-required-candidate-win-prop` default `0.5` (`cpp/command/gatekeeper.cpp:271`) |
| gate visit cap | 300 nodes, → 400 after 2 days | visits | l.669 | `maxVisits = 150` (`gatekeeper1.cfg:49`) — mirror ≠ paper |
| gate komi | fixed, not randomized | 7.5 | l.672 | `komiAuto = True` (`gatekeeper1.cfg:42`) — mirror ≠ paper |
| gate `T` | move-selection temperature start | 0.5 | l.675 | `chosenMoveTemperatureEarly = 0.5` (`gatekeeper1.cfg:72`) |
| eval visits | strength-match search cap | 1600 | l.240 | not a training key |
| cost metric | self-play compute modelled as `~ b c^2` per query | queries | l.252 | not implemented in the mirror |
| Elo | BayesElo maximum-likelihood rating | Elo | l.234, l.237 | not implemented in the mirror |

## 7. Symbol collisions in the paper (resolve before implementation)

- `b` = **residual block count** at l.71 (`(b,c)` = (6,96)…(20,256)) but = **board width** at
  l.185, l.360, l.404, l.653, l.690. Appendix A re-names the block count `n` (l.419, l.525).
  Convention adopted here: `b` = board width; `n_blocks` = trunk depth.
- `n` = **cheap visit cap** at l.96 but = **residual block count** at l.419/l.525.
  Convention adopted here: `n` = cheap visit cap; `n_blocks` = depth.
- `N` = **child playout count** at l.59, **full visit cap** at l.96, **number of legal moves**
  at l.69, and `N_window`/`N_total` at l.638. Always subscript.
- `c` = **trunk channels** (l.71), **L2 coefficient** (l.588), **window anchor 250,000** (l.639),
  and **a search child** (l.58). Always subscript.
- `sigma` = board-width variance `sigma^2 = 10` (l.404) vs score-belief stdev `sigma_s` (l.470).

## 8. 9x9-only substitutions

Mission regime: `bSizes = 9` only, transformer trunk `b5c48h3tfr`, ≤4 GPUs, ≤24 CPUs, 3-day wall.
Every row states the paper's mixed-size value and what it becomes at 9×9.

| symbol | paper (19×19 / mixed) | 9×9-only value / behaviour | note |
|---|---|---|---|
| board-size distribution (l.650) | 37.5→50% on 19×19; rest triangular 9…18, weights 1..10 | `bSizes = 9`, `bSizeRelProbs = 1` | `[ASSUMPTION] mission-9only` — no upstream 9-only config exists; `selfplay1_maxsize9.cfg:95-96` is `7,8,9`/`1,1,8`, so a mission-owned override is required |
| `b` (board width, l.360) | `[b_min,b_max] = [9,19]` | fixed 9 | width is now a constant, not a distribution |
| `b_avg = 14` (l.404) | `0.5(9+19)` — mid-range of the training distribution | still **hard-coded 14.0** in `model_pytorch.py:505`,`:534` | `[ASSUMPTION] bavg-keep` — keep 14.0 unmodified; at `b=9` the gpool channel 2 is the constant `(3-14)/10 = -1.1`, i.e. an extra bias, not a size signal. Changing it would fork the mirror (kernel §4) |
| `sigma^2 = 10` (l.404) | variance of widths 9…19 | still hard-coded (`/100.0 - 0.1`, `model_pytorch.py:540`) | `[ASSUMPTION] sigma-keep` — same reasoning; value-head pool channel 3 becomes the constant `(121/100)-0.1 = 1.11` |
| `S = 19*19 + 60 = 421` (l.497, l.512) | max plausible score at 19×19 | `S = 9*9 + 60 = 141` when trained with `-pos-len 9` | mechanical: `pos_len*pos_len + EXTRA_SCORE_DISTR_RADIUS` (`model_pytorch.py:2759`). `[OPEN] poslen-wiring` — `python/selfplay/train.sh:88` hard-codes `-pos-len 19`; the mission must override it. **Closes when** the mission's `train.sh` invocation is written with `-pos-len 9` and the resulting `scorebelief_len = 282` observed |
| `w_o = 1.5/b^2` (l.185, l.559) | `1.5/361` at 19×19 | `1.5/81` at 9×9 — automatic | the code already divides by `mask_sum_hw`, so no change is needed |
| `u_score` divisor `b` (l.690) | 19 in Figure `ScoreUtility` (l.697) | 9 — automatic from board width | score utility saturates ~2× faster in points |
| `alpha` Dirichlet `= 0.03*19^2/N` (l.69) | 10.83 total concentration, spread over ≤362 moves | total concentration unchanged (10.83), now spread over ≤82 moves | per-move `alpha` rises ~4.4×; `[HYPOTHESIS] noise-9x9` — root exploration is effectively stronger at 9×9; no measurement here |
| `r` opening moves `Exp(0.04 b^2)` (l.653) | mean 14.4 turns | mean 3.24 turns — automatic | |
| `T` halflife `= b` turns (l.653) | 19 turns | 9 turns intended; mirror hard-codes `chosenMoveTemperatureHalflife = 19` | `[OPEN] temp-halflife` — **closes when** the mission config sets the halflife explicitly for 9×9 |
| handicap free moves (l.652) | 3 at 19×19 | **0 for board sizes 9 and 10** (paper, l.652) | handicap contributes nothing at 9×9; `[ASSUMPTION] handicap-off` — mission may set `handicapProb = 0` |
| trunk = residual CNN + 2-3 gpool blocks (l.419-439) | `b6c96`…`b20c256`, gpool in the trunk | `b5c48h3tfr`: 5×(`attnrope` + `ffng`) blocks, **no gpool block in the trunk** (`modelconfigs.py:999`) | gpool survives only in the heads (`PolicyHead` `model_pytorch.py:2647`, `ValueHead` `:2745`, both unconditional). `[HYPOTHESIS] gpool-attn` — self-attention is globally receptive, so the trunk gpool blocks the paper ablates (l.286, Table l.335: 1.60×) have no direct analogue here; the ablation factor does not transfer |
| `(b,c)` progressive resizing (l.71) | 4 sizes, switched at 0.75/1.75/7.5 days | single size `b5c48h3tfr` for the whole run | `[ASSUMPTION] single-size` — mission budget is 3 days total |
| `N`, `n`, `p` (l.96) | 600/100 → 1000/200 at `p=0.25` | `[OPEN] visit-caps-9x9` — paper values are tuned for 19×19 search depth. **Closes when** the mission's `selfplay.cfg` records chosen `maxVisits`/`cheapSearchVisits` with the CPU-budget derivation |
| all reported Elo (l.240, l.293, Table l.332-338) | 19×19 matches vs ELF / Leela Zero | not applicable | `[OPEN] success-criterion` — no 9×9 opponent pool exists in the mirror. **Closes when** a 9×9-only success criterion is defined that cites no paper Elo figure |
