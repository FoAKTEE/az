# c14 — the 400-game matches that separate "the loss stalled" from "the net stopped improving"

Memo option (h). Job **317503**, `COMPLETED 0:0`, 1 GPU on `b200`/`gb203`, elapsed **00:06:51**,
2026-09-06 10:37:53 → 10:44:44 EDT. Nothing under `runs/p1` was written; the chain (305318
RUNNING, 314831 PENDING) was not touched or signalled.

---

## The answer

| | latest vs **t9-s20919936-d1053205** (best by loss, 19 exports back) | latest vs **t9-s143744-d157367** (first accepted net) |
|---|---|---|
| games | 400 (200 B / 200 W) | 400 (200 B / 200 W) |
| latest scores | **296.5 / 400** — 282 W, 89 L, 29 D | **400 / 400** — 400 W, 0 L, 0 D |
| win rate `p` | **0.7412** | **1.0000** |
| 95 % CI, `se = sqrt(p(1-p)/n)` | **[0.6983, 0.7842]** | degenerate (`se = 0`) |
| exact 95 % CI (Clopper-Pearson, decisive games) | [0.7133, 0.8027] | **[0.9908, 1.0000]** |
| Elo | **+182.8** | **> +813** |
| Elo 95 % CI | **[+145.8, +224.1]** | [+813.3, ∞) |
| `summarize_sgfs.py` ML Elo (2-game prior) | +91.13 ± 19.76 each side, gap **182.3** | (see `summarize_sgfs_armB.txt`) |

**Decision rule (memo §6.1 item 3): `p(latest vs s20919936) = 0.7412 ≥ 0.60`.
The 19-export loss stall is NOT a strength stall. Option (b), LR ×0.5, is NOT triggered
for link 4.**

The latest net is **+183 Elo** over the net that still holds the run's best `p0loss`
(1.485115) and best `pacc1` (0.544882). Those two loss metrics have been flat-to-worse for
19 exports and ~6 M samples while head-to-head strength moved by nearly two hundred Elo.
`p0loss` / `pacc1` are therefore not measuring what the run is producing, and the gate's
accept-by-match record is the signal that tracks strength.

## Per-colour split

| | latest as Black | latest as White |
|---|---|---|
| **vs s20919936** | 135/200 = 0.6750 [0.6101, 0.7399], Elo +127.0 (w129 l59 d12) | 161.5/200 = 0.8075 [0.7529, 0.8621], Elo +249.1 (w153 l30 d17) |
| **vs first net** | 200/200 = 1.0000 (w200 l0 d0) | 200/200 = 1.0000 (w200 l0 d0) |

Colour effect, both bots pooled, at the fixed komi 7: White scores **226.5/400 = 0.5663
[0.5177, 0.6148]** in the s20919936 arm — a real White edge at this komi, significant at
95 %. It cancels out of the head-to-head number because each net plays exactly 200 games of
each colour (`match.cpp:99-110` emplaces both orderings with `numBots = 2` and no
`secondaryBots`/`includeBots`; the 200/200 split is measured, not assumed). In the first-net
arm the strength gap saturates both colours and no colour effect is visible.

## What ran

`c14_match.sbatch` is a **driver only**. Each arm is `codes/eval/match.sbatch` run unmodified
as a bash script, with the two environment variables it already documents:

```
arm A   BASEDIR=<snapshot>  EVALDIR=<matches>/2026-09-06/armA_vs_s20919936  NUM_GAMES=400
arm B   BASEDIR=<snapshot>  EVALDIR=<matches>/2026-09-06/armB_vs_first      NUM_GAMES=400
```

so `codes/cfg/match_first_latest_9.cfg`, the model-path resolution and the refusal checks
that ran are the audited ones. `codes/eval/match.sbatch` and the cfg were **not edited**.

**Board size and rules.** `bSizes = 9`, `bSizeRelProbs = 1`, `allowRectangleProb = 0`; the
job's own check reported `sgf lines written: 400 (not SZ[9]: 0)` for each arm. The rule
block is character-identical to `codes/cfg/selfplay_9x9.cfg:101-109` —
`koRules SIMPLE,POSITIONAL,SITUATIONAL`, `scoringRules AREA,TERRITORY`,
`taxRules NONE,NONE,SEKI,SEKI,ALL`, `multiStoneSuicideLegals false,true`,
`hasButtons false,false,true`, `maxMovesPerGame 1600`,
`drawEquivalentWinsForWhite 0.5`, `noResultUtilityForWhite 0.0`.
Three things differ **by design**, each documented at `match_first_latest_9.cfg:22-30`:
komi is fixed (`komiAuto false`, `komiMean 7`) where selfplay uses `komiAuto True` with
`komiStdev 1.0`, so the two nets cannot be compared at komi they each chose;
`handicapProb 0.0` against selfplay's 0.10; and `maxVisits 150` — the **gatekeeper's** visit
count (`gatekeeper_9x9.cfg:66`), not selfplay's 600, so the match measures the same search
the gate ran.

**Both nets pinned by content.** `runs/p1/models` gains a net roughly every 32 min, so
`match.sbatch`'s "largest s in `BASEDIR/models`" would not resolve to the same net in both
arms. `BASEDIR` is therefore a frozen snapshot taken on the login node at 10:23 EDT holding
exactly the three nets under test, each verified byte-identical to its source by sha256:

```
t9-s27212800-d2664932   d207dfb02769ac75a42b590ee0373f24ab6b4d8018b3e434ffad639b5b014626   (latest)
t9-s20919936-d1053205   c58932380ae6a188b52513c6ab06569d932d0d8ac9da5037b7ab6030a4e001f0   (arm A baseline)
t9-s143744-d157367      859c58d6785e5efdc3c40fb24400e3f5f56afca247009d2f1e94d35a8b4ac5d8   (arm B baseline)
```

The job log re-verified each baseline hash against its manifest before starting
(`job-317503.out:11, :250`). Arm B's manifest is the one `codes/eval/freeze_baseline.py`
writes over that snapshot — its `first_model` and `first_model_sha256` were cross-checked
against an independent `freeze_baseline.py --eval-dir` run and agree. Arm A's manifest is
the same schema with the baseline pinned to the best-by-loss net instead, which is the
comparison the memo's rule is written against; `freeze_baseline.py`'s smallest-`s` rule does
not apply to it and the manifest says so.

**The latest net.** `t9-s27212800-d2664932`, accepted 10:11 EDT, one export newer than the
`t9-s26913152-d2573793` the memo names.

## Compute policy

`policy_check.txt` — `bash .claude/skills/compute-budget/check.sh --gpus 1 --cpus 32
--partition b200,l40s` exited 0 before submission:
`my jobs: gpus=1 cpus=64 (2 jobs incl. 1 dependency-pending, not counted)` … `OK: request
gpus=1 cpus=32 part=b200,l40s within policy (gpu<=4, no cpu cap)`. Footprint during the run:
1 running chain link + 1 dependency-pending link + this 1 GPU job = **3 of the cap of 4**.
Both arms ran sequentially on the one GPU for exactly that reason.

## Files

| file | what |
|---|---|
| `results.txt` / `results.json` | the numbers above, from `summarize_c14.py` |
| `summarize_c14.py` | parses the sgfs; normal-approximation CI plus an exact Clopper-Pearson interval (checked against the closed form `(α/2)^(1/n)` at `k = n`) |
| `summarize_sgfs_armA.txt` / `_armB.txt` | upstream `python/summarize_sgfs.py`, unmodified |
| `c14_match.sbatch` | the driver actually submitted |
| `job-317503.out` / `.err` | the job's own log; `.err` is empty |
| `policy_check.txt` | the compute-budget check and the queue state at submission |
| `sgfs_manifest.txt` | sha256, game count and size of all 36 `.sgfs` files |
| `sgfs/` | the raw records — **on disk, deliberately not committed** (`.gitignore` here), per `mission.json gitPolicy.neverCommit`. Also at `/scratch/.../runtime/matches/2026-09-06/<arm>/match-317503/`. |

## Open

- `[OPEN]` Arm B is saturated at 400/400: it bounds the improvement from the first accepted
  net at `> +813` Elo but cannot measure it. Closing evidence would be a ladder against an
  intermediate net (e.g. `t9-s1762560`, the `vloss` minimum), not more games against
  `t9-s143744`.
- `[OPEN]` This is one measurement at 150 visits. Whether the +183 Elo survives at selfplay's
  600 visits is untested; the memo deliberately chose the gate's visit count so the number is
  comparable with the gate's own record.
- `[OPEN]` The result invites, but does not settle, the question the memo's option (f) raises:
  if `p0loss`/`pacc1` are 19 exports stale while strength moves +183 Elo, the plateau rule
  should be written against a match, not against the loss metrics.
