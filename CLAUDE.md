# OS Migration Pipeline — Claude Context

## What this repo is
Reusable extraction + BRD generation pipeline for migrating **OutSystems 11 → Mendix**.
Takes OS eSpace XML files → JSON knowledge base → BRD scaffolds per module → HTML report.

## Working directory
Always run pipeline commands from `pipeline/`:
```bash
cd pipeline
node run.js 2 xml       # Phase 2: extract all XML → knowledge-base/*.json
node run.js 3           # Phase 3: BRD scaffolds → knowledge-base/brd/*.brd.json
node generate-report.js # Report  → knowledge-base/extraction-report.html
```

## Source paths
Configured in `pipeline/config.json`. Set `blueprintDir` to the folder containing OS XML files before running.

## Output location
`pipeline/knowledge-base/` — gitignored, generated fresh each run. Never edit files here manually.

## Key folders
- `pipeline/extractors/` — source parsers (xml-extractor.js is the active one)
- `pipeline/generators/brd-mappers/` — 5 mappers: domain-entity, microflow, page, use-case, integration
- `pipeline/lib/` — merger, linker, key-resolver
- `pipeline/generate-report.js` — HTML report generator
- `pipeline-guide.html` — open in browser for full interactive pipeline walkthrough

## OS → Mendix concept mapping
| OS | Mendix |
|---|---|
| Server Action | Microflow |
| Client/Screen Action | Nanoflow |
| BPT Process | Workflow (deferred — needs business design) |
| WebScreen | Page |
| WebBlock | Building Block |
| Entity | Persistent Entity |
| Static Entity | Enumeration |
| Structure | Non-persistent Entity |
| ServiceAction | Published REST |
| Timer | Scheduled Event |

## Known gap noise (suppress these — not real issues)
- `no-db-table-found` — fires on all entities when no DB source provided; irrelevant for Mendix migration
- `fk-unresolved:User` → maps to `Administration.Account`
- `fk-unresolved:Group` / `fk-unresolved:Role` → maps to `Administration.UserRole`
- `fk-unresolved:Espace` → no Mendix equivalent, ignore

## What is NOT in scope yet
- Mendix Workflow mapping (BPT processes flagged but deferred — needs business conversation first)
- MDL generation (Phase 7 — after BRD sign-off)
- CS/JS/DB extractors (stubs exist, skipped — XML covers full OS stack)

## Shared toolkit
Canonical repo: `https://github.com/MendixMau/mxcli-project-toolkit`. Local clone (this machine):
`~/Mendix/mxcli-project-toolkit`. If that path is missing or looks stale, `git clone` the repo
fresh rather than trusting an old local copy — this file previously pointed at a stale
Windows path from a different machine.

Load the relevant skill file **when the task calls for it**:

| Task | Read this file |
|------|---------------|
| Running or explaining the pipeline | `skills/migration-pipeline.md` |
| Writing or enriching a BRD | `skills/brd-generation.md` |
| Extracting Excel/Word/PDF specs | `skills/kb-generation.md` |
| Understanding OS XML structure | `skills/source-os11.md` + `skills/os-xml-schema.md` |
| Writing MDL scripts | `skills/mdl-cookbook-microflows.md` |
| Diagnosing mxcli CLI errors | `bug-logs/mxcli-bugs.md` |
| Understanding past process decisions | `process/process-learnings.md` |

## Adding new extractors or mappers
See `pipeline/extractors/README.md` and `pipeline/generators/brd-mappers/README.md`.
