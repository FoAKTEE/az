# Implementation plan — Python · mission `ktg-train` (paper_arxiv-1902.10565)

Partitioned by `logic.md` DAG node. **CODE-FIRST**: the v1.18.2 mirror
`ref-code/lightvector-KataGo/` @ `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4` is the source of
truth; every `path:line` below is relative to that mirror unless it starts with `codes/`
(= `results/ktg/paper_1902.10565/codes/`) or `results/`. The mirror is **read-only**: mission
code is configs + wrapper scripts only. Nothing here has been executed.

Design constants in force (fixed upstream of this plan, not re-decided here): single node;
1 GPU (`b200`, `b300` reserved); ≤24 CPUs; 3-day walltime + self-resubmit; 9x9-only
(`bSizes=9`, `bSizeRelProbs=1`, `allowRectangleProb=0`, `dataBoardLen=9`, `-pos-len 9`);
shuffle `-num-processes 8`; train `OMP_NUM_THREADS=4`; smoke net `b5c48h3tfr`, scale-up
`b7c96h3tfrs`/`b8c96h3tfrs`; exporter is `python/export_model_pytorch.py`, never
`python/export_model.py`; `USEGATING=1`; scratch cap 200 GB on
`BASEDIR=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/loop`; ≤6 longterm checkpoints.

Every job launch is preceded by
`bash "$POLICY_CHECK" --gpus 1 --cpus 24 --partition b200`
(exit 0 required; `check.sh:8-9`).

---

## tiny_model_export_smoke

Predecessors: `env_build`, `transformer_trunk_b5c48h3tfr`, `cfg_9x9_override`.

| item | value |
|---|---|
| file to create | `codes/eval/check_export_blocks.py` |
| upstream entry point | `python/export_model_pytorch.py:34-42` (CLI), `:57-58` (exactly one of `-checkpoint` / `-export-random-initialized-model`), `:120-122` (writes `<prefix>.bin`), `:521-522` (`writeln("trunk")`, `writeln(len(model.blocks))`), `write_block` `:469-504` |
| block-kind tokens it scans for | `ordinary_block` `:472`, `gpool_block` `:479`, `nested_bottleneck_block` `:483`/`:496`, `transformer_attention_block` `:420`, `transformer_ffn_block` `:457` |
| C++ acceptor it mirrors | `cpp/neuralnet/desc.cpp:1521` (`transformer_attention_block`), `:1542` (`transformer_ffn_block`), `:1557` (`throw ... unknown block kind`) |
| expected counts | `b5c48h3tfr` = 10 blocks: 5 `attnrope` + 5 `ffng` (`python/katago/train/modelconfigs.py:999`) → 5 attention + 5 ffn, 0 of every other kind |
| script behaviour | open `.bin` or `.bin.gz` as bytes; locate `b"trunk\n"`; read the following ASCII line as `N`; count each kind token; exit 0 iff `N` and the per-kind counts match the `-model-kind` argument, else exit 1 |
| verification command | `python codes/eval/check_export_blocks.py --model $R/runtime/smoke/model-b5c48h3tfr/model.bin.gz --model-kind b5c48h3tfr` then `katago benchmark -model <bin.gz> -config codes/cfg/selfplay_9x9.cfg -v 80 -t 1 -boardsize 9` (`cpp/command/benchmark.cpp:199-206` for `-boardsize`) |
| metric + tolerance | block counts exactly (10, 5, 5, 0, 0, 0); benchmark visits/s > 0; `desc.cpp:1557` never fires |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/tiny_model_export_smoke/` |

`[OPEN] block-scan-false-positive` — the scan runs over the whole byte stream, `@BIN@` float
payloads included (`export_model_pytorch.py:224-226`); a kind token appearing inside binary
float data is not excluded by construction. Closes when the scanner walks blocks sequentially
from `trunk\n` instead of counting occurrences, or when a control export of a non-tf net
(e.g. an `ordinary_block` net) shows zero cross-contamination.

`[OPEN] smoke-model-mismatch` — `codes/env/env_build.sbatch:32` sets `MODEL_KIND=b7c96h3tfrs`,
but the design fixes the smoke net at `b5c48h3tfr`. Closes when this node's own export is run
at `b5c48h3tfr` (the env job's `b7c96h3tfrs` export stays as an extra scale-up probe).

---

## shuffle_stage

Predecessors: `selfplay_stage`, `training_window_shuffle`, `data_format_pos_len`.

| item | value |
|---|---|
| file to create | none — upstream `python/selfplay/shuffle.sh` is used unchanged (all window flags are pass-through, `:53`, `:72`, `:89`) |
| upstream entry points | `python/selfplay/shuffle.sh:42-54` (`SKIP_VALIDATE=1` branch) → `python/shuffle.py`; fixed flags `-expand-window-per-row 0.4` `:44`, `-taper-window-exponent 0.65` `:45`, `-approx-rows-per-out-file 70000` `:48`, `-num-processes` `:49`, `-keep-target-rows 20000000` `:50` (overridden by the loop) |
| loop-supplied flags | `-min-rows $SHUFFLE_MINROWS`, `-keep-target-rows $SHUFFLE_KEEPROWS`, `-taper-window-scale $TAPER_WINDOW_SCALE` (`python/selfplay/synchronous_loop.sh:105`) |
| thread budget | `-num-processes 8` (`shuffle.py:791` requires it; `synchronous_loop.sh:58`) → ≤8 processes, inside the 24-CPU cap |
| output contract | `shuffleddata/<ts>.tmp/train/data<b>_<i>.npz` + `<out-dir>.json` row range (`shuffle.py:1330-1335`), renamed to `shuffleddata/<ts>` at `shuffle.sh:105`; refuses a non-empty out-dir (`shuffle.py:1079-1083`) |
| verification command | `python codes/eval/rows_per_game.py --basedir $BASEDIR` (below) then one `train_9x9.sh` epoch |
| metric + tolerance | shuffle exits 0; ≥1 `data*.npz` written; `python/katago/train/data_processing_pytorch.py:91` shape assert passes at `-pos-len 9`; npz uncompressed row size = 2145 B at posLen 9 (`cpp/dataio/trainingwrite.cpp:292-299`; 19-reference `shuffle.py:39-40`) |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/shuffle_stage/` |

`[OPEN] shuffle-window-alpha` — `shuffle.sh:44-45` hard-codes `-expand-window-per-row 0.4` and
`-taper-window-exponent 0.65`; neither is 9x9-derived. Closes when a measured rows/game feeds a
recorded choice, or when the defaults are accepted with the measurement on record.

---

## train_stage

Predecessors: `shuffle_stage`, `loss_targets_metrics`, `transformer_trunk_b5c48h3tfr`,
`train_resume_semantics`, `train_optimizer_schedule`.

| item | value |
|---|---|
| file to create | `codes/loop/train_9x9.sh` — mission copy of `python/selfplay/train.sh` (upstream `:88` hard-codes `-pos-len 19`, so the mission owns its own wrapper) |
| upstream entry point | `python/train.py`; flag block mirrored from `train.sh:83-93` |
| exact flag list | `-traindir $BASEDIR/train/$TRAININGNAME` (`train.py:69`) · `-latestdatadir $BASEDIR/shuffleddata/` (`:71`) · `-exportdir $BASEDIR/torchmodels_toexport` (`:72`; subdir choice `train.sh:66-69`) · `-exportprefix $TRAININGNAME` (`:73`) · **`-pos-len 9`** (`:79`, required) · `-batch-size $BATCHSIZE` (`:80`, required) · `-model-kind $MODELKIND` (`:82`; ignored on resume, `train.py:850`) · then the loop's `-samples-per-epoch` (`:81`) · `-swa-period-samples` (`:95`) · `-quit-if-no-data` (`:130`) · `-stop-when-train-bucket-limited` (`:124`) · `-no-repeat-files` (`:129`) · `-max-train-bucket-per-new-data` (`:121`) · `-max-train-bucket-size` (`:122`) |
| env the wrapper exports | `OMP_NUM_THREADS=4`, `MKL_NUM_THREADS=4`; `-data-prefetch-depth` left at its default 1 (`train.py:126`) — obligation `o11_torch_threads_cap` |
| resume contract | `train.py:573-574` / `:780` (`checkpoint.ckpt` probe) → `:796` (load); 4 short-term ckpts (`:578`, `:614-622`); `model.ckpt` per `epochs_per_export` (default 1, `:438-439`, `:1845-1861`); `longterm_checkpoints/<ts>.ckpt` every 12 h (`:1884-1889`) |
| metrics file | `train/<name>/metrics_train.json` (`train.py:1350`), JSON-lines; keys are the `_sum` names with the suffix stripped (`python/katago/train/metrics_logging.py:31-33`), so the policy loss is `p0loss` (`metrics_pytorch.py:893`) |
| verification command | `grep -c -- "-pos-len 19" codes/loop/train_9x9.sh` = 0; run one cycle; `python -c` over `metrics_train.json` comparing `p0loss` |
| metric + tolerance | all logged terms finite (no `NONFINITE VALUE OF METRIC` line, `metrics_logging.py:52`); `p0loss` at epoch 10 < `p0loss` at epoch 1 (claim `c12_loss_decreases`); process thread count ≤24 (`ps -o nlwp`) |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/train_stage/` |

`[OPEN] lr-scale-9x9` — `train.py:1094` per-sample LR `3e-5 * lr_scale * sqrt(batch/256)` with a
9-step warmup to 2M samples (`:1059-1079`); no 9x9-specific `-lr-scale` is derived. Closes when
the first 10 epochs' `p0loss` curve is on record and a scale is chosen or the default kept.

---

## export_stage

Predecessors: `train_stage`, `tiny_model_export_smoke`.

| item | value |
|---|---|
| file to create | `codes/loop/export_model_for_selfplay_9x9.sh` — mission copy of `python/selfplay/export_model_for_selfplay.sh` with two changes only |
| change 1 (kill window) | move `rm -r "$SRC"` (upstream `:89`) to **after** `mv "$TMPDST" "$TARGET"` (upstream `:108`) — obligation `o09_export_kill_window`; skip markers read at `:54-56` |
| change 2 (guard) | capture the exporter's exit code; a non-zero exit from the `2.5e4` attention-logit bound (`export_model_pytorch.py:42-43`, raised at `:105-117`; bound computed `model_pytorch.py:3010`) is written to the error ledger and fails the cycle loudly instead of silently — obligation `o15_attn_logit_export_guard` |
| upstream entry points kept verbatim | `export_model_pytorch.py` invocation `:77-82` (`-checkpoint $SRC/model.ckpt`, `-export-dir`, `-model-name "$NAMEPREFIX-$NAME"`, `-filename-prefix model`, `-use-swa`); `clean_checkpoint.py` `:84-86`; `gzip "$TMPDST"/model.bin` `:90`; `list_by_mtime.py` `:43`; gating branch `:115-120` |
| loader on the C++ side | `cpp/dataio/loadmodel.cpp:58` `findLatestModel` (recursive `:65`, suffixes `:20-25`/`:67`, newest by mtime `:68-73`) |
| verification command | `grep -rn 'export_model\.py' codes/` returns nothing (obligation `o08_exporter_name`); `python codes/eval/check_export_blocks.py --model $BASEDIR/modelstobetested/<name>/model.bin.gz --model-kind b5c48h3tfr`; `katago benchmark` on the produced net |
| metric + tolerance | `modelstobetested/<name>/` contains `model.bin.gz` + `model.ckpt` + `metadata.json` (`export_model_pytorch.py:682`); no `*.exported` dir survives the cycle; block counts as in `tiny_model_export_smoke` |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/export_stage/` |

---

## data_budget

Predecessors: `synchronous_loop_smoke`, `data_format_pos_len`.

| item | value |
|---|---|
| files to create | `codes/eval/rows_per_game.py`, `codes/eval/prune_checkpoints.py` |
| `rows_per_game.py` inputs | `$BASEDIR/selfplay/<model>/tdata/*.npz` and `.../sgfs/*.sgfs` (`cpp/command/selfplay.cpp:176-178,186-188,224`; `trainingwrite.cpp:1092`) |
| rows | sum of `npz["binaryInputNCHWPacked"].shape[0]`; the six required keys are asserted at `python/shuffle.py:52-60` |
| games | line count of each `.sgfs` file — one SGF per line (`python/summarize_sgfs.py:38-41`) |
| bytes/row | on-disk = `sum(os.path.getsize(npz)) / rows`; the uncompressed reference is 2145 B at posLen 9 = 1653 required + 492 qvalue (`trainingwrite.cpp:292-299`, packing `:288`,`:314-334`), 19-reference constants at `shuffle.py:39-40`, compressed fraction 0.12 at `shuffle.py:47` |
| `prune_checkpoints.py` | keeps the newest 6 `*.ckpt` in `train/<name>/longterm_checkpoints/` — `train.py:1884-1889` writes one every 12 h and **never prunes** (obligation `o04_scratch_budget`); short-term rotation is already capped at 4 by `train.py:578` |
| verification command | `python codes/eval/rows_per_game.py --basedir $BASEDIR`; `python codes/eval/prune_checkpoints.py --traindir $BASEDIR/train/<name> --keep 6 && ls $BASEDIR/train/<name>/longterm_checkpoints/*.ckpt \| wc -l` |
| metric + tolerance | rows/game ∈ [12, 35] (expected ≈22, claim `c10_rows_per_game`); on-disk bytes/game ≤ 10 KB (expected ≈5.7 KB); longterm ckpt count ≤6; `du -sb $BASEDIR` < 2.0e11 (enforced in `codes/loop/loop.sbatch`, see the bash plan) |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/data_budget/` |

`[OPEN] tdata-retention` — nothing upstream prunes `selfplay/<model>/tdata|sgfs`; growth is
monotonic. Closes when a retention rule (keep last K cycles / K models) is chosen and coded.

---

## eval_improvement (Python half — analysis only; the match itself is in the C++ plan)

Predecessors: `gatekeeper_stage`.

| item | value |
|---|---|
| file to create | `codes/eval/match_winrate.py` |
| input | the `katago match -sgf-output-dir` tree (`cpp/command/match.cpp:43`, `:54`) |
| parsing | same `.sgfs` convention as `summarize_sgfs.py:38-41`; per-game `PB[]`/`PW[]` give the seat, `RE[]` the result; both colors are played because `match.cpp:104-105` emplaces `(i,j)` **and** `(j,i)` each round |
| statistic | candidate win rate `p̂` over all 400 decided games + Wilson 95% CI; `SE = sqrt(0.25/400) = 0.025` at the null |
| cross-check | `python summarize_sgfs.py <dir> -elo-prior-games N` (`python/summarize_sgfs.py:89-107`) via `katago/utils/elo.py` — reported alongside, not as the primary statistic |
| metric + tolerance | pass iff `p̂ ≥ 0.60` **and** the Wilson lower bound > 0.5 (claim `c14_elo_vs_first_net`, ≈ +70 Elo); the gatekeeper half of the criterion (≥2 acceptances) is counted from `models/` subdirs |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/eval_improvement/` |

`[OPEN] draw-handling` — `cpp/command/gatekeeper.cpp:138` counts draws as half for gating;
`match.cpp` has no equivalent tally in the lines read. Closes when the draw/no-result convention
used by `match_winrate.py` is fixed against the SGF `RE[]` values actually produced at komi 7
(integer komi ⇒ draws are possible).

---

## scale_up (Python half)

Predecessors: `eval_improvement`, `data_budget`, `transformer_trunk_b5c48h3tfr`,
`head_gpool_degeneracy_9x9`.

| item | value |
|---|---|
| files touched | `codes/loop/train_9x9.sh` (`MODELKIND` argument only), `codes/eval/check_export_blocks.py` (expected-count table) |
| model configs | `b7c96h3tfrs` = 7 × [`attnrope`, `ffnsg`] → 14 blocks (`modelconfigs.py:1008-1028`, block list `:1021`); `b8c96h3tfrs` = 8 × → 16 blocks (`:1057-1077`, `:1070`); both registered at `modelconfigs.py:1887`, `:1889` |
| why they still export | `ffnsg` (swiglu) is written under the same `transformer_ffn_block` kind with a `use_swiglu` flag (`export_model_pytorch.py:457`, `:461`); no new C++ kind is needed (`desc.cpp:1542`) |
| 2-GPU split | `-multi-gpus` (`train.py:110`) is **not** used; instead train pins one device and selfplay the other via the cfg's `cudaDeviceToUse*` keys (`selfplay1_maxsize9.cfg:127-131`) — see the C++ plan |
| verification command | `python codes/eval/check_export_blocks.py --model <bin.gz> --model-kind b7c96h3tfrs` (expect 14 / 7 / 7 / 0) plus a full loop cycle |
| metric + tolerance | export block counts exact; selfplay games/hour within 2× of the smoke config (claim `c16_scale_up_within_caps`); CPU total still ≤24 |
| evidence lands at | `results/ktg/paper_1902.10565/evidence/scale_up/` |

---

## Code-reading nodes — no code, verification only

These four nodes produce **no** file under `codes/`. Their obligation is to confirm the cited
constant in the mirror at run time and record the observation; nothing is patched.

| node | what is verified | anchor to re-check | verification command | tolerance |
|---|---|---|---|---|
| `loss_targets_metrics` | the loss weights the mission actually trains under are the coded ones, not the paper's | `metrics_pytorch.py:856-882` (assembly), `:84-88` (opp-policy 0.15), `:127`/`:136` (value 1.20), `:157-161` (ownership `1.5/b²`), `:273`/`:267` (score pdf/cdf 0.02); flag multipliers `train.py:143` (soft 8.0), `:146` (value 0.6), `:147` (td 0.6×3) | one training epoch's `metrics_train.json` line contains every key of `metrics_pytorch.py:892-923`, and `qwlloss`/`qscloss` are exactly 0 (`metrics_pytorch.py:838-841`, no `predict_q_values` in `b5c48h3tfr`) | every listed key present; q losses ≡ 0 |
| `train_optimizer_schedule` | defaults are SGD+momentum 0.9 with Lookahead k=6 α=0.5, not AdamW | `train.py:844`/`:942` (SGD), `:97-98` (lookahead), `:1094` (3e-5 per-sample), `:1141` (`sqrt(batch·world/256)`), `:1059-1079` (warmup), `:87` (head lr 0.5) | the train log's optimizer name line (`train.py:374`) reads SGD; no `-use-adamw`/`-use-muon` appears in `codes/loop/train_9x9.sh` | exact string match; grep count 0 |
| `transformer_trunk_b5c48h3tfr` | the trunk is 5×(attnrope, ffng), version 17, RoPE θ=100 non-learnable, `seq_len == pos_len²` | `modelconfigs.py:986-1006` (`:999` block list), `model_pytorch.py:2167-2171` (θ, tables non-persistent), `:1284-1285` (`seq_len == pos_len²`), `:2108`/`:2112` (`q_head_dim` 16, `%4==0`), `:3231-3239` (`attnrope`), `:3278-3285` (`ffng`) | the smoke export's block counts (10/5/5) from `check_export_blocks.py`; `assert rope_theta > pos_len*2` (`:2168`) holds at 100 > 18 | counts exact; no assert fires |
| `head_gpool_degeneracy_9x9` | trunk has no gpool; policy/value heads do, and at strict 9x9 their pooled channels are collinear | `model_pytorch.py:3157-3160` (trunk gpool only for `*gpool` kinds), `:492-518` (`KataGPool`), `:521-543` (`KataValueHeadGPool`), `:505`/`:534` (offset 14.0), `:540` (σ²/100 = 0.1), `:2647`/`:2711`/`:2745`/`:2855` (heads) | at `mask_sum_hw = 81`: assert `pool2 == -0.5·pool1` (policy and value) and `pool3 == 0.15·pool1` (value) numerically on one forward pass at `pos_len=9` | relative error < 1e-5; **constants are not changed** (would break C++ backend compatibility) |

`[OPEN] gpool-recenter` — whether re-centering the 14.0/σ² constants for 9x9 is worth a C++
fork is not evaluated (carried from `audit_paper_code_map.md`). Closes only if a measured head
capacity loss justifies it; deferred as `[FUTURE]`.

---
`POLICY_CHECK` = the value of `compute.policyCheck` in `mission.json` (the compute-budget skill check script), resolved relative to the `az` root.
