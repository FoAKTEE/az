# Validation record — `arxiv-1902.10565::data_budget` (candidate result row `data-budget-guard-500gib`)

Role: Chandra VALIDATOR (refuter, then judge), cross-model from the worker. Host `login03`, CPU only, no GPU job. cwd `/home/schmidt/ssci-haiyangw/az`, branch `main`.
Inputs received: `tasks/data_budget/implementation.md`, `evidence/data_budget/candidate_rows.json` (1 result row, staged `empirical`), `evidence/data_budget/*.txt`, `codes/data_budget/{budget.env,scratch_guard.sh,prune_retention.py,tests/}`, the worker's `data_budget` rows in `results/ledgers/error/paper_arxiv-1902.10565/trials.jsonl`, `mission.json` (`decisions[]`: 500 GiB scratch budget, no CPU cap), the ledger schemas and the admission contract.

## Verdict

**ADMIT at status `conditional`** (not the staged `empirical`), with the claim narrowed to what the evidence shows. Result row `data-budget-guard-500gib`, row hash `5cf754db629df666f97e1e5596da536cb4eb4b35f795c31ea5feda1af7a007a6` (first append `8a2396de99000194d240ce5ba096c7d7ef5fadd9c5827d97f6c917bde18c530d`, superseded only to renumber an obligation reference; see § 6).

Gate outcome in plain language (spec gates 3-6 are the validator's brief):
- Gate 3 (evidence matches the evidence type): PASS for `empirical_measurement` — the fixture-driven exit-code contract, the synthetic retention runs and the `du -sb` are executed measurements.
- Gate 6 (empirical claims specify code/protocol, checks, uncertainty, artifacts): PASS for the guard artefacts.
- "Claim promoted beyond what the evidence shows": **FAIL as staged, repaired by narrowing.** (a) The staged claim said the guard "cannot be loosened by an environment variable"; probes ADV2-ADV4 below show `KTG_SCRATCH_ROOT`, `KTG_CYCLE_PROJECTED_BYTES` and `KTG_BUDGET_ENV` each loosen it — only the *threshold* variables are pinned, and contract case C tests only `KTG_SCRATCH_HARD_BYTES`. (b) The retention half of the claim holds only with `--root`: without it the pruner exits 3 (ADV1), and the wrapper call contract written in the `scratch_guard.sh` header passes no `--root`. (c) Nothing here measures production behaviour — no wrapper calls the guard (o04 conjunct b, now o27) and no loop data exists — so `empirical` for the protective claim is not honest; `conditional` with the conditions listed on the row is.
- Node-closure gate 4 (no `[BLOCKING]`/`[OPEN]` on the checked-claim path): not met — recorded, not hidden: `codes/loop/loop.sbatch:74-75,195` still hard-code `214748364800` / `193273528320` (o04 conjunct b; another validator's node, tracked as `o27_scratch_guard_reconcile_500gib`). The claim is therefore admitted only as far as the guard itself.

## 1. Re-run of the 11-case exit-code contract (verbatim, validator)

```
== scratch_guard exit-code contract  2026-09-04T00:05:51-04:00 ==
guard: /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/../scratch_guard.sh
PASS  exit 0   A. within budget, default 20 GiB projection
PASS  exit 1   B. projected write crosses the 500 GiB hard cap
PASS  exit 1   C. a stray KTG_SCRATCH_HARD_BYTES in the environment cannot loosen the cap
PASS  exit 1   D. current usage already over the cap, zero projection
PASS  exit 2   E. group scratch free space below the safety floor
PASS  exit 0   F. group free below the warn floor only: warns, does not abort
PASS  exit 3   G. mission root does not exist
PASS  exit 3   H. malformed --projected-bytes
PASS  exit 3   I. unknown argument
PASS  exit 3   J. constants file missing
PASS  exit 0   K. quotas.py unreadable: falls back to df on the same pool and warns
== 11 passed, 0 failed ==
```
`bash results/ktg/paper_1902.10565/codes/data_budget/tests/run_guard_tests.sh` exit 0. Matches the worker's `evidence/data_budget/guard_exit_contract.txt` (11/11).

## 2. Re-run of the § 2 verification command (verbatim)

```
section2_verification exit=0
== scratch_guard 2026-09-04T00:06:52-04:00 [validator re-measure] ==
constants            : /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env
root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
du -sb               : 7558580421	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
df -B1               : wekafs1/scratchssci 40000000000000 37625166176256 2374833823744 95% /weka/scratch/schmidt
quotas.py            | +--------------------------------------------------------+
quotas.py            | | Usage for [31mssci-haiyangw[0m as of [31mFri Sep  4 00:01:02 2026[0m |
quotas.py            | +----------------------+----------+-----------+----------+
quotas.py            | |          FS          |   Used   |   Quota   |  Used %  |
quotas.py            | +----------------------+----------+-----------+----------+
quotas.py            | | /home/[31mssci-haiyangw[0m/ | 3.40 GB  | 100.00 GB |  3.40%   |
quotas.py            | | /scratch/[31mssci-anima[0m/ | 37.63 TB |  40.00 TB |   94%    |
quotas.py            | +----------------------+----------+-----------+----------+
projected write      : 21474836480 B
projected root total : 29033416901 B   (hard cap 536870912000 B = 500 GiB)
group scratch free   : 2370000000000 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
scratch_guard: OK  used=7558580421 B  projected_total=29033416901 B  group_free=2370000000000 B
guard exit=0
```
The admission gate re-executed the same command at both appends: `verified_exit_code: 0` (durations 33-40 s). `du -sb` = 7558580421 B ≤ 536870912000 B. Note the free-space source flipped to `quotas.py` (2370000000000 B) because it was now the smaller of the two — the `min(quotas.py, df)` rule behaving as designed.

## 3. Adversarial probes of `scratch_guard.sh` and the pruner default path (verbatim)

```
##### ADVERSARIAL 1: pruner with NO --root (the call contract in scratch_guard.sh header: python3 $PRUNE --apply) -- dry run without --apply
prune_retention: mission root does not exist: ${KTG_SCRATCH_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}
== prune_retention 2026-09-04T00:07:45-0400 DRY-RUN ==
constants : /weka/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env
root      : ${KTG_SCRATCH_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}
basedir   : ${KTG_SCRATCH_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}/loop
exit=3

##### ADVERSARIAL 1b: what load_budget parses KTG_SCRATCH_ROOT as
KTG_SCRATCH_ROOT -> '${KTG_SCRATCH_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}'
KTG_CYCLE_PROJECTED_BYTES -> '${KTG_CYCLE_PROJECTED_BYTES:-21474836480}'

##### ADVERSARIAL 2: KTG_SCRATCH_ROOT env var redirects the measured root to an empty dir -> a 529 GB projection passes
== scratch_guard 2026-09-04T00:07:45-04:00 [ADV2 env-root-redirect] ==
root                 : <scratch>/emptyroot
du -sb               : 4096	<scratch>/emptyroot
projected root total : 529312337096 B   (hard cap 536870912000 B = 500 GiB)
VIOLATION: group scratch free space 147707842560 B is below the 1099511627776 B safety floor.
exit=2

##### ADVERSARIAL 3: KTG_CYCLE_PROJECTED_BYTES=0 in the environment zeroes the default projection
projected write      : 0 B
scratch_guard: OK  used=7558580421 B  projected_total=7558580421 B  group_free=2370000000000 B
exit=0

##### ADVERSARIAL 4: KTG_BUDGET_ENV pointing at a LOOSE constants file raises the cap
constants            : <scratch>/loose.env
projected root total : 536870913421 B   (hard cap 99999999999999 B = 500 GiB)
scratch_guard: OK  used=7558580421 B  projected_total=536870913421 B  group_free=2370000000000 B
exit=0

##### ADVERSARIAL 5: --root pointing at BASEDIR-like subdir (task file forbids scoping to BASEDIR) is accepted
root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime
du -sb               : 7272559	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime
projected root total : 529319605559 B   (hard cap 536870912000 B = 500 GiB)
scratch_guard: OK  used=7272559 B  projected_total=529319605559 B  group_free=2370000000000 B
exit=0

##### ADVERSARIAL 6: boundary -- projected total exactly == cap must pass (-gt), cap+1 must fail
used=7558580421
scratch_guard: OK  used=7558580421 B  projected_total=536870912000 B  group_free=2370000000000 B
exit(==cap)=0
VIOLATION: projected mission-root usage 536870912001 B exceeds the mission-root budget (hard cap 536870912000 B).
exit(cap+1)=1
```

Reading of the probes:
- ADV1 / ADV1b — **defect (real, fail-safe).** `load_budget` (`prune_retention.py:81-83`) tests `val.startswith("${")` before stripping the quotes, so the quoted `${VAR:-default}` lines are returned verbatim. `python3 prune_retention.py` with no `--root` exits 3 and deletes nothing; the header call contract (`python3 "$PRUNE" --apply`) would therefore never prune. The § 2 command masks this by always passing `--root`.
- ADV2 / ADV3 / ADV4 / ADV5 — **claim wording exceeded the evidence.** The measured root, the default projection and the constants file are all selectable from the environment or the command line; ADV2 exited 2 only because the scratchpad pool is small (the cap check itself passed on `du` = 4096 B). By design the caller (the loop wrapper) chooses these, so this is a hardening item plus a wording correction, not a broken threshold.
- ADV6 — boundary correct: projected total exactly equal to the cap passes (`-gt`), cap+1 fails.
- `min(quotas.py, df -B1)`: both sources report the same 40000000000000 B pool (df's filesystem total equals the quota), so the minimum is well-posed. A stale-low `quotas.py` can only refuse spuriously (safe direction); a fast fill is caught by live `df`. Sensible.

## 4. Adversarial synthetic tree for `prune_retention.py` (verbatim)

Tree: five old shuffle windows (all older than 2 h) so the newest window is itself old; a selfplay generation newer than the newest window; an old orphan `.tmp` and a young `.tmp`; three `models/` dirs; `checkpoint.ckpt` + `checkpoint_prev0.ckpt`; an `evidence/` path component under `loop/`; a symlinked directory inside `selfplay/`.

```
### ADV-A dry run, fixed rules (exit 0 )
== prune_retention 2026-09-04T00:08:05-0400 DRY-RUN ==
constants : /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env
root      : <scratch>/prune_adv
basedir   : <scratch>/prune_adv/loop
-- protected set (6 entries; never a deletion candidate) --
   PROTECT  <scratch>/prune_adv/loop/models/m_base    <- frozen baseline (oldest models/ dir)
   PROTECT  <scratch>/prune_adv/loop/models/m_new    <- latest accepted net (newest models/ dir)
   PROTECT  <scratch>/prune_adv/loop/train/ktg9/checkpoint.ckpt    <- short-term checkpoint (train.py:573-578)
   PROTECT  <scratch>/prune_adv/loop/train/ktg9/checkpoint_prev0.ckpt    <- short-term checkpoint (train.py:573-578)
   PROTECT  <scratch>/prune_adv/loop/shuffleddata/w4    <- newest shuffleddata dir
   PROTECT  <scratch>/prune_adv/evidence    <- evidence tree
-- deletion plan (5 paths, 650000 B) --
   WOULD-REMOVE         100000 B  <scratch>/prune_adv/loop/shuffleddata/w0    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
   WOULD-REMOVE         100000 B  <scratch>/prune_adv/loop/shuffleddata/w1    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
   WOULD-REMOVE          50000 B  <scratch>/prune_adv/loop/shuffleddata/orphan.tmp    <- orphan shuffleddata .tmp: shuffle.sh:105 renamed nothing; cleanup_old_dirs.py applies no name filter
   WOULD-REMOVE         200000 B  <scratch>/prune_adv/loop/selfplay/gen0    <- selfplay: keep newest 3 generations, and only delete generations older than the oldest retained shuffle window
   WOULD-REMOVE         200000 B  <scratch>/prune_adv/loop/selfplay/gen1    <- selfplay: keep newest 3 generations, and only delete generations older than the oldest retained shuffle window

### ADV-B rolling --target-bytes 0 : must keep newest window w4 + >=1 gen, warn (exit 0 )
== prune_retention 2026-09-04T00:08:05-0400 DRY-RUN ==
constants : /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env
root      : <scratch>/prune_adv
basedir   : <scratch>/prune_adv/loop
-- protected set (6 entries; never a deletion candidate) --
   PROTECT  <scratch>/prune_adv/loop/models/m_base    <- frozen baseline (oldest models/ dir)
   PROTECT  <scratch>/prune_adv/loop/models/m_new    <- latest accepted net (newest models/ dir)
   PROTECT  <scratch>/prune_adv/loop/train/ktg9/checkpoint.ckpt    <- short-term checkpoint (train.py:573-578)
   PROTECT  <scratch>/prune_adv/loop/train/ktg9/checkpoint_prev0.ckpt    <- short-term checkpoint (train.py:573-578)
   PROTECT  <scratch>/prune_adv/loop/shuffleddata/w4    <- newest shuffleddata dir
   PROTECT  <scratch>/prune_adv/evidence    <- evidence tree
-- rolling mode: du -sb = 1703328 B, after fixed rules 1053328 B, target 0 B --
-- deletion plan (9 paths, 1250000 B) --
   WOULD-REMOVE         100000 B  <scratch>/prune_adv/loop/shuffleddata/w0    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
   WOULD-REMOVE         100000 B  <scratch>/prune_adv/loop/shuffleddata/w1    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
   WOULD-REMOVE          50000 B  <scratch>/prune_adv/loop/shuffleddata/orphan.tmp    <- orphan shuffleddata .tmp: shuffle.sh:105 renamed nothing; cleanup_old_dirs.py applies no name filter
   WOULD-REMOVE         200000 B  <scratch>/prune_adv/loop/selfplay/gen0    <- selfplay: keep newest 3 generations, and only delete generations older than the oldest retained shuffle window
   WOULD-REMOVE         200000 B  <scratch>/prune_adv/loop/selfplay/gen1    <- selfplay: keep newest 3 generations, and only delete generations older than the oldest retained shuffle window
   WOULD-REMOVE         100000 B  <scratch>/prune_adv/loop/shuffleddata/w2    <- rolling: over --target-bytes 0
   WOULD-REMOVE         100000 B  <scratch>/prune_adv/loop/shuffleddata/w3    <- rolling: over --target-bytes 0
   WOULD-REMOVE         200000 B  <scratch>/prune_adv/loop/selfplay/gen2    <- rolling: over --target-bytes 0
   WOULD-REMOVE         200000 B  <scratch>/prune_adv/loop/selfplay/gen3    <- rolling: over --target-bytes 0
prune_retention: WARNING cannot reach 0 B without going below the rolling minimum (1 shuffle window, 1 selfplay generation) or touching a protected path; best reachable 453328 B

### ADV-C APPLY rolling to 0 (exit 0 )
== prune_retention 2026-09-04T00:08:05-0400 APPLY ==
constants : /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env
root      : <scratch>/prune_adv
basedir   : <scratch>/prune_adv/loop
-- protected set (6 entries; never a deletion candidate) --
   PROTECT  <scratch>/prune_adv/loop/models/m_base    <- frozen baseline (oldest models/ dir)
   PROTECT  <scratch>/prune_adv/loop/models/m_new    <- latest accepted net (newest models/ dir)
   PROTECT  <scratch>/prune_adv/loop/train/ktg9/checkpoint.ckpt    <- short-term checkpoint (train.py:573-578)
   PROTECT  <scratch>/prune_adv/loop/train/ktg9/checkpoint_prev0.ckpt    <- short-term checkpoint (train.py:573-578)
   PROTECT  <scratch>/prune_adv/loop/shuffleddata/w4    <- newest shuffleddata dir
   PROTECT  <scratch>/prune_adv/evidence    <- evidence tree
-- rolling mode: du -sb = 1703328 B, after fixed rules 1053328 B, target 0 B --
-- deletion plan (9 paths, 1250000 B) --
   REMOVE          100000 B  <scratch>/prune_adv/loop/shuffleddata/w0    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
   REMOVE          100000 B  <scratch>/prune_adv/loop/shuffleddata/w1    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
   REMOVE           50000 B  <scratch>/prune_adv/loop/shuffleddata/orphan.tmp    <- orphan shuffleddata .tmp: shuffle.sh:105 renamed nothing; cleanup_old_dirs.py applies no name filter
   REMOVE          200000 B  <scratch>/prune_adv/loop/selfplay/gen0    <- selfplay: keep newest 3 generations, and only delete generations older than the oldest retained shuffle window
   REMOVE          200000 B  <scratch>/prune_adv/loop/selfplay/gen1    <- selfplay: keep newest 3 generations, and only delete generations older than the oldest retained shuffle window
   REMOVE          100000 B  <scratch>/prune_adv/loop/shuffleddata/w2    <- rolling: over --target-bytes 0
   REMOVE          100000 B  <scratch>/prune_adv/loop/shuffleddata/w3    <- rolling: over --target-bytes 0
   REMOVE          200000 B  <scratch>/prune_adv/loop/selfplay/gen2    <- rolling: over --target-bytes 0
   REMOVE          200000 B  <scratch>/prune_adv/loop/selfplay/gen3    <- rolling: over --target-bytes 0
-- removed 9 paths, 1250000 B --
prune_retention: WARNING cannot reach 0 B without going below the rolling minimum (1 shuffle window, 1 selfplay generation) or touching a protected path; best reachable 453328 B

### survivors after apply:
  D loop
  D evidence
  D loop/train
  D loop/models
  D loop/shuffleddata
  D loop/selfplay
  D loop/evidence
  D loop/train/ktg9
  F loop/train/ktg9/checkpoint.ckpt
  F loop/train/ktg9/checkpoint_prev0.ckpt
  D loop/models/m_new
  D loop/models/m_mid
  D loop/models/m_base
  F loop/models/m_new/f.bin
  F loop/models/m_mid/f.bin
  F loop/models/m_base/f.bin
  D loop/shuffleddata/w4
  D loop/shuffleddata/young.tmp
  F loop/shuffleddata/w4/f.bin
  F loop/shuffleddata/young.tmp/f.bin
  D loop/selfplay/gen_link
  D loop/selfplay/gen4
  F loop/selfplay/gen4/f.bin
  F loop/evidence/keep.txt
  F evidence/keep.txt
symlink target intact (/etc/hostname exists): True
```
Result: newest window `w4`, young `.tmp`, both checkpoints, all three `models/` dirs, both `evidence` locations and the symlinked dir survive even `--target-bytes 0 --apply`; the rolling minimum (1 window + 1 generation) holds and the WARNING is emitted; the generation newer than the oldest retained window is never removed. No refutation of the retention rules.

## 5. Row-level checks

- Evidence paths: all five files under `evidence/data_budget/` exist; `closing_measurement.txt` content-hashed by the gate (`evidence_sha256 7ae8dfdb7c781f96e0523cef76748f7c7b032fa0a0768010cd0cab387a3116a8`).
- Dependencies: `arxiv-1902.10565::data_format_pos_len` resolves (knowledge ledger, `preliminary`).
- Circular evidence: none — the verification command exercises the guard, not the ledger.
- Worker's error rows (iterations 1-5) read: the iteration-1 partial (test hook shadowed) and iteration-3 fail (retention floor bypass) were both fixed before staging and the fixes are what the fixtures and rolling minima now test.
- Worker's evidence `guard_exit_contract.txt` used `du` = 7562895421 B vs 7558580421 B in the closing measurement: 4.3 MB of transient files during the test run, immaterial.

## 6. Appends (verbatim gate output) and row hashes

```
result append #1:
{"appended": true, "paper": "arxiv-1902.10565", "result_id": "data-budget-guard-500gib", "status": "conditional", "timestamp": "2026-09-04T04:12:22.220880+00:00", "evidence_sha256": "7ae8dfdb7c781f96e0523cef76748f7c7b032fa0a0768010cd0cab387a3116a8", "verified_exit_code": 0}
result append #2 (renumbered o25 -> o28 in open_obligations; content otherwise identical):
{"appended": true, "paper": "arxiv-1902.10565", "result_id": "data-budget-guard-500gib", "status": "conditional", "timestamp": "2026-09-04T04:14:40.291239+00:00", "evidence_sha256": "7ae8dfdb7c781f96e0523cef76748f7c7b032fa0a0768010cd0cab387a3116a8", "verified_exit_code": 0}
claims append-batch (o04 skipped by dedup, o25 + c11 appended):
{"appended": 2, "skipped": 1, "papers": ["arxiv-1902.10565"]}
claims single appends (o25 waived-as-renumbered, o28 opened, o04 re-affirmed):
  o25_data_budget_guard_repairs waived  row_hash 49e8dada275e23d6b63f429efda847be18d0191c71758c9204d0df0d32ad67b3
  o28_data_budget_guard_repairs open    row_hash 5012cc5d08990148f4c2f74af8fe6105b20e83cf64b6f43c27c81d94f27e0378
  o04_scratch_budget            open    row_hash 2da56098b33ac15a4304df8cd2968500e400219ddb052b84bff4e929cdc30cda
  c11_scratch_budget            in_progress row_hash c6dadc7e5d97e7c2505a0db15d297ace2c43383c05602ce6f7c301b2c4dfa0ff
error-ledger validation rows:
{"appended": 2, "of": 2, "papers": ["arxiv-1902.10565"]}
  data_budget iteration 6 validation partial  row_hash bc16f52283a43b5e2527dafcd32d1894674f3d61e87b4f4f8c1154c2fd6fc744
```
Result row (latest): `data-budget-guard-500gib` status `conditional`, `actor_role validator`, row hash `5cf754db629df666f97e1e5596da536cb4eb4b35f795c31ea5feda1af7a007a6`, no `admission_flags`.

Why two result appends: the repair obligation was first appended as `o25_data_budget_guard_repairs` (04:12:59); a concurrent validation (commit `f2f16df`, 04:07) had already used the `o25`-`o27` prefixes and its `o27_scratch_guard_reconcile_500gib` already tracks conjunct (b). Ledgers are append-only, so `o25_data_budget_guard_repairs` was marked `waived` with a note that it is a renumbering only, the identical obligation was appended as `o28_data_budget_guard_repairs`, and the result row was re-appended (same `result_id`, latest wins) with `open_obligations` naming o27 and o28.

## 7. Claim transitions

- `c11_scratch_budget`: `open` → `in_progress` (result row exists at `conditional`; admission needs production cycle logs).
- `o04_scratch_budget`: stays `open` (blocking) — cannot be discharged while `loop.sbatch` duplicates the literals (o27) and the guard-side repairs (o28) are open.
- `o28_data_budget_guard_repairs`: new, `open`, blocking, owner `worker data_budget` — the two defects in § 3.

## 8. Remaining [OPEN]

1. o27 — `loop.sbatch:74-75,195`, `synchronous_loop_9x9.sh:190-191` must call `scratch_guard.sh` (owner `loop_resume_under_walltime`).
2. o28 — pruner default-root parse; environment-selectable root / projection / constants file; add contract cases.
3. Status upgrade `conditional` → `empirical` needs o27 + o28 discharged and one production cycle log with the guard triple and exit code.
4. Design-choice constants (20 GiB projection, 1 / 1.5 TiB floors, 6/10/3/3 retention) stay re-openable once `measure_stage_throughput` measures bytes/row.
