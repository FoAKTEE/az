# Checkpoints saved outside git — 9x9 production chain

The run's models, trainer state, self-play games and logs are too large to
track here. They are copied to durable space under `/home`, outside git and
outside scratch, and this file is the tracked pointer to them.

## 2026-09-06 — the human stop

    /home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop

| | |
|---|---|
| written | 2026-09-06, immediately after job 305318 ended at 13:03:11 EDT |
| total size | 7 683 842 860 B (7.2 GB) |
| files | 10 957 (10 956 + `MANIFEST.sha256` itself) |
| manifest | `MANIFEST.sha256`, 10 956 lines, 1 377 406 B |
| manifest sha256 | `ef75ba6c3155593a687daaf70e0b3ef5f0c705af6ec17974e8f12bc0a7efc4d2` |
| verified | `sha256sum -c MANIFEST.sha256` → exit 0, 10 956 `OK`, 0 failures |
| source repo commit | `4963393` (`code_snapshot/GIT.txt`) |

Verify at any time with

    cd /home/schmidt/ssci-haiyangw/ktg-checkpoints/2026-09-06_stop
    sha256sum -c MANIFEST.sha256

or run the full stop-and-save verifier, which re-checks the two Slurm jobs, the
wrapper log, `runs/p1`'s final dot-state, the checkpoint's size and file count,
every hash in the manifest, and the saved net's own sha256:

    bash results/ktg/paper_1902.10565/evidence/production_chain/verify_stop.sh

It takes about 45 s and exits 0 only if all 20 checks pass.

### Contents and sizes

Every component was compared source-to-destination on both byte count and file
count before the manifest was written; all ten matched exactly.

| path | bytes | files | what |
|---|---:|---:|---|
| `p1/models/` | 903 245 548 | 372 | the 93 accepted exports |
| `p1/rejectedmodels/` | 29 159 343 | 12 | the 3 the gatekeeper turned down |
| `p1/modelstobetested/` | 0 | 0 | empty — nothing pending at the stop |
| `p1/train/t9/` | 65 512 917 | 9 | `checkpoint.ckpt` + 4 rolling previous, `metrics_train.json` (1937 rows), `stdout.txt`, `train0.log` |
| `p1/selfplay/` | 1 549 242 381 | 883 | 412 tdata `.npz` + 110 `.sgfs` (183 443 games) + per-net logs |
| `p1/shuffleddata/` | 657 058 250 | 78 | 13 shuffle windows (under the 3 GB cut, so kept) |
| `p1/gatekeepersgf/` | 38 622 359 | 443 | every gatekeeper match played |
| `p1/monitor/` | 10 611 451 | 6 | ps and GPU samplers, both links |
| `p1/logs/` | 1 984 452 | 2 | the loop's per-stage logs |
| `p1/wrapper_logs/` | 16 186 953 | 2 | `loop-301099.log` (link 1), `loop-305318.log` (link 2) |
| `p1/.cycles_completed .chain_depth .failcount .pos_len_checked STOP` | — | 5 | the dot-state the loop resumes from |
| `t7/` | 4 284 227 815 | 9 100 | the 7x7 test run in full (stopped 2026-09-04) |
| `code_snapshot/` | 202 364 | 24 | loop scripts, configs, `budget.env`, env diffs, `GIT.txt`, and `link2_archive/` — the resolved cfgs, engine `version.txt`, working-tree diff and the sha256 of the `katago` binary that played link 2 |
| `pages/` | 126 394 351 | 19 | 16 built game viewers + `t9_loss_curve.html`, `t7_loss_curve.html`, `t7_games_v2.html` |
| `README.md` | — | 1 | stop record, net identities, c14 result, resume procedure, how to serve the net |

### The nets

| role | net | sha256 of `model.bin.gz` |
|---|---|---|
| latest accepted **and** best by `p0loss` / `pacc1` | `t9-s28711040-d3032547` | `4cbedf24ac86f97f1d15ec69706161e7ac98c3f3a2fddadb543d40bea897f49c` |
| c14 arm-A / arm-B challenger | `t9-s27212800-d2664932` | `d207dfb02769ac75a42b590ee0373f24ab6b4d8018b3e434ffad639b5b014626` |
| c14 arm-A baseline (former loss record) | `t9-s20919936-d1053205` | `c58932380ae6a188b52513c6ab06569d932d0d8ac9da5037b7ab6030a4e001f0` |
| frozen first accepted net | `t9-s143744-d157367` | `859c58d6785e5efdc3c40fb24400e3f5f56afca247009d2f1e94d35a8b4ac5d8` |

`t9-s28711040-d3032547` is the net to use: `p0loss` 1.468345, `pacc1` 0.546604,
both the best of all 93 exports. Ranked by raw `vloss` alone the minimum falls on
an early, far weaker net (`t9-s1762560-d595534`, `vloss` 0.569050 but `p0loss`
2.734) — raw `vloss` is not a strength ranking. See `status_log.txt`, the
`STOPPED BY HUMAN 2026-09-06` block, section 4.

### What is not in the checkpoint

The venv, the CUDA build tree and the compiled `katago` binary — all rebuildable
from `codes/env/env_build.sbatch` plus `code_snapshot/env/*.diff`, and the
binary's sha256 is recorded so a rebuild can be checked against what ran.
`runs/p1/scripts/dated/` (56 MB) — rebuildable from the tag, with the
non-reproducible parts saved in `code_snapshot/link2_archive/`.
`models_extra/`, `torchmodels_toexport{,_extra}/`, `shufflescratch/` — all empty
at the stop.

### Resuming from it

`README.md` § 7 in the checkpoint directory is the procedure. In short: restore
`p1/` into `runs/p1`, rebuild the environment if scratch was cleared, `rm
runs/p1/STOP`, run the compute-policy check, then `sbatch
--partition=b200,l40s codes/loop/loop.sbatch`. The loop resumes from
`.cycles_completed` (249) and the newest directory in `models/`; the trainer
continues from `train/t9/checkpoint.ckpt`, 239 744 samples past the last export.
Note that on the wrapper version that ran here, a clean `STOP` exit does **not**
cancel the queued successor — cancel it by hand if the chain should not extend.
