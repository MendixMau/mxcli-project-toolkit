# BRD JSON Generation — Prompt Template
**Applies to:** migration or requirements-driven build (works from documents/SME input — no legacy source needed).
**Purpose:** How to synthesise KB files + extracted JSON into BRD (Business Requirements
Document) JSON files — the structured handoff from analysis to MDL scripting.
**Source:** Apex M-0022 — F001–F012 BRDs produced in conversation, 2026-05.

---

## What a BRD file is

A BRD JSON file is a structured, machine-readable summary of ONE feature area.
It combines information from multiple KB files and extracted JSON (screens, entities,
logics) into a format that Claude uses when writing MDL domain model and microflow scripts.

One BRD = one Mendix module (roughly). It contains use cases, domain entities,
microflows to build, pages to build, and integration stubs needed.

---

## File naming convention

```
F{NNN}-{kebab-topic}.brd.json

Examples:
  F001-payer-registration.brd.json
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
  "title": "Payer & Billing Address Registration",
  "modules": ["M0022_PayerRegist"],
  "actors": ["PayerRegisterUser", "SuperUser", "SysAdmin"],

  "useCases": [
    {
      "id": "UC001",
      "title": "View Payer Registration List",
      "actors": ["PayerRegisterUser", "SuperUser"],
      "preconditions": ["User is logged in with appropriate role"],
      "postconditions": ["System displays the payer registration list"],
      "mainFlow": [
        "1. User navigates to PayerRegistration_Overview page",
        "2. System retrieves and displays all PayerApplicationHeader records"
      ],
      "screens": ["PayerRegistration_Overview"],
      "mdlRefs": ["M0022_PayerRegist"]
    }
  ],

  "domainEntities": [
    {
      "name": "PayerDetail",
      "module": "PayerRegistration",
      "persistent": true,
      "sourceOS": "ENPayerDetail",
      "attributes": [
        { "name": "PayerCode",     "type": "String",   "length": 10,  "mandatory": true  },
        { "name": "CustomerCode",  "type": "String",   "length": 10,  "mandatory": false },
        { "name": "CurrencyCode",  "type": "String",   "length": 3,   "mandatory": true  },
        { "name": "IsActive",      "type": "Boolean",                 "mandatory": true  }
      ],
      "auditFields": ["IsActive", "LockVersion", "CreatedOn", "CreatedBy"],
      "associations": [
        {
          "name": "PayerDetail_PayerApplicationHeader",
          "target": "PayerApplicationHeader",
          "type": "ManyToOne",
          "owner": "PayerDetail"
        }
      ]
    }
  ],

  "microflows": [
    {
      "name": "ACT_PayerDetail_Save",
      "module": "PayerRegistration",
      "purpose": "Validates and persists a new payer draft. Returns the created PayerDetail.",
      "params": [{ "name": "Dto", "type": "PayerDetail_Dto" }],
      "returns": "PayerDetail",
      "pattern": "validate-then-save",
      "calls": ["GET_PayerArea_Dto", "ACT_PayerDetail_SaveDraft"],
      "validations": ["SelectedCompanyName not blank", "CurrencyCode not blank", "Deadline not empty"]
    }
  ],

  "pages": [
    {
      "name": "PayerDetail_NewEdit",
      "module": "PayerRegistration",
      "layout": "Atlas_Core.Atlas_Default",
      "purpose": "Data entry form for new payer registration",
      "dataContext": "PayerDetail_Dto",
      "sections": ["OrgChoice", "PayerInfo", "AreaData", "SalesAreaData"],
      "actions": ["ACT_PayerDetail_Save", "ACT_PayerDetail_Cancel"]
    }
  ],

  "integrations": [
    {
      "name": "CorpSearch Corporate Search",
      "type": "REST",
      "stubName": "STUB_ACT_CorpSearch_Execute",
      "stubBehaviour": "Returns hardcoded PayerBase co. result",
      "realTarget": "C-0031 CorpSearch API",
      "apiDoc": "KB_C0031_CorporateSearch.md"
    }
  ],

  "openQuestions": [
    { "id": "D1", "question": "Approval route branching logic", "status": "Resolved", "answer": "Single route J001, no branching" }
  ],

  "sourceKB": [
    "KB_M0022_RequirementsSpec_V5.md",
    "KB_M0022_FieldLabels_EN.md",
    "KB_M0022_QA.md"
  ]
}
```

---

## Automated BRD Scaffolding (run before Step 1)

Before writing BRDs manually, run the automated BRD mapper layer if a code extraction pipeline is available.
This produces a `{ModuleName}.brd.json` scaffold per module in `knowledge-base/brd/`.

```bash
node run.js 3           # brd-mappers/ → knowledge-base/brd/*.brd.json
node generate-report.js # → knowledge-base/extraction-report.html
```

Each auto-generated BRD contains:
- `domainEntities[]` — entities + enumerations with key attributes, associations, mendixType
- `microflows[]` — all logic items with inferred purpose (name-pattern rules: GET_/ACT_/VAL_/CAL_/SUB_), kind (Microflow/Nanoflow/BPTProcess), parameters, call count
- `pages[]` — screens with UI pattern (list/form/detail/mixed), input params, linked logics
- `useCases[]` — **scaffold only** — screen-per-row with all narrative fields as explicit TODOs
- `integrations[]` — exposed APIs (inbound) + external entities (outbound)
- `timers[]` — scheduled events
- `confidence` — high (0 gaps) / medium (1–3) / low (4+)

**Use the HTML report** (`extraction-report.html`) as the review surface — click any module to inspect its BRD.
Use the auto-generated BRD as the starting point for Step 3 (Claude enrichment prompt).
The use-case narrative is never auto-generated — that requires business input.

---

## Step 1 — Decide BRD scope

Before prompting, decide the BRD boundaries. One BRD per major feature area.
Use the extracted `screens.json` and `entities.json` to group by functional cohesion.

A good BRD boundary = one Mendix module. Aim for 3-8 use cases per BRD.

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
This BRD covers: [feature area, e.g. "Payer Registration — the main registration flow"]
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

## Mendix naming conventions:
- Entity: PascalCase, no EN prefix (ENPayerDetail → PayerDetail)
- Module: PascalCase (M0022_PayerRegist → PayerRegistration)
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

---

## Step 5 — Maintain the BRD index

```json
// extraction/knowledge-base/brd/index.json
{
  "generated": "YYYY-MM-DD",
  "brds": [
    { "id": "F001", "title": "Payer Registration",      "file": "F001-payer-registration.brd.json",  "status": "complete" },
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

## Tips from M-0022

- **One BRD session at a time.** Don't try to write all 12 BRDs in one session.
  Write F001, validate it, use it to generate MDL, learn what's missing, then write F002.
- **BRDs are living documents.** Add `openQuestions` entries when you discover ambiguity
  during MDL scripting. Resolve them with client, update the BRD.
- **Cross-BRD dependencies.** F001 may use entities from F003 (master data) and F006
  (common components). Write dependency BRDs first. Track in `cross-reference-map.json`.
- **Language note.** The Apex BRDs were written in Chinese (client preference).
  For other clients, write in English. The structure is the same.
