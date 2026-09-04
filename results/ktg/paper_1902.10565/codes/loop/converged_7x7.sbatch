#!/bin/bash -l
# ^ the -l matters: without a login shell `module` is undefined on compute nodes.
#
# converged_7x7.sbatch -- mission ktg-train, node arxiv-1902.10565::converged_test_7x7.
# THE job for tasks/converged_test_7x7. ONE short interactive-class allocation:
# 1 GPU, 16 CPUs, 96 G, 6 h, b200 OR l40s -- whichever frees first.
#
# WHAT IT DOES, in one allocation:
#   1  preflight   assert the KTG_PRINT_EVERY patch is in the scratch clone, assert the
#                  7x7 configs say what they claim, record the allocation, storage guard
#   2  cycles      gatekeeper -> selfplay -> shuffle -> train -> export, one cycle at a
#                  time via codes/loop/t7_cycle.sh (KTG_ONE_CYCLE=1), until
#                  T_start + walltime - 35 min. Cycle 1 runs 600 games; rows/game is then
#                  MEASURED and games/cycle re-derived as ceil(1.2*E/r).
#   3  match       200 games, balanced colours, fixed 100 visits, 7x7: the LATEST ACCEPTED
#                  net against the FIRST EXPORTED net of this same run
#   4  summary     evidence/converged_7x7/summary-<jobid>.json, rewritten after EVERY
#                  cycle so the curve can be plotted mid-run, and once more after the match
#
# ABORT RULES (tasks/converged_test_7x7/implementation.md section 11). Neither one tunes
# anything: both stop the cycle loop, write the summary, and make the job exit non-zero.
#   A1  no export by the end of cycle 6
#   A2  min p0loss still >= 3.5 once 15000 samples have been trained
#
# WHY IT IS SAFE FOR THE QUEUED 9x9 CHAIN (job 299461, PENDING at submission time).
# Everything 7x7 travels in the ENVIRONMENT (KTG_POS_LEN, KTG_PRINT_EVERY,
# SELFPLAY_CONFIG, GATING_CONFIG and the knob block), never as an edit to a 9x9 default.
# The three shared files that changed carry `${KTG_POS_LEN:-9}` / `KTG_PRINT_EVERY`
# defaults, so a caller that exports nothing -- the chain -- sees the previous behaviour.
# codes/eval/check_board_param.sh proves both directions and is this node's verifier.
#
# usage (from the az root). The policy self-check is NOT optional and its path is not
# written here: it is whatever mission.json names, so the two can never drift apart.
#   POLICY=$(python3 -c 'import json;print(json.load(open("mission.json"))["compute"]["policyCheck"])')
#   bash "$POLICY" --gpus 1 --cpus 16 --partition b200,l40s      # must exit 0
#   sbatch results/ktg/paper_1902.10565/codes/loop/converged_7x7.sbatch
#
#SBATCH --job-name=ktg-t7
#SBATCH --account=ssci-anima
#SBATCH --partition=b200,l40s
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=06:00:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/ktg-t7-%j.out
#SBATCH --error=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/ktg-t7-%j.err

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
GAMES_CYCLE1="${KTG_T7_GAMES1:-600}"
GAMES_MIN=200
GAMES_MAX=1500
MATCH_GAMES="${KTG_T7_MATCH_GAMES:-200}"
export KTG_PRINT_EVERY="${KTG_PRINT_EVERY:-8}"
export KTG_POS_LEN=7

JOBID="${SLURM_JOB_ID:-nojob}"
JOBLOG="$KTG_ROOT/logs/ktg-t7-${JOBID}.out"
SUMMARY="$EVID/summary-${JOBID}.json"
META="$W/allocation-${JOBID}.json"
STATUS="$EVID/status_log.txt"

mkdir -p "$W" "$W/logs" "$EVID" "$KTG_ROOT/logs"

say() { echo "=== [$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# env.sh sources the venv activate script, which is not written for `set -u`.
set +u
# shellcheck disable=SC1091
source "$KTG_ROOT/env.sh"
set -u

OVERALL=0
ABORT=""

# ------------------------------------------------------------------ 0. deadline
T_START=$(date +%s)
# The honest walltime, read from the scheduler rather than assumed. squeue prints the
# limit as [D-]HH:MM:SS; anything unparsable falls back to the 6 h in the header.
TL="$(squeue -h -j "$JOBID" -o '%l' 2>/dev/null | tr -d ' ')"
WALL_S="$(python3 - "$TL" <<'PY'
import sys
s = (sys.argv[1] or "").strip()
try:
    d, _, rest = s.partition("-")
    if rest:
        days, hms = int(d), rest
    else:
        days, hms = 0, s
    parts = [int(x) for x in hms.split(":")]
    while len(parts) < 3:
        parts.insert(0, 0)
    h, m, sec = parts[-3:]
    total = days * 86400 + h * 3600 + m * 60 + sec
    print(total if 600 <= total <= 3 * 86400 else 21600)
except Exception:
    print(21600)
PY
)"
RESERVE_S=2100                       # 35 min: the 200-game match plus summary and margin
CYCLE_DEADLINE=$(( T_START + WALL_S - RESERVE_S ))

echo "======================================================================"
echo "ktg-t7 (converged 7x7 test)  job=$JOBID  host=$(hostname)  start=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  basedir        = $W"
echo "  codes          = $KTG_CODES"
echo "  evidence       = $EVID"
echo "  partition      = ${SLURM_JOB_PARTITION:-?}   cpus = ${SLURM_CPUS_PER_TASK:-?}   mem = ${SLURM_MEM_PER_NODE:-?}   gres = gpu:1"
echo "  walltime       = ${WALL_S}s  (squeue '%l' = '${TL:-unset}')"
echo "  cycle deadline = $(date -u -d "@$CYCLE_DEADLINE" +%Y-%m-%dT%H:%M:%SZ)  (reserve ${RESERVE_S}s for the match)"
echo "  pos_len        = $KTG_POS_LEN   print_every = $KTG_PRINT_EVERY   samples/epoch = $SAMPLES_PER_EPOCH"
echo "======================================================================"
scontrol show job "$JOBID" 2>/dev/null | sed -n '1,12p' || true
nvidia-smi --query-gpu=index,name,compute_cap,memory.total,driver_version --format=csv,noheader || true
python3 /apps/helpers/quotas.py 2>/dev/null || true

cat > "$META" <<JSON
{
 "slurm_job_id": "$JOBID",
 "node": "$(hostname)",
 "partition": "${SLURM_JOB_PARTITION:-unknown}",
 "gpu_name": "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)",
 "gpu_compute_cap": "$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)",
 "cpus_per_task": ${SLURM_CPUS_PER_TASK:-16},
 "mem_mb": ${SLURM_MEM_PER_NODE:-98304},
 "gpus": 1,
 "walltime_s": $WALL_S,
 "reserve_s": $RESERVE_S,
 "started_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
cp "$META" "$EVID/allocation-${JOBID}.json" 2>/dev/null || true

# ----------------------------------------------------------------- 1. preflight
say "preflight"

PRE_RC=0
if grep -q 'KTG_PRINT_EVERY' "$KATAGO_SRC/python/train.py"; then
  echo "  [ok] scratch clone train.py carries the KTG_PRINT_EVERY hook"
  echo "       sha256 $(sha256sum "$KATAGO_SRC/python/train.py" | cut -d' ' -f1)"
else
  echo "  [FAIL] $KATAGO_SRC/python/train.py has no KTG_PRINT_EVERY hook -- the loss log" >&2
  echo "         would be empty at $SAMPLES_PER_EPOCH samples/epoch. Apply" >&2
  echo "         codes/env/train-print-every.diff and resubmit." >&2
  PRE_RC=1
fi
for f in "$KTG_CODES/cfg/selfplay_7x7.cfg" "$KTG_CODES/cfg/gatekeeper_7x7.cfg" \
         "$KTG_CODES/cfg/match_first_latest_7.cfg" "$KTG_CODES/loop/t7_cycle.sh" \
         "$KTG_CODES/eval/summarize_7x7_run.py"; do
  [ -f "$f" ] || { echo "  [FAIL] missing $f" >&2; PRE_RC=1; }
done
echo "  selfplay_7x7  : $(grep -E '^(dataBoardLen|bSizes|maxVisits|cheapSearchVisits|numGameThreads) *=' "$KTG_CODES/cfg/selfplay_7x7.cfg" | tr '\n' ' ')"
echo "  gatekeeper_7x7: $(grep -E '^(bSizes|maxVisits|numGamesPerGating|numGameThreads) *=' "$KTG_CODES/cfg/gatekeeper_7x7.cfg" | tr '\n' ' ')"
bash "$KTG_CODES/data_budget/scratch_guard.sh" --label "converged_test_7x7 job $JOBID preflight" || PRE_RC=1
if [ "$PRE_RC" -ne 0 ]; then
  say "preflight FAILED -- not starting a cycle"
  exit 2
fi

# A resubmission must not inherit a STOP file: the loop exits 0 immediately when one is
# present and the cycle would silently not run.
if [ -e "$W/STOP" ]; then
  say "NOTE: $W/STOP exists from an earlier attempt; recording and removing it"
  cp "$W/STOP" "$W/STOP.previous-$JOBID" 2>/dev/null || true
  rm -f "$W/STOP"
fi

# ------------------------------------------------------- 2. background evidence
# Every 10 min: copy the dense loss log and snapshot the checkpoint's running_metrics.
# Every 30 min: append one status line. Both write into the az repo's evidence dir so the
# coordinator can plot and read progress while the allocation is still running.
MONPID=""
monitor() {
  local tick=0
  while :; do
    sleep 600
    tick=$((tick + 1))
    cp "$W/train/$TRAININGNAME/metrics_train.json" "$EVID/metrics_train-${JOBID}.json" 2>/dev/null || true
    python3 - "$W/train/$TRAININGNAME" "$EVID/running_metrics-${JOBID}.json" "$JOBID" <<'PY' 2>/dev/null || true
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
            "export_cycle_counter": ts.get("export_cycle_counter"),
            "running_metrics_nsamp": sums.get("nsamp"),
            "running_metrics_terms": len(sums),
            "running_metrics_means": vals,
        }
except Exception as e:
    rec["error"] = "%s: %s" % (type(e).__name__, e)
json.dump(rec, open(out, "w"), indent=1, sort_keys=True)
PY
    if [ $((tick % 3)) -eq 0 ]; then
      status_line "monitor"
    fi
  done
}

status_line() {
  local why="$1" n
  n="$(python3 - "$SUMMARY" <<'PY' 2>/dev/null || echo "summary not written yet"
import json, sys
try:
    s = json.load(open(sys.argv[1]))
except Exception:
    print("summary not written yet"); raise SystemExit
last = s.get("loss_log", {}).get("last") or {}
lo = s.get("loss_log", {})
print("cycles=%s samples=%s loss_rows=%s p0loss=%s(min %s) vloss=%s(min %s) exports=%s accepted=%s rejected=%s"
      % (s.get("cycles_completed"), s.get("samples_total"), lo.get("rows"),
         last.get("p0loss"), lo.get("min_p0loss"), last.get("vloss"), lo.get("min_vloss"),
         s.get("export_count"), len(s.get("accepted") or []), len(s.get("rejected") or [])))
PY
)"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) job=$JOBID node=$(hostname -s) part=${SLURM_JOB_PARTITION:-?} [$why] $n" >> "$STATUS"
}

# --------------------------------------------------------------- helpers
summarize() {
  # any extra arguments are appended verbatim (the match block adds --match-sgfs ...).
  # The optional flags go through an ARRAY, not ${VAR:+...}: the abort reason contains
  # spaces and an unquoted conditional expansion would split it into several arguments.
  local extra=()
  [ -n "$FIRST_EXPORT_NAME" ] && extra+=(--first-export "$FIRST_EXPORT_NAME")
  [ -n "$ABORT" ] && extra+=(--abort "$ABORT")
  python3 "$KTG_CODES/eval/summarize_7x7_run.py" "$W" \
      --out "$SUMMARY" --board "$BOARD" --training-name "$TRAININGNAME" \
      --samples-per-epoch "$SAMPLES_PER_EPOCH" --meta "$META" \
      "${extra[@]}" "$@"
}

# The FIRST EXPORTED net of this run: the export with the smallest -s<samples>, taken
# across models/ + rejectedmodels/ + modelstobetested/ because the gatekeeper moves a
# candidate out of modelstobetested/ one cycle after it appears. Recorded ONCE, by NAME,
# and re-resolved by name at match time so a move cannot lose it.
FIRST_EXPORT_NAME=""
FIRST_EXPORT_FILE="$W/first_export.json"
if [ -f "$FIRST_EXPORT_FILE" ]; then
  FIRST_EXPORT_NAME="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("name",""))' "$FIRST_EXPORT_FILE" 2>/dev/null || echo "")"
fi

resolve_model() {   # resolve_model <name> -> prints path to model.bin.gz, or nothing
  local name="$1" d
  for d in models rejectedmodels modelstobetested models_extra modelsuploaded; do
    if [ -f "$W/$d/$name/model.bin.gz" ]; then echo "$W/$d/$name/model.bin.gz"; return 0; fi
  done
  return 1
}

freeze_first_export() {
  [ -n "$FIRST_EXPORT_NAME" ] && return 0
  local name
  name="$(python3 - "$W" <<'PY'
import os, re, sys
b = sys.argv[1]
SD = re.compile(r"-s(\d+)-d(\d+)$")
best = None
for d in ("models", "rejectedmodels", "modelstobetested"):
    p = os.path.join(b, d)
    if not os.path.isdir(p):
        continue
    for n in os.listdir(p):
        if not os.path.isfile(os.path.join(p, n, "model.bin.gz")):
            continue
        m = SD.search(n)
        k = int(m.group(1)) if m else 1 << 60
        if best is None or k < best[0]:
            best = (k, n)
print(best[1] if best else "")
PY
)"
  [ -n "$name" ] || return 1
  FIRST_EXPORT_NAME="$name"
  local path; path="$(resolve_model "$name")" || return 1
  cat > "$FIRST_EXPORT_FILE" <<JSON
{
 "name": "$name",
 "path_at_freeze": "$path",
 "sha256": "$(sha256sum "$path" | cut -d' ' -f1)",
 "frozen_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "slurm_job_id": "$JOBID"
}
JSON
  cp "$FIRST_EXPORT_FILE" "$EVID/first_export-${JOBID}.json" 2>/dev/null || true
  say "froze the FIRST EXPORTED net of this run: $name"
  return 0
}

# --------------------------------------------------------------- 3. cycle loop
monitor & MONPID=$!
trap 'kill "$MONPID" 2>/dev/null || true' EXIT

CYCLE=0
GAMES="$GAMES_CYCLE1"
ROWS_PER_GAME=""
LAST_RC=0
status_line "start"

while :; do
  NOW=$(date +%s)
  LEFT=$(( CYCLE_DEADLINE - NOW ))
  if [ "$LEFT" -le 0 ]; then
    say "cycle deadline reached after $CYCLE cycle(s) -- moving to the match"
    break
  fi
  CYCLE=$((CYCLE + 1))
  say "cycle $CYCLE: games=$GAMES  ${LEFT}s left before the match reserve"
  set +e
  bash "$KTG_CODES/loop/t7_cycle.sh" "cycle$CYCLE" "$GAMES"
  LAST_RC=$?
  set -e
  say "cycle $CYCLE: t7_cycle exit=$LAST_RC"
  if [ "$LAST_RC" -ne 0 ]; then
    ABORT="cycle $CYCLE exited $LAST_RC -- see $W/logs/t7_cycle$CYCLE.txt"
    OVERALL=1
    say "STOPPING the cycle loop: $ABORT"
    break
  fi

  freeze_first_export || true

  # --- cycle 1 only: MEASURE rows/game and re-derive games/cycle ---------------
  if [ "$CYCLE" -eq 1 ]; then
    MEAS="$(python3 - "$W" "$KTG_CODES/eval/check_pos_len_npz.py" <<'PY'
import glob, json, os, subprocess, sys
b, checker = sys.argv[1], sys.argv[2]
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
    with open(f, errors="replace") as fh:
        games += sum(1 for line in fh if line.strip())
print(json.dumps({"rows": rows, "games": games,
                  "rows_per_game": (rows / games) if games else 0.0}))
PY
)"
    echo "  cycle 1 measurement: $MEAS"
    echo "$MEAS" > "$EVID/rows_per_game-${JOBID}.json"
    ROWS_PER_GAME="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["rows_per_game"])' "$MEAS")"
    GAMES="$(python3 - "$ROWS_PER_GAME" "$SAMPLES_PER_EPOCH" "$GAMES_MIN" "$GAMES_MAX" <<'PY'
import math, sys
r, E, lo, hi = float(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
# rows/cycle >= 1.2 * samples_per_epoch, at the rows/game this run actually measured
n = hi if r <= 0 else int(math.ceil(1.2 * E / r))
print(max(lo, min(hi, n)))
PY
)"
    say "measured rows/game = $ROWS_PER_GAME at 7x7 -> games/cycle re-derived to $GAMES (target rows/cycle >= $(( 12 * SAMPLES_PER_EPOCH / 10 )))"
  fi

  # --- summary after every cycle (this is what makes mid-run plotting possible) -
  summarize || true
  cp "$W/train/$TRAININGNAME/metrics_train.json" "$EVID/metrics_train-${JOBID}.json" 2>/dev/null || true
  status_line "cycle$CYCLE"

  # --- abort rules ------------------------------------------------------------
  ABORT_CHECK="$(python3 - "$SUMMARY" "$CYCLE" <<'PY' 2>/dev/null || echo ""
import json, sys
s = json.load(open(sys.argv[1])); cyc = int(sys.argv[2])
lo = s.get("loss_log", {})
msgs = []
if cyc >= 6 and (s.get("export_count") or 0) == 0:
    msgs.append("A1: no export by the end of cycle %d (export_count=0)" % cyc)
n = s.get("samples_total") or 0
mp = lo.get("min_p0loss")
if n >= 15000 and (mp is None or mp >= 3.5):
    msgs.append("A2: %d samples trained and min p0loss is %s, not below 3.5" % (n, mp))
print(" | ".join(msgs))
PY
)"
  if [ -n "$ABORT_CHECK" ]; then
    ABORT="$ABORT_CHECK"
    OVERALL=1
    say "ABORT RULE FIRED: $ABORT"
    say "Stopping the cycle loop. No knob is being changed -- this is reported as measured."
    break
  fi
done

CYCLES_DONE="$CYCLE"
say "cycle loop finished: $CYCLES_DONE cycle(s) attempted, last exit $LAST_RC, abort='${ABORT:-none}'"

# ------------------------------------------------------------------- 4. match
MATCH_SGFS="$W/match-${JOBID}"
MATCH_NOTE=""
run_match() {
  local first_path latest_name latest_path
  if [ -z "$FIRST_EXPORT_NAME" ]; then
    MATCH_NOTE="no export was ever produced -- there is no baseline to match against"
    return 1
  fi
  first_path="$(resolve_model "$FIRST_EXPORT_NAME")" || {
    MATCH_NOTE="the frozen first export '$FIRST_EXPORT_NAME' can no longer be resolved"
    return 1; }
  latest_name="$(python3 - "$W" <<'PY'
import os, re, sys
b = sys.argv[1]; SD = re.compile(r"-s(\d+)-d(\d+)$")
best = None
p = os.path.join(b, "models")
if os.path.isdir(p):
    for n in os.listdir(p):
        if not os.path.isfile(os.path.join(p, n, "model.bin.gz")):
            continue
        m = SD.search(n)
        k = int(m.group(1)) if m else -1
        if best is None or k > best[0]:
            best = (k, n)
print(best[1] if best else "")
PY
)"
  if [ -z "$latest_name" ]; then
    MATCH_NOTE="no gatekeeper-ACCEPTED net exists -- the match needs one"
    return 1
  fi
  latest_path="$(resolve_model "$latest_name")" || {
    MATCH_NOTE="the latest accepted net '$latest_name' holds no model.bin.gz"; return 1; }
  if [ "$latest_path" = "$first_path" ]; then
    MATCH_NOTE="the latest accepted net IS the first exported net ($latest_name) -- nothing to compare"
    return 1
  fi
  mkdir -p "$MATCH_SGFS"
  say "match: first='$FIRST_EXPORT_NAME' vs latest='$latest_name', $MATCH_GAMES games, 7x7, 100 visits, balanced colours"
  echo "  first  : $first_path"
  echo "           sha256 $(sha256sum "$first_path" | cut -d' ' -f1)"
  echo "  latest : $latest_path"
  echo "           sha256 $(sha256sum "$latest_path" | cut -d' ' -f1)"
  "$KATAGO_BIN" match \
    -config "$KTG_CODES/cfg/match_first_latest_7.cfg" \
    -override-config "nnModelFile0=$first_path,nnModelFile1=$latest_path,numGamesTotal=$MATCH_GAMES" \
    -sgf-output-dir "$MATCH_SGFS" \
    -log-file "$W/logs/match-${JOBID}.log"
  local rc=$?
  say "katago match exit=$rc"
  python3 "$KATAGO_SRC/python/summarize_sgfs.py" "$MATCH_SGFS" -recursive \
    2>&1 | tee "$EVID/match_summary-${JOBID}.txt" || true
  return "$rc"
}

MATCH_OK=0
set +e
run_match
MATCH_RC=$?
set -e
if [ "$MATCH_RC" -eq 0 ]; then
  MATCH_OK=1
else
  say "match not run or failed (rc=$MATCH_RC): ${MATCH_NOTE:-see the log above}"
  OVERALL=1
fi

# ------------------------------------------------------------------ 5. summary
kill "$MONPID" 2>/dev/null || true
cp "$W/train/$TRAININGNAME/metrics_train.json" "$EVID/metrics_train-${JOBID}.json" 2>/dev/null || true

if [ "$MATCH_OK" -eq 1 ]; then
  summarize --match-sgfs "$MATCH_SGFS" --bot-first first --bot-latest latest || OVERALL=1
else
  summarize || OVERALL=1
fi

python3 - "$SUMMARY" "$CYCLES_DONE" "$MATCH_OK" "${MATCH_NOTE:-}" "$GAMES" "${ROWS_PER_GAME:-}" <<'PY' || true
import json, sys
p, cycles, match_ok, note, games, rpg = sys.argv[1:7]
s = json.load(open(p))
s["cycles_attempted"] = int(cycles)
s["match_ran"] = bool(int(match_ok))
s["match_note"] = note or None
s["games_per_cycle_final"] = int(games)
s["rows_per_game_measured"] = float(rpg) if rpg else None
json.dump(s, open(p, "w"), indent=1, sort_keys=True)
PY

status_line "final"
cp "$W/logs/match-${JOBID}.log" "$EVID/match-${JOBID}.log" 2>/dev/null || true
sleep 2
cp "$JOBLOG" "$EVID/ktg-t7-${JOBID}.txt" 2>/dev/null || true

echo
echo "======================================================================"
echo "ktg-t7  job=$JOBID  end=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  cycles attempted : $CYCLES_DONE"
echo "  abort            : ${ABORT:-none}"
echo "  match ran        : $MATCH_OK  ${MATCH_NOTE:-}"
echo "  summary          : $SUMMARY"
python3 -c "
import json,sys
s=json.load(open('$SUMMARY'))
lo=s.get('loss_log',{}); last=lo.get('last') or {}; m=s.get('match') or {}
print('  loss rows        : %s' % lo.get('rows'))
print('  p0loss first/min/last : %s / %s / %s  (uniform %.4f, target < 2.5)'
      % (lo.get('first_p0loss'), lo.get('min_p0loss'), last.get('p0loss'),
         s['criteria']['uniform_policy_baseline']))
print('  vloss  min/last  : %s / %s' % (lo.get('min_vloss'), last.get('vloss')))
print('  exports/accepted : %s / %s' % (s.get('export_count'), len(s.get('accepted') or [])))
if m: print('  match latest-first: %s-%s (%s draws), score %s, Elo %s'
            % (m.get('latest_wins'), m.get('first_wins'), m.get('draws'),
               m.get('score_latest'), m.get('elo_latest_minus_first')))
print('  CONVERGED        : %s' % s.get('converged'))
" 2>/dev/null || true
echo "  overall          = $OVERALL"
echo "======================================================================"
exit "$OVERALL"
