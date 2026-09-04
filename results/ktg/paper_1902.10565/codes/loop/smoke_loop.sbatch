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

# The job script itself needs the mission venv, not just its children: leg B/C call
# audit_smoke.py --snapshot, which imports torch to read checkpoint.ckpt. In job 298712
# only smoke_one_cycle.sh sourced env.sh (in a child shell), so the snapshots died with
# ModuleNotFoundError: No module named 'torch' and S6 had no cycle-1 counter to compare
# against. env.sh is not written for `set -u`, hence the guard.
set +u
# shellcheck disable=SC1091
source "$KTG_ROOT/env.sh"
set -u
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
  # Every failed leg -- hard or soft -- makes the JOB fail. In job 298712 a soft leg
  # returned 0 from here, so `|| OVERALL=1` at the call site never fired and the job
  # reported COMPLETED 0:0 with D1, D2 and E all failed. A job whose audit did not pass
  # must not look terminal-clean to sacct.
  OVERALL=1
  if [ "$kind" = "hard" ]; then
    echo "leg $name failed and is a hard prerequisite of the remaining cycle legs; running leg E and stopping." >&2
    return "$rc"
  fi
  echo "leg $name failed but is not a prerequisite; continuing so the allocation still yields the other legs (the job still exits non-zero)." >&2
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
probe_json_field() {
  python3 -c 'import json,sys
try: d = json.load(open(sys.argv[1])) or {}
except Exception: d = {}
v = d.get(sys.argv[2])
print(v if v is not None else 0)' "$1" "$2" 2>/dev/null || echo 0
}

leg_d1() {
  phase probe_search
  local sd="$KTG_ROOT/runs/smoke_probe/search"
  bash "$KTG_CODES/eval/probe_search_9x9.sh" 20
  local rc=$?
  local turns; turns="$(probe_json_field "$sd/probe_search.json" searched_turns)"
  echo "leg D1: probe_search (forks at cfg values) exit=$rc searched_turns=$turns"
  if [ "${turns%%.*}" -lt 500 ]; then
    # tasks/paper_code_map_search section 11: fewer than 500 searched turns is too noisy
    # for a +-0.05 band, so re-run at 60 games inside the SAME allocation.
    echo "leg D1: searched_turns < 500 -- re-running at 60 games in this allocation"
    bash "$KTG_CODES/eval/probe_search_9x9.sh" 60
    rc=$?
  fi
  cp "$sd/probe_search.json" "$EVID/probe_search-${JOBID}.json" 2>/dev/null || true

  # Job 298712 measured full_frac = 0.3330, above the [0.20, 0.30] band. The risk table
  # of tasks/paper_code_map_search prescribes exactly one response: forks halve
  # cheapSearchProb for six turns (cpp/program/play.cpp:1127-1129), so re-run with
  # earlyForkGameProb = forkGameProb = 0 and record it as a SECOND row. Both runs are
  # kept; neither is discarded.
  local ff; ff="$(probe_json_field "$sd/probe_search.json" full_frac)"
  local in_band; in_band="$(python3 -c 'import sys;f=float(sys.argv[1]);print(1 if 0.20<=f<=0.30 else 0)' "$ff" 2>/dev/null || echo 0)"
  echo "leg D1: full_frac=$ff in_band=$in_band"
  local rc2=0
  if [ "$in_band" -ne 1 ]; then
    echo "leg D1: full_frac outside [0.20, 0.30] -- recording the prescribed fork-free second row"
    bash "$KTG_CODES/eval/probe_search_9x9.sh" 60 nofork
    rc2=$?
    cp "$sd/probe_search_nofork.json" "$EVID/probe_search_nofork-${JOBID}.json" 2>/dev/null || true
    local ff2; ff2="$(probe_json_field "$sd/probe_search_nofork.json" full_frac)"
    echo "leg D1: fork-free full_frac=$ff2 (forks were the hypothesis for the 298712 excess)"
    # the leg passes if EITHER recorded row lands in the band
    [ "$rc2" -eq 0 ] && rc=0
  fi

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
  cp "$KTG_ROOT/runs/smoke_probe/train/probe_train.json" "$EVID/probe_train-${JOBID}.json" 2>/dev/null || true
  cp "$KTG_ROOT/runs/smoke_probe/train/probe_resume.json" "$EVID/probe_resume-${JOBID}.json" 2>/dev/null || true
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
OVERALL=0

# $$ is this job script's own pid: the monitor records only its descendants, so no other
# tenant of a shared b200 node can enter the S9 / S13 measurement (job 298712 defect).
bash "$KTG_CODES/eval/stage_monitor.sh" start "$MON" "$$"
phase legA

HARD_FAILED=0
run_leg A  hard leg_a           || HARD_FAILED=1
[ "$HARD_FAILED" -eq 0 ] && { run_leg B  hard leg_cycle cycle1 || HARD_FAILED=1; }
[ "$HARD_FAILED" -eq 0 ] && { run_leg C  hard leg_cycle cycle2 || HARD_FAILED=1; }
[ "$HARD_FAILED" -eq 0 ] && { run_leg D1 soft leg_d1 || true; }
[ "$HARD_FAILED" -eq 0 ] && { run_leg D2 soft leg_d2 || true; }

run_leg E soft leg_e || true

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
