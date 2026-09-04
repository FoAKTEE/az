#!/usr/bin/env python3
"""check_knobs_9x9.py -- mission ktg-train, node arxiv-1902.10565::derive_cycle_knobs_9x9.

Closing check for the production cycle knobs.  Reads NOTHING by hand:

  * the measured numbers come from the smoke's admitted evidence
    (evidence/smoke/rows_per_game-298712.txt and throughput_smoke-298712.json --
    the frozen, content-hashed copies; obligation o37 records that the unsuffixed
    names were overwritten by attempt-2 job 299259),
  * the storage constants come from codes/data_budget/budget.env,
  * the knob values come from codes/loop/knobs_9x9.env,
  * the arithmetic comes from codes/eval/derive_knobs.py,

then it asserts the mission tolerances and, unless --no-loop, that the
${VAR:-default} block of codes/loop/synchronous_loop_9x9.sh carries exactly the
values in knobs_9x9.env.

Tolerances asserted (the work packet's four, on top of derive_knobs.py's K1-K7):

  T1  no train starvation   rows_per_cycle >= 1.2 * samples_per_epoch, at the
                            measured r AND at its 90 % lower bound r_lo
  T2  bucket holds batches  min(shuffle window, keep) >= round(E/batch) batches
                            in EVERY cycle from the first, and the per-cycle
                            bucket gain covers the epochs the cycle runs
  T3  storage projection    projected bytes after one full chain link < the
                            500 GiB cap in budget.env
  T4  threads <= cpus       worst stage thread count <= KTG_CPUS_PER_TASK

Exit 0 iff every check passes.  Usage:

  python3 results/ktg/paper_1902.10565/codes/eval/check_knobs_9x9.py [--no-loop] [--json OUT]
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))          # .../codes/eval
PAPER = os.path.dirname(os.path.dirname(HERE))             # .../paper_1902.10565
sys.path.insert(0, HERE)

import derive_knobs as dk  # noqa: E402

KNOBS_ENV = os.path.join(PAPER, "codes", "loop", "knobs_9x9.env")
LOOP_SH = os.path.join(PAPER, "codes", "loop", "synchronous_loop_9x9.sh")
BUDGET_ENV = os.path.join(PAPER, "codes", "data_budget", "budget.env")
EVID = os.path.join(PAPER, "evidence", "smoke")

# The admitted, frozen evidence first; the mutable name only as a fallback.
ROWS_FILES = ("rows_per_game-298712.txt", "rows_per_game.txt")
TPUT_FILES = ("throughput_smoke-298712.json", "throughput_smoke.json")
# Both jobs measured the two rates K7 needs. 298712 (leg-D1 probe, n=20 real-net games,
# node-wide sampler) and 299259 (n=20 + n=60, ppid-filtered sampler, no foreign pids --
# the o37-clean one). The check takes the SLOWER of each pair, so K7 can only be
# pessimistic. audit-298712.json / audit-299259.json carry the same numbers.
RATE_FILES = ("throughput_smoke-298712.json", "throughput_smoke-299259.json")


def pick(names):
    for n in names:
        p = os.path.join(EVID, n)
        if os.path.exists(p):
            return p
    raise SystemExit("none of %s found under %s" % (list(names), EVID))


def sha256(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-loop", action="store_true",
                    help="skip the synchronous_loop_9x9.sh default-wiring assertion")
    ap.add_argument("--json", default=None)
    a = ap.parse_args(argv)

    knobs = dk.read_budget_env(KNOBS_ENV)
    rows_file = pick(ROWS_FILES)
    tput_file = pick(TPUT_FILES)

    print("check_knobs_9x9 -- node arxiv-1902.10565::derive_cycle_knobs_9x9")
    print("")
    print("INPUTS (content-hashed)")
    for p in (rows_file, tput_file, KNOBS_ENV, BUDGET_ENV, LOOP_SH):
        print("  %s  %s" % (sha256(p), os.path.relpath(p, os.path.dirname(PAPER))))
    print("")

    with open(rows_file) as f:
        rows_blob = f.read()

    # Rebuild derive_knobs' argument namespace from the knob file, not from flags.
    p = dk.build_parser()
    args = p.parse_args([])
    args.rows_per_game = rows_blob
    args.rows_per_game_random = rows_blob
    args.reuse = float(knobs["MAX_TRAIN_PER_DATA"])
    args.samples_per_epoch = int(knobs["NUM_TRAIN_SAMPLES_PER_EPOCH"])
    args.games = int(knobs["NUM_GAMES_PER_CYCLE"])
    args.keep = int(knobs["SHUFFLE_KEEPROWS"])
    args.cap = int(knobs["MAX_TRAIN_SAMPLES_PER_CYCLE"])
    args.min_rows = int(knobs["SHUFFLE_MINROWS"])
    args.taper = int(knobs["TAPER_WINDOW_SCALE"])
    args.batch = int(knobs["BATCHSIZE"])
    args.shuffle_processes = int(knobs["NUM_THREADS_FOR_SHUFFLING"])
    args.cpus = int(knobs["KTG_CPUS_PER_TASK"])
    args.game_threads = int(knobs["KTG_NUM_GAME_THREADS"])
    args.throughput = tput_file

    # slowest measured rate of the two jobs -> K7 is pessimistic by construction
    gph, sps = [], []
    for name in RATE_FILES:
        fp = os.path.join(EVID, name)
        if not os.path.exists(fp):
            continue
        j = json.load(open(fp))
        if j.get("train_samples_per_second"):
            sps.append((float(j["train_samples_per_second"]), name))
        pr = j.get("probe_search", {}) or {}
        ps = (j.get("per_phase_stage", {}) or {}).get("probe_search/selfplay", {}) or {}
        stage_sp = (j.get("stage_elapsed_s", {}) or {}).get("selfplay")
        if (j.get("selfplay_games_per_hour") and stage_sp and ps.get("elapsed_s")
                and abs(float(stage_sp) - float(ps["elapsed_s"])) < 1e-6):
            # the whole selfplay stage WAS the real-net probe (attempt-2 shape):
            # the file's own games/h already counts every real-net game it played
            gph.append((float(j["selfplay_games_per_hour"]), name))
        elif pr.get("games") and ps.get("elapsed_s"):
            # mixed stage (random bootstrap + the real-net probe): pair the probe's
            # own game count with the probe pid's own elapsed time
            gph.append((3600.0 * float(pr["games"]) / float(ps["elapsed_s"]), name))
    if gph:
        args.selfplay_games_per_hour = min(gph)[0]
        print("REAL-NET SELFPLAY games/h: %s -> taking %.1f (%s)"
              % (", ".join("%.1f (%s)" % g for g in gph), min(gph)[0], min(gph)[1]))
    if sps:
        args.train_samples_per_second = min(sps)[0]
        print("TRAIN samples/s:           %s -> taking %.3f (%s)"
              % (", ".join("%.3f (%s)" % x for x in sps), min(sps)[0], min(sps)[1]))
    print("")
    args.budget_env = BUDGET_ENV
    args.window_cycles = 20
    args = dk.finish(args)

    d = dk.derive(args)
    dk.report(d)

    # ---- the tolerances, asserted here rather than inside the derivation ----
    fails = []
    E = args.samples_per_epoch
    v = d["derived"]
    print("")
    print("MISSION TOLERANCES")

    def T(name, ok, detail):
        print("  %-4s %-34s %s" % ("ok" if ok else "FAIL", name, detail))
        if not ok:
            fails.append(name)

    T("T1_no_train_starvation",
      v["rows_per_cycle"] >= 1.2 * E and v["rows_per_cycle_lower90"] >= 1.2 * E,
      "rows_per_cycle %.1f (lower90 %.1f) >= 1.2*E = %.1f" % (
          v["rows_per_cycle"], v["rows_per_cycle_lower90"], 1.2 * E))

    worst = min(d["window_by_cycle"], key=lambda w: w["rows_available"])
    T("T2_bucket_holds_batches",
      worst["batches_available"] >= v["batches_per_epoch"]
      and v["bucket_gain_lower90"] >= v["epochs_per_export"] * E,
      "worst cycle %d has %d batches >= %d needed; per-cycle bucket gain %.0f "
      "(lower90 %.0f) >= epochs*E = %d" % (
          worst["cycle"], worst["batches_available"], v["batches_per_epoch"],
          v["bucket_gain"], v["bucket_gain_lower90"], v["epochs_per_export"] * E))

    s = d["storage"]
    T("T3_storage_projection_under_budget",
      s["projected_bytes_after_one_link"] < s["hard_cap_bytes"],
      "%.3f GiB after one %d-cycle link < %.0f GiB (KTG_SCRATCH_HARD_BYTES)" % (
          s["projected_bytes_after_one_link"] / 2 ** 30, s["cycles_per_link"],
          s["hard_cap_bytes"] / 2 ** 30))

    t = d["threads"]
    T("T4_threads_le_cpus",
      t["worst_case"] <= t["cpus_per_task"],
      "worst stage %d <= KTG_CPUS_PER_TASK %d" % (t["worst_case"], t["cpus_per_task"]))

    for c in d["checks"]:
        if not c["pass_"]:
            fails.append(c["name"])

    # ---- loop wiring -------------------------------------------------------
    if not a.no_loop:
        print("")
        print("LOOP DEFAULT WIRING  (%s)" % os.path.relpath(LOOP_SH, os.path.dirname(PAPER)))
        # assert the loop against knobs_9x9.env, and knobs_9x9.env against the derivation
        for var, want in d["env"].items():
            if int(knobs[var]) != int(want):
                print("  FAIL %s: knobs_9x9.env %s != derived %s" % (var, knobs[var], want))
                fails.append("knobs_env_%s" % var)
        bad = dk.assert_loop_defaults(LOOP_SH, {k: int(v) for k, v in knobs.items()
                                                if k in d["env"]})
        for b in bad:
            print("  FAIL %s" % b)
            fails.append("loop_default")

    print("")
    print("CHECK_KNOBS_9X9: %s" % ("PASS" if not fails else "FAIL %s" % sorted(set(fails))))
    if a.json:
        d["tolerance_failures"] = sorted(set(fails))
        with open(a.json, "w") as f:
            json.dump(d, f, indent=1, sort_keys=True)
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
