# RESEARCH_STATE — ktg-train

**Mission.** Train a 9×9 transformer-trunk KataGo net end-to-end (self-play → shuffle → train → export →
gatekeeper) on the Schmidt B200/B300 cluster within the compute policy (≤4 GPUs total, ≤24 CPUs, b300 preferred /
b200 fallback, 3-day walltime). **Phase.** 1-decompose done (brain pass) → 2-work wave 1. **Branch.** `ssci`.
**Paper id (ledger label only).** `arxiv-1902.10565`. **Layout (2026-09-03).** consumer artifacts at the `az` root:
`results/`, `progress/`, `ref-code/`, `ref-paper/`, `mission.json`; tools invoked as `python3 phys-agentic-loop/_common/...`
from `az`. **Runtime.** `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/` (venv, build, loop data, logs).

## Source Library

| ID | Source | Status | Notes |
|---|---|---|---|
| `code` | `ref-code/lightvector-KataGo/` @ v1.18.2 `fd0723fd` | `[SOLID]` | **primary source of truth** (human redirect 2026-09-03: code-first). Declarations `results/ktg/sources/code_lightvector-KataGo.md`; audits `results/ktg/paper_1902.10565/evidence/decomposition/audit_*.md` |
| `paper` | `ref-paper/arxiv-1902.10565/` | `[SOLID]` | background only; ideas still in code mapped in `decomposition/derivation.md` |
| `cluster` | `docs/cluster-manual.md` | `[SOLID]` | verified live 2026-09-03; b200 free 2/128, b300 0/8, scratch 94 % |

## Working Context

| Name | Meaning | Regime / assumptions |
|---|---|---|
| source priority | v1.18.2 code decides nodes, claims, plans; paper cited only where the code still implements the idea (playout cap randomization, root forced visits + target pruning, aux targets, score utility, gating) | `[ASSUMPTION] a09` |
| board | 9×9 only: `bSizes=9`, `bSizeRelProbs=1`, `allowRectangleProb=0`, `dataBoardLen=9`, `train.py -pos-len 9` — the last two together (`data_processing_pytorch.py:91`); upstream `maxsize9` presets are 7–9 with rectangles, `dataBoardLen=19`, `train.sh:88 -pos-len 19` | `[ASSUMPTION] a05`; leaving both at 19 silently costs ~20× attention FLOPs |
| trunk | `b5c48h3tfr` = 5 × (`attnrope`, `ffng`), RoPE θ 100, no trunk gpool (heads keep gpool; collinear at strict 9x9); exportable | `[SOLID]` code reading; family `tf`, `nbt` = `[FUTURE]` |
| loop | mission copy of `synchronous_loop.sh`; exporter `export_model_pytorch.py`; USEGATING=1; threads: selfplay 18 / gatekeeper 20 game threads, 1 search, 1 nnServer, shuffle 8 procs, OMP 4 | ≤24 OS threads per stage; 1 GPU start |
| build | CUDA backend, cuDNN 9.x pip wheel; **`cpp/CMakeLists.txt:761` omits sm_100 for CUDA 12.8** → env_build now applies `codes/env/cmake-sm100.diff` (stage 2b) and asserts sm_100 SASS via `cuobjdump`; env_build's smoke model was switched to `b7c96h3tfrs` (design: `b5c48h3tfr`) — reconcile | `[BLOCKING] o06`, `[OPEN] o18` |
| loss / optimizer | code weights (policy 0.93, value 0.72, ownership 1.5/b², …), SGD m=0.9 + Lookahead, lr 3e-5 base — paper values are not targets | `[SOLID]` `derivation.md` §2 |

## Active Claims (ledger `results/ledgers/claim/paper_arxiv-1902.10565/`, 45 rows: 16 claims / 18 obligations (1 discharged) / 10 assumptions)

| Claim | Needed evidence | Priority |
|---|---|---|
| c01/c02 env_build runs; sm_100 SASS or working JIT | numerical_simulation | `[BLOCKING]` job 297952 running on gb205 |
| c03 tiny export loads in C++; c04 all SGFs SZ[9]; c05 pos_len-9 shuffle+train epoch | numerical_simulation | wave 1 |
| c06 threads ≤ 24; c07 one loop cycle; c08 kill/resume no loss | empirical / numerical | wave 1–2 |
| c09/c10/c11 selfplay rate, rows/game ∈ [12,35], scratch ≤ 200 GB | empirical_measurement | wave 2 |
| c13 ≥ 2 gatekeeper acceptances; c14 latest vs first net ≥ 60 % over 400 games @150 visits | empirical / statistical_inference | P1 exit |
| c15 paper ideas present in code (literature_grounding) | code reading — evidence on disk | promote via probes |

## Accepted Results Log

<!-- GENERATED block — regenerate with: python3 phys-agentic-loop/_common/result_database.py render-state --paper arxiv-1902.10565 -->
(empty — no admitted results yet)

## Next Work Steps

- `[SOLID] decompose (brain pass)` — DONE 2026-09-03: 26 knowledge nodes (13 preliminary code-reading, 13 hypothesis infra), 43 claim-ledger rows,
  `decomposition/{convention,derivation,ref,summary,logic,claims,obligations,assumptions,DESIGN,implementation_plan_*,result_seed}.md`,
  `results/ktg/GLOBAL_DAG.md`, task files `tasks/{env_build,cfg_9x9_override,paper_code_map_search,paper_code_map_training,tiny_model_export_smoke,data_budget}/`.
  Second-reviewer pass (`logic_pass2.md`, `design_pass2.md`) runs in parallel; two-model adjudication is the next brain wave.
- `[BLOCKING] env_build` — job 297952; after PASS run `cuobjdump --list-elf katago | grep -c sm_100` (o06), record cuDNN version (o05), write `requirements.txt` (o12).
- `[OPEN] cfg_9x9_override` → `tiny_model_export_smoke` → `synchronous_loop_smoke` (20 games, 1 cycle; mission loop copy must copy `$KATAGO_BIN`, not `cpp/katago` — `[BLOCKING] o17`) → kill/resume test → `data_budget` measurement → P1.
- `[OPEN] probes` — `paper_code_map_search` / `paper_code_map_training` promote the 13 preliminary nodes to solid.

## Open Questions (human)

- Is the 20 % CPU policy per job or summed over my concurrent jobs? Design assumes summed (no second concurrent job) — `DESIGN.md` §1 `[HOLE]`.
- b300 reserved until 2026-09-04 15:00 → running on b200 at 1 GPU (default yes).
- Scratch at 94 %: mission cap 200 GB on `BASEDIR`; group-level cleanup is outside this mission.

## Audit references

Ledgers `results/ledgers/{error,knowledge,claim}/paper_arxiv-1902.10565/` · DAG `results/ktg/paper_1902.10565/decomposition/logic.md`,
`results/ktg/GLOBAL_DAG.md` · design `decomposition/DESIGN.md` · digest `progress/ktg-train/HUMAN_DIGEST.md` · commit grammar
`phys-agentic-loop/_common/contracts/commit_template.md`.
