# mxcli-project-toolkit — Claude Context

## What this repo is
Shared skills, prompt templates, and learnings for **Mendix migration and development projects**.
Used across all mxcli-powered projects — OS migrations, Java/Angular migrations, and other client integration work.

## Key skills and when to load them

Load skill files **on demand when the task calls for it** — not all upfront.

| Task | Read this file |
|------|---------------|
| Deciding whether to extract at all, checking extractor/mapper coverage, scoping a large source | `skills/source-triage.md` |
| Running or explaining the pipeline | `skills/migration-pipeline.md` |
| Deciding Mendix module boundaries (Phase 6, before `create module`) | `skills/modularize-domain.md` |
| Scanning/classifying an unstructured document folder | `skills/document-discovery.md` |
| Writing or enriching a BRD JSON | `skills/brd-generation.md` |
| Validating BRDs against code + doc KB, iterating to clean | `skills/brd-validation.md` |
| Extracting Excel/Word/PDF specs | `skills/kb-generation.md` |
| Understanding OS XML structure or concepts | `skills/source-os11.md` + `skills/os-xml-schema.md` |
| Writing MDL microflow scripts | `skills/mdl-cookbook-microflows.md` |
| Assessing a migration up front | `skills/assess-migration.md` |
| Generic (source-agnostic) migration guidance | `skills/migrate-general.md` |
| Migrating an OutSystems app | `skills/migrate-outsystems.md` |
| Diagnosing a mxcli CLI error | `bug-logs/mxcli-bugs.md` |
| Understanding past process decisions | `process/process-learnings.md` |
| Setting up dev-process subagents (draft/gate/test) on a new project | `skills/agent-roles.md` |

## Pipelines (extraction tooling — code lives in this repo)
The source-specific extraction pipelines now live **in this repo** under `pipelines/`:

| Source platform | Pipeline | Run |
|-----------------|----------|-----|
| OutSystems | `pipelines/outsystems/` (imported with history from the former `os-migration-pipeline` repo) | `cd pipelines/outsystems/pipeline && npm install` — see its `README.md` / `pipeline-guide.html` |
| Java + Angular / Spring Boot | `pipelines/java-angular/` | `cd pipelines/java-angular/pipeline && npm install` — see its `README.md` |

`node_modules/` is gitignored — run `npm install` locally per pipeline. Curated sample outputs live under each pipeline (e.g. `pipelines/outsystems/sample-outputs/`).

## Consuming this toolkit (reference model)
Clone once to a standard location and point projects at it:
```
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
```
Each project's CLAUDE.md references `~/Mendix/mxcli-project-toolkit` — one clone, no copies, no drift. For a self-contained handoff, add it as a git submodule instead.

**Project output never lives here** — `analysis/`, `sources/`, `knowledge-base/`, `*.mpr` are gitignored. Each migration runs in its own workspace that *references* this repo.

**A project's build plan and session notes live in that project's own repo, never here.** This is tools + skills + curated examples only — not a place to accumulate one project's architecture docs, numbered build plan, or running session diary. Promote a reusable pattern out of a project's own notes into `skills/learned-*.md` instead of leaving the whole plan here.

## Adding new skills
Create `skills/{topic}.md` with a `# Title`, `**Purpose:**`, and step-by-step guide.
Add it to the table above and commit. **If the skill applies on every MDL-writing session regardless of task** (universal discipline, not a phase-specific procedure), also add it to `README.md`'s "Baseline routing" table — that's the list consuming projects are told to copy into their own `CLAUDE.md`. A skill that only lives in the situational table here can go unnoticed by every project that isn't actively hunting for it.
