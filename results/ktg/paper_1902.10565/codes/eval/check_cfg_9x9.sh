#!/bin/bash
# check_cfg_9x9.sh -- mission ktg-train, node arxiv-1902.10565::cfg_9x9_override
#
# The five asserts of tasks/cfg_9x9_override/implementation.md section 2. Exits 0
# only if all five hold; every intermediate number is printed so the output itself
# is the evidence object.
#
#   1  key-diff codes/cfg/selfplay_9x9.cfg   vs cpp/configs/training/selfplay1_maxsize9.cfg
#      -> every differing line's key is in the allowed set, and nothing else moved
#   2  key-diff codes/cfg/gatekeeper_9x9.cfg vs cpp/configs/training/gatekeeper1_maxsize9.cfg
#   3  katago selfplay -config codes/cfg/selfplay_9x9.cfg -max-games-total 1 exits 0
#   4  every line of every written .sgfs carries SZ[9]  (n9 == n_all, n_all >= 1)
#   5  max ps -o nlwp= sampled on the live selfplay pid is <= the declared CPU budget
#
# Check 5 needs all 18 game threads simultaneously busy, so it uses its own longer
# selfplay run (-max-games-total 36 = 2 games per game thread); with one game total
# 17 of the 18 threads exit immediately and the sample would be meaningless.
#
# No GPU is required: with an empty models dir LoadModel::findLatestModel returns
# modelFile "/dev/null" (cpp/dataio/loadmodel.cpp:77-93) and cpp/program/setup.cpp:126
# turns that into debugSkipNeuralNet, so cpp/neuralnet/nneval.cpp:134 never creates a
# compute context. The run is still executed inside a Slurm allocation because
# CPU_BUDGET must be a real allocation, not a login-node guess.
#
# Usage:   bash results/ktg/paper_1902.10565/codes/eval/check_cfg_9x9.sh
# Env:     KATAGO_BIN    katago binary (else sourced from the mission env.sh)
#          KTG_W         scratch workdir (default $KTG_ROOT/runtime/cfgcheck)
#          CPU_BUDGET    threads allowed (default: the job's allocated CPUs, else 24)

set -u
set -o pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SD/../../../../.." && pwd)"
M="$ROOT/results/ktg/paper_1902.10565"
UP="$ROOT/ref-code/lightvector-KataGo/cpp/configs/training"

SP_UP="$UP/selfplay1_maxsize9.cfg"
GK_UP="$UP/gatekeeper1_maxsize9.cfg"
SP="$M/codes/cfg/selfplay_9x9.cfg"
GK="$M/codes/cfg/gatekeeper_9x9.cfg"

SP_ALLOWED="dataBoardLen numGameThreads bSizes bSizeRelProbs allowRectangleProb numNNServerThreadsPerModel cudaDeviceToUse"
GK_ALLOWED="numGameThreads bSizes bSizeRelProbs allowRectangleProb numNNServerThreadsPerModel cudaDeviceToUse"

FAILURES=0
fail() { echo "FAIL: $*"; FAILURES=$((FAILURES + 1)); }

echo "check_cfg_9x9.sh"
echo "repo_root  = $ROOT"
echo "date_utc   = $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host       = $(hostname)"

# ---------------------------------------------------------------- CPU budget
# The 20%-of-all-CPUs clause was withdrawn by the human on 2026-09-03, so the
# thread budget is no longer a policy constant: it is whatever this process was
# actually allocated. Derive it, do not assume it.
if [ -n "${CPU_BUDGET:-}" ]; then
  CPU_SRC="CPU_BUDGET env override"
elif [ -n "${SLURM_CPUS_PER_TASK:-}" ]; then
  CPU_BUDGET="$SLURM_CPUS_PER_TASK"; CPU_SRC="SLURM_CPUS_PER_TASK"
elif [ -n "${SLURM_CPUS_ON_NODE:-}" ]; then
  CPU_BUDGET="$SLURM_CPUS_ON_NODE"; CPU_SRC="SLURM_CPUS_ON_NODE"
else
  CPU_BUDGET=24; CPU_SRC="fallback (no Slurm allocation visible)"
fi
echo "cpu_budget = $CPU_BUDGET   (source: $CPU_SRC)"
echo "affinity   = $(nproc) usable cpus (nproc)"

# ---------------------------------------------------------------- 1 and 2
strip() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

key_diff() {
  local up="$1" mine="$2" allowed="$3" label="$4"
  local d n_up n_mine bad=0 line body key

  for f in "$up" "$mine"; do
    [ -f "$f" ] || { fail "$label: missing file $f"; return 1; }
  done

  n_up=$(strip "$up" | wc -l)
  n_mine=$(strip "$mine" | wc -l)
  d=$(diff <(strip "$up") <(strip "$mine"))

  echo
  echo "=== check $label: key-diff $(basename "$up") -> $(basename "$mine")"
  echo "--- allowed keys: $allowed"
  echo "--- significant lines: upstream=$n_up mission=$n_mine"
  echo "--- diff:"
  if [ -z "$d" ]; then echo "(identical)"; else echo "$d"; fi

  if [ "$n_up" -ne "$n_mine" ]; then
    fail "$label: significant line count changed ($n_up -> $n_mine); only values may differ"
  fi

  while IFS= read -r line; do
    case "$line" in
      '<'*|'>'*) ;;
      *) continue ;;
    esac
    body="${line:2}"
    key="${body%%=*}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    [ -n "$key" ] || continue
    case " $allowed " in
      *" $key "*) ;;
      *) bad=$((bad + 1)); echo "OUT_OF_SET_KEY: $key" ;;
    esac
  done <<< "$d"

  echo "OUT_OF_SET_KEYS($label) = $bad"
  [ "$bad" -eq 0 ] || fail "$label: $bad changed line(s) carry a key outside the allowed set"
  return 0
}

key_diff "$SP_UP" "$SP" "$SP_ALLOWED" "1_selfplay"
key_diff "$GK_UP" "$GK" "$GK_ALLOWED" "2_gatekeeper"

# The three keys o01/o02 actually own, asserted by value and not only by diff.
echo
echo "=== value asserts"
for spec in "$SP:dataBoardLen = 9" "$SP:bSizes = 9" "$SP:bSizeRelProbs = 1" \
            "$SP:allowRectangleProb = 0" "$SP:numGameThreads = 18" \
            "$GK:bSizes = 9" "$GK:bSizeRelProbs = 1" \
            "$GK:allowRectangleProb = 0" "$GK:numGameThreads = 18"; do
  f="${spec%%:*}"; kv="${spec#*:}"
  if grep -qx -- "$kv" "$f"; then
    echo "ok   $(basename "$f"): $kv"
  else
    fail "$(basename "$f"): expected a line '$kv'"
  fi
done

# ---------------------------------------------------------------- environment
if [ -z "${KATAGO_BIN:-}" ]; then
  KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
  # shellcheck disable=SC1091
  [ -f "$KTG_ROOT/env.sh" ] && source "$KTG_ROOT/env.sh"
fi
KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
W="${KTG_W:-$KTG_ROOT/runtime/cfgcheck}"
echo
echo "katago_bin = ${KATAGO_BIN:-<unset>}"
echo "workdir    = $W"
if [ -z "${KATAGO_BIN:-}" ] || [ ! -x "${KATAGO_BIN:-}" ]; then
  fail "KATAGO_BIN is unset or not executable; source the mission env.sh first"
  echo
  echo "FAILURES = $FAILURES"
  echo "CHECK_CFG_9X9: FAIL"
  exit 1
fi

rm -rf "$W/selfplay" "$W/models"
mkdir -p "$W/selfplay" "$W/models" "$W/logs"

# ---------------------------------------------------------------- 3
echo
echo "=== check 3: katago selfplay parse run, -max-games-total 1"
t0=$(date +%s)
"$KATAGO_BIN" selfplay \
  -config "$SP" \
  -models-dir "$W/models" \
  -output-dir "$W/selfplay" \
  -max-games-total 1 > "$W/logs/selfplay_parse.log" 2>&1
RC_PARSE=$?
t1=$(date +%s)
echo "exit_code = $RC_PARSE   elapsed_s = $((t1 - t0))"
echo "--- last 12 log lines:"
tail -n 12 "$W/logs/selfplay_parse.log"
[ "$RC_PARSE" -eq 0 ] || fail "check 3: katago selfplay exited $RC_PARSE (see $W/logs/selfplay_parse.log)"

# ---------------------------------------------------------------- 5 (run first, 4 counts both runs)
echo
echo "=== check 5: ps -o nlwp= on the live selfplay pid, -max-games-total 36"
"$KATAGO_BIN" selfplay \
  -config "$SP" \
  -models-dir "$W/models" \
  -output-dir "$W/selfplay" \
  -max-games-total 36 > "$W/logs/selfplay_threads.log" 2>&1 &
PID=$!
MAX_NLWP=0
SAMPLES=0
START=$(date +%s)
while kill -0 "$PID" 2>/dev/null; do
  n=$(ps -o nlwp= -p "$PID" 2>/dev/null | tr -d ' ')
  if [ -n "$n" ]; then
    SAMPLES=$((SAMPLES + 1))
    [ "$n" -gt "$MAX_NLWP" ] && MAX_NLWP="$n"
  fi
  if [ $(( $(date +%s) - START )) -gt 900 ]; then
    echo "watchdog: killing pid $PID after 900 s"
    kill -9 "$PID" 2>/dev/null
    break
  fi
  sleep 0.05
done
wait "$PID"
RC_THREADS=$?
echo "exit_code = $RC_THREADS   elapsed_s = $(( $(date +%s) - START ))"
echo "NLWP_SAMPLES = $SAMPLES"
echo "NLWP_MAX     = $MAX_NLWP"
echo "CPU_BUDGET   = $CPU_BUDGET"
[ "$RC_THREADS" -eq 0 ] || fail "check 5: thread-measurement selfplay exited $RC_THREADS"
[ "$SAMPLES" -ge 5 ] || fail "check 5: only $SAMPLES nlwp samples taken; measurement is not admissible"
[ "$MAX_NLWP" -gt 0 ] || fail "check 5: no nlwp value was read"
if [ "$MAX_NLWP" -le "$CPU_BUDGET" ]; then
  echo "ok   NLWP_MAX $MAX_NLWP <= CPU_BUDGET $CPU_BUDGET"
else
  fail "check 5: NLWP_MAX $MAX_NLWP exceeds CPU_BUDGET $CPU_BUDGET"
fi

# ---------------------------------------------------------------- 4
echo
echo "=== check 4: SZ[9] fraction over every .sgfs line written by both runs"
shopt -s nullglob
SGFS=("$W"/selfplay/*/sgfs/*.sgfs)
shopt -u nullglob
echo "sgfs_files = ${#SGFS[@]}"
for f in "${SGFS[@]}"; do echo "  $f"; done
if [ "${#SGFS[@]}" -eq 0 ]; then
  fail "check 4: no .sgfs file was written under $W/selfplay"
  N_ALL=0; N9=0
else
  N_ALL=$(cat "${SGFS[@]}" | wc -l)
  N9=$(cat "${SGFS[@]}" | grep -c 'SZ\[9\]')
  echo "--- first sgf line, truncated:"
  head -c 120 "${SGFS[0]}"; echo
fi
echo "n_all = $N_ALL"
echo "n9    = $N9"
if [ "$N_ALL" -ge 1 ]; then
  echo "SZ9_FRACTION = $(awk -v a="$N9" -v b="$N_ALL" 'BEGIN{printf "%.3f", a/b}')"
else
  echo "SZ9_FRACTION = NA"
fi
[ "$N_ALL" -ge 1 ] || fail "check 4: n_all = $N_ALL, expected >= 1"
[ "$N9" -eq "$N_ALL" ] || fail "check 4: n9 = $N9 != n_all = $N_ALL; a non-9x9 board leaked in"

# any rectangular game would be SZ[x:y] and is counted explicitly
N_RECT=$(cat "${SGFS[@]:-/dev/null}" 2>/dev/null | grep -c 'SZ\[[0-9]*:[0-9]*\]' || true)
echo "n_rectangular = $N_RECT"
[ "${N_RECT:-0}" -eq 0 ] || fail "check 4: $N_RECT rectangular games written despite allowRectangleProb = 0"

# ---------------------------------------------------------------- verdict
echo
echo "FAILURES = $FAILURES"
if [ "$FAILURES" -eq 0 ]; then
  echo "CHECK_CFG_9X9: PASS"
  exit 0
fi
echo "CHECK_CFG_9X9: FAIL"
exit 1
