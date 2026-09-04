#!/bin/bash
# stage_monitor.sh -- mission ktg-train, nodes arxiv-1902.10565::synchronous_loop_smoke
#                     (S9/o03/c06) and ::measure_stage_throughput (S13 inputs).
#
# Samples, for the four loop stages, the two quantities the smoke job owes:
#   * per-process OS thread count  (ps -o nlwp=)  -> S9  nlwp_max per stage
#   * per-process resident set     (ps -o rss=)   -> S13 peak RSS per stage
# and, separately, GPU utilisation and used VRAM (nvidia-smi) -> S13 peak VRAM.
#
# It never asserts. The thresholds live in audit_smoke.py; this script only records.
#
# usage:
#   stage_monitor.sh start <outdir> [rootpid] begin sampling (ps 0.2 s, nvidia-smi 2 s);
#                                            rootpid defaults to the caller's PPID
#   stage_monitor.sh phase <outdir> <label>  retag subsequent samples (cycle1, cycle2,
#                                            probe_search, probe_train, ...)
#   stage_monitor.sh stop  <outdir>          stop both samplers
#
# outputs under <outdir>:
#   ps_samples.tsv   epoch_s \t phase \t stage \t pid \t nlwp \t rss_kb \t ppid
#   gpu_samples.csv  timestamp, index, utilization.gpu [%], memory.used [MiB]
#   phase            the current phase label
#   monitor.pids     sampler pids
#
# The phase label is what makes S9's "real-net clause" readable: cycle1 selfplay runs
# the random bootstrap (no CUDA context, cpp/program/setup.cpp:126), while probe_search
# and -- if the gate accepted -- cycle2 selfplay run an exported net with a live CUDA
# context. audit_smoke.py reports nlwp_max per (phase, stage) as well as per stage.
#
# SCOPE (repair after job 298712): `ps -e` lists EVERY process on the node, and a b200
# node is shared. In 298712 three foreign PIDs (317109, 322317, 323223) whose command
# lines contain "train.py" were sampled from before leg A to the end of leg E and put
# nlwp_max=36 on the `train` stage, which our own trainer never reached (14, PIDs 325065
# and 331077). The sampler now walks each candidate's ppid chain and keeps only
# processes descended from ROOT_PID -- the job script itself -- so no other tenant's
# process can enter the measurement. The raw ps_samples.tsv carries the ppid too, so
# the attribution is re-checkable after the fact.

set -u

ACTION="${1:-}"
OUT="${2:-}"
ROOT_PID_ARG="${3:-}"

if [ -z "$ACTION" ] || [ -z "$OUT" ]; then
  echo "usage: $0 start|phase|stop <outdir> [label]" >&2
  exit 2
fi

PS_FILE="$OUT/ps_samples.tsv"
GPU_FILE="$OUT/gpu_samples.csv"
RUN_FILE="$OUT/monitor.run"
PID_FILE="$OUT/monitor.pids"
PHASE_FILE="$OUT/phase"
ROOT_FILE="$OUT/monitor.rootpid"

sample_ps() {
  # One ps sweep per 0.2 s. Classification is on the command line, so it catches the
  # engine both as ./bin/katago (loop, run out of the dated archive) and as an absolute
  # $KATAGO_BIN path (the probes). Only descendants of ROOT_PID are recorded.
  local root
  root="$(cat "$ROOT_FILE" 2>/dev/null || echo 1)"
  while [ -e "$RUN_FILE" ]; do
    now="$(date +%s.%N)"
    ph="$(cat "$PHASE_FILE" 2>/dev/null || echo unknown)"
    ps -eo pid=,ppid=,nlwp=,rss=,args= 2>/dev/null | awk -v now="$now" -v ph="$ph" -v root="$root" '
      {
        pid = $1; ppid = $2; nlwp = $3; rss = $4
        parent[pid] = ppid
        args = ""
        for (i = 5; i <= NF; i++) args = args $i " "
        if (index(args, "katago selfplay"))        stage = "selfplay"
        else if (index(args, "katago gatekeeper")) stage = "gatekeeper"
        else if (index(args, "train.py"))          stage = "train"
        else if (index(args, "shuffle.py"))        stage = "shuffle"
        else next
        n_pid[++n] = pid; n_ppid[n] = ppid; n_nlwp[n] = nlwp; n_rss[n] = rss; n_stage[n] = stage
      }
      END {
        for (i = 1; i <= n; i++) {
          # walk the ppid chain up to root; bounded so a cycle cannot hang the sweep
          p = n_pid[i]; ours = 0
          for (hops = 0; hops < 64; hops++) {
            if (p == root) { ours = 1; break }
            if (p == 1 || p == 0 || !(p in parent)) break
            p = parent[p]
          }
          if (ours)
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", now, ph, n_stage[i], n_pid[i], n_nlwp[i], n_rss[i], n_ppid[i]
        }
      }' >> "$PS_FILE"
    sleep 0.2
  done
}

sample_gpu() {
  while [ -e "$RUN_FILE" ]; do
    nvidia-smi --query-gpu=timestamp,index,utilization.gpu,memory.used \
               --format=csv,noheader 2>/dev/null >> "$GPU_FILE" || true
    sleep 2
  done
}

case "$ACTION" in
  start)
    mkdir -p "$OUT"
    # Default root: the process that invoked this script (the job script), so every
    # stage the job starts is a descendant and nothing else is.
    if [ -n "$ROOT_PID_ARG" ]; then echo "$ROOT_PID_ARG" > "$ROOT_FILE"; else echo "$PPID" > "$ROOT_FILE"; fi
    echo "stage_monitor: root pid = $(cat "$ROOT_FILE") (only its descendants are sampled)"
    : > "$RUN_FILE"
    echo "boot" > "$PHASE_FILE"
    touch "$PS_FILE" "$GPU_FILE"
    sample_ps  & PS_PID=$!
    sample_gpu & GPU_PID=$!
    printf '%s\n%s\n' "$PS_PID" "$GPU_PID" > "$PID_FILE"
    echo "stage_monitor: started (ps pid $PS_PID, gpu pid $GPU_PID) -> $OUT"
    ;;
  phase)
    LABEL="${3:-}"
    [ -n "$LABEL" ] || { echo "phase needs a label" >&2; exit 2; }
    echo "$LABEL" > "$PHASE_FILE"
    echo "stage_monitor: phase = $LABEL"
    ;;
  stop)
    rm -f "$RUN_FILE"
    if [ -f "$PID_FILE" ]; then
      while read -r p; do
        [ -n "$p" ] && kill "$p" 2>/dev/null || true
      done < "$PID_FILE"
      rm -f "$PID_FILE"
    fi
    # the ps sweep sleeps 0.2 s and nvidia-smi 2 s; give them a beat to notice
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      sleep 0.2
    done
    pkill -f "nvidia-smi --query-gpu=timestamp,index,utilization.gpu" 2>/dev/null || true
    echo "stage_monitor: stopped; $(wc -l < "$PS_FILE" 2>/dev/null || echo 0) ps samples, $(wc -l < "$GPU_FILE" 2>/dev/null || echo 0) gpu samples"
    ;;
  *)
    echo "unknown action: $ACTION" >&2
    exit 2
    ;;
esac
exit 0
