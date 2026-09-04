# env.sh -- reusable toolchain environment for mission ktg-train.
# Source it (do not execute) on a compute node, or in a job script after `#!/bin/bash -l`:
#   source /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/env.sh
# Canonical copy lives at $KTG_ROOT/env.sh; this repo copy is the tracked mirror.

export KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"

module load gcc/12.3.0 cmake/3.30.2 cuda/12.8.1 python/3.11.9

# Python 3.11 venv (torch 2.11.0+cu128, numpy, scipy, psutil, packaging, sgfmill,
# nvidia-cudnn-cu12 >= 9.8 which is also the cuDNN the C++ engine links against).
# shellcheck disable=SC1091
source "$KTG_ROOT/venv/bin/activate"

# cuDNN comes from the pip wheel: no system cuDNN exists on these nodes.
export KTG_CUDNN_DIR="$KTG_ROOT/venv/lib/python3.11/site-packages/nvidia/cudnn"
export LD_LIBRARY_PATH="$KTG_CUDNN_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# KataGo v1.18.2 source tree and CUDA-backend binary.
export KATAGO_SRC="$KTG_ROOT/build/KataGo"
export KATAGO_BUILD="$KATAGO_SRC/cpp/build"
export KATAGO_BIN="$KATAGO_BUILD/katago"
export PATH="$KATAGO_BUILD:$PATH"

# So `import katago.train...` and `import muon` resolve from anywhere.
export PYTHONPATH="$KATAGO_SRC/python${PYTHONPATH:+:$PYTHONPATH}"
