# Validation — node `arxiv-1902.10565::cfg_9x9_override`

Independent validator (refuter, then judge), 2026-09-04. Inputs: the candidate rows in
`candidate_rows.json`, the evidence in this directory, the four artifacts under `codes/`, the
upstream mirror at `fd0723fd` (v1.18.2), the worker's error row `abfb7390…`, Slurm accounting for
job 298359, and the ledger state at HEAD `deb3d19`. The worker ran on a different model.

## 1. Refutation attempts

Each item names what was tried, the command, and whether it refuted anything.

### 1.1 Key set changed in each config is exactly what the task file allows
- `diff ref-code/…/selfplay1_maxsize9.cfg codes/cfg/selfplay_9x9.cfg` (full, comments kept): a
  12-line provenance comment header inserted at the top, then `dataBoardLen 19->9`,
  `numGameThreads 128->18`, `bSizes 7,8,9->9`, `bSizeRelProbs 1,1,8->1`,
  `allowRectangleProb 0.50->0`. Nothing else.
- Same for the gatekeeper: header, then `numGameThreads`, `bSizes`, `bSizeRelProbs`,
  `allowRectangleProb`. Nothing else.
- Task file §10 requires precisely these value changes (`numNNServerThreadsPerModel` and
  `cudaDeviceToUse` are *allowed* to change but §10 says leave them; they are unchanged).
  Extra keys: none. Missing required changes: none. Comment-stripped significant line counts
  101/101 and 62/62 — no key added or removed. **Not refuted.**

### 1.2 `train_9x9.sh` differs from upstream in exactly one line?
- `diff <(grep -v '^\s*#' upstream/train.sh) <(grep -v '^\s*#' codes/loop/train_9x9.sh)` →
  a single hunk `80c80: -pos-len 19 -> -pos-len 9`. Full diff additionally shows a 10-line
  comment header inserted after line 2.
- So the literal wording "exactly one line" in the candidate knowledge summary is imprecise:
  it is exactly one *non-comment* line plus an inert header. Functionally the claim holds;
  the summary wording was narrowed at admission (§2.2). **Not refuted; wording narrowed.**

### 1.3 The two-run deviation (1 game for parse, 36 games for the thread sample)
- Task file §2 check 5 says the `ps -o nlwp=` sample is taken "while stage 3 runs" (the
  1-game run). The worker instead ran a second `-max-games-total 36` process and sampled that.
- `cpp/command/selfplay.cpp:291-293`: `gameIdx = numGamesStarted.fetch_add(1); if(gameIdx <
  maxGamesTotal) { … }` — with `maxGamesTotal = 1` only the thread that draws index 0 plays;
  the other 17 fall through to `break` (`:313-322`). The job's own `selfplay_parse.log` shows
  `Game loop thread 1 … terminating` through thread 17 within the same second. A peak sampled
  on that process would depend on whether `ps` landed before or after the 17 exits.
- 36 = 2 games per game thread keeps all 18 busy; `selfplay_threads.log` reports
  `Final games finished: 36`. The deviation is justified, documented in the task file §12,
  the checker header, the error row and the candidate rows. **Not refuted.**

### 1.4 Does the SGF count prove 9x9-only? What about `allowRectangleProb=0` / `bSizeRelProbs`?
- Empirically: `cat …/sgfs/*.sgfs | grep -o 'SZ\[[^]]*\]' | sort | uniq -c` on the job's
  files (archived before the re-run at
  `/scratch/…/ktg-train/runtime/cfgcheck-job298359-archive/`, sha256
  `44afe357…`, `6e1aecc3…`) → `37 SZ[9]`, nothing else. One SGF per line
  (`selfplaymanager.cpp:377-378`), `SZ[x:y]` for rectangles (`sgf.cpp:2013-2015`).
- A count over 37 games cannot by itself exclude a rare size. The proof is structural:
  `cpp/program/play.cpp:137-172` builds `allowedBSizes` from `bSizes`; with one edge (9) the
  double loop has a single `(9,9)` cell, and off-diagonal (rectangular) cells are emplaced
  only under `if(allowRectangleProb > 0.0)` — with `allowRectangleProb = 0` they never exist.
  `bSizeRelProbs = 1` is arity-matched (`:149-150` would throw otherwise; check 3's exit 0 is
  that proof). `startPoses*` / `hintPoses*` are commented out in the config, so no SGF-seeded
  positions can import another size. The sampler does not consult the net, so the random-net
  run is representative for board size. **Not refuted.**

### 1.5 Does NLWP sampling capture the peak?
- Thread inventory of a `katago selfplay` process at v1.18.2: 18 game threads
  (`selfplay.cpp:359-362`), 0 search helpers (`numSearchThreads = 1`;
  `searchmultithreadhelpers.cpp:39-53` spawns `numThreads-1`), 1 NN server thread
  (`nneval.cpp:433-441`, spawned even with `debugSkipNeuralNet` — the log shows `GPU -1
  finishing`), 1 detached data-write thread (`selfplaymanager.cpp:156`, created at model load,
  lives to shutdown and also writes the SGFs), 1 model-load loop thread (`selfplay.cpp:364`),
  main. Total 22. All are long-lived for the duration of the run, so any sample in the steady
  state sees the peak; 52 samples at 50 ms over a 6 s run did. Measured 22 = arithmetic.
- **Limitation found (not a refutation of what was measured):** the process ran the random
  net with `debugSkipNeuralNet` (`setup.cpp:126`), so `nneval.cpp:134` created no CUDA
  context. A production selfplay process carries CUDA-runtime threads invisible here. The
  candidate's own assumptions state this; the candidate's proposal to treat the *selfplay
  clause of c06 as discharged* does not survive it. Consequence: c06 → `in_progress`, not
  admitted; o03's selfplay clause stays open pending a real-net measurement at
  `selfplay_stage`. The 22-thread figure itself is admitted as stated (random net).

### 1.6 Job 298359 accounting vs evidence
- `sacct -j 298359 -X -n -o JobID,State,ExitCode,Elapsed,NodeList,AllocTRES%50` →
  `COMPLETED 0:0 00:00:09 gb205 billing=24,cpu=24,energy=3429,gres/gpu=1,mem=64G`. Start
  `2026-09-04T00:30:22` local = evidence `date_utc 2026-09-04T04:30:23Z`. Steps `.batch` and
  `.extern` both `COMPLETED 0:0`. Evidence header: `SLURM_CPUS_PER_TASK = 24`,
  `SLURM_MEM_PER_NODE = 65536`, host `gb205`. `cfg_9x9_check.sbatch` requests exactly that.
- `diff` of the Slurm `.out` (`/scratch/…/logs/ktg-cfg9x9-298359.out`) against
  `check_cfg_9x9-298359.txt`: identical up to the appended sacct/seff block; `.err` is empty.
  **Not refuted.**
- Timing note: the checker and the configs were *committed* (978f746 00:33, f5df1a4 00:36)
  after the job ran (00:30). Nothing in git can prove the committed bytes equal the bytes the
  job executed — which is why the knowledge row's `verification.command` re-runs the checker
  on the committed artifacts inside the validator's own allocation (§2.3).

### 1.7 Proposed statuses
- Knowledge `preliminary`, not `solid`: predecessors at HEAD are `selfplay_search_params`,
  `game_randomization_9x9`, `gating_rule`, `data_format_pos_len` = `preliminary` (seq 2 each),
  `env_build` = `solid` (seq 2). Four preliminary predecessors block `solid`. **Confirmed.**
- `c04_9x9_only_games` (needed evidence `numerical_simulation`, result evidence type
  `numerical_simulation`): admitted on `cfg-9x9-override` with the structural argument of
  §1.4 in the notes; `selfplay_stage` re-checks production SGFs with `grep -L`.
- `c05_pos_len_9_pipeline`: the candidate result row's claim sentence lists it as a claim of
  this result. c05 requires a shuffle plus a training epoch; neither ran. This node only sets
  its preconditions (`dataBoardLen = 9`, `-pos-len 9`). Over-claim → the admitted claim
  sentence says "sets the configuration preconditions of c05 without evidencing it"; c05 is
  left `open` (its task is `shuffle_stage`).
- `c06_threads_le_24` "half-discharged": the ledger has no partial state for claims; and per
  §1.5 the selfplay clause is not fully evidenced. → `in_progress` with the measurement
  recorded and the CUDA-thread gap named.
- `o01_bsizes9_override`: fully met → `discharged`, `discharged_by = cfg-9x9-override`.
- `o02_databoardlen_poslen_9`: coupling clause met, discard clause not yet live → stays
  `open`; owner moved to `shuffle_stage` (the candidate result row itself lists o02 under
  `open_obligations`, so this agrees with the worker).
- `o03_thread_budget_24cpu` "half-discharged": no partial state for obligations; stays `open`
  with the justification restated per `mission.json decisions[0]` (worker deferred this
  amendment to the validator) and the selfplay measurement recorded as partial.
- `o13`/`o17`: not this node's; already handled by the `loop_resume_under_walltime`
  validator. `a11`/`o22`: already retired/waived at `befb3b1` by the data_budget worker; no
  transition owed here.
- Residual, not a gate: `gatekeeper_9x9.cfg` is key-diffed and value-asserted but no
  gatekeeper process parsed it; the task file does not require one, and `gatekeeper_stage`'s
  first run is that test. Recorded in the knowledge row's notes.

### 1.8 Refutation verdict
No gate fails on the evidence as measured. Two claim sentences were promoted beyond the
evidence (c05 as a claim of this result; c06's selfplay clause as discharged) and one summary
phrase was imprecise ("exactly one line"). All three are wording of the *rows*, not of the
artifacts or the measurement, and were narrowed at admission rather than bounced — the
narrowed rows claim strictly less than the candidates. Proceed to judge.

## 2. Judgement

**Verdict: ADMIT (narrowed), knowledge status `preliminary`, with one visible bypass and one new
blocking obligation to close it.** Gate named for the one deviation: the admission contract's
"verification commands are EXECUTED" clause was not met for the knowledge row (§2.3); it is
recorded on the row as `admission_flags: ["skip_exec"]` and repaired by `o30`.

### 2.1 Compute-policy pre-flight
the compute-policy script named by `mission.json compute.policyCheck`, run as `--gpus 1 --cpus 24 --partition b200`, → exit 0
(`OK : request gpus=1 cpus=24 part=b200 within policy (gpu<=4, no cpu cap)`; b200 and b300 both
`free_gpus=0`).

### 2.2 Result row — appended from the login node (verifier is a CPU-only evidence re-check)
`CHANDRA_ROLE=validator python3 phys-agentic-loop/_common/result_database.py append --row-file …/result_row.json`
```
{"appended": true, "paper": "arxiv-1902.10565", "result_id": "cfg-9x9-override", "status": "empirical", "timestamp": "2026-09-04T04:45:32.064316+00:00", "evidence_sha256": "e39348bf760d7ef64980beb71117aa1c1d639c858ce31d64078fb5fc0629ddd3", "verified_exit_code": 0}
```
Row hash `113f9d57dac5b2fe7f2038f1b8635c187d884d472e54f652e27961a635058508`, status `empirical`, `verifier_result.execution.exit_code = 0`,
`admission_flags` none. Narrowing relative to `candidate_rows.json`: claim sentence states
comment headers, "one changed non-comment line", the structural play.cpp argument, the
random-net/no-CUDA-context condition of the thread peak, c05 as precondition-only, c06 as partial.

### 2.3 Knowledge row — allocation not obtainable; appended with the documented bypass
The row's `verification.command` runs two selfplay processes, so the append was launched inside
`srun --account=ssci-anima --partition=b200 --gres=gpu:1 --cpus-per-task=24 --mem=64G --time=00:20:00`
(job **298524**). `squeue --start` put it at 2026-09-04T21:00 (~20 h) with `free_gpus=0/128`; on
the coordinator's decision the job was cancelled after the brief's pend cap and the row appended
from the login node with `--skip-exec`. Verbatim srun/scancel log
(`validator_append_knowledge_srun.txt`):
```
== validator knowledge-row append, launched 2026-09-04T04:45:48Z from login03
== srun --account=ssci-anima --partition=b200 --gres=gpu:1 --cpus-per-task=24 --mem=64G --time=00:20:00 --job-name=ktg-cfg9x9-val
[BILLING] loaded!
[BILLING] Re-emitting cost at job start!
srun: job 298524 queued and waiting for resources
srun: Job has been cancelled
srun: error: Unable to allocate resources: Job/step already completing or completed
SRUN_WRAPPER_EXIT=1
== finished 2026-09-04T04:49:16Z
== 2026-09-04T04:49:19Z scancel 298524 by the validator on the coordinator's decision: squeue --start estimated 2026-09-04T21:00 (~20 h; b200 free_gpus=0/128), beyond the 25-min pend cap of the brief.
== sacct -j 298524 -X -n -o JobID,State,ExitCode,Elapsed,NodeList
298524       CANCELLED+      0:0   00:00:00   None assigned 
== consequence: the knowledge row is appended from the login node with --skip-exec (recorded in admission_flags); the executed evidence is the worker's job 298359; re-execution inside a GPU job is obligation o30_cfg_9x9_knowledge_verify_in_allocation (owner synchronous_loop_smoke).
```
`CHANDRA_ROLE=validator python3 phys-agentic-loop/_common/knowledge_database.py append --skip-exec --row-file …/knowledge_row.json`
```
{"appended": true, "git_commit": "deb3d19", "timestamp": "2026-09-04T04:49:45.347934+00:00", "paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::cfg_9x9_override", "status": "preliminary", "evidence_sha256": "e39348bf760d7ef64980beb71117aa1c1d639c858ce31d64078fb5fc0629ddd3", "admission_flags": ["skip_exec"]}
```
Row hash `32f53697d4f3ba7fbf1a4c86ae6e94370b7ef3c7424354e44e964cf4444b1936`, `node_seq 3`, status `preliminary`, `admission_flags ['skip_exec']`,
`evidence_sha256 e39348bf760d7ef64980beb71117aa1c1d639c858ce31d64078fb5fc0629ddd3` (= the result row's, same evidence file). What stands behind
the row instead of a gate execution: the worker's job 298359 executed the identical command
(COMPLETED 0:0, gb205, 24 CPUs, 1 GPU), its transcript is the content-hashed evidence file and is
byte-identical to the Slurm `.out` up to the appended sacct/seff block (§1.6), and the artifacts it
ran against are the committed ones at 978f746/f5df1a4 (not provable from git alone — §1.6 —
which is exactly what `o30` closes). `preliminary` is also the ceiling from predecessors (§1.7).

### 2.4 Claim-ledger transitions (settling refs resolved by the gate; all exit 0)
| entry | status | row hash |
|---|---|---|
| `o30_cfg_9x9_knowledge_verify_in_allocation` | `open` | `798b43886b8744be4243628b7d102da43a941589d72bfe775f388e76bf319cf0` |
| `o01_bsizes9_override` | `discharged` | `2741aacc440f4c66a452303c1c43b46f53d90fdf66b5c311de425e163bc4cb0d` |
| `o02_databoardlen_poslen_9` | `open` | `d0041f3ebdb4c336883c2d33f2bfd82fa72f198541e300c6d703848a2aa37b2f` |
| `o03_thread_budget_24cpu` | `open` | `6e6f3129c73182690b8aa75cd417c9dd70a75ea8e708ac0bd61706b7d8bd3e8c` |
| `c04_9x9_only_games` | `admitted` | `aaa5bf251e5f14a93b9c6aa4587b73fe3b39b160f6559954b811bc6c3e58601b` |
| `c06_threads_le_24` | `in_progress` | `6ea339170c87292e385411d3b840245833ad2f0f7ea14d4029358e40fbeec9e3` |

- `o30_cfg_9x9_knowledge_verify_in_allocation` — NEW, blocking, owner `synchronous_loop_smoke`:
  re-append the knowledge row with the gate actually executing the checker inside that node's GPU
  job, superseding the `skip_exec` row.
- `o01` discharged by `cfg-9x9-override`; `c04` admitted on `cfg-9x9-override`; `c06` → `in_progress`
  (selfplay clause partial, CUDA-runtime threads unmeasured); `o02`, `o03` amended, still `open`
  (see §1.7 for each reason). `c05` left `open`, untouched.

### 2.5 Rendered views refreshed
`claims_database.py render-md --paper arxiv-1902.10565 --out-dir results/ktg/paper_1902.10565/decomposition`
(claims.md / obligations.md / assumptions.md) and `dag_mermaid.py render … --out decomposition/logic.md`.

### 2.6 Remaining [OPEN] items touching this node
- `o30` — gate-executed re-append of the knowledge row inside a GPU job (`synchronous_loop_smoke`).
- `o03` — real-net `ps -o nlwp` for selfplay (`selfplay_stage`), gatekeeper (`gatekeeper_stage`), train (`train_stage`).
- `o02` — discard-pos_len-19-data guard before the first shuffle (`shuffle_stage`).
- `c05`, `c06` — settle at shuffle/train and selfplay/gatekeeper stages respectively.
- `visit-caps-9x9`, `gate-visits-9x9` (convention.md §10) and `-attn-logit-penalty-cap` — owned by
  `selfplay_stage` / `export_stage`, unchanged here.
- `gatekeeper_9x9.cfg` has never been parsed by a gatekeeper process (first run = `gatekeeper_stage`).
- Node stays `preliminary` until the four preliminary predecessors go `solid` and `o30` closes.
