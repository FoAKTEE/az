# RESEARCH_STATE — ktg-train

**Mission.** Train a 9×9 transformer-trunk KataGo net end-to-end (self-play → shuffle → train → export →
gatekeeper) on the Schmidt B200/B300 cluster within the compute policy (≤4 GPUs total, ≤24 CPUs, b300 preferred /
b200 fallback, 3-day walltime). **Phase.** 1-decompose closed (two-seat DAG review reconciled 2026-09-04) → 2-work wave 1.
**Branch.** az `main` (consumer), framework submodule `ssci`. **Paper id (ledger label only).** `arxiv-1902.10565`.
**Layout.** consumer artifacts at the `az` root: `results/`, `progress/`, `ref-code/`, `ref-paper/`, `mission.json`; tools run as
`python3 phys-agentic-loop/_common/...` from `az`. **Runtime.** `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/` (venv, build, loop data, logs).

## Source Library

| ID | Source | Status | Notes |
|---|---|---|---|
| `code` | `ref-code/lightvector-KataGo/` @ v1.18.2 `fd0723fd` | `[SOLID]` | **primary source of truth** (human redirect 2026-09-03: code-first). Declarations `results/ktg/sources/code_lightvector-KataGo.md`; audits `results/ktg/paper_1902.10565/evidence/decomposition/audit_*.md` |
| `paper` | `ref-paper/arxiv-1902.10565/` | `[SOLID]` | background only; ideas still in code mapped in `decomposition/derivation.md` |
| `cluster` | `docs/cluster-manual.md` | `[SOLID]` | verified live 2026-09-03; b200 free 2/128, b300 0/8, scratch 94 % |
| `reviews` | `evidence/decomposition/dag_review_{a,b}.md` → `dag_reconciliation.md` | `[SOLID]` | seat A (38) / seat B (39) merged into the canonical 38-node DAG; every load-bearing anchor re-read in the mirror |

## Working Context

| Name | Meaning | Regime / assumptions |
|---|---|---|
| source priority | v1.18.2 code decides nodes, claims, plans; paper cited only where the code still implements the idea (playout cap randomization, root forced visits + target pruning, aux targets, score utility, gating) | `[ASSUMPTION] a09` |
| board | 9×9 only: `bSizes=9`, `bSizeRelProbs=1`, `allowRectangleProb=0`, `dataBoardLen=9`, `train.py -pos-len 9` — the last two together (`data_processing_pytorch.py:91`, asserts in *training*); upstream presets are 7–9 with rectangles, `dataBoardLen=19`, `train.sh:88 -pos-len 19` | `[ASSUMPTION] a05`; leaving both at 19 silently costs ~20× attention FLOPs |
| trunk | **`b7c96h3tfrs`** (7 × attnrope+ffnsg, 96 ch, 825 837 params) start; ladder b8c96h3tfrs → b14c192h6tfrs as fresh runs (`train.py:850`). `b5c48h3tfr` (ffng) unservable — every backend throws "Non-SwiGLU transformer FFN is not yet supported" (node `engine_ffn_swiglu_constraint`, **solid**) | `[SOLID]`; node `select_transformer_ladder`; nbt family `[FUTURE]` |
| loop | mission copy of `synchronous_loop.sh` (copies `cpp/build/katago`, 9x9 cfgs); exporter `export_model_pytorch.py`; USEGATING=1 throughout; cycle 1 gates the first candidate **against the random baseline** (`loadmodel.cpp:77-93`, `setup.cpp:126`) — not skipped; first dir in `models/` = frozen baseline | threads: selfplay 18 / gatekeeper **18** game threads (data-write thread counted → 22 each), shuffle 8, OMP 4; ≤24 OS threads per stage; 1 GPU |
| knobs | derived after the smoke from measured rows/game (`derive_cycle_knobs_9x9`): games × rows/game × reuse ≥ 0.99 × samples/epoch (`train.py:1256-1259,1433-1445`), KEEPROWS > train cap, `-epochs-per-export N` → one candidate/cycle. Pilot hypothesis: 500 games, reuse 8, 20 k samples/epoch, MINROWS 10 k, KEEPROWS 300 k, cap 200 k | `[PRELIMINARY]`; obligation `o24` blocking before P1 |
| scratch | 200 GiB cap on the whole mission root, no new cycle at ≥ 180 GiB, group quota check, bounded logged retention | `[PRELIMINARY]` `o04`, `c11` |
| build | CUDA backend, cuDNN 9.19 wheel; `cmake-sm100.diff` applied (sm_100 SASS count 2); result row `env-toolchain-b200` (empirical); node `env_build` **solid**; no TCMalloc (`o20`) | `c01`, `c02` admitted; `o05`, `o12` open |
| loss / optimizer | code weights (policy 0.93, value 0.72, ownership 1.5/b², …), SGD m=0.9 + Lookahead, lr 3e-5 base; warm-up reaches 1.0 only past 2 M samples | `[SOLID]` `derivation.md` §2 |

## Active Claims (ledger `results/ledgers/claim/paper_arxiv-1902.10565/`, 51 entries: 16 claims (2 admitted) / 24 obligations (6 discharged) / 11 assumptions)

| Claim | Needed evidence | Priority |
|---|---|---|
| c01/c02 env_build runs; sm_100 SASS | numerical_simulation | **admitted** (result `env-toolchain-b200`) |
| c03 b7 export loads (+ b5 negative fixture o23); c04 all SGFs SZ[9]; c05 pos_len-9 shuffle+train epoch | numerical_simulation | wave 1 |
| c06 threads ≤ 24 (gatekeeper 18); c07 one loop cycle + audit; c08 kill/resume (`verify_preemption_resume`) | empirical / numerical | wave 1–2 |
| c09/c10 rates, rows/game ∈ [12,35]; c11 mission root ≤ 200 GiB | empirical_measurement | wave 2 (`measure_stage_throughput`) |
| c13 ≥ 1 acceptance (target 2); c14 400-game CI excludes 0.5 (target p ≥ 0.60) | empirical / statistical_inference | P1 exit |
| c15 paper ideas present in code | literature_grounding | probes `paper_code_map_*` promote 15 code-map nodes |

## Accepted Results Log

<!-- GENERATED block — regenerate with: python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565 -->
- `env-toolchain-b200` (empirical, verifier pass, job 298018): KataGo v1.18.2 CUDA + torch 2.11.0+cu128 on B200; sm_100 SASS; b7c96h3tfrs benchmark/gtp/torch fwd-bwd at 9x9.

## Next Work Steps

- `[SOLID] decompose + two-seat reconciliation` — DONE 2026-09-04: 38 canonical nodes (2 solid: `env_build`, `engine_ffn_swiglu_constraint`; 14 preliminary code-map; 21 hypothesis; 1 future), every node with predecessors + verification (16 executed at append, 22 carry `closing_check`), `transformer_trunk_b5c48h3tfr` retired (amended); 25 claim-ledger rows appended; `duplicates` = `[]`; framework fix: a latest `amended` row now retires a node (submodule `ssci`).
  Adjudication: `evidence/decomposition/dag_reconciliation.md`; DAG `decomposition/logic.md`, `results/ktg/GLOBAL_DAG.md`; design `DESIGN.md` revised in place.
- **READY frontier (all predecessors solid/preliminary), task files current:**
  1. `[OPEN] cfg_9x9_override` — `codes/cfg/{selfplay,gatekeeper}_9x9.cfg` + `codes/loop/train_9x9.sh`; check `codes/eval/check_cfg_9x9.sh` (key-diff whitelist, 1-game run all `SZ[9]`, gatekeeper `numGameThreads = 18`).
  2. `[OPEN] tiny_model_export_smoke` — b7 export → block histogram {7,7} → `benchmarknn -require-exact-nnlen -json` + gtp on CUDA; b5 negative fixture (o23). Independent of 1.
  3. `[OPEN] loop_resume_under_walltime` — `codes/loop/loop.sbatch` + `synchronous_loop_9x9.sh` + reordered exporter (static checks: `bash -n`, afterany, failcount, `cpp/build/katago`, `check.sh --gpus 1 --cpus 24`).
  4. `[OPEN] data_budget` — 180/200 GiB guard + quota in the wrapper (`grep 193273528320 loop.sbatch`; `du -sb $KTG ≤ 214748364800`).
  Probe tasks (promote code-map nodes): `paper_code_map_search`, `paper_code_map_training` (need 1 + the binary).
- `[OPEN] next after the frontier` — `synchronous_loop_smoke` (20 games, 1 cycle, audit, rows/game) → `derive_cycle_knobs_9x9` (o24), `verify_preemption_resume` (c08), `loop_failure_circuit_breaker` → P1 five stages + `bootstrap_accepted_model` → `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first` → `eval_improvement` → `scale_data_window` → `scale_search_budget` → `scale_up`.
- `[BLOCKING]` before P1: `o01`, `o02`, `o03` (cfg), `o04` (scratch), `o13`, `o17` (loop copy), `o24` (knobs) — all owned by the frontier / smoke workers.
- `[OPEN]` non-blocking: `o05` cuDNN SDPA compile flag, `o12` requirements.txt, `o19` random-baseline gate observed in the smoke log, `o20` TCMalloc RSS, `o21` `-exclude-qvalues`, `o22` CPU-policy scope (human), `o23` b5 negative fixture; `[FUTURE]` `async_multi_gpu_layout`, nbt family, external 9x9 reference net.

## Open Questions (human)

- Is the 20 % CPU policy per job or summed over my concurrent jobs? Design assumes summed (assumption `a11`, one job at a time) — `DESIGN.md` §1 `[HOLE]`, obligation `o22`.
- b300 reserved until 2026-09-04 15:00 → running on b200 at 1 GPU (default yes).
- Scratch at 94 %: mission cap 200 GiB on the whole mission root; group-level cleanup is outside this mission.

## Audit references

Ledgers `results/ledgers/{error,knowledge,claim,result}/paper_arxiv-1902.10565/` · DAG `results/ktg/paper_1902.10565/decomposition/logic.md`,
`results/ktg/GLOBAL_DAG.md` · reconciliation `evidence/decomposition/dag_reconciliation.md` · design `decomposition/DESIGN.md` ·
digest `progress/ktg-train/HUMAN_DIGEST.md` · commit grammar `phys-agentic-loop/_common/contracts/commit_template.md`.
