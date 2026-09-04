# Summary — mission `ktg-train` (code-first)

Stage 1-decompose artifact. Output contract: `pipelines/1-decompose/spec.md` § Output contract.
Markers per `_common/contracts/markers.md`.

**Source of truth = the code mirror** `ref-code/lightvector-KataGo` @ `v1.18.2` (`fd0723fd`);
arXiv:1902.10565 is background. `l.NNN` = line in
`ref-paper/arxiv-1902.10565/src/Accelerating_Self_Play_Learning_In_Go_2020.tex`.
Paths without a `ref-` prefix are inside the code mirror. Mission-regime statements
(9×9-only, `b5c48h3tfr`, ≤4 GPUs, ≤24 CPUs, 3-day wall) not asserted by paper or code
carry a marker.

## Motivation

AlphaZero-class self-play works but is priced out of reach: DeepMind's Go run used 5000
TPUs for several days, ~41 TPU-years (l.33); ELF OpenGo used 2000 V100 GPUs for 13-14 days,
~74 GPU-years (l.33). The paper's premise is that most of that cost is not intrinsic — it
is recoverable through better data balance, richer targets, and global context in the net
(l.44) — and, diagnostically, that measuring the domain-specific share tells us how far
general methods still are from what is possible (l.46).

## Goal

Reach ELF OpenGo's final strength from random initialization, no human data, on ~50× less
computation, with each contributing component individually ablatable (l.38, l.48).

## Result scope

- **Measured.** (1) Elo through training versus a Leela Zero ladder (LZ30…LZ225) and ELF's
  final "V2" net, BayesElo over ~21,000 games (l.232-240). (2) Three 400-game matches versus
  ELF's native engine (l.261, Table l.268-270). (3) Six 2-day ablation runs — `FixedN`,
  `NoForcedTP`, `NoGPool`, `NoPAux`, `NoVAux`, `NoGoFeat` — ~147,000 games (l.282-293).
- **Board sizes.** *Training* mixed: 37.5→50% on 19×19, remainder triangular 9×9…18×18 with
  weights 1…10 (l.650). *All evaluation* 19×19, fixed 7.5 komi, 1600 visits (l.240, l.293).
  No 9×9 result is reported anywhere in the paper.
- **Hardware / time.** 19 days, max 28 V100s (avg 26-27): 16→24 self-play, 2 gating, 1-2
  training (l.81, l.603). 241M samples over 4.2M games across four sizes b6c96 → b20c256
  (Table l.610-613). Ablations ~2 days each (l.282).
- **Cost metric.** Equivalent 20b×256c queries, modelling a `b`-block `c`-channel net as
  `~ b c^2` per query (l.252) — not implemented in the mirror.

## Conclusions

- KataGo surpasses ELF's final model after 19 days on <30 GPUs (~1.4 GPU-years), ~50× less
  computation; ~10× better than Leela Zero at equal net size (l.38, l.259).
- All three direct matches favour KataGo: 239/400, 246/400, 254/400 (Table l.268-270).
- Every ablated component costs Elo; the product of the acceleration factors is ≈9.1×
  (l.325), called an *underestimate* because the runs stopped early (l.321).
- Domain-specific gains are real but partial: ownership+score targets 1.65× and Go input
  features 1.55× are the two largest single factors (Table l.337-338).
- Playout cap randomization beats every fixed playout count tried (l.319).

## Key challenge

The AlphaZero process contains a structural conflict: the game-outcome value target gets
one noisy bit per whole game, so value learning wants many cheap games; the policy target
wants ~800 playouts per move or the search never deviates enough from the prior to teach
the policy anything (l.92-94). Under fixed compute these demands are opposed and no single
visit count satisfies both. Every technique attacks a version of this data-poverty problem
— decoupling the two budgets, decoupling the policy target from the search that generates
it, or extracting more supervised signal per game.

## What the v1.18.2 loop does today

Per pipeline stage, then per surviving paper idea. Every bullet carries a `file:line` anchor.

**Stage 1 — self-play** (`cpp/main.cpp:105` → `MainCmds::selfplay`;
`synchronous_loop.sh:99`; config `cpp/configs/training/selfplay1_maxsize9.cfg`).
- Writes training rows at a **fixed edge length** set by `dataBoardLen`
  (`cpp/command/selfplay.cpp:97`, passed as `dataXLen`/`dataYLen` at `:220`) — `19` in every
  shipped config including the maxsize9 preset (`selfplay1_maxsize9.cfg:16`).
- Board size, rules, komi, handicap, and forks are randomized per game
  (`selfplay1_maxsize9.cfg:89-108`); `allowRectangleProb = 0.50` (`:97`) makes half the games
  non-square — a code behaviour with no paper counterpart.
- **Playout cap randomization** survives verbatim: `cheapSearchProb = 0.75`,
  `cheapSearchVisits = 100`, `cheapSearchTargetWeight = 0.0`, `maxVisits = 600`
  (`selfplay1_maxsize9.cfg:60-62,115`) = paper's `p = 0.25`, `(N,n) = (600,100)` (l.96).
- **Forced playouts** survive: `rootDesiredPerChildVisitsCoeff = 2`
  (`selfplay1_maxsize9.cfg:148`) drives urgency to `1e20` while
  `childWeight < sqrt(policy * total * coeff)` (`cpp/search/searchexplorehelpers.cpp:166-169`)
  = paper's `k = 2`, `n_forced = (k P sum N)^{1/2}` (l.105-106).
- **Policy target pruning** survives as `Search::pruneNoiseWeight`
  (`cpp/search/searchupdatehelpers.cpp:495`, called at `searchresults.cpp:1116,1491,1696`),
  plus `chosenMovePrune = 1` (`selfplay1_maxsize9.cfg:142`) = paper l.108.
- **No resignation in self-play**: visits and sample weight taper instead
  (`reduceVisits*`, `reducedVisitsWeight = 0.1`, `selfplay1_maxsize9.cfg:64-68`) = paper l.660,
  though the code triggers after 3 consecutive turns at winrate 0.9, not 5 turns at 5%.
- **Score utility** survives as `dynamicScoreUtilityFactor = 0.40` with re-centring via
  `dynamicScoreCenterZeroWeight`/`Scale` (`selfplay1_maxsize9.cfg:159-161`) = paper `c_score`,
  `x0 = mu_s_hat` (l.690, l.701).
- Code-only, no paper analogue: `useGraphSearch` (DAG not tree, `:183`),
  `subtreeValueBiasFactor` (`:180`), `policySurpriseDataWeight`/`valueSurpriseDataWeight`
  (`:75-76`), `estimateLeadProb` (`:78`), `sidePositionProb` (`:58`).

**Stage 2 — shuffle** (`python/shuffle.py`; driver `shuffle.sh:42,61,78`; `synchronous_loop.sh:105`).
- The paper's moving-window law `N_window` (l.638) is `compute_desired_num_rows`
  (`python/shuffle.py:414-430`), parameterized by `-min-rows` (paper `c`),
  `-taper-window-exponent` (paper `alpha`), `-expand-window-per-row` (paper `beta`)
  (`shuffle.py:777,780-782`). Upstream advises `alpha` 0.65-0.675 and `beta` 0.4
  (`shuffle.py:733-734`) versus the paper's 0.75 / 0.4 (l.639).
- `-num-processes` (`shuffle.py:791`, required) is the shuffler's CPU knob.

**Stage 3 — train** (`python/train.py`; driver `train.sh:83`; `synchronous_loop.sh:109`).
- `-pos-len` (`train.py:79`, required) fixes the expected row edge length; the shipped driver
  hard-codes `-pos-len 19` (`train.sh:88`).
- **Auxiliary policy target** survives: `loss_policy_opponent_samplewise` weight `0.15`
  (`python/katago/train/metrics_pytorch.py:84-88`) = paper `w_opp = 0.15` (l.555).
- **Ownership + score targets** survive: `loss_ownership_samplewise` weight `1.5` over
  on-board points (`metrics_pytorch.py:146-161`), score-belief pdf and cdf at `0.020` each
  (`:260-273`) = paper `w_o = 1.5/b^2`, `w_spdf` = `w_scdf` = 0.02 (l.559-567).
- Score-mean self-prediction survives with different constants: weight `0.0015`, Huber
  `delta = 12.0` (`metrics_pytorch.py:250-253`) versus paper `w_sbreg = 0.004`, `delta = 10.0`
  (l.570-571). Value loss is `1.20` (`:127`) times `-value-loss-scale` default `0.6`
  (`train.py:146`) versus paper `c_value = 1.5` (l.547).
- **SWA** survives as `-swa-period-samples` / `-swa-scale` (`train.py:95-96`, defaults at
  `:440-443`) = paper's snapshot-EMA candidate generator (l.79).
- Code-only: optimizer choice among adamw/muon/normuon/aurora (`train.py:101-104`),
  transformer attention-logit penalty (`train.py:140-142`), TD-value and seki losses
  (`train.py:147-148`), Q-value targets (`metrics_pytorch.py:90-118`).

**Stage 4 — export** (`python/export_model_pytorch.py`; driver
`export_model_for_selfplay.sh:77`; `synchronous_loop.sh:113`).
- Exports the SWA weights (`-use-swa`, `export_model_pytorch.py:39`, passed by the driver).
- **Refuses to export** when any attention layer's data-free logit bound exceeds
  `-attn-logit-bound-limit`, default `2.5e4` (`export_model_pytorch.py:42`), overridable by
  `-ignore-attn-logit-bound` (`:43`). Transformer-only; no paper counterpart.
- `python/export_model.py` **does not exist** at `v1.18.2`; two upstream docs still name it
  (`SelfplayTraining.md:9`, `python/README.md:13`).

**Stage 5 — gatekeeper** (`cpp/main.cpp:95`; `synchronous_loop.sh:96`; config
`cpp/configs/training/gatekeeper1_maxsize9.cfg`).
- **Gating** survives: `numGamesPerGating = 200` (`gatekeeper1_maxsize9.cfg:20`) and
  `-required-candidate-win-prop` default `0.5` (`cpp/command/gatekeeper.cpp:271`, enforced at
  `:184`) = paper's ≥100/200 (l.669). Noise, forced playouts and cheap searches are simply
  absent from the gate config = paper l.676; resignation is enabled (`:22-24`) = l.678.
- Gate visit cap is `maxVisits = 150` (`:49`) versus the paper's 300→400 (l.669).

**Global pooling** (l.126-148, l.397-412) survives **only in the heads**: `PolicyHead.gpool`
(`model_pytorch.py:2647`) and `ValueHead.gpool` (`:2745`) are unconditional, and
`b5c48h3tfr` sets `gpool_num_channels = 32` (`modelconfigs.py:995`). Paper's `b_avg = 14`
and `sigma^2 = 10` (l.404) are hard-coded as `- 14.0` (`:505,534`) and `- 0.1` (`:540`).

## Paper ideas superseded by the current code

- **Residual-CNN trunk with global-pooling blocks** (l.414-441). `b5c48h3tfr`'s trunk is
  5 × (`attnrope`, `ffng`) transformer blocks (`modelconfigs.py:999`) — no residual conv
  block, no gpool block. Model version 17 introduced transformers (`modelconfigs.py:43`);
  the paper has no attention architecture at all.
- **Progressive net resizing** `(b,c)` = (6,96)→(20,256) (l.71). `$MODELKIND` is a single
  argument (`synchronous_loop.sh:109`); the mission runs one config.
- **19×19 evaluation against ELF / Leela Zero** (l.240, l.293). No opponent pool, no BayesElo
  implementation, and no `~ b c^2` cost metric exist in the mirror.
- **The 27-GPU, 19-day budget** and its hyperparameters (l.603, l.635). The mirror ships no
  such schedule: LR is `-lr-scale`/`-lr-schedule` (`train.py:83-86`), window parameters are
  shuffle flags, and the loop's cycle size is `NUM_GAMES_PER_CYCLE`
  (`synchronous_loop.sh:99`).
- **Fixed komi 7.5 in gating** (l.672). The code uses `komiAuto = True`
  (`gatekeeper1_maxsize9.cfg:42`) — komi is set from the net's own fair estimate.
- **`c_value = 1.5`, `w_sbreg = 0.004`, `delta = 10.0`, root temperature 1.03** (l.547, l.571,
  l.69). Current values are `1.20 × 0.6`, `0.0015`, `12.0`, and `rootPolicyTemperature = 1.1`
  (`metrics_pytorch.py:127,253`, `train.py:146`, `selfplay1_maxsize9.cfg:169`).

## Possible bottleneck

For the mission, not for the paper.

- **Paper regime ≠ 9×9 transformer regime.** `[OPEN] boardsize-gap` — every paper Elo is
  19×19 (l.240, l.293) and its training distribution is mixed 9…19 (l.650). No paper number
  is a target. `[OPEN] success-criterion` — **closes when** a 9×9 criterion is defined citing
  no paper Elo figure.
- **No transformer in the paper.** `[OPEN] arch-gap` — `[HYPOTHESIS] gpool-attn` the 1.60×
  global-pooling ablation factor (Table l.335) does not transfer, because the trunk gpool
  blocks it ablates are absent and attention is already globally receptive.
  `[HYPOTHESIS] bavg-dead` — with one board width, the `(b−14)/10` pool channel is the
  constant `-1.1` and the value-head channel `1.11`, i.e. biases rather than size signals.
- **Two board-size settings must agree.** `dataBoardLen` (`selfplay1_maxsize9.cfg:16`, `19`)
  and `-pos-len` (`train.sh:88`, `19`) both default to 19. `[HYPOTHESIS] shape-mismatch` —
  changing one without the other gives 19×19-shaped rows to a 9×9 trainer or the reverse;
  this is the cheapest way for the mission to burn a full cycle silently.
- **Self-play:train compute ratio.** The paper spends 16-24 GPUs on self-play against 1-2 on
  training (l.603) — 4-40× — inside a 26-27 GPU pool. `[HYPOTHESIS] ratio-4gpu` — on ≤4 GPUs
  that ratio cannot hold without starving the trainer or letting self-play own the wall
  clock. `[OPEN] hparam-scale` — **closes when** scaled `maxVisits` / `cheapSearchVisits` /
  `NUM_GAMES_PER_CYCLE` / batch size are recorded with their derivation or measured.
  `[OPEN] cfg-audit` — `numGameThreads = 128` (`selfplay1_maxsize9.cfg:84`,
  `gatekeeper1_maxsize9.cfg:18`), `-num-processes` (`shuffle.py:791`): ≤24-CPU cap.
- **Export can refuse.** `[OPEN] attn-logit` — `-attn-logit-bound-limit` default `2.5e4`
  (`export_model_pytorch.py:42`) rejects transformer models whose attention logits grow;
  the training-side counter-measure `-attn-logit-penalty-cap` (`train.py:140`) is off by
  default. A rejection lands at stage 4 of 5, after self-play has already spent GPU hours.
  **Closes when** a first `b5c48h3tfr` export succeeds or the penalty is enabled.
- **Stale export path.** `[HYPOTHESIS] export-stage` — a loop script copied from
  `SelfplayTraining.md:9` calls the nonexistent `python/export_model.py`, failing at the
  same late stage.
- **Scratch storage.** The paper's run produced 241M samples over 4.2M games (l.603) with a
  window growing to ~22M samples (l.77). `[ASSUMPTION] scratch-only` — self-play data goes to
  `/scratch/…/ktg-train/`, never committed. `[OPEN] scratch-budget` — the 9×9 per-row byte
  size and the 3-day accumulation rate are unmeasured, so `-min-rows` / `-taper-window-scale`
  / `-keep-target-rows` are unset. **Closes when** one cycle's on-disk row count and byte
  size are measured on the cluster.
