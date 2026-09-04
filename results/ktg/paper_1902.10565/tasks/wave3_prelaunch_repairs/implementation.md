# Implementation — `wave3_prelaunch_repairs`

## 0. Header

**Task ID:** `wave3_prelaunch_repairs`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::loop_resume_under_walltime` (R1 o39, R5 o02 wiring, R6 monitor), `::derive_cycle_knobs_9x9` (R2 o40, R3 o41), `::playout_cap_randomization` via task `paper_code_map_search` (R4 o38). One packet, ONE worker, CPU only, one commit per repair (R1–R6), no job submitted.
**Language:** bash / Slurm wrapper + Python (stdlib; the mission venv only for R4's optional sgf cross-check)
**Method class:** refactor (R1, R5, R6) + symbolic (R2, R3) + simulation on recorded data (R4)
**Scheduling policy (wave 3):** the four ledger nodes are `preliminary`/`solid`; every repair here is admitted as an AMENDED result row at the status the prior row holds (`existence_only` for the wrapper pair, `conditional` for the knobs), plus one new `empirical` row for the re-binned full-search fraction. `[BLOCKING]` for `tasks/production_chain_9x9`: R1, R5, R6 must land (commit + validator admission of the wrapper row) before `sbatch codes/loop/loop.sbatch`; R2, R3, R4 may land in parallel and must land before the chain's cycle 5 is read.

## 1. Claim

> After this packet, `codes/loop/loop.sbatch` declares and asserts the CPUs the derived knobs require (32, read from `knobs_9x9.env`, o39), samples every stage's threads and the GPU for the whole link (R6), and the loop copy refuses to shuffle any npz that is not a `dataBoardLen = 9` row set (o02 wiring); `derive_knobs.py` models the export ramp as the validator derived it (first candidate at cycle 5, o40) and fails loudly on a missing measured key (o41); and the full-search fraction of the surviving 60-game probe run, re-binned at `Root visits == maxVisits`, is 0.2516 inside the band `[0.20, 0.30]` (o38), which is what promotes `playout_cap_randomization`.

## 2. Success Criterion

- **Needed evidence type:** `static_verification` + offline injection under the scheduler shims (R1, R5, R6); `symbolic_derivation` with executed check (R2, R3); `empirical_measurement` on recorded artifacts (R4).
- **Done when:** every per-repair command below exits 0 and the candidate rows in `evidence/wave3_prelaunch_repairs/candidate_rows.json` are staged for the validator.
- **Verification commands (all from the az root, login node, no GPU; `P=results/ktg/paper_1902.10565`):**
  | # | repair | command | tolerance |
  |---|---|---|---|
  | R1 | o39 | `bash -n $P/codes/loop/loop.sbatch && grep -q '^#SBATCH --cpus-per-task=32$' $P/codes/loop/loop.sbatch && grep -q 'REQ_CPUS="${KTG_CPUS_PER_TASK' $P/codes/loop/loop.sbatch && ! grep -n 'cpus-per-task=24\|REQ_CPUS=24' $P/codes/loop/loop.sbatch && bash "$(python3 -c 'import json;print(json.load(open("mission.json"))["compute"]["policyCheck"])')" --gpus 1 --cpus 32 --partition b200` | exit 0; the policy line reads `OK : request gpus=1 cpus=32 part=b200 within policy` |
  | R1 | o39 shim | the wrapper under the PATH shims of `evidence/loop_resume/validation_repair4_harness.txt` Part B1 (`sbatch scancel sinfo sacct scontrol squeue nvidia-smi`), stand-in loop, `SLURM_JOB_ID=9910`: with `SLURM_CPUS_PER_TASK=24` → log line `declared CPUs 24 != KTG_CPUS_PER_TASK 32`, wrapper exit 2, `PRE-FLIGHT FAILURE`, `SCANCEL` in the shim log; with `SLURM_CPUS_PER_TASK=32` → the loop starts and the successor pre-flight prints `cpus=32` | exact |
  | R2 | o40 | `python3 $P/codes/eval/derive_knobs.py --self-test && python3 $P/codes/eval/check_knobs_9x9.py \| grep -E 'first_export_cycle *= 5$\|first_exactly_one_cycle *= 1[5-7]$' \| wc -l` | self-test exit 0 with the new ramp case listed; both lines present (`first_exactly_one_cycle` 16 ± 1 with `--first-accept-cycle 6`); `CHECK_KNOBS_9X9: PASS` |
  | R3 | o41 | `python3 $P/codes/eval/check_knobs_9x9.py && ! grep -nE '^[^#"]*\b(14\.243\|353\.8\|70\.19\|3\.35\|2534)\b' $P/codes/eval/derive_knobs.py` and the B3 replay: copy `$P` to the scratchpad, delete `train_samples_per_second` and `bytes_per_row_on_disk` from both `throughput_smoke-*.json`, run the copy's `check_knobs_9x9.py` | copy exits non-zero and stderr names `train_samples_per_second` (not `nan`); original exits 0; no baked-in rate literal left in code lines |
  | R4 | o38 | `python3 $P/codes/eval/probe_search_9x9.py $KTG_ROOT/runs/smoke_probe/search/selfplay $KTG_ROOT/runs/smoke_probe/search/selfplay/log20260904-055425-11022754EF29BF2B.log --json $P/evidence/smoke/probe_search_rebin-299259.json` | `searched_turns = 7401`, `full_search_turns = 1862`, `FULL_FRAC = 0.2516` in `[0.20, 0.30]`, `between_count = 667`, `PROBE_SEARCH_9X9: PASS`; the json carries `full_frac_rule = "root_visits == maxVisits"`, the full histogram (100 × 4872, 600 × 1862) and the source sha256 `59e2574e…` |
  | R5 | o02 | `KTG_STAGE_ONLY=1` dry run into a throwaway BASEDIR (exit 0, line `pos_len check: 0 npz`); the same with the smoke's two `selfplay/random/tdata/*.npz` symlinked in → `CHECK_POS_LEN_NPZ: PASS` over 2534 rows; with one synthetic npz whose `binaryInputNCHWPacked` trailing shape is `(22, 21)` → exit non-zero before any stage, the file named; the REAL loop with dummy stages (harness Part 2 W1 form, `KTG_ONE_CYCLE=1`): a dummy selfplay that drops a good npz → `cycle 1 complete`; one that drops a bad npz → exit 1 at the pre-shuffle check, `.cycles_completed` unchanged | exact |
  | R6 | monitor | shim run of R1 with the stand-in loop executing `exec -a "katago selfplay" sleep 3`: `$BASEDIR/monitor/ps_samples-9910.tsv` exists with ≥ 1 row whose stage column is `selfplay` and ppid chain rooted at the wrapper; log has `stage_monitor: started` and, in finalize, `stage_monitor: stopped`; `KTG_MON_PS_INTERVAL` unset → 0.2 s (smoke unchanged), `=1` → 1 s | exact |
  | all | regression | harness scenarios A, D, G, K1, L2, P3 of `validation_repair4.md` § 1 re-run under the same shims | outcomes line-for-line as recorded; `KTG_STAGE_ONLY=1` dry run from the real scratch clone still stages 80 files / 28 702 024 B |
- **Open obligations before start:** o39, o40, o41, o38, o02 (wiring half) — all owned here; o03's measurement conjunct and o40 (c) stay with the chain. o33/o36 are untouched (non-blocking).
- **Reduction-to-baseline test:** NA

## 3. Motivation

The first production chain (`tasks/production_chain_9x9`) cannot be submitted while `loop.sbatch` declares 24 CPUs against a measured 25 per CUDA-context stage (o39, `[BLOCKING]`), and its data cannot settle `o03`/`c09` unless the thread and GPU samplers run inside the link (the smoke job carried them in `smoke_loop.sbatch`; `loop.sbatch` has none). The remaining three are CPU-only defects the validator recorded against admitted rows: the export-ramp prose that would mis-set the human's expectations (o40), silent constants in the knob check (o41), and a probe discriminator that turned a 0.25 measurement into a false refutation (o38). o02's wiring half is decided here rather than carried: a blocking obligation must not ride into the launch un-decided.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | the four nodes above and `selfplay_stage`'s predecessor list |
| DESIGN | `results/ktg/paper_1902.10565/decomposition/DESIGN.md` | §1 thread budget (32/18), §2 ramp bullet (:176-184) and decision line (:353) — R2 rewrites both in place |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | o02, o38, o39, o40, o41 verbatim closing conditions |
| results | `results/ktg/paper_1902.10565/decomposition/results.md` | `r_loop_resume_under_walltime_static`, `r_cycle_knobs_9x9_derived`, `r_smoke_full_frac_binning` (the rows amended or answered here) |
| evidence | `evidence/derive_cycle_knobs/validation.md` § 2.7 (the ramp simulation to reproduce), `evidence/smoke/validation_probes.md` item 2 and `root_visits_hist-v299259.json` (the re-bin targets), `evidence/loop_resume/validation_repair4_harness.txt` (shim set, stand-in tree, dummy-stage form) |

**Upstream task outputs:** `tasks/loop_resume_under_walltime` (§ 10/13 rules for the wrapper), `tasks/derive_cycle_knobs_9x9` (§ 13: never hand-pick a knob), `tasks/paper_code_map_search` § 2 (assertion (a) as written), `codes/eval/{stage_monitor.sh,check_pos_len_npz.py,audit_smoke.py}`.

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- CPU only, login node (parallelism ≤ 2, 5 GB cgroup); the mission venv only for R4's sgf cross-check and nothing else. No `sbatch`, `srun`, `interact`.
- Order: R1 → R6 → R5 (the three touch `codes/loop/`; commit each before the next), then R2, R3 (`codes/eval/derive_knobs.py`, `check_knobs_9x9.py`, prose), then R4 (`probe_search_9x9.py`, `audit_smoke.py`). Never leave `codes/loop/` in a state where `bash -n` fails.
- The knob VALUES in `knobs_9x9.env` and the loop's CHANGE 9 block are not touched (R2 changes a model and prose, not a knob; `check_knobs_9x9.py` must keep reporting the same eleven values).
- Every trial is an error-ledger row (`CHANDRA_ROLE=worker`); result/claim/knowledge rows are STAGED in `evidence/wave3_prelaunch_repairs/candidate_rows.json` for a cross-model validator, never appended by the worker.
- 3 iterations / 30 min stuck on one repair → `pipelines/0-acquire/spec.md`; do not widen the packet.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference code | `ref-code/lightvector-KataGo/` (`python/train.py:871,975,1256-1259,1303-1346,1434-1445,1487-1489,1743,1828-1836`, `python/shuffle.py:414-435,1077`, `katago/utils/training_data_generator.py:35`, `cpp/search/search.cpp:509,579-580`, `cpp/program/play.cpp:1147,1234,1567`) |
| Code output | `results/ktg/paper_1902.10565/codes/loop/{loop.sbatch,synchronous_loop_9x9.sh,knobs_9x9.env}`, `codes/eval/{derive_knobs.py,check_knobs_9x9.py,probe_search_9x9.py,audit_smoke.py,stage_monitor.sh}` |
| Evidence | `results/ktg/paper_1902.10565/evidence/wave3_prelaunch_repairs/{repair_R1..R6.txt,candidate_rows.json}`, `evidence/smoke/probe_search_rebin-299259.json`, `evidence/knobs/derivation.txt` (regenerated) |
| Progress dir | `progress/paper_1902.10565/wave3_prelaunch_repairs/` |
| Git branch | `main` (az) |

## 7. Architecture

```text
codes/loop/loop.sbatch              # R1: --cpus-per-task=32; sources knobs_9x9.env (set -a); REQ_CPUS from KTG_CPUS_PER_TASK;
                                    #     pre-flight asserts SLURM_CPUS_PER_TASK == KTG_CPUS_PER_TASK and cfg numGameThreads == KTG_NUM_GAME_THREADS
                                    # R6: stage_monitor.sh start $BASEDIR/monitor $$ after env.sh; stop in finalize()
codes/loop/synchronous_loop_9x9.sh  # R5: CHANGE 11 pre-shuffle pos_len guard (loop start + every cycle, files newer than .pos_len_checked)
                                    # R6: stage_monitor.sh phase cycle$N at the top of the cycle when monitor.run exists
codes/eval/stage_monitor.sh         # R6: KTG_MON_PS_INTERVAL (default 0.2) and KTG_MON_GPU_INTERVAL (default 2) env knobs
codes/eval/derive_knobs.py          # R2: per-cycle ramp simulation (random rows until first export AND acceptance; --first-accept-cycle);
                                    #     prints first_export_cycle / first_exactly_one_cycle; K2c text; two-net gate = 28
                                    # R3: _req(tput, key) raises SystemExit naming the key; no rate constants outside --self-test inputs
codes/eval/check_knobs_9x9.py       # R3: asserts the measured keys before deriving; --throughput FILE / --rows-file FILE for the production re-run
codes/eval/probe_search_9x9.py      # R4: full = (v == MAX_VISITS); between/legacy counts; optional --sgf-v second instrument; never deletes the log
codes/eval/audit_smoke.py           # R4: S7 requires full_frac_rule == "root_visits == maxVisits"
```

## 8. Phase Plan

### Phase 1 - `wrapper` (R1, R6, R5)
- **Nodes:** `loop_resume_under_walltime`
- **Files:** `loop.sbatch`, `synchronous_loop_9x9.sh`, `stage_monitor.sh`
- **Test:** the R1, R6, R5 and regression rows of § 2. Details that must hold: the knobs file is read in the contract section without exiting (a missing file leaves `REQ_CPUS` empty, `resubmit()` then refuses to chain exactly as it does for an unresolvable policy check) and is asserted with `exit 2` in the environment section, after the EXIT trap, so the failure is a counted pre-flight failure that cancels the successor; `set -a; . knobs_9x9.env; set +a` exports the eleven loop knobs, which equal the CHANGE 9 defaults (`check_knobs_9x9.py` loop wiring) — no value changes; `stage_monitor.sh stop` is the first statement of `finalize()` after `FINALIZED=1` and is `|| true`; the loop's `phase` call is guarded by `[ -f "$BASEDIR/monitor/monitor.run" ]` so `smoke_loop.sbatch` and the dry run are unaffected; the o02 guard runs `check_pos_len_npz.py` only over npz newer than `$BASEDIR/.pos_len_checked` (all of them when the marker is absent), skips cleanly at 0 files, and touches the marker after a pass.
- **Estimate:** `3.0` h

### Phase 2 - `knob model` (R2, R3)
- **Nodes:** `derive_cycle_knobs_9x9`
- **Files:** `derive_knobs.py`, `check_knobs_9x9.py`, `knobs_9x9.env` (comments :102-109 and :126-135 only), `DESIGN.md` (:176-184, :353), `evidence/derive_cycle_knobs/derivation.md` (§ 3 revised in place, marked "amended 2026-09-04 (o40)"), `evidence/knobs/derivation.txt` (regenerated)
- **Test:** R2 and R3 rows of § 2; the ramp model reproduces `validation.md` § 2.7: cycles 1–5 one epoch each (window = 25 000 rows = 195 batches ≥ 156, `-no-repeat-files` ends the instance after one epoch), export at cycle 5, real-net rows only from the cycle after the first ACCEPTED gate (`--first-accept-cycle`, default = first gate cycle = 6), exports at cycles 5, 8, 10, 12, 14, 16, 17, 18 … under acceptance at 6; K1/K3/K4/K5/T1–T4 unchanged; the prose says "first candidate at cycle 5, gated at cycle 6; exactly one per cycle once the window holds 5 × E rows (≈ cycle 16 if accepted at 6, later per rejection)"; the two-real-net gate reads `18 + 2 + 1 + 1 + 2 × 3 = 28`, headroom 4.
- **Estimate:** `2.5` h

### Phase 3 - `re-bin` (R4)
- **Nodes:** `playout_cap_randomization` (promotion proposed), `synchronous_loop_smoke` (o38 discharge)
- **Files:** `probe_search_9x9.py`, `audit_smoke.py`, `evidence/smoke/probe_search_rebin-299259.json`
- **Test:** R4 row of § 2; the sgf `v=` instrument (60-game sgfs, 7401 moves) gives the identical histogram; the loop's 80 random-net sgfs give 2311/9211 = 0.2509 (recorded, second run); `audit_smoke.py --tag 299259` into a temp dir now reports `S7 FULL_FRAC = 0.2516` and the rule; the two unrecoverable 20-game rows are named `[UNCHECKED]` in the candidate row, not re-binned.
- **Estimate:** `1.5` h

## 9. Quick-Win Path

1. `Phase 1` — R1 only (three edits + the assert), run the R1 static command and the 24-vs-32 shim pair; commit `fix(resume,ktg): declare and assert 32 CPUs from knobs_9x9.env`.
2. `Phase 2` — R3 before R2 (smaller): make `_req()` raise, move the three self-test cases to explicit rates, run `--self-test` and the B3 replay.
3. **Smoke check:** `check_knobs_9x9.py` still prints the same eleven values and `PASS`; the policy check passes at 32.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| `#SBATCH --cpus-per-task` / `REQ_CPUS` | `32` / `"${KTG_CPUS_PER_TASK:-}"` | `knobs_9x9.env:134`; measured 25 per CUDA-context stage (`nlwp_max-298712.txt`, `-299259.txt`); worst projected stage 28 |
| cfg `numGameThreads` assert | `== KTG_NUM_GAME_THREADS` (18) on both cfgs | `selfplay_9x9.cfg:96`, `gatekeeper_9x9.cfg:30`; `knobs_9x9.env:135` |
| `KTG_MON_PS_INTERVAL` / `KTG_MON_GPU_INTERVAL` | default `0.2` / `2` (smoke), chain sets `1` / `5` | 3-day link at 1 s ≈ 260 k sweeps ≈ 50 MB tsv; `ps -eo` on a shared 124-core node costs ~20 ms |
| o02 guard | `check_pos_len_npz.py` over `find $BASEDIR/selfplay -name '*.npz' -newer $BASEDIR/.pos_len_checked` | stdlib zip-header read, ~1 ms per file; `data_processing_pytorch.py:91` would otherwise assert only at train time, after a whole selfplay stage |
| ramp inputs | `--first-accept-cycle 6` default; `r_lo = 25.08`, `r0_lo = 28.13`; window at `expand 0.4 / exponent 0.65` | `validation.md` § 2.7; `shuffle.sh:44-45`; `train.py:972` fresh bucket = E |
| re-bin rule | `full = (Root visits == 600)`, `cheap = (== 100)`, `between` = rest | `search.cpp:509,579-580`; `play.cpp:1147`; expected 1862 / 4872 / 667 of 7401 |

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| `set -a` sourcing exports an operator knob that the o33 (d) "clean shell" rule forbids | `env \| grep KTG_` in the job shows the eleven loop knobs plus `KTG_CPUS_PER_TASK`/`KTG_NUM_GAME_THREADS` | intended and identical to the defaults; the wrapper prints the sourced file's sha256 at pre-flight; `KTG_MAX_FAILS`/`KTG_MAX_CHAIN`/`KTG_MIN_RUNTIME_SECONDS` are NOT in the file (assert with `grep -c` in R1) |
| the monitor's background children change finalize's SIGTERM classification | harness K1–K3 outcomes differ | run K1 with the monitor on; the samplers are `|| true` and killed by `stop`; if any K scenario changes, revert R6 to a `phase`-less, stop-in-trap-only form and record |
| a resumed BASEDIR carries thousands of npz → the first o02 check is slow | `pos_len check` line reports > 10 000 files | still zip-header reads (~10 s); the marker makes every later cycle incremental |
| the ramp model disagrees with the validator's table by > 1 cycle | `first_exactly_one_cycle` outside 15–17 | do not tune; record both tables in `repair_R2.txt` and stage the discrepancy as an `[OPEN]` on o40 (c) for the chain to settle at cycle 5 / 16 |
| removing the rate constants breaks `--self-test` cases that relied on them | `--self-test` raises | give every case explicit `--train-samples-per-second`, `--selfplay-games-per-hour`, `--bytes-per-row` (new arg) |
| the engine log or sgfs of the 60-game run were pruned from scratch | `probe_search_9x9.py` finds 0 `Root visits` lines | the sha256 in `root_visits_hist-v299259.json` is the witness; if missing, R4 closes only on the sgf instrument of the loop's 80 games (0.2509) and says so |

## 12. Current State

- `[SOLID]` The defects are recorded on admitted rows with `path:line`: o39 (`loop.sbatch:8,:90`), o40 (`derive_knobs.py:252-267,:281-288`; `DESIGN.md:176-184,:353`; `knobs_9x9.env:106-108`; `derivation.md:118,:249`), o41 (`derive_knobs.py:320-321,:338-344`), o38 (`probe_search_9x9.py:94-95`; `audit_smoke.py:534-538`), o02 (`r_smoke_probe_training` open obligation: "a pre-shuffle call of `check_pos_len_npz.py` inside the loop copy").
- `[SOLID]` The policy script named by `mission.json` `compute.policyCheck` passes at `--gpus 1 --cpus 32 --partition b200` on 2026-09-04T06:43:18-04:00: `OK : request gpus=1 cpus=32 part=b200 within policy (gpu<=4, no cpu cap)`, exit 0 (b200 `free_gpus=1/128`, b300 `0/8`).
- `[SOLID]` o02 wiring DECIDED: wire it. The smoke proved no pos_len-19 row can exist on a fresh BASEDIR whose only writer is `selfplay_9x9.cfg` (S5), so the check is vacuous there — but it costs ~1 ms per new file, it is the only guard on a resumed or hand-populated BASEDIR, it turns a train-time assert (after a 1000-game selfplay stage) into a pre-shuffle refusal naming the file, and it discharges a `[BLOCKING]` obligation as written instead of re-wording it at launch.
- `[SOLID]` The re-bin targets exist on scratch: `runs/smoke_probe/search/selfplay/log20260904-055425-11022754EF29BF2B.log` (11 985 614 B, sha256 `59e2574e…`) and `…/t9-s1216-d1221/sgfs/580EB049130C5206.sgfs` (60 games); the validator's counts (1862 / 4872 / 667 of 7401; 2311/9211 on the loop sgfs) are in `root_visits_hist-v299259.json`.
- `[OPEN]` Nothing in this packet has run; every row in § 2 is `[HYPOTHESIS]` until its command exits 0 and the transcript is in `evidence/wave3_prelaunch_repairs/repair_R<n>.txt`.
- `[OPEN]` o39's third conjunct (one real-net cycle re-measuring `nlwp_max ≤ 32`) and o40 (c) (executed first-export cycle) are the chain's (`tasks/production_chain_9x9` P1, P4); o03 carries the measurement.
- `[OPEN]` o33/o36 (wrapper residuals, non-blocking) stay where they are; R1 is a `structural` change to the same file (the crash-triage constraint recorded in `current_iter.md` § 3(b)) and the error rows must say so.

## 13. Forbidden Actions

- Never change a knob VALUE (`knobs_9x9.env`, CHANGE 9 block, either cfg's `numGameThreads`); never raise `--gres` above `gpu:1`; never touch `smoke_loop.sbatch` or `ref-code/`.
- Never make the knobs file, the cfg assert or the pos_len guard advisory: each failure is `exit 2` (pre-flight) or a non-zero stage exit (loop), never a warning.
- Never "fix" a between-value by clearing the tree before cheap searches (`play.cpp:1147` is engine behaviour, not mission config); never re-tune the band; never re-bin the two unrecoverable 20-game rows from memory.
- Never keep a baked-in rate as a fallback behind a flag that `check_knobs_9x9.py` could pass by default.
- Never submit a job, never `scancel` anything, never append a result/claim/knowledge row (worker appends error rows only).

## 14. Promise Tag

- **Promise format:** `<promise>wave3_prelaunch_repairs CPUS_DECLARED ==32 AND POLICY_CHECK ==0 AND POS_LEN_GUARD WIRED AND MONITOR WIRED AND FIRST_EXPORT_CYCLE ==5 AND MISSING_KEY RAISES AND FULL_FRAC WITHIN [0.20,0.30]</promise>`
- **Required in commit body (per repair):** the verbatim § 2 command output, the shim-log lines for R1/R5/R6, the ramp table for R2, the B3 replay stderr for R3, the histogram line for R4, evidence paths, obligations touched, evidence type.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions: one commit per repair (`fix(resume,ktg)`, `fix(knobs,ktg)`, `fix(probe,ktg)`), tests before or with code; joint progress file `progress/paper_1902.10565/wave3_prelaunch_repairs/progress.md`; `${RESEARCH_STATE}` § Next Work Steps gets the o39/o02/o40/o41/o38 transitions and the launch unblock line.

## 16. Termination Checklist

- [ ] Every § 2 command ran and its output is in `evidence/wave3_prelaunch_repairs/repair_R<n>.txt`.
- [ ] Candidate rows staged: amended `r_loop_resume_under_walltime_static` (o39 wiring conjuncts, o02 wiring, R6), amended `r_cycle_knobs_9x9_derived` (o40 (a)(b), o41), new `r_smoke_full_frac_rebinned` (o38; proposes `playout_cap_randomization` → solid); claim transitions o39 (discharged; measurement conjunct → o03), o02 (discharged), o40 (narrowed to (c), open), o41 (discharged), o38 (discharged).
- [ ] `check_knobs_9x9.py` prints the same eleven values as before and `PASS`.
- [ ] Harness regression scenarios reproduce; the dry run stages 80 files.
- [ ] No silent scope expansion: six repairs, no job, no knob value moved.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected (none planned).
