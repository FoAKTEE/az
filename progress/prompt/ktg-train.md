
**central task** training of 9*9 transformer-based KataGo using 1-2 B300
* ref-code: https://github.com/lightvector/KataGo
* we are on schmidt cluster




## Graph building-up
* auto decomposition - each paper should have their own DAG under phys-agentic-loop
* all brain needed works to fable 5.1 xhigh
* giant DAG - all should have one giant DAG (do this two times, by fable 5.1 xhigh, chatgpt 5.6 sol max + two model review)
* work, brainless work to opus 5 ultra

## Git commit policy
* substage commits: one commit per DAG node (or finer), commit tests before/with code
* messages follow `phys-agentic-loop/_common/contracts/commit_template.md`
  (commit-msg gate already wire); no mention / no coauthor of Claude in any case
* never commit large datasets

## Management policy
* under `phys-agentic-loop`: multiscale memory (this prompt + DAG + design doc
  are the upstream-dependency ledger; update DAG node status as nodes land)
    * you are allowed to use depth-2 agentic workflow, making all paper decomposition run in parallel
* maximal topological scheduling: deploy parallel subagents;
* verification discipline: every claim in commit bodies tagged
  `[SOLID|PRELIMINARY|HOLE|FUTURE]` with a real `verify:` object

## Computation Usage
* CPU: 
  * no more than 20% of all CPUs
* GPU:
  * at most only use the last 4 GPUs (use only B200 or B300)
  * if GPUs are occupied, use maximal available GPUs
* make computation usage a recurring skill to self-check when launching large computation jobs

