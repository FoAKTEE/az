#!/usr/bin/env python3
"""Checks for the append-only per-net rows/game record.  Obligation o51.

Runnable on a login node with the standard library only, either as

    python3 codes/eval/test_rows_history.py
    python3 -m pytest codes/eval/test_rows_history.py -q

Five tests, one per conjunct of o51:

  A  append idempotence   appending the same observation twice adds one line; a LATER
                          observation of the same net (more games, more rows) supersedes
                          the earlier one without rewriting it.
  B  gap refusal          a trend window that would span a gap is REFUSED and narrowed to
                          the contiguous run ending at the newest record, and the refusal
                          names the gap.  A window that fits inside the run is untouched.
  C  contiguous fit       over the record built from the committed link-1 -> link-2
                          rows_per_game.txt the marginal reproduces the validator's
                          16.9087 = 118361 / 7000 exactly, and the slope over the
                          contiguous run reproduces the read-6 arithmetic.
  D  the newest is never  the directory still being written is excluded from the record,
     recorded             whichever source the record was built from.
  E  prev_net is merged   a pruned later observation cannot erase a predecessor an
     monotonically        earlier observation proved.
  F  the accepted-net     with a <basedir>/models/ index on both sides of a gap, the gap
     index counts a gap   reports HOW MANY accepted nets have no complete record, and an
                          index pair one apart proves adjacency on its own.
"""

from __future__ import annotations

import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import rows_history as H  # noqa: E402

# The per-net table of evidence/production_chain/rows_per_game.txt as committed at the
# link-1 -> link-2 boundary (commit ebbc623).  Reproduced verbatim so the test does not
# depend on a file the read tooling regenerates.
BOUNDARY_TABLE = """
per selfplay net directory (name = the net that played, 'random' = bootstrap):
  t9-s15847040-d2653436        real_net=True  games=2000   rows=33894    rows/game=16.947
  t9-s16146944-d2687330        real_net=True  games=5000   rows=83635    rows/game=16.727
  t9-s16746112-d2770965        real_net=True  games=3000   rows=51020    rows/game=17.006666666666668
  t9-s17045760-d2821985        real_net=True  games=2000   rows=33981    rows/game=16.9905
  t9-s17345664-d2855966        real_net=True  games=3000   rows=50883    rows/game=16.961
  t9-s17645440-d2906849        real_net=True  games=2000   rows=33497    rows/game=16.7485
  t9-s17945216-d2940346        real_net=True  games=2823   rows=36100    rows/game=12.787814381863265
"""

# Three of the nets recorded at read 8 whose directories the link-2 retention pass then
# deleted; they sit on the far side of the 13-net gap from the table above.
EARLY_TABLE = """
per selfplay net directory (name = the net that played, 'random' = bootstrap):
  t9-s10453248-d1890719        real_net=True  games=2000   rows=33429    rows/game=16.7145
  t9-s10752896-d1924148        real_net=True  games=3000   rows=51272    rows/game=17.0906
  t9-s11052672-d1975420        real_net=True  games=2000   rows=33473    rows/game=16.7365
  t9-s11352064-d2008893        real_net=True  games=3000   rows=50780    rows/game=16.9266
  t9-s11651712-d2059673        real_net=True  games=908    rows=12114    rows/game=13.34
"""


def records_of(table, source):
    complete, _newest = H.records_from_rows_table(table)
    return [H.make_record(n, g, r, prev_net=p, source=source)
            for (n, g, r, p) in complete]


def newest_of(table):
    _complete, newest = H.records_from_rows_table(table)
    return newest


def seeded(path):
    """A record holding the early table and then the boundary table -- with the gap."""
    H.append_records(path, records_of(EARLY_TABLE, "test:early"))
    H.append_records(path, records_of(BOUNDARY_TABLE, "test:boundary"))
    return H.ordered(H.read_history(path))


# --------------------------------------------------------------------------- A
def test_append_is_idempotent():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "h.jsonl")
        recs = records_of(BOUNDARY_TABLE, "test")
        added, skipped = H.append_records(p, recs)
        assert len(added) == 6 and not skipped, (len(added), len(skipped))
        added, skipped = H.append_records(p, recs)
        assert not added and len(skipped) == 6, (len(added), len(skipped))
        assert len(H.read_history(p)) == 6
        assert len(H.ordered(H.read_history(p))) == 6

        # a LATER observation of the same net supersedes it, and appends rather than
        # rewrites: the file grows, the merged view does not.
        more = [H.make_record("t9-s17645440-d2906849", 2600, 43600,
                              prev_net="t9-s17345664-d2855966", source="test:later")]
        added, _ = H.append_records(p, more)
        assert len(added) == 1
        assert len(H.read_history(p)) == 7
        merged = H.latest_by_net(H.read_history(p))
        assert merged["t9-s17645440-d2906849"]["games"] == 2600
        assert len(H.ordered(H.read_history(p))) == 6
    print("A ok  append idempotence, and a later observation supersedes without rewriting")


# --------------------------------------------------------------------------- B
def test_gap_is_refused_not_fitted():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "h.jsonl")
        recs = seeded(p)
        assert len(recs) == 10, len(recs)

        gaps = [(x, y) for x, y, ok in H.adjacency(recs) if not ok]
        assert len(gaps) == 1, gaps
        assert gaps[0][0]["net"] == "t9-s11352064-d2008893"
        assert gaps[0][1]["net"] == "t9-s15847040-d2653436"

        run = H.tail_run(recs)
        assert [r["net"] for r in run] == [
            "t9-s15847040-d2653436", "t9-s16146944-d2687330", "t9-s16746112-d2770965",
            "t9-s17045760-d2821985", "t9-s17345664-d2855966", "t9-s17645440-d2906849"]

        # a window inside the run is taken as asked, with no note
        win, note = H.fit_window(recs, 3)
        assert note == "", note
        assert [r["net"] for r in win] == [r["net"] for r in run[-3:]]

        # a window that would span the gap is refused and narrowed, loudly
        win, note = H.fit_window(recs, 9)
        assert "REFUSED to fit across a gap" in note, note
        assert "t9-s11352064-d2008893 -> t9-s15847040-d2653436" in note, note
        assert "narrowed to the 6 record(s)" in note, note
        assert win == run
        # and the narrowed fit never sees a record from the far side of the gap
        assert all(r["s"] >= 15847040 for r in win)
    print("B ok  a trend window that would span the gap is refused and narrowed, named")


# --------------------------------------------------------------------------- C
def test_contiguous_fit_reproduces_the_validator():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "h.jsonl")
        recs = seeded(p)

        # the validator's marginal: the last three COMPLETE real-net directories of the
        # boundary table, (33981 + 50883 + 33497) / (2000 + 3000 + 2000)
        win, note = H.fit_window(recs, 3)
        rows, games, r = H.aggregate(win)
        assert (rows, games) == (118361, 7000), (rows, games)
        assert abs(r - 16.9087) < 5e-5, r
        assert "%.4f" % r == "16.9087"

        # and the slope over the contiguous run, which is the leg o48 fires on.
        # -0.008762 rows/game per accepted net over these six: the drift the boundary
        # table alone shows. It is NOT the validator's -0.0017, which was fitted across
        # the 13-net gap and is exactly what fit_window now refuses, and it is not
        # read 6's -0.1742, which was a different nine-net window earlier in the run.
        slope = H.least_squares_slope(H.tail_run(recs))
        assert -0.2 < slope < 0.0, slope
        assert abs(slope - (-0.0087619)) < 1e-6, slope
        # 10 accepted nets forward, the o48 horizon
        r_lo = r + 10 * slope
        assert abs(r_lo - 16.82108) < 1e-4, r_lo
        assert r_lo > 11.733, r_lo      # the o48 trigger the leg is tested against
    print("C ok  marginal 16.9087 = 118361/7000 and the contiguous slope reproduce")


# --------------------------------------------------------------------------- D
def test_the_newest_directory_is_never_recorded():
    complete, newest = H.records_from_rows_table(BOUNDARY_TABLE)
    assert newest[0] == "t9-s17945216-d2940346"
    assert all(n != "t9-s17945216-d2940346" for (n, _g, _r, _p) in complete)

    per_net = {
        "random": {"games": 5000, "rows": 171000, "real_net": False},
        "t9-s100-d1": {"games": 1000, "rows": 20000, "real_net": True},
        "t9-s200-d2": {"games": 1000, "rows": 19000, "real_net": True},
        "t9-s300-d3": {"games": 300, "rows": 900, "real_net": True},
    }
    recs, newest = H.records_from_per_net(per_net, with_mtimes=False)
    assert newest == "t9-s300-d3"
    assert [r["net"] for r in recs] == ["t9-s100-d1", "t9-s200-d2"]
    assert recs[0]["prev_net"] == "random"       # the bootstrap anchors the first real net
    assert recs[1]["prev_net"] == "t9-s100-d1"
    print("D ok  the directory still being written is never recorded")


# --------------------------------------------------------------------------- E
def test_prev_net_is_merged_monotonically():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "h.jsonl")
        H.append_records(p, records_of(BOUNDARY_TABLE, "test:boundary"))
        # a LATER, more pruned observation sees the same net first and cannot name a
        # predecessor. That must not erase what the earlier observation proved.
        pruned = [H.make_record("t9-s16746112-d2770965", 3000, 51020, prev_net=None,
                                source="test:pruned")]
        H.append_records(p, pruned)
        merged = H.latest_by_net(H.read_history(p))
        assert merged["t9-s16746112-d2770965"]["prev_net"] == "t9-s16146944-d2687330"
        recs = H.ordered(H.read_history(p))
        assert all(ok for _x, _y, ok in H.adjacency(recs))
    print("E ok  a pruned later observation cannot erase a proven predecessor")


# --------------------------------------------------------------------------- F
def test_the_accepted_net_index_counts_a_gap():
    # the two nets on either side of the run's real gap, with the indices
    # <basedir>/models/ gives them (37 and 51; models/ is never pruned)
    a = H.make_record("t9-s11352064-d2008893", 3000, 50780, prev_net="x", net_index=37)
    b = H.make_record("t9-s15847040-d2653436", 2000, 33894, prev_net=None, net_index=51)
    assert not H.is_adjacent(a, b)
    msg = H.describe_gap(a, b)
    assert "accepted net 37" in msg and "accepted net 51" in msg, msg
    assert "13 accepted net(s) in between have no complete record" in msg, msg

    # an index pair one apart proves adjacency even with no prev_net at all
    c = H.make_record("t9-s16146944-d2687330", 5000, 83635, prev_net=None, net_index=52)
    d = H.make_record("t9-s16746112-d2770965", 3000, 51020, prev_net=None, net_index=53)
    assert H.is_adjacent(c, d)
    assert H.is_adjacent(b, c)      # 51 -> 52
    assert not H.is_adjacent(a, c)  # 37 -> 52

    # and the index is merged forward like prev_net: a later observation that could
    # not read models/ does not erase it
    with tempfile.TemporaryDirectory() as t:
        p = os.path.join(t, "h.jsonl")
        H.append_records(p, [b])
        H.append_records(p, [H.make_record("t9-s15847040-d2653436", 2100, 35000,
                                           net_index=None, source="pruned")])
        merged = H.latest_by_net(H.read_history(p))
        assert merged["t9-s15847040-d2653436"]["net_index"] == 51
        assert merged["t9-s15847040-d2653436"]["games"] == 2100
    print("F ok  the accepted-net index counts the gap and proves adjacency on its own")


TESTS = (test_append_is_idempotent, test_gap_is_refused_not_fitted,
         test_contiguous_fit_reproduces_the_validator,
         test_the_newest_directory_is_never_recorded,
         test_prev_net_is_merged_monotonically,
         test_the_accepted_net_index_counts_a_gap)


def main():
    for t in TESTS:
        t()
    print("test_rows_history: %d/%d passed" % (len(TESTS), len(TESTS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
