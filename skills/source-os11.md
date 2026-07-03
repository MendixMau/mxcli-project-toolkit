# Source Platform: OutSystems 11 → Mendix
**Purpose:** OS 11-specific extraction rules, concept mappings, and migration patterns
for use alongside `migration-pipeline.md`.
**Scope:** OutSystems 11 traditional eSpace/module model only. ODC is out of scope.
**Source:** Apex M-0022 — 114 eSpace XML files, 2026-05.

---

## Module Classification

Every OS 11 application has a module naming convention. Classify before extracting.

| Prefix | Type | Mendix target | Extract priority |
|--------|------|---------------|-----------------|
| `M-XXXX_` | Business feature module | Feature module | Phase A (first) |
| `C-XXXX_` | Common / reusable component | Shared utility module | Phase B |
| `T-XXXX_` | Technical / integration | Integration module | Phase B |
| `AppCommon_*` | Framework base module | Base infrastructure | Reference only |
| `BusinessAppCommon_*` | Business framework layer | Reference or thin wrapper | Phase B |
| `CustomerAppCommon_*` | Customer-specific common | Shared module | Phase B |
| `OSF_*` | OutSystems Foundation | Skip — platform runtime | Skip |
| `OutSystemsUI*` | OS UI framework | Skip — use Atlas instead | Skip |
| `RichWidgets` | Legacy OS widgets | Skip | Skip |
| `IdP*` | Identity provider | Reference — use Mendix SSO module | Skip |

**3-tier dependency rule (OS 11):** M → C → AppCommon. Never upward.
Enforce the same direction in Mendix module layering.

**RW vs CW suffix:**
- `_RW` = Reactive Web (modern SPA, strict client/server split)
- `_CW` = Traditional Web / Client Web (older, server-rendered)
Both target the same Mendix web app; note CW modules may have more screen-level server logic.

---

## XML Extraction Schema

Each `.xml` file is one eSpace. Root element: `<ESpace>`.

```xml
<ESpace
  Key="ESpace:EXAMPLEeSpaceKey000001"   ← GUID with type prefix
  Name="M0022_PayerRegist"               ← module name = file name without .xml
  Description="Order & billing registration"        ← often Japanese
  ModuleType="Service"                   ← Service = normal app module
>
```

### Key sections and what to extract

| XML section | OS concept | Extract as |
|-------------|-----------|-----------|
| `<Entities>` | Persistent DB tables | `entity` items |
| `<StaticEntities>` | Lookup tables (enumerations) | `staticEntity` items |
| `<Structures>` | Non-persistent DTOs | `structure` items |
| `<Actions>` | Server actions | `logic` items |
| `<ClientActions>` | Client-side actions | `logic` items (tag: client) |
| `<WebScreens>` | Full pages | `screen` items |
| `<WebBlocks>` | Reusable UI blocks | `webBlock` items |
| `<WebFlows>` | Navigation groups | `webFlow` items |
| `<Timers>` | Scheduled jobs | `timer` items |
| `<ServiceAPIs>` | Exposed REST/SOAP | `serviceApi` items |
| `<Roles>` | Security roles | `role` items |
| `<References>` | Cross-module dependencies | used for cross-ref linking |
| `<SiteProperties>` | Module constants | embedded in module metadata |
| `<ExceptionFlows>` | Custom exceptions | `exception` items |

### Key XML identifier patterns

All OS identifiers use a typed GUID prefix:
```
ESpace:xxx         ← module reference
Entity:xxx         ← entity
EntityAction:xxx   ← CRUD action on an entity (GetForUpdate, Save, etc.)
Action:xxx         ← server action (same-module)
ActionReference:xxx ← cross-module action reference
WebScreen:xxx      ← screen
WebBlock:xxx       ← block
Structure:xxx      ← structure/DTO
StructureReference:xxx ← cross-module structure reference
```

Cross-module references use `ActionReference:` and `StructureReference:` — these require
the key-resolver to map back to the source module and name.

---

## Concept Mapping: OS 11 → Mendix

### Module structure

| OS 11 | Mendix |
|-------|--------|
| eSpace / Module | Module |
| `M-XXXX` business module | Feature module (e.g. `PayerRegistration`) |
| `C-XXXX` common module | Shared utility module |
| `AppCommon_*` base | Base infrastructure module |

### Action types → flow types

| OS 11 | Runs where | Mendix |
|-------|-----------|--------|
| Server Action | Server, DB access | Microflow |
| Client Action | Browser, no direct DB | Nanoflow |
| Service Action | Exposed REST/SOAP endpoint | Microflow + Published REST operation |
| Data Action | Screen-level DB query | Page data source microflow |
| Aggregate | SQL-like query | `retrieve` statement or OQL view |

### DAO pattern

OS 11 organises entity operations in `{Entity}_DAO` folders:

| OS DAO action | Mendix equivalent |
|---------------|------------------|
| `{Entity}_Save` | `ACT_{Entity}_Save` |
| `{Entity}_GetForUpdate` | `GET_{Entity}_ById` |
| `{Entity}_DeleteLogical` | `ACT_{Entity}_SoftDelete` — sets `IsActive = false` |
| `{Entity}_DeletePhysical` | `ACT_{Entity}_Delete` |
| `{Entity}_GetById` | `GET_{Entity}_ById` |

OS uses soft-delete (`IsActive = false`) by default. Preserve in Mendix.

### UI concepts

| OS 11 | Mendix |
|-------|--------|
| Screen | Page |
| Popup Screen | Popup page (Atlas popup layout) |
| Block | Snippet |
| Screen Action | Microflow / nanoflow from button |
| Input Parameter (screen) | Page parameter |
| Local Variable (screen) | NPE attribute (form backing object) |
| Aggregate on screen | Page data source microflow |
| OnInitialize | Page data source microflow (init pattern) |

### Static Entities → Enumerations

| OS 11 | Mendix |
|-------|--------|
| StaticEntity with fixed records | Enumeration |
| `IsAutoNumber=No`, sequences from 10000 | Not needed — enumeration values are string keys |
| Sequence entity (`M_Saiban`) | `Sequence` entity + counter microflow |

### Security model

| OS 11 | Mendix |
|-------|--------|
| Role (eSpace native) | Module role |
| URPM role | User role aggregating module roles |
| Screen permission | Page grant (`GRANT VIEW ON PAGE`) |
| Action permission | Microflow grant (`GRANT EXECUTE ON MICROFLOW`) |

URPM permissions are managed outside the eSpace. Reconstruct grants from the OS
permission matrix when migrating.

---

## Audit Field Standard

Every persistent OS 11 entity carries these 8 fields. Preserve in Mendix:

| OS field | Mendix attribute | Type | Default |
|----------|-----------------|------|---------|
| `IsActive` | `IsActive` | Boolean | `true` |
| `LockVersion` | `LockVersion` | Integer | `0` — increment on every change |
| `CreatedOn` | `CreatedOn` | DateTime | — |
| `CreatedBy` | `CreatedBy` | String(200) | `$currentUser/Name` |
| `CreatedByEMP_ID` | `CreatedByEMP_ID` | String(5) | — |
| `ModifiedOn` | `ModifiedOn` | DateTime | — |
| `ModifiedBy` | `ModifiedBy` | String(200) | — |
| `ModifiedByEMP_ID` | `ModifiedByEMP_ID` | String(5) | — |

---

## Integration Patterns

| OS 11 pattern | Mendix approach |
|--------------|----------------|
| SAP IQ (Sybase) read-only views | External Database Connector (JDBC); case-sensitive column names |
| SAP write-back via integration table | Database Connector → hub table; SAP reads async |
| REST API consumption | Published REST client + microflow |
| HRSystem employee sync | Scheduled microflow + External DB or REST |
| CorpSearch corporate search | REST client (`CompanySearchResult` NPE as response DTO) |
| `AppCommon_MSG` message table | `Common_Utils.Message` entity + `GET_Message_ById` microflow |

### Stub pattern for integrations

All external calls that cannot be implemented in POC:

```mdl
create or modify microflow "Module"."STUB_ExternalSystem_Operation" (
  "Request": "Module"."RequestNPE"
)
returns "Module"."ResultNPE" as $Result
begin
  log warning node 'Module'
    'STUB_ExternalSystem_Operation: skipped (POC stub). Key=' + $Request/KeyField;
  $Result = create "Module"."ResultNPE" (
    "IsSuccess" = true,
    "ResultCode" = 'STUB-001'
  );
  return $Result;
end;
```

Rules: `STUB_` prefix, identical signature to real operation, LOG WARNING + happy-path return.

---

## Message / Error Code Patterns

| OS pattern | Meaning |
|-----------|---------|
| `MSGS####S/W/I/E` | Screen message — Success/Warning/Info/Error |
| `MSGB####S/W/I/E` | Batch message — Success/Warning/Info/Error |

In Mendix: `log info/warning/error node 'ModuleName' 'MSGS0001I: ...'`

---

## BRD Generation Notes — OS 11 Specific

### Module naming translation

| OS name | Mendix module name |
|---------|-------------------|
| `M0022_PayerRegist` | `PayerRegistration` |
| `C0031_ControlMaterialGroupSearch` | `MaterialGroupSearch` |
| `AppCommon_BaseUtils` | `Common_Utils` |
| `BusinessAppCommon_CS` | `BusinessApp_Common` |

Rules: drop `M-`/`C-`/`T-` prefix and number, expand abbreviations, PascalCase.

### Entity naming translation

| OS name | Mendix name |
|---------|------------|
| `ENPayerDetail` | `PayerDetail` (drop `EN` prefix) |
| `ENPayerApplicationHeader` | `PayerApplicationHeader` |
| `ENPayerAreaData` | `PayerAreaData` |

### BRD source inputs per OS module

For each business module BRD, collect:
1. `entities.json` — filter by `module = ModuleName`
2. `logics.json` — filter by `module = ModuleName`
3. `screens.json` — filter by `module = ModuleName`
4. `staticEntities.json` — filter by `module = ModuleName`
5. `cross-reference-map.json` — cross-module dependencies for this module
6. `KB_{ModuleName}_*.md` — if design docs were extracted (Path B)

### Extraction order for BRDs

1. `AppCommon_*` and `C-XXXX` common modules → Common BRDs (no feature deps)
2. `M-XXXX` business modules → Feature BRDs (depend on common)
3. Integration modules (`T-XXXX`) → Integration BRDs (depend on feature entities)
4. Skip: `OSF_*`, `OutSystemsUI*`, `RichWidgets`, `IdP*`

---

## Known Extraction Gaps — OS 11

| Gap type | Cause | Mitigation |
|----------|-------|-----------|
| Cross-module action calls unresolved | `ActionReference:` keys span modules | Run key-resolver across all XMLs together |
| Client action logic missing | Client actions compile to JS, not in XML | Extract from compiled `scripts/` JS files |
| URPM permissions not in eSpace XML | URPM module manages permissions centrally | Extract URPM module separately |
| SAP field mappings | Stored in integration tables, not eSpace | Requires DB schema or integration doc |
| Screen layout detail | XML stores widget tree but not pixel layout | Use screen mockups from design docs |
