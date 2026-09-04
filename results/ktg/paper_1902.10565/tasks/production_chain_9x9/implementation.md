# Implementation — `production_chain_9x9`

## 0. Header

**Task ID:** `production_chain_9x9`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::selfplay_stage`, `::shuffle_stage`, `::train_stage`, `::export_stage`, `::gatekeeper_stage`, `::bootstrap_accepted_model`, `::verify_preemption_resume`, `::loop_failure_circuit_breaker`, `::measure_stage_throughput`, `::count_gatekeeper_acceptances`, `::match_latest_against_first`, `::eval_improvement`; production-log condition of `::data_budget`; obligations o03, o25 (walltime half), o39 (c), o40 (c), o11, o20, o15.
**Language:** bash / Slurm (ONE self-resubmitting chain, 1 GPU) + Python (login-node readers)
**Method class:** simulation (the first production self-play loop at the derived knobs) + empirical measurement
**Scheduling policy (wave 3):** `preliminary` predecessors are usable; `data_budget` (hypothesis, result `conditional`) and the two executed-proof nodes (`verify_preemption_resume`, `loop_failure_circuit_breaker`, hypothesis) are predecessors of `selfplay_stage` that THIS chain settles — cycle 1's guard log and link 1's walltime end are their evidence. Stage rows are therefore proposed at `preliminary` and promoted once those three close on the same data; `solid` still needs `solid` predecessors. `[BLOCKING]` before `sbatch`: `tasks/wave3_prelaunch_repairs` R1, R5, R6 admitted (o39 wiring, o02 wiring, monitor).

## 1. Claim

> The mission loop runs unattended at the derived knobs on one B200 across a chain of three 71.5 h links from a fresh `BASEDIR`, producing 9x9-only self-play, shuffle windows, checkpoints and exports; the first candidate exports at cycle 5 and is gated at cycle 6; at least one candidate is accepted by cycle 20 (c13); the walltime SIGTERM at each link end resumes into the queued successor without loss (c08, o25 walltime half); every real-net stage stays ≤ 32 OS threads (o03); the storage guard logs its triple every cycle under the cap (c11); and the rates at the production knobs are measured (c09, `measure_stage_throughput`) — the data on which the human decides scale-up.

## 2. Success Criterion

- **Needed evidence type:** `numerical_simulation` (stage nodes, c08), `empirical_measurement` (throughput, threads, storage, c13), `statistical_inference` (c14).
- **Done when:** the chain has ended (3 links or a recorded stop), every P-row below is either within tolerance or recorded as a finding with an error row, and the candidate rows are staged.
- **Paths:** `KTG_ROOT=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train`, `P1=$KTG_ROOT/runs/p1` (the ledger's twelve closing checks already name `runs/p1`; the brief's "prod1" is realised as this path), `L=$KTG_ROOT/logs/loop-<jobid>.log` per link, `EV=results/ktg/paper_1902.10565/evidence/p1`.
- **Verification commands and tolerances (login node, CPU; `python3` = system python unless the venv is named):**
  | # | metric | verification | tolerance | settles |
  |---|---|---|---|---|
  | P1 | selfplay 9x9-only, real-net trial, threads | `test $(grep -L 'SZ\[9\]' $P1/selfplay/*/sgfs/*.sgfs \| wc -l) -eq 0 && test $(cat $P1/selfplay/*/sgfs/*.sgfs \| wc -l) -ge 1000 && ls -d $P1/selfplay/t9-* && python3 codes/eval/throughput_report.py $P1 --out $EV/throughput.json --assert-nlwp-le 32` | exact; `nlwp_max` per stage ≤ 32 on real-net selfplay AND the two-real-net gatekeeper (first at ≈ cycle 9); games/h recorded | `selfplay_stage`, o03, o39 (c), c09 (rate half), c06 re-statement |
  | P2 | shuffle windows | ledger closing check (`shuffleddata/<latest>.json` exists, no `*.tmp`) `&& python3 codes/eval/check_pos_len_npz.py $P1/shuffleddata/<latest>/train && grep -c 'Final input rows to shuffle' $P1/logs/outshuffle.txt` | `CHECK_POS_LEN_NPZ: PASS`; cycle-1 window = 25 000 rows; windows non-decreasing after the first acceptance | `shuffle_stage`, `training_window_shuffle` (partial → executed), o21 stays open (flag not adopted) |
  | P3 | training | `python3 codes/eval/check_metrics.py $P1/train/t9/metrics_train.json --epochs 10 && ! grep -q 'not enough new data rows, terminating' $P1/train/t9/stdout.txt && test $(grep -c 'Initializing new model!' $P1/train/t9/stdout.txt) -eq 1` | all terms finite; `p0loss` at ≥ 200 k samples < at ≤ 20 k (c12); 0 bucket-starvation exits through cycle 20; exactly one initialisation over the whole chain | `train_stage`, c12, `loss_targets_metrics` (executed), o11 (train nlwp ≤ 32) |
  | P4 | exports | ledger closing check (`Done exporting:` ≥ 1, no `*.exported` orphan, no `export_model.py`) `&& bash codes/eval/chain_status.sh $P1 --first-export-cycle` | first export cycle `== 5` (o40 (c); `!= 5` re-opens o40, `> 8` aborts); at most one export per cycle; 0 exporter refusals (o15) | `export_stage`, o40 (c), o15 |
  | P5 | gatekeeper | ledger closing check (`Candidate (won\|lost) match` ≥ 1, gatekeepersgf `SZ[9]` only) `&& bash codes/eval/chain_status.sh $P1 --first-gate-cycle` | first decision at cycle 6 ± 1; every candidate ends in `models/` or `rejectedmodels/` exactly once; two-real-net gate `nlwp_max` ≤ 32 | `gatekeeper_stage`, `gating_rule` (decision conjunct), o03 two-net row |
  | P6 | frozen baseline | `python3 codes/eval/freeze_baseline.py $P1` then the ledger closing check (`manifest.json` sha256 of `models/<first>/model.bin.gz`) | exact; written the first time `models/` is non-empty, never rewritten | `bootstrap_accepted_model` |
  | P7 | acceptances | ledger closing check (`#models − 1 == 'Candidate won match' count ≥ 1`) | ≥ 1 by cycle 20 (c13 minimum), target ≥ 2 by link 3 | `count_gatekeeper_acceptances`, c13 |
  | P8 | throughput | `python3 codes/eval/throughput_report.py $P1 --out $EV/throughput.json && python3 -c "import json;d=json.load(open('$EV/throughput.json'));assert d['projected_cycle_h']<=60" && python3 codes/eval/check_knobs_9x9.py --throughput $EV/throughput.json --rows-file $EV/rows_per_game.txt` | keys: `selfplay_games_per_hour` (real net), `rows_per_game`, `bytes_per_row_on_disk`, `train_samples_per_second`, `per_phase_stage.cycle<N>/{gatekeeper,shuffle,selfplay,train}.elapsed_s`, `gpu_util_mean_pct` per stage, `peak_vram_mib`, `nlwp_max_per_stage`, `projected_cycle_h`; the knob check re-run PASSES or its FAIL is recorded for `scale_data_window` (never tuned here) | `measure_stage_throughput`, c09, data_budget calibration, o41 consumer |
  | P9 | walltime resume | `sacct -j <link1> -X -n -o State,Elapsed,End` = `TIMEOUT` at ≈ 2-23:30; `grep -c 'SIGTERM received -- scheduler termination' $L1` ≥ 1; `grep -c 'scheduler termination at walltime' $L1` = 1; `grep -c 'cancelling queued successor' $L1` = 0; `sacct -j <link2> -o Start` ≥ link-1 `End`; `cat $P1/.chain_depth` = 2, `.failcount` = 0; `grep -c 'Initializing new model!\|No preexisting checkpoint found' $L2` = 0; last `Global step` of link 1 ≤ first of link 2; npz count at link-2 start ≥ count in the last status snapshot of link 1; no `shuffleddata/*.tmp` selected (`train.py:1210`) and none left; no orphan `*.exported`; the stage the SIGTERM landed in (last stage echo before the trap line) recorded | exact; the mid-train conjunct of c08 holds iff at least one of the three link ends landed in `train` (P(none) ≈ 5 %); the mid-export conjunct is P9b | `verify_preemption_resume` (c08), `loop_failure_circuit_breaker` (classification half), o25 (walltime half), o31/o33 r1 |
  | P9b | export kill window (CPU) | on a throwaway BASEDIR with `runs/smoke/rejectedmodels/t9-s1216-d1221/model.ckpt` copied to `torchmodels_toexport/kw/model.ckpt`: `timeout -s KILL 2 bash codes/loop/export_model_for_selfplay_9x9.sh ktg9 <dir> 1`, then the same command uncut, then the wrapper's startup sweep | after the kill: source intact, no `modelstobetested/kw`; after the re-run: `modelstobetested/kw/{model.bin.gz,model.ckpt,metadata.json}` complete, no `kw.exported` left; a hand-made stale `x.exported` with no target is removed by the sweep | c08 mid-export conjunct, o09 executed |
  | P10 | storage | `grep -c '^== scratch_guard .*\[cycle [0-9]* pre-gatekeeper\] ==' $L` = cycles started in that link `&& grep -c 'scratch_guard: OK' $L` = same `&& test $(du -sb $KTG_ROOT \| cut -f1) -le 536870912000` | exact; each block carries the `du -sb`, `df -B1`, `quotas.py` lines; ≤ 21 GiB after link 1 (T3) | `data_budget` → preliminary, c11 → empirical |
  | P11 | latest vs first | ONE extra 1-GPU job (`codes/eval/match.sbatch`, ≤ 1 h) when P7 ≥ 1: `katago match -config codes/cfg/match_first_latest_9.cfg` (400 games, 9x9, komi 7, `maxVisits 150`, `numSearchThreads 1`, `numGameThreads 18`, both colour orderings via `MatchPairer`, `play.cpp:671-700`) → `summarize_sgfs.py`; `p = (W + 0.5 D)/N` | 400 sgf lines, all `SZ[9]`, 200/200 colour split; CI (95 %) excludes 0.5 required; `p ≥ 0.60` target | `match_latest_against_first`, c14 |
  | P12 | declaration | `python3 codes/eval/declare.py $KTG_ROOT/eval --require-acceptances 1 --ci 0.95 --target-p 0.60` | prints `improves` iff P7 ≥ 1 AND P11's CI excludes 0.5, else `not demonstrated`; reports samples trained vs the 2 M warm-up (`train.py:1074-1079`), GPU-hours (`sacct` Elapsed sum), net hashes | `eval_improvement` |
- **Open obligations before start:** o39 (R1), o02 (R5), R6 monitor — all in `wave3_prelaunch_repairs`; o25's breaker-trip conjunct is narrowed here (§ 12), not executed.
- **Reduction-to-baseline test:** NA

## 3. Motivation

Everything upstream is proven on tiny knobs; the mission's central task is the run itself. One chain at the derived knobs is the smallest allocation that settles twelve nodes and gives the human the three numbers a scale-up decision needs (acceptances, Elo vs the first net, cycle rate). The `data_budget` and executed-proof predecessors of `selfplay_stage` are closed by the chain's own first cycle and first link end, so waiting for them separately would cost a second GPU allocation and a second queue wait for no additional evidence.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| logic / DESIGN | `results/ktg/paper_1902.10565/decomposition/{logic.md,DESIGN.md}` | §1 thread budget, §2 P1 row and ramp, §4 idempotency table, §7 evaluation criterion, §8 R3/R4/R5/R12/R14/R16 |
| claims / obligations | `decomposition/{claims,obligations}.md` | c08, c09, c11, c12, c13, c14; o03, o11, o15, o20, o25, o39, o40 |
| knobs | `codes/loop/knobs_9x9.env`, `evidence/derive_cycle_knobs/{derivation,validation}.md` | the eleven values, the 3.11 h / 20.9 GiB projections, the § 2.7 ramp |
| wrapper | `codes/loop/loop.sbatch` (post-R1/R6), `synchronous_loop_9x9.sh` (post-R5), `evidence/loop_resume/validation_repair4.md` | chain semantics: afterany successor, finalize classes, `KTG_MAX_CHAIN`, STOP, `.failcount` |
| smoke | `evidence/smoke/{throughput_smoke-298712.json,throughput_smoke-299259.json,audit-299259.json}` | the rates the timeline below is derived from |

**Upstream task outputs:** `tasks/wave3_prelaunch_repairs` (R1–R6), `tasks/synchronous_loop_smoke` (`audit_smoke.py` parsers reused by `throughput_report.py`), `tasks/data_budget` (guard), `tasks/derive_cycle_knobs_9x9`.

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- Compute: exactly ONE `sbatch codes/loop/loop.sbatch` (it self-resubmits; `KTG_MAX_CHAIN=3` caps the chain at three links) plus, when P7 ≥ 1, ONE `codes/eval/match.sbatch` (1 GPU, ≤ 1 h). Before each: `bash <mission.json compute.policyCheck> --gpus 1 --cpus 32 --partition b200` exit 0 (with the chain running the match request shows `my_gpus(1) + 1 ≤ 4`). Nothing else on a GPU. Never a second chain, never a duplicate submission while a successor is `PENDING`.
- Pre-flight (login node, in this order; all must pass, transcript to `$EV/preflight.txt`): (1) `git status --porcelain -- results/ktg/paper_1902.10565/codes` empty and HEAD contains R1/R5/R6; (2) `bash -n` on the four `codes/loop/*.sh*` files; (3) `python3 codes/eval/check_knobs_9x9.py` exit 0; (4) the policy check above; (5) `python3 /apps/helpers/quotas.py` and `bash codes/data_budget/scratch_guard.sh --label preflight` exit 0; (6) `test ! -e $P1` (fresh run); (7) `KTG_STAGE_ONLY=1 bash codes/loop/synchronous_loop_9x9.sh ktg9 $KTG_ROOT/runs/p1_dryrun t9 b7c96h3tfrs 1` from `$KATAGO_SRC` after `source $KTG_ROOT/env.sh` exits 0 with the pos_len line, then `rm -rf $KTG_ROOT/runs/p1_dryrun`; (8) a fresh login shell with `env | grep -c '^KTG_\|^BASEDIR\|^OMP_\|^MKL_'` = 0 (o33 (d) clean-shell rule).
- Submission (the ONLY environment the chain inherits, by design of `--export=ALL`): `BASEDIR=$KTG_ROOT/runs/p1 KTG_MAX_CHAIN=3 KTG_MON_PS_INTERVAL=1 KTG_MON_GPU_INTERVAL=5 sbatch results/ktg/paper_1902.10565/codes/loop/loop.sbatch`; record the job id, `scontrol show job`, and the pre-flight in the `exp(chain,ktg)` commit.
- Monitoring is READ-ONLY on the login node (`codes/eval/chain_status.sh $P1`, ≤ 2 cores, no torch except checkpoint metadata reads at link boundaries): every 3 h for the first 24 h, then every 12 h, and at every link boundary; each run appends to `$EV/status_log.txt` and is the packet's WAL. Never `srun --overlap`, never attach to the node.
- No tuning: no knob, cfg, gating or search parameter changes while the chain runs. A finding is an error row plus escalation (§ 11), never a silent edit. `touch $P1/STOP` only on the human's instruction or a § 11 abort.
- Worker appends error rows only; result/claim/knowledge rows are staged in `$EV/candidate_rows.json` per link and admitted by a validator.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference code | `ref-code/lightvector-KataGo/` (`train.py:1074-1079,1206-1213,1442-1448`, `cpp/command/match.cpp:224-225`, `cpp/program/play.cpp:671-700`, `python/summarize_sgfs.py`) |
| Code output | `results/ktg/paper_1902.10565/codes/eval/{chain_status.sh,throughput_report.py,check_metrics.py,freeze_baseline.py,declare.py,match.sbatch}`, `codes/cfg/match_first_latest_9.cfg` |
| Evidence | `results/ktg/paper_1902.10565/evidence/p1/` (`preflight.txt`, `status_log.txt`, `throughput.json`, `rows_per_game.txt`, `sacct_chain.txt`, `link<N>_summary.json`, `candidate_rows.json`); copies of `$L` per link as `loop-<jobid>.txt` |
| Progress dir | `progress/paper_1902.10565/production_chain_9x9/` |
| Git branch | `main` (az) |
| `BASEDIR` / eval | `$KTG_ROOT/runs/p1` / `$KTG_ROOT/eval` |

## 7. Architecture

```text
codes/loop/loop.sbatch                 # the chain (post-R1/R6): 1 GPU, 32 CPUs, 120G, 2-23:30:00, b300-if-free/b200, afterany successor
codes/eval/chain_status.sh             # login-node reader: sacct of ktg-loop jobs, chain state files, cycles/exports/gate lines,
                                       #   bucket-starvation and no-data lines, last guard triple, du -sb, nlwp max per stage (tail of
                                       #   ps_samples-<jobid>.tsv), GPU util mean (tail of gpu_samples), last selfplay games/h;
                                       #   --first-export-cycle / --first-gate-cycle print one integer (cycles completed before the line)
codes/eval/throughput_report.py        # measure_stage_throughput: reuses audit_smoke.parse_monitor/sgfs_stats/npz_report over $P1;
                                       #   per-cycle stage timings from $L echo lines; emits every key check_knobs_9x9.py reads (o41)
codes/eval/check_metrics.py            # train_stage c12: metrics_train.json rows are per 100 batches; epoch k = row nearest 20000*k
codes/eval/freeze_baseline.py          # bootstrap_accepted_model: manifest.json {first_model, first_model_sha256, frozen_at}, write-once
codes/cfg/match_first_latest_9.cfg     # from cpp/configs/match_example.cfg: numBots 2, nnModelFile0 first / 1 latest, bSizes 9,
                                       #   allowRectangleProb 0, komiAuto false komiMean 7, maxVisits 150, numSearchThreads 1,
                                       #   numGameThreads 18, numGamesTotal 400, logSearchInfo false
codes/eval/match.sbatch                # 1 GPU b200, --cpus-per-task 32, --mem 32G, --time 01:00:00; runs the match then summarize_sgfs.py
codes/eval/declare.py                  # eval_improvement: reads manifest, gate log, match summary, sacct; prints the declaration
```

## 8. Phase Plan

### Phase 0 - `pre-flight and readers` (CPU, before and during the queue wait)
- **Nodes:** none closed; prerequisites of every P-row
- **Files:** `chain_status.sh`, `throughput_report.py`, `check_metrics.py`, `freeze_baseline.py` — each dry-run against `runs/smoke` (two cycles) before the chain produces data; `preflight.txt`
- **Test:** `throughput_report.py runs/smoke` reproduces `throughput_smoke-298712.json`'s `train_samples_per_second` 14.243 and `bytes_per_row_on_disk` 353.8; `check_metrics.py` on the smoke's 0-byte `metrics_train.json` exits non-zero with a clear message; pre-flight steps (1)–(8) exit 0.
- **Estimate:** `4.0` h + queue wait (5 min – 20 h, b200 `free_gpus=1/128` at planning time)

### Phase 1 - `link 1` (0 – 71.5 h of GPU time)
- **Nodes:** `selfplay_stage`, `shuffle_stage`, `train_stage`, `export_stage`, `gatekeeper_stage`, `bootstrap_accepted_model`, `data_budget` (P10), `count_gatekeeper_acceptances` (first reading)
- **Test:** P1–P8, P10 at the link end; the § 10 timeline checkpoints on the way.
- **Estimate:** `71.5` h wall

### Phase 2 - `links 2–3` (resume proof, acceptance statistics)
- **Nodes:** `verify_preemption_resume`, `loop_failure_circuit_breaker`, `measure_stage_throughput` (rates over ≥ 20 real-net cycles), `count_gatekeeper_acceptances`
- **Test:** P9 at each boundary (two boundaries = two executed resumes), P9b once (CPU), P7/P8 at link 3's end; `KTG_MAX_CHAIN=3` → link 3 logs `chain depth 3 >= 3 -- not resubmitting` and no fourth job exists in `sacct`.
- **Estimate:** `143` h wall + two queue waits

### Phase 3 - `match and declaration`
- **Nodes:** `match_latest_against_first`, `eval_improvement`
- **Test:** P11 (submitted at the end of link 1 if P7 ≥ 1 there, and again after link 3 against the then-latest net), P12; the human receives § 10's decision table.
- **Estimate:** `1.0` h GPU (per match) + `2.0` h CPU

## 9. Quick-Win Path

1. `Phase 0` — pre-flight (1)–(8), submit, record the job id.
2. `Phase 1` — at +6 h: `chain_status.sh` shows `cycles completed ≥ 5`, one `SAVING MODEL FOR EXPORT`, one `Candidate (won|lost) match` line.
3. **Smoke check:** `grep -c 'scratch_guard: OK' $L` equals the cycle count and `nlwp max` ≤ 32 on every stage seen so far.

## 10. First Test Parameters

| Parameter | Value | Notes / source |
|---|---|---|
| allocation | `--gres=gpu:1 --cpus-per-task=32 --mem=120G --time=2-23:30:00`, `b300` if free else `b200` | `loop.sbatch` post-R1; 2-23:30:00 is the admitted contract (a03) and the value K7's `walltime_seconds 257400` is computed at — "72 h" in this file means 71.5 h |
| chain depth | `KTG_MAX_CHAIN=3` (≈ 9 GPU-days) | link 1 alone reaches cycle 20 (≤ 51 h, § 10 timeline) and settles P1–P8/P10; links 2–3 give two executed resumes (P9) and ≥ 40 more cycles for acceptances and the match; a 4th link is the human's scale-up decision |
| knobs | `knobs_9x9.env`: 1000 games, 20 000/epoch, batch 128, reuse 8, SWA 10 000, MINROWS 25 000, cap 100 000, keep 120 000, taper 50 000, 5 epochs/export; 18 game threads | admitted `conditional`; sourced by the wrapper (R1) |
| model / loop args | `ktg9 $P1 t9 b7c96h3tfrs 1` | `USEGATING=1` always |
| monitor | `KTG_MON_PS_INTERVAL=1`, `KTG_MON_GPU_INTERVAL=5` | R6; ≈ 50 MB tsv per link |
| expected timeline (t0 = link-1 start) | cycles 1–5 random-net, ≈ 45–60 min each: selfplay 1000 games at 5569 games/h measured random-net (11 min; 22 min at the 0.5 derate), one 20 000-sample epoch at 14.243 samples/s (23 min), shuffle ≈ 2 min, no gate; **first export ≈ 4–5 h** (cycle 5), **first gate decision ≈ 5–6 h** (cycle 6); upper bounds at the all-real-net K7 rate of 3.11 h/cycle: 15.5 h / 18.6 h; cycle 20 ≤ 51 h; **link end at 71.5 h** (SIGTERM, successor starts at the next GPU slot); link 3 end ≈ 9 GPU-days + two queue waits | `throughput_smoke-298712.json` (random 5569.5 games/h, 14.243 samples/s), `-299259.json` (real net 2031.7 games/h), `derivation.txt` K7; `validation.md` § 2.7 ramp |
| storage | ≤ 21 GiB after link 1, ≤ 30 GiB after link 3 | T3; guard refuses at 480 GiB |
| match | 400 games, komi 7, `maxVisits 150`, 1 search thread, 18 game threads, ≈ 10–20 min on one B200 | DESIGN §7; gate at equal strength P(≥ 100/200) ≈ 0.53, hence the separate match |
| decision table for the human (end of link 3) | acceptances (P7), rejections and their scores, first-export/first-gate cycles, match `p` / CI / Elo (P11), samples trained vs 2 M warm-up, GPU-hours, cycle rate and GPU duty (P8), scratch used (P10) | the scale-up call (`scale_up`: b8c96h3tfrs fresh run) or a 4th b7 link is the human's; `eval_improvement` is only the declaration |

## 11. Risk Mitigation — abort criteria (escalate with data; never tune silently)

| Signal | Signature | Action |
|---|---|---|
| breaker trips / link fails | `.breaker_tripped`, `sacct` `FAILED`, `failcount now 3/3`, no successor | collect `$L`, error row (expected/observed/root_cause), escalate; do not `rm .failcount` without the human |
| storage stop | `STOP` written by the loop or wrapper, `scratch_guard exit 1/2` | escalate (group pool or cap); never bypass the guard |
| no export by cycle 8 | `SAVING MODEL FOR EXPORT` count 0 with `cycles completed ≥ 8` | o40 refuted; `touch STOP`, escalate with the train log's `Not enough data files` / `Export cycle counter` lines |
| bucket starvation (R14) | `not enough new data rows, terminating` in ≥ 3 consecutive cycles | escalate; `check_knobs_9x9.py --throughput $EV/throughput.json` output attached |
| no-data exit on a real-net cycle (R16) | `Not enough data files to fill a subepoch` at cycle ≥ 6 | escalate; window sizes from `outshuffle.txt` attached |
| gate never accepts by cycle 20 | `models/` empty with `cycles completed ≥ 20` | escalate with every `Candidate lost match, score …` line; do NOT touch `numGamesPerGating`, `maxVisits` or `-required-candidate-win-prop` |
| threads over the declaration | `nlwp max` > 32 on any stage | error row (o03 refuted at 32), escalate; never lower `numGameThreads` unilaterally |
| export refusal (R3, o15) | exporter exit ≠ 0, `attn` bound > 2.5e4 in `outexport.txt` | failure row; escalate (the loop dies each cycle → breaker) |
| queue | successor `PENDING` > 24 h | report only; never submit a duplicate |
| group scratch warn | `scratch_guard: WARNING group scratch free space` | notify the human at the next status |
| link ends other than `TIMEOUT` | `sacct` `CANCELLED`/`NODE_FAIL`/`OUT_OF_MEMORY` | successor continues (queued afterany); read `$L`'s finalize line, record the class for o25/o33 |

## 12. Current State

- `[SOLID]` The chain wrapper is admitted (`r_loop_resume_under_walltime_static`, existence_only) and the knobs are admitted (`r_cycle_knobs_9x9_derived`, conditional); the policy check passes at 32 CPUs (2026-09-04T06:43:18-04:00, `OK : request gpus=1 cpus=32 part=b200`); `free_gpus` b200 1/128, b300 0/8; group scratch 36.88 / 40.00 TB (92 %), mission root 7.4 GiB.
- `[BLOCKING]` `wave3_prelaunch_repairs` R1 (o39), R5 (o02 wiring), R6 (monitor) are not landed; without R6 the chain cannot settle o03 or c09 and without R1 the first real-net cycle repeats the declared-24/measured-25 defect.
- `[PRELIMINARY]` The timeline in § 10 is arithmetic on smoke-scale rates (100 real-net probe games, batch-32 training); P8 replaces it.
- `[OPEN]` o25 narrowed here, for the validator: a healthy chain proves the walltime classification (TIMEOUT + `scheduler termination` + successor kept + `.failcount` unchanged, P9) — the `r1` residual of o33 — but not a breaker trip under real `sbatch`; that conjunct is deferred `[FUTURE]` unless a failure occurs naturally (then its `sacct`/log records are the evidence), because a deliberate three-failure injection would spend three GPU allocations and three queue waits on a property already executed under shims.
- `[OPEN]` `data_budget` stays `hypothesis` until P10 (cycle 1); the stage rows name it as the hypothesis predecessor, as the smoke's did.
- `[OPEN]` o20 (TCMalloc): record selfplay `MaxRSS` per cycle from the monitor's rss column; rebuild only if it grows across cycles — a finding, not an action here. o21 (`-exclude-qvalues`): not adopted; stays open.
- `[HOLE]` No external 9x9 reference net; strength is relative to the run's own frozen first net (DESIGN §7).

## 13. Forbidden Actions

- Never submit anything but the one chain and the one match job; never `--gres=gpu:2`, never a partition outside `mission.json` `compute.partitions`; never resubmit while a successor is queued.
- Never edit `codes/loop/*`, `codes/cfg/*` or `knobs_9x9.env` while the chain runs; never override a knob in the submitting shell beyond `BASEDIR`, `KTG_MAX_CHAIN`, `KTG_MON_*`.
- Never `scancel` a link to manufacture a resume test; never `rm .failcount`/`.breaker_tripped`/`STOP` without the human.
- Never read c13 from a rejection, never promote a stage node from a single cycle, never report the § 10 estimates as measurements.
- Never run torch, `du` over the group pool, or anything above 2 cores on the login node; never attach to the compute node.

## 14. Promise Tag

- **Promise format:** `<promise>production_chain_9x9 LINKS ==3 AND FIRST_EXPORT_CYCLE ==5 AND ACCEPTANCES >=1 AND NLWP_MAX <=32 AND RESUME_LOSS ==0 AND GUARD_OK_PER_CYCLE AND MATCH_CI EXCLUDES 0.5</promise>`
- **Required in commit body:** the `exp(chain,ktg)` commit carries the job id, the pre-flight transcript and the policy check; each link's `diag(chain,ktg)` commit carries `sacct_chain.txt`, the P-row outputs, `status_log.txt`, evidence paths, claims/obligations touched, evidence types.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions: one `exp` commit at submission, one `diag` commit per link end and one per match; joint progress file `progress/paper_1902.10565/production_chain_9x9/progress.md`; `${RESEARCH_STATE}` § Training status gets the cycle count, exports, acceptances and the next expected event after every status run; `HUMAN_DIGEST.md` gets the § 10 decision table at link 3.

## 16. Termination Checklist

- [ ] Pre-flight transcript in `$EV/preflight.txt`; policy check pasted.
- [ ] Every P-row ran; each is within tolerance or has an error row and an escalation.
- [ ] Candidate rows staged per link; `data_budget` and the two executed-proof nodes proposed before the stage nodes.
- [ ] `sacct` shows exactly three `ktg-loop` links (or a recorded stop) and at most one match job.
- [ ] No silent scope expansion: no knob moved, no extra GPU job.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected (none planned).
