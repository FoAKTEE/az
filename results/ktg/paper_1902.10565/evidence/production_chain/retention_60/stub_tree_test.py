#!/usr/bin/env python3
"""Stub-tree test: does prune_retention.py behave differently at KEEP_SELFPLAY_GENERATIONS 60?

Nothing here touches runs/p1. Every tree is synthetic, built under a scratch runtime dir
with mtimes set to reproduce the geometry the real tree will have at link-3 start
(2026-09-06T17:53:21 EDT) and at link-4 start one link (23.5 h) later.

Measured rates it uses, all from logs/loop-305318.log over link 2's 79 cycles:
  cycle wall           12.21 min      (79 shuffles, 2026-09-05T18:23:27 -> 2026-09-06T10:28)
  generations per hour  1.866         (30 accepted nets over 16.075 h)
  shuffleddata dirs     bounded at "newest 3 older than 2 h" by python/selfplay/
                        cleanup_old_dirs.py, which shuffle.sh runs after EVERY shuffle,
                        so the pruner's identical rule finds nothing left to do.

Scenarios:
  A  51 generations, 13 shuffle dirs   the projected link-3 start
  B  95 generations, 13 shuffle dirs   the projected link-4 start (60 becomes binding)
  C  51 generations, mtime order != s-number order (a re-touched old generation)
  D  scenario B with --target-bytes, to show rolling mode's floors at keep 60
"""
import json, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
RT = "/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/runtime/retention_60_dryrun"
KEEP3 = os.path.join(RT, "keep3", "prune_retention.py")
KEEP60 = os.path.join(RT, "keep60", "prune_retention.py")

CYCLE_S = 12.21 * 60
GEN_S = 3600.0 / 1.866
GEN_BYTES = 79_951 * 11.2          # rows/generation x measured bytes/row, see README
NOW = time.time()


def touch(path, mtime, nbytes=4096):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(b"\0" * nbytes)
    os.utime(path, (mtime, mtime))


def build(root, n_gen, n_shuf, scramble=False):
    """A minimal runs/pN look-alike: selfplay/, shuffleddata/, models/, train/."""
    shutil.rmtree(root, ignore_errors=True)
    base = os.path.join(root, "p")
    names = []
    for i in range(n_gen):
        s = 143744 + (i + 1) * 300000
        names.append("t9-s%d-d%d" % (s, s // 10))
    # mtimes: newest generation "now", one every GEN_S back
    mtimes = [NOW - (n_gen - 1 - i) * GEN_S for i in range(n_gen)]
    if scramble:
        # one old generation re-touched to a recent mtime, as a mid-cycle write would do
        mtimes[3] = NOW - 0.5 * GEN_S
    for name, mt in zip(names, mtimes):
        d = os.path.join(base, "selfplay", name)
        touch(os.path.join(d, "tdata", "aa.npz"), mt, 8192)
        touch(os.path.join(d, "sgfs", "aa.sgfs"), mt, 8192)
        os.utime(os.path.join(d, "tdata"), (mt, mt))
        os.utime(os.path.join(d, "sgfs"), (mt, mt))
        os.utime(d, (mt, mt))
    for i in range(n_shuf):
        mt = NOW - (n_shuf - 1 - i) * CYCLE_S
        d = os.path.join(base, "shuffleddata", time.strftime("%Y%m%d-%H%M%S", time.localtime(mt)))
        touch(os.path.join(d, "train", "d.npz"), mt, 16384)
        os.utime(os.path.join(d, "train"), (mt, mt))
        os.utime(d, (mt, mt))
    for i, name in enumerate((names[0], names[-1])):
        d = os.path.join(base, "models", name)
        touch(os.path.join(d, "model.bin.gz"), NOW - (1 - i) * 10000, 1024)
    for ck in ("checkpoint.ckpt", "checkpoint_prev0.ckpt"):
        touch(os.path.join(base, "train", "t9", ck), NOW, 1024)
    touch(os.path.join(base, "train", "t9", "longterm_checkpoints", "c1.ckpt"), NOW, 1024)
    return base, names


def run(script, base, root, extra=()):
    cmd = [sys.executable, script, "--root", root, "--basedir", base,
           "--json", os.path.join(root, os.path.basename(os.path.dirname(script)) + ".json")]
    cmd += list(extra)
    p = subprocess.run(cmd, capture_output=True, text=True)
    plan = json.load(open(cmd[cmd.index("--json") + 1]))
    return p, plan


def sp(plan):
    return [os.path.basename(e["path"]) for e in plan["plan"] if "/selfplay/" in e["path"]]


def sh(plan):
    return [os.path.basename(e["path"]) for e in plan["plan"] if "/shuffleddata/" in e["path"]]


def scenario(tag, n_gen, n_shuf, scramble=False, extra=()):
    root = os.path.join(RT, "stub_" + tag)
    base, names = build(root, n_gen, n_shuf, scramble)
    print("=" * 78)
    print("SCENARIO %s: %d selfplay generations, %d shuffleddata dirs%s%s"
          % (tag, n_gen, n_shuf, ", mtime order scrambled" if scramble else "",
             (", extra args " + " ".join(extra)) if extra else ""))
    print("=" * 78)
    out = {}
    for label, script in (("keep3", KEEP3), ("keep60", KEEP60)):
        p, plan = run(script, base, root, extra)
        gens, shufs = sp(plan), sh(plan)
        out[label] = (gens, shufs, plan["plan_bytes"], p.returncode)
        print("  %-6s exit=%d  plan=%d paths %d B   selfplay=%d  shuffleddata=%d"
              % (label, p.returncode, len(plan["plan"]), plan["plan_bytes"], len(gens), len(shufs)))
        if gens:
            print("         selfplay deleted: %s ... %s" % (gens[0], gens[-1]))
        if p.stderr.strip():
            print("         stderr: " + " ".join(p.stderr.split())[:200])
        n_prot = sum(1 for _ in plan["protected"])
        print("         protected entries: %d" % n_prot)
        prot_kinds = sorted({e["reason"].split("(")[0].strip() for e in plan["protected"]})
        print("         protected kinds  : %s" % "; ".join(prot_kinds))
    g3, g60 = out["keep3"][0], out["keep60"][0]
    s3, s60 = out["keep3"][1], out["keep60"][1]
    print("  DELTA  selfplay deleted 3 -> 60 : %d -> %d   (generations spared by 60: %d)"
          % (len(g3), len(g60), len(g3) - len(g60)))
    print("  DELTA  shuffleddata deleted     : %d -> %d   (%s)"
          % (len(s3), len(s60), "identical" if s3 == s60 else "DIFFERENT"))
    print("  DELTA  survivors on disk        : %d -> %d generations"
          % (n_gen - len(g3), n_gen - len(g60)))
    print()
    return out


if __name__ == "__main__":
    print("stub_tree_test  %s" % time.strftime("%Y-%m-%dT%H:%M:%S%z"))
    print("prune_retention.py sha256 identical in both trees; only budget.env:55 differs.")
    print("GEN_S = %.1f s between generations; CYCLE_S = %.1f s between shuffle dirs.\n"
          % (GEN_S, CYCLE_S))
    scenario("A_link3", 51, 13)
    scenario("B_link4", 95, 13)
    scenario("C_scramble", 51, 13, scramble=True)
    scenario("D_rolling", 95, 13, extra=("--target-bytes", "1000000"))
    print("done.")
