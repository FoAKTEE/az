#!/usr/bin/env python3
"""Block-kind histogram over a KataGo-exported ``model.bin`` (node
``arxiv-1902.10565::tiny_model_export_smoke``).

``python/export_model_pytorch.py::write_block`` emits, for every trunk block, a
standalone ASCII line naming the block kind, drawn from a closed set:

    ordinary_block | gpool_block | nested_bottleneck_block
    transformer_attention_block | transformer_ffn_block

Anything else hits ``assert False`` in the exporter, and the C++ reader
(``cpp/neuralnet/desc.cpp``) throws ``found unknown block kind``.

``model.bin`` is ASCII text interleaved with ``@BIN@``-prefixed little-endian
float32 blobs, so the kind lines are located by a MULTILINE byte regex rather
than by a full structural parse.  A stray match inside a float blob would need
an exact 20+ byte ASCII sequence bounded by newlines, so two independent
structural witnesses are checked as well:

  * the trunk header declares its block count (``write_trunk`` writes
    ``len(model.blocks)`` right after the literal ``trunk``), and
  * each attention block writes a ``<name>.q_proj`` matmul and each FFN block a
    ``<name>.ffn_linear1`` matmul, giving per-kind counts derived from a
    completely different part of the record.

The check fails unless the histogram matches the expectation EXACTLY -- the
expected kinds at the expected counts, and no other kind present at all.

Usage:
    check_export_blocks.py <path/to/model.bin> [--expect KIND=N,KIND=N]

Default expectation is the ``b7c96h3tfrs`` trunk
(``python/katago/train/modelconfigs.py``: ``block_kind = 7 x [attnrope, ffnsg]``):
``transformer_attention_block=7, transformer_ffn_block=7``.
"""

import argparse
import json
import re
import sys

# Closed set, in the order write_block tests them.
BLOCK_KINDS = (
    "ordinary_block",
    "gpool_block",
    "nested_bottleneck_block",
    "transformer_attention_block",
    "transformer_ffn_block",
)

DEFAULT_EXPECT = {
    "transformer_attention_block": 7,
    "transformer_ffn_block": 7,
}

# Blocks that recurse into sub-blocks, so top-level kind lines outnumber the
# count declared in the trunk header.
NESTING_KINDS = ("nested_bottleneck_block",)

# Independent witness: a matmul name that every block of a kind writes exactly once.
WITNESS = {
    "transformer_attention_block": rb"^[A-Za-z0-9_.]+\.q_proj$",
    "transformer_ffn_block": rb"^[A-Za-z0-9_.]+\.ffn_linear1$",
}


def parse_expect(spec):
    expect = {}
    for piece in spec.split(","):
        piece = piece.strip()
        if not piece:
            continue
        kind, _, count = piece.partition("=")
        kind = kind.strip()
        if kind not in BLOCK_KINDS:
            raise SystemExit("unknown block kind in --expect: %s" % kind)
        expect[kind] = int(count)
    return expect


def main():
    ap = argparse.ArgumentParser(description="Exact block-kind histogram over an exported model.bin")
    ap.add_argument("model_bin", help="path to the uncompressed exported model.bin")
    ap.add_argument(
        "--expect",
        default=None,
        help="comma-separated KIND=COUNT expectation (default: transformer_attention_block=7,transformer_ffn_block=7)",
    )
    args = ap.parse_args()

    expect = DEFAULT_EXPECT if args.expect is None else parse_expect(args.expect)

    with open(args.model_bin, "rb") as f:
        blob = f.read()

    hist = {}
    for kind in BLOCK_KINDS:
        n = len(re.findall(rb"^" + re.escape(kind.encode("ascii")) + rb"$", blob, re.M))
        if n:
            hist[kind] = n

    print("model.bin       : %s (%d bytes)" % (args.model_bin, len(blob)))
    print("block histogram : %s" % json.dumps(hist, sort_keys=True))
    print("expected        : %s" % json.dumps(expect, sort_keys=True))

    failures = []

    if hist != expect:
        failures.append("histogram %s != expected %s" % (json.dumps(hist, sort_keys=True), json.dumps(expect, sort_keys=True)))

    # Witness 1 -- the trunk header's own declared block count.
    m = re.search(rb"^trunk\n(\d+)$", blob, re.M)
    if m is None:
        failures.append("no 'trunk' header with a block count found")
        declared = None
    else:
        declared = int(m.group(1))
        total = sum(hist.values())
        nested = any(hist.get(k, 0) for k in NESTING_KINDS)
        print("trunk declares  : %d blocks; kind lines found: %d%s"
              % (declared, total, " (nesting present, equality not required)" if nested else ""))
        if not nested and total != declared:
            failures.append("trunk declares %d blocks but %d block-kind lines were found" % (declared, total))

    # Witness 2 -- per-kind matmul names written by that kind and nothing else.
    for kind, pattern in WITNESS.items():
        n = len(re.findall(pattern, blob, re.M))
        got = hist.get(kind, 0)
        print("witness         : %-28s %d (kind lines: %d)" % (pattern.decode("ascii"), n, got))
        if n != got:
            failures.append("witness count %d for %s disagrees with %d kind lines" % (n, kind, got))

    for kind in hist:
        if kind not in expect:
            failures.append("unexpected block kind present: %s" % kind)

    if failures:
        for msg in failures:
            print("FAIL: %s" % msg)
        print("BLOCK_HISTOGRAM: FAIL")
        return 1

    print("BLOCK_HISTOGRAM: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
