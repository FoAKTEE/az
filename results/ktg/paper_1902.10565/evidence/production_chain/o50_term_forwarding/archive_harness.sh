#!/bin/bash
# ============================================================================
# SGF-archive harness (packet 3) and the KTG_ARCHIVE_SGF=0 no-op proof.
# CPU only, login node, no Slurm job, no scheduler call. Everything happens in
# $W; runs/p1 is neither read nor written.
# ============================================================================
set -u
W=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/work/o50_o51
S="$W/sandbox"
AZ=/home/schmidt/ssci-haiyangw/az
CODES="$AZ/results/ktg/paper_1902.10565/codes"
PASS=0; FAIL=0
ck() { local label="$1"; shift; if "$@"; then printf '    ok    %s\n' "$label"; PASS=$((PASS+1)); else printf '    FAIL  %s\n' "$label"; FAIL=$((FAIL+1)); fi; }
sect() { echo; echo "########## $*"; }

echo "host: $(hostname)  date: $(date -Is)"
sha256sum "$CODES/data_budget/archive_sgf.sh" "$CODES/loop/knobs_9x9.env" \
          "$CODES/loop/synchronous_loop_9x9.sh" "$CODES/loop/loop.sbatch" \
          "$CODES/data_budget/prune_retention.py" \
          "$CODES/eval/games_viewer/extract_games.py" | sed 's/^/    /'
echo "  mode bits:"; stat -c '    %a  %n' "$CODES/data_budget/archive_sgf.sh" "$CODES/eval/rows_history.py" "$CODES/eval/seed_rows_history.py" "$CODES/eval/test_rows_history.py"

# ---------------------------------------------------------------- 1. bash -n
sect "1. bash -n over every script of codes/loop and codes/data_budget"
n_ok=0; n_bad=0
for f in "$CODES"/loop/*.sh "$CODES"/loop/*.sbatch "$CODES"/data_budget/*.sh "$CODES"/eval/*.sh; do
  if bash -n "$f" 2>/dev/null; then n_ok=$((n_ok+1)); else echo "  PARSE FAIL $f"; bash -n "$f"; n_bad=$((n_bad+1)); fi
done
echo "  parsed ok: $n_ok   parse failures: $n_bad"
ck "1a every shell script parses" test "$n_bad" -eq 0
ck "1b archive_sgf.sh is 0755" test "$(stat -c %a "$CODES/data_budget/archive_sgf.sh")" = "755"

# ---------------------------------------------------------------- 2. flag is 0
sect "2. the committed knob file ships the flag OFF"
grep -n '^KTG_ARCHIVE_SGF=' "$CODES/loop/knobs_9x9.env" | sed 's/^/  /'
ck "2a KTG_ARCHIVE_SGF=0 in the committed knob file" \
   grep -qx 'KTG_ARCHIVE_SGF=0' "$CODES/loop/knobs_9x9.env"
ck "2b the archiver is a no-op with the flag unset" \
   bash -c "cd $W && rm -rf arch_noop && mkdir -p arch_noop/selfplay/n1/sgfs && : > arch_noop/selfplay/n1/sgfs/a.sgfs && bash '$CODES/data_budget/archive_sgf.sh' $W/arch_noop >/dev/null 2>&1 && [ ! -e $W/arch_noop/archive ]"

# ---------------------------------------------------------------- 3. staged-file no-op proof
sect "3. KTG_STAGE_ONLY=1: the staged archive is byte-identical to the version at HEAD"
HEADDIR="$W/head_codes"; rm -rf "$HEADDIR"; mkdir -p "$HEADDIR"
git -C "$AZ" show HEAD:results/ktg/paper_1902.10565/codes/loop/synchronous_loop_9x9.sh > "$HEADDIR/synchronous_loop_9x9.sh"
chmod 0755 "$HEADDIR/synchronous_loop_9x9.sh"
stage_run() {   # stage_run <loop-script> <outdir-tag>
  local sh="$1" tag="$2"
  local base="$W/stage_$tag"
  rm -rf "$base"; mkdir -p "$base"
  ( cd "$S/src/katago-clone" && \
    KTG_CODES="$CODES" KATAGO_SRC="$S/src/katago-clone" \
    KATAGO_BIN="$S/src/katago-clone/cpp/build/katago" \
    TRAIN_WRAPPER="$S/src/train_stub.sh" EXPORT_WRAPPER="$S/src/export_stub.sh" \
    KTG_SCRATCH_GUARD="$S/src/guard_stub.sh" \
    KTG_ARCHIVE_SGF=0 KTG_STAGE_ONLY=1 \
    bash "$sh" ktg9 "$base" t9 b7c96h3tfrs 1 ) > "$W/stage_$tag.log" 2>&1
  echo "$?"
}
rc_head=$(stage_run "$HEADDIR/synchronous_loop_9x9.sh" head)
rc_new=$(stage_run "$CODES/loop/synchronous_loop_9x9.sh" new)
echo "  HEAD dry run exit $rc_head ; working-tree dry run exit $rc_new"
tail -2 "$W/stage_head.log" | sed 's/^/  HEAD: /'
tail -2 "$W/stage_new.log"  | sed 's/^/  NEW : /'
manifest() {  # sha256 of every staged file, with the dated directory name normalised away
  ( cd "$1" && find . -type f -printf '%P\n' | sort | while read -r f; do
      printf '%s  %s\n' "$(sha256sum "$1/$f" 2>/dev/null | cut -d' ' -f1)" \
        "$(printf '%s' "$f" | sed -E 's#scripts/dated/[0-9]{8}-[0-9]{6}/#scripts/dated/<TS>/#')"
    done )
}
manifest "$W/stage_head" > "$W/manifest_head.txt"
manifest "$W/stage_new"  > "$W/manifest_new.txt"
echo "  staged files: HEAD $(wc -l < "$W/manifest_head.txt")   working tree $(wc -l < "$W/manifest_new.txt")"
if diff -u "$W/manifest_head.txt" "$W/manifest_new.txt" > "$W/manifest_diff.txt"; then
  echo "  diff of the two staged manifests: EMPTY"
else
  echo "  diff of the two staged manifests:"; sed 's/^/    /' "$W/manifest_diff.txt"
fi
ck "3a both dry runs exit 0"                    bash -c "[ '$rc_head' = 0 ] && [ '$rc_new' = 0 ]"
ck "3b the staged trees are byte-identical"     test ! -s "$W/manifest_diff.txt"
ck "3c no archive/ directory was created at 0"  test ! -e "$W/stage_new/archive"

# ---------------------------------------------------------------- 4. the archiver at 1
sect "4. KTG_ARCHIVE_SGF=1: hard links, idempotence, and what du sees"
B="$W/arch_tree"; rm -rf "$B"; mkdir -p "$B"/selfplay/{t9-s100-d1,t9-s200-d2}/sgfs
head -c 4000 /dev/urandom | base64 > "$B/selfplay/t9-s100-d1/sgfs/AAA.sgfs"
head -c 4000 /dev/urandom | base64 > "$B/selfplay/t9-s200-d2/sgfs/BBB.sgfs"
before=$(du -sb "$B" | cut -f1)
KTG_ARCHIVE_SGF=1 bash "$CODES/data_budget/archive_sgf.sh" "$B" --label "test" | sed 's/^/  /'
after=$(du -sb "$B" | cut -f1)
echo "  du -sb before $before  after $after  delta $(( after - before )) B (hard links: du counts an inode once)"
ck "4a the archive tree exists"          test -d "$B/archive/sgf/t9-s100-d1"
ck "4b the archived file is the SAME inode" test "$B/archive/sgf/t9-s100-d1/AAA.sgfs" -ef "$B/selfplay/t9-s100-d1/sgfs/AAA.sgfs"
ck "4c du grew by less than one file"    test $(( after - before )) -lt 4000
out2=$(KTG_ARCHIVE_SGF=1 bash "$CODES/data_budget/archive_sgf.sh" "$B" --label "again")
echo "$out2" | sed 's/^/  /'
ck "4d the second pass links nothing"    bash -c "printf '%s' \"$out2\" | grep -q 'linked=0 copied=0 already-linked=2'"
# the generation is pruned; the archive keeps the games
rm -rf "$B/selfplay/t9-s100-d1"
ck "4e the archive survives the deleted generation" test -s "$B/archive/sgf/t9-s100-d1/AAA.sgfs"

# ---------------------------------------------------------------- 5. the pruner protects it
sect "5. prune_retention.py protects the archive"
P5="$W/prune_tree"; rm -rf "$P5"; mkdir -p "$P5"/loop/archive/sgf/t9-old "$P5"/loop/selfplay/t9-old/sgfs
echo x > "$P5/loop/archive/sgf/t9-old/AAA.sgfs"
python3 "$CODES/data_budget/prune_retention.py" --root "$P5" --basedir "$P5/loop" \
    --budget-env "$CODES/data_budget/budget.env" > "$W/prune_out.txt" 2>&1
grep -E "PROTECT .*archive|DELETE|would delete" "$W/prune_out.txt" | sed 's/^/  /'
ck "5a the archive is in the protected set" grep -q "PROTECT .*/loop/archive .*SGF archive" "$W/prune_out.txt"
ck "5b nothing under archive/ is a candidate" bash -c "! grep -E '^[[:space:]]*(DELETE|would)' '$W/prune_out.txt' | grep -q '/archive/'"

# ---------------------------------------------------------------- 6. the viewer reads it
sect "6. extract_games.py reads archive/sgf and de-duplicates"
python3 - "$CODES" "$W" <<'PY'
import os, sys, time
codes, W = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(codes, "eval", "games_viewer"))
import extract_games as E
run = os.path.join(W, "viewer_tree")
os.system("rm -rf %s" % run)
for p in ("selfplay/t9-s200-d2/sgfs", "archive/sgf/t9-s100-d1", "archive/sgf/t9-s200-d2"):
    os.makedirs(os.path.join(run, p))
live = os.path.join(run, "selfplay/t9-s200-d2/sgfs/BBB.sgfs")
open(live, "w").write("(;FF[4]SZ[9];B[cc];W[dd])\n")
# the archived copy of the LIVE net is the same file (hard link), and the archived
# copy of the PRUNED net is all that is left of it
os.link(live, os.path.join(run, "archive/sgf/t9-s200-d2/BBB.sgfs"))
open(os.path.join(run, "archive/sgf/t9-s100-d1/AAA.sgfs"), "w").write(
    "(;FF[4]SZ[9];B[ee];W[ff])\n")
files, hot = E.snapshot_files(run, 0)
paths = sorted(f[2].replace(run + "/", "") for f in files)
print("  snapshot_files ->")
for p in paths:
    print("    %s" % p)
n_arch = sum(1 for f in files if "/archive/" in f[2])
assert len(files) == 2, files
assert n_arch == 1, n_arch
assert "archive/sgf/t9-s100-d1/AAA.sgfs" in paths
assert "selfplay/t9-s200-d2/sgfs/BBB.sgfs" in paths
print("  OK: 2 files, 1 from the archive, the hard-linked duplicate de-duplicated")
PY
ck "6a viewer dedupe + archive read" test $? -eq 0

# ---------------------------------------------------------------- 7. knob checker still passes
sect "7. the knob checker still passes with the new knob file"
NEWSHA=$(sha256sum "$CODES/loop/knobs_9x9.env" | cut -c1-16)
echo "  knobs_9x9.env sha256 (first 16) = $NEWSHA   full: $(sha256sum "$CODES/loop/knobs_9x9.env" | cut -d' ' -f1)"
( cd "$AZ/results/ktg/paper_1902.10565" && python3 codes/eval/check_knobs_9x9.py \
    --knobs codes/loop/knobs_9x9.env --throughput "$W/throughput_live.json" \
    --rows-file evidence/production_chain/rows_per_game_history.jsonl \
    --marginal-nets 3 --trend-nets 9 --horizon-nets 10 ) > "$W/checkknobs_after.txt" 2>&1
CKRC=$?
tail -3 "$W/checkknobs_after.txt" | sed 's/^/  /'
ck "7a check_knobs_9x9 exits 0" test "$CKRC" -eq 0
ck "7b check_knobs_9x9 says PASS" grep -q '^CHECK_KNOBS_9X9: PASS' "$W/checkknobs_after.txt"

echo
echo "########## RESULT"
echo "archive harness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
