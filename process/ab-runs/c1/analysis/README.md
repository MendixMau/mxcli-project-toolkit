# analysis/

Generated analysis output and every customer-showable surface the pipeline renders. Unlike
`../sources/`, nothing here is hand-authored — each file has a script or skill that produces it,
and the honest way to change one is to re-run its producer.

| File | Produced by | Stage |
|---|---|---|
| `source-sufficiency.html` | `bin/source-sufficiency.sh report` | 0 |
| `triage.html` | `bin/triage-report.sh <project>` | 0 |
| `extraction-report.html` | the extraction pipeline, or `kb-generation.md` for a document corpus | 1 |
| `brd-report.html` | `bin/brd-report.sh <project>` | 2 |
| `open-questions.html` | `bin/questions-report.sh <project> --stage N` | any gate |

**This folder exists in every entry mode.** A requirements-driven or greenfield project runs no
extraction pipeline, but it still produces a sufficiency grade, a scope decision and a BRD report
— `bin/brd-report.sh` reads BRDs, not source, so the Stage 2 surface is the same page whatever
wrote the BRDs.

**Where the knowledge base goes:** under `analysis/<source-name>/knowledge-base/`, not at the top
level, so a project with two source systems keeps them apart. `bin/lib/discover-brds.sh` is the
one thing that resolves that path — never hardcode it.
