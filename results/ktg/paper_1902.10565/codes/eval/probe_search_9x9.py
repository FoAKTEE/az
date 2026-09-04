#!/usr/bin/env python3
"""probe_search_9x9.py -- mission ktg-train, task paper_code_map_search section 2.

Reads ONE recorded probe run (leg D1 of the synchronous_loop_smoke job) and computes
the three selfplay-side metrics that promote nodes selfplay_search_params,
playout_cap_randomization, root_explore_and_target_pruning, score_utility_search and
game_randomization_9x9 from `preliminary` to executed evidence:

  (a) full_frac    = #("Root visits: N" with N == maxVisits) / #("Root visits:")
                     expected 1 - cheapSearchProb = 1 - 0.75 = 0.25, the paper's p
                     (cpp/program/play.cpp:779 emits the line, :1141-1142 caps a cheap
                     turn at min(maxVisits, cheapSearchVisits) = 100)

      THE RULE IS `== maxVisits`, NOT `> cheapSearchVisits` (obligation o38). Selfplay
      clears the search tree before a FULL search (play.cpp:1567 asserts
      clearBotBeforeSearch for forSelfPlay, :1234 clears) but NOT before a cheap one when
      cheapSearchTargetWeight <= 0 (play.cpp:1147), and search.cpp:509,579-580 count the
      INHERITED root visits toward maxVisits. A cheap search that inherits a subtree
      already holding >= cheapSearchVisits visits therefore does no new playout and logs
      the inherited count -- a value strictly between 100 and 600. On the fork-free 60-game
      run of job 299259 there are 667 such values out of 7401, and binning them as full
      turned a 0.2516 measurement into a 0.3417 false refutation of the [0.20, 0.30] band.
      A full search always logs exactly maxVisits, so equality is the discriminator; the
      between-count is reported separately and the old rule is kept only as
      `legacy_full_frac_gt_cheap`, never as the verdict.
  (b) rows_per_game = sum(npz rows over tdata) / #(.sgfs lines)
                     one SGF per line, cpp/program/selfplaymanager.cpp:377-378
  (c) sz_other     = #(.sgfs lines without "SZ[9]")

Tolerances (task paper_code_map_search section 2): (a) in [0.20, 0.30] with at least
500 searched turns, (b) in [12, 35], (c) == 0.

Standard library only (no numpy): npz shapes come from check_pos_len_npz.npz_array_meta.

usage: probe_search_9x9.py <selfplay-dir> <log-dir-or-file> [--json OUT] [--no-assert]
                           [--sgf-v] [--visits-from log|sgf]
"""

import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_pos_len_npz import npz_array_meta, num_rows  # noqa: E402

CHEAP_SEARCH_VISITS = 100          # codes/cfg/selfplay_9x9.cfg:73
CHEAP_SEARCH_PROB = 0.75           # codes/cfg/selfplay_9x9.cfg:72
MAX_VISITS = 600                   # codes/cfg/selfplay_9x9.cfg:127
FULL_FRAC_LO, FULL_FRAC_HI = 0.20, 0.30
ROWS_PER_GAME_LO, ROWS_PER_GAME_HI = 12, 35
MIN_SEARCHED_TURNS = 500

ROOT_VISITS_RE = re.compile(r"^Root visits:\s*(\d+)\s*$")
# the per-move annotation KataGo writes into each sgf comment: "... v=600 weight=..."
SGF_V_RE = re.compile(r"\bv=(\d+)")
FULL_FRAC_RULE = "root_visits == maxVisits"


def sha256(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sgf_visit_values(selfplay_dir):
    """Second, independent instrument: the v= field of every sgf move comment."""
    vals = []
    files = sorted(glob.glob(os.path.join(selfplay_dir, "*", "sgfs", "*.sgfs")))
    for f in files:
        with open(f, "r", errors="replace") as fh:
            for line in fh:
                if line.strip():
                    vals.extend(int(m) for m in SGF_V_RE.findall(line))
    return files, vals


def bin_visits(visits):
    """The o38 binning: full == maxVisits, cheap == cheapSearchVisits, rest is between."""
    full = sum(1 for v in visits if v == MAX_VISITS)
    cheap = sum(1 for v in visits if v == CHEAP_SEARCH_VISITS)
    between = sum(1 for v in visits if CHEAP_SEARCH_VISITS < v < MAX_VISITS)
    outside = len(visits) - full - cheap - between
    legacy = sum(1 for v in visits if v > CHEAP_SEARCH_VISITS)
    hist = {}
    for v in visits:
        hist[v] = hist.get(v, 0) + 1
    return dict(searched_turns=len(visits), full=full, cheap=cheap, between=between,
                outside=outside, legacy_full=legacy,
                histogram=dict(sorted(hist.items())), distinct_values=len(hist))


def log_files(target):
    if os.path.isfile(target):
        return [target]
    out = []
    for root, _dirs, names in os.walk(target):
        for n in sorted(names):
            if n.endswith((".log", ".txt")):
                out.append(os.path.join(root, n))
    return sorted(out)


def root_visits(paths):
    vals = []
    for p in paths:
        with open(p, "r", errors="replace") as fh:
            for line in fh:
                m = ROOT_VISITS_RE.match(line.strip())
                if m:
                    vals.append(int(m.group(1)))
    return vals


def sgfs_lines(selfplay_dir):
    n_all = n9 = n_rect = 0
    files = sorted(glob.glob(os.path.join(selfplay_dir, "*", "sgfs", "*.sgfs")))
    for f in files:
        with open(f, "r", errors="replace") as fh:
            for line in fh:
                if not line.strip():
                    continue
                n_all += 1
                if "SZ[9]" in line:
                    n9 += 1
                if re.search(r"SZ\[\d+:\d+\]", line):
                    n_rect += 1
    return files, n_all, n9, n_rect


def tdata_rows(selfplay_dir):
    files = sorted(glob.glob(os.path.join(selfplay_dir, "*", "tdata", "*.npz")))
    rows = 0
    for f in files:
        rows += num_rows(npz_array_meta(f))
    return files, rows


def analyse(selfplay_dir, log_target, with_sgf_v=False, visits_from="log"):
    logs = log_files(log_target)
    if visits_from == "sgf":
        # For a run whose engine log did not survive (the loop's own random-net games:
        # the probe script's rm -rf took the capture, the sgfs stayed). The v= field is
        # the same number the log line carries -- proved by the two instruments agreeing
        # move for move on the run whose log DID survive.
        _f, visits = sgf_visit_values(selfplay_dir)
        with_sgf_v = False
    else:
        visits = root_visits(logs)
    b = bin_visits(visits)
    searched = b["searched_turns"]
    full_frac = (b["full"] / searched) if searched else None

    sgf_files, n_all, n9, n_rect = sgfs_lines(selfplay_dir)
    npz_files, rows = tdata_rows(selfplay_dir)
    rows_per_game = (rows / n_all) if n_all else None
    sz_other = n_all - n9

    out = {
        "selfplay_dir": selfplay_dir,
        "visits_from": visits_from,
        "log_files": logs,
        # o38: the source is named AND content-hashed, so a re-bin of this exact run is
        # checkable later. The script never removes the log or the sgfs it reads.
        "log_files_sha256": {f: sha256(f) for f in logs},
        "root_visits_histogram": b["histogram"],
        "root_visits_distinct_values": b["distinct_values"],
        "searched_turns": searched,
        "full_search_turns": b["full"],
        "cheap_search_turns": b["cheap"],
        "between_count": b["between"],
        "outside_band_count": b["outside"],
        "legacy_full_frac_gt_cheap": (b["legacy_full"] / searched) if searched else None,
        "full_frac": full_frac,
        "full_frac_rule": FULL_FRAC_RULE,
        "full_frac_expected": 1.0 - CHEAP_SEARCH_PROB,
        "full_frac_band": [FULL_FRAC_LO, FULL_FRAC_HI],
        "max_root_visits_seen": max(visits) if visits else None,
        "min_root_visits_seen": min(visits) if visits else None,
        "max_visits_cfg": MAX_VISITS,
        "cheap_search_visits_cfg": CHEAP_SEARCH_VISITS,
        "sgfs_files": len(sgf_files),
        "games": n_all,
        "games_sz9": n9,
        "sz_other": sz_other,
        "rectangular_games": n_rect,
        "npz_files": len(npz_files),
        "rows": rows,
        "rows_per_game": rows_per_game,
        "rows_per_game_band": [ROWS_PER_GAME_LO, ROWS_PER_GAME_HI],
    }
    if with_sgf_v:
        # The engine log and the sgfs are written by different code paths, so agreeing
        # histograms are an instrument check, not a tautology.
        sgf_v_files, sgf_vals = sgf_visit_values(selfplay_dir)
        sb = bin_visits(sgf_vals)
        out["sgf_v"] = {
            "files": sgf_v_files,
            "searched_turns": sb["searched_turns"],
            "full_search_turns": sb["full"],
            "cheap_search_turns": sb["cheap"],
            "between_count": sb["between"],
            "histogram": sb["histogram"],
            "full_frac": (sb["full"] / sb["searched_turns"]) if sb["searched_turns"] else None,
        }
        out["instruments_agree"] = (sb["histogram"] == b["histogram"])
    return out


def verdict(r):
    checks = []

    def add(name, ok, detail):
        checks.append({"name": name, "pass": bool(ok), "detail": detail})

    add("searched_turns_sufficient", r["searched_turns"] >= MIN_SEARCHED_TURNS,
        "searched_turns=%s >= %d" % (r["searched_turns"], MIN_SEARCHED_TURNS))
    ff = r["full_frac"]
    add("a_full_frac_in_band", ff is not None and FULL_FRAC_LO <= ff <= FULL_FRAC_HI,
        "full_frac=%s rule='%s' band=[%s, %s]; between=%s (reused-subtree cheap searches, "
        "o38), legacy '> cheapSearchVisits' rule would give %s"
        % (ff, r["full_frac_rule"], FULL_FRAC_LO, FULL_FRAC_HI, r["between_count"],
           r["legacy_full_frac_gt_cheap"]))
    if "sgf_v" in r:
        add("a2_sgf_v_instrument_agrees", bool(r.get("instruments_agree")),
            "sgf v= histogram identical to the engine log's: %s (%s sgf annotations vs %s log lines)"
            % (r.get("instruments_agree"), r["sgf_v"]["searched_turns"], r["searched_turns"]))
    rpg = r["rows_per_game"]
    add("b_rows_per_game_in_band",
        rpg is not None and ROWS_PER_GAME_LO <= rpg <= ROWS_PER_GAME_HI,
        "rows_per_game=%s band=[%s, %s]" % (rpg, ROWS_PER_GAME_LO, ROWS_PER_GAME_HI))
    add("c_sz_other_zero", r["games"] >= 1 and r["sz_other"] == 0,
        "games=%d sz_other=%d rectangular=%d" % (r["games"], r["sz_other"], r["rectangular_games"]))
    return checks


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    json_out = None
    do_assert = True
    with_sgf_v = False
    visits_from = "log"
    it = iter(argv[1:])
    for a in it:
        if a == "--json":
            json_out = next(it, None)
            if json_out in args:
                args.remove(json_out)
        elif a == "--no-assert":
            do_assert = False
        elif a == "--sgf-v":
            with_sgf_v = True
        elif a == "--visits-from":
            visits_from = next(it, "log")
            if visits_from in args:
                args.remove(visits_from)
    if len(args) < 2:
        print(__doc__)
        return 2

    r = analyse(args[0], args[1], with_sgf_v=with_sgf_v, visits_from=visits_from)
    checks = verdict(r)
    r["checks"] = checks
    r["pass"] = all(c["pass"] for c in checks)

    print("probe_search_9x9")
    print("  selfplay_dir      = %s" % r["selfplay_dir"])
    print("  log_files         = %d   visits read from: %s"
          % (len(r["log_files"]), r["visits_from"]))
    print("  searched_turns    = %d  (full %d / cheap %d)"
          % (r["searched_turns"], r["full_search_turns"], r["cheap_search_turns"]))
    print("  root_visits_range = [%s, %s]  (cfg cheap=%d max=%d)"
          % (r["min_root_visits_seen"], r["max_root_visits_seen"],
             CHEAP_SEARCH_VISITS, MAX_VISITS))
    top = sorted(r["root_visits_histogram"].items(), key=lambda kv: -kv[1])[:8]
    print("  root_visits_hist  = %s   (%d distinct values)"
          % (", ".join("%s:%d" % kv for kv in top), r["root_visits_distinct_values"]))
    print("  between_count     = %d   (strictly between %d and %d: cheap searches on a "
          "reused subtree, play.cpp:1147 / search.cpp:509,579-580)"
          % (r["between_count"], CHEAP_SEARCH_VISITS, MAX_VISITS))
    print("  outside_band      = %d" % r["outside_band_count"])
    print("  FULL_FRAC_RULE    = %s" % r["full_frac_rule"])
    print("  FULL_FRAC         = %s   expected %.2f, band [%.2f, %.2f]"
          % (("%.4f" % r["full_frac"]) if r["full_frac"] is not None else "NA",
             r["full_frac_expected"], FULL_FRAC_LO, FULL_FRAC_HI))
    print("  legacy '> cheap'  = %s   (the defective rule, reported for comparison only)"
          % (("%.4f" % r["legacy_full_frac_gt_cheap"])
             if r["legacy_full_frac_gt_cheap"] is not None else "NA"))
    if "sgf_v" in r:
        print("  sgf v= instrument = %d annotations, full %d, cheap %d, between %d, "
              "full_frac %s; histograms identical: %s"
              % (r["sgf_v"]["searched_turns"], r["sgf_v"]["full_search_turns"],
                 r["sgf_v"]["cheap_search_turns"], r["sgf_v"]["between_count"],
                 ("%.4f" % r["sgf_v"]["full_frac"]) if r["sgf_v"]["full_frac"] is not None else "NA",
                 r.get("instruments_agree")))
    print("  games (.sgfs lines) = %d   sz9 = %d   SZ_OTHER = %d   rectangular = %d"
          % (r["games"], r["games_sz9"], r["sz_other"], r["rectangular_games"]))
    print("  rows              = %d over %d npz" % (r["rows"], r["npz_files"]))
    print("  ROWS_PER_GAME     = %s   band [%d, %d]"
          % (("%.3f" % r["rows_per_game"]) if r["rows_per_game"] is not None else "NA",
             ROWS_PER_GAME_LO, ROWS_PER_GAME_HI))
    for c in checks:
        print("  %-6s %-28s %s" % ("ok" if c["pass"] else "FAIL", c["name"], c["detail"]))
    print("PROBE_SEARCH_9X9: %s" % ("PASS" if r["pass"] else "FAIL"))

    if json_out:
        with open(json_out, "w") as fh:
            json.dump(r, fh, indent=1, sort_keys=True)
        print("  json -> %s" % json_out)

    if not do_assert:
        return 0
    return 0 if r["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
