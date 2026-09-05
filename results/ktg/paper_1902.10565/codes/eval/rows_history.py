#!/usr/bin/env python3
"""rows_history.py -- the append-only per-net rows/game record.  Obligation o51.

WHY THIS FILE EXISTS.  `rows_per_game.txt` and the `per_net` table of
`throughput.json` are both REGENERATED from the live scratch tree at every
monitoring read, and node data_budget's retention pass deletes selfplay
generations at every link start (`prune_retention.py`, KTG_KEEP_SELFPLAY_
GENERATIONS = 3, plus the shuffle-window guard).  So the regenerated tables lose
a net the moment its directory is pruned: at the link-1 -> link-2 boundary 52
generations were removed, 7 remained, 6 of them complete, and 12 accepted nets
(t9-s11951360-d2093144 .. t9-s15547392-d2603142) exist in no surviving table at
all.  That is what made o48's slope leg -- a least-squares fit of rows/game over
the last NINE complete real-net directories -- uncomputable from the tree, and it
is obligation o51.

WHAT THIS FILE IS.  A JSON-lines record, one line per COMPLETE real-net selfplay
directory, appended by the read tooling BEFORE anything can prune the directory,
never rewritten and never sorted in place.  Old lines are only ever superseded by
a newer line for the same net; readers take the LAST line per net.

    {"net": "t9-s17045760-d2821985", "s": 17045760, "d": 2821985,
     "prev_net": "t9-s16746112-d2770965", "games": 2000, "rows": 33981,
     "rows_per_game": 16.9905, "tdata_bytes": 12447232,
     "first_mtime": 1757..., "last_mtime": 1757..., "link_job": "305318",
     "basedir": "/scratch/.../runs/p1", "recorded_at": "2026-09-05T23:41:02Z",
     "source": "throughput_report.py"}

`tdata_bytes`, the two mtimes and `link_job` are null for a record recovered from
git history, which carries only the committed table.  Nothing downstream reads
them for arithmetic; they are provenance.

THE GAP RULE (the reason `prev_net` is on every record).  A trend fit over
"the last nine accepted nets" is only that if the nine are CONSECUTIVE.  Across a
gap the x axis of the least-squares fit is a lie -- the validator's own
gap-spanning fit came out at -0.0017 rows/game per accepted net against the
-0.1742 the contiguous read-6 window measured, two orders of magnitude apart --
so a fit across a gap must be REFUSED, not silently computed.

Contiguity is recorded, not inferred from the net names: a rejected candidate
consumes training samples without ever producing a selfplay directory, so the
step between two consecutive accepted nets is not a constant and cannot be used
to detect a missing one.  What CAN be used is the observation the record came
from.  `prune_retention.py` deletes selfplay generations oldest-first (its
candidate list is `sp_gens[:len-keep]`, ordered by mtime, and the shuffle-window
`continue` can only skip a suffix of that list because mtime is ascending), so
what survives in the tree is always a contiguous SUFFIX of the true sequence.
Therefore the real-net directories listed in ONE observation are consecutive, and
`prev_net` -- the directory immediately before this one in the same observation --
is a fact about the run, not a guess.  Two records are provably adjacent iff the
later one's `prev_net` names the earlier one; anything else is a gap, including
an unknown (`null`) predecessor.  `"random"` as a `prev_net` marks the first real
net of the run, whose predecessor is the bootstrap directory.

STANDARD LIBRARY ONLY.  This is a login-node reader, like everything else in
codes/eval that the monitoring reads call.
"""

from __future__ import annotations

import json
import os
import re

NET_RE = re.compile(r"-s([0-9]+)-d([0-9]+)$")

# Every key a record carries, in the order they are written.
FIELDS = ("net", "s", "d", "net_index", "prev_net", "games", "rows", "rows_per_game",
          "tdata_bytes", "first_mtime", "last_mtime", "link_job", "basedir",
          "recorded_at", "source")

# The keys that make two records the same OBSERVATION of the same net.  A record
# is appended only when this triple is new, which is what makes the append
# idempotent: running the read tooling twice over an unchanged tree adds nothing.
IDENTITY = ("net", "games", "rows")


def parse_net(name):
    """('t9-s17045760-d2821985') -> (17045760, 2821985); None for 'random'."""
    m = NET_RE.search(name or "")
    if not m:
        return None
    return int(m.group(1)), int(m.group(2))


def make_record(net, games, rows, prev_net=None, tdata_bytes=None,
                first_mtime=None, last_mtime=None, link_job=None, basedir=None,
                recorded_at=None, source=None, net_index=None):
    sd = parse_net(net)
    if sd is None:
        raise ValueError("not a real-net selfplay directory name: %r" % (net,))
    if not games:
        raise ValueError("net %s has no games; an empty directory is not a record" % net)
    return {
        "net": net, "s": sd[0], "d": sd[1], "net_index": net_index,
        "prev_net": prev_net,
        "games": int(games), "rows": int(rows),
        "rows_per_game": int(rows) / float(games),
        "tdata_bytes": tdata_bytes, "first_mtime": first_mtime,
        "last_mtime": last_mtime, "link_job": link_job, "basedir": basedir,
        "recorded_at": recorded_at, "source": source,
    }


def read_history(path):
    """Every line of the record, in file order.  A missing file reads as empty."""
    out = []
    if not path or not os.path.exists(path):
        return out
    with open(path, "r") as fh:
        for n, line in enumerate(fh, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                raise SystemExit("rows_history: %s line %d is not JSON" % (path, n))
            if not isinstance(rec, dict) or "net" not in rec:
                raise SystemExit("rows_history: %s line %d is not a record" % (path, n))
            out.append(rec)
    return out


def latest_by_net(records):
    """{net: record}, the LAST line per net winning, with `prev_net` carried.

    A later observation of the same net supersedes an earlier one (it saw more of
    the directory).  `prev_net` is merged separately and monotonically: once ANY
    observation has named a net's predecessor, that fact does not expire because a
    later, more pruned observation could not see it.
    """
    best = {}
    prev = {}
    idx = {}
    for rec in records:
        net = rec.get("net")
        if not net:
            continue
        if rec.get("prev_net"):
            prev[net] = rec["prev_net"]
        if rec.get("net_index") is not None:
            idx[net] = rec["net_index"]
        cur = best.get(net)
        if cur is None or (int(rec.get("rows") or 0), int(rec.get("games") or 0)) >= \
                (int(cur.get("rows") or 0), int(cur.get("games") or 0)):
            best[net] = dict(rec)
    for net, p in prev.items():
        if net in best:
            best[net]["prev_net"] = p
    for net, i in idx.items():
        if net in best:
            best[net]["net_index"] = i
    return best


def ordered(records):
    """The merged records as a list ordered by global-step samples, ascending."""
    best = latest_by_net(records)
    out = [r for r in best.values() if parse_net(r["net"])]
    out.sort(key=lambda r: (int(r.get("s") or parse_net(r["net"])[0]), r["net"]))
    return out


def append_records(path, records):
    """Append the records this history does not already hold.  Returns (added, skipped).

    Idempotent on (net, games, rows): the same observation appended twice adds one
    line.  Nothing is ever rewritten, so the file is safe to append to from a
    monitoring read while a link is running.
    """
    have = set()
    for rec in read_history(path):
        have.add(tuple(str(rec.get(k)) for k in IDENTITY))
    added, skipped = [], []
    lines = []
    for rec in records:
        key = tuple(str(rec.get(k)) for k in IDENTITY)
        if key in have:
            skipped.append(rec)
            continue
        have.add(key)
        added.append(rec)
        lines.append(json.dumps({k: rec.get(k) for k in FIELDS}, sort_keys=False))
    if lines:
        d = os.path.dirname(os.path.abspath(path))
        if d and not os.path.isdir(d):
            os.makedirs(d)
        with open(path, "a") as fh:
            fh.write("\n".join(lines) + "\n")
    return added, skipped


# --------------------------------------------------------------------------- gaps
def is_adjacent(a, b):
    """True when `b` is provably the accepted net immediately after `a`.

    Two independent proofs, either of which suffices:
      * `b` was observed in a table whose previous row was `a` (`prev_net`), or
      * both carry an accepted-net index read from <basedir>/models/, which the
        retention pass never touches, and the indices differ by exactly one.
    Anything else -- including an unknown predecessor -- is a gap. The
    conservative direction is deliberate: a fit is refused, never faked.
    """
    if b.get("prev_net") == a.get("net"):
        return True
    ia, ib = a.get("net_index"), b.get("net_index")
    if ia is not None and ib is not None:
        return int(ib) - int(ia) == 1
    return False


def adjacency(recs):
    """[(earlier, later, contiguous_bool), ...] over `recs` in the given order."""
    return [(a, b, is_adjacent(a, b)) for a, b in zip(recs, recs[1:])]


def contiguous_runs(recs):
    """Split `recs` (ordered) into maximal runs of provably adjacent records."""
    if not recs:
        return []
    runs = [[recs[0]]]
    for a, b, ok in adjacency(recs):
        if ok:
            runs[-1].append(b)
        else:
            runs.append([b])
    return runs


def describe_gap(a, b):
    ia, ib = a.get("net_index"), b.get("net_index")
    if ia is not None and ib is not None:
        missing = int(ib) - int(ia) - 1
        return ("%s (accepted net %d) -> %s (accepted net %d): %d accepted net(s) in "
                "between have no complete record"
                % (a.get("net"), int(ia), b.get("net"), int(ib), missing))
    return ("%s -> %s (the later record's prev_net is %s, not %s, and no accepted-net "
            "index pair proves adjacency)"
            % (a.get("net"), b.get("net"),
               ("null" if not b.get("prev_net") else b["prev_net"]), a.get("net")))


def tail_run(recs):
    """The maximal run of provably adjacent records ENDING at the newest one."""
    runs = contiguous_runs(recs)
    return runs[-1] if runs else []


def fit_window(recs, want):
    """(window, note) -- the last `want` records, never crossing a gap.

    Returns the last `want` records when they are provably consecutive.  When they
    are not, the window is NARROWED to the contiguous run that ends at the newest
    record and `note` says which gap stopped it.  The fit is never computed across
    a gap and the narrowing is never silent -- that is the whole of obligation
    o51's second half.
    """
    if want <= 0 or not recs:
        return [], "no records"
    run = tail_run(recs)
    if want <= len(run):
        return run[-want:], ""
    runs = contiguous_runs(recs)
    if len(runs) < 2:
        return run, ("only %d complete record(s) exist, fewer than the %d asked for"
                     % (len(run), want))
    a, b = runs[-2][-1], runs[-1][0]
    return run, ("REFUSED to fit across a gap: %s. The window is narrowed to the %d "
                 "record(s) of the contiguous run ending at %s, instead of the %d "
                 "asked for." % (describe_gap(a, b), len(run), run[-1]["net"], want))


def least_squares_slope(recs):
    """Least-squares slope of rows/game per accepted net over `recs` (x = 0,1,2...)."""
    ys = [r["rows"] / float(r["games"]) for r in recs]
    if len(ys) < 2:
        return 0.0
    xs = list(range(len(ys)))
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    den = sum((x - mx) ** 2 for x in xs)
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den if den else 0.0


def aggregate(recs):
    """(rows, games, rows/game) over `recs`."""
    rows = sum(int(r["rows"]) for r in recs)
    games = sum(int(r["games"]) for r in recs)
    return rows, games, (rows / float(games) if games else None)


def is_history_file(path):
    """True for a JSON-lines history, False for the rows_per_game text table."""
    if not path or not os.path.exists(path):
        return False
    if path.endswith(".jsonl"):
        return True
    with open(path, "r") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            return line.startswith("{")
    return False


def records_from_rows_table(text):
    """Parse the per-net block of a `rows_per_game.txt` into records.

    The table is what `throughput_report.write_rows_file` writes:

        t9-s17045760-d2821985  real_net=True  games=2000  rows=33981  rows/game=16.99

    Real-net rows are returned ordered by global-step samples, each carrying the
    `prev_net` the ORDER of this one table proves (see the module docstring), and
    the NEWEST row is dropped: it is the directory still being written, whose npz
    lag its own sgfs.  `random` is not a record; it only anchors the first real
    net's `prev_net`.
    """
    rows, has_random = [], False
    for line in (text or "").splitlines():
        m = re.match(r"\s+(\S+)\s+real_net=(\S+)\s+games=(\d+)\s+rows=(\d+)\b", line)
        if not m:
            continue
        name, real, games, nrows = m.group(1), m.group(2), int(m.group(3)), int(m.group(4))
        if name == "probe_search":
            continue
        if real.lower().startswith("f") or parse_net(name) is None:
            has_random = has_random or name == "random"
            continue
        rows.append((parse_net(name)[0], name, games, nrows))
    rows.sort()
    out = []
    for i, (_s, name, games, nrows) in enumerate(rows):
        if i == 0:
            prev = "random" if has_random else None
        else:
            prev = rows[i - 1][1]
        out.append((name, games, nrows, prev))
    return out[:-1], (out[-1] if out else None)


def dir_mtimes(path):
    """(first, last) mtime over the sgfs and tdata files of one selfplay directory."""
    lo = hi = None
    for sub in ("sgfs", "tdata"):
        d = os.path.join(path, sub)
        if not os.path.isdir(d):
            continue
        for name in os.listdir(d):
            try:
                m = os.stat(os.path.join(d, name)).st_mtime
            except OSError:
                continue
            lo = m if lo is None or m < lo else lo
            hi = m if hi is None or m > hi else hi
    return lo, hi


def models_index(basedir):
    """{net name: accepted-net index} from <basedir>/models/, ordered by -s<samples>.

    models/ is the one directory prune_retention.py never touches (it protects the
    oldest and the newest and no rule names the rest), so it is the authority on
    WHICH accepted nets exist and in what order -- including the ones whose
    selfplay generation was deleted long ago. That is what turns "a gap" into
    "13 accepted nets in between have no complete record".
    """
    d = os.path.join(basedir or "", "models")
    if not os.path.isdir(d):
        return {}
    names = [n for n in os.listdir(d)
             if parse_net(n) and os.path.isdir(os.path.join(d, n))]
    names.sort(key=lambda n: parse_net(n)[0])
    return {n: i for i, n in enumerate(names)}


def records_from_per_net(per_net, basedir=None, link_job=None, recorded_at=None,
                         source=None, with_mtimes=True, index=None):
    """(records, newest) from a throughput_report-shaped `per_net` mapping.

    `per_net` is {name: {"games": n, "rows": n, "real_net": bool, ...}}.  Only
    COMPLETE real-net directories become records: the newest real-net directory is
    the one still being written -- its npz lag its own sgfs, which is why the same
    18035 rows read as 15.88 rows/game in one table and 17.34 in another -- so it
    is returned separately and never recorded.  `prev_net` comes from the order of
    THIS observation (module docstring), with "random" for the first real net when
    the bootstrap directory is still present.
    """
    real, has_random = [], False
    for name, d in (per_net or {}).items():
        if not d or not d.get("games"):
            if name == "random":
                has_random = True
            continue
        sd = parse_net(name)
        if sd is None or not d.get("real_net", True):
            if name == "random":
                has_random = True
            continue
        real.append((sd[0], name, int(d["games"]), int(d["rows"]),
                     d.get("tdata_bytes")))
    real.sort()
    if index is None:
        index = models_index(basedir) if basedir else {}
    out = []
    for i, (_s, name, games, rows, tbytes) in enumerate(real[:-1]):
        prev = real[i - 1][1] if i else ("random" if has_random else None)
        lo = hi = None
        if with_mtimes and basedir:
            lo, hi = dir_mtimes(os.path.join(basedir, "selfplay", name))
        out.append(make_record(name, games, rows, prev_net=prev, tdata_bytes=tbytes,
                               first_mtime=lo, last_mtime=hi, link_job=link_job,
                               basedir=basedir, recorded_at=recorded_at,
                               source=source, net_index=index.get(name)))
    return out, (real[-1][1] if real else None)


if __name__ == "__main__":  # a reader, not a command; print what a history holds
    import sys
    p = sys.argv[1] if len(sys.argv) > 1 else None
    recs = ordered(read_history(p))
    print("rows_history %s -- %d complete real-net record(s)" % (p, len(recs)))
    for a, b, ok in adjacency(recs):
        if not ok:
            print("  GAP  %s" % describe_gap(a, b))
    for r in recs:
        print("  %-30s idx %-4s games %6d  rows %8d  rows/game %7.3f  prev %s"
              % (r["net"], r.get("net_index"), r["games"], r["rows"],
                 r["rows"] / float(r["games"]), r.get("prev_net")))
