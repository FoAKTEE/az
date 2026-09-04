# Implementation — `cfg_9x9_override`

## 0. Header

**Task ID:** `cfg_9x9_override`
**Paper:** `arxiv-1902.10565` — "Accelerating Self-Play Learning in Go" (code-first: `ref-code/lightvector-KataGo/` @ `v1.18.2`)
**Logic-graph nodes covered:** `arxiv-1902.10565::cfg_9x9_override`
**Language:** KataGo cfg (key = value) + bash checker
**Method class:** simulation (config authoring verified by an executed parse run)

## 1. Claim

> Mission-owned `selfplay_9x9.cfg` / `gatekeeper_9x9.cfg`, derived from the `*_maxsize9` presets by changing only the board-size, row-size and thread keys, make `katago selfplay` produce exclusively `SZ[9]` games within the 24-CPU cap (claims `c04_9x9_only_games`, `c06_threads_le_24`, part of `c05_pos_len_9_pipeline`).

## 2. Success Criterion

- **Needed evidence type:** `numerical_simulation`
- **Done when:** the key-diff against the upstream preset touches only the allowed keys **and** a 1-game parse run writes an `.sgfs` whose every line carries `SZ[9]`.
- **Verification command:**
  `bash /home/schmidt/ssci-haiyangw/az/results/ktg/paper_1902.10565/codes/eval/check_cfg_9x9.sh`
  which must (exit 0 only if all four hold):
  1. `diff <(grep -vE '^[[:space:]]*(#|$)' ref-code/lightvector-KataGo/cpp/configs/training/selfplay1_maxsize9.cfg) <(grep -vE '^[[:space:]]*(#|$)' codes/cfg/selfplay_9x9.cfg)` — every differing line's key is in `{dataBoardLen, numGameThreads, bSizes, bSizeRelProbs, allowRectangleProb, numNNServerThreadsPerModel, cudaDeviceToUse}`;
  2. same for `gatekeeper1_maxsize9.cfg` vs `codes/cfg/gatekeeper_9x9.cfg`, allowed key set `{numGameThreads, bSizes, bSizeRelProbs, allowRectangleProb, numNNServerThreadsPerModel, cudaDeviceToUse}`;
  3. `$KATAGO_BIN selfplay -config codes/cfg/selfplay_9x9.cfg -models-dir $W/models -output-dir $W/selfplay -max-games-total 1` exits 0;
  4. `n_all=$(cat $W/selfplay/*/sgfs/*.sgfs | wc -l)`, `n9=$(cat $W/selfplay/*/sgfs/*.sgfs | grep -c 'SZ\[9\]')`, assert `n9 -eq n_all` and `n_all -ge 1`.
- **Measured tolerance / metric:** diff touches **only** the listed keys (count of out-of-set changed keys `== 0`); `n9 == n_all` (fraction 1.000, no tolerance band); `ps -o nlwp` on the live selfplay PID `<= 24`.
- **Open obligations before start:** `o01_bsizes9_override`, `o02_databoardlen_poslen_9`, `o03_thread_budget_24cpu`.
- **Reduction-to-baseline test:** NA

One SGF is written per line (`cpp/program/selfplaymanager.cpp:377-378`), and `SZ[` is emitted at `cpp/dataio/sgf.cpp:2013` (square) / `:2015` (rectangular, `SZ[x:y]`) — so a rectangular board would fail the `SZ[9]` count, which is exactly the intent of `allowRectangleProb = 0`.

## 3. Motivation

`decomposition/convention.md` §10 lists the 9x9 substitutions; `derivation.md` row 10 marks board-size mixing as the one paper idea the mission **replaces**. Upstream has no 9-only preset and the mirror is read-only (kernel §4), so the configs must be mission-owned. Leaving `dataBoardLen = 19` is the highest-severity silent misconfiguration in the audit: a 361-token model trained on 81 real tokens, ~20x attention FLOPs (`audit_paper_code_map.md` §10, divergence summary "HIGH").

## 4. Inputs From Decomposition

| Artifact | Path | Required content |
|---|---|---|
| convention | `results/ktg/paper_1902.10565/decomposition/convention.md` | §1 sp9 keys, §2 gk9 keys, §10 substitutions |
| derivation | `results/ktg/paper_1902.10565/decomposition/derivation.md` | rows 9, 10, 11 (randomization, board mixing, gating) |
| logic | `results/ktg/paper_1902.10565/decomposition/logic.md` | `cfg_9x9_override` predecessors: `selfplay_search_params`, `game_randomization_9x9`, `gating_rule`, `data_format_pos_len` |
| implementation_plan | not produced at stage 1 | `[OPEN]` |
| ref | `results/ktg/paper_1902.10565/decomposition/ref.md` | v1.18.2 provenance |
| assumptions | `results/ktg/paper_1902.10565/decomposition/assumptions.md` | `a05_9x9_only`, `a02_gpu_cap_start_at_1` |
| claims | `results/ktg/paper_1902.10565/decomposition/claims.md` | `c04`, `c05`, `c06` |
| obligations | `results/ktg/paper_1902.10565/decomposition/obligations.md` | `o01`, `o02`, `o03` |
| result_seed | not produced at stage 1 | `[OPEN]` |

**Upstream task outputs:** `tasks/env_build/implementation.md` (a working `$KATAGO_BIN` is needed for check 3-4).
**Evidence pack:** `evidence/decomposition/audit_loop_scripts_configs.md` §D (full preset key table), §E (selfplay CLI, model discovery), §F (row bytes).

## 5. Execution Rules

- Read `alignment.md` and `_common/contracts/research_admission_contract.md` before work.
- Copy the preset, change only the keys in §10, keep comments and ordering — the checker is a line diff.
- No scope creep into `synchronous_loop.sh` or `train.sh` (those belong to `loop_resume_under_walltime` / `train_stage`).
- 3 iterations / 30 min stuck -> `pipelines/0-acquire/spec.md`.

## 6. Files And Links

| Slot | Path / URL |
|---|---|
| Reference paper | `ref-paper/arxiv-1902.10565/` |
| Reference code | `ref-code/lightvector-KataGo/` |
| Decomposition outputs | `results/ktg/paper_1902.10565/decomposition/` |
| Code output | `results/ktg/paper_1902.10565/codes/cfg/`, `codes/eval/` |
| Plot / figure output | `results/ktg/paper_1902.10565/plots/` |
| Loop notes | `results/ktg/paper_1902.10565/loop_note/` |
| Progress dir | `progress/paper_1902.10565/cfg_9x9_override/` |
| Git branch | `ssci` |
| Scratch workdir `$W` | `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/cfgcheck` |

## 7. Architecture

```text
results/ktg/paper_1902.10565/codes/
├── cfg/selfplay_9x9.cfg      # node cfg_9x9_override - selfplay1_maxsize9.cfg + the 5 changed keys
├── cfg/gatekeeper_9x9.cfg    # node cfg_9x9_override - gatekeeper1_maxsize9.cfg + the 4 changed keys
└── eval/check_cfg_9x9.sh     # node cfg_9x9_override - the 4 asserts of §2; exits non-zero on any failure
```

## 8. Phase Plan

### Phase 1 - `author`
- **Nodes:** `cfg_9x9_override`
- **Files:** `codes/cfg/selfplay_9x9.cfg`, `codes/cfg/gatekeeper_9x9.cfg`
- **Test:** checks 1-2 of §2 (key-diff) pass; no out-of-set key changed.
- **Estimate:** `0.5` h

### Phase 2 - `parse + SZ proof`
- **Nodes:** `cfg_9x9_override`
- **Files:** `codes/eval/check_cfg_9x9.sh`
- **Test:** checks 3-4 of §2; `ps -o nlwp` on the selfplay PID `<= 24`.
- **Estimate:** `0.5` h

## 9. Quick-Win Path

1. `Phase 1` — `cp` the two presets into `codes/cfg/`, apply the §10 key edits.
2. `Phase 2` — run `check_cfg_9x9.sh` inside a 1-GPU b200 job (empty `$W/models` -> the random-net bootstrap, `cpp/dataio/loadmodel.cpp:77-80`, so no model is needed and the SwiGLU blocker of `env_build` is not hit).
3. **Smoke check:** at least one `.sgfs` line, and every line matches `SZ[9]`.

## 10. First Test Parameters

| Parameter | Value | Notes / source line |
|---|---|---|
| `dataBoardLen` (selfplay) | `19` -> **`9`** | `cpp/configs/training/selfplay1_maxsize9.cfg:16`; read at `cpp/command/selfplay.cpp:97`, becomes `dataXLen`/`dataYLen` at `:220`; must equal `-pos-len` (`data_processing_pytorch.py:91`) |
| `bSizes` (selfplay / gate) | `7,8,9` -> **`9`** | `selfplay1_maxsize9.cfg:95` / `gatekeeper1_maxsize9.cfg:38`; `a05_9x9_only` |
| `bSizeRelProbs` | `1,1,8` -> **`1`** | `:96` / `:39`; arity must match `bSizes` |
| `allowRectangleProb` | `0.50` -> **`0`** | `:97` / `:40`; otherwise half the games are non-square |
| `numGameThreads` (selfplay) | `128` -> **`18`** | `:84`; 18 game + 1 NN-server + 1 dataWrite + 1 modelLoad + 1 main = 22 (+2 transient during a net switch) — audit §D thread table, `o03` |
| `numGameThreads` (gate) | `128` -> **`20`** | `gatekeeper1_maxsize9.cfg:18`; 20 + 2 models + 1 main = 23 |
| `numSearchThreads` | `1` (unchanged) | `selfplay1_maxsize9.cfg:116`, `gatekeeper1_maxsize9.cfg:50`; search spawns `numThreads-1` (`searchmultithreadhelpers.cpp:40,50-52`) |
| `numNNServerThreadsPerModel` | `1` (unchanged) | `:123` / `:57`; 1 GPU to start (`a02_gpu_cap_start_at_1`) |
| `cudaDeviceToUse` | left commented **or** `0` | `:127` / `:61`; only set when the loop pins stages to different GPUs |
| `maxVisits` (selfplay) | `600` (unchanged) | `:115` = the paper's `N` (l.96); `[OPEN] visit-caps-9x9` in `convention.md` §10 |
| `cheapSearchProb / Visits / TargetWeight` | `0.75 / 100 / 0.0` (unchanged) | `:60-62` = the paper's `p=0.25`, `n=100` (l.96) |
| `maxVisits` (gate) | `150` (unchanged) | `gatekeeper1_maxsize9.cfg:49` |
| `numGamesPerGating` | `200` (unchanged) | `gatekeeper1_maxsize9.cfg:20`; `USEGATING=1` per `o16` |
| `chosenMoveTemperatureHalflife` | `19` (**unchanged**) | `:139` / `:73` — correct as-is: `cpp/search/searchhelpers.cpp:541-545` multiplies by `19/sqrt(area)`, giving a 9-turn halflife at 9x9 |
| `handicapProb` | `0.10` (**unchanged**) | `:105`; `cpp/program/playutils.cpp:10-22` returns 0 extra black for `sqrt(area) <= 10`, so handicap is already off at 9x9 and the key is a no-op. `convention.md` §10 proposes `0.0`; deferred `[FUTURE]` because it is outside the allowed changed-key set |
| `-max-games-total` | `1` | `cpp/command/selfplay.cpp:53`; parse/SZ proof only |

## 11. Risk Mitigation

| Risk | Likely signature | Mitigation |
|---|---|---|
| `bSizes`/`bSizeRelProbs` arity mismatch | `katago selfplay` throws at config parse, exit != 0 before any game | check 3 catches it; both keys edited in the same commit |
| `dataBoardLen` left at 19 (silent) | no error at selfplay time; later `assert binaryInputNCHW.shape[2] == ((pos_len*pos_len+7)//8)*8` fires at `data_processing_pytorch.py:91` — or, worse, `-pos-len 19` also stays and nothing fires | grep-assert `dataBoardLen = 9` in check 1; `o02` couples it to `-pos-len 9` in the same wrapper |
| Rectangular boards leak in | `.sgfs` lines with `SZ[9:7]` (`sgf.cpp:2015`) -> `n9 < n_all` | check 4 compares counts, not just presence |
| Thread budget exceeded | `ps -o nlwp <pid>` > 24 while selfplay runs | measure in Phase 2 and record; drop `numGameThreads` if needed |
| Preset drift (edited the wrong file) | key-diff shows unexpected keys, e.g. `komiStdev` | check 1/2 fail on any out-of-set key |
| Empty `models/` misread as an error | selfplay logs `modelName "random"`, writes to `selfplay/random/` | expected: `cpp/dataio/loadmodel.cpp:77-80`, `a10_random_bootstrap_ok` |

## 12. Current State

- `[SOLID]` The upstream presets and every key/line above were read from the read-only mirror; the full key table is in `evidence/decomposition/audit_loop_scripts_configs.md` §D.
- `[SOLID]` `selfplay1_maxsize9.cfg` differs from `selfplay1.cfg` only at `:95-97`, and the gatekeeper pair only at `:38-40` (audit §D header) — so the `maxsize9` presets are the right base.
- `[PRELIMINARY]` The five/four changed keys are derived from code constants and the 24-CPU cap but nothing is executed: `codes/cfg/` does not exist yet (`ls results/ktg/paper_1902.10565/codes/` = `env` only).
- `[OPEN]` `o01_bsizes9_override` — closes when both cfg files exist and checks 1-2 pass.
- `[OPEN]` `o02_databoardlen_poslen_9` — half of it lands here (`dataBoardLen = 9`); the `-pos-len 9` half belongs to the mission train wrapper (upstream `python/selfplay/train.sh:88` hard-codes 19). Closes only when both are set in the same commit and pos_len-19 data is discarded before the first shuffle.
- `[OPEN]` `o03_thread_budget_24cpu` — closes with a recorded `ps -o nlwp` measurement, not with the arithmetic above.
- `[OPEN]` `visit-caps-9x9` and `gate-visits-9x9` (`convention.md` §10): 600/100/150 are 19x19-derived. Closes when the mission records chosen values with a 9x9 games-per-hour derivation (task `selfplay_stage`).
- `[BLOCKING]` The SwiGLU engine refusal recorded in `tasks/env_build/implementation.md` §12 does not affect checks 1-4 (random-net bootstrap), but it blocks any cfg check that loads a real `b5c48h3tfr` net. Unblocks with the model-family decision owned by the brain.

## 13. Forbidden Actions

- Never edit `ref-code/lightvector-KataGo/cpp/configs/training/*.cfg`; author copies under `codes/cfg/` only.
- Never set `dataBoardLen` and `-pos-len` independently or in separate commits — they are one obligation (`o02`).
- Never change `chosenMoveTemperatureHalflife` to 9: `searchhelpers.cpp:541-545` already rescales by `19/sqrt(area)`.
- Never raise `numGameThreads` above 18 (selfplay) / 20 (gatekeeper) or `numSearchThreads` above 1 while the job holds 24 CPUs.
- Never uncomment more than one `cudaDeviceToUse*` family without a matching `--gres` increase (<= 4 GPUs total).
- Never add keys that do not exist in v1.18.2 (there is no `forcedPlayouts` key; the mechanism is `rootDesiredPerChildVisitsCoeff`, `cpp/program/setup.cpp:645-647`).
- Never accept "some SGFs are SZ[9]" — the metric is `n9 == n_all`.

## 14. Promise Tag

- **Promise format:** `<promise>cfg_9x9_override SZ9_FRACTION WITHIN ==1.000 AND OUT_OF_SET_KEYS ==0</promise>`
- **Required in commit body:** verbatim `check_cfg_9x9.sh` output, the two diffs, `n9`/`n_all`, the `ps -o nlwp` value, claim `c04`/`c06`, evidence path under `evidence/cfg/`.

## 15. Progress Update Principles

Inherits `../../_common/contracts/progress_principles.md`. Additions:
- Per-substage commit: one for the two cfg files, one for the checker + its passing output.
- Joint progress file: `progress/paper_1902.10565/cfg_9x9_override/progress.md`.
- Loop notes: `results/ktg/paper_1902.10565/loop_note/note_session_{id}_loop_{n}.md` before compaction.
- State-note sync: record `o01`/`o02`/`o03` transitions in `${RESEARCH_STATE}`.

## 16. Termination Checklist

- [ ] Verification command ran and output is pasted.
- [ ] Result-log delta records claim, evidence type, evidence, dependencies, assumptions, status, open obligations.
- [ ] Metric is within the threshold in §2 (`n9 == n_all`, out-of-set keys 0).
- [ ] Reduction-to-baseline test passed when relevant (NA).
- [ ] No `[BLOCKING]`, `[OPEN]`, or `[UNCHECKED]` markers remain for this checked claim.
- [ ] No silent scope expansion: only `codes/cfg/*.cfg` and `codes/eval/check_cfg_9x9.sh` are produced.
- [ ] Contributing sub-agents had `alignment.md` plus `_common/contracts/research_admission_contract.md` injected.
