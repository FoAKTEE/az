#!/usr/bin/env python3
"""seed_rows_history.py -- fill evidence/production_chain/rows_per_game_history.jsonl.
Obligation o51.

The history is append-only and is written from then on by the read tooling
(`throughput_report.py --history-out`, on by default beside `--out`).  This script
exists for the ONE-OFF seeding of everything that happened before the history
existed, and it is re-runnable: `rows_history.append_records` is idempotent on
(net, games, rows), so running it twice adds nothing.

Two sources, both read-only:

  --git REPO   every committed version of `--rows-file-path` in REPO, oldest
               commit first.  `rows_per_game.txt` is REGENERATED from the live
               tree at each monitoring read and committed with it, so the seven
               committed versions together carry the per-net table of seven
               different moments -- including the nets that node data_budget's
               retention pass has since deleted from the tree.  Each version is
               parsed by `rows_history.records_from_rows_table`, which drops that
               version's newest directory (still being written) and stamps the
               `prev_net` that the version's own ordering proves.

  --tree DIR   the selfplay directories present in a BASEDIR right now, counted
               the way throughput_report counts them (audit_smoke.sgfs_stats for
               games, audit_smoke.npz_report for rows).  READ-ONLY: nothing is
               written under DIR.

usage:
  seed_rows_history.py --out EV/rows_per_game_history.jsonl \\
      [--git /home/.../az] [--rows-file-path results/.../rows_per_game.txt] \\
      [--tree /scratch/.../runs/p1] [--link-job 305318] [--dry-run]
"""

from __future__ import annotations

import argparse
import glob
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import audit_smoke as A            # noqa: E402
import rows_history as H           # noqa: E402

DEFAULT_ROWS_PATH = ("results/ktg/paper_1902.10565/evidence/production_chain/"
                     "rows_per_game.txt")


def git(repo, *args):
    return subprocess.check_output(("git", "-C", repo) + args,
                                   stderr=subprocess.DEVNULL).decode("utf-8", "replace")


def from_git(repo, rel_path, index=None):
    """Records from every committed version of `rel_path`, oldest commit first."""
    index = index or {}
    out = []
    shas = git(repo, "log", "--format=%H", "--", rel_path).split()
    for sha in reversed(shas):              # oldest first: prev_net merges forward
        when = git(repo, "log", "-1", "--format=%cI", sha).strip()
        try:
            blob = git(repo, "show", "%s:%s" % (sha, rel_path))
        except subprocess.CalledProcessError:
            continue
        complete, newest = H.records_from_rows_table(blob)
        for name, games, rows, prev in complete:
            out.append(H.make_record(
                name, games, rows, prev_net=prev, net_index=index.get(name),
                recorded_at=when,
                source="git:%s:%s" % (sha[:12], os.path.basename(rel_path))))
        print("  %s  %s  %2d complete record(s), newest (dropped) %s"
              % (sha[:12], when, len(complete), newest))
    return out


def from_tree(basedir, link_job=None):
    """Records from the selfplay directories a BASEDIR holds right now (read-only)."""
    per_net = {}
    for d in sorted(glob.glob(os.path.join(basedir, "selfplay", "*"))):
        if not os.path.isdir(d):
            continue
        name = os.path.basename(d)
        s = A.sgfs_stats([os.path.join(d, "sgfs", "*.sgfs")])
        rep = A.npz_report(sorted(glob.glob(os.path.join(d, "tdata", "*.npz"))))
        per_net[name] = {"games": s["lines"], "rows": rep["rows"],
                         "real_net": name != "random",
                         "tdata_bytes": A.dir_bytes(os.path.join(d, "tdata"))}
    recs, newest = H.records_from_per_net(
        per_net, basedir=basedir, link_job=link_job,
        recorded_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        source="seed_rows_history.py --tree")
    print("  %s  %d complete record(s), newest (dropped) %s"
          % (basedir, len(recs), newest))
    return recs


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True, help="the history JSONL to append to")
    ap.add_argument("--git", default=None, help="repo whose history of --rows-file-path is read")
    ap.add_argument("--rows-file-path", default=DEFAULT_ROWS_PATH,
                    help="path of rows_per_game.txt INSIDE the repo")
    ap.add_argument("--tree", default=None, help="a BASEDIR to scan (read-only)")
    ap.add_argument("--models-from", default=None,
                    help="BASEDIR whose models/ supplies the accepted-net index "
                         "(default: --tree). models/ is never pruned, so it is what "
                         "turns a gap into a COUNT of missing accepted nets.")
    ap.add_argument("--link-job", default=None)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)

    index = H.models_index(a.models_from or a.tree or "")
    if index:
        print("accepted-net index from %s/models: %d net(s), 0..%d (never pruned)"
              % (a.models_from or a.tree, len(index), len(index) - 1))
    else:
        print("NO accepted-net index available: pass --tree or --models-from to read "
              "<BASEDIR>/models, or the gap report can only use prev_net")
    recs = []
    if a.git:
        print("from git history of %s in %s:" % (a.rows_file_path, a.git))
        recs += from_git(a.git, a.rows_file_path, index)
    if a.tree:
        print("from the live tree:")
        recs += from_tree(a.tree, a.link_job)
    if not recs:
        print("seed_rows_history: nothing to seed (pass --git and/or --tree)",
              file=sys.stderr)
        return 2

    if a.dry_run:
        print("DRY RUN: %d record(s) would be offered to %s" % (len(recs), a.out))
        return 0
    added, skipped = H.append_records(a.out, recs)
    print("")
    print("appended %d record(s), skipped %d already present -> %s"
          % (len(added), len(skipped), a.out))
    merged = H.ordered(H.read_history(a.out))
    print("history now holds %d complete real-net net(s)" % len(merged))
    gaps = [(x, y) for x, y, ok in H.adjacency(merged) if not ok]
    for x, y in gaps:
        print("  GAP  %s" % H.describe_gap(x, y))
    if not gaps:
        print("  no gaps: every recorded net names its predecessor")
    return 0


if __name__ == "__main__":
    sys.exit(main())
