# Migration Pipeline — Source Code to Mendix BRD
**Purpose:** Platform-agnostic orchestration playbook for migrating any legacy application
to Mendix via structured extraction, KB synthesis, and BRD generation.
**Companion skills:** `source-os11.md`, `source-oracle-forms.md`, `source-java-spring.md`,
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

## Decision Log

Track key pipeline decisions per project:

| Decision | Options | Chosen | Reason |
|----------|---------|--------|--------|
| Module scope | All 114 / Business only | Business first | Framework modules add noise |
| BRD format | JSON / Markdown / Both | JSON + .md review copy | Machine-readable + human review |
| Rearchitect strategy | 1:1 / Consolidated / Split | TBD per project | Depends on domain complexity |
| Cross-module assocs | mxcli / Studio Pro | Studio Pro always | mxcli BUG-02 |
