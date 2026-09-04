#!/usr/bin/env python3
"""check_pos_len_npz.py -- mission ktg-train, obligation o02_pos_len_matches_databoardlen.

Asserts that every training-data .npz written by the mission selfplay config is a
dataBoardLen = 9 row set, and reports the per-row byte cost the data-budget node needs:

    binaryInputNCHWPacked  (N, 22, 11)   uint8    22 * 11 =  242 B/row
    globalInputNC          (N, 19)       float32  19 *  4 =   76 B/row
    policyTargetsNCMove    (N,  2, 82)   int16     2*82*2 =  328 B/row
    globalTargetsNC        (N, 80)       float32  80 *  4 =  320 B/row
    scoreDistrN            (N, 282)      int8         282 =  282 B/row
    valueTargetsNCHW       (N,  5, 9, 9) int8      5*9*9  =  405 B/row
    qValueTargetsNCMove    (N,  3, 82)   int16    3*82*2  =  492 B/row
                                                   total  = 2145 B/row

(cpp/dataio/trainingwrite.cpp:292-299; qValueTargetsNCMove is written unconditionally
at :880-882, so the row is 2145 B whether or not the model kind sets predict_q_values.)

The whole module is standard library only -- no numpy, no torch -- on purpose: it is
part of the login-node-executable closing check of node synchronous_loop_smoke, and the
login node has neither. Array shapes and dtypes are read out of each member's .npy
header inside the .npz zip container (numpy format 1.0/2.0/3.0).

usage:
  check_pos_len_npz.py <npz-or-dir> [more ...]        assert and print
  check_pos_len_npz.py --json <npz-or-dir> [more ...] machine-readable summary

exit 0 only if at least one npz was found and every one of them passes.
"""

import ast
import json
import os
import struct
import sys
import zipfile

# What a pos_len = 9 row must look like. Trailing dims only; N is free.
EXPECTED_SHAPES = {
    "binaryInputNCHWPacked": (22, 11),
    "globalInputNC": (19,),
    "policyTargetsNCMove": (2, 82),
    "globalTargetsNC": (80,),
    "scoreDistrN": (282,),
    "valueTargetsNCHW": (5, 9, 9),
    "qValueTargetsNCMove": (3, 82),
}
EXPECTED_ROW_BYTES = 2145


def _read_npy_header(fh):
    """Parse a .npy header from an open binary stream; return (dtype_str, shape)."""
    magic = fh.read(6)
    if magic != b"\x93NUMPY":
        raise ValueError("not a .npy member (bad magic %r)" % (magic,))
    major, _minor = struct.unpack("<BB", fh.read(2))
    if major == 1:
        (hlen,) = struct.unpack("<H", fh.read(2))
    else:
        (hlen,) = struct.unpack("<I", fh.read(4))
    header = fh.read(hlen).decode("latin1")
    d = ast.literal_eval(header.strip())
    return d["descr"], tuple(d["shape"])


def _itemsize(descr):
    """Bytes per element of a numpy dtype string such as '|u1', '<f4', '<i2'."""
    base = descr.lstrip("<>|=")
    kind, size = base[0], base[1:]
    if kind in ("u", "i", "f", "c"):
        return int(size)
    if kind == "b":
        return 1
    raise ValueError("unsupported dtype %r" % descr)


def npz_array_meta(path):
    """{array_name: {"dtype": str, "shape": tuple}} for every member of an .npz."""
    out = {}
    with zipfile.ZipFile(path) as zf:
        for name in zf.namelist():
            # KataGo's writer stores members WITHOUT the .npy suffix numpy's savez adds
            # (python/shuffle.py and cpp/dataio/trainingwrite.cpp both write bare names),
            # so accept either spelling.
            key = name[:-4] if name.endswith(".npy") else name
            with zf.open(name) as fh:
                try:
                    descr, shape = _read_npy_header(fh)
                except ValueError:
                    continue
            out[key] = {"dtype": descr, "shape": shape,
                        "itemsize": _itemsize(descr)}
    return out


def row_bytes(meta):
    """Sum over arrays of itemsize * prod(shape[1:]) -- the bytes one row occupies."""
    total = 0
    for name, m in meta.items():
        n = m["itemsize"]
        for dim in m["shape"][1:]:
            n *= dim
        total += n
    return total


def num_rows(meta):
    for name in ("binaryInputNCHWPacked", "globalInputNC"):
        if name in meta and meta[name]["shape"]:
            return int(meta[name]["shape"][0])
    return 0


def check_one(path):
    meta = npz_array_meta(path)
    problems = []
    for name, want in EXPECTED_SHAPES.items():
        if name not in meta:
            problems.append("missing array %s" % name)
            continue
        got = tuple(meta[name]["shape"][1:])
        if got != want:
            problems.append("%s trailing shape %s != %s" % (name, got, want))
    extra = sorted(set(meta) - set(EXPECTED_SHAPES))
    rb = row_bytes(meta)
    if rb != EXPECTED_ROW_BYTES:
        problems.append("row bytes %d != %d" % (rb, EXPECTED_ROW_BYTES))
    return {
        "path": path,
        "rows": num_rows(meta),
        "row_bytes": rb,
        "arrays": {k: {"dtype": v["dtype"], "shape": list(v["shape"])}
                   for k, v in sorted(meta.items())},
        "extra_arrays": extra,
        "problems": problems,
        "pass": not problems,
    }


def collect(targets):
    files = []
    for t in targets:
        if os.path.isdir(t):
            for root, _dirs, names in os.walk(t):
                for n in sorted(names):
                    if n.endswith(".npz"):
                        files.append(os.path.join(root, n))
        elif t.endswith(".npz"):
            files.append(t)
    return sorted(set(files))


def main(argv):
    as_json = False
    args = []
    for a in argv[1:]:
        if a == "--json":
            as_json = True
        else:
            args.append(a)
    if not args:
        print(__doc__)
        return 2
    files = collect(args)
    reports = [check_one(f) for f in files]
    rows = sum(r["rows"] for r in reports)
    ok = bool(reports) and all(r["pass"] for r in reports)
    summary = {
        "npz_files": len(reports),
        "total_rows": rows,
        "row_bytes_expected": EXPECTED_ROW_BYTES,
        "row_bytes_observed": sorted({r["row_bytes"] for r in reports}),
        "pass": ok,
        "reports": reports,
    }
    if as_json:
        print(json.dumps(summary, indent=1, sort_keys=True))
    else:
        print("check_pos_len_npz: %d npz file(s), %d rows" % (len(reports), rows))
        for r in reports:
            print("  %-6s rows=%-7d row_bytes=%-6d %s"
                  % ("ok" if r["pass"] else "FAIL", r["rows"], r["row_bytes"], r["path"]))
            for p in r["problems"]:
                print("        problem: %s" % p)
        if reports:
            print("  arrays of %s:" % reports[0]["path"])
            for k, v in reports[0]["arrays"].items():
                print("    %-24s %-6s %s" % (k, v["dtype"], v["shape"]))
        print("CHECK_POS_LEN_NPZ: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
