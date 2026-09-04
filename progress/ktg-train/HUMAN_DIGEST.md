# HUMAN_DIGEST — ktg-train

**Status:** wave 0 closed (stage `0-acquire` + stage `1-decompose`); wave 1 workers dispatched and running.

## What landed

- **0-acquire**: KataGo v1.18.2 mirrored to `ref-code/lightvector-KataGo` (pinned `fd0723fd`, sha-verified), `arXiv:1902.10565` tex mirror to `ref-paper/`, both with `PROVENANCE.md`.
- **1-decompose**: two independent DAG passes (26 nodes, then a deeper 32-concept pass), two independent review seats (seat A 38 nodes, seat B 39 nodes — seat B run by the external reviewer), reconciled into the **canonical 38-node DAG** (74 edges, `duplicates` = `[]`). Deliverables: `DESIGN.md`, `logic.md`, `results/ktg/GLOBAL_DAG.md`, 51 claim-ledger entries (16 claims/2 admitted, 24 obligations/6 discharged, 11 assumptions), task packets for the four-node READY frontier plus two code-map probes.
- **env_build executed and admitted**: attempt 1 (job 297952) failed 2/5 smoke steps — the CUDA backend refuses any non-SwiGLU transformer FFN block (`b5c48h3tfr` uses `ffng`), and the stock CMake list omits `sm_100` for CUDA 12.8. Attempt 2 (job 298018, b200/gb205), after switching the smoke net to `b7c96h3tfrs` and applying a one-line `cmake-sm100.diff`, passed all 6 steps. Result row **`env-toolchain-b200`** admitted (empirical); this also promoted `engine_ffn_swiglu_constraint` to solid.
- **Framework fix**: `phys-agentic-loop` (submodule branch `ssci`) bumped to `959a4cd` — a `status=amended` knowledge row now correctly retires its node instead of leaving a ghost `blocking` row in `render`/`progress`/dependency resolution; `pytest -q tests` → 173 passed.
- **Human decisions landed** (`mission.json.decisions[]`, commit `ace9d0c`): no CPU usage limit (PROMPT.md's 20 % clause withdrawn); scratch budget 500 GiB for selfplay data + checkpoints; run on b200 while b300 is reserved, same GPU count.

## What is blocked / open

- **Nothing blocks wave 1** — the loop gate reports `continue` (no-progress 0/8, stuck 0/3).
- **Propagation gap** (not blocking, tracked for the wave-1 `data_budget` worker): the human's 500 GiB scratch decision has not yet been written into `DESIGN.md` §5 or `tasks/data_budget/implementation.md`, which still hard-code the old 200 GiB cap / 180 GiB guard; and claim-ledger rows `o22_cpu_policy_scope` / `a11_cpu_policy_summed` / `o04_scratch_budget` have not been waived/relaxed/amended to match the two decisions. This observer recorded the decisions and the gap in `RESEARCH_STATE.md`; closing the ledger rows requires a worker/brain append (executable admission), not an observer append.
- **Simplification obligation**: `loop_policy.py simplification-status --task env_build` reports `status: required` — the next `env_build`-adjacent commit (the `data_budget` scratch-constant rewrite touches the same environment) must carry `change_type=refactor`.
- **Wave 1 in flight** (uncommitted at the time of this digest): workers are running on `cfg_9x9_override`, `tiny_model_export_smoke`, `loop_resume_under_walltime`, `data_budget`, and the two code-map promotion probes (`paper_code_map_search`, `paper_code_map_training`). Untracked output already visible under `results/ktg/paper_1902.10565/{codes,evidence}/…`.

## Decisions needed from you

- **None pending.** All three decisions raised at wave 0 (CPU policy, scratch budget, b200 vs b300) are recorded and landed in `mission.json`.

## Pointers

`progress/ktg-train/RESEARCH_STATE.md` (mission through-line, ≤ 10 KB) · `progress/ktg-train/nodal_note.md` (10-iter window: DAG snapshot, accepted results, simplification cycle) · `progress/ktg-train/loop_notes/current_iter.md` (this wave's verbatim verifier output) · `results/ktg/paper_1902.10565/decomposition/{logic,DESIGN}.md` · `results/ktg/GLOBAL_DAG.md`.
