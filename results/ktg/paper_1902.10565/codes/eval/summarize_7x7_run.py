#!/usr/bin/env python3
"""summarize_7x7_run.py -- mission ktg-train, node arxiv-1902.10565::converged_test_7x7.

Reads one converged-test BASEDIR and emits the run's summary JSON: cycles, samples,
exports, gatekeeper acceptances, the DENSE per-batch loss log, and -- when a match was
run -- the fixed-visit W/L/D and Elo of the latest accepted net against the first
exported net.

Everything is read from artefacts the loop itself wrote; this module computes nothing
that a later reader could not recompute from the same BASEDIR:

  $BASEDIR/train/<name>/metrics_train.json   one JSON object per logged batch
                                             (train.py:1350 open(...,"a"),
                                              :1694 log_metrics ->
                                              katago/train/metrics_logging.py:28).
                                             Keys are the metric names with the "_sum"
                                             suffix stripped, so the policy loss is
                                             "p0loss" (metrics_pytorch.py:893), the value
                                             loss "vloss" (:901), the total "loss" (:920),
                                             and "nsamp" is the CUMULATIVE sample count
                                             (:943) -- the x-axis of the loss curve.
  $BASEDIR/models/                           gatekeeper-ACCEPTED nets
  $BASEDIR/rejectedmodels/                   gatekeeper-REJECTED nets
  $BASEDIR/modelstobetested/                 exported, not yet gated
  $BASEDIR/gatekeepersgf/stdout.txt          "Candidate won/lost match ..." lines
  $BASEDIR/.cycles_completed                 the loop's own progress counter
  <match sgfs>/*.sgfs                        one game per LINE
                                             (cpp/program/selfplaymanager.cpp:377-378)

Standard library only, on purpose: it must run on the login node, which has neither
numpy nor torch.

usage:
  summarize_7x7_run.py BASEDIR --out FILE [options]

options:
  --board N            board length the run used (default 7); games of any other SZ[]
                       are counted separately and reported, never silently mixed
  --training-name S    subdirectory of $BASEDIR/train (default t7)
  --samples-per-epoch N   bucket width for the per-cycle loss table (default 5000)
  --match-sgfs DIR     directory of the closing match's .sgfs files
  --bot-first S        botName0 in the match config (default "first")
  --bot-latest S       botName1 in the match config (default "latest")
  --first-export NAME  the model directory name frozen as the match baseline
  --meta FILE          a JSON object merged into the summary under "allocation"
  --abort REASON       record that the cycle loop stopped on an abort rule
  --loss-rows-max N    cap on the number of dense rows embedded (default 5000; the full
                       metrics_train.json is copied into evidence alongside this file)

exit 0 always when the summary could be written; 1 if BASEDIR is unusable.
"""

import argparse
import glob
import hashlib
import json
import math
import os
import re
import sys

RE_RE = re.compile(r"RE\[([^\]]*)\]")
PB_RE = re.compile(r"PB\[([^\]]*)\]")
PW_RE = re.compile(r"PW\[([^\]]*)\]")
SZ_RE = re.compile(r"SZ\[([^\]]*)\]")
GATE_RE = re.compile(r"Candidate (won|lost) match[^\n]*")
# export directory names look like <trainingname>-s<samples>-d<datarows>
SD_RE = re.compile(r"-s(\d+)-d(\d+)$")

UNIFORM_BASELINE_NOTE = ("ln(board*board+1): the cross-entropy of a uniform policy over "
                         "the legal-move-plus-pass vector, the number a learned policy "
                         "must beat for the run to have learned anything at all")


def sha256(path):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
    except OSError:
        return None
    return h.hexdigest()


def z_for(conf):
    """Two-sided normal quantile by bisection on math.erf -- no scipy on the login node."""
    target = (1.0 + conf) / 2.0
    lo, hi = 0.0, 12.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if 0.5 * (1.0 + math.erf(mid / math.sqrt(2.0))) < target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def wilson(p_hat, n, conf=0.95):
    if n <= 0:
        return (None, None)
    z = z_for(conf)
    denom = 1.0 + z * z / n
    centre = (p_hat + z * z / (2 * n)) / denom
    half = (z * math.sqrt(max(0.0, p_hat * (1 - p_hat)) / n + z * z / (4 * n * n))) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def elo(p):
    """Standard logistic inversion: +400 * log10(p / (1 - p))."""
    if p is None:
        return None
    p = min(max(p, 1e-9), 1 - 1e-9)
    return -400.0 * math.log10(1.0 / p - 1.0)


def model_dirs(d):
    """Export directories under d, oldest-first by the -s<samples> in the name."""
    out = []
    if not os.path.isdir(d):
        return out
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        if not os.path.isdir(p):
            continue
        m = SD_RE.search(name)
        out.append({
            "name": name,
            "dir": p,
            "samples": int(m.group(1)) if m else None,
            "data_rows": int(m.group(2)) if m else None,
            "has_model_bin": os.path.isfile(os.path.join(p, "model.bin.gz")),
        })
    out.sort(key=lambda r: (r["samples"] is None, r["samples"] or 0, r["name"]))
    return out


def read_loss_rows(path):
    rows = []
    bad = 0
    try:
        with open(path, "r", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    bad += 1
    except OSError:
        pass
    return rows, bad


def slim(row):
    """The loss-curve columns, in the order a plot wants them."""
    keep = ("nsamp", "nsamp_train", "p0loss", "vloss", "loss", "smloss", "tdvloss",
            "sloss", "oloss", "evstatus", "time_since_last_print", "window_start_row",
            "wsum", "pslr")
    out = {}
    for k in keep:
        if k in row:
            v = row[k]
            out[k] = round(v, 6) if isinstance(v, float) else v
    return out


def read_gate_lines(basedir):
    out = []
    seen = set()
    pats = [os.path.join(basedir, "gatekeepersgf", "stdout.txt"),
            os.path.join(basedir, "logs", "*.txt")]
    for pat in pats:
        for p in sorted(glob.glob(pat)):
            try:
                with open(p, "r", errors="replace") as fh:
                    for line in fh:
                        m = GATE_RE.search(line)
                        if m and m.group(0) not in seen:
                            seen.add(m.group(0))
                            out.append({"file": os.path.basename(p), "line": m.group(0).strip()})
            except OSError:
                continue
    return out


def read_match(sgfs_dir, board, first_name, latest_name):
    files = sorted(set(
        glob.glob(os.path.join(sgfs_dir, "**", "*.sgfs"), recursive=True)
        + glob.glob(os.path.join(sgfs_dir, "**", "*.sgf"), recursive=True)))
    r = {"sgfs_dir": sgfs_dir, "files": len(files), "games": 0,
         "sz_board": 0, "sz_other": 0,
         "latest_wins": 0, "first_wins": 0, "draws": 0, "unscored": 0,
         "latest_as_black": 0, "latest_as_white": 0,
         "bots_seen": {}, "unknown_results": {}}
    want_sz = str(board)
    for f in files:
        try:
            with open(f, "r", errors="replace") as fh:
                for line in fh:
                    if not line.strip():
                        continue
                    r["games"] += 1
                    m = SZ_RE.search(line)
                    if m and m.group(1) == want_sz:
                        r["sz_board"] += 1
                    else:
                        r["sz_other"] += 1
                    mb, mw = PB_RE.search(line), PW_RE.search(line)
                    pb = mb.group(1) if mb else ""
                    pw = mw.group(1) if mw else ""
                    for n in (pb, pw):
                        r["bots_seen"][n] = r["bots_seen"].get(n, 0) + 1
                    if pb == latest_name:
                        r["latest_as_black"] += 1
                    elif pw == latest_name:
                        r["latest_as_white"] += 1
                    mr = RE_RE.search(line)
                    res = mr.group(1) if mr else ""
                    if res.startswith("B+"):
                        winner = pb
                    elif res.startswith("W+"):
                        winner = pw
                    elif res in ("0", "Draw", "draw"):
                        r["draws"] += 1
                        continue
                    else:
                        r["unscored"] += 1
                        r["unknown_results"][res] = r["unknown_results"].get(res, 0) + 1
                        continue
                    if winner == latest_name:
                        r["latest_wins"] += 1
                    elif winner == first_name:
                        r["first_wins"] += 1
                    else:
                        r["unscored"] += 1
        except OSError:
            continue
    decided = r["latest_wins"] + r["first_wins"] + r["draws"]
    if decided > 0:
        p = (r["latest_wins"] + 0.5 * r["draws"]) / decided
        lo, hi = wilson(p, decided, 0.95)
        r["decided_games"] = decided
        r["score_latest"] = round(p, 6)
        r["score_ci95"] = [round(lo, 6), round(hi, 6)]
        r["elo_latest_minus_first"] = round(elo(p), 2)
        r["elo_ci95"] = [round(elo(lo), 2), round(elo(hi), 2)]
        r["positive_score"] = bool(lo > 0.5)
    else:
        r["decided_games"] = 0
        r["score_latest"] = None
        r["positive_score"] = False
    return r


def read_int_file(path, default=0):
    try:
        with open(path) as fh:
            return int(fh.read().strip() or default)
    except (OSError, ValueError):
        return default


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("basedir")
    ap.add_argument("--out", required=True)
    ap.add_argument("--board", type=int, default=7)
    ap.add_argument("--training-name", default="t7")
    ap.add_argument("--samples-per-epoch", type=int, default=5000)
    ap.add_argument("--match-sgfs", default=None)
    ap.add_argument("--bot-first", default="first")
    ap.add_argument("--bot-latest", default="latest")
    ap.add_argument("--first-export", default=None)
    ap.add_argument("--meta", default=None)
    ap.add_argument("--abort", default=None)
    ap.add_argument("--loss-rows-max", type=int, default=5000)
    args = ap.parse_args(argv)

    b = os.path.abspath(args.basedir)
    if not os.path.isdir(b):
        sys.stderr.write("no such BASEDIR: %s\n" % b)
        return 1

    traindir = os.path.join(b, "train", args.training_name)
    metrics_path = os.path.join(traindir, "metrics_train.json")
    rows, bad_rows = read_loss_rows(metrics_path)
    E = max(1, args.samples_per_epoch)

    # per-cycle table: the LAST logged row inside each E-wide nsamp bucket. The buckets
    # are the trainer's own epochs (one epoch == one cycle, -max-epochs-this-instance 1).
    per_cycle = {}
    for r in rows:
        n = r.get("nsamp")
        if n is None:
            continue
        k = int((float(n) - 1e-9) // E) + 1
        per_cycle[k] = slim(r)
    per_cycle_list = [dict(cycle=k, **per_cycle[k]) for k in sorted(per_cycle)]

    accepted = model_dirs(os.path.join(b, "models"))
    rejected = model_dirs(os.path.join(b, "rejectedmodels"))
    pending = model_dirs(os.path.join(b, "modelstobetested"))
    exported = sorted(accepted + rejected + pending,
                      key=lambda r: (r["samples"] is None, r["samples"] or 0, r["name"]))

    first_p0 = next((r.get("p0loss") for r in (slim(x) for x in rows) if "p0loss" in r), None)
    last_row = slim(rows[-1]) if rows else {}
    min_p0 = min((r["p0loss"] for r in (slim(x) for x in rows) if "p0loss" in r), default=None)
    min_v = min((r["vloss"] for r in (slim(x) for x in rows) if "vloss" in r), default=None)
    uniform = math.log(args.board * args.board + 1)

    summary = {
        "node_id": "arxiv-1902.10565::converged_test_7x7",
        "task_id": "converged_test_7x7",
        "basedir": b,
        "board": args.board,
        "training_name": args.training_name,
        "samples_per_epoch": E,
        "cycles_completed": read_int_file(os.path.join(b, ".cycles_completed"), 0),
        "loss_log": {
            "path": metrics_path,
            "rows": len(rows),
            "unparsable_rows": bad_rows,
            "sha256": sha256(metrics_path),
            "first": slim(rows[0]) if rows else None,
            "last": last_row,
            "min_p0loss": min_p0,
            "min_vloss": min_v,
            "first_p0loss": first_p0,
        },
        "criteria": {
            "uniform_policy_baseline": round(uniform, 6),
            "uniform_policy_baseline_note": UNIFORM_BASELINE_NOTE,
            "policy_target": 2.5,
            "policy_below_target": (min_p0 is not None and min_p0 < 2.5),
            "policy_below_uniform": (min_p0 is not None and min_p0 < uniform),
            "value_loss_fell": (
                min_v is not None and rows and "vloss" in slim(rows[0])
                and min_v < slim(rows[0])["vloss"]),
            "acceptances_target": 2,
            "acceptances": len(accepted),
            "acceptances_met": len(accepted) >= 2,
        },
        "samples_total": last_row.get("nsamp"),
        "exports": exported,
        "export_count": len(exported),
        "accepted": accepted,
        "rejected": rejected,
        "pending_gate": pending,
        "gate_lines": read_gate_lines(b),
        "per_cycle_losses": per_cycle_list,
        "loss_rows": [slim(r) for r in rows[:args.loss_rows_max]],
        "loss_rows_truncated": len(rows) > args.loss_rows_max,
        "first_export_frozen": args.first_export,
        "abort": args.abort,
    }

    if args.meta and os.path.isfile(args.meta):
        try:
            summary["allocation"] = json.load(open(args.meta))
        except ValueError:
            summary["allocation"] = {"error": "unparsable meta file %s" % args.meta}

    if args.match_sgfs and os.path.isdir(args.match_sgfs):
        summary["match"] = read_match(args.match_sgfs, args.board,
                                      args.bot_first, args.bot_latest)
    else:
        summary["match"] = None

    c = summary["criteria"]
    m = summary["match"] or {}
    summary["converged"] = bool(
        c["policy_below_target"] and c["value_loss_fell"] and c["acceptances_met"]
        and m.get("positive_score"))

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    with open(args.out, "w") as fh:
        json.dump(summary, fh, indent=1, sort_keys=True)

    print("summarize_7x7_run -> %s" % args.out)
    print("  cycles=%s  loss_rows=%s  samples=%s"
          % (summary["cycles_completed"], len(rows), summary["samples_total"]))
    print("  exports=%d  accepted=%d  rejected=%d  pending=%d"
          % (len(exported), len(accepted), len(rejected), len(pending)))
    print("  p0loss first=%s min=%s last=%s   (uniform baseline %.4f, target < 2.5)"
          % (first_p0, min_p0, last_row.get("p0loss"), uniform))
    print("  vloss  min=%s last=%s" % (min_v, last_row.get("vloss")))
    if summary["match"]:
        mm = summary["match"]
        print("  match  latest %d - %d first, %d draws over %d decided; score=%s Elo=%s"
              % (mm["latest_wins"], mm["first_wins"], mm["draws"], mm["decided_games"],
                 mm["score_latest"], mm.get("elo_latest_minus_first")))
        print("         colours: latest as black %d / as white %d; SZ[%d] %d, other %d"
              % (mm["latest_as_black"], mm["latest_as_white"], args.board,
                 mm["sz_board"], mm["sz_other"]))
    print("  CONVERGED = %s" % summary["converged"])
    if summary["abort"]:
        print("  ABORT: %s" % summary["abort"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
