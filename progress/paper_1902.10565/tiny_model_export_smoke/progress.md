# progress — `tiny_model_export_smoke`

Node `arxiv-1902.10565::tiny_model_export_smoke`. Gate between the toolchain and the
loop: a random-initialized `b7c96h3tfrs` must export, lower to exactly 7 attention +
7 FFN blocks, be accepted by the C++ model reader, serve >0 nnEval/s at 9x9, and play a
legal `genmove` — while the *same* binary must refuse a non-SwiGLU transformer FFN with
its exact diagnostic (`o23_ffn_negative_fixture`).

Code: `results/ktg/paper_1902.10565/codes/eval/`.
Evidence: `results/ktg/paper_1902.10565/evidence/tiny_smoke/`.

## Files

| file | role |
|---|---|
| `codes/eval/check_export_blocks.py` | exact block-kind histogram over `model.bin`, with two independent structural witnesses |
| `codes/eval/export_smoke.sh` | legs 1-5 of task §2 in one script; exits 0 only if every leg passes |
| `codes/eval/export_smoke.sbatch` | 1-GPU b200 runner (8 CPUs, 64 G, 30 min); supplies the GPU and a transcript, no science |

## Why the histogram check is not a bare grep

`model.bin` is ASCII text interleaved with `@BIN@`-prefixed little-endian float32 blobs, and
the blob lengths are only recoverable by reimplementing the whole reader. So the block-kind
lines are found by a MULTILINE byte regex over the closed set that
`export_model_pytorch.py::write_block` can emit, and the result is corroborated by two
structural witnesses drawn from unrelated parts of the record:

1. the trunk header's own declared block count (`write_trunk` writes `len(model.blocks)`
   directly after the literal `trunk`) — for `b7c96h3tfrs` that is `14`, and the kind lines
   must sum to it;
2. per-kind matmul names — every attention block writes one `<name>.q_proj`, every FFN block
   one `<name>.ffn_linear1`. Those counts must equal the kind-line counts.

A spurious match inside a float blob would have to be an exact 20+ byte ASCII sequence
bounded by newlines *and* be matched by an independent witness in the same multiplicity.
The match is exact equality with the expected dict, and any other block kind is a failure.

## Negative fixture (`o23`)

`b5c48h3tfr` is named in exactly one file in the mission (`codes/eval/export_smoke.sh`) and
never reaches `MODELKIND`, `-model-kind`, or any loop script. Leg 5 asserts four things, not
just a non-zero exit:

- exit code `!= 0`;
- the exact string `Non-SwiGLU transformer FFN is not yet supported in CUDA backend` present;
- exactly **one distinct** diagnostic string (the engine prints that same line more than once
  per abort — `ERROR: NN server thread failed: …` plus `what(): …` — so "count == 1" is read
  as one distinct diagnostic, not one occurrence);
- the engine got far enough to print `Model name: ktg-smoke-b5c48h3tfr`, which rules out the
  §11 risk that a missing file or a CLI error produced the non-zero exit instead.

This closes the two-variable confound of job `297952` (unpatched arch list + `b5c48h3tfr`)
versus `298018` (patched + `b7c96h3tfrs`): both kinds now run on one binary in one job.

`ulimit -c 0` guards the deliberate abort — scratch is ~94% full and a core dump is pure
waste.

## Run

One Slurm job, one binary, both model kinds. `298358` on b200/`gb205`: 1 GPU, 8 CPUs, 64 G,
`--time 00:30:00`, elapsed `00:00:20`, `COMPLETED 0:0`. Budget check
(`--gpus 1 --cpus 8 --partition b200`) exited 0 before submission.

| leg | measured | threshold | verdict |
|---|---|---|---|
| 1 export | `model.bin` 3281596 B, `model.bin.gz` 2992914 B, `metadata.json`, `log.txt` | files written | OK |
| 2 histogram | `{"transformer_attention_block": 7, "transformer_ffn_block": 7}`; trunk declares 14 == 14 kind lines; witnesses 7 `*.q_proj`, 7 `*.ffn_linear1` | exact dict equality, no other kind | OK |
| 3 `benchmarknn` | exit 0, `sumMedianNNEvalsPerSec = 4536.95806`, `perThreadMedianMs [0.440824]`, fp16 true, `requireExactNNLen` true | exit 0 and `> 0` | OK |
| 4 gtp | exit 0, `= J6` | exit 0, legal 9x9 vertex | OK |
| 5 negative fixture | exit 134, 1 occurrence and 1 distinct `Non-SwiGLU transformer FFN is not yet supported in CUDA backend`, model identified as `ktg-smoke-b5c48h3tfr (transformer, 125241 params)` before the throw | exit != 0 AND the exact string AND identified first | OK |

`EXPORT_SMOKE RESULT: PASS`, `export_smoke.sh exit=0`.

The engine identified the positive model as `ktg-smoke-b7c96h3tfrs (transformer, 818857 params)`
and took the fast paths — combined QKV projection, CUTLASS fused FFN, tensor-core mma flash
attention — so the 4536.96 nnEval/s is the shape the loop will actually serve.

Cost: 20 s of one B200, 6.1 MB at `$W` plus 964 KB at `$W_neg`, no core file.

Verification: §2's command needs a CUDA device for its first conjunct, so that conjunct ran as
job 298358 (exit 0) and the closing histogram check was then re-run standalone on `login03`
against the `model.bin` the job left at `$W` (exit 0, 0.24 s). Both halves verbatim in
`evidence/tiny_smoke/verification.txt`.

## Ledger

- error ledger trial (worker, appended):
  `a3553e5c2688f03b6764393df69d1d42dd021ce8b3a0f4e16de8c2b608e60400` — pass, 5/5 legs,
  `metric = {smoke_legs_passed: 5, threshold: 5}`, `git_commit a6dd902`.
- result / knowledge / claim-transition rows are **candidates only**, staged at
  `results/ktg/paper_1902.10565/evidence/tiny_smoke/candidate_rows.json` for an independent
  validator. The worker appended none of them.
- The knowledge row is proposed `preliminary`, not `solid`, for a mechanical reason: the
  admission gate requires solid predecessors and `select_transformer_ladder` is `preliminary`.
  Nothing about this node's own evidence is outstanding.

## Open

- `[OPEN] o15_attn_logit_export_guard` — by design. The exporter logged a data-free attention
  logit bound of **14** over 7 layers against the `2.5e4` limit, because the weights are random;
  only a trained checkpoint can approach the guard. Owner `export_stage`. `-ignore-attn-logit-bound`
  appears nowhere in `codes/`.
- `[OPEN] o08_exporter_name` — this node's files call `export_model_pytorch.py` only, but the
  obligation's literal repo-wide grep still returns one hit outside this node:
  `codes/loop/export_model_for_selfplay_9x9.sh:30`, an upstream *usage string*. That file
  invokes `./export_model_pytorch.py` at `:130`, so it is a message and not a call — but the
  test is a grep. One word in one `echo` closes it. Not edited from here: the file belongs to
  another node.
- `[OPEN] c03_tf_export_loads` — proposed `in_progress`. Every conjunct is measured except the
  one naming `selfplay_9x9.cfg`, which §13 of the task file forbids this node from using.
  Belongs to `cfg_9x9_override` / `synchronous_loop_smoke`, or `c03` gets amended.
- `[OPEN]` path conventions — the work packet named `codes/tiny_smoke/` and `evidence/tiny_smoke/`;
  the task file's §2 verification command hardcodes `codes/eval/` and its §14 names
  `evidence/export_smoke/`. Scripts went to `codes/eval/` so the §2 command runs as written;
  evidence went to `evidence/tiny_smoke/` per the packet. The scheduler should pick one.
