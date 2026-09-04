# Validation of the fifth repair packet (o44, partition inheritance) — `loop_resume_under_walltime`; and of the L40S runnability row — `env_build`

Role: validator (refuter, then judge), cross-model relative to both workers. Inputs received: the
candidate rows `evidence/loop_resume/candidate_rows_repair5.json` and `evidence/env/candidate_rows_l40s.json`,
the worker transcripts `evidence/loop_resume/repair_partitions.txt` (sha256 `04c717e7…`, 2557 lines, equal to the
candidate file's hash) and `evidence/env/l40s-300987.txt` (sha256 `55184b87…`, equal), the artifact under test
`codes/loop/loop.sbatch` at `8e394116…` (commit `4c30b00`; the pre-repair file `0a03fbb2…` re-read from
`git show 56f2979:`), `mission.json` (`compute.partitions = [b300, b200, l40s]`, `decisions[3]`, `compute.policyCheck`),
the task file § 2, the contracts, and the ledger schemas. Host login03, CPU only, no Slurm job submitted, none
cancelled. **The production chain's link 1 was already queued when this validation started: job 301099, PENDING,
`Partition=b200,l40s`, `TimeLimit=23:30:00`, start estimate 2026-09-04T21:54; its stored batch script hashes to
`8e394116…` (`scontrol write batch_script 301099 -`), i.e. exactly the file validated here.**

Verbatim transcript: `evidence/loop_resume/validation_repair5_harness.txt` (sections 0–11, every harness source
included). The harness is the validator's own: a fixture-driven `sinfo` / `scontrol` / `sbatch` shim set written
without reading the worker's `hp_common.sh` beyond its interface, mirroring what the *real* `sinfo` and `scontrol`
printed on this cluster the same afternoon (section 2 of the transcript), layered on the wave-3 validator's
verbatim `w3v_common.sh` for the whole-wrapper runs. The wave-3 regression set and seed matrix were re-run with the
recorded `v2_regress.sh` / `v3_seeds.sh` (sha256 `9d4648ab…` / `02199feb…`, extracted by this validator and equal
to the worker's record).

## 0. Chain safety — read first

**No defect was found that would misroute or corrupt the successors of job 301099.** Specifically:

- The live link carries `KTG_PARTITIONS="b300 b200,l40s"` as a *command prefix* on the launcher's `sbatch` line
  (`evidence/production_chain/preflight.txt:892-896`), so the variable is in the `sbatch` process's environment and
  Slurm's default `--export=ALL` puts it in the job's environment; inside the job the plain
  `KTG_PARTITIONS="${KTG_PARTITIONS:-b300 b200}"` keeps the export attribute and `resubmit()`'s `sbatch` call
  carries no `--export` of its own (0 non-comment matches). Three chained links under the shims each saw
  `KTG_PARTITIONS='b300 b200,l40s'` in their `sbatch` environment and each resolved `--partition=b200,l40s` (VL5).
- A command-line `--partition` beats `SBATCH_PARTITION`: Slurm 25.11.2 `man sbatch` ("command line options will
  override any environment variables") and a live `sbatch --test-only` (queues nothing) that accepted
  `--partition=b200` with `SBATCH_PARTITION=zzz` in the environment and rejected the same request without the
  argv option (`invalid partition specified: zzz`). The wrapper's resolved value therefore always wins (VL6).
- With b300 in its present `IDLE+RESERVED` state, link 1 will queue link 2 on `b200,l40s`; the live
  `pick_partition()` extracted from `8e394116…` resolved `b200,l40s` against the real `sinfo`/`scontrol` this
  afternoon, and its per-partition free counts (b300 0, b200 12–13, l40s 4) equalled the policy script's own lines
  taken the same minute (three consecutive per-node snapshots, zero diff).

Three things the coordinator should know now, none a corruption and none introduced by this repair:

1. **Submission-time pinning.** `pick_partition()` runs when a link *starts*, and the successor it queues cannot
   start for up to one full link (23.5 h). If b300 shows one unreserved free GPU at that instant, the successor is
   queued on `b300` *alone* and is never re-evaluated; a reservation placed on gb301 afterwards (the pattern on this
   cluster: `ssci-adamgleave-aug2026` → `ssci-adamgleave-sep2026`, back to back) leaves that link PENDING in b300
   until the reservation ends. That is the human's stated preference ("b300 stays preferred when free") executed
   literally, and it stalls the chain without corrupting it; the manual remedy is `scancel` of the pending successor
   and a resubmission of that link with the knob. If stall-freedom matters more than the preference, the single-set
   spelling `KTG_PARTITIONS="b300,b200,l40s"` is accepted by the policy script and lets Slurm start wherever first.
   Recorded on the restated assumption `a04` and as a validator qualification on the result row.
2. **Upcoming reservations count as free.** A node whose reservation has not yet *started* (gb206 from 22:00,
   gb207 from 23:00 tonight) has no `RESERVED` in `State=` and is counted free by both `pick_partition()` and the
   policy script; a 23.5 h job will not be placed on it. This only affects the b300-vs-set choice, identically to
   the pre-repair function.
3. **The scratch clone every link stages changed at 16:52.** `python/train.py` in
   `$KTG_ROOT/build/KataGo` now carries the 7x7 packet's `KTG_PRINT_EVERY` hook (7 lines, default `100` = the
   stock interval, `mission.json decisions[4]`). Link 1 will copy it into its dated archive, as it copies the
   `cmake-sm100.diff` already there. The production submission line sets no `KTG_PRINT_EVERY`, so the default path
   runs; this is why the dry run's `du -sb` figure below is not the worker's 28835171 B.

## 1. Refutation attempts — the repair (o44)

Each attempt names what would have rejected, what was run, and the outcome. Transcript section in brackets.

- **R1. Unset knob must be byte-identical to the old function.** `pick_partition()` extracted from both files by
  function name; 56 cells (14 b300 states × alloc {0,1,7,8}) plus 14 b200-fallback cells: `before == after` in every
  cell, including `MIXED+PLANNED`, `IDLE+PLANNED`, `COMPLETING`, `DRAINED`, `ALLOCATED+RESERVED` (states the worker's
  27-cell matrix did not include). Whole-wrapper VL1 before/after: `--partition=b200`, the shim environment
  `KTG_PARTITIONS='<unset>'`. **Not refuted.** [4 M1/M1b, 5 VL1]
- **R2. `"b300 b200,l40s"` with a free b300 GPU → `b300`; b300 busy/reserved → `b200,l40s`.** Seven fixture
  scenarios including the real present state (`IDLE+RESERVED`), `MIXED 7/8` (one free), `IDLE` with 8/8 allocated,
  `MIXED+DRAIN`. All as claimed; before/after differ exactly where the defect was (`b200` → `b200,l40s`).
  **Not refuted.** [4 M2, 5 VL2–VL4]
- **R3. The comma set must SUM its members and must not count reserved/drained nodes.** Fixture with two b200
  nodes (one `IDLE+RESERVED`) and two l40s nodes (one `MIXED+DRAIN`): b200 = 2, l40s = 2, `b200,l40s` = 4; a set whose
  members are all idle-but-reserved/drained sums to 0 and falls through to the LAST candidate. On the real cluster the
  same code and the policy script agreed node for node (gb201/208/210/211/212/215/216 `RESERVED` → 0; gl110
  `MIXED+DRAIN` → 0). One earlier read gave b200 = 20 against the script's 12 seconds later; three consecutive
  per-node snapshots then agreed at 12 with zero diff, and the two counters are the same six lines of shell, so that
  was a scheduler-state transient, not a parsing difference. **Not refuted.** [2, 4 M3]
- **R4. Nothing free anywhere → last candidate.** `b200,l40s` after (was `b200` before). **Not refuted.** [4 M2, 5 VL4]
- **R5. Malformed candidates must be refused, never submitted.** `zzz`, `b300 zzz`, `,b200`, `b200,`, `b200,,l40s`,
  `b2*` (no matching file). The real `sinfo` *accepts* leading/trailing/double commas (returns the named
  partitions' nodes, exit 0) and prints nothing for `zzz` or `b2*` (exit 0), so `pick_partition()` hands the string
  on unchanged; the policy script's `case` then prints `VIOLATION`, `resubmit()` says "refusing to chain", and the
  `sbatch` shim log is empty in every case. **Not refuted.** The failure mode is a chain that ends (no successor),
  not a wrong submission. [2, 4 M4/M5, 5 VL7]
- **R6. Pathname expansion of the unquoted list — is `set -f` required?** With the job's cwd holding files named
  `b200`, `b2zz`, `b3xx`, `l40s.txt`: `b3*` → `b3xx` → VIOLATION, refused; `b2*` → `b200` → accepted and submitted
  to b200; `*` → `b200 b2zz b3xx l40s.txt` → `b200` (first with a free GPU) → submitted to b200; `b3* b200,l40s` →
  `b3xx b200,l40s` → `b200,l40s`. With `set -f` in force all three globs stay literal and are refused. The live
  job's `WorkDir` (`/weka/home/schmidt/ssci-haiyangw/az`) holds no `b*`/`l*` entry. **Decision: `set -f` is not
  required for chain safety** — no string outside the policy script's accepted set can reach `sbatch`, and the only
  accident is an *allowed* partition chosen from a file name; it is a hardening (`set -f` inside the function or a
  `local -` guard) for the next scheduled edit of an admitted script, not for a file a live chain is queued on.
  Recorded as the residual the worker already noted. [4 M4, 5 VL8]
- **R7. `SBATCH_PARTITION` in the environment.** Shim run with `SBATCH_PARTITION=b300` exported and the knob set:
  argv `--partition=b200,l40s`, environment `SBATCH_PARTITION='b300'`; with the knob unset and
  `SBATCH_PARTITION=b200,l40s`: argv `--partition=b200`. Which wins is a Slurm fact, settled by the man page and the
  `--test-only` pair in § 0. **Not refuted.** [3, 5 VL6]
- **R8. Propagation is only through the environment.** A knob set but not exported by the submitting shell does
  not reach the link (`KTG_PARTITIONS='<unset>'` in the shim log → default list, `b200`); `''` and `' '` take the
  default list. The launcher's prefix form exports it. **Not refuted.** [5 VL9/VL10]
- **R9. Regression set + seed matrix unchanged.** `v2_regress.sh` (46 links) and `v3_seeds.sh` (51 links) run
  unmodified against `8e394116…`: v3 normalised diff **0** with the worker's `norm.sed`; v2 normalised diff = **4
  lines** with `norm.sed` alone, all timing artifacts of the harness, not of the wrapper: three placements of bash's
  job-control message `Terminated` (the sampler pids `stage_monitor.sh stop` kills from `finalize`; the record itself
  carries it 21 times, twice in a row at ref:262-263) and one elapsed-seconds instance inside parentheses,
  `(rc=3 after 8s)`, which `norm.sed`'s rule needs a trailing space to match. With those two rules added
  (`norm3.sed`, listed) both diffs are **0**; line counts 632 vs 631 (the extra line is one `Terminated`) and
  420 vs 420. No accounting, breaker, scancel or successor line differs. **Not refuted; the worker's "normalised diff
  = 0" is reproduced under a normalisation that names one more artifact than the worker's did.** [6]
- **R10. § 2 closing check and the row's verification command.** Both exit 0 in a clean non-interactive bash
  (`afterany` 8, `failcount` 35, `cpp/build/katago` 5, `cpp/katago"` 0; policy `OK … part=b200`). Note for future
  validators: this agent shell defines `grep` as a *function* wrapping a different tool, under which the
  `REQ_CPUS="${KTG_CPUS_PER_TASK` conjunct fails; a non-interactive `bash -l` (what a batch job gets) and the
  ledger's subprocess both resolve `/usr/bin/grep`, and the 7x7 job's log shows GNU grep on the compute node. Not a
  property of the wrapper. [1, 8]
- **R11. `KTG_STAGE_ONLY=1` dry run byte-identical.** Twice from the real scratch clone: 87 files each, manifest
  diff exit 0, `cmp bin/katago` 0, `dataBoardLen = 9`. The `du -sb` total (28882815 B on ext4) is not the worker's
  28835171 B: `du -sb` adds directory entries whose apparent size is filesystem-dependent, and `python/train.py`
  changed at 16:52 (§ 0 item 3); the filesystem-independent sum of file sizes is 28837759 B. **Not refuted.** [7]
- **R12. Line references in the candidate rows.** At `8e394116…`: `KTG_PARTITIONS=` :287, `pick_partition()`
  :288-303, `resubmit()` :522-563 with the pick at :543, the policy call at :548 and `sbatch` at :554 — the
  candidate's ":287", ":288-303", ":548", ":554" are exact; its ":543-560" for `resubmit()` names the pick-to-sbatch
  span rather than the function, which is stated on the discharged row's notes. Static claims re-checked: code
  lines changed 4 + the assignment (the diff of `4c30b00` shows exactly those), `--export` 0 non-comment matches,
  `bash -n` clean on nine scripts, untouched files' hashes equal to the candidate's list.

## 2. Refutation attempts — the L40S row (r_env_l40s)

- **L1. Verification command.** Exit 0 as written (eleven `grep` conjuncts on the transcript plus the binary's
  sha256 `4d2bbed4…` on scratch, file dated Sep 3 22:02 — unchanged since the B200 build). [9]
- **L2. sacct.** Job 300987 `l40s COMPLETED 00:00:38 0:0 gl111 gres/gpu=1,cpu=9,mem=48G`; job 298018 (the B200
  reference) `b200 COMPLETED gb205`. The transcript's header lines are those records. [9]
- **L3. Is 2401.88 vs 2322.17 like for like?** Both are `katago benchmark … -v 80 -t 1 -boardsize 9` on the same
  `model.bin.gz` (sha256 `4e55191e…`); `smoke.txt:103` carries the B200 line verbatim. One thread, batch size 1,
  0.3 s — a latency figure. The row says so in its assumptions and in an `[OPEN]` item. **Not refuted, but the
  claim's closing sentence "the l40s partition is therefore usable by the production chain with the binary exactly
  as it stands" promotes a single-thread engine probe to a production statement.** Judge's narrowing (below).
- **L4. Which image served sm_89?** Inferred (sm_86 cubin under CUDA's minor-version rule), not measured; the
  probe did not run a `CUDA_FORCE_PTX_JIT=1` control. The row states this as an `[OPEN]` item and does not claim it.
  A load-time JIT would have shown as a stall; the 38 s wall clock (including torch import and a 9x9 forward/backward)
  and the 1.034× ratio make a JIT penalty implausible but not excluded. Left `[OPEN]` as the worker wrote it.
- **L5. Is `empirical` honest?** The claim's measured conjuncts (device line, `runtests` "All tests passed",
  benchmark line, zero "no kernel image" diagnostics, torch capability (8, 9), finite gradient, binary unchanged) are
  each a verbatim line of the job transcript and each is checked by the verification command. The status vocabulary
  allows `empirical` rows to carry visible `[OPEN]` items; the contract forbids promoting a measurement to `checked`,
  which the row does not do. **Honest for the measured claim; not honest for the "usable by the production chain"
  sentence**, which is narrowed at admission to "runnable by the production chain's engine and trainer" with the
  production-regime throughput and VRAM left where the row already puts them, `[OPEN]`.
- **L6. Its fourth `[OPEN]` item** ("loop.sbatch pick_partition() hard-codes …") is the defect this same validation
  discharges as o44; at admission it is replaced by a pointer to the discharge, so the row does not carry a stale
  open item.
- **L7. Obligation id collision.** The worker proposed `o44_arch_image_per_allowed_partition`; `o44` is the loop
  worker's `o44_chain_successors_inherit_partition_set`. Landed as **`o45_arch_image_per_allowed_partition`**, opened
  and discharged for the three allowed partitions by `r_env_l40s`, with the collision stated in its notes.
- **L8. Dependencies.** `arxiv-1902.10565::env_build` is `solid` in the knowledge ledger; `env-toolchain-b200` is
  an admitted result row (`132224eb…`); the two code paths exist. Resolvable.

## 3. Verdicts

| candidate | verdict | gate | row |
|---|---|---|---|
| amended `r_loop_resume_under_walltime_static` (iteration 8, `existence_only`) | **Admit** with validator qualifications (vii)–(x) appended to the claim | all gates pass; nothing ran under a real scheduler, so the status stays `existence_only` | see § 3a |
| `o44_chain_successors_inherit_partition_set` open → discharged | **Admit** — every closing condition in the proposal reproduced (R1–R11) | — | see § 3a |
| `a04_b200_fallback` | restated, same id, `active` | the fallback is now the LAST candidate of `KTG_PARTITIONS`; the preference is evaluated at the successor's submission | see § 3a |
| `r_env_l40s` (`empirical`) | **Admit** with the claim's last sentence narrowed and `[OPEN]` item 4 replaced | evidence matches the type; the promoted sentence would have failed gate 3 | see § 3a |
| `o45_arch_image_per_allowed_partition` (proposed as `o44`) | **Admit** as `o45`, open → discharged for b300/b200 (sm_100, job 298018) and l40s (sm_89 via sm_86, job 300987) | — | see § 3a |

Nothing was rejected; no `[OPEN]` repair obligation was opened. The two error-ledger rows are the validator's own
`pass` trials for the two packets.

### 3a. Rows appended (`CHANDRA_ROLE=validator`, 2026-09-04T21:47Z; hashes are the ledgers' `row_hash`; every gate ran, no bypass flag)

| ledger | row | status | row_hash |
|---|---|---|---|
| result | `r_loop_resume_under_walltime_static` (iteration 8, amends `d71a8172…`; verification command re-run by the gate, exit 0; evidence sha `04c717e7…`) | `existence_only` | `423b1bdffe31fef1ee09d37d479886526a96ae41059f87cc045294fd286584f0` |
| claim | `o44_chain_successors_inherit_partition_set` | `open` | `e0d771e8614755f551267265ad92fa6ea332b11dbdc424e105609fb06a879548` |
| claim | `o44_chain_successors_inherit_partition_set` (discharged_by `r_loop_resume_under_walltime_static`) | `discharged` | `397ce637a2794b3f6269a17a02b77f1c60c5f4818dac5139e2e6fb49ef83ccaf` |
| claim | `a04_b200_fallback` (restated, same id; supersedes `6d54dc20…`) | `active` | `1b0791c0146ec1830e1dc22b4b24ddcd3d433a86cc2e2c7dfb483e510a11de1c` |
| result | `r_env_l40s` (iteration 3; verification command re-run by the gate, exit 0; evidence sha `55184b87…`) | `empirical` | `d7e99fbdfe08dd08671811a833fdaf8d05eb5051e0223ef408653e443bd90e28` |
| claim | `o45_arch_image_per_allowed_partition` (the worker's proposed `o44`, renumbered) | `open` | `a705084fff4eb3f42bf87925210ef28bdc60bdb8680e4ecfeb785b5058965565` |
| claim | `o45_arch_image_per_allowed_partition` (discharged_by `r_env_l40s`) | `discharged` | `0de45133a5ac770595f22bf497d917b279958366f803005de74196d414e95203` |
| error | validator trial, node `loop_resume_under_walltime` (node_seq 19) | `pass` | `6ebe62f9cfda205d69e4f6284d80668498f3ffa555e6589961936691f384423e` |
| error | validator trial, node `env_build` (node_seq 2) | `pass` | `049878928166103820a91e01b518f52656ddbb0410ead8ac8df9bacd4ac9a47f` |

Views re-rendered from the ledgers: `decomposition/{claims,obligations,assumptions}.md` and `decomposition/results.md`.
Harness transcript sha256 `15dd9913f07297565b568c3d7447c20d423c1b3b119b126b8c2ea7b503fb051e` (cited on both result rows).

## 4. Remaining `[OPEN]`

- **Stall risk of submission-time pinning to `b300`** (§ 0 item 1) — a design property of the human's preference,
  not a defect; the coordinator may prefer `KTG_PARTITIONS="b300,b200,l40s"`.
- **`set -f` hardening** of the unquoted list (R6) — next scheduled edit of `loop.sbatch`, not now.
- **The scratch clone is shared and mutable** (§ 0 item 3) — every link stages whatever `python/` holds at its
  start; a second packet editing the clone mid-chain changes what later links run. Worth a pin (a per-chain clone or
  a recorded `git diff` in each link's log) before an unattended second chain.
- L40S production regime: throughput at 25–28 threads, batched `nnEvals`, and VRAM at production batch sizes are
  not characterised (the row's `[OPEN]` items 2–3); which arch image served sm_89 is inferred (item 1).
- Carried from earlier packets and untouched here: o25, o33, o36, o42, o03 (executed real-net `nlwp_max`), c07, c08.
