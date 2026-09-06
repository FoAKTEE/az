#!/bin/bash -l
# Refutation of knobs_9x9.env:198 -- "chain link 2 ... resumes a mature window pinned at
# SHUFFLE_KEEPROWS = 120000 rows" -- and of the same file's ":226 samples/cycle =
# SHUFFLE_KEEPROWS = 120000", at the link-1 -> link-2 boundary.
#
# Exit 0 iff the claim is present in the knob file AND the log shows the window below
# SHUFFLE_KEEPROWS at the boundary AND shuffle.py's own formula reproduces that window.
# Run from the az root.
set -uo pipefail
AZ="${AZ:-/home/schmidt/ssci-haiyangw/az}"
KNOBS="$AZ/results/ktg/paper_1902.10565/codes/loop/knobs_9x9.env"
LOG="${KTG_LOOP_LOG:-/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/logs/loop-305318.log}"
python3 - "$KNOBS" "$LOG" <<'PY'
import re, sys
knobs, log = sys.argv[1], sys.argv[2]
K = open(knobs).read().splitlines()

# 1. the claims are in the knob file, at the lines the memo names
c198 = "\n".join(K[195:199])
assert "resumes a mature window pinned at" in c198 and "SHUFFLE_KEEPROWS = 120000 rows" in c198, \
    "knobs_9x9.env:196-199 no longer carries the claim under test"
c226 = "\n".join(K[219:227])
assert "samples/cycle = SHUFFLE_KEEPROWS = 120000" in c226, \
    "knobs_9x9.env:220-227 no longer carries the samples/cycle claim"
assert K[225].strip() == "SHUFFLE_KEEPROWS=120000", "SHUFFLE_KEEPROWS is no longer 120000"
KEEPROWS = 120000
print("claim (knobs_9x9.env:198) :", [l for l in c198.splitlines() if "resumes" in l][0].strip())
print("claim (knobs_9x9.env:226) :", [l for l in c226.splitlines() if "samples/cycle" in l][0].strip())

# 2. the first shuffles of link 2, verbatim from the loop log
des = re.findall(r"^Desired num rows: (\d+) / (\d+)$", open(log).read(), re.M)
fin = re.findall(r"^Finally, using: \((\d+)-(\d+)\) \((\d+)/(\d+) desired rows\)$",
                 open(log).read(), re.M)
assert des and fin, "the loop log has no shuffle window lines"
print("\nfirst five shuffles of link 2 (verbatim):")
below = 0
for i in range(5):
    d, tot = int(des[i][0]), int(des[i][1])
    used = int(fin[i][2])
    flag = "BELOW KEEPROWS" if used < KEEPROWS else "at/above KEEPROWS"
    if used < KEEPROWS:
        below += 1
    print(f"  rows on disk {tot:>9,}  desired {d:>8,}  used {used:>8,}   {flag}")

# 3. the refutation
d0, tot0, used0 = int(des[0][0]), int(des[0][1]), int(fin[0][2])
assert used0 < KEEPROWS, f"the first link-2 window {used0} is not below KEEPROWS {KEEPROWS}"
assert d0 < KEEPROWS, f"the first link-2 desired {d0} is not below KEEPROWS {KEEPROWS}"
assert below >= 3, "fewer than three consecutive link-2 shuffles were below KEEPROWS"
print(f"\nREFUTED: the first link-2 window was {used0:,} rows ({d0:,} desired), "
      f"{KEEPROWS-used0:,} BELOW SHUFFLE_KEEPROWS = {KEEPROWS:,};")
print(f"         {below} of the first five shuffles were below it, so keep_prob was 1.000 "
      f"and samples/cycle was the whole window, not KEEPROWS.")

# 4. shuffle.py's own formula reproduces it from the rows left on disk by the prune
def window(n, min_rows=25000, taper=50000, expo=0.65, expand=0.4):
    x = n - min_rows + taper
    sc = (x ** expo - taper ** expo) / (expo * taper ** (expo - 1))
    return max(int(sc * expand + min_rows), min_rows)
got = window(tot0)
assert got == d0, f"formula gave {got}, log says {d0}"
print(f"\nshuffle.py:414-435 transcribed: window({tot0:,}) = {got:,} == the log's "
      f"'Desired num rows: {d0}' -- min_rows is an ADDITIVE term at every window size and "
      f"was the operative floor here, not KEEPROWS.")
print("\nOK")
PY
