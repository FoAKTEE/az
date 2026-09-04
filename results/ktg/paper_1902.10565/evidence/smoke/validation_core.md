# Validation record — `arxiv-1902.10565::synchronous_loop_smoke`, core groups (job 298712)

Role: cross-model validator (refuter, then judge). Date: 2026-09-04, login node, CPU only; no job submitted.
Scope: the candidate groups in `candidate_rows.json` that do not depend on attempt-2 job 299259 —
`r_synchronous_loop_smoke`, the knowledge row for `synchronous_loop_smoke`, `r_smoke_threads_realnet`,
`r_smoke_throughput_tiny`, and the transitions tied to S1–S6, S8–S10, S13 (o30, c07, o19, c06, o03).
`r_smoke_probe_search`, `r_smoke_probe_training` and S7/S11/S12 (c04, c10, c05, c15, o02) are untouched.

## Verdicts

| candidate | verdict | status | row_hash |
|---|---|---|---|
| result `r_synchronous_loop_smoke` | ADMIT | empirical | `686b052f97d2f428247bb39d4842cf853e89ef4c903f691b6f0dfc76aa0e07ba` |
| knowledge `arxiv-1902.10565::synchronous_loop_smoke` | ADMIT | preliminary (seq 3) | `53a2fcd47d33d67c79efffe3c936af57f3bd3b4d3c9a4fd1476c2bb8f0f8d402` |
| result `r_smoke_threads_realnet` | ADMIT | refuted (c06 real-net clause) | `6e210ec384baad4a566a1c5f88431455ede4e914d1128e35d52a9b2d4cbe98e4` |
| result `r_smoke_throughput_tiny` | ADMIT | empirical | `9070dfb080837aade6d1a8e6e5f4399deec2d484142375ca81f70fe170588000` |
| o30 | discharged by `arxiv-1902.10565::cfg_9x9_override` (worker's in-allocation row, verified, not re-appended) | | `2d69b152274fd665811dac2323766e6a8eb8b62803bd53d79a2b4b50e8c59b4c` |
| c07 | admitted on `r_synchronous_loop_smoke`, wording narrowed | | `5a06f64f921727d4a3c9425de9dd2e0bd2edfe089127dda596427ec354673c9f` |
| o19 | discharged by `r_synchronous_loop_smoke` | | `601bb0cbc20f71d0cee988442ad8b73a42bd7160a742723afb5d2934df0c164b` |
| c06 | refuted on `r_smoke_threads_realnet` | | `f1a7c94c471726e43223f6812abd17a758e28984d56acfe025a9e50f93effe0f` |
| o03 | stays open (re-appended with the measurement) | | `d1f52bfffb791a32bc5a5298f516098f73fbb3ac8db9509dfdc890d32599ed78` |
| o37 (new) | open — sampler append + evidence overwrite defects | | `61ababfd1f7d23adbda0acbee880b09f515bc333133a7fddbf3c05308c2f363b` |

No `admission_flags` on any appended row; every gate re-executed its `verification.command` with exit 0.

## Refutation attempts and what they showed

1. **Re-run `audit_smoke.py` against the run directory** (`runs/smoke`, read-only). S1–S6 and S8 reproduce the
   snapshot `audit-298712.json` exactly: cycles 2; exported dirs `rejectedmodels/t9-s1216-d1221`,
   `modelstobetested/t9-s2528-d2534`; gated 1 (won 0 / lost 1); gate_random 1; sgf lines 80 + 156, sz_other 0,
   rectangular 0; row bytes 2145 on 2 raw + 2 shuffled npz (2534 rows each side); global_step_samples 1216 -> 2528;
   172 running-metrics terms, none non-finite; reinit in cycle-2 log 0. `rows_per_game.txt` byte-identical.
   S9/S13 did NOT reproduce from the live run directory — because attempt 2 (job 299259, started 09:53:37Z on the
   same node) was already appending 7-column rows to `monitor/ps_samples.tsv` and had replaced
   `markers/allocation.json`. Re-running on a scratch basedir (run-dir artifacts + the retained
   `ps_samples-298712.tsv`, `gpu_samples-298712.csv`, `allocation-298712.json`) regenerates `nlwp_max.txt`
   byte-identically and `throughput_smoke.json` identically except `basedir_bytes` (symlinked scratch layout) and
   the `probe_search` block (already overwritten by 299259 — out of scope).
2. **Checkpoints re-read with the mission venv** (`torch.load(map_location='cpu', mmap=True)`, 10 MB files, metadata
   keys only): `checkpoint_prev0.ckpt` train_state global_step_samples 1216, total_num_data_rows 1221,
   window_start_data_row_idx 0, train_bucket_level 0; `checkpoint.ckpt` 2528 / 2534 / 1221 / 3744.0,
   train_steps_since_last_reload 1312; 86 numeric running-metrics terms in each, 0 non-finite; 825837 params in
   both. `metrics_train.json` is 0 bytes (38 batches < print_train_loss_every_batches 100) — the worker's substitution
   of the checkpoint's running_metrics is disclosed on the error row and accepted. The two export names
   `t9-s1216-d1221` / `t9-s2528-d2534` corroborate the counters independently.
3. **No re-initialisation in cycle 2**: `logs/smoke_cycle2.txt` has 0 `Initializing new model!`, 0
   `No preexisting checkpoint found`, and `Advancing trainbucket row 1221 to 2534, 1313 new rows` / `New rows in
   bucket: 4000` / `Consuming 256 rows from train bucket (4000 -> 3744)` / `Global step: 1216 samples` at epoch start;
   cycle 1 has exactly one of each initialisation line.
4. **Exports and gate**: both `model.bin.gz` exist (3004833 B and 3005068 B, with `model.ckpt`, `metadata.json`,
   `log.txt`); `models/` is empty as the rejection implies. `gatekeepersgf/stdout.txt`: `Loaded candidate neural net
   t9-s1216-d1221 from: .../modelstobetested/t9-s1216-d1221/model.bin.gz`, `Loaded accepted neural net random
   from: /dev/null`, `Candidate has already lost too many games, terminating remaning games`, `Candidate lost match,
   score 55.500 to 100.500 in 156 games, rejecting candidate t9-s1216-d1221`; `numGamesPerGating = 200`,
   `numGameThreads = 18`, `numNNServerThreadsPerModel = 1`, `numSearchThreads = 1` in the run's gatekeeper cfg.
   sgf: 40 + 40 selfplay lines and 156 gatekeeper lines, every one `SZ[9]`, none rectangular.
5. **S9 contamination, checked independently of the worker's rule.** The 298712 samples are 6-column (no ppid, no
   command line), so pid ownership cannot be read off the file. Independent corroboration that 317109, 322317,
   323223 are foreign: (a) `sacct -a -N gb207` shows three other users' jobs (298847: 4 GPUs, 298859: 1 GPU,
   299237: 1 GPU) resident on gb207 across the window — the node was shared; (b) all three are present at the
   sampler's first sweep (+0.00 s = 09:20:49.59Z, 0.6 s after the job script's own start line) already at 36
   threads and ~2.5 GB RSS, which no process spawned by the job script could have reached; (c) the batch step's
   `MaxRSS` 8889928 kB is below 7932452 kB (the three) + 4549468 kB (our gatekeeper, which overlapped them), so they
   were not in the job's cgroup; (d) our own trainers 325065 (+32.8..+135.2 s) and 331077 (+242.4..+272.0 s) match
   the transcript's train phases and peak at 14. Ownership of the two 25-thread pids: 328662 (gatekeeper,
   +150.66..+220.85 s) coincides with the cycle-2 gatekeeper 09:23:20-09:24:26Z, 332406 (selfplay,
   +285.47..+316.22 s) with leg D1 09:25:34-09:26:06Z; no other gatekeeper/selfplay pid existed in those
   intervals, and both ran configs with numGameThreads 18. Residual caveat recorded on the row: ownership is by
   timing and cgroup arithmetic, not a recorded parent chain.
6. **S13 raw sources**: `du -sb selfplay/random/tdata` = 896536 B over 2534 rows = 353.78 -> 353.8 B/row;
   `gpu_samples-298712.csv`: 170 samples, util max 80, mean 21.48, memory.used max 4094 MiB; `du -sh` 97M;
   apparent size 100545534 B in the evidence file vs 100544216 in the candidate's metric — corrected on the
   admitted row to the evidence file's value. seff: 8.48 GB utilised, CPU 00:10:07.
7. **Leg A (S10)**: knowledge node_seq 4 (`a1f26db6…`) has `verification_run.exit_code 0`, duration 8.761 s,
   `CHECK_CFG_9X9: PASS`, `NLWP_MAX 22 <= CPU_BUDGET 24`, and no `admission_flags` key; `leg_a_append_298712.txt`
   shows `appended: true`, git 9fdeb6b. Appended by the worker inside the allocation (the obligation text named
   the validator; the executed-in-allocation requirement is what mattered and is met). Not re-appended.
8. **Verification commands**: all five candidate commands exit 0 from the az root. Four read the immutable
   `audit-298712.json`; `r_smoke_throughput_tiny`'s did NOT — it read the mutable `throughput_smoke.json`, and two
   rows named mutable files (`nlwp_max.txt`, `throughput_smoke.json`) as content-hashed evidence, while the
   `test -s rows_per_game.txt` witness was mutable too. Attempt 2's leg E overwrote all four at 09:58:41Z (it ran
   D1 -> exit 1, D2 -> exit 0, E -> exit 1; sacct FAILED 1:0, so the driver's exit-code repair works). Before
   that, at 09:55:20Z, byte-identical copies were frozen and verified by sha256:
   `nlwp_max-298712.txt` c153834283bfe29bf9c1f99856b405f690b53ac8040dd3094fa877d0992042d3,
   `throughput_smoke-298712.json` 927fb04cd2ac97eef7c30d471f06ac2d67ba8a014ac92cfe2109aa1efc72c947,
   `rows_per_game-298712.txt` daed88eff2a9d4e8cfa70b538caf5597fc2addb71cbcb6a1adc169ba16c3c828. The admitted rows
   point at those copies; the gate's recorded `evidence_sha256` values match them.
9. **Statuses**: `r_synchronous_loop_smoke` empirical (one run, two cycles, candidate rejected — c13 not claimed);
   `r_smoke_threads_realnet` refuted (the c06 statement asserts <= 24 on the real-net selfplay and gatekeeper
   processes; 25 measured on both); knowledge `preliminary` (predecessor `data_budget` is `hypothesis`; the
   worker's `hypothesis` seq-2 row is superseded). Honest.
10. **The worker's "COMPLETED 0:0 was wrong" self-finding** is recorded in error row `4566497308…`: root_cause (vi),
    `parameter_regime.state = "COMPLETED 0:0 (incorrectly -- see root_cause vi)"`, fix (vi), pass_fail partial with
    metric 10/11. Honest. The candidate rows' working_context still said "sacct COMPLETED 0:0" bare; the admitted
    rows carry the caveat.

## Findings that change what may be admitted later

- **c10's second conjunct fails at this scale**: 896536 B / 80 games = 11207 B = 10.94 KiB per game on disk,
  above the claimed `<= 10 KiB`, because random-net games give 31.7 rows/game rather than the ~22 assumed. The
  later validation of `r_smoke_probe_search` must not admit c10 as proposed in `candidate_rows.json`.
- **o37**: `stage_monitor.sh start` appends to an existing `ps_samples.tsv`; with 6-column attempt-1 rows plus
  7-column attempt-2 rows the audit sees ncols = 7, skips the legA exclusion rule, and re-admits the three foreign
  pids — reproduced live at 09:55Z (train nlwp 36, "foreign pids excluded: none"). Attempt 2's own audit output
  therefore carries the same contamination. Leg E also overwrites shared evidence files. Both need a fix before
  the 299259 groups are validated.
- c07 wording narrowed: the export lands in `modelstobetested/<name>/`; the gate moves it to `models/` only on
  acceptance.

## Remaining [OPEN]
o03 (thread budget: raise `--cpus-per-task` to >= 25 or lower numGameThreads, jointly, at derive_cycle_knobs_9x9);
o37; o24; S7 / S11 / S12 groups and c04 / c10 / c05 / c15 / o02 (next validation, after the o37 recompute);
two-real-net gatekeeper threads (gatekeeper_stage, cycle 3+); c13 acceptance (gatekeeper_stage).
