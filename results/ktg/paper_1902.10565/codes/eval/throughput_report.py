#!/usr/bin/env python3
"""throughput_report.py -- mission ktg-train, node arxiv-1902.10565::measure_stage_throughput.

P8 of tasks/production_chain_9x9: the rates at the PRODUCTION knobs, measured over a
running or finished chain BASEDIR, in the shape check_knobs_9x9.py consumes.

    python3 codes/eval/throughput_report.py $P1 --out $EV/throughput.json
    python3 codes/eval/check_knobs_9x9.py --throughput $EV/throughput.json \
                                          --rows-file $EV/rows_per_game.txt

STANDARD LIBRARY ONLY -- no numpy, no torch, no GPU, one process. It is a login-node
reader (task section 5: "Monitoring is READ-ONLY on the login node ... no torch except
checkpoint metadata reads at link boundaries"), and it does not even need that
exception: every number below comes from files the loop already wrote.

  games            one line of a .sgfs file            (selfplaymanager.cpp:377-378)
  rows             sum of binaryInputNCHWPacked.shape[0] over the tdata npz
  samples trained  max global_step_samples over the exported nets' metadata.json and
                   over $BASEDIR/audit_hooks/ckpt_*.json -- the same counter
                   audit_smoke.py reads out of the checkpoint, but taken from the JSON
                   the exporter already wrote, so no torch is needed
  stage timings    the stage sampler's per-(phase, stage) spans, phase = "cycle<N>"
                   (stage_monitor.sh; synchronous_loop_9x9.sh:339-342 retags per cycle)
  gpu              nvidia-smi samples, joined to the stage intervals by timestamp

REUSED, not re-implemented (task section 7: "reuses audit_smoke.parse_monitor /
sgfs_stats / npz_report over $P1"):
    audit_smoke.parse_monitor   per-(phase, stage) thread / RSS peaks with the o37
                                per-job file rule and the legA foreign-pid exclusion
    audit_smoke.sgfs_stats      game counts and the SZ[9] split
    audit_smoke.npz_report      row counts and the 2145 B row assertion
    audit_smoke.pick_ps_file    the o37 "one ps file per job" rule

OUTPUTS
    --out FILE        the throughput JSON (default: stdout only)
    --rows-out FILE   rows_per_game text in the form derive_knobs.parse_rows_per_game
                      reads (default: rows_per_game.txt beside --out)

ASSERTIONS (each exits non-zero, and each is a P-row of the task file)
    --assert-nlwp-le N            P1 / o03 / o39 (c): nlwp_max per stage <= N
    --assert-projected-cycle-h X  P8: projected_cycle_h <= X
    --assert-real-rows            fail if no real-net games were measured at all

usage:
  throughput_report.py <BASEDIR> [--job TAG] [--ps-file F] [--gpu-file F]
                       [--probe-search JSON] [--out F] [--rows-out F] [--note TEXT]
                       [--assert-nlwp-le N] [--assert-projected-cycle-h X]
                       [--assert-real-rows] [--quiet]

`--job TAG` selects monitor/ps_samples-<TAG>.tsv and monitor/gpu_samples-<TAG>.csv, the
o37 per-job files. Without it the newest per-job file wins, and the legacy shared
ps_samples.tsv is the last resort -- exactly audit_smoke.pick_ps_file's rule.
"""

import argparse
import datetime
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audit_smoke as A  # noqa: E402

STAGES = ("gatekeeper", "selfplay", "shuffle", "train")


# --------------------------------------------------------------------------- helpers
def dir_bytes(path):
    return A.dir_bytes(path)


def stage_spans(ps_file):
    """One extra pass over the ps samples for the TIME SPANS parse_monitor discards.

    parse_monitor returns elapsed_s per (phase, stage) -- the length of a span -- but
    not where it sits on the clock, and the GPU join and the per-cycle wall clock both
    need the endpoints. Foreign pids are excluded by the same rule parse_monitor uses
    (a pid classified `train` during phase legA in an unfiltered 6-column row).
    """
    rows = []
    ncols_seen = set()
    if ps_file and os.path.exists(ps_file):
        with open(ps_file, "r", errors="replace") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 6:
                    continue
                ncols_seen.add(len(parts))
                try:
                    t = float(parts[0])
                    pid = int(parts[3])
                except ValueError:
                    continue
                rows.append((t, parts[1], parts[2], pid, len(parts)))
    foreign = {pid for (_t, ph, st, pid, nc) in rows
               if nc < 7 and st == "train" and ph == "legA"}

    per_ps, per_phase = {}, {}
    for (t, ph, st, pid, _nc) in rows:
        if pid in foreign:
            continue
        for key, table in (("%s/%s" % (ph, st), per_ps), (ph, per_phase)):
            e = table.setdefault(key, [t, t])
            if t < e[0]:
                e[0] = t
            if t > e[1]:
                e[1] = t
    return per_ps, per_phase


def parse_gpu(path):
    """nvidia-smi samples: 'YYYY/MM/DD HH:MM:SS.mmm, idx, N %, M MiB' -> (epoch, util, mib).

    The timestamp is the node's LOCAL time and the ps sampler's is epoch seconds, so the
    join below converts through the reader's own local zone. Both were written on the
    same node in the same run, so the zone is the same one.
    """
    out = []
    if not path or not os.path.exists(path):
        return out
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            cols = [c.strip() for c in line.split(",")]
            if len(cols) < 4:
                continue
            try:
                ts = datetime.datetime.strptime(cols[0][:23], "%Y/%m/%d %H:%M:%S.%f")
            except ValueError:
                try:
                    ts = datetime.datetime.strptime(cols[0][:19], "%Y/%m/%d %H:%M:%S")
                except ValueError:
                    continue
            u = cols[2].replace("%", "").strip()
            m = cols[3].replace("MiB", "").strip()
            try:
                out.append((ts.timestamp(), int(u), int(m)))
            except ValueError:
                continue
    return out


def gpu_by_stage(gpu_samples, per_ps):
    """Attribute each GPU sample to the SHORTEST (phase, stage) span that contains it.

    The loop runs its stages one after another, so the spans of one cycle are disjoint;
    the shortest-containing-span rule only matters where a straggler process stretches
    one span across the start of the next, and it then prefers the more specific one.
    Samples inside no span (before the first sweep, between links) are not attributed.
    """
    spans = sorted(((lo, hi, k) for k, (lo, hi) in per_ps.items()),
                   key=lambda s: (s[1] - s[0]))
    per_stage, per_phase_stage, unattributed = {}, {}, 0
    for (t, u, _m) in gpu_samples:
        hit = None
        for (lo, hi, k) in spans:
            if lo <= t <= hi:
                hit = k
                break
        if hit is None:
            unattributed += 1
            continue
        stage = hit.split("/", 1)[1] if "/" in hit else hit
        for key, table in ((stage, per_stage), (hit, per_phase_stage)):
            e = table.setdefault(key, [0, 0])
            e[0] += u
            e[1] += 1
    fmt = lambda tab: {k: {"util_mean_pct": round(v[0] / v[1], 2), "samples": v[1]}
                       for k, v in tab.items()}
    return fmt(per_stage), fmt(per_phase_stage), unattributed


def samples_trained(basedir):
    """max global_step_samples over the exporter's own metadata.json files.

    train.py writes it into every exported net's metadata.json next to the model, and
    export_model_for_selfplay_9x9.sh copies that file into modelstobetested/<name>/ and
    from there the gatekeeper moves it into models/ or rejectedmodels/. Reading it there
    is exactly the counter audit_smoke.py pulls out of checkpoint.ckpt with torch, minus
    the torch (task section 13: never run torch on the login node).
    """
    best, src = None, None
    pats = [os.path.join(basedir, d, "*", "metadata.json")
            for d in ("models", "rejectedmodels", "modelstobetested", "torchmodels_toexport")]
    for pat in pats:
        for p in sorted(glob.glob(pat)):
            j = A.read_json(p, {}) or {}
            v = j.get("global_step_samples")
            if isinstance(v, (int, float)) and (best is None or v > best):
                best, src = v, p
    for p in sorted(glob.glob(os.path.join(basedir, "audit_hooks", "ckpt_*.json"))):
        j = A.read_json(p, {}) or {}
        v = j.get("global_step_samples")
        if isinstance(v, (int, float)) and (best is None or v > best):
            best, src = v, p
    return best, src


def cycle_key(name):
    """Sort key for the phase labels: cycle1 < cycle2 < ... < cycle10, others last."""
    if name.startswith("cycle"):
        try:
            return (0, int(name[5:]))
        except ValueError:
            pass
    return (1, 0, name)


# --------------------------------------------------------------------------- main
def build(basedir, args):
    W = basedir.rstrip("/")

    ps_file = args.ps_file or A.pick_ps_file(W, args.job)
    mon = A.parse_monitor(W, ps_file)
    per_ps_span, per_phase_span = stage_spans(ps_file)

    gpu_file = args.gpu_file
    if not gpu_file:
        cand = []
        if args.job:
            cand.append(os.path.join(W, "monitor", "gpu_samples-%s.csv" % args.job))
        cand += sorted(glob.glob(os.path.join(W, "monitor", "gpu_samples-*.csv")),
                       key=os.path.getmtime, reverse=True)
        cand.append(os.path.join(W, "monitor", "gpu_samples.csv"))
        gpu_file = next((c for c in cand if os.path.exists(c)), None)
    gpu = parse_gpu(gpu_file)
    gpu_stage, gpu_phase_stage, gpu_unattr = gpu_by_stage(gpu, per_ps_span)

    # ---- games and rows, per selfplay net directory --------------------------
    # A selfplay subdirectory is named after the net that played it
    # (LoadModel::findLatestModel -> modelName; "random" for the bootstrap), so the
    # real-net / random-net split IS the directory name.
    per_net = {}
    for d in sorted(glob.glob(os.path.join(W, "selfplay", "*"))):
        if not os.path.isdir(d):
            continue
        name = os.path.basename(d)
        s = A.sgfs_stats([os.path.join(d, "sgfs", "*.sgfs")])
        rep = A.npz_report(sorted(glob.glob(os.path.join(d, "tdata", "*.npz"))))
        per_net[name] = {
            "games": s["lines"], "sz9": s["sz9"], "sz_other": s["sz_other"],
            "rows": rep["rows"], "npz_files": rep["files"],
            "npz_problems": rep["problems"],
            "tdata_bytes": dir_bytes(os.path.join(d, "tdata")),
            "rows_per_game": (rep["rows"] / s["lines"]) if s["lines"] else None,
            "real_net": name != "random",
        }

    probe = A.read_json(args.probe_search, {}) if args.probe_search else {}
    probe_games = (probe or {}).get("games") or 0
    probe_rows = (probe or {}).get("rows") or 0

    real_games = sum(v["games"] for v in per_net.values() if v["real_net"]) + probe_games
    real_rows = sum(v["rows"] for v in per_net.values() if v["real_net"]) + probe_rows
    rand_games = sum(v["games"] for v in per_net.values() if not v["real_net"])
    rand_rows = sum(v["rows"] for v in per_net.values() if not v["real_net"])
    rpg_real = (real_rows / real_games) if real_games else None
    rpg_rand = (rand_rows / rand_games) if rand_games else None

    total_games = sum(v["games"] for v in per_net.values())
    total_rows = sum(v["rows"] for v in per_net.values())
    tdata_bytes = sum(v["tdata_bytes"] for v in per_net.values())
    sz_other = sum(v["sz_other"] for v in per_net.values())

    gate = A.sgfs_stats([os.path.join(W, "gatekeepersgf", "*", "*.sgfs")])

    # ---- stage timing ---------------------------------------------------------
    def stage_elapsed(stage):
        return sum(v["elapsed_s"] for k, v in mon["per_phase_stage"].items()
                   if k.endswith("/" + stage))

    st_elapsed = {s: round(stage_elapsed(s), 2) for s in STAGES}
    sp_elapsed = st_elapsed["selfplay"]
    tr_elapsed = st_elapsed["train"]

    trained, trained_src = samples_trained(W)

    # ---- per-cycle wall clock and the projection ------------------------------
    cyc = {k: round(hi - lo, 2) for k, (lo, hi) in per_phase_span.items()
           if k.startswith("cycle")}
    ordered = sorted(cyc, key=cycle_key)
    # A cycle is "full" when the sampler saw all four stages inside it: a cycle whose
    # gatekeeper had nothing to test, or that the walltime cut in half, is not a rate.
    full = [c for c in ordered
            if all(("%s/%s" % (c, s)) in mon["per_phase_stage"] for s in STAGES)]
    if args.real_net_from is not None:
        basis = [c for c in full
                 if c.startswith("cycle") and c[5:].isdigit()
                 and int(c[5:]) >= args.real_net_from]
        basis_rule = "cycles >= --real-net-from %d that carry all four stages" % args.real_net_from
    else:
        basis = full
        basis_rule = "every measured cycle that carries all four stages"
    if not basis:
        basis = ordered
        basis_rule = "every measured cycle (none carried all four stages)"
    proj_h = (sum(cyc[c] for c in basis) / len(basis) / 3600.0) if basis else None
    proj_max_h = (max(cyc[c] for c in basis) / 3600.0) if basis else None

    stage_max = {k: v["nlwp_max"] for k, v in mon["per_stage"].items()}

    note = args.note or (
        "[PRELIMINARY] measured over %s; a rate is a rate only over the cycles listed in "
        "projected_cycle_h_basis_cycles, and only the cycles whose selfplay directory is "
        "not 'random' are real-net" % W)

    thr = {
        "note": note,
        "basedir": W,
        "generated_at": datetime.datetime.now().astimezone().isoformat(),
        "ps_file": ps_file,
        "ps_scope": mon["ps_scope"],
        "ps_samples": mon["ps_samples"],
        "gpu_file": gpu_file,
        "foreign_pids_excluded": mon["foreign_pids_excluded"],
        "cycles_completed": _read_int(os.path.join(W, ".cycles_completed")),
        "chain_depth": _read_int(os.path.join(W, ".chain_depth")),

        # ---- the keys check_knobs_9x9.py asserts present (o41) ----------------
        "train_samples_total": trained,
        "train_samples_source": trained_src,
        "train_samples_per_second": (round(trained / tr_elapsed, 3)
                                     if trained and tr_elapsed else None),
        "bytes_per_row_on_disk": (round(tdata_bytes / total_rows, 2) if total_rows else None),
        "selfplay_rows_total": total_rows,
        "selfplay_games_total": total_games,
        "selfplay_games_per_hour": (round(total_games / sp_elapsed * 3600, 1)
                                    if sp_elapsed else None),
        "selfplay_rows_per_hour": (round(total_rows / sp_elapsed * 3600, 1)
                                   if sp_elapsed else None),
        "stage_elapsed_s": st_elapsed,
        "per_phase_stage": mon["per_phase_stage"],
        "probe_search": {"games": probe_games, "rows": probe_rows,
                         "full_frac": (probe or {}).get("full_frac"),
                         "full_frac_rule": (probe or {}).get("full_frac_rule")},

        # ---- P8's own list ----------------------------------------------------
        "selfplay_games_per_hour_real_net": (
            round(sum(v["games"] for v in per_net.values() if v["real_net"])
                  / _real_selfplay_elapsed(mon, per_net) * 3600, 1)
            if _real_selfplay_elapsed(mon, per_net) else None),
        "rows_per_game": rpg_real,
        "rows_per_game_real": rpg_real,
        "rows_per_game_random": rpg_rand,
        "real_games": real_games, "real_rows": real_rows,
        "random_games": rand_games, "random_rows": rand_rows,
        "per_net": per_net,
        "gatekeeper_games_total": gate["lines"],
        "gatekeeper_sz_other": gate["sz_other"],
        "selfplay_sz_other": sz_other,
        "gpu_util_mean_pct_per_stage": gpu_stage,
        "gpu_util_mean_pct_per_phase_stage": gpu_phase_stage,
        "gpu_samples_unattributed": gpu_unattr,
        "gpu_util_mean_pct": (round(sum(u for (_t, u, _m) in gpu) / len(gpu), 2)
                              if gpu else None),
        "gpu_util_max_pct": (max(u for (_t, u, _m) in gpu) if gpu else None),
        "gpu_util_samples": len(gpu),
        "peak_vram_mib": (max(m for (_t, _u, m) in gpu) if gpu else None),
        "nlwp_max_per_stage": stage_max,
        "nlwp_max_per_phase_stage": {k: v["nlwp_max"] for k, v in mon["per_phase_stage"].items()},
        "peak_rss_kb_per_stage": {k: v["rss_kb_max"] for k, v in mon["per_stage"].items()},
        "per_cycle_wall_s": {c: cyc[c] for c in ordered},
        "projected_cycle_h": (round(proj_h, 4) if proj_h is not None else None),
        "projected_cycle_h_max": (round(proj_max_h, 4) if proj_max_h is not None else None),
        "projected_cycle_h_basis": basis_rule,
        "projected_cycle_h_basis_cycles": basis,

        # ---- storage ----------------------------------------------------------
        "tdata_bytes_on_disk": tdata_bytes,
        "row_bytes_uncompressed": A.EXPECTED_ROW_BYTES,
        "shuffleddata_bytes": dir_bytes(os.path.join(W, "shuffleddata")),
        "basedir_bytes": dir_bytes(W),
        "cpus_per_task": _cpus(W),
    }
    return thr


def _real_selfplay_elapsed(mon, per_net):
    """Selfplay seconds attributable to the real-net cycles.

    Without a per-cycle net attribution this is the whole selfplay stage minus nothing,
    so it is only meaningful once every selfplay directory is a real net. It is reported
    separately from selfplay_games_per_hour, which is the all-nets rate, and is None
    while any random-net games are still in the mix.
    """
    if any(not v["real_net"] for v in per_net.values()):
        return None
    return sum(v["elapsed_s"] for k, v in mon["per_phase_stage"].items()
               if k.endswith("/selfplay")) or None


def _read_int(path):
    try:
        with open(path) as fh:
            return int(fh.read().strip())
    except Exception:
        return None


def _cpus(basedir):
    v = os.environ.get("SLURM_CPUS_PER_TASK")
    if v and v.isdigit():
        return int(v)
    j = A.read_json(os.path.join(basedir, "markers", "allocation.json"), {}) or {}
    for k in ("cpus_per_task", "cpus", "SLURM_CPUS_PER_TASK"):
        if str(j.get(k, "")).isdigit():
            return int(j[k])
    return None


def write_rows_file(path, thr):
    """The text derive_knobs.parse_rows_per_game reads (`<key> = <float>`)."""
    with open(path, "w") as fh:
        fh.write("rows_per_game -- node arxiv-1902.10565::measure_stage_throughput; claim c10\n")
        fh.write("basedir = %s\n" % thr["basedir"])
        fh.write("games = one line of a .sgfs file (cpp/program/selfplaymanager.cpp:377-378)\n")
        fh.write("rows  = sum of npz binaryInputNCHWPacked.shape[0] over tdata\n\n")
        if thr["rows_per_game_real"] is not None:
            fh.write("rows_per_game_real   = %s   (%d rows / %d games)\n"
                     % (thr["rows_per_game_real"], thr["real_rows"], thr["real_games"]))
        else:
            fh.write("# rows_per_game_real is NOT written: no real-net games measured yet.\n")
            fh.write("# check_knobs_9x9.py will refuse this file, which is the correct\n")
            fh.write("# refusal -- there is no measurement to read (obligation o41).\n")
        if thr["rows_per_game_random"] is not None:
            fh.write("rows_per_game_random = %s   (%d rows / %d games)\n"
                     % (thr["rows_per_game_random"], thr["random_rows"], thr["random_games"]))
        fh.write("\nper selfplay net directory (name = the net that played, 'random' = bootstrap):\n")
        for name, v in sorted(thr["per_net"].items()):
            fh.write("  %-28s real_net=%-5s games=%-6d rows=%-8d rows/game=%s\n"
                     % (name, v["real_net"], v["games"], v["rows"], v["rows_per_game"]))
        if thr["probe_search"]["games"]:
            fh.write("  %-28s real_net=True  games=%-6d rows=%-8d (probe_search json)\n"
                     % ("probe_search", thr["probe_search"]["games"], thr["probe_search"]["rows"]))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("basedir")
    ap.add_argument("--job", default=None, help="job tag of the o37 per-job monitor files")
    ap.add_argument("--ps-file", default=None)
    ap.add_argument("--gpu-file", default=None)
    ap.add_argument("--probe-search", default=None,
                    help="probe_search json whose games/rows count as real-net")
    ap.add_argument("--out", default=None)
    ap.add_argument("--rows-out", default=None)
    ap.add_argument("--note", default=None)
    ap.add_argument("--real-net-from", type=int, default=None,
                    help="first cycle to treat as real-net for projected_cycle_h")
    ap.add_argument("--assert-nlwp-le", type=int, default=None)
    ap.add_argument("--assert-projected-cycle-h", type=float, default=None)
    ap.add_argument("--assert-real-rows", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)

    if not os.path.isdir(a.basedir):
        print("throughput_report: BASEDIR does not exist: %s" % a.basedir, file=sys.stderr)
        return 2

    thr = build(a.basedir, a)

    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        with open(a.out, "w") as fh:
            json.dump(thr, fh, indent=1, sort_keys=True, default=str)
    rows_out = a.rows_out or (os.path.join(os.path.dirname(os.path.abspath(a.out)),
                                           "rows_per_game.txt") if a.out else None)
    if rows_out:
        os.makedirs(os.path.dirname(os.path.abspath(rows_out)), exist_ok=True)
        write_rows_file(rows_out, thr)

    if not a.quiet:
        print("throughput_report -- node arxiv-1902.10565::measure_stage_throughput")
        print("basedir            : %s" % thr["basedir"])
        print("ps file            : %s  (%s, %d rows)"
              % (thr["ps_file"], thr["ps_scope"], thr["ps_samples"]))
        print("gpu file           : %s" % thr["gpu_file"])
        print("cycles completed   : %s" % thr["cycles_completed"])
        print("")
        print("selfplay games     : %s (%s real-net, %s random-net)"
              % (thr["selfplay_games_total"], thr["real_games"], thr["random_games"]))
        print("selfplay games/h   : %s   (all nets, over %s s of selfplay)"
              % (thr["selfplay_games_per_hour"], thr["stage_elapsed_s"]["selfplay"]))
        print("selfplay games/h   : %s   (real net only)" % thr["selfplay_games_per_hour_real_net"])
        print("rows_per_game      : %s real  /  %s random"
              % (thr["rows_per_game_real"], thr["rows_per_game_random"]))
        print("bytes_per_row_disk : %s B   (uncompressed row %s B)"
              % (thr["bytes_per_row_on_disk"], thr["row_bytes_uncompressed"]))
        print("train samples      : %s  (%s)" % (thr["train_samples_total"], thr["train_samples_source"]))
        print("train samples/s    : %s   (over %s s of train)"
              % (thr["train_samples_per_second"], thr["stage_elapsed_s"]["train"]))
        print("gatekeeper games   : %s   (sz_other %s)"
              % (thr["gatekeeper_games_total"], thr["gatekeeper_sz_other"]))
        print("")
        print("stage_elapsed_s    : %s" % json.dumps(thr["stage_elapsed_s"], sort_keys=True))
        print("per_cycle_wall_s   : %s" % json.dumps(thr["per_cycle_wall_s"], sort_keys=True))
        print("projected_cycle_h  : %s   (max %s; basis: %s over %s)"
              % (thr["projected_cycle_h"], thr["projected_cycle_h_max"],
                 thr["projected_cycle_h_basis"], thr["projected_cycle_h_basis_cycles"]))
        print("nlwp_max_per_stage : %s" % json.dumps(thr["nlwp_max_per_stage"], sort_keys=True))
        print("gpu util mean/stage: %s" % json.dumps(thr["gpu_util_mean_pct_per_stage"], sort_keys=True))
        print("gpu util mean      : %s %%   max %s %%   peak vram %s MiB   (%s samples, %s unattributed)"
              % (thr["gpu_util_mean_pct"], thr["gpu_util_max_pct"], thr["peak_vram_mib"],
                 thr["gpu_util_samples"], thr["gpu_samples_unattributed"]))
        print("basedir bytes      : %s" % thr["basedir_bytes"])
        if a.out:
            print("")
            print("wrote %s" % a.out)
        if rows_out:
            print("wrote %s" % rows_out)

    # ---- assertions ----------------------------------------------------------
    fails = []
    if a.assert_nlwp_le is not None:
        over = {k: v for k, v in thr["nlwp_max_per_stage"].items() if v > a.assert_nlwp_le}
        if over:
            fails.append("nlwp_max per stage over the declared %d: %s (o03 / o39 (c))"
                         % (a.assert_nlwp_le, json.dumps(over, sort_keys=True)))
        elif not thr["nlwp_max_per_stage"]:
            fails.append("--assert-nlwp-le %d: no ps samples, so the thread budget is "
                         "UNMEASURED and cannot be asserted" % a.assert_nlwp_le)
    if a.assert_projected_cycle_h is not None:
        p = thr["projected_cycle_h"]
        if p is None:
            fails.append("--assert-projected-cycle-h: no complete cycle measured yet")
        elif p > a.assert_projected_cycle_h:
            fails.append("projected_cycle_h %.4f h > %.4f h" % (p, a.assert_projected_cycle_h))
    if a.assert_real_rows and thr["rows_per_game_real"] is None:
        fails.append("--assert-real-rows: no real-net games measured (every selfplay "
                     "directory is 'random' and no --probe-search json was given)")
    for f in fails:
        print("throughput_report FAIL: %s" % f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
