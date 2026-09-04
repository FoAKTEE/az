# References — arXiv:1902.10565 (*Accelerating Self-Play Learning in Go*)

Stage 1-decompose artifact. Output contract: `pipelines/1-decompose/spec.md` § Output contract.
Markers per `_common/contracts/markers.md`.

Citations are transcribed from
`ref-paper/arxiv-1902.10565/src/Accelerating_Self_Play_Learning_In_Go_2020.bbl`
(the `.bib` in the same directory carries six further uncited entries, listed in §3).
`l.NNN` = line in the `.tex`. "Mission need" is for `ktg-train`
(9×9-only transformer-trunk self-play run on the `v1.18.2` mirror).

**Primacy.** The decomposition is code-first: `code_lightvector-KataGo` @ `v1.18.2` is the
source of truth and `paper_arxiv-1902.10565` is secondary background — the paper is cited
for the ideas the current code still implements, not as a specification.

## 1. Primary sources of the mission

| id | source | pin | role |
|---|---|---|---|
| `paper_arxiv-1902.10565` | David J. Wu, *Accelerating Self-Play Learning in Go*, arXiv:1902.10565 (2019; mirrored 2020 revision) | archive sha256 `71a0e894…c8fa6c4e`; mirror `ref-paper/arxiv-1902.10565/` | **Seed.** Defines the loop, the auxiliary targets, and the randomization machinery. Declared in `results/ktg/sources/paper_arxiv-1902.10565.md` |
| `code_lightvector-KataGo` | `lightvector/KataGo`, MIT | tag `v1.18.2`, commit `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4`; mirror `ref-code/lightvector-KataGo/` | **Baseline / implementation.** The only place the transformer trunk exists; runs the five-process loop. Declared in `results/ktg/sources/code_lightvector-KataGo.md` |

## 2. Cited by the paper

Ordered by how directly the mission depends on them.

### 2.1 Needed — the mission reimplements or runs the construct

| key | citation | what the paper takes from it | mission need |
|---|---|---|---|
| `AGZ` | David Silver, Julian Schrittwieser, Karen Simonyan, Ioannis Antonoglou, Aja Huang, Arthur Guez, Thomas Hubert, Lucas Baker, Matthew Lai, Adrian Bolton, et al. *Mastering the game of go without human knowledge.* Nature 550:354–359, 2017. | The self-play-from-random-init loop and the gating test that KataGo's architecture "resembles" (l.54, l.668). | **Yes** — the loop the mission runs (selfplay → shuffle → train → export → gatekeeper) is this loop. |
| `AZ` | David Silver, Thomas Hubert, Julian Schrittwieser, Ioannis Antonoglou, Matthew Lai, Arthur Guez, Marc Lanctot, Laurent Sifre, Dharshan Kumaran, Thore Graepel, et al. *A general reinforcement learning algorithm that masters chess, shogi, and go through selfplay.* Science 362(6419):1140–1144, 2018. | The compute baseline (5000 TPUs, ~41 TPU-years, l.33), the 800-playouts-per-move setting (l.94), Dirichlet root noise `alpha = 0.03` at 19×19 (l.69), and the PUCT/temperature scheme every technique in the paper modifies. | **Yes** — the PUCT formula (l.58) and root-noise scaling are the search the mission runs. |
| `IDMapRes` | Kaiming He, Xiangyu Zhang, Shaoqing Ren, and Jian Sun. *Identity mappings in deep residual networks.* ECCV, pages 630–645, Springer, 2016. | The pre-activation residual block used for the whole trunk (l.71, l.419-428). | **Partial** — `[HYPOTHESIS] preact-tf` the mission's `b5c48h3tfr` trunk is `attnrope`/`ffng` blocks (`modelconfigs.py:999`), not pre-activation ResNet blocks; the pre-activation convention survives only in the heads. |
| `SE` | Jie Hu, Li Shen, Samuel Albanie, Gang Sun, and Enhua Wu. *Squeeze-and-excitation networks.* CVPR, pages 7132–7141, 2018. | Independent confirmation that channel-wise global context helps; the acknowledged relative of KataGo's global pooling (l.44, l.152). | **Partial** — global pooling survives in the policy and value heads (`model_pytorch.py:2647`, `:2745`) but not in the transformer trunk. |
| `Darkforest` | Yuandong Tian and Yan Zhu. *Better computer go player with neural network and long-term prediction.* ICLR, 2016. | The auxiliary future-action policy target revived as `pi_opp` with `w_opp = 0.15` (l.156-160). | **Yes** — the target is in the mirror's loss (`metrics_pytorch.py:88`). |
| `MLVGo` | Ti-Rong Wu, I-Chen Wu, Guan-Wun Chen, Ting-han Wei, Tung-Yi Lai, Hung-Chun Wu, and Li-Cheng Lan. *Multi-labelled value networks for computer go.* IEEE Transactions on Games 10(4):378–389, 2018. | Prior art for ownership/score auxiliary targets, in supervised rather than self-play settings (l.46, l.168). | **Yes** — ownership and score-belief heads are active in every `tf` config. |
| `SWA` | Pavel Izmailov, Dmitrii Podoprikhin, Timur Garipov, Dmitry Vetrov, and Andrew Gordon Wilson. *Averaging weights leads to wider optima and better generalization.* UAI, 2018. | The snapshot-EMA scheme producing gating candidates (l.79). | **Yes** — `-swa-period-samples` / `-swa-scale` in `python/train.py:95-96`. |
| `TrompTaylor` | John Tromp. *The game of go*, 2014. http://tromp.github.io/go.html | The self-play ruleset, modified for pass-alive territory (l.81). | **Yes** — the rules the selfplay engine plays under. |
| `Benson` | David Benson. *Life in the game of go.* Information Sciences, 10:17–29, 1976. | Pass-alive proof enabling the end-of-game optimization and the pass-alive input planes (l.84, l.216). | **Yes** — pass-alive planes are part of the V7 input features the mirror computes. |
| `OptimalVisits` | Henrik Forsten. *Optimal amount of visits per move*, 2019. Leela Zero issue #1416. | The empirical claim that policy learning wants ~800 visits while value learning wants fewer — the tension playout cap randomization resolves (l.94). | **Yes** — the motivation for `cheapSearchProb` / `cheapSearchVisits`, which the mission must retune for 9×9 (`[OPEN] visit-caps-9x9` in `convention.md`). |
| `SAI` | Francesco Morandin, Gianluca Amato, Marco Fantozzi, Rosa Gini, Carlo Metta, and Maurizio Parton. *Sai: a sensible artificial intelligence that plays with handicap and targets high scores in 9x9 go (extended version)*, 2019. arXiv:1905.10863. | The root softmax temperature of 1.03 for policy convergence stability (l.69). | **Partial** — the mirror ships `rootPolicyTemperature = 1.1` instead (`selfplay1.cfg:169`). Note this is the one cited work whose own experiments are **9×9**; `[FUTURE] sai-9x9` it is the closest published 9×9 self-play regime to the mission's. |

### 2.2 Comparison-only — cited for baselines the mission does not reproduce

| key | citation | what the paper takes from it | mission need |
|---|---|---|---|
| `FB2` | Yuandong Tian, Jerry Ma, Qucheng Gong, Shubho Sengupta, Zhuoyuan Chen, James Pinkerton, and C. Lawrence Zitnick. *Elf opengo: An analysis and open reimplementation of alphazero.* ICML, 2019. | The 2000-GPU / ~74 GPU-year baseline and the opponent for the 50× claim (l.33, l.259, Table l.268-270). | **No** — 19×19 strength baseline; `[OPEN] boardsize-gap` makes it untransferable. |
| `LeelaZero` | Gian-Carlo Pascutto et al., 2019. Leela Zero project, https://zero.sjeng.org/ | Progressive net-size growth (l.71), the `V(c)` first-play-urgency convention (l.62), and the Elo ladder for Figure `PlotVsLZ` (l.232, l.259). | **Partial** — the FPU convention is implemented (`fpuReductionMax`); the Elo comparison is not reproducible at 9×9. |
| `AG` | David Silver, Aja Huang, Chris J. Maddison, Arthur Guez, Laurent Sifre, George van den Driessche, Julian Schrittwieser, Ioannis Antonoglou, Veda Panneershelvam, Marc Lanctot, et al. *Mastering the game of go with deep neural networks and tree search.* Nature 529:484–489, 2016. | Evidence that 1-playout self-play still trains a usable value net — motivating cheap searches (l.92). | **No** — motivation only. |
| `BayesElo` | Remi Coulom. *Bayesian elo rating*, 2010. https://www.remi-coulom.fr/Bayesian-Elo/ | The rating system behind every Elo number in the paper (l.237). | **No** — `[OPEN] success-criterion`; needed only if the mission defines an Elo-based 9×9 criterion. |
| `LCB` | Jonathan Roy. *Fresh max_lcb_root experiments*, 2019. Leela Zero issue #2282. | Lower-confidence-bound move selection used in the evaluation matches (l.240). | **Partial** — the mirror enables it in training too (`useLcbForSelection = true`, `selfplay1.cfg:151`), so it is on by default in the mission's runs. |
| `LeelaChessZero` | Gary Linscott et al., 2019. https://lczero.org/ | Evidence that Squeeze-Excite-like structures are in use in AlphaZero-family projects (l.152). | **No.** |
| `MiniGo` | Tom Madams, Andrew Jackson, et al., 2019. https://github.com/tensorflow/minigo/ | Same as `LeelaChessZero` (l.152). | **No.** |

### 2.3 Background — no construct the mission executes

| key | citation | what the paper takes from it | mission need |
|---|---|---|---|
| `ClarkStorkey` | Christopher Clark and Amos Storkey. *Training deep convolutional neural networks to play go.* ICML, pages 1766–1774, 2015. | Prior art for hand-designed Go input features (l.216). | **No** — but the V7 feature planes the mirror computes descend from this line of work. |
| `Cazenave` | Tristan Cazenave. *Residual networks for computer go.* IEEE Transactions on Games 10(1):107–110, 2017. | Same (l.216). | **No.** |
| `DeepGoConv` | Chris Maddison, Aja Huang, Ilya Sutskever, and David Silver. *Move evaluation in go using deep convolutional neural networks.* ICLR, 2015. | Same (l.216). | **No.** |
| `MultiSurvey` | Yu Zhang and Qiang Yang. *A survey on multi-task learning*, 2017. arXiv:1707.08114. | Framing for the "predict subcomponents of the target" heuristic (l.200). | **No.** |
| `MultiNLP` | Joachim Bingel and Anders Søgaard. *Identifying beneficial task relations for multi-task learning in deep neural networks.* EACL, 2017. | Same (l.200). | **No.** |

## 3. In the `.bib` but never cited in the `.tex`

`FB` (Facebook ELF OpenGo blog post), `LCZSE` (Leela Chess Zero technical wiki), `MiniGoSE`
(MiniGo squeeze-and-excite issue), `MiniGoInitLoss` (MiniGo RESULTS.md), `SAIPolicyTemp`
(SAI self-play temperature issue), `GatherExcite` (Hu et al., *Gather-Excite*, NeurIPS 2018).
Verified by comparing `grep -o '\cite{...}'` over the `.tex` (23 distinct keys) against the
29 entries in the `.bib`; the `.bbl` contains exactly the 23 cited keys. None is needed.

## 4. Sources the mission needs that the paper does **not** cite

- **Transformer trunk.** `[OPEN] arch-ref` — the paper contains no attention architecture
  (`results/ktg/sources/paper_arxiv-1902.10565.md`, `[OPEN] arch-gap`). The mission's
  `attnrope` / `ffng` blocks (`modelconfigs.py:999`, `model_pytorch.py:2966`, `:2971`) have
  no citation anywhere in the mirror either. **Closes when** the rotary-embedding /
  transformer-block references are located in the mirror's own docs or declared absent, so
  the design stage does not inherit an uncited construct.
- **9×9 self-play regime.** `[FUTURE] sai-9x9` — `SAI` (§2.1) is the only cited work that
  reports 9×9 self-play; it is not a mission dependency, but it is the only published
  anchor for what 9×9 self-play behaves like.
