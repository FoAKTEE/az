# Validation record (repair) — `arxiv-1902.10565::data_budget`, obligation `o28_data_budget_guard_repairs`

Role: Chandra VALIDATOR (refuter, then judge), cross-model from the worker. Host `login03`, CPU only, no Slurm job. cwd `/home/schmidt/ssci-haiyangw/az`, branch `main`, code under test at HEAD `989f337` (working tree clean for `codes/data_budget/`).
Inputs received: `evidence/data_budget/candidate_rows_repair.json` (sha256 `460594a9…`), `evidence/data_budget/repair_o28.txt` (sha256 `65105acb…`), `codes/data_budget/{budget.env 6f38681e…, scratch_guard.sh 361ad2c0…, prune_retention.py 32d27040…, tests/}`, the worker's error rows `0024b5ef…` (iteration 7, partial) and `17302639…` (iteration 8, pass), `tasks/data_budget/implementation.md` § 2, the prior validation record `validation.md`, the ledger schemas, `mission.json`, the admission contract.

## Verdict

**ADMIT at status `conditional`** (as staged; not `empirical` — no production cycle log exists). **`o28_data_budget_guard_repairs` → `discharged`**, `discharged_by` the result row `data-budget-guard-500gib` (the ledger requires a result_id or knowledge node_id; the worker's staged `discharged_by` was a file path, which does not resolve). Two amendments to the staged row, both narrowing: (1) the staged text still called `o27_scratch_guard_reconcile_500gib` open and said "no wrapper calls the guard"; at HEAD o27 is `discharged` (row `914f6cf9…`, 04:59 UTC, `discharged_by r_loop_resume_under_walltime_static`) and `codes/loop/loop.sbatch` / `synchronous_loop_9x9.sh` call `scratch_guard.sh` with `--label` only — no `--root`, no `--projected-bytes`, no `KTG_BUDGET_ENV`; (2) "must hold literal values" is broader than the check: the guard refuses the braced `${…}` form only; an in-tree file written with an unbraced `$VAR` or `$((…))` is sourced and evaluated (probes V9a/V9c). That is inside the trusted-directory condition the row already declares — the attacker who can write such a file can edit `budget.env` itself — and every committed constants file is literal (grep below), so it is a wording fix plus a non-blocking hardening obligation (`o32_data_budget_guard_hardening`), not a rejection.

Gates in plain language (spec § Validation gates 3–6 are the validator's brief):
- Gate 3 (evidence matches evidence type `empirical_measurement`): PASS — the 25-case exit-code contract, the § 2 command, the du/df/quotas triple and the synthetic retention runs are executed measurements; I reproduced all of them.
- Gate 4 (units/regimes): PASS — exact byte integers; binary GiB for the cap, decimal TB for `quotas.py` converted as such; regime stated as pre-loop.
- Gate 6 (code/protocol/checks/uncertainty/artifacts): PASS — code paths, fixtures, the verification command and the uncertainty (production behaviour unmeasured) are all on the row.
- Claim vs evidence: PASS after the two narrowings above. Nothing in the candidate is promoted beyond what was executed; `conditional` is the honest status because the wrapper's guard call has been exercised only under the loop validator's scheduler shims and no cycle has run.
- Hidden `[OPEN]`: none hidden; the stale "o27 open" item is corrected, and o32 is added visibly.
- Circular evidence: none — the verification command exercises the code, not the ledgers.

`o04_scratch_budget`: its ledger note (row `2da56098…`) named exactly two unmet remainders, o27 and o28. Both are now discharged, so o04 is discharged here too, `discharged_by data-budget-guard-500gib`, with the per-cycle logging conjunct verified at code level only (the guard prints the triple; the wrapper calls it at the top of every cycle). `c11_scratch_budget` stays `in_progress`: "for the whole run" needs production logs.

## 1. Re-run of the 25-case exit-code contract (verbatim, validator)

```
== scratch_guard exit-code contract  2026-09-04T00:59:03-04:00 ==
guard: /weka/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/../scratch_guard.sh
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
PASS  exit 0   M. control: an EXPLICIT --projected-bytes 0 is caller control and passes
PASS  exit 1   L. KTG_CYCLE_PROJECTED_BYTES=0 in the environment cannot zero the projection
PASS  exit 0   Q. control: an EXPLICIT --root is caller control, and is announced in the log
PASS  exit 1   P. KTG_SCRATCH_ROOT in the environment cannot redirect the measured root
PASS  exit 0   N1. control: a raised-cap constants file INSIDE the guard dir is honoured
PASS  exit 3   N2. the byte-identical file OUTSIDE the guard dir is refused, cap not raised
PASS  exit 3   O. an in-tree constants file with a ${...} indirection is refused by the guard
PASS  exit 2   R. a fake KTG_QUOTAS_BIN overstating free space cannot lift the group floor
PASS  exit 0   S1. pruner with no --root (documented contract) dry-runs the MISSION ROOT
PASS  exit 0   S2. the legacy ${NAME:-default} form resolves to the file default, not the env
PASS  exit 0   S3. an exported KTG_SCRATCH_ROOT cannot redirect the pruner
PASS  exit 3   S4. pruner refuses an out-of-tree --budget-env
PASS  exit 1   T1. control: the same root, nothing unreadable, measures and refuses on the cap
PASS  exit 3   T2. du -sb non-zero on every attempt: partial total discarded, guard refuses
== 25 passed, 0 failed ==
run_guard_tests.sh exit=0  wall=43 s
```

## 2. Re-run of the task § 2 verification command (verbatim, unchanged command)

```
section2_verification exit=0 wall=50 s
== scratch_guard 2026-09-04T01:02:19-04:00 [validator o28 re-measure] ==
constants            : /weka/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env
root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
du -sb               : 7567084124	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
df -B1               : wekafs1/scratchssci 40000000000000 37537422614528 2462577385472 94% /weka/scratch/schmidt
projected write      : 21474836480 B
projected root total : 29041920604 B   (hard cap 536870912000 B = 500 GiB)
group scratch free   : 2460000000000 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
scratch_guard: OK  used=7567084124 B  projected_total=29041920604 B  group_free=2460000000000 B
guard exit=0
```
`du -sb` = 7567084124 B ≤ 536870912000 B. Free-space source is `quotas.py` (2460000000000 B) because it is the smaller of the two — `min(quotas.py, df -B1)` as designed.

## 3. Refutation set 1 — the constants-file pin (`KTG_BUDGET_ENV` allow-list, symlinks, form). Verbatim; only `--root` on a 3 MB probe dir so each probe is cheap.

Reading: V1 in-tree loose file is honoured (documented trust condition; the wrapper exports no `KTG_BUDGET_ENV`). V2/V2p/V2q an in-tree SYMLINK to an out-of-tree file is refused by both tools (`realpath`). V3 an out-of-tree symlink INTO the tree resolves to the real `budget.env` (no loosening; the printed `constants :` line shows the caller's path). V4a/V4b/V5b directories or non-shell in-tree files are refused or die on `set -u` — non-zero, never 0, but V4b/V5b exit 1 (via `set -u`) rather than 3, which the wrapper would book as "hard cap" (fail-safe, misclassified). V5 pointing `KTG_BUDGET_ENV` at `scratch_guard.sh` itself recurses (self-source) and hangs until killed — cannot loosen, but is a hang. V7 CRLF: guard exit 3 (the `\r` fails the integer check), pruner accepts (`strip()`); asymmetric, fail-safe on the guard. V8 trailing spaces: both fine. **V9a/V9c: unbraced `$KTG_LOOSE` and `$((1<<50))` in an in-tree file pass the literal check and are evaluated — the check matches `\$\{` only**; V9b the braced form is refused. V10–V12b path spellings resolve correctly (`pwd -P` vs `/home`, traversal in and out). V13 committed fixtures only tighten.

```
    probe files:
    -rw-r--r-- 1 ssci-haiyangw users 3273 Sep  4 01:04 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.arith.env
    -rw-r--r-- 1 ssci-haiyangw users 3275 Sep  4 01:04 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.braced.env
    -rw-r--r-- 1 ssci-haiyangw users 3330 Sep  4 01:04 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env
    lrwxrwxrwx 1 ssci-haiyangw users   93 Sep  4 01:04 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.link.env -> /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/loose.env
    -rw-r--r-- 1 ssci-haiyangw users 3277 Sep  4 01:04 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.loose.env
    -rw-r--r-- 1 ssci-haiyangw users 3308 Sep  4 01:04 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.trailsp.env
    -rw-r--r-- 1 ssci-haiyangw users 3273 Sep  4 01:04 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.unbraced.env
    
    /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy:
    total 8
    drwx------ 1 ssci-haiyangw users    0 Sep  4 01:04 .
    drwxr-xr-x 1 ssci-haiyangw users    0 Sep  4 01:04 ..
    lrwxrwxrwx 1 ssci-haiyangw users   88 Sep  4 01:04 link_to_real_budget.env -> /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env
    -rw-r--r-- 1 ssci-haiyangw users 3277 Sep  4 01:04 loose.env
    drwxr-xr-x 1 ssci-haiyangw users    0 Sep  4 01:04 small
    
    ##### V0 control: production budget.env, small root, 600 GB projection -> exit 1 (cap holds)
    $ bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 600000000000 --label V0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 600003000000 B   (hard cap 536870912000 B = 500 GiB)
      | VIOLATION: projected mission-root usage 600003000000 B exceeds the mission-root budget (hard cap 536870912000 B).
      |            current 3000000 B + projected 600000000000 B. Run prune_retention.py --apply --target-bytes 536870912000 before retrying.
      exit=1
    
    ##### V1 in-tree loose file (allow-listed dir) raises cap: honoured, exit 0 [documented trust condition]
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.loose.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 600000000000 --label V1
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 600003000000 B   (hard cap 99999999999999 B = 500 GiB)
      exit=0
    
    ##### V2 in-tree SYMLINK -> out-of-tree loose file: must be refused (realpath)
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.link.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 600000000000 --label V2
      | scratch_guard: refusing an out-of-tree constants file: /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.link.env
      |                only files under /weka/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/ may set the byte thresholds.
      exit=3
    
    ##### V2p pruner, same symlink via --budget-env
    $ python3 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py --budget-env /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.link.env --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | prune_retention: refusing an out-of-tree constants file: /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.link.env
      |                  only files under /weka/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/ may set the retention bounds and the mission root.
      exit=3
    
    ##### V2q pruner, same symlink via KTG_BUDGET_ENV
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.link.env python3 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | prune_retention: refusing an out-of-tree constants file: /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.link.env
      |                  only files under /weka/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/ may set the retention bounds and the mission root.
      exit=3
    
    ##### V3 out-of-tree symlink -> in-tree budget.env: resolves in-tree, real constants, printed path is the caller's
    $ env KTG_BUDGET_ENV=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/link_to_real_budget.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 600000000000 --label V3
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 600003000000 B   (hard cap 536870912000 B = 500 GiB)
      | VIOLATION: projected mission-root usage 600003000000 B exceeds the mission-root budget (hard cap 536870912000 B).
      |            current 3000000 B + projected 600000000000 B. Run prune_retention.py --apply --target-bytes 536870912000 before retrying.
      exit=1
    
    ##### V4a KTG_BUDGET_ENV = the guard directory itself
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | scratch_guard: refusing an out-of-tree constants file: /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget
      |                only files under /weka/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/ may set the byte thresholds.
      exit=3
    
    ##### V4b KTG_BUDGET_ENV = the tests/ subdirectory (in-tree, but a directory)
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | grep: /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests: Is a directory
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh: line 131: .: /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests: is a directory
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh: line 134: KTG_SCRATCH_ROOT: unbound variable
      exit=1
    
    ##### V5 KTG_BUDGET_ENV = scratch_guard.sh itself (in-tree non-.env file; self-source), 20 s timeout
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh timeout 20 bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      exit=124
    
    ##### V5b KTG_BUDGET_ENV = prune_retention.py (in-tree, not shell)
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 75: default: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 75: node data_budget - bounded rolling retention for the mission scratch tree.
      | 
      | Dry-run by default. Nothing is ever removed without --apply, and the protected set is
      | computed and PRINTED before a single path is considered for deletion.
      | 
      |   usage: prune_retention.py [--root DIR] [--basedir DIR] [--apply]
      |                             [--target-bytes N] [--budget-env FILE] [--json FILE]
      | 
      |   --root DIR         mission root (default: KTG_SCRATCH_ROOT from budget.env)
      |   --basedir DIR      loop data dir (default: <root>/loop)
      |   --apply            actually delete; without it this is a report
      |   --target-bytes N   rolling mode: after the fixed rules, keep deleting the oldest
      |                      unprotected shuffleddata / selfplay generations until the measured
      |                      root size is at or below N bytes
      |   --budget-env FILE  alternate constants file (default: budget.env next to this script).
      |                      PINNED (o28): only a file that resolves INSIDE this script's own
      |                      directory is honoured - budget.env and the committed tests/ fixtures.
      |                      /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py supplies the same default and is subject to the same
      |                      restriction; anything outside that subtree exits 3.
      |   --json FILE        also write the full plan as JSON
      | 
      | Root selection (o28). The root comes from KTG_SCRATCH_ROOT in the constants file, resolved
      | the way scratch_guard.sh resolves it: the FILE's value, never the environment. An exported
      | KTG_SCRATCH_ROOT does not redirect the pruner. Only an explicit --root does, and a --root
      | that differs from the constants file's root is announced with a NOTE line, so a re-scoped
      | prune cannot pass unremarked in a cycle log. Running with no --root is the documented call
      | contract in the scratch_guard.sh header (python3 prune_retention.py --apply) and it
      | targets the mission root.
      | 
      | Legacy constants files. A value written in the shell-default form default
      | resolves to  - the quotes are stripped BEFORE the form is recognised (the bug that
      | made the no---root call exit 3), and the environment is deliberately NOT consulted, so the
      | form cannot be used as an environment channel. The pruner accepts such a file with a NOTE
      | where scratch_guard.sh refuses it outright: the guard's refusal protects byte THRESHOLDS,
      | which is where an environment channel would matter, while a pruner that refuses to start
      | simply stops bounding the tree - which is the failure o28 was opened for.
      | 
      | Retention rules, each with its upstream justification:
      | 
      |   shuffleddata/<ts>            keep the newest KTG_KEEP_SHUFFLEDDATA dirs that are older
      |                                than KTG_SHUFFLEDDATA_MIN_AGE_S, matching upstream
      |                                python/selfplay/cleanup_old_dirs.py:13,24. Dirs younger than
      |                                the age threshold are never touched (a shuffle may be
      |                                feeding the trainer right now).
      |   shuffleddata/<ts>.tmp        orphan output of a shuffle that died before the rename at
      |                                python/selfplay/shuffle.sh:105. Upstream applies NO name
      |                                filter (cleanup_old_dirs.py:15-20 tests only is_dir and
      |                                mtime), so an orphan .tmp competes for one of the three
      |                                retained slots and can push out a GOOD shuffle dir. Swept
      |                                here explicitly, oldest first, once older than the age
      |                                threshold.
      |   selfplay/<model>/            keep the newest KTG_KEEP_SELFPLAY_GENERATIONS generations,
      |                                and NEVER remove a generation whose rows may still be inside
      |                                a retained shuffle window: a generation is deletable only if
      |                                it is older than the OLDEST retained shuffleddata dir.
      |   train/*/longterm_checkpoints keep the newest KTG_KEEP_LONGTERM_CHECKPOINTS .ckpt files.
      |                                python/train.py:1883-1889 writes one every 12 h forever and
      |                                nothing upstream prunes them.
      |   rejectedmodels/<name>        keep the newest KTG_KEEP_REJECTED_MODELS dirs.
      |   scripts/dated/<ts>           keep the newest KTG_KEEP_DATED_SCRIPTS archives (each holds
      |                                a katago binary).
      | 
      | Protected set (never a deletion candidate, always printed):
      |   - the frozen baseline: the OLDEST directory under <basedir>/models/
      |   - the latest accepted net: the NEWEST directory under <basedir>/models/
      |   - every train/*/checkpoint.ckpt and train/*/checkpoint_prev*.ckpt
      |     (python/train.py:573-578 keeps 4 short-term checkpoints itself)
      |   - anything under a path component named 'evidence'
      |   - the newest shuffleddata dir and anything younger than the age threshold
      | 
      | Rolling mode (--target-bytes) relaxes the keep-N floors above, but never below ONE shuffle
      | window older than the age threshold and ONE selfplay generation feeding it, and it never
      | removes a generation that a still-retained window could reference.
      | : File name too long
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 77: from: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 79: import: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 80: import: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 81: import: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 82: import: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 83: import: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 84: import: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 85: import: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 86: import: command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 88: syntax error near unexpected token `('
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py: line 88: `HERE = os.path.dirname(os.path.abspath(__file__))'
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh: line 134: KTG_SCRATCH_ROOT: unbound variable
      exit=1
    
    ##### V7 CRLF line endings, in-tree copy of budget.env: guard
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env: line 7: $'\r': command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env: line 16: $'\r': command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env: line 19: $'\r': command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env: line 27: $'\r': command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env: line 38: $'\r': command not found
      | /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env: line 42: $'\r': command not found
      | scratch_guard: KTG_SCRATCH_HARD_BYTES is not a byte integer in /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env: '536870912000
'
      exit=3
    
    ##### V7p CRLF, pruner
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.crlf.env python3 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | == prune_retention 2026-09-04T01:04:49-0400 DRY-RUN ==
      | root      : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE      : measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | basedir   : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small/loop
      | -- protected set (0 entries; never a deletion candidate) --
      |    (none: the loop tree does not exist yet)
      | -- deletion plan (0 paths, 0 B) --
      |    (nothing to remove)
      exit=0
    
    ##### V8 trailing spaces after every KTG_ value: guard
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.trailsp.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 3000000 B   (hard cap 536870912000 B = 500 GiB)
      exit=0
    
    ##### V8p trailing spaces, pruner
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.trailsp.env python3 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | == prune_retention 2026-09-04T01:04:49-0400 DRY-RUN ==
      | root      : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE      : measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | basedir   : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small/loop
      | -- protected set (0 entries; never a deletion candidate) --
      |    (none: the loop tree does not exist yet)
      | -- deletion plan (0 paths, 0 B) --
      |    (nothing to remove)
      exit=0
    
    ##### V9a in-tree file with UNBRACED $KTG_LOOSE (literal check matches only ${...}): env re-opened?
    $ env KTG_LOOSE=99999999999999 KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.unbraced.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 600000000000 --label V9a
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 600003000000 B   (hard cap 99999999999999 B = 500 GiB)
      exit=0
    
    ##### V9b control: same file with BRACED ${KTG_LOOSE}: refused
    $ env KTG_LOOSE=99999999999999 KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.braced.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 600000000000 --label V9b
      | scratch_guard: constants file is not literal: /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.braced.env
      |                a KTG_* assignment contains a ${...} indirection; write byte
      |                integers and the root path literally.
      exit=3
    
    ##### V9c in-tree file with arithmetic $((1<<50))
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.arith.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 600000000000 --label V9c
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 600003000000 B   (hard cap 1125899906842624 B = 500 GiB)
      exit=0
    
    ##### V9p pruner with the unbraced file (no shell evaluation expected)
    $ env KTG_LOOSE=99999999999999 KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/validator_probe.1391182.unbraced.env python3 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | == prune_retention 2026-09-04T01:04:51-0400 DRY-RUN ==
      | root      : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE      : measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | basedir   : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small/loop
      | -- protected set (0 entries; never a deletion candidate) --
      |    (none: the loop tree does not exist yet)
      | -- deletion plan (0 paths, 0 B) --
      |    (nothing to remove)
      exit=0
    
    ##### V10 same budget.env spelled through /home (HERE is pwd -P = /weka/home)
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 3000000 B   (hard cap 536870912000 B = 500 GiB)
      exit=0
    
    ##### V11 KTG_BUDGET_ENV empty string -> default
    $ env KTG_BUDGET_ENV= bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 3000000 B   (hard cap 536870912000 B = 500 GiB)
      exit=0
    
    ##### V12 path traversal that leaves the dir: $D/../loose.env (file need not exist)
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/../loose.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | scratch_guard: refusing an out-of-tree constants file: /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/../loose.env
      |                only files under /weka/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/ may set the byte thresholds.
      exit=3
    
    ##### V12b traversal that returns in-tree: $D/tests/../budget.env
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/../budget.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 3000000 B   (hard cap 536870912000 B = 500 GiB)
      exit=0
    
    ##### V13 committed fixtures can only TIGHTEN: tinycap on the small root, 0 projection
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/fixture_tinycap.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small --projected-bytes 0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28env.KbtYYy/small (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | projected root total : 3000000 B   (hard cap 1000000 B = 500 GiB)
      | VIOLATION: projected mission-root usage 3000000 B exceeds the mission-root budget (hard cap 1000000 B).
      |            current 3000000 B + projected 0 B. Run prune_retention.py --apply --target-bytes 1000000 before retrying.
      exit=1
    cleanup: in-tree probes removed:
    fixture_failfloor.env
    fixture_legacy_shellform.env
    fixture_tinycap.env
    fixture_warnfloor.env
    run_guard_tests.sh
```

Committed constants files — every `KTG_*` assignment containing `$` or a backtick (expect only the legacy fixture, which the guard refuses by form):
```
results/ktg/paper_1902.10565/codes/data_budget/tests/fixture_legacy_shellform.env:21:KTG_SCRATCH_ROOT="${KTG_SCRATCH_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"   # FIXTURE: legacy shell-default form
results/ktg/paper_1902.10565/codes/data_budget/tests/fixture_legacy_shellform.env:30:KTG_CYCLE_PROJECTED_BYTES="${KTG_CYCLE_PROJECTED_BYTES:-21474836480}"   # FIXTURE: legacy shell-default form
```

## 4. Refutation set 2 — `--root`, `KTG_QUOTAS_BIN`, du retry knobs, the du race, the pruner under du failure (verbatim)

Reading: R1 `--root` given as a SYMLINK to the mission root measures 51 B (`du -sb` does not dereference its argument) — `--root` is caller control and is announced by the NOTE line; the wrapper passes none; recorded in o32 as a hardening item (`realpath` the root or `du -sbD`). R1b trailing slash only changes the textual comparison (NOTE printed, same measurement). R2/R2b the documented caller-control case: empty root + `--projected-bytes 0` passes with the NOTE; with no `--projected-bytes` the 20 GiB file default applies. Is the NOTE enough? Yes, given the caller: both wrappers call `bash "$SCRATCH_GUARD" --label …` and nothing else (verified in `loop.sbatch` and `synchronous_loop_9x9.sh` at HEAD and by the o27 discharge row: "no --root is passed to either tool"). R3 a file as root → exit 3. R4a a reporter claiming 99999 TB free is discarded for live df (`source: df`); R4b a reporter claiming the pool is full refuses (safe direction); R4c negative usage → `max(0,…)` then min with df; R4d a crashing reporter → df fallback with WARNING. R5 the retry knobs reject 0 / non-integer / negative and cannot loosen. R6a–R6c the worker's T1/T2 reproduced independently (chmod 000 subdir; restored afterwards): partial total 2000000 B discarded on every attempt, exit 3. **R6d the transient race**: subdir unlocked 3 s in; attempts 1–2 fail, attempt 3 succeeds and counts the FULL 4000000 B — the retry never uses a partial total. R7 the pruner in `--apply --target-bytes 0` under a persistent du failure exits 3 BEFORE any deletion (12 entries before, 12 after); R7b the same tree readable prunes to the rolling minimum (`w4` kept).

```
    
    ##### R1 --root is a SYMLINK to the mission root: du -sb does not dereference, so 'used' is the link size
    $ bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/rootlink --projected-bytes 0 --label R1
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/rootlink
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/rootlink (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 51	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/rootlink
      | projected root total : 51 B   (hard cap 536870912000 B = 500 GiB)
      | group scratch free   : 2460000000000 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | scratch_guard: OK  used=51 B  projected_total=51 B  group_free=2460000000000 B
      exit=0
    
    ##### R1b --root with a trailing slash (same root, textual mismatch -> NOTE printed)
    $ bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/ --projected-bytes 0 --label R1b
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/ (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 7571084186	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/
      | projected root total : 7571084186 B   (hard cap 536870912000 B = 500 GiB)
      | group scratch free   : 2460000000000 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | scratch_guard: OK  used=7571084186 B  projected_total=7571084186 B  group_free=2460000000000 B
      exit=0
    
    ##### R2 --root empty dir, --projected-bytes 0, production constants (the o27 wrapper must pass neither)
    $ bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty --projected-bytes 0 --label R2
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 0	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | projected root total : 0 B   (hard cap 536870912000 B = 500 GiB)
      | group scratch free   : 2460000000000 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | scratch_guard: OK  used=0 B  projected_total=0 B  group_free=2460000000000 B
      exit=0
    
    ##### R2b --root empty dir, NO --projected-bytes: file default 20 GiB applies
    $ bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty --label R2b
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 0	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | projected root total : 21474836480 B   (hard cap 536870912000 B = 500 GiB)
      | group scratch free   : 2460000000000 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | scratch_guard: OK  used=0 B  projected_total=21474836480 B  group_free=2460000000000 B
      exit=0
    
    ##### R3 --root is a regular file
    $ bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/notadir --projected-bytes 0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/notadir
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/notadir (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | scratch_guard: mission root does not exist: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/notadir
      exit=3
    
    ##### R4a KTG_QUOTAS_BIN claims 99999 TB free, PRODUCTION constants: min() must pick df
    $ env KTG_QUOTAS_BIN=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/fake_huge.py bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-an
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 0	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | projected root total : 0 B   (hard cap 536870912000 B = 500 GiB)
      | group scratch free   : 2465836142592 B   (source: df; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | scratch_guard: OK  used=0 B  projected_total=0 B  group_free=2465836142592 B
      exit=0
    
    ##### R4b KTG_QUOTAS_BIN claims the pool is full: refuses (safe direction)
    $ env KTG_QUOTAS_BIN=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/fake_full.py bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-an
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 0	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | projected root total : 0 B   (hard cap 536870912000 B = 500 GiB)
      | group scratch free   : 0 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | VIOLATION: group scratch free space 0 B is below the 1099511627776 B safety floor.
      |            The pool is shared by the whole group; do not start a cycle. Escalate.
      exit=2
    
    ##### R4c KTG_QUOTAS_BIN reports negative usage: max(0,..) then min() with df
    $ env KTG_QUOTAS_BIN=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/fake_negative.py bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssc
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 0	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | projected root total : 0 B   (hard cap 536870912000 B = 500 GiB)
      | group scratch free   : 2465836142592 B   (source: df; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | scratch_guard: OK  used=0 B  projected_total=0 B  group_free=2465836142592 B
      exit=0
    
    ##### R4d KTG_QUOTAS_BIN crashes: df fallback with WARNING
    $ env KTG_QUOTAS_BIN=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/fake_crash.py bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-a
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 0	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | scratch_guard: WARNING quotas.py unreadable or unparseable at /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/fake_crash.py; using df -B1 on the same pool
      | projected root total : 0 B   (hard cap 536870912000 B = 500 GiB)
      | group scratch free   : 2465836142592 B   (source: df (quotas.py unavailable); fail floor 1099511627776 B, warn floor 1649267441664 B)
      | scratch_guard: OK  used=0 B  projected_total=0 B  group_free=2465836142592 B
      exit=0
    
    ##### R5a KTG_DU_ATTEMPTS=0
    $ env KTG_DU_ATTEMPTS=0 bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty --projected-bytes 0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | scratch_guard: KTG_DU_ATTEMPTS must be a positive integer, got '0'
      exit=3
    
    ##### R5b KTG_DU_ATTEMPTS=abc
    $ env KTG_DU_ATTEMPTS=abc bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty --projected-bytes 0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | scratch_guard: KTG_DU_ATTEMPTS must be a positive integer, got 'abc'
      exit=3
    
    ##### R5c KTG_DU_RETRY_SLEEP=-1
    $ env KTG_DU_RETRY_SLEEP=-1 bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty --projected-bytes 0
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | scratch_guard: KTG_DU_RETRY_SLEEP must be a non-negative integer, got '-1'
      exit=3
    
    ##### R5d KTG_DU_ATTEMPTS=99 KTG_DU_RETRY_SLEEP=0 on an empty root (cannot loosen; just knobs)
    $ env KTG_DU_ATTEMPTS=99 KTG_DU_RETRY_SLEEP=0 bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty --proj
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 0	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/empty
      | projected root total : 0 B   (hard cap 536870912000 B = 500 GiB)
      | group scratch free   : 2460000000000 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | scratch_guard: OK  used=0 B  projected_total=0 B  group_free=2460000000000 B
      exit=0
    
    ##### R6a control: duroot readable, tinycap -> exit 1, total 4000000+
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/fixture_tinycap.env bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --root /scratch/schmidt
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | du -sb               : 4000000	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot
      | projected root total : 4000000 B   (hard cap 1000000 B = 500 GiB)
      | group scratch free   : 2460000000000 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | VIOLATION: projected mission-root usage 4000000 B exceeds the mission-root budget (hard cap 1000000 B).
      |            current 4000000 B + projected 0 B. Run prune_retention.py --apply --target-bytes 1000000 before retrying.
      exit=1
    
    ##### R6b permanent: locked subdir, KTG_DU_ATTEMPTS=1 -> one attempt, exit 3, partial 2000000 discarded
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/fixture_tinycap.env KTG_DU_ATTEMPTS=1 bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --roo
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | scratch_guard: WARNING du -sb attempt 1/1 on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot exited non-zero; its partial total is discarded (du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw
      | scratch_guard: du -sb failed on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot after 1 attempts: du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/du
      exit=3
    
    ##### R6c permanent: default attempts, KTG_DU_RETRY_SLEEP=1 -> exit 3 (worker's T2 reproduced independently)
    $ env KTG_BUDGET_ENV=/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/tests/fixture_tinycap.env KTG_DU_RETRY_SLEEP=1 bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/scratch_guard.sh --quiet --
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | scratch_guard: WARNING du -sb attempt 1/3 on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot exited non-zero; its partial total is discarded (du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw
      | scratch_guard: WARNING du -sb attempt 2/3 on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot exited non-zero; its partial total is discarded (du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw
      | scratch_guard: WARNING du -sb attempt 3/3 on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot exited non-zero; its partial total is discarded (du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw
      | scratch_guard: du -sb failed on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot after 3 attempts: du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/du
      exit=3
    
    ##### R6d TRANSIENT: subdir unlocked 3 s after the guard starts; attempts 3, sleep 2 -> a later attempt must succeed and count the FULL 4000000+
      [background: chmod 755 locked at +3 s]
      | root                 : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot
      | NOTE  measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | scratch_guard: WARNING du -sb attempt 1/3 on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot exited non-zero; its partial total is discarded (du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw
      | scratch_guard: WARNING du -sb attempt 2/3 on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot exited non-zero; its partial total is discarded (du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw
      | scratch_guard: NOTE du -sb succeeded on attempt 3/3 (entries were changing under the walk)
      | du -sb               : 4000000	/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/duroot
      | projected root total : 4000000 B   (hard cap 1000000 B = 500 GiB)
      | group scratch free   : 2460000000000 B   (source: quotas.py; fail floor 1099511627776 B, warn floor 1649267441664 B)
      | VIOLATION: projected mission-root usage 4000000 B exceeds the mission-root budget (hard cap 1000000 B).
      |            current 4000000 B + projected 0 B. Run prune_retention.py --apply --target-bytes 1000000 before retrying.
      exit=1
    
    ##### R7 pruner --apply --target-bytes 0 with an unreadable subdir under root: du None -> exit 3 before any deletion
    $ python3 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot --apply --target-bytes 0
      | prune_retention: WARNING du -sb attempt 1/3 on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot exited 1; its partial total is discarded (du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw/k
      | prune_retention: WARNING du -sb attempt 2/3 on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot exited 1; its partial total is discarded (du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw/k
      | prune_retention: WARNING du -sb attempt 3/3 on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot exited 1; its partial total is discarded (du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw/k
      | prune_retention: du -sb failed on /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot after 3 attempts: du: cannot read directory '/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzI
      | == prune_retention 2026-09-04T01:05:15-0400 APPLY ==
      | root      : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot
      | NOTE      : measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | basedir   : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot/loop
      | -- protected set (1 entries; never a deletion candidate) --
      |    PROTECT  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot/loop/shuffleddata/w4    <- newest shuffleddata dir
      exit=3
      entries under loop/ before=12 after=12 (must be equal)
    
    ##### R7b same tree, subdir readable: rolling apply proceeds (w0..w3 removed, w4 kept)
    $ python3 /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/prune_retention.py --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot --apply --target-bytes 0
      | prune_retention: WARNING cannot reach 0 B without going below the rolling minimum (1 shuffle window, 1 selfplay generation) or touching a protected path; best reachable 100100 B
      | == prune_retention 2026-09-04T01:05:19-0400 APPLY ==
      | root      : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot
      | NOTE      : measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | basedir   : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot/loop
      | -- protected set (1 entries; never a deletion candidate) --
      |    PROTECT  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot/loop/shuffleddata/w4    <- newest shuffleddata dir
      | -- rolling mode: du -sb = 500100 B, after fixed rules 300100 B, target 0 B --
      | -- deletion plan (4 paths, 400000 B) --
      |    REMOVE          100000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot/loop/shuffleddata/w0    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
      |    REMOVE          100000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot/loop/shuffleddata/w1    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
      |    REMOVE          100000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot/loop/shuffleddata/w2    <- rolling: over --target-bytes 0
      |    REMOVE          100000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot/loop/shuffleddata/w3    <- rolling: over --target-bytes 0
      | -- removed 4 paths, 400000 B --
      exit=0
      survivors:
        /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb/pruneroot/loop/shuffleddata/w4
    cleanup done: ls: cannot access '/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28du.4pzIGb': No such file or directory
```

## 5. Refutation set 3 — `prune_retention.py --apply` on a synthetic tree WITH a young window (verbatim)

Tree: five old windows `w0–w4` plus a window younger than 2 h (`wyoung`), old `orphan.tmp` and young `young.tmp`, generations `gen0–gen3` older than `w4`, `gen4` between `w4` and `wyoung`, `gen5` newer than everything, a symlink `gen_link` → `models/m_base`, three `models/`, `checkpoint.ckpt` + `checkpoint_prev0.ckpt`, nine longterm `.ckpt` plus a symlink `evil_link.ckpt` → `checkpoint.ckpt`, 14 rejectedmodels, 6 dated archives, `evidence/` at both levels. `--apply --target-bytes 0` then 14 assertions. Note for the record: the docstring's rolling minimum says "one shuffle window OLDER than the age threshold", but the code counts any surviving window — with a young window present all five old windows were removable and the young one is the survivor. That matches the claim as worded ("never drops below one shuffle window plus one selfplay generation") and upstream `cleanup_old_dirs.py` semantics (the newest dir is what the trainer reads); it is a docstring imprecision, folded into o32.

```
    ##### P0 dry run, fixed rules
      | == prune_retention 2026-09-04T01:05:30-0400 DRY-RUN ==
      | constants : /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env
      | root      : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root
      | NOTE      : measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | basedir   : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop
      | -- protected set (6 entries; never a deletion candidate) --
      | -- deletion plan (15 paths, 660000 B) --
      exit=0
    
    ##### P1 --apply --target-bytes 0
      | prune_retention: WARNING cannot reach 0 B without going below the rolling minimum (1 shuffle window, 1 selfplay generation) or touching a protected path; best reachable 401241 B
      | == prune_retention 2026-09-04T01:05:30-0400 APPLY ==
      | constants : /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/data_budget/budget.env
      | root      : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root
      | NOTE      : measuring an OVERRIDDEN root: --root /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root (constants file root: /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train)
      | basedir   : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop
      | -- protected set (6 entries; never a deletion candidate) --
      | -- rolling mode: du -sb = 1961241 B, after fixed rules 1301241 B, target 0 B --
      | -- deletion plan (21 paths, 1560000 B) --
      |    REMOVE          100000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/shuffleddata/w0    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
      |    REMOVE          100000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/shuffleddata/w1    <- shuffleddata: keep newest 3 older than 7200s (cleanup_old_dirs.py:13,24)
      |    REMOVE           50000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/shuffleddata/orphan.tmp    <- orphan shuffleddata .tmp: shuffle.sh:105 renamed nothing; cleanup_old_dirs.py
      |    REMOVE          200000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/selfplay/gen0    <- selfplay: keep newest 3 generations, and only delete generations older than the oldest 
      |    REMOVE          200000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/selfplay/gen1    <- selfplay: keep newest 3 generations, and only delete generations older than the oldest 
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/train/ktg9/longterm_checkpoints/lt0.ckpt    <- longterm_checkpoints: keep newest 6 (train.py:1883-1889 writ
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/train/ktg9/longterm_checkpoints/lt1.ckpt    <- longterm_checkpoints: keep newest 6 (train.py:1883-1889 writ
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/train/ktg9/longterm_checkpoints/lt2.ckpt    <- longterm_checkpoints: keep newest 6 (train.py:1883-1889 writ
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/rejectedmodels/rej0    <- rejectedmodels: keep newest 10
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/rejectedmodels/rej1    <- rejectedmodels: keep newest 10
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/rejectedmodels/rej2    <- rejectedmodels: keep newest 10
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/rejectedmodels/rej3    <- rejectedmodels: keep newest 10
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/scripts/dated/d0    <- scripts/dated: keep newest 3 (each holds a katago binary)
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/scripts/dated/d1    <- scripts/dated: keep newest 3 (each holds a katago binary)
      |    REMOVE            1000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/scripts/dated/d2    <- scripts/dated: keep newest 3 (each holds a katago binary)
      |    REMOVE          100000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/shuffleddata/w2    <- rolling: over --target-bytes 0
      |    REMOVE          100000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/shuffleddata/w3    <- rolling: over --target-bytes 0
      |    REMOVE          100000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/shuffleddata/w4    <- rolling: over --target-bytes 0
      |    REMOVE          200000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/selfplay/gen2    <- rolling: over --target-bytes 0
      |    REMOVE          200000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/selfplay/gen3    <- rolling: over --target-bytes 0
      |    REMOVE          200000 B  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/root/loop/selfplay/gen4    <- rolling: over --target-bytes 0
      | -- removed 21 paths, 1560000 B --
      | -- plan written to /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/validator_o28prune.neT4ki/plan.json --
      exit=0
    
    ##### survivors after apply (relative to root)
        ./evidence
        ./evidence/keep.txt
        ./loop
        ./loop/evidence
        ./loop/evidence/keep.txt
        ./loop/models
        ./loop/models/m_base
        ./loop/models/m_base/f.bin
        ./loop/models/m_mid
        ./loop/models/m_mid/f.bin
        ./loop/models/m_new
        ./loop/models/m_new/f.bin
        ./loop/rejectedmodels
        ./loop/rejectedmodels/rej10
        ./loop/rejectedmodels/rej10/f.bin
        ./loop/rejectedmodels/rej11
        ./loop/rejectedmodels/rej11/f.bin
        ./loop/rejectedmodels/rej12
        ./loop/rejectedmodels/rej12/f.bin
        ./loop/rejectedmodels/rej13
        ./loop/rejectedmodels/rej13/f.bin
        ./loop/rejectedmodels/rej4
        ./loop/rejectedmodels/rej4/f.bin
        ./loop/rejectedmodels/rej5
        ./loop/rejectedmodels/rej5/f.bin
        ./loop/rejectedmodels/rej6
        ./loop/rejectedmodels/rej6/f.bin
        ./loop/rejectedmodels/rej7
        ./loop/rejectedmodels/rej7/f.bin
        ./loop/rejectedmodels/rej8
        ./loop/rejectedmodels/rej8/f.bin
        ./loop/rejectedmodels/rej9
        ./loop/rejectedmodels/rej9/f.bin
        ./loop/scripts
        ./loop/scripts/dated
        ./loop/scripts/dated/d3
        ./loop/scripts/dated/d3/f.bin
        ./loop/scripts/dated/d4
        ./loop/scripts/dated/d4/f.bin
        ./loop/scripts/dated/d5
        ./loop/scripts/dated/d5/f.bin
        ./loop/selfplay
        ./loop/selfplay/gen5
        ./loop/selfplay/gen5/f.bin
        ./loop/selfplay/gen_link
        ./loop/shuffleddata
        ./loop/shuffleddata/wyoung
        ./loop/shuffleddata/wyoung/f.bin
        ./loop/shuffleddata/young.tmp
        ./loop/shuffleddata/young.tmp/f.bin
        ./loop/train
        ./loop/train/ktg9
        ./loop/train/ktg9/checkpoint.ckpt
        ./loop/train/ktg9/checkpoint_prev0.ckpt
        ./loop/train/ktg9/longterm_checkpoints
        ./loop/train/ktg9/longterm_checkpoints/evil_link.ckpt
        ./loop/train/ktg9/longterm_checkpoints/lt3.ckpt
        ./loop/train/ktg9/longterm_checkpoints/lt4.ckpt
        ./loop/train/ktg9/longterm_checkpoints/lt5.ckpt
        ./loop/train/ktg9/longterm_checkpoints/lt6.ckpt
        ./loop/train/ktg9/longterm_checkpoints/lt7.ckpt
        ./loop/train/ktg9/longterm_checkpoints/lt8.ckpt
    
    ##### assertions
      PASS some shuffle window survives
      PASS the newest window (wyoung) survives
      PASS young.tmp survives
      PASS orphan.tmp removed
      PASS at least one selfplay generation survives
      PASS gen5 (newer than every retained window) survives
      PASS symlink gen_link untouched and its target intact
      PASS all three models/ dirs survive
      PASS checkpoint.ckpt and checkpoint_prev0.ckpt survive
      PASS longterm_checkpoints: exactly 6 regular .ckpt remain, newest kept
      PASS evil_link.ckpt symlink was never a candidate; its target intact
      PASS rejectedmodels == 10, newest kept
      PASS scripts/dated == 3, newest kept
      PASS both evidence trees intact
      windows surviving: wyoung
    young.tmp
      generations surviving: gen5
    gen_link
    
    ##### P2 second apply is idempotent (nothing left to remove beyond the rolling minimum)
      | prune_retention: WARNING cannot reach 0 B without going below the rolling minimum (1 shuffle window, 1 selfplay generation) or touching a protected path; best reachable 401241 B
      | -- deletion plan (0 paths, 0 B) --
      | -- removed 0 paths, 0 B --
    ALL ASSERTIONS PASS
    cleanup done
```

## 6. The worker's two error rows, checked

- `0024b5ef…` (iteration 7, `partial`, metric 22/23): the quoted observation is verbatim in `repair_o28.txt` § 4 (`FAIL  exit 3  (wanted 1)  D. …` / `== 22 passed, 1 failed ==`), and the earlier unexplained `section2_verification exit=1` is stated as unattributed at the time — honest. `scratch_guard.sh:95 took a SINGLE sample` is correct for commit `497fbbc` (line 95: `DU_LINE="$(du -sb "$ROOT" 2>/dev/null)" || { …; exit 3; }`). One caveat the row does not state: because that line discarded du's stderr, the specific du error was never captured; "an entry disappeared from under the walk" is an attribution by elimination (the same root measured cleanly seconds before and after, and today's `du` exits 0, so no persistent unreadable entry exists), not a captured message. The fix captures stderr, so a recurrence will be attributed directly. The fix is correct for every cause of a non-zero du (transient or persistent), which is why this does not change the verdict.
- `17302639…` (iteration 8, `pass`, 25/25): tests_run match what I reproduced (25/25; § 2 exit 0; ADV1–ADV5; T1/T2). The note correctly says no result/claim/knowledge row was appended by the worker and that the amended row stays `conditional`. Its one stale statement — o27 "still open" — was true at 04:54 UTC when the row was written; o27 was discharged at 04:59 UTC.

## 7. Remaining `[OPEN]`

1. `o32_data_budget_guard_hardening` (non-blocking, owner `worker data_budget`), opened here: (a) widen the literal-form check from `\$\{` to any `$` or backtick in a `KTG_*` assignment (V9a/V9c); (b) restrict `KTG_BUDGET_ENV` to a `*.env` basename inside the directory so a non-constants in-tree file cannot be sourced (V5 self-source hang, V4b/V5b `set -u` exit 1 misbooked by the wrapper as a hard-cap stop); (c) `realpath -e` the `--root` argument before `du`, or use `du -sbD`, so a symlink root cannot under-measure (R1); (d) align the pruner docstring's rolling minimum with the code (§ 5). None of these can loosen the guard from the environment with the committed files; the wrapper passes none of the affected inputs.
2. Status upgrade of `data-budget-guard-500gib` to `empirical`: at least one production cycle log showing the guard triple and exit code.
3. `c11_scratch_budget` stays `in_progress` (whole-run claim).

## 8. Appends (verbatim gate output) and row hashes

All appends with `CHANDRA_ROLE=validator` from the az root; no bypass flags on any row (`admission_flags` absent).

```
result append (gate re-ran the section-2 command: exit 0, 50.9 s):
{"appended": true, "paper": "arxiv-1902.10565", "result_id": "data-budget-guard-500gib", "status": "conditional", "timestamp": "2026-09-04T05:11:14.344821+00:00", "evidence_sha256": "65105acb43687a10d075f8fa0e5eef86729547c7f1cc1a4af0c8d86f5d21fbf9", "verified_exit_code": 0}
  data-budget-guard-500gib  conditional  row_hash 512cb7e2360343ba0f9793619365e9f27eeaa5d595d5a1625593c219f0778857
  (supersedes 5cf754db629df666f97e1e5596da536cb4eb4b35f795c31ea5feda1af7a007a6; evidence_sha256 is repair_o28.txt)

claims appends:
{"appended": true, "paper": "arxiv-1902.10565", "entry_id": "o28_data_budget_guard_repairs", "kind": "obligation", "status": "discharged", "timestamp": "2026-09-04T05:12:05.472495+00:00"}
  o28_data_budget_guard_repairs   discharged  discharged_by data-budget-guard-500gib  row_hash 6306461289bd72f02f3b07251f102014913916c6bf49dc14af84ecee5b2b339d
{"appended": true, "paper": "arxiv-1902.10565", "entry_id": "o04_scratch_budget", "kind": "obligation", "status": "discharged", "timestamp": "2026-09-04T05:12:05.665077+00:00"}
  o04_scratch_budget              discharged  discharged_by data-budget-guard-500gib  row_hash f040a35348b8233b171788430379b12cb1b8dcb29c28c3a1699a9d68923de347
{"appended": true, "paper": "arxiv-1902.10565", "entry_id": "o32_data_budget_guard_hardening", "kind": "obligation", "status": "open", "timestamp": "2026-09-04T05:12:05.815131+00:00"}
  o32_data_budget_guard_hardening open (non-blocking)                                  row_hash 57dff89ad39faf93439e089c0204c308ad3603610c5b3ef4055529299368627d

error-ledger validation row (pass, metric validator_probes_that_loosened_the_guard_from_the_environment 0/0):
{"appended": true, "git_commit": "741beca", "timestamp": "2026-09-04T05:12:05+00:00"}
  row_hash c132c7137245a88a833db517446217a821b5402f5c7e509ff3f080056c7df753
```

Views re-rendered from the ledgers: `decomposition/{claims,obligations,assumptions}.md` (`claims_database.py render-md`) and `decomposition/results.md` (`result_database.py render-md`).

## 9. Claim transitions

- `data-budget-guard-500gib`: re-admitted `conditional` (third append, latest wins); metric 11/11 → 25/25; o27/o28 conditions retired; production-log condition remains.
- `o28_data_budget_guard_repairs`: `open` → `discharged`.
- `o04_scratch_budget`: `open` → `discharged` (its two recorded remainders, o27 and o28, are both discharged).
- `o32_data_budget_guard_hardening`: new, `open`, non-blocking.
- `c11_scratch_budget`: unchanged, `in_progress`.
