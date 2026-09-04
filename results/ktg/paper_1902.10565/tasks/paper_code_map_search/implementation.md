# Implementation — `paper_code_map_search`

## 0. Header

**Task ID:** `paper_code_map_search`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::selfplay_search_params`, `::playout_cap_randomization`, `::root_explore_and_target_pruning`, `::score_utility_search`, `::game_randomization_9x9`, `::gating_rule`
**Language:** C++ engine run (`katago selfplay` / `katago gatekeeper`) + Python log/npz analysis
**Method class:** simulation (executed probe promoting six read-only nodes from `preliminary` to `solid`)

## 1. Claim

> Running the mission 9x9 config for ~20 games reproduces, as measured behaviour, the search-side paper ideas the v1.18.2 code still implements: a full search on 0.25 of searched turns, ~22 training rows per game, and no board other than 9x9 (claim `c15_paper_ideas_in_code`, and the search half of `c04`/`c10`).

## 2. Success Criterion

- **Needed evidence type:** `numerical_simulation` (the nodes were read; this run is what promotes them)
- **Done when:** the probe's three assertions hold on one recorded run.
- **Verification command:**
  `bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/eval/probe_search_9x9.sh 20`
  which runs
  `$KATAGO_BIN selfplay -config codes/cfg/selfplay_9x9.cfg -models-dir $W/models -output-dir $W/selfplay -max-games-total 20 -override-config 'logSearchInfo=true,logGamesEvery=1,reduceVisits=false,normalAsymmetricPlayoutProb=0.0,handicapAsymmetricPlayoutProb=0.0,estimateLeadProb=0.0'`
  then `python codes/eval/probe_search_9x9.py $W/selfplay $W/logs` printing and asserting:
  - `full_frac  = (# "Root visits:" lines with N > 100) / (# "Root visits:" lines)`
  - `rows_per_game = (sum of npz["binaryInputNCHWPacked"].shape[0] over $W/selfplay/*/tdata/*.npz) / (# lines in $W/selfplay/*/sgfs/*.sgfs)`
  - `sz_other = (# .sgfs lines without "SZ[9]")`
- **Measured tolerance / metric:**
  (a) `full_frac` in `[0.20, 0.30]` (0.25 +- 0.05);
  (b) `rows_per_game` in `[12, 35]`;
  (c) `sz_other == 0`.
  Exit 0 only if all three hold.
- **Open obligations before start:** `o01_bsizes9_override`, `o02_databoardlen_poslen_9` (the mission cfg must exist) — i.e. task `cfg_9x9_override` must have landed.
- **Reduction-to-baseline test:** NA

**Why the overrides:** `reduceVisits=true` would taper a winning side down to `reducedVisitsMin = 100` (`selfplay1_maxsize9.cfg:64-68`, `cpp/program/play.cpp:1151-1187`), which is indistinguishable from a cheap search at the log level; the asymmetric-playout keys (`:70-73`) and `estimateLeadProb` (`:78`) likewise perturb root visits. With them off, cheap turns log exactly `Root visits: 100` (`min(maxVisits, cheapSearchVisits)`, `play.cpp:1141-1142`) and full turns log up to 600 (`:115`).

## 3. Motivation

`derivation.md` §1 rows 2, 3, 4, 8, 9, 11 are the paper ideas the code still implements; `claims.md` `c15_paper_ideas_in_code` asserts exactly that. All six nodes are currently `preliminary` — read in code, never executed (`results/ledgers/knowledge/paper_arxiv-1902.10565/nodes.jsonl`). A `solid` node requires evidence in a verifiable form (admission contract, Admission Gates), so a single cheap 20-game run is the minimum that upgrades six nodes at once.

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §1 (every sp9 search key -> paper symbol), §2 (gk9), §9 (symbol collisions) |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | §1 rows 2, 3, 4, 8, 9, 11; §4 rows/game arithmetic |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | the six nodes and their edges into `selfplay_stage` / `gatekeeper_stage` |
| implementation_plan | not produced at stage 1 | `[OPEN]` |
| ref | `results/ktg/paper_1902.10565/decomposition/ref.md` | tex line anchors l.96, l.105-109, l.649-663, l.669-678, l.689-703 |
| assumptions | `results/ktg/paper_1902.10565/decomposition/assumptions.md` | `a05_9x9_only`, `a07_moves_per_game_80`, `a09_code_first`, `a10_random_bootstrap_ok` |
| claims | `results/ktg/paper_1902.10565/decomposition/claims.md` | `c15`, `c10`, `c04` |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | `o01`, `o02`, `o16` |
| result_seed | not produced at stage 1 | `[OPEN]` |

**Upstream task outputs:** `tasks/env_build/implementation.md` (binary), `tasks/cfg_9x9_override/implementation.md` (cfg).
**Evidence packs:** `evidence/decomposition/audit_paper_code_map.md` §1, §2, §6, §7, §8; `audit_loop_scripts_configs.md` §D, §F.

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- One cluster only: search-side nodes. Training-side nodes are `paper_code_map_training`.
- Everything that promotes a node must come from the run's own logs/npz, not from re-reading the code.
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference paper | `ref-paper/arxiv-1902.10565/` |
| Reference code | `ref-code/lightvector-KataGo/` |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/eval/` |
| Plot / figure output | `results/ktg/paper_1902.10565/plots/` |
| Loop notes | `results/ktg/paper_1902.10565/loop_note/` |
| Progress dir | `progress/paper_1902.10565/paper_code_map_search/` |
| Git branch | `ssci` |
| Scratch workdir `$W` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/probe_search` |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/eval/
├── probe_search_9x9.sh    # nodes selfplay_search_params, game_randomization_9x9 - runs the 20-game selfplay with the overrides
├── probe_search_9x9.py    # nodes playout_cap_randomization, root_explore_and_target_pruning, score_utility_search - the 3 asserts
└── probe_gate_9x9.sh      # node gating_rule - config-parse leg: gatekeeper on an empty accepted-models-dir must exit 0
```

## 8. Phase Plan

### Phase 1 - `selfplay probe`
- **Nodes:** `selfplay_search_params`, `playout_cap_randomization`, `game_randomization_9x9`
- **Files:** `probe_search_9x9.sh`, `probe_search_9x9.py`
- **Test:** assertions (a), (b), (c) of §2 all pass in one run.
- **Estimate:** `1.0` h

### Phase 2 - `search-internals + gate parse`
- **Nodes:** `root_explore_and_target_pruning`, `score_utility_search`, `gating_rule`
- **Files:** `probe_search_9x9.py` (extra reporting), `probe_gate_9x9.sh`
- **Test:** the `Tree:` block printed by `logSearch` (`cpp/program/play.cpp:791`) shows root children whose visit counts follow the forced-playout floor, and no child is left with exactly 1 playout in the written policy target (`chosenMovePrune = 1`); `probe_gate_9x9.sh` exits 0 with the log naming `numGamesPerGating` 200.
- **Estimate:** `1.0` h

## 9. Quick-Win Path

1. `Phase 1` — one 1-GPU b200 job, empty `$W/models` so the random-net bootstrap runs (`cpp/dataio/loadmodel.cpp:77-80`); 20 games at 600/100 visits on 9x9 is minutes.
2. `Phase 2` — parse the same log; no second engine run needed except the gate parse leg.
3. **Smoke check:** `full_frac` printed and inside `[0.20, 0.30]`.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| `-max-games-total` | `20` | `cpp/command/selfplay.cpp:53`; enough for `full_frac` SE ~ 0.011 at ~1600 searched turns |
| `cheapSearchProb` | `0.75` | `selfplay1_maxsize9.cfg:60` -> expected `full_frac` = 1 - 0.75 = 0.25 = the paper's `p` (l.96) |
| `cheapSearchVisits` | `100` | `:61` = the paper's `n` (l.96); the log discriminator threshold |
| `cheapSearchTargetWeight` | `0.0` | `:62`; zeroes the row weight (`play.cpp:1143`), so ~75 % of turns write no row |
| `maxVisits` | `600` | `:115` = the paper's `N` (l.96) |
| `rootDesiredPerChildVisitsCoeff` | `2` | `:148` = the paper's `k` (l.105); floor `sqrt(P * totalChildWeight * coeff)` at `cpp/search/searchexplorehelpers.cpp:166-169` |
| `chosenMoveSubtract` / `chosenMovePrune` | `0` / `1` | `:141-142`; prune floor `min(1, max/64) = 1` at 600 visits (`cpp/search/searchresults.cpp:318-328`) |
| `dynamicScoreUtilityFactor` | `0.40` | `:159` = the paper's `c_score` 0.4 (l.690, l.705); denominator `0.5*sqrt(area) = 4.5` at 9x9 (`cpp/neuralnet/nninputs.cpp:56`) |
| `dynamicScoreCenterZeroWeight` / `Scale` | `0.25` / `0.50` | `:160-161`; `cpp/search/search.cpp:1160-1165` |
| `logSearchInfo` | `false` -> **`true`** | `:3`, read at `cpp/program/play.cpp:2611`; emits `Root visits: N` at `play.cpp:779` |
| `logGamesEvery` | `10` -> **`1`** | `:5`, read at `play.cpp:684` |
| `reduceVisits` | `true` -> **`false`** | `:64`; otherwise reduced turns also log 100 visits |
| `normalAsymmetricPlayoutProb` | `0.01` -> **`0.0`** | `:71` |
| `handicapAsymmetricPlayoutProb` | `0.5` -> **`0.0`** | `:70` (moot at 9x9: `playutils.cpp:10-22` gives 0 extra black) |
| `estimateLeadProb` | `0.05` -> **`0.0`** | `:78`; spends extra visits |
| `sidePositionProb` | `0.020` (unchanged) | `:58`; kept at production value because it contributes rows (`play.cpp:974-982`) |
| expected `rows_per_game` | `~22` | `(1 - 0.75)*80 + 0.02*80` with `a07_moves_per_game_80`; `derivation.md` §4 |

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| `full_frac` biased by early-game policy moves | denominator smaller than the move count; `full_frac` still ~0.25 | the metric is defined over *searched* turns only; opening moves from `initGamesWithPolicy` (`:55`) never call `logSearch` |
| Forks/hints halve `cheapSearchProb` for 6 turns | `full_frac` drifts above 0.25 | `play.cpp:1127-1129`; with `earlyForkGameProb = 0.04` (`:26`) the effect is well inside the +-0.05 band; if `full_frac > 0.30`, set `earlyForkGameProb=0,forkGameProb=0` and re-run as a second recorded row |
| Random-net games are pathologically short | `rows_per_game` below 12 because games end in a few moves | record `moves/game` alongside; if `moves/game << 80`, re-run with the first exported net and note that `a07_moves_per_game_80` is refuted for random-net play |
| 20 games too few | `full_frac` outside band with a wide CI | print the searched-turn count; require >= 500 searched turns, else raise `-max-games-total` |
| SGF count != game count | forks and side positions add `.sgfs` lines | define `games` = `.sgfs` line count (one SGF per line, `cpp/program/selfplaymanager.cpp:377-378`) and say so in the row |
| `logSearchInfo=true` floods the log | multi-GB log on scratch at 94 % usage | 20 games only; delete `$W/logs` after extracting the counts |
| gate leg cannot run 200 real games | no two servable nets exist yet (SwiGLU blocker) | the gate leg asserts only config parse + the empty-`accepted-models-dir` early return (`cpp/command/gatekeeper.cpp:399-402`); full gating stays `[OPEN]` for `gatekeeper_stage` |

## 12. Current State

- `[PRELIMINARY]` All six nodes are `preliminary` in `results/ledgers/knowledge/paper_arxiv-1902.10565/nodes.jsonl`: every constant is read at a `path:line` in `evidence/decomposition/audit_paper_code_map.md`, nothing is executed.
- `[SOLID]` The engine that will run the probe exists and passes `runtests` (`tasks/env_build/implementation.md` §12, evidence `evidence/env/smoke-298018.txt`).
- `[OPEN]` `codes/cfg/selfplay_9x9.cfg` does not exist yet — the probe cannot start until `cfg_9x9_override` lands. Needed evidence: the cfg files plus a passing `check_cfg_9x9.sh`.
- `[OPEN]` `gating_rule` cannot be promoted to `solid` by this task: acceptance behaviour needs 200 real games between two servable nets. Closes in `gatekeeper_stage` (claim `c13_gatekeeper_accepts`).
- `[OPEN]` `score_utility_search` promotion is partial: the probe confirms the parameters are live in a running search, not the arctan form. Closes with a targeted numeric check of `cpp/neuralnet/nninputs.cpp:56` (`u = c*(2/pi)*atan((x-x0)/(0.5*sqrt(area)))`) against logged root score utilities.
- `[OPEN]` `visit-caps-9x9` (`convention.md` §10): 600/100 are 19x19-derived; this probe records their 9x9 behaviour but does not justify them. Closes in `selfplay_stage` with a games/hour derivation.
- `[SOLID]` resolved history: `b5c48h3tfr` (ffng) is refused by every v1.18.2 backend (`cpp/neuralnet/cudaandrocmbackend.inc:3307-3308`, `eigenbackend.cpp:1634`, `openclbackend.cpp:2729`; job 297952 FAILED 1:0, `smoke-297952.txt`). The mission model is `b7c96h3tfrs` (job 298018 COMPLETED 0:0, `smoke-298018.txt` PASS); ledger: node `transformer_trunk_b7c96h3tfrs`, `a06`/`o07`/`c03`/`c16` amended, `o18` discharged (commit ee47dd9). Nothing in this task is blocked by it.

## 13. Forbidden Actions

- Never edit `ref-code/lightvector-KataGo/`; all overrides go through `-override-config` (`cpp/command/commandline.cpp:253`) or `codes/cfg/`.
- Never promote a node to `solid` from a code re-read; only this run's logs/npz count.
- Never leave `reduceVisits=true` in the probe and then report `full_frac` — the two visit regimes become indistinguishable.
- Never change `cheapSearchProb`, `cheapSearchVisits`, `maxVisits` or `rootDesiredPerChildVisitsCoeff` in the probe: they are the quantities being measured.
- Never exceed 24 CPUs / 1 GPU for the probe job, and never drop `--gres=gpu:1` on `b200`.
- Never count "some SGFs are 9x9": the metric is `sz_other == 0`.
- Never keep the `logSearchInfo=true` log after extraction (scratch is at 94 % group usage).

## 14. Promise Tag

- **Promise format:** `<promise>paper_code_map_search FULL_SEARCH_FRACTION WITHIN 0.25+-0.05 AND ROWS_PER_GAME WITHIN [12,35] AND SZ_OTHER ==0</promise>`
- **Required in commit body:** verbatim probe output (all three metrics plus searched-turn and game counts), evidence path under `evidence/probe_search/`, claim `c15`/`c10`/`c04`, evidence type `numerical_simulation`, and the six node ids promoted.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions:
- Per-substage commit: Phase 1 and Phase 2 commit separately, each with its passing metric.
- Joint progress file: `progress/paper_1902.10565/paper_code_map_search/progress.md`.
- Loop notes: `results/ktg/paper_1902.10565/loop_note/note_session_{id}_loop_{n}.md` before compaction.
- State-note sync: each node promoted `preliminary -> solid` is recorded with the run id in `${RESEARCH_STATE}`.

## 16. Termination Checklist

- [ ] Verification command ran and output is pasted.
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] All three metrics are within the thresholds in §2.
- [ ] Reduction-to-baseline test passed when relevant (NA).
- [ ] No `[BLOCKING]`, `[OPEN]`, or `[UNCHECKED]` markers remain for the nodes actually promoted (`gating_rule` and `score_utility_search` stay partial by design and must not be marked `solid`).
- [ ] No silent scope expansion: no training-side node touched here.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
