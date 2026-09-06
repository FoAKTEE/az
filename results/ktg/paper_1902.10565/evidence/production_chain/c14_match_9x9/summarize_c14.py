#!/usr/bin/env python3
"""c14: win rate, Elo with a 95 % CI, and the per-colour split, from the match sgfs.

One .sgfs line is one game (match.sbatch counts them the same way). PB/PW carry the bot
names from match_first_latest_9.cfg (botName0 = the baseline, botName1 = latest) and RE[]
carries the result; a draw scores 0.5 to each side.

CI: the normal approximation the packet asks for, se = sqrt(p(1-p)/n), 95 % = p +/- 1.96 se,
then the same Elo map applied to each bound. It is quoted alongside summarize_sgfs.py's own
maximum-likelihood Elo +/- one approximate standard error, which uses a 2-game prior.
"""
import glob, json, math, os, re, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else \
    "/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/matches/2026-09-06"
ARMS = [("armA_vs_s20919936", "t9-s20919936-d1053205", "best by p0loss / pacc1, 19 exports back"),
        ("armB_vs_first", "t9-s143744-d157367", "the frozen first accepted net")]
LATEST = open(os.path.join(ROOT, "LATEST_PINNED")).read().strip()
Z = 1.959963985           # two-sided 95 %

HDR = re.compile(r"PB\[([^\]]*)\]PW\[([^\]]*)\].*?RE\[([^\]]*)\]")

def elo(p):
    if p <= 0.0: return float("-inf")
    if p >= 1.0: return float("inf")
    return -400.0 * math.log10(1.0 / p - 1.0)


_LOGC = {}


def _log_comb(n):
    if n not in _LOGC:
        _LOGC[n] = [math.lgamma(n + 1) - math.lgamma(i + 1) - math.lgamma(n - i + 1)
                    for i in range(n + 1)]
    return _LOGC[n]


def binom_cdf(k, n, q):
    """P(X <= k) for X ~ Binomial(n, q), summed in log space."""
    if q <= 0.0: return 1.0
    if q >= 1.0: return 0.0 if k < n else 1.0
    lq, l1q = math.log(q), math.log1p(-q)
    lc = _log_comb(n)
    return sum(math.exp(lc[i] + i * lq + (n - i) * l1q) for i in range(0, k + 1))


def clopper_pearson(k, n, alpha=0.05):
    """Exact two-sided 1-alpha interval for k successes of n, by bisection on the CDF.

    Quoted because the normal approximation se = sqrt(p(1-p)/n) is DEGENERATE at k = n:
    it reports se = 0 and an interval of zero width, which is not a statement about the
    true win rate. Clopper-Pearson is well defined there, with the closed-form lower bound
    (alpha/2)**(1/n) that the bisection below is checked against.

    Both bound functions are INCREASING in q and straddle 0 on (0,1), so one bisection
    routine serves both.
    """
    def bisect(f):
        lo, hi = 0.0, 1.0
        for _ in range(200):
            mid = 0.5 * (lo + hi)
            if f(mid) < 0.0: lo = mid
            else: hi = mid
        return 0.5 * (lo + hi)
    lo = 0.0 if k == 0 else bisect(lambda q: (1.0 - binom_cdf(k - 1, n, q)) - alpha / 2)
    hi = 1.0 if k == n else bisect(lambda q: alpha / 2 - binom_cdf(k, n, q))
    if k == n:      # closed form check on the degenerate case
        assert abs(lo - (alpha / 2) ** (1.0 / n)) < 1e-9, (lo, (alpha / 2) ** (1.0 / n))
    return lo, hi

out = {"latest": LATEST, "root": ROOT, "arms": {}}
for arm, base, why in ARMS:
    files = sorted(glob.glob(os.path.join(ROOT, arm, "match-*", "*.sgfs")))
    tot = {"n": 0, "w": 0.0, "wins": 0, "losses": 0, "draws": 0, "noresult": 0}
    bycol = {"B": dict(n=0, w=0.0, wins=0, losses=0, draws=0),
             "W": dict(n=0, w=0.0, wins=0, losses=0, draws=0)}
    for f in files:
        for line in open(f):
            line = line.strip()
            if not line:
                continue
            m = HDR.search(line)
            assert m, "unparsed sgf line in " + f
            pb, pw, re_ = m.group(1), m.group(2), m.group(3)
            assert {pb, pw} == {"latest", "first"}, (pb, pw)
            colour = "B" if pb == "latest" else "W"       # colour the LATEST net held
            winner = re_[0].upper() if re_ else "?"
            if winner == "0" or re_ == "" or winner == "?":
                s, tag = 0.5, "draws"
            elif winner == "B":
                s, tag = (1.0, "wins") if colour == "B" else (0.0, "losses")
            elif winner == "W":
                s, tag = (1.0, "wins") if colour == "W" else (0.0, "losses")
            else:
                s, tag = 0.5, "noresult"
            tot["n"] += 1; tot["w"] += s; tot[tag] = tot.get(tag, 0) + 1
            b = bycol[colour]
            b["n"] += 1; b["w"] += s
            b[tag if tag in b else "draws"] = b.get(tag, 0) + 1
    n, w = tot["n"], tot["w"]
    p = w / n
    se = math.sqrt(p * (1 - p) / n)
    lo, hi = max(0.0, p - Z * se), min(1.0, p + Z * se)
    # Exact interval on the DECISIVE games (draws excluded), for the k = n case where the
    # normal approximation collapses to zero width.
    dec = tot["wins"] + tot["losses"]
    cp_lo, cp_hi = clopper_pearson(tot["wins"], dec)
    rec = {"baseline": base, "why": why, "games": n, "score_for_latest": w,
           "wins": tot["wins"], "losses": tot["losses"], "draws": tot["draws"],
           "p": p, "se": se, "ci95": [lo, hi],
           "elo": elo(p), "elo_ci95": [elo(lo), elo(hi)],
           "decisive_games": dec,
           "p_decisive": tot["wins"] / dec if dec else float("nan"),
           "clopper_pearson95_decisive": [cp_lo, cp_hi],
           "elo_clopper_pearson95_decisive": [elo(cp_lo), elo(cp_hi)],
           "by_colour": {}}
    for c, lab in (("B", "latest as Black"), ("W", "latest as White")):
        b = bycol[c]
        pc = b["w"] / b["n"] if b["n"] else float("nan")
        sec = math.sqrt(pc * (1 - pc) / b["n"]) if b["n"] else float("nan")
        rec["by_colour"][lab] = {"games": b["n"], "score": b["w"], "p": pc, "se": sec,
                                 "wins": b.get("wins", 0), "losses": b.get("losses", 0),
                                 "draws": b.get("draws", 0),
                                 "ci95": [max(0.0, pc - Z * sec), min(1.0, pc + Z * sec)],
                                 "elo": elo(pc)}
    out["arms"][arm] = rec

    print(f"=== {arm}:  {LATEST}  vs  {base} ===")
    print(f"    ({why})")
    print(f"    games {n}   colour split {rec['by_colour']['latest as Black']['games']} B / "
          f"{rec['by_colour']['latest as White']['games']} W")
    print(f"    latest scores {w:g}/{n}  = p {p:.4f}   se {se:.4f}   "
          f"95 % CI [{lo:.4f}, {hi:.4f}]")
    print(f"    wins {tot['wins']}  losses {tot['losses']}  draws {tot['draws']}")
    print(f"    Elo  {elo(p):+.1f}   95 % CI [{elo(lo):+.1f}, {elo(hi):+.1f}]"
          + ("   [DEGENERATE: se = 0 at p = 1]" if se == 0.0 else ""))
    print(f"    exact (Clopper-Pearson, {tot['wins']} wins of {dec} DECISIVE games): "
          f"p [{cp_lo:.4f}, {cp_hi:.4f}]   Elo [{elo(cp_lo):+.1f}, "
          f"{('+inf' if cp_hi >= 1.0 else '%+.1f' % elo(cp_hi))}]")
    for lab in ("latest as Black", "latest as White"):
        d = rec["by_colour"][lab]
        print(f"    {lab:<16} {d['score']:g}/{d['games']} = p {d['p']:.4f} "
              f"[{d['ci95'][0]:.4f}, {d['ci95'][1]:.4f}]   Elo {d['elo']:+.1f}   "
              f"(w{d['wins']} l{d['losses']} d{d['draws']})")
    # colour effect: the score of whoever held White, summed over both bots. It cancels out
    # of the head-to-head number (each net plays 200 of each colour) and is reported only as
    # a check that the pairing really was balanced.
    bB, bW = rec["by_colour"]["latest as Black"], rec["by_colour"]["latest as White"]
    white_score = (bB["games"] - bB["score"]) + bW["score"]
    pw = white_score / n
    sew = math.sqrt(pw * (1 - pw) / n)
    rec["white_score_overall"] = white_score
    rec["p_white_overall"] = pw
    rec["p_white_ci95"] = [pw - Z * sew, pw + Z * sew]
    print(f"    colour effect    White scores {white_score:g}/{n} = {pw:.4f} "
          f"[{pw-Z*sew:.4f}, {pw+Z*sew:.4f}] at komi 7 (both bots pooled); "
          f"{'significant' if abs(pw-0.5) > Z*sew else 'not significant'}")
    print()

# the memo's decision rule, applied
pa = out["arms"]["armA_vs_s20919936"]["p"]
if pa <= 0.55:
    verdict = ("p <= 0.55: the 19-export loss stall IS a strength stall. "
               "Option (b), LR x0.5, is pre-registered for link 4.")
elif pa >= 0.60:
    verdict = ("p >= 0.60: the loss stall is NOT a strength stall. Option (b) is NOT "
               "triggered; keep running unchanged.")
else:
    verdict = "0.55 < p < 0.60: inconclusive; the memo says repeat at 800 games."
out["decision_rule"] = {"rule": "memo section 6.1 item 3 / options json recommendation."
                                "decision_rule_for_b",
                        "p_latest_vs_s20919936": pa, "verdict": verdict}
print("=== memo decision rule ===")
print(f"    p(latest vs t9-s20919936) = {pa:.4f}")
print(f"    {verdict}")

here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, "results.json"), "w") as fh:
    json.dump(out, fh, indent=2)
print(f"\nwrote {os.path.join(here, 'results.json')}")
