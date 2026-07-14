# Node/Express + React Migration Skills — Extraction Pipeline

Extraction pipeline for **Node.js/Express (backend) + React/TypeScript (frontend) applications to Mendix**.

Takes Express route/controller/model source + React component/route source → structured JSON knowledge base → BRD scaffolds per module.

Sibling to `java-angular` and `outsystems` — see `mxcli-project-toolkit/skills/migration-pipeline.md` for the shared phase model all three follow.

## Known gap: not yet a generic Node/Express+React tool

Unlike `java-angular` (tree-sitter AST parsing), `backend-extractor.js` is **regex-based, by explicit design choice recorded in its own header comment**: "the RWA source is small and cleanly structured, so regex scanning is sufficient... if the source grows or becomes messier, replace the regex passes with ts-morph." It also assumes a specific layout (`src/models/*.ts` for entities, `backend/*-routes.ts` for routes) that matches the Cypress Real World App this pipeline was first built against — not a validated-generic Express project layout. Treat this pipeline as **proven on one source shape**, not yet as reusable across arbitrary Node/Express+React codebases. Before pointing it at a second, structurally different source: expect to extend the regex passes or layout assumptions, and validate output against hand-built ground truth per `source-triage.md`'s coverage-gate rule, same as any new extractor.

---

## Quickstart

```bash
cd pipeline
npm install

# 1. Extract backend + frontend source, merge (writes to config.json's knowledgeBaseDir, NOT here — see
#    "Project Workspace Convention" in migration-pipeline.md)
node run.js 2

# 2. Generate BRD scaffolds (one .brd.json per module)
node run.js 3

# 3. Phase 4 — enrich the BRDs (human/conversational step, not mechanical — see
#    migration-pipeline.md's "extractors capture structure, mappers/review supply narrative")
```

Set `sourceDir` and **`knowledgeBaseDir`** in `pipeline/config.json` before running. `knowledgeBaseDir` should point at `<project-root>/analysis/<source-repo-name>/knowledge-base` (inside the project folder, never a sibling) — **never** leave it unset for a real run, and never commit real local paths into this file.

---

## HTML reports

This pipeline ships both report generators (ported from `java-angular`, 2026-07-14):

```bash
npm run reports   # generate-report.js (raw extraction/gap dashboard)
                  # + generate-enrichment-report.js (business-facing enrichment-summary.html)
```

The enrichment summary's hero block is config-driven — set `config.json` → `"project": { "title", "description", "techTags": [] }`; without it the report still renders with a placeholder hero derived from the workspace folder name.

---

## Known gap: `enrichers/` is not wired into `run.js`

`pipeline/enrichers/` (`cypress-usecase-enricher.js`, `merge-backend-usecases.js`, `enrich-high-risk-ucs.js`, `manual-enrich-usecases.js`) is a real capability — Cypress-test-driven use-case enrichment, useful when the source repo ships its own E2E test suite as a second source of business-rule evidence — but it is **not** invoked by any `run.js` phase. Run these scripts manually, after Phase 2, if the source has a Cypress suite worth mining. This is a capability the generic three-phase pipeline spec (`migration-pipeline.md`) doesn't yet account for; don't silently fold it into Phase 2 without updating that spec first.

---

## Folder structure

```
node-express-react/
  pipeline/
    config.json                  ← source paths
    run.js                       ← phase orchestrator (node run.js <1|2|3|all> [backend|frontend])
    generate-report.js           ← raw extraction/gap HTML dashboard
    extractors/
      backend-extractor.js       ← Express routes/controllers/models
      frontend-extractor.js      ← React components/routes
      backend-usecase-mapper.js  ← maps backend routes to use cases
    enrichers/                  ← NOT wired into run.js — run manually, see gap above
      cypress-usecase-enricher.js
      merge-backend-usecases.js
      enrich-high-risk-ucs.js
      manual-enrich-usecases.js
    generators/
      brd-mappers/                ← BRD scaffold generation
      lib/
    lib/
      interfaces.js, merger.js, linker.js, key-resolver.js
```

---

## What gets extracted

| Node/Express/React concept | KB type | Mendix equivalent |
|---|---|---|
| Express model/schema | `entity` | Persistent Entity |
| Express route + controller handler | `logic` (`logicKind: 'action'`) | Microflow |
| React routed component | `screen` | Page |
| React dialog/modal component | `screen` | Popup |
| Model relation (FK / ref) | synthetic `"<Entity> Identifier"` attribute | Association |

---

## Shared toolkit

Cross-project skills and prompt templates live in `mxcli-project-toolkit/skills/`.
Key skills: `migration-pipeline.md`, `brd-generation.md`, `qa-loop-goal-pattern.md`.
