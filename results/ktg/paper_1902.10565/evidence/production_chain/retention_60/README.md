# Retention 60 — the go/no-go page for memo option c1

`KTG_KEEP_SELFPLAY_GENERATIONS 3 -> 60` at `codes/data_budget/budget.env:55`.

**PREPARED, NOT APPLIED.** The repo working tree still reads `=3`. `apply_c1.sh` refuses
without `--yes`. No file under `runs/p1` was written, no job was signalled, and neither
`budget.env` nor `knobs_9x9.env` is modified in the commit that carries this directory.

Everything below is measured. Provenance for each number is the file named beside it.

---

## 1. The three numbers that decide it

| | KEEP=3 (today) | KEEP=60 (option c1) |
|---|---|---|
| generations deleted at link-3 start | **46 of 51** | **0 of 51** |
| shuffle window, first cycle of link 3 | **110 163 – 125 299 rows** (−78 % to −75 %) | **509 034 rows** (−0 %) |
| peak mission-root scratch during link 3 | 14.90 GiB | **16.58 GiB** — 7.32 % of the 500 GiB cap |

The cost of the change is **2.01 GiB, 0.401 % of the mission budget**, and it removes a
75–78 % window collapse that at the previous boundary moved `vloss` +0.0144 and cost about
two exports (memo §3.5).

**GO on storage. GO on the loop's own checks. The one thing it does not do is archive
anything — see §6.**

---

## 2. What runs, and when it takes effect

`loop.sbatch:876` runs `python3 prune_retention.py --basedir $BASEDIR --apply` exactly once,
at the **start** of a chain link, with no `--target-bytes` (so rolling mode never runs), and
`prune_retention.py` reads `budget.env` from the repo at that moment (`loop.sbatch:81`).

- Nothing re-reads the file mid-link. No running job is signalled.
- Link 2 is job **305318**, walltime end **2026-09-06T17:53:21 EDT**. Link 3 is **314831**,
  `PENDING (Dependency)` on it, and it sources the loop scripts and both env files from the
  repo when it starts. **The edit must be on disk before 17:53:21 to reach link 3**; after
  that it reaches link 4.

## 3. Files here

| file | what it is |
|---|---|
| `apply_c1.diff` | the one-line patch; `git apply --check` passes against the live repo |
| `apply_c1.sh` | applies it and runs `check_knobs_9x9.py` + `run_guard_tests.sh`; **refuses without `--yes`** |
| `apply_c1_test.txt` | that script run end to end on a scratch copy of the repo — exit 0 |
| `checks_before.txt` | the same checks on the unpatched repo, for the before/after diff |
| `dryrun_keep3.txt` / `dryrun_keep60.txt` | verbatim `prune_retention.py` dry runs against `runs/p1`, 10:28 EDT |
| `stub_tree_test.py` / `.txt` | four synthetic trees that put the 17:53 and link-4 geometries under both counts |
| `projection.py` / `.txt` / `.json` | window, scratch and SGF arithmetic, with the formula calibrated on 9 log points |
| `scratch_guard_now.txt` | `scratch_guard.sh` output at 10:30, the measured baseline |

## 4. The prune plans (deliverable 2)

Verbatim, `runs/p1`, 2026-09-06T10:28 EDT, 37 generations and 13 shuffleddata dirs on disk:

- **KEEP=3** — `-- deletion plan (32 paths, 1 131 433 908 B) --`, all 32 `selfplay/t9-*`
  generations from `t9-s15847040-d2653436` to `t9-s25414912-d2205679`. 5 survive.
- **KEEP=60** — `-- deletion plan (0 paths, 0 B) --`. The protected set is **identical**
  (18 entries, same paths) in both runs.

Only `budget.env:55` differs between the two trees; `prune_retention.py` is byte-identical
(`sha256 c07bc668b16ca866ac8316175d1ce66f92921fb7143dd6f414710cf324f44144`).

Neither run deletes a `shuffleddata` dir, because upstream `cleanup_old_dirs.py` — which
`shuffle.sh:113` runs after **every** shuffle — already holds it at "newest 3 older than
2 h", the pruner's own rule. That rule is untouched by this change.

The 10:28 dry run is a snapshot. At 17:53 the tree will hold **51** generations, so the stub
tree in §7 is the projection that matters.

## 5. The shuffle window (deliverable 4)

`shuffle.py:414-435` sizes the window from the rows **on disk**:

```
window_taper_offset = taper_window_scale                       # 50 000
power_law_x         = num_usable_rows - min_rows + offset      # min_rows 25 000
unscaled            = x**0.65 - offset**0.65
scaled              = unscaled / (0.65 * offset**(0.65-1))
desired_num_rows    = int(scaled * 0.4 + min_rows)             # expand_window_per_row 0.4
```

Arguments: `-min-rows 25000 -keep-target-rows 120000 -taper-window-scale 50000`
(`synchronous_loop_9x9.sh:506`) over `-expand-window-per-row 0.4 -taper-window-exponent 0.65`
(`shuffle.sh:43-51`). **No `-max-rows` is passed anywhere**, so `max_rows is None`.

Transcribed into `projection.py` it reproduces **all nine** `Desired num rows` lines of
`logs/loop-305318.log` exactly, including the boundary one (321 499 rows -> 102 521).

At the projected link-3 start (**3 788 433 rows on disk**, +36 cycles at the measured 30 365
rows/cycle):

| | rows on disk | window | step |
|---|---|---|---|
| last cycle of link 2 | 3 788 433 | 509 034 | — |
| **KEEP=60**, first cycle of link 3 | 3 788 433 | **509 034** | **+0 (0.0 %)** |
| KEEP=3, first cycle of link 3 | 359 825 – 439 786 | 110 163 – 125 299 | −398 871 to −383 735 (−78 % to −75 %) |
| link-1 -> link-2 boundary, **measured** | — | 421 842 -> 109 442 | −74.1 %, `vloss` 0.6002 -> 0.6146 |

**The boundary collapse does not recur at 60**: nothing is deleted, `num_usable_rows` is
continuous, and the window is therefore continuous. The counterfactual at 3 is a collapse
*deeper* than link 2's, because the generations are larger now (1800 games/cycle).

**What binds instead.** `SHUFFLE_KEEPROWS = 120 000` binds, which is what the knob file
intends: with a 509 034-row window `keep_prob = 0.236`, so a cycle draws 120 000 of 509 034
rows and "samples per cycle = SHUFFLE_KEEPROWS" is true again. `SHUFFLE_MINROWS = 25 000` is
20× below the window and never binds. `TAPER_WINDOW_SCALE = 50 000` is the power-law
*offset* (`shuffle.py:421`), not a clamp — it shapes the curve at every size and can never
bind. There is no `max_rows`. Reuse `rho = KEEPROWS/(G·r) = 120000/(1800·16.87) = 3.95` is a
function of games/cycle and rows/game only and is **unchanged** by retention.

At KEEP=3 the projected window straddles `KEEPROWS`: at the low end (110 163) `keep_prob`
returns to **1.000** — every row on disk drawn every cycle, the over-training signature the
memo identified at the last boundary.

## 6. Scratch (deliverable 3) — the guard's cap does NOT need raising

Measured at 2026-09-06T10:30 by `scratch_guard.sh` (`scratch_guard_now.txt`):

```
du -sb  15 446 626 012 B  (14.39 GiB)   mission root
        1 362 996 266 B                 runs/p1/selfplay, 37 generations
          658 610 549 B                 runs/p1/shuffleddata, 13 dirs
projected root total 36 921 462 492 B of the 536 870 912 000 B (500 GiB) hard cap  = 6.88 %
```

Mean **complete** link-2 generation = **39 150 047 B (37.3 MiB)** = 23 287 955 tdata +
15 836 783 sgfs, over the 29 complete generations. 79 961 rows/generation, 489.6 B/row.

| | link-3 start | link-3 end (+44 generations) | peak root | guard's projected total |
|---|---|---|---|---|
| KEEP=3 | 5 gen, 0.18 GiB | 49 gen, 1.79 GiB | 14.90 GiB | 6.98 % of cap |
| **KEEP=60** | 51 gen, 1.86 GiB | 95 gen, 3.46 GiB | **16.58 GiB** | **7.32 % of cap** |

Thresholds in `budget.env` are unchanged and remain far away: hard cap 500 GiB, default
projection 20 GiB (effective soft cap 480 GiB), group free floor 1 TiB against 8.39 TiB free.
**Headroom under the soft cap with 60 generations retained: 464.7 GiB = 12 744 further
generations.** No threshold in `budget.env` needs to move.

`derive_knobs.py:519-523` reads `KEEP_SHUFFLEDDATA`, `KEEP_REJECTED_MODELS`,
`KEEP_LONGTERM_CHECKPOINTS` and `KEEP_DATED_SCRIPTS` — and **not**
`KEEP_SELFPLAY_GENERATIONS`. T3 treats every cycle's selfplay write as monotonic within a
link, which is exactly what happens. So the storage check's verdict cannot move on this edit,
and `apply_c1_test.txt` shows it does not.

## 7. Risk to link 3 (deliverable 6) — stub-tree test

`stub_tree_test.py` builds synthetic trees with mtimes reproducing the real cadence
(12.21 min/cycle, 1.866 generations/h, both measured over link 2's 79 cycles) and runs both
constants files over each. `stub_tree_test.txt` is the output.

| scenario | KEEP=3 deletes | KEEP=60 deletes | survivors 3 → 60 |
|---|---|---|---|
| A — 51 generations, the link-3 start | 46 selfplay, 0 shuffleddata | **0, 0** | 5 → 51 |
| B — 95 generations, the link-4 start | 90 | **35** | 5 → **60** |
| C — A with one generation's mtime out of s-number order | 45 | **0** | 6 → 51 |
| D — B with `--target-bytes` (rolling mode) | 90 | 47 selfplay + 3 shuffleddata | 5 → 48 |

What this shows about the three things that could behave differently at 60:

- **Ordering.** `entries()` sorts by **mtime**, not by name or s-number. At 60 the slice
  `sp_gens[:max(0, len-60)]` is empty whenever ≤ 60 generations exist, so ordering cannot
  matter (scenario C: identical `0` plan with the order scrambled). At 3 it does.
- **Min-age.** `KTG_SHUFFLEDDATA_MIN_AGE_S` applies to `shuffleddata` only; the selfplay rule
  has no age term. The shuffleddata plan is **identical** at 3 and 60 in A, B and C.
- **Protect list.** Identical in every scenario — 18 entries against `runs/p1`, 14 against the
  stubs, same kinds, same paths. `keep_gen` is not an input to it.
- **The `oldest retained shuffle window` guard** still applies at 60; it is simply never
  reached, because the keep-N slice empties first. It is not bypassed.
- **Rolling mode** still works at 60 (scenario D) and still honours its floors
  (1 shuffle dir, 1 selfplay generation). The loop never passes `--target-bytes`
  (`loop.sbatch:877`), so this path is only what an operator would run after a
  `scratch_guard` exit 1.
- **The bound is still a bound.** Scenario B: at 95 generations, KEEP=60 deletes 35 and
  leaves exactly 60. Retention does not become unbounded.

Residual risk to link 3: **one extra `shutil.rmtree` pass is not run**, and ~1.8 GiB more
stays on disk. `prune_retention.py` is not modified, `scratch_guard.sh` is not modified, and
no threshold moves.

## 8. SGF side effect (deliverable 5) — for obligation o52, quantified, not decided

A generation is deleted **whole** and `sgfs/*.sgfs` goes with it. Measured from the 37
generations on disk (`projection.txt` §6): **161 470 games** in **549 853 444 B** of `.sgfs`;
4 655 games and 15 836 783 B (15.1 MiB) per complete link-2 generation; **3 402 B per game**.

At link-3 start the tree will hold ~**226 270 games** (161 470 now + 36 cycles × 1800) in
~735 MiB of `.sgfs` across 51 generations.

| | generations kept | games kept | `.sgfs` kept |
|---|---|---|---|
| KEEP=3 | 5 | ~23 276 (**10.3 %**) | ~76 MiB |
| KEEP=60 | 51 (all) | **226 270 (100 %)** | ~735 MiB |
| difference | 46 | **202 994 games** | **~659 MiB** |

Of link 2's own output (~115 cycles × 1800 = ~207 000 games in ~44 generations), KEEP=3
carries ~5 generations into link 3 and KEEP=60 carries all of it.

**What this does and does not do for o52.** It is not an archive. It defers the deletion by
roughly one link: the 60th-oldest generation is deleted at the *next* boundary, so the tree
holds about **32 h** of game history (~906 MiB at 60 generations) instead of about 3 h.
`codes/data_budget/archive_sgf.sh` exists and `loop.sbatch:859-869` runs it **before** the
prune when `KTG_ARCHIVE_SGF=1`; the knob is committed at 0. Whether to switch it on is the
human's decision and this page does not take it.

## 9. Checks, before and after

| check | before (`checks_before.txt`) | after (`apply_c1_test.txt`) |
|---|---|---|
| `check_knobs_9x9.py` (frozen smoke evidence, the documented default) | **PASS, exit 0** | **PASS, exit 0** |
| `check_knobs_9x9.py --throughput … --rows-file …` (production evidence) | **PASS, exit 0** | **PASS, exit 0** |
| `run_guard_tests.sh` | **25 passed, 0 failed** | **25 passed, 0 failed** |
| `check_knobs_9x9.py … --marginal-nets 3 --trend-nets 9 --horizon-nets 10` | **exit 1** | **exit 1** |

`[OPEN]` The last row is the invocation the memo §6.1 item 4 names, and it **already exits 1
before any edit**: rows/game has turned upward (+0.0356 rows/game per accepted net over the
last 9 complete directories), so the carried-forward lower bound lands above the measurement
and `derive_knobs.py` refuses — *"a lower bound that exceeds the measurement is not a bound"*.
That is an open item about the trend arguments, not about this patch, and it must not be read
as the patch breaking a check. Closing evidence: either a `--trend-nets`/`--horizon-nets`
pair whose least-squares slope is negative over the window used, or a change to
`derive_knobs.py` that clamps the carried bound at the measurement.

## 10. Open items this page leaves behind

- `[OPEN]` the trend-argument failure in §9.
- `[OPEN]` `runs/p1/models` is **854 631 897 B** across 88 accepted nets and grows ~18 MiB/h;
  `prune_retention.py` has **no rule for `models/`** (only `rejectedmodels/`). Unrelated to
  c1 and still small, but it is the only unbounded directory in the tree.
- `[OPEN]` the projection's rates are link-2 averages. If cycle time changes in link 3 the
  generation count at the link-4 boundary moves, and 60 could bind earlier or later than
  scenario B says. Closing evidence: re-run `projection.py` against link 3's own log.
- `[OPEN]` the `!` correction to `knobs_9x9.env:198` ("resumes a mature window pinned at
  `SHUFFLE_KEEPROWS`") is filed as an error-ledger row; the comment in the knob file is
  deliberately **not** edited, because that edit belongs with the human's decision.
