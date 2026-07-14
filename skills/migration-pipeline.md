# Migration Pipeline — Source Code to Mendix BRD
**Applies to:** migration.
**Purpose:** Platform-agnostic orchestration playbook for migrating any legacy application
to Mendix via structured extraction, KB synthesis, and BRD generation.
**Companion skills:** `source-os11.md`, `source-oracle-forms.md`, `source-java-spring-angular.md`,
`document-discovery.md`, `kb-generation.md`, `brd-generation.md`, `brd-validation.md`, `migrate-general.md`,
`extractor-quality-loop.md` (mandatory Phase 2 gate — read before writing any extractor)
**Gate:** `source-triage.md` runs right after Phase 1 (platform identified) and **before Phase 2/3 proceed** — it decides whether an extraction pipeline is even warranted at this size, checks coverage against the extractors/mappers that actually exist, and recommends a bounded scope. Phase 3 does not start on unconfirmed scope.
**Downstream:** Phase 6 decides module boundaries via `modularize-domain.md` (criteria + user sign-off — never map source files/BRDs 1:1 onto modules) *before* writing `.mx-brd.json`. Then hand off to `architecture-blueprint.md` (diagrams, module defs, wiring, fit-gap) and `design-artifacts.md` (design system + wireframes) to make the architecture legible and verifiable, then to `brd-to-build-plan.md` to turn it all into a dependency-ordered, numbered build plan before any MDL scripting starts.

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
Phase 1: Source Triage → capabilities, coverage matrix
       │
  [CAC-1 Scope] — POC boundary · extractor strategy · external refs
       │
       ├─ Path A: Code Extraction (Phase 2)
       │    └─ XML / Java / C# / SQL → extracted JSON (knowledge-base/)
       │         → BRD Scaffold (Phase 3 — auto-generated draft BRDs)
       │              │
       │         [CAC-2 BRD] — enrichment order · source patterns · hidden rules
       │
       ├─ Path B: Document Discovery & Extraction (Phase 4)
       │    └─ recursive scan → classify → KB_*.md → KB.md
       │
       └─ MERGE
            └─ Scaffold BRD + KB.md enrichment → validate → F{NNN}.brd.json (Phase 5)
                    │
               [CAC-3 Architecture] — module split · cross-module data · NFRs
                    │
               Phase 6: Rearchitect to Mendix → F{NNN}.mx-brd.json
                    │
               [CAC-4 Design] — Atlas layout · platform target · branding/Figma
                    │
               Phase 6b: Design Artifacts (design-artifacts.md)
                    │
               [CAC-5 Build] — MDL strategy · security timing · deadline/priority
                    │
               Phase 7: MDL Generation
                    │
               layer1/ (domain) + layer2/ (microflows) + layer3/ (pages)
```

**Path A and Path B run independently and in either order** — Path B does not block Path A.
For a demo or first pass on a new project, run Path A end-to-end first (extraction → scaffold)
since it needs no human triage; run Path B (document discovery) as a follow-up once the code-side
BRD scaffold exists to cross-reference against.

---

## Project Workspace Convention

**A pipeline tool repo (`os-migration-pipeline`, `java-angular-migration-skills`, future ones)
must never accumulate project-specific output inside its own directory tree.** Every project
gets its own workspace folder, kept entirely separate from the reusable tool:

```
<workspace-root>/
  sources/<source-repo-name>/          ← raw cloned/copied source, untouched
  analysis/<source-repo-name>/         ← ALL project-specific output lives here
    architecture.md                     ← hand-written findings (Phase 1, optional but recommended)
    knowledge-base/                     ← everything the pipeline generates (Phase 2–4)
      extracted/                        ← raw per-extractor JSON
      entities.json, logics.json, screens.json, cross-reference-map.json, ...  ← merged KB
      reports/                          ← gaps/coverage/summary .md
      brd/                              ← Phase 3 scaffolds + Phase 4 enriched BRDs
      extraction-report.html            ← raw extraction/gap dashboard
      enrichment-summary.html           ← business-facing summary
  os-migration-pipeline/                ← reusable tool, NO project-specific data
  java-angular-migration-skills/        ← reusable tool, NO project-specific data
```

Rules:

1. Every pipeline's `config.json` must have a `knowledgeBaseDir` field pointing at
   `analysis/<source-repo-name>/knowledge-base` — every script (extractors, merger, `run.js`,
   both report generators) reads its output location from `config.json`, never a hardcoded
   path relative to the tool's own `__dirname`.
2. Starting a new project always begins with creating `analysis/<source-repo-name>/` (mirroring
   `sources/<source-repo-name>/` if a clone exists) *before* running anything, then pointing
   `knowledgeBaseDir` there.
3. A tool repo may still fall back to a local `knowledge-base/` when `config.json` has no
   `knowledgeBaseDir` set — that's gitignored scratch space for quick standalone testing, never the
   documented way to actually run an analysis.
4. This is why the tool repo can stay genuinely downloadable/reusable per
   `os-migration-pipeline`'s own README ("clone and run" quickstart) — a fresh clone of the
   tool never has to be cleaned of a previous project's BRDs/reports before reuse.

### Variant: in-repo workspace (source already lives inside the Mendix target project)

Some projects start with the source app already checked into the Mendix project repo itself
(e.g. `<mendix-project>/source/` holding a cloned frontend+backend), rather than as a separate
clone the pipeline tool has to be pointed at. In that case, don't relocate the source just to
satisfy the `sources/` + `analysis/` split above — instead treat the Mendix project repo itself
as `<workspace-root>`:

```
<mendix-project>/                        ← workspace root AND the mxcli target, same repo
  source/                                 ← existing source app, left in place, untouched
  analysis/<source-repo-name>/            ← ALL pipeline output lives here (same internal shape
                                             as analysis/<source-repo-name>/ above: knowledge-base/,
                                             brd/, reports/, etc.)
  architecture/, design/, mdlsource/      ← later-phase outputs, per their own skills
  <mendix-project>.mpr                    ← the actual mxcli target
```

The tool repo (`mxcli-project-toolkit`) still stays untouched — `config.json`'s
`knowledgeBaseDir` points at `<mendix-project>/analysis/<source-repo-name>/knowledge-base`
exactly as it would for the separate-workspace layout; only the location of `sources/` changes
(it doesn't get a separate copy — `source/` in place serves that role). Use this variant when the
source was never a standalone clone to begin with; use the strict separate-workspace layout above
when scaffolding a new migration from scratch or when the source is a genuine external clone.

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

## Gate: Source Triage (`source-triage.md`)

**Run this before Phase 2 or Phase 3, not after.** The counts from 1.3 tell you the app's size; they don't tell you whether this toolkit's extractors/mappers actually cover this stack, whether extraction is even worth setting up at this size, or what a sane first slice looks like if the app is large. `source-triage.md` produces:

- An explicit **Manual-only / Reuse existing pipeline / Build new pipeline** decision (not every app justifies the extraction machinery)
- A **coverage matrix** — per business capability, extractable? mapper exists? output trustworthy? — so gaps are named before Phase 2 runs, not discovered mid-run
- A **bounded scope recommendation** when the source is large, signed off by the user
- A flag (not a full decision) for whether this app's scale raises a multiple-Mendix-apps question, upstream of `modularize-domain.md`'s module-boundary decision

**Phase 3 (BRD scaffolding) does not start until this triage is confirmed.** Skipping straight from extraction to BRDs produces scaffolds for a scope nobody agreed to.

### ► CAC-1 Scope Checkpoint

After triage is complete and confirmed, run `checkpoints/checkpoint-scope.md` before Phase 2 starts.
This gate locks the POC boundary, extractor strategy, and any external project references.

---

## Phase 2 — Code Extraction (Path A)

Runs the extraction pipeline against source code to produce typed JSON per artifact.

### Output structure

`knowledge-base/` below always means `analysis/<source-repo-name>/knowledge-base/` — see
"Project Workspace Convention" above. Never a path inside the tool repo itself.

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

### Multiple source repos/modules — extract everything before the one merge pass

A legacy app is rarely a single repo. When source spans several repos or modules (a shared
library plus multiple downstream services, several Maven modules, etc.), **every stack's
orchestrator must extract all of them before running the merger, and the merger must run exactly
once over the combined set** — not once per repo/module. The merger's cross-reference resolution
only ever sees items merged together in the same run; splitting extraction across separate
merge passes silently breaks cross-module links (a downstream module's call into the shared
library's service shows up as an unresolved gap even though the target genuinely exists — it's
just sitting in a different knowledge base).

This is a required convention for every extractor pipeline built against this skill, not a
one-off feature of any particular stack's implementation:

- Config accepts a `sources` array — `[{ name, <stack-specific source path fields> }, ...]` — in
  addition to (not replacing) a flat single-source config for the common case of one repo.
- Each source's raw extractor output is tagged by name (e.g. `extracted/<type>-<name>.json`) so
  writing multiple sources into the same `extracted/` directory never clobbers another source's
  output.
- The merger loads every tagged file it finds (glob, not a fixed filename list) and runs its
  dedup/link/emit pass once over the full combined set.
- A flat single-source config must keep working unchanged — this is additive, never a breaking
  change to a stack's existing extractor/merger.

See `pipelines/java-angular/pipeline/{run.js,lib/merger.js,extractors/*.js}` for the reference
implementation of this pattern — copy its shape (source tag → tagged output filename → glob-load
in merger) when building a new stack's extractor rather than re-deriving it.

### Quality gate before BRD generation — enforced by `extractor-quality-loop.md`

**Phase 3 (BRD scaffolding) does not start until the extraction quality score ≥ 95%.**

Read `extractor-quality-loop.md` in full before writing or running any extractor. That skill
defines the mandatory test/build loop, the 6 scored dimensions, the `extraction-quality.json`
format, and the `run.sh` interface every stack extractor must implement.

The loop:
1. Run extractor → emits `inventory.json` (or KB JSONs)
2. Run validator → emits `extraction-quality.json` with dimension scores
3. If overall score < 95%: fix the extractor, go to 1
4. If overall score ≥ 95%: gate passed, update `pipeline-state.md`, proceed to Phase 3

Never hand-patch `inventory.json` to inflate a score. The validator must derive ground truth
from source files directly.

Quick checklist (validator covers these automatically):
- [ ] Entity field count matches source interfaces/models
- [ ] Cross-file enum references resolved (not typed as String)
- [ ] Union types resolved to the enum variant, not String fallback
- [ ] All FK fields mapped to associations (including aliased FKs)
- [ ] All route-defining files globbed (not just `*-routes.ts` — include auth, app.ts, etc.)
- [ ] All test spec files classified to a capability (no "Other" bucket)
- [ ] Business logic items explicitly listed as BRD-only, not penalised

---

## Phase 3 — Automated BRD Scaffolding

**Requires the `source-triage.md` gate confirmed first** — scope subset agreed, coverage checked. Given that, this phase itself needs no *document* input (Path B) to run: once the code extraction pipeline (Phase 2) has produced KB JSONs for the confirmed scope, run the BRD mapper layer to
auto-generate one structured `{ModuleName}.brd.json` per source module — purely off the code-derived KB, so it's the fastest path to a first reviewable artifact **within that confirmed scope**:

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

### ► CAC-2 BRD Checkpoint

After scaffold BRDs are generated, run `checkpoints/checkpoint-brd.md` before Phase 5 enrichment.
This gate sets enrichment priority order, resolves detected source patterns (soft-delete, state machines,
shared balances), and surfaces business rules not visible in code.

---

## Phase 4 — Document Discovery & KB (Path B)

Recursively scans an unstructured document folder (design specs, requirements, manuals —
whatever exists outside the source code), classifies every file, and turns the relevant ones
into a canonical `KB.md`. See `document-discovery.md` for the full classification/routing
methodology and human-checkpoint procedure, and `kb-generation.md` for the per-file extraction
prompt template it hands off to.

### Why this is a separate phase from BRD scaffolding

Document folders often contain more than documents — source code exports, DB tooling,
credentials-flagged spreadsheets. `document-discovery.md` classifies and routes all of that
*before* any extraction happens; `kb-generation.md` only ever sees files already confirmed
relevant.

### Document priority order (within files classified as documents)

1. Requirements specifications (main feature spec per module)
2. Field label / translation sheets (Japanese ↔ English mappings)
3. QA / clarification sheets (resolved decisions, open questions)
4. API / integration manuals (external system specs)
5. Development standards (naming, audit fields, security conventions)

### Output structure

```
knowledge-base/
  share/
    discovery-manifest.json   ← full file inventory: classification, tier, alreadyCovered flag
    Review_Later.md           ← unsupported / too-large / unclassifiable files, nothing dropped
    KB_{Module}_{Topic}.md    ← one per source document or domain area
    KB.md                     ← canonical merge, cross-references every KB_*.md
    EXTRACTION_LOG.md         ← session diary of what was processed
```

### When to skip Path B

- Framework/platform modules with no design docs → skip, extract from code only
- Modules fully covered by code (pure CRUD, no business rule ambiguity) → Path A sufficient
- Duplicate docs (older version of same spec) → process latest only, note in log

---

## Phase 5 — BRD Validation & Enrichment

Merges the Phase 3 scaffold BRDs with Phase 4's `KB.md`, then validates the result for
consistency before calling it done. See `brd-generation.md` for the merge schema/prompt template
and `brd-validation.md` for the validation checks (duplicates, conflicts, orphaned concepts,
broken relationships) and the iterate-until-clean procedure.

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
Phase 3 scaffold BRD →  draft (high confidence on structure, low on intent)
     +
Phase 4 KB.md        →  enrichment (adds use cases, business rules, field labels, open questions)
     =
F{NNN}.brd.json (draft complete)
     │
     ▼
brd-validation.md checks → validation-report.md → fix → re-run → repeat until clean
     =
F{NNN}.brd.json (validated)
```

When no `KB.md` coverage exists for a module, the JSON draft BRD is sufficient — mark
`openQuestions` with items that need business confirmation, and validation should not treat
the absence as a conflict.

### ► CAC-3 Architecture Checkpoint

After BRDs are validated (all open questions resolved, `brd-validation.md` clean), run
`checkpoints/checkpoint-architecture.md` before Phase 6 starts. This gate decides module
structure, cross-module data strategy, and captures non-functional requirements.

### BRD generation order

Write dependency BRDs first:
1. Master data / enumerations (no dependencies)
2. Common components (depend only on master data)
3. Business feature modules (depend on common + master data)
4. Integration modules (depend on business entities)

---

## Phase 6 — Rearchitect BRDs to Mendix Architecture

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
- **Cross-module associations** are created via mxcli `CREATE ASSOCIATION` (BUG-02 fixed in v0.13.0)
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

### ► CAC-4 Design Checkpoint

After `.mx-brd.json` files are produced and module boundaries confirmed, run
`checkpoints/checkpoint-design.md` before `design-artifacts.md`. This gate locks the Atlas
layout, platform target (web/responsive/native), and captures branding or Figma assets.

---

## Phase 6b — Design Artifacts (`design-artifacts.md`)

Produces design system decisions (Atlas layout, tokens, component naming) and wireframe outlines.
Reads: `.mx-brd.json` files + CAC-4 design decisions.

### ► CAC-5 Build Plan Checkpoint

After design artifacts are signed off, run `checkpoints/checkpoint-build.md` before MDL
generation starts. This gate sets MDL layer strategy, security timing, and surfaces any
deadline or feature priority that should front-load the build plan.

---

## Phase 7 — MDL Generation

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

- [ ] Every script (extractors, merger, `run.js`, both report generators) reads its output
      location from `config.json`'s `knowledgeBaseDir`, never a path hardcoded relative to the tool's
      own directory — see "Project Workspace Convention" above
- [ ] Copy the generic files/folders listed above from the nearest existing pipeline repo
- [ ] Write extractor(s) for the new source type(s), one per `extractors/README.md` template
- [ ] Add/adapt linker rules for this stack's real cross-reference patterns
- [ ] Run the copied `brd-mappers/*` against real extracted output; where a mapper's assumption
      doesn't hold (e.g. no `logicKind` concept), patch it in place and note the change — don't fork
      a parallel mapper implementation
- [ ] Confirm `brd-mappers/index.js` guards against overwriting Phase 4 enrichment — before
      writing `{module}.brd.json`, check whether the existing file already has enrichment
      (any `reviewStatus: 'reviewed'` useCase, or non-empty `openQuestions`); if so, write the
      fresh scaffold to `{module}.brd.scaffold.json` instead and warn, rather than silently
      overwriting reviewed narrative with a fresh `pending` scaffold. Confirmed via the
      java-angular-migration-skills build that re-running Phase 3 without this guard destroys
      Phase 4 work with no warning.
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
| Cross-module assocs | mxcli / Studio Pro | mxcli (BUG-02 fixed v0.13.0) | `CREATE ASSOCIATION` works correctly |
| Phase ordering | Docs before code / Code before docs | Code first (Phase 3), docs second (Phase 4) | BRD scaffolding needs no human triage; document discovery does — run the free pass first |
