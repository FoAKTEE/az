# Value-loss drift: escalation memo, written before the 0.62 flag is crossed

Mission `ktg-train`, node namespace `arxiv-1902.10565` (label only; the 2019 paper is not a
target). Production chain link 2, job 305318, read 13 (2026-09-06T09:45 EDT). Memo written
2026-09-06 09:50-10:25 EDT by the brain role from read-only inputs. **No ledger row was
appended: the brain role cannot append (kernel section 6), and every `[SOLID]` claim below carries
a `verify:` a worker or validator can execute to admit it.** Nothing under `runs/p1`, no knob
file and no loop code was touched; no job was launched.

Code citations are to the mirror `ref-code/lightvector-KataGo` at v1.18.2
(`fd0723fdbc0e9d82cf269c9630af8c27c57c07c4`). Inputs and their state when read:

| input | state |
|---|---|
| `runs/p1/train/t9/metrics_train.json` | first 1809 rows, last `nsamp` 27 024 256, read 09:48 EDT; the file is append-only, `head -n 1809 \| sha256sum` = `4cf09c954af82ad561b3472d694dbe3c60d120030bbbcdac3d54e960814d8f4e` |
| `evidence/production_chain/status_log.txt` reads 9-13 | sha256 `7db24efcada84c2dfeed5534b72c7053a5291bff8a8af48e53173ee6ec77ccbb` |
| `codes/loop/knobs_9x9.env` | sha256 `78121713b305630980fca3b1476098540f7eda8ed5f722083e5b93d5545a5dc0` (the option-C file link 2 runs under a different sha, `ba7f1bf7e1bc166d`, read 9 (3)) |
| `runs/p1/selfplay/t9-*/sgfs/*.sgfs` | 36 generations still on disk, `t9-s15847040` .. `t9-s26913152`, 152 903 games |
| `runtime/games_viewer/p1/**/games.json` | viewer snapshots, 274 240 distinct games over 76 nets incl. the 52 generations pruned at the link-1 -> link-2 boundary |
| `runs/p1/models`, `rejectedmodels` | 87 accepted + 3 rejected = 90 exports |
| `logs/loop-305318.log` | lines 23-71 (boundary prune), 656 (boundary shuffle window) |

---

## 0. The answer to question 1, in one paragraph

A rising training value loss under an improving policy and a gate that keeps accepting is the
expected regime here, and the 0.62 flag is measuring the wrong quantity. `vloss` is
`1.2 x` the raw three-way cross-entropy of the value head against the **final game outcome**
(`metrics_pytorch.py:121-127`; target built with `nowFactor 0.0` at `trainingwrite.cpp:573`, so
the target is the result itself, with a draw encoded as `(0.5, 0.5, 0)` by `play.cpp:2000-2002`
under `drawEquivalentWinsForWhite = 0.5`, `selfplay_9x9.cfg:175`). Unlike the TD value losses,
which subtract the target's own entropy (`metrics_pytorch.py:135`), `vloss` carries the
irreducible entropy of the outcome distribution, so it is **not comparable across data
distributions**: every position of a drawn game costs at least `1.2 ln 2 = 0.832` however good
the head is. The games have hardened exactly as this predicts: the share of drawn games in the
training window rose 0.037 -> 0.070 across link 1 and 0.083 -> 0.114 across link 2, the share
of games decided by <= 2.5 points rose 0.128 -> 0.43, and across the 29 link-2 exports `vloss`
tracks the window's draw share with `r = 0.835` and slope `0.321 per unit draw share`
(`R^2 = 0.70`), which alone reproduces the whole link-2 rise (predicted +0.010, observed
+0.0106 from `t9-s19720960` to `t9-s26913152`). Every signal that IS distribution-invariant is
flat or improving: the three entropy-corrected TD value losses are `0.1466 / 0.1007 / 0.0855` at
9-12 M samples and `0.1465 / 0.1009 / 0.0858` at >= 24 M; the 600-visit search's own
cross-entropy against the outcome on each net's games is `0.432 +- 0.006` over 28 link-2 nets
with no correlation to `vloss` (`r = 0.10`); ownership and score losses fell (0.478 -> 0.462,
0.375 -> 0.359). Two further facts close the over-fit reading: over-fitting lowers a
**training** loss, and what was observed is a **rising** training loss with no held-out
number anywhere (`SKIP_VALIDATE=1`, `synchronous_loop_9x9.sh:506`, so `metrics_val.json` is 0
bytes); and the stale-window mechanism named in the knob derivation was tested by option C,
which halved the applied reuse from 7.2 to 3.9 at the link boundary, after which `vloss` did
not fall (0.5997 at read 8 -> 0.5970 at read 9 -> 0.6085 at read 13). What the reads did
not see is that the single largest deterioration of the run, `vloss 0.6002 -> 0.6146` inside
1.3 epochs at 17.94-18.09 M samples, was caused by the link boundary itself: startup retention
deleted 52 generations and the shuffle window collapsed from 421 842 to 109 442 rows. That
artefact recurs at every link boundary under `KTG_KEEP_SELFPLAY_GENERATIONS=3`, the next one is
at 17:53 EDT today, and `0.6074 + 0.0144 = 0.622` is the most likely way the 0.62 flag gets
crossed tonight -- by the loop, not by the trainer.

## 0.1 The one recommendation

**Do not change the trainer, the net, the gate or the data knobs at link 3.** Before 17:53
EDT today: (i) retire the raw-`vloss` 0.62 flag and replace it with the distribution-invariant
pair in section 6.2; (ii) stop the boundary window collapse with one line,
`codes/data_budget/budget.env:55` `KTG_KEEP_SELFPLAY_GENERATIONS=3 -> 60`; (iii) authorise the
400-game transitive match that DESIGN section 7 already specifies (c14) but that has never been
run on 9x9: latest accepted vs `t9-s20919936` (the policy-loss best) and vs the frozen first
net, one GPU, well inside the cap. The LR anneal (option b) is **pre-registered as the next
move at link 4, applied only if** the match gives the latest net p <= 0.55 against
`t9-s20919936`. Section 6 gives the exact edits and what each would falsify.

---

## 1. What the number is (code, not opinion)

- `vloss` = `1.20 * global_weight * weight * CE(pred_logits, target_probs)` summed over the
  batch and divided by the summed weights: `metrics_pytorch.py:121-127` (`loss_value_samplewise`),
  keyed `"vloss_sum"` at `:901`. The 1.2 factor is inside the logged number:
  `vloss / 1.2` is the mean CE in nats. The flag `0.62` is therefore `0.517` nats.
- The target is the final result. `trainingwrite.cpp:573` calls `fillValueTDTargets(..., nowFactor = 0.0, rowGlobal)`;
  with `nowFactor 0` every weight but the last is zero (`:411-435`), so `rowGlobal[0..2]` is the
  game's terminal `(win, loss, noResult)` flipped to the player to move. At game end
  `play.cpp:2000-2002` sets `win = whiteWinsOfWinner(winner, drawEquivalentWinsForWhite)`,
  `loss = 1 - win`, `noResult = 0`; `selfplay_9x9.cfg:175` has `drawEquivalentWinsForWhite = 0.5`,
  so a **drawn game's target is (0.5, 0.5, 0) at every position**, floor `ln 2 = 0.693` nats.
- The TD value losses subtract the target entropy: `metrics_pytorch.py:135`
  `cross_entropy(pred, target) - cross_entropy(log target, target)`; they are excess CE against
  the search's own soft values over three horizons (`trainingwrite.cpp:578-580`,
  `1/(1 + 81 * {0.176, 0.056, 0.016})` on 9x9) and are comparable across distributions.
- The logged values are exponential moving averages over training batches,
  `accumulate_metrics(..., decay=0.999, new_weight=1.0)` at `train.py:1658`, i.e. a ~1000-batch
  (~128 000-sample, about one cycle) memory (`metrics_logging.py:10-25`). They are computed on the
  rows the trainer draws, i.e. `SHUFFLE_KEEPROWS = 120 000` rows sampled each cycle from the
  shuffle window (section 3.5), never on held-out rows.
- The `loss` metric (35.04 at the last row) is the weighted sum of every head
  (`metrics_pytorch.py:856-920`); it is dominated by the policy terms and says nothing on its
  own about the value head.
- `vsquare` (`metrics_pytorch.py:331-332`) is the mean squared `P(win) - P(loss)` of the
  head's own prediction, a decisiveness measure independent of the target.
- There is no held-out set: `synchronous_loop_9x9.sh:506` runs `SKIP_VALIDATE=1 ./shuffle.sh`,
  the branch of `shuffle.sh:36-54` that writes only `train/`; the validation branch
  (`shuffle.sh:58-95`) would peel 5 % of the selfplay files by md5 and `train.py:1785-1825`
  would evaluate them at each epoch end into `metrics_val.json`, which is 0 bytes.

## 2. Provenance of the 0.62 flag

The flag was set at monitoring read 5 (`status_log.txt:1528`, 2026-09-05T05:45), by the
monitoring worker, in these words (`status_log.txt:1889-1894`):

> It is the classic signature of the value head beginning to overfit the current window while
> the policy continues to gain. Recorded as a measured fact; it is not a section-11 condition
> and nothing was touched. Worth a line every read, and worth the validator's attention if
> vloss passes ~0.62 while p0loss is still falling.

"~0.62" was a round number 0.02 above the value then observed (0.5928 at `t9-s6257664`). It
appears nowhere in `decomposition/DESIGN.md` (`grep -c '0\.62'` = 0), in
`codes/eval/chain_status.sh` (the section-11 escalate table, which lists breaker / storage /
link-failure signals only) or in `derive_cycle_knobs/derivation.md`. It was carried forward by
reads 8-13 as "the 0.62 flag" and acquired its status by repetition. The over-fit attribution
in the same paragraph is a `[HYPOTHESIS]` that was never tested, and section 3 shows it is
inconsistent with the evidence. `[SOLID]` verify: `grep -n 'vloss passes ~0.62'
evidence/production_chain/status_log.txt` -> `1893`; `grep -c '0\.62' decomposition/DESIGN.md
codes/eval/chain_status.sh` -> `0` and `0`.

## 3. Evidence

### 3.1 Per-export trajectory with the outcome distribution of the training window

`vloss`, `p0loss`, `pacc1`, `tdvloss1` are the last `metrics_train.json` row with
`nsamp <= export samples` (this differs by <= 0.002 from the per-export numbers of record in
`status_log.txt`, which are the numbers to cite; the table is for covariate alignment).
`draw`, `close`, `moves` are game-count-weighted over the **five accepted nets before the
export**, which is what the ~13-cycle shuffle window holds (section 3.5); from the viewer
snapshots. `search CE` is the training-weight-weighted cross-entropy of the search's own
root value (the per-move `win loss noResult` comment the selfplay writer emits,
`sgf.cpp:2153-2171`, white-relative) against the final outcome, on that net's own games, draws
scored as `-(0.5 ln w + 0.5 ln l)`, values clipped at 0.005 (two-decimal printing).

| export | samples | vloss | p0loss | pacc1 | tdvloss1 | draw | close<=2.5 | moves | search CE |
|---|---|---|---|---|---|---|---|---|---|
| t9-s1762560 (vloss low) | 1 762 560 | 0.5691 | 2.7345 | 0.3619 | 0.0623 | 0.037 | 0.128 | 99.6 | - |
| t9-s6257664 (read 5) | 6 257 664 | 0.5928 | 1.8457 | 0.4557 | 0.1350 | 0.051 | 0.349 | 79.5 | - |
| t9-s9254144 | 9 254 144 | 0.6011 | 1.6918 | 0.4840 | 0.1451 | 0.070 | 0.392 | 73.8 | - |
| t9-s11651712 | 11 651 712 | 0.6003 | 1.6223 | 0.5072 | 0.1450 | 0.079 | 0.410 | 74.4 | - |
| t9-s13150080 | 13 150 080 | 0.6026 | 1.6108 | 0.5075 | 0.1488 | 0.072 | 0.436 | 73.5 | - |
| t9-s15847040 | 15 847 040 | 0.6012 | 1.5417 | 0.5308 | 0.1469 | - | - | - | 0.431 |
| t9-s17945216 (link-1 end) | 17 945 216 | 0.6002 | 1.5289 | 0.5340 | 0.1448 | 0.087 | 0.425 | 74.0 | 0.424 |
| t9-s18225024 (first of link 2) | 18 225 024 | 0.6069 | 1.5720 | 0.5137 | 0.1540 | 0.085 | 0.426 | 74.0 | 0.430 |
| t9-s18522368 | 18 522 368 | 0.5930 | 1.5501 | 0.5222 | 0.1467 | 0.083 | 0.422 | 74.1 | 0.431 |
| t9-s19720960 (read 9) | 19 720 960 | 0.5968 | 1.5354 | 0.5289 | 0.1463 | 0.083 | 0.417 | 74.3 | 0.436 |
| t9-s20919936 (p0loss best) | 20 919 936 | 0.6004 | 1.4848 | 0.5450 | 0.1468 | 0.095 | 0.424 | 73.3 | 0.428 |
| t9-s22418432 (p0loss peak) | 22 418 432 | 0.5974 | 1.5366 | 0.5283 | 0.1454 | 0.085 | 0.428 | 73.4 | 0.419 |
| t9-s23316992 | 23 316 992 | 0.5944 | 1.5285 | 0.5295 | 0.1483 | 0.082 | 0.424 | 73.6 | 0.441 |
| t9-s24215808 | 24 215 808 | 0.6054 | 1.4948 | 0.5422 | 0.1472 | 0.094 | 0.426 | 73.4 | 0.440 |
| t9-s24515584 | 24 515 584 | 0.6071 | 1.4890 | 0.5441 | 0.1467 | 0.102 | 0.426 | 73.1 | 0.433 |
| t9-s24815616 (closest approach) | 24 815 616 | 0.6026 | 1.4863 | 0.5439 | 0.1435 | 0.107 | 0.431 | 72.8 | 0.430 |
| t9-s25114880 | 25 114 880 | 0.6031 | 1.4878 | 0.5432 | 0.1452 | 0.109 | 0.431 | 72.6 | 0.437 |
| t9-s25714304 | 25 714 304 | 0.6040 | 1.5000 | 0.5386 | 0.1471 | 0.114 | 0.425 | 72.6 | 0.439 |
| t9-s26014080 (REJECTED 96.5-100.5) | 26 014 080 | 0.6073 | 1.5032 | 0.5365 | 0.1475 | 0.111 | 0.427 | 73.0 | - |
| t9-s26313728 | 26 313 728 | 0.6074 | 1.4932 | 0.5407 | 0.1480 | 0.111 | 0.427 | 73.0 | 0.433 |
| t9-s26613120 | 26 613 120 | 0.6059 | 1.4939 | 0.5409 | 0.1463 | 0.107 | 0.422 | 73.4 | 0.437 |
| t9-s26913152 (read 13) | 26 913 152 | 0.6074 | 1.4944 | 0.5402 | 0.1470 | 0.106 | 0.423 | 73.5 | 0.427 |

Whole-run reference points (viewer snapshots): the random net's games averaged 118.7 moves,
draw rate 0.005, mean |margin| 39.2; `t9-s143744` 130.8 moves, `t9-s1762560` 78.7 moves /
draw 0.027 / |margin| 9.8 / close 0.234; every net from `t9-s7156736` on sits at 72-75 moves,
draw 0.07-0.12, |margin| 7.8-9.2, close 0.38-0.44. Black wins 0.40-0.49, White 0.42-0.52 of
selfplay games on every net from `t9-s1166208` on (komi auto, mean 6-7): no side bias. Resignations: 0.000 on all 36
generations on disk (`allowResignation = true` at `-0.90` for 5 turns, `selfplay_9x9.cfg:34-36`,
never fires on 9x9 at this strength), so every game is played out and every endgame position is
in the data.

### 3.2 Decomposition of the rise by the outcome distribution

Draw floor. With `f_d` the training-weight share of positions from drawn games, the head cannot
go below `1.2 * ln 2 * f_d = 0.832 f_d`. On the 36 generations on disk `f_d` runs
`0.075 (t9-s17945216) -> 0.115 (t9-s24215808) -> 0.088 (t9-s26913152)`, i.e. the floor moved
between 0.062 and 0.096. The search's own CE on drawn-game positions is 0.79-0.82 (it assigns
about 0.45/0.55 in games that end level), on non-draw positions 0.385-0.404.

Regression of `vloss` at export on the window covariates of table 3.1 (ordinary least squares;
`n` = exports with a 5-net window; code in section 8):

| sample | model | R^2 | slope(s) |
|---|---|---|---|
| all exports after the low (n = 76) | `vloss ~ draw + close` | 0.756 | 0.170 per unit draw, 0.060 per unit close |
| link 1 after the low (n = 46) | `vloss ~ draw + close` | 0.773 | 0.248, 0.051 |
| link 2 (n = 29) | `vloss ~ draw` | 0.697 | **0.321** (`r = 0.835`) |
| link 2 | `vloss ~ close` | 0.102 | (close share is flat in link 2) |
| link 2 | `vloss ~ moves` | 0.358 | -0.0047 per move |

Arithmetic cross-check of the link-2 slope: if the head's CE on drawn positions is at the
search's 0.80 and its CE on the rest is `(0.6074/1.2 - 0.106 * 0.80) / 0.894 = 0.47`, the
expected slope is `1.2 * (0.80 - 0.47) = 0.40` per unit draw share; the fitted 0.32 is the same
order. Link 2's rise: window draw share `0.083 -> 0.114` (`t9-s19720960 -> t9-s25714304`) times
0.321 = **+0.010 predicted, +0.0106 observed** (`0.5968 -> 0.6074`). Link 1's rise from the low,
`0.5691 -> 0.6011` (+0.032), is 68 % reproduced by draw (+0.033 share) and close (+0.264
share) at the link-1 coefficients (+0.0218); the residual +0.010 is `[OPEN]` (candidate
covariates: the handicap / fork / komi-variation mix, 10 % `handicapProb`, 4 % forks; a worker
should extend the regression to the gtype and komi fields already in `games.json`).

`[PRELIMINARY]` (the derivation lives in scratch and has not been admitted): the link-2 value-loss
rise is accounted for by the draw share of the training window. `verify:` re-run section 8's
scripts against `runtime/games_viewer/p1/**/games.json` and `metrics_train.json` and admit the
per-net table as a knowledge row.

### 3.3 The fit-quality signals that do not depend on the target distribution

| signal | 9-12 M samples | >= 24 M samples | reads as |
|---|---|---|---|
| `tdvloss1` (excess CE, ~6-turn horizon) | 0.1466 | 0.1465 | flat |
| `tdvloss2` (~16-turn) | 0.1007 | 0.1009 | flat |
| `tdvloss3` (~50-turn) | 0.0855 | 0.0858 | flat |
| `vsquare` (own decisiveness) | 0.3241 | 0.3200 | flat (slightly less decisive, consistent with more level games) |
| `oloss` (ownership) | 0.4783 | 0.4618 | improving |
| `sloss` (final scoring) | 0.3745 | 0.3590 | improving |
| search CE vs outcome, own games (28 link-2 nets) | - | mean 0.4321, sd 0.0056, min 0.419, max 0.442 | flat; `r(search CE, vloss) = 0.10` |

The search reference deserves one more line. The net's CE is `vloss / 1.2`: 0.4973 at
`t9-s19720960`, 0.5062 at `t9-s26913152` (+0.009 nats). The 600-visit search on the same nets'
games moved 0.436 -> 0.427. The draw-share change over that span, +0.023, predicts
`0.023 * (0.80 - 0.47) = +0.0076` nats of the net's +0.009; the unexplained residual, ~0.002
nats, is below the export-to-export scatter of `vloss` (rmse 0.0022 around the link-2 fit).
`[SOLID]` verify (tdvloss flatness): `python3 - <<'EOF'` over `metrics_train.json` computing the
means of `tdvloss1..3` for rows with `9e6 <= nsamp < 12e6` and `nsamp >= 24e6` reproduces the
table to 4 decimals.

### 3.4 The reuse hypothesis was tested by option C and did not move `vloss`

`derive_cycle_knobs/derivation.md:587` names link 1's applied reuse `rho = KEEPROWS/(G r) = 6.99-7.22`
as "the measured mechanism behind the value-loss drift". Option C (human decision 2026-09-05,
`mission.json decisions[-1]`) took `rho` to 3.93 at the link-1 -> link-2 boundary
(`status_log.txt` read 9 (2): "rho at the knob link 2 is running, G=1800 ... 3.928 (cap 8)").
`vloss` of record: read 8 `0.599702` (before), read 9 `0.596950`, read 10 `0.600090`, read 11
`0.594310`, read 12 `0.602601`, read 13 `0.608482`. A halving of the reuse produced no
downward step; the subsequent movement is the draw-share tracking of section 3.2.
`[PRELIMINARY]` reuse is not the driver of the drift; the confound is the boundary transient of
section 3.5, which was in flight at read 9. `verify:` the six numbers above are verbatim from
`status_log.txt` reads 8-13 sections "VALUE LOSS".

### 3.5 The link boundary collapses the data window, and that is what will cross 0.62 tonight

Measured from `metrics_train.json` (`window_end_batch - window_start_batch` is the shuffle's
`datainfo["range"]`, `train.py:1241-1242`) and `logs/loop-305318.log`:

| nsamp | window rows | vloss | p0loss | pacc1 | tdvloss1 |
|---|---|---|---|---|---|
| 17 936 256 (last of link 1) | 421 842 | 0.6002 | 1.5289 | 0.5340 | 0.1448 |
| 17 958 016 (first of link 2) | 238 185 | 0.6036 | 1.5374 | 0.5308 | 0.1474 |
| 17 970 816 | 109 660 | 0.6058 | 1.5469 | 0.5261 | 0.1494 |
| 18 092 928 (peak) | 112 660 | **0.6146** | 1.5748 | 0.5126 | 0.1570 |
| 18 513 536 (undershoot) | 129 309 | **0.5930** | 1.5501 | 0.5222 | 0.1467 |
| 20 072 064 | 193 472 | 0.5989 | 1.5183 | 0.5343 | 0.1460 |
| 27 024 256 (now) | 398 606 | 0.6073 | 1.4925 | 0.5409 | 0.1465 |

Mechanism. `loop.sbatch:876` runs `prune_retention.py --basedir $BASEDIR --apply` once at link
start; with `codes/data_budget/budget.env:55` `KTG_KEEP_SELFPLAY_GENERATIONS=3` it removed 52
selfplay generations (`loop-305318.log:23-71`, "keep newest 3 generations, and only delete
generations older than the oldest retained shuffle window"), leaving 351 470 rows on disk. The
shuffle sizes its window from the rows **on disk**: `shuffle.py:414-435`
`compute_desired_num_rows(num_usable_rows, min_rows, ...)` with `expand_window_per_row 0.4`,
`taper_window_exponent 0.65` (`shuffle.sh:41-42`) and our `TAPER_WINDOW_SCALE 50000`,
`SHUFFLE_MINROWS 25000`; at 2.9 M rows that is ~420 000 rows, at 351 470 rows it is 102 521
(`loop-305318.log:656`: "Finally, using: (212057-321499) (109442/102521 desired rows)"). Since
`SHUFFLE_KEEPROWS 120 000` exceeded the window, every row on disk was drawn every cycle until
the window regrew past 120 000 rows (about three cycles; the window first exceeded 120 000 rows at 18.31 M samples), which is the one stretch of the run
with a genuine over-training signature: the training `vloss` **fell below** its pre-boundary
level (0.5930 at 18.51 M against 0.6002 before the boundary) while `pacc1` was 0.02 lower.
The spike-then-undershoot cost about two exports (`t9-s18225024` was exported from the peak,
`pacc1 0.5137` against `0.5340` two exports earlier) and after 75 link-2 cycles the window (398 606 rows) has still not regained its
pre-boundary size (421 842). The knob file's statement that link 2 "resumes a mature window pinned at
SHUFFLE_KEEPROWS = 120000 rows" (`knobs_9x9.env:198`) is refuted at the boundary: the window
was 109 442 rows, below `KEEPROWS`, and `min_rows` was the operative floor.
`validation_boundary_1_2.md:45` recorded "shuffle window 109.4K ... confirmed" as an expected
value; it was the defect.

Prediction. Link 2 ends at 17:53:21 EDT today (`squeue` END_TIME of 305318; 314831 is PENDING
on it). The same prune runs at link-3 start. Adding the measured boundary step (+0.0144 in
`vloss`) to the current 0.6074-0.6085 gives **0.622-0.623**: the flag is crossed by the boundary
artefact in the first epoch of link 3, then undershoots. `[PRELIMINARY]` (one boundary
observed). `verify:` after link 3 starts, the first two `metrics_train.json` rows of link 3
show `window_end_batch - window_start_batch` < 150 000 and a `vloss` step >= +0.010 within
200 000 samples unless the fix in section 6 lands first.

`[SOLID]` verify (the collapse itself): `python3 -c "import json; R=[json.loads(l) for l in
open('metrics_train.json')]; print([(r['nsamp'], r['window_end_batch']-r['window_start_batch'],
round(r['vloss'],4)) for r in R if 17900000<=r['nsamp']<=18100000])"` -> window 421 842 at
17 936 256, 109 660 at 17 970 816, `vloss` 0.6002 -> 0.6146; `sed -n 656p logs/loop-305318.log`.

### 3.6 The 7x7 comparator reproduces the shape

`evidence/converged_7x7/metrics_train-t7.json` (job 301096, same trainer, same LR, 7x7,
`samples_per_epoch 5000`): `vloss` minimum 0.5249 at 243 264 samples, 0.5370 at the final
2 449 536 (+2.3 %) while `p0loss` fell 2.335 -> 1.265 and `pacc1` rose 0.389 -> 0.648. Same
early minimum, same slow rise under a still-improving policy, no knob shared with the 9x9
option-C set. `[SOLID]` verify: `python3 -c` over that file reproduces the four numbers.

### 3.7 What the mirror's own documentation says

`docs/KataGoMethods.md:207-213` shows value loss on a **fixed** selfplay dataset falling
monotonically with training; that is the reference shape for a fixed distribution and does not
apply to a moving one. `synchronous_loop.sh:60` is the only in-repo statement on reuse:
`MAX_TRAIN_PER_DATA=8 # ... Larger numbers may cause overfitting.` The maintainer's published
run histories (value-loss curves of the public runs) are not in the mirror: `[HOLE]`, acquire
stage if the human wants that comparison.

## 4. Question 2: the 19-export policy stall

Facts. `p0loss` best `1.485115` / `pacc1` best `0.544882` at `t9-s20919936` (read 10); 19
exports and ~6 M samples since; excursion to `1.535492` (`t9-s22418432`), retrace to
`1.486201` (`t9-s24815616`, 0.07 % short), now `1.495273`. Over the same span the gate accepted
29 of 30 with losing scores 39.0-87.5 (mean 63.7, i.e. the candidate took 61.5 % of the
points against its immediate predecessor; equal strength would give ~50 % and an acceptance
probability of 0.53, `DESIGN.md:384`). The one rejection, `t9-s26014080` at 96.5-100.5, is
inside the gate's noise (`numGamesPerGating = 200`, `gatekeeper_9x9.cfg:32`; SE of the
candidate's share 0.035).

What the LR is doing (code). `train_9x9.sh` passes no `-lr-scale`; neither does
`synchronous_loop_9x9.sh:512` (`grep -c -- '-lr-scale'` on both -> 0); `KTG_TRAIN_EXTRA_ARGS`
(`train_9x9.sh:44,118`) is the empty hook for it. So `lr_scale = 1.0` (`train.py:422-423`),
`lr_scale_auto_factor = 1.0` (`:566-567`), optimizer SGD momentum 0.9 (`:844`),
`per_sample_lr = 0.00003` (`:1094`), warmup finished at 2 M samples (`:1062-1079`). The trainer
confirms it: `pslr_batch = 3.0e-05` on every row since 2 M samples (1.5e-06 at 12 800). **The
LR has been constant for 25 M samples and nothing in the loop will ever lower it.** The
mirror's built-in decays (`-lr-scale-auto`, `:504-521`, first step at 550 M samples;
`-lr-scale-auto2`, `:523-554`, 12x until 20 M then 9x, 6x, ... 0.05x by 600 M) are keyed to
19x19 sample counts and are not in use; `-lr-schedule` (`:86`) accepts an explicit
piecewise-constant schedule. Weight decay scales with the LR as `(lr_scale)^0.70-0.75`
(`:698-700`), so an LR change is also a regularisation change.

Capacity. `b7c96h3tfrs` (`modelconfigs.py:1008-1028`): 7 x (RoPE attention + SwiGLU ffn) at 96
channels, ffn 256, 3 heads, 0.82 M parameters; 27 M samples is 33 samples per parameter. The
next sizes in the mirror are `b8c96h3tfrs` (`:1057`, one more block, about +13 % parameters by
the block arithmetic 4 x 96^2 + 3 x 96 x 256 = 111 k per block), `b2b10c96h3tfrs` (`:1079`, two
conv blocks in front) and `b14c192h6tfrs` (`:1453`, the DESIGN section 9 ladder "b8 -> b14 as
fresh runs"; roughly 6 M parameters, to be confirmed by counting before use).

Data window. ~400 000 rows = ~13 cycles = ~5 accepted nets (section 3.5), reuse 3.9 trainings
per row, 30 600 fresh rows per cycle, one export per 2.5 cycles trained on ~300 000 samples.

Verdict. The stall is real on the loss metrics and **not visible in play strength as the gate
measures it**, which is head-to-head against the predecessor at 150 visits and can be
non-transitive. Its cause is undetermined among (LR noise floor, capacity, window): the
excursion's amplitude (+-0.025 in `p0loss`, +-0.008 in `pacc1`) is what a constant-LR SGD run
does at a plateau `[HYPOTHESIS]`; the boundary transient of section 3.5 cost two of the 19
exports; capacity cannot be judged without a larger net. The discriminating measurement is
cheap and already specified: the c14 400-game match (`codes/cfg/match_first_latest_9.cfg`,
`codes/eval/match.sbatch`, komi 7, 150 visits, SE 0.025 at n = 400). It has never been run on
the 9x9 chain (no `evidence/match*` directory exists). Run latest-vs-`t9-s20919936`: if the
latest net scores p <= 0.55 the last 19 exports bought no transitive strength and the LR anneal
is the next move; if p >= 0.60 the loss stall is a target-hardening effect like the value loss
and nothing should change.

## 5. Options for the human

Each option: mechanism, expected effect, cost, risk to the running chain, exact edit, first
link that carries it. Link 3 (job 314831) reads the knob file, `budget.env` and the loop
scripts at its own start (`loop.sbatch:192-211`, `:876`, `:953`); an edit landing before 17:53
EDT today reaches link 3, later ones reach link 4. Machine-readable copy:
`vloss_escalation_options.json`.

**(a) Do nothing to the trainer; retire and redefine the flag.** Mechanism: the flag measures the
outcome distribution, not the fit (sections 1-3). Effect: no false escalation tonight; the value
head stays under watch through invariant signals. Cost: none. Risk: none. Edit: the
monitoring packet's watch list only (section 6.2 gives the replacement). First link: now.
**Recommended, as part of the recommendation.**

**(b) LR scale.** Mechanism: `per_sample_lr = 0.00003 * lr_scale` (`train.py:1094`), WD follows as
`lr_scale^0.75`. Effect if the stall is LR-noise-limited: a one-time drop in `p0loss`/`vloss`
within 2-3 exports, then a lower noise floor; otherwise nothing. Cost: none. Risk: irreversible
loss of the exploration a higher LR buys; applied at link 3 it is confounded with the boundary
transient; the knob checker (`derive_knobs.py --assert-loop-defaults`) must be run on the edited
copy since the variable is new to the file. Edit: append `KTG_TRAIN_EXTRA_ARGS="-lr-scale 0.5"`
to `codes/loop/knobs_9x9.env` (exported by `loop.sbatch:209-211`, read by `train_9x9.sh:44`,
expanded at `:118`). First link: 3 if before 17:53 EDT. **Pre-registered for link 4,
conditional on the match (section 6).**

**(c) Data window.** Three distinct things hide under this heading.
(c1) *Stop the boundary collapse*: `codes/data_budget/budget.env:55`
`KTG_KEEP_SELFPLAY_GENERATIONS=3 -> 60`. Mechanism: keeps >= two links of generations on disk
so `shuffle.py`'s rows-on-disk window formula is continuous across the prune; the steady-state
window is unchanged. Cost: 20-92 MB per generation retained (`loop-305318.log:54-71`), ~3-5 GB
per link, against a 500 GiB cap at 2.9 % used. Risk: none to the trainer; the rolling
`--target-bytes` mode is not invoked (`loop.sbatch:876` passes `--apply` only). First link: 3 if
before 17:53 EDT. **Recommended.** The exact alternative that keeps the formula honest without
retaining data is `-add-to-data-rows <rows deleted>` (`shuffle.py:783`) on
`synchronous_loop_9x9.sh:506`, but it needs a rows-ever counter the loop does not keep:
`[FUTURE]`.
(c2) *Deliberately larger window*: `TAPER_WINDOW_SCALE 50000 -> 200000` (`knobs_9x9.env:215`)
raises the window at 2.6 M rows from ~399 k to ~582 k; `SHUFFLE_MINROWS 25000 -> 400000`
(`:200`) raises it to ~734 k because `min_rows` is added back (`shuffle.py:430`) and would also
have stopped tonight's collapse. Mechanism: more, older games per training draw at the same
reuse. Effect on the value head: unknown sign (diversity vs staleness). Cost: none. Risk:
changes the training distribution mid-chain and confounds every metric for ~20 cycles; the
`SHUFFLE_MINROWS` form trips the bootstrap inequality K5 in `check_knobs_9x9.py` (moot mid-run
but the checker will print FAIL). First link: 3 or 4. Not recommended now.
(c3) `SHUFFLE_KEEPROWS 120000 -> 240000` (`:226`): doubles samples per cycle **and** the
applied reuse to 7.8 against the cap of 8 (`knobs_9x9.env:178`), train time 53 -> 106 s per
cycle. This is the opposite of a fresher window. Not recommended. `-approx-rows-per-out-file`
(o49) changes epoch granularity and export cadence, not the window; irrelevant here.

**(d) Larger net as a new chain seeded from the current best.** Mechanism: weights cannot be
transferred across depths (the mirror's `migrate_*.py` scripts change channels, heads or
losses, not block count), so "seeded" means: new `BASEDIR` (`runs/p2`), `KTG_MODELKIND=b8c96h3tfrs`
or `b14c192h6tfrs`, `KTG_TRAININGNAME=t9b8` (`loop.sbatch:165-166`), `runs/p2/selfplay` seeded
with a copy of the current 36 generations (2.6 M rows) and `runs/p2/models` seeded with
`t9-s26913152` as the gate baseline, so the first candidates are gated against the current
best rather than against random. Effect: the only option that can move a capacity ceiling.
Cost: a second GPU for >= 1 link before any comparison is meaningful (1 GPU in flight now, cap
4); b8 adds ~13 % train time, b14c192 several times more and slows selfplay by an unmeasured
factor (GPU duty is 21.5 % on b7, DESIGN section 1). Risk to the running chain: none
(separate directory), except GPU contention. First link: p2 link 1. Not before (d) is justified
by the match.

**(e) Gate bar / match games.** `-required-candidate-win-prop 0.55` on the gatekeeper line
`synchronous_loop_9x9.sh:471` (`gatekeeper.cpp:271`, default 0.5, candidate wins ties `:579`), or
`numGamesPerGating 200 -> 400` (`gatekeeper_9x9.cfg:32`; SE 0.035 -> 0.025). Mechanism: fewer
non-transitive acceptances. Effect: none on `vloss`; slower incumbent turnover. Cost: gate stage
+195 s per gate at 400 games (~+6 % cycle wall at one gate per 2.5 cycles). Risk: a rejection
keeps the loop in the one-epoch regime for that cycle (read 8 note), and at 0.55 a genuinely
+35 Elo candidate is rejected half the time. First link: 3 or 4. Not recommended.

**(f) Stop-and-declare plateau.** Criterion proposed: no new `p0loss`/`pacc1` best for >= 30
exports **and** the c14 match gives the latest net p <= 0.55 against the best-by-loss net.
Then run the final latest-vs-first match and move to (d). Mechanism: converts the stall into a
decision with a measured strength test, as `plateau_check.py` did for 7x7 (its rule needs the
gate quiet for 15 cycles, which is not the case here). Cost: none. Risk: none. First link:
n/a; the counter is at 19.

**(g) Validation split (instrumentation).** Remove `SKIP_VALIDATE=1` at
`synchronous_loop_9x9.sh:506` so `shuffle.sh:58-95` peels 5 % of files into `val/` and
`train.py:1785-1825` writes `metrics_val.json` at each epoch end. Mechanism: the first held-out
number of the run, the only thing that can ever show an over-fit. Cost: 5 % of files leave the
training set; ~2 s per epoch. Risk: untested path in this loop; the val shuffle receives our
`-min-rows 25000` and with ~5 % of rows can hit `shuffle.py:1090-1091` "Not enough rows"
and exit before the train shuffle runs, which would fail the cycle and count against the
breaker. Needs a dry run on the 7x7 tree first (a CPU-only job). First link: 4. Recommended
for link 4 after the dry run, not for tonight.

**(h) Transitive strength match now (the c14 measurement).** `codes/eval/match.sbatch`
(`--gres=gpu:1`, `numGamesTotal 400`, `maxVisits 150`, komi 7, colours alternated) for
`t9-s26913152` vs `t9-s20919936` and vs `t9-s143744`. Cost: one GPU for well under an hour
(the gate plays 200 games at 150 visits in ~100 s). Risk: none to the chain. Policy: run the
compute-budget check first; 1 GPU in flight, cap 4. **Recommended, as part of the
recommendation.**

## 6. Recommendation, exact edits, and what each result would falsify

**6.1 The decision.** Option (a) + (c1) + (h) now; (b) pre-registered for link 4 conditional
on (h); (g) at link 4 after a dry run; (d) only if (h) and then (b) both fail to restore
progress. No LR, net, gate or window-size change at link 3, because link 3's first ~40 cycles
will carry the boundary transient (or its absence, if (c1) lands) and any trainer change made
at the same boundary is unattributable.

Edits, in the order to make them, all before 17:53 EDT today for link 3:

1. `codes/data_budget/budget.env:55`: `KTG_KEEP_SELFPLAY_GENERATIONS=3` -> `KTG_KEEP_SELFPLAY_GENERATIONS=60`.
   Owner: data_budget. Verify after link 3 starts: `loop-314831.log` prune block removes no
   `selfplay/t9-*` directory; first link-3 `metrics_train.json` row has
   `window_end_batch - window_start_batch` >= 380 000; no `vloss` step > 0.005 across the
   boundary. Falsifies section 3.5's prediction if the step still appears.
2. Monitoring packet: replace "vloss vs the 0.62 flag" with section 6.2.
3. `sbatch codes/eval/match.sbatch` twice (latest vs `t9-s20919936`; latest vs `t9-s143744`),
   after the compute-policy check named by `mission.json` `compute.policyCheck`
   (`--gpus 1 --cpus 32 --partition b200`).
   Record `p`, the 95 % CI from `python/summarize_sgfs.py`, and the Elo as DESIGN section 7
   specifies. Decision rule: p(latest vs s20919936) <= 0.55 -> apply (b) at link 4;
   >= 0.60 -> the stall is not a strength stall, keep running; between -> repeat at 800 games.
4. (link 4, conditional) `codes/loop/knobs_9x9.env`: append
   `KTG_TRAIN_EXTRA_ARGS="-lr-scale 0.5"`; run `python3 codes/eval/check_knobs_9x9.py
   --throughput evidence/production_chain/throughput.json --rows-file
   evidence/production_chain/rows_per_game.txt --marginal-nets 3 --trend-nets 9 --horizon-nets 10`
   and `codes/eval/derive_knobs.py --assert-loop-defaults` on the edited file. Expected
   signature if LR-limited: new `p0loss` and `pacc1` bests within 3 exports of link 4's start.

**6.2 The replacement for the 0.62 flag.** Report every read, escalate on any one:

- `tdvloss1` (EMA at the newest export) > 0.160 for three consecutive exports (10 % above its
  18 M-sample plateau of 0.146); this is the entropy-corrected value fit.
- search CE vs outcome on the newest complete generation > 0.46 (five sd above 0.432), computed
  by the section-8 script; this is the strength of the value estimate the selfplay actually
  uses, on its own games.
- once (g) exists: `metrics_val.json` `vloss` rising over three exports while
  `metrics_train.json` `vloss` falls; this is the over-fit signature, and the only one.
- raw `vloss` stays in the table as `vloss` and `vloss_adj = vloss - 0.321 * (draw_share - 0.090)`
  with the window draw share alongside; neither carries a threshold.
- the first two exports after any link boundary are excluded from every counter above.

**6.3 What the human would be accepting.** That the value head is being judged on a number
whose rise is explained by the games getting closer; that the policy stall is a loss-metric
stall of undetermined cause with the gate still reporting head-to-head gains; that one loop
defect (the boundary collapse) has been costing ~2 exports per link and will cross the flag
tonight unless a one-line retention change lands; and that the next trainer change is decided by
a 400-game measurement, not by a threshold.

## 7. Markers

- `[OPEN]` knowledge-ledger rows for sections 3.2, 3.3 and 3.5 (a worker re-runs section 8,
  appends with `CHANDRA_ROLE=worker`; a validator refutes or admits). The brain wrote none.
- `[OPEN]` the link-1 residual (+0.010 of the +0.032 rise) not explained by draw and close
  shares; extend the regression to gtype / handicap / komi.
- `[OPEN]` the knob file's "resumes a mature window pinned at SHUFFLE_KEEPROWS" (`knobs_9x9.env:198`)
  and `scale_data_window`'s "samples per cycle = SHUFFLE_KEEPROWS" hold only when the window
  exceeds `KEEPROWS`; at the boundary it did not. A `!`-tagged correction row is due.
- `[HOLE]` no held-out loss exists anywhere in the run; option (g) is the only way to get one.
- `[HOLE]` the maintainer's public run histories are not in the mirror.
- `[FUTURE]` `-add-to-data-rows` bookkeeping in the loop as the exact fix for the window formula.
- `[FUTURE]` a per-position value-CE breakdown for the **net** (not the search) by draw /
  non-draw and by game phase, which needs a forward pass over a fixed position set: a job.
- `[UNCHECKED]` the parameter counts quoted for b8 / b14 are block arithmetic, not a count.

## 8. Reproduction

Inputs: `runs/p1/train/t9/metrics_train.json` (append-only; `head -n 1809 | sha256sum` =
`4cf09c954af82ad561b3472d694dbe3c60d120030bbbcdac3d54e960814d8f4e`; the last of those rows is
`nsamp 27024256, vloss 0.607303, p0loss 1.492507, pacc1 0.540918`); the viewer snapshots
`runtime/games_viewer/p1/{games,cycles1-40,cycles41-70,cycles81-157,link2_cycles41-76}/games.json`
(schema 3, fields `src black white komi result handicap gtype nmoves moves hash cycle`, deduplicated
on `hash`); the 36 `runs/p1/selfplay/t9-*/sgfs/*.sgfs` on disk.

Method for the per-net game table: for each selfplay game (`src == selfplay`, `black == white`)
take `nmoves`, the `RE[]` winner (`B`/`W`/`draw`), `|margin|` from `RE[]`, `close = |margin| <= 2.5`;
average per net. Window covariates at an export = game-count-weighted means over the five
accepted nets exported before it. Search CE: for each move comment
`C[w l nr score v=... weight=wt]` (`sgf.cpp:2153-2205`; `w`,`l`,`nr` are the white-relative
search values at that turn, `wt` the training-row weight), take `p = w` if White won, `l` if
Black won, `-(0.5 ln w + 0.5 ln l)` for a draw, `nr` for a void game, clip at 0.005, and average
`-ln p` with weight `wt` over rows with `wt > 0`. OLS in pure Python (no numpy on the login
node); the coefficients of section 3.2 are reproduced by any least-squares routine on the
export table. Every script fits in ~60 lines and should be committed by the worker who admits
the rows, under `codes/eval/`.

No emission of this memo changed any file under `runs/p1`, `codes/loop`, `codes/cfg` or
`codes/data_budget`.
