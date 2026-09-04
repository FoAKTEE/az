# PROVENANCE — ref-code/lightvector-KataGo

| field | value |
|---|---|
| source URL | https://github.com/lightvector/KataGo.git |
| upstream project | KataGo (David J. Wu / lightvector) |
| tag | `v1.18.2` |
| commit SHA | `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4` |
| expected SHA (mission.json) | `fd0723fdbc0e9d82cf269c9630af8c27c57c07c4` |
| SHA match | yes |
| retrieved (UTC) | 2026-09-04T01:34:19Z |
| mirror path | `ref-code/lightvector-KataGo/` |
| license | MIT (upstream `LICENSE`) |

## Exact retrieval commands

```bash
cd ref-code
git clone https://github.com/lightvector/KataGo.git lightvector-KataGo
cd lightvector-KataGo
git checkout tags/v1.18.2
git rev-parse HEAD
```

## Verbatim verification output

```
$ git rev-parse HEAD
fd0723fdbc0e9d82cf269c9630af8c27c57c07c4

$ git describe --tags
v1.18.2

$ git rev-list -n 1 v1.18.2
fd0723fdbc0e9d82cf269c9630af8c27c57c07c4

$ git status --short
(empty — clean working tree, no local modifications)
```

## Discipline

Read-only mirror (alignment kernel §4). Nothing in this tree is edited in place.
Commentary, patches, and derived configs live under `results/ktg/` or the mission
runtime at `/scratch/schmidt/ssci-anima/ssci-haiyangw/ktg-train/`.
This directory is gitignored (`.gitignore:1`) and is never committed.
