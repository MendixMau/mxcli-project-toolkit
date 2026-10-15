# General Migration to Mendix Skill
**Applies to:** migration.

Guidance for migrating any legacy application to Mendix using MDL and mxcli. Platform-agnostic process; OutSystems 11 specifics live in `skills/source-os11.md`.

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

**Concrete failure:** `ACT_OrderCustomerBase_Create` was initially designed with 8 individual String parameters (CompanyName, PostalCode, etc.). The correct design is `(Header: ApplicationCommonHeader, SearchResult: PartnerSearchResult)` — two objects the page already has in scope. The 8-string version required a refactor.

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

→ see `skills/learned-microflow-patterns.md` § NPE as Form Backing Object ("Dto" Pattern) — `_Dto` naming, the four-step lifecycle (init microflow, e.g. `ACT_Entity_InitNew`), never committed.

### NPE associations

NPEs can have associations to other NPEs or persistent entities. Navigation works the same as for persistent entities in retrieve WHERE clauses and XPath expressions. Cross-module NPE associations are created via mxcli like any other (`bin/bug-lookup.sh BUG-02`).

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

### Cross-module associations — inspection gap

`CREATE ASSOCIATION` handles cross-module associations (history: `bin/bug-lookup.sh BUG-02`). **Inspection gap:** `SHOW ASSOCIATIONS IN Module` does NOT show cross-module associations. Use `SHOW ASSOCIATIONS` (global) to verify they were created.

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

→ see `skills/source-os11.md` § Concept Mapping: OS 11 → Mendix (plus its Audit Field Standard, Integration Patterns and Message / Error Code Patterns sections) — when the legacy source is OutSystems 11.
