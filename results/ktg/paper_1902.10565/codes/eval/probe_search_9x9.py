#!/usr/bin/env python3
"""probe_search_9x9.py -- mission ktg-train, task paper_code_map_search section 2.

Reads ONE recorded probe run (leg D1 of the synchronous_loop_smoke job) and computes
the three selfplay-side metrics that promote nodes selfplay_search_params,
playout_cap_randomization, root_explore_and_target_pruning, score_utility_search and
game_randomization_9x9 from `preliminary` to executed evidence:

  (a) full_frac    = #("Root visits: N" with N > cheapSearchVisits) / #("Root visits:")
                     expected 1 - cheapSearchProb = 1 - 0.75 = 0.25, the paper's p
                     (cpp/program/play.cpp:779 emits the line, :1141-1142 caps a cheap
                     turn at min(maxVisits, cheapSearchVisits) = 100)
  (b) rows_per_game = sum(npz rows over tdata) / #(.sgfs lines)
                     one SGF per line, cpp/program/selfplaymanager.cpp:377-378
  (c) sz_other     = #(.sgfs lines without "SZ[9]")

Tolerances (task paper_code_map_search section 2): (a) in [0.20, 0.30] with at least
500 searched turns, (b) in [12, 35], (c) == 0.

Standard library only (no numpy): npz shapes come from check_pos_len_npz.npz_array_meta.

usage: probe_search_9x9.py <selfplay-dir> <log-dir-or-file> [--json OUT] [--no-assert]
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


def analyse(selfplay_dir, log_target):
    logs = log_files(log_target)
    visits = root_visits(logs)
    searched = len(visits)
    full = sum(1 for v in visits if v > CHEAP_SEARCH_VISITS)
    cheap = sum(1 for v in visits if v <= CHEAP_SEARCH_VISITS)
    full_frac = (full / searched) if searched else None

    sgf_files, n_all, n9, n_rect = sgfs_lines(selfplay_dir)
    npz_files, rows = tdata_rows(selfplay_dir)
    rows_per_game = (rows / n_all) if n_all else None
    sz_other = n_all - n9

    # Job 298712 and 299259 measured full_frac ~ 0.34 against the 0.25 that
    # 1 - cheapSearchProb predicts, with and without forks. The counts alone cannot
    # say why, and the logSearchInfo log is deleted after extraction, so record the
    # full distribution of root-visit values here: a full search should log exactly
    # maxVisits and a cheap one exactly cheapSearchVisits, and any third value means
    # something else is altering the visit budget.
    hist = {}
    for v in visits:
        hist[v] = hist.get(v, 0) + 1

    return {
        "selfplay_dir": selfplay_dir,
        "log_files": logs,
        "root_visits_histogram": dict(sorted(hist.items())),
        "root_visits_distinct_values": len(hist),
        "searched_turns": searched,
        "full_search_turns": full,
        "cheap_search_turns": cheap,
        "full_frac": full_frac,
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


def verdict(r):
    checks = []

    def add(name, ok, detail):
        checks.append({"name": name, "pass": bool(ok), "detail": detail})

    add("searched_turns_sufficient", r["searched_turns"] >= MIN_SEARCHED_TURNS,
        "searched_turns=%s >= %d" % (r["searched_turns"], MIN_SEARCHED_TURNS))
    ff = r["full_frac"]
    add("a_full_frac_in_band", ff is not None and FULL_FRAC_LO <= ff <= FULL_FRAC_HI,
        "full_frac=%s band=[%s, %s]" % (ff, FULL_FRAC_LO, FULL_FRAC_HI))
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
    it = iter(argv[1:])
    for a in it:
        if a == "--json":
            json_out = next(it, None)
            if json_out in args:
                args.remove(json_out)
        elif a == "--no-assert":
            do_assert = False
    if len(args) < 2:
        print(__doc__)
        return 2

    r = analyse(args[0], args[1])
    checks = verdict(r)
    r["checks"] = checks
    r["pass"] = all(c["pass"] for c in checks)

    print("probe_search_9x9")
    print("  selfplay_dir      = %s" % r["selfplay_dir"])
    print("  log_files         = %d" % len(r["log_files"]))
    print("  searched_turns    = %d  (full %d / cheap %d)"
          % (r["searched_turns"], r["full_search_turns"], r["cheap_search_turns"]))
    print("  root_visits_range = [%s, %s]  (cfg cheap=%d max=%d)"
          % (r["min_root_visits_seen"], r["max_root_visits_seen"],
             CHEAP_SEARCH_VISITS, MAX_VISITS))
    top = sorted(r["root_visits_histogram"].items(), key=lambda kv: -kv[1])[:8]
    print("  root_visits_hist  = %s   (%d distinct values)"
          % (", ".join("%s:%d" % kv for kv in top), r["root_visits_distinct_values"]))
    print("  FULL_FRAC         = %s   expected %.2f, band [%.2f, %.2f]"
          % (("%.4f" % r["full_frac"]) if r["full_frac"] is not None else "NA",
             r["full_frac_expected"], FULL_FRAC_LO, FULL_FRAC_HI))
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
