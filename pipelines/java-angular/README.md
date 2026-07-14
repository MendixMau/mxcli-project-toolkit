# Java/Angular Migration Skills — Extraction Pipeline

Reusable engine for migrating **Java/Spring Boot + Angular applications to Mendix**.

Takes Java source (`@Entity`/`@RestController`/`@Service`) + Angular source (components,
routes, dialogs) → structured JSON knowledge base → BRD scaffolds per module → enrichment →
two HTML reports.

Sibling to `os-migration-pipeline` (OutSystems 11 → Mendix) — see
`mxcli-project-toolkit/skills/migration-pipeline.md` for the shared phase model both follow.

---

## Quickstart

```bash
cd pipeline

# 1. Extract Java + Angular source, merge (writes to config.json's knowledgeBaseDir, NOT here — see
#    "Project Workspace Convention" in migration-pipeline.md)
node run.js 2

# 2. Generate BRD scaffolds (one .brd.json per module)
node run.js 3

# 3. Phase 4 — enrich the BRDs (human/conversational step, not mechanical — see
#    migration-pipeline.md's "extractors capture structure, mappers/review supply narrative")

# 4. Generate both reports
npm run reports
# → <knowledgeBaseDir>/extraction-report.html      (raw extraction + gaps, interactive drilldown)
# → <knowledgeBaseDir>/enrichment-summary.html      (business-facing: app overview, modules,
#                                              entities, functions, use cases, open questions)
```

Set `javaSourceDir`, `angularSourceDir`, and **`knowledgeBaseDir`** in `pipeline/config.json` before
running. `knowledgeBaseDir` should point at `analysis/<project-name>/knowledge-base` in your
project workspace — **never** leave it unset for a real run; this tool must never accumulate
project-specific output inside its own directory tree (that's the whole point of it staying
a reusable, downloadable pipeline rather than one-off-per-project code).

### Multiple source repos (`sources` array)

A real migration is rarely one repo. If the legacy app is split across several Maven/Angular repos
(e.g. a Common lib + several downstream services), extract them **all before merging**, not one at a
time — running them separately means cross-module calls (e.g. Service A calling into Common's
`LocationService`) can never resolve, since the linker only sees whatever was merged in a single run.

Replace the flat `javaSourceDir`/`angularSourceDir` fields with a `sources` array:

```json
{
  "sources": [
    { "name": "common", "javaSourceDir": "/abs/path/repo-a/src/main/java" },
    { "name": "billing", "javaSourceDir": "/abs/path/repo-b/src/main/java" }
  ],
  "angularSourceDir": "",
  "knowledgeBaseDir": "/abs/path/analysis/<project-name>/knowledge-base"
}
```

`node run.js 2` extracts every entry in `sources` into the same `knowledgeBaseDir/extracted/`
(tagged `java-<name>.json`/`angular-<name>.json` so they don't clobber each other), then runs the
merger **once** over everything — so calls/aggregates across repos link correctly before BRD
generation (`node run.js 3`) buckets the result by module.

The old flat single-source config still works unchanged if `sources` is absent — this is additive,
not a breaking change.

---

## Folder structure

```
java-angular-migration-skills/
  pipeline/
    config.json                  ← source paths
    run.js                       ← phase orchestrator (node run.js <1|2|3|all> [java|angular])
    generate-report.js           ← raw extraction/gap HTML dashboard
    generate-enrichment-report.js ← business-facing enrichment summary HTML
    extractors/
      java-extractor.js          ← tree-sitter-java: @Entity/@RestController/@Service
      angular-extractor.js       ← tree-sitter-typescript: components/routes/dialogs/forms
    generators/
      brd-mappers/                ← 5 mappers, reused near-verbatim from os-migration-pipeline
      lib/type-converter.js       ← Java→Mendix type table (the one stack-specific swap)
    lib/
      interfaces.js, merger.js    ← reused verbatim from os-migration-pipeline
      linker.js                   ← rules rewritten for this stack (repo-call naming,
                                     same-module call chains, API path+verb matching,
                                     dialog-launch + template-composition links)
      key-resolver.js             ← placeholder (OS's version is XML-key-specific, unused here)
  SESSION-NOTES.md               ← real bugs found/fixed while building this, with root causes
```

---

## What gets extracted

| Java/Angular concept | KB type | Mendix equivalent |
|---|---|---|
| `@Entity` class | `entity` | Persistent Entity |
| Plain `@Data` DTO (no `@Entity`) | `entity` (`isPersistent: false`) | Non-persistent Entity *(mapper doesn't distinguish yet — known limitation)* |
| `@Service`/controller method | `logic` (`logicKind: 'action'`) | Microflow |
| Angular `@Component` (routed, dialog, or embedded) | `screen` | Page / Popup |
| `@ManyToOne`/`@OneToOne` field | synthetic `"<Entity> Identifier"` attribute | Association |

---

## Shared toolkit

Cross-project skills and prompt templates live in a separate repo:
`https://github.com/MendixMau/mxcli-project-toolkit`
Key skills: `migration-pipeline.md`, `brd-generation.md`, `qa-loop-goal-pattern.md`.
