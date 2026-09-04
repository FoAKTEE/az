# derivation.md — paper ideas still present in the v1.18.2 code (code-first map)

**Source priority (human redirect, 2026-09-03):** the code mirror `ref-code/lightvector-KataGo/` @ v1.18.2 is
the source of truth; arXiv:1902.10565 (2019/2020 tex, `ref-paper/arxiv-1902.10565/src/*.tex`, `l.NNN`) is
background. This file therefore is not an equation-by-equation derivation: it lists each paper idea that the
current code still implements, with the code anchor, the config keys that control it, and its status on a
9x9-only transformer run. Ideas the code has superseded are listed once at the end so nobody inherits them.
The tex has no `\label` on displayed equations; where a paper formula is quoted it is labelled by tex line
(`eq:lNNN`). Full evidence with every path:line: `../evidence/decomposition/audit_paper_code_map.md`,
`../evidence/decomposition/audit_loop_scripts_configs.md`.

Status vocabulary (markers.md): `[SOLID]` = read in code with path:line; `[PRELIMINARY]` = derived from code
constants but not executed; `[OPEN]` = needs execution or a decision.

## 1. Ideas the code still implements (mission inherits them by running the code)

| # | idea (paper anchor) | code anchor (v1.18.2) | config keys / flags (maxsize9 preset values) | 9x9 transformer status |
|---|---|---|---|---|
| 1 | PUCT search with root Dirichlet noise scaled to legal moves (eq:l58, eq:l68) | `cpp/search/searchexplorehelpers.cpp`, `searchparams.h` | `rootNoiseEnabled` true, `rootDirichletNoiseTotalConcentration` 10.83, `rootDirichletNoiseWeight` 0.25, `rootPolicyTemperature` 1.1 / `Early` 1.25 (`selfplay1_maxsize9.cfg:144-146,168-169`) | `[SOLID]` unchanged; board-independent |
| 2 | Playout cap randomization: full search on a fraction of turns, cheap elsewhere, only full turns recorded (l.96-97; paper p=0.25, (N,n)=(600,100)) | `cpp/program/play.cpp:1132-1150` (`:1141-1142` visits, `:1143` target weight, `:1146-1149` noise off) | `cheapSearchProb` 0.75, `cheapSearchVisits` 100, `cheapSearchTargetWeight` 0.0, `maxVisits` 600 (`:60-62,115`) = the paper's initial setting | `[SOLID]` unchanged; drives rows/game (~0.27 rows per turn) |
| 3 | Forced root playouts n_forced = (k P Σ N)^{1/2}, k = 2 (eq:l105) | `cpp/search/searchexplorehelpers.cpp:166-169` (returns 1e20 while `childWeight < sqrt(P * total * coeff)`) | `rootDesiredPerChildVisitsCoeff` 2 (`:148`); default 0.0 (`searchparams.cpp:54`) | `[SOLID]` unchanged; no `forcedPlayouts` key exists |
| 4 | Policy target pruning: subtract playouts PUCT would not have chosen, prune single-playout children (l.109) | `Search::getReducedPlaySelectionWeight` `searchexplorehelpers.cpp:229-263`, applied `searchresults.cpp:142-195`; single-playout prune `:318-328` | `chosenMoveSubtract` 0, `chosenMovePrune` 1 (`:141-142`); `useNoisePruning` false in selfplay (`setup.cpp:578`) | `[SOLID]` unchanged; prune floor min(1, max/64) = 1 at 9x9/600 visits |
| 5 | Auxiliary opponent-reply policy, w_opp = 0.15 (eq:l159) | `metrics_pytorch.py:84-88` (0.15 exact); head channel `model_pytorch.py:2630`; target `trainingwrite.cpp:1174,562` | none (constant) | `[SOLID]` unchanged; plus code-only soft/optimistic policy terms (`train.py:143`, `metrics_pytorch.py:600-607`) |
| 6 | Ownership loss with 1.5/b² normalisation (eq:l184) | `metrics_pytorch.py:157-161` (`1.5 * Σ BCE·mask / mask_sum_hw`) | none | `[SOLID]` exact; at b = 9 the per-cell weight is 1.5/81 |
| 7 | Score-belief pdf + cdf losses, 0.02 each (eq:l188, eq:l192) | `metrics_pytorch.py:273`, `:267`; support `2·(pos_len² + EXTRA_SCORE_DISTR_RADIUS)` (`:35`, `model_pytorch.py:2759-2760`) | none | `[SOLID]` exact weights; support shrinks 842 -> 282 automatically at pos_len 9 |
| 8 | Score utility u = c·(2/π)·arctan((x−x0)/scale·√area), x0 re-centred each search (eq:l689-l702) | `cpp/neuralnet/nninputs.cpp:56,113-190`; centre `search.cpp:1137-1166` | `dynamicScoreUtilityFactor` 0.40 (= paper's 0.4), `dynamicScoreCenterZeroWeight` 0.25, `dynamicScoreCenterScale` 0.50, `staticScoreUtilityFactor` 0 (`:157-163`) | `[SOLID]` unchanged in form; denominator is 0.5·√area = 4.5 at 9x9, x0 pulled 25 % toward 0 (code, not paper) |
| 9 | Game randomization: rules, komi ~ N(auto, σ), policy-sampled opening r ~ Exp(0.04 b²), temperature decay with board-scaled half-life, forks, side positions, reduced visits instead of resignation (l.648-663) | `play.cpp:189-204,974-982,1151-1187,1681-1693,2446`; `playutils.cpp:10-65,234-268`; `searchhelpers.cpp:541-545` | `komiAuto` True, `komiStdev` 1.0, `komiBigStdevProb` 0.06, `komiBigStdev` 12; `policyInitAreaProp` 0.04; `chosenMoveTemperatureEarly` 0.75 / `chosenMoveTemperature` 0.15 / `Halflife` 19; `sidePositionProb` 0.02; `earlyForkGameProb` 0.04 + `forkGameProb` 0.01; `reduceVisits*` (`:26-33,55-68,99-108,138-140`) | `[SOLID]` unchanged; at 9x9: komi σ scaled to 0.474 (`playutils.cpp:42`), handicap silently off (`playutils.cpp:10-22`), half-life 19 is **correct** (`searchhelpers.cpp:543` divides by √area/19) |
| 10 | Board-size mixing (l.650) | `bSizes`/`bSizeRelProbs`/`allowRectangleProb` | `7,8,9` / `1,1,8` / 0.50 (`:95-97`) | **replaced**: mission sets `9` / `1` / `0` — `[OPEN] o01` |
| 11 | Gating: candidate must win ≥ 50 % of N games vs current net (l.669) | `cpp/command/gatekeeper.cpp:108,184,188,271,580` | `numGamesPerGating` 200 (`gatekeeper1_maxsize9.cfg:20`), `-required-candidate-win-prop` 0.5 (CLI default), `maxVisits` 150 (`:49`) | `[SOLID]` unchanged; `USEGATING=0` bypass exists (`export_model_for_selfplay.sh:115-120`) — `[OPEN] o16` decision |
| 12 | Sliding training window N_window = c(1 + β((N/c)^α − 1)/α) (eq:l638) | `shuffle.py:414-435` (identical when `taper_window_scale = min_rows`) | `-expand-window-per-row` 0.4 (β), `-taper-window-exponent` 0.65 (paper 0.75), `-min-rows`, `-taper-window-scale`, `-keep-target-rows` (`shuffle.sh:44-45`; `synchronous_loop.sh:63-66`) | `[SOLID]` form present; constants are mission levers |
| 13 | Global pooling with (b − 14)/10 and ((b − 14)² − 10)/100 channels (l.398-404) | `model_pytorch.py:492-543` (`:505,514,534,539-540`); policy head `:2647`, value head `:2745` | none | **heads only**: the transformer trunk has no gpool (`:3157-3160,3231-3285`); at strict 9x9 the value-head pooled vector is exactly collinear (pool2 = −0.5·pool1, pool3 = 0.15·pool1) — `[PRELIMINARY]` harmless, wasted capacity; see node `head_gpool_degeneracy_9x9` |
| 14 | SGD momentum 0.9 + weight decay; snapshot averaging (l.78-80) | `train.py:844,942` (SGD default), `:632-750` (decoupled wd 0.00125·…), `:97-98` (Lookahead k=6 α=0.5), `:95-96` (SWA flags) | `-lr-scale`, `-lr-schedule`, `-swa-period-samples`, `-use-muon/-use-adamw` opt-in | `[SOLID]` code defaults differ from paper (lr 3e-5 per sample, warmup ramp over 2M samples) — code values are the mission's |

## 2. Loss-weight table the mission actually trains with

| term | code effective weight | source |
|---|---|---|
| policy | 0.930 | `metrics_pytorch.py:605` |
| opponent policy | 0.15 | `:88` |
| soft policy ×2 | 8.0 | `train.py:143` |
| long / short optimistic policy | 0.10 / 0.20 | `:600-601` |
| game outcome value | 1.20 × 0.6 = 0.72 | `:127`, `train.py:146` |
| TD value ×3 | 0.72 each | `:136`, `train.py:147` |
| ownership | 1.5 / b² | `:157-161` |
| scoring / futurepos / seki | 0.25 (/b²) / 0.25 (/b) / adaptive | `:869,171-173`, `:192-194`, `:222-246` |
| score pdf / cdf | 0.02 / 0.02 | `:273`, `:267` |
| score mean / stdev self-prediction | 0.0015 (Huber 12) / 0.001 (Huber 10) | `:257-258`, `:281-288` |
| lead / variance-time / shortterm value / shortterm score | 0.006 / 0.0003 / 2.0 / 2e-5 | `:297-323` |
| weight decay | optimizer-side, base 0.00125, attn group 0.5 | `train.py:711-712,733` |

The paper's `c_value = 1.5`, `w_sbreg = 0.004`, `w_scale = 0.0005` (l.547,571,585) are **not** what the code uses.

## 3. Paper constructs superseded or absent in v1.18.2 (do not build on them)

| construct | paper anchor | what the code does instead |
|---|---|---|
| Residual-CNN trunk with gpool blocks, BN + ReLU, (b,c) ladder (6,96)→(20,256) | l.72, l.414-441, l.518-534 | transformer trunk `b7c96h3tfrs`: 7 × (`attnrope`, `ffnsg`), 96 channels, 3 heads, RoPE θ=100 (`modelconfigs.py:1008-1029`, `model_pytorch.py:2149-2171,3231-3285`). `b5c48h3tfr` (`ffng`, `:986-1006`) is trainable but no C++ backend serves non-SwiGLU FFNs (`cudaandrocmbackend.inc:3307-3308`); `nbt` fused family also exists and is exportable (`export_model_pytorch.py:495-502`) |
| Score support S = 19·19 + 60 fixed | l.496, l.512 | support derived from `pos_len` (`metrics_pytorch.py:35`) |
| Fixed per-sample lr 6e-5, ÷3 for 5M samples, ÷10 late | l.635-636 | 3e-5 base, 9-step warmup to 2M samples, `-lr-scale*` flags (`train.py:1059-1094`) |
| Batch 256 | l.635 | loop default 128 (`synchronous_loop.sh:62`) |
| Handicap up to 3 free moves | l.652 | table differs; 0 at ≤ 10 (`playutils.cpp:10-22`) |
| Gating 300→400 nodes, komi fixed 7.5 | l.669-671 | `maxVisits` 150, `komiAuto` (`gatekeeper1_maxsize9.cfg:42,49`) |
| 16–24 V100 self-play : 1 train GPU, 19 days | l.603 | only the *ratio* (self-play ≫ train) is carried into `DESIGN.md`; no paper number is a target |
| 19x19 Elo vs ELF / Leela Zero | l.238-274, l.331-342 | not applicable; `eval_improvement` node defines the 9x9 criterion |
| V1 input features: 18 spatial + 10 global | l.361-394 | V7: 22 spatial + 19 global (`model_pytorch.py:3103,3110-3111`) |

## 4. Mission arithmetic derived from code constants (`[PRELIMINARY]` until measured)

- rows/game at 9x9 ≈ (1 − 0.75)·80 + 0.02·80 ≈ 22 (cheap-search turns write w = 0, `play.cpp:1143`; `trainingwrite.cpp:1206-1251`); bytes/row 2145 at pos_len 9 vs 7675 at 19 (`trainingwrite.cpp:292-299`); on-disk ≈ 0.12 × (`shuffle.py:47`) ⇒ ≈ 5.7 KB/game.
- Attention cost at pos_len 19 vs 9 for the same 9x9 games: (361/81)² ≈ 19.9× — the reason `dataBoardLen` and `-pos-len` must both be 9.
- Gating at p = 0.5 with 200 games and threshold 0.5 accepts with probability ≈ 0.53 — the filter is weak by design (paper l.669 "fairly lightweight").
