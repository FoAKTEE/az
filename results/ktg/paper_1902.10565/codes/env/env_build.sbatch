#!/bin/bash -l
#SBATCH --job-name=ktg-env-build
#SBATCH --account=ssci-anima
#SBATCH --partition=b200
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=03:00:00
#SBATCH --output=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/env_build-%j.log
#
# Mission ktg-train, task env_build: build the whole toolchain for 9x9
# transformer KataGo under one root R, on one B200 node.
#
#   R/venv              python 3.11 + torch 2.11.0+cu128 + KataGo training deps
#   R/build/KataGo      lightvector/KataGo v1.18.2, cpp/ built with USE_BACKEND=CUDA
#   R/env.sh            reusable environment
#
# Idempotent: each stage is guarded by a stamp under R/.stamps and is skipped when
# already done. Delete a stamp (or pass FORCE=<stage>) to redo one stage.

set -uo pipefail

R=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train
REPO=/home/schmidt/ssci-haiyangw/az/phys-agentic-loop
KATAGO_TAG=v1.18.2
KATAGO_SHA=fd0723fdbc0e9d82cf269c9630af8c27c57c07c4
MODEL_KIND=b7c96h3tfrs
POS_LEN=9
NPROC=${SLURM_CPUS_PER_TASK:-16}

STAMPS="$R/.stamps"
mkdir -p "$STAMPS" "$R/logs" "$R/build" "$R/evidence/env" "$R/runtime/smoke"

say() { echo; echo "=== [$(date -Is)] $* ==="; }
die() { echo "!!! FAILED: $*" >&2; exit 1; }
done_stage() { [ -f "$STAMPS/$1" ] && [ "${FORCE:-}" != "$1" ]; }
stamp()      { date -Is > "$STAMPS/$1"; }

say "job $SLURM_JOB_ID on $(hostname) cpus=$NPROC"
nvidia-smi --query-gpu=index,name,compute_cap,memory.total --format=csv,noheader || die "nvidia-smi"

# ---------------------------------------------------------------- 0. modules
say "stage 0: modules"
module load gcc/12.3.0 cmake/3.30.2 cuda/12.8.1 python/3.11.9 || die "module load"
module list 2>&1
echo "gcc     : $(gcc --version | head -1)"
echo "cmake   : $(cmake --version | head -1)"
echo "nvcc    : $(nvcc --version | tail -2 | head -1)"
echo "python  : $(python3 --version)  ($(command -v python3))"
echo "zip.h   : $(ls -l /usr/include/zip.h 2>&1)"
echo "libzip  : $(ls -l /lib64/libzip.so* 2>&1 | head -2)"
[ -f /usr/include/zip.h ] || die "zip.h missing on this node"

# ------------------------------------------------------------------- 1. venv
if done_stage venv; then
  say "stage 1: venv -- already done, skipping"
else
  say "stage 1: python venv + wheels"
  if [ ! -x "$R/venv/bin/python" ]; then
    python3 -m venv "$R/venv" || die "venv create"
    "$R/venv/bin/python" -m ensurepip --upgrade || die "ensurepip"
  fi
  "$R/venv/bin/python" -m pip install --upgrade pip setuptools wheel || die "pip upgrade"
  "$R/venv/bin/python" -m pip install --no-cache-dir \
      --index-url https://download.pytorch.org/whl/cu128 \
      "torch==2.11.0+cu128" || die "pip install torch"
  "$R/venv/bin/python" -m pip install --no-cache-dir \
      numpy scipy psutil packaging sgfmill || die "pip install training deps"
  # cuDNN >= 9.8 is required by the KataGo CUDA backend's cudnn-frontend SDPA path
  # for transformer nets; there is no system cuDNN on these nodes.
  "$R/venv/bin/python" -m pip install --no-cache-dir \
      "nvidia-cudnn-cu12>=9.8,<10" || die "pip install cudnn"
  stamp venv
fi

CUDNN_DIR="$R/venv/lib/python3.11/site-packages/nvidia/cudnn"
[ -f "$CUDNN_DIR/include/cudnn.h" ] || die "cudnn.h not found under $CUDNN_DIR"
# find_library(cudnn) wants an unversioned soname; the wheel ships libcudnn.so.9 only.
if [ ! -e "$CUDNN_DIR/lib/libcudnn.so" ]; then
  ln -sf libcudnn.so.9 "$CUDNN_DIR/lib/libcudnn.so"
fi
echo "cudnn version header:"
grep -E "define CUDNN_MAJOR|define CUDNN_MINOR|define CUDNN_PATCHLEVEL" \
     "$CUDNN_DIR/include/cudnn_version.h" 2>/dev/null || \
  grep -E "define CUDNN_MAJOR|define CUDNN_MINOR|define CUDNN_PATCHLEVEL" "$CUDNN_DIR/include/cudnn.h"
ls -l "$CUDNN_DIR/lib" | head -8
"$R/venv/bin/python" -m pip list 2>/dev/null | grep -iE "^(torch|numpy|scipy|psutil|packaging|sgfmill|nvidia-cudnn) " || true

# ------------------------------------------------------------------ 2. clone
if done_stage clone; then
  say "stage 2: clone -- already done, skipping"
else
  say "stage 2: clone KataGo $KATAGO_TAG"
  if [ ! -d "$R/build/KataGo/.git" ]; then
    rm -rf "$R/build/KataGo"
    git clone https://github.com/lightvector/KataGo.git "$R/build/KataGo" \
      || git clone "$REPO/ref-code/lightvector-KataGo" "$R/build/KataGo" \
      || die "git clone"
  fi
  git -C "$R/build/KataGo" checkout --quiet "$KATAGO_SHA" || die "git checkout $KATAGO_SHA"
  stamp clone
fi
GOT_SHA=$(git -C "$R/build/KataGo" rev-parse HEAD)
echo "HEAD          = $GOT_SHA"
echo "expected      = $KATAGO_SHA"
[ "$GOT_SHA" = "$KATAGO_SHA" ] || die "SHA mismatch: $GOT_SHA != $KATAGO_SHA"
git -C "$R/build/KataGo" describe --tags --exact-match 2>&1 || true

# ------------------------------------------------------- 2b. sm_100 arch patch
# cpp/CMakeLists.txt hard-sets CMAKE_CUDA_ARCHITECTURES for CUDA 12.8 with a plain
# set(), which shadows any -DCMAKE_CUDA_ARCHITECTURES, and its list has no 100 --
# so a stock build carries no sm_100 SASS for the B200. Patch the scratch clone
# only; the ref-code mirror stays read-only (alignment kernel S4).
say "stage 2b: sm_100 architecture patch"
PATCH="$REPO/results/ktg/paper_1902.10565/codes/env/cmake-sm100.diff"
if grep -q "86 87 90 100 120" "$R/build/KataGo/cpp/CMakeLists.txt"; then
  echo "already patched, skipping"
else
  git -C "$R/build/KataGo" apply --verbose "$PATCH" || die "git apply cmake-sm100.diff"
  rm -f "$STAMPS/build"          # architecture list changed -> force a rebuild
  echo "patch applied; build stamp invalidated"
fi
grep -n "CMAKE_CUDA_ARCHITECTURES 50" "$R/build/KataGo/cpp/CMakeLists.txt"

# ------------------------------------------------------------------ 3. build
if done_stage build && [ -x "$R/build/KataGo/cpp/build/katago" ]; then
  say "stage 3: build -- already done, skipping"
else
  say "stage 3: cmake configure + build (USE_BACKEND=CUDA)"
  mkdir -p "$R/build/KataGo/cpp/build"
  cd "$R/build/KataGo/cpp/build" || die "cd build"
  rm -f CMakeCache.txt
  cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_BACKEND=CUDA \
    -DCUDNN_ROOT_DIR="$CUDNN_DIR" \
    -DCUDNN_INCLUDE_DIR="$CUDNN_DIR/include" \
    -DCUDNN_LIBRARY="$CUDNN_DIR/lib/libcudnn.so" \
    || die "cmake configure"
  make -j"$NPROC" 2>&1 | tail -60
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "make"
  [ -x "$R/build/KataGo/cpp/build/katago" ] || die "katago binary not produced"
  stamp build
fi

# ----------------------------------------------------------------- 4. env.sh
say "stage 4: install env.sh"
cp -f "$REPO/results/ktg/paper_1902.10565/codes/env/env.sh" "$R/env.sh" || die "cp env.sh"
# shellcheck disable=SC1090
source "$R/env.sh" || die "source env.sh"
echo "KATAGO_BIN      = $KATAGO_BIN"
echo "LD_LIBRARY_PATH = $LD_LIBRARY_PATH"
ldd "$KATAGO_BIN" | grep -iE "cudnn|cublas|cudart" || true

# ------------------------------------------------------------------ 5. smoke
say "stage 5: smoke tests"
SMOKE="$R/evidence/env/smoke.txt"
: > "$SMOKE"
FAILED=0
smoke() { # smoke <label> <cmd...>
  local label="$1"; shift
  echo "--- $label" | tee -a "$SMOKE"
  if "$@" >>"$SMOKE" 2>&1; then
    echo "[OK] $label" | tee -a "$SMOKE"
  else
    echo "[FAIL] $label (exit $?)" | tee -a "$SMOKE"
    FAILED=1
  fi
}

cd "$R/runtime/smoke" || die "cd runtime/smoke"

echo "== ktg-train env_build smoke, job $SLURM_JOB_ID, $(hostname), $(date -Is)" >> "$SMOKE"
echo "== gpu: $(nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader)" >> "$SMOKE"
echo "== katago sha: $GOT_SHA ($KATAGO_TAG)" >> "$SMOKE"

# (a) engine self-tests
smoke "katago version" "$KATAGO_BIN" version
smoke "katago runtests" "$KATAGO_BIN" runtests

# (a2) the binary must carry real sm_100 SASS, not just lower-arch PTX to JIT
smoke "sm_100 SASS present in katago binary" bash -c \
  'n=$(cuobjdump --list-elf "'"$KATAGO_BIN"'" | grep -c sm_100);
   echo "cuobjdump --list-elf | grep -c sm_100 = $n";
   cuobjdump --list-elf "'"$KATAGO_BIN"'" | grep -oP "sm_[0-9]+" | sort -u | tr "\n" " "; echo;
   [ "$n" -gt 0 ]'

# (b) a transformer net actually runs on the GPU
if [ ! -f "$R/runtime/smoke/model-$MODEL_KIND/model.bin.gz" ]; then
  say "exporting a fresh random-initialized $MODEL_KIND"
  ( cd "$KATAGO_SRC/python" && python export_model_pytorch.py \
      -export-random-initialized-model "$MODEL_KIND" \
      -export-dir "$R/runtime/smoke/model-$MODEL_KIND" \
      -model-name "ktg-smoke-$MODEL_KIND" \
      -filename-prefix model ) || die "export_model_pytorch"
  gzip -kf "$R/runtime/smoke/model-$MODEL_KIND/model.bin" || die "gzip model"
fi
ls -l "$R/runtime/smoke/model-$MODEL_KIND/" | tee -a "$SMOKE"

MODEL="$R/runtime/smoke/model-$MODEL_KIND/model.bin.gz"
CFG="$KATAGO_SRC/cpp/configs/gtp_example.cfg"

smoke "katago benchmark ($MODEL_KIND, 9x9 board, 80 visits, 1 thread)" \
  "$KATAGO_BIN" benchmark -model "$MODEL" -config "$CFG" -v 80 -t 1 -boardsize 9

printf 'boardsize 9\nkomi 7.0\nclear_board\ngenmove b\nshowboard\nquit\n' > gtp_in.txt
smoke "katago gtp genmove on 9x9 vs $MODEL_KIND" \
  bash -c "\"$KATAGO_BIN\" gtp -model \"$MODEL\" -config \"$CFG\" < gtp_in.txt"

# (c) torch sees the GPU and trains the same architecture at pos_len 9
cat > "$R/runtime/smoke/torch_smoke.py" <<'PY'
import sys, torch
from katago.train import modelconfigs
from katago.train.model_pytorch import Model

print("torch", torch.__version__, "cuda", torch.version.cuda, "cudnn", torch.backends.cudnn.version())
assert torch.cuda.is_available(), "torch.cuda.is_available() is False"
dev = torch.device("cuda:0")
print("torch.cuda.is_available() =", torch.cuda.is_available())
print("device name =", torch.cuda.get_device_name(0))
print("capability  =", torch.cuda.get_device_capability(0))

name, pos_len, batch = sys.argv[1], int(sys.argv[2]), 4
cfg = modelconfigs.config_of_name[name]
nb = modelconfigs.get_num_bin_input_features(cfg)
ng = modelconfigs.get_num_global_input_features(cfg)
print(f"model={name} pos_len={pos_len} bin_feats={nb} global_feats={ng}")

model = Model(cfg, pos_len=pos_len).to(dev)
model.initialize()
nparams = sum(p.numel() for p in model.parameters())
print("parameters  =", nparams)

spatial = torch.rand(batch, nb, pos_len, pos_len, device=dev)
spatial[:, 0, :, :] = 1.0          # channel 0 is the on-board mask
glob = torch.rand(batch, ng, device=dev)

def flat(o):
    if torch.is_tensor(o):
        yield o
    elif isinstance(o, (list, tuple)):
        for x in o:
            yield from flat(x)

out = model(spatial, glob)
tensors = [t for t in flat(out) if t.is_floating_point()]
print("forward ok: %d output tensors, shapes[:4]=%s" % (len(tensors), [tuple(t.shape) for t in tensors[:4]]))
loss = sum(t.float().square().mean() for t in tensors)
loss.backward()
gnorm = sum(float(p.grad.float().square().sum()) for p in model.parameters() if p.grad is not None) ** 0.5
print("loss        = %.6f" % float(loss))
print("grad l2norm = %.6f" % gnorm)
assert gnorm > 0.0 and gnorm == gnorm, "gradient is zero or NaN"
torch.cuda.synchronize()
print("mem alloc MB=%.1f" % (torch.cuda.max_memory_allocated() / 2**20))
print("TORCH_SMOKE_OK")
PY
smoke "torch cuda forward/backward ($MODEL_KIND, pos_len $POS_LEN)" \
  python "$R/runtime/smoke/torch_smoke.py" "$MODEL_KIND" "$POS_LEN"

# ----------------------------------------------------------------- 6. verdict
say "stage 6: verdict"
if [ "$FAILED" -eq 0 ]; then
  echo "SMOKE RESULT: PASS" | tee -a "$SMOKE"
  stamp smoke
  cp -f "$SMOKE" "$R/evidence/env/smoke-$SLURM_JOB_ID.txt"
  exit 0
else
  echo "SMOKE RESULT: FAIL" | tee -a "$SMOKE"
  cp -f "$SMOKE" "$R/evidence/env/smoke-$SLURM_JOB_ID.txt"
  exit 1
fi
