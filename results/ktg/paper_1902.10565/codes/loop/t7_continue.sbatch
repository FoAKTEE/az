#!/bin/bash -l
# ^ the -l matters: without a login shell `module` is undefined on compute nodes.
#
# t7_continue.sbatch -- mission ktg-train, node arxiv-1902.10565::converged_test_7x7.
# ONE SEGMENT of the continued 7x7 run. Segments chain themselves with
# --dependency=afterany until the PLATEAU RULE fires.
#
# WHY THIS EXISTS. The human directive of 2026-09-04 (mission.json decisions) is that the
# 7x7 run must NOT stop at a hard time cap: it trains, and the curve is watched, until no
# progress is being made. A Slurm walltime cannot be extended, so "keep going" is realised
# as a CHAIN of segments over ONE run directory. The stopping condition is measured, not
# clocked: codes/eval/plateau_check.py.
#
# WHAT A SEGMENT DOES
#   0  marker gate  $BASEDIR/PLATEAU or $BASEDIR/ABORT present -> log and exit 0, submit
#                   nothing. This is what actually ends the chain.
#   1  preflight    the KTG_PRINT_EVERY patch, the 7x7 configs, the storage guard, and a
#                   RESUME assertion: models/, checkpoint.ckpt and .cycles_completed must
#                   already exist -- a segment never starts a run, it only continues one
#   2  cycles       gatekeeper -> selfplay -> shuffle -> train -> export via
#                   codes/loop/t7_cycle.sh, SAME BASEDIR, SAME knobs, SAME -lr-scale-auto,
#                   cycle labels continuing from $BASEDIR/.cycles_completed. After the
#                   segment's FIRST cycle the log is asserted to contain
#                   'Initializing new model!' ZERO times (train.py:799) -- a re-init would
#                   mean the run silently restarted from scratch, and that is fatal
#   3  plateau      plateau_check.py after EVERY cycle; every evaluation is a line in
#                   evidence/converged_7x7/plateau_log.txt
#   4  end          plateau  -> write $BASEDIR/PLATEAU, run the closing match, final
#                              summary, submit nothing
#                   diverge  -> write $BASEDIR/ABORT, summary, submit nothing, exit non-zero
#                   walltime -> finish the current cycle, write the summary, NO match, and
#                              submit the next segment
#
# THE MATCH RUNS ONLY WHEN THE PLATEAU RULE FIRES. A segment that ends on walltime exits
# cleanly after its last cycle and hands over; only the terminal segment measures strength.
#
# SEGMENT CAP = 12 (KTG_T7_MAX_SEGMENTS). At the 8 h default that is a bound of about
# 4 GPU-days. IT IS A SAFETY BOUND, NOT A TARGET -- the run is expected to end on the
# plateau rule long before it, and reaching the cap is itself a reportable outcome.
#
# CUMULATIVE vs PER-SEGMENT EVIDENCE. Files that describe the RUN carry the run name and
# are overwritten in place across segments: summary-t7.json, metrics_train-t7.json,
# running_metrics-t7.json, plateau_log.txt, status_log.txt. Files that describe ONE
# ALLOCATION carry the job id: allocation-<jobid>.json, segment-<jobid>.json,
# ktg-t7c-<jobid>.txt. Job 301096's own summary-301096.json and metrics_train-301096.json
# are left untouched as the first segment's record.
#
# usage (from the az root). Walltime is chosen at submission, not baked in, so a segment
# can be sized around the night's reservations:
#   POLICY=$(python3 -c 'import json;print(json.load(open("mission.json"))["compute"]["policyCheck"])')
#   bash "$POLICY" --gpus 1 --cpus 16 --partition b200,l40s
#   sbatch --time=08:00:00 --dependency=afterany:301096 \
#          results/ktg/paper_1902.10565/codes/loop/t7_continue.sbatch
#
#SBATCH --job-name=ktg-t7c
#SBATCH --account=ssci-anima
#SBATCH --partition=b200,l40s
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=08:00:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/ktg-t7c-%j.out
#SBATCH --error=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/ktg-t7c-%j.err

set -u
set -o pipefail

export KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
export AZ_ROOT="${AZ_ROOT:-/home/schmidt/ssci-haiyangw/az}"
export KTG_CODES="$AZ_ROOT/results/ktg/paper_1902.10565/codes"
EVID="$AZ_ROOT/results/ktg/paper_1902.10565/evidence/converged_7x7"

export KTG_T7_BASEDIR="${KTG_T7_BASEDIR:-$KTG_ROOT/runs/t7}"
W="$KTG_T7_BASEDIR"
TRAININGNAME="${KTG_T7_TRAININGNAME:-t7}"
export KTG_T7_TRAININGNAME="$TRAININGNAME"
BOARD=7
SAMPLES_PER_EPOCH=5000
GAMES_MIN=200
GAMES_MAX=1500
MATCH_GAMES="${KTG_T7_MATCH_GAMES:-200}"
SEG_HOURS="${KTG_T7_SEG_HOURS:-8}"
MAX_SEGMENTS="${KTG_T7_MAX_SEGMENTS:-12}"
export KTG_PRINT_EVERY="${KTG_PRINT_EVERY:-8}"
export KTG_POS_LEN=7

# plateau-rule parameters, all passed explicitly so the log records them
PLATEAU_WINDOW="${KTG_T7_PLATEAU_WINDOW:-50000}"
PLATEAU_REL="${KTG_T7_PLATEAU_REL:-0.01}"
PLATEAU_ACCEPT_CYCLES="${KTG_T7_PLATEAU_ACCEPT_CYCLES:-15}"
PLATEAU_DIVERGE="${KTG_T7_PLATEAU_DIVERGE:-0.05}"

JOBID="${SLURM_JOB_ID:-nojob}"
JOBLOG="$KTG_ROOT/logs/ktg-t7c-${JOBID}.out"
SUMMARY="$EVID/summary-t7.json"                 # cumulative: the RUN
METRICS_COPY="$EVID/metrics_train-t7.json"      # cumulative: the RUN
RUNMETRICS="$EVID/running_metrics-t7.json"      # cumulative: the RUN
PLATEAU_LOG="$EVID/plateau_log.txt"             # cumulative: the RUN
STATUS="$EVID/status_log.txt"                   # cumulative: the RUN
PLATEAU_STATE="$W/plateau_state.json"           # cumulative: the RUN
META="$EVID/allocation-${JOBID}.json"           # per segment
SEGREC="$EVID/segment-${JOBID}.json"            # per segment

mkdir -p "$W" "$W/logs" "$EVID" "$KTG_ROOT/logs"
say() { echo "=== [$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

set +u
# shellcheck disable=SC1091
source "$KTG_ROOT/env.sh"
set -u

OVERALL=0
ABORT=""
ENDED_ON=""          # plateau | diverge | walltime | cycle_failure | cap
MONPID=""

# ------------------------------------------------------- 0. the marker gate
# This, not the walltime, is what ends the chain.
for m in PLATEAU ABORT; do
  if [ -e "$W/$m" ]; then
    say "$m marker present at $W/$m -- the run is over; this segment submits nothing and exits 0"
    cat "$W/$m" 2>/dev/null || true
    exit 0
  fi
done

SEGMENT=$(( $(cat "$W/.segment_count" 2>/dev/null || echo 0) + 1 ))
case "$SEGMENT" in ''|*[!0-9]*) SEGMENT=1 ;; esac
echo "$SEGMENT" > "$W/.segment_count"

T_START=$(date +%s)
TL="$(squeue -h -j "$JOBID" -o '%l' 2>/dev/null | tr -d ' ')"
WALL_S="$(python3 - "$TL" <<'PY'
import sys
s = (sys.argv[1] or "").strip()
try:
    d, _, rest = s.partition("-")
    days, hms = (int(d), rest) if rest else (0, s)
    parts = [int(x) for x in hms.split(":")]
    while len(parts) < 3:
        parts.insert(0, 0)
    h, m, sec = parts[-3:]
    total = days * 86400 + h * 3600 + m * 60 + sec
    print(total if 600 <= total <= 3 * 86400 else 28800)
except Exception:
    print(28800)
PY
)"
RESERVE_S=1200                      # 20 min, per the directive
CYCLE_DEADLINE=$(( T_START + WALL_S - RESERVE_S ))
CYCLES_AT_START="$(cat "$W/.cycles_completed" 2>/dev/null || echo 0)"
case "$CYCLES_AT_START" in ''|*[!0-9]*) CYCLES_AT_START=0 ;; esac

echo "======================================================================"
echo "ktg-t7c  SEGMENT $SEGMENT of at most $MAX_SEGMENTS  job=$JOBID  host=$(hostname)"
echo "  start          = $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  basedir        = $W   (CONTINUED, not re-initialised)"
echo "  cycles so far  = $CYCLES_AT_START"
echo "  partition      = ${SLURM_JOB_PARTITION:-?}   cpus = ${SLURM_CPUS_PER_TASK:-?}   mem = ${SLURM_MEM_PER_NODE:-?}   gres = gpu:1"
echo "  walltime       = ${WALL_S}s  (squeue '%l' = '${TL:-unset}')   reserve = ${RESERVE_S}s"
echo "  cycle deadline = $(date -u -d "@$CYCLE_DEADLINE" +%Y-%m-%dT%H:%M:%SZ)"
echo "  plateau rule   = trailing ${PLATEAU_WINDOW}-sample windows; BOTH rel improvements"
echo "                   < $(python3 -c "print($PLATEAU_REL*100)")% on 2 consecutive evaluations"
echo "                   AND no gatekeeper acceptance for $PLATEAU_ACCEPT_CYCLES cycles"
echo "  divergence     = p0loss rising more than $(python3 -c "print($PLATEAU_DIVERGE*100)")% over ${PLATEAU_WINDOW} samples"
echo "  segment cap    = $MAX_SEGMENTS segments -- a SAFETY BOUND, not a target; the run is"
echo "                   expected to end on the plateau rule long before it"
echo "======================================================================"
nvidia-smi --query-gpu=index,name,compute_cap,memory.total --format=csv,noheader || true

cat > "$META" <<JSON
{
 "slurm_job_id": "$JOBID",
 "segment": $SEGMENT,
 "node": "$(hostname)",
 "partition": "${SLURM_JOB_PARTITION:-unknown}",
 "gpu_name": "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)",
 "cpus_per_task": ${SLURM_CPUS_PER_TASK:-16},
 "mem_mb": ${SLURM_MEM_PER_NODE:-98304},
 "gpus": 1,
 "walltime_s": $WALL_S,
 "reserve_s": $RESERVE_S,
 "cycles_at_start": $CYCLES_AT_START,
 "started_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

# ----------------------------------------------------------- 1. preflight
PRE_RC=0
grep -q 'KTG_PRINT_EVERY' "$KATAGO_SRC/python/train.py" \
  || { echo "  [FAIL] the scratch clone's train.py lost the KTG_PRINT_EVERY hook" >&2; PRE_RC=1; }
for f in "$KTG_CODES/cfg/selfplay_7x7.cfg" "$KTG_CODES/cfg/gatekeeper_7x7.cfg" \
         "$KTG_CODES/cfg/match_first_latest_7.cfg" "$KTG_CODES/loop/t7_cycle.sh" \
         "$KTG_CODES/eval/summarize_7x7_run.py" "$KTG_CODES/eval/plateau_check.py"; do
  [ -f "$f" ] || { echo "  [FAIL] missing $f" >&2; PRE_RC=1; }
done
# A segment CONTINUES a run; it must never be the thing that starts one.
[ -f "$W/train/$TRAININGNAME/checkpoint.ckpt" ] \
  || { echo "  [FAIL] no checkpoint at $W/train/$TRAININGNAME/checkpoint.ckpt -- refusing to start a fresh run" >&2; PRE_RC=1; }
[ "$CYCLES_AT_START" -ge 1 ] \
  || { echo "  [FAIL] .cycles_completed = $CYCLES_AT_START -- there is no run to continue" >&2; PRE_RC=1; }
echo "  [ok] resuming: $(ls -1 "$W/models" 2>/dev/null | wc -l) accepted net(s), checkpoint $(stat -c %s "$W/train/$TRAININGNAME/checkpoint.ckpt" 2>/dev/null) bytes, $CYCLES_AT_START cycles"
bash "$KTG_CODES/data_budget/scratch_guard.sh" --label "converged_test_7x7 segment $SEGMENT job $JOBID" || PRE_RC=1
if [ "$PRE_RC" -ne 0 ]; then
  say "preflight FAILED -- no cycle run, no successor submitted"
  exit 2
fi
if [ -e "$W/STOP" ]; then
  say "NOTE: removing a stale $W/STOP left by an earlier segment"
  cp "$W/STOP" "$W/STOP.previous-$JOBID" 2>/dev/null || true
  rm -f "$W/STOP"
fi

# games/cycle, re-derived from THIS run's own data so a segment never inherits a stale number
GAMES="$(python3 - "$W" "$SAMPLES_PER_EPOCH" "$GAMES_MIN" "$GAMES_MAX" "$KTG_CODES/eval/check_pos_len_npz.py" <<'PY'
import glob, json, math, os, subprocess, sys
b, E, lo, hi, checker = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
env = dict(os.environ); env["KTG_POS_LEN"] = "7"
rows = 0
try:
    out = subprocess.run([sys.executable, checker, "--json", os.path.join(b, "selfplay")],
                         capture_output=True, text=True, env=env)
    rows = json.loads(out.stdout).get("total_rows", 0)
except Exception:
    rows = 0
games = 0
for f in glob.glob(os.path.join(b, "selfplay", "*", "sgfs", "*.sgfs")):
    try:
        with open(f, errors="replace") as fh:
            games += sum(1 for line in fh if line.strip())
    except OSError:
        pass
r = (rows / games) if games else 0.0
print(max(lo, min(hi, hi if r <= 0 else int(math.ceil(1.2 * E / r)))))
PY
)"
say "games/cycle for this segment = $GAMES (re-derived from the run's own rows/game)"

# --------------------------------------------- 2. background evidence writers
status_line() {
  local why="$1" n
  n="$(python3 - "$SUMMARY" <<'PY' 2>/dev/null || echo "summary not written yet"
import json, sys
try:
    s = json.load(open(sys.argv[1]))
except Exception:
    print("summary not written yet"); raise SystemExit
lo = s.get("loss_log", {}); last = lo.get("last") or {}
print("cycles=%s samples=%s loss_rows=%s p0loss=%s(min %s) vloss=%s(min %s) exports=%s accepted=%s rejected=%s"
      % (s.get("cycles_completed"), s.get("samples_total"), lo.get("rows"),
         last.get("p0loss"), lo.get("min_p0loss"), last.get("vloss"), lo.get("min_vloss"),
         s.get("export_count"), len(s.get("accepted") or []), len(s.get("rejected") or [])))
PY
)"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) job=$JOBID seg=$SEGMENT node=$(hostname -s) part=${SLURM_JOB_PARTITION:-?} [$why] $n" >> "$STATUS"
}

monitor() {
  local tick=0
  while :; do
    sleep 600
    tick=$((tick + 1))
    cp "$W/train/$TRAININGNAME/metrics_train.json" "$METRICS_COPY" 2>/dev/null || true
    python3 - "$W/train/$TRAININGNAME" "$RUNMETRICS" "$JOBID" <<'PY' 2>/dev/null || true
import json, os, sys
traindir, out, jobid = sys.argv[1:4]
rec = {"slurm_job_id": jobid, "traindir": traindir, "checkpoints": {}}
try:
    import torch
    for name in ("checkpoint.ckpt", "checkpoint_prev0.ckpt"):
        p = os.path.join(traindir, name)
        if not os.path.isfile(p):
            continue
        d = torch.load(p, map_location="cpu", weights_only=False)
        rm = d.get("running_metrics", {}) or {}
        sums, weights = rm.get("sums", {}) or {}, rm.get("weights", {}) or {}
        ts = d.get("train_state", {}) or {}
        vals = {}
        for k in ("p0loss_sum", "vloss_sum", "loss_sum", "smloss_sum", "tdvloss_sum"):
            w = weights.get(k)
            if w:
                vals[k[:-4]] = sums[k] / w
        rec["checkpoints"][name] = {
            "bytes": os.path.getsize(p),
            "global_step_samples": ts.get("global_step_samples"),
            "total_num_data_rows": ts.get("total_num_data_rows"),
            "running_metrics_nsamp": sums.get("nsamp"),
            "running_metrics_means": vals,
        }
except Exception as e:
    rec["error"] = "%s: %s" % (type(e).__name__, e)
json.dump(rec, open(out, "w"), indent=1, sort_keys=True)
PY
    [ $((tick % 3)) -eq 0 ] && status_line "monitor"
  done
}

summarize() {
  local extra=()
  [ -n "${FIRST_EXPORT_NAME:-}" ] && extra+=(--first-export "$FIRST_EXPORT_NAME")
  [ -n "$ABORT" ] && extra+=(--abort "$ABORT")
  python3 "$KTG_CODES/eval/summarize_7x7_run.py" "$W" \
      --out "$SUMMARY" --board "$BOARD" --training-name "$TRAININGNAME" \
      --samples-per-epoch "$SAMPLES_PER_EPOCH" --meta "$META" \
      "${extra[@]}" "$@"
}

FIRST_EXPORT_NAME=""
[ -f "$W/first_export.json" ] && FIRST_EXPORT_NAME="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("name",""))' "$W/first_export.json" 2>/dev/null || echo "")"

resolve_model() {
  local name="$1" d
  for d in models rejectedmodels modelstobetested models_extra modelsuploaded; do
    [ -f "$W/$d/$name/model.bin.gz" ] && { echo "$W/$d/$name/model.bin.gz"; return 0; }
  done
  return 1
}

# --------------------------------------------------------------- 3. cycles
monitor & MONPID=$!
trap 'kill "$MONPID" 2>/dev/null || true' EXIT
status_line "segment${SEGMENT}_start"

SEG_CYCLES=0
while :; do
  NOW=$(date +%s); LEFT=$(( CYCLE_DEADLINE - NOW ))
  if [ "$LEFT" -le 0 ]; then
    ENDED_ON="walltime"
    say "cycle deadline reached after $SEG_CYCLES cycle(s) in this segment -- handing over, NO match"
    break
  fi
  GLOBAL=$(( $(cat "$W/.cycles_completed" 2>/dev/null || echo 0) + 1 ))
  case "$GLOBAL" in ''|*[!0-9]*) GLOBAL=$(( CYCLES_AT_START + SEG_CYCLES + 1 )) ;; esac
  LABEL="s${SEGMENT}c${GLOBAL}"
  SEG_CYCLES=$((SEG_CYCLES + 1))
  say "segment $SEGMENT cycle $SEG_CYCLES (run cycle $GLOBAL): games=$GAMES  ${LEFT}s left"
  set +e
  bash "$KTG_CODES/loop/t7_cycle.sh" "$LABEL" "$GAMES"
  RC=$?
  set -e
  say "run cycle $GLOBAL: t7_cycle exit=$RC"

  # The RESUME assertion, on the segment's FIRST cycle only. train.py:799 logs
  # 'Initializing new model!' exactly when it builds a fresh net; seeing it here would
  # mean this segment silently restarted the run rather than continuing it.
  if [ "$SEG_CYCLES" -eq 1 ]; then
    NINIT="$(grep -ac 'Initializing new model!' "$W/logs/t7_${LABEL}.txt" 2>/dev/null || echo 0)"
    echo "  resume assertion: 'Initializing new model!' occurrences in this segment's first cycle log = $NINIT (must be 0)"
    if [ "$NINIT" -ne 0 ]; then
      ABORT="segment $SEGMENT RE-INITIALISED the model ($NINIT occurrence(s) in $W/logs/t7_${LABEL}.txt) -- the run did not continue"
      ENDED_ON="cycle_failure"; OVERALL=1
      say "FATAL: $ABORT"
      date -u +%Y-%m-%dT%H:%M:%SZ > "$W/ABORT"; echo "$ABORT" >> "$W/ABORT"
      break
    fi
  fi

  if [ "$RC" -ne 0 ]; then
    ABORT="run cycle $GLOBAL exited $RC -- see $W/logs/t7_${LABEL}.txt"
    ENDED_ON="cycle_failure"; OVERALL=1
    say "STOPPING: $ABORT"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$W/ABORT"; echo "$ABORT" >> "$W/ABORT"
    break
  fi

  [ -z "$FIRST_EXPORT_NAME" ] && [ -f "$W/first_export.json" ] && \
    FIRST_EXPORT_NAME="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("name",""))' "$W/first_export.json" 2>/dev/null || echo "")"

  summarize || true
  cp "$W/train/$TRAININGNAME/metrics_train.json" "$METRICS_COPY" 2>/dev/null || true

  # --- THE STOPPING RULE, evaluated every cycle and logged every time -------
  set +e
  python3 "$KTG_CODES/eval/plateau_check.py" "$W" \
      --log "$PLATEAU_LOG" --state "$PLATEAU_STATE" --job "$JOBID" \
      --window "$PLATEAU_WINDOW" --rel "$PLATEAU_REL" \
      --accept-cycles "$PLATEAU_ACCEPT_CYCLES" --diverge "$PLATEAU_DIVERGE" \
      --training-name "$TRAININGNAME" --json "$EVID/plateau_last.json"
  PRC=$?
  set -e
  status_line "cycle$GLOBAL"

  if [ "$PRC" -eq 10 ]; then
    ENDED_ON="plateau"
    say "PLATEAU RULE FIRED at run cycle $GLOBAL -- the run is done; the closing match runs now"
    { date -u +%Y-%m-%dT%H:%M:%SZ; echo "plateau at run cycle $GLOBAL, job $JOBID, segment $SEGMENT";
      tail -1 "$PLATEAU_LOG"; } > "$W/PLATEAU"
    break
  elif [ "$PRC" -eq 20 ]; then
    ABORT="DIVERGENCE: $(tail -1 "$PLATEAU_LOG")"
    ENDED_ON="diverge"; OVERALL=1
    say "DIVERGENCE ABORT at run cycle $GLOBAL -- stopping and reporting as measured, not retuning"
    { date -u +%Y-%m-%dT%H:%M:%SZ; echo "$ABORT"; } > "$W/ABORT"
    break
  fi

  if [ "$SEG_CYCLES" -ge 1 ] && [ "$((SEG_CYCLES % 25))" -eq 0 ]; then
    say "segment $SEGMENT: $SEG_CYCLES cycles done, run cycle $GLOBAL, $(( CYCLE_DEADLINE - $(date +%s) ))s left"
  fi
done

# ---------------------------------------------------- 4. match, ONLY on plateau
MATCH_OK=0
MATCH_NOTE=""
if [ "$ENDED_ON" = "plateau" ]; then
  MATCH_SGFS="$W/match-${JOBID}"
  run_match() {
    local first_path latest_name latest_path
    [ -n "$FIRST_EXPORT_NAME" ] || { MATCH_NOTE="no first export was ever recorded"; return 1; }
    first_path="$(resolve_model "$FIRST_EXPORT_NAME")" || { MATCH_NOTE="the frozen first export '$FIRST_EXPORT_NAME' cannot be resolved"; return 1; }
    latest_name="$(python3 - "$W" <<'PY'
import os, re, sys
b = sys.argv[1]; SD = re.compile(r"-s(\d+)-d(\d+)$"); best = None
p = os.path.join(b, "models")
if os.path.isdir(p):
    for n in os.listdir(p):
        if not os.path.isfile(os.path.join(p, n, "model.bin.gz")):
            continue
        m = SD.search(n); k = int(m.group(1)) if m else -1
        if best is None or k > best[0]:
            best = (k, n)
print(best[1] if best else "")
PY
)"
    [ -n "$latest_name" ] || { MATCH_NOTE="no gatekeeper-accepted net exists"; return 1; }
    latest_path="$(resolve_model "$latest_name")" || { MATCH_NOTE="the latest accepted net '$latest_name' holds no model.bin.gz"; return 1; }
    [ "$latest_path" != "$first_path" ] || { MATCH_NOTE="the latest accepted net IS the first export ($latest_name)"; return 1; }
    mkdir -p "$MATCH_SGFS"
    say "closing match: first='$FIRST_EXPORT_NAME' vs latest='$latest_name', $MATCH_GAMES games, 7x7, 100 visits, balanced colours"
    echo "  first  : $first_path  sha256 $(sha256sum "$first_path" | cut -d' ' -f1)"
    echo "  latest : $latest_path  sha256 $(sha256sum "$latest_path" | cut -d' ' -f1)"
    "$KATAGO_BIN" match -config "$KTG_CODES/cfg/match_first_latest_7.cfg" \
      -override-config "nnModelFile0=$first_path,nnModelFile1=$latest_path,numGamesTotal=$MATCH_GAMES" \
      -sgf-output-dir "$MATCH_SGFS" -log-file "$W/logs/match-${JOBID}.log"
    local rc=$?
    say "katago match exit=$rc"
    python3 "$KATAGO_SRC/python/summarize_sgfs.py" "$MATCH_SGFS" -recursive 2>&1 \
      | tee "$EVID/match_summary-${JOBID}.txt" || true
    return "$rc"
  }
  set +e; run_match; MRC=$?; set -e
  if [ "$MRC" -eq 0 ]; then MATCH_OK=1; else
    say "match not run or failed (rc=$MRC): ${MATCH_NOTE:-see above}"; OVERALL=1
  fi
else
  MATCH_NOTE="segment ended on '$ENDED_ON'; the match runs only when the plateau rule fires"
  say "$MATCH_NOTE"
fi

# ------------------------------------------------------------- 5. summarise
kill "$MONPID" 2>/dev/null || true
cp "$W/train/$TRAININGNAME/metrics_train.json" "$METRICS_COPY" 2>/dev/null || true
if [ "$MATCH_OK" -eq 1 ]; then
  summarize --match-sgfs "$MATCH_SGFS" --bot-first first --bot-latest latest || OVERALL=1
else
  summarize || OVERALL=1
fi
CYCLES_NOW="$(cat "$W/.cycles_completed" 2>/dev/null || echo 0)"
cat > "$SEGREC" <<JSON
{
 "slurm_job_id": "$JOBID",
 "segment": $SEGMENT,
 "max_segments": $MAX_SEGMENTS,
 "node": "$(hostname)",
 "partition": "${SLURM_JOB_PARTITION:-unknown}",
 "cycles_at_start": $CYCLES_AT_START,
 "cycles_at_end": ${CYCLES_NOW:-0},
 "cycles_this_segment": $SEG_CYCLES,
 "games_per_cycle": $GAMES,
 "ended_on": "$ENDED_ON",
 "match_ran": $( [ "$MATCH_OK" -eq 1 ] && echo true || echo false ),
 "match_note": "${MATCH_NOTE:-}",
 "abort": "${ABORT:-}",
 "ended_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
status_line "segment${SEGMENT}_end_${ENDED_ON}"
cp "$W/logs/match-${JOBID}.log" "$EVID/match-${JOBID}.log" 2>/dev/null || true

# ------------------------------------------- 6. hand over, or end the chain
NEXT=""
if [ "$ENDED_ON" = "walltime" ]; then
  if [ -e "$W/PLATEAU" ] || [ -e "$W/ABORT" ]; then
    say "a marker appeared during this segment -- not submitting a successor"
  elif [ "$SEGMENT" -ge "$MAX_SEGMENTS" ]; then
    say "SEGMENT CAP REACHED: this was segment $SEGMENT of $MAX_SEGMENTS. The cap is a SAFETY"
    say "BOUND, not a target -- reaching it means the plateau rule never fired, which is"
    say "itself the finding to report. Not submitting a successor."
    ENDED_ON="cap"; OVERALL=1
  else
    POLICY="$(python3 -c 'import json;print(json.load(open("mission.json"))["compute"]["policyCheck"])' 2>/dev/null || echo "")"
    cd "$AZ_ROOT" || true
    say "policy self-check before submitting segment $((SEGMENT + 1)) (mission.json compute.policyCheck)"
    set +e
    bash "$POLICY" --gpus 1 --cpus 16 --partition b200,l40s 2>&1 | tee "$EVID/compute_budget_check-seg$((SEGMENT + 1)).txt"
    PRC="${PIPESTATUS[0]}"
    set -e
    if [ "$PRC" -ne 0 ]; then
      say "POLICY CHECK FAILED (exit $PRC) -- refusing to submit segment $((SEGMENT + 1))"
      OVERALL=1
    else
      NEXT="$(sbatch --parsable --time="${SEG_HOURS}:00:00" \
                --dependency=afterany:"$JOBID" \
                "$KTG_CODES/loop/t7_continue.sbatch" 2>&1 | tail -1)"
      say "submitted segment $((SEGMENT + 1)) as job ${NEXT:-<failed>} (--dependency=afterany:$JOBID, --time=${SEG_HOURS}:00:00)"
      echo "$NEXT" > "$W/.next_segment_job"
    fi
  fi
else
  say "chain ends here: ended_on=$ENDED_ON. No successor submitted."
fi

sleep 2
cp "$JOBLOG" "$EVID/ktg-t7c-${JOBID}.txt" 2>/dev/null || true

echo
echo "======================================================================"
echo "ktg-t7c segment $SEGMENT  job=$JOBID  end=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  cycles this segment : $SEG_CYCLES   run cycles total: ${CYCLES_NOW:-?}"
echo "  ended on            : $ENDED_ON"
echo "  match ran           : $MATCH_OK  ${MATCH_NOTE:-}"
echo "  successor           : ${NEXT:-none}"
echo "  plateau log         : $PLATEAU_LOG"
tail -1 "$PLATEAU_LOG" 2>/dev/null || true
python3 -c "
import json
s=json.load(open('$SUMMARY'))
lo=s.get('loss_log',{}); last=lo.get('last') or {}; m=s.get('match') or {}
print('  loss rows           : %s' % lo.get('rows'))
print('  p0loss first/min/last: %s / %s / %s  (uniform %.4f, target < 2.5)'
      % (lo.get('first_p0loss'), lo.get('min_p0loss'), last.get('p0loss'),
         s['criteria']['uniform_policy_baseline']))
print('  vloss  min/last     : %s / %s' % (lo.get('min_vloss'), last.get('vloss')))
print('  exports/accepted    : %s / %s' % (s.get('export_count'), len(s.get('accepted') or [])))
if m: print('  match latest-first  : %s-%s (%s draws), score %s, Elo %s'
            % (m.get('latest_wins'), m.get('first_wins'), m.get('draws'),
               m.get('score_latest'), m.get('elo_latest_minus_first')))
print('  CONVERGED           : %s' % s.get('converged'))
" 2>/dev/null || true
echo "  overall             = $OVERALL"
echo "======================================================================"
exit "$OVERALL"
