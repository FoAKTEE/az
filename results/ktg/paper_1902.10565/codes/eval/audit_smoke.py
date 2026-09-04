#!/usr/bin/env python3
"""audit_smoke.py -- mission ktg-train, node arxiv-1902.10565::synchronous_loop_smoke.

The closing check of the smoke node and the single place where S1-S9 and S13 of
tasks/synchronous_loop_smoke/implementation.md section 2 are evaluated against the
artifacts one allocation produced.

TWO MODES
  audit_smoke.py <BASEDIR> --snapshot <label>
      Runs INSIDE the allocation, right after a cycle. Reads
      <BASEDIR>/train/<name>/checkpoint.ckpt with torch and freezes its train_state
      counters into <BASEDIR>/audit_hooks/ckpt_<label>.json. This exists because S6
      compares cycle 2's global_step_samples against cycle 1's, and cycle 2 overwrites
      the checkpoint -- the cycle-1 value has to be captured while it is still there.

  audit_smoke.py <BASEDIR> --evidence <dir>
      The node's closing check. STANDARD LIBRARY ONLY -- no numpy, no torch -- so the
      admission gate can execute it on the login node, which has neither. Every number
      it needs from a checkpoint comes from the snapshots above; npz shapes come from
      the .npy headers inside the zip (check_pos_len_npz).

WHAT IS HARD AND WHAT IS RECORDED
  HARD (exit 1 if violated) -- the node's own claim c07 / obligations o19, o03, and the
  9x9 and row-format facts the node asserts:
      S1 cycles_completed == 2
      S2 candidate_exported >= 1 and candidate_gated >= 1
      S3 gate_random >= 1
      S4 sz_other == 0
      S5 npz trailing shapes (22,11)/(2,82) and row bytes == 2145, raw and shuffled
      S6 global_step_samples cycle2 > cycle1, metrics finite, no re-initialisation
      S9 nlwp_max per stage <= the allocation's cpus-per-task
  RECORDED (measured, banded, never fatal here) -- these settle OTHER packets' rows and
  carry their own verification scripts, so a probe failure must not block a node whose
  own claim is proved:
      S7  full_frac        (probe_search_9x9.py; band [0.20, 0.30])
      S8  rows_per_game    (band [12, 35]; section 2 says out-of-band is a finding)
      S11 trunk gpool / gpool residuals (probe_train_9x9.py)
      S12 kill-and-resume  (probe_resume_9x9.sh)
      S13 throughput       (no threshold by construction)
  --strict promotes S7, S11 and S12 to hard as well; the validator may use it.

OUTPUTS under --evidence
  audit.json             every number below, plus the per-check verdicts
  rows_per_game.txt      S8: the real-net and random-net rows/game measurements
  throughput_smoke.json  S13: the measure_stage_throughput inputs
  nlwp_max.txt           S9: per-stage and per-(phase, stage) thread peaks
"""

import glob
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_pos_len_npz import npz_array_meta, row_bytes, num_rows, EXPECTED_SHAPES  # noqa: E402

EXPECTED_ROW_BYTES = 2145
EXPECTED_CYCLES = 2
ROWS_PER_GAME_LO, ROWS_PER_GAME_HI = 12, 35
BYTES_PER_GAME_MAX = 10 * 1024   # c10's second conjunct: <= 10 KiB on disk per 9x9 game
FULL_FRAC_LO, FULL_FRAC_HI = 0.20, 0.30
DEFAULT_CPUS = 24

ONE_CYCLE_DONE = "one cycle done"
GATE_RANDOM_RE = re.compile(r"Loaded accepted neural net random")
GATED_RE = re.compile(r"Candidate (won|lost) match")


# ----------------------------------------------------------------- helpers
def read_json(path, default=None):
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception:
        return default


def count_in_files(paths, pattern):
    n = 0
    rx = pattern if hasattr(pattern, "search") else re.compile(re.escape(pattern))
    for p in paths:
        try:
            with open(p, "r", errors="replace") as fh:
                for line in fh:
                    if rx.search(line):
                        n += 1
        except OSError:
            pass
    return n


def dir_bytes(path):
    total = 0
    for root, _d, names in os.walk(path):
        for n in names:
            try:
                total += os.path.getsize(os.path.join(root, n))
            except OSError:
                pass
    return total


def sgfs_stats(patterns):
    files, n_all, n9, n_rect = [], 0, 0, 0
    for pat in patterns:
        files.extend(sorted(glob.glob(pat)))
    for f in files:
        try:
            with open(f, "r", errors="replace") as fh:
                for line in fh:
                    if not line.strip():
                        continue
                    n_all += 1
                    if "SZ[9]" in line:
                        n9 += 1
                    if re.search(r"SZ\[\d+:\d+\]", line):
                        n_rect += 1
        except OSError:
            pass
    return {"files": len(files), "lines": n_all, "sz9": n9,
            "sz_other": n_all - n9, "rectangular": n_rect}


def npz_report(paths):
    rows, bad, per_file = 0, [], []
    row_bytes_seen = set()
    for p in paths:
        try:
            meta = npz_array_meta(p)
        except Exception as exc:
            bad.append("%s: unreadable (%s)" % (p, exc))
            continue
        rb = row_bytes(meta)
        n = num_rows(meta)
        rows += n
        row_bytes_seen.add(rb)
        for name, want in EXPECTED_SHAPES.items():
            if name not in meta:
                bad.append("%s: missing %s" % (p, name))
            elif tuple(meta[name]["shape"][1:]) != want:
                bad.append("%s: %s trailing shape %s != %s"
                           % (p, name, tuple(meta[name]["shape"][1:]), want))
        if rb != EXPECTED_ROW_BYTES:
            bad.append("%s: row bytes %d != %d" % (p, rb, EXPECTED_ROW_BYTES))
        per_file.append({"path": p, "rows": n, "row_bytes": rb})
    return {"files": len(paths), "rows": rows,
            "row_bytes_seen": sorted(row_bytes_seen),
            "problems": bad, "per_file": per_file}


# ----------------------------------------------------------------- snapshot mode
def _read_ckpt(path):
    """train_state counters + running-metrics finiteness of one checkpoint (needs torch)."""
    import torch  # allocation-only
    rec = {"checkpoint": path, "exists": os.path.exists(path)}
    if not rec["exists"]:
        return rec
    d = torch.load(path, map_location="cpu", weights_only=False)
    ts = d.get("train_state", {}) or {}
    rec.update({
        "global_step_samples": ts.get("global_step_samples"),
        "total_num_data_rows": ts.get("total_num_data_rows"),
        "train_bucket_level": ts.get("train_bucket_level"),
        "train_bucket_level_at_row": ts.get("train_bucket_level_at_row"),
        "export_cycle_counter": ts.get("export_cycle_counter"),
        "window_start_data_row_idx": ts.get("window_start_data_row_idx"),
        "train_steps_since_last_reload": ts.get("train_steps_since_last_reload"),
        "checkpoint_bytes": os.path.getsize(path),
    })
    # S6's "metrics all finite". metrics_train.json is only appended every
    # print_train_loss_every_batches = 100 batches (train.py:1379,1661,1694), so at the
    # smoke scale (38 batches/epoch) it stays EMPTY and cannot carry the measurement.
    # running_metrics inside the checkpoint is the same accumulator and is always there.
    rm = d.get("running_metrics") or {}
    nonfinite, terms = [], 0
    for section in ("sums", "weights"):
        for k, v in (rm.get(section) or {}).items():
            try:
                f = float(v)
            except (TypeError, ValueError):
                continue
            terms += 1
            if math.isnan(f) or math.isinf(f):
                nonfinite.append("%s.%s=%r" % (section, k, f))
    rec["running_metrics_terms"] = terms
    rec["running_metrics_nonfinite"] = nonfinite
    rec["running_metrics_nsamp"] = (rm.get("sums") or {}).get("nsamp")
    return rec


def snapshot(basedir, label, trainingname):
    traindir = os.path.join(basedir, "train", trainingname)
    out_dir = os.path.join(basedir, "audit_hooks")
    os.makedirs(out_dir, exist_ok=True)

    if label == "cycles":
        # Post-hoc / belt-and-braces path: train.py rotates checkpoint.ckpt into
        # checkpoint_prev0.ckpt before each save (train.py:578,1875), so after two
        # cycles prev0 IS cycle 1's final checkpoint and checkpoint.ckpt is cycle 2's.
        # This recovers S6 from a run whose per-cycle snapshots did not execute.
        pairs = [("cycle1", os.path.join(traindir, "checkpoint_prev0.ckpt")),
                 ("cycle2", os.path.join(traindir, "checkpoint.ckpt"))]
    else:
        pairs = [(label, os.path.join(traindir, "checkpoint.ckpt"))]

    for lab, path in pairs:
        rec = _read_ckpt(path)
        rec["label"] = lab
        rec["source"] = "checkpoint_prev0.ckpt (rotated cycle-1 save)" if path.endswith("prev0.ckpt") \
            else "checkpoint.ckpt (latest save)"
        out = os.path.join(out_dir, "ckpt_%s.json" % lab)
        with open(out, "w") as fh:
            json.dump(rec, fh, indent=1, sort_keys=True)
        print("audit_smoke snapshot %s -> %s" % (lab, out))
        print(json.dumps(rec, indent=1, sort_keys=True))
    return 0


# ----------------------------------------------------------------- monitor parse
def pick_ps_file(basedir, tag):
    """The sampler's file for ONE attempt.

    Obligation o37: stage_monitor.sh used to APPEND to a single ps_samples.tsv, so a
    resubmission mixed attempts in one file and any aggregate over it is a mixture of
    two different sampling scopes. The sampler now writes ps_samples-<jobid>.tsv; this
    picks the file for `tag` when given, else the newest per-job file, else the legacy
    shared file (which parse_monitor then handles row by row).
    """
    mon = os.path.join(basedir, "monitor")
    if tag:
        cand = os.path.join(mon, "ps_samples-%s.tsv" % tag)
        if os.path.exists(cand):
            return cand
    per_job = sorted(glob.glob(os.path.join(mon, "ps_samples-*.tsv")),
                     key=lambda f: os.path.getmtime(f))
    if per_job:
        return per_job[-1]
    return os.path.join(mon, "ps_samples.tsv")


def parse_monitor(basedir, ps_file=None):
    """Per-stage and per-(phase, stage) thread/RSS peaks, attributed per PID.

    Scope repair after job 298712: the pre-repair sampler used a node-wide `ps -e` on a
    SHARED b200 node, so foreign processes whose command line contains "train.py" landed
    on the `train` stage (three of them, nlwp 36, from before leg A to the end of leg E,
    against our own trainer's 14). The repaired sampler writes a 7th column, the ppid,
    and only records descendants of the job script; a 7-column file therefore needs no
    exclusion. For a 6-column file the exclusion rule is provable rather than heuristic:
    leg A runs only codes/eval/check_cfg_9x9.sh, which starts `katago selfplay` and no
    trainer at all, so ANY pid classified `train` during phase legA is foreign to this
    job and is dropped everywhere. Excluded pids are reported, never silently removed.
    """
    path = ps_file or os.path.join(basedir, "monitor", "ps_samples.tsv")
    # A legacy shared file may still APPEND across resubmissions, so one file can hold both the
    # pre-repair 6-column rows of an earlier attempt and the ancestry-filtered
    # 7-column rows of a later one. Job 299259 proved that a per-FILE decision is
    # wrong: max(columns) was 7, which switched the legA exclusion off and let the
    # earlier attempt's foreign pids back in (train read 36 again). The scope is a
    # property of each ROW, so decide per row and let the exclusion apply to the
    # unfiltered rows only.
    rows, ncols_seen = [], set()
    if os.path.exists(path):
        with open(path, "r", errors="replace") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 6:
                    continue
                ncols_seen.add(len(parts))
                try:
                    t = float(parts[0])
                    pid = int(parts[3])
                    nlwp = int(parts[4])
                    rss = int(parts[5])
                except ValueError:
                    continue
                rows.append((t, parts[1], parts[2], pid, nlwp, rss, len(parts)))
    rows = [r[:6] + (r[6],) for r in rows]
    ncols = max(ncols_seen) if ncols_seen else 0

    # A pid is foreign if it was classified `train` during phase legA in an
    # UNFILTERED (6-column) sample: leg A runs only codes/eval/check_cfg_9x9.sh,
    # which starts katago selfplay and no trainer at all.
    foreign = sorted({pid for (_t, ph, st, pid, _n, _r, nc) in rows
                      if nc < 7 and st == "train" and ph == "legA"})
    per_pid = {}
    for (t, ph, st, pid, nlwp, rss, _nc) in rows:
        e = per_pid.setdefault(pid, {"pid": pid, "stage": st, "phases": set(),
                                     "nlwp_max": 0, "rss_kb_max": 0, "samples": 0,
                                     "t_min": t, "t_max": t,
                                     "foreign": pid in foreign})
        e["phases"].add(ph)
        e["nlwp_max"] = max(e["nlwp_max"], nlwp)
        e["rss_kb_max"] = max(e["rss_kb_max"], rss)
        e["samples"] += 1
        e["t_min"] = min(e["t_min"], t)
        e["t_max"] = max(e["t_max"], t)
    for e in per_pid.values():
        e["elapsed_s"] = round(e["t_max"] - e["t_min"], 2)
        e["phases"] = sorted(e["phases"])
        e.pop("t_min", None)
        e.pop("t_max", None)

    per_stage, per_ps, samples = {}, {}, 0
    if True:
        if True:
            for (t, phase, stage, pid, nlwp, rss, _nc) in rows:
                if pid in foreign:
                    continue
                samples += 1
                for key, table in ((stage, per_stage), ("%s/%s" % (phase, stage), per_ps)):
                    e = table.setdefault(key, {"nlwp_max": 0, "rss_kb_max": 0,
                                               "samples": 0, "t_min": t, "t_max": t})
                    e["nlwp_max"] = max(e["nlwp_max"], nlwp)
                    e["rss_kb_max"] = max(e["rss_kb_max"], rss)
                    e["samples"] += 1
                    e["t_min"] = min(e["t_min"], t)
                    e["t_max"] = max(e["t_max"], t)
    for table in (per_stage, per_ps):
        for e in table.values():
            e["elapsed_s"] = round(e["t_max"] - e["t_min"], 2)
            e.pop("t_min", None)
            e.pop("t_max", None)
    gpu = {"samples": 0, "util_max": None, "mem_used_mib_max": None, "util_mean": None}
    gpath = os.path.join(basedir, "monitor", "gpu_samples.csv")
    if os.path.exists(gpath):
        utils, mems = [], []
        with open(gpath, "r", errors="replace") as fh:
            for line in fh:
                cols = [c.strip() for c in line.split(",")]
                if len(cols) < 4:
                    continue
                m_u = re.match(r"(\d+)\s*%", cols[2])
                m_m = re.match(r"(\d+)\s*MiB", cols[3])
                if m_u:
                    utils.append(int(m_u.group(1)))
                if m_m:
                    mems.append(int(m_m.group(1)))
        gpu["samples"] = len(utils)
        if utils:
            gpu["util_max"] = max(utils)
            gpu["util_mean"] = round(sum(utils) / len(utils), 2)
            gpu["util_over_50_frac"] = round(sum(1 for u in utils if u > 50) / len(utils), 3)
        if mems:
            gpu["mem_used_mib_max"] = max(mems)
    return {"ps_samples": samples,
            "ps_file": path,
            "ps_sample_columns": ncols,
            "ps_scope": ("mixed: %d ancestry-filtered rows and %d unfiltered rows; the unfiltered ones are subject to the legA exclusion"
                         % (sum(1 for r in rows if r[6] >= 7), sum(1 for r in rows if r[6] < 7))
                         if len(ncols_seen) > 1 else
                         ("descendants of the job script (ppid-filtered sampler)" if ncols >= 7 else
                          "node-wide ps -e (pre-repair sampler); foreign pids excluded by the legA rule")),
            "foreign_pids_excluded": foreign,
            "per_pid": sorted(per_pid.values(), key=lambda e: e["pid"]),
            "per_stage": per_stage,
            "per_phase_stage": per_ps, "gpu": gpu}


# ----------------------------------------------------------------- full audit
def audit(basedir, evidence, trainingname, strict, tag=None):
    """With --tag, every output is written as <name>-<tag>.<ext> and NOTHING unstamped
    is touched. Obligation o37: attempt 2's leg E overwrote audit.json, nlwp_max.txt,
    rows_per_game.txt and throughput_smoke.json, the very files the validator had
    already admitted rows against for attempt 1. The job script always passes --tag
    $SLURM_JOB_ID, so a run can no longer clobber another run's admitted evidence; the
    untagged form stays for the login-node closing check."""
    W = basedir
    ev = evidence
    os.makedirs(ev, exist_ok=True)
    r = {"basedir": W, "evidence_dir": ev, "trainingname": trainingname}
    checks = []

    def add(name, hard, ok, detail):
        checks.append({"name": name, "hard": bool(hard), "pass": bool(ok), "detail": detail})

    alloc = read_json(os.path.join(W, "markers", "allocation.json"), {}) or {}
    attempts = [read_json(p, {}) for p in
                sorted(glob.glob(os.path.join(W, "markers", "attempt_*.json")))]
    r["attempts"] = [a for a in attempts if a]
    r["resumed_from_leg"] = [a.get("resumed_from_leg") for a in r["attempts"]]
    r["markers_present"] = sorted(os.path.basename(p) for p in
                                  glob.glob(os.path.join(W, "markers", "*.done")))
    cpus = int(alloc.get("cpus_per_task") or os.environ.get("SLURM_CPUS_PER_TASK") or DEFAULT_CPUS)
    r["allocation"] = alloc
    r["cpus_per_task"] = cpus

    # ---- S1 cycles completed -------------------------------------------------
    cycle_logs = sorted(glob.glob(os.path.join(W, "logs", "smoke_*.txt")))
    cycles = count_in_files(cycle_logs, ONE_CYCLE_DONE)
    r["S1_cycles_completed"] = cycles
    r["cycle_logs"] = cycle_logs
    add("S1_cycles_completed_eq_2", True, cycles == EXPECTED_CYCLES,
        "'%s' lines = %d, expected %d, over %d log(s)"
        % (ONE_CYCLE_DONE, cycles, EXPECTED_CYCLES, len(cycle_logs)))

    # ---- S2 candidate exported and gated ------------------------------------
    exported = []
    for sub in ("modelstobetested", "models", "rejectedmodels"):
        for p in sorted(glob.glob(os.path.join(W, sub, "*", "model.bin.gz"))):
            exported.append({"dir": sub, "name": os.path.basename(os.path.dirname(p)),
                             "path": p, "mtime": os.path.getmtime(p),
                             "bytes": os.path.getsize(p)})
    exported.sort(key=lambda e: e["mtime"])
    gk_stdout = os.path.join(W, "gatekeepersgf", "stdout.txt")
    gated = count_in_files([gk_stdout], GATED_RE)
    won = count_in_files([gk_stdout], re.compile(r"Candidate won match"))
    lost = count_in_files([gk_stdout], re.compile(r"Candidate lost match"))
    r["S2_candidate_exported"] = len(exported)
    r["S2_exported"] = exported
    r["S2_candidate_gated"] = gated
    r["S2_candidate_won"] = won
    r["S2_candidate_lost"] = lost
    add("S2_candidate_exported_ge_1", True, len(exported) >= 1,
        "exported model.bin.gz dirs = %d (%s)"
        % (len(exported), ", ".join("%s/%s" % (e["dir"], e["name"]) for e in exported) or "none"))
    add("S2_candidate_gated_ge_1", True, gated >= 1,
        "'Candidate (won|lost) match' lines = %d (won %d, lost %d)" % (gated, won, lost))

    # ---- S3 gate against the random baseline --------------------------------
    gate_random = count_in_files([gk_stdout], GATE_RANDOM_RE)
    r["S3_gate_random"] = gate_random
    add("S3_gate_random_ge_1", True, gate_random >= 1,
        "'Loaded accepted neural net random' lines = %d in %s" % (gate_random, gk_stdout))

    # ---- S4 board size ------------------------------------------------------
    sp_sgfs = sgfs_stats([os.path.join(W, "selfplay", "*", "sgfs", "*.sgfs")])
    gk_sgfs = sgfs_stats([os.path.join(W, "gatekeepersgf", "*", "*.sgfs"),
                          os.path.join(W, "gatekeepersgf", "*", "*", "*.sgfs")])
    sz_other = sp_sgfs["sz_other"] + gk_sgfs["sz_other"]
    rect = sp_sgfs["rectangular"] + gk_sgfs["rectangular"]
    r["S4_selfplay_sgfs"] = sp_sgfs
    r["S4_gatekeeper_sgfs"] = gk_sgfs
    r["S4_sz_other"] = sz_other
    r["S4_rectangular"] = rect
    add("S4_sz_other_eq_0", True,
        sz_other == 0 and rect == 0 and (sp_sgfs["lines"] + gk_sgfs["lines"]) >= 1,
        "sgf lines selfplay=%d gatekeeper=%d, sz_other=%d, rectangular=%d"
        % (sp_sgfs["lines"], gk_sgfs["lines"], sz_other, rect))

    # ---- S5 npz row format --------------------------------------------------
    raw_npz = sorted(glob.glob(os.path.join(W, "selfplay", "*", "tdata", "*.npz")))
    shuf_npz = sorted(glob.glob(os.path.join(W, "shuffleddata", "*", "train", "*.npz")))
    raw = npz_report(raw_npz)
    shuf = npz_report(shuf_npz)
    r["S5_raw_npz"] = raw
    r["S5_shuffled_npz"] = shuf
    add("S5_raw_npz_pos_len_9_2145", True,
        raw["files"] >= 1 and not raw["problems"],
        "raw npz files=%d rows=%d row_bytes=%s problems=%d"
        % (raw["files"], raw["rows"], raw["row_bytes_seen"], len(raw["problems"])))
    add("S5_shuffled_npz_pos_len_9_2145", True,
        shuf["files"] >= 1 and not shuf["problems"],
        "shuffled npz files=%d rows=%d row_bytes=%s problems=%d"
        % (shuf["files"], shuf["rows"], shuf["row_bytes_seen"], len(shuf["problems"])))

    # ---- S6 checkpoint resume + finite metrics ------------------------------
    snap1 = read_json(os.path.join(W, "audit_hooks", "ckpt_cycle1.json"), {}) or {}
    snap2 = read_json(os.path.join(W, "audit_hooks", "ckpt_cycle2.json"), {}) or {}
    g1, g2 = snap1.get("global_step_samples"), snap2.get("global_step_samples")
    metrics_path = os.path.join(W, "train", trainingname, "metrics_train.json")
    nonfinite, nlines, last_metrics = [], 0, None
    if os.path.exists(metrics_path):
        with open(metrics_path, "r", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                nlines += 1
                last_metrics = d
                for k, v in d.items():
                    if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
                        nonfinite.append("%s=%r" % (k, v))
    train_log = os.path.join(W, "train", trainingname, "stdout.txt")
    reinit_total = count_in_files([train_log], re.compile(r"Initializing new model!"))
    cycle2_log = cycle_logs[-1] if len(cycle_logs) >= 2 else None
    reinit_cycle2 = count_in_files([cycle2_log], re.compile(r"Initializing new model!")) if cycle2_log else None
    r["S6"] = {"snapshot_cycle1": snap1, "snapshot_cycle2": snap2,
               "global_step_samples_cycle1": g1, "global_step_samples_cycle2": g2,
               "metrics_train_json": metrics_path, "metrics_lines": nlines,
               "metrics_nonfinite": nonfinite, "last_metrics": last_metrics,
               "initializing_new_model_in_train_stdout_total": reinit_total,
               "initializing_new_model_in_cycle2_log": reinit_cycle2}
    add("S6_global_step_samples_increases", True,
        isinstance(g1, (int, float)) and isinstance(g2, (int, float)) and g2 > g1,
        "global_step_samples cycle1=%s -> cycle2=%s" % (g1, g2))
    # S6 "metrics_train.json all terms finite": at the smoke scale that file is EMPTY by
    # construction -- train.py:1379 sets print_train_loss_every_batches = 100 and only
    # then calls log_metrics (:1661,:1694), while an epoch here is 38 batches. The same
    # accumulator is carried in the checkpoint as running_metrics, so the finiteness
    # measurement is taken there and the empty file is reported, not counted against.
    rm_terms = (snap2.get("running_metrics_terms") or 0) + (snap1.get("running_metrics_terms") or 0)
    rm_nonfinite = list(snap1.get("running_metrics_nonfinite") or []) + \
                   list(snap2.get("running_metrics_nonfinite") or [])
    r["S6"]["running_metrics_terms"] = rm_terms
    r["S6"]["running_metrics_nonfinite"] = rm_nonfinite
    r["S6"]["metrics_train_json_empty_reason"] = (
        "print_train_loss_every_batches = 100 (train.py:1379) > batches per epoch at the "
        "smoke knobs; log_metrics never fires, so the file is 0 bytes. Not a defect.")
    add("S6_metrics_finite", True, rm_terms >= 1 and not rm_nonfinite,
        "running_metrics numeric terms=%d nonfinite=%s (metrics_train.json lines=%d, empty by scale)"
        % (rm_terms, rm_nonfinite or "none", nlines))
    add("S6_no_reinit_in_cycle2", True, reinit_cycle2 == 0,
        "'Initializing new model!' in the cycle-2 log = %s (train stdout total over both cycles = %d, 1 expected from cycle 1)"
        % (reinit_cycle2, reinit_total))

    # ---- S9 threads ---------------------------------------------------------
    mon = parse_monitor(W, pick_ps_file(W, tag))
    r["S9_monitor"] = mon
    stage_max = {k: v["nlwp_max"] for k, v in mon["per_stage"].items()}
    over = {k: v for k, v in stage_max.items() if v > cpus}
    add("S9_nlwp_max_within_cpus", True,
        bool(stage_max) and not over,
        "nlwp_max per stage = %s, cpus_per_task = %d, over budget = %s (scope: %s; foreign pids excluded: %s)"
        % (stage_max, cpus, over or "none", mon["ps_scope"], mon["foreign_pids_excluded"] or "none"))

    # ---- S7 / S11 / S12 probe results ---------------------------------------
    ktg_root = os.environ.get("KTG_ROOT", "/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train")
    probe_search = read_json(os.path.join(ktg_root, "runs", "smoke_probe", "search",
                                          "probe_search.json"), {}) or {}
    probe_train = read_json(os.path.join(ktg_root, "runs", "smoke_probe", "train",
                                         "probe_train.json"), {}) or {}
    probe_resume = read_json(os.path.join(ktg_root, "runs", "smoke_probe", "train",
                                          "probe_resume.json"), {}) or {}
    r["S7_probe_search"] = probe_search
    r["S11_probe_train"] = probe_train
    r["S12_probe_resume"] = probe_resume
    ff = probe_search.get("full_frac")
    add("S7_full_frac_in_band", strict,
        ff is not None and FULL_FRAC_LO <= ff <= FULL_FRAC_HI,
        "full_frac=%s band=[%.2f, %.2f] searched_turns=%s"
        % (ff, FULL_FRAC_LO, FULL_FRAC_HI, probe_search.get("searched_turns")))
    add("S11_probe_train_pass", strict, bool(probe_train.get("pass")),
        "trunk_gpool_count=%s res2=%s res3=%s row_bytes=%s"
        % (probe_train.get("trunk_gpool_count"),
           probe_train.get("residual_pool2_plus_half_pool1"),
           probe_train.get("residual_pool3_minus_015_pool1"),
           probe_train.get("row_bytes")))
    add("S12_probe_resume_pass", strict, bool(probe_resume.get("pass")),
        "global_step_samples %s -> %s, reinit_phase2=%s"
        % (probe_resume.get("global_step_samples_at_kill"),
           probe_resume.get("global_step_samples_after"),
           probe_resume.get("initializing_new_model_phase2")))

    # ---- S8 rows per game ---------------------------------------------------
    # A selfplay subdirectory is named after the net that produced it
    # (LoadModel::findLatestModel -> modelName; "random" for the bootstrap), so the
    # split between random-net and real-net games is exactly the directory name.
    per_net = {}
    for d in sorted(glob.glob(os.path.join(W, "selfplay", "*"))):
        if not os.path.isdir(d):
            continue
        name = os.path.basename(d)
        s = sgfs_stats([os.path.join(d, "sgfs", "*.sgfs")])
        npz = sorted(glob.glob(os.path.join(d, "tdata", "*.npz")))
        rep = npz_report(npz)
        per_net[name] = {"games": s["lines"], "rows": rep["rows"],
                         "npz_files": rep["files"],
                         "tdata_bytes": dir_bytes(os.path.join(d, "tdata")),
                         "rows_per_game": (rep["rows"] / s["lines"]) if s["lines"] else None,
                         "real_net": name != "random"}
    probe_games = probe_search.get("games") or 0
    probe_rows = probe_search.get("rows") or 0

    real_games = sum(v["games"] for v in per_net.values() if v["real_net"]) + probe_games
    real_rows = sum(v["rows"] for v in per_net.values() if v["real_net"]) + probe_rows
    rand_games = sum(v["games"] for v in per_net.values() if not v["real_net"])
    rand_rows = sum(v["rows"] for v in per_net.values() if not v["real_net"])
    rpg_real = (real_rows / real_games) if real_games else None
    rpg_rand = (rand_rows / rand_games) if rand_games else None
    in_band = rpg_real is not None and ROWS_PER_GAME_LO <= rpg_real <= ROWS_PER_GAME_HI
    # c10's SECOND conjunct: on-disk bytes per game <= 10 KiB at pos_len 9.
    loop_bytes = sum(v["tdata_bytes"] for v in per_net.values())
    loop_games = sum(v["games"] for v in per_net.values())
    bytes_per_game = (loop_bytes / loop_games) if loop_games else None
    bytes_ok = bytes_per_game is not None and bytes_per_game <= BYTES_PER_GAME_MAX
    r["S8"] = {"per_net": per_net,
               "probe_search_games": probe_games, "probe_search_rows": probe_rows,
               "rows_per_game_real": rpg_real, "real_games": real_games, "real_rows": real_rows,
               "rows_per_game_random": rpg_rand, "random_games": rand_games,
               "random_rows": rand_rows,
               "band": [ROWS_PER_GAME_LO, ROWS_PER_GAME_HI],
               "real_in_band": in_band,
               "tdata_bytes_on_disk": loop_bytes,
               "bytes_per_game_on_disk": bytes_per_game,
               "bytes_per_game_max": BYTES_PER_GAME_MAX,
               "bytes_per_game_within_c10": bytes_ok}
    add("S8_bytes_per_game_within_10KiB", False, bytes_ok,
        "bytes_per_game_on_disk=%s B (%.3f KiB) over %d games, c10 bound %d B (10 KiB)"
        % (round(bytes_per_game, 1) if bytes_per_game else None,
           (bytes_per_game / 1024.0) if bytes_per_game else 0.0, loop_games, BYTES_PER_GAME_MAX))
    add("S8_rows_per_game_real_in_band", False, in_band,
        "rows_per_game_real=%s over %d games band=[%d, %d] (random-net %s over %d games)"
        % (rpg_real, real_games, ROWS_PER_GAME_LO, ROWS_PER_GAME_HI, rpg_rand, rand_games))

    # ---- S13 throughput -----------------------------------------------------
    def stage_elapsed(stage):
        return sum(v["elapsed_s"] for k, v in mon["per_phase_stage"].items()
                   if k.endswith("/" + stage))

    sp_elapsed = stage_elapsed("selfplay")
    gk_elapsed = stage_elapsed("gatekeeper")
    tr_elapsed = stage_elapsed("train")
    sh_elapsed = stage_elapsed("shuffle")
    total_rows = sum(v["rows"] for v in per_net.values())
    total_games = sum(v["games"] for v in per_net.values())
    tdata_bytes = sum(v["tdata_bytes"] for v in per_net.values())
    samples_trained = (g2 or 0)
    thr = {
        "note": "[PRELIMINARY] tiny-count smoke knobs (40 games/cycle, 256 samples/epoch, batch 32); inputs of measure_stage_throughput and of the data_budget calibration, not production rates",
        "stage_elapsed_s": {"selfplay": round(sp_elapsed, 2), "gatekeeper": round(gk_elapsed, 2),
                            "train": round(tr_elapsed, 2), "shuffle": round(sh_elapsed, 2)},
        "per_phase_stage": mon["per_phase_stage"],
        "selfplay_games_total": total_games,
        "selfplay_rows_total": total_rows,
        "selfplay_games_per_hour": round(total_games / sp_elapsed * 3600, 1) if sp_elapsed else None,
        "selfplay_rows_per_hour": round(total_rows / sp_elapsed * 3600, 1) if sp_elapsed else None,
        "per_net": per_net,
        "probe_search": {"games": probe_games, "rows": probe_rows,
                         "full_frac": ff, "searched_turns": probe_search.get("searched_turns")},
        "train_samples_total": samples_trained,
        "train_samples_per_second": round(samples_trained / tr_elapsed, 3) if tr_elapsed else None,
        "peak_vram_mib": mon["gpu"].get("mem_used_mib_max"),
        "gpu_util_max_pct": mon["gpu"].get("util_max"),
        "gpu_util_mean_pct": mon["gpu"].get("util_mean"),
        "gpu_util_samples": mon["gpu"].get("samples"),
        "peak_rss_kb_per_stage": {k: v["rss_kb_max"] for k, v in mon["per_stage"].items()},
        "nlwp_max_per_stage": stage_max,
        "nlwp_max_per_phase_stage": {k: v["nlwp_max"] for k, v in mon["per_phase_stage"].items()},
        "nlwp_per_pid": mon["per_pid"],
        "ps_scope": mon["ps_scope"],
        "foreign_pids_excluded": mon["foreign_pids_excluded"],
        "tdata_bytes_on_disk": tdata_bytes,
        "bytes_per_row_on_disk": round(tdata_bytes / total_rows, 2) if total_rows else None,
        "row_bytes_uncompressed": EXPECTED_ROW_BYTES,
        "shuffleddata_bytes": dir_bytes(os.path.join(W, "shuffleddata")),
        "basedir_bytes": dir_bytes(W),
        "cpus_per_task": cpus,
    }
    r["S13_throughput"] = thr

    # ---- verdict ------------------------------------------------------------
    r["checks"] = checks
    hard_fail = [c for c in checks if c["hard"] and not c["pass"]]
    soft_fail = [c for c in checks if not c["hard"] and not c["pass"]]
    r["hard_failures"] = [c["name"] for c in hard_fail]
    r["recorded_findings"] = [c["name"] for c in soft_fail]
    r["pass"] = not hard_fail

    # ---- evidence files -----------------------------------------------------
    def out(stem, ext):
        return os.path.join(ev, "%s-%s.%s" % (stem, tag, ext) if tag else "%s.%s" % (stem, ext))

    r["evidence_files"] = {k: out(k, "json" if k not in ("rows_per_game", "nlwp_max") else "txt")
                           for k in ("audit", "throughput_smoke", "rows_per_game", "nlwp_max")}
    with open(out("audit", "json"), "w") as fh:
        json.dump(r, fh, indent=1, sort_keys=True, default=str)
    with open(out("throughput_smoke", "json"), "w") as fh:
        json.dump(thr, fh, indent=1, sort_keys=True, default=str)
    with open(out("rows_per_game", "txt"), "w") as fh:
        fh.write("rows_per_game -- node arxiv-1902.10565::synchronous_loop_smoke, S8; claim c10\n")
        fh.write("basedir = %s\n" % W)
        fh.write("games = one line of a .sgfs file (cpp/program/selfplaymanager.cpp:377-378)\n")
        fh.write("rows  = sum of npz binaryInputNCHWPacked.shape[0] over tdata\n\n")
        fh.write("rows_per_game_real   = %s   (%d rows / %d games)\n"
                 % (rpg_real, real_rows, real_games))
        fh.write("rows_per_game_random = %s   (%d rows / %d games)\n"
                 % (rpg_rand, rand_rows, rand_games))
        fh.write("band (c10)           = [%d, %d]   real_in_band = %s\n"
                 % (ROWS_PER_GAME_LO, ROWS_PER_GAME_HI, in_band))
        fh.write("\nc10 second conjunct -- on-disk bytes per game at pos_len 9:\n")
        fh.write("  tdata_bytes_on_disk  = %d over %d loop games\n" % (loop_bytes, loop_games))
        fh.write("  BYTES_PER_GAME       = %s B = %.3f KiB\n"
                 % (round(bytes_per_game, 1) if bytes_per_game else None,
                    (bytes_per_game / 1024.0) if bytes_per_game else 0.0))
        fh.write("  bound                = %d B (10 KiB)   within_bound = %s\n"
                 % (BYTES_PER_GAME_MAX, bytes_ok))
        fh.write("\nper selfplay net directory (name = the net that played, 'random' = bootstrap):\n")
        for name, v in sorted(per_net.items()):
            fh.write("  %-28s real_net=%-5s games=%-6d rows=%-8d rows/game=%s\n"
                     % (name, v["real_net"], v["games"], v["rows"], v["rows_per_game"]))
        fh.write("  %-28s real_net=%-5s games=%-6d rows=%-8d rows/game=%s\n"
                 % ("probe_search_9x9 (leg D1)", True, probe_games, probe_rows,
                    (probe_rows / probe_games) if probe_games else None))
    with open(out("nlwp_max", "txt"), "w") as fh:
        fh.write("nlwp_max -- node arxiv-1902.10565::synchronous_loop_smoke, S9; obligation o03, claim c06\n")
        fh.write("cpus_per_task = %d   ps samples = %d\n\n" % (cpus, mon["ps_samples"]))
        fh.write("per stage:\n")
        for k, v in sorted(mon["per_stage"].items()):
            fh.write("  %-12s nlwp_max=%-4d rss_kb_max=%-10d samples=%-7d elapsed_s=%s\n"
                     % (k, v["nlwp_max"], v["rss_kb_max"], v["samples"], v["elapsed_s"]))
        fh.write("\nper phase/stage (phase 'cycle1' = random-net bootstrap, no CUDA context;\n"
                 "'probe_search' and an accepted-net 'cycle2' are real-net with a live CUDA context):\n")
        for k, v in sorted(mon["per_phase_stage"].items()):
            fh.write("  %-28s nlwp_max=%-4d rss_kb_max=%-10d samples=%-7d elapsed_s=%s\n"
                     % (k, v["nlwp_max"], v["rss_kb_max"], v["samples"], v["elapsed_s"]))
        fh.write("\nsampling scope: %s\n" % mon["ps_scope"])
        fh.write("foreign pids excluded: %s\n" % (mon["foreign_pids_excluded"] or "none"))
        fh.write("\nper process (the attribution the stage numbers are built from):\n")
        for e in mon["per_pid"]:
            fh.write("  pid=%-8d %-11s nlwp_max=%-4d rss_kb_max=%-10d samples=%-6d elapsed_s=%-8s phases=%s%s\n"
                     % (e["pid"], e["stage"], e["nlwp_max"], e["rss_kb_max"], e["samples"],
                        e["elapsed_s"], ",".join(e["phases"]),
                        "   [EXCLUDED: foreign to this job]" if e["foreign"] else ""))

    # ---- print --------------------------------------------------------------
    print("audit_smoke -- node arxiv-1902.10565::synchronous_loop_smoke")
    print("  basedir       = %s" % W)
    print("  evidence      = %s" % ev)
    print("  cpus_per_task = %d   slurm job = %s" % (cpus, alloc.get("slurm_job_id")))
    print()
    print("  S1  CYCLES_COMPLETED   = %d   (expected %d)" % (cycles, EXPECTED_CYCLES))
    print("  S2  CANDIDATE_EXPORTED = %d   CANDIDATE_GATED = %d (won %d / lost %d)"
          % (len(exported), gated, won, lost))
    print("  S3  GATE_RANDOM        = %d" % gate_random)
    print("  S4  SZ_OTHER           = %d   rectangular = %d   (sgf lines %d selfplay + %d gatekeeper)"
          % (sz_other, rect, sp_sgfs["lines"], gk_sgfs["lines"]))
    print("  S5  ROW_BYTES raw      = %s over %d npz / %d rows;  shuffled = %s over %d npz / %d rows"
          % (raw["row_bytes_seen"], raw["files"], raw["rows"],
             shuf["row_bytes_seen"], shuf["files"], shuf["rows"]))
    print("  S6  GLOBAL_STEP_SAMPLES cycle1 = %s -> cycle2 = %s;  metrics lines = %d, nonfinite = %s;  reinit in cycle-2 log = %s"
          % (g1, g2, nlines, nonfinite or "none", reinit_cycle2))
    print("  S7  FULL_FRAC          = %s   band [%.2f, %.2f]" % (ff, FULL_FRAC_LO, FULL_FRAC_HI))
    print("  S8  ROWS_PER_GAME real = %s over %d games;  random = %s over %d games;  band [%d, %d]"
          % (rpg_real, real_games, rpg_rand, rand_games, ROWS_PER_GAME_LO, ROWS_PER_GAME_HI))
    print("  S8  BYTES_PER_GAME     = %s B = %.3f KiB over %d loop games;  c10 bound 10 KiB"
          % (round(bytes_per_game, 1) if bytes_per_game else None,
             (bytes_per_game / 1024.0) if bytes_per_game else 0.0, loop_games))
    print("  S9  NLWP_MAX per stage = %s   (cpus_per_task %d)" % (stage_max, cpus))
    print("  S11 probe_train pass   = %s   trunk_gpool_count = %s"
          % (probe_train.get("pass"), probe_train.get("trunk_gpool_count")))
    print("  S12 probe_resume pass  = %s   %s -> %s"
          % (probe_resume.get("pass"), probe_resume.get("global_step_samples_at_kill"),
             probe_resume.get("global_step_samples_after")))
    print("  S13 peak VRAM = %s MiB   gpu util max/mean = %s/%s %%   bytes/row on disk = %s"
          % (thr["peak_vram_mib"], thr["gpu_util_max_pct"], thr["gpu_util_mean_pct"],
             thr["bytes_per_row_on_disk"]))
    print()
    for c in checks:
        print("  %-6s %-8s %-36s %s"
              % ("ok" if c["pass"] else "FAIL", "hard" if c["hard"] else "recorded",
                 c["name"], c["detail"]))
    print()
    for p in raw["problems"][:10] + shuf["problems"][:10]:
        print("  npz problem: %s" % p)
    print("  wrote %s" % ", ".join(sorted(r["evidence_files"].values())))
    print("  ps samples from %s (%d rows)" % (mon["ps_file"], mon["ps_samples"]))
    print("AUDIT_SMOKE: %s" % ("PASS" if r["pass"] else "FAIL"))
    if soft_fail:
        print("RECORDED FINDINGS (not fatal): %s" % ", ".join(c["name"] for c in soft_fail))
    return 0 if r["pass"] else 1


def main(argv):
    args, evidence, snap_label, strict, tag = [], None, None, False, None
    trainingname = os.environ.get("KTG_SMOKE_TRAININGNAME", "t9")
    it = iter(argv[1:])
    for a in it:
        if a == "--evidence":
            evidence = next(it, None)
        elif a == "--snapshot":
            snap_label = next(it, None)
        elif a == "--trainingname":
            trainingname = next(it, None)
        elif a == "--tag":
            tag = next(it, None)
        elif a == "--strict":
            strict = True
        else:
            args.append(a)
    if not args:
        print(__doc__)
        return 2
    basedir = args[0]
    if snap_label:
        return snapshot(basedir, snap_label, trainingname)
    if evidence is None:
        print("--evidence <dir> is required for the audit mode")
        return 2
    return audit(basedir, evidence, trainingname, strict, tag)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
