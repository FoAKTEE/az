#!/usr/bin/env python3
"""check_metrics.py -- mission ktg-train, node arxiv-1902.10565::train_stage, claim c12.

P3 of tasks/production_chain_9x9:

    python3 codes/eval/check_metrics.py $P1/train/t9/metrics_train.json --epochs 10

with the tolerance "all terms finite; p0loss at >= 200 k samples < at <= 20 k (c12)".

THREE SOURCES, in the order they become usable over the life of a run
  1. metrics_train.json   train.py:1350,1379,1661,1694 append one JSON object every
                          print_train_loss_every_batches = 100 batches. At the
                          PRODUCTION knobs (E = 20000, batch 128 -> 156 batches per
                          epoch) that is one row per epoch onwards, so this is the
                          normal source. At the SMOKE knobs (256 samples/epoch,
                          batch 32 -> 8 batches) it is never reached and the file
                          stays 0 bytes -- which is why this reader treats an empty
                          metrics file as a hard FAIL with that explanation, rather
                          than as "no problems found".
  2. audit_hooks/ckpt_*.json  the snapshots audit_smoke.py --snapshot froze out of
                          checkpoint.ckpt: running_metrics_terms /
                          running_metrics_nonfinite / global_step_samples. STDLIB,
                          no torch, and the source S6 of the smoke node used.
  3. the checkpoint itself  --ckpt PATH --allow-torch. Task section 13 forbids torch
                          on the login node and section 5 carves out exactly one
                          exception, "no torch except checkpoint metadata reads at
                          link boundaries", so this route is never taken unless it is
                          asked for by name. It caps itself to one thread.

LOSS TREND PER EXPORT
Each exported net carries the accumulator with it: metadata.json's
extra_stats {sums, weights} is the same running_metrics, so
    p0loss(export) = sums["p0loss_sum"] / weights["p0loss_sum"]
and global_step_samples orders the exports. That is the series c12 is a statement
about, and it is readable from JSON alone for every net the chain has ever exported,
including the ones the gate rejected.

usage:
  check_metrics.py <metrics_train.json> [--epochs N] [--samples-per-epoch N]
                   [--basedir DIR] [--snapshots DIR] [--ckpt PATH] [--allow-torch]
                   [--assert-c12] [--early-samples N] [--late-samples N]
                   [--allow-empty-metrics] [--json FILE]

exit 0 only if every source consulted was readable and every metric term finite (and,
with --assert-c12, only if the c12 comparison is available and holds).
"""

import argparse
import glob
import json
import math
import os
import sys

DEFAULT_SAMPLES_PER_EPOCH = 20000     # knobs_9x9.env NUM_TRAIN_SAMPLES_PER_EPOCH
C12_EARLY_SAMPLES = 20000             # "p0loss at <= 20 k"
C12_LATE_SAMPLES = 200000             # "... < p0loss at >= 200 k"
EXPORT_DIRS = ("models", "rejectedmodels", "modelstobetested", "torchmodels_toexport")


def read_json(path, default=None):
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception:
        return default


def finite(v):
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None          # not a number: not a finiteness question
    return not (math.isnan(f) or math.isinf(f))


def scan_finite(obj, prefix=""):
    """Every non-finite float in a nested dict/list, as dotted names."""
    bad = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            bad += scan_finite(v, "%s.%s" % (prefix, k) if prefix else str(k))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            bad += scan_finite(v, "%s[%d]" % (prefix, i))
    else:
        ok = finite(obj)
        if ok is False:
            bad.append("%s=%r" % (prefix, obj))
    return bad


def load_metrics_rows(path):
    """JSON-lines; returns (rows, error-or-None)."""
    if not os.path.exists(path):
        return [], "does not exist"
    if os.path.getsize(path) == 0:
        return [], ("is 0 bytes. train.py appends one row every "
                    "print_train_loss_every_batches = 100 batches (train.py:1379,1661,1694), "
                    "so a run whose epoch is shorter than 100 batches never writes one -- "
                    "the smoke's 256-sample / batch-32 epoch is 8 batches. Use the "
                    "checkpoint snapshots instead (--snapshots), which carry the same "
                    "running_metrics accumulator")
    rows, bad = [], 0
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except ValueError:
                bad += 1
    if not rows:
        return [], "holds %d line(s), none of them parseable JSON" % bad
    return rows, None


def row_samples(row):
    for k in ("nsamp", "global_step_samples", "wsum"):
        v = row.get(k)
        if isinstance(v, (int, float)):
            return float(v)
    return None


def epoch_rows(rows, epochs, spe):
    """Section 7: 'metrics_train.json rows are per 100 batches; epoch k = row nearest
    20000*k'. Returns [(k, target_samples, row_index, row)]."""
    out = []
    have = [(i, row_samples(r)) for i, r in enumerate(rows)]
    have = [(i, s) for (i, s) in have if s is not None]
    if not have:
        return out
    for k in range(1, epochs + 1):
        target = spe * k
        i, s = min(have, key=lambda pair: abs(pair[1] - target))
        out.append((k, target, i, rows[i], s))
    return out


def exports_series(basedir):
    """(global_step_samples, p0loss, name, path) per exported net, sorted by samples."""
    series, seen = [], set()
    for d in EXPORT_DIRS:
        for p in sorted(glob.glob(os.path.join(basedir, d, "*", "metadata.json"))):
            name = os.path.basename(os.path.dirname(p))
            if name in seen:
                continue
            j = read_json(p, {}) or {}
            gs = j.get("global_step_samples")
            ex = (j.get("extra_stats") or {})
            sums = ex.get("sums") or {}
            weights = ex.get("weights") or {}
            rec = {"name": name, "path": p, "global_step_samples": gs,
                   "total_num_data_rows": j.get("total_num_data_rows"),
                   "where": d, "losses": {}, "nonfinite": scan_finite(ex, "extra_stats")}
            for term in ("p0loss", "p1loss", "vloss", "loss", "pacc1", "sloss"):
                key = term + "_sum"
                if key in sums and weights.get(key):
                    try:
                        rec["losses"][term] = float(sums[key]) / float(weights[key])
                    except (TypeError, ValueError, ZeroDivisionError):
                        pass
            if gs is not None:
                seen.add(name)
                series.append(rec)
    series.sort(key=lambda r: r["global_step_samples"])
    return series


def snapshot_records(snapdir):
    out = []
    for p in sorted(glob.glob(os.path.join(snapdir, "ckpt_*.json"))):
        j = read_json(p, {})
        if j is None:
            out.append({"path": p, "error": "unreadable or not JSON"})
        else:
            j["path"] = p
            out.append(j)
    return out


def read_ckpt_with_torch(path):
    """The section-5 exception: one checkpoint's counters and running-metrics finiteness.

    Kept to one thread and to CPU on purpose -- this may run on the login node at a link
    boundary, and nothing else there may exceed two cores (task section 13).
    """
    os.environ.setdefault("OMP_NUM_THREADS", "1")
    os.environ.setdefault("MKL_NUM_THREADS", "1")
    import torch  # noqa: E402  (deliberately local: never imported unless asked for)
    try:
        torch.set_num_threads(1)
    except Exception:
        pass
    d = torch.load(path, map_location="cpu", weights_only=False)
    ts = d.get("train_state", {}) or {}
    rm = d.get("running_metrics") or {}
    rec = {
        "path": path,
        "global_step_samples": ts.get("global_step_samples"),
        "total_num_data_rows": ts.get("total_num_data_rows"),
        "train_bucket_level": ts.get("train_bucket_level"),
        "export_cycle_counter": ts.get("export_cycle_counter"),
        "running_metrics_nsamp": (rm.get("sums") or {}).get("nsamp"),
    }
    terms, nonfinite = 0, []
    for section in ("sums", "weights"):
        for k, v in (rm.get(section) or {}).items():
            ok = finite(v)
            if ok is None:
                continue
            terms += 1
            if not ok:
                nonfinite.append("%s.%s=%r" % (section, k, v))
    rec["running_metrics_terms"] = terms
    rec["running_metrics_nonfinite"] = nonfinite
    return rec


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("metrics", nargs="?", default=None,
                    help="path to metrics_train.json (typically $BASEDIR/train/<name>/)")
    ap.add_argument("--epochs", type=int, default=0,
                    help="check the rows nearest samples-per-epoch * k for k = 1..N")
    ap.add_argument("--samples-per-epoch", type=int, default=DEFAULT_SAMPLES_PER_EPOCH)
    ap.add_argument("--basedir", default=None,
                    help="BASEDIR for the export series (default: two levels above the "
                         "metrics file, i.e. $BASEDIR/train/<name>/metrics_train.json)")
    ap.add_argument("--snapshots", default=None,
                    help="directory of audit_smoke --snapshot ckpt_*.json (default "
                         "$BASEDIR/audit_hooks)")
    ap.add_argument("--ckpt", action="append", default=[],
                    help="read this checkpoint with torch (requires --allow-torch)")
    ap.add_argument("--allow-torch", action="store_true",
                    help="permit the section-5 checkpoint-metadata read at a link boundary")
    ap.add_argument("--assert-c12", action="store_true")
    ap.add_argument("--early-samples", type=int, default=C12_EARLY_SAMPLES)
    ap.add_argument("--late-samples", type=int, default=C12_LATE_SAMPLES)
    ap.add_argument("--allow-empty-metrics", action="store_true",
                    help="do not fail when metrics_train.json is empty or absent (use "
                         "when the checkpoint snapshots are the intended source)")
    ap.add_argument("--json", default=None, help="write the full report here")
    a = ap.parse_args(argv)

    if not a.metrics and not a.basedir:
        ap.error("give a metrics_train.json path, or --basedir")

    basedir = a.basedir
    if basedir is None and a.metrics:
        # $BASEDIR/train/<trainingname>/metrics_train.json
        basedir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(a.metrics))))
    snapdir = a.snapshots or (os.path.join(basedir, "audit_hooks") if basedir else None)

    rep = {"metrics_file": a.metrics, "basedir": basedir, "snapshots_dir": snapdir,
           "failures": [], "notes": []}
    fails = rep["failures"]

    print("check_metrics -- node arxiv-1902.10565::train_stage, claim c12")
    print("metrics file : %s" % a.metrics)
    print("basedir      : %s" % basedir)
    print("")

    # ---- 1. metrics_train.json ----------------------------------------------
    rows, err = ([], None)
    if a.metrics:
        rows, err = load_metrics_rows(a.metrics)
        rep["metrics_rows"] = len(rows)
        rep["metrics_error"] = err
        if err:
            msg = "metrics_train.json %s" % err
            print("METRICS: UNUSABLE -- %s" % msg)
            if not a.allow_empty_metrics:
                fails.append(msg)
        else:
            print("METRICS: %d row(s)" % len(rows))
            nonfinite = []
            for i, r in enumerate(rows):
                nonfinite += ["row %d: %s" % (i, b) for b in scan_finite(r)]
            rep["metrics_nonfinite"] = nonfinite
            if nonfinite:
                print("  NON-FINITE TERMS: %d" % len(nonfinite))
                for b in nonfinite[:20]:
                    print("    %s" % b)
                fails.append("%d non-finite term(s) in %s" % (len(nonfinite), a.metrics))
            else:
                print("  every term finite across every row")
            if a.epochs:
                sel = epoch_rows(rows, a.epochs, a.samples_per_epoch)
                rep["epoch_rows"] = [
                    {"epoch": k, "target_samples": t, "row_index": i,
                     "samples": s,
                     "p0loss": r.get("p0loss"), "vloss": r.get("vloss"),
                     "loss": r.get("loss"), "pacc1": r.get("pacc1")}
                    for (k, t, i, r, s) in sel]
                if not sel:
                    m = ("--epochs %d asked for, but no row carries a sample count "
                         "(nsamp / global_step_samples / wsum)" % a.epochs)
                    print("  %s" % m)
                    fails.append(m)
                else:
                    print("  epoch rows (epoch k = the row nearest %d * k):"
                          % a.samples_per_epoch)
                    print("    %-6s %-12s %-8s %-12s %-12s %-12s"
                          % ("epoch", "samples", "row", "p0loss", "vloss", "loss"))
                    for e in rep["epoch_rows"]:
                        print("    %-6s %-12s %-8s %-12s %-12s %-12s"
                              % (e["epoch"], e["samples"], e["row_index"],
                                 e["p0loss"], e["vloss"], e["loss"]))
                    got = len({e["row_index"] for e in rep["epoch_rows"]})
                    if got < a.epochs:
                        rep["notes"].append(
                            "only %d distinct row(s) for %d epochs -- the run has not "
                            "trained %d epochs yet" % (got, a.epochs, a.epochs))
                        print("    NOTE: %s" % rep["notes"][-1])

    # ---- 2. checkpoint snapshots (stdlib) ------------------------------------
    snaps = snapshot_records(snapdir) if snapdir and os.path.isdir(snapdir) else []
    rep["snapshots"] = snaps
    print("")
    print("RUNNING_METRICS FROM CHECKPOINT SNAPSHOTS (%s):" % (snapdir or "none"))
    if not snaps:
        print("  none found (audit_smoke.py <BASEDIR> --snapshot <label> writes them)")
    for s in snaps:
        if s.get("error"):
            print("  %s: %s" % (s["path"], s["error"]))
            fails.append("%s: %s" % (s["path"], s["error"]))
            continue
        nf = s.get("running_metrics_nonfinite")
        print("  %-14s gss=%-10s rows=%-10s terms=%-6s nonfinite=%s"
              % (s.get("label", os.path.basename(s["path"])),
                 s.get("global_step_samples"), s.get("total_num_data_rows"),
                 s.get("running_metrics_terms"), (nf if nf else "0")))
        if nf:
            fails.append("non-finite running_metrics in %s: %s" % (s["path"], nf))
        elif s.get("running_metrics_terms") in (None, 0):
            rep["notes"].append("%s carries no running_metrics terms" % s["path"])

    # ---- 3. the checkpoint itself (torch, opt-in) ----------------------------
    if a.ckpt:
        if not a.allow_torch:
            m = ("--ckpt given without --allow-torch: task section 13 forbids torch on "
                 "the login node and section 5 permits it only for a checkpoint-metadata "
                 "read at a link boundary, so this reader will not import it implicitly")
            print("")
            print("CHECKPOINT: REFUSED -- %s" % m)
            fails.append(m)
        else:
            print("")
            print("RUNNING_METRICS FROM THE CHECKPOINT (torch, 1 thread):")
            rep["checkpoints"] = []
            for p in a.ckpt:
                try:
                    rec = read_ckpt_with_torch(p)
                except Exception as exc:            # noqa: BLE001 -- reported, not raised
                    print("  %s: unreadable (%s)" % (p, exc))
                    fails.append("%s: unreadable (%s)" % (p, exc))
                    continue
                rep["checkpoints"].append(rec)
                nf = rec["running_metrics_nonfinite"]
                print("  %-40s gss=%-10s terms=%-6s nonfinite=%s"
                      % (os.path.basename(p), rec["global_step_samples"],
                         rec["running_metrics_terms"], (nf if nf else "0")))
                if nf:
                    fails.append("non-finite running_metrics in %s: %s" % (p, nf))

    # ---- 4. loss trend per export -------------------------------------------
    series = exports_series(basedir) if basedir else []
    rep["exports"] = series
    print("")
    print("LOSS TREND PER EXPORT (metadata.json extra_stats: <term>_sum / weights):")
    if not series:
        print("  no exported net carries a global_step_samples yet")
    else:
        print("  %-22s %-8s %-12s %-12s %-12s %-12s %-10s"
              % ("net", "where", "samples", "p0loss", "vloss", "loss", "pacc1"))
        for r in series:
            L = r["losses"]
            print("  %-22s %-8s %-12s %-12s %-12s %-12s %-10s"
                  % (r["name"], r["where"], r["global_step_samples"],
                     _f(L.get("p0loss")), _f(L.get("vloss")),
                     _f(L.get("loss")), _f(L.get("pacc1"))))
            if r["nonfinite"]:
                fails.append("non-finite extra_stats in %s: %s" % (r["path"], r["nonfinite"]))

    # ---- c12 -----------------------------------------------------------------
    early = [r for r in series
             if r["global_step_samples"] is not None
             and r["global_step_samples"] <= a.early_samples and "p0loss" in r["losses"]]
    late = [r for r in series
            if r["global_step_samples"] is not None
            and r["global_step_samples"] >= a.late_samples and "p0loss" in r["losses"]]
    c12 = {"early_samples": a.early_samples, "late_samples": a.late_samples,
           "early": None, "late": None, "verdict": "unavailable"}
    print("")
    if early and late:
        e = min(early, key=lambda r: r["global_step_samples"])
        l = max(late, key=lambda r: r["global_step_samples"])
        c12["early"] = {"net": e["name"], "samples": e["global_step_samples"],
                        "p0loss": e["losses"]["p0loss"]}
        c12["late"] = {"net": l["name"], "samples": l["global_step_samples"],
                       "p0loss": l["losses"]["p0loss"]}
        holds = l["losses"]["p0loss"] < e["losses"]["p0loss"]
        c12["verdict"] = "holds" if holds else "violated"
        print("c12: p0loss %.6f at %s samples (%s)  vs  %.6f at %s samples (%s)  ->  %s"
              % (l["losses"]["p0loss"], l["global_step_samples"], l["name"],
                 e["losses"]["p0loss"], e["global_step_samples"], e["name"],
                 c12["verdict"].upper()))
        if a.assert_c12 and not holds:
            fails.append("c12 violated: p0loss at >= %d samples (%.6f) is not below "
                         "p0loss at <= %d samples (%.6f)"
                         % (a.late_samples, l["losses"]["p0loss"],
                            a.early_samples, e["losses"]["p0loss"]))
    else:
        print("c12: UNAVAILABLE -- need an export at <= %d samples (%d found) and one at "
              ">= %d samples (%d found); the chain has not trained that far"
              % (a.early_samples, len(early), a.late_samples, len(late)))
        if a.assert_c12:
            fails.append("--assert-c12 but the comparison is unavailable (early=%d, late=%d)"
                         % (len(early), len(late)))
    rep["c12"] = c12

    if a.json:
        os.makedirs(os.path.dirname(os.path.abspath(a.json)), exist_ok=True)
        with open(a.json, "w") as fh:
            json.dump(rep, fh, indent=1, sort_keys=True, default=str)
        print("")
        print("wrote %s" % a.json)

    print("")
    if fails:
        print("CHECK_METRICS: FAIL")
        for f in fails:
            print("  - %s" % f)
        return 1
    print("CHECK_METRICS: PASS")
    return 0


def _f(v):
    return "%.6f" % v if isinstance(v, float) else ("-" if v is None else str(v))


if __name__ == "__main__":
    sys.exit(main())
