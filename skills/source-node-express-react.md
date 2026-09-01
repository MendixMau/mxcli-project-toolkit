# Source Platform: Node/Express + React → Mendix
**Applies to:** migration.
**Purpose:** Node/Express+React-specific extraction rules and concept mappings, for use alongside `migration-pipeline.md` and `pipelines/node-express-react/`.
**Scope:** Currently validated against one source shape (Cypress Real World App-style layout: `src/models/*.ts` + `backend/*-routes.ts` + React components). See the pipeline's own README "Known gap" section before assuming this generalizes — the extractor is regex-based by design, not AST-based, and has not been proven against a structurally different Express project.
**Source:** `pipelines/node-express-react/pipeline/extractors/backend-extractor.js` and `frontend-extractor.js`, read directly rather than assumed — this doc mirrors what the code actually does.

---

## When to Use This Skill

- The source is a Node.js/Express backend paired with a React (or React/TypeScript) frontend.
- You're about to run `pipelines/node-express-react/` and want to know what it does and doesn't capture before trusting its output.
- Extraction output looks thin or wrong — check the layout assumptions below before assuming the source itself lacks structure.

---

## Layout is CONFIGURED — set it before running, do not fork the extractor

**Read the real source layout first, then write it into config.json's `layout` block.** The
values below are the *defaults* (the Cypress-RWA shape), not a requirement:

| Config key (default) | What's extracted | KB type |
|---|---|---|
| `modelDirs` (`src/models`) / `modelFiles` — TS interfaces **and** `export type X = {…}` aliases | Entity shape | `entity` |
| same files — TS enums | Static entity | `staticEntity` |
| `routeDirs` (`backend`) + `routeFilePattern` (`-routes\.ts$`) — Express router files | One item per route handler | `logic` (`logicKind: 'action'`) |
| `sqlDirs` (none) — `CREATE TABLE` / `ALTER TABLE` migrations | Entity, with NOT NULL / UNIQUE / FK / delete rule | `entity` |
| `serverFiles` (none) — `app.use('<prefix>', xRouter)` | Mount prefix applied to that router's paths | — |
| `screenDirs` (`src/containers`, walked recursively) — React components | Screen (`modal`/`embedded` inferred from the name) | `screen` |
| `apiClientFiles` (none) — typed client modules | Screen→endpoint links | — |

**Where both a TS type and a SQL table describe one entity, they are reconciled into a single
entity** — the schema is authoritative for constraints, the TS type for the attribute names a
developer actually wrote — with each attribute tagged `sql+ts` / `sql-only` / `ts-only`. A
`ts-only` attribute is a finding, not noise: it is a field with no column behind it.

**The failure this replaced (2026-08-31, a dashboard-publishing migration project).** The paths above were hardcoded. A
second real source on the same stack kept its types in `api/src/shared/db/types.ts` and its
routes in `api/src/api/routes/*.ts`; the extractor matched nothing, and said so only as
"models directory not found" — which reads as a broken run rather than a wrong assumption.
Setting the layout took minutes; noticing it needed setting is the part this section exists
to make automatic. **Confirm the real layout by reading the source before running extraction,
never after seeing a suspiciously small KB.**

---

## Concept Mapping

| Node/Express/React concept | Mendix equivalent |
|---|---|
| TypeScript interface (model) | Persistent Entity |
| TypeScript enum | Enumeration / static entity |
| Model relation (FK / id reference field) | Association, surfaced as a synthetic `"<Entity> Identifier"` attribute |
| Express route + controller handler | Microflow |
| React routed component | Page |
| React dialog/modal component | Popup |

---

## Known Extras Not Wired Into the Standard Phases

`pipeline/enrichers/` (`cypress-usecase-enricher.js`, `merge-backend-usecases.js`, `enrich-high-risk-ucs.js`, `manual-enrich-usecases.js`) mines the source repo's own Cypress E2E test suite as a second evidence source for business rules and use cases — genuinely useful (tests often encode intent that route handlers don't), but **not invoked by any `run.js` phase**. Run these manually after Phase 2 if the source ships a Cypress suite. Don't assume this ran just because Phase 2/3 completed.

---

## Checklist Before Trusting Extraction Output

- [ ] Read the source's real layout and wrote it into `config.json`'s `layout` block (or a project-local config passed as `PIPELINE_CONFIG`) — the defaults are one source's shape, not a standard.
- [ ] Counted the ground truth BY HAND first — entities, endpoints, screens — and compared the extractor's counts against those numbers, not against how complete the output looks. A layout miss produces a small, clean, entirely wrong KB.
- [ ] Checked `errors/` **and** the extractor's stderr for `directory not found` lines: on this pipeline that message means a layout key is wrong, not that the source lacks the construct.
- [ ] If the source has a Cypress suite, ran the `enrichers/` scripts manually — they don't run automatically.
- [ ] Validated a sample of extracted entities/routes against the actual source file, not just against the KB JSON (regex extraction can silently under- or over-match).
- [ ] If this is the first run against a source that isn't Cypress-RWA-shaped, treated it as building a new extractor variant (per `source-triage.md`'s reuse-vs-build-new call), not as "reusing" a proven generic tool.
