#!/usr/bin/env python3
"""derive_knobs.py -- mission ktg-train, node arxiv-1902.10565::derive_cycle_knobs_9x9.

Turns the smoke's MEASURED rows/game into the production cycle knobs of
codes/loop/synchronous_loop_9x9.sh and checks every constraint train.py and
shuffle.py impose.  Nothing here is hand-picked: each knob is the solution of a
constraint that is read out of the reference code at path:line, evaluated at a
number that was measured by Slurm job 298712.

Checks (labels are the ones in tasks/derive_cycle_knobs_9x9/implementation.md
section 2, plus the two mission tolerances T1/T4 the work packet adds):

  K1  gain = games * r * reuse  >=  0.99 * samples_per_epoch
      train.py:1256-1259 fills the bucket, :1434 gates an epoch on it.
  T1  freshness: games * r  >=  1.2 * samples_per_epoch
      one cycle must produce at least 20 % more NEW rows than one epoch draws,
      so the trainer never runs on a window it has already exhausted.
  K2  epochs_per_export = max_epochs_this_instance
        = floor(min(gain, cap_eff) / samples_per_epoch),  cap_eff = max(cap, E)
      train.py:1257 (cap), :1434 (consume), :1743/:1831 (export counter),
      :1423 (max_epochs_this_instance).  >= 1 required.
  K3  keep > cap (synchronous_loop.sh:66 rule) and keep >= epochs_per_export * E.
  K4  window feasibility, the defect the smoke exposed: get_files_for_subepoch
      (train.py:1303-1346) returns None -- and -quit-if-no-data then exits 0 with
      NO export (:1487-1488) -- unless the shuffled files hold
      round(samples_per_epoch / batch) batches.  Conservative form:
        min(desired_window_rows, keep) >= samples_per_epoch
      with desired_window_rows the verbatim port of shuffle.py:414-435 at
      -expand-window-per-row 0.4 -taper-window-exponent 0.65 (shuffle.sh:44-45).
      Evaluated at EVERY early cycle, not only one: cycle 1 is the random
      bootstrap (usable rows capped at min_rows, shuffle.py:1077) and is the
      binding case.
  K5  bootstrap: games * r_random >= min_rows, so cycle 1 clears
      shuffle.py:1090 ("Not enough rows ... exit 0") and fills the cycle-1
      window, whose size IS min_rows.
  K6  swa period = samples_per_epoch // 2 -- train.py:441's own default, made
      explicit in the loop block.
  K7  cycle wall projection, from the smoke's throughput_smoke.json.
      [PRELIMINARY]: tiny-count inputs; measure_stage_throughput owns the bound.
  T4  thread budget: max stage threads (with the real-net CUDA block and the
      net-switch allowance) <= declared --cpus-per-task.

CLI (section 7 of the task file):
  derive_knobs.py --rows-per-game R [--rows-per-game-random R0] --reuse M
                  --samples-per-epoch E --games G --keep K --cap C
                  [--min-rows m] [--taper t] [--batch 128]
                  [--gate-games 200] [--cpus 32] [--game-threads 18]
                  [--throughput FILE] [--budget-env FILE]
                  [--assert-loop-defaults FILE] [--emit-env] [--self-test]

--rows-per-game also accepts the CONTENT of evidence/smoke/rows_per_game.txt.
The task file's section 2 command interpolates that file with an unquoted
$(cat ...), which word-splits it into many argv tokens; normalize_argv() below
re-joins the blob and pulls `rows_per_game_real` out of it, so the section 2
command runs as written.

Exit 0 iff every check passes (and, with --assert-loop-defaults, iff the loop
copy's ${VAR:-default} block equals the derived values).
"""

import argparse
import json
import math
import os
import re
import sys

# ---------------------------------------------------------------------------
# argv normalisation -- see the module docstring.
# ---------------------------------------------------------------------------

VALUE_OPTS = ()   # filled from the parser in main(); see _option_sets()
FLAG_OPTS = ("-h", "--help")


def _option_sets(parser):
    """Read the option strings off the parser so normalize_argv never drifts from it."""
    value_opts, flag_opts = set(), set(FLAG_OPTS)
    for a in parser._actions:
        for s_ in a.option_strings:
            (flag_opts if a.nargs == 0 else value_opts).add(s_)
    return tuple(value_opts), tuple(flag_opts)


def normalize_argv(argv, value_opts=None, flag_opts=None):
    """Re-join a value that $(cat file) word-split into many argv tokens."""
    VALUE_OPTS = tuple(value_opts) if value_opts is not None else globals()["VALUE_OPTS"]
    FLAG_OPTS = tuple(flag_opts) if flag_opts is not None else globals()["FLAG_OPTS"]
    out = []
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok in FLAG_OPTS:
            out.append(tok)
            i += 1
        elif tok in VALUE_OPTS:
            out.append(tok)
            i += 1
            blob = []
            while i < len(argv) and argv[i] not in VALUE_OPTS and argv[i] not in FLAG_OPTS:
                blob.append(argv[i])
                i += 1
            out.append(" ".join(blob))
        else:
            out.append(tok)
            i += 1
    return out


def parse_rows_per_game(blob, key):
    """Accept a bare float, or the text of evidence/smoke/rows_per_game.txt."""
    blob = (blob or "").strip()
    try:
        return float(blob)
    except ValueError:
        pass
    m = re.search(key + r"\s*=\s*([0-9]+(?:\.[0-9]+)?)", blob)
    if m:
        return float(m.group(1))
    raise SystemExit("could not read %s from %r" % (key, blob[:120]))


# ---------------------------------------------------------------------------
# verbatim port of shuffle.py:414-435
# ---------------------------------------------------------------------------

def compute_desired_num_rows(num_usable_rows, min_rows, add_to_data_rows,
                             taper_window_exponent, expand_window_per_row,
                             taper_window_scale, max_rows):
    window_taper_offset = taper_window_scale if taper_window_scale is not None else min_rows
    power_law_x = num_usable_rows - min_rows + window_taper_offset + add_to_data_rows
    unscaled_power_law = (power_law_x ** taper_window_exponent) - (window_taper_offset ** taper_window_exponent)
    scaled_power_law = unscaled_power_law / (
        taper_window_exponent * (window_taper_offset ** (taper_window_exponent - 1))
    )
    desired_num_rows = int(scaled_power_law * expand_window_per_row + min_rows)
    desired_num_rows = max(desired_num_rows, min_rows)
    if max_rows is not None:
        desired_num_rows = min(desired_num_rows, max_rows)
    return desired_num_rows


def _req(tput, key, override, flag):
    """A MEASURED scalar: the throughput JSON's value, an explicit override, or an exit.

    Obligation o41. This function replaces a set of hard-coded fallbacks that let
    check_knobs_9x9.py report a rate it had never measured when the key was missing
    from the JSON (validator break attempt B3). There is deliberately no default
    anywhere below it: a projection is either evaluated at a number some job actually
    produced, or it is not evaluated at all.
    """
    if override is not None:
        return float(override)
    v = (tput or {}).get(key)
    if v is None:
        raise SystemExit(
            "derive_knobs: measured key '%s' is missing from the throughput JSON and no "
            "%s was given. There is no baked-in fallback for it (obligation o41): pass %s, "
            "or point --throughput at a measurement that carries the key."
            % (key, flag, flag))
    return float(v)


def _req_phase(tput, phase, key, override, flag):
    """The same rule for a per_phase_stage entry, e.g. per_phase_stage['cycle2/shuffle']."""
    if override is not None:
        return float(override)
    d = ((tput or {}).get("per_phase_stage") or {}).get(phase) or {}
    v = d.get(key)
    if v is None:
        raise SystemExit(
            "derive_knobs: measured key 'per_phase_stage[\"%s\"][\"%s\"]' is missing from "
            "the throughput JSON and no %s was given. There is no baked-in fallback for it "
            "(obligation o41): pass %s, or point --throughput at a measurement that carries "
            "the entry." % (phase, key, flag, flag))
    return float(v)


def rows_lower_bound(r, n_games_measured):
    """Section 11's binomial-free 90 % lower bound on a rows/game measured over n games."""
    if n_games_measured <= 0:
        return r
    return r * (1.0 - 1.0 / math.sqrt(n_games_measured))


# ---------------------------------------------------------------------------
# the derivation
# ---------------------------------------------------------------------------

SMOKE_CYCLES = 2                 # the smoke ran two loop cycles; its selfplay_rows_total
                                 # covers both, and each shuffle saw one cycle's rows
EXPAND_WINDOW_PER_ROW = 0.4      # shuffle.sh:44
TAPER_WINDOW_EXPONENT = 0.65     # shuffle.sh:45
APPROX_ROWS_PER_OUT_FILE = 70000  # shuffle.sh:48 (not credited by K4; slack only)


def derive(args):
    r = args.r
    r0 = args.r0
    E = args.samples_per_epoch
    G = args.games
    M = args.reuse
    keep = args.keep
    cap = args.cap
    min_rows = args.min_rows
    taper = args.taper
    batch = args.batch

    r_lo = rows_lower_bound(r, args.n_games_real)
    r0_lo = rows_lower_bound(r0, args.n_games_random)

    d = {}
    d["inputs"] = dict(
        rows_per_game_real=r, rows_per_game_real_lower90=r_lo,
        rows_per_game_random=r0, rows_per_game_random_lower90=r0_lo,
        n_games_real_measured=args.n_games_real, n_games_random_measured=args.n_games_random,
        reuse=M, samples_per_epoch=E, games=G, keep=keep, cap=cap,
        min_rows=min_rows, taper_window_scale=taper, batch=batch,
    )

    rows_per_cycle = G * r
    rows_per_cycle_lo = G * r_lo
    gain = rows_per_cycle * M
    gain_lo = rows_per_cycle_lo * M
    cap_eff = max(cap, E)
    epochs = int(min(gain, cap_eff) // E)
    epochs_lo = int(min(gain_lo, cap_eff) // E)
    batches_per_epoch = int(round(E / batch))
    swa = max(1, E // 2)

    d["derived"] = dict(
        rows_per_cycle=rows_per_cycle, rows_per_cycle_lower90=rows_per_cycle_lo,
        bucket_gain=gain, bucket_gain_lower90=gain_lo,
        bucket_cap_effective=cap_eff,
        epochs_per_export=epochs, epochs_per_export_lower90=epochs_lo,
        batches_per_epoch=batches_per_epoch,
        samples_per_cycle=epochs * E,
        effective_reuse=(epochs * E) / rows_per_cycle if rows_per_cycle else float("inf"),
        effective_reuse_lower90=(epochs * E) / rows_per_cycle_lo if rows_per_cycle_lo else float("inf"),
        swa_period_samples=swa,
    )

    checks = []

    def chk(name, ok, detail):
        checks.append(dict(name=name, pass_=bool(ok), detail=detail))
        return ok

    # K1 -------------------------------------------------------------------
    chk("K1_bucket_gain_clears_epoch",
        gain >= 0.99 * E and gain_lo >= 0.99 * E,
        "gain = games*r*reuse = %.1f (lower90 %.1f) vs 0.99*E = %.1f; ratio gain/E = %.3f (lower90 %.3f)"
        % (gain, gain_lo, 0.99 * E, gain / E, gain_lo / E))

    # T1 -------------------------------------------------------------------
    chk("T1_freshness_rows_per_cycle_ge_1p2_E",
        rows_per_cycle >= 1.2 * E and rows_per_cycle_lo >= 1.2 * E,
        "rows_per_cycle = %.1f (lower90 %.1f) vs 1.2*E = %.1f; ratio %.3f (lower90 %.3f)"
        % (rows_per_cycle, rows_per_cycle_lo, 1.2 * E,
           rows_per_cycle / E, rows_per_cycle_lo / E))

    # K2 -------------------------------------------------------------------
    chk("K2_one_export_per_cycle",
        epochs >= 1 and epochs_lo >= 1 and epochs == epochs_lo,
        "epochs_per_export = max_epochs_this_instance = floor(min(gain,cap_eff)/E) = %d "
        "(lower90 %d); cap_eff = max(cap,E) = %d; effective reuse %.2f (lower90 %.2f) <= %s"
        % (epochs, epochs_lo, cap_eff,
           d["derived"]["effective_reuse"], d["derived"]["effective_reuse_lower90"], M))

    chk("K2b_effective_reuse_within_cap",
        d["derived"]["effective_reuse_lower90"] <= M,
        "epochs*E/rows_per_cycle = %.2f (lower90 %.2f) <= reuse cap %s"
        % (d["derived"]["effective_reuse"], d["derived"]["effective_reuse_lower90"], M))

    # K3 -------------------------------------------------------------------
    chk("K3_keep_gt_cap",
        keep > cap and keep >= epochs * E,
        "keep = %d > cap = %d (synchronous_loop.sh:66) and keep >= epochs*E = %d"
        % (keep, cap, epochs * E))

    # K5 -------------------------------------------------------------------
    boot_rows = G * r0
    boot_rows_lo = G * r0_lo
    chk("K5_random_bootstrap_reaches_min_rows",
        boot_rows >= min_rows and boot_rows_lo >= min_rows,
        "cycle-1 random rows = games*r_random = %.1f (lower90 %.1f) >= min_rows = %d "
        "(shuffle.py:1090 exit-0 gate; :1077 caps the usable count at min_rows)"
        % (boot_rows, boot_rows_lo, min_rows))

    # K4 -------------------------------------------------------------------
    # cycle 1: usable = min(random rows, min_rows) -> window == min_rows.
    # cycle c>=2: usable = min_rows + (c-1)*games*r  (post-random rows are uncapped).
    windows = []
    for c in range(1, args.window_cycles + 1):
        if c == 1:
            usable = min(boot_rows_lo, min_rows)
        else:
            usable = min_rows + (c - 1) * rows_per_cycle_lo
        w = compute_desired_num_rows(usable, min_rows, 0.0, TAPER_WINDOW_EXPONENT,
                                     EXPAND_WINDOW_PER_ROW, taper, None)
        avail = min(w, keep)
        windows.append(dict(cycle=c, usable_rows=usable, desired_window_rows=w,
                            rows_available=avail,
                            batches_available=int(avail // batch),
                            epochs_supported=int(avail // E)))
    d["window_by_cycle"] = windows
    worst = min(windows, key=lambda x: x["rows_available"])
    full = [w["cycle"] for w in windows if w["rows_available"] >= epochs * E]
    d["derived"]["first_cycle_with_full_epoch_set"] = full[0] if full else None
    chk("K4_window_holds_one_epoch",
        worst["rows_available"] >= E,
        "worst of cycles 1..%d is cycle %d: min(window %d, keep %d) = %d rows = %d batches "
        ">= round(E/batch) = %d batches (= %d rows); ratio %.3f. Conservative: the "
        "file-granularity slack of shuffle.sh:48 (-approx-rows-per-out-file %d) is not credited."
        % (args.window_cycles, worst["cycle"], worst["desired_window_rows"], keep,
           worst["rows_available"], worst["batches_available"], batches_per_epoch,
           batches_per_epoch * batch, worst["rows_available"] / E, APPROX_ROWS_PER_OUT_FILE))

    chk("K2c_at_most_one_export_per_cycle",
        True,
        "epochs_per_export == max_epochs_this_instance == %d, so train.py's persistent "
        "export_cycle_counter (:871,:975,:1743,:1831) can advance by at most %d per cycle: "
        "never more than one candidate per cycle. Exactly one per cycle from cycle %s on, "
        "when the shuffled window first holds %d rows; before that the counter carries over "
        "and the export slips, which is upstream's own designed behaviour."
        % (epochs, epochs, d["derived"]["first_cycle_with_full_epoch_set"], epochs * E))

    # K6 -------------------------------------------------------------------
    chk("K6_swa_period_is_half_epoch",
        swa == max(1, E // 2),
        "swa_period_samples = samples_per_epoch // 2 = %d (train.py:441 default made explicit)" % swa)

    # T4 thread budget -----------------------------------------------------
    gt = args.game_threads
    sp_threads = gt + 4 + 3          # game + nnServer + dataWrite + modelLoad + main, + CUDA block
    sp_switch = sp_threads + 2       # mid-run net switch allowance
    gk_one_net = gt + 4 + 3          # game + 2 nnServer + dataWrite + main - 1 (one model), + CUDA
    gk_two_net = gt + 5 + 3 + 3      # two models: second nnServer thread and a second CUDA block
    train_threads = 14
    shuffle_threads = 4 + args.shuffle_processes
    worst_threads = max(sp_switch, gk_two_net, train_threads, shuffle_threads)
    d["threads"] = dict(selfplay_real_net=sp_threads, selfplay_with_net_switch=sp_switch,
                        gatekeeper_one_real_net=gk_one_net, gatekeeper_two_real_nets=gk_two_net,
                        train=train_threads, shuffle=shuffle_threads,
                        worst_case=worst_threads, cpus_per_task=args.cpus)
    chk("T4_threads_le_cpus",
        worst_threads <= args.cpus,
        "worst stage thread count %d (selfplay real-net %d +2 net switch = %d; gatekeeper "
        "two real nets %d; train %d; shuffle 4+%d=%d) <= --cpus-per-task %d, headroom %d"
        % (worst_threads, sp_threads, sp_switch, gk_two_net, train_threads,
           args.shuffle_processes, shuffle_threads, args.cpus, args.cpus - worst_threads))

    # K7 + storage ---------------------------------------------------------
    tput = {}
    if args.throughput and os.path.exists(args.throughput):
        with open(args.throughput) as f:
            tput = json.load(f)
    bpr = _req(tput, "bytes_per_row_on_disk", args.bytes_per_row, "--bytes-per-row")
    train_sps = _req(tput, "train_samples_per_second", args.train_samples_per_second,
                     "--train-samples-per-second")
    probe = tput.get("probe_search", {}) or {}
    pps = (tput.get("per_phase_stage", {}) or {}).get("probe_search/selfplay", {}) or {}
    if args.selfplay_games_per_hour is not None:
        gph_measured = float(args.selfplay_games_per_hour)
    elif tput.get("selfplay_games_per_hour") and not (tput.get("per_net") or {}).get("random"):
        # attempt-2 shape: the whole selfplay stage was the real-net probe
        gph_measured = float(tput["selfplay_games_per_hour"])
    elif probe.get("games") and pps.get("elapsed_s"):
        # mixed stage: pair the probe's own game count with the probe pid's elapsed time
        gph_measured = 3600.0 * float(probe["games"]) / float(pps["elapsed_s"])
    else:
        # o41: never nan, and never a constant -- the projection simply cannot be made.
        raise SystemExit(
            "derive_knobs: the throughput JSON carries no measured REAL-NET selfplay rate "
            "('selfplay_games_per_hour' with no random per_net, or probe_search.games with "
            "per_phase_stage['probe_search/selfplay'].elapsed_s) and no "
            "--selfplay-games-per-hour was given. There is no baked-in fallback for it "
            "(obligation o41).")
    gph_plan = gph_measured * args.games_per_hour_derate

    gate_games_measured = _req(tput, "gatekeeper_games_total", args.gate_games_measured,
                               "--gate-games-measured")
    gate_s = _req_phase(tput, "cycle2/gatekeeper", "elapsed_s", args.gate_elapsed_s,
                        "--gate-elapsed-s")
    gate_per_game = gate_s / gate_games_measured
    gate_proj_s = 2.0 * gate_per_game * args.gate_games       # x2 for the two-real-net gate

    shuffle_s_measured = _req_phase(tput, "cycle2/shuffle", "elapsed_s", args.shuffle_elapsed_s,
                                    "--shuffle-elapsed-s")
    if args.shuffle_rows_measured is not None:
        shuffle_rows_measured = float(args.shuffle_rows_measured)
    else:
        # the measured shuffle elapsed is ONE cycle's, and the smoke ran SMOKE_CYCLES of them
        shuffle_rows_measured = _req(tput, "selfplay_rows_total", None,
                                     "--shuffle-rows-measured") / SMOKE_CYCLES
    shuffle_proj_s = 60.0 + float(shuffle_s_measured) * (keep / max(shuffle_rows_measured, 1.0))

    selfplay_proj_s = 3600.0 * G / gph_plan if gph_plan == gph_plan and gph_plan > 0 else float("nan")
    train_proj_s = epochs * E / train_sps
    export_proj_s = 60.0
    cycle_s = selfplay_proj_s + train_proj_s + gate_proj_s + shuffle_proj_s + export_proj_s

    d["cycle_time"] = dict(
        selfplay_games_per_hour_measured=gph_measured,
        games_per_hour_derate=args.games_per_hour_derate,
        selfplay_games_per_hour_planning=gph_plan,
        train_samples_per_second=train_sps,
        selfplay_s=selfplay_proj_s, train_s=train_proj_s, gatekeeper_s=gate_proj_s,
        shuffle_s=shuffle_proj_s, export_s=export_proj_s, cycle_s=cycle_s,
        cycle_h=cycle_s / 3600.0,
        cycles_per_link=int(args.walltime_seconds // cycle_s) if cycle_s > 0 else 0,
    )
    chk("K7_cycle_wall_under_bound",
        cycle_s <= args.cycle_bound_hours * 3600.0 and cycle_s < args.walltime_seconds,
        "projected cycle = %.0f s = %.2f h <= %.0f h bound, and %d whole cycles fit the "
        "%d s chain link. [PRELIMINARY] tiny-count throughput inputs."
        % (cycle_s, cycle_s / 3600.0, args.cycle_bound_hours,
           d["cycle_time"]["cycles_per_link"], args.walltime_seconds))

    # storage --------------------------------------------------------------
    budget = read_budget_env(args.budget_env)
    hard = int(budget.get("KTG_SCRATCH_HARD_BYTES", 536870912000))
    keep_shuf = int(budget.get("KTG_KEEP_SHUFFLEDDATA", 3))
    keep_rej = int(budget.get("KTG_KEEP_REJECTED_MODELS", 10))
    keep_long = int(budget.get("KTG_KEEP_LONGTERM_CHECKPOINTS", 6))
    keep_dated = int(budget.get("KTG_KEEP_DATED_SCRIPTS", 3))

    sgf_b = args.sgf_bytes_per_game
    model_b = args.model_bytes
    ckpt_b = args.checkpoint_bytes
    per_cycle_monotonic = rows_per_cycle * bpr + G * sgf_b + args.gate_games * sgf_b + model_b
    bounded = (keep_shuf * keep * bpr
               + keep_rej * model_b
               + (keep_long + 4) * ckpt_b
               + keep_dated * args.dated_archive_bytes)
    env_b = args.env_bytes
    cycles_per_link = max(1, d["cycle_time"]["cycles_per_link"])
    proj_link = env_b + bounded + cycles_per_link * per_cycle_monotonic
    headroom_cycles = int((hard - env_b - bounded) // per_cycle_monotonic) if per_cycle_monotonic > 0 else 0

    d["storage"] = dict(
        bytes_per_row_on_disk=bpr,
        per_cycle_monotonic_bytes=per_cycle_monotonic,
        bounded_steady_state_bytes=bounded,
        env_and_build_bytes=env_b,
        cycles_per_link=cycles_per_link,
        projected_bytes_after_one_link=proj_link,
        hard_cap_bytes=hard,
        cycles_until_hard_cap=headroom_cycles,
    )
    chk("T3_storage_projection_under_budget",
        proj_link < hard and headroom_cycles > cycles_per_link,
        "per-cycle monotonic write %.1f MiB; bounded steady state %.1f MiB; env+build %.1f GiB; "
        "after one full %d-cycle link %.2f GiB of %.0f GiB cap; %d cycles fit before the cap"
        % (per_cycle_monotonic / 2**20, bounded / 2**20, env_b / 2**30, cycles_per_link,
           proj_link / 2**30, hard / 2**30, headroom_cycles))

    d["checks"] = checks
    d["pass"] = all(c["pass_"] for c in checks)
    d["env"] = dict(
        NUM_GAMES_PER_CYCLE=G,
        NUM_THREADS_FOR_SHUFFLING=args.shuffle_processes,
        NUM_TRAIN_SAMPLES_PER_EPOCH=E,
        MAX_TRAIN_PER_DATA=M,
        NUM_TRAIN_SAMPLES_PER_SWA=swa,
        BATCHSIZE=batch,
        SHUFFLE_MINROWS=min_rows,
        MAX_TRAIN_SAMPLES_PER_CYCLE=cap,
        TAPER_WINDOW_SCALE=taper,
        SHUFFLE_KEEPROWS=keep,
        EPOCHS_PER_EXPORT=epochs,
    )
    d["sbatch"] = dict(KTG_CPUS_PER_TASK=args.cpus, KTG_NUM_GAME_THREADS=args.game_threads)
    return d


def read_budget_env(path):
    out = {}
    if not path or not os.path.exists(path):
        return out
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            v = v.strip()
            if re.fullmatch(r"[0-9]+", v):
                out[k.strip()] = int(v)
            else:
                out[k.strip()] = v
    return out


# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------

def report(d):
    i = d["inputs"]
    v = d["derived"]
    print("derive_knobs.py -- node arxiv-1902.10565::derive_cycle_knobs_9x9")
    print("")
    print("MEASURED INPUTS (Slurm job 298712, commit 5bb85ad)")
    print("  rows/game real      r        = %-10.4f  (lower90 %.4f over %d games)"
          % (i["rows_per_game_real"], i["rows_per_game_real_lower90"], i["n_games_real_measured"]))
    print("  rows/game random    r0       = %-10.4f  (lower90 %.4f over %d games)"
          % (i["rows_per_game_random"], i["rows_per_game_random_lower90"], i["n_games_random_measured"]))
    print("  bytes/row on disk            = %.1f" % d["storage"]["bytes_per_row_on_disk"])
    print("")
    print("KNOB SET UNDER TEST")
    for k, val in d["env"].items():
        print("  %-28s = %s" % (k, val))
    print("")
    print("DERIVED QUANTITIES")
    print("  rows_per_cycle    = games*r            = %.1f   (lower90 %.1f)"
          % (v["rows_per_cycle"], v["rows_per_cycle_lower90"]))
    print("  bucket gain       = games*r*reuse      = %.1f   (lower90 %.1f)"
          % (v["bucket_gain"], v["bucket_gain_lower90"]))
    print("  bucket cap_eff    = max(cap,E)         = %d" % v["bucket_cap_effective"])
    print("  epochs_per_export = max_epochs_this_instance = %d" % v["epochs_per_export"])
    print("  batches_per_epoch = round(E/batch)     = %d" % v["batches_per_epoch"])
    print("  samples_per_cycle = epochs*E           = %d" % v["samples_per_cycle"])
    print("  effective reuse   = epochs*E/rows      = %.3f  (lower90 %.3f, cap %s)"
          % (v["effective_reuse"], v["effective_reuse_lower90"], i["reuse"]))
    print("  first cycle with a full %d-epoch window = %s"
          % (v["epochs_per_export"], v["first_cycle_with_full_epoch_set"]))
    print("  swa_period_samples                     = %d" % v["swa_period_samples"])
    print("")
    print("SHUFFLE WINDOW BY CYCLE (shuffle.py:414-435 at expand 0.4 / exponent 0.65)")
    print("  %-6s %-14s %-16s %-14s %-10s %s" % ("cycle", "usable_rows", "desired_window",
                                                 "rows_available", "batches", "epochs_supported"))
    for w in d["window_by_cycle"]:
        print("  %-6d %-14.0f %-16d %-14d %-10d %d"
              % (w["cycle"], w["usable_rows"], w["desired_window_rows"],
                 w["rows_available"], w["batches_available"], w["epochs_supported"]))
    print("")
    print("THREAD BUDGET")
    t = d["threads"]
    for k in ("selfplay_real_net", "selfplay_with_net_switch", "gatekeeper_one_real_net",
              "gatekeeper_two_real_nets", "train", "shuffle", "worst_case", "cpus_per_task"):
        print("  %-28s = %s" % (k, t[k]))
    print("")
    print("CYCLE WALL PROJECTION  [PRELIMINARY]")
    c = d["cycle_time"]
    for k in ("selfplay_games_per_hour_measured", "games_per_hour_derate",
              "selfplay_games_per_hour_planning", "train_samples_per_second",
              "selfplay_s", "train_s", "gatekeeper_s", "shuffle_s", "export_s",
              "cycle_s", "cycle_h", "cycles_per_link"):
        print("  %-34s = %s" % (k, ("%.3f" % c[k]) if isinstance(c[k], float) else c[k]))
    print("")
    print("STORAGE PROJECTION")
    s = d["storage"]
    print("  per-cycle monotonic         = %.2f MiB" % (s["per_cycle_monotonic_bytes"] / 2**20))
    print("  bounded steady state        = %.2f MiB" % (s["bounded_steady_state_bytes"] / 2**20))
    print("  env + build allowance       = %.2f GiB" % (s["env_and_build_bytes"] / 2**30))
    print("  after one %d-cycle link      = %.3f GiB" % (s["cycles_per_link"], s["projected_bytes_after_one_link"] / 2**30))
    print("  hard cap (budget.env)       = %.0f GiB" % (s["hard_cap_bytes"] / 2**30))
    print("  cycles until the cap        = %d" % s["cycles_until_hard_cap"])
    print("")
    print("CHECKS")
    for c in d["checks"]:
        print("  %-4s %-38s %s" % ("ok" if c["pass_"] else "FAIL", c["name"], c["detail"]))
    print("")
    print("RESULT: %s" % ("PASS" if d["pass"] else "FAIL"))


LOOP_VAR_RE = r'^%s="\$\{%s:-([0-9]+)\}"'


def assert_loop_defaults(path, env):
    with open(path) as f:
        text = f.read()
    bad = []
    for var, want in env.items():
        m = re.search(LOOP_VAR_RE % (var, var), text, re.M)
        if not m:
            bad.append("%s: no ${%s:-default} line in %s" % (var, var, path))
        elif int(m.group(1)) != int(want):
            bad.append("%s: loop default %s != derived %s" % (var, m.group(1), want))
        else:
            print("  ok   %-28s loop default %s == derived %s" % (var, m.group(1), want))
    return bad


# ---------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("--rows-per-game", required=False, default=None)
    p.add_argument("--rows-per-game-random", required=False, default=None)
    p.add_argument("--reuse", type=float, default=8)
    p.add_argument("--samples-per-epoch", type=int, default=20000)
    p.add_argument("--games", type=int, default=500)
    p.add_argument("--keep", type=int, default=300000)
    p.add_argument("--cap", type=int, default=200000)
    p.add_argument("--min-rows", type=int, default=10000,
                   help="section 10 first-test default; the derived value is passed explicitly")
    p.add_argument("--taper", type=int, default=50000)
    p.add_argument("--batch", type=int, default=128)
    p.add_argument("--gate-games", type=int, default=200)
    p.add_argument("--cpus", type=int, default=32)
    p.add_argument("--game-threads", type=int, default=18)
    p.add_argument("--shuffle-processes", type=int, default=8)
    p.add_argument("--n-games-real", type=int, default=20)
    p.add_argument("--n-games-random", type=int, default=80)
    p.add_argument("--window-cycles", type=int, default=20)
    p.add_argument("--games-per-hour-derate", type=float, default=0.5)
    p.add_argument("--walltime-seconds", type=int, default=257400)
    p.add_argument("--cycle-bound-hours", type=float, default=60.0)
    p.add_argument("--sgf-bytes-per-game", type=int, default=2048)
    p.add_argument("--model-bytes", type=int, default=3004833)
    p.add_argument("--checkpoint-bytes", type=int, default=10021767)
    p.add_argument("--dated-archive-bytes", type=int, default=107374182)
    p.add_argument("--env-bytes", type=int, default=21474836480)
    p.add_argument("--selfplay-games-per-hour", type=float, default=None,
                   help="override the rate read from --throughput (real-net selfplay)")
    p.add_argument("--train-samples-per-second", type=float, default=None,
                   help="override the rate read from --throughput")
    # o41: one explicit override per MEASURED input the projections read, so a caller can
    # state a number instead of a file -- and so --self-test never depends on an evidence
    # file. None of them has a value baked into this module.
    p.add_argument("--bytes-per-row", type=float, default=None,
                   help="override bytes_per_row_on_disk read from --throughput")
    p.add_argument("--gate-games-measured", type=float, default=None,
                   help="override gatekeeper_games_total read from --throughput")
    p.add_argument("--gate-elapsed-s", type=float, default=None,
                   help="override per_phase_stage['cycle2/gatekeeper'].elapsed_s")
    p.add_argument("--shuffle-elapsed-s", type=float, default=None,
                   help="override per_phase_stage['cycle2/shuffle'].elapsed_s")
    p.add_argument("--shuffle-rows-measured", type=float, default=None,
                   help="override selfplay_rows_total / SMOKE_CYCLES")
    p.add_argument("--throughput", default=None)
    p.add_argument("--budget-env", default=None)
    p.add_argument("--assert-loop-defaults", default=None)
    p.add_argument("--emit-env", action="store_true")
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--json", default=None)
    return p


HERE = os.path.dirname(os.path.abspath(__file__))          # .../codes/eval
PAPER = os.path.dirname(os.path.dirname(HERE))              # .../paper_1902.10565


def finish(args):
    args.r = parse_rows_per_game(args.rows_per_game, "rows_per_game_real")
    if args.rows_per_game_random:
        args.r0 = parse_rows_per_game(args.rows_per_game_random, "rows_per_game_random")
    else:
        try:
            args.r0 = parse_rows_per_game(args.rows_per_game, "rows_per_game_random")
        except SystemExit:
            args.r0 = args.r
    if args.throughput is None:
        # The unsuffixed evidence names are MUTABLE and were overwritten by attempt-2
        # job 299259 (obligation o37, evidence/smoke/validation_core.md finding 2);
        # the admitted, content-hashed copies carry the -298712 suffix.
        for name in ("throughput_smoke-298712.json", "throughput_smoke.json"):
            cand = os.path.join(PAPER, "evidence", "smoke", name)
            if os.path.exists(cand):
                args.throughput = cand
                break
    if args.budget_env is None:
        cand = os.path.join(PAPER, "codes", "data_budget", "budget.env")
        args.budget_env = cand if os.path.exists(cand) else None
    return args


# Synthetic, deliberately round MEASURED inputs for --self-test. They are stand-ins, not
# measurements: giving every self-test case an explicit value is what keeps the self-test
# independent of any evidence file, and is the other half of o41 -- this module must carry
# no number that could be mistaken for something a job produced.
SELF_TEST_RATES = ["--train-samples-per-second", "15.0",
                   "--selfplay-games-per-hour", "2000.0",
                   "--bytes-per-row", "400.0",
                   "--gate-games-measured", "150",
                   "--gate-elapsed-s", "60.0",
                   "--shuffle-elapsed-s", "4.0",
                   "--shuffle-rows-measured", "1200"]


def self_test():
    """DESIGN section 2's two negative cases, the smoke's executed case, and the o41
    missing-measured-key cases."""
    P = build_parser()
    fails = []

    def run(label, argv, expect_pass, expect_failing=()):
        print("--- self-test: %s" % label)
        a = finish(P.parse_args(argv + SELF_TEST_RATES))
        d = derive(a)
        got_failing = tuple(c["name"] for c in d["checks"] if not c["pass_"])
        print("    pass=%s failing=%s" % (d["pass"], list(got_failing)))
        ok = (d["pass"] == expect_pass)
        for name in expect_failing:
            if name not in got_failing:
                ok = False
                print("    expected %s to fail and it did not" % name)
        if not ok:
            fails.append(label)
        return d

    # DESIGN section 2, pass 2's set at the planning r = 22: gain 44 000 < 49 500.
    run("DESIGN pass-2 knobs (reuse 4, 50k/epoch) starve from cycle 2",
        ["--rows-per-game", "22", "--rows-per-game-random", "22", "--reuse", "4",
         "--samples-per-epoch", "50000", "--games", "500", "--keep", "300000",
         "--cap", "200000", "--min-rows", "50000", "--n-games-real", "20"],
        False, ("K1_bucket_gain_clears_epoch",))

    # DESIGN section 2, pass 1's data window: keep 300k with a 500k cycle cap.
    run("pass-1 data window keep 300k <= cap 500k",
        ["--rows-per-game", "22", "--rows-per-game-random", "22", "--reuse", "8",
         "--samples-per-epoch", "20000", "--games", "500", "--keep", "300000",
         "--cap", "500000", "--min-rows", "10000"],
        False, ("K3_keep_gt_cap",))

    # The smoke's executed knob set. K1/K2/K3/K5 pass; K4's CONSERVATIVE form
    # fails because it does not credit shuffle.sh:48 file granularity -- the run
    # itself got a single 1221-row file for a 200-row window and did train one
    # epoch of 38 batches, which is why the executed smoke exported.
    d = run("smoke knobs (40 games, 256/epoch, reuse 8, batch 32)",
            ["--rows-per-game", "31.675", "--rows-per-game-random", "31.675",
             "--reuse", "8", "--samples-per-epoch", "256", "--games", "40",
             "--keep", "5000", "--cap", "4000", "--min-rows", "200",
             "--taper", "200", "--batch", "32", "--n-games-real", "80",
             "--cpus", "24", "--window-cycles", "2"],
            False, ("K4_window_holds_one_epoch", "T4_threads_le_cpus"))
    for name in ("K1_bucket_gain_clears_epoch", "K2_one_export_per_cycle", "K3_keep_gt_cap",
                 "K5_random_bootstrap_reaches_min_rows"):
        c = [x for x in d["checks"] if x["name"] == name][0]
        if not c["pass_"]:
            fails.append("smoke positive conjunct %s" % name)
            print("    expected %s to pass and it did not" % name)
    if d["derived"]["epochs_per_export"] < 1:
        fails.append("smoke epochs_per_export < 1")

    # o41 negative cases: every MEASURED key the projections read must raise, naming
    # itself, when it is missing -- never fall back to a constant.
    print("--- self-test: o41 missing measured keys raise, naming the key")
    import tempfile
    base_tput = {
        "train_samples_per_second": 15.0,
        "bytes_per_row_on_disk": 400.0,
        "selfplay_rows_total": 2400,
        "selfplay_games_per_hour": 2000.0,
        "gatekeeper_games_total": 150,
        "per_phase_stage": {"cycle2/gatekeeper": {"elapsed_s": 60.0},
                            "cycle2/shuffle": {"elapsed_s": 4.0}},
    }
    base_argv = ["--rows-per-game", "32.3", "--rows-per-game-random", "31.675",
                 "--reuse", "8", "--samples-per-epoch", "20000", "--games", "1000",
                 "--keep", "120000", "--cap", "100000", "--min-rows", "25000",
                 "--taper", "50000", "--batch", "128", "--cpus", "32", "--game-threads", "18"]
    drops = [("train_samples_per_second", None), ("bytes_per_row_on_disk", None),
             ("selfplay_games_per_hour", None), ("gatekeeper_games_total", None),
             ("selfplay_rows_total", None),
             ("cycle2/gatekeeper", "per_phase_stage"), ("cycle2/shuffle", "per_phase_stage")]
    tmpdir = tempfile.mkdtemp(prefix="derive_knobs_selftest_")
    for key, where in drops:
        tp = dict(base_tput)
        tp["per_phase_stage"] = dict(base_tput["per_phase_stage"])
        if where == "per_phase_stage":
            del tp["per_phase_stage"][key]
        else:
            del tp[key]
        fp = os.path.join(tmpdir, "tput_no_%s.json" % key.replace("/", "_"))
        with open(fp, "w") as f:
            json.dump(tp, f)
        try:
            derive(finish(P.parse_args(base_argv + ["--throughput", fp,
                                                    "--budget-env", ""])))
        except SystemExit as exc:
            msg = str(exc)
            ok = key in msg and "fallback" in msg
            print("    dropped %-26s -> SystemExit naming it: %s" % (key, ok))
            if not ok:
                fails.append("o41 %s: %s" % (key, msg[:120]))
        else:
            print("    dropped %-26s -> NO EXIT (a fallback survived)" % key)
            fails.append("o41 %s did not raise" % key)
    # and the positive control: with every key present the same call derives
    fp = os.path.join(tmpdir, "tput_full.json")
    with open(fp, "w") as f:
        json.dump(base_tput, f)
    derive(finish(P.parse_args(base_argv + ["--throughput", fp, "--budget-env", ""])))
    print("    every key present            -> derives, no exit")
    for f_ in os.listdir(tmpdir):
        os.remove(os.path.join(tmpdir, f_))
    os.rmdir(tmpdir)

    print("")
    if fails:
        print("SELF-TEST: FAIL  %s" % fails)
        return 1
    print("SELF-TEST: PASS  (3 knob cases: 2 negative, 1 executed-smoke; "
          "7 o41 missing-key cases plus a positive control)")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    p = build_parser()
    vo, fo = _option_sets(p)
    args = p.parse_args(normalize_argv(argv, vo, fo))
    if args.rows_per_game is None:
        p.error("--rows-per-game is required")
    args = finish(args)
    d = derive(args)

    if args.emit_env:
        for k, v in d["env"].items():
            print("%s=%s" % (k, v))
        return 0 if d["pass"] else 1

    report(d)
    if args.json:
        with open(args.json, "w") as f:
            json.dump(d, f, indent=1, sort_keys=True)

    rc = 0 if d["pass"] else 1
    if args.assert_loop_defaults:
        print("")
        print("LOOP DEFAULT WIRING  (%s)" % args.assert_loop_defaults)
        bad = assert_loop_defaults(args.assert_loop_defaults, d["env"])
        for b in bad:
            print("  FAIL %s" % b)
        if bad:
            rc = 1
        print("  %s" % ("WIRING: PASS" if not bad else "WIRING: FAIL"))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
