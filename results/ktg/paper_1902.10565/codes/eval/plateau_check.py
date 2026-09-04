#!/usr/bin/env python3
"""plateau_check.py -- mission ktg-train, node arxiv-1902.10565::converged_test_7x7.

THE STOPPING RULE for the 7x7 run. The human directive of 2026-09-04 is that the run
must not stop at a hard time cap but must keep training until no progress is being made,
so "done" has to be a MEASURED property of the loss curve rather than a clock reading.
This module is that measurement, and it is the only thing allowed to end the run.

THE RULE, exactly as implemented
--------------------------------
Let W = 50 000 samples (--window) and let N be the largest `nsamp` in the run's
cumulative metrics_train.json.

    window A (recent)   = rows with  N - W  <  nsamp <= N
    window B (previous) = rows with  N - 2W <  nsamp <= N - W

For each of p0loss and vloss take the arithmetic mean over each window and form the
RELATIVE IMPROVEMENT of A over B:

    rel = (mean_B - mean_A) / |mean_B|          positive = still improving

  * FLAT           when rel_p0 < 0.01 AND rel_v < 0.01   (--rel; both, not either)
  * PLATEAU        when FLAT held on two CONSECUTIVE evaluations
                   AND no gatekeeper acceptance in the last 15 cycles (--accept-cycles)
  * DIVERGING      when rel_p0 < -0.05 (--diverge): p0loss ROSE by more than 5 % over
                   the trailing 50 k samples. Stop and report; never retune.
  * INSUFFICIENT   when fewer than 2W samples exist, or either window holds no rows.
                   Never a stop condition -- the run keeps going.

Both halves of the PLATEAU conjunction matter and neither is redundant: the loss curve
can be flat while the gatekeeper is still accepting candidates (the net is still getting
stronger in play even when the training loss has stopped moving, because the DATA is
improving), and the gate can be quiet for a stretch while the loss is still falling.
Only when both have stopped is there no progress left to make.

The logged p0loss/vloss are exponential moving averages with decay 0.999 per batch
(python/katago/train/metrics_logging.py:10-25, about a 1000-batch memory), so they LAG
the instantaneous loss. That makes this rule CONSERVATIVE in the direction that matters:
a curve the EMA reports as flat has been flat for a while already.

STATE persists in BASEDIR across Slurm segments, so the consecutive-evaluation count and
the last-acceptance cycle survive a job boundary. Cycle numbering comes from the loop's
own $BASEDIR/.cycles_completed, which is likewise cumulative across segments.

usage:
  plateau_check.py BASEDIR --log FILE --state FILE [--job ID] [--window 50000]
                   [--rel 0.01] [--accept-cycles 15] [--diverge 0.05]
                   [--training-name t7] [--json FILE]

exit codes -- the driver branches on these:
   0  keep going (improving / flat-but-not-yet-plateau / insufficient data)
  10  PLATEAU    -> run the closing match, write $BASEDIR/PLATEAU, stop the chain
  20  DIVERGING  -> write $BASEDIR/ABORT, stop the chain, report as measured
   2  could not evaluate (unreadable BASEDIR); the driver treats this as non-fatal
"""

import argparse
import json
import os
import re
import sys
import time

SD_RE = re.compile(r"-s(\d+)-d(\d+)$")

EXIT_CONTINUE = 0
EXIT_PLATEAU = 10
EXIT_DIVERGING = 20
EXIT_ERROR = 2


def read_rows(path):
    rows = []
    try:
        with open(path, "r", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if "nsamp" in d:
                    rows.append(d)
    except OSError:
        pass
    rows.sort(key=lambda r: r["nsamp"])
    return rows


def mean_in(rows, key, lo, hi):
    """Mean of `key` over rows with lo < nsamp <= hi. None if the window is empty."""
    vals = [r[key] for r in rows if key in r and lo < r["nsamp"] <= hi]
    if not vals:
        return None, 0
    return sum(vals) / len(vals), len(vals)


def count_accepted(basedir):
    d = os.path.join(basedir, "models")
    if not os.path.isdir(d):
        return 0
    return sum(1 for n in os.listdir(d)
               if os.path.isfile(os.path.join(d, n, "model.bin.gz")))


def read_cycles(basedir):
    try:
        with open(os.path.join(basedir, ".cycles_completed")) as fh:
            return int(fh.read().strip() or 0)
    except (OSError, ValueError):
        return 0


def load_state(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("basedir")
    ap.add_argument("--log", required=True)
    ap.add_argument("--state", required=True)
    ap.add_argument("--job", default="?")
    ap.add_argument("--window", type=int, default=50000)
    ap.add_argument("--rel", type=float, default=0.01)
    ap.add_argument("--accept-cycles", type=int, default=15)
    ap.add_argument("--diverge", type=float, default=0.05)
    ap.add_argument("--training-name", default="t7")
    ap.add_argument("--json", default=None)
    a = ap.parse_args(argv)

    b = os.path.abspath(a.basedir)
    if not os.path.isdir(b):
        sys.stderr.write("no such BASEDIR: %s\n" % b)
        return EXIT_ERROR

    rows = read_rows(os.path.join(b, "train", a.training_name, "metrics_train.json"))
    cycles = read_cycles(b)
    accepts = count_accepted(b)
    st = load_state(a.state)

    # The acceptance clock. First run of a fresh state adopts the current counts, so the
    # 15-cycle window starts from now rather than from a history this file cannot see.
    prev_accepts = st.get("last_accept_count")
    last_accept_cycle = st.get("last_accept_cycle")
    if prev_accepts is None or last_accept_cycle is None:
        prev_accepts, last_accept_cycle = accepts, cycles
    elif accepts > prev_accepts:
        prev_accepts, last_accept_cycle = accepts, cycles
    cycles_since_accept = max(0, cycles - last_accept_cycle)

    W = a.window
    consecutive_flat = int(st.get("consecutive_flat", 0))
    rec = {
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "job": a.job,
        "cycle": cycles,
        "accepted_total": accepts,
        "cycles_since_accept": cycles_since_accept,
        "window_samples": W,
        "rel_threshold": a.rel,
        "accept_cycles_threshold": a.accept_cycles,
        "diverge_threshold": a.diverge,
        "loss_rows": len(rows),
    }

    N = rows[-1]["nsamp"] if rows else 0.0
    rec["nsamp"] = N
    verdict = "INSUFFICIENT"
    rc = EXIT_CONTINUE

    if N < 2 * W:
        rec["reason"] = "only %.0f samples; need 2*W = %d before the first evaluation" % (N, 2 * W)
    else:
        aLo, aHi = N - W, N
        bLo, bHi = N - 2 * W, N - W
        mA_p, nA = mean_in(rows, "p0loss", aLo, aHi)
        mB_p, nB = mean_in(rows, "p0loss", bLo, bHi)
        mA_v, _ = mean_in(rows, "vloss", aLo, aHi)
        mB_v, _ = mean_in(rows, "vloss", bLo, bHi)
        rec.update({
            "window_a": [aLo, aHi], "window_a_rows": nA,
            "window_b": [bLo, bHi], "window_b_rows": nB,
            "mean_p0loss_a": mA_p, "mean_p0loss_b": mB_p,
            "mean_vloss_a": mA_v, "mean_vloss_b": mB_v,
        })
        if None in (mA_p, mB_p, mA_v, mB_v) or mB_p == 0 or mB_v == 0:
            rec["reason"] = "a window held no usable rows"
        else:
            rel_p = (mB_p - mA_p) / abs(mB_p)
            rel_v = (mB_v - mA_v) / abs(mB_v)
            rec["rel_improve_p0loss"] = rel_p
            rec["rel_improve_vloss"] = rel_v
            if rel_p < -a.diverge:
                verdict = "DIVERGING"
                rc = EXIT_DIVERGING
                consecutive_flat = 0
                rec["reason"] = ("p0loss ROSE %.2f %% over the trailing %d samples "
                                 "(threshold %.1f %%)" % (-rel_p * 100.0, W, a.diverge * 100.0))
            elif rel_p < a.rel and rel_v < a.rel:
                consecutive_flat += 1
                if consecutive_flat >= 2 and cycles_since_accept >= a.accept_cycles:
                    verdict = "PLATEAU"
                    rc = EXIT_PLATEAU
                    rec["reason"] = ("both relative improvements < %.1f %% on %d consecutive "
                                     "evaluations AND no acceptance for %d cycles"
                                     % (a.rel * 100.0, consecutive_flat, cycles_since_accept))
                else:
                    verdict = "FLAT"
                    rec["reason"] = ("flat evaluation %d of 2; %d cycle(s) since the last "
                                     "acceptance, need %d"
                                     % (consecutive_flat, cycles_since_accept, a.accept_cycles))
            else:
                consecutive_flat = 0
                verdict = "IMPROVING"
                rec["reason"] = ("p0loss %+.2f %%, vloss %+.2f %% -- still improving"
                                 % (rel_p * 100.0, rel_v * 100.0))

    rec["consecutive_flat"] = consecutive_flat
    rec["verdict"] = verdict
    rec["exit"] = rc

    st.update({
        "consecutive_flat": consecutive_flat,
        "last_accept_count": prev_accepts,
        "last_accept_cycle": last_accept_cycle,
        "last_verdict": verdict,
        "last_eval_utc": rec["utc"],
        "last_nsamp": N,
        "last_cycle": cycles,
    })
    try:
        os.makedirs(os.path.dirname(os.path.abspath(a.state)) or ".", exist_ok=True)
        with open(a.state, "w") as fh:
            json.dump(st, fh, indent=1, sort_keys=True)
    except OSError as e:
        sys.stderr.write("could not write state %s: %s\n" % (a.state, e))

    def fmt(x, d=4):
        return "n/a" if x is None else ("%.*f" % (d, x))

    line = ("%s job=%s cycle=%-4s nsamp=%-9.0f rows=%-5d | A(%.0f,%.0f] p0=%s v=%s n=%s | "
            "B(%.0f,%.0f] p0=%s v=%s n=%s | dp0=%s dv=%s | accepts=%d since_accept=%d "
            "flat=%d | %s -- %s"
            % (rec["utc"], a.job, cycles, N, len(rows),
               rec.get("window_a", [0, 0])[0], rec.get("window_a", [0, 0])[1],
               fmt(rec.get("mean_p0loss_a")), fmt(rec.get("mean_vloss_a")),
               rec.get("window_a_rows", 0),
               rec.get("window_b", [0, 0])[0], rec.get("window_b", [0, 0])[1],
               fmt(rec.get("mean_p0loss_b")), fmt(rec.get("mean_vloss_b")),
               rec.get("window_b_rows", 0),
               ("%+.3f%%" % (rec["rel_improve_p0loss"] * 100.0)) if "rel_improve_p0loss" in rec else "n/a",
               ("%+.3f%%" % (rec["rel_improve_vloss"] * 100.0)) if "rel_improve_vloss" in rec else "n/a",
               accepts, cycles_since_accept, consecutive_flat,
               verdict, rec.get("reason", "")))
    try:
        os.makedirs(os.path.dirname(os.path.abspath(a.log)) or ".", exist_ok=True)
        with open(a.log, "a") as fh:
            fh.write(line + "\n")
    except OSError as e:
        sys.stderr.write("could not append to %s: %s\n" % (a.log, e))
    print(line)

    if a.json:
        try:
            with open(a.json, "w") as fh:
                json.dump(rec, fh, indent=1, sort_keys=True)
        except OSError:
            pass
    return rc


if __name__ == "__main__":
    sys.exit(main())
