# Validation record — `arxiv-1902.10565::synchronous_loop_smoke`, probe groups (attempt 2, job 299259)

Role: cross-model validator (refuter, then judge). Date: 2026-09-04, login node, CPU only; no job submitted
(compute policy: the script named by `mission.json` `compute.policyCheck`; no allocation was requested).
Scope: the groups of `candidate_rows.json` that depend on attempt-2 job 299259 (worker commit 98d6c42) —
`r_smoke_probe_search` (proposed **refuted** on the full_frac band), `r_smoke_probe_training` (proposed empirical
4/4), the c10 amendment, the o37 transition, and the transitions for S7 / S11 / S12 (c04, c05, c15, o02). The three
core groups admitted from attempt 1 (commit 0fab404, `validation_core.md`) were not re-appended.

`sacct -j 299259 -X -n -o JobID,State,ExitCode,Elapsed,NodeList` → `299259 FAILED 1:0 00:05:06 gb207`
(05:53:37 → 05:58:43 local); legs `A=skipped B=skipped C=skipped D1=1 D2=0 E=1`, overall 1 (`attempt_299259.json`).

## Verdicts

| candidate | verdict | status landed | row_hash |
|---|---|---|---|
| result `r_smoke_probe_training` | ADMIT | empirical | `52f58dea8c5a31a2dde77412deaf15f27c1a1b5c970994cea45b28561a30d258` |
| result `r_smoke_probe_search` as proposed (band **refuted**) | **REJECT** — gate 3, evidence type vs claim: the 0.342 is an instrument artefact, not a measurement of the full-search fraction | — | — |
| result `r_smoke_probe_search` re-scoped: (b) rows/game, (c) 9x9-only, (d) random-baseline gate hold; (a) **unchecked** | ADMIT | empirical | `e9b4ae38f33f4bb946d0a6e34162d4bf5770f36500d2d36fcd8948238f093f9b` |
| result `r_smoke_full_frac_binning` (validator counterexample; the band is neither refuted nor admitted) | recorded | unchecked | `2dd72bb136359415010f1e805da5f0bcc89535f9c2e333fc7f7a282743608323` |
| result `r_smoke_c10_bytes_per_game` (c10 byte conjunct) | ADMIT as refutation | refuted | `0eb89b01fef1695c1b13caf072a796b9b21469bba1064f8334a0c591e55b1af4` |
| knowledge `transformer_trunk_b7c96h3tfrs` | promote preliminary → solid (seq 4) | solid | `ebebbddad785f7d7fe418cfdc3aefd5fc0036efad35aaf69cebeb50133da9ef0` |
| knowledge `head_gpool_degeneracy_9x9` | promote → solid (seq 5; predecessor solid) | solid | `8f7dd09484f75870eabaeab5758d7f5d59126621a823043db4e701ced973f005` |
| knowledge `data_format_pos_len` | promote → solid (seq 4; compression factor corrected) | solid | `35c5250113a088d67b70c7d6552559fc565afdfab5b44ddad72a375db53ebb80` |
| knowledge `train_resume_semantics` | promote → solid (seq 4) | solid | `044166f67dee5b65457f42f6a2d80648e0896897cc1d3246a2e41f3b52046aaa` |
| knowledge `synchronous_loop_smoke` seq 4 (attempt-2 record, o37 target) | appended | preliminary | `97ef37060f4a968249e6068b8477ba146186368b28b633e4ac239350c5e649f1` |
| c05 | admitted on `r_smoke_probe_training` | | `1f8e4281df0e9a51796d3ec8365eca91d1148d24b8e5fa14264ce66bef9f36f9` |
| c04 | re-admitted on `r_smoke_probe_search` (real-net games) | | `28306d3945984d7d1b1b4e5a914de97a2f322566058ccc3a73df00ecd530cd46` |
| c10 | refuted as written on `r_smoke_c10_bytes_per_game`; statement not re-tuned | | `28b7743e6bb379ca6dd965444f8bceebf76de42db67a5c392a9e7d70c12be67b` |
| c15 | in_progress (training half done; search half 3/4, (a) unchecked) | | `9d87a67841170b955d0abbb5545acef4cf32ae86965510a97046066efcc12f1f` |
| o02 | stays open (measurement half settled; wiring half with shuffle_stage) | | `ad2de7600eacef917b54bf98a6fc7ca681142b97497c6247f6dc9c39af6b9fcd` |
| o37 | discharged by knowledge `arxiv-1902.10565::synchronous_loop_smoke` | | `54d259f3b6ef3460d4ca337a1e6a73e86cb75500a374e56f70b3e9b6e3f87a4e` |
| o38 (new) | open — corrected full_frac discriminator, re-propose (a) from existing data | | `f1475e88ba04e5dc96585de324a2f3d02cbe45158a93418372f638a3bf88a399` |
| error ledger | fail row for the rejected band verdict (iteration 5, stage validation) | | `8bcb8a095995d0abcc922f99e83b04c2c8cef2aed5410de239bc15489bf07e5f` |

No `admission_flags` on any appended row; every gate re-executed its `verification.command` with exit 0.
Not promoted: `loss_targets_metrics` (partial by design: scorebelief_len 282 and finite terms only),
`train_optimizer_schedule` (only its resume half executed), every search-side node (`playout_cap_randomization`
waits on o38; `selfplay_search_params`, `game_randomization_9x9`, `root_explore_and_target_pruning`,
`score_utility_search`, `gating_rule` have no packet criterion met by 3/4).

## Refutation attempts and what they showed

1. **`audit_smoke.py --tag 299259` re-run into a temporary directory** (run directory read-only). All 509 leaf keys
   of `audit-299259.json` reproduce except the five output-path keys; `nlwp_max-299259.txt` and
   `rows_per_game-299259.txt` byte-identical; `throughput_smoke-299259.json` identical apart from `evidence_files`.
   Verbatim: `S7 FULL_FRAC = 0.34413965087281795 band [0.20, 0.30]`, `S8 ROWS_PER_GAME real = 31.95 over 20 games;
   random = 31.675 over 80 games`, `S8 BYTES_PER_GAME = 11206.7 B = 10.944 KiB over 80 loop games; c10 bound
   10 KiB`, `S9 NLWP_MAX per stage = {'selfplay': 25, 'train': 14} (cpus_per_task 24)`, `S11 probe_train pass =
   True trunk_gpool_count = 0`, `S12 probe_resume pass = True 4992 -> 14976`, `S13 peak VRAM = 6112 MiB gpu util
   max/mean = 80/28.2 %`, `ps samples from .../ps_samples-299259.tsv (1287 rows)`. Only tagged names were written.

2. **full_frac recomputed from the raw data — the band verdict is an instrument artefact.** The probe script deletes
   its stdout capture, but the engine's own log file in the selfplay output dir survives for the fork-free 60-game
   run (`runs/smoke_probe/search/selfplay/log20260904-055425-11022754EF29BF2B.log`, 11985614 B — the size the
   transcript records for the deleted capture; sha256 `59e2574e…`). Its 7401 `Root visits:` lines: **100 × 4872,
   600 × 1862, and 667 values strictly between 100 and 600** (322 distinct). The run's sgfs carry a per-move `v=`
   annotation: 7401 moves over 60 games with the identical histogram. The probe's rule `> cheapSearchVisits`
   gives `(7401 − 4872)/7401 = 0.34171` — the candidate's number to the last digit; `== maxVisits` gives
   `1862/7401 = 0.25159`.
   *Mechanism (reference code):* a fresh cheap search stops at exactly 100 visits and a fresh full search at
   exactly 600 (`cpp/search/search.cpp:509,579-580` count the inherited root visits toward `maxVisits`); selfplay
   clears the tree before a full search (`cpp/program/play.cpp:1567` asserts `clearBotBeforeSearch` for
   `forSelfPlay`, `:1234` clears) but not before a cheap search when `cheapSearchTargetWeight <= 0`
   (`play.cpp:1147`), so a cheap search that inherits a subtree already holding ≥ 100 visits does no new playout
   and logs the inherited count. *Sharp prediction, tested per game:* a between value can only follow a 600 or
   another between value, never a 100, and never opens a game — **0 of 667 follow a 100, 533 follow a 600, 134 a
   between, 0 open a game**. Independent second run: the smoke loop's own 80 random-net games (different net,
   job 298712, `reduceVisits=true`) give `2311/9211 = 0.25090` at `v == 600` and 0 of 543 between values after a
   100. Evidence: `root_visits_hist-v299259.json` (both histograms, transition counts, source hashes).
   The worker's candidate mechanisms are all excluded: (b) *in-flight games* — `Total games: 78` is 60 games run
   plus 18 game threads that each did one `fetch_add` past `maxGamesTotal` and ran nothing
   (`cpp/command/selfplay.cpp:292-293`); the log has exactly 60 `Started` and 18 `terminating` lines, and 7401 log
   lines = 7401 sgf moves, so nothing beyond the 60 finished games is counted; (c) `sekiForkHackProb` only halves
   `cheapSearchProb` for six turns and cannot create a third visit value; reanalysis is off (`useReanalyze` absent,
   default false); side positions do not call `logSearch`. The fork test (0.34414 → 0.34171) is a fact about forks
   but answered the wrong question.
   *Consequence:* the proposed `refuted` status is wrong. The band is **unchecked**: not refuted, and not admitted
   either, because the task-file criterion is defined through the defective rule, the two 20-game rows cannot be
   re-binned (their logs, sgfs and npz were removed by the script's `rm -rf`), and the positive measurement is the
   worker's to re-propose (o38 — no allocation needed; the surviving 60-game data and the loop sgfs suffice). The
   validator's 0.25159 / 0.25090 are recorded as observations and propose no band.

3. **Kill/resume (S12), checkpoints re-read with the mission venv** (`torch.load(map_location='cpu', mmap=True)`,
   10 MB files, metadata only): `traindir/checkpoint.ckpt` global_step_samples 14976 / total_num_data_rows 5068;
   `checkpoint_prev0..3` 13728, 11232, 9984, 7488 / 5068; the eight `export/proberesume-s*/model.ckpt` from s2496
   to s14976 all 5068 rows and 825837 parameters. `train_phase1.log`: one `No preexisting checkpoint found`, one
   `Initializing new model!`, last `Global step: 4992 samples`; `train_phase2.log`: zero of either, first
   `Global step: 4992 samples`, then 6240 … 14976, `Exiting with code exit_code=0`. The transcript's phase-2
   command is byte-identical to phase 1 (`-pos-len 9 -model-kind b7c96h3tfrs -batch-size 32 -samples-per-epoch
   2048 -swa-period-samples 1024 -max-epochs-this-instance 6 -no-compile`). `probe_resume-299259.json` 6/6.

4. **S11 (assertions 1-3)**: the in-job run (`smoke-299259.txt` lines 131-158, `PROBE_TRAIN_9X9: PASS`) and the CPU
   re-run `probe_train_rerun_cpu-299259.json` agree on every number: 14 blocks `7 × [attnrope, ffnsg]`,
   trunk_gpool_count 0 (0 anywhere), 825837 parameters, `sqrt(81) − 14 = −5`, both residuals `0.000e+00`,
   `242 + 76 + 320 + 328 + 492 + 282 + 405 = 2145` B/row on the real 1221-row npz, scorebelief_len 282. The
   deletion of the in-job json was the probe's own `rm -rf` (worker-repaired); the values were never in doubt.

5. **c10 bytes/game recomputed**: `du -sb runs/smoke/selfplay/random/tdata` = 896536 B (433304 + 463232) over
   80 sgf lines (40 + 40) = 11206.7 B = **10.944 KiB/game**, 353.8 B/row over 2534 rows; the surviving real-net
   60-game probe npz is 741040 B over 2064 rows / 60 games = **12.06 KiB/game**, 359.0 B/row. Both exceed 10 KiB;
   rows/game 31.675 / 34.40 are inside [12, 35]. c10 refuted as written; the measured pair is on the result row and
   in c10's notes, no re-tuned bound (o24 / data_budget consume the measurements).

6. **Sampler scope (S9)**: `ps_samples-299259.tsv` in evidence is byte-identical to the run directory's; 1287 rows,
   all 7 columns; exactly five pids — 339236 and 340387 (selfplay, the two `probe_search_9x9.sh` runs of leg D1),
   343312 (train, **the transcript's own `phase1 pid = 343312`**), 345147 (a 1-thread wrapper) and 345148 (the
   phase-2 trainer); the first sample is 0.6 s after leg D1's start line. `sacct -a -N gb207` shows four other
   users' jobs resident (298847, 298859, 299237 started before ours; 294325 started 05:59:05, after our end); the
   sampler keeps only descendants of root pid 339140 by walking the ppid chain at each sweep
   (`stage_monitor.sh:71-94`), and the audit reports `foreign pids excluded: none`. S9's 25 is ours (real-net
   selfplay with a CUDA context), confirming attempt 1; o03 unchanged.

7. **o37 repairs**: `stage_monitor.sh` writes `ps_samples-<jobid>.tsv` / `gpu_samples-<jobid>.csv`;
   `audit_smoke.py --tag` writes only `<name>-<tag>.<ext>` (item 1 confirms: the temporary directory received only
   tagged names); `smoke_loop.sbatch:275` passes `--tag "$JOBID"`; the split of the mixed table is exact by column
   count. Discharged.

8. **Verification commands** of both candidate rows exit 0 from the az root and read only `*-299259.*` /
   `*-298712.*` files — but the search row's command asserted `0.32 < full_frac < 0.36` on all three rows, i.e. it
   would have gate-checked the artefact as a fact; the admitted row's command checks (b), (c), (d) only.

9. **Statuses**: the worker's `refuted` on the band would have entered a false refutation into the ledger — the
   refutation itself was refuted. `r_smoke_probe_training` empirical is honest (one GPU run, CPU regeneration of a
   deleted file disclosed). Knowledge promotions to `solid` are limited to nodes whose defining assertion executed
   with content-hashed evidence and whose predecessors are solid; unexecuted clauses are named in each summary.

## Findings that change what may be admitted later

- Any future search probe must retain the engine log or the sgfs (the `v=` field is the cheapest instrument) and
  identify a full search by `Root visits == maxVisits`; `audit_smoke.py` S7 must read the corrected key.
- `data_format_pos_len`'s earlier "compressed x0.12" (19x19 constants) is withdrawn: 9x9 measures 353.8 B/row =
  0.165 of 2145.
- `a07_moves_per_game_80` is superseded for rows/game by the measurements (31.7 random net, 32.0-34.4 real net at
  these smoke-scale nets).

## Remaining [OPEN]
o38 (corrected full_frac discriminator; re-propose (a) from existing data; `playout_cap_randomization` waits);
o03 (25 threads vs 24 declared, derive_cycle_knobs_9x9's joint decision); o24 (knobs from the measured rows/game
and bytes/game); o02 wiring half (shuffle_stage); `loss_targets_metrics` and `train_optimizer_schedule` remain
partial; the smoke node stays preliminary until S9 (o03) and S7 (o38) close and `data_budget` leaves hypothesis;
two-real-net gatekeeper threads and c13 (gatekeeper_stage).
