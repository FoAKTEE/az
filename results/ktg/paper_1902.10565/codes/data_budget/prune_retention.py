#!/usr/bin/env python3
"""node data_budget - bounded rolling retention for the mission scratch tree.

Dry-run by default. Nothing is ever removed without ``--apply``, and the protected set is
computed and PRINTED before a single path is considered for deletion.

  usage: prune_retention.py [--root DIR] [--basedir DIR] [--apply]
                            [--target-bytes N] [--budget-env FILE] [--json FILE]

  --root DIR         mission root (default: KTG_SCRATCH_ROOT from budget.env)
  --basedir DIR      loop data dir (default: <root>/loop)
  --apply            actually delete; without it this is a report
  --target-bytes N   rolling mode: after the fixed rules, keep deleting the oldest
                     unprotected shuffleddata / selfplay generations until the measured
                     root size is at or below N bytes
  --budget-env FILE  alternate constants file (default: budget.env next to this script).
                     PINNED (o28): only a file that resolves INSIDE this script's own
                     directory is honoured - budget.env and the committed tests/ fixtures.
                     $KTG_BUDGET_ENV supplies the same default and is subject to the same
                     restriction; anything outside that subtree exits 3.
  --json FILE        also write the full plan as JSON

Root selection (o28). The root comes from KTG_SCRATCH_ROOT in the constants file, resolved
the way scratch_guard.sh resolves it: the FILE's value, never the environment. An exported
KTG_SCRATCH_ROOT does not redirect the pruner. Only an explicit --root does, and a --root
that differs from the constants file's root is announced with a NOTE line, so a re-scoped
prune cannot pass unremarked in a cycle log. Running with no --root is the documented call
contract in the scratch_guard.sh header (``python3 prune_retention.py --apply``) and it
targets the mission root.

Legacy constants files. A value written in the shell-default form ``"${NAME:-default}"``
resolves to `default` - the quotes are stripped BEFORE the form is recognised (the bug that
made the no---root call exit 3), and the environment is deliberately NOT consulted, so the
form cannot be used as an environment channel. The pruner accepts such a file with a NOTE
where scratch_guard.sh refuses it outright: the guard's refusal protects byte THRESHOLDS,
which is where an environment channel would matter, while a pruner that refuses to start
simply stops bounding the tree - which is the failure o28 was opened for.

Retention rules, each with its upstream justification:

  shuffleddata/<ts>            keep the newest KTG_KEEP_SHUFFLEDDATA dirs that are older
                               than KTG_SHUFFLEDDATA_MIN_AGE_S, matching upstream
                               python/selfplay/cleanup_old_dirs.py:13,24. Dirs younger than
                               the age threshold are never touched (a shuffle may be
                               feeding the trainer right now).
  shuffleddata/<ts>.tmp        orphan output of a shuffle that died before the rename at
                               python/selfplay/shuffle.sh:105. Upstream applies NO name
                               filter (cleanup_old_dirs.py:15-20 tests only is_dir and
                               mtime), so an orphan .tmp competes for one of the three
                               retained slots and can push out a GOOD shuffle dir. Swept
                               here explicitly, oldest first, once older than the age
                               threshold.
  selfplay/<model>/            keep the newest KTG_KEEP_SELFPLAY_GENERATIONS generations,
                               and NEVER remove a generation whose rows may still be inside
                               a retained shuffle window: a generation is deletable only if
                               it is older than the OLDEST retained shuffleddata dir.
  train/*/longterm_checkpoints keep the newest KTG_KEEP_LONGTERM_CHECKPOINTS .ckpt files.
                               python/train.py:1883-1889 writes one every 12 h forever and
                               nothing upstream prunes them.
  rejectedmodels/<name>        keep the newest KTG_KEEP_REJECTED_MODELS dirs.
  scripts/dated/<ts>           keep the newest KTG_KEEP_DATED_SCRIPTS archives (each holds
                               a katago binary).

Protected set (never a deletion candidate, always printed):
  - the frozen baseline: the OLDEST directory under <basedir>/models/
  - the latest accepted net: the NEWEST directory under <basedir>/models/
  - every train/*/checkpoint.ckpt and train/*/checkpoint_prev*.ckpt
    (python/train.py:573-578 keeps 4 short-term checkpoints itself)
  - anything under a path component named 'evidence'
  - the newest shuffleddata dir and anything younger than the age threshold

Rolling mode (--target-bytes) relaxes the keep-N floors above, but never below ONE shuffle
window older than the age threshold and ONE selfplay generation feeding it, and it never
removes a generation that a still-retained window could reference.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


SHELL_DEFAULT_RE = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*):-(.*)\}$", re.S)


def resolve_budget_env(path: str) -> str:
    """Refuse a constants file outside this script's own directory (o28).

    Honouring an arbitrary $KTG_BUDGET_ENV would let any writer choose the retention
    counts, and scratch_guard.sh applies the identical restriction to the byte thresholds.
    """
    here = os.path.realpath(HERE)
    real = os.path.realpath(os.path.abspath(path))
    if real != here and not real.startswith(here + os.sep):
        print(f"prune_retention: refusing an out-of-tree constants file: {path}",
              file=sys.stderr)
        print(f"                 only files under {here}{os.sep} may set the retention "
              f"bounds and the mission root.", file=sys.stderr)
        return ""
    return path


def load_budget(path: str) -> dict:
    """Read budget.env without executing it as a shell script.

    Quotes are stripped BEFORE the shell-default form is recognised: budget.env writes
    ``KTG_SCRATCH_ROOT="${KTG_SCRATCH_ROOT:-/scratch/...}"``-shaped values in quotes, and
    testing ``startswith("${")`` on the still-quoted string made every such value come back
    verbatim - the defect that made ``python3 prune_retention.py`` (no --root) exit 3 on a
    root literally named '${KTG_SCRATCH_ROOT:-...}' and prune nothing (o28).

    The default branch of ``${NAME:-default}`` is used and ``os.environ`` is deliberately
    NOT consulted: the constants file is the single source of truth, matching how
    scratch_guard.sh resolves the same value once the file is sourced.
    """
    out = {}
    notes = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip()
            # Unquote first, then drop any trailing inline comment - the same order bash
            # applies when scratch_guard.sh sources this file. Doing it the other way round
            # is what left a quoted ${...} value unrecognised (o28).
            quote = val[:1]
            if quote in ('"', "'"):
                end = val.find(quote, 1)
                val = val[1:end] if end != -1 else val[1:]
            elif "#" in val:
                val = val.split("#", 1)[0].strip()
            m = SHELL_DEFAULT_RE.match(val)
            if m:
                val = m.group(2)
                notes.append(f"{key} written as ${{{m.group(1)}:-...}}; pinned to the "
                             f"file default '{val}' (environment NOT consulted)")
            out[key] = val
    out["__notes__"] = notes          # printed by main(), never a constant
    return out


def du_bytes(root: str, attempts: int = 3, retry_sleep: float = 2.0) -> int | None:
    """`du -sb <root>` as an int, or None if it never exited 0.

    Same rule as scratch_guard.sh: entries vanishing from under the walk on a live mission
    root make du exit non-zero, so retry; but a non-zero du is never trusted, not even when
    it printed a partial total, because a partial total UNDER-counts and rolling mode would
    then think it had already reached its target.
    """
    err = ""
    for n in range(1, attempts + 1):
        proc = subprocess.run(["du", "-sb", root], capture_output=True, text=True)
        if proc.returncode == 0:
            try:
                return int(proc.stdout.split("\t")[0])
            except (ValueError, IndexError):
                pass
        err = " ".join(proc.stderr.split())[:300]
        print(f"prune_retention: WARNING du -sb attempt {n}/{attempts} on {root} exited "
              f"{proc.returncode}; its partial total is discarded"
              + (f" ({err})" if err else ""), file=sys.stderr)
        if n < attempts:
            time.sleep(retry_sleep)
    print(f"prune_retention: du -sb failed on {root} after {attempts} attempts"
          + (f": {err}" if err else ""), file=sys.stderr)
    return None


def dir_bytes(path: str) -> int:
    total = 0
    for dirpath, dirnames, filenames in os.walk(path, followlinks=False):
        for name in filenames:
            fp = os.path.join(dirpath, name)
            try:
                total += os.lstat(fp).st_size
            except OSError:
                pass
    return total


def entries(path: str, want_dirs: bool = True, suffix: str | None = None):
    """(mtime, path) for the children of `path`, oldest first."""
    if not os.path.isdir(path):
        return []
    out = []
    with os.scandir(path) as it:
        for e in it:
            try:
                st = e.stat(follow_symlinks=False)
            except OSError:
                continue
            if want_dirs and not e.is_dir(follow_symlinks=False):
                continue
            if not want_dirs and not e.is_file(follow_symlinks=False):
                continue
            if suffix is not None and not e.name.endswith(suffix):
                continue
            if suffix is None and want_dirs and e.name.endswith(".tmp"):
                continue
            out.append((st.st_mtime, e.path))
    out.sort()
    return out


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--root")
    ap.add_argument("--basedir")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--target-bytes", type=int, default=None)
    ap.add_argument("--budget-env", default=os.environ.get("KTG_BUDGET_ENV",
                                                           os.path.join(HERE, "budget.env")))
    ap.add_argument("--json")
    args = ap.parse_args()

    budget_env = resolve_budget_env(args.budget_env)
    if not budget_env:
        return 3
    if not os.path.isfile(budget_env):
        print(f"prune_retention: constants file not readable: {budget_env}", file=sys.stderr)
        return 3
    cfg = load_budget(budget_env)
    file_root = cfg["KTG_SCRATCH_ROOT"]
    root = args.root or file_root
    basedir = args.basedir or os.path.join(root, "loop")
    keep_shuf = int(cfg["KTG_KEEP_SHUFFLEDDATA"])
    min_age = int(cfg["KTG_SHUFFLEDDATA_MIN_AGE_S"])
    keep_long = int(cfg["KTG_KEEP_LONGTERM_CHECKPOINTS"])
    keep_rej = int(cfg["KTG_KEEP_REJECTED_MODELS"])
    keep_dated = int(cfg["KTG_KEEP_DATED_SCRIPTS"])
    keep_gen = int(cfg["KTG_KEEP_SELFPLAY_GENERATIONS"])

    now = time.time()
    age_cut = now - min_age

    print(f"== prune_retention {time.strftime('%Y-%m-%dT%H:%M:%S%z')} "
          f"{'APPLY' if args.apply else 'DRY-RUN'} ==")
    print(f"constants : {budget_env}")
    for note in cfg["__notes__"]:
        print(f"NOTE      : {note}")
    print(f"root      : {root}")
    if args.root and args.root != file_root:
        print(f"NOTE      : measuring an OVERRIDDEN root: --root {args.root} "
              f"(constants file root: {file_root})")
    print(f"basedir   : {basedir}")
    if not os.path.isdir(root):
        print(f"prune_retention: mission root does not exist: {root}", file=sys.stderr)
        return 3

    # ---- protected set, computed and printed FIRST --------------------------
    protected: list[tuple[str, str]] = []
    models_dir = os.path.join(basedir, "models")
    model_dirs = entries(models_dir)
    if model_dirs:
        protected.append(("frozen baseline (oldest models/ dir)", model_dirs[0][1]))
        if len(model_dirs) > 1:
            protected.append(("latest accepted net (newest models/ dir)", model_dirs[-1][1]))
    traindir = os.path.join(basedir, "train")
    if os.path.isdir(traindir):
        for name in sorted(os.listdir(traindir)):
            sub = os.path.join(traindir, name)
            for ck in ("checkpoint.ckpt",):
                p = os.path.join(sub, ck)
                if os.path.exists(p):
                    protected.append(("short-term checkpoint (train.py:573-578)", p))
            for _, p in entries(sub, want_dirs=False, suffix=".ckpt"):
                if os.path.basename(p).startswith("checkpoint_prev"):
                    protected.append(("short-term checkpoint (train.py:573-578)", p))
    shuf_dir = os.path.join(basedir, "shuffleddata")
    shuf_all = entries(shuf_dir)
    young = [p for (m, p) in shuf_all if m >= age_cut]
    for p in young:
        protected.append((f"shuffleddata younger than {min_age}s", p))
    if shuf_all:
        protected.append(("newest shuffleddata dir", shuf_all[-1][1]))
    ev = os.path.join(root, "evidence")
    if os.path.isdir(ev):
        protected.append(("evidence tree", ev))

    seen: set[str] = set()
    deduped = []
    for why, p in protected:
        if p in seen:
            continue
        seen.add(p)
        deduped.append((why, p))
    protected = deduped
    protected_paths = seen
    print(f"-- protected set ({len(protected)} entries; never a deletion candidate) --")
    if not protected:
        print("   (none: the loop tree does not exist yet)")
    for why, p in protected:
        print(f"   PROTECT  {p}    <- {why}")

    plan: list[dict] = []

    def consider(path: str, rule: str) -> None:
        if path in protected_paths:
            return
        if any(part == "evidence" for part in os.path.relpath(path, root).split(os.sep)):
            return
        plan.append({"path": path, "rule": rule,
                     "mtime": os.lstat(path).st_mtime if os.path.exists(path) else None,
                     "bytes": dir_bytes(path) if os.path.isdir(path)
                              else (os.lstat(path).st_size if os.path.exists(path) else 0)})

    # ---- rule: shuffleddata ------------------------------------------------
    shuf_old = [(m, p) for (m, p) in shuf_all if m < age_cut]
    for _, p in shuf_old[:max(0, len(shuf_old) - keep_shuf)]:
        consider(p, f"shuffleddata: keep newest {keep_shuf} older than {min_age}s "
                    f"(cleanup_old_dirs.py:13,24)")
    retained_shuf = [m for (m, p) in shuf_all
                     if (m, p) in shuf_old[max(0, len(shuf_old) - keep_shuf):] or m >= age_cut]
    oldest_retained_shuf = min(retained_shuf) if retained_shuf else None

    # ---- rule: orphan .tmp shuffle dirs ------------------------------------
    for m, p in entries(shuf_dir, suffix=".tmp"):
        if m < age_cut:
            consider(p, "orphan shuffleddata .tmp: shuffle.sh:105 renamed nothing; "
                        "cleanup_old_dirs.py applies no name filter")

    # ---- rule: selfplay generations ----------------------------------------
    sp_dir = os.path.join(basedir, "selfplay")
    sp_gens = entries(sp_dir)
    for m, p in sp_gens[:max(0, len(sp_gens) - keep_gen)]:
        if oldest_retained_shuf is not None and m >= oldest_retained_shuf:
            continue          # rows may still be inside a retained shuffle window
        consider(p, f"selfplay: keep newest {keep_gen} generations, and only delete "
                    f"generations older than the oldest retained shuffle window")

    # ---- rule: longterm checkpoints ----------------------------------------
    if os.path.isdir(traindir):
        for name in sorted(os.listdir(traindir)):
            lt = os.path.join(traindir, name, "longterm_checkpoints")
            cks = entries(lt, want_dirs=False, suffix=".ckpt")
            for _, p in cks[:max(0, len(cks) - keep_long)]:
                consider(p, f"longterm_checkpoints: keep newest {keep_long} "
                            f"(train.py:1883-1889 writes one every 12 h, never prunes)")

    # ---- rule: rejectedmodels ----------------------------------------------
    rej = entries(os.path.join(basedir, "rejectedmodels"))
    for _, p in rej[:max(0, len(rej) - keep_rej)]:
        consider(p, f"rejectedmodels: keep newest {keep_rej}")

    # ---- rule: dated script archives ---------------------------------------
    dated = entries(os.path.join(basedir, "scripts", "dated"))
    for _, p in dated[:max(0, len(dated) - keep_dated)]:
        consider(p, f"scripts/dated: keep newest {keep_dated} (each holds a katago binary)")

    # ---- rolling mode: keep going until under --target-bytes ----------------
    # Rolling mode relaxes the fixed keep-N floors, but never below the minimum the loop
    # needs to keep running: ONE shuffle window older than the age threshold, and ONE
    # selfplay generation feeding it. It prunes shuffleddata first, then recomputes the
    # oldest retained window so the selfplay guard tightens with every window dropped -
    # a generation is only ever deletable once no retained window can still reference it.
    ROLLING_MIN_SHUFFLE_DIRS = 1
    ROLLING_MIN_SELFPLAY_GENERATIONS = 1
    rolling: list[dict] = []
    if args.target_bytes is not None:
        used = du_bytes(root)
        if used is None:
            return 3
        projected = used - sum(e["bytes"] for e in plan)
        print(f"-- rolling mode: du -sb = {used} B, after fixed rules {projected} B, "
              f"target {args.target_bytes} B --")
        planned = {e["path"] for e in plan}

        def add(path: str, mtime: float) -> None:
            nonlocal projected
            b = dir_bytes(path)
            rolling.append({"path": path, "mtime": mtime, "bytes": b,
                            "rule": f"rolling: over --target-bytes {args.target_bytes}"})
            planned.add(path)
            projected -= b

        # 1. shuffle windows, oldest first, down to ROLLING_MIN_SHUFFLE_DIRS survivors
        live_shuf = [(m, pth) for (m, pth) in shuf_all
                     if pth not in planned and pth not in protected_paths]
        live_shuf.sort()
        for m, pth in live_shuf:
            if projected <= args.target_bytes:
                break
            survivors = len([1 for (mm, pp) in shuf_all if pp not in planned])
            if survivors <= ROLLING_MIN_SHUFFLE_DIRS:
                break
            add(pth, m)

        # 2. selfplay generations, oldest first, only those no retained window can reference
        live_shuf_mtimes = [m for (m, pp) in shuf_all if pp not in planned]
        oldest_retained = min(live_shuf_mtimes) if live_shuf_mtimes else None
        live_gens = [(m, pth) for (m, pth) in sp_gens
                     if pth not in planned and pth not in protected_paths]
        live_gens.sort()
        for m, pth in live_gens:
            if projected <= args.target_bytes:
                break
            survivors = len([1 for (mm, pp) in sp_gens if pp not in planned])
            if survivors <= ROLLING_MIN_SELFPLAY_GENERATIONS:
                break
            if oldest_retained is not None and m >= oldest_retained:
                continue      # rows may still be inside a retained shuffle window
            add(pth, m)

        if projected > args.target_bytes:
            print(f"prune_retention: WARNING cannot reach {args.target_bytes} B without going "
                  f"below the rolling minimum ({ROLLING_MIN_SHUFFLE_DIRS} shuffle window, "
                  f"{ROLLING_MIN_SELFPLAY_GENERATIONS} selfplay generation) or touching a "
                  f"protected path; best reachable {projected} B", file=sys.stderr)
    plan.extend(rolling)

    # ---- report / apply -----------------------------------------------------
    total = sum(e["bytes"] for e in plan)
    print(f"-- deletion plan ({len(plan)} paths, {total} B) --")
    if not plan:
        print("   (nothing to remove)")
    for e in plan:
        print(f"   {'REMOVE ' if args.apply else 'WOULD-REMOVE'} {e['bytes']:>14} B  "
              f"{e['path']}    <- {e['rule']}")

    removed = 0
    if args.apply:
        for e in plan:
            p = e["path"]
            try:
                if os.path.isdir(p) and not os.path.islink(p):
                    shutil.rmtree(p)
                else:
                    os.remove(p)
                removed += 1
            except OSError as exc:
                print(f"prune_retention: failed to remove {p}: {exc}", file=sys.stderr)
                return 1
        print(f"-- removed {removed} paths, {total} B --")

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"root": root, "basedir": basedir, "apply": args.apply,
                       "constants": budget_env,
                       "protected": [{"reason": w, "path": p} for w, p in protected],
                       "plan": plan, "plan_bytes": total}, fh, indent=2)
        print(f"-- plan written to {args.json} --")
    return 0


if __name__ == "__main__":
    sys.exit(main())
