#!/bin/bash
# probe_resume_9x9.sh -- mission ktg-train, task paper_code_map_training section 2,
# assertion 4; nodes train_resume_semantics and train_optimizer_schedule.
# Also S12 of tasks/synchronous_loop_smoke. Leg D2 of codes/loop/smoke_loop.sbatch.
#
#   usage: probe_resume_9x9.sh [REAL_NPZ_DIR]
#          default $KTG_SMOKE_BASEDIR/selfplay/random/tdata
#
# Protocol (task section 2, assertion 4):
#   1  build a synthetic shuffled-data dir in the layout train.py:1226,1240-1242,1273
#      expects -- <datadir>/train.json carrying {"range":[start,end]} plus
#      <datadir>/train/*.npz -- by TILING rows of a REAL cycle-1 npz. Tiling real rows
#      rather than fabricating tensors means the probe cannot pass on a row layout the
#      engine would never write.
#   2  run train.py -pos-len 9 -model-kind b7c96h3tfrs -batch-size 32
#      -samples-per-epoch 2048 in the background, wait until the checkpoint shows two
#      epochs (global_step_samples >= 2*2048), then SIGKILL the process group.
#   3  re-run the IDENTICAL command and assert
#        global_step_samples_after > global_step_samples_at_kill
#        total_num_data_rows unchanged for the same data dir  (train.py:979-980,1242)
#        no "Initializing new model!" (train.py:798) in the resumed log
#
# -no-compile (train.py:113) is passed on both runs: this probe measures resume
# bookkeeping, not throughput, and torch.compile costs minutes per start (DESIGN R10).
# The smoke's own cycles 1 and 2 run WITH compile, so the throughput record S13 is
# unaffected by this choice.

set -u
set -o pipefail

KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
AZ_ROOT="${AZ_ROOT:-/home/schmidt/ssci-haiyangw/az}"
W="${KTG_SMOKE_BASEDIR:-$KTG_ROOT/runs/smoke}"
WP="${KTG_PROBE_TRAIN_DIR:-$KTG_ROOT/runs/smoke_probe/train}"
SRC_NPZ_DIR="${1:-$W/selfplay/random/tdata}"

SAMPLES_PER_EPOCH=2048
BATCH_SIZE=32
MODEL_KIND=b7c96h3tfrs
KILL_AFTER_SAMPLES=$((SAMPLES_PER_EPOCH * 2))
PHASE1_TIMEOUT="${KTG_PROBE_RESUME_TIMEOUT:-1500}"
PHASE2_TIMEOUT="${KTG_PROBE_RESUME_TIMEOUT2:-1500}"

if [ -z "${KATAGO_SRC:-}" ]; then
  set +u
  # shellcheck disable=SC1091
  source "$KTG_ROOT/env.sh"
  set -u
fi
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4

echo "probe_resume_9x9.sh"
echo "  src npz dir = $SRC_NPZ_DIR"
echo "  probe dir   = $WP"
echo "  katago_src  = ${KATAGO_SRC:-<unset>}"

rm -rf "$WP"
mkdir -p "$WP/data/train" "$WP/traindir" "$WP/export" "$WP/logs"

# ---- 1. synthetic data from real rows ---------------------------------------
python3 - "$SRC_NPZ_DIR" "$WP/data" <<'PY'
import glob, json, os, sys
import numpy as np

src_dir, out_dir = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(src_dir, "*.npz")))
if not files:
    print("FAIL: no source npz under %s" % src_dir); sys.exit(3)

arrays = None
for f in files:
    with np.load(f) as z:
        cur = {k: z[k] for k in z.files}
    arrays = cur if arrays is None else {k: np.concatenate([arrays[k], cur[k]], axis=0)
                                         for k in arrays}
n_src = next(iter(arrays.values())).shape[0]
print("source rows = %d over %d file(s)" % (n_src, len(files)))

TARGET_PER_FILE = 1024
NUM_FILES = 4
reps = max(1, -(-TARGET_PER_FILE * NUM_FILES // n_src))
tiled = {k: np.concatenate([v] * reps, axis=0) for k, v in arrays.items()}
n_tot = next(iter(tiled.values())).shape[0]
per = n_tot // NUM_FILES
os.makedirs(os.path.join(out_dir, "train"), exist_ok=True)
written = 0
for i in range(NUM_FILES):
    lo, hi = i * per, (i + 1) * per
    stem = os.path.join(out_dir, "train", "data%d" % i)
    np.savez_compressed(stem + ".npz", **{k: v[lo:hi] for k, v in tiled.items()})
    # train.py:225-236 get_npz_num_rows reads a per-file <basename>.json {"num_rows": n}
    # whenever the directory has no consolidated index.json. Job 298712 leg D2 died with
    # FileNotFoundError on data0.json because the probe wrote only the .npz.
    with open(stem + ".json", "w") as jf:
        json.dump({"num_rows": int(hi - lo)}, jf)
    written += hi - lo
with open(os.path.join(out_dir, "train.json"), "w") as fh:
    json.dump({"range": [0, written]}, fh)
print("synthetic rows = %d in %d files (tiled x%d, each with its num_rows sidecar); "
      "train.json range = [0, %d]" % (written, NUM_FILES, reps, written))
PY
RC=$?
[ "$RC" -eq 0 ] || { echo "FAIL: could not build synthetic data (exit $RC)" >&2; exit "$RC"; }

read_ckpt() {
  python3 - "$1" <<'PY'
import json, sys
import torch
try:
    d = torch.load(sys.argv[1], map_location="cpu", weights_only=False)
except Exception as exc:
    print(json.dumps({"error": str(exc)})); sys.exit(0)
ts = d.get("train_state", {})
print(json.dumps({
    "global_step_samples": ts.get("global_step_samples"),
    "total_num_data_rows": ts.get("total_num_data_rows"),
    "export_cycle_counter": ts.get("export_cycle_counter"),
    "running_metrics_present": "running_metrics" in d,
}))
PY
}

CKPT="$WP/traindir/checkpoint.ckpt"
TRAINPY="$KATAGO_SRC/python/train.py"
CMD=(python3 "$TRAINPY"
     -traindir "$WP/traindir"
     -datadir "$WP/data"
     -exportdir "$WP/export"
     -exportprefix proberesume
     -pos-len 9
     -batch-size "$BATCH_SIZE"
     -model-kind "$MODEL_KIND"
     -samples-per-epoch "$SAMPLES_PER_EPOCH"
     -swa-period-samples 1024
     -max-epochs-this-instance 6
     -no-compile)
echo "  command = ${CMD[*]}"

# ---- 2. first instance, killed after two epochs -----------------------------
echo
echo "=== phase 1: train, then SIGKILL after >= $KILL_AFTER_SAMPLES samples"
cd "$KATAGO_SRC/python"
"${CMD[@]}" > "$WP/logs/train_phase1.log" 2>&1 &
TPID=$!
echo "  phase1 pid = $TPID"
T0=$(date +%s)
SAMPLES_AT_KILL=""
STATE_AT_KILL='{}'
while kill -0 "$TPID" 2>/dev/null; do
  if [ -f "$CKPT" ]; then
    ST="$(read_ckpt "$CKPT")"
    N="$(printf '%s' "$ST" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("global_step_samples") or 0)' 2>/dev/null || echo 0)"
    if [ -n "$N" ] && [ "$N" -ge "$KILL_AFTER_SAMPLES" ] 2>/dev/null; then
      SAMPLES_AT_KILL="$N"
      STATE_AT_KILL="$ST"
      break
    fi
  fi
  if [ $(( $(date +%s) - T0 )) -gt "$PHASE1_TIMEOUT" ]; then
    echo "  watchdog: phase 1 exceeded ${PHASE1_TIMEOUT}s"
    break
  fi
  sleep 5
done
echo "  phase1 elapsed_s = $(( $(date +%s) - T0 ))"
# a real SIGKILL of the trainer and its dataloader children -- no clean shutdown,
# no final save(): the checkpoint the resume reads is the one epoch 2 wrote.
pkill -9 -P "$TPID" 2>/dev/null || true
kill -9 "$TPID" 2>/dev/null || true
wait "$TPID" 2>/dev/null || true
sleep 5
if [ -z "$SAMPLES_AT_KILL" ] && [ -f "$CKPT" ]; then
  STATE_AT_KILL="$(read_ckpt "$CKPT")"
  SAMPLES_AT_KILL="$(printf '%s' "$STATE_AT_KILL" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("global_step_samples") or 0)' 2>/dev/null || echo 0)"
fi
echo "  state_at_kill = $STATE_AT_KILL"
echo "  --- phase 1 log tail:"
tail -n 6 "$WP/logs/train_phase1.log" | sed 's/^/    /'

# ---- 3. second instance, identical command ----------------------------------
echo
echo "=== phase 2: re-run the identical command (resume from checkpoint.ckpt)"
T2=$(date +%s)
timeout "$PHASE2_TIMEOUT" "${CMD[@]}" > "$WP/logs/train_phase2.log" 2>&1
RC2=$?
echo "  phase2 exit_code = $RC2   elapsed_s = $(( $(date +%s) - T2 ))"
STATE_AFTER='{}'
[ -f "$CKPT" ] && STATE_AFTER="$(read_ckpt "$CKPT")"
echo "  state_after = $STATE_AFTER"
echo "  --- phase 2 log tail:"
tail -n 6 "$WP/logs/train_phase2.log" | sed 's/^/    /'

INIT_NEW=$(grep -c 'Initializing new model!' "$WP/logs/train_phase2.log" || true)
INIT_NEW_P1=$(grep -c 'Initializing new model!' "$WP/logs/train_phase1.log" || true)
NO_PREEXIST=$(grep -c 'No preexisting checkpoint found' "$WP/logs/train_phase2.log" || true)

# ---- verdict -----------------------------------------------------------------
python3 - "$WP/probe_resume.json" "$SAMPLES_AT_KILL" "$STATE_AT_KILL" "$STATE_AFTER" \
         "$INIT_NEW" "$INIT_NEW_P1" "$NO_PREEXIST" "$RC2" <<'PY'
import json, sys
out, at_kill_raw, st_kill_s, st_after_s, init_new, init_new_p1, no_preexist, rc2 = sys.argv[1:9]

def load(s):
    try:
        return json.loads(s)
    except Exception:
        return {}

st_kill, st_after = load(st_kill_s), load(st_after_s)
gk = st_kill.get("global_step_samples")
ga = st_after.get("global_step_samples")
rk = st_kill.get("total_num_data_rows")
ra = st_after.get("total_num_data_rows")
init_new, init_new_p1, no_preexist, rc2 = int(init_new), int(init_new_p1), int(no_preexist), int(rc2)

checks = []
def add(name, ok, detail):
    checks.append({"name": name, "pass": bool(ok), "detail": detail})

add("phase1_reached_two_epochs", isinstance(gk, (int, float)) and gk >= 4096,
    "global_step_samples_at_kill=%s >= 4096" % gk)
add("phase1_initialized_fresh", init_new_p1 >= 1,
    "'Initializing new model!' in phase 1 log = %d (expected >= 1)" % init_new_p1)
add("4a_samples_increase_after_resume",
    isinstance(gk, (int, float)) and isinstance(ga, (int, float)) and ga > gk,
    "global_step_samples %s -> %s" % (gk, ga))
add("4b_no_reinitialisation_on_resume", init_new == 0 and no_preexist == 0,
    "'Initializing new model!' = %d, 'No preexisting checkpoint found' = %d in phase 2"
    % (init_new, no_preexist))
add("4c_total_num_data_rows_unchanged", rk == ra,
    "total_num_data_rows %s -> %s" % (rk, ra))
add("phase2_exit_zero", rc2 == 0, "phase 2 exit_code = %d" % rc2)

res = {
    "global_step_samples_at_kill": gk,
    "global_step_samples_after": ga,
    "total_num_data_rows_at_kill": rk,
    "total_num_data_rows_after": ra,
    "state_at_kill": st_kill,
    "state_after": st_after,
    "initializing_new_model_phase1": init_new_p1,
    "initializing_new_model_phase2": init_new,
    "no_preexisting_checkpoint_phase2": no_preexist,
    "phase2_exit_code": rc2,
    "checks": checks,
}
res["pass"] = all(c["pass"] for c in checks)
with open(out, "w") as fh:
    json.dump(res, fh, indent=1, sort_keys=True)

print()
print("  GLOBAL_STEP_SAMPLES_AT_KILL = %s" % gk)
print("  GLOBAL_STEP_SAMPLES_AFTER   = %s" % ga)
print("  TOTAL_NUM_DATA_ROWS         = %s -> %s" % (rk, ra))
for c in checks:
    print("  %-6s %-34s %s" % ("ok" if c["pass"] else "FAIL", c["name"], c["detail"]))
print("PROBE_RESUME_9X9: %s" % ("PASS" if res["pass"] else "FAIL"))
print("  json -> %s" % out)
sys.exit(0 if res["pass"] else 1)
PY
exit $?
