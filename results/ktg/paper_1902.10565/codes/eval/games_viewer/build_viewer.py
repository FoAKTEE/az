#!/usr/bin/env python3
"""Build a ready-to-publish game viewer page from a training run, in one command.

    python3 build_viewer.py --preset p1              # the whole 9x9 chain so far
    python3 build_viewer.py --preset p1 --link 1     # only link 1, its own page
    python3 build_viewer.py --preset p1 --cycle-range 1-50
    python3 build_viewer.py --preset p1 --all-links-index
    python3 build_viewer.py --preset t7              # the finished 7x7 run

A whole-chain page grows with the run and will eventually be too large to publish, so a
build stops rather than write a page above --max-mib (15 MiB by default); --link and
--cycle-range then cut the run into pages that each stay publishable.

It runs the extractor over a fresh snapshot, generates the self-test fixture, and pastes
both plus the optional gatekeeper analysis into viewer.html, writing a single self-
contained page.  Re-running it simply takes a newer snapshot, so it is the command to
repeat at every monitoring read while a chain is live.

Add --test to also run the full A-D test suite against the new bundle.
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import extract_games as EX  # noqa: E402

SCRATCH = "/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train"
RUNTIME = os.path.join(SCRATCH, "runtime", "games_viewer")

PRESETS = {
    "p1": {
        "run": os.path.join(SCRATCH, "runs", "p1"),
        "out": os.path.join(RUNTIME, "p1"),
        "page": os.path.join(RUNTIME, "viewer_built_9x9.html"),
        "index": os.path.join(RUNTIME, "viewer_9x9_links.html"),
        "title": "Nine-by-Nine Games",
        "label": "9×9 production chain · link {link} · job {job}",
        "loop_log": os.path.join(SCRATCH, "logs", "loop-301099.log"),
        "loop_logs": os.path.join(SCRATCH, "logs", "loop-*.log"),
        "board": "9×9",
        "target_mib": 6.0,
    },
    "t7": {
        "run": os.path.join(SCRATCH, "runs", "t7"),
        "out": os.path.join(RUNTIME, "t7"),
        "page": os.path.join(RUNTIME, "viewer_built_7x7.html"),
        "title": "Seven-by-Seven Games",
        "label": "7×7 converged run · job 301096 · finished",
        "loop_log": None,
        "loop_logs": None,
        "index": None,
        "board": "7×7",
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


INDEX_PAGE = """<title>%(title)s</title>
<style>
:root { color-scheme: light; --bg:#E8ECF0; --panel:#FDFEFF; --ink:#141D25; --muted:#64757F;
        --line:#CDD7DE; --accent:#1C6C86; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { color-scheme: dark;
  --bg:#0D1218; --panel:#161F27; --ink:#E3EAF0; --muted:#8598A5; --line:#2A3742; --accent:#4FA6C4; } }
:root[data-theme="dark"] { color-scheme: dark; --bg:#0D1218; --panel:#161F27; --ink:#E3EAF0;
  --muted:#8598A5; --line:#2A3742; --accent:#4FA6C4; }
body { margin:0; background:var(--bg); color:var(--ink); font:14px/1.5 "IBM Plex Sans",
       system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; }
.wrap { max-width: 720px; margin: 0 auto; padding: 40px 24px 60px; }
h1 { font-family: "IBM Plex Serif", Georgia, serif; font-size: 24px; margin: 0 0 4px; }
.sub { color: var(--muted); font-family: "IBM Plex Mono", ui-monospace, monospace;
       font-size: 12px; margin-bottom: 28px; }
table { width:100%%; border-collapse: collapse; background: var(--panel);
        border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
th, td { text-align: left; padding: 9px 14px; border-bottom: 1px solid var(--line); }
th { font-size: 10px; letter-spacing: .09em; text-transform: uppercase; color: var(--muted); }
tr:last-child td { border-bottom: 0; }
td.n { font-family: "IBM Plex Mono", ui-monospace, monospace;
       font-variant-numeric: tabular-nums; }
.note { color: var(--muted); font-size: 12px; margin-top: 18px; }
</style>
<div class="wrap">
<h1>%(heading)s</h1>
<div class="sub">%(sub)s</div>
<table>
<tr><th>Link</th><th>Job</th><th>Cycles</th><th>Games</th><th>Page</th></tr>
%(rows)s
</table>
<div class="note">%(note)s</div>
</div>
"""


def write_index(cfg, out_dir, index_path, page_for_link):
    """A small page listing the chain's links; it carries no game data."""
    with open(os.path.join(out_dir, "games_stats.json")) as fh:
        stats = json.load(fh)
    links = stats.get("links") or []
    by_link = stats.get("games_by_link") or {}
    rows = []
    for link in links:
        n = by_link.get(str(link["link"]), 0)
        rows.append("<tr><td class=\"n\">%d</td><td class=\"n\">%s</td>"
                    "<td class=\"n\">%d&ndash;%d</td><td class=\"n\">%s</td>"
                    "<td class=\"n\">%s</td></tr>"
                    % (link["link"], link["job"], link["first_cycle"], link["last_cycle"],
                       "{:,}".format(n), os.path.basename(page_for_link(link["link"]))))
    html = INDEX_PAGE % {
        "title": cfg["title"] + " index",
        "heading": "%s production chain" % cfg["board"],
        "sub": "snapshot %s  ·  %s games over %d link%s"
               % (stats.get("snapshot_utc"), "{:,}".format(stats.get("games", 0)),
                  len(links), "" if len(links) == 1 else "s"),
        "rows": "\n".join(rows) or "<tr><td colspan=\"5\">no links found</td></tr>",
        "note": "Each link has its own page, built with "
                "<code>build_viewer.py --preset p1 --link N</code>. "
                "Counts are games in the snapshot above, not the whole link, when a "
                "link is still running.",
    }
    with open(index_path, "w", encoding="utf-8") as fh:
        fh.write(html)
    return len(html.encode("utf-8"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--preset", choices=sorted(PRESETS), required=True)
    ap.add_argument("--link", type=int, default=None,
                    help="build only this chain link, on its own page")
    ap.add_argument("--cycle-range", default=None, metavar="A-B",
                    help="build only the games from cycles A to B, on their own page")
    ap.add_argument("--all-links-index", action="store_true",
                    help="also write a small index page listing the links")
    ap.add_argument("--max-mib", type=float, default=15.0,
                    help="refuse to write a page larger than this (default 15 MiB, "
                         "under the 16 MB the host accepts)")
    ap.add_argument("--quiet-seconds", type=int, default=120,
                    help="leave out files written this recently (default 120)")
    ap.add_argument("--cases", type=int, default=200,
                    help="games in the browser self-test fixture (default 200)")
    ap.add_argument("--test", action="store_true", help="also run the full test suite")
    args = ap.parse_args(argv)

    cfg = PRESETS[args.preset]
    if (args.link or args.cycle_range) and not cfg.get("loop_logs"):
        ap.error("--link and --cycle-range need a preset with loop logs to read cycles from")
    if args.link and args.cycle_range:
        ap.error("give either --link or --cycle-range, not both")

    label = cfg["label"]
    page = cfg["page"]
    out = cfg["out"]
    cycle_range = args.cycle_range

    if args.link:
        links = EX.read_links(cfg["loop_logs"])
        match = [l for l in links if l["link"] == args.link]
        if not match:
            raise SystemExit("link %d not found; the chain has %d link(s) so far"
                             % (args.link, len(links)))
        link = match[0]
        cycle_range = "%d-%d" % (link["first_cycle"], link["last_cycle"])
        label = ("%s production chain · link %d · job %s · cycles {cycles}"
                 % (cfg["board"], link["link"], link["job"]))
        page = page.replace(".html", "_link%d.html" % args.link)
        out = os.path.join(out, "link%d" % args.link)
    elif cycle_range:
        label = "%s production chain · cycles {cycles} · job {job}" % cfg["board"]
        page = page.replace(".html", "_cycles%s.html" % cycle_range)
        out = os.path.join(out, "cycles%s" % cycle_range)

    fixture = os.path.join(out, "selftest_fixture.json")
    games = os.path.join(out, "games.json")
    os.makedirs(out, exist_ok=True)

    extract = [sys.executable, os.path.join(HERE, "extract_games.py"),
               "--run-dir", cfg["run"], "--out-dir", out,
               "--label", label,
               "--quiet-seconds", str(args.quiet_seconds),
               "--target-mib", str(cfg["target_mib"])]
    if cfg["loop_log"]:
        extract += ["--loop-log", cfg["loop_log"]]
    if cfg.get("loop_logs"):
        extract += ["--loop-logs", cfg["loop_logs"]]
    if cycle_range:
        extract += ["--cycle-range", cycle_range]
    run(extract)

    template = os.path.join(HERE, "viewer.html")
    limit = int(args.max_mib * 1024 * 1024)
    projected = os.path.getsize(template)
    for name in ("games.json", "games_analysis.json", "selftest_fixture.json"):
        path = os.path.join(out, name)
        if os.path.exists(path):
            projected += os.path.getsize(path)
    if projected > limit:
        print("")
        print("REFUSING to build: the page would be about %.2f MiB, over the %.2f MiB "
              "ceiling." % (projected / 1048576.0, args.max_mib))
        print("The host rejects a page near 16 MB, so this would not publish. Split the")
        print("run instead:")
        print("    python3 build_viewer.py --preset %s --link N" % args.preset)
        print("    python3 build_viewer.py --preset %s --cycle-range A-B" % args.preset)
        print("    python3 build_viewer.py --preset %s --all-links-index" % args.preset)
        return 1

    test = [sys.executable, os.path.join(HERE, "test_games_viewer.py"),
            "--games", games, "--run-dir", cfg["run"], "--fixture", fixture,
            "--cross-check", str(args.cases), "--quiet-seconds", str(args.quiet_seconds)]
    run(test if args.test else test + ["--fixture-only"])

    size = inject(template, page, out, cfg["title"])
    audit(template, page, out)
    print("")
    print("page                    %s" % page)
    print("page size               %d bytes (%.2f MiB), ceiling %.2f MiB"
          % (size, size / 1048576.0, args.max_mib))
    print("title                   %s" % cfg["title"])

    if args.all_links_index and cfg.get("index"):
        def page_for_link(n):
            return cfg["page"].replace(".html", "_link%d.html" % n)
        n = write_index(cfg, out, cfg["index"], page_for_link)
        print("index page              %s (%d bytes)" % (cfg["index"], n))

    print("")
    rel = os.path.relpath(os.path.join(HERE, "build_viewer.py"))
    extra = ""
    if args.link:
        extra = " --link %d" % args.link
    elif args.cycle_range:
        extra = " --cycle-range %s" % args.cycle_range
    print("rebuild with            python3 %s --preset %s%s" % (rel, args.preset, extra))
    return 0


if __name__ == "__main__":
    sys.exit(main())
