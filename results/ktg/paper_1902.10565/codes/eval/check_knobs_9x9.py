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

Every MEASURED key the projections read is asserted to be PRESENT before any
derivation runs (obligation o41): derive_knobs.py has no fallback constants left,
and this script names every missing key at once instead of failing later on one of
them.  The gate's game count is a measurement too -- it is the gatekeeper sgf line
count of the audit, not a number typed here.

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
      [--throughput FILE] [--rows-file FILE] [--audit FILE]
      [--marginal-nets K --trend-nets M --horizon-nets N] [--games-per-hour-derate D]

--throughput / --rows-file / --audit replace the frozen smoke evidence with a newer
measurement (that is how measure_stage_throughput re-runs this check against its own
output); with none of them the admitted -298712 / -299259 copies are used.

Which CYCLE a stage ran in is not part of the contract.  The smoke gated in cycle 2 and
this script used to name `cycle2/gatekeeper` literally, so it refused a production file
outright (status_log.txt read 4): under the admitted export ramp (o40) the first
candidate exports at cycle 5 and the first gate runs at cycle 6, so a production run HAS
no cycle-2 gate.  A structurally absent stage is not a missing key -- the gate the file
does record is the same measurement in a different cycle -- and resolve_gate_measurement
/ resolve_phase_elapsed find it.  o41 is unchanged: a file that records no gate at all
still exits naming the key, and no constant is ever substituted.

--marginal-nets K re-derives rows/game from the throughput JSON's own per_net table as
the aggregate over the last K COMPLETE real-net selfplay directories, and
--trend-nets M / --horizon-nets N set the lower bound by carrying that value N accepted
nets forward at the least-squares rows/game slope over the last M complete directories.
The whole-run aggregate averages in the early, long-game nets and so overstates what the
NEXT cycle gets; and at production sample sizes the sampling formula r*(1-1/sqrt(n)) is
not the binding uncertainty -- drift of r as the net trains is.
"""

import argparse
import json
import os
import re
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
# The gatekeeper's game count is measured, not typed: it is the number of sgf lines the
# gate wrote, which the audit records. o41 -- derive_knobs.py used to substitute 156 here.
AUDIT_FILES = ("audit-298712.json", "audit-299259.json")

# Every MEASURED key derive_knobs.py's projections read. Asserted here, before deriving,
# so a missing measurement is reported as itself rather than as a nan downstream (o41,
# validator break attempt B3).
REQUIRED_SCALARS = ("train_samples_per_second", "bytes_per_row_on_disk",
                    "selfplay_rows_total")
# The cycle in which the SMOKE ran each stage. It is a preference, not a requirement:
# see resolve_phase_elapsed. A production run under the admitted export ramp (o40) has
# no cycle-2 gate at all, because the first candidate exports at cycle 5 and the first
# gate runs at cycle 6.
PREFERRED_PHASE = {"gatekeeper": "cycle2/gatekeeper", "shuffle": "cycle2/shuffle"}


def cycle_phases(tput, stage):
    """[(N, 'cycleN/<stage>', elapsed_s), ...] for every cycle phase of <stage>, by N."""
    out = []
    for k, v in ((tput or {}).get("per_phase_stage") or {}).items():
        head, _, tail = k.partition("/")
        if tail != stage:
            continue
        m = re.fullmatch(r"cycle([0-9]+)", head)
        if not m or (v or {}).get("elapsed_s") is None:
            continue
        out.append((int(m.group(1)), k, float(v["elapsed_s"])))
    return sorted(out)


def resolve_phase_elapsed(tput, stage):
    """The measured elapsed_s of one <stage>, tolerating a different CYCLE LAYOUT.

    o41 is untouched.  A MISSING KEY is still an exit naming the key: this returns
    (None, None) when the file records no cycle phase of <stage> at all, and the caller
    reports it.  What it stops doing is treating a STRUCTURALLY ABSENT stage as a
    missing measurement.  The smoke gated in cycle 2 and this check used to name
    'cycle2/gatekeeper' literally; under the admitted export ramp (o40) the first
    candidate exports at cycle 5 and the first gate runs at cycle 6, so a production
    throughput file HAS no cycle-2 gate to measure -- the gate it does record is the
    same measurement, taken in a different cycle.  The preferred cycle is used when the
    file has it (so a smoke file reads exactly as before), else the earliest cycle the
    file records, and which one was used is printed.
    """
    phases = cycle_phases(tput, stage)
    if not phases:
        return None, None
    want = PREFERRED_PHASE.get(stage)
    for _, k, e in phases:
        if k == want:
            return e, k
    _, k, e = phases[0]
    return e, k


def resolve_gate_measurement(tput, audit_json, audit_name):
    """(elapsed_s, games, provenance) for the gate -- a CONSISTENT MEASURED PAIR.

    Both halves of the ratio must cover the SAME gates or the seconds-per-gate-game it
    feeds derive_knobs is meaningless.  Two layouts satisfy that, and neither introduces
    a constant:

      (a) the file counted its own gate games (`gatekeeper_games_total`): pair them with
          the gate stage's own total seconds (`stage_elapsed_s['gatekeeper']`), which is
          the sum over exactly those gates.  This is the production layout, and it is
          also the larger sample by an order of magnitude.
      (b) the smoke layout: one gate wrote sgfs and the audit counted its lines, so the
          audit's count belongs to that one gate phase and is paired with it.

    Returns (None, None, None) when the file supports neither, and the caller names the
    keys as missing (o41).
    """
    games_total = (tput or {}).get("gatekeeper_games_total")
    stage_s = ((tput or {}).get("stage_elapsed_s") or {}).get("gatekeeper")
    audit_games = ((audit_json or {}).get("S4_gatekeeper_sgfs") or {}).get("lines")
    phases = cycle_phases(tput, "gatekeeper")
    if games_total and stage_s:
        return float(stage_s), float(games_total), (
            "stage_elapsed_s['gatekeeper'] = %.2f s over the %d gate stage(s) the file "
            "records (%s) / gatekeeper_games_total = %d measured gate games"
            % (float(stage_s), len(phases),
               ", ".join(k for _, k, _ in phases) or "none", int(games_total)))
    phase_s, phase_k = resolve_phase_elapsed(tput, "gatekeeper")
    if phase_s is not None and audit_games:
        return float(phase_s), float(audit_games), (
            "per_phase_stage['%s'].elapsed_s = %.2f s / %s S4_gatekeeper_sgfs.lines = %d"
            % (phase_k, phase_s, audit_name, int(audit_games)))
    return None, None, None


def resolve_real_net_rate(tput, knob_games):
    """Real-net selfplay games/h from a PRODUCTION file, or (None, None).

    A production throughput file reports one `selfplay_games_per_hour` over the whole
    selfplay stage, and that stage contains the random-net bootstrap cycles, which are
    an order of magnitude faster per game than a real-net cycle.  derive_knobs therefore
    refuses the all-net figure whenever `per_net` carries a random directory -- correctly
    -- and the smoke's probe branch does not apply either, because a production run runs
    no probe.  The real-net rate is nevertheless IN the file: the random cycles are the
    ones before the first gate (while models/ is empty every cycle plays the random net,
    o40), so the real-net seconds are the cycle selfplay phases from the first gate cycle
    on, and `real_games` counts exactly the games those phases played.

    The split is cross-checked against the file itself: random_games divided by the
    number of bootstrap cycles must be a whole number of games per cycle, and it is
    printed.  If it is not, this returns (None, None) rather than guess, and the caller
    falls through to o41.
    """
    gates = cycle_phases(tput, "gatekeeper")
    sp = cycle_phases(tput, "selfplay")
    real_games = (tput or {}).get("real_games")
    random_games = (tput or {}).get("random_games")
    if not gates or not sp or not real_games or not random_games:
        return None, None
    first_gate = gates[0][0]
    boot = [x for x in sp if x[0] < first_gate]
    real = [x for x in sp if x[0] >= first_gate]
    if not boot or not real:
        return None, None
    if int(random_games) % len(boot) != 0:
        return None, None
    real_s = sum(e for _, _, e in real)
    if real_s <= 0:
        return None, None
    return 3600.0 * float(real_games) / real_s, (
        "%d real-net games over the %d cycle selfplay phase(s) from cycle %d (the first "
        "gate) on, %.2f s; the %d bootstrap cycle(s) before it played %d random-net games, "
        "%d games/cycle, and are excluded"
        % (int(real_games), len(real), first_gate, real_s, len(boot), int(random_games),
           int(random_games) // len(boot)))


def real_net_dirs(tput):
    """[(global_step_samples, name, games, rows), ...] for the real-net selfplay dirs."""
    out = []
    for name, d in ((tput or {}).get("per_net") or {}).items():
        m = re.search(r"-s([0-9]+)-d[0-9]+$", name or "")
        if not d.get("real_net") or not m or not d.get("games"):
            continue
        out.append((int(m.group(1)), name, int(d["games"]), int(d["rows"])))
    return sorted(out)


def marginal_rows_per_game(tput, k_nets, trend_nets, horizon_nets):
    """(r, n_games, r_lo, table, prov_r, prov_lo) from the file's per-net directories.

    Nothing is typed: r is the aggregate over the last `k_nets` COMPLETE real-net
    directories and the lower bound is that value carried `horizon_nets` accepted nets
    forward at the least-squares slope of rows/game over the last `trend_nets` complete
    directories.  The newest real-net directory is excluded as INCOMPLETE -- it is the
    net that is still playing, and its npz files lag its own sgfs file, so its rows/game
    is an artefact of when the measurement was taken, not a measurement of the net.
    """
    dirs = real_net_dirs(tput)
    if len(dirs) < 2:
        raise SystemExit("check_knobs_9x9: the throughput JSON carries fewer than two "
                         "real-net per_net directories, so no marginal rows/game can be "
                         "formed from it (obligation o41: nothing is substituted).")
    complete = dirs[:-1]
    for want, flag in ((k_nets, "--marginal-nets"), (trend_nets, "--trend-nets")):
        if want > len(complete):
            raise SystemExit("check_knobs_9x9: %s %d exceeds the %d COMPLETE real-net "
                             "directories the file carries (the newest, %s, is still "
                             "being written)." % (flag, want, len(complete), dirs[-1][1]))
    tail = complete[-k_nets:]
    games = sum(x[2] for x in tail)
    rows = sum(x[3] for x in tail)
    r = rows / float(games)
    fit = complete[-trend_nets:]
    ys = [x[3] / float(x[2]) for x in fit]
    xs = list(range(len(ys)))
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    den = sum((x - mx) ** 2 for x in xs)
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den if den else 0.0
    r_lo = r + horizon_nets * slope if slope < 0 else r
    prov_r = ("aggregate over the last %d COMPLETE real-net selfplay directories "
              "(%s): %d rows / %d games"
              % (k_nets, ", ".join(x[1] for x in tail), rows, games))
    prov_lo = ("%.4f carried %d accepted nets forward at the least-squares slope of "
               "rows/game over the last %d complete directories, %+.4f rows/game per "
               "accepted net (NOT the sampling formula: over %d games its 90 %% term is "
               "%.2f %%, while the binding uncertainty is drift as the net trains)"
               % (r, horizon_nets, trend_nets, slope, games, 100.0 / games ** 0.5))
    table = [(x[1], x[2], x[3], x[3] / float(x[2])) for x in dirs]
    return r, games, r_lo, table, prov_r, prov_lo


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
    ap.add_argument("--throughput", default=None,
                    help="throughput JSON to read instead of the frozen smoke copies")
    ap.add_argument("--rows-file", default=None,
                    help="rows_per_game text to read instead of the frozen smoke copy")
    ap.add_argument("--audit", default=None,
                    help="audit JSON the gatekeeper game count is read from")
    ap.add_argument("--knobs", default=None,
                    help="knob file to put under test instead of the live "
                         "codes/loop/knobs_9x9.env. A candidate set can then be checked "
                         "without editing the file a queued chain link will source. The "
                         "loop-default assertion is skipped for a non-live knob file, "
                         "because synchronous_loop_9x9.sh is wired to the live one.")
    ap.add_argument("--marginal-nets", type=int, default=None,
                    help="re-derive rows/game from the throughput JSON's per_net table as "
                         "the aggregate over the last N COMPLETE real-net selfplay "
                         "directories, instead of the whole-run aggregate in --rows-file. "
                         "The whole-run aggregate averages in the early, long-game nets "
                         "and so overstates what the NEXT cycle gets.")
    ap.add_argument("--trend-nets", type=int, default=None,
                    help="fit the rows/game trend over the last N complete real-net "
                         "directories; required with --marginal-nets")
    ap.add_argument("--horizon-nets", type=int, default=None,
                    help="carry the marginal rows/game this many accepted nets forward "
                         "along that trend to get the lower bound; required with "
                         "--marginal-nets")
    ap.add_argument("--games-per-hour-derate", type=float, default=None,
                    help="planning derate on the measured selfplay rate; the default 0.5 "
                         "is an allowance for a 20-game probe and does not apply to a rate "
                         "measured over production cycles")
    a = ap.parse_args(argv)
    if a.marginal_nets and not (a.trend_nets and a.horizon_nets):
        raise SystemExit("check_knobs_9x9: --marginal-nets needs --trend-nets and "
                         "--horizon-nets; the lower bound is not defaulted.")

    knobs_env = os.path.abspath(a.knobs) if a.knobs else KNOBS_ENV
    if knobs_env != KNOBS_ENV:
        a.no_loop = True
        print("KNOB FILE UNDER TEST: %s (not the live knobs_9x9.env; the loop-default "
              "assertion is skipped)" % knobs_env)
    knobs = dk.read_budget_env(knobs_env)
    rows_file = a.rows_file or pick(ROWS_FILES)
    tput_file = a.throughput or pick(TPUT_FILES)
    audit_file = a.audit or pick(AUDIT_FILES)
    rate_files = [a.throughput] if a.throughput else list(RATE_FILES)

    print("check_knobs_9x9 -- node arxiv-1902.10565::derive_cycle_knobs_9x9")
    print("")
    print("INPUTS (content-hashed)")
    for p in (rows_file, tput_file, audit_file, knobs_env, BUDGET_ENV, LOOP_SH):
        print("  %s  %s" % (sha256(p), os.path.relpath(p, os.path.dirname(PAPER))))
    print("")

    # ---- o41: every measured key must be present BEFORE anything is derived --------
    tput_json = json.load(open(tput_file))
    audit_json = json.load(open(audit_file))
    audit_name = os.path.basename(audit_file)

    missing = [k for k in REQUIRED_SCALARS if tput_json.get(k) is None]

    gate_s, gate_games, gate_prov = resolve_gate_measurement(tput_json, audit_json,
                                                             audit_name)
    if gate_s is None:
        missing.append("gatekeeper_games_total with stage_elapsed_s['gatekeeper'], or "
                       "per_phase_stage['cycle<N>/gatekeeper'].elapsed_s with the audit's "
                       "S4_gatekeeper_sgfs.lines")
    shuffle_s, shuffle_phase = resolve_phase_elapsed(tput_json, "shuffle")
    if shuffle_s is None:
        missing.append("per_phase_stage['cycle<N>/shuffle'].elapsed_s")
    n_cycle_selfplay = len(cycle_phases(tput_json, "selfplay"))
    if not n_cycle_selfplay:
        missing.append("per_phase_stage['cycle<N>/selfplay'] (the cycles selfplay_rows_total "
                       "is spread over)")

    # the real-net selfplay rate, in the order the layouts appear
    probe = tput_json.get("probe_search") or {}
    ps = ((tput_json.get("per_phase_stage") or {}).get("probe_search/selfplay") or {})
    prod_gph, prod_prov = resolve_real_net_rate(tput_json, int(knobs["NUM_GAMES_PER_CYCLE"]))
    has_rate = (bool(tput_json.get("selfplay_games_per_hour"))
                or bool(probe.get("games") and ps.get("elapsed_s"))
                or prod_gph is not None)
    if not has_rate:
        missing.append("selfplay_games_per_hour (or probe_search.games with "
                       "per_phase_stage['probe_search/selfplay'].elapsed_s, or cycle "
                       "selfplay phases with real_games/random_games)")

    if missing:
        raise SystemExit(
            "check_knobs_9x9: %s is missing the measured key(s) %s. derive_knobs.py has no "
            "fallback constants (obligation o41), so the projections cannot be evaluated: "
            "re-run the measurement, or pass --throughput with a file that carries them."
            % (os.path.relpath(tput_file, os.path.dirname(PAPER)), ", ".join(missing)))
    print("MEASURED KEYS PRESENT: %s" % ", ".join(REQUIRED_SCALARS))
    print("GATE (measured pair): %s -> %.5f s per gate game" % (gate_prov, gate_s / gate_games))
    print("SHUFFLE (measured):   per_phase_stage['%s'].elapsed_s = %.2f s, over the %d cycle "
          "selfplay phase(s) selfplay_rows_total is spread across"
          % (shuffle_phase, shuffle_s, n_cycle_selfplay))
    print("")

    with open(rows_file) as f:
        rows_blob = f.read()

    # Rebuild derive_knobs' argument namespace from the knob file, not from flags.
    p = dk.build_parser()
    args = p.parse_args([])
    args.rows_per_game = rows_blob
    args.rows_per_game_random = rows_blob
    args.source_label = os.path.relpath(tput_file, os.path.dirname(PAPER))

    if a.marginal_nets:
        r_marg, n_marg, r_lo, table, prov_r, prov_lo = marginal_rows_per_game(
            tput_json, a.marginal_nets, a.trend_nets, a.horizon_nets)
        print("ROWS/GAME BY SELFPLAY NET DIRECTORY (throughput JSON per_net; the last row "
              "is the net still playing and is NOT used)")
        for name, g, rws, rg in table:
            print("  %-30s games %6d  rows %8d  rows/game %7.3f%s"
                  % (name, g, rws, rg, "   <- incomplete" if name == table[-1][0] else ""))
        print("  marginal r    = %.4f   %s" % (r_marg, prov_r))
        print("  lower bound   = %.4f   %s" % (r_lo, prov_lo))
        print("  whole-run aggregate in %s = %s (NOT used: it averages in the early "
              "long-game nets)"
              % (os.path.basename(rows_file), tput_json.get("rows_per_game_real")))
        print("")
        args.rows_per_game = "%.6f" % r_marg
        args.rows_per_game_lower = r_lo
        args.rows_lower_source = prov_lo
        args.n_games_real = n_marg
        if tput_json.get("random_games"):
            args.n_games_random = int(tput_json["random_games"])
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
    for name in rate_files:
        fp = name if os.path.isabs(name) or os.sep in name else os.path.join(EVID, name)
        if not os.path.exists(fp):
            continue
        j = json.load(open(fp))
        if j.get("train_samples_per_second"):
            sps.append((float(j["train_samples_per_second"]), os.path.basename(name)))
        pr = j.get("probe_search", {}) or {}
        ps = (j.get("per_phase_stage", {}) or {}).get("probe_search/selfplay", {}) or {}
        stage_sp = (j.get("stage_elapsed_s", {}) or {}).get("selfplay")
        if (j.get("selfplay_games_per_hour") and stage_sp and ps.get("elapsed_s")
                and abs(float(stage_sp) - float(ps["elapsed_s"])) < 1e-6):
            # the whole selfplay stage WAS the real-net probe (attempt-2 shape):
            # the file's own games/h already counts every real-net game it played
            gph.append((float(j["selfplay_games_per_hour"]), os.path.basename(name)))
        elif pr.get("games") and ps.get("elapsed_s"):
            # mixed stage (random bootstrap + the real-net probe): pair the probe's
            # own game count with the probe pid's own elapsed time
            gph.append((3600.0 * float(pr["games"]) / float(ps["elapsed_s"]),
                        os.path.basename(name)))
    if not gph and prod_gph is not None:
        # a production file: no probe, and its own selfplay_games_per_hour is all-net
        gph.append((prod_gph, "real-net cycles of %s" % os.path.basename(tput_file)))
        print("REAL-NET SELFPLAY games/h: %.1f -- %s" % (prod_gph, prod_prov))
        print("  the same file's all-net selfplay_games_per_hour = %s is %.2fx this, "
              "because it credits the fast random-net bootstrap cycles; every cycle from "
              "here on is real-net, so the real-net rate is the one that projects"
              % (tput_json.get("selfplay_games_per_hour"),
                 float(tput_json.get("selfplay_games_per_hour") or 0) / prod_gph))
        if a.games_per_hour_derate is None:
            # The 0.5 derate is DESIGN's allowance for a 20-game probe run with
            # logSearchInfo writing a multi-MB log outside a real cycle. This rate was
            # measured over production cycles, so the allowance has nothing left to
            # cover and applying it would halve a measurement.
            args.games_per_hour_derate = 1.0
            print("  planning derate 1.0: this is a production rate, not a probe "
                  "(the 0.5 probe allowance does not apply)")
    if a.games_per_hour_derate is not None:
        args.games_per_hour_derate = float(a.games_per_hour_derate)
    if len(gph) > 1:
        print("REAL-NET SELFPLAY games/h: %s -> taking %.1f (%s)"
              % (", ".join("%.1f (%s)" % g for g in gph), min(gph)[0], min(gph)[1]))
    if gph:
        args.selfplay_games_per_hour = min(gph)[0]
    if sps:
        args.train_samples_per_second = min(sps)[0]
        print("TRAIN samples/s:           %s -> taking %.3f (%s)"
              % (", ".join("%.3f (%s)" % x for x in sps), min(sps)[0], min(sps)[1]))
    print("")
    args.budget_env = BUDGET_ENV
    args.window_cycles = 20
    # o41: the remaining measured inputs, all of them read from evidence, none defaulted.
    # The gate pair and the shuffle phase are RESOLVED above rather than named by cycle,
    # so a run whose export ramp puts its first gate at cycle 6 is measured, not refused.
    args.gate_games_measured = float(gate_games)
    args.gate_elapsed_s = float(gate_s)
    args.bytes_per_row = None          # taken from --throughput, asserted present above
    args.shuffle_elapsed_s = float(shuffle_s)
    # selfplay_rows_total covers every cycle the file records, not the smoke's two.
    args.shuffle_rows_measured = (float(tput_json["selfplay_rows_total"])
                                  / n_cycle_selfplay)
    args.first_accept_cycle = None     # o40: the optimistic case, the cycle after the export
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
