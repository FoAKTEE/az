#!/bin/bash -l
# export_smoke.sh -- node arxiv-1902.10565::tiny_model_export_smoke.
#
# End-to-end smoke for the transformer export path: exporter -> model.bin ->
# C++ model reader -> GPU forward pass, plus the SwiGLU negative fixture.
# Legs, in order (see tasks/tiny_model_export_smoke/implementation.md Section 2):
#
#   1  export a random-initialized <kind> with python/export_model_pytorch.py, gzip it
#   2  check_export_blocks.py -- exact block-kind histogram over model.bin
#   3  katago benchmarknn -json at 9x9, require sumMedianNNEvalsPerSec > 0
#   4  katago gtp at 9x9, require a legal genmove vertex
#   5  negative fixture (o23_ffn_negative_fixture): the same binary must REFUSE a
#      non-SwiGLU transformer FFN export with its exact diagnostic
#
# Must run on a GPU node (legs 3-5 need a CUDA device); the export itself is CPU.
# Exits 0 only if every leg passes. Usage:
#
#   bash export_smoke.sh <model-kind>          # e.g. b7c96h3tfrs
#
# Env overrides: KTG_ROOT, W (positive workdir), W_NEG (negative-fixture workdir).

set -uo pipefail

# Leg 5 deliberately aborts the engine (throw -> terminate). Scratch is ~94% full,
# so never let that abort leave a core file behind.
ulimit -c 0 2>/dev/null || true

KIND="${1:-}"
if [ -z "$KIND" ]; then
  echo "usage: export_smoke.sh <model-kind>   (e.g. b7c96h3tfrs)" >&2
  exit 2
fi

: "${KTG_ROOT:=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"

# Self-sufficient environment: only source env.sh when the toolchain is not
# already in the shell, so this runs standalone or nested inside a job script.
if [ -z "${KATAGO_BIN:-}" ]; then
  if ! type module >/dev/null 2>&1; then
    for f in /etc/profile.d/zz-dsai_lmod.sh /etc/profile.d/lmod.sh /etc/profile.d/modules.sh; do
      # shellcheck disable=SC1090
      [ -f "$f" ] && . "$f" && break
    done
  fi
  # shellcheck disable=SC1090
  . "$KTG_ROOT/env.sh"
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$HERE/check_export_blocks.py"

: "${W:=$KTG_ROOT/runtime/smoke/x}"
: "${W_NEG:=$KTG_ROOT/runtime/smoke/x_ffng}"

# The one place in the mission allowed to name the non-SwiGLU config: it exists
# solely as this fixture and must never reach MODELKIND or any loop script.
NEG_KIND=b5c48h3tfr
NEG_DIAG="Non-SwiGLU transformer FFN is not yet supported in CUDA backend"

CFG="$KATAGO_SRC/cpp/configs/gtp_example.cfg"
EXPORTER="$KATAGO_SRC/python/export_model_pytorch.py"

FAILED=0
say()  { echo; echo "--- $*"; }
ok()   { echo "[OK] $*"; }
bad()  { echo "[FAIL] $*"; FAILED=1; }

echo "== tiny_model_export_smoke  $(date -Is)  host=$(hostname)  job=${SLURM_JOB_ID:-none}"
echo "== kind=$KIND  W=$W  W_NEG=$W_NEG"
echo "== katago=$KATAGO_BIN"
echo "== cfg=$CFG"
"$KATAGO_BIN" version 2>&1 | sed 's/^/   /'
nvidia-smi --query-gpu=index,name,compute_cap --format=csv,noheader 2>&1 | sed 's/^/   gpu: /'
echo "== katago sha: $(git -C "$KATAGO_SRC" rev-parse HEAD 2>/dev/null)"

# ---------------------------------------------------------------- leg 1: export
say "leg 1: export random-initialized $KIND with export_model_pytorch.py"
rm -rf "$W"; mkdir -p "$W"
( cd "$KATAGO_SRC/python" && python export_model_pytorch.py \
    -export-random-initialized-model "$KIND" \
    -export-dir "$W" \
    -model-name "ktg-smoke-$KIND" \
    -filename-prefix model ) 2>&1 | tail -5
if [ "${PIPESTATUS[0]}" -eq 0 ] && [ -f "$W/model.bin" ]; then
  gzip -kf "$W/model.bin" && ok "leg 1 export ($EXPORTER)" || bad "leg 1 gzip"
else
  bad "leg 1 export ($EXPORTER)"
fi
ls -l "$W"

# ------------------------------------------------------------- leg 2: histogram
say "leg 2: block-kind histogram (exact match, no other kind)"
if python3 "$CHECKER" "$W/model.bin"; then
  ok "leg 2 block histogram"
else
  bad "leg 2 block histogram"
fi

# ----------------------------------------------------------- leg 3: benchmarknn
say "leg 3: benchmarknn -json, 9x9, require-exact-nnlen, batch 2"
mkdir -p "$W/gtp_logs"
cd "$W" || exit 1
"$KATAGO_BIN" benchmarknn \
  -model "$W/model.bin.gz" -config "$CFG" \
  -boardsize 9 -require-exact-nnlen -batch-size 2 -warmup 1 -iterations 2 -json \
  >"$W/benchmarknn.json" 2>"$W/benchmarknn.err"
BNN_RC=$?
echo "benchmarknn exit=$BNN_RC"
echo "stdout:"; cat "$W/benchmarknn.json"
echo "stderr (tail):"; tail -20 "$W/benchmarknn.err"
if [ "$BNN_RC" -eq 0 ] && python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
v=d["sumMedianNNEvalsPerSec"]
print("sumMedianNNEvalsPerSec = %r" % v)
sys.exit(0 if (v == v and v > 0) else 1)
' "$W/benchmarknn.json"; then
  ok "leg 3 benchmarknn sumMedianNNEvalsPerSec > 0"
else
  bad "leg 3 benchmarknn (exit $BNN_RC or sumMedianNNEvalsPerSec <= 0)"
fi

# -------------------------------------------------------------------- leg 4: gtp
say "leg 4: gtp genmove on 9x9"
printf 'boardsize 9\nkomi 7.0\nclear_board\ngenmove b\nquit\n' > "$W/gtp_in.txt"
"$KATAGO_BIN" gtp -model "$W/model.bin.gz" -config "$CFG" \
  <"$W/gtp_in.txt" >"$W/gtp_out.txt" 2>"$W/gtp_err.txt"
GTP_RC=$?
echo "gtp exit=$GTP_RC"
echo "stdout:"; cat "$W/gtp_out.txt"
GTP_VERTEX=$(grep -cE '^= ([A-HJ][1-9]|pass|PASS)[[:space:]]*$' "$W/gtp_out.txt")
echo "legal-vertex responses = $GTP_VERTEX"
grep -E '^= ([A-HJ][1-9]|pass|PASS)[[:space:]]*$' "$W/gtp_out.txt" | sed 's/^/genmove response: /'
if [ "$GTP_RC" -eq 0 ] && [ "$GTP_VERTEX" -ge 1 ]; then
  ok "leg 4 gtp genmove returned a legal 9x9 vertex"
else
  bad "leg 4 gtp (exit $GTP_RC, legal-vertex responses $GTP_VERTEX)"
fi

# -------------------------------------------- leg 5: negative fixture (o23)
say "leg 5: negative fixture -- the engine must REFUSE a non-SwiGLU transformer FFN"
rm -rf "$W_NEG"; mkdir -p "$W_NEG"
( cd "$KATAGO_SRC/python" && python export_model_pytorch.py \
    -export-random-initialized-model "$NEG_KIND" \
    -export-dir "$W_NEG" \
    -model-name "ktg-smoke-$NEG_KIND" \
    -filename-prefix model ) 2>&1 | tail -3
NEG_EXPORT_RC=${PIPESTATUS[0]}
if [ "$NEG_EXPORT_RC" -eq 0 ] && [ -f "$W_NEG/model.bin" ]; then
  gzip -kf "$W_NEG/model.bin"
  ok "leg 5a negative fixture exported (the exporter itself does not object)"
else
  bad "leg 5a negative fixture export failed (exit $NEG_EXPORT_RC) -- fixture is inconclusive"
fi
cd "$W_NEG" || exit 1
mkdir -p "$W_NEG/gtp_logs"
"$KATAGO_BIN" benchmarknn \
  -model "$W_NEG/model.bin.gz" -config "$CFG" \
  -boardsize 9 -require-exact-nnlen -batch-size 2 -warmup 1 -iterations 2 -json \
  >"$W_NEG/benchmarknn.out" 2>"$W_NEG/benchmarknn.err"
NEG_RC=$?
cat "$W_NEG/benchmarknn.out" "$W_NEG/benchmarknn.err" > "$W_NEG/benchmarknn.both"
echo "negative benchmarknn exit=$NEG_RC"
echo "combined stdout+stderr (tail):"; tail -12 "$W_NEG/benchmarknn.both"
NEG_HITS=$(grep -cF "$NEG_DIAG" "$W_NEG/benchmarknn.both")
NEG_DISTINCT=$(grep -oF "$NEG_DIAG" "$W_NEG/benchmarknn.both" | sort -u | wc -l)
NEG_LOADED=$(grep -cF "Model name: ktg-smoke-$NEG_KIND" "$W_NEG/benchmarknn.both")
echo "diagnostic occurrences   = $NEG_HITS"
echo "distinct diagnostics     = $NEG_DISTINCT"
echo "model-identified lines   = $NEG_LOADED  (proves the refusal is the FFN throw, not a CLI/file error)"
if [ "$NEG_RC" -ne 0 ] && [ "$NEG_HITS" -ge 1 ] && [ "$NEG_DISTINCT" -eq 1 ] && [ "$NEG_LOADED" -ge 1 ]; then
  ok "leg 5 negative fixture REFUSED with the exact diagnostic (exit $NEG_RC)"
else
  bad "leg 5 negative fixture (exit $NEG_RC, diagnostic hits $NEG_HITS, distinct $NEG_DISTINCT, model-identified $NEG_LOADED)"
fi

# ---------------------------------------------------------------------- verdict
say "verdict"
if [ "$FAILED" -eq 0 ]; then
  echo "EXPORT_SMOKE RESULT: PASS"
  exit 0
else
  echo "EXPORT_SMOKE RESULT: FAIL"
  exit 1
fi
