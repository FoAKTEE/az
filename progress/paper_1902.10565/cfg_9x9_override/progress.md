# progress — `cfg_9x9_override`

Node `arxiv-1902.10565::cfg_9x9_override`, wave 1. Authors the three mission-owned 9x9
artifacts and the checker that proves them, then executes the checker once inside a real
allocation. Evidence lives under `results/ktg/paper_1902.10565/evidence/cfg_9x9/`.

## Landed

| phase | files | outcome |
|---|---|---|
| 1 author | `codes/cfg/selfplay_9x9.cfg`, `codes/cfg/gatekeeper_9x9.cfg`, `codes/loop/train_9x9.sh` | both key-diffs show `OUT_OF_SET_KEYS = 0`; the train wrapper differs from upstream `train.sh` in exactly one line |
| 2 execute | `codes/eval/check_cfg_9x9.sh` | five asserts, run as Slurm job 298359 (b200, 1 GPU, 24 CPUs) — see the closing check below |

## What changed and why

Five keys, in one commit because `o02` couples two of them:

| key | upstream | mission | why |
|---|---|---|---|
| `dataBoardLen` | 19 | 9 | selfplay writes 19x19-shaped rows for 9x9 games otherwise; silent (`selfplay.cpp:97,220`) |
| `-pos-len` (train wrapper) | 19 hard-coded | 9 | must equal `dataBoardLen` or `data_processing_pytorch.py:91` asserts; leaving *both* at 19 asserts nothing and costs ~(361/81)^2 attention FLOPs |
| `bSizes` | 7,8,9 | 9 | no 9-only preset exists upstream and the mirror is read-only |
| `bSizeRelProbs` | 1,1,8 | 1 | arity must match `bSizes` (`play.cpp:148-150`) |
| `allowRectangleProb` | 0.50 | 0 | half the games would be `SZ[x:y]` rectangles (`sgf.cpp:2015`) |
| `numGameThreads` | 128 | 18 (both configs) | 128 game threads would be a false `--cpus-per-task` declaration by more than 5x |

Deliberately unchanged, each because the code already does the right thing at 9x9:
`chosenMoveTemperatureHalflife = 19` (`searchhelpers.cpp:541-545` rescales by 19/sqrt(area)),
`handicapProb = 0.10` (`playutils.cpp:10-22` returns 0 extra black below sqrt(area) 10, so the
key is a no-op), `numSearchThreads = 1`, `numNNServerThreadsPerModel = 1`, `maxVisits`,
`cheapSearch*`, `numGamesPerGating`. `handicapProb = 0.0` is what `convention.md` §10 proposes
and is equivalent; it is deferred because the key is outside the checker's allowed set.

## Thread budget without the CPU cap

The human withdrew the 20 % CPU clause on 2026-09-03 (`mission.json` `decisions[0]`,
`compute.cpuCapPerJob = null`), so 18 game threads is no longer derived from a ceiling. The
derivation now runs the other way: sum the live threads the stage needs (18 game + 1 nnServer +
1 dataWrite + 1 modelLoad + 1 main = 22, +2 transient at a net switch) and declare at least that
many CPUs — hence `--cpus-per-task=24`, which is also what `loop.sbatch` already asks for. The
checker reads its threshold from `SLURM_CPUS_PER_TASK` rather than from a constant, so the
comparison is against the allocation the job actually holds. Full re-derivation, with the
consequences for `o03`, `c06`, `a11` and `o22`: `evidence/cfg_9x9/thread_budget.md`.
`DESIGN.md` §1 and §9 are revised in place to match.

## Two runs, not one

The task file's `-max-games-total 1` proves the config parses and plays, but it cannot support
the thread measurement: 17 of the 18 game threads take a `gameIdx >= maxGamesTotal` and break
immediately (`selfplay.cpp:291-293`), so a peak sampled there would be a startup race. The
checker therefore runs a second `-max-games-total 36` pass (2 games per game thread) for the
`ps -o nlwp=` sampling, and counts `SZ[9]` over the SGFs of both — strictly more evidence for
check 4, not less.

## Closing check

`CHECK_CFG_9X9: PASS`, `CHECKER_EXIT=0`, Slurm 298359 `COMPLETED 0:0` in `00:00:09` on `gb205`
(b200, `cpu=24`, `gres/gpu=1`, `mem=64G`). The five asserts:

| assert | measured | threshold |
|---|---|---|
| 1 selfplay key-diff | `OUT_OF_SET_KEYS(1_selfplay) = 0`, significant lines 101 vs 101 | 0 |
| 2 gatekeeper key-diff | `OUT_OF_SET_KEYS(2_gatekeeper) = 0`, significant lines 62 vs 62 | 0 |
| 3 parse run | `exit_code = 0` in 2 s, 1 game, 68 moves, 39 data rows | 0 |
| 4 board size | `n_all = 37`, `n9 = 37`, `SZ9_FRACTION = 1.000`, `n_rectangular = 0` | `n9 == n_all`, `n_all >= 1` |
| 5 threads | `NLWP_MAX = 22` over `NLWP_SAMPLES = 52` vs `CPU_BUDGET = 24` (`SLURM_CPUS_PER_TASK`) | `<= CPU_BUDGET` |

Plus `grep -c -- '-pos-len 9' train_9x9.sh = 1`, `'-pos-len 19' = 0`, and `numGameThreads = 18`
in both configs. Verbatim run, with `sacct` and `seff` appended:
`evidence/cfg_9x9/check_cfg_9x9-298359.txt`.

22 threads is exactly the arithmetic — 18 game + 1 nnServer + 1 dataWrite + 1 modelLoad + 1 main
— with nothing unaccounted for and 2 to spare against the declaration. `seff`'s 11.57 % CPU
efficiency is an artifact of a 9 s job whose 24 cores idle through the module loads and the
static checks; it says nothing about the production loop.

## Ledger

- error ledger: one trial, one row, `pass` —
  `row_hash abfb7390df4e1775c9fa980685f0d3a3617d78853ba2cc9766140d6b4f1b242f`,
  `node_seq 1`, `git_commit 0fdf38f`. No failed attempt preceded it.
- result and knowledge rows are NOT appended by this worker: the candidates are written to
  `evidence/cfg_9x9/candidate_rows.json` for an independent validator to refute or admit.
