#!/usr/bin/env python3
"""Extract every game of a self-play training run into a compact JSON bundle.

Reads the ``.sgfs`` files written by the self-play and gatekeeper workers (one SGF game
per line) and emits three files:

  games.json           compact records for the browser viewer
  games_analysis.json  per-move analysis for gatekeeper games; a separate optional file
                       so the main bundle stays as small as it can
  games_stats.json     counts by source / net / result / gtype, mean length, snapshot time

The run may still be writing while this runs, so the extractor takes a snapshot: it stats
every file once, then reads at most that many bytes and keeps only complete lines.
Re-running it simply takes a newer snapshot, so it is safe to run at any time.

Standard library only, streaming, single pass -- safe to run on a login node.

games.json layout (positional arrays rather than objects, to keep the file small)::

    {
      "schema": 3,
      "snapshot_utc": "2026-09-05T00:23:54Z",
      "board_size": 9,
      "label": "9x9 production chain",
      "sources":  ["selfplay", "gatekeeper"],
      "gtypes":   ["normal", "fork", "asym", "cleanuptraining"],
      "nets":     [{"i":0,"name":"t7-s11808-d11838","samples":11808,"rows":11838,"cycle":1}, ...],
      "results":  [["B+1.5","B"], ["Draw","draw"], ["Void","unknown"], ...],
      "move_encoding": "packed1",
      "fields":   ["src","black","white","komi","result","handicap","gtype","nmoves","moves","hash"],
      "games":    [[0, 12, 12, 8, 4, 0, 0, 28, "ONn6g", "484ABD87"], ...],
      "extra":    {"1734": {"ab": "gacced", "aw": "fbgd", "first": "W"}, ...}
    }

  src        index into ``sources``
  black      index into ``nets``          white   index into ``nets``
  komi       number                       result  index into ``results``
  handicap   integer from HA[]            gtype   index into ``gtypes``
  nmoves     number of moves              moves   see ``move_encoding``
  hash       the first ``hash_chars`` characters of the gameHash, enough to search on

``results`` entries are ``[result string, winner]`` with winner in B / W / draw / unknown.

``move_encoding`` is ``"packed1"`` by default: one character per move, taken from
``move_alphabet`` at index ``row * board_size + column``, with index ``board_size ** 2``
meaning a pass.  ``--sgf2-moves`` switches it to ``"sgf2"``, one string of two-character
SGF coordinates with ``--`` for a pass, which is easier to read but twice the size.  The
viewer reads either form.  ``packed1`` needs one alphabet character per board point, so
it is available up to a 9x9 board and the extractor falls back to ``sgf2`` above that.

The board size is read from the first game's ``SZ[]`` and every game of another size is
skipped and counted; ``--board-size`` pins it explicitly.

``extra`` is sparse and holds only what few games need: ``ab`` / ``aw`` are the AB[] / AW[]
setup stones as concatenated two-character coordinates (cleanup-training positions start
from a filled board), and ``first`` is ``"W"`` when White plays the first move.  Moves
alternate colour from there, so no per-move colour has to be stored.

games_analysis.json layout::

    {"schema":1,"wr":{"<game index>":[51,48,...]},"visits":{"<game index>":100 | [...]}}

``wr`` is the black winrate x100 as an integer per move (-1 where the record carries no
analysis comment); ``visits`` is a single integer when every move used the same visit
count, otherwise one integer per move.
"""

import argparse
import json
import os
import re
import statistics
import sys
import time

DEFAULT_BOARD_SIZE = 7
DEFAULT_RUN = "/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runs/t7"
DEFAULT_OUT = "/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/games_viewer"
DEFAULT_HASH_CHARS = 8
DEFAULT_QUIET_SECONDS = 120

SOURCES = ["selfplay", "gatekeeper"]

MOVE_RE = re.compile(r";([BW])\[([a-z]*)\](?:C\[((?:[^\]\\]|\\.)*)\])?")
PROP_RE = re.compile(r"([A-Z]+)\[((?:[^\]\\]|\\.)*)\]")
SETUP_RE = re.compile(r"\b(AB|AW)((?:\[[a-z]*\])+)")
SIZE_RE = re.compile(r"\bSZ\[(\d+)")
COORD_RE = re.compile(r"\[([a-z]*)\]")
NET_RE = re.compile(r"-s(\d+)-d(\d+)$")
CYCLE_DONE_RE = re.compile(r"cycle (\d+) complete")
CYCLE_INDEX_RE = re.compile(r"CYCLE_INDEX=(\d+)")
CHAIN_DEPTH_RE = re.compile(r"chain depth (\d+)/(\d+)")
JOB_RE = re.compile(r"loop\.sbatch job (\d+)")
HASH_RE = re.compile(r"gameHash=([0-9A-Fa-f]+)")
GTYPE_RE = re.compile(r"gtype=([A-Za-z0-9_]+)")
VISITS_RE = re.compile(r"v=(\d+)")

# 86 characters that need no escaping in JSON, cannot close a script tag, and carry no
# underscore, so a packed move string can never look like an injection placeholder.
# One per board point, plus one for a pass: enough for any board up to 9x9.
MOVE_ALPHABET = ("0123456789"
                 "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                 "abcdefghijklmnopqrstuvwxyz"
                 "!#()*+,-.:;=?^~|/&'`")


def can_pack(board_size):
    """Whether one alphabet character per board point (plus a pass) is available."""
    return board_size * board_size + 1 <= len(MOVE_ALPHABET)


def pack_moves(moves, board_size):
    """Encode a list of two-character SGF coordinates as one character each."""
    out = []
    pass_code = board_size * board_size
    for mv in moves:
        if mv == "--":
            out.append(MOVE_ALPHABET[pass_code])
        else:
            col = ord(mv[0]) - 97
            row = ord(mv[1]) - 97
            out.append(MOVE_ALPHABET[row * board_size + col])
    return "".join(out)


def unpack_moves(packed, board_size):
    """Inverse of :func:`pack_moves`."""
    out = []
    pass_code = board_size * board_size
    for ch in packed:
        code = MOVE_ALPHABET.index(ch)
        if code == pass_code:
            out.append("--")
        else:
            out.append(chr(97 + code % board_size) + chr(97 + code // board_size))
    return out


def split_moves(text, encoding, board_size):
    """Split a stored move string back into a list of two-character coordinates."""
    if encoding == "packed1":
        return unpack_moves(text, board_size)
    return [text[i:i + 2] for i in range(0, len(text), 2)]


# --------------------------------------------------------------------------- files

def net_sort_key(name):
    """Order net directories the way the training loop produced them."""
    m = NET_RE.search(name)
    if m:
        return (1, int(m.group(1)), name)
    return (0, 0, name)


def expand_label(label, run_info, board_size, n_games):
    """Fill {job} {link} {chain} {cycle} {n} {games} in a header label."""
    if not label:
        return None
    subs = {
        "{job}": str(run_info.get("job") or "?"),
        "{link}": str(run_info.get("link") or "?"),
        "{chain}": str(run_info.get("chain_length") or "?"),
        "{cycle}": str(run_info.get("current_cycle")
                       if run_info.get("current_cycle") is not None
                       else run_info.get("cycles_completed") or "?"),
        "{n}": str(board_size),
        "{games}": "{:,}".format(n_games),
    }
    for k, v in subs.items():
        label = label.replace(k, v)
    return label


def detect_board_size(files):
    """Board size of the first game in the snapshot, from its SZ[] property."""
    for _source, _net, path, size, _mtime in files:
        for raw in stream_lines(path, min(size, 1 << 16)):
            m = SIZE_RE.search(raw.decode("utf-8", "replace"))
            if m:
                return int(m.group(1))
    return None


def read_run_info(run_dir, loop_log):
    """Cycle and chain position, read from the loop log and the run's cycle counter."""
    info = {"cycles_completed": None, "current_cycle": None, "link": None,
            "chain_length": None, "job": None, "loop_log": loop_log}
    counter = os.path.join(run_dir, ".cycles_completed")
    if os.path.exists(counter):
        try:
            with open(counter) as fh:
                info["cycles_completed"] = len([l for l in fh if l.strip()])
        except OSError:
            pass
    if loop_log and os.path.exists(loop_log):
        try:
            with open(loop_log, errors="replace") as fh:
                for line in fh:
                    m = CYCLE_DONE_RE.search(line)
                    if m:
                        info["cycles_completed"] = int(m.group(1))
                    m = CYCLE_INDEX_RE.search(line)
                    if m:
                        info["current_cycle"] = int(m.group(1))
                    m = CHAIN_DEPTH_RE.search(line)
                    if m:
                        info["link"], info["chain_length"] = int(m.group(1)), int(m.group(2))
                    m = JOB_RE.search(line)
                    if m:
                        info["job"] = m.group(1)
        except OSError:
            pass
    return info


def snapshot_files(run_dir, quiet_seconds=0):
    """List the .sgfs files with the size each had at snapshot time.

    A file written within the last ``quiet_seconds`` is left out entirely, so the
    snapshot only contains files the run has finished with.
    """
    files = []
    cutoff = time.time() - quiet_seconds
    skipped_hot = []
    for source, root in ((0, os.path.join(run_dir, "selfplay")),
                         (1, os.path.join(run_dir, "gatekeepersgf"))):
        if not os.path.isdir(root):
            continue
        for net in sorted(os.listdir(root), key=net_sort_key):
            sgf_dir = os.path.join(root, net, "sgfs")
            if not os.path.isdir(sgf_dir):
                sgf_dir = os.path.join(root, net)
            if not os.path.isdir(sgf_dir):
                continue
            for fn in sorted(os.listdir(sgf_dir)):
                if not fn.endswith(".sgfs"):
                    continue
                path = os.path.join(sgf_dir, fn)
                try:
                    st = os.stat(path)
                except OSError:
                    continue
                if not st.st_size:
                    continue
                if quiet_seconds and st.st_mtime > cutoff:
                    skipped_hot.append(path)
                    continue
                files.append((source, net, path, st.st_size, st.st_mtime))
    return files, skipped_hot


def stream_lines(path, limit, chunk=1 << 20):
    """Yield complete lines from the first ``limit`` bytes of ``path``."""
    remaining = limit
    tail = b""
    with open(path, "rb") as fh:
        while remaining > 0:
            block = fh.read(min(chunk, remaining))
            if not block:
                break
            remaining -= len(block)
            tail += block
            start = 0
            idx = tail.find(b"\n", start)
            while idx != -1:
                yield tail[start:idx]
                start = idx + 1
                idx = tail.find(b"\n", start)
            tail = tail[start:]
    if tail.strip():
        yield tail


# --------------------------------------------------------------------------- parse

def parse_result(raw):
    """Map an SGF RE[] value to (display string, winner)."""
    if raw is None:
        return ("?", "unknown")
    text = raw.strip()
    if text in ("", "?"):
        return ("?", "unknown")
    if text in ("0", "Draw", "draw", "Jigo"):
        return ("Draw", "draw")
    if text.lower() == "void":
        return ("Void", "unknown")
    head = text[0].upper()
    if head in ("B", "W") and len(text) > 1 and text[1] == "+":
        return (text, head)
    return (text, "unknown")


def parse_game(line):
    """Parse one SGF line into a plain dict, or None if it is not a usable game."""
    if not line.startswith("(;"):
        return None
    first = MOVE_RE.search(line)
    root = line[:first.start()] if first else line

    props = {}
    for m in PROP_RE.finditer(root):
        props.setdefault(m.group(1), m.group(2))

    setup = {"AB": "", "AW": ""}
    for m in SETUP_RE.finditer(root):
        setup[m.group(1)] = "".join(c for c in COORD_RE.findall(m.group(2)) if c)

    moves = []
    winrates = []
    visits = []
    first_colour = "B"
    for i, m in enumerate(MOVE_RE.finditer(line)):
        if i == 0:
            first_colour = m.group(1)
        coord = m.group(2)
        comment = m.group(3)
        moves.append("--" if coord in ("", "tt") else coord)
        wr = -1
        vis = -1
        if comment:
            head = comment.split(None, 1)
            if head:
                try:
                    wr = int(round(float(head[0]) * 100))
                except ValueError:
                    wr = -1
            vm = VISITS_RE.search(comment)
            if vm:
                vis = int(vm.group(1))
        winrates.append(wr)
        visits.append(vis)

    try:
        komi = float(props.get("KM", "0") or 0)
    except ValueError:
        komi = 0.0
    if komi == int(komi):
        komi = int(komi)
    try:
        handicap = int(props.get("HA", "0") or 0)
    except ValueError:
        handicap = 0

    comment0 = props.get("C", "")
    hm = HASH_RE.search(comment0)
    gm = GTYPE_RE.search(comment0)
    return {
        "black": props.get("PB", "?"),
        "white": props.get("PW", "?"),
        "komi": komi,
        "result": parse_result(props.get("RE")),
        "handicap": handicap,
        "gtype": gm.group(1) if gm else "unknown",
        "moves": moves,
        "first": first_colour,
        "ab": setup["AB"],
        "aw": setup["AW"],
        "hash": hm.group(1) if hm else "",
        "wr": winrates,
        "visits": visits,
        "size": int(props.get("SZ", "0").split(":")[0] or 0),
    }


# --------------------------------------------------------------------------- build

def build(run_dir, out_dir, keep_analysis, target_bytes, packed=True, verbose=True,
          board_size=None, label=None, hash_chars=DEFAULT_HASH_CHARS,
          quiet_seconds=DEFAULT_QUIET_SECONDS, loop_log=None):
    snapshot_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    files, skipped_hot = snapshot_files(run_dir, quiet_seconds)
    total_bytes = sum(f[3] for f in files)
    run_info = read_run_info(run_dir, loop_log)

    if board_size is None:
        board_size = detect_board_size(files) or DEFAULT_BOARD_SIZE
    if packed and not can_pack(board_size):
        packed = False
    encoding = "packed1" if packed else "sgf2"

    nets, net_index = [], {}
    results, result_index = [], {}
    gtypes, gtype_index = [], {}
    games, extra = [], {}
    analysis_wr, analysis_visits = {}, {}

    by_source = [0, 0]
    by_winner = {"B": 0, "W": 0, "draw": 0, "unknown": 0}
    by_net = {}
    by_komi = {}
    by_gtype = {}
    handicap_games = 0
    setup_games = 0
    white_first = 0
    pass_moves = 0
    bad_lines = 0
    wrong_size = 0
    lengths = []

    def net_id(name):
        idx = net_index.get(name)
        if idx is None:
            idx = len(nets)
            net_index[name] = idx
            m = NET_RE.search(name)
            nets.append({"i": idx, "name": name,
                         "samples": int(m.group(1)) if m else 0,
                         "rows": int(m.group(2)) if m else 0})
            by_net[name] = {"black": 0, "white": 0, "games": 0}
        return idx

    for source, _net_dir, path, size, _mtime in files:
        for raw in stream_lines(path, size):
            line = raw.decode("utf-8", "replace").strip()
            if not line.endswith(")"):
                bad_lines += 1  # truncated tail of a file still being written
                continue
            game = parse_game(line)
            if game is None:
                bad_lines += 1
                continue
            if game["size"] != board_size:
                wrong_size += 1
                continue

            bi = net_id(game["black"])
            wi = net_id(game["white"])

            rkey = game["result"]
            ri = result_index.get(rkey)
            if ri is None:
                ri = len(results)
                result_index[rkey] = ri
                results.append([rkey[0], rkey[1]])

            gkey = game["gtype"]
            gt_i = gtype_index.get(gkey)
            if gt_i is None:
                gt_i = len(gtypes)
                gtype_index[gkey] = gt_i
                gtypes.append(gkey)

            moves = game["moves"]
            gi = len(games)
            games.append([
                source, bi, wi, game["komi"], ri, game["handicap"], gt_i,
                len(moves), pack_moves(moves, board_size) if packed else "".join(moves),
                game["hash"][:hash_chars],
            ])

            odd = {}
            if game["ab"]:
                odd["ab"] = game["ab"]
            if game["aw"]:
                odd["aw"] = game["aw"]
            if game["first"] != "B":
                odd["first"] = game["first"]
                white_first += 1
            if odd:
                extra[str(gi)] = odd
                if "ab" in odd or "aw" in odd:
                    setup_games += 1

            if source == 1:
                analysis_wr[gi] = game["wr"]
                vs = game["visits"]
                analysis_visits[gi] = vs[0] if vs and len(set(vs)) == 1 else vs

            by_source[source] += 1
            by_winner[rkey[1]] += 1
            by_net[nets[bi]["name"]]["black"] += 1
            by_net[nets[wi]["name"]]["white"] += 1
            by_net[nets[bi]["name"]]["games"] += 1
            if wi != bi:
                by_net[nets[wi]["name"]]["games"] += 1
            kkey = str(game["komi"])
            by_komi[kkey] = by_komi.get(kkey, 0) + 1
            by_gtype[gkey] = by_gtype.get(gkey, 0) + 1
            if game["handicap"]:
                handicap_games += 1
            pass_moves += moves.count("--")
            lengths.append(len(moves))

    # cycle number: rank of the net by training samples (the random net is cycle 0)
    for rank, i in enumerate(sorted(range(len(nets)),
                                    key=lambda k: (nets[k]["samples"], nets[k]["name"]))):
        nets[i]["cycle"] = rank

    label = expand_label(label, run_info, board_size, len(games))

    bundle = {
        "schema": 3,
        "snapshot_utc": snapshot_utc,
        "run_dir": run_dir,
        "board_size": board_size,
        "label": label or ("%d\u00d7%d games" % (board_size, board_size)),
        "run": run_info,
        "sources": SOURCES,
        "gtypes": gtypes,
        "nets": nets,
        "results": results,
        "hash_chars": hash_chars,
        "move_encoding": encoding,
        "move_alphabet": MOVE_ALPHABET if packed else None,
        "fields": ["src", "black", "white", "komi", "result", "handicap", "gtype",
                   "nmoves", "moves", "hash"],
        "games": games,
        "extra": extra,
    }

    os.makedirs(out_dir, exist_ok=True)
    games_path = os.path.join(out_dir, "games.json")
    analysis_path = os.path.join(out_dir, "games_analysis.json")
    stats_path = os.path.join(out_dir, "games_stats.json")

    payload = json.dumps(bundle, separators=(",", ":"))
    with open(games_path, "w") as fh:
        fh.write(payload)
    games_bytes = len(payload.encode("utf-8"))

    analysis_bytes = 0
    if keep_analysis and analysis_wr:
        apayload = json.dumps({"schema": 1,
                               "wr": {str(k): v for k, v in analysis_wr.items()},
                               "visits": {str(k): v for k, v in analysis_visits.items()}},
                              separators=(",", ":"))
        with open(analysis_path, "w") as fh:
            fh.write(apayload)
        analysis_bytes = len(apayload.encode("utf-8"))
    elif os.path.exists(analysis_path):
        os.remove(analysis_path)

    by_result = {}
    for g in games:
        key = results[g[4]][0]
        by_result[key] = by_result.get(key, 0) + 1

    per_cycle = {}
    for g in games:
        for ni in (g[1], g[2]):
            key = str(nets[ni]["cycle"])
            per_cycle[key] = per_cycle.get(key, 0) + (1 if g[1] != g[2] else 0.5)
    per_cycle = {k: int(round(v)) for k, v in per_cycle.items()}

    stats_out = {
        "snapshot_utc": snapshot_utc,
        "run_dir": run_dir,
        "label": bundle["label"],
        "board_size": board_size,
        "run": run_info,
        "files_read": len(files),
        "files_skipped_still_hot": len(skipped_hot),
        "quiet_seconds": quiet_seconds,
        "games_by_cycle": per_cycle,
        "hash_chars": hash_chars,
        "bytes_snapshotted": total_bytes,
        "games": len(games),
        "games_by_source": {SOURCES[i]: by_source[i] for i in (0, 1)},
        "games_by_winner": by_winner,
        "games_by_result": by_result,
        "games_by_net": by_net,
        "games_by_komi": by_komi,
        "games_by_gtype": by_gtype,
        "handicap_games": handicap_games,
        "games_with_setup_stones": setup_games,
        "games_white_first": white_first,
        "distinct_nets": len(nets),
        "distinct_results": len(results),
        "moves_total": sum(lengths),
        "pass_moves": pass_moves,
        "moves_mean": round(statistics.mean(lengths), 3) if lengths else 0,
        "moves_median": statistics.median(lengths) if lengths else 0,
        "moves_min": min(lengths) if lengths else 0,
        "moves_max": max(lengths) if lengths else 0,
        "skipped_lines": bad_lines,
        "skipped_wrong_board_size": wrong_size,
        "bytes_games_json": games_bytes,
        "bytes_games_analysis_json": analysis_bytes,
        "analysis_kept": bool(analysis_bytes),
        "move_encoding": encoding,
        "target_bytes": target_bytes,
        "bytes_games_json_per_1000_games":
            int(round(games_bytes * 1000.0 / len(games))) if games else 0,
        "bytes_bundle_per_1000_games":
            int(round((games_bytes + analysis_bytes) * 1000.0 / len(games))) if games else 0,
    }
    with open(stats_path, "w") as fh:
        json.dump(stats_out, fh, indent=1, sort_keys=True)
        fh.write("\n")

    if verbose:
        mb = 1024.0 * 1024.0
        print("label                   %s" % bundle["label"])
        print("board size              %dx%d" % (board_size, board_size))
        print("snapshot_utc            %s" % snapshot_utc)
        print("files snapshotted       %d (%.1f MiB on disk); %d skipped as written "
              "within %ds" % (len(files), total_bytes / mb, len(skipped_hot), quiet_seconds))
        if run_info.get("job"):
            print("run                     job %s, link %s/%s, cycle %s in progress, "
                  "%s complete"
                  % (run_info["job"], run_info["link"], run_info["chain_length"],
                     run_info["current_cycle"], run_info["cycles_completed"]))
        print("games parsed            %d  (selfplay %d, gatekeeper %d)"
              % (len(games), by_source[0], by_source[1]))
        print("lines skipped           %d incomplete/unparsable, %d not %dx%d"
              % (bad_lines, wrong_size, board_size, board_size))
        print("distinct nets           %d" % len(nets))
        print("distinct results        %d" % len(results))
        print("game types              %s"
              % ", ".join("%s %d" % (k, by_gtype[k]) for k in sorted(by_gtype)))
        print("setup-stone games       %d   white-to-move-first %d   handicap %d"
              % (setup_games, white_first, handicap_games))
        print("moves total / mean      %d / %.2f" % (sum(lengths), stats_out["moves_mean"]))
        print("winner B/W/draw/unk     %d / %d / %d / %d"
              % (by_winner["B"], by_winner["W"], by_winner["draw"], by_winner["unknown"]))
        print("move encoding           %s   hash kept %d chars" % (encoding, hash_chars))
        print("games.json              %d bytes (%.2f MiB)  %s"
              % (games_bytes, games_bytes / mb, games_path))
        if analysis_bytes:
            print("games_analysis.json     %d bytes (%.2f MiB)  %s"
                  % (analysis_bytes, analysis_bytes / mb, analysis_path))
        else:
            print("games_analysis.json     not written (analysis dropped)")
        print("games_stats.json        %s" % stats_path)
        total = games_bytes + analysis_bytes
        print("total bundle            %d bytes (%.2f MiB), target %.2f MiB -> %s"
              % (total, total / mb, target_bytes / mb,
                 "within target" if total <= target_bytes else "OVER TARGET"))
        if games:
            per_k = stats_out["bytes_bundle_per_1000_games"]
            print("growth                  %d bytes (%.3f MiB) per 1000 games"
                  % (per_k, per_k / mb))
            headroom = 16 * 1024 * 1024 - total
            print("                        %s more games before a 16 MB page"
                  % ("{:,}".format(int(headroom / per_k * 1000)) if per_k > 0 and headroom > 0
                     else "0"))
    return games_bytes, analysis_bytes, stats_out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--run-dir", default=DEFAULT_RUN)
    ap.add_argument("--out-dir", default=DEFAULT_OUT)
    ap.add_argument("--label", default=None,
                    help="the line the viewer prints in its header, e.g. "
                         "\"9x9 production chain - link 1 - job 301099\"")
    ap.add_argument("--board-size", type=int, default=None,
                    help="pin the board size instead of reading it from the first SZ[]")
    ap.add_argument("--loop-log", default=None,
                    help="loop log to read the cycle and chain position from")
    ap.add_argument("--quiet-seconds", type=int, default=DEFAULT_QUIET_SECONDS,
                    help="leave out any file written this recently, so the snapshot only "
                         "holds files the run has finished with (default %d)"
                         % DEFAULT_QUIET_SECONDS)
    ap.add_argument("--hash-chars", type=int, default=DEFAULT_HASH_CHARS,
                    help="how much of each game hash to keep for searching (default %d)"
                         % DEFAULT_HASH_CHARS)
    ap.add_argument("--target-mib", type=float, default=6.0,
                    help="size target for the bundle (default 6 MiB)")
    ap.add_argument("--sgf2-moves", action="store_true",
                    help="store the two-character SGF coordinate per move instead of the "
                         "packed single character; easier to read, twice the size")
    ap.add_argument("--no-analysis", action="store_true",
                    help="do not write the gatekeeper per-move analysis file")
    args = ap.parse_args(argv)

    target = int(args.target_mib * 1024 * 1024)
    games_bytes, analysis_bytes, _ = build(
        args.run_dir, args.out_dir, not args.no_analysis, target,
        packed=not args.sgf2_moves, board_size=args.board_size, label=args.label,
        hash_chars=args.hash_chars, quiet_seconds=args.quiet_seconds,
        loop_log=args.loop_log)

    if games_bytes + analysis_bytes > target:
        print("")
        print("NOTE the bundle is over the target. In order, the levers are:")
        if args.sgf2_moves:
            print("     drop --sgf2-moves (the packed encoding halves the move payload),")
        print("     --no-analysis (drops the gatekeeper per-move arrays, kept in their own")
        print("     file so they never inflate games.json), then a smaller --hash-chars.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
