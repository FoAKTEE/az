#!/usr/bin/env python3
"""Checks for the 7x7 game bundle, the capture rule, and the viewer's board logic.

Three tests, all runnable on a login node with the standard library only:

  A  round trip     50 random games are re-serialised from games.json and compared,
                    move for move, with the SGF lines they came from.

  B  replay         every game is replayed through the reference capture rule below.
                    Two invariants must hold at every position -- no stone count is ever
                    negative, and stones on the board plus stones captured always equals
                    stones played plus setup stones.  The final position is then scored
                    (Tromp-Taylor area, and a plain stone difference) and compared with
                    the sign of RE[] wherever RE is decisive; the agreement rate is
                    reported, not asserted, because the run scores with several rule
                    strings and games end on passes rather than on full cleanup.

  C  cross-check    the board logic inside viewer.html is lifted out of the file and run
                    on the same 200 games as this module, so the browser code and this
                    reference agree stone for stone.  The same 200 games are written to
                    selftest_fixture.json, which the viewer reads in its ?selftest mode.

  D  headless run    the viewer's whole script is executed against a small stand-in for
                    the browser, on the real bundle, and then walked from the first
                    position to the last with the same key presses a reader would use.
                    The stones it draws and the capture counters it prints are compared
                    with this module's replay at every position.

Usage::

    python3 test_games_viewer.py
    python3 test_games_viewer.py --games /path/to/games.json --node /path/to/node
"""

import argparse
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import extract_games as EX  # noqa: E402

N = 0
NP = 0
NEIGH = []
PASS = -1


def set_board_size(n):
    """Point the reference logic at an n x n board."""
    global N, NP, NEIGH
    N, NP, NEIGH = n, n * n, []
    for y in range(n):
        for x in range(n):
            a = []
            if x > 0:
                a.append(y * n + x - 1)
            if x < n - 1:
                a.append(y * n + x + 1)
            if y > 0:
                a.append((y - 1) * n + x)
            if y < n - 1:
                a.append((y + 1) * n + x)
            NEIGH.append(a)

DEFAULT_GAMES = os.path.join(EX.DEFAULT_OUT, "games.json")
NODE_CANDIDATES = [
    "node",
    "/weka/home/schmidt/ssci-haiyangw/.vscode-server/bin/"
    "7e7950df89d055b5a378379db9ee14290772148a/node",
]


# --------------------------------------------------------------- reference board logic

def sgf_to_point(s):
    if not s or s[0] == "-":
        return PASS
    x = ord(s[0]) - 97
    y = ord(s[1]) - 97
    if not (0 <= x < N and 0 <= y < N):
        return PASS
    return y * N + x


def point_name(p):
    if p == PASS:
        return "pass"
    return "ABCDEFGHJKLMNOPQRSTUVWXYZ"[p % N] + str(N - p // N)


def group_liberties(stones, p):
    """Return (liberty count, group points) for the group containing p."""
    colour = stones[p]
    seen = [False] * NP
    seen[p] = True
    stack = [p]
    group = []
    libs = 0
    while stack:
        q = stack.pop()
        group.append(q)
        for n in NEIGH[q]:
            if stones[n] == 0:
                libs += 1
            elif stones[n] == colour and not seen[n]:
                seen[n] = True
                stack.append(n)
    return libs, group


def play_stone(stones, num, p, colour, move_no):
    """Place one stone; return (stones captured from the opponent, own stones lost)."""
    opp = 2 if colour == 1 else 1
    stones[p] = colour
    num[p] = move_no
    taken = 0
    for n in NEIGH[p]:
        if stones[n] == opp:
            libs, group = group_liberties(stones, n)
            if libs == 0:
                for q in group:
                    stones[q] = 0
                    num[q] = 0
                taken += len(group)
    libs, group = group_liberties(stones, p)
    lost = 0
    if libs == 0:
        lost = len(group)
        for q in group:
            stones[q] = 0
            num[q] = 0
    return taken, lost


def replay(moves, ab="", aw="", first="B"):
    """Replay a game; return the final state and the running invariant check."""
    stones = [0] * NP
    num = [0] * NP
    placed = [0, 0, 0]      # index by colour
    setup = [0, 0, 0]
    for i in range(0, len(ab) - 1, 2):
        p = sgf_to_point(ab[i:i + 2])
        if p != PASS and stones[p] == 0:
            stones[p] = 1
            setup[1] += 1
    for i in range(0, len(aw) - 1, 2):
        p = sgf_to_point(aw[i:i + 2])
        if p != PASS and stones[p] == 0:
            stones[p] = 2
            setup[2] += 1

    cap = {1: 0, 2: 0}      # stones captured BY that colour
    lost = {1: 0, 2: 0}     # stones of that colour taken off the board
    colour = 2 if first == "W" else 1
    problems = []

    for i, p in enumerate(moves):
        if p != PASS:
            if stones[p] != 0:
                problems.append("move %d plays on an occupied point %s" % (i + 1, point_name(p)))
            placed[colour] += 1
            taken, self_lost = play_stone(stones, num, p, colour, i + 1)
            cap[colour] += taken
            lost[2 if colour == 1 else 1] += taken
            if self_lost:
                cap[2 if colour == 1 else 1] += self_lost
                lost[colour] += self_lost
        on_b = stones.count(1)
        on_w = stones.count(2)
        if on_b < 0 or on_w < 0 or cap[1] < 0 or cap[2] < 0:
            problems.append("negative count after move %d" % (i + 1))
        if on_b + lost[1] != placed[1] + setup[1]:
            problems.append("black stone budget broken after move %d: %d on board + %d lost "
                            "!= %d played + %d setup" % (i + 1, on_b, lost[1], placed[1], setup[1]))
        if on_w + lost[2] != placed[2] + setup[2]:
            problems.append("white stone budget broken after move %d: %d on board + %d lost "
                            "!= %d played + %d setup" % (i + 1, on_w, lost[2], placed[2], setup[2]))
        colour = 2 if colour == 1 else 1

    return {"stones": stones, "capB": cap[1], "capW": cap[2], "problems": problems}


def board_string(stones):
    return "".join("b" if v == 1 else ("w" if v == 2 else ".") for v in stones)


def area_score(stones):
    """Tromp-Taylor area score for Black, before komi."""
    black = stones.count(1)
    white = stones.count(2)
    seen = [False] * NP
    for start in range(NP):
        if stones[start] != 0 or seen[start]:
            continue
        stack = [start]
        seen[start] = True
        region = []
        borders = set()
        while stack:
            q = stack.pop()
            region.append(q)
            for n in NEIGH[q]:
                if stones[n] == 0:
                    if not seen[n]:
                        seen[n] = True
                        stack.append(n)
                else:
                    borders.add(stones[n])
        if borders == {1}:
            black += len(region)
        elif borders == {2}:
            white += len(region)
    return black - white


# --------------------------------------------------------------------------- helpers

def load_bundle(path):
    with open(path) as fh:
        return json.load(fh)


def moves_of(bundle, row):
    """The stored moves as two-character SGF coordinates ("--" for a pass)."""
    return EX.split_moves(row[8], bundle.get("move_encoding", "sgf2"),
                          bundle.get("board_size", 7))


def points_of(bundle, row):
    """The stored moves as board point indices (PASS for a pass)."""
    return [sgf_to_point(m) for m in moves_of(bundle, row)]


def serialise(bundle, gi, row):
    """Rebuild the SGF move sequence of one record."""
    ex = (bundle.get("extra") or {}).get(str(gi), {})
    colour = ex.get("first", "B")
    out = []
    for mv in moves_of(bundle, row):
        out.append(";%s[%s]" % (colour, "" if mv == "--" else mv))
        colour = "W" if colour == "B" else "B"
    return "".join(out)


def source_move_sequence(line):
    """The move sequence as written in the source SGF, normalised for passes."""
    out = []
    for m in EX.MOVE_RE.finditer(line):
        coord = m.group(2)
        out.append(";%s[%s]" % (m.group(1), "" if coord in ("", "tt") else coord))
    return "".join(out)


def iter_source_lines(run_dir, quiet_seconds):
    """Yield the SGF lines in exactly the order the extractor accepted them."""
    files, _hot = EX.snapshot_files(run_dir, quiet_seconds)
    for _source, _net, path, size, _mtime in files:
        for raw in EX.stream_lines(path, size):
            line = raw.decode("utf-8", "replace").strip()
            if not line.endswith(")"):
                continue
            g = EX.parse_game(line)
            if g is None or g["size"] != N:
                continue
            yield line


def find_node(explicit):
    if explicit:
        return explicit if os.access(explicit, os.X_OK) else None
    for cand in NODE_CANDIDATES:
        if os.path.sep in cand:
            if os.access(cand, os.X_OK):
                return cand
        else:
            for d in os.environ.get("PATH", "").split(os.pathsep):
                p = os.path.join(d, cand)
                if os.access(p, os.X_OK):
                    return p
    return None


# --------------------------------------------------------------------------- test A

def test_round_trip(bundle, run_dir, sample_n, rng, quiet_seconds):
    print("A  round trip: re-serialise %d random games and compare with the source SGF" % sample_n)
    rows = bundle["games"]
    want = sorted(rng.sample(range(len(rows)), min(sample_n, len(rows))))
    wanted = set(want)
    checked = 0
    failures = []
    for gi, line in enumerate(iter_source_lines(run_dir, quiet_seconds)):
        if gi not in wanted:
            continue
        row = rows[gi]
        got = serialise(bundle, gi, row)
        expect = source_move_sequence(line)
        hash_in_line = EX.HASH_RE.search(line)
        if hash_in_line and hash_in_line.group(1)[:len(row[9])] != row[9]:
            failures.append("game %d: hash mismatch %s != %s" % (gi, hash_in_line.group(1), row[9]))
        if got != expect:
            failures.append("game %d: move sequence differs\n   record %s\n   source %s"
                            % (gi, got[:160], expect[:160]))
        checked += 1
        if checked == len(want):
            break
    print("   games compared      %d" % checked)
    print("   mismatches          %d" % len(failures))
    for f in failures[:5]:
        print("   " + f)
    ok = checked == len(want) and not failures
    print("   RESULT              %s" % ("PASS" if ok else "FAIL"))
    print("")
    return ok


# --------------------------------------------------------------------------- test B

def test_replay_all(bundle):
    print("B  replay: every game through the reference capture rule")
    rows = bundle["games"]
    extra = bundle.get("extra") or {}
    results = bundle["results"]
    t0 = time.time()

    problems = []
    decisive = 0
    agree_area = 0
    agree_stones = 0
    total_caps = 0
    capture_games = 0
    for gi, row in enumerate(rows):
        ex = extra.get(str(gi), {})
        st = replay(points_of(bundle, row), ex.get("ab", ""), ex.get("aw", ""),
                    ex.get("first", "B"))
        if st["problems"]:
            problems.append((gi, st["problems"][0]))
        caps = st["capB"] + st["capW"]
        total_caps += caps
        if caps:
            capture_games += 1

        winner = results[row[4]][1]
        if winner not in ("B", "W"):
            continue
        decisive += 1
        komi = row[3]
        margin_area = area_score(st["stones"]) - komi
        margin_stones = (st["stones"].count(1) - st["stones"].count(2)) - komi
        if (margin_area > 0 and winner == "B") or (margin_area < 0 and winner == "W"):
            agree_area += 1
        if (margin_stones > 0 and winner == "B") or (margin_stones < 0 and winner == "W"):
            agree_stones += 1

    dt = time.time() - t0
    print("   games replayed      %d in %.1f s" % (len(rows), dt))
    print("   invariant breaks    %d   (stone counts never negative; on board + captured"
          " == played + setup)" % len(problems))
    for gi, msg in problems[:5]:
        print("   game %d: %s" % (gi, msg))
    print("   games with captures %d   stones captured in total %d" % (capture_games, total_caps))
    print("   decisive RE[] games %d" % decisive)
    if decisive:
        print("   final board agrees with the RE[] winner:")
        print("     area score - komi   %6d / %d  = %.1f%%"
              % (agree_area, decisive, 100.0 * agree_area / decisive))
        print("     stones on board     %6d / %d  = %.1f%%"
              % (agree_stones, decisive, 100.0 * agree_stones / decisive))
        print("   (reported, not asserted: the run randomises between territory and area")
        print("    scoring with several taxes, and games end on passes, so the replayed")
        print("    board is not expected to reproduce every scored result)")
    ok = not problems
    print("   RESULT              %s" % ("PASS" if ok else "FAIL"))
    print("")
    return ok


# --------------------------------------------------------------------------- test C

CORE_BEGIN = "/* --- go-core:begin ---"
CORE_END = "/* --- go-core:end --- */"


def extract_core(viewer_path):
    with open(viewer_path, encoding="utf-8") as fh:
        text = fh.read()
    a = text.index(CORE_BEGIN)
    b = text.index(CORE_END) + len(CORE_END)
    return text[a:b]


def build_fixture(bundle, sample_n, rng):
    rows = bundle["games"]
    extra = bundle.get("extra") or {}
    enc = bundle.get("move_encoding", "sgf2")
    picks = sorted(rng.sample(range(len(rows)), min(sample_n, len(rows))))
    # make sure the odd shapes are represented, not only quiet self-play games
    for key in sorted(extra, key=lambda k: int(k))[:12]:
        gi = int(key)
        if gi not in picks:
            picks.append(gi)
    picks = sorted(set(picks))

    cases = []
    for gi in picks:
        row = rows[gi]
        ex = extra.get(str(gi), {})
        st = replay(points_of(bundle, row), ex.get("ab", ""), ex.get("aw", ""),
                    ex.get("first", "B"))
        cases.append({
            "gi": gi,
            "h": row[9],
            "enc": enc,
            "moves": row[8],
            "ab": ex.get("ab", ""),
            "aw": ex.get("aw", ""),
            "first": ex.get("first", "B"),
            "final": board_string(st["stones"]),
            "capB": st["capB"],
            "capW": st["capW"],
        })
    return {"schema": 2,
            "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "source_snapshot_utc": bundle.get("snapshot_utc"),
            "board_size": bundle.get("board_size", 7),
            "cases": cases}


NODE_DRIVER = """
var GO = require(%s);
var fixture = require(%s);
GO.init(fixture.board_size || 7);
var pass = 0, fail = 0, first = [];
for (var i = 0; i < fixture.cases.length; i++) {
  var c = fixture.cases[i];
  var states = GO.replay(GO.decodeMoves(c.moves, c.enc),
                         { ab: c.ab, aw: c.aw, first: c.first });
  var fin = states[states.length - 1];
  var got = GO.boardString(fin);
  if (got === c.final && fin.capB === c.capB && fin.capW === c.capW) pass++;
  else {
    fail++;
    if (first.length < 3) {
      first.push("  case " + i + " game " + c.gi + " hash " + c.h +
                 "\\n    expected " + c.final + " capB " + c.capB + " capW " + c.capW +
                 "\\n    observed " + got + " capB " + fin.capB + " capW " + fin.capW);
    }
  }
}
console.log("   board               " + GO.N + "x" + GO.N);
console.log("   cases               " + fixture.cases.length);
console.log("   agree               " + pass);
console.log("   disagree            " + fail);
if (first.length) console.log(first.join("\\n"));
console.log("   RESULT              " + (fail === 0 ? "PASS" : "FAIL"));
process.exit(fail === 0 ? 0 : 1);
"""


def test_cross_check(bundle, viewer_path, fixture_path, sample_n, rng, node_path):
    print("C  cross-check: the viewer's board logic against the reference, same games")
    fixture = build_fixture(bundle, sample_n, rng)
    with open(fixture_path, "w") as fh:
        json.dump(fixture, fh, separators=(",", ":"))
        fh.write("\n")
    size = os.path.getsize(fixture_path)
    print("   fixture written     %s (%d bytes, %d cases)"
          % (fixture_path, size, len(fixture["cases"])))
    print("   viewer ?selftest    paste this file in place of the __SELFTEST__ placeholder")

    core = extract_core(viewer_path)
    m = re.search(r'var ALPHABET = "([^"]*)";', core)
    same = bool(m) and m.group(1) == EX.MOVE_ALPHABET
    print("   packing alphabet    %d chars, page and extractor %s"
          % (len(m.group(1)) if m else 0, "agree" if same else "DIFFER"))
    if not same:
        print("   RESULT              FAIL")
        print("")
        return False

    node = find_node(node_path)
    if not node:
        print("   node                not found -- browser-side check SKIPPED")
        print("   RESULT              SKIPPED (open viewer.html?selftest to run it)")
        print("")
        return True

    tmp = tempfile.mkdtemp(prefix="s7core")
    core_js = os.path.join(tmp, "go_core.js")
    drv_js = os.path.join(tmp, "drive.js")
    with open(core_js, "w", encoding="utf-8") as fh:
        fh.write(core)
    with open(drv_js, "w", encoding="utf-8") as fh:
        fh.write(NODE_DRIVER % (json.dumps(core_js), json.dumps(os.path.abspath(fixture_path))))
    print("   engine              %s (%s)" % (node, subprocess.run(
        [node, "--version"], stdout=subprocess.PIPE).stdout.decode().strip()))
    proc = subprocess.run([node, drv_js], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    sys.stdout.write(proc.stdout.decode())
    print("")
    return proc.returncode == 0



DOM_DRIVER = r"""
/* A small stand-in for the browser: enough of document/window for the viewer's script
   to run, render into strings, and answer key presses. */
var fs = require("fs");
var vm = require("vm");

var gamesPath = process.argv[2], analysisPath = process.argv[3];
var scriptPath = process.argv[4], expectPath = process.argv[5], fixturePath = process.argv[6];

function El(id) {
  this.id = id;
  this.textContent = "";
  this.innerHTML = "";
  this.value = "";
  this.checked = false;
  this.disabled = false;
  this.hidden = false;
  this.max = "0";
  this.style = {};
  this.scrollTop = 0;
  this.clientHeight = 600;
  this.offsetTop = 0;
  this.offsetHeight = 16;
  this.attrs = {};
  this.listeners = {};
}
El.prototype.addEventListener = function (t, f) {
  (this.listeners[t] = this.listeners[t] || []).push(f);
};
El.prototype.setAttribute = function (k, v) { this.attrs[k] = String(v); };
El.prototype.removeAttribute = function (k) { delete this.attrs[k]; };
El.prototype.getAttribute = function (k) { return this.attrs[k] === undefined ? null : this.attrs[k]; };
El.prototype.querySelectorAll = function () { return []; };
El.prototype.closest = function () { return null; };
Object.defineProperty(El.prototype, "children", { get: function () { return []; } });

var src = fs.readFileSync(scriptPath, "utf8")
  .replace("__GAMES__", "JSON.parse(FS.readFileSync(" + JSON.stringify(gamesPath) + ', "utf8"))');

/* Run the viewer's script once, in its own set of stand-in elements. */
function runViewer(search, selftestText) {
  var els = {};
  function el(id) { if (!els[id]) els[id] = new El(id); return els[id]; }
  var docListeners = {};
  el("analysis-data").textContent = fs.existsSync(analysisPath)
    ? fs.readFileSync(analysisPath, "utf8") : "__ANALYSIS__";
  el("selftest-data").textContent = selftestText;
  el("lastn").value = "5";

  var sandbox = {
    console: console, FS: fs,
    document: {
      getElementById: el,
      documentElement: el("__root__"),
      addEventListener: function (t, f) { (docListeners[t] = docListeners[t] || []).push(f); }
    },
    window: { addEventListener: function () {} },
    location: { search: search },
    requestAnimationFrame: function () { return 0; },
    Int8Array: Int8Array, Int16Array: Int16Array, Uint8Array: Uint8Array
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(src, sandbox, { filename: "viewer-script.js" });
  return { el: el, keydown: (docListeners.keydown || [])[0] };
}

var fails = [];
function check(cond, msg) { if (!cond) fails.push(msg); }

var app;
try {
  app = runViewer("", "__SELFTEST__");
} catch (e) {
  console.log("   viewer script threw: " + (e && e.stack ? e.stack.split("\n")[0] : e));
  console.log("   RESULT              FAIL");
  process.exit(1);
}
var el = app.el;
var expect = JSON.parse(fs.readFileSync(expectPath, "utf8"));

function countStones(html) {
  return [(html.match(/class="stone-b"/g) || []).length,
          (html.match(/class="stone-w"/g) || []).length];
}

check(el("shown").textContent === expect.shown,
      "count line shows " + el("shown").textContent + ", expected " + expect.shown);
check(el("total").textContent === expect.shown,
      "total shows " + el("total").textContent + ", expected " + expect.shown);
check(el("pbname").textContent === expect.black,
      "black name is " + el("pbname").textContent + ", expected " + expect.black);
check(el("pwname").textContent === expect.white,
      "white name is " + el("pwname").textContent + ", expected " + expect.white);
check((el("movelist").innerHTML.match(/class="mv"/g) || []).length === expect.positions.length - 1,
      "move list has the wrong number of rows");
check((el("listInner").innerHTML.match(/class="grow"/g) || []).length > 0,
      "game list rendered no rows");
check((el("listInner").innerHTML.match(/class="grow"/g) || []).length < 40,
      "game list rendered every row instead of a window");
check(el("grid").innerHTML.indexOf("gridline") >= 0, "board grid was not drawn");
check((el("labels").innerHTML.match(/class="coord"/g) || []).length === expect.n * 2,
      "expected " + (expect.n * 2) + " coordinate labels, drew " +
      (el("labels").innerHTML.match(/class="coord"/g) || []).length);
check((el("grid").innerHTML.match(/class="star"/g) || []).length === expect.stars,
      "expected " + expect.stars + " star points, drew " +
      (el("grid").innerHTML.match(/class="star"/g) || []).length);
check(el("recordhead").innerHTML.indexOf("spark") >= 0,
      "the winrate sparkline is missing on a gatekeeper game");
check(el("metarow").innerHTML.indexOf("Komi") >= 0, "the header is missing its fields");

var keydown = app.keydown;
check(!!keydown, "no keyboard handler was registered");

function press(key) {
  keydown({ key: key, target: { tagName: "BODY" }, preventDefault: function () {},
            metaKey: false, ctrlKey: false, altKey: false });
}

if (keydown) {
  press("Home");
  for (var i = 0; i < expect.positions.length; i++) {
    if (i > 0) press("ArrowRight");
    var got = countStones(el("stones").innerHTML);
    var want = expect.positions[i];
    if (got[0] !== want[0] || got[1] !== want[1] ||
        String(el("capb").textContent) !== String(want[2]) ||
        String(el("capw").textContent) !== String(want[3])) {
      fails.push("position " + i + ": drew " + got[0] + "b/" + got[1] + "w capB " +
                 el("capb").textContent + " capW " + el("capw").textContent +
                 ", expected " + want[0] + "b/" + want[1] + "w capB " + want[2] + " capW " + want[3]);
    }
    var nums = (el("stones").innerHTML.match(/class="num /g) || []).length;
    if (nums > 5) fails.push("position " + i + " numbered " + nums + " stones with last-5 selected");
    if (fails.length > 8) { fails.push("(stopping)"); break; }
  }
  check(String(el("curmove").textContent) === String(expect.positions.length - 1),
        "the walk did not end on the last move");
  press("End");
  check(String(el("curmove").textContent) === String(expect.positions.length - 1),
        "End did not go to the last move");
  press("Home");
  check(String(el("curmove").textContent) === "0", "Home did not go to the first position");
  check(countStones(el("stones").innerHTML)[0] === expect.positions[0][0],
        "Home did not restore the opening position");
}

/* the page's own ?selftest mode, driven with the fixture this run produced */
var stOut = "no output";
try {
  var st = runViewer("?selftest", fs.readFileSync(fixturePath, "utf8"));
  stOut = st.el("selftest").textContent;
  check(st.el("app").hidden === true, "?selftest did not hide the app");
  check(stOut.indexOf("RESULT PASS") >= 0, "?selftest did not report a pass");
  check(stOut.indexOf("fail  0") >= 0, "?selftest reported failing cases");
} catch (e) {
  fails.push("?selftest threw: " + e);
}

console.log("   board               " + expect.n + "x" + expect.n +
            ", " + expect.stars + " star points, " + (expect.n * 2) + " coordinate labels");
console.log("   opening game        #" + expect.gi + "  " + expect.black + " vs " + expect.white);
console.log("   positions walked    " + expect.positions.length);
console.log("   list rows drawn     " +
            (el("listInner").innerHTML.match(/class="grow"/g) || []).length + " of " + expect.shown);
console.log("   ?selftest output    " + stOut.split("\n").filter(function (l) {
  return /^(pass|fail|RESULT)/.test(l); }).join(" | "));
console.log("   mismatches          " + fails.length);
for (var f = 0; f < Math.min(fails.length, 6); f++) console.log("     " + fails[f]);
console.log("   RESULT              " + (fails.length ? "FAIL" : "PASS"));
process.exit(fails.length ? 1 : 0);
"""


def extract_script(viewer_path):
    """The viewer's one executable script block."""
    with open(viewer_path, encoding="utf-8") as fh:
        text = fh.read()
    blocks = re.findall(r"<script>(.*?)</script>", text, re.S)
    if len(blocks) != 1:
        raise RuntimeError("expected exactly one plain script block, found %d" % len(blocks))
    return blocks[0]


def opening_expectations(bundle):
    """What the viewer should show when it opens, and at every position of that game."""
    rows = bundle["games"]
    gi = -1
    for i in range(len(rows) - 1, -1, -1):
        if rows[i][0] == 1:
            gi = i
            break
    if gi < 0:
        gi = len(rows) - 1
    row = rows[gi]
    ex = (bundle.get("extra") or {}).get(str(gi), {})
    moves = points_of(bundle, row)
    stones = [0] * NP
    num = [0] * NP
    for i in range(0, len(ex.get("ab", "")) - 1, 2):
        p = sgf_to_point(ex["ab"][i:i + 2])
        if p != PASS:
            stones[p] = 1
    for i in range(0, len(ex.get("aw", "")) - 1, 2):
        p = sgf_to_point(ex["aw"][i:i + 2])
        if p != PASS:
            stones[p] = 2
    cap = {1: 0, 2: 0}
    colour = 2 if ex.get("first", "B") == "W" else 1
    positions = [[stones.count(1), stones.count(2), cap[1], cap[2]]]
    for i, p in enumerate(moves):
        if p != PASS:
            taken, self_lost = play_stone(stones, num, p, colour, i + 1)
            cap[colour] += taken
            if self_lost:
                cap[2 if colour == 1 else 1] += self_lost
        positions.append([stones.count(1), stones.count(2), cap[1], cap[2]])
        colour = 2 if colour == 1 else 1
    n = bundle.get("board_size", 7)
    stars = 1 if n < 9 and n % 2 else (5 if n % 2 else 4)
    nets = bundle["nets"]
    return {"gi": gi, "n": n, "stars": stars,
            "shown": "{:,}".format(len(rows)),
            "black": nets[row[1]]["name"],
            "white": nets[row[2]]["name"],
            "positions": positions}


def test_headless(bundle, games_path, viewer_path, fixture_path, node_path):
    print("D  headless run: the viewer's own script, walked move by move")
    node = find_node(node_path)
    if not node:
        print("   node                not found -- SKIPPED")
        print("   RESULT              SKIPPED")
        print("")
        return True
    tmp = tempfile.mkdtemp(prefix="s7dom")
    script_js = os.path.join(tmp, "viewer_script.js")
    driver_js = os.path.join(tmp, "dom_driver.js")
    expect_json = os.path.join(tmp, "expect.json")
    with open(script_js, "w", encoding="utf-8") as fh:
        fh.write(extract_script(viewer_path))
    with open(driver_js, "w", encoding="utf-8") as fh:
        fh.write(DOM_DRIVER)
    with open(expect_json, "w") as fh:
        json.dump(opening_expectations(bundle), fh)
    analysis = os.path.join(os.path.dirname(games_path), "games_analysis.json")
    proc = subprocess.run([node, driver_js, os.path.abspath(games_path),
                           os.path.abspath(analysis), script_js, expect_json,
                           os.path.abspath(fixture_path)],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    sys.stdout.write(proc.stdout.decode())
    print("")
    return proc.returncode == 0


# --------------------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--games", default=DEFAULT_GAMES)
    ap.add_argument("--run-dir", default=EX.DEFAULT_RUN)
    ap.add_argument("--viewer", default=os.path.join(HERE, "viewer.html"))
    ap.add_argument("--fixture", default=os.path.join(EX.DEFAULT_OUT, "selftest_fixture.json"))
    ap.add_argument("--round-trip", type=int, default=50)
    ap.add_argument("--quiet-seconds", type=int, default=EX.DEFAULT_QUIET_SECONDS,
                    help="must match the value the bundle was extracted with, so the "
                         "round trip walks the same files in the same order")
    ap.add_argument("--fixture-only", action="store_true",
                    help="only write selftest_fixture.json, run no tests")
    ap.add_argument("--cross-check", type=int, default=200)
    ap.add_argument("--seed", type=int, default=20260905)
    ap.add_argument("--node", default=None)
    args = ap.parse_args(argv)

    bundle = load_bundle(args.games)
    set_board_size(bundle.get("board_size", 7))

    if args.fixture_only:
        fixture = build_fixture(bundle, args.cross_check, random.Random(args.seed + 1))
        with open(args.fixture, "w") as fh:
            json.dump(fixture, fh, separators=(",", ":"))
            fh.write("\n")
        print("fixture %s (%d cases, %dx%d)"
              % (args.fixture, len(fixture["cases"]), N, N))
        return 0

    print("games.json  %s" % args.games)
    print("label       %s" % bundle.get("label"))
    print("snapshot    %s" % bundle.get("snapshot_utc"))
    print("board       %dx%d" % (N, N))
    print("games       %d   nets %d   encoding %s   hash %d chars"
          % (len(bundle["games"]), len(bundle["nets"]), bundle.get("move_encoding"),
             bundle.get("hash_chars", 32)))
    print("seed        %d" % args.seed)
    print("")

    ok = True
    ok &= test_round_trip(bundle, args.run_dir, args.round_trip, random.Random(args.seed),
                          args.quiet_seconds)
    ok &= test_replay_all(bundle)
    ok &= test_cross_check(bundle, args.viewer, args.fixture, args.cross_check,
                           random.Random(args.seed + 1), args.node)
    ok &= test_headless(bundle, args.games, args.viewer, args.fixture, args.node)

    print("OVERALL     %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
