# PROVENANCE — ref-paper/arxiv-1902.10565

| field | value |
|---|---|
| paper | arXiv:1902.10565 — *Accelerating Self-Play Learning in Go* |
| author | David J. Wu (Jane Street Group) |
| source URL | https://arxiv.org/src/1902.10565 |
| retrieved (UTC) | 2026-09-04T01:34:19Z |
| downloaded archive | `1902.10565.src` |
| archive sha256 | `71a0e8946078158c7d63bff54514051bfb832d74c403a3b93dfaa2d3c8fa6c4e` |
| archive type | gzip → POSIX tar (GNU), original size 1034240 B |
| tex present | yes — full LaTeX source, no OCR / VLM recovery needed |
| mirror path | `ref-paper/arxiv-1902.10565/` |

## Exact retrieval commands

```bash
mkdir -p ref-paper/arxiv-1902.10565
cd ref-paper/arxiv-1902.10565
curl -L https://arxiv.org/src/1902.10565 -o 1902.10565.src
file 1902.10565.src
sha256sum 1902.10565.src
gzip -dc 1902.10565.src > 1902.10565.tar
tar -tf 1902.10565.tar
mkdir -p src && tar -xf 1902.10565.tar -C src && rm -f 1902.10565.tar
```

## Verbatim verification output

```
$ file 1902.10565.src
1902.10565.src: gzip compressed data, last modified: Tue Nov 10 01:43:59 2020, from Unix, original size modulo 2^32 1034240

$ sha256sum 1902.10565.src
71a0e8946078158c7d63bff54514051bfb832d74c403a3b93dfaa2d3c8fa6c4e  1902.10565.src

$ gzip -dc 1902.10565.src | file -
/dev/stdin: POSIX tar archive (GNU)
```

## Extracted files (`src/`)

| file | bytes | role |
|---|---|---|
| `Accelerating_Self_Play_Learning_In_Go_2020.tex` | 70865 | main LaTeX source (2020 revision) |
| `Accelerating_Self_Play_Learning_In_Go_2020.bib` | 8058 | bibliography source |
| `Accelerating_Self_Play_Learning_In_Go_2020.bbl` | 4840 | compiled bibliography |
| `ablate1.png` | 34060 | ablation figure |
| `ablate2.png` | 39667 | ablation figure |
| `ablate3.png` | 47935 | ablation figure |
| `gpool.png` | 60536 | global pooling figure |
| `logpolicy1.png` | 223238 | policy-target figure |
| `logpolicy2.png` | 222334 | policy-target figure |
| `ownership.png` | 256229 | ownership-target figure |
| `scoreutility.png` | 14222 | score-utility figure |
| `vslz.png` | 39178 | strength-vs-Leela-Zero figure |

12 files total. No PDF-only fallback was needed.

## Discipline

Read-only mirror (alignment kernel §4). Nothing here is edited in place; derived
notes go under `results/ktg/paper_1902.10565/`. This directory is gitignored
(`.gitignore:2`) and is never committed.
