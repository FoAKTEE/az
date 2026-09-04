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
| scratch | budget raised 200→**500 GiB** by human decision (see below); group quota check, bounded logged retention unchanged | `[PRELIMINARY]` `o04`, `c11`; `[OPEN]` propagation, see Human decisions |
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

<!-- Pointer to the GENERATED block: python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565 -->
<!-- Re-run this wave (2026-09-03): output unchanged, still the single admitted row below; full BEGIN/END-marker table (2315 B)
     would push this file over the 10240 B cap, so only the pointer form is kept here — the full row lives in
     progress/ktg-train/nodal_note.md `## Accepted-results snapshot` and is reproducible verbatim by re-running the command. -->
- `env-toolchain-b200` (empirical, verifier pass, job 298018): KataGo v1.18.2 CUDA + torch 2.11.0+cu128 on B200; sm_100 SASS; b7c96h3tfrs benchmark/gtp/torch fwd-bwd at 9x9.

## Next Work Steps

- `[SOLID] decompose + reconciliation` — DONE 2026-09-04: 38 nodes; `evidence/decomposition/dag_reconciliation.md`, `logic.md`, `DESIGN.md`.
- `[SOLID] wave 1` — DONE 2026-09-04: `env_build` solid; `cfg_9x9_override` (empirical; knowledge row `skip_exec` → `o30`), `tiny_model_export_smoke` (empirical; o23 discharged), `loop_resume_under_walltime` (existence_only; o08/o09/o17/o27 discharged, o26 rejected on the SIGTERM path → `o31`) all preliminary; `data_budget` result conditional, node still `hypothesis` (o28 repair `989f337`, validation pending); 14 code-map nodes re-affirmed preliminary.
- **Wave-2 READY frontier** (ledger walk 2026-09-04; `preliminary` predecessors admit `empirical`/`conditional` at `preliminary`; `solid` needs `solid`):
  1. `[OPEN] synchronous_loop_smoke` — preds `cfg_9x9_override`/`tiny_model_export_smoke`/`loop_resume_under_walltime` (preliminary) + `data_budget` (hypothesis, result admitted): **ONE 1-GPU b200 job** (`codes/loop/smoke_loop.sbatch`, 24 CPUs, 64G, 3 h, no chain; ~20 h queue), legs A-E: (A) in-allocation re-append of the `cfg_9x9_override` row (gate runs `check_cfg_9x9.sh`) → o30; (B,C) two cycles of `synchronous_loop_9x9.sh` with 40 games / 256 samples/epoch / batch 32 / reuse 8 / minrows 200 / keep 5000 > cap 4000 / epochs-per-export 1 → c07, o19, real-net `nlwp` per stage (o03/c06), rows/game (c10), row bytes 2145 + `SZ[9]` (c05, o02 measurement); (D1) `paper_code_map_search` probes on the exported net (full_frac, rows/game, sz_other, gate_random); (D2) `paper_code_map_training` probes (trunk gpool 0, gpool residuals, real-npz row bytes, kill/resume); (E) audit → `evidence/smoke/{rows_per_game.txt,audit.json,throughput_smoke.json}` for `derive_cycle_knobs_9x9` / `measure_stage_throughput`. Task file `tasks/synchronous_loop_smoke/`. `[SOLID]` DESIGN §2 S2 knobs (20 games, 2000/epoch) export nothing: `train.py:1303-1346` needs shuffled rows ≥ samples/epoch.
  2. `[OPEN] data_budget` → knowledge row to `preliminary` once the o28 repair validation lands (CPU).
  3. `[OPEN] loop_resume_under_walltime` → o26/o31 SIGTERM classification in `loop.sbatch` (CPU; not needed by the smoke).
  Probe packets `paper_code_map_{search,training}`: **no separate GPU job** — produced by item 1 (task files updated).
- `[OPEN] after the smoke lands` — `derive_cycle_knobs_9x9` (CPU; task file written; `derive_knobs.py` K1-K7 closes o24 + o13, rewrites the knob block), `verify_preemption_resume` (c08), `loop_failure_circuit_breaker` (o25) → P1 five stages + `bootstrap_accepted_model` → `measure_stage_throughput`, `count_gatekeeper_acceptances`, `match_latest_against_first` → `eval_improvement` → `scale_*` → `scale_up`.
- `[BLOCKING]` before P1: `o02` wiring (shuffle_stage), `o03` (smoke S9), `o04`/`o28` (data_budget), `o13`/`o24` (knobs), `o25`, `o26`/`o31` (wrapper), `o30` (smoke leg A).
- `[OPEN]` non-blocking: `o05`, `o11`, `o12`, `o15`, `o19` (smoke S3), `o20`, `o21`, `o29` (c03 mission-cfg conjunct; smoke runs the exported b7 under the mission cfgs — validator decides); `[FUTURE]` `async_multi_gpu_layout`, nbt family, external 9x9 reference net.

## Human decisions (resolved 2026-09-03, `mission.json.decisions[]`, landed `ace9d0c`)

- CPU policy: **no limit**, 20 % clause withdrawn (was per-job-vs-summed `[HOLE]`, `a11`). Scratch: **500 GiB** for selfplay+checkpoints (was 200 GiB, 94 % group scratch). Compute: **b200** while b300 reserved, same GPU count.
- `[OPEN]` propagation gap: `DESIGN.md` §5 and `tasks/data_budget/implementation.md` still hard-code the superseded 200 GiB cap / 180 GiB guard (`214748364800`/`193273528320` B); ledger rows `o22_cpu_policy_scope` (open), `a11_cpu_policy_summed` (active), `o04_scratch_budget` (open, states 200/180) not yet waived/relaxed/amended. Fix is a worker/brain ledger append (`data_budget` wave-1 task), not an observer append — see Next Work Steps item 4.

## Audit references

Ledgers `results/ledgers/{error,knowledge,claim,result}/paper_arxiv-1902.10565/` · DAG `results/ktg/paper_1902.10565/decomposition/logic.md`,
`results/ktg/GLOBAL_DAG.md` · reconciliation `evidence/decomposition/dag_reconciliation.md` · design `decomposition/DESIGN.md` ·
digest `progress/ktg-train/HUMAN_DIGEST.md` · commit grammar `phys-agentic-loop/_common/contracts/commit_template.md`.
