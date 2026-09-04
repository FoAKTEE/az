# Validation — `arxiv-1902.10565::tiny_model_export_smoke`

Role: validator (refuter, then judge). Cross-model relative to the worker that produced the
candidate. Inputs received: the task file (`tasks/tiny_model_export_smoke/implementation.md`
sections 1, 2, 13, 14), `evidence/tiny_smoke/candidate_rows.json`, the evidence directory
`evidence/tiny_smoke/`, the three artifacts under `codes/eval/`, the worker's error-ledger row
`a3553e5c…`, Slurm accounting for job 298358, the exported artifacts under
`/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/{x,x_ffng}`, and the ledger
schemas. Host: login03, CPU only — no job submitted, no GPU touched.
Date: 2026-09-04 (UTC); 2026-09-04 00:30–00:45 local.

## 1. Refutation attempt — re-run the CPU conjunct of the section-2 command

The section-2 command is `bash codes/eval/export_smoke.sh b7c96h3tfrs && python3
codes/eval/check_export_blocks.py $W/model.bin`. Conjunct 1 needs a CUDA device and ran as job
298358 (section 2 below). Conjunct 2 re-run by the validator from the az root, verbatim:

```
model.bin       : /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/x/model.bin (3281596 bytes)
block histogram : {"transformer_attention_block": 7, "transformer_ffn_block": 7}
expected        : {"transformer_attention_block": 7, "transformer_ffn_block": 7}
trunk declares  : 14 blocks; kind lines found: 14
witness         : ^[A-Za-z0-9_.]+\.q_proj$     7 (kind lines: 7)
witness         : ^[A-Za-z0-9_.]+\.ffn_linear1$ 7 (kind lines: 7)
BLOCK_HISTOGRAM: PASS
exit=0
```

Identical to the worker's `verification.txt` and to leg 2 of the job transcript. The artifact is the
job's: `model.bin` sha256 `c9b7ec220789f3e6a43043ef6cbb6109f455bf6a4de133645f82016958ad03fc`,
3281596 B, mtime 2026-09-04 00:24:51.321 -0400, inside the job window 00:24:44–00:25:04.

Control: the negative-fixture export through the same checker must fail the default expectation,
and does: `{"transformer_attention_block": 5, "transformer_ffn_block": 5}`, trunk declares 10,
witnesses 5/5, `FAIL: histogram … != expected`, exit 1. The refutation fails.

## 2. Refutation attempt — did job 298358 really run the GPU legs?

```
$ sacct -j 298358 -X -n -o JobID,State,ExitCode,Elapsed,NodeList,AllocTRES%50,Start,End
298358  COMPLETED  0:0  00:00:20  gb205  billing=8,cpu=8,energy=7097,gres/gpu=1,mem=64G,no+  2026-09-04T00:24:44  2026-09-04T00:25:04
```

Transcript identity: `diff <(sed '$d' /scratch/…/logs/export-smoke-298358.log)
evidence/tiny_smoke/export_smoke-298358.txt` → identical (the Slurm log's extra last line is the
runner's `transcript: …` echo). The scratch-side and repo-side transcripts have the same sha256
`a6fa0f5569987d575558ee67563530da4e02e9980b572056a7d97830fcb99737`. The raw job outputs match the
transcript line for line: `$W/benchmarknn.json` carries
`"boardSizes":[9],"requireExactNNLen":true,"usingFP16":true,"batchSize":2,…,"sumMedianNNEvalsPerSec":4536.95806`;
`$W/gtp_out.txt` is `=`, `=`, `=`, `= J6`, `=`; `$W_neg/benchmarknn.both` ends with
`Model name: ktg-smoke-b5c48h3tfr (transformer, 125241 params)` / `terminate called after throwing an
instance of 'StringError'` / `what():  Non-SwiGLU transformer FFN is not yet supported in CUDA
backend`. Exit 134 = 128 + SIGABRT, consistent with `std::terminate`. No core file under `$W` or
`$W_neg`. The `-dirty` engine revision is the sm_100 arch-list patch recorded by `env_build`
(result `env-toolchain-b200`), i.e. the "one patched binary" o23 asks for. The refutation fails.

## 3. Refutation attempt — can `check_export_blocks.py` be fooled?

The histogram is a MULTILINE byte regex `^<kind>$` over the whole `model.bin`. Inspection of the
real file: the model name is line 1 (`ktg-smoke-b7c96h3tfrs`), the trunk header `trunk\n14` at
byte 82, 92 `@BIN@` float sections; every kind string occurs exactly as often anywhere in the file
as it does as a full line (7/7), `q_proj` 7, `ffn_linear1` 7, and no `ordinary_block` /
`gpool_block` / `nested_bottleneck_block` bytes at all. `metadata.json` is `{}` and is not read.

Seven fixtures derived from the real `model.bin` (each written to the scratchpad, run through the
unmodified checker, deleted):

| fixture | mutation | exit | caught by |
|---|---|---|---|
| A | model name replaced by `transformer_attention_block` | 1 | histogram 8≠7; trunk declares 14 but 15 lines; witness 7≠8 |
| B | kind lines relabeled to 7 `ordinary_block` + 7 `gpool_block` | 1 | histogram ≠; both witnesses 7≠0; "unexpected block kind" ×2 |
| C | `transformer_ffn_block` appended as trailing text | 1 | histogram 8≠7; 15≠14; witness 7≠8 |
| D | one attention block relabeled `transformer_ffn_block` | 1 | histogram {6,8}; witnesses 7≠6, 7≠8 |
| E | one kind line duplicated | 1 | histogram 8≠7; 15≠14; witness 7≠8 |
| F | `.q_proj` matmul names renamed (kind lines intact, 7+7) | 1 | witness 0≠7 only — the witness is what discriminates here |
| G | one attn + one ffn kind line deleted | 1 | histogram {6,6}; 12≠14; witnesses 7≠6 |

So the two structural witnesses do discriminate: the trunk-declared count catches any injected or
missing kind line (A, C, E, G), and the matmul-name witness catches kind relabeling that keeps the
totals (D) and body/label disagreement (F). A stray match inside a float blob would need 21–27
exact ASCII bytes bounded by `\n` and would still trip the trunk count. What the checker does NOT
see: the SwiGLU variant — `b5c48h3tfr` also writes `transformer_ffn_block` and `ffn_linear1` (5/5
above). That is not claimed of it; the SwiGLU refusal is the engine's job (leg 5). GTP regex
`[A-HJ][1-9]` is stricter than the task file's `[A-J]` (Go has no I column) and `J6` is a legal
9x9 vertex. The refutation fails.

## 4. Refutation attempt — does the negative fixture assert the model name BEFORE the throw?

Not literally: `export_smoke.sh` counts `Model name: ktg-smoke-b5c48h3tfr` lines (≥1) and distinct
diagnostics (==1) independently; it does not compare positions. The ordering is nevertheless
established by the transcript (model-name line 87, `terminate called` 88, `what()` 89) and is
forced by the mechanism: the diagnostic is printed by the terminate handler, so every other line
necessarily precedes it. The "asserts … BEFORE" wording in `candidate_rows.json` is a slight
overstatement of the script; the evidence itself is correct. Recorded, not a gate failure.

Reading of o23's "identical benchmarknn/gtp on both": `benchmarknn` was run on both kinds, `gtp`
only on the positive kind. The throw site is backend model construction
(`cpp/neuralnet/cudaandrocmbackend.inc:3308`), before any command-specific code, and the task file's
section 2 defines leg 5 as `benchmarknn`; the benchmarknn pair isolates the FFN variable. Discharged.

## 5. Status audit of the proposed rows

- **Result row `checked` → rejected as proposed; admitted as `empirical`.** The result schema
  says `open_obligations: [] for checked results`, and the row carries `o08`, `o15`. The contract
  does not promote simulations/measurements to exact results, and the append-time gate re-executes
  only the CPU histogram conjunct; the GPU legs are witnessed by the content-hashed transcript and
  Slurm accounting, not re-run. `empirical` is also the status of the sibling
  `env-toolchain-b200`. The claim text is admitted unchanged — every number in it was checked
  against the raw job outputs.
- **Knowledge row `preliminary` — confirmed.** `knowledge_database.py predecessors` →
  `env_build` (solid), `select_transformer_ladder` (preliminary). The gate rule "solid needs solid
  predecessors" blocks `solid` mechanically; nothing about this node's own evidence is outstanding.
  Promoting `select_transformer_ladder` is outside this validation's inputs.
- **c03 `open → in_progress` — honest.** Its last conjunct names `katago benchmark … with the
  mission selfplay_9x9.cfg`; section 13 forbids this node from using `selfplay_9x9.cfg` (no edge to
  `cfg_9x9_override`) and from substituting `benchmark` for `benchmarknn`. The claim as worded
  cannot be settled by its only node. Opened `o29_c03_mission_cfg_conjunct` (non-blocking) so the
  reconciliation is visible in `obligations.md` rather than buried in notes.
- **o23 `discharged`**, `discharged_by = r_tiny_model_export_smoke_b7c96h3tfrs` (the settled result
  row rather than the knowledge node the worker suggested; both resolve).
- **o08, o15 stay open, untouched** (owner `export_stage`). Observation only: the literal o08 grep
  `grep -rn 'export_model\.py' codes/` now returns nothing on both HEAD (commit `4fd3302`, after the
  worker's `guards.txt` at 00:26) and the working tree; discharge belongs to that node's validation.
- **Path deviations**: scripts in `codes/eval/` (packet said `codes/tiny_smoke/`; the section-2
  command hardcodes `codes/eval/` and runs green) and evidence in `evidence/tiny_smoke/` (section 14
  says `evidence/export_smoke/`). Neither breaks an executed check; section 14 governs a commit
  body. Owner of the convention question: `jobs`.
- Live guards re-run: `b5c48h3tfr` appears only in `codes/eval/export_smoke.sh`;
  `-ignore-attn-logit-bound` nowhere in `codes/`; dependencies `env_build`,
  `select_transformer_ladder`, `transformer_trunk_b7c96h3tfrs`, `engine_ffn_swiglu_constraint` all
  resolve to knowledge nodes; `error_db_refs` hash/timestamp/commit match the worker's trial row.

## 6. Verdict — ADMIT (with the result status lowered to `empirical`)

Ledger verification command (CPU-only, run by the gate from the az root, exit 0; it pins
`model.bin` to the sha256 above, re-derives the histogram live, and pins each recorded GPU outcome
against the content-hashed transcript):

```
echo 'c9b7ec220789f3e6a43043ef6cbb6109f455bf6a4de133645f82016958ad03fc  /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/x/model.bin' | sha256sum -c --quiet && python3 results/ktg/paper_1902.10565/codes/eval/check_export_blocks.py /scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/smoke/x/model.bin && T=results/ktg/paper_1902.10565/evidence/tiny_smoke/export_smoke-298358.txt && grep -q '^EXPORT_SMOKE RESULT: PASS$' "$T" && grep -q '"sumMedianNNEvalsPerSec":4536.95806' "$T" && grep -q '^genmove response: = J6$' "$T" && grep -q '^negative benchmarknn exit=134$' "$T" && grep -q '^distinct diagnostics     = 1$' "$T" && grep -q 'Non-SwiGLU transformer FFN is not yet supported in CUDA backend' "$T" && grep -q '^model-identified lines   = 1' "$T"
```

Appends (`CHANDRA_ROLE=validator`; the gate re-ran the verifier, exit 0; no `admission_flags`):

```
{"appended": true, "paper": "arxiv-1902.10565", "result_id": "r_tiny_model_export_smoke_b7c96h3tfrs", "status": "empirical", "timestamp": "2026-09-04T04:40:58.595697+00:00", "evidence_sha256": "a38afcdd3f2c6d3aba8c87491db422337ae97cd4ed15c0b39353e4debb69b690", "verified_exit_code": 0}
{"appended": true, "git_commit": "e56b240", "timestamp": "2026-09-04T04:40:59.149339+00:00", "paper": "arxiv-1902.10565", "node_id": "arxiv-1902.10565::tiny_model_export_smoke", "status": "preliminary", "evidence_sha256": "a38afcdd3f2c6d3aba8c87491db422337ae97cd4ed15c0b39353e4debb69b690"}
{"appended": true, "paper": "arxiv-1902.10565", "entry_id": "o23_ffn_negative_fixture", "kind": "obligation", "status": "discharged", "timestamp": "2026-09-04T04:40:59.681064+00:00"}
{"appended": true, "paper": "arxiv-1902.10565", "entry_id": "c03_tf_export_loads", "kind": "claim", "status": "in_progress", "timestamp": "2026-09-04T04:40:59.821377+00:00"}
{"appended": true, "paper": "arxiv-1902.10565", "entry_id": "o29_c03_mission_cfg_conjunct", "kind": "obligation", "status": "open", "timestamp": "2026-09-04T04:40:59.966825+00:00"}
{"appended": true, "git_commit": "e56b240", "timestamp": "2026-09-04T04:41:00+00:00"}
```

Row hashes: result `d4b30beefb32a7062b83d88e51aacce0ce1fd355e464c2551a59fbc468635013`; knowledge
`96d79bb1cfddf5ed4988e09e6aae6e125c9e2e9f6dba0d5f01bc36fcaf457881` (node_seq 4); o23
`a326d0a97bb5c9834da2111571efc84c917924cdb57016f13deaea69df7c0bc1`; c03
`e3291f09a0563966fa8818db8df3bc6440b506e1838fc34170c61f03cf462ad2`; o29
`a28349ca904f3601ee049fe4bda0d3c5e9cbc3844b4bad6e8d0984e00246daf6`; error (validation trial, pass)
`d0a48be809dfdece56df620ea5457047382c4dbc59438b87b083c65157601710`.

Remaining `[OPEN]`, none on this node's own path:
- `o29_c03_mission_cfg_conjunct` — amend c03 or run the export under `codes/cfg/selfplay_9x9.cfg` (jobs / cfg_9x9_override).
- `o15_attn_logit_export_guard` — trained checkpoint only (export_stage).
- `o08_exporter_name` — grep is clean on HEAD; formal discharge by export_stage's validation.
- node promotion `preliminary → solid` — waits on `select_transformer_ladder`.
- packet path convention (`codes/tiny_smoke` vs `codes/eval`; `evidence/export_smoke` vs `evidence/tiny_smoke`) — jobs.
