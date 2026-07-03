# java-angular-migration-skills — Session Notes
**Date:** 2026-07-01/02
**Project origin:** IVM-SourceCodeAnalysis — generalizing the Apex OS→Mendix pipeline
(`os-migration-pipeline` + `mxcli-project-toolkit`) to a Java/Spring Boot + Angular source,
piloted against `inventory-management-with-angular-spring-boot`.

---

## What's built and validated

Full chain, run against real source (not fixtures): `java-extractor.js` + `angular-extractor.js`
→ `lib/merger.js` (copied unchanged) → `lib/linker.js` (rules rewritten for this stack) →
`generators/brd-mappers/*.js` (4 of 5 reused near-unchanged, `microflow-mapper.js` enhanced) →
`generate-report.js` (copied, cosmetic-only changes).

Result on the pilot repo: 3 entities, 19 logic items, 11 screens → 56 cross-references, only 2
gaps, both legitimate (pure dialog components with no direct API call of their own — their
caller does the real work). Confidence: `item`=medium, `itemAction`=medium, `itemSummary`=high.

## Reused vs written from scratch

- **Reused close to verbatim:** `lib/interfaces.js`, `lib/merger.js`, all 5 `brd-mappers/*.js`
  files' structure, `generate-report.js` (only page-title string changed).
- **Replaced entirely:** `lib/key-resolver.js` (OS XML-key-specific, ours is a documented
  no-op placeholder), `generators/lib/type-converter.js`'s `TYPE_MAP` (Java types → Mendix,
  not OS types → Mendix).
- **Rewritten rules, same engine:** `lib/linker.js` — OS's rules (DB table name pattern,
  C#/JS name-substring match) replaced with ours (repository-call naming convention,
  same-module call-name matching, API path/verb matching, dialog-launch + composition links).
- **New:** `extractors/java-extractor.js`, `extractors/angular-extractor.js`.
- **One small enhancement, not a fork:** `microflow-mapper.js` gained a `hiddenRules` field
  (generic pattern detection: thrown exceptions, PUT-as-upsert, multi-repo cascade delete) —
  patched in place per `migration-pipeline.md`'s "patch it in place, don't fork" rule.

## Real bugs found and fixed during iteration (not hypothetical — caught by inspecting actual output)

1. **Chained method call names were giant duplicated blobs.** `repo.findAll().stream().map(...)`
   — a call's `object` field can itself be another call node; using its full `.text` embedded
   the whole nested chain as one string. Fix: only prefix with the receiver when it's a simple
   identifier/field/`this`; otherwise use the bare method name.
2. **Wrong merger/extractor output path.** `extractors/README.md`'s template says write to
   `extracted/{type}.json`; the real (working) `xml-extractor.js` and `merger.js` actually use
   `knowledge-base/extracted/{type}.json`. The README is stale — followed the code, not the doc.
3. **`linker.js`'s OS rules produced noise, not signal.** Every entity got a `no-db-table-found`
   gap because Rule 1 checked for an `ossys_*` table that will never exist for us. Fixed by
   replacing the OS-specific rules outright rather than suppressing the symptom.
4. **Screen→Logic linking initially matched EVERY item-module screen to the same two
   endpoints** (`getItems`/`saveItem`). Root cause: URLs are built via string concatenation
   (`'literal' + this.item.id + 'literal'`) in the Angular source, and the first extractor
   version only read the first string fragment, truncating `/api/items/{id}/itemActions` down
   to `/api/items` — which happened to coincide with the two collection-level endpoints' exact
   path, so everything falsely matched those two. Fixed by reconstructing `+`-concatenated and
   template-literal (`` ` ``) strings, substituting `*` for interpolated/non-literal segments.
5. **Path-shape matching alone over-linked by HTTP verb** — `ItemDeleteComponent` matched
   `getItem`/`replaceItem`/`deleteItem` all, since they share the same path shape
   (`/api/items/{id}`) and only differ by verb. Fixed by cross-referencing the Angular
   `*.service.ts` files' own `this.http.<verb>()` calls to resolve which verb each component
   call actually uses, pairing verb+path per-method rather than matching path alone.
6. **`architecture.md` (hand-written earlier in the same project) had a transcription error** —
   documented `/api/itemSummary`, real endpoint is `/api/items/summary`. Caught by the
   extractor disagreeing with the hand-written doc; fixed the doc, not the extractor.

## What this proves about the extractor-vs-mapper split

`migration-pipeline.md`'s rule ("extractors capture structure, mappers/human review supply
narrative") held up in practice: `java-extractor.js` captures raw facts (thrown exception
types, repository call chains) without claiming to know *why* — the `hiddenRules` enhancement
in `microflow-mapper.js` only mechanically surfaces those facts (e.g. "may throw X, review the
guarding condition") rather than fabricating an explanation. The one thing this pipeline still
cannot produce is use-case narrative (actors, preconditions, main flow) — those stay explicit
`TODO`/`pending` stubs, same as the OS pipeline, because they're business decisions, not
derivable from code.

## Phase 4 enrichment pass (2026-07-02)

Used the app's own `README.md` ("Features & Behaviours") + 4 sampled screenshots in `Images/`
as Path B input (no external business docs/recordings existed for this pilot). Enriched all
11 use cases across the 3 BRDs with real narrative (actors/preconditions/mainFlow/
postconditions), flipped `reviewStatus` to `reviewed`, and added 4 `openQuestions`. Also
produced `generate-enrichment-report.js` — a business-facing summary (app overview, per-module
entities/functions/pages/use-cases/hidden-rules/open-questions), reading only from the enriched
BRD JSON so its numbers are never hand-typed.

Two more real findings surfaced by actually looking at the screenshots, not just the code:
- **"Item History" is a dead nav link.** `sidenav-menu-items.component.ts` advertises
  `routerLink: ['/items/history']`, but no such route exists, and no screen anywhere calls the
  one backend endpoint that would power it (`GET /api/items/{itemId}/itemActions`). Backend
  capability exists; frontend feature was never built. Real candidate for the Mendix rebuild,
  not something to silently drop or silently reproduce as broken.
- **`ItemActionsComponent` was mis-bucketed** into the `itemAction` module by the
  name-matching heuristic (`moduleForComponent()`) — it's actually just the per-row
  Sell/Insert/Update/Delete button composition, unrelated to the `ItemAction` transaction
  entity. A real, confirmed instance of the heuristic's known limitation, not just a
  theoretical one.

**CSS/SASS: deliberately not extracted, and correctly so for this app.** Checked directly
(all `.sass` files + a grep for `[ngClass]`/`[class.` across every template): everything is
layout mechanics (widths, elevation) with zero migration value — Mendix has its own theming
system, Angular Material CSS isn't a port target. The one thing that *would* matter — a
data-driven style binding hiding a business rule, e.g. a status color-code — doesn't exist
anywhere in this app (confirmed empty). Added a cheap, permanent check for it anyway
(`hasConditionalStyling` in `angular-extractor.js`/`page-mapper.js`/both report generators)
since it's a one-line regex and pays for itself the moment a messier app has one. Notably,
**the OS pipeline has the exact same gap this would have had**: `xml-extractor.js` does
capture widget `Visible`-property expressions (`node.visibilityCondition`), but it's only
consumed by `widget-translator.js` for Phase 6 MDL generation — never surfaced in
`page-mapper.js` or `generate-report.js`, so a BRD reviewer would never see it flagged.

**Bug found while verifying the above: re-running Phase 3 silently destroyed Phase 4
enrichment.** `node run.js 3` regenerates every `.brd.json` unconditionally — running it again
(to verify the `hasConditionalStyling` field landed correctly) reverted all 11 use cases back
to `reviewStatus: 'pending'` and wiped `openQuestions` entirely. Fixed in
`brd-mappers/index.js`: before writing, check whether the existing file already has enrichment
(`reviewStatus: 'reviewed'` anywhere, or non-empty `openQuestions`) — if so, write the fresh
scaffold to `{module}.brd.scaffold.json` instead of overwriting, and warn. This is a generic
risk any stack's Phase 3/4 split would have, not specific to this pilot — worth carrying the
same guard into `migration-pipeline.md`'s checklist.

## Output location refactor (2026-07-02)

All pipeline output (`knowledge-base/`) was originally written inside this repo
(`pipeline/knowledge-base/`) — coupling this supposedly-reusable tool to one pilot project's
data. Fixed: every script (both extractors, `lib/merger.js`, `run.js`, both report generators)
now reads its output location from `config.json`'s `outputDir`, falling back to a local
`knowledge-base/` only when unset (gitignored scratch space for standalone testing). Real
output for this pilot now lives at
`analysis/inventory-management-with-angular-spring-boot/knowledge-base/`. Verified by clearing
the old location entirely and re-running the full chain (extract → merge → BRD → enrich →
reports) fresh — landed correctly, `pipeline/` confirmed to have zero project-specific files
left. Documented as "Project Workspace Convention" in `mxcli-project-toolkit/skills/
migration-pipeline.md` so every future stack pipeline follows the same rule from the start
instead of retrofitting it like this one needed.

## Syncing with os-migration-pipeline upstream improvements (2026-07-02)

`os-migration-pipeline` and `mxcli-project-toolkit` both got real updates independently (new
`document-discovery.md`/`brd-validation.md` skills, pipeline renumbered to 7 phases, and
`use-case-mapper.js` upgraded to produce code-inferred narrative instead of blank TODOs). Ported
the applicable parts here:

- **Config key renamed `outputDir` → `knowledgeBaseDir`** everywhere (config.json, both
  extractors, merger.js, run.js, both report generators, README.md, migration-pipeline.md) to
  match the name `os-migration-pipeline` settled on — the two sibling pipelines had drifted to
  different names for the same field.
- **`use-case-mapper.js` rewritten** to produce real code-inferred `mainFlow`/`openQuestions`
  instead of blank TODO stubs, adapted (not copied) from OS's version since the underlying
  signals differ: OS reads `widgetTree` nav edges + screen-permission-role links; ours reads
  the linker's `_links` (`api-call-match`/`api-path-match-no-verb` for business actions split by
  HTTP method, `composes-component`/`dialog-opens` for navigation/composition edges). Also added
  `classifyAppType()` — kept OS's `Integration-heavy`/`Master Data-CRUD`/`Mixed` categories,
  dropped the BPT/workflow-action category since it has no Java/Angular equivalent in this
  stack's extractors.
- **`brd-mappers/index.js`** now sets `appType` on the BRD and folds `useCases[].gaps` into
  `openGaps`; the Phase 3/4 overwrite guard is more thorough (also checks `status ===
  'doc-confirmed'/'doc-conflict'` and resolved use-case-level `openQuestions`, matching
  `brd-validation.md` check #6's reconciliation states, not just `reviewStatus === 'reviewed'`).
- **`generate-report.js`**'s "Use Cases (scaffolds)" table replaced with a "Business Process
  Overview" section: `appType` badge + per-use-case main flow/open questions/status, colored
  green for `reviewed`/`doc-confirmed`, red for `doc-conflict`, blue for `code-inferred`.
- Verified end-to-end: re-ran `node run.js 3` against the pilot's existing enriched BRDs — the
  overwrite guard correctly redirected all 3 modules to `.brd.scaffold.json` (8/8 `item` use
  cases stayed `reviewed`, untouched), and the fresh scaffolds show real inferred content, e.g.
  `AddItemComponent` → `"User triggers an action causing POST /api/items"` with a matching
  validation open question, not a TODO. Scaffold files deleted after verification (test
  artifacts only, not meant to persist since the pilot's BRDs are already past this stage).

## `domain-entity-mapper.js` non-persistent entity fix (2026-07-02)

Previously noted below as "harmless looseness, not silently wrong" — that assessment didn't hold
up once the BRD's finished artifacts started traveling on their own into `IVM-MxCLI-main`,
detached from this session's context. `java-extractor.js` already correctly captures
`isPersistent: false` for `ItemSummary` (a plain `@Data` DTO, no `@Entity`) in `entities.json` —
but `domain-entity-mapper.js` (shared with `os-migration-pipeline`) ignored that field and
hardcoded `mendixType: 'PersistentEntity'` for every entity. Someone building the Mendix domain
model from the copied BRD alone, with no memory of this pilot's extraction quirks, would have
built `ItemSummary` as persistent — wrong, since it's a computed daily-profit/sold/inserted
summary, never stored.

Fixed at the root in both `domain-entity-mapper.js` copies (this repo and
`os-migration-pipeline`, since they were identical): `mendixType` is now
`e.isPersistent === false ? 'NonPersistentEntity' : 'PersistentEntity'` — defaults to persistent
when the extractor doesn't set the field at all (true for `xml-extractor.js` today), only flips
when an extractor explicitly says otherwise. Re-ran `node run.js 3`, confirmed the scaffold now
shows `NonPersistentEntity`, then hand-patched just that one field on the real (enriched)
`itemSummary.brd.json` rather than letting the overwrite guard redirect it — a mapper-level
correctness fix isn't enrichment content, so it's fine to touch in place. Re-copied the corrected
file into `IVM-MxCLI-main/migration-input/.../brd/itemSummary.brd.json`.

**Lesson**: "acceptable POC looseness" is only actually acceptable as long as the person reading
the output still has the context to know it's loose. Once a BRD is handed off standalone, every
known mapper limitation needs to either be fixed at the root or surfaced as a `gaps`/
`openQuestions` entry on the BRD itself — never left as a note in a session-only doc like this
one, which doesn't travel with the artifact.

## Known remaining limitations (not fixed — deliberate scope calls, not bugs)

- Component-to-module bucketing (`item` / `itemAction` / `itemSummary`) is a name-matching
  heuristic (`moduleForComponent()` in `angular-extractor.js`), not a real Angular module
  boundary — this app has one flat `NgModule`. Works because these components are named after
  their domain; would need real work for a source with less consistent naming.
- `AddItemComponent` has its own inline `<form>` almost identical to the shared
  `ItemDetailsFormComponent` dialog form — a real duplication in the source, flagged but not
  "fixed" (fixing source code isn't in scope; it's a finding for whoever designs the Mendix
  rebuild).
