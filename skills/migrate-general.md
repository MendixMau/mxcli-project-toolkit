# General Migration to Mendix Skill
**Applies to:** migration.

Guidance for migrating any legacy application to Mendix using MDL and mxcli. Platform-agnostic process, with an OutSystems 11 section at the end.

**Scope note — OutSystems version:** This skill covers **OutSystems 11 (traditional eSpace/module model)**. ODC (OutSystems Developer Cloud) has a fundamentally different architecture (cloud-native, REST-first, no eSpaces, no URPM) and is out of scope.

## When to Use This Skill

- Planning a migration from any legacy platform (OutSystems, K2, Oracle Forms, SAP WebDynpro, etc.) to Mendix
- Deciding script layering, design order, and Studio Pro handoffs
- Applying the stub pattern for external integrations
- Understanding which operations must go through Studio Pro vs mxcli

---

## 1. Correct Design Order — CRITICAL

**Domain → page sketch → logic + pages together.**

Do NOT write microflow signatures before sketching the page structure. Page design determines microflow signatures, not the other way around.

### Why this matters

A microflow called from a page button can only receive **entity objects** — not individual primitives (String, Integer, etc.). The objects available to that button depend on which data views enclose it on the page. Designing microflows before pages means guessing what objects are in scope, and the guess is often wrong.

**Concrete failure:** `ACT_OrderCustomerBase_Create` was initially designed with 8 individual String parameters (CompanyName, PostalCode, etc.). The correct design is `(Header: ApplicationCommonHeader, SearchResult: CompanySearchResult)` — two objects the page already has in scope. The 8-string version required a refactor.

### Design order per feature

1. Review source screenshots / requirements for this feature
2. Sketch page data view nesting: which DV holds which object, what each button has in scope
3. Remember: a button inside a nested DV has access to objects from **all enclosing DVs**, not just the innermost one
4. Derive microflow parameter signatures from the sketch
5. Write and apply microflows (mxcli)
6. Build pages to match (Studio Pro or mxcli)

---

## 2. Layered Script Approach

Separate domain model changes from logic changes into distinct script layers. Never mix them.

```
mdlsource/
  layer1/   ← domain model only (entities, associations, enumerations)
  layer2/   ← microflows only (no entity/association creation)
```

### Why separation is mandatory

**mxcli BUG-01 (MPR corruption):** If you drop an attribute via `alter entity drop attribute` after microflows have been applied, those microflows store the attribute's internal UUID in BSON. The dropped UUID leaves dangling references that cause `KeyNotFoundException` when Studio Pro or mxbuild loads the project.

**Rule:** Apply ALL domain model changes (layer1) before applying any microflows (layer2). If you need to add or drop an entity/attribute after microflows exist, do it in Studio Pro, not mxcli.

### Script naming convention

```
layer1/01-module-name.mdl       ← entities + enumerations + intra-module assocs
layer1/security-setup.mdl       ← roles + grants (last in layer1)
layer2/01-enum-additions.mdl    ← any new enumerations needed for microflows
layer2/09-module-rewrite.mdl    ← microflows, numbered by dependency order
```

---

## 3. Stub Pattern for External Integrations

All external calls that cannot be implemented in the POC follow this pattern:

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

**Rules:**
- Name prefix: `STUB_` — makes stubs searchable and distinguishable
- Signature: identical to the real operation (same params + return type) — callers need no changes when the stub is replaced
- Body: LOG WARNING + hardcoded happy-path return
- Phase 1 real implementation: replace the body only, callers unchanged

---

## 4. NPE as Form Backing Object (Dto Pattern)

A **Non-Persistent Entity (NPE)** is an in-memory entity never stored in the database. In Mendix, NPEs are used as form backing objects — the page data view binds to one, the user fills in fields, and a button passes the object to a microflow.

The suffix `_Dto` marks these objects in this project.

### Lifecycle

1. **Init microflow** (`ACT_Entity_InitNew`) — creates NPE in memory, sets defaults, returns it. Page calls this as its data source.
2. **Page data view** — bound to the NPE. All form widgets bind to NPE attributes.
3. **Button calls microflow** — passes NPE object (`$Dto`). Microflow reads `$Dto/AttributeName` and creates/updates persistent entities.
4. **NPE is never committed** — lives only for the page session.

### NPE associations

NPEs can have associations to other NPEs or persistent entities. Navigation works the same as for persistent entities in retrieve WHERE clauses and XPath expressions.

**Cross-module NPE associations can be created via mxcli** — BUG-02 is fixed in v0.13.0 (see §6).

---

## 5. Microflow Naming Conventions

| Prefix | Purpose | Example |
|--------|---------|---------|
| `ACT_` | Action — creates/modifies persistent state | `ACT_OrderDetail_SaveDraft` |
| `GET_` | Query — returns object(s), no side effects | `GET_OrderDetail_Dto` |
| `VAL_` | Validation — returns Boolean, fires validation feedback | `VAL_PaymentTerm` |
| `CAL_` | Calculation — returns derived value, no side effects | `CAL_AccountGroup` |
| `SUB_` | Sub-flow — internal helper, not called from pages | `SUB_BuildSAPRequest` |
| `STUB_` | Stub — placeholder for external call, same signature | `STUB_SAP_DuplicateCheck` |

---

## 6. mxcli Execution Bugs — Known Issues

### BUG-01: `alter entity drop attribute` with access rules → MPR corruption

**Never drop an attribute via mxcli when the entity has access rules.**

Access rules store per-attribute UUID pointers in BSON. mxcli does not update them when the attribute is dropped, leaving dangling references that cause `KeyNotFoundException` when Studio Pro loads the project.

**Fix:** Drop attributes in Studio Pro's domain model editor only.

### BUG-02: `create association` for cross-module associations → MPR corruption — **FIXED in v0.13.0**

`CREATE ASSOCIATION` for cross-module associations now works correctly. No Studio Pro handoff needed.

**Inspection gap (still applies):** `SHOW ASSOCIATIONS IN Module` does NOT show cross-module associations. Use `SHOW ASSOCIATIONS` (global) to verify they were created.

### BUG-03: SQLITE_BUSY mid-script — partial apply

If `exec` fails mid-script, already-created objects remain in the MPR. The next exec attempt will fail on the first object that already exists.

**Fix:** Identify what was created (`SHOW ENTITIES IN Module`, `SHOW ASSOCIATIONS`), write a patch script containing only the missing objects, apply the patch.

### CE0854: Association `set` on wrong entity (direction error)

`set $Entity/Module.AssocName = $Other` must be called on the entity that **owns the FK column** — the `from` entity in the association definition (`owner Default` means FK is on the `from` side).

```mdl
-- Association: OrderAreaData_OrderDetail
-- FROM = OrderAreaData (FK is here), TO = OrderDetail
-- CORRECT: set on the FROM entity (OrderAreaData)
set $OrderAreaData/OrderRegistration.OrderAreaData_OrderDetail = $OrderDetail;

-- WRONG: set on the TO entity
set $OrderDetail/OrderRegistration.OrderAreaData_OrderDetail = $OrderAreaData; -- CE0854
```

Use `DESCRIBE ASSOCIATION Module.Name` to check which entity is `from`.

---

## 7. Studio Pro Handoffs — What Cannot Be Done via mxcli

| Operation | Why mxcli can't do it | Studio Pro action |
|---|---|---|
| Drop attribute on entity with access rules | BUG-01 | Domain model editor → select attribute → Delete |
| ~~Create cross-module association~~ | ~~BUG-02~~ — fixed in v0.13.0, use `CREATE ASSOCIATION` | — |
| CE0066 after GRANT scripts | Security hash not updated by mxcli | Domain model → "Update security" → Ctrl+S |
| Java action body | mxcli creates stub only | `javasource/module/actions/ActionName.java` |
| Workflow definition (J001 steps) | Not MDL-generatable | Studio Pro workflow editor |
| Module mark-as-UI-resources | Not MCP-reachable | Right-click module → Mark as UI resources module |

---

## 8. Security Setup Pattern

Apply security in this order:

1. **Layer1 domain scripts** — entities + access rules together (GRANT on entity)
2. **security-setup.mdl** — module roles, user roles, demo users, microflow grants
3. **After any GRANT script** — `mx check` will fire CE0066 ("security hash mismatch")
4. **Fix CE0066** — Studio Pro → open any domain model → click "Update security" → Ctrl+S

CE0066 cannot be resolved via mxcli. It requires the Studio Pro security hash reconciliation step. This is always needed after applying GRANT scripts and is not a sign of an error in the script.

---

## 9. OutSystems 11 Platform Concepts → Mendix Mapping

> **Scope:** OutSystems 11 traditional model (eSpaces, URPM, Reactive Web / Traditional Web modules). ODC is a different platform and is not covered here.

### Module / eSpace structure

| OS 11 concept | Description | Mendix equivalent |
|---|---|---|
| eSpace / Module | Unit of deployment, has its own entities, actions, UI | Mendix module |
| `M-XXXX` prefix | Business application module | Business feature module (e.g. `OrderRegistration`) |
| `C-XXXX` prefix | Common / reusable component | Shared utility module (e.g. `Customer_Common`, `Common_Utils`) |
| `AppCommon_*` | Framework-level base module | Base infrastructure module |
| `T-XXXX` prefix | Technical/integration module | Integration module (e.g. `SAP_Integration`) |
| RW suffix | Reactive Web module (modern SPA) | Standard Mendix web app (Atlas responsive) |
| CW suffix | Traditional Web / Client Web (older pattern) | Same target; note: RW has stricter client/server action split |

**3-tier architecture rule (OS 11):** Business modules (M) may call Common modules (C), which may call base components — but never upward. A `C-` module cannot reference an `M-` module.

**Mendix equivalent:** Enforce the same dependency direction via module layering. Lower modules (Common_Utils, BusinessApp_Common) must not import from higher modules (OrderRegistration). Mendix does not enforce this automatically — apply it as a design rule.

### Action types → Mendix flow types

| OS 11 action type | Where it runs | Mendix equivalent |
|---|---|---|
| **Server Action** | Server-side, database access, long operations | **Microflow** |
| **Client Action** | Client-side (browser), no direct DB access, fast UI logic | **Nanoflow** |
| **Service Action** | Exposed as REST/SOAP endpoint | Microflow + Published REST operation |
| **Data Action** | Screen-level database query (like an Aggregate bound to a screen) | Page data source microflow |
| **Aggregate** | SQL-like query with grouping/filtering, used in screens or actions | `retrieve` statement or OQL view entity |

**Key implication:** If an OS screen uses a Data Action to load its data, the equivalent Mendix page needs a data source microflow. If OS logic is in a Client Action, consider whether a nanoflow is sufficient or a server round-trip (microflow) is needed.

### DAO pattern → Mendix CRUD naming

OS 11 typically organises entity operations in a `{Entity}_DAO` folder with standard actions:

| OS DAO action | Mendix equivalent |
|---|---|
| `{Entity}_Save` | `ACT_{Entity}_Save` microflow (create or update) |
| `{Entity}_GetForUpdate` | `GET_{Entity}_ById` or retrieve by key |
| `{Entity}_DeleteLogical` | `ACT_{Entity}_SoftDelete` — sets `IsActive = false` |
| `{Entity}_DeletePhysical` | `ACT_{Entity}_Delete` — actual `delete $Entity` |
| `{Entity}_GetById` | `GET_{Entity}_ById` — retrieve by PK or business key |

OS uses soft-deletes (`IsActive = false`) by default. Preserve this pattern in Mendix entities.

### UI concepts → Mendix equivalents

| OS 11 concept | Description | Mendix equivalent |
|---|---|---|
| Screen | Full page, URL-routable | Page |
| Popup Screen | Modal dialog | Popup page (Atlas popup layout) |
| Block | Reusable UI component with own logic | Snippet |
| Widget | Individual UI control | Widget |
| Screen Action | Button/event handler on a screen | Microflow or nanoflow called from button |
| Input Parameter (screen) | Data passed into a screen | Page parameter |
| Local Variable (screen) | Temporary in-memory data on screen | NPE attribute (form backing object) |
| Aggregate (on screen) | Data source query | Page data source microflow or XPath retrieve |
| OnInitialize | Screen startup action | Page data source microflow (init pattern) |

### Static Entities → Enumerations

OS 11 Static Entities (lookup tables with fixed records) map to Mendix enumerations. Important nuance:

- OS Static Entities with `IsAutoNumber=No` and sequences starting at 10000 — this prevents environment drift where auto-number IDs differ between dev/test/prod
- In Mendix, enumeration values are string keys, not integers — no drift risk
- Sequences (like `M_Saiban`) map to a Mendix `Sequence` entity with a counter attribute, incremented by a dedicated microflow

### Security model

| OS 11 concept | Mendix equivalent |
|---|---|
| Role (OS native) | Module role |
| URPM (Universal Role Permission Management) | User role aggregating module roles |
| Permission | Entity access rule / microflow grant |
| Screen permission | Page grant (`GRANT VIEW ON PAGE`) |
| Action permission | Microflow grant (`GRANT EXECUTE ON MICROFLOW`) |

OS 11 projects using URPM have their permissions managed outside the eSpace (in the URPM module). When migrating, map each URPM role to a Mendix user role and reconstruct the grants from the OS permission matrix.

### Audit field standard

OS 11 applications typically carry an 8-field audit standard on persistent entities:

| OS field | Type | Mendix equivalent |
|---|---|---|
| `IsActive` | Boolean | `IsActive: Boolean DEFAULT true` |
| `LockVersion` | Integer | `LockVersion: Integer DEFAULT 0` — increment on every change |
| `CreatedOn` | DateTime | `CreatedOn: DateTime` |
| `CreatedBy` | Text (name) | `CreatedBy: String` — use `$currentUser/Name` |
| `CreatedByEMP_ID` | Text (5-char) | `CreatedByEMP_ID: String(5)` |
| `ModifiedOn` | DateTime | `ModifiedOn: DateTime` |
| `ModifiedBy` | Text (name) | `ModifiedBy: String` |
| `ModifiedByEMP_ID` | Text (5-char) | `ModifiedByEMP_ID: String(5)` |

### Integration patterns

| OS 11 pattern | Mendix approach |
|---|---|
| SAP IQ (Sybase) — read-only views | External Database Connector (JDBC); case-sensitive column names |
| SAP write-back via integration table | Database Connector writes to hub table; SAP reads asynchronously |
| REST API consumption | Published REST client + microflow |
| HRSystem employee sync | Scheduled microflow + External DB or REST |
| CorpSearch corporate search | REST client (`CompanySearchResult` NPE as response DTO) |
| AppCommon_MSG message table | `Common_Utils.Message` entity + `GET_Message_ById` microflow |

### Message / error code naming

OS 11 uses structured message codes:

| Pattern | Meaning |
|---|---|
| `MSGS####S/W/I/E` | Screen message, Severity (Success/Warning/Info/Error) |
| `MSGB####S/W/I/E` | Batch message, Severity |

In Mendix, use LOG node names matching the module and severity via `log info/warning/error node 'ModuleName' 'MSGS0001I: ...'`.
