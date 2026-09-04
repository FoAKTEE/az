# Implementation plan — Bash / Slurm · mission `ktg-train` (paper_arxiv-1902.10565)

Partitioned by `logic.md` DAG node. **CODE-FIRST**: `path:line` anchors are relative to the
read-only mirror `ref-code/lightvector-KataGo/` @ `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4`
unless prefixed `codes/` (= `results/ktg/paper_1902.10565/codes/`). Mission scripts are copies
and wrappers; no upstream script is patched in place. Nothing here has been executed.

Roots: `KTG_ROOT=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train` (`codes/env/env.sh:6`),
`BASEDIR=$KTG_ROOT/loop`, `KATAGO_SRC=$KTG_ROOT/build/KataGo`,
`KATAGO_BIN=$KATAGO_SRC/cpp/build/katago` (`codes/env/env.sh:20-23`).

## Mandatory pre-flight — before **every** `sbatch`

```
bash "$POLICY_CHECK" \
     --gpus 1 --cpus 24 --partition b200
```

Exit 0 is required (`check.sh:8-9`; caps `check.sh:23-25`: CPU ≤24 = 20 % of 124, GPU ≤4,
`b200`/`b300` only). The self-resubmit inside `loop.sbatch` runs the same check and refuses to
chain when it fails.

---

## loop_resume_under_walltime

Predecessors: `train_resume_semantics`.

### `codes/loop/loop.sbatch`

| directive | value | reason |
|---|---|---|
| shebang | `#!/bin/bash -l` | login shell so `module load` works (`codes/env/env.sh:9`) |
| `--job-name` | `ktg-loop` | |
| `--account` | `ssci-anima` | matches `codes/env/env_build.sbatch:4` |
| `--partition` | `b200` (`b300` once `gb301` frees) | assumption `a04_b200_fallback` |
| `--nodes` / `--ntasks-per-node` | `1` / `1` | assumption `a01_single_node` |
| `--gres` | `gpu:1` | assumption `a02_gpu_cap_start_at_1`; → `gpu:2` only after `eval_improvement` passes |
| `--cpus-per-task` | `24` | 20 % node cap (`check.sh:23-25`) |
| `--mem` | `120G` | |
| `--time` | `2-23:30:00` | inside the 3-day MaxTime with 30 min of slack (assumption `a03_walltime_resume`) |
| `--output` | `$KTG_ROOT/logs/loop-%j.log` | on `/scratch`, never in the repo |

Body, in order:

1. **Resubmit first.** `sbatch --dependency=afterany:$SLURM_JOB_ID $0` is issued *at the top* of
   the script so the chain survives an OOM, a node failure, or a hard walltime kill. Guards, all
   required: skip if `$BASEDIR/STOP` exists; skip if the compute-budget check fails; increment
   `$BASEDIR/.chain_depth` and skip past a recorded maximum. `[OPEN] chain-runaway` — a job that
   dies in its first seconds would otherwise spawn a successor immediately and loop forever;
   closes when the depth cap and a minimum-runtime guard are both coded and tested once.
2. `source $KTG_ROOT/env.sh` (`codes/env/env.sh`), then `mkdir -p $BASEDIR`.
3. Export `KTG_SCRATCH_CAP_BYTES=200000000000` (200 GB) and `KTG_ONE_CYCLE=0`.
4. Pre-flight `du -sb $BASEDIR` guard (see `data_budget` below) — abort before starting rather
   than after filling the filesystem.
5. `exec bash codes/loop/synchronous_loop_9x9.sh ktg9 $BASEDIR t9 b5c48h3tfr 1`
   (arg order fixed by `python/selfplay/synchronous_loop.sh:12-32`:
   `NAMEPREFIX BASEDIR TRAININGNAME MODELKIND USEGATING`).

### Idempotence of a mid-cycle kill (what makes the resubmit safe)

| stage | behaviour on restart | anchor |
|---|---|---|
| gatekeeper | restarts; the candidate stays in `modelstobetested/` until the rename | `cpp/command/gatekeeper.cpp:591-598`, `:623-630`; empty-accepted early return `:399-402` |
| selfplay | completed `.npz` persist (`.npz.tmp` → rename); only the ≤10000-row in-memory buffer is lost | `cpp/dataio/trainingwrite.cpp:1093-1096`; `selfplay1_maxsize9.cfg:19` |
| shuffle | writes `shuffleddata/<ts>.tmp`, renamed at the end; train skips `.tmp` | `python/selfplay/shuffle.sh:105`; `python/train.py:1206-1213` |
| train | auto-resume from `checkpoint.ckpt`, shuffle-order state inside `train_state` | `python/train.py:573-574`, `:780-796`, `:850`; `python/katago/utils/training_data_generator.py:12-20` |
| export | **hazard**: upstream `rm -r "$SRC"` at `export_model_for_selfplay.sh:89` precedes `mv "$TMPDST" "$TARGET"` at `:108`; a kill between them leaves a `<NAME>.exported` dir that the next run skips (`:54-56`) and loses the checkpoint | fixed in `codes/loop/export_model_for_selfplay_9x9.sh` (Python plan) **and** belt-and-braces: `synchronous_loop_9x9.sh` deletes stale `torchmodels_toexport/*.exported` on startup — obligation `o09_export_kill_window` |
| orphan `.tmp` shuffle dirs | never cleaned by `cleanup_old_dirs.py` (it only prunes real dirs, keeping the newest 3 older than 2 h) | `python/selfplay/cleanup_old_dirs.py:13,19,24` |

| verification | value |
|---|---|
| command | submit the loop; `scancel` it mid-train and again mid-export; confirm the queued successor starts and that `train_state` row counter, `shuffleddata/`, and `models/` are all consistent |
| metric + tolerance | no completed `.npz` lost; `checkpoint.ckpt` resumes at the same global-step samples; zero surviving `*.exported` dirs; the successor job is `PENDING (Dependency)` while the parent runs (claim `c08_resume_no_loss`) |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/loop_resume_under_walltime/` |

---

## synchronous_loop_smoke

Predecessors: `tiny_model_export_smoke`, `cfg_9x9_override`, `loop_resume_under_walltime`.

### `codes/loop/synchronous_loop_9x9.sh` — mission copy of `python/selfplay/synchronous_loop.sh`

Copied verbatim except for the changes below. Positional args and the cycle order
(gatekeeper → selfplay → shuffle → train → export, `:93-116`) are unchanged; `#!/bin/bash -eu`
+ `set -o pipefail` (`:1-2`) is kept, so any stage failure still stops the loop.

| # | upstream | line | mission change | reason |
|---|---|---|---|---|
| 1 | `SELFPLAY_CONFIG=$GITROOTDIR/cpp/configs/training/selfplay1.cfg` | `:70` | `codes/cfg/selfplay_9x9.cfg` | upstream default is the mixed-size `selfplay1.cfg`, not even the maxsize9 preset — obligation `o13_loop_config_paths` |
| 2 | `GATING_CONFIG=$GITROOTDIR/cpp/configs/training/gatekeeper1.cfg` | `:71` | `codes/cfg/gatekeeper_9x9.cfg` | same |
| 3 | `cp "$GITROOTDIR"/cpp/katago "$DATED_ARCHIVE"/bin` | `:81` | `cp "$KATAGO_BIN" "$DATED_ARCHIVE"/bin/katago` | the CMake build puts the binary at `cpp/build/katago` (`codes/env/env.sh:22`), not `cpp/katago`; the upstream `cp` would fail under `-eu` on the very first cycle |
| 4 | `./train.sh ... main ...` | `:109` | `./train_9x9.sh ...`, with `codes/loop/train_9x9.sh` copied into `$DATED_ARCHIVE` alongside the upstream `*.sh` (`:78`) | upstream `train.sh:88` hard-codes `-pos-len 19` |
| 5 | `./export_model_for_selfplay.sh` | `:113` | `./export_model_for_selfplay_9x9.sh`, likewise copied into the archive | rm-before-mv fix + attn-logit-bound guard (Python plan) |
| 6 | — | before `:93` | `rm -rf "$BASEDIR"/torchmodels_toexport/*.exported` | clears a stale marker left by a killed export |
| 7 | — | top of the `while` body | scratch-cap check (below) | `data_budget` |
| 8 | — | top of the `while` body | `[ "${KTG_ONE_CYCLE:-0}" = 1 ] && ONE=1` … `break` at the end of the body | lets `smoke_loop.sbatch` run exactly one cycle |
| 9 | knob block | `:57-66` | table below | 9x9 rows/game ≈22, not 19x19 |

`GITROOTDIR=$(git rev-parse --show-toplevel)` (`:35`) and `git show`/`git diff` (`:84-86`) are
kept, so the script must run from inside the scratch git clone `$KATAGO_SRC` (created at
`codes/env/env_build.sbatch:126-134`), never from the read-only mirror.

### Knob table

| variable | upstream | line | smoke | production (provisional) |
|---|---|---|---|---|
| `NUM_GAMES_PER_CYCLE` | 500 | `:57` | 20 | 2000 |
| `NUM_THREADS_FOR_SHUFFLING` | 8 | `:58` | 4 | 8 |
| `NUM_TRAIN_SAMPLES_PER_EPOCH` | 100000 | `:59` | 2000 | 50000 |
| `MAX_TRAIN_PER_DATA` | 8 | `:60` | 8 | 8 |
| `NUM_TRAIN_SAMPLES_PER_SWA` | 80000 | `:61` | 2000 | 40000 |
| `BATCHSIZE` | 128 | `:62` | 32 | 128 |
| `SHUFFLE_MINROWS` | 100000 | `:63` | 200 | 20000 |
| `MAX_TRAIN_SAMPLES_PER_CYCLE` | 500000 | `:64` | 4000 | 300000 |
| `TAPER_WINDOW_SCALE` | 50000 | `:65` | 1000 | 20000 |
| `SHUFFLE_KEEPROWS` | 600000 | `:66` | 20000 | 400000 |

Smoke sizing: 20 games × ≈22 rows/game ≈ 440 rows > `SHUFFLE_MINROWS` 200, so the first shuffle
is not starved; `SHUFFLE_KEEPROWS` ≫ available rows so the window keeps everything.
`[OPEN] production-knobs` — the production column is arithmetic from the *expected* ≈22
rows/game (`trainingwrite.cpp:1206-1251`, `play.cpp:1143`, ~80 moves/game per assumption
`a07_moves_per_game_80`), not a measurement. Closes when `c09_selfplay_rate` and
`c10_rows_per_game` land and the column is re-derived from the measured rate.

### `codes/loop/smoke_loop.sbatch`

Same `#SBATCH` block as `loop.sbatch` except `--time=02:00:00`, `--job-name=ktg-smoke`, and
`--output=$KTG_ROOT/logs/smoke-%j.log`. It does **not** resubmit itself. It sources `env.sh`,
sets `KTG_ONE_CYCLE=1` and `BASEDIR=$KTG_ROOT/smoke_loop`, then runs
`codes/loop/synchronous_loop_9x9.sh ktg9smoke $BASEDIR t9smoke b5c48h3tfr 1` with the smoke knob
column, and exits after one cycle.

| verification | value |
|---|---|
| command | `bash "$POLICY_CHECK" --gpus 1 --cpus 24 --partition b200 && sbatch codes/loop/smoke_loop.sbatch`; then `ls -d $BASEDIR/models/*/` and `katago benchmark -model $BASEDIR/models/*/model.bin.gz -config codes/cfg/selfplay_9x9.cfg -boardsize 9 -v 80 -t 1` |
| metric + tolerance | one cycle exits 0; ≥1 `data*.npz` in `shuffleddata/<ts>/train`; exactly one new net reaches `modelstobetested/` (USEGATING=1) and, after the next cycle's gatekeeper, `models/`; the engine loads it (claim `c07_loop_cycle_completes`) |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/synchronous_loop_smoke/` |

Cycle 1 has no accepted model: the gatekeeper returns 0 immediately
(`cpp/command/gatekeeper.cpp:399-402`) and selfplay bootstraps with the built-in random net
(`cpp/dataio/loadmodel.cpp:77-80`; `cpp/program/setup.cpp:126-130`) writing into
`selfplay/random/` — assumption `a10_random_bootstrap_ok`, obligation `o10_random_net_bootstrap`.

---

## data_budget (Bash half — the cap enforcement; measurement scripts are in the Python plan)

Predecessors: `synchronous_loop_smoke`, `data_format_pos_len`.

Inserted at the top of each `while` iteration of `codes/loop/synchronous_loop_9x9.sh`:

```
USED=$(du -sb "$BASEDIR" | cut -f1)
if [ "$USED" -ge "${KTG_SCRATCH_CAP_BYTES:-200000000000}" ]; then
  echo "scratch cap reached: $USED >= $KTG_SCRATCH_CAP_BYTES"; touch "$BASEDIR"/STOP; exit 3
fi
python codes/eval/prune_checkpoints.py --traindir "$BASEDIR"/train/"$TRAININGNAME" --keep 6
rm -rf "$BASEDIR"/rejectedmodels/*
```

`touch $BASEDIR/STOP` also stops the `loop.sbatch` chain from resubmitting, so the run halts
cleanly instead of failing repeatedly.

| what grows | pruned by | anchor |
|---|---|---|
| `selfplay/<model>/tdata\|sgfs` | **nothing upstream** — `[OPEN] tdata-retention` (also raised in the Python plan) | `cpp/command/selfplay.cpp:176-178,186-188` |
| `shuffleddata/<ts>` | `cleanup_old_dirs.py` keeps the newest 3 older than 2 h | `python/selfplay/cleanup_old_dirs.py:13,19,24`, called at `shuffle.sh:113` |
| `train/<name>/checkpoint*.ckpt` | train.py rotates 4 | `python/train.py:578`, `:614-622` |
| `train/<name>/longterm_checkpoints` | **nothing upstream** (one every 12 h) → `prune_checkpoints.py --keep 6` | `python/train.py:1884-1889` |
| `models/`, `modelstobetested/`, `rejectedmodels/` | nothing upstream → `rejectedmodels` cleared per cycle | `export_model_for_selfplay.sh:65-69` |
| `scripts/dated/<ts>` | nothing upstream — one archive per loop restart, i.e. one per resubmit | `python/selfplay/synchronous_loop.sh:75-81` |

| verification | value |
|---|---|
| command | `du -sb $BASEDIR`; `ls $BASEDIR/train/*/longterm_checkpoints/*.ckpt \| wc -l`; `python3 /apps/helpers/quotas.py` recorded once before the first production cycle (obligation `o04_scratch_budget`) |
| metric + tolerance | `du -sb $BASEDIR` < 2.0e11 at every cycle boundary; longterm ckpts ≤6; selfplay data < 20 GB per 10⁶ games (claim `c11_scratch_budget`) |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/data_budget/` |

`[OPEN] dated-archive-growth` — every resubmit creates a new `scripts/dated/<ts>` archive
containing a full copy of `python/` plus the ≈100 MB `katago` binary
(`synchronous_loop.sh:77-81`); over a multi-week chain this is not negligible against the
200 GB cap and nothing prunes it. Closes when the mission loop either reuses one archive per
chain or prunes archives older than the newest N.

---
`POLICY_CHECK` = the value of `compute.policyCheck` in `mission.json` (the compute-budget skill check script), resolved relative to the `az` root.
