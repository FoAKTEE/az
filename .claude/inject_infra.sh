#!/usr/bin/env bash
# az consumer-repo adapter: the Chandra kernel lives in the nested
# phys-agentic-loop/ clone, whose inject_infra.sh resolves paths via
# `git rev-parse --show-toplevel` — so run it from inside that tree.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE/phys-agentic-loop" 2>/dev/null || { printf '(phys-agentic-loop/ missing — kernel not injected)\n'; exit 0; }
bash .claude/inject_infra.sh
printf '\n<consumer-repo-context>\nrepo=az  mission prompt: progress/prompt/ktg-train.md  cluster: docs/cluster-manual.md  skills: cluster-job, compute-budget\n</consumer-repo-context>\n'
