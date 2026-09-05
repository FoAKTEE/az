#!/usr/bin/env python3
"""Build a ready-to-publish game viewer page from a training run, in one command.

    python3 build_viewer.py --preset p1      # the 9x9 production chain
    python3 build_viewer.py --preset t7      # the finished 7x7 run

It runs the extractor over a fresh snapshot, generates the self-test fixture, and pastes
both plus the optional gatekeeper analysis into viewer.html, writing a single self-
contained page.  Re-running it simply takes a newer snapshot, so it is the command to
repeat at every monitoring read while a chain is live.

Add --test to also run the full A-D test suite against the new bundle.
"""

import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRATCH = "/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train"
RUNTIME = os.path.join(SCRATCH, "runtime", "games_viewer")

PRESETS = {
    "p1": {
        "run": os.path.join(SCRATCH, "runs", "p1"),
        "out": os.path.join(RUNTIME, "p1"),
        "page": os.path.join(RUNTIME, "viewer_built_9x9.html"),
        "title": "Nine-by-Nine Games",
        "label": "9×9 production chain · link {link} · job {job}",
        "loop_log": os.path.join(SCRATCH, "logs", "loop-301099.log"),
        "target_mib": 6.0,
    },
    "t7": {
        "run": os.path.join(SCRATCH, "runs", "t7"),
        "out": os.path.join(RUNTIME, "t7"),
        "page": os.path.join(RUNTIME, "viewer_built_7x7.html"),
        "title": "Seven-by-Seven Games",
        "label": "7×7 converged run · job 301096 · finished",
        "loop_log": None,
        "target_mib": 4.0,
    },
}


# Sequences a script scanner may read as a comment, a template delimiter or an HTML
# entity.  The template itself carries a few, in its own source comments and the font
# URL; the injected data must add none, or a large page starts looking like markup
# rather than text.
MARKER_SEQUENCES = ["/*", "*/", "//", "{{", "}}", "${", "{%", "<!", "&#"]


def audit(template_path, page_path, out_dir):
    """Compare marker sequences in the finished page with the template's own."""
    with open(template_path, encoding="utf-8") as fh:
        template = fh.read()
    with open(page_path, encoding="utf-8") as fh:
        page = fh.read()
    data = ""
    for name in ("games.json", "games_analysis.json", "selftest_fixture.json"):
        path = os.path.join(out_dir, name)
        if os.path.exists(path):
            with open(path, encoding="utf-8") as fh:
                data += fh.read()

    print("")
    print("marker audit            %-8s %-8s %-8s" % ("data", "template", "page"))
    failures = []
    for seq in MARKER_SEQUENCES:
        d, t, g = data.count(seq), template.count(seq), page.count(seq)
        flag = ""
        if d:
            flag = "  <- injected data must carry none"
            failures.append("%r appears %d times in the injected data" % (seq, d))
        elif g > t:
            flag = "  <- page exceeds the template"
            failures.append("%r appears %d times in the page but %d in the template"
                            % (seq, g, t))
        print("  %-20s %-8d %-8d %-8d%s" % (repr(seq), d, t, g, flag))
    if failures:
        for f in failures:
            print("AUDIT FAILED: " + f)
        raise SystemExit(1)
    print("  data clean; the page carries only the template's own source markers")
    return True


def run(cmd):
    print("$ " + " ".join(("'%s'" % c if " " in c else c) for c in cmd))
    proc = subprocess.run(cmd)
    if proc.returncode != 0:
        raise SystemExit("command failed with exit %d" % proc.returncode)


def inject(template, page, out_dir, title):
    """Paste the bundle, the analysis and the fixture into the viewer template."""
    with open(template, encoding="utf-8") as fh:
        html = fh.read()
    if title:
        html = re.sub(r"<title>.*?</title>", "<title>%s</title>" % title, html, count=1)
    for token, name, required in (("__ANALYSIS__", "games_analysis.json", False),
                                  ("__SELFTEST__", "selftest_fixture.json", False),
                                  ("__GAMES__", "games.json", True)):
        path = os.path.join(out_dir, name)
        if not os.path.exists(path):
            if required:
                raise SystemExit("missing %s" % path)
            continue
        with open(path, encoding="utf-8") as fh:
            data = fh.read().strip()
        if html.count(token) != 1:
            raise SystemExit("expected exactly one %s in the template" % token)
        html = html.replace(token, data)
    with open(page, "w", encoding="utf-8") as fh:
        fh.write(html)
    return len(html.encode("utf-8"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--preset", choices=sorted(PRESETS), required=True)
    ap.add_argument("--quiet-seconds", type=int, default=120,
                    help="leave out files written this recently (default 120)")
    ap.add_argument("--cases", type=int, default=200,
                    help="games in the browser self-test fixture (default 200)")
    ap.add_argument("--test", action="store_true", help="also run the full test suite")
    args = ap.parse_args(argv)

    cfg = PRESETS[args.preset]
    page = cfg["page"]
    out = cfg["out"]
    fixture = os.path.join(out, "selftest_fixture.json")
    games = os.path.join(out, "games.json")
    os.makedirs(out, exist_ok=True)

    extract = [sys.executable, os.path.join(HERE, "extract_games.py"),
               "--run-dir", cfg["run"], "--out-dir", out,
               "--label", cfg["label"],
               "--quiet-seconds", str(args.quiet_seconds),
               "--target-mib", str(cfg["target_mib"])]
    if cfg["loop_log"]:
        extract += ["--loop-log", cfg["loop_log"]]
    run(extract)

    test = [sys.executable, os.path.join(HERE, "test_games_viewer.py"),
            "--games", games, "--run-dir", cfg["run"], "--fixture", fixture,
            "--cross-check", str(args.cases), "--quiet-seconds", str(args.quiet_seconds)]
    run(test if args.test else test + ["--fixture-only"])

    template = os.path.join(HERE, "viewer.html")
    size = inject(template, page, out, cfg["title"])
    audit(template, page, out)
    print("")
    print("page                    %s" % page)
    print("page size               %d bytes (%.2f MiB) of the 16 MB limit"
          % (size, size / 1048576.0))
    print("title                   %s" % cfg["title"])
    print("")
    print("rebuild with            python3 %s --preset %s"
          % (os.path.relpath(os.path.join(HERE, "build_viewer.py")), args.preset))
    return 0


if __name__ == "__main__":
    sys.exit(main())
