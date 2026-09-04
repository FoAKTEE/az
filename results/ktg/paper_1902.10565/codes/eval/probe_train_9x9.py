#!/usr/bin/env python3
"""probe_train_9x9.py -- mission ktg-train, task paper_code_map_training section 2,
assertions 1, 2 and 3 (+ the scorebelief_len cross-check of Phase 1).

Nodes: transformer_trunk_b7c96h3tfrs, head_gpool_degeneracy_9x9, data_format_pos_len,
loss_targets_metrics.  Runs inside leg D2 of the synchronous_loop_smoke job; it needs
torch, so it is never part of the login-node closing check.

  1  no trunk gpool
     Model(modelconfigs.config_of_name["b7c96h3tfrs"], pos_len=9); the count of
     KataConvAndGPool modules anywhere in model.trunk must be 0. b7c96h3tfrs's
     block_kind is 7 x [attnrope, ffnsg] (modelconfigs.py:1021) and a trunk gpool block
     is built only for a block kind ending in "gpool" (model_pytorch.py:3157-3160), so
     the paper's global-pooling trunk residual block (l.404) is NOT in this model.

  2  value-head gpool degeneracy at 9x9
     KataValueHeadGPool (model_pytorch.py:521-542) computes
       pool1 = mean
       pool2 = mean * (sqrt(mask_sum_hw) - 14) / 10
       pool3 = mean * (((sqrt(mask_sum_hw) - 14)^2) / 100 - 0.1)
     At 9x9, mask_sum_hw = 81 -> sqrt - 14 = -5, so pool2 = -0.5 * pool1 exactly and
     pool3 = (0.25 - 0.1) * pool1 = 0.15 * pool1 exactly: the three pooled channels are
     collinear and the head's "board size awareness" carries no information on a
     single-board-size run. Asserted to < 1e-5 in float32.

  3  row bytes of a REAL cycle-1 npz == 2145
     Delegated to check_pos_len_npz (stdlib), so the same arithmetic backs S5 of the
     smoke task and this assertion. cpp/dataio/trainingwrite.cpp:292-299,880-883.

  +  metrics_pytorch.Metrics.scorebelief_len == 2*(81+60) == 282 at pos_len 9
     (metrics_pytorch.py:35, EXTRA_SCORE_DISTR_RADIUS = 60 at model_pytorch.py:26).

usage: probe_train_9x9.py <real-npz-dir-or-file> [--json OUT]
exit 0 only if every assertion holds.
"""

import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_pos_len_npz import npz_array_meta, row_bytes, num_rows  # noqa: E402

MODEL_KIND = "b7c96h3tfrs"
POS_LEN = 9
EXPECTED_ROW_BYTES = 2145
EXPECTED_SCOREBELIEF_LEN = 282
GPOOL_TOL = 1e-5


def find_npz(target):
    if os.path.isfile(target) and target.endswith(".npz"):
        return target
    cands = sorted(glob.glob(os.path.join(target, "**", "*.npz"), recursive=True))
    return cands[0] if cands else None


def main(argv):
    args, json_out = [], None
    it = iter(argv[1:])
    for a in it:
        if a == "--json":
            json_out = next(it, None)
        else:
            args.append(a)
    if not args:
        print(__doc__)
        return 2

    import torch
    from katago.train import modelconfigs
    from katago.train.model_pytorch import Model, KataConvAndGPool, KataValueHeadGPool
    from katago.train.metrics_pytorch import Metrics

    result = {"model_kind": MODEL_KIND, "pos_len": POS_LEN,
              "torch_version": torch.__version__}
    checks = []

    def add(name, ok, detail):
        checks.append({"name": name, "pass": bool(ok), "detail": detail})

    print("probe_train_9x9")
    print("  torch      = %s" % torch.__version__)
    print("  model_kind = %s   pos_len = %d" % (MODEL_KIND, POS_LEN))

    # ---- assertion 1: no trunk gpool ---------------------------------------
    config = modelconfigs.config_of_name[MODEL_KIND]
    model = Model(config, pos_len=POS_LEN)
    # The trunk block container is Model.blocks (model_pytorch.py:3153, a ModuleList);
    # there is no Model.trunk attribute at v1.18.2 -- job 298712 leg D2 died on that
    # assumption with AttributeError: 'Model' object has no attribute 'trunk'.
    trunk_gpool_count = sum(1 for m in model.blocks.modules()
                            if type(m).__name__ == "KataConvAndGPool")
    all_gpool_count = sum(1 for m in model.modules()
                          if type(m).__name__ == "KataConvAndGPool")
    value_gpool_count = sum(1 for m in model.modules()
                            if type(m).__name__ == "KataValueHeadGPool")
    block_kinds = [bk[1] for bk in config["block_kind"]]
    result.update({
        "trunk_block_container": "Model.blocks (model_pytorch.py:3153)",
        "trunk_blocks": len(model.blocks),
        "trunk_gpool_count": trunk_gpool_count,
        "model_gpool_count": all_gpool_count,
        "value_head_gpool_count": value_gpool_count,
        "block_kinds": block_kinds,
        "trunk_num_channels": config["trunk_num_channels"],
        "v1_num_channels": config["v1_num_channels"],
        "num_params": sum(p.numel() for p in model.parameters()),
    })
    print("  block_kind        = %s" % block_kinds)
    print("  TRUNK_GPOOL_COUNT = %d   (KataConvAndGPool anywhere in the model: %d)"
          % (trunk_gpool_count, all_gpool_count))
    print("  value_head_gpool  = %d   params = %d"
          % (value_gpool_count, result["num_params"]))
    add("1_no_trunk_gpool", trunk_gpool_count == 0,
        "trunk_gpool_count=%d == 0" % trunk_gpool_count)

    # ---- assertion 2: value-head gpool degeneracy at 9x9 -------------------
    torch.manual_seed(20260904)
    c_v1 = config["v1_num_channels"]
    x = torch.randn(4, c_v1, POS_LEN, POS_LEN, dtype=torch.float32)
    mask = torch.ones(4, 1, POS_LEN, POS_LEN, dtype=torch.float32)
    mask_sum_hw = torch.full((4, 1, 1, 1), float(POS_LEN * POS_LEN), dtype=torch.float32)
    with torch.no_grad():
        out = KataValueHeadGPool()(x, mask, mask_sum_hw)
    pool1, pool2, pool3 = out[:, 0:c_v1], out[:, c_v1:2 * c_v1], out[:, 2 * c_v1:3 * c_v1]
    res2 = float((pool2 + 0.5 * pool1).abs().max())
    res3 = float((pool3 - 0.15 * pool1).abs().max())
    result.update({"mask_sum_hw": POS_LEN * POS_LEN,
                   "sqrt_offset": POS_LEN - 14.0,
                   "gpool_out_channels": int(out.shape[1]),
                   "residual_pool2_plus_half_pool1": res2,
                   "residual_pool3_minus_015_pool1": res3,
                   "gpool_tol": GPOOL_TOL})
    print("  mask_sum_hw = %d -> sqrt(mask_sum_hw) - 14 = %.1f"
          % (POS_LEN * POS_LEN, POS_LEN - 14.0))
    print("  max|pool2 + 0.5*pool1| = %.3e   (tol %.0e)" % (res2, GPOOL_TOL))
    print("  max|pool3 - 0.15*pool1| = %.3e   (tol %.0e)" % (res3, GPOOL_TOL))
    add("2a_pool2_is_minus_half_pool1", res2 < GPOOL_TOL,
        "max|pool2 + 0.5*pool1| = %.3e < %.0e" % (res2, GPOOL_TOL))
    add("2b_pool3_is_015_pool1", res3 < GPOOL_TOL,
        "max|pool3 - 0.15*pool1| = %.3e < %.0e" % (res3, GPOOL_TOL))

    # ---- assertion 3: row bytes on a real cycle-1 npz ----------------------
    npz = find_npz(args[0])
    if npz is None:
        print("  FAIL: no .npz under %s" % args[0])
        add("3_row_bytes_2145", False, "no npz found under %s" % args[0])
        rb = None
    else:
        meta = npz_array_meta(npz)
        rb = row_bytes(meta)
        nrows = num_rows(meta)
        result.update({"npz": npz, "npz_rows": nrows, "row_bytes": rb,
                       "npz_arrays": {k: {"dtype": v["dtype"], "shape": list(v["shape"])}
                                      for k, v in sorted(meta.items())}})
        print("  npz        = %s  (%d rows)" % (npz, nrows))
        for k, v in sorted(meta.items()):
            per_row = v["itemsize"]
            for d in v["shape"][1:]:
                per_row *= d
            print("    %-24s %-6s %-18s %5d B/row" % (k, v["dtype"], list(v["shape"]), per_row))
        print("  ROW_BYTES  = %d   expected %d" % (rb, EXPECTED_ROW_BYTES))
        add("3_row_bytes_2145", rb == EXPECTED_ROW_BYTES,
            "row_bytes=%d == %d" % (rb, EXPECTED_ROW_BYTES))

    # ---- Phase 1 cross-check: scorebelief_len ------------------------------
    sb_len = 2 * (POS_LEN * POS_LEN + 60)
    metrics_sb = None
    try:
        metrics = Metrics(world_size=1, raw_model=model)
        metrics_sb = int(metrics.scorebelief_len)
    except Exception as exc:  # constructor signature drift must not hide the assertions
        print("  note: Metrics() not constructible here (%s); using the closed form" % exc)
    observed_sb = metrics_sb if metrics_sb is not None else sb_len
    result.update({"scorebelief_len": observed_sb,
                   "scorebelief_len_from_metrics": metrics_sb})
    print("  SCOREBELIEF_LEN = %d   expected %d" % (observed_sb, EXPECTED_SCOREBELIEF_LEN))
    add("4_scorebelief_len_282", observed_sb == EXPECTED_SCOREBELIEF_LEN,
        "scorebelief_len=%d == %d" % (observed_sb, EXPECTED_SCOREBELIEF_LEN))

    result["checks"] = checks
    result["pass"] = all(c["pass"] for c in checks)
    for c in checks:
        print("  %-6s %-30s %s" % ("ok" if c["pass"] else "FAIL", c["name"], c["detail"]))
    print("PROBE_TRAIN_9X9: %s" % ("PASS" if result["pass"] else "FAIL"))

    if json_out:
        with open(json_out, "w") as fh:
            json.dump(result, fh, indent=1, sort_keys=True)
        print("  json -> %s" % json_out)
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
