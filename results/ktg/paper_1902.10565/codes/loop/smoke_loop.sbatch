#!/bin/bash -l
# ^ the -l matters: without a login shell `module` is undefined on compute nodes.
#
# smoke_loop.sbatch -- mission ktg-train, node arxiv-1902.10565::synchronous_loop_smoke.
# THE job for that node, and the only job for tasks/paper_code_map_search and
# tasks/paper_code_map_training (their section 2 probes are legs D1 and D2 here).
#
# Legs (tasks/synchronous_loop_smoke/implementation.md section 8):
#   A  o30      re-append the cfg_9x9_override knowledge row INSIDE the allocation, so
#               the admission gate EXECUTES check_cfg_9x9.sh with a real
#               SLURM_CPUS_PER_TASK instead of recording skip_exec
#   B  cycle 1  random-net selfplay -> shuffle -> train from scratch -> export candidate 1
#   C  cycle 2  gatekeeper (candidate 1 vs the random baseline) -> selfplay with the
#               accepted net -> shuffle -> train resumed from checkpoint.ckpt -> candidate 2
#   D1 search probes on a REAL net (the cycle-1 candidate) + the gate log assertion
#   D2 training probes: architecture / gpool degeneracy / row bytes, and kill-and-resume
#   E  audit + evidence
#
# RESUMABILITY: there is NO afterany chain here (loop.sbatch's chain would queue a
# successor that runs a further cycle ~20 h later; tasks/synchronous_loop_smoke section
# 10 "chaining: none", section 13). Every leg writes $W/markers/<leg>.done and is
# skipped when the marker is present, so a killed job is resumed by plain resubmission
# of this same script.
#
#SBATCH --job-name=ktg-smoke
#SBATCH --account=ssci-anima
#SBATCH --partition=b200
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=24
#SBATCH --mem=64G
#SBATCH --time=03:00:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/ktg-smoke-%j.out
#SBATCH --error=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/ktg-smoke-%j.err

set -u
set -o pipefail

export KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
export AZ_ROOT="${AZ_ROOT:-/home/schmidt/ssci-haiyangw/az}"
export KTG_CODES="$AZ_ROOT/results/ktg/paper_1902.10565/codes"
EVID="$AZ_ROOT/results/ktg/paper_1902.10565/evidence/smoke"
export KTG_SMOKE_BASEDIR="$KTG_ROOT/runs/smoke"
W="$KTG_SMOKE_BASEDIR"
MARK="$W/markers"
MON="$W/monitor"
export KTG_SMOKE_TRAININGNAME="${KTG_SMOKE_TRAININGNAME:-t9}"
JOBID="${SLURM_JOB_ID:-nojob}"
JOBLOG="$KTG_ROOT/logs/ktg-smoke-${JOBID}.out"

mkdir -p "$W" "$MARK" "$MON" "$W/logs" "$EVID" "$KTG_ROOT/logs"

echo "======================================================================"
echo "ktg-smoke  job=$JOBID  host=$(hostname)  start=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  basedir       = $W"
echo "  codes         = $KTG_CODES"
echo "  evidence      = $EVID"
echo "  cpus_per_task = ${SLURM_CPUS_PER_TASK:-?}   mem = ${SLURM_MEM_PER_NODE:-?}   gres = gpu:1"
echo "======================================================================"
scontrol show job "$JOBID" 2>/dev/null | sed -n '1,12p' || true
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader || true
python3 /apps/helpers/quotas.py 2>/dev/null || true

cat > "$MARK/allocation.json" <<JSON
{
 "slurm_job_id": "$JOBID",
 "node": "$(hostname)",
 "partition": "${SLURM_JOB_PARTITION:-b200}",
 "cpus_per_task": ${SLURM_CPUS_PER_TASK:-24},
 "mem_mb": ${SLURM_MEM_PER_NODE:-65536},
 "gpus": 1,
 "started_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

# A resubmission must not inherit a STOP file: the loop copy exits 0 immediately when
# one is present (synchronous_loop_9x9.sh:215-220) and the cycle would silently not
# run. Every leg re-checks that its cycle log actually gained the completion line.
if [ -e "$W/STOP" ]; then
  echo "NOTE: $W/STOP exists from an earlier attempt; recording and removing it."
  cp "$W/STOP" "$MARK/STOP.previous-$JOBID" 2>/dev/null || true
  ls -l "$W/STOP"
  rm -f "$W/STOP"
fi

SKIPPED=""
FAILED=""
LEG_RC_SUMMARY=""

run_leg() {
  # run_leg <name> <hard|soft> <command...>
  local name="$1"; shift
  local kind="$1"; shift
  local t0 rc
  if [ -e "$MARK/$name.done" ]; then
    echo
    echo "=== leg $name: SKIPPED (marker $MARK/$name.done from $(date -u -r "$MARK/$name.done" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?'))"
    SKIPPED="$SKIPPED $name"
    LEG_RC_SUMMARY="$LEG_RC_SUMMARY $name=skipped"
    return 0
  fi
  echo
  echo "=== leg $name: START  $(date -u +%Y-%m-%dT%H:%M:%SZ)  ($kind)"
  t0=$(date +%s)
  set +e
  "$@"
  rc=$?
  set -e
  echo "=== leg $name: END    $(date -u +%Y-%m-%dT%H:%M:%SZ)  exit=$rc  elapsed_s=$(( $(date +%s) - t0 ))"
  LEG_RC_SUMMARY="$LEG_RC_SUMMARY $name=$rc"
  if [ "$rc" -eq 0 ]; then
    date -u +%Y-%m-%dT%H:%M:%SZ > "$MARK/$name.done"
    echo "job=$JOBID elapsed_s=$(( $(date +%s) - t0 ))" >> "$MARK/$name.done"
    return 0
  fi
  FAILED="$FAILED $name"
  if [ "$kind" = "hard" ]; then
    echo "leg $name failed and is a hard prerequisite of the remaining cycle legs; running leg E and stopping." >&2
    return "$rc"
  fi
  echo "leg $name failed but is not a prerequisite; continuing so the allocation still yields the other legs." >&2
  return 0
}

phase() { bash "$KTG_CODES/eval/stage_monitor.sh" phase "$MON" "$1" >/dev/null 2>&1 || true; }

cycle_completed() {
  # the loop prints this only on the KTG_ONE_CYCLE exit (synchronous_loop_9x9.sh:282)
  local n
  n="$(grep -c 'one cycle done' "$W/logs/smoke_$1.txt" 2>/dev/null)"
  [ -n "$n" ] || n=0
  echo "$n"
}

# ---------------------------------------------------------------- leg A (o30)
leg_a() {
  local rendered="$W/cfg_9x9_reappend_row.rendered.json"
  local attempt rc
  cd "$AZ_ROOT" || return 1
  python3 - "$EVID/cfg_9x9_reappend_row.json" "$rendered" "$JOBID" "$(hostname)" <<'PY'
import json, sys
src, dst, jobid, host = sys.argv[1:5]
row = json.load(open(src))
row["notes"] = row["notes"].replace("__SLURM_JOB_ID__", jobid).replace("__NODE__", host)
rm = row.setdefault("runtime_metadata", {})
rm["slurm_job_id"] = jobid
rm["device"] = "b200 node %s, 1 GPU allocated (the checker itself needs none: empty models dir -> debugSkipNeuralNet)" % host
json.dump(row, open(dst, "w"), indent=1, sort_keys=True)
print("rendered leg-A row -> %s (job %s, node %s)" % (dst, jobid, host))
PY
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  export CHANDRA_ROLE=worker
  echo "--- knowledge_database.py append (CHANDRA_ROLE=$CHANDRA_ROLE, no --skip-exec)"
  for attempt in 1 2; do
    python3 phys-agentic-loop/_common/knowledge_database.py append --row-file "$rendered" \
      2>&1 | tee "$EVID/leg_a_append_${JOBID}.txt"
    rc="${PIPESTATUS[0]}"
    if [ "$rc" -eq 0 ]; then
      cp "$rendered" "$EVID/cfg_9x9_reappend_row.rendered-${JOBID}.json" 2>/dev/null || true
      return 0
    fi
    echo "leg A: append attempt $attempt exited $rc; sleeping 10 s before the retry (section 11)"
    sleep 10
  done
  return "$rc"
}

# ---------------------------------------------------------------- legs B / C
leg_cycle() {
  local label="$1"
  phase "$label"
  bash "$KTG_CODES/loop/smoke_one_cycle.sh" "$label"
  local rc=$?
  local done_lines
  done_lines="$(cycle_completed "$label")"
  echo "leg $label: loop exit=$rc, 'one cycle done' lines in $W/logs/smoke_$label.txt = $done_lines"
  if [ "$rc" -ne 0 ]; then return "$rc"; fi
  if [ "$done_lines" -lt 1 ]; then
    echo "leg $label: the loop exited 0 without completing a cycle (STOP file, or the storage guard) -- not a completed leg" >&2
    return 4
  fi
  python3 "$KTG_CODES/eval/audit_smoke.py" "$W" --snapshot "$label" || true
  return 0
}

# ---------------------------------------------------------------- leg D1
leg_d1() {
  phase probe_search
  bash "$KTG_CODES/eval/probe_search_9x9.sh" 20
  local rc=$?
  local turns
  turns="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])) or {}).get("searched_turns") or 0)' \
            "$KTG_ROOT/runs/smoke_probe/search/probe_search.json" 2>/dev/null || echo 0)"
  echo "leg D1: probe_search exit=$rc searched_turns=$turns"
  if [ "$turns" -lt 500 ]; then
    # section 11 of tasks/paper_code_map_search: fewer than 500 searched turns is too
    # noisy for a +-0.05 band, so re-run at 60 games inside the SAME allocation.
    echo "leg D1: searched_turns < 500 -- re-running the probe at 60 games in this allocation"
    bash "$KTG_CODES/eval/probe_search_9x9.sh" 60
    rc=$?
  fi
  cp "$KTG_ROOT/runs/smoke_probe/search/probe_search.json" "$EVID/probe_search.json" 2>/dev/null || true
  echo
  bash "$KTG_CODES/eval/probe_gate_9x9.sh" | tee "$EVID/probe_gate_${JOBID}.txt"
  local grc="${PIPESTATUS[0]}"
  echo "leg D1: probe_gate exit=$grc"
  [ "$rc" -eq 0 ] && [ "$grc" -eq 0 ]
}

# ---------------------------------------------------------------- leg D2
leg_d2() {
  phase probe_train
  bash "$KTG_CODES/eval/probe_train_9x9.sh"
  local rc=$?
  cp "$KTG_ROOT/runs/smoke_probe/train/probe_train.json" "$EVID/probe_train.json" 2>/dev/null || true
  cp "$KTG_ROOT/runs/smoke_probe/train/probe_resume.json" "$EVID/probe_resume.json" 2>/dev/null || true
  return "$rc"
}

# ---------------------------------------------------------------- leg E
leg_e() {
  phase audit
  bash "$KTG_CODES/eval/stage_monitor.sh" stop "$MON" || true
  cp "$MON/ps_samples.tsv" "$EVID/ps_samples-${JOBID}.tsv" 2>/dev/null || true
  cp "$MON/gpu_samples.csv" "$EVID/gpu_samples-${JOBID}.csv" 2>/dev/null || true
  echo
  python3 "$KTG_CODES/eval/audit_smoke.py" "$W" --evidence "$EVID"
  local rc=$?
  echo
  echo "--- du of $W"
  du -sh "$W" 2>/dev/null || true
  du -sh "$KTG_ROOT/runs/smoke_probe" 2>/dev/null || true
  return "$rc"
}

# ---------------------------------------------------------------- driver
bash "$KTG_CODES/eval/stage_monitor.sh" start "$MON"
phase legA

OVERALL=0

run_leg A  hard leg_a           || OVERALL=1
[ "$OVERALL" -eq 0 ] && { run_leg B  hard leg_cycle cycle1 || OVERALL=1; }
[ "$OVERALL" -eq 0 ] && { run_leg C  hard leg_cycle cycle2 || OVERALL=1; }
[ "$OVERALL" -eq 0 ] && { run_leg D1 soft leg_d1           || OVERALL=1; }
[ "$OVERALL" -eq 0 ] && { run_leg D2 soft leg_d2           || OVERALL=1; }

run_leg E soft leg_e || OVERALL=1

cat > "$MARK/attempt_${JOBID}.json" <<JSON
{
 "slurm_job_id": "$JOBID",
 "node": "$(hostname)",
 "ended_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
 "leg_exit_codes": "$LEG_RC_SUMMARY",
 "resumed_from_leg": "${SKIPPED:-none}",
 "failed_legs": "${FAILED:-none}",
 "overall": $OVERALL
}
JSON

# The transcript is the witness for the executed GPU legs (tasks/synchronous_loop_smoke
# section 2). It is copied here and re-copied by the worker after the job is terminal,
# so the retained file also contains this closing block.
sleep 2
cp "$JOBLOG" "$EVID/smoke-${JOBID}.txt" 2>/dev/null || true

echo
echo "======================================================================"
echo "ktg-smoke  job=$JOBID  end=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  legs      :$LEG_RC_SUMMARY"
echo "  skipped   :${SKIPPED:- none}"
echo "  failed    :${FAILED:- none}"
echo "  markers   : $(ls "$MARK"/*.done 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
echo "  overall   = $OVERALL"
echo "======================================================================"
exit "$OVERALL"
