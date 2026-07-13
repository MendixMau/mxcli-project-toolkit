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

## Layout Assumptions (regex-based, not AST — verify against your source before relying on this)

| Expected location | What's extracted | KB type |
|---|---|---|
| `src/models/*.ts` — TypeScript interfaces | Entity shape | `entity` |
| `src/models/*.ts` — TypeScript enums | Static entity | `staticEntity` |
| `backend/*-routes.ts` — Express router files | One item per route handler | `logic` (`logicKind: 'action'`) |
| React routed components | Screen | `screen` |
| React dialog/modal components | Screen (popup) | `screen` |

If your source uses a different directory convention (e.g. `models/` at repo root, or route files not suffixed `-routes.ts`), the extractor will silently miss them — it has no fallback discovery, only these literal patterns. Confirm the real layout by reading the source directly before running extraction, not after seeing a suspiciously small KB.

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

- [ ] Confirmed the source actually uses the `src/models/*.ts` + `backend/*-routes.ts` layout, or adjusted the extractor first.
- [ ] Checked `errors/` for any files the regex passes failed to parse.
- [ ] If the source has a Cypress suite, ran the `enrichers/` scripts manually — they don't run automatically.
- [ ] Validated a sample of extracted entities/routes against the actual source file, not just against the KB JSON (regex extraction can silently under- or over-match).
- [ ] If this is the first run against a source that isn't Cypress-RWA-shaped, treated it as building a new extractor variant (per `source-triage.md`'s reuse-vs-build-new call), not as "reusing" a proven generic tool.
