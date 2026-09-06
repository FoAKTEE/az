#!/usr/bin/env python3
"""retention 60: shuffle-window, scratch and SGF projection for the link-2 -> link-3 boundary.

Read-only. Every input is either a verbatim number from logs/loop-305318.log, a measurement
of runs/p1 taken at 2026-09-06T10:30 EDT, or a constant read out of the committed files.
"""
import json, os, time

OUT = {}

# ---------------------------------------------------------------- window formula
# python/shuffle.py:414-435, transcribed verbatim; the run's arguments come from
# codes/loop/synchronous_loop_9x9.sh:506 (-min-rows 25000, -keep-target-rows 120000,
# -taper-window-scale 50000) on top of python/selfplay/shuffle.sh:43-51
# (-expand-window-per-row 0.4, -taper-window-exponent 0.65).  No -max-rows is passed
# anywhere, so max_rows is None and there is no upper clamp.
MIN_ROWS, TAPER, EXPO, EXPAND, KEEPROWS = 25000, 50000, 0.65, 0.4, 120000

def window(num_usable_rows, add_to_data_rows=0):
    off = TAPER
    x = num_usable_rows - MIN_ROWS + off + add_to_data_rows
    un = x ** EXPO - off ** EXPO
    sc = un / (EXPO * off ** (EXPO - 1))
    return max(int(sc * EXPAND + MIN_ROWS), MIN_ROWS)

CAL = [(321499, 102521), (351470, 108521), (381697, 114405), (412531, 120251),
       (443329, 125948), (2604285, 398509), (2634485, 401521), (2664932, 404546),
       (2695293, 407550)]
print("== 1. window formula calibrated against logs/loop-305318.log ==")
ok = True
for n, want in CAL:
    got = window(n)
    ok &= got == want
    print(f"   rows on disk {n:>9,} -> desired {got:>8,}   log: {want:>8,}   "
          f"{'MATCH' if got == want else 'MISMATCH'}")
print(f"   all {len(CAL)} log points reproduced: {ok}")
OUT["window_formula_calibration_all_match"] = ok
assert ok

# ---------------------------------------------------------------- measured rates
ROWS_PER_CYCLE = 30365          # mean of the last five deltas of "Total rows found"
CYCLES_LINK2 = 79               # count of "Total rows found" in loop-305318.log at 10:28
GENS_LINK2 = 30                 # accepted nets t9-s18225024 .. t9-s27212800
H_LINK2 = 16.075                # 2026-09-05T18:23:27 -> 2026-09-06T10:28
CYCLES_PER_H = CYCLES_LINK2 / H_LINK2
GENS_PER_H = GENS_LINK2 / H_LINK2
ROWS_NOW = 2695293              # last "Total rows found" at 10:28
GENS_NOW = 37
H_TO_LINK3 = (17 + 53 / 60 + 21 / 3600) - (10 + 28 / 60)     # 10:28 -> 17:53:21 EDT
print("\n== 2. rates measured over link 2 ==")
print(f"   cycles/h {CYCLES_PER_H:.3f}  ({CYCLES_LINK2} shuffles / {H_LINK2} h "
      f"= {60/CYCLES_PER_H:.2f} min per cycle)")
print(f"   generations/h {GENS_PER_H:.3f}  ({CYCLES_LINK2/GENS_LINK2:.3f} cycles per generation)")
print(f"   rows/cycle {ROWS_PER_CYCLE:,}   rows/generation {ROWS_PER_CYCLE*CYCLES_LINK2/GENS_LINK2:,.0f}")
print(f"   hours from the 10:28 measurement to link-3 start (17:53:21) = {H_TO_LINK3:.2f}")

cyc_more = round(H_TO_LINK3 * CYCLES_PER_H)
rows_at_end = ROWS_NOW + cyc_more * ROWS_PER_CYCLE
gens_at_end = GENS_NOW + round(H_TO_LINK3 * GENS_PER_H)
print(f"   projected at link-3 start: +{cyc_more} cycles, {rows_at_end:,} rows on disk, "
      f"{gens_at_end} generations")
OUT["projected_link3_start"] = {"cycles_added": cyc_more, "rows_on_disk": rows_at_end,
                                "generations": gens_at_end}

# ---------------------------------------------------------------- the boundary
print("\n== 3. the shuffle window across the link-2 -> link-3 boundary ==")
w_before = window(rows_at_end)
print(f"   LAST CYCLE OF LINK 2  rows {rows_at_end:>9,} -> window {w_before:>8,}")

# KEEP=60: the stub-tree test (scenario A) shows 0 generations deleted at 51 <= 60,
# so num_usable_rows is continuous across the boundary.
w_60 = window(rows_at_end)
print(f"   KEEP=60  0 generations deleted (51 <= 60, stub scenario A)")
print(f"            rows {rows_at_end:>9,} -> window {w_60:>8,}   step {w_60-w_before:+,}"
      f"   ({100*(w_60-w_before)/w_before:+.1f} %)")

# KEEP=3: survivors = newest 3 U {generations newer than the oldest retained shuffle
# window}.  cleanup_old_dirs.py already holds shuffleddata at "newest 3 older than 2 h",
# so the oldest retained dir is ~2 h + 2 cycles old and about 5 generations survive.
GEN_ROWS = ROWS_PER_CYCLE * CYCLES_LINK2 / GENS_LINK2
surv_lo, surv_hi = 4.5, 5.5          # 5 survivors, the newest one partial
rows3_lo, rows3_hi = int(surv_lo * GEN_ROWS), int(surv_hi * GEN_ROWS)
w3_lo, w3_hi = window(rows3_lo), window(rows3_hi)
print(f"   KEEP=3   {gens_at_end-5} of {gens_at_end} generations deleted, 5 survive "
      f"(stub scenario A: 46 of 51 deleted)")
print(f"            rows {rows3_lo:>9,}-{rows3_hi:,} -> window {w3_lo:>8,}-{w3_hi:,}"
      f"   step {w3_lo-w_before:+,} to {w3_hi-w_before:+,}"
      f"   ({100*(w3_lo-w_before)/w_before:.1f} % to {100*(w3_hi-w_before)/w_before:.1f} %)")
print(f"   link-2 boundary, for comparison (measured): 421,842 -> 109,442 rows "
      f"({100*(109442-421842)/421842:.1f} %), vloss 0.6002 -> 0.6146")
OUT["window"] = {"last_cycle_link2": w_before, "keep60_first_cycle_link3": w_60,
                 "keep3_first_cycle_link3_lo": w3_lo, "keep3_first_cycle_link3_hi": w3_hi,
                 "keep60_step": w_60 - w_before,
                 "keep3_step_lo": w3_lo - w_before, "keep3_step_hi": w3_hi - w_before}

# ---------------------------------------------------------------- what binds
print("\n== 4. which knob binds once the collapse is gone ==")
for label, w in (("last cycle of link 2", w_before), ("KEEP=60 first cycle of link 3", w_60),
                 ("KEEP=3 first cycle of link 3 (low)", w3_lo),
                 ("KEEP=3 first cycle of link 3 (high)", w3_hi)):
    keep_prob = min(1.0, KEEPROWS / w)
    binds = ("SHUFFLE_KEEPROWS binds: %d of %d rows drawn, keep_prob %.3f"
             % (min(KEEPROWS, w), w, keep_prob)) if w > KEEPROWS else \
            ("SHUFFLE_KEEPROWS DOES NOT bind: window %d < KEEPROWS %d, keep_prob 1.000 "
             "-- every row on disk is drawn every cycle" % (w, KEEPROWS))
    print(f"   {label:<38} window {w:>8,}   {binds}")
print(f"   SHUFFLE_MINROWS  {MIN_ROWS:,}: the clamp floor; the smallest window above is "
      f"{min(w3_lo, w_60):,} = {min(w3_lo, w_60)/MIN_ROWS:.1f}x it -- never binds")
print(f"   TAPER_WINDOW_SCALE {TAPER:,}: the power-law OFFSET (shuffle.py:421), not a clamp; "
      f"it shapes the curve at every window size and can never bind")
print(f"   -max-rows: not passed by shuffle.sh or synchronous_loop_9x9.sh -> max_rows=None, "
      f"no upper clamp exists")
print(f"   reuse rho = KEEPROWS/(G*r) = {KEEPROWS}/(1800*{ROWS_PER_CYCLE/1800:.2f}) = "
      f"{KEEPROWS/ROWS_PER_CYCLE:.3f} -- a function of games/cycle and rows/game only, "
      f"unchanged by retention")
OUT["binding"] = {"keeprows": KEEPROWS, "minrows": MIN_ROWS, "taper": TAPER,
                  "max_rows": None,
                  "keeprows_binds_at_keep60": w_60 > KEEPROWS,
                  "keeprows_binds_at_keep3_lo": w3_lo > KEEPROWS,
                  "rho": KEEPROWS / ROWS_PER_CYCLE}

# ---------------------------------------------------------------- scratch
print("\n== 5. scratch projection ==")
DU_ROOT = 15446626012          # scratch_guard.sh 2026-09-06T10:30:10, verbatim
SELFPLAY_NOW = 1362996266      # du -sb runs/p1/selfplay at 10:31
SHUF_NOW = 658610549           # du -sb runs/p1/shuffleddata at 10:31
GEN_B = 39150047               # mean of the 29 complete link-2 generations
GEN_TDATA_B, GEN_SGF_B = 23287955, 15836783
HARD = 536870912000
PROJ = 21474836480
print(f"   measured now: mission root {DU_ROOT:,} B ({DU_ROOT/2**30:.2f} GiB), "
      f"selfplay {SELFPLAY_NOW:,} B, shuffleddata {SHUF_NOW:,} B, {GENS_NOW} generations")
print(f"   mean COMPLETE link-2 generation: {GEN_B:,} B ({GEN_B/2**20:.1f} MiB) "
      f"= tdata {GEN_TDATA_B:,} + sgfs {GEN_SGF_B:,}")
cyc_link3 = round(23.5 * CYCLES_PER_H)
gens_link3 = round(23.5 * GENS_PER_H)
for keep, surv in (("KEEP=3", 5), ("KEEP=60", 60)):
    start = min(surv, gens_at_end)
    peak = start + gens_link3
    sp_start, sp_peak = start * GEN_B, peak * GEN_B
    root_peak = DU_ROOT - SELFPLAY_NOW + sp_peak
    print(f"   {keep:<8} link-3 start {start:>3} generations = {sp_start/2**30:>5.2f} GiB;"
          f" link-3 END {peak:>3} generations = {sp_peak/2**30:>5.2f} GiB")
    print(f"            peak mission root {root_peak:,} B = {root_peak/2**30:.2f} GiB;"
          f" guard's projected total {root_peak+PROJ:,} B = "
          f"{100*(root_peak+PROJ)/HARD:.2f} % of the 500 GiB hard cap")
    OUT.setdefault("scratch", {})[keep] = {
        "gens_link3_start": start, "gens_link3_end": peak,
        "selfplay_bytes_peak": sp_peak, "root_bytes_peak": root_peak,
        "guard_projected_total": root_peak + PROJ,
        "pct_of_hard_cap": 100 * (root_peak + PROJ) / HARD}
delta = (60 - 5) * GEN_B
print(f"   COST OF THE CHANGE: at most (60-5) x {GEN_B:,} B = {delta:,} B = "
      f"{delta/2**30:.2f} GiB extra, {100*delta/HARD:.3f} % of the 500 GiB budget")
print(f"   guard thresholds unchanged: hard cap {HARD:,} B, default projection {PROJ:,} B "
      f"(effective soft cap {(HARD-PROJ)/2**30:.0f} GiB)")
head = HARD - PROJ - (DU_ROOT - SELFPLAY_NOW + 60 * GEN_B)
print(f"   headroom under the soft cap with 60 generations retained: {head:,} B = "
      f"{head/2**30:.1f} GiB = {int(head/GEN_B):,} further generations")
print(f"   VERDICT: the guard's own cap does NOT need raising.")
OUT["scratch"]["delta_bytes"] = delta
OUT["scratch"]["headroom_bytes_at_60"] = head
OUT["scratch"]["cap_needs_raising"] = False

# ---------------------------------------------------------------- sgfs
print("\n== 6. SGF side effect (bears on o52; quantified, not decided) ==")
GAMES = [2000,5000,3000,2000,3000,2000,6243,3600,5400,3600,5400,3600,5400,3600,5400,
         3600,5400,3600,5400,3600,5400,3600,5400,3600,5400,3600,5400,3600,5400,3600,
         5400,3600,9000,5400,3600,5400,3227]
SGFB = [6885483,17163239,10316797,6853974,10296876,6872908,21268301,12506407,18737525,
        12460935,18352518,12263321,18297809,12137027,18308814,12276216,18325015,12196762,
        18563759,12306390,18267989,12242287,18433435,12288657,18479020,12190773,18085686,
        12044183,18069270,12191633,18149896,12245395,30662832,18542452,12260414,18380300,
        10929146]
assert len(GAMES) == len(SGFB) == GENS_NOW
print(f"   on disk now: {sum(GAMES):,} games in {sum(SGFB):,} B of .sgfs across "
      f"{GENS_NOW} generations ({sum(SGFB)/2**20:.0f} MiB)")
print(f"   mean per COMPLETE link-2 generation: {sum(GAMES[7:-1])/29:,.0f} games, "
      f"{GEN_SGF_B:,} B ({GEN_SGF_B/2**20:.1f} MiB); {GEN_SGF_B/(sum(GAMES[7:-1])/29):.0f} B/game")
per_game = GEN_SGF_B / (sum(GAMES[7:-1]) / 29)
gpg = sum(GAMES[7:-1]) / 29
# Exact accounting, not the link-2 mean: the 7 link-1 survivors were played at 1000
# games/cycle, the link-2 generations at 1800.  games_at_link3 = what is on disk now
# plus the games the remaining cycles of link 2 will write.
games_at_link3 = sum(GAMES) + cyc_more * 1800
sgfb_at_link3 = sum(SGFB) + cyc_more * 1800 * per_game
print(f"   at link-3 start the tree will hold {games_at_link3:,} games "
      f"({sum(GAMES):,} now + {cyc_more} cycles x 1800) in ~{sgfb_at_link3/2**20:,.0f} MiB "
      f"of .sgfs, across {gens_at_end} generations")
newest5 = GAMES[-5:]
print(f"   KEEP=3   5 generations survive: the newest five now hold {sum(newest5):,} games; "
      f"at link-3 start expect ~{5*gpg:,.0f} games, ~{5*GEN_SGF_B/2**20:.0f} MiB "
      f"({100*5*gpg/games_at_link3:.1f} % of the tree)")
print(f"   KEEP=60  all {gens_at_end} generations survive (51 <= 60): {games_at_link3:,} games, "
      f"~{sgfb_at_link3/2**20:,.0f} MiB (100 % of the tree)")
print(f"   DELTA    {games_at_link3-5*gpg:,.0f} games and ~{(sgfb_at_link3-5*GEN_SGF_B)/2**20:,.0f} MiB "
      f"of .sgfs that KEEP=3 deletes at 17:53 and KEEP=60 keeps")
prev_link_gens = gens_at_end - 7
print(f"   link 2 alone will have written ~{CYCLES_LINK2+cyc_more} cycles = "
      f"~{(CYCLES_LINK2+cyc_more)*1800:,} games in ~{prev_link_gens} generations; KEEP=60 "
      f"carries every one of them into link 3, KEEP=3 carries the newest ~5 generations")
print(f"   the deleted games are unrecoverable unless codes/data_budget/archive_sgf.sh ran "
      f"first (KTG_ARCHIVE_SGF, committed at 0; loop.sbatch:859-869 runs it BEFORE the prune)")
print(f"   NOTE for o52: KEEP=60 does not archive anything. It defers the loss by one link "
      f"(the 60th-oldest generation is deleted at the NEXT boundary) and buys ~{60/GENS_PER_H:.0f} h "
      f"of game history on disk at ~{60*GEN_SGF_B/2**20:.0f} MiB. An archive decision is still open.")
OUT["sgf"] = {"games_on_disk_now": sum(GAMES), "sgf_bytes_on_disk_now": sum(SGFB),
              "games_per_generation": gpg, "sgf_bytes_per_generation": GEN_SGF_B,
              "bytes_per_game": per_game,
              "keep3_games_surviving_link3_start": 5 * gpg,
              "keep60_games_surviving_link3_start": gens_at_end * gpg,
              "link2_games_written_estimate": round(CYCLES_LINK2 + cyc_more) * 1800}

here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, "projection.json"), "w") as fh:
    json.dump(OUT, fh, indent=2)
print(f"\nwrote {os.path.join(here, 'projection.json')}")
