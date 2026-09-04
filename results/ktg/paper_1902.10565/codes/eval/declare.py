#!/usr/bin/env python3
"""declare.py -- mission ktg-train, node arxiv-1902.10565::eval_improvement.

P12 of tasks/production_chain_9x9:

    python3 codes/eval/declare.py $KTG_ROOT/eval --require-acceptances 1 --ci 0.95 \
                                  --target-p 0.60

    "prints `improves` iff P7 >= 1 AND P11's CI excludes 0.5, else `not demonstrated`;
     reports samples trained vs the 2 M warm-up (train.py:1074-1079), GPU-hours
     (sacct Elapsed sum), net hashes"

This is a DECLARATION, not a gate: it reports what the run demonstrated, on the
evidence the run produced, and it says "not demonstrated" -- never "worse" and never
"no improvement" -- when the evidence is absent. `eval_improvement` is only the
declaration; the scale-up call is the human's (task section 10).

INPUTS, all read-only and all standard library
  <EVALDIR>/manifest.json     the frozen first accepted net (freeze_baseline.py)
  <BASEDIR>                   taken from the manifest unless --basedir overrides:
                              models/ and rejectedmodels/ are the acceptance count and
                              the rejection list; the "Candidate (won|lost) match,
                              score ..." lines of the logs are the gate scores
  <EVALDIR>/match/**.sgfs     the P11 match games (--match-sgfs to point elsewhere).
                              One .sgfs LINE is one game; PB/PW name the bots and RE[]
                              carries the result, so W / L / D are counted without
                              sgfmill and p = (W + 0.5 D) / N
  <EVALDIR>/match_summary.txt summarize_sgfs.py's own output, echoed verbatim when it
                              exists -- this reader does not replace it, it makes the
                              same counts checkable without the training venv

THE INTERVAL
Wilson score interval at --ci (default 0.95) on p = (W + 0.5 D)/N. Wilson rather than
the normal approximation because the interval has to be honest near p = 1, where the
match may well land, and because it is defined at W = N. The declaration turns on
whether that interval EXCLUDES 0.5 -- the equal-strength null -- which is exactly the
question the gate cannot answer: at equal strength the gate's own accept rule fires
with probability about 0.53 (DESIGN section 7), which is why P11 is a separate match.
Elo is reported as -400 * log10(1/p - 1), the standard logistic inversion, and is a
restatement of p, not a second measurement.

usage:
  declare.py <EVALDIR> [--basedir DIR] [--match-sgfs DIR] [--match-summary FILE]
             [--bot-first NAME] [--bot-latest NAME] [--require-acceptances N]
             [--ci C] [--target-p P] [--sacct FILE] [--no-sacct] [--json FILE]

exit 0 when the declaration was produced (either verdict); 2 when the manifest is
missing, which is the one input without which there is nothing to declare.
"""

import argparse
import datetime
import glob
import hashlib
import json
import math
import os
import re
import subprocess
import sys

WARMUP_SAMPLES = 2000000          # train.py:1074-1079: warmup_scale reaches 1.0 at 2 M
RE_RE = re.compile(r"RE\[([^\]]*)\]")
PB_RE = re.compile(r"PB\[([^\]]*)\]")
PW_RE = re.compile(r"PW\[([^\]]*)\]")
SZ_RE = re.compile(r"SZ\[([^\]]*)\]")
GATE_RE = re.compile(r"Candidate (won|lost) match[^\n]*")


def read_json(path, default=None):
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception:
        return default


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def z_for(conf):
    """Two-sided normal quantile by bisection on math.erf -- no scipy on the login node."""
    target = (1.0 + conf) / 2.0
    lo, hi = 0.0, 12.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        cdf = 0.5 * (1.0 + math.erf(mid / math.sqrt(2.0)))
        if cdf < target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def wilson(p_hat, n, conf):
    """Wilson score interval. n is the game count; p_hat may carry half-points."""
    if n <= 0:
        return (None, None)
    z = z_for(conf)
    denom = 1.0 + z * z / n
    centre = (p_hat + z * z / (2 * n)) / denom
    half = (z * math.sqrt(p_hat * (1 - p_hat) / n + z * z / (4 * n * n))) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def elo(p):
    if p is None:
        return None
    p = min(max(p, 1e-9), 1 - 1e-9)
    return -400.0 * math.log10(1.0 / p - 1.0)


def read_match(sgfs_dirs, first_name, latest_name):
    """Count one .sgfs LINE as one game (cpp/program/selfplaymanager.cpp:377-378)."""
    files = []
    for d in sgfs_dirs:
        if os.path.isfile(d):
            files.append(d)
        else:
            files += sorted(glob.glob(os.path.join(d, "**", "*.sgfs"), recursive=True))
            files += sorted(glob.glob(os.path.join(d, "**", "*.sgf"), recursive=True))
    files = sorted(set(files))
    r = {"files": len(files), "games": 0, "sz9": 0, "sz_other": 0,
         "latest_wins": 0, "first_wins": 0, "draws": 0, "unscored": 0,
         "latest_as_black": 0, "latest_as_white": 0,
         "bots_seen": {}, "unknown_results": {}}
    for f in files:
        try:
            with open(f, "r", errors="replace") as fh:
                for line in fh:
                    if not line.strip():
                        continue
                    r["games"] += 1
                    m = SZ_RE.search(line)
                    if m and m.group(1) == "9":
                        r["sz9"] += 1
                    else:
                        r["sz_other"] += 1
                    pb = (PB_RE.search(line) or [None, ""])
                    pw = (PW_RE.search(line) or [None, ""])
                    pb = pb.group(1) if hasattr(pb, "group") else ""
                    pw = pw.group(1) if hasattr(pw, "group") else ""
                    for name in (pb, pw):
                        r["bots_seen"][name] = r["bots_seen"].get(name, 0) + 1
                    res = RE_RE.search(line)
                    res = res.group(1) if res else ""
                    if pb == latest_name:
                        r["latest_as_black"] += 1
                    elif pw == latest_name:
                        r["latest_as_white"] += 1
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
    return r


def gate_lines(basedir):
    out = []
    pats = [os.path.join(basedir, "gatekeepersgf", "stdout.txt"),
            os.path.join(basedir, "logs", "*.txt")]
    root = os.path.dirname(os.path.dirname(basedir))
    pats.append(os.path.join(root, "logs", "loop-*.log"))
    seen = set()
    for pat in pats:
        for p in sorted(glob.glob(pat)):
            try:
                with open(p, "r", errors="replace") as fh:
                    for line in fh:
                        m = GATE_RE.search(line)
                        if m and m.group(0) not in seen:
                            seen.add(m.group(0))
                            out.append({"file": p, "line": m.group(0)})
            except OSError:
                continue
    return out


def gpu_hours(sacct_file, no_sacct):
    """Sum of Elapsed over the chain's and the match's jobs (one GPU each, so GPU-h == wall-h)."""
    txt = None
    if sacct_file and os.path.exists(sacct_file):
        with open(sacct_file, "r", errors="replace") as fh:
            txt = fh.read()
        src = sacct_file
    elif not no_sacct:
        try:
            txt = subprocess.check_output(
                ["sacct", "-n", "-P", "-X", "-S", "now-30days",
                 "--name=ktg-loop,ktg-match",
                 "-o", "JobID,JobName,State,Elapsed,AllocTRES"],
                stderr=subprocess.DEVNULL).decode("utf-8", "replace")
            src = "sacct -X --name=ktg-loop,ktg-match"
        except Exception:
            return {"hours": None, "source": "sacct unavailable", "jobs": []}
    else:
        return {"hours": None, "source": "not queried (--no-sacct)", "jobs": []}

    total, jobs = 0.0, []
    for line in txt.splitlines():
        parts = line.split("|")
        if len(parts) < 4:
            continue
        jid, jname, state, el = parts[0], parts[1], parts[2], parts[3]
        secs = parse_elapsed(el)
        if secs is None:
            continue
        total += secs
        jobs.append({"job": jid, "name": jname, "state": state, "elapsed": el,
                     "seconds": secs,
                     "alloc": parts[4] if len(parts) > 4 else None})
    return {"hours": round(total / 3600.0, 3), "source": src, "jobs": jobs}


def parse_elapsed(s):
    """[DD-]HH:MM:SS -> seconds."""
    s = (s or "").strip()
    if not s:
        return None
    days = 0
    if "-" in s:
        d, s = s.split("-", 1)
        try:
            days = int(d)
        except ValueError:
            return None
    bits = s.split(":")
    try:
        bits = [float(b) for b in bits]
    except ValueError:
        return None
    while len(bits) < 3:
        bits.insert(0, 0.0)
    return days * 86400 + bits[0] * 3600 + bits[1] * 60 + bits[2]


def latest_accepted(basedir):
    """The newest accepted net -- the match's other side."""
    d = os.path.join(basedir, "models")
    if not os.path.isdir(d):
        return None
    best = None
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name, "model.bin.gz")
        if not os.path.exists(p):
            continue
        m = re.search(r"-s(\d+)-d(\d+)$", name)
        key = (0, int(m.group(1))) if m else (1, int(os.path.getmtime(os.path.dirname(p))))
        if best is None or key > best[0]:
            best = (key, name, p)
    return best


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("evaldir")
    ap.add_argument("--basedir", default=None)
    ap.add_argument("--match-sgfs", action="append", default=[])
    ap.add_argument("--match-summary", default=None)
    ap.add_argument("--bot-first", default="first")
    ap.add_argument("--bot-latest", default="latest")
    ap.add_argument("--require-acceptances", type=int, default=1)
    ap.add_argument("--ci", type=float, default=0.95)
    ap.add_argument("--target-p", type=float, default=0.60)
    ap.add_argument("--sacct", default=None, help="a saved sacct -P transcript to sum")
    ap.add_argument("--no-sacct", action="store_true")
    ap.add_argument("--json", default=None)
    a = ap.parse_args(argv)

    evaldir = a.evaldir.rstrip("/")
    manifest_path = os.path.join(evaldir, "manifest.json")
    manifest = read_json(manifest_path)

    print("declare -- node arxiv-1902.10565::eval_improvement (P12)")
    print("evaldir  : %s" % evaldir)
    print("manifest : %s" % manifest_path)
    if manifest is None:
        print("")
        print("MISSING INPUT: no manifest.json. Run codes/eval/freeze_baseline.py $BASEDIR")
        print("first -- the declaration is a statement ABOUT the frozen first accepted net,")
        print("so without it there is nothing to declare.")
        return 2

    basedir = a.basedir or manifest.get("basedir")
    print("basedir  : %s" % basedir)
    print("")

    # ---- acceptances and gate scores -----------------------------------------
    models = []
    if basedir and os.path.isdir(os.path.join(basedir, "models")):
        models = sorted(n for n in os.listdir(os.path.join(basedir, "models"))
                        if os.path.exists(os.path.join(basedir, "models", n, "model.bin.gz")))
    rejected = []
    if basedir and os.path.isdir(os.path.join(basedir, "rejectedmodels")):
        rejected = sorted(os.listdir(os.path.join(basedir, "rejectedmodels")))
    gl = gate_lines(basedir) if basedir else []
    acceptances = len(models)

    print("-- gatekeeper -------------------------------------------------------------")
    print("accepted (models/)        : %d" % acceptances)
    for n in models:
        print("    %s" % n)
    print("rejected (rejectedmodels/): %d" % len(rejected))
    for n in rejected:
        print("    %s" % n)
    print("gate decisions in the logs: %d" % len(gl))
    for g in gl:
        print("    %s" % g["line"])
    print("")

    # ---- nets ---------------------------------------------------------------
    first_name = manifest.get("first_model")
    first_sha = manifest.get("first_model_sha256")
    first_path = manifest.get("first_model_path")
    first_now = sha256(first_path) if first_path and os.path.exists(first_path) else None
    latest = latest_accepted(basedir) if basedir else None
    latest_name = latest[1] if latest else None
    latest_sha = sha256(latest[2]) if latest else None
    latest_meta = read_json(os.path.join(basedir, "models", latest_name, "metadata.json"), {}) \
        if latest_name else {}
    samples = (latest_meta or {}).get("global_step_samples")

    print("-- nets -------------------------------------------------------------------")
    print("frozen first   : %s" % first_name)
    print("  sha256 frozen: %s" % first_sha)
    print("  sha256 now   : %s%s" % (first_now,
          "" if (first_now is None or first_now == first_sha) else "   MISMATCH"))
    print("  frozen_at    : %s" % manifest.get("frozen_at"))
    print("latest accepted: %s" % latest_name)
    print("  sha256       : %s" % latest_sha)
    print("  samples      : %s  vs the %d-sample warm-up end (train.py:1074-1079): %s"
          % (samples, WARMUP_SAMPLES,
             ("%.3f of it" % (samples / float(WARMUP_SAMPLES))) if isinstance(samples, (int, float))
             else "unknown"))
    print("")

    # ---- match ---------------------------------------------------------------
    dirs = a.match_sgfs or [os.path.join(evaldir, "match")]
    match = read_match(dirs, a.bot_first, a.bot_latest)
    scored = match["latest_wins"] + match["first_wins"] + match["draws"]
    p = ((match["latest_wins"] + 0.5 * match["draws"]) / scored) if scored else None
    lo, hi = wilson(p, scored, a.ci) if p is not None else (None, None)

    print("-- match (P11: latest accepted vs the frozen first) ------------------------")
    print("sgfs searched  : %s" % ", ".join(dirs))
    print("files / games  : %d / %d   (SZ[9] %d, other %d)"
          % (match["files"], match["games"], match["sz9"], match["sz_other"]))
    print("bot names seen : %s" % json.dumps(match["bots_seen"], sort_keys=True))
    print("colour split   : latest as black %d, as white %d"
          % (match["latest_as_black"], match["latest_as_white"]))
    print("W / L / D      : %d / %d / %d   (unscored %d %s)"
          % (match["latest_wins"], match["first_wins"], match["draws"],
             match["unscored"], json.dumps(match["unknown_results"], sort_keys=True)))
    if p is None:
        print("p              : no scored game yet")
    else:
        print("p = (W + 0.5 D)/N = %.4f over %d scored games" % (p, scored))
        print("Wilson %.0f%% CI  : [%.4f, %.4f]   excludes 0.5: %s"
              % (a.ci * 100, lo, hi, "YES" if lo > 0.5 else "no"))
        print("Elo            : %+.1f   (CI %+.1f .. %+.1f)"
              % (elo(p), elo(lo), elo(hi)))
        print("target p       : %.2f -> %s" % (a.target_p, "met" if p >= a.target_p else "not met"))
    if a.match_summary and os.path.exists(a.match_summary):
        print("")
        print("summarize_sgfs.py output (%s), verbatim:" % a.match_summary)
        with open(a.match_summary, "r", errors="replace") as fh:
            for line in fh:
                print("    %s" % line.rstrip("\n"))
    print("")

    # ---- compute -------------------------------------------------------------
    gh = gpu_hours(a.sacct, a.no_sacct)
    print("-- compute ----------------------------------------------------------------")
    print("GPU-hours (sacct Elapsed sum, 1 GPU per job): %s   [%s]"
          % (gh["hours"], gh["source"]))
    for j in gh["jobs"]:
        print("    %-10s %-10s %-14s %s" % (j["job"], j["name"], j["state"], j["elapsed"]))
    print("")

    # ---- the declaration -----------------------------------------------------
    ci_excludes_half = (p is not None and lo is not None and lo > 0.5)
    enough_acceptances = acceptances >= a.require_acceptances
    demonstrated = enough_acceptances and ci_excludes_half

    print("-- declaration ------------------------------------------------------------")
    print("P7  acceptances >= %d           : %s (%d)"
          % (a.require_acceptances, "yes" if enough_acceptances else "no", acceptances))
    print("P11 %.0f%% CI excludes 0.5       : %s"
          % (a.ci * 100, "yes" if ci_excludes_half else
             ("no" if p is not None else "no match played")))
    print("")
    if demonstrated:
        print("eval_improvement: improves")
        print("improvement over the frozen first accepted net is DEMONSTRATED.")
    else:
        print("eval_improvement: not demonstrated")
        print("improvement over the frozen first accepted net is NOT DEMONSTRATED on this")
        print("evidence. That is a statement about the evidence, not a claim that the")
        print("latest net is no better: the missing conjunct is named above.")
    print("")
    print("The scale-up decision is the human's (task section 10); this node is only the")
    print("declaration.")

    rep = {
        "node": "arxiv-1902.10565::eval_improvement",
        "generated_at": datetime.datetime.now().astimezone().isoformat(),
        "evaldir": evaldir, "basedir": basedir,
        "manifest": manifest,
        "first_model": first_name, "first_model_sha256": first_sha,
        "first_model_sha256_now": first_now,
        "latest_model": latest_name, "latest_model_sha256": latest_sha,
        "latest_global_step_samples": samples,
        "warmup_samples": WARMUP_SAMPLES,
        "acceptances": acceptances, "accepted": models,
        "rejections": len(rejected), "rejected": rejected,
        "gate_lines": gl,
        "match": match, "match_scored_games": scored,
        "p": p, "ci_level": a.ci, "ci_low": lo, "ci_high": hi,
        "ci_excludes_half": ci_excludes_half,
        "target_p": a.target_p,
        "elo": elo(p), "elo_low": elo(lo), "elo_high": elo(hi),
        "gpu_hours": gh,
        "require_acceptances": a.require_acceptances,
        "verdict": "improves" if demonstrated else "not demonstrated",
    }
    if a.json:
        os.makedirs(os.path.dirname(os.path.abspath(a.json)), exist_ok=True)
        with open(a.json, "w") as fh:
            json.dump(rep, fh, indent=1, sort_keys=True, default=str)
        print("")
        print("wrote %s" % a.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
