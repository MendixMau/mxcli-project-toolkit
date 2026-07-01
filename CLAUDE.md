# mxcli-project-toolkit — Claude Context

## What this repo is
Shared skills, prompt templates, and learnings for **Mendix migration and development projects**.
Used across all mxcli-powered projects — OS migration, ClientB, future Java/Angular migrations.

## Key skills and when to load them
| Task | File |
|------|------|
| Running the extraction pipeline | `skills/migration-pipeline.md` |
| Writing or enriching a BRD JSON | `skills/brd-generation.md` |
| Extracting Excel/Word/PDF specs | `skills/kb-generation.md` |
| Understanding OS XML source format | `skills/source-os11.md` + `skills/os-xml-schema.md` |
| Writing MDL microflow scripts | `skills/mdl-cookbook-microflows.md` |
| Diagnosing mxcli errors | `bug-logs/mxcli-bugs.md` |

## Pipeline repo
The extraction pipeline lives at:
`https://github.com/MendixMau/os-migration-pipeline`

## Adding new skills
Create `skills/{topic}.md` with a `# Title`, `**Purpose:**`, and step-by-step guide.
Add it to the table above and commit.
