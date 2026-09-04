#!/bin/bash
# check_board_param.sh -- mission ktg-train, node arxiv-1902.10565::converged_test_7x7.
#
# THE VERIFIER for this node's first claim: the 7x7 test run is obtained by
# PARAMETERISING the existing 9x9 loop, and every shared file it touches behaves exactly
# as before when the new environment variables are unset -- so the 9x9 production chain
# (job 299461, PENDING when this was written, which stages these files at start) is not
# disturbed.
#
# It is login-node executable: no GPU, no Slurm, no torch. Eleven checks, all EXECUTED:
#
#   C1  train_9x9.sh passes -pos-len "${KTG_POS_LEN:-9}"; the expansion is 9 unset, 7 set
#   C2  check_pos_len_npz.py with KTG_POS_LEN unset reproduces, exactly, the seven
#       trailing shapes and the 2145 B/row it hard-coded before it was parameterised
#   C3  the same module with KTG_POS_LEN=7 gives the shapes trainingwrite.cpp:288-298
#       derives at xLen = yLen = 7, and 1513 B/row
#   C4  the guard ACCEPTS the mission's existing 9x9 npz with the variable unset
#   C5  the guard REFUSES those same npz with KTG_POS_LEN=7 (it is a real guard, not a
#       formality: it fails in the direction that matters)
#   C6  train.py in the SCRATCH CLONE evaluates print_train_loss_every_batches to 100
#       with KTG_PRINT_EVERY unset and to 8 with KTG_PRINT_EVERY=8
#   C7  ref-code/lightvector-KataGo (the read-only mirror) is NOT patched
#   C8  selfplay_7x7.cfg differs from selfplay_9x9.cfg in exactly the six declared keys,
#       gatekeeper_7x7.cfg in exactly four, match_first_latest_7.cfg in exactly five
#   C9  a KTG_STAGE_ONLY=1 dry run of the 9x9 loop still exits 0 and still stages the
#       9x9 configs, byte for byte
#   C10 the same dry run under the 7x7 environment stages the 7x7 configs instead
#   C11 train_9x9.sh's $KTG_TRAIN_EXTRA_ARGS passthrough is EMPTY unset (the 9x9 command
#       line is unchanged) and carries -lr-scale-auto for the 7x7 run
#
# usage:  bash codes/eval/check_board_param.sh
# exit 0 iff every check passes.

set -u
set -o pipefail

AZ_ROOT="${AZ_ROOT:-/home/schmidt/ssci-haiyangw/az}"
PAPER="$AZ_ROOT/results/ktg/paper_1902.10565"
CODES="$PAPER/codes"
KTG_ROOT="${KTG_ROOT:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train}"
KATAGO_SRC="${KATAGO_SRC:-$KTG_ROOT/build/KataGo}"
MIRROR="$AZ_ROOT/ref-code/lightvector-KataGo"
SMOKE_NPZ="${KTG_SMOKE_NPZ:-$KTG_ROOT/runs/smoke/selfplay}"

FAILED=0
pass() { printf '  [ok]   %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*" >&2; FAILED=1; }
head_() { printf '\n== %s\n' "$*"; }

echo "check_board_param -- node arxiv-1902.10565::converged_test_7x7  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  az     = $AZ_ROOT"
echo "  clone  = $KATAGO_SRC"
echo "  mirror = $MIRROR"

# ------------------------------------------------------------------------- C1
head_ "C1  train_9x9.sh -pos-len is \${KTG_POS_LEN:-9}"
if grep -q -- '-pos-len "${KTG_POS_LEN:-9}"' "$CODES/loop/train_9x9.sh"; then
  pass "the literal is present in $CODES/loop/train_9x9.sh"
else
  fail "train_9x9.sh does not pass -pos-len \"\${KTG_POS_LEN:-9}\""
fi
U="$(unset KTG_POS_LEN; bash -c 'echo "${KTG_POS_LEN:-9}"')"
S="$(KTG_POS_LEN=7 bash -c 'echo "${KTG_POS_LEN:-9}"')"
[ "$U" = "9" ] && pass "unset  -> -pos-len 9   (the 9x9 chain is unaffected)" || fail "unset -> '$U', expected 9"
[ "$S" = "7" ] && pass "set 7  -> -pos-len 7" || fail "KTG_POS_LEN=7 -> '$S', expected 7"

# ------------------------------------------------------------------- C2 / C3
head_ "C2/C3  check_pos_len_npz.py expectations at L = 9 (unset) and L = 7"
python3 - "$CODES/eval/check_pos_len_npz.py" <<'PY'
import importlib.util, os, sys
mod_path = sys.argv[1]
# the seven trailing shapes and the row size the file hard-coded BEFORE parameterisation
BEFORE_SHAPES = {
    "binaryInputNCHWPacked": (22, 11),
    "globalInputNC": (19,),
    "policyTargetsNCMove": (2, 82),
    "globalTargetsNC": (80,),
    "scoreDistrN": (282,),
    "valueTargetsNCHW": (5, 9, 9),
    "qValueTargetsNCMove": (3, 82),
}
BEFORE_ROW_BYTES = 2145
# trainingwrite.cpp:288-298 evaluated at xLen = yLen = 7
SEVEN_SHAPES = {
    "binaryInputNCHWPacked": (22, 7),
    "globalInputNC": (19,),
    "policyTargetsNCMove": (2, 50),
    "globalTargetsNC": (80,),
    "scoreDistrN": (218,),
    "valueTargetsNCHW": (5, 7, 7),
    "qValueTargetsNCMove": (3, 50),
}
SEVEN_ROW_BYTES = 1513

def load(env):
    os.environ.pop("KTG_POS_LEN", None)
    if env is not None:
        os.environ["KTG_POS_LEN"] = env
    spec = importlib.util.spec_from_file_location("cpl_%s" % (env or "unset"), mod_path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

rc = 0
m = load(None)
if m.POS_LEN == 9 and m.EXPECTED_SHAPES == BEFORE_SHAPES and m.EXPECTED_ROW_BYTES == BEFORE_ROW_BYTES:
    print("  [ok]   unset -> POS_LEN 9, 2145 B/row, shapes identical to the pre-parameterised constants")
else:
    print("  [FAIL] unset -> POS_LEN %r, %r B/row, shapes %r" % (m.POS_LEN, m.EXPECTED_ROW_BYTES, m.EXPECTED_SHAPES))
    rc = 1
m = load("7")
if m.POS_LEN == 7 and m.EXPECTED_SHAPES == SEVEN_SHAPES and m.EXPECTED_ROW_BYTES == SEVEN_ROW_BYTES:
    print("  [ok]   KTG_POS_LEN=7 -> POS_LEN 7, 1513 B/row, shapes as trainingwrite.cpp derives at 7")
else:
    print("  [FAIL] KTG_POS_LEN=7 -> POS_LEN %r, %r B/row, shapes %r" % (m.POS_LEN, m.EXPECTED_ROW_BYTES, m.EXPECTED_SHAPES))
    rc = 1
sys.exit(rc)
PY
[ $? -eq 0 ] || FAILED=1

# ------------------------------------------------------------------- C4 / C5
head_ "C4/C5  the guard on this mission's real 9x9 npz, both ways"
if [ -d "$SMOKE_NPZ" ] && [ -n "$(find "$SMOKE_NPZ" -name '*.npz' -print -quit 2>/dev/null)" ]; then
  if (unset KTG_POS_LEN; python3 "$CODES/eval/check_pos_len_npz.py" "$SMOKE_NPZ" >/dev/null 2>&1); then
    pass "unset  -> ACCEPTS the 9x9 rows in $SMOKE_NPZ (exit 0)"
  else
    fail "unset  -> refused the mission's own 9x9 rows"
  fi
  if KTG_POS_LEN=7 python3 "$CODES/eval/check_pos_len_npz.py" "$SMOKE_NPZ" >/dev/null 2>&1; then
    fail "KTG_POS_LEN=7 -> ACCEPTED 9x9 rows; the guard is not guarding"
  else
    pass "KTG_POS_LEN=7 -> REFUSES the 9x9 rows (exit non-zero), naming every wrong array"
  fi
else
  fail "no 9x9 npz under $SMOKE_NPZ -- C4/C5 could not be executed"
fi

# ------------------------------------------------------------------------- C6
head_ "C6  print_train_loss_every_batches in the SCRATCH CLONE"
python3 - "$KATAGO_SRC/python/train.py" <<'PY'
import os, re, sys
src = open(sys.argv[1]).read()
m = re.search(r"^\s*print_train_loss_every_batches = (.+)$", src, re.M)
if not m:
    print("  [FAIL] no print_train_loss_every_batches assignment found"); sys.exit(1)
expr = m.group(1)
if "KTG_PRINT_EVERY" not in expr:
    print("  [FAIL] the assignment does not read KTG_PRINT_EVERY: %s" % expr); sys.exit(1)
rc = 0
for env, want in ((None, 100), ("8", 8), ("5", 5)):
    os.environ.pop("KTG_PRINT_EVERY", None)
    if env is not None:
        os.environ["KTG_PRINT_EVERY"] = env
    got = eval(expr, {"os": os, "max": max, "int": int}, {"gnorm_stats_debug": False})
    label = "unset" if env is None else "KTG_PRINT_EVERY=%s" % env
    if got == want:
        print("  [ok]   %-22s -> print interval %d" % (label, got))
    else:
        print("  [FAIL] %-22s -> %r, expected %d" % (label, got, want)); rc = 1
got = eval(expr, {"os": os, "max": max, "int": int}, {"gnorm_stats_debug": True})
if got == 1000:
    print("  [ok]   gnorm_stats_debug branch still 1000 (untouched)")
else:
    print("  [FAIL] gnorm_stats_debug branch -> %r, expected 1000" % (got,)); rc = 1
sys.exit(rc)
PY
[ $? -eq 0 ] || FAILED=1

# ------------------------------------------------------------------------- C7
head_ "C7  the read-only mirror is NOT patched (alignment.md section 4)"
if grep -q 'KTG_PRINT_EVERY' "$MIRROR/python/train.py" 2>/dev/null; then
  fail "$MIRROR/python/train.py carries the patch -- the mirror must never be edited"
else
  pass "$MIRROR/python/train.py is unpatched"
fi
if grep -q 'print_train_loss_every_batches = 100 if not gnorm_stats_debug else 1000' "$MIRROR/python/train.py" 2>/dev/null; then
  pass "the mirror still holds upstream's literal 100"
else
  fail "the mirror's assignment is not upstream's literal 100"
fi

# ------------------------------------------------------------------------- C8
head_ "C8  the 7x7 configs differ from the 9x9 ones in exactly the declared keys"
cfgdiff() {  # cfgdiff <9x9> <7x7> <expected key count> <key ...>
  local a="$1" b="$2" want="$3"; shift 3
  local got n
  got="$(diff <(grep -v '^#' "$a") <(grep -v '^#' "$b") | grep '^[<>]' | sed 's/^[<>] *//' \
         | sed 's/ *=.*//' | sed 's/#.*//' | tr -d ' ' | grep -v '^$' | sort -u | tr '\n' ' ')"
  n=$(echo "$got" | wc -w)
  if [ "$n" -eq "$want" ]; then
    pass "$(basename "$b"): $want keys differ -> $got"
  else
    fail "$(basename "$b"): $n keys differ (expected $want) -> $got"
  fi
  local k
  for k in "$@"; do
    case " $got " in *" $k "*) ;; *) fail "$(basename "$b"): declared key '$k' does not actually differ" ;; esac
  done
}
cfgdiff "$CODES/cfg/selfplay_9x9.cfg" "$CODES/cfg/selfplay_7x7.cfg" 6 \
        dataBoardLen bSizes numGameThreads maxVisits cheapSearchVisits reducedVisitsMin
cfgdiff "$CODES/cfg/gatekeeper_9x9.cfg" "$CODES/cfg/gatekeeper_7x7.cfg" 4 \
        bSizes numGameThreads numGamesPerGating maxVisits
cfgdiff "$CODES/cfg/match_first_latest_9.cfg" "$CODES/cfg/match_first_latest_7.cfg" 5 \
        bSizes numGameThreads numGamesTotal maxVisits komiMean

# ------------------------------------------------------------------ C9 / C10
head_ "C9/C10  KTG_STAGE_ONLY dry runs of the 9x9 loop"
if [ ! -x "$KATAGO_SRC/cpp/build/katago" ]; then
  fail "no katago binary at $KATAGO_SRC/cpp/build/katago -- the dry runs need it staged"
else
  staged_hashes() {   # staged_hashes <basedir>
    local a
    a="$(ls -1dt "$1"/scripts/dated/*/ 2>/dev/null | head -1)"
    [ -n "$a" ] || return 1
    sha256sum "$a/selfplay.cfg" "$a/gatekeeper.cfg" 2>/dev/null | cut -d' ' -f1 | tr '\n' ' '
  }
  NINE_SP="$(sha256sum "$CODES/cfg/selfplay_9x9.cfg" | cut -d' ' -f1)"
  NINE_GK="$(sha256sum "$CODES/cfg/gatekeeper_9x9.cfg" | cut -d' ' -f1)"
  SEVEN_SP="$(sha256sum "$CODES/cfg/selfplay_7x7.cfg" | cut -d' ' -f1)"
  SEVEN_GK="$(sha256sum "$CODES/cfg/gatekeeper_7x7.cfg" | cut -d' ' -f1)"

  D9="$KTG_ROOT/runs/dryrun_check9"; rm -rf "$D9"; mkdir -p "$D9"
  if (cd "$KATAGO_SRC" && env -u KTG_POS_LEN -u SELFPLAY_CONFIG -u GATING_CONFIG \
        KATAGO_BIN="$KATAGO_SRC/cpp/build/katago" KATAGO_SRC="$KATAGO_SRC" \
        KTG_CODES="$CODES" KTG_STAGE_ONLY=1 \
        bash "$CODES/loop/synchronous_loop_9x9.sh" chk9 "$D9" t9 b7c96h3tfrs 1 >/dev/null 2>&1); then
    got="$(staged_hashes "$D9")"
    if [ "$got" = "$NINE_SP $NINE_GK " ]; then
      pass "C9  9x9 dry run exits 0 and stages selfplay_9x9.cfg + gatekeeper_9x9.cfg byte for byte"
    else
      fail "C9  9x9 dry run staged '$got', expected '$NINE_SP $NINE_GK '"
    fi
  else
    fail "C9  the 9x9 KTG_STAGE_ONLY dry run did not exit 0"
  fi

  D7="$KTG_ROOT/runs/dryrun_check7"; rm -rf "$D7"; mkdir -p "$D7"
  if (cd "$KATAGO_SRC" && env KTG_POS_LEN=7 \
        SELFPLAY_CONFIG="$CODES/cfg/selfplay_7x7.cfg" \
        GATING_CONFIG="$CODES/cfg/gatekeeper_7x7.cfg" \
        KATAGO_BIN="$KATAGO_SRC/cpp/build/katago" KATAGO_SRC="$KATAGO_SRC" \
        KTG_CODES="$CODES" KTG_STAGE_ONLY=1 \
        bash "$CODES/loop/synchronous_loop_9x9.sh" chk7 "$D7" t7 b7c96h3tfrs 1 >/dev/null 2>&1); then
    got="$(staged_hashes "$D7")"
    if [ "$got" = "$SEVEN_SP $SEVEN_GK " ]; then
      pass "C10 7x7 dry run exits 0 and stages selfplay_7x7.cfg + gatekeeper_7x7.cfg"
    else
      fail "C10 7x7 dry run staged '$got', expected '$SEVEN_SP $SEVEN_GK '"
    fi
  else
    fail "C10 the 7x7 KTG_STAGE_ONLY dry run did not exit 0"
  fi
  rm -rf "$D9" "$D7"
fi

# ------------------------------------------------------------------------ C11
head_ "C11  train_9x9.sh \$KTG_TRAIN_EXTRA_ARGS passthrough"
if grep -q '^     \$KTG_TRAIN_EXTRA_ARGS \\$' "$CODES/loop/train_9x9.sh"; then
  pass "the unquoted passthrough sits on its own line in the train.py invocation"
else
  fail "train_9x9.sh does not expand \$KTG_TRAIN_EXTRA_ARGS in the train.py invocation"
fi
# The wrapper builds the command line by UNQUOTED expansion, exactly like $EXTRAFLAG, so
# an unset variable must contribute zero words -- not one empty argument, which train.py
# would reject.
NARGS_UNSET="$(unset KTG_TRAIN_EXTRA_ARGS; bash -c 'KTG_TRAIN_EXTRA_ARGS="${KTG_TRAIN_EXTRA_ARGS:-}"; set -- x $KTG_TRAIN_EXTRA_ARGS y; echo $#')"
NARGS_SET="$(KTG_TRAIN_EXTRA_ARGS=-lr-scale-auto bash -c 'KTG_TRAIN_EXTRA_ARGS="${KTG_TRAIN_EXTRA_ARGS:-}"; set -- x $KTG_TRAIN_EXTRA_ARGS y; echo $#')"
[ "$NARGS_UNSET" = "2" ] && pass "unset  -> contributes 0 words (the 9x9 command line is unchanged)"                          || fail "unset  -> the expansion contributed $((NARGS_UNSET - 2)) word(s), expected 0"
[ "$NARGS_SET" = "3" ]   && pass "set    -> contributes exactly 1 word (-lr-scale-auto)"                          || fail "set    -> $((NARGS_SET - 2)) word(s), expected 1"
if grep -q 'KTG_TRAIN_EXTRA_ARGS:--lr-scale-auto' "$CODES/loop/t7_cycle.sh"; then
  pass "t7_cycle.sh defaults it to -lr-scale-auto (train.py:504-512 -> constant 8.0 below 550 M samples)"
else
  fail "t7_cycle.sh does not default KTG_TRAIN_EXTRA_ARGS to -lr-scale-auto"
fi
if grep -q "elif train_state\[\"global_step_samples\"\] < 250000:" "$KATAGO_SRC/python/train.py" \
   && grep -q 'warmup_scale = 1.0 / 20.0' "$KATAGO_SRC/python/train.py"; then
  pass "the 1/20 warmup below 250000 samples that motivates it is still in train.py"
else
  fail "train.py's <250000-sample 1/20 warmup branch was not found -- re-derive the LR choice"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "CHECK_BOARD_PARAM: PASS"
else
  echo "CHECK_BOARD_PARAM: FAIL"
fi
exit "$FAILED"
