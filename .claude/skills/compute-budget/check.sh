#!/usr/bin/env bash
# compute-budget/check.sh — recurring self-check before launching or scaling any
# compute job on skipjack. Encodes progress/prompt/ktg-train.md "Computation Usage".
#
#   CPU : no cap (human decision 2026-09-03) — reported for information only
#   GPU : at most 4 GPUs, b200/b300 only; if GPUs are scarce, take what is free
#
# Usage:  check.sh [--gpus N] [--cpus N] [--partition b200|b300]
# Exit 0 = request is within policy; exit 1 = violates policy; prints live state.

set -u
REQ_GPUS=0; REQ_CPUS=0; PART=""
while [ $# -gt 0 ]; do
  case "$1" in
    --gpus) REQ_GPUS="$2"; shift 2 ;;
    --cpus) REQ_CPUS="$2"; shift 2 ;;
    --partition) PART="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done

NODE_CPUS=124
CPU_CAP=0   # 0 = no CPU cap (human decision 2026-09-03); CPUs are reported, never enforced
GPU_CAP=4
ACCOUNT=ssci-anima
ok=0

echo "== compute-budget self-check  $(date -Is) =="

# --- my footprint right now -------------------------------------------------
my_gpus=$(squeue -u "$USER" -t RUNNING,PENDING -h -o "%b %D" 2>/dev/null \
  | awk '{n=$1; sub(/.*:/,"",n); if(n=="") n=0; s+=n*$2} END{print s+0}')
my_cpus=$(squeue -u "$USER" -t RUNNING,PENDING -h -o "%C" 2>/dev/null | awk '{s+=$1} END{print s+0}')
echo "my jobs      : gpus=${my_gpus} cpus=${my_cpus}  ($(squeue -u "$USER" -h | wc -l) jobs)"

# --- free GPUs on the allowed partitions -------------------------------------
for p in b200 b300; do
  tot=0; free=0
  for n in $(sinfo -p "$p" -N -h -o "%N" | sort -u); do
    info=$(scontrol show node "$n" 2>/dev/null)
    st=$(grep -oP 'State=\K\S+' <<<"$info")
    a=$(grep -oP 'AllocTRES=.*?gres/gpu=\K\d+' <<<"$info"); a=${a:-0}
    tot=$((tot+8))
    # reserved / drained nodes are not free to us
    case "$st" in *RESERVED*|*DRAIN*|*DOWN*|*MAINT*) ;; *) free=$((free+8-a)) ;; esac
  done
  echo "partition $p : free_gpus=${free}/${tot} (excludes reserved/drained nodes)"
done
echo "reservations : $(scontrol show reservation 2>/dev/null | grep -c ReservationName) defined ($(scontrol show reservation 2>/dev/null | grep -c 'State=ACTIVE') active) — scontrol show reservation"

# --- scratch quota -------------------------------------------------------------
if [ -x /apps/helpers/quotas.py ] || [ -f /apps/helpers/quotas.py ]; then
  python3 /apps/helpers/quotas.py 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -E "scratch|home" | sed 's/^/quota        : /'
fi

# --- policy checks on the requested job ---------------------------------------
if [ -n "$PART" ] && [ "$PART" != b200 ] && [ "$PART" != b300 ]; then
  echo "VIOLATION    : partition '$PART' — policy allows b200/b300 only"; ok=1
fi
if [ "$REQ_GPUS" -gt "$GPU_CAP" ]; then
  echo "VIOLATION    : --gpus $REQ_GPUS > cap $GPU_CAP"; ok=1
fi
if [ $((my_gpus + REQ_GPUS)) -gt "$GPU_CAP" ]; then
  echo "VIOLATION    : my_gpus($my_gpus) + request($REQ_GPUS) > cap $GPU_CAP — wait for running jobs or shrink"; ok=1
fi
if [ "$CPU_CAP" -gt 0 ] && [ "$REQ_CPUS" -gt "$CPU_CAP" ]; then
  echo "VIOLATION    : --cpus $REQ_CPUS > cap $CPU_CAP"; ok=1
fi
if [ "$REQ_GPUS" -gt 0 ] || [ "$REQ_CPUS" -gt 0 ]; then
  [ $ok -eq 0 ] && echo "OK           : request gpus=$REQ_GPUS cpus=$REQ_CPUS part=${PART:-b200} within policy (gpu<=$GPU_CAP, no cpu cap)"
fi
exit $ok
