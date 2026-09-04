# current_iter — ktg-train (iteration 0, wave 0)

1. **Paper anchor** — none yet; wave 0 is acquire + decompose (`pipelines/0-acquire`, `pipelines/1-decompose`).
2. **What shipped this iter** — mission spine (`mission.json`), notes scaffold, commit-msg gate extended with provenance hygiene, `ssci` branch opened.
3. **Next-3 roadmap** — (a) acquire paper+code mirrors with provenance; (b) fable decomposition → claim ledger + DAG; codex independent DAG; (c) env build on a GPU node (venv + katago CUDA/cuDNN). crash-triage: n/a (no trials yet).
4. **Simplification flag** — n/a (no metric yet).
5. **Verifier output** — `python3 -m pytest -q` → 164 passed (infra self-hosts); gate self-test rejects AI-attribution lines (see tests/test_commit_msg_gate.py).
