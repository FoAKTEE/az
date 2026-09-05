# o47 -- structural options for the rows/game drift (PREPARED, NOT APPLIED)

node `arxiv-1902.10565::scale_data_window` | obligation `o47_rows_per_game_drift_rederive_at_17`
worker, 2026-09-05. CPU only, no jobs, nothing under `runs/p1` written, `codes/loop/knobs_9x9.env`
NOT modified. Inputs, content-hashed by every run below: `262c1926ad77b9bd` rows_per_game.txt,
`5c5521e4356bb1f3` throughput.json (both read 5), `3504a8ea9c9d0bfa` knobs_9x9.env (live, G=1500).
Companion evidence here: `check_live_baseline.txt`, `check_option_{A,B,C}.txt`,
`scenarios_r15_r13.txt`, `epoch_granularity.txt`, `knobs_option_{A,B,C}.env`.

## 1. Trigger
Read 5 (05:45) measures marginal r = 17.7235 over the last three complete real-net directories,
least-squares slope -0.1070 rows/game per accepted net over the last nine, 10-net drift bound
r_lo = 16.6532. The o47 threshold 17.0 is 6.1 accepted nets away at ~30 min per net, ~09:10 today.
At the queued link-2 set (G=1500, E=20000) T1 fails again at 1.2E/G + 10*|slope| = 17.070
rows/game: 6.1 nets, ~18 cycles, ~4.8 h. Link 2 = job 305318, granted TimeLimit 84600 s.

## 2. The three options
r_lo = the scenario r carried 10 accepted nets forward at -0.1070. headroom =
(17.7235 - (1.2E/G + 1.070))/0.1070 accepted nets, cycles at the measured 2.90 cycles per
acceptance (21 in 61). Cycle = the measured-basis model 3600*G/6296.116 + 120000/2069.395 + 109.8 s
(its train term does not depend on E -- section 3). rho: section 3. Storage never binds: worst
per-link projection 23.65 GiB of 500 GiB; 74-87 cycles fit the granted link.

| set                     |    G |     E | rows/cycle | T1 margin (at r_lo) | headroom nets/cyc/h | rho  | cycle  | MiB/cyc |
|-------------------------|------|-------|------------|---------------------|---------------------|------|--------|---------|
| live (link 2 as queued) | 1500 | 20000 |    26585.3 | +10.8 %  (+4.1 %)   |   6.1 /  18 /  4.8  | 4.51 |  967 s |   15.13 |
| A  more games           | 1800 | 20000 |    31902.3 | +32.9 % (+24.9 %)   |  31.0 /  90 / 28.5  | 3.76 | 1139 s |   17.50 |
| B  epoch to the floor   | 1500 | 12800 |    26585.3 | +73.1 % (+62.6 %)   |  59.9 / 174 / 46.8  | 4.51 |  967 s |   15.13 |
| C  both (RECOMMENDED)   | 1800 | 16000 |    31902.3 | +66.2 % (+56.1 %)   |  55.9 / 162 / 51.3  | 3.76 | 1139 s |   17.50 |

At the two scenario rates (transcripts `scenarios_r15_r13.txt`, T1 lines in section 7):

| set   | r = 15                          | r = 13                          |
|-------|---------------------------------|---------------------------------|
| live  | T1 FAIL (20895 < 24000)         | T1 FAIL (17895 < 24000)         |
| A     | needs G = 2100 (PASS, 29253)    | needs G = 2500 (PASS, 29825)    |
| B     | PASS (20895 vs 15360, +36.0 %)  | PASS (17895 vs 15360, +16.5 %)  |
| C     | PASS (25074 vs 19200, +30.6 %)  | PASS (21474 vs 19200, +11.8 %)  |
| Clite | PASS (20895 vs 19200,  +8.8 %)  | T1 FAIL (17895 < 19200)         |

"needs G" is the smallest hundred with G*r_lo >= 1.2*(1.2E) = 28800, i.e. T1 restored with a 20 %
margin on the tolerance. Option A must be re-derived at every read that sees the marginal fall
(1800 -> 2100 -> 2500): the ratchet o47 asks to replace. Clite = the packet's example, E = 16000
with G = 1500.

## 3. What the loop actually does -- measured (`epoch_granularity.txt`)
From `logs/loop-301099.log` and the live shuffleddata directory, read-only:
* the shuffle writes the kept sample as round(SHUFFLE_KEEPROWS/70000) = 2 output files
  (shuffle.sh:48, shuffle.py:406-412); measured 60136 + 59864 = 120000 rows exactly;
* `get_files_for_subepoch` (train.py:1306-1345) takes WHOLE files -- its probabilistic skip at
  :1332 needs `batches_to_use_so_far > 0`, which a first file of 467 batches never allows -- so an
  epoch trains one whole file: global steps 6557440 -> 6617216 -> 6677248, i.e. 467 and 469
  batches against the nominal round(E/128) = 156;
* the third epoch of each cycle finds no unused file (-no-repeat-files,
  training_data_generator.py:35) and exits 0 (:1487-1489). 174 epochs started, 62 aborted there.

So NUM_TRAIN_SAMPLES_PER_EPOCH does not set what an epoch trains and MAX_TRAIN_SAMPLES_PER_CYCLE
does not set what a cycle trains: samples/cycle = SHUFFLE_KEEPROWS, and the real reuse is

    rho = SHUFFLE_KEEPROWS / (G * r) = 120000 / 26585.3 = 4.51 today,

5.33 at r = 15 and 6.15 at r = 13 if nothing moves, against MAX_TRAIN_PER_DATA = 8 (reached at
r = 10.0 with G = 1500). Three consequences. (i) B leaves rho at 4.51: lowering E restores the
WRITTEN T1 and changes nothing the loop does; only A and C move rho, because only they move G.
(ii) The export cadence is pinned at 2 epochs/cycle, one candidate per EPOCHS_PER_EXPORT/2 = 2.5
cycles (measured 22/62 = 2.82 with the ramp); only EPOCHS_PER_EXPORT or SHUFFLE_KEEPROWS moves it.
(iii) The loss-log density is floor(467/100) = 4 metrics_train.json lines per epoch
(train.py:1379/:1661), 8 per cycle, for every option: the 100-batch floor that makes 12800 the
nominal lower bound on E is unreachable while one file carries 467 batches, so B's zero margin
over it is latent -- and becomes active the moment SHUFFLE_KEEPROWS splits the sample finer.
[PRELIMINARY: (i)-(iii) are inferences from that code path plus the measured step sizes.]

[OPEN] the real structural lever is `-approx-rows-per-out-file` (shuffle.sh:48) with
SHUFFLE_KEEPROWS: a smaller out file would make E operative and let the export cadence be set
deliberately -- a change to shuffle.sh, not the knob file, and it needs its own packet.

## 4. The value-loss drift against the options
Measured (read 5): vloss minimum 0.568837 at t9-s1762560-d595534 (1.76 M samples), monotone up to
0.592790 at t9-s6257664-d1299077 (6.26 M): +0.0240, +4.2 %, while p0loss 3.603458 -> 1.844065 and
pacc1 0.075852 -> 0.455931 move the right way. The value target is per GAME (outcome plus the TD
targets), the policy target per ROW, so a cycle produces G independent value labels, not G*r; and
by section 3 the samples drawn from one game over its residence are SHUFFLE_KEEPROWS / G,
independent of r. Hence, all [PRELIMINARY]:
* the drift is not what is pushing the value head: it raises rho (policy-target repetition,
  4.51 -> 6.15) and leaves value-target repetition at exactly 120000/G. That figure was 120 through
  all of link 1 (G = 1000); link 2 at G = 1500 cuts it to 80, A / C at G = 1800 to 66.7, while B
  and Clite leave it at 80. Raising G is the only lever here that touches the value head at all;
* a smaller E gives no fresher epochs either: freshness is set by the shuffle cadence (once per
  cycle, synchronous_loop_9x9.sh:390) and the power-law window (shuffle.py:414-435, ~240 k rows),
  neither of which reads E;
* a smaller E is mildly ADVERSE for a head that is overfitting: swa_period_samples = E//2
  (train.py:441) with swa_scale 8 (:443) makes the export an EMA over ~4E samples, so E 20000 ->
  16000 shortens the averaging horizon 80000 -> 64000 and E -> 12800 to 51200. Less averaging is
  less regularisation on exactly the head that is drifting.

## 5. Recommendation
**Option C: NUM_GAMES_PER_CYCLE 1500 -> 1800 AND NUM_TRAIN_SAMPLES_PER_EPOCH 20000 -> 16000**, with
NUM_TRAIN_SAMPLES_PER_SWA 8000 and MAX_TRAIN_SAMPLES_PER_CYCLE 80000 as their derived companions
and every other knob unchanged (`knobs_option_C.env`). Not the packet's example E = 16000 with
G = 1500: that variant leaves rho and the value head untouched and already fails T1 at r = 13.
* C alone both restores the written tolerance with real margin (+66.2 %, +56.1 % at the 10-net
  bound) and moves the quantity the loop responds to (rho 4.51 -> 3.76, its pre-drift value;
  value-label repetition 80 -> 66.7);
* it buys 55.9 accepted nets, ~162 cycles, ~51 h -- the next re-derivation becomes a scheduled
  read, not an emergency -- and survives r = 13 (+11.8 % at the drift bound) where A needs two
  further G moves and Clite fails; it keeps 25 batches of margin over the 100-batch metrics floor
  and shortens the SWA horizon by only 20 %, where B removes the first and cuts the second by 36 %;
* it costs +20.0 % selfplay, +17.7 % cycle wall (967 -> 1139 s), +15.7 % storage per cycle -- the
  whole cost, and A pays it too for half the headroom and no T1 margin at r = 13; EPOCHS_PER_EXPORT,
  SHUFFLE_KEEPROWS, SHUFFLE_MINROWS, TAPER_WINDOW_SCALE, MAX_TRAIN_PER_DATA and both allocation
  knobs are untouched, so gate cadence, window and thread budget do not move.
If no GPU time may be spent, B is the second choice -- free, largest T1 headroom (59.9 nets),
costs only latent -- but a paper fix that leaves the value head where it is. A is dominated by C.

`verify:` (exit 0, CHECK_KNOBS_9X9: PASS; transcript `check_option_C.txt`)

    python3 results/ktg/paper_1902.10565/codes/eval/check_knobs_9x9.py \
      --knobs      results/ktg/paper_1902.10565/evidence/scale_data_window/knobs_option_C.env \
      --throughput results/ktg/paper_1902.10565/evidence/production_chain/throughput.json \
      --rows-file  results/ktg/paper_1902.10565/evidence/production_chain/rows_per_game.txt \
      --marginal-nets 3 --trend-nets 9 --horizon-nets 10

APPLYING ANY OF THESE IS A HUMAN DECISION AND AN ESCALATION (mission tolerance). Nothing here is
applied; the running link 1 keeps the knobs it sourced. A chosen file must be copied over
`codes/loop/knobs_9x9.env`, the `${VAR:-default}` block of `synchronous_loop_9x9.sh` brought to
match (re-run `check_knobs_9x9.py` with no arguments after), and mission.json's decisions list
appended -- all before link 2 sources the file.

## 6. Verbatim -- every K and T inequality at the measured marginal r = 17.7235
Per option: `check_knobs_9x9.py --knobs <option file> --throughput <read-5 throughput.json>
--rows-file <read-5 rows_per_game.txt> --marginal-nets 3 --trend-nets 9 --horizon-nets 10`; all
three exit 0. `--knobs` skips the loop-default assertion (wired to the live file), so
EPOCHS_PER_EXPORT is checked by reading the derived value back in K2: every option derives 5,
which is what its file carries. Each block is the run's `CHECKS` lines, then T2 (the one tolerance
check_knobs adds to derive_knobs' set), then the verdict; full transcripts are the files above.

### OPTION A
  ok   K1_bucket_gain_clears_epoch            gain = games*r*reuse = 255218.4 (lower90 239806.4) vs 0.99*E = 19800.0; ratio gain/E = 12.761 (lower90 11.990)
  ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 31902.3 (lower90 29975.8) vs 1.2*E = 24000.0; ratio 1.595 (lower90 1.499)
  ok   K2_one_export_per_cycle                epochs_per_export = max_epochs_this_instance = floor(min(gain,cap_eff)/E) = 5 (lower90 5); cap_eff = max(cap,E) = 100000; effective reuse 3.13 (lower90 3.34) <= 8.0
  ok   K2b_effective_reuse_within_cap         epochs*E/rows_per_cycle = 3.13 (lower90 3.34) <= reuse cap 8.0
  ok   K3_keep_gt_cap                         keep = 120000 > cap = 100000 (synchronous_loop.sh:66) and keep >= epochs*E = 100000
  ok   K5_random_bootstrap_reaches_min_rows   cycle-1 random rows = games*r_random = 56652.1 (lower90 55850.9) >= min_rows = 25000 (shuffle.py:1090 exit-0 gate; :1077 caps the usable count at min_rows)
  ok   K4_window_holds_one_epoch              worst of cycles 1..20 is cycle 1: min(window 25000, keep 120000) = 25000 rows = 195 batches >= round(E/batch) = 156 batches (= 19968 rows); ratio 1.250. Conservative: the file-granularity slack of shuffle.sh:48 (-approx-rows-per-out-file 70000) is not credited.
  ok   K2c_at_most_one_export_per_cycle       epochs_per_export == max_epochs_this_instance == 5, so train.py's persistent export_cycle_counter (:871,:975,:1743,:1831) can advance by at most 5 per cycle: never more than one candidate per cycle, from cycle 1 on. The ramp (o40): the window is pinned at min_rows while models/ is empty (shuffle.py:1077), each of those cycles trains ONE epoch (-no-repeat-files, training_data_generator.py:35; -quit-if-no-data, train.py:1487-1489), so the FIRST candidate exports at cycle 5 and is gated at cycle 6; with the gate accepting at cycle 6 the exports fall on cycles [5, 8, 10, 12, 14, 15, 16, 17, 18, 19, 20] and every cycle exports from cycle 14 on, the window first holding 100000 rows at cycle 15. A rejection keeps the loop in the one-epoch regime and moves the whole ramp later.
  ok   K6_swa_period_is_half_epoch            swa_period_samples = samples_per_epoch // 2 = 10000 (train.py:441 default made explicit)
  ok   T4_threads_le_cpus                     worst stage thread count 28 (selfplay real-net 25 +2 net switch = 27; gatekeeper two real nets 28; train 14; shuffle 4+8=12) <= --cpus-per-task 32, headroom 4
  ok   K7_cycle_wall_under_bound              projected cycle = 1421 s = 0.39 h <= 60 h bound, and 181 whole cycles fit the 257400 s chain link. [PRELIMINARY] tiny-count throughput inputs.
  ok   T3_storage_projection_under_budget     per-cycle monotonic write 17.5 MiB; bounded steady state 552.5 MiB; env+build 20.0 GiB; after one full 181-cycle link 23.63 GiB of 500 GiB cap; 28049 cycles fit before the cap
  ok   T2_bucket_holds_batches            worst cycle 1 has 195 batches >= 156 needed; per-cycle bucket gain 255218 (lower90 239806) >= epochs*E = 100000
CHECK_KNOBS_9X9: PASS

### OPTION B
  ok   K1_bucket_gain_clears_epoch            gain = games*r*reuse = 212682.0 (lower90 199838.7) vs 0.99*E = 12672.0; ratio gain/E = 16.616 (lower90 15.612)
  ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 26585.3 (lower90 24979.8) vs 1.2*E = 15360.0; ratio 2.077 (lower90 1.952)
  ok   K2_one_export_per_cycle                epochs_per_export = max_epochs_this_instance = floor(min(gain,cap_eff)/E) = 5 (lower90 5); cap_eff = max(cap,E) = 64000; effective reuse 2.41 (lower90 2.56) <= 8.0
  ok   K2b_effective_reuse_within_cap         epochs*E/rows_per_cycle = 2.41 (lower90 2.56) <= reuse cap 8.0
  ok   K3_keep_gt_cap                         keep = 120000 > cap = 64000 (synchronous_loop.sh:66) and keep >= epochs*E = 64000
  ok   K5_random_bootstrap_reaches_min_rows   cycle-1 random rows = games*r_random = 47210.1 (lower90 46542.4) >= min_rows = 25000 (shuffle.py:1090 exit-0 gate; :1077 caps the usable count at min_rows)
  ok   K4_window_holds_one_epoch              worst of cycles 1..20 is cycle 1: min(window 25000, keep 120000) = 25000 rows = 195 batches >= round(E/batch) = 100 batches (= 12800 rows); ratio 1.953. Conservative: the file-granularity slack of shuffle.sh:48 (-approx-rows-per-out-file 70000) is not credited.
  ok   K2c_at_most_one_export_per_cycle       epochs_per_export == max_epochs_this_instance == 5, so train.py's persistent export_cycle_counter (:871,:975,:1743,:1831) can advance by at most 5 per cycle: never more than one candidate per cycle, from cycle 1 on. The ramp (o40): the window is pinned at min_rows while models/ is empty (shuffle.py:1077), each of those cycles trains ONE epoch (-no-repeat-files, training_data_generator.py:35; -quit-if-no-data, train.py:1487-1489), so the FIRST candidate exports at cycle 5 and is gated at cycle 6; with the gate accepting at cycle 6 the exports fall on cycles [5, 7, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20] and every cycle exports from cycle 11 on, the window first holding 64000 rows at cycle 11. A rejection keeps the loop in the one-epoch regime and moves the whole ramp later.
  ok   K6_swa_period_is_half_epoch            swa_period_samples = samples_per_epoch // 2 = 6400 (train.py:441 default made explicit)
  ok   T4_threads_le_cpus                     worst stage thread count 28 (selfplay real-net 25 +2 net switch = 27; gatekeeper two real nets 28; train 14; shuffle 4+8=12) <= --cpus-per-task 32, headroom 4
  ok   K7_cycle_wall_under_bound              projected cycle = 1232 s = 0.34 h <= 60 h bound, and 208 whole cycles fit the 257400 s chain link. [PRELIMINARY] tiny-count throughput inputs.
  ok   T3_storage_projection_under_budget     per-cycle monotonic write 15.1 MiB; bounded steady state 552.5 MiB; env+build 20.0 GiB; after one full 208-cycle link 23.61 GiB of 500 GiB cap; 32451 cycles fit before the cap
  ok   T2_bucket_holds_batches            worst cycle 1 has 195 batches >= 100 needed; per-cycle bucket gain 212682 (lower90 199839) >= epochs*E = 64000
CHECK_KNOBS_9X9: PASS

### OPTION C (recommended)
  ok   K1_bucket_gain_clears_epoch            gain = games*r*reuse = 255218.4 (lower90 239806.4) vs 0.99*E = 15840.0; ratio gain/E = 15.951 (lower90 14.988)
  ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 31902.3 (lower90 29975.8) vs 1.2*E = 19200.0; ratio 1.994 (lower90 1.873)
  ok   K2_one_export_per_cycle                epochs_per_export = max_epochs_this_instance = floor(min(gain,cap_eff)/E) = 5 (lower90 5); cap_eff = max(cap,E) = 80000; effective reuse 2.51 (lower90 2.67) <= 8.0
  ok   K2b_effective_reuse_within_cap         epochs*E/rows_per_cycle = 2.51 (lower90 2.67) <= reuse cap 8.0
  ok   K3_keep_gt_cap                         keep = 120000 > cap = 80000 (synchronous_loop.sh:66) and keep >= epochs*E = 80000
  ok   K5_random_bootstrap_reaches_min_rows   cycle-1 random rows = games*r_random = 56652.1 (lower90 55850.9) >= min_rows = 25000 (shuffle.py:1090 exit-0 gate; :1077 caps the usable count at min_rows)
  ok   K4_window_holds_one_epoch              worst of cycles 1..20 is cycle 1: min(window 25000, keep 120000) = 25000 rows = 195 batches >= round(E/batch) = 125 batches (= 16000 rows); ratio 1.562. Conservative: the file-granularity slack of shuffle.sh:48 (-approx-rows-per-out-file 70000) is not credited.
  ok   K2c_at_most_one_export_per_cycle       epochs_per_export == max_epochs_this_instance == 5, so train.py's persistent export_cycle_counter (:871,:975,:1743,:1831) can advance by at most 5 per cycle: never more than one candidate per cycle, from cycle 1 on. The ramp (o40): the window is pinned at min_rows while models/ is empty (shuffle.py:1077), each of those cycles trains ONE epoch (-no-repeat-files, training_data_generator.py:35; -quit-if-no-data, train.py:1487-1489), so the FIRST candidate exports at cycle 5 and is gated at cycle 6; with the gate accepting at cycle 6 the exports fall on cycles [5, 8, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20] and every cycle exports from cycle 12 on, the window first holding 80000 rows at cycle 12. A rejection keeps the loop in the one-epoch regime and moves the whole ramp later.
  ok   K6_swa_period_is_half_epoch            swa_period_samples = samples_per_epoch // 2 = 8000 (train.py:441 default made explicit)
  ok   T4_threads_le_cpus                     worst stage thread count 28 (selfplay real-net 25 +2 net switch = 27; gatekeeper two real nets 28; train 14; shuffle 4+8=12) <= --cpus-per-task 32, headroom 4
  ok   K7_cycle_wall_under_bound              projected cycle = 1411 s = 0.39 h <= 60 h bound, and 182 whole cycles fit the 257400 s chain link. [PRELIMINARY] tiny-count throughput inputs.
  ok   T3_storage_projection_under_budget     per-cycle monotonic write 17.5 MiB; bounded steady state 552.5 MiB; env+build 20.0 GiB; after one full 182-cycle link 23.65 GiB of 500 GiB cap; 28049 cycles fit before the cap
  ok   T2_bucket_holds_batches            worst cycle 1 has 195 batches >= 125 needed; per-cycle bucket gain 255218 (lower90 239806) >= epochs*E = 80000
CHECK_KNOBS_9X9: PASS
## 7. Verbatim -- T1 at the two scenario rates (`scenarios_r15_r13.txt`)
live G1500 E20000 r=17.7235 ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 26585.3 (lower90 24979.8) vs 1.2*E = 24000.0; ratio 1.329 (lower90 1.249)
live G1500 E20000 r=15     FAIL T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 22500.0 (lower90 20895.0) vs 1.2*E = 24000.0; ratio 1.125 (lower90 1.045)
live G1500 E20000 r=13     FAIL T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 19500.0 (lower90 17895.0) vs 1.2*E = 24000.0; ratio 0.975 (lower90 0.895)
A    G2100 E20000 r=15     ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 31500.0 (lower90 29253.0) vs 1.2*E = 24000.0; ratio 1.575 (lower90 1.463)
A    G2500 E20000 r=13     ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 32500.0 (lower90 29825.0) vs 1.2*E = 24000.0; ratio 1.625 (lower90 1.491)
B    G1500 E12800 r=15     ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 22500.0 (lower90 20895.0) vs 1.2*E = 15360.0; ratio 1.758 (lower90 1.632)
B    G1500 E12800 r=13     ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 19500.0 (lower90 17895.0) vs 1.2*E = 15360.0; ratio 1.523 (lower90 1.398)
C    G1800 E16000 r=15     ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 27000.0 (lower90 25074.0) vs 1.2*E = 19200.0; ratio 1.688 (lower90 1.567)
C    G1800 E16000 r=13     ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 23400.0 (lower90 21474.0) vs 1.2*E = 19200.0; ratio 1.462 (lower90 1.342)
Clit G1500 E16000 r=15     ok   T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 22500.0 (lower90 20895.0) vs 1.2*E = 19200.0; ratio 1.406 (lower90 1.306)
Clit G1500 E16000 r=13     FAIL T1_freshness_rows_per_cycle_ge_1p2_E   rows_per_cycle = 19500.0 (lower90 17895.0) vs 1.2*E = 19200.0; ratio 1.219 (lower90 1.118)
## 8. Open items
* [OPEN] the drift is unbounded; the last-4 slope -0.091 is deceleration, not a bound. Every
  option above is a horizon, not a fix. [OPEN] section 3's out-file lever is untried and is the
  only way found to make E operative. [PRELIMINARY] every rho / value-head statement in sections
  3-4 is an inference from the code path plus the measured step sizes; no ablation was run.
