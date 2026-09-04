# derivation.md — arxiv-1902.10565 (Wu, *Accelerating Self-Play Learning in Go*)

Source: `ref-paper/arxiv-1902.10565/src/Accelerating_Self_Play_Learning_In_Go_2020.tex` (713 lines,
2020 revision). The tex carries **no `\label` on any displayed equation**; every equation below is
therefore labelled by its tex line, `eq:lNNN`, and the enclosing `\section`/`\subsection` label is
quoted verbatim. Formulas are reproduced verbatim from the tex. Physical explanation is kept at or
below the paper's own; nothing is added except the **9x9-only / transformer-trunk applicability**
note at the end of each block, which is the mission's contribution and carries markers
(`_common/contracts/markers.md`). Code-side realisation is deferred to
`implementation_plan_{python,cpp,bash}.md`; this file is paper-only.

Regime the paper assumes throughout: residual-CNN trunk, board width `b ∈ [9,19]` mixed within one
run (`l.650`), 19x19 evaluation (`l.238`, `l.293`), ~27 V100 GPUs for 19 days (`l.603`). The mission's
regime is 9x9 only, transformer trunk, ≤4 GPUs. Each block ends with `9x9/transformer:` stating
whether the construct is **unchanged**, **degenerate**, **replaced**, or **not applicable**.

---

## 1. Search — `\label{Overview}` (l.52–86)

### eq:l58 — PUCT selection
```
\text{PUCT}(c) = V(c) + c_{\text{PUCT}} P(c) \frac{ \sqrt{\sum_{c'} N(c')} } { 1 + N(c) }
```
`V(c)` mean predicted utility of `c`'s subtree, `P(c)` policy prior, `N(c)` playouts through `c`,
`c_PUCT = 1.1` (l.59). Footnote l.62: for `N(c)=0`,
`V(c) = V(n) - c_FPU \sqrt{P_explored}`, `P_explored = Σ_{c'|N(c')>0} P(c')`, `c_FPU = 0.2`, except
`c_FPU = 0` at the root when Dirichlet noise is on.
9x9/transformer: **unchanged** — search-side, board-size independent.

### eq:l68 — root Dirichlet noise
```
P(c) = 0.75 P_{\text{raw}}(c) + 0.25 \, \eta
```
`η ~ Dirichlet(α)`, `α = 0.03 · 19² / N`, `N` = number of legal moves (l.69). Root softmax
temperature 1.03 (l.69).
9x9/transformer: **unchanged in form; value shifts** — on an empty 9x9 board `N = 82` so
`α ≈ 0.132`, i.e. the paper's own board-size scaling already handles 9x9. No mission choice needed.

### eq:l74 — base loss (AlphaZero-style)
```
L = - c_{\text{g}} \sum_{r} z(r) \log(\hat{z}(r))  - \sum_{m} \pi(m) \log(\hat{\pi}(m)) + c_{L2} ||\theta||^2
```
`r ∈ {win, loss}`, `c_L2 = 3e-5`, `c_g = 1.5` (l.75). Superseded by the full loss of §7.
9x9/transformer: **unchanged** (subsumed by §7).

### l.78–80 — optimiser and SWA (prose, no equation)
SGD momentum 0.9, batch 256, per-sample lr `6e-5` (`2e-5` for first 5M samples; `6e-6` after
17.5 days) (l.78). Snapshot every ~250,000 samples; every four snapshots an EMA with decay 0.75
produces a candidate net (l.80). Gating: ≥100/200 wins (l.80; detail §11).
9x9/transformer: **replaced by code defaults** — `[OPEN] hparam-scale`: the code at v1.18.2 has its
own optimiser/lr schedule; the paper values are not a target. See `implementation_plan_python.md`.

---

## 2. Playout Cap Randomization — `\label{PlayoutCapRandomization}` (l.89–100)

No displayed equation. Definition (l.97): on a proportion `p` of turns perform a full search to a
cap of `N` nodes; on all other turns a fast search with cap `n < N`. **Only full-search turns are
recorded for training.** Fast searches disable Dirichlet noise and other explorative settings.
Main run: `p = 0.25`, `(N, n) = (600, 100)` annealed to `(1000, 200)` after two days (l.97).
Ablation Table `\label{AblateTable}` (l.331–342): removing it costs 1.37x.
9x9/transformer: **unchanged** — turn-level scheduling, independent of board and trunk.
`[ASSUMPTION]` the mission keeps `p`, `N`, `n` at the code-config defaults; smaller `N` is a
legitimate scale-down lever because 9x9 game trees are shallower (mean game length ~80 vs ~250 moves
at 19x19 — `[HYPOTHESIS]`, to be measured from selfplay SGFs).

---

## 3. Forced Playouts and Policy Target Pruning — `\label{ForcedTPSection}` (l.101–125)

### eq:l105 — forced playouts
```
n_{\text{forced}}(c) = \left( k P(c) \sum_{c'} N(c') \right)^{1/2}
```
Applied to each root child with ≥1 playout; realised by setting `PUCT(c) = ∞` while
`N(c) < n_forced(c)`; `k = 2` (l.106).

### l.109 — policy target pruning (prose rule)
Identify `c* = argmax_c N(c)`; from each other child subtract up to `n_forced` playouts as long as
this does not make `PUCT(c) ≥ PUCT(c*)` holding the *final* utility estimates fixed; children reduced
to a single playout are pruned outright (l.109). The pruned distribution is the policy target `π`.
Ablation: 1.25x (l.335).
9x9/transformer: **unchanged** — root-level search bookkeeping.

---

## 4. Global Pooling — `\label{GlobalPooling}` (l.126–154) and `\subsection{Global Pooling}` (l.397–413)

Global pooling layer on `c` channels outputs `3c` values (l.399–403):
1. mean of each channel;
2. mean of each channel multiplied by `\frac{1}{10}(b - b_{\text{avg}})`;
3. max of each channel;
with `b_avg = 0.5(b_min + b_max) = 0.5(9 + 19) = 14` (l.404). In the value head (3) is replaced by
mean × `\frac{1}{100}((b - b_{\text{avg}})^2 - \sigma^2)`,
`\sigma^2 = \frac{1}{11}\sum_{b'=9}^{19} (b'-b_{\text{avg}})^2` (l.404).
Derived constants (mission arithmetic, exact): `σ² = 110/11 = 10`; at `b = 9`:
`(b−b_avg)/10 = −0.5` and `((b−b_avg)²−σ²)/100 = (25−10)/100 = 0.15`.

Global pooling bias structure (l.131–138, l.406–411): BN+ReLU on `G` → global pool (`3c_G`) →
FC to `c_X` → channelwise add to `X`. Used after the first conv of 2–3 residual blocks and in the
policy head; value head uses the plain pooling layer (l.140, l.457). Ablation: 1.60x (l.336).
9x9/transformer: **degenerate on 9x9, trunk usage replaced.** In a 9x9-only run the two
board-size-scaled channels are constant multiples (−0.5, 0.15) of the mean channel, so they carry no
information beyond a rescaled mean; harmless but redundant (`[SOLID]` by the arithmetic above).
Whether the transformer trunk (`attnrope`/`ffng`) still contains any gpool block, and whether the
heads keep the structure, is code-only — `[OPEN] gpool-in-tf`, resolved in
`implementation_plan_python.md` from `model_pytorch.py`.

---

## 5. Auxiliary Policy Targets — `\label{AuxiliaryPolicyTargets}` (l.155–164)

### eq:l159 — opponent-reply policy loss
```
- w_{\text{opp}} \sum_{m \in \text{moves}} \pi_{\text{opp}}(m) \log(\hat{\pi}_{\text{opp}}(m))
```
`π_opp` = policy target recorded for the *next* turn; `w_opp = 0.15` (l.160). Ablation: 1.30x (l.337).
9x9/transformer: **unchanged** — a head output + loss term; independent of trunk and board.

---

## 6. Auxiliary Ownership and Score Targets — `\label{OwnershipAndScoreTargets}` (l.167–214)

### eq:l184 — ownership loss
```
- w_o \sum_{l \in \text{board}} \sum_{p \in \text{players}} o(l,p) \log \left(\hat{o}(l,p)\right)
```
`o(l,p) ∈ {0, 0.5, 1}`, `w_o = 1.5 / b²`, `b ∈ [9,19]` (l.185). At `b = 9`: `w_o = 1.5/81 ≈ 0.01852`.

### eq:l188 — score belief loss (pdf)
```
- w_{\text{spdf}} \sum_{x \in \text{possible scores}} p_s(x) \log(\hat{p}_s(x))
```
`p_s` one-hot final score difference, `w_spdf = 0.02` (l.189).

### eq:l192 — score belief loss (cdf)
```
w_{\text{scdf}} \sum_{x \in \text{possible scores}} \left( \sum_{y < x} p_s(y) - \hat{p}_s(y) \right)^2
```
`w_scdf = 0.02` (l.193). Ablation (both removed): 1.65x (l.338).
9x9/transformer: **unchanged in form; `w_o` is board-normalised by design**, so the per-board total
ownership weight stays 1.5 at 9x9. The score-bin range is fixed by §8 (`S`), not by `b`.

---

## 7. Loss Function — `\label{LossFunction}` (l.541–600)

The training loss is the **sum** of (weights verbatim):

| eq label | term | weight |
|---|---|---|
| eq:l546 | `c_{\text{value}} \sum_{r \in \{\text{win},\text{loss}\}} z(r) \log(\hat{z}(r))` | `c_value = 1.5` (l.547) |
| eq:l550 | `- \sum_{m \in \text{moves}} \pi(m) \log(\hat{\pi}(m))` | 1 |
| eq:l554 | `- w_{\text{opp}} \sum_{m} \pi_{\text{opp}}(m) \log(\hat{\pi}_{\text{opp}}(m))` | `w_opp = 0.15` (l.555) |
| eq:l558 | `- w_o \sum_{l} \sum_{p} o(l,p) \log(\hat{o}(l,p))` | `w_o = 1.5/b²` (l.559) |
| eq:l562 | `- w_{\text{spdf}} \sum_{x} p_s(x) \log(\hat{p}_s(x))` | `w_spdf = 0.02` (l.563) |
| eq:l566 | `w_{\text{scdf}} \sum_{x} ( \sum_{y<x} p_s(y) - \hat{p}_s(y) )^2` | `w_scdf = 0.02` (l.567) |
| eq:l570 | `- w_{\text{sbreg}} \text{Huber}(\hat{\mu}_s - \mu_s, \delta = 10.0)` | `w_sbreg = 0.004` (l.571) |
| eq:l572 | `\mu_s = \sum_{x} x \hat{p}_s(x)` | (self-prediction target) |
| eq:l578 | `- w_{\text{sbreg}} \text{Huber}(\hat{\sigma}_s - \sigma_s, \delta = 10.0)` | `w_sbreg = 0.004` |
| eq:l580 | `\sigma_s = ( \sum_{x} (x-\mu)^2 \hat{p}_s(x) )^{1/2}` | (self-prediction target) |
| eq:l584 | `w_{\text{scale}} \gamma^2` | `w_scale = 0.0005` (l.585) |
| eq:l588 | `c ||\theta||^2` | `c = 0.00003` (l.589) |

Huber: `f(x) = ½x²` for `|x| ≤ δ`, linear continuation beyond (l.573). The sign convention on
eq:l546 is as printed in the tex (no leading minus); the intent from eq:l74 is a cross-entropy.
A root-value-variance term exists with negligible/zero weight (l.592). Weights were "mostly guesses"
tuned so auxiliary gradients are 10–40 % of the main terms (l.594).
9x9/transformer: **form unchanged; values are not authoritative** — v1.18.2 `metrics.py` weights
differ and are the ones the mission trains with (`[OPEN] loss-weights-code` closes in
`implementation_plan_python.md`). Only `w_o` has an explicit `b` dependence.

---

## 8. Value/score head dimensioning — `\label{NNArchitecture}` (l.455–515)

### eq:l496 — score support
```
s \in \{-S+0.5,-S+1.5,\dots,S-1.5,S-0.5 \}
```
`S = 19·19 + 60 = 421` (footnote l.512) ⇒ `2S = 842` score bins. Score head concatenates
`V_pooled` with `(0.05 s, Parity(s) − 0.5)` (l.499); `\hat{\mu}_s` = 4th value × 20 and
`\hat{\sigma}_s` = softplus(5th) × 20 (l.469–470); ownership = tanh of a 1x1 conv on `V` (l.485).
9x9/transformer: **over-dimensioned but valid** — at 9x9 the reachable |score| ≤ 81 + komi, so most
of the 842 bins are never hit; the paper's own runs also trained 9x9 games against this fixed support
(l.650), so this is within the paper's regime. Whether the code sizes the support from `pos_len` is
`[OPEN] score-bins-poslen` (code-only).

---

## 9. Training Details — `\label{TrainingDetails}` (l.601–643)

### eq:l638 — sliding training window
```
N_{\text{window}} = c \left( 1 + \beta \frac{ ( N_{\text{total}} / c ) ^ \alpha - 1} { \alpha } \right)
```
`c = 250,000`, `α = 0.75`, `β = 0.4` (l.639): the curve `n^α` rescaled so `f(c) = c`, `f'(c) = β`.
Batch 256, per-sample lr `6e-5` (per-batch `256·6e-5`), ÷3 for the first 5M samples per net size,
÷10 for the final net after 17.5 days (l.636). Compute split (l.603): 16→24 V100 self-play,
2 gating, 1 training (+1 for the next size) ⇒ self-play : training GPU ratio **16:1 → 24:1**;
241M samples over 4.2M games ⇒ **≈57 recorded samples per game** at mixed sizes (Table
`\label{TrainSummaryTable}`, l.617).
9x9/transformer: **formula unchanged, constants are mission levers.** `[ASSUMPTION]` the mission
uses the code's `shuffle.py` window (`-taper-window-scale`, `-keep-target-rows`), not these exact
constants; the 16–24:1 GPU ratio is the paper's evidence behind the "4–40×" guidance and is the
central constraint on a ≤4-GPU design (`DESIGN.md` §1).

---

## 10. Game Randomization and Termination — `\label{GameInit}` (l.644–666)

Prose rules (no displayed equations):
- Rules: uniform over positional/situational superko, suicide on/off (l.648).
- **Board size**: 37.5 % → 50 % on 19x19, remainder triangular over 9..18 with weights `1..10` (l.650).
- Komi ~ `N(7, 1)` truncated at 3σ, rounded to half-integers; 5 % of games use σ = 10 (l.652).
- Handicap: 5 % of games; 90 % of those komi-compensated; **max free Black moves is 0 for board
  sizes 9 and 10** (l.654).
- Opening: first `r` moves from the raw policy, `r ~ Exp(mean 0.04·b²)`; move temperature `T` from
  0.8 decaying to 0.2 with half-life `b` turns (l.656).
- Branching: 2.5 % of positions branch to an alternative policy move (70 % T=1, 25 % T=2, else T=∞),
  full search recorded, a quarter continued one more move (l.658).
- Fork games: 5 % of games, `r ~ Exp(mean 0.025·b²)` random opening moves, komi re-fairised (l.660).
- No resignation; if the losing side's MCTS winrate `p < 5 %` for 5 consecutive turns the visit cap
  becomes `λn + (1−λ)N`, `λ = p/0.05`, and samples are recorded with probability `0.1 + 0.9λ` (l.663).
9x9/transformer: **board-size rule replaced; the rest is unchanged with b = 9 plugged in.**
`bSizes = 9`, `bSizeRelProbs = 1` replaces l.650 entirely (`[ASSUMPTION] 9x9-only`, mission scope).
Derived at `b = 9` (exact): mean random-opening length `0.04·81 = 3.24` moves; fork-opening mean
`0.025·81 = 2.025`; temperature half-life 9 turns; **handicap is a no-op on 9x9** (0 free moves,
l.654) so `handicapProb` is irrelevant at 9x9. Komi distribution is board-independent in the paper
(`[OPEN] komi-9x9`: 7 is the 19x19 centre; the code's `komiAuto` may re-centre — code-only).

---

## 11. Gating — `\label{GatingAppendix}` (l.667–682)

Candidate must win **≥ 100 of 200** games vs the current self-play net (l.669). Gating search cap
300 nodes → 400 after 2 days (l.669). Differences from self-play (l.671–679): komi fixed 7.5, rules
and board size still randomised; no handicap/branching; full search from move 1; `T` starts at 0.5;
Dirichlet noise, forced playouts and visit-cap oscillation off, tree reuse on; root `c_FPU = 0.2`;
resignation on (both sides agree `p < 5 %` for 5 turns).
9x9/transformer: **unchanged except board list.** `[ASSUMPTION]` gatekeeper config also gets
`bSizes = 9`. The 100/200 threshold is the paper's only quantitative acceptance criterion and is the
seed of the mission's `eval_improvement` metric. Statistical note (mission): 100/200 at p = 0.5 is
accepted with probability ≈ 0.53, i.e. gating is a weak filter by design (l.669 "fairly lightweight").

---

## 12. Score Maximization — `\label{ScoreMaximization}` (l.683–713)

### eq:l687, eq:l689, eq:l691 — utilities
```
u_{\text{win}}(x) = \text{sign}(x) \in \{-1,1\}
u_{\text{score}}(x) = c_{\text{score}} f\left(\frac{x - x_0}{b}\right)
f(x) = \frac{2}{\pi} \arctan(x)
```
`x` final score difference, `x_0` re-centred each search to the root `\hat{\mu}_s` (l.700),
`b ∈ [9,19]`, `c_score = 0.5 → 0.4` after two days (l.709).

### eq:l702 — expected score utility
```
E(u_{\text{score}}) \approx \int_{-\infty}^{\infty} u_{\text{score}}(x) N(x,\hat{\mu}_s,\hat{\sigma}_s^2) dx
```
evaluated by lookup-table interpolation (l.703).
9x9/transformer: **unchanged in form; `b` in the denominator makes the utility per point 19/9 ≈ 2.1×
steeper at 9x9** — this is the paper's intended board scaling, no mission change.

---

## 13. Paper-only constructs that do NOT transfer (recorded so nobody inherits them)

| construct | anchor | why not |
|---|---|---|
| Residual-CNN trunk: 5x5 stem + `n` pre-activation blocks, 2–3 gpool blocks, BN+ReLU (`\subsection{Trunk}` l.414–441; constants Table `\label{NNConstants}` l.518–534) | l.414 | **replaced** by the v1.18.2 transformer trunk (`b5c48h3tfr`, model version 17) — code-only, `[OPEN] arch-gap` from acquire is discharged by this table plus `implementation_plan_python.md` |
| Inputs: 18 binary spatial + 10 global (Tables l.365–394) | l.361 | **replaced** by the code's V7 feature set (`[OPEN] input-features-v7`, code-only) |
| 19x19 evaluation vs ELF/LZ at 1600 visits, Elo tables (`\label{TestingVersusLeelaZero}`, `\label{AblateTable}`) | l.238, l.331 | **not applicable**: no 19x19 games, no external reference nets on 9x9 — `[OPEN] boardsize-gap` closes only via the mission's own `eval_improvement` criterion |
| Net-size ladder (6,96)→(20,256) (l.72) | l.72 | **not applicable** at ≤4 GPUs; `scale_up` node defines the mission's own second config |
| 27 V100 × 19 days budget (l.603) | l.603 | **not applicable**; only the *ratio* (self-play ≫ training) is carried forward |

## 14. Constructs that transfer unchanged (the paper claims the mission actually inherits)

eq:l58/l62/l68 (search), §2 playout cap randomization, §3 forced playouts + pruning, §5 aux policy,
§6/§7 ownership + score losses (form), §9 window formula (form), §10 rules except board list,
§11 gating rule, §12 score utility. Every one is realised in v1.18.2 C++/Python, so the mission's
evidence for them is **execution of the code path**, not re-derivation; see `claims.md` for the
per-construct claim rows and the evidence type each needs.
