# Migration Pipeline — Source Code to Mendix BRD
**Purpose:** Platform-agnostic orchestration playbook for migrating any legacy application
to Mendix via structured extraction, KB synthesis, and BRD generation.
**Companion skills:** `source-os11.md`, `source-oracle-forms.md`, `source-java-spring-angular.md`,
`kb-generation.md`, `brd-generation.md`, `migrate-general.md`

---

## When to Use This Skill

- Starting a migration from any source platform to Mendix
- Planning the extraction and analysis phase before MDL scripting begins
- Deciding which pipeline path applies (code extraction, document extraction, or both)

---

## Pipeline Overview

```
SOURCE (code + docs)
       │
       ├─ Path A: Code Extraction
       │    └─ XML / Java / C# / SQL → extracted JSON (knowledge-base/)
       │
       ├─ Path B: Document Extraction
       │    └─ xlsx / docx / PDF → KB_*.md files (knowledge-base/share/)
       │
       └─ MERGE
            └─ JSON draft BRD  +  KB.md enrichment  →  F{NNN}.brd.json
                                                              │
                                               Phase 4: Rearchitect to Mendix
                                                              │
                                                   F{NNN}.mx-brd.json (Mendix-aligned)
                                                              │
                                                   Phase 5: MDL Generation
                                                              │
                                                layer1/ (domain) + layer2/ (microflows)
```

---

## Phase 1 — Source Analysis

Before extracting anything, classify and scope the source.

### 1.1 Identify the platform

| Signal | Platform |
|--------|----------|
| `.xml` files with `<ESpace>` root | OutSystems 11 |
| `pom.xml` + `@Entity` annotations | Java / Spring |
| `*.csproj` + `DbContext` | .NET / EF Core |
| `.fmb` / `.fmx` files | Oracle Forms |
| `*.oaf` / `OAF Controller` | Oracle ADF |
| `*.abap` | SAP ABAP |

Load the matching `source-{platform}.md` skill for platform-specific extraction rules.

### 1.2 Classify modules

Every source platform has a module/component hierarchy. Classify before extracting:

| Tier | Description | Extract first? |
|------|-------------|---------------|
| Business modules | Core feature logic, user-facing screens | Yes — Phase A |
| Common/shared modules | Reusable utilities, shared entities | Yes — Phase B |
| Integration modules | External API connectors, ETL | Yes — Phase B |
| Framework/platform modules | OS runtime, UI frameworks, 3rd party | No — skip or reference only |

**Rule:** Never migrate framework modules. Reference them as stubs.

### 1.3 Scope the extraction

Count before committing:
- How many modules/components total?
- How many are business vs framework?
- Are design docs available? Which modules do they cover?
- Is a database schema available separately?

---

## Phase 2 — Code Extraction (Path A)

Runs the extraction pipeline against source code to produce typed JSON per artifact.

### Output structure

```
knowledge-base/
  extracted/
    xml.json          ← raw extracted items from source
  entities.json       ← persistent data entities
  staticEntities.json ← enumerations / lookup tables
  structures.json     ← non-persistent DTOs / structures
  logics.json         ← server actions / microflows / procedures
  screens.json        ← UI screens / pages
  webBlocks.json      ← reusable UI components
  timers.json         ← scheduled jobs
  serviceApis.json    ← exposed / consumed APIs
  extEntities.json    ← external entity references
  dataScreenActions.json
  cross-reference-map.json
  reports/
    gaps-report.md
    coverage-report.md
    summary.md
```

### Extraction order

1. Run extractors in parallel (one per source type: XML, CS, JS, DB, docs)
2. Run merger — deduplicates, resolves cross-references, writes knowledge-base JSONs
3. Review `gaps-report.md` — unresolved references indicate cross-module dependencies
4. Review `coverage-report.md` — confirm expected artifact counts match source

### Quality checks before BRD generation

- [ ] Entity count matches source module inventory
- [ ] Cross-reference gaps < 15% of total references
- [ ] All business modules present in extracted output
- [ ] No extractor failed silently (check `errors/` directory)

---

## Phase 3 — Document Extraction (Path B)

Converts raw design documents into structured KB.md files.
See `kb-generation.md` for the full prompt template and extraction method.

### Document priority order

1. Requirements specifications (main feature spec per module)
2. Field label / translation sheets (Japanese ↔ English mappings)
3. QA / clarification sheets (resolved decisions, open questions)
4. API / integration manuals (external system specs)
5. Development standards (naming, audit fields, security conventions)

### Output structure

```
knowledge-base/
  share/
    KB_{Module}_{Topic}.md     ← one per source document or domain area
    EXTRACTION_LOG.md          ← session diary of what was processed
```

### When to skip Path B

- Framework/platform modules with no design docs → skip, extract from code only
- Modules fully covered by code (pure CRUD, no business rule ambiguity) → Path A sufficient
- Duplicate docs (older version of same spec) → process latest only, note in log

---

## Phase 3b — Automated BRD Scaffolding (new — runs after Phase 2 code extraction)

When the code extraction pipeline has produced KB JSONs, run the BRD mapper layer to auto-generate
one structured `{ModuleName}.brd.json` per source module:

```bash
node run.js 3           # generates knowledge-base/brd/*.brd.json
node generate-report.js # generates knowledge-base/extraction-report.html
```

The `brd-mappers/` layer (in `pipeline/generators/brd-mappers/`) contains one mapper per Mendix concept:
- `domain-entity-mapper` — entities + enumerations with key attributes + associations
- `microflow-mapper` — logic items with inferred purpose (name-pattern rules), kind, parameters
- `page-mapper` — screens with UI pattern (list / form / detail / mixed), linked logics
- `use-case-mapper` — scaffold per screen, **all narrative fields are explicit TODOs** for business review
- `integration-mapper` — exposed REST (inbound) + external entities (outbound)

The HTML report (`extraction-report.html`) is the primary human review surface — open in browser,
click any module to see its BRD summary alongside raw extraction data.

**Important:** use-case narrative (actors, preconditions, main flow) is NOT auto-generated — these are
business decisions, not derivable from code. The scaffold provides the structure; the business fills in the content.

## Phase 4 — BRD Generation (enrichment pass)

Merges auto-scaffolded BRDs (Phase 3b) with Path B KB.md documents into reviewed, complete BRDs.
See `brd-generation.md` for the full JSON schema and prompt template.

### BRD scope decision

One BRD = one Mendix module (roughly). Group by functional cohesion, not source module 1:1.

**Typical split:**
- F001: Core registration / main feature flow
- F002: Approval / workflow
- F003: Master data / lookups
- F004: External integrations (one BRD per external system if complex)
- F005+: Common components consumed by this app

### Merge strategy

```
Path A JSON  →  draft BRD (high confidence on structure, low on intent)
     +
Path B KB.md →  enrichment (adds use cases, business rules, field labels, open questions)
     =
F{NNN}.brd.json (complete)
```

When no KB.md exists for a module, the JSON draft BRD is sufficient — mark `openQuestions`
with items that need business confirmation.

### BRD generation order

Write dependency BRDs first:
1. Master data / enumerations (no dependencies)
2. Common components (depend only on master data)
3. Business feature modules (depend on common + master data)
4. Integration modules (depend on business entities)

---

## Phase 5 — Rearchitect BRDs to Mendix Architecture

OS/Java/Oracle modules don't map 1:1 to Mendix modules. This phase restructures.

### Mendix module tiers

```
App (one Mendix app)
  ├─ Domain modules       ← persistent entities + associations + enumerations
  ├─ UI modules           ← pages, snippets, layouts (may reference domain)
  ├─ Logic modules        ← microflows, nanoflows (no entity definitions)
  ├─ Integration modules  ← REST clients, consumed services, stubs
  └─ Common modules       ← shared utilities, shared entities across features
```

### Rearchitect rules

- **Consolidate** small source modules covering the same domain into one Mendix module
- **Split** large source modules where UI and domain logic are entangled
- **Promote** entities used by 3+ source modules to a Common or Domain module
- **Cross-module associations** must be created in Studio Pro (mxcli BUG-02)
- **Layering rule:** Common modules must not import from feature modules (same as OS 3-tier rule)

### Output

```
knowledge-base/
  brd/
    F001-payer-registration.brd.json     ← OS-aligned draft
    F001-payer-registration.mx-brd.json  ← Mendix-rearchitected (add .mx- prefix)
    index.json
```

---

## Phase 6 — MDL Generation

Reads `.mx-brd.json` files and produces layered MDL scripts.
See `migrate-general.md` for layering rules, naming conventions, and known mxcli bugs.

### Script output structure

```
mdlsource/
  layer1/
    01-{module}-domain.mdl      ← entities, enumerations, intra-module associations
    security-setup.mdl          ← roles, grants (always last in layer1)
  layer2/
    01-enum-additions.mdl       ← enumerations needed by microflows
    09-{module}-microflows.mdl  ← microflows, numbered by dependency order
  layer3/                       ← pages (if generated via mxcli)
    01-{module}-pages.mdl
```

### Generation order per BRD

1. `domainEntities` → layer1 entity scripts
2. `enumerations` from staticEntities → layer1 (or layer2 if microflow-only)
3. `microflows` → layer2 scripts
4. `integrations` with `stubName` → STUB_ microflows in layer2
5. `pages` → layer3 scripts

---

## Creating a New Stack Pipeline (e.g. Java/Spring + Angular, .NET, Oracle Forms)

Each source stack gets its own **self-contained pipeline repo** (e.g. `os-migration-pipeline`,
`java-angular-migration-skills`) — not a shared npm dependency on a common engine package.
Decided 2026-07: `mxcli-project-toolkit` holds only knowledge (skills, prompt templates), never
executable pipeline code, so that every pipeline repo stays independently cloneable and runnable
with zero cross-repo wiring. Revisit this only if real drift/duplication pain shows up across two
or more working pipelines — don't extract a shared engine package pre-emptively.

### Copy verbatim from the nearest existing pipeline repo

These are already stack-agnostic — copy first, adapt only if a genuine gap appears:
- `pipeline/lib/interfaces.js` — the ExtractionResult/BaseExtractor contract
- `pipeline/lib/merger.js` — dedup + KB JSON emission (generic)
- `pipeline/lib/linker.js` — the cross-reference *engine* is generic; the rules inside are not (see below)
- `pipeline/generators/brd-mappers/*.js` — all 5 mappers (domain-entity, microflow, page, use-case,
  integration) are ~90% generic; they read normalized KB fields (`name`, `module`, `attributes[]`,
  `inputParameters`, `widgetSummary`, etc.), never raw source syntax
- `pipeline/run.js` orchestration skeleton and `pipeline/config.json` shape
- `pipeline/generate-report.js` — ~90% reusable as-is. It reads KB files defensively
  (`readJson()` returns `[]` on anything missing, so a stack that never produces
  `webBlocks.json`/`timers.json`/etc. doesn't break it) and the whole dashboard/heatmap/
  module-drilldown is data-driven off KB + BRD JSON, not OS-specific structure. Only cosmetic
  strings need changing (page title, any OS-flavored table labels like "Server Action / BPT").
  **Do not rewrite this file — patch strings in place.**

### Reuse the `logicKind` vocabulary — don't invent a parallel one

`generate-report.js`'s `logicKindLabel()` and `microflow-mapper.js`'s `KIND_LABEL` both key off
the same five values: `action`, `clientAction`, `screenAction`, `dataAction`, `process` →
Microflow/Nanoflow/DataAction/BPTProcess. If a new extractor tags its own logic items using this
same vocabulary wherever the concept genuinely matches (e.g. a Spring `@Service`/`@RestController`
method is server-side business logic, same role as an OS Server Action → tag it `logicKind:
'action'`), **both of those files need zero changes.** Only invent a new `logicKind` value if the
new stack has a concept with no reasonable match in the existing five — and if you do, update both
label maps together, not just one.

### Must be newly written per stack

- `pipeline/extractors/{type}-extractor.js` — one per source type, following
  `pipeline/extractors/README.md`'s item interface exactly
- Linker rules inside `lib/linker.js` — e.g. "Screen → Endpoint by URL match" for Spring/Angular
  replaces OS's "Screen → JS module by filename" rule; the engine that runs the rules doesn't change
- Any `KIND_LABEL`-style concept-mapping table entry that has no equivalent in the reused vocabulary
  above (Spring has no client/server action split the way OS does, so most Java logic items will
  just be `action`)
- A `source-{stack}.md` skill in `mxcli-project-toolkit/skills/`, companion to this doc, same role as
  `source-os11.md` — documents the stack's concept-mapping table and extraction conventions

### Checklist for bootstrapping a new stack pipeline repo

- [ ] Copy the generic files/folders listed above from the nearest existing pipeline repo
- [ ] Write extractor(s) for the new source type(s), one per `extractors/README.md` template
- [ ] Add/adapt linker rules for this stack's real cross-reference patterns
- [ ] Run the copied `brd-mappers/*` against real extracted output; where a mapper's assumption
      doesn't hold (e.g. no `logicKind` concept), patch it in place and note the change — don't fork
      a parallel mapper implementation
- [ ] Run `generate-report.js` against real extracted output and confirm the HTML report renders
      (module/entity/page counts, gap heatmap, per-module drilldown) — update only cosmetic strings
      (page title, any OS-flavored table labels), never the data-driven logic
- [ ] Write `source-{stack}.md` and add it to this file's "Companion skills" line above
- [ ] Before trusting BRD output, hand-verify a small amount of ground truth (an
      `architecture.md`-style doc), then run the iterative validation loop in
      `qa-loop-goal-pattern.md` until cross-reference quality is actually verified against
      that ground truth, not just "no errors thrown"

---

## Decision Log

Track key pipeline decisions per project:

| Decision | Options | Chosen | Reason |
|----------|---------|--------|--------|
| Module scope | All 114 / Business only | Business first | Framework modules add noise |
| BRD format | JSON / Markdown / Both | JSON + .md review copy | Machine-readable + human review |
| Rearchitect strategy | 1:1 / Consolidated / Split | TBD per project | Depends on domain complexity |
| Cross-module assocs | mxcli / Studio Pro | Studio Pro always | mxcli BUG-02 |
