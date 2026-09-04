# progress — `synchronous_loop_smoke`

Node: `arxiv-1902.10565::synchronous_loop_smoke`
Task: `results/ktg/paper_1902.10565/tasks/synchronous_loop_smoke/implementation.md`
Also carries the § 2 probes of `paper_code_map_search` (leg D1) and `paper_code_map_training` (leg D2).

## Attempts

| # | job | state | legs | outcome |
|---|---|---|---|---|
| 1 | **298712** | `COMPLETED 0:0`, gb207, `00:05:53` | A=0 B=0 C=0 **D1=1 D2=1 E=1** | all six legs RAN; nothing skipped, no `STOP`, no marker reuse. `A.done B.done C.done` written |
| 2 | **299259** | `FAILED 1:0`, gb207, `00:05:06` | A/B/C **skipped** from markers, D1=1 **D2=0** E=1 | `D2.done` written; the exit code is now correct |

Job 298712 ran the working tree at az commit `9fdeb6b`, i.e. `codes/loop/synchronous_loop_9x9.sh`
**with** the o34/o35 repairs (`6b83dc0` `set -eu -o pipefail`, `0c6d38d` base-10 counters, the
`$BASEDIR/.cycles_completed` counter — which holds `2`).

## Sub-results

| # | outcome |
|---|---|
| S1 `cycles_completed` | **2** ✓ |
| S2 exported / gated | **2 / 1** ✓ (`t9-s1216-d1221` rejected, `t9-s2528-d2534` pending) |
| S3 `gate_random` | **1** ✓ |
| S4 `sz_other` | **0** over 236 sgf lines ✓ |
| S5 row bytes | **2145** raw and shuffled ✓ |
| S6 resume | **1216 → 2528** samples, 0 re-inits, 172 finite metric terms ✓ |
| S7 `full_frac` | **0.33304 / 0.34414 / 0.34171** over three runs — band **refuted**, forks excluded by direct test |
| S8 rows/game | real **31.95 / 34.40**, random **31.675** — in `[12, 35]` ✓ |
| S8 bytes/game | **10.944 KiB** vs c10's `≤ 10 KiB` — **refuted** |
| S9 `nlwp_max` | real-net **25 > 24** (reproduced by two independently scoped samplers), train 14 |
| S10 `o30` | **discharged** — `a1f26db6…`, `verification_run.exit_code 0`, no `admission_flags` |
| S11 gpool / row bytes | **PASS** 4/4 |
| S12 kill+resume | **PASS** 6/6 — `4992 → 14976`, rows `5068 → 5068`, no re-init |
| S13 throughput | 6112 MiB VRAM, GPU 80 %/28.2 %, 353.8 B/row |


## Ledger appends by the worker

- error `4566497308b2445511a64d660419bcc74009bf7648db42b5b1410a8d1739edd2` — attempt 1, `partial`
- error `d3e3dcb75124ca004a1f092f9fa4663e8e6d2941839a1a40ab27b1d649ee2c49` — post-hoc CPU recovery, `pass`
- knowledge `a1f26db6fc8efc14f9085f1d5a3851fd4833e1be666c24ca2b1c2b28537ad27c` — leg A, `o30`

Everything else is staged for the validator in `evidence/smoke/candidate_rows.json`
(5 result groups + 10 claim transitions; every `verification.command` exits 0 on the login node).

## Resume procedure when 299259 is terminal

1. `sacct -j 299259 -X -n -o JobID,State,ExitCode,Elapsed,NodeList` and `seff 299259`.
2. `cp $KTG_ROOT/logs/ktg-smoke-299259.out results/ktg/paper_1902.10565/evidence/smoke/smoke-299259.txt`
3. `python3 results/ktg/paper_1902.10565/codes/eval/audit_smoke.py \
      /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/smoke \
      --evidence results/ktg/paper_1902.10565/evidence/smoke && \
    test -s results/ktg/paper_1902.10565/evidence/smoke/rows_per_game.txt`
4. Read `evidence/smoke/probe_search_nofork-299259.json` (S7) and `probe_resume-299259.json` (S12).
5. Append the attempt-2 error row, extend `candidate_rows.json` groups `r_smoke_probe_search`
   and `r_smoke_probe_training`, commit `exp(smoke,ktg)`.

## Open

- `[BLOCKING]` `o03` / `c06` real-net clause — 25 threads against 24 declared CPUs. Needs
  `--cpus-per-task ≥ 25` and `numGameThreads` moved **together**; that is `derive_cycle_knobs_9x9`'s
  call, recorded in `DESIGN.md § 1`.
- `[OPEN]` S7, S12 — attempt 2.
- `[OPEN]` two-real-net gatekeeper threads — first measurable at `gatekeeper_stage`, cycle 3+.
- `[OPEN]` `c13` acceptance is **not** settled here; one gate on a 256-sample net is not evidence.
- `[OPEN]` mechanism behind `full_frac = 0.342` — the `root_visits_histogram` the probe now records resolves it at no extra allocation cost.
- `[OPEN]` `c10` amendment — refuted as written on the byte conjunct; the validator decides the wording.
- `[OPEN]` `o37` worker half repaired here (per-job sampler files, `--tag` outputs); the transition is the validator's.
- Attempts used: **2 of 3. No third allocation requested** — every remaining gap is recorded or CPU-settleable.
