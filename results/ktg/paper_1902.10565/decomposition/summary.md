# Summary — arXiv:1902.10565 (*Accelerating Self-Play Learning in Go*)

Stage 1-decompose artifact. Output contract: `pipelines/1-decompose/spec.md` § Output contract.
Markers per `_common/contracts/markers.md`.
`l.NNN` = line in `ref-paper/arxiv-1902.10565/src/Accelerating_Self_Play_Learning_In_Go_2020.tex`.
Statements about the mission regime (9×9-only, transformer trunk `b5c48h3tfr`, ≤4 GPUs,
≤24 CPUs, 3-day wall) that the paper does not make carry a marker.

## Motivation

AlphaZero-class self-play learning works but is priced out of reach: DeepMind's Go run used
5000 TPUs for several days, ~41 TPU-years (l.33); ELF OpenGo's replication used 2000 V100
GPUs for 13-14 days, ~74 GPU-years (l.33). The paper's premise is that this cost is not
intrinsic to the algorithm — a large fraction of it is avoidable through better data
balance, better targets, and better architecture, most of them not specific to Go (l.44).
A second motivation is diagnostic: measuring how much of the remaining gap is closed by
*domain-specific* tricks tells us how far general methods still are from what is possible
(l.46).

## Goal

Reach ELF OpenGo's final strength from random initialization, with no human data and no
external strategic knowledge, on a computation budget roughly 50× smaller, and attribute
the speedup to individually ablatable components (l.38, l.48).

## Result scope

- **What was measured.** (1) Elo of KataGo's nets through training versus a Leela Zero
  ladder (LZ30…LZ225) and ELF's final "V2" net, all rated by BayesElo from ~21,000 games
  (l.232-240). (2) Three direct 400-game matches against ELF's native engine, at fixed
  playouts and at fixed wall clock (l.261, Table l.268-270). (3) Six 2-day ablation runs —
  `FixedN`, `NoForcedTP`, `NoGPool`, `NoPAux`, `NoVAux`, `NoGoFeat` — rated over ~147,000
  games (l.282-293, Table l.332-338).
- **Board sizes.** *Training* mixes sizes: 37.5→50% of games on 19×19, the rest triangular
  from 9×9 to 18×18 with weights 1…10 (l.650). *All evaluation* is 19×19 with fixed 7.5
  komi, 1600 visits, no multithreading (l.240, l.293). No 9×9 result is reported anywhere.
- **Hardware / time.** Main run: 19 days, max 28 V100 GPUs (averaging 26-27) — 16 for
  self-play rising to 24, 2 for gating, 1-2 for training (l.81, l.603). Output: 241M
  training samples over 4.2M games across four net sizes b6c96 → b20c256 (l.71, l.603,
  Table l.610-613). Ablations: ~2 days each (l.282).
- **Cost metric.** Compute is reported not in GPU-hours but as equivalent 20-block ×
  256-channel queries, modelling a `b`-block `c`-channel net as `~ b c^2` per query (l.252).

## Conclusions

- KataGo surpasses ELF's final model after 19 days on <30 GPUs (~1.4 GPU-years), ~50× less
  computation, and beats Leela Zero's efficiency by ~10× at equal net size (l.38, l.259).
- The three direct matches all favour KataGo: 239/400, 246/400, 254/400 (Table l.268-270).
- Every ablated component costs measurable Elo; the product of the individual acceleration
  factors is ≈9.1× (l.325), which the author calls an *underestimate* because the ablation
  runs were shorter than the regime where several techniques matter most (l.321, l.325).
- Domain-specific gains are real but partial: ownership+score targets (1.65×) and Go input
  features (1.55×) are the two largest single factors (Table l.337-338), so a purely general
  method still leaves substantial efficiency on the table (l.46, l.323).
- Playout cap randomization beats *every* fixed playout count tried, which is the signature
  predicted if it genuinely relieves the policy/value data tension (l.319).

## Key challenge

The AlphaZero process contains a structural conflict: the game-outcome value target gets
exactly one noisy bit per whole game, so value learning wants many cheap games; the policy
target wants ~800 playouts per move or the search never deviates enough from the prior to
teach the policy anything (l.92-94). Under a fixed compute budget these demands are
directly opposed, and no single fixed visit count satisfies both. Every technique in the
paper is an attack on some version of this data-poverty problem — either by decoupling the
two budgets (playout cap randomization), by decoupling the policy target from the search
dynamics that generate it (target pruning), or by extracting more supervised signal per
game (auxiliary targets).

## Method innovation

- **Playout cap randomization** (l.89-98). On probability `p = 0.25` of turns run a full
  search to a cap of `N` nodes and record it for training; otherwise run a cheap search to
  `n < N` with noise and exploration disabled and record nothing. `(N,n) = (600,100)`
  annealed to `(1000,200)`. Cheap turns are numerous but individually cheap, so game count
  rises sharply while good policy samples per unit compute barely fall. Ablation: 1.37×.
- **Forced playouts + policy target pruning** (l.101-119). Guarantee each root child that
  got any visits at least `n_forced(c) = (k P(c) sum N)^{1/2}` playouts with `k = 2`, by
  setting its selection urgency to infinity; then, before recording the policy target,
  subtract those extra playouts back off (up to the point where PUCT would have chosen them
  anyway) and drop children reduced to one playout. This buys exploration without training
  the policy on the noise that caused it. The general lesson stated at l.119 is the
  decoupling itself, not the specific rule. Ablation: 1.25×.
- **Global pooling** (l.126-148, l.397-412). A pooling layer emits, per channel, the mean,
  the mean scaled by `(b - b_avg)/10`, and the max — `3c` values — which a fully connected
  layer turns into channelwise biases on another tensor. Used in 2-3 trunk residual blocks,
  in the policy head, and (with a `(b-b_avg)^2 - sigma^2` term instead of the max, so score-like
  quantities can scale quadratically with board width) in the value head. Ablation: 1.60×,
  the largest of the general techniques.
- **Auxiliary policy targets** (l.155-162). One extra policy-head channel predicts the
  *opponent's* policy target on the following turn, weighted `w_opp = 0.15`; never used for
  play, purely regularization. Ablation: 1.30×.
- **Ownership + score targets** (l.167-200, l.557-567). The binary game result is a function
  of finer variables: per-point ownership `o(l,p)` (weight `1.5/b^2`) and the final score
  distribution `p_s` (pdf and cdf terms, weight 0.02 each). Mispredicting a region produces
  a gradient localized to that region, which is the stated mechanism for better credit
  assignment (l.198). Generalized heuristic: predict subevents whenever the target
  decomposes into them (l.200). Ablation: 1.65×, the largest single factor.
- **Score utility** (l.683-705). Search maximizes `u_win + u_score` where
  `u_score(x) = c_score * (2/pi) arctan((x - x0)/b)`, `x0` re-centred each search on the net's
  own predicted mean score. Saturation prevents the bot from chasing improbable large score
  swings. `c_score` 0.5 → 0.4. Not separately ablated.
- **Game randomization** (l.644-660). Board size, ko/suicide rules, komi (`N(7,1)`, 5% with
  sd 10), 5% handicap games, exponential-length raw-policy openings, smoothly decaying move
  temperature `T` 0.8→0.2 with halflife `b`, 2.5% position forks and 5% unusual-opening
  forks. Games are played to completion with *no resignation*; instead visits are tapered by
  `lambda = p/0.05` and samples downweighted to `0.1 + 0.9 lambda`, which keeps ownership and
  score targets computable and unbiased (l.660-662).
- **Gating** (l.79, l.667-679). A SWA candidate net enters self-play only after winning
  ≥100/200 games against the incumbent at a 300-node cap (400 after 2 days), with noise,
  forced playouts, handicap, and branching disabled and komi fixed at 7.5.

## Possible bottleneck

For the mission, not for the paper.

- **Paper regime ≠ 9×9 transformer regime.** `[OPEN] boardsize-gap` (from
  `results/ktg/sources/paper_arxiv-1902.10565.md`) — every Elo in the paper is 19×19
  (l.240, l.293) and the training distribution is mixed 9…19 (l.650). No paper number is a
  target for a 9×9-only run. `[OPEN] success-criterion` — **closes when** a 9×9 criterion is
  defined that cites no paper Elo figure.
- **No transformer anywhere in the paper.** `[OPEN] arch-gap` — the trunk described at
  l.414-441 is pre-activation residual CNN with global-pooling blocks. `b5c48h3tfr` is
  `attnrope`+`ffng` blocks with **no gpool block in the trunk** (`modelconfigs.py:999`);
  gpool survives only in the heads. `[HYPOTHESIS] gpool-attn` — the 1.60× global-pooling
  ablation factor (Table l.335) therefore does not transfer, because attention is already
  globally receptive. `[HYPOTHESIS] bavg-dead` — with a single board width, the gpool
  channel scaled by `(b - b_avg)/10` is a constant (`-1.1` at `b=9`, since 14.0 is hard-coded
  in `model_pytorch.py:505`), so the board-size machinery becomes dead weight rather than a
  signal. Neither is measured here.
- **Self-play:train compute ratio.** The paper's main run spends 16-24 GPUs on self-play
  against 1-2 on training — a 4-40× ratio inside a 26-27 GPU pool (l.603). `[HYPOTHESIS]
  ratio-4gpu` — on ≤4 GPUs that ratio cannot be reproduced without either starving the
  trainer or making self-play the whole wall-clock; the loop's cycle time, not its
  correctness, is what ≤4 GPUs threatens. `[OPEN] hparam-scale` (from the acquire
  declaration) — **closes when** scaled-down `maxVisits` / `cheapSearchVisits` /
  `numGamesPerCycle` / batch size are recorded with their derivation or measured on the
  cluster. `[OPEN] cfg-audit` — every thread count must respect the ≤24-CPU cap.
- **Scratch storage.** The paper's run produced 241M samples across 4.2M games (l.603) with
  a sampling window growing to ~22M samples (l.77). `[ASSUMPTION] scratch-only` — mission
  self-play data goes to `/scratch/…/ktg-train/` and is never committed. `[OPEN]
  scratch-budget` — the 9×9 per-sample row size and the 3-day accumulation rate are not yet
  measured, so the window/retention settings for `shuffle.py` (`-min-rows`,
  `-taper-window-scale`) are unset. **Closes when** one cycle's on-disk row count and byte
  size are measured on the cluster.
- **Loop stage most likely to fail first.** `[HYPOTHESIS] export-stage` — the export step is
  the one whose upstream documentation is stale: `SelfplayTraining.md:9` names
  `python/export_model.py`, which does not exist at `v1.18.2`; only
  `python/export_model_pytorch.py` does (`export_model_for_selfplay.sh:77`). A mission script
  copied from the docs fails at the fourth of five stages, after self-play has already
  burned GPU hours.
- **`-pos-len` wiring.** `[OPEN] poslen-wiring` — `python/selfplay/train.sh:88` hard-codes
  `-pos-len 19`. Left unchanged, the score head is sized `S = 19*19+60` (l.512) for a 9×9
  run, wasting most of a 842-wide output and mismatching the data. **Closes when** the
  mission's train invocation is written with `-pos-len 9` and `scorebelief_len = 282`
  observed.
