# OutSystems → Mendix Migration: Source Analysis Pipeline

This skill covers the full pipeline from raw OutSystems XML exports to structured BRD and knowledge-base documents, ready for Mendix implementation. It is the **analysis phase** (Phase 1) of a migration engagement. The Mendix implementation phase (MDL generation, Studio Pro work) is covered in `skills/migrate-general.md`.

**Scope:** OutSystems 11 traditional model (eSpaces, Reactive Web, Traditional Web). Not applicable to ODC.

---

## Folder Contents

```
OS-migration-skills/
├── migrate-outsystems.md          ← this file — pipeline overview + demo guide
├── skills/
│   ├── migrate-general.md         ← OS11 → Mendix concept mapping + MDL implementation rules
│   └── assess-migration.md        ← generic assessment template (entities, logic, pages, security)
├── pipeline/
│   ├── run.js                     ← orchestrator: phase 1 (sample), phase 2 (extract), phase 3 (generate)
│   ├── package.json               ← npm dependencies (fast-xml-parser, tree-sitter, glob)
│   ├── extractors/
│   │   ├── xml-extractor.js       ← parses OutSystems eSpace XML → structured JSON
│   │   ├── cs-extractor.js        ← parses C# generated code (tree-sitter)
│   │   └── js-extractor.js        ← parses JavaScript client code (tree-sitter)
│   ├── generators/
│   │   ├── brd-mappers/           ← BRD generation (Phase 3 — primary output)
│   │   │   ├── index.js               ← orchestrates BRD mappers, writes brd/*.brd.json
│   │   │   ├── domain-entity-mapper.js
│   │   │   ├── microflow-mapper.js
│   │   │   ├── page-mapper.js
│   │   │   ├── use-case-mapper.js
│   │   │   └── integration-mapper.js
│   │   ├── mappers/               ← MDL generation (Phase 4 — after BRD sign-off)
│   │   │   ├── entity-mapper.js       ← Entity → CREATE PERSISTENT ENTITY MDL
│   │   │   ├── enumeration-mapper.js
│   │   │   ├── microflow-mapper.js
│   │   │   ├── page-mapper.js
│   │   │   ├── service-api-mapper.js
│   │   │   ├── structure-mapper.js
│   │   │   ├── timer-mapper.js
│   │   │   └── ext-entity-mapper.js
│   │   └── lib/                   ← shared type converter, structure index helpers
│   └── lib/                       ← merger, interfaces, cross-reference builder
└── sample-outputs/
    ├── summary.md                 ← construct counts + gap report summary
    ├── entities.json              ← extracted entity knowledge base
    ├── screens.json               ← extracted screen knowledge base
    └── brd/
        ├── index.json             ← BRD feature index
        └── F001-payer-registration.brd.json  ← worked example: full BRD for one feature
```

---

## The Pipeline — Three Phases

### Phase 1 · Sample (fast, optional)

Samples a few XMLs to produce `samples/schema.json` — a structural fingerprint of the XML format. Use this first to orient yourself before full extraction.

```bash
node run.js 1 xml
```

Output: `pipeline/samples/xml-schema.json`

### Phase 2 · Extract (the main step)

Runs the full `xml-extractor.js` against all XML files, then the merger builds the knowledge base.

```bash
node run.js 2 xml
```

Output written to `knowledge-base/`:
- `entities.json` — all persistent + static entities with attributes, types, audit fields
- `logics.json` — all server actions, client actions, data actions (5,000+ for a large app)
- `screens.json` — all screens + blocks with widget trees
- `structures.json` — all structures (map to NPEs)
- `serviceApis.json` — exposed REST/SOAP operations
- `timers.json` — scheduled events
- `roles.json` — permission matrix
- `cross-reference-map.json` — caller/callee graph across all constructs
- `summary.md` — counts + gap report

### Phase 3 · Generate BRD JSON (synthesis step)

Runs the BRD mappers over the knowledge base and produces one structured BRD JSON per module, plus a self-contained HTML report for human review.

```bash
node run.js 3
```

Output: `knowledge-base/brd/{ModuleName}.brd.json` (one per module, 113+ files)

Each BRD file contains:
- `confidence` — high / medium / low (based on unresolved gap count)
- `summary` — entity, microflow, page, use case, integration, timer counts
- `domainEntities` — persistent entities + enumerations with key attributes + associations
- `microflows` — all server/client actions with inferred purpose, kind, parameters, call count
- `pages` — screens with UI pattern (list/form/detail), input params, linked logics
- `useCases` — scaffold per screen with TODO stubs for business review
- `integrations` — exposed REST APIs (inbound) + external entities (outbound)
- `timers` — scheduled events with schedule + description
- `openGaps` — list of unresolved cross-references

Then generate the interactive HTML report:

```bash
node generate-report.js
```

Output: `knowledge-base/extraction-report.html` — open in browser. Shows:
- Dashboard with stat cards, construct breakdown, BRD coverage
- Gap heatmap (top 30 modules by gap count)
- Per-module drill-down with BRD summary + raw extraction data

### Phase 4 · MDL Generation (future — after BRD sign-off)

After BRDs are reviewed and approved with the business, MDL scripts are generated from the agreed BRDs.
This is a separate step covered in `skills/migrate-general.md`.

---

## What the xml-extractor Pulls Out

The `xml-extractor.js` parses an OutSystems eSpace XML and extracts these construct types:

| XML element | Extracted as | KB JSON key |
|---|---|---|
| `Entity` + `Attribute` | Persistent entity with typed attributes | `entities` |
| `StaticRecord` / `StaticRecordAttributeValue` | Static lookup table | `staticEntities` |
| `Structure` + `RecordType` | DTO / structure definition | `structures` |
| `Action` (server-side) | Server Action → microflow candidate | `logics` |
| `ClientAction` | Client Action → nanoflow candidate | `logics` |
| `DataAction` / `DataScreenAction` | Screen data source | `dataScreenActions` |
| `WebScreen` | Full page with widget tree | `screens` |
| `WebBlock` | Reusable block (snippet) | `webBlocks` |
| `WebFlow` | Navigation flow / module grouping | `webFlows` |
| `ServiceAction` | Exposed REST/SOAP endpoint | `serviceApis` |
| `Timer` | Scheduled event | `timers` |
| `Role` | Security role | `roles` |
| `SiteProperty` | App constant / configuration | `siteProperties` |
| `SessionVariable` | Session-scoped variable | `sessionVariables` |
| `UserException` | Custom exception type | `exceptions` |
| `SQL` | Inline SQL (Advanced Query) | embedded in logics |
| `Reference` | Inter-module dependency | `references` |

### Why not go straight to a BRD document from XML?

The XML contains the **what** (constructs and their names) but not the **why** (feature grouping, business intent, actor mapping). The intermediate JSON step:

1. Normalises encoding: base64 assets, attribute-prefixed keys, array-vs-object ambiguities
2. Decodes HTML entities in descriptions
3. Classifies constructs (e.g. binary attributes → file storage vs blob vs image)
4. Builds cross-references between callers and callees
5. Produces a format Claude can read in full context without the raw XML noise

---

## What the Mappers Do

Each mapper is a single-concern transform from extracted JSON → Mendix-ready representation:

### entity-mapper.js
- Classifies `Binary Data` attributes as File (has FileName/MimeType companions), Image (name matches picture/photo/icon), or Blob (raw data)
- File entities → `EXTENDS System.FileDocument`, drop Binary
- Pure image entities → `EXTENDS System.Image`, drop Binary
- Large business entities with one image attr → split into `*_Picture EXTENDS System.Image`
- Maps OS system entities (`User`, `Group`, `Tenant`) to Mendix equivalents
- Preserves the 8-field audit standard (IsActive, LockVersion, CreatedOn/By, ModifiedOn/By)

### enumeration-mapper.js
- Converts Static Entity records to enumeration values
- Preserves integer codes as caption metadata (Mendix enums are string keys)
- Sequences with `IsAutoNumber=No` and 10000+ seeds → documents the drift-prevention intent

### microflow-mapper.js
- Server Action → Microflow (applies `ACT_` / `GET_` / `VAL_` / `CAL_` / `SUB_` naming)
- Client Action → Nanoflow
- Data Action → page data source microflow pattern
- DAO pattern detection: `{Entity}_Save`, `{Entity}_GetForUpdate`, `{Entity}_DeleteLogical` → standardised MDL signatures
- SAP integration actions → `STUB_SAP_*` pattern

### page-mapper.js
- Screen → Page with layout inference (popup vs full-page, based on `IsPopup` attribute)
- Widget tree walk: maps OS widget types to Mendix equivalents (TableRecords→ListView, EditRecord→DataView, etc.)
- Screen Input Parameters → Page parameters
- Local Variables → NPE attributes (form backing object pattern)
- OnInitialize → init microflow data source

### structure-mapper.js
- Structure → Non-Persistent Entity (NPE)
- Used as DTOs for SAP responses, search results, form backing objects
- Named with `_Dto` suffix

### service-api-mapper.js
- ServiceAction → Published REST operation with HTTP method inference
- Input/output parameter types mapped to JSON schema

### timer-mapper.js
- Timer → Scheduled Event with interval + timezone metadata

---

## Demo Flow (Terminal + VS Code Side-by-Side)

This is the recommended recording setup:

**Left pane — VS Code** open on this `OS-migration-skills/` folder:
- Show the XML in `../OS-ExtractedXML/M0022_PayerRegist.xml` (raw, incomprehensible)
- Show the extractors in `pipeline/extractors/xml-extractor.js`
- Show the mappers in `pipeline/generators/mappers/`
- Show the BRD output in `sample-outputs/brd/F001-payer-registration.brd.json`

**Right pane — Terminal** running the pipeline:

```bash
cd <path-to-your-workspace>/extraction   # set to your local clone — see pipeline/config.json

# Phase 2: full extraction (60 seconds on the full Apex project)
node run.js 2 xml

# Phase 3: BRD generation
node run.js 3
```

**Claude chat** (open in any window):

> "I've just run the extraction pipeline on an OutSystems 11 application. The results are in `extraction/knowledge-base/`. Look at `summary.md` for the scale, then look at `brd/F001-payer-registration.brd.json`. Explain what this feature does, who uses it, and what Mendix constructs we'd need to implement it."

---

## Prompt Sequence for a New Engagement

Use these prompts in order when starting a real migration engagement:

### Step 1 — Orient from the XML

> "I have OutSystems 11 XML export files in `[path]`. Look at two or three of them and tell me: what modules are here, what is the application domain, and what is the rough scale (entity count, screen count, integration points)?"

### Step 2 — Run the extraction

> "Run Phase 2 of the extraction pipeline: `node run.js 2 xml` from the `extraction/` directory. Then summarise `knowledge-base/summary.md`. How many entities, screens, logics, and cross-references were found? Are there any gaps?"

### Step 3 — Understand the data model

> "Look at `knowledge-base/entities.json`. Which entities are persistent business entities (not audit, not system)? Group them by likely business domain. Which ones have SAP integration patterns (external keys, IQ_* prefixes)?"

### Step 4 — Understand the feature map

> "Look at `knowledge-base/brd/index.json`. What are the 12 feature areas identified? For each one, summarise the business purpose in one sentence."

### Step 5 — Deep-dive a feature

> "Look at `knowledge-base/brd/F001-payer-registration.brd.json`. Walk me through every use case: who does what, what screens are involved, what business rules apply, and what open questions remain. Use the confidence flags to tell me where the evidence is strong vs uncertain."

### Step 6 — Reconcile with documents (Stream B)

> "I have process documents in `Share/converted/`. Read the PDF for the Payer Registration feature and compare it against `brd/F001-payer-registration.brd.json`. What does the source code show that the document doesn't mention? What does the document clarify that the code doesn't make obvious?"

### Step 7 — Plan the Mendix implementation

> "Based on F001, what Mendix entities, enumerations, and microflows would we need? Apply the conventions from `skills/migrate-general.md`: ACT_/GET_/VAL_ naming, NPE form backing pattern, stub pattern for SAP calls, 8-field audit standard."

---

## Key Insight for the Demo

> **Source code is the gold standard.** It shows what the system actually does — not what people remember it doing.

The XML pipeline makes this concrete:
- The raw XML is unreadable → the extractor makes it structured
- The JSON is complete but flat → the mappers add business meaning
- The BRD is readable and traceable → Claude can reason about it and plan Mendix implementation
- Gaps are made explicit (266 in the Apex project) → confidence is honest, not hidden

---

## Related Skills

- [migrate-general.md](./skills/migrate-general.md) — OS11→Mendix concept mapping, MDL implementation rules, known mxcli bugs
- [assess-migration.md](./skills/assess-migration.md) — Generic assessment template for any platform
