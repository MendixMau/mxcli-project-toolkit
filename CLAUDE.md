# mxcli-project-toolkit — Claude Context

## What this repo is
Shared skills, prompt templates, and learnings for **Mendix migration and development projects**.
Used across all mxcli-powered projects — OS migration, ClientB, future Java/Angular migrations.

## Key skills and when to load them

Load skill files **on demand when the task calls for it** — not all upfront.

| Task | Read this file |
|------|---------------|
| Running or explaining the pipeline | `skills/migration-pipeline.md` |
| Deciding Mendix module boundaries (Phase 6, before `create module`) | `skills/modularize-domain.md` |
| Scanning/classifying an unstructured document folder | `skills/document-discovery.md` |
| Writing or enriching a BRD JSON | `skills/brd-generation.md` |
| Validating BRDs against code + doc KB, iterating to clean | `skills/brd-validation.md` |
| Extracting Excel/Word/PDF specs | `skills/kb-generation.md` |
| Understanding OS XML structure or concepts | `skills/source-os11.md` + `skills/os-xml-schema.md` |
| Writing MDL microflow scripts | `skills/mdl-cookbook-microflows.md` |
| Diagnosing a mxcli CLI error | `bug-logs/mxcli-bugs.md` |
| Understanding past process decisions | `process/process-learnings.md` |

## Pipeline repo
The extraction pipeline lives at:
`https://github.com/MendixMau/os-migration-pipeline`

## Adding new skills
Create `skills/{topic}.md` with a `# Title`, `**Purpose:**`, and step-by-step guide.
Add it to the table above and commit.
