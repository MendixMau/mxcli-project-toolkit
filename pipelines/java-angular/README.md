# Java/Angular Migration Skills — Extraction Pipeline

Reusable engine for migrating **Java/Spring Boot + Angular applications to Mendix**.

Takes Java source (`@Entity`/`@RestController`/`@Service`) + Angular source (components,
routes, dialogs) → structured JSON knowledge base → BRD scaffolds **per business capability**
(not per Java package — see Capability grouping below) → enrichment → two HTML reports.

Sibling to `../outsystems` and `../node-express-react` — see
`skills/migration-pipeline.md` for the shared phase model all three follow.

---

## Quickstart

```bash
cd pipeline

# 1. Extract Java + Angular source, merge (writes to config.json's knowledgeBaseDir, NOT here — see
#    "Project Workspace Convention" in migration-pipeline.md)
node run.js 2

# 2. Generate BRD scaffolds (one .brd.json per business capability) + grouping proposal
node run.js 3
# → review <knowledgeBaseDir>/brd/grouping-proposal.md at CAC-2 (checkpoint-brd.md Q0)

# 3. Phase 4 — enrich the BRDs (human/conversational step, not mechanical — see
#    migration-pipeline.md's "extractors capture structure, mappers/review supply narrative")

# 4. Generate both reports
npm run reports
# → <knowledgeBaseDir>/extraction-report.html      (raw extraction + gaps, interactive drilldown)
# → <knowledgeBaseDir>/enrichment-summary.html      (business-facing: app overview, modules,
#                                              entities, functions, use cases, open questions)
```

Set `javaSourceDir`, `angularSourceDir`, and **`knowledgeBaseDir`** in `pipeline/config.json` before
running. `knowledgeBaseDir` points at `<project-root>/analysis/<source-name>/knowledge-base`
(**inside the project folder, never a sibling** — see migration-pipeline.md's Project Workspace
Convention). Never leave it unset for a real run, and never commit real local paths; this tool
must never accumulate project-specific output inside its own directory tree.

Optional `config.json` keys:

- `"project": { "title", "description", "techTags": [] }` — drives the enrichment report's hero
  block (a placeholder hero renders without it).
- `"brdGrouping": { "<rawModule>": "<capability>" }` — explicit overrides for capability grouping
  (see below); set after reviewing `grouping-proposal.md`, then re-run `node run.js 3`.

### Capability grouping (Phase 3)

BRDs land per **business capability**, not per Java package. Technical-layer packages (`impl`,
`api`, `spi`, `commands`, `events`, `handler`, …) are rolled up into their business domain using
each item's own source-path evidence — per item, because the same leaf name (an `impl` package)
legitimately exists in several domains. The applied mapping is written to
`brd/grouping-proposal.md` and confirmed at CAC-2 (`skills/checkpoints/checkpoint-brd.md` Q0);
corrections go in `brdGrouping` and Phase 3 re-runs in seconds. Mendix module boundaries remain a
Stage 3 decision (`skills/modularize-domain.md`). Implementation:
`pipeline/generators/lib/capability-grouper.js`.

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
java-angular/
  pipeline/
    config.json                  ← source paths
    run.js                       ← phase orchestrator (node run.js <1|2|3|all> [java|angular])
    generate-report.js           ← raw extraction/gap HTML dashboard
    generate-enrichment-report.js ← business-facing enrichment summary HTML
    extractors/
      java-extractor.js          ← tree-sitter-java: @Entity/@RestController/@Service
      angular-extractor.js       ← tree-sitter-typescript: components/routes/dialogs/forms
    generators/
      brd-mappers/                ← 5 mappers, reused near-verbatim from the outsystems pipeline
      lib/type-converter.js       ← Java→Mendix type table (the one stack-specific swap)
      lib/capability-grouper.js   ← package→capability rollup + grouping-proposal.md (CAC-2)
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

This pipeline lives inside `mxcli-project-toolkit` — cross-project skills are two levels up in
`skills/`. Key skills: `migration-pipeline.md`, `brd-generation.md`, `checkpoints/checkpoint-brd.md`,
`qa-loop-goal-pattern.md`.
