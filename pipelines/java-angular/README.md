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

# 0. Project-owned config, kept in the project — never edit pipeline/config.json (the template)
#    in the shared toolkit clone. Relative paths in it resolve against the file's own folder.
cp config.json <project-root>/analysis/<source-name>/pipeline-config.json   # then fill it in
CFG=<project-root>/analysis/<source-name>/pipeline-config.json             # or: export MXTK_PIPELINE_CONFIG=$CFG

# 1. Extract Java + Angular source, merge (writes to the config's knowledgeBaseDir, NOT here — see
#    "Project Workspace Convention" in migration-pipeline.md)
node run.js 2 --config "$CFG"

# 2. Generate BRD scaffolds (one .brd.json per business capability) + grouping proposal
node run.js 3 --config "$CFG"
# → review <knowledgeBaseDir>/brd/grouping-proposal.md at CAC-2 (checkpoint-brd.md Q0)

# 3. Phase 4 — enrich the BRDs (human/conversational step, not mechanical — see
#    migration-pipeline.md's "extractors capture structure, mappers/review supply narrative")

# 4. Generate the extraction dashboard
npm run reports -- --config "$CFG"
# → <knowledgeBaseDir>/extraction-report.html      (raw extraction + gaps, interactive drilldown)

# 5. Stage 2 — the business-facing BRD surface
../../../bin/brd-report.sh <project-root>
# → <project-root>/analysis/brd-report.html
#
# Not a pipeline script and deliberately not in this folder: it reads BRDs, not source, so it
# is the same renderer for every entry mode (migration, requirements-driven, greenfield) and
# for BRDs that no extractor produced. It replaced this pipeline's own
# generate-enrichment-report.js on 2026-08-19 — see CLAUDE.md, "Writing in this toolkit".
```

Set `javaSourceDir`, `angularSourceDir`, and **`knowledgeBaseDir`** in your project's copy of
`pipeline/config.json` before running, and pass it with `--config <file>` (or `MXTK_PIPELINE_CONFIG`).
`run.js` refuses the tracked template while it still holds `/path/to/your` placeholders; a clone
whose tracked file was already filled in keeps working, but move that config into the project. `knowledgeBaseDir` points at `<project-root>/analysis/<source-name>/knowledge-base`
(**inside the project folder, never a sibling** — see migration-pipeline.md's Project Workspace
Convention). Never leave it unset for a real run, and never commit real local paths; this tool
must never accumulate project-specific output inside its own directory tree.

Optional config keys:

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
                                 ← (no enrichment report here: the business-facing Stage 2
                                    surface is bin/brd-report.sh, one renderer for every source)
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
| Java `enum` (nested: named `Outer_Inner`, label `Outer.Inner`, `outerType` set) | `staticEntity` | Enumeration |

**REST endpoints.** Every `@Get/Post/Put/Delete/Patch/RequestMapping` on a method of a
`*Controller`-stereotyped class lands as an `httpEndpoint` on a `logic` item; path constants
(`API_LOCATIONS + "/{pKey}"`, `TMSApi.TRANSPORT_ORDERS`) are evaluated from the `String`
constants declared in the same source. If a service method in the controller's own package has
the controller method's name, it carries the endpoint (the pilot shape). Otherwise the controller
method itself becomes the item (`layer: "controller"`) and `delegatesTo[]` names the service
methods it calls through its injected fields, resolved by type, so a controller and its
`*ServiceImpl` in different packages still link. An endpoint with no resolvable delegate carries
the gap `endpoint-delegate-unresolved`. Independently, the extractor regex-counts the mapping
annotations in each controller file; `reports/gaps-report.md` and `summary.md` print
"captured N of M", and any shortfall is added to the gaps total.

---

## Shared toolkit

This pipeline lives inside `mxcli-project-toolkit` — cross-project skills are two levels up in
`skills/`. Key skills: `migration-pipeline.md`, `brd-generation.md`, `checkpoints/checkpoint-brd.md`,
`qa-loop-goal-pattern.md`.
