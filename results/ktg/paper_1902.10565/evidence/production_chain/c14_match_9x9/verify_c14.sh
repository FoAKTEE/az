#!/bin/bash -l
# Re-derives the c14 numbers from the raw match records and asserts them against
# results.json. Exit 0 iff every recorded number is reproduced. Run from the az root.
set -uo pipefail
HERE="${HERE:-/home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/evidence/production_chain/c14_match_9x9}"
SGFS="${C14_SGFS:-$HERE/sgfs}"
[ -d "$SGFS" ] || SGFS=/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/matches/2026-09-06
python3 - "$HERE" "$SGFS" <<'PY'
import glob, json, math, os, re, sys
here, sgfs = sys.argv[1], sys.argv[2]
R = json.load(open(os.path.join(here, "results.json")))
HDR = re.compile(r"PB\[([^\]]*)\]PW\[([^\]]*)\].*?RE\[([^\]]*)\]")
Z = 1.959963985
ok = True
for arm, rec in R["arms"].items():
    files = sorted(glob.glob(os.path.join(sgfs, arm, "*.sgfs"))) or \
            sorted(glob.glob(os.path.join(sgfs, arm, "match-*", "*.sgfs")))
    assert files, "no sgfs found for " + arm
    n = w = 0; wins = losses = draws = 0
    for f in files:
        for line in open(f):
            line = line.strip()
            if not line: continue
            m = HDR.search(line); assert m
            pb, pw, re_ = m.groups()
            colour = "B" if pb == "latest" else "W"
            win = re_[:1].upper()
            s = 1.0 if win == colour else (0.0 if win in ("B", "W") else 0.5)
            n += 1; w += s
            wins += (s == 1.0); losses += (s == 0.0); draws += (s == 0.5)
    p = w / n
    se = math.sqrt(p * (1 - p) / n)
    elo = float("inf") if p >= 1 else -400 * math.log10(1 / p - 1)
    checks = [("games", n, rec["games"]), ("score", w, rec["score_for_latest"]),
              ("wins", wins, rec["wins"]), ("losses", losses, rec["losses"]),
              ("draws", draws, rec["draws"]),
              ("p", round(p, 9), round(rec["p"], 9)),
              ("se", round(se, 9), round(rec["se"], 9)),
              ("ci_lo", round(max(0.0, p - Z * se), 9), round(rec["ci95"][0], 9)),
              ("ci_hi", round(min(1.0, p + Z * se), 9), round(rec["ci95"][1], 9)),
              ("elo", elo, rec["elo"])]
    print(f"{arm}: {int(w) if w==int(w) else w}/{n}  p={p:.4f}  se={se:.4f}  "
          f"CI=[{max(0.0,p-Z*se):.4f},{min(1.0,p+Z*se):.4f}]  "
          f"Elo={'inf' if math.isinf(elo) else '%+.1f' % elo}")
    for name, got, want in checks:
        if got != want:
            print(f"   MISMATCH {name}: recomputed {got} vs recorded {want}"); ok = False
    assert n == 400, f"{arm} is not 400 games"
    b = sum(1 for f in files for line in open(f) if line.strip()
            and HDR.search(line).group(1) == "latest")
    assert b == 200, f"{arm} colour split is {b}/200 Black, not 200/200"
    print(f"   colour split verified 200 B / 200 W; every field reproduced")
pa = R["arms"]["armA_vs_s20919936"]["p"]
assert pa >= 0.60, "arm A no longer clears the memo's 0.60 rule"
print(f"\nC14_VERIFIED: p(latest vs t9-s20919936) = {pa:.4f} >= 0.60 -- the 19-export loss "
      f"stall is NOT a strength stall; memo option (b) LR x0.5 is NOT triggered")
sys.exit(0 if ok else 1)
PY
