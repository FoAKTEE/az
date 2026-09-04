#!/usr/bin/env python3
"""freeze_baseline.py -- mission ktg-train, node arxiv-1902.10565::bootstrap_accepted_model.

P6 of tasks/production_chain_9x9:

    python3 codes/eval/freeze_baseline.py $P1

then the ledger closing check reads the manifest's sha256 of
models/<first>/model.bin.gz. Tolerance: "exact; written the first time models/ is
non-empty, never rewritten".

WHAT "FIRST" MEANS
$BASEDIR/models/ holds the nets the gatekeeper ACCEPTED, named
<trainingname>-s<global_step_samples>-d<total_num_data_rows> (export_model_pytorch.py's
naming, carried through export_model_for_selfplay_9x9.sh). The s-number is a strictly
increasing training counter, so the first accepted net is the one with the smallest
s-number; the directory mtime is recorded alongside it as a cross-check and is used only
when no name parses. The frozen net is the fixed opponent of the P11 match, so it must
be pinned by CONTENT, not by path: the manifest carries the sha256 of model.bin.gz.

WRITE-ONCE
A monitoring pass runs this at every status. Re-running it is therefore a no-op:
  * models/ empty            -> nothing frozen, exit 0 ("not frozen yet" is the normal
                               state before the first acceptance; --require makes it fatal)
  * manifest already present -> the recorded net is re-verified against the file on disk
                               and the manifest is NOT rewritten. A mismatch of the
                               recorded name is a hard error (the baseline the match and
                               the declaration are written against would have moved);
                               --force is the only way past it and is recorded on the
                               manifest as a rewrite.
  * a content mismatch on the SAME name is a hard error too: the frozen file changed
    underneath the frozen hash.

The manifest lives in the EVAL directory ($KTG_ROOT/eval by default -- the directory
declare.py reads), not inside BASEDIR, so nothing the loop owns is ever written by a
monitoring read.

usage:
  freeze_baseline.py <BASEDIR> [--eval-dir DIR] [--manifest FILE] [--require] [--force]
                     [--quiet]
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import sys

NAME_RE = re.compile(r"-s(\d+)-d(\d+)$")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def accepted_nets(models_dir):
    """[(sort_key, name, path)] for every accepted net directory holding a model.bin.gz."""
    out = []
    if not os.path.isdir(models_dir):
        return out
    for name in sorted(os.listdir(models_dir)):
        d = os.path.join(models_dir, name)
        bin_gz = os.path.join(d, "model.bin.gz")
        if not os.path.isdir(d) or not os.path.exists(bin_gz):
            continue
        m = NAME_RE.search(name)
        if m:
            key = (0, int(m.group(1)), name)
        else:
            key = (1, int(os.path.getmtime(d)), name)
        out.append((key, name, d))
    out.sort(key=lambda t: t[0])
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("basedir")
    ap.add_argument("--eval-dir", default=None,
                    help="where manifest.json lives (default: <KTG_ROOT>/eval, i.e. the "
                         "sibling 'eval' of the BASEDIR's parent 'runs' directory)")
    ap.add_argument("--manifest", default=None)
    ap.add_argument("--require", action="store_true",
                    help="exit non-zero when models/ is still empty")
    ap.add_argument("--force", action="store_true",
                    help="rewrite an existing manifest (recorded as a rewrite)")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)

    basedir = a.basedir.rstrip("/")
    if not os.path.isdir(basedir):
        print("freeze_baseline: BASEDIR does not exist: %s" % basedir, file=sys.stderr)
        return 2

    eval_dir = a.eval_dir or os.environ.get("KTG_EVAL_DIR")
    if not eval_dir:
        # $KTG_ROOT/runs/<run> -> $KTG_ROOT/eval
        eval_dir = os.path.join(os.path.dirname(os.path.dirname(basedir)), "eval")
    manifest_path = a.manifest or os.path.join(eval_dir, "manifest.json")

    models_dir = os.path.join(basedir, "models")
    nets = accepted_nets(models_dir)

    print("freeze_baseline -- node arxiv-1902.10565::bootstrap_accepted_model")
    print("basedir  : %s" % basedir)
    print("models/  : %s (%d accepted net(s) with a model.bin.gz)" % (models_dir, len(nets)))
    for (_k, name, _d) in nets:
        print("           %s" % name)
    print("manifest : %s" % manifest_path)

    existing = None
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path) as fh:
                existing = json.load(fh)
        except Exception as exc:                    # noqa: BLE001
            print("freeze_baseline: manifest exists but is unreadable (%s) -- refusing to "
                  "overwrite it; move it aside deliberately if it is corrupt" % exc)
            return 1

    if not nets:
        print("")
        print("NOT FROZEN: models/ is empty -- no candidate has been accepted yet.")
        print("P6 writes the manifest the FIRST time models/ is non-empty, so this is the")
        print("normal state before the first acceptance (expected around cycle 6).")
        if existing is not None:
            print("WARNING: a manifest already records %r but models/ no longer holds it."
                  % existing.get("first_model"))
            return 1
        return 1 if a.require else 0

    key, name, path = nets[0]
    bin_gz = os.path.join(path, "model.bin.gz")
    digest = sha256(bin_gz)
    meta_path = os.path.join(path, "metadata.json")
    meta = {}
    if os.path.exists(meta_path):
        try:
            with open(meta_path) as fh:
                meta = json.load(fh)
        except Exception:
            meta = {}

    record = {
        "node": "arxiv-1902.10565::bootstrap_accepted_model",
        "task_id": "production_chain_9x9",
        "basedir": basedir,
        "first_model": name,
        "first_model_path": bin_gz,
        "first_model_sha256": digest,
        "first_model_bytes": os.path.getsize(bin_gz),
        "first_model_global_step_samples": meta.get("global_step_samples"),
        "first_model_total_num_data_rows": meta.get("total_num_data_rows"),
        "selection_rule": ("smallest s<samples> in the accepted net's name; directory "
                           "mtime only as a fallback for a name that does not parse"),
        "accepted_at_freeze_time": [n for (_k, n, _d) in nets],
        "frozen_at": datetime.datetime.now().astimezone().isoformat(),
    }

    if existing is not None and not a.force:
        prev_name = existing.get("first_model")
        prev_sha = existing.get("first_model_sha256")
        print("")
        if prev_name != name:
            print("REFUSED: the manifest froze %r, but the first accepted net is now %r."
                  % (prev_name, name))
            print("P6 says the baseline is written once and never rewritten -- the match")
            print("and the declaration are both stated against the frozen net. Escalate")
            print("with both names; --force is the only way past this and is recorded.")
            return 1
        if prev_sha != digest:
            print("REFUSED: %s still names the frozen baseline, but its model.bin.gz now"
                  % name)
            print("hashes %s, not the recorded %s." % (digest, prev_sha))
            print("The frozen file changed underneath the frozen hash. Escalate.")
            return 1
        print("ALREADY FROZEN (write-once, unchanged):")
        print("  first_model        = %s" % prev_name)
        print("  first_model_sha256 = %s" % prev_sha)
        print("  frozen_at          = %s" % existing.get("frozen_at"))
        print("  re-verified against %s" % bin_gz)
        return 0

    if existing is not None and a.force:
        record["rewrote_previous"] = {k: existing.get(k) for k in
                                      ("first_model", "first_model_sha256", "frozen_at")}
        record["rewritten_at"] = record["frozen_at"]

    os.makedirs(os.path.dirname(os.path.abspath(manifest_path)), exist_ok=True)
    with open(manifest_path, "w") as fh:
        json.dump(record, fh, indent=1, sort_keys=True)
    print("")
    print("FROZEN%s:" % (" (FORCED REWRITE)" if (existing is not None and a.force) else ""))
    print("  first_model        = %s" % record["first_model"])
    print("  first_model_sha256 = %s" % record["first_model_sha256"])
    print("  bytes              = %s" % record["first_model_bytes"])
    print("  global_step_samples= %s" % record["first_model_global_step_samples"])
    print("  frozen_at          = %s" % record["frozen_at"])
    print("wrote %s" % manifest_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
