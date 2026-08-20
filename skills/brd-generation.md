# BRD JSON Generation — Prompt Template
**Applies to:** migration or requirements-driven build (works from documents/SME input — no legacy source needed).
**Requires:** bash and Python 3 — this skill runs toolkit shell scripts. Run `bin/doctor.sh` once on a new machine; it names anything missing and how to get it. Windows: use Git Bash, and see the Prerequisites section of `conversion-runbook.md`.
**Purpose:** How to synthesise KB files + extracted JSON into BRD (Business Requirements
Document) JSON files — the structured handoff from analysis to MDL scripting.
**Source:** reference sample — F001–F012 BRDs produced in conversation, 2026-05.

---

## What a BRD file is

A BRD JSON file is a structured, machine-readable summary of ONE feature area. It combines
information from multiple KB files and extracted JSON (screens, entities, logics) into a format
that Claude uses when writing MDL domain model and microflow scripts. It contains use cases,
domain entities, microflows to build, pages to build, and integration stubs needed.

**A BRD's scope is whatever is listed in its `modules[]`, and that is an array of 1..n.**

- **Module-scoped** — `modules` has exactly one entry. This is what the extractor scaffolders
  produce: `node run.js 3` writes one `{ModuleName}.brd.json` per source module, so its
  `modules` array always has length 1.
- **Feature-scoped** — `modules` has several. This is what a hand-written or doc-derived
  `F{NNN}` BRD usually is: one business capability that lands across more than one Mendix
  module.

Neither is more correct. The array is what makes them the same kind of file, and every reader
must handle both lengths.

> **Why this paragraph is this pedantic (2026-08-19).** This section used to say *"A BRD JSON
> file is a structured, machine-readable summary of ONE feature area"* and, two sentences
> later, *"One BRD = one Mendix module (roughly)."* That `(roughly)` was read three different
> ways by three different implementations. All three extractor scaffolders emitted `module:`
> **singular**; the OutSystems report renderer read `modules` **plural** and therefore rendered
> `undefined` against its own pipeline's output; the other two renderers read the singular and
> rendered `undefined` against anything written by hand from this file. Nobody noticed, because
> a BRD reader that cannot find a key prints a blank, not an error. A definition that can be
> read two ways will be, and the cost lands in a renderer months later.

`module` (singular) is the retired key. `bin/brd-report.sh` still reads it so existing
knowledge bases keep rendering, and it names every BRD that still carries it so the transition
finishes instead of becoming permanent.

---

## File naming convention

```
F{NNN}-{kebab-topic}.brd.json

Examples:
  F001-order-registration.brd.json
  F002-approval-workflow.brd.json
  F003-master-data.brd.json
  F004-corporate-search.brd.json
```

Store in: `extraction/knowledge-base/brd/`
Also maintain: `extraction/knowledge-base/brd/index.json` (list of all BRDs)

---

## BRD JSON structure

```json
{
  "id": "F001",
  "title": "Order & Billing Address Registration",
  "modules": ["ACME01_OrderRegist"],
  "actors": ["OrderRegisterUser", "SuperUser", "SysAdmin"],

  "useCases": [
    {
      "id": "UC001",
      "title": "View Order Registration List",
      "actors": ["OrderRegisterUser", "SuperUser"],
      "preconditions": ["User is logged in with appropriate role"],
      "postconditions": ["System displays the order registration list"],
      "mainFlow": [
        "1. User navigates to OrderRegistration_Overview page",
        "2. System retrieves and displays all OrderApplicationHeader records"
      ],
      "screens": ["OrderRegistration_Overview"],
      "mdlRefs": ["ACME01_OrderRegist"]
    }
  ],

  "domainEntities": [
    {
      "name": "OrderDetail",
      "module": "OrderRegistration",
      "persistent": true,
      "sourceOS": "ENOrderDetail",
      "attributes": [
        { "name": "OrderCode",     "type": "String",   "length": 10,  "mandatory": true  },
        { "name": "CustomerCode",  "type": "String",   "length": 10,  "mandatory": false },
        { "name": "CurrencyCode",  "type": "String",   "length": 3,   "mandatory": true  },
        { "name": "IsActive",      "type": "Boolean",                 "mandatory": true  }
      ],
      "auditFields": ["IsActive", "LockVersion", "CreatedOn", "CreatedBy"],
      "associations": [
        {
          "name": "OrderDetail_OrderApplicationHeader",
          "target": "OrderApplicationHeader",
          "type": "ManyToOne",
          "owner": "OrderDetail"
        }
      ]
    }
  ],

  "microflows": [
    {
      "name": "ACT_OrderDetail_Save",
      "module": "OrderRegistration",
      "purpose": "Validates and persists a new order draft. Returns the created OrderDetail.",
      "params": [{ "name": "Dto", "type": "OrderDetail_Dto" }],
      "returns": "OrderDetail",
      "pattern": "validate-then-save",
      "calls": ["GET_OrderArea_Dto", "ACT_OrderDetail_SaveDraft"],
      "validations": ["SelectedCompanyName not blank", "CurrencyCode not blank", "Deadline not empty"]
    }
  ],

  "pages": [
    {
      "name": "OrderDetail_NewEdit",
      "module": "OrderRegistration",
      "layout": "Atlas_Core.Atlas_Default",
      "purpose": "Data entry form for new order registration",
      "dataContext": "OrderDetail_Dto",
      "sections": ["OrgChoice", "OrderInfo", "AreaData", "SalesAreaData"],
      "actions": ["ACT_OrderDetail_Save", "ACT_OrderDetail_Cancel"]
    }
  ],

  "integrations": [
    {
      "name": "PartnerLookup Corporate Search",
      "type": "REST",
      "stubName": "STUB_ACT_PartnerLookup_Execute",
      "stubBehaviour": "Returns hardcoded OrderBase co. result",
      "realTarget": "C-0001 PartnerLookup API",
      "apiDoc": "KB_C0001_CorporateSearch.md"
    }
  ],

  "openQuestions": [
    { "id": "D1", "question": "Approval route branching logic", "status": "Resolved", "answer": "Single route J001, no branching" }
  ],

  "sourceKB": [
    "KB_ACME01_RequirementsSpec_V5.md",
    "KB_ACME01_FieldLabels_EN.md",
    "KB_ACME01_QA.md"
  ],

  "provenance": "documents"
}
```

### `provenance` — optional, and the one key worth filling in by hand

`"provenance"` is one of `code-extracted` | `documents` | `interview` | `greenfield`. It says
where this BRD's content came from, and it is the field `bin/brd-report.sh` uses to decide what
an EMPTY section means: a requirements-driven BRD with no `domainEntities` is normal, and a
migration BRD with no `domainEntities` means the extractor produced nothing and nobody looked.
Without it the report can only infer — from the scaffolder fingerprint, or from a non-empty
`sourceKB` — and when it can do neither it reports **provenance undetermined** and refuses a
verdict on every section rather than guessing. `sourceKB` is *evidence* of document provenance,
never a substitute for declaring it: the scaffolders never emit `sourceKB`, and an SME-interview
BRD has no KB files to name.

`coverage-ledger.md` already ledgers `/provenance/*` and `/sourceKB/*` as BRD metadata rather
than buildable requirements, so neither key needs a build-plan row.

### Keys the scaffolders add that the block above does not show

Verified against `pipelines/*/pipeline/generators/brd-mappers/`. These are real, they are on
every scaffolded BRD, and they were missing from this document — which is part of why readers
of BRDs kept guessing at the shape.

| Key | Where | Emitted by | Notes |
|---|---|---|---|
| `confidence` | top level | all three scaffolders (`brd-mappers/index.js`) | `high` / `medium` / `low`, purely a gap count — see "Confidence" below |
| `generatedAt`, `appType`, `summary{}`, `openGaps[]` | top level | all three scaffolders | the fingerprint that identifies a BRD as code-extracted |
| `webBlocks[]`, `timers[]` | top level | all three scaffolders | |
| `reviewStatus` | `useCases[]` | all three (`use-case-mapper.js`) | `pending` until a human reviews the narrative |
| `status` | `useCases[]` | set by `brd-validation.md` check 6 | `code-inferred` / `doc-confirmed` / `doc-conflict` |
| `hiddenRules[]` | `microflows[]` | java-angular and node-express-react only (`microflow-mapper.js`) — **not** OutSystems | rules found inside code that the domain model does not show |
| `mendixType`, `attributeCount` | `domainEntities[]` | all three (`domain-entity-mapper.js`) | `attributeCount` is the retired form of `attributes[]`; the count is derivable from the list, the list is not derivable from the count |
| `gaps[]` | every mapped item | all three | feeds `confidence` |

A hand-written BRD is not obliged to carry any of these. A reader of BRDs is obliged to
tolerate all of them.

---

## Automated BRD Scaffolding (run before Step 1)

Before writing BRDs manually, run the automated BRD mapper layer if a code extraction pipeline is available.
This produces a `{ModuleName}.brd.json` scaffold per module in `knowledge-base/brd/`.

```bash
node run.js 3               # brd-mappers/ → knowledge-base/brd/*.brd.json
node generate-report.js     # → knowledge-base/extraction-report.html
bin/brd-report.sh <root>    # → analysis/brd-report.html   (Stage 2 surface, any source)
```

Each auto-generated BRD contains:
- `domainEntities[]` — entities + enumerations with key attributes, associations, mendixType
- `microflows[]` — all logic items with inferred purpose (name-pattern rules: GET_/ACT_/VAL_/CAL_/SUB_), kind (Microflow/Nanoflow/BPTProcess), parameters, call count
- `pages[]` — screens with UI pattern (list/form/detail/mixed), input params, linked logics
- `useCases[]` — **scaffold only** — screen-per-row with all narrative fields as explicit TODOs
- `integrations[]` — exposed APIs (inbound) + external entities (outbound)
- `timers[]` — scheduled events
- `confidence` — high (0 gaps) / medium (1–3) / low (4+). **This measures the extractor, not
  the requirement.** `brd-validation.md` check 5 says so and says what to do about it: read it
  next to doc-KB corroboration, never alone. `bin/brd-report.sh` prints the two side by side.

**Use the HTML reports** as the review surface: `extraction-report.html` (produced by the
pipeline, `npm run reports`) for what the extractors did and did not get, and
`bin/brd-report.sh <project-root>` → `analysis/brd-report.html` for the Stage 2 business-facing
BRD surface. The second one is not a pipeline script: it reads BRDs, not source, so it renders
the same page for a hand-written or doc-derived BRD as for a scaffolded one.
Use the auto-generated BRD as the starting point for Step 3 (Claude enrichment prompt).
The use-case narrative is never auto-generated — that requires business input.

---

## Step 1 — Decide BRD scope

Before prompting, decide the BRD boundaries. One BRD per major feature area.
Use the extracted `screens.json` and `entities.json` to group by functional cohesion.

A good BRD boundary is one coherent feature area. Whether that is one Mendix module or
several, list every one of them in `modules[]`. Aim for 3-8 use cases per BRD.

**Typical split for a medium OS application:**
- F001: Core registration flow (main screens + entities)
- F002: Approval workflow (WF integration + status transitions)
- F003: Master data (lookup tables, seed data)
- F004: External search integration (corporate search, postal code)
- F005: SAP/ERP integration (scheduler, FTP, field mapping)
- F006+: Common components consumed by this app

---

## Step 2 — Gather inputs

Collect before prompting:

1. Relevant KB files (from `extraction/knowledge-base/share/`)
2. Relevant extracted JSON sections (entities, screens, logics for this feature)
3. Cross-reference map (`cross-reference-map.json`) for dependencies
4. Any OS screen action names from `logics.json` that map to this feature

---

## Step 3 — Prompt Claude to write the BRD

```
You are writing a BRD JSON file for an OutSystems → Mendix migration.
This BRD covers: [feature area, e.g. "Order Registration — the main registration flow"]
Feature ID: F[NNN]

## Input context:

[paste or reference the relevant KB files]

[paste or summarise relevant extracted entities from entities.json]

[paste or summarise relevant screens from screens.json]

## Task:

Write F[NNN]-[topic].brd.json following this structure:
- id, title, modules, actors
- useCases — each with id, title, actors, preconditions, postconditions, mainFlow, screens, mdlRefs
- domainEntities — map from OS ENxxx to Mendix entity names, with all attributes and their Mendix types
- microflows — list each action to implement with purpose, params, returns, pattern, calls, validations
- pages — list each screen to implement with layout, dataContext, sections, actions
- integrations — external calls with stub plan
- openQuestions — anything still unclear
- sourceKB — list of KB files used
- provenance — code-extracted | documents | interview | greenfield

## Mendix naming conventions:
- Entity: PascalCase, no EN prefix (ENOrderDetail → OrderDetail)
- Module: PascalCase (ACME01_OrderRegist → OrderRegistration)
- Microflow: ACT_ (action), GET_ (retrieve/build DTO), VAL_ (validation), SUB_ (sub-routine)
- Page: EntityName_NewEdit, EntityName_View, EntityName_Overview
- Dto: EntityName_Dto (non-persistent)

## Audit fields to add to every persistent entity:
IsActive (Boolean), LockVersion (Integer), CreatedOn (DateTime), CreatedBy (String(200)),
ModifiedOn (DateTime, optional), ModifiedBy (String(200), optional)

Output: valid JSON only. No prose, no markdown fences.
```

---

## Step 4 — Validate the BRD

After Claude writes the BRD, review these checkpoints:

- [ ] All OS entities in scope mapped to Mendix entities (no ENxxx names left)
- [ ] All screens in scope have a corresponding `pages` entry
- [ ] All cross-module dependencies have an integration or reference entry
- [ ] Audit fields included on every persistent entity
- [ ] Stub plan defined for every external integration
- [ ] Open questions from KB QA sheets captured in `openQuestions`
- [ ] `sourceKB` lists every KB file that contributed
- [ ] `modules[]` is an array and lists **every** Mendix module this BRD covers — one entry for
      a module-scoped BRD, several for a feature-scoped one. Never the retired `module` string.
- [ ] `provenance` is set. Without it `bin/brd-report.sh` cannot tell a legitimately empty
      section from a broken one, and says so on the page rather than guessing.
- [ ] `bin/brd-report.sh <project> --json` shows 0 unreadable keys. A non-zero count is schema
      drift: a key this file documents that the BRD carries under some other name.
- [ ] `bin/facts-lock.sh <project> check` is clean — see below

---

## Running BRDs in parallel — bind to the facts lock

BRDs fan out well: one agent per module, no dependencies between them. The catch is that each
agent re-derives the same identifiers from the same corpus, and they disagree.

Measured on PROJECT-C, 20 BRDs written in parallel: **10 identifier conflicts**, every one
of them acronym casing — `WIPStatus`/`WipStatus`, `CreateWIPException`/`CreateWipException`,
`QueryAISafeWIPSummary`/`QueryAiSafeWipSummary` (71 uses against 78). Each surfaced later as an
*open question* addressed to the user, as though it were a business decision. It is not. It is
what happens when N agents each hold their own copy of a fact.

So the order is: **freeze first, then fan out.**

```bash
bin/facts-lock.sh <project> build    # harvest, freeze what is unanimous, list what is contested
bin/facts-lock.sh <project> check    # fail any BRD that contradicts a frozen fact
```

`build` freezes every identifier the corpus agrees on into `analysis/facts.lock.json`. Where it
finds two mixed-case spellings it freezes **nothing** and records the conflict — picking a
winner silently is the failure being prevented. Resolve a conflict by verifying against the
source corpus and setting `canonical` in the lock; **do not ask the user which spelling is
right**, that is research, not a decision (see `interview-protocol.md` on the RESEARCH tier).

Once frozen, the lock wins. Parallel agents read it instead of re-deriving, and `check` fails
any BRD that drifts — at write time, where it costs one edit, instead of at gate time, where it
costs the user's attention.

**Its blind spot, stated plainly:** it compares BRDs against each other, so it cannot detect a
mistake every BRD makes identically. It replaces N inconsistent guesses with one consistent
guess — which is strictly better and still a guess until someone checks it against the source.

Chunk per module rather than per capability while you are at it: cheaper retries, and a bad
run poisons one file instead of a capability.

## Step 5 — Maintain the BRD index

```json
// extraction/knowledge-base/brd/index.json
{
  "generated": "YYYY-MM-DD",
  "brds": [
    { "id": "F001", "title": "Order Registration",      "file": "F001-order-registration.brd.json",  "status": "complete" },
    { "id": "F002", "title": "Approval Workflow",        "file": "F002-approval-workflow.brd.json",   "status": "complete" },
    { "id": "F003", "title": "Master Data",              "file": "F003-master-data.brd.json",         "status": "complete" }
  ]
}
```

---

## From BRD to MDL

Once a BRD is complete, the MDL scripting phase reads it directly:

1. **Domain model script** — read `domainEntities` array → write `CREATE PERSISTENT ENTITY` MDL
2. **Microflow scripts** — read `microflows` array → write `CREATE MICROFLOW` MDL
3. **Page scripts** — read `pages` array → write `CREATE PAGE` MDL
4. **Stub scripts** — read `integrations` array → write `CREATE MICROFLOW STUB_...` MDL

Each BRD becomes 3-5 layered MDL scripts (layer1: domain, layer2: microflows, layer3: pages).
Execute domain model first — microflows and pages reference entities that must already exist.

---

## Tips from ACME01

- **One BRD session at a time.** Don't try to write all 12 BRDs in one session.
  Write F001, validate it, use it to generate MDL, learn what's missing, then write F002.
- **BRDs are living documents.** Add `openQuestions` entries when you discover ambiguity
  during MDL scripting. Resolve them with client, update the BRD.
- **Cross-BRD dependencies.** F001 may use entities from F003 (master data) and F006
  (common components). Write dependency BRDs first. Track in `cross-reference-map.json`.
- **Language note.** BRDs may need to be written in the client's working language rather
  than English — ask at Stage 0, it is not a late-stage detail. The structure is identical
  in any language; only the prose changes. If you do write non-English BRDs, keep entity,
  microflow and page *identifiers* in English so the generated MDL stays readable.
