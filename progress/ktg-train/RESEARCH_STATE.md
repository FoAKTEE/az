# RESEARCH_STATE — ktg-train

**Mission.** Train a 9×9 transformer-trunk KataGo network end-to-end (self-play → shuffle →
train → export → gatekeeper) on the Schmidt B200/B300 cluster, within the compute policy in
`PROMPT.md` (≤4 GPUs total, ≤24 CPUs/job, b300 preferred / b200 fallback).
**Phase.** 0-acquire → 1-decompose (wave 0). **Branch.** `ssci`. **Paper.** `arxiv-1902.10565`.
**Project tree.** `results/ktg/paper_1902.10565/`. **Ledgers.** `results/ledgers/<db>/paper_1902.10565/`.
**Runtime.** `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/` (venv, build, selfplay data, logs).

## Source Library

| ID | Source | Kind | Status | Notes |
|---|---|---|---|---|
| `paper` | `ref-paper/arxiv-1902.10565/` | paper | `[SOLID]` acquired | tex mirrored 2026-09-04, sha256 `71a0e894…6c4e`, 12 files, `PROVENANCE.md` + `results/ktg/sources/paper_arxiv-1902.10565.md`. No PDF fallback needed |
| `code` | `ref-code/lightvector-KataGo/` @ v1.18.2 `fd0723fd` | code | `[SOLID]` acquired | `git rev-parse HEAD` = `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4`, matches pin; tree clean. `PROVENANCE.md` + `results/ktg/sources/code_lightvector-KataGo.md` (all citations grep-verified) |
| `cluster` | `../docs/cluster-manual.md` | infra | `[SOLID]` | verified live 2026-09-03 |

## Working Context

| Name | Meaning | Assumptions / regime |
|---|---|---|
| board | 9×9 only (`bSizes=9`, `bSizeRelProbs=1`) | `[ASSUMPTION]` no mixed-size training. Upstream ships only `7,8,9` presets (`cpp/configs/training/{selfplay1,gatekeeper1}_maxsize9.cfg:95-96/:38-39`) — needs a mission-owned override |
| trunk | interleaved `attn*`+`ffn*` family `b*c*h*tf*` (`modelconfigs.py:1886-1942`) | smoke = `b5c48h3tfr` (`:986-1006`), which uses `ffng` not `ffnsg` (`:999`, `# no swiglu`). Fused `nbt` family (`bottlenest2transformerropesg`, `model_pytorch.py:2972-2978`) is the alternative — `[OPEN] family-choice` |
| loop | `python/selfplay/synchronous_loop.sh` on one node: gatekeeper `:96` → selfplay `:99` → shuffle `:105` → train `:109` → export `:113` | `[ASSUMPTION]` single-node; upstream advises 4–40× more GPU on selfplay than train (`SelfplayTraining.md`). Exporter is `python/export_model_pytorch.py` — upstream docs' `export_model.py` does not exist at this tag |
| backend | CUDA + cuDNN ≥ 9.8 (pip `nvidia-cudnn-cu12`) | `[OPEN]` TensorRT deferred |

## Active Claims

| Claim | Needed evidence | Priority | Owner |
|---|---|---|---|
| Environment: katago C++ (CUDA/cuDNN) + torch cu128 venv build and run on a B200 node | numerical_simulation (smoke game + 1 train step) | `[BLOCKING]` | worker |
| A 9×9 transformer net improves under self-play (gatekeeper accepts ≥1 successor) | empirical_measurement | `[OPEN]` | worker |

## Accepted Results Log

<!-- GENERATED block — regenerate with: python3 _common/result_database.py render-state --paper arxiv-1902.10565 -->
(empty — no admitted results yet)

## Next Work Steps

- `[SOLID] acquire` — DONE 2026-09-04. Both mirrors + `PROVENANCE.md` + both `results/ktg/sources/*.md`; ledger rows `dc1afe0c…` (code) and `d96071fb…` (paper) in `results/ledgers/error/paper_arxiv-1902.10565/trials.jsonl`, `sha_match` pass. Carry-forward `[OPEN]`s: paper — arch-gap, boardsize-gap, hparam-scale, tex-compile; code — nbt-export, family-choice, pydeps, cfg-audit, build-unverified, export-name.
- `[OPEN] decompose` — claim ledger + `logic.md` DAG (fable pass) and an independent codex pass; two-model review → `results/ktg/GLOBAL_DAG.md`. Verifier: `dag_mermaid.py render/merge` exit 0, no duplicate node ids.
- `[OPEN] env_build` — venv + katago build on a GPU node; smoke: `katago benchmark` on a tiny transformer net. Verifier: exit 0, output in `evidence/env/`.

## Open Questions (human)

- B300 (`gb301`) is fully reserved by another group until at least 2026-09-04 15:00; run on `b200` meanwhile? (default: yes, same GPU count)
- Scratch is at 94 % of the group's 40 TB — self-play data will need a budget or cleanup.

## Audit references

Ledgers `results/ledgers/{error,result,knowledge,claim}/paper_1902.10565/` · DAG `results/ktg/paper_1902.10565/decomposition/logic.md`, `results/ktg/GLOBAL_DAG.md` · digest `progress/ktg-train/HUMAN_DIGEST.md` · commit template `_common/contracts/commit_template.md`.
