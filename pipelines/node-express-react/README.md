# Node/Express + React Migration Skills — Extraction Pipeline

Extraction pipeline for **Node.js/Express (backend) + React/TypeScript (frontend) applications to Mendix**.

Takes Express route/controller/model source + React component/route source → structured JSON knowledge base → BRD scaffolds per module.

Sibling to `java-angular` and `outsystems` — see `mxcli-project-toolkit/skills/migration-pipeline.md` for the shared phase model all three follow.

## Known gap: not yet a generic Node/Express+React tool

Unlike `java-angular` (tree-sitter AST parsing), `backend-extractor.js` is **regex-based, by explicit design choice recorded in its own header comment**: "the RWA source is small and cleanly structured, so regex scanning is sufficient... if the source grows or becomes messier, replace the regex passes with ts-morph." Treat this pipeline as **proven on two source shapes**, not as reusable across arbitrary Node/Express+React codebases. Before pointing it at a third, structurally different source: expect to extend the regex passes, and validate output against hand-built ground truth per `source-triage.md`'s coverage-gate rule, same as any new extractor.

**Layout is configured, not assumed (2026-08-31).** The directory assumptions used to be hardcoded to the Cypress-RWA shape and were the first thing a second source hit: Puffin (a dashboard-publishing app: `api/src/shared/db/types.ts` + `api/src/api/routes/*.ts`) matched the stack, missed every hardcoded path, and extracted nothing — reporting only a directory-not-found error, which reads as a broken run rather than a wrong assumption. Layout now comes from `config.json`'s `layout` block (defaults = the RWA shape, so existing runs are unchanged); `config.json`'s `_layout_keys` documents every key. Four capabilities were added along the way, each because a real source needed it:

| Capability | Why it exists |
|---|---|
| `export type X = { … }` alongside `export interface` | Puffin declares all four entities as type aliases; the interface-only regex found zero |
| SQL migrations → entities (`sqlDirs`) | A schema states NOT NULL / UNIQUE / FK / ON DELETE that a TS type only implies. Where both exist they are **reconciled into one entity** — schema for constraints, TS for the developer-facing attribute names — instead of emitting the same entity twice |
| Router mount prefixes (`serverFiles`) | A router declaring `'/'` and `'/:id'` is two real endpoints once `app.use('/api/dashboards/:dashboardId/viewers', …)` is read; without it they extract pathless |
| Typed API clients (`apiClientFiles`) | An app calling `api.listThings()` has no axios anywhere, so every screen extracted as `no-api-calls-found` and nothing linked screens to endpoints (10 of 10 screens, before the fix) |

**Field run, 2026-08-31 (T-WF-migration / Puffin):** 4 entities, 13 `/api` endpoints and 10 screens extracted, against a hand-built ground truth of the same counts — the 14th documented endpoint (`/health`) is an `app.get` in the server file, not a router, and is correctly absent; the `admins` table created in migration 001 and dropped in 003 is correctly absent too. 13 screen→endpoint links, 25 cross-references, 1 gap.

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

**Capability grouping (Phase 3):** BRDs land per business capability, not per source folder — technical-layer names roll up via each item's path evidence (`generators/lib/capability-grouper.js`, shared with java-angular). Review `brd/grouping-proposal.md` at CAC-2 (`checkpoint-brd.md` Q0); override via `config.json` → `"brdGrouping"` and re-run `node run.js 3`. Optional `"project": { "title", "description", "techTags" }` drives the enrichment report's hero.

---

## HTML reports

Two surfaces, and only one of them lives here.

```bash
npm run reports                        # generate-report.js — raw extraction/gap dashboard
../../../bin/brd-report.sh <project>   # Stage 2 — the business-facing BRD surface
```

`generate-report.js` is a pipeline tool: it reads this stack's extracted JSON and reports what
the extractors did and did not get. `bin/brd-report.sh` reads **BRDs**, which is why it is not
in this folder — the same page has to render for a requirements-driven or greenfield project
that never runs an extractor at all. This pipeline had its own copy
(`generate-enrichment-report.js`) until 2026-08-19; all three pipeline copies had drifted onto
different BRD key names and rendered blanks for each other's output. See CLAUDE.md, "Writing in
this toolkit — generic first".

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
