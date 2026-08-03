# mxcli Bug Report

Issues encountered during AI-assisted Mendix development using mxcli + MDL.
Collected for reporting to the mxcli team.

---

## Provenance convention — read before adding an entry

Every finding carries `**Discovered:**` and `**Reproducible:**` fields so a reader can
judge whether it is *confirmed* or *theoretical*. That judgement needs the **mxcli
version, the Mendix version, the date, and what was actually exercised**. It does not
need the client's name — no reader of this file can go and check that project, so the
name carries zero evidential value while carrying full NDA risk.

**Refer to projects descriptively, never by name or repo:**

| Instead of | Write |
|---|---|
| a client engagement codename | `a WMS conversion project` |
| a repo name (`Foo-Bar-main`) | `a PLM parts-flow project` |
| a source-analysis repo | `a Java/Angular analysis project` |
| the demo/reference app | `a WMS demo project` |

**Keep distinctness when it is the evidence.** "Reproduced independently on two projects"
is a stronger claim than "reproduced" — so if two *different* projects hit the same bug,
say so ("seen in both a WMS conversion project and a Java/Angular analysis project").
Collapsing them to "a project" throws away the corroboration.

`bin/check-no-client-data.sh` blocks the commit if a denylisted name reaches this file.

---

## BUG-01: `alter entity drop attribute` causes MPR corruption when entity has access rules

**Severity:** Critical — project becomes unopenable in Studio Pro and mxbuild  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact version unrecorded)  
**Retested on v0.13.0:** No — not yet verified fixed or open

### Steps to reproduce
1. Apply security GRANTs on a persistent entity with `read *, write *` (e.g. via `grant Role on Module.Entity (create, read *, write *)`)
2. Run `alter entity "Module"."Entity" drop attribute "AttrName";` via mxcli

### Expected behavior
Attribute is dropped cleanly; project remains loadable.

### Actual behavior
mxbuild and Studio Pro fail to load the project with:
```
KeyNotFoundException: The given key 'd01b1aff-6cf9-49bb-887f-1b5ba49b953c' was not present in the dictionary.
   at UnitContentsLoader.ConstructObjectInternalAndResolvePendingPointers(...)
```

### Root cause (inferred)
Entity access rules store per-attribute UUID pointers in the BSON unit file.
`alter entity drop attribute` removes the attribute from the entity definition but does NOT
update the access rule's internal attribute pointer list. mxbuild fails when it tries to
resolve the now-dead UUID pointer during project load.

Studio Pro's own "delete attribute" UI operation handles this correctly (updates all
references atomically). mxcli does not.

### Workaround
Do not drop attributes that have access rules applied to them via mxcli.
Drop attributes manually in Studio Pro instead.

---

## BUG-02: `create association` for cross-module associations corrupts the MPR (CRITICAL)

**Status: FIXED in mxcli v0.13.0** — `CREATE ASSOCIATION` for cross-module associations works correctly. Verified 2026-07-04 on a large-source WMS project (Mendix 11.12.0): 0 CE errors, project loads cleanly in mxbuild. **No Studio Pro handoff required.**

~~**Severity:** Critical — project becomes unopenable in Studio Pro and mxbuild~~  
~~**Reproducible:** Yes, consistently~~  
~~**Mendix version:** 11.10.0~~  
**mxcli version when fixed:** v0.13.0 (codec engine rewrite)

### Fix history
Fixed in the RnD mxcli changelog under: `CE1613 and Studio Pro crash from invalid CrossAssociation BSON (ParentConnection/ChildConnection fields) (#50)`. A follow-up fix landed in v0.9.0: `Cross-module associations preserved on CREATE object actions (#502)`.

### Original root cause (for reference only)
mxcli was embedding `DomainModels$EntityImpl` objects from other modules using internal UUIDs that Studio Pro's unit loader could not resolve, causing `KeyNotFoundException`. This is now handled correctly by the `CrossModuleAssociation` type in the association executor.

### Syntax (confirmed working)
```mdl
CREATE ASSOCIATION ModuleA."EntityA_EntityB"
  FROM ModuleA."EntityA" TO ModuleB."EntityB"
  TYPE Reference
  OWNER Default;
```

---

## BUG-03: MDL `retrieve ... where [AssocName = $Param]` XPath syntax not documented / not obvious

**Severity:** Low — developer friction  
**Reproducible:** Yes  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No

### Issue
When writing XPath constraints in MDL `retrieve` statements, attribute names and association
names must be **unquoted**. Quoting them causes CE0161 or silent wrong-result errors.

**Wrong (causes error):**
```
retrieve $Obj from "Module"."Entity" where [Module.Assoc = $OtherObj]
-- attribute access: $Obj/"AttributeName"  ← wrong, causes CE errors
```

**Correct:**
```
retrieve $Obj from "Module"."Entity" where [Module.Assoc = $OtherObj]
-- attribute access: $Obj/AttributeName  ← correct (unquoted)
```

The MDL documentation and error messages do not make this distinction clear.
Generated code (e.g. from AI) tends to quote identifiers everywhere for safety,
which causes subtle bugs specifically in XPath and attribute access expressions.

---

## BUG-04: `grant execute` on microflows in modules with no roles silently fails or errors

**Severity:** Low — confusing behavior  
**Reproducible:** Yes  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No

### Steps to reproduce
1. Create a stub module (e.g. `Customer_Lookups`) with no module roles defined
2. Create a microflow in that module
3. Run `grant execute on microflow "Customer_Lookups"."MyFlow" to "Customer_Lookups"."User";`

### Actual behavior
Error: `module role not found: Customer_Lookups.User`
The script aborts at this point; subsequent statements in the same script do not execute.

### Expected behavior
Either a warning (not a fatal error) so the script continues, or clearer documentation
that grant statements require roles to exist first.

### Workaround
Check module roles before writing grant statements. Skip grants for modules with no roles.

---

## BUG-05: Parameter names in MDL must NOT include `$` in declaration

**Severity:** Medium — causes cryptic errors if not known  
**Reproducible:** Yes  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No — likely a grammar/parser rule, unlikely to change

### Issue
MDL parameter declarations use bare names, but references in the body use `$` prefix.
This is inconsistent with how variables are declared (`declare $Var`) and confusing
for developers familiar with other languages.

**Wrong:**
```
create microflow "Module"."MyFlow" ("$Name": String)
```

**Correct:**
```
create microflow "Module"."MyFlow" ("Name": String)
-- referenced in body as $Name
```

The error message when `$` is included in the parameter name is not clearly diagnostic.

---

## BUG-06: SQLITE_BUSY — partial script apply leaves orphan objects

**Severity:** Medium — requires manual recovery  
**Reproducible:** Intermittent (worse when Studio Pro is open)  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No — v0.13.0 codec engine rewrote write path; SP-open guard in exec.sh makes this much less likely

### Symptom
Script exec fails mid-run with a SQLite locking error. Objects created before the failure remain in the MPR. Re-running the full script fails on the first already-existing object with a duplicate-name error.

### Workaround
1. Run `SHOW ENTITIES IN Module` and `SHOW ASSOCIATIONS` to identify what was already created.
2. Write a patch script containing only the missing objects.
3. Apply the patch.

Close Studio Pro before running large scripts where possible.

**Discovered:** 2026-05-17, an OS 11 reference migration Phase 1 (order-registration.mdl).

---

## CE0854: `set` association called on wrong entity (direction error)

**Not a mxcli bug** — a valid Mendix model error, but included here because it appears consistently in AI-generated scripts that don't check association direction.

**Symptom:** CE0854 "Association X not reachable from entity Y" at `mx check`.

**Root cause:** `set $Entity/Module.AssocName = $Other` must be called on the entity that holds the FK column. With `owner Default`, the FK is on the `from` entity in the association definition.

**Diagnosis:** Run `DESCRIBE ASSOCIATION Module.AssocName` — the `from` entity is the one you must call `set` on.

```mdl
-- Association: OrderAreaData_OrderDetail
-- FROM = OrderAreaData (FK here), TO = OrderDetail

-- CORRECT: set on the FROM entity
set $OrderAreaData/OrderRegistration.OrderAreaData_OrderDetail = $OrderDetail;

-- WRONG: set on the TO entity → CE0854
set $OrderDetail/OrderRegistration.OrderAreaData_OrderDetail = $OrderAreaData;
```

**Also check creation order:** the FK-owning entity (`from`) must be committed after the entity it points to (`to`) already exists in the database.

**Discovered:** 2026-05-18, an OS 11 reference migration script 11 (ACT_OrderDetail_SaveDraft).

---

## BUG-07: `ALTER PAGE SET content` fails on DYNAMICTEXT widgets with ContentParams

**Severity:** Low — silent failure (SET returns success but value doesn't change)  
**Reproducible:** Yes  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No

### Steps to reproduce
1. Create a page with a `dynamictext` widget that has `ContentParams` (e.g. `Content: '{1}', ContentParams: [{1} = SomeAttr]`)
2. Run `ALTER PAGE Module.Page { SET content = 'New Text' ON widgetName }`

### Expected behavior
Content is updated to `'New Text'` and ContentParams are cleared.

### Actual behavior
Error: `property "content" not found (widget has no pluggable Object)`
The widget retains its original `Content: '{1}'` value.

### Root cause (inferred)
Dynamictext widgets with ContentParams use a pluggable widget storage format internally.
The `SET content` operation targets the simple text property, which does not exist on
the pluggable variant. These are two distinct internal types.

### Workaround
Use `REPLACE widgetName WITH { dynamictext newName (Content: 'New Text') }` — but use a
**different name** for the replacement widget (see BUG-08). The REPLACE drops the old widget
(including its ContentParams) and inserts a clean new one.

**Discovered:** 2026-05-21, an OS 11 reference migration script 34 (fixing CE0720 on lblHdrAction).

---

## BUG-08: `ALTER PAGE REPLACE widgetName WITH { widgetName }` fails with duplicate name

**Severity:** Low — easy to work around once known  
**Reproducible:** Yes  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No

### Steps to reproduce
Run `ALTER PAGE Module.Page { REPLACE myWidget WITH { dynamictext myWidget (...) } }`
(replacement widget uses the same name as the widget being replaced)

### Expected behavior
Old widget is replaced in-place; same name is preserved.

### Actual behavior
Error: `duplicate widget name 'myWidget': widget names must be unique within a page`

### Root cause
mxcli builds the replacement widget first (creating a second `myWidget`), then removes
the original. The duplicate-name check fires before removal completes.

### Workaround
Always use a **different name** in the replacement widget body:
```mdl
ALTER PAGE Module.Page {
  REPLACE oldWidgetName WITH {
    dynamictext newWidgetName (Content: 'Fixed Text')
  }
}
```
The old widget (and its name) is dropped; the new widget takes its place in the layout.

**Discovered:** 2026-05-21, an OS 11 reference migration script 34 (fixing CE0720 on lblHdrAction).

---

## BUG-09: Gallery `filter {}` block cannot express association-path filter attributes

**Severity:** Medium — limits AI-assisted filter configuration; requires Studio Pro for association-based filters  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No

### Context

Mendix Gallery filters **fully support** filtering over associated entities, including multi-hop paths (e.g. `OrderDetail → OrderApplicationHeader → ApplicationCommonHeader → Status`). This works correctly at runtime and is configurable in Studio Pro.

### Issue

MDL `filter {}` block syntax only accepts **direct entity attribute names** (short or fully-qualified) in filter widget definitions:

```mdl
-- Works: direct attribute on datasource entity
filter filter1 {
  textfilter txtKeyword (Attributes: [OrderRegistration.OrderDetail.CustomerCode])
  dropdownfilter statusFilter (Attributes: [OrderRegistration.OrderDetail.Status])
}
```

There is no MDL syntax for specifying an association-path as a filter attribute:

```mdl
-- NOT expressible in MDL — cannot write association-path filter attributes
filter filter1 {
  dropdownfilter statusFilter (Attributes: [
    OrderDetail_OrderApplicationHeader/OrderApplicationHeader_ApplicationCommonHeader/Status
  ])
}
```

mxcli has no way to resolve or write the attribute binding for a multi-hop association path in a filter widget. The filter widget stores an attribute reference (GUID), not a free-form path string.

### Practical consequence

Any gallery filter that needs to filter on an **associated entity's attribute** (1-hop or 2-hop, same or cross-module) **cannot be configured via mxcli**. It must be set in Studio Pro:
1. Open the page in Studio Pro
2. Select the Gallery widget → Properties → Filters
3. Add or edit the filter widget
4. Set the attribute using the association path browser

### Workaround

- For filters on **direct entity attributes**: configure via mxcli as normal
- For filters on **associated entity attributes**: document the filter as a Studio Pro manual step; note the association path (e.g. `OrderDetail → [OrderDetail_OrderApplicationHeader] → OrderApplicationHeader → [OrderApplicationHeader_ApplicationCommonHeader] → ApplicationCommonHeader.Status`)

**Discovered:** 2026-05-22, an OS 11 reference migration OrderRegistration_Overview (Status filter via 2-hop cross-module association).

---

## BUG-10: Filter `Attributes` list — syntax checker and executor are inconsistent

**Severity:** Medium — requires workaround to configure multi-attribute or correctly-bound filters via mxcli  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No — v0.13.0 unified datagrid widget engine may have addressed the check/exec grammar split; not verified

### Symptom

`textfilter` and `datefilter` `Attributes` lists behave differently depending on how mxcli is invoked:

| Invocation | Short name `[CustomerCode]` | Qualified `[Module.Entity.Attribute]` |
|------------|---------------------------|--------------------------------------|
| `mxcli check` (syntax check) | ✅ Accepted | ❌ Rejected — "extraneous input '.'" |
| `mxcli exec` (executor) | ⚠️ Silently skipped — "invalid attribute path: expected Module.Entity.Attribute format" | ✅ Applied correctly |
| `mxcli -c` inline (executor) | ⚠️ Silently skipped | ✅ Applied correctly |

Result: no combination of check + exec succeeds with a valid attribute binding. Short names pass the check but are silently dropped at exec. Qualified names fail the check but work at exec.

### Workaround

Skip `mxcli check` for filter blocks and use `mxcli -c` inline with the qualified `Module.Entity.Attribute` format:

```bash
./mxcli -p Project.mpr -c "alter page \"Module\".\"PageName\" {
  replace oldFilter with {
    textfilter newFilter (Attributes: [Module.Entity.Attribute1, Module.Entity.Attribute2])
  }
}"
```

Note: due to BUG-08 (REPLACE with same name fails), the replacement filter must use a **different name** than the widget being replaced.

### Root cause (inferred)

The mxcli parser grammar does not allow dots inside `[]` attribute lists (treats them as separate tokens). The executor uses a separate path-resolver that requires the qualified format to look up the attribute GUID. These two code paths are not aligned.

**Discovered:** 2026-05-22, an OS 11 reference migration script 35 (OrderRegistration_Overview gallery filter extension).

---

## BUG-11: `ALTER PAGE` cannot change a DataView's datasource type

**Severity:** Medium — requires Studio Pro manual step for datasource type changes  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No

### Issue

`ALTER PAGE SET` cannot change a DataView's datasource **type** (e.g. from `microflow` to `context/association`). The datasource type determines the structural shape of the DataView's configuration — microflow datasource stores a microflow reference; context/association datasource stores an association path. These are different slots in the MPR, and mxcli's `SET` only handles scalar property mutations, not structural slot swaps.

There is no MDL syntax for reassigning a DataView's datasource type after creation. `CREATE OR MODIFY PAGE` could rebuild the DataView from scratch with the correct datasource, but this also wipes all nested widgets inside the DataView.

### Workaround

Change the DataView datasource type manually in Studio Pro:
1. Open the page → click the DataView
2. Properties → Data source → Type → select **Context**
3. Use the association tree picker to navigate from the page parameter to the target entity

### Additional finding — mxcli cannot produce Context datasource with association traversal

Tested in session 13. Mendix has two distinct DataView datasource types that look similar but are stored differently:

- **Context** — uses an object already directly in scope (page param or enclosing DataView). Studio Pro: set Type = Context, pick object from tree. No association traversal.
- **Association** — traverses from a context object via association. **CE6705 blocks this entirely** (`"Data view cannot have a data source of type association."`).

Both MDL syntaxes tested produce the **Association** internal type and get CE6705:

```mdl
-- Tested outside parent DataView (page param traversal) → CE6705
dataview dvTest (DataSource: $OrderDetail/OrderRegistration.OrderDetail_OrderCustomerBase) { ... }

-- Tested inside parent DataView (currentObject traversal) → CE6705
dataview dvTest (DataSource: $currentObject/OrderRegistration.OrderDetail_OrderCustomerBase) { ... }
```

When Studio Pro manually sets Type = Context and traverses via the association tree picker, it writes a different internal type that does NOT trigger CE6705. mxcli has no syntax that produces this internal type.

**Conclusion:** mxcli cannot create a valid DataView datasource that retrieves an associated entity. Use microflow datasource (current approach) or configure manually in Studio Pro.

**Discovered:** 2026-05-22, an OS 11 reference migration OrderDetail_View (`dvOrderCustomerBase`, `dvPaymentTermData`).

---

## CE0056 / CE0161: `retrieve` on a Non-Persistent Entity (NPE) — must use association action

**Not a mxcli bug** — a Mendix model constraint, but a common MDL authoring error.

**Symptom:** `CE0056 "Entity X cannot be retrieved from the database because it is non-persistable."` and `CE0161 "Error(s) in XPath constraint."` when a `retrieve` statement targets an NPE entity.

**Root cause:** MDL `retrieve $Var from Module.Entity where [...]` always generates a "Retrieve from database" activity. NPEs have no database table — they live only in memory. The database retrieve fails.

**Fix option A (MDL — change microflow signature):** Pass the NPE as a direct microflow parameter instead of navigating via association. If the page has both the parent and child NPE in scope via nested data views, the button can pass both objects directly. This eliminates the need to retrieve the associated NPE inside the microflow.

**Fix option B (Studio Pro manual):** In Studio Pro, open the microflow and replace the "Retrieve from database" activity with a "Retrieve by association" activity. Set the association and the starting object. This is the correct Mendix pattern for NPE-to-NPE traversal and does not require changing the microflow signature.

**Discovered:** 2026-05-18, an OS 11 reference migration script 11 (ACT_OrderDetail_SaveDraft — PartnerSearchResult NPE retrieve).

---

## BUG-14: `ALTER PAGE DROP + INSERT BEFORE` with MICROFLOW action corrupts page BSON

**Severity:** High — MPR becomes unloadable by `mx` after execution  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No — v0.13.0 fixed several page-authoring BSON issues; worth retesting before routing to SP  
**Discovered:** 2026-05-25, an OS 11 reference migration Script 56

### Steps to reproduce

```mdl
ALTER PAGE Module.PageName {
  DROP WIDGET btnSomething;
  INSERT BEFORE btnSibling {
    ACTIONBUTTON btnSomething (
      Caption: 'Next',
      Action: MICROFLOW Module.SomeMicroflow
    )
  }
};
```

### Expected behavior

Button is dropped and re-inserted with the microflow action wired correctly. `mx check` passes.

### Actual behavior

mxcli reports success and `DESCRIBE PAGE` shows the correct wiring. But `mx check` (mxbuild) crashes on MPR load with:

```
System.InvalidOperationException: Type Mendix.Modeler.WebUI.Forms.Widgets.FormCalls.LayoutCallArgument
does not contain a constructor with a parameter of type
Mendix.Modeler.WebUI.Forms.PageSettingss.PageSettings.
```

The page's `.mxunit` file has a `PageSettings`-typed object serialized into a `LayoutCallArgument` slot — the layout call BSON for the page is corrupted by the INSERT operation.

### Variants tested

All produce the same crash:
- `INSERT BEFORE` with `Action: MICROFLOW Module.MF(Param: $currentObject)`
- `INSERT BEFORE` with `Action: MICROFLOW Module.MF` (no params)
- `REPLACE oldBtn WITH { ACTIONBUTTON newBtn (Action: show_page Module.Page(Param: $currentObject)) }` — also crashes (BUG-14b: explicit page params in REPLACE also corrupt BSON)

### Root cause (inferred)

`ALTER PAGE INSERT` correctly writes the widget tree but corrupts the page's layout call arguments section in the `.mxunit` BSON — likely a wrong type discriminator or offset when serializing the action's microflow reference into an existing page structure.

### Workaround

Wire the button action manually in Studio Pro:
1. Open the page → click the button
2. Properties → On click → Call a microflow → select microflow → OK

### Does NOT affect

- `CREATE PAGE` / `CREATE OR MODIFY PAGE` — microflow actions written from scratch work correctly
- `ALTER PAGE SET caption/style/label` — scalar property changes work
- `ALTER PAGE DROP WIDGET` alone — no corruption

---

## BUG-15: `retrieve $X from $ObjVar/Module.AssocName limit 1` generates broken "Retrieve by Association" BSON

**Severity:** High — silently writes broken BSON; causes CE0018 + CE0136 which cannot be fixed in Studio Pro (no visual indicator of which retrieve is broken)  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No  
**Discovered:** 2026-05-26, an OS 11 reference migration scripts 62 + 63

### Symptoms

After executing a microflow script that uses the association-path retrieve syntax, `./mxcli docker check` reports:

```
[error] [CE0018] "The `Association' property is required for the `By Association' data source."
        at Retrieve object(s) activity 'Retrieve from association'
[error] [CE0136] "Retrieve object must specify the 'Entity' property."
        at Retrieve object(s) activity 'Retrieve from association'
```

Two errors fire per broken retrieve activity. The activity appears in Studio Pro's canvas as a "Retrieve" activity with no entity or association configured.

### MDL that triggers the bug

```mdl
-- In ACT_Order_ExpansionApply_Save (script 63):
retrieve $OldOrderDetail from OrderRegistration.OrderDetail
  where [OrderDetail/CustomerCode = $Dto/CustomerCode]
  limit 1;

-- Then: Broken retrieve — association path from variable
retrieve $ExistingBase from $OldOrderDetail/OrderRegistration.OrderDetail_OrderCustomerBase
  limit 1;
```

The second `retrieve` (via object-variable association path) is the broken form.

```mdl
-- In ACT_Order_ExpansionApply_InitNew (script 62):
retrieve $Base from $ExistingOrderDetail/OrderRegistration.OrderDetail_OrderCustomerBase
  limit 1;
```

Same pattern — both cause CE0018 + CE0136.

### Expected behavior

mxcli generates a "Retrieve by Association" activity with `Association = OrderRegistration.OrderDetail_OrderCustomerBase` and `Entity = Customer_Common.OrderCustomerBase` properties wired correctly.

### Actual behavior

mxcli generates a "Retrieve by Association" activity where both `Association` and `Entity` BSON properties are empty GUIDs. The activity is stored but is invalid — Studio Pro cannot render it and the model checker rejects it.

### Root cause (inferred)

mxcli's MDL compiler parses `retrieve $X from $ObjVar/Module.AssocName limit 1` but fails to resolve and serialize the association and entity references into the underlying BSON `InternalId` fields. The association name and target entity are lost during compilation.

### Workaround

Replace the association-path retrieve with an XPath DB retrieve against the target entity:

```mdl
-- BROKEN (generates empty BSON):
retrieve $ExistingBase from $OldOrderDetail/OrderRegistration.OrderDetail_OrderCustomerBase
  limit 1;

-- FIXED (XPath cross-entity filter):
declare $CCode String = $Dto/CustomerCode;
retrieve $ExistingBase from Customer_Common.OrderCustomerBase
  where [OrderRegistration.OrderDetail_OrderCustomerBase/OrderRegistration.OrderDetail/CustomerCode = $CCode]
  limit 1;
```

**Pre-conditions required for XPath workaround:**
1. The target entity (`OrderCustomerBase`) must be a **persistent** entity (not an NPE).
2. All entities referenced in the XPath path must be **persistent**.
3. The object being filtered on must be **committed to the database** — XPath queries the DB, not in-memory objects.

If any condition fails, pass the related object as a microflow parameter instead.

### Does NOT affect

- `retrieve $X from Module.Entity where [condition] limit 1` — XPath DB retrieve works correctly.
- `retrieve $X from Module.Entity limit 1` — retrieves without filter, works correctly.
- NPE association retrieval via parameter passing — separate workaround (see learned-microflow-patterns.md NPE rule).

### BUG-15b: ALL `retrieve ... where [...]` XPath constraints silently dropped in BSON

**Severity upgrade: Critical** — affects every `retrieve ... where [...]` written via mxcli. mxcli passes CE checks (0 errors) and `DESCRIBE MICROFLOW` shows the XPath text correctly, but Studio Pro shows the XPath constraint field **empty** on every retrieve activity. The XPath text is stored somewhere mxcli can read it, but NOT in the BSON slot that Studio Pro (and the Mendix runtime) uses as the actual filter.

**Effect:** all filtered retrieves execute as "From database, entity X, Range=First/All" with no XPath — returns an arbitrary record or full table scan. Functionally incorrect at runtime.

**Confirmed on:**
- `retrieve $ExistingOrderDetail from OrderRegistration.OrderDetail where [OrderDetail/CustomerCode = $ExistingCustomerCode]` (simple attribute XPath)
- `retrieve $Base from Customer_Common.OrderCustomerBase where [OrderRegistration.OrderDetail_OrderCustomerBase/.../CustomerCode = $ExistingCustomerCode]` (cross-module association XPath)

**Root cause confirmed (2026-05-26) via `mxcli bson dump` comparison:**

mxcli writes the BSON key as **`XPathConstraint`** (capital P), but Studio Pro writes and reads **`XpathConstraint`** (lowercase p). BSON field lookup is case-sensitive. The XPath value IS stored in the file — just under the wrong key name. Studio Pro cannot find it and renders the constraint field as empty. The runtime executes with no filter.

Evidence from BSON dump:
```
Working (GET_Sequence_NextId — written by Studio Pro):  "Key": "XpathConstraint"
Broken  (ACT_Order_ExpansionApply_* — written by mxcli): "Key": "XPathConstraint"
```

This explains why annotation text writes correctly (its field name is spelled correctly in mxcli's writer) but XPath does not. The fix in mxcli's source (`writer_microflows.go`) is to change `XPathConstraint` → `XpathConstraint`.

**Both simple and complex XPath constraints are dropped** — this is a systemic serialization failure, not specific to cross-module paths.

**Implication:** ALL microflows in this project built via mxcli with `retrieve ... where [...]` should be inspected in Studio Pro. The XPath constraint field will be empty even when the business logic requires filtering.

**STATUS: RESOLVED via binary patch (2026-05-26). Root cause fixed in mxcli v0.13.0** — the codec engine correctly serialises `XpathConstraint` (lowercase p). New projects on v0.13.0 do not need the binary patch. The patch script is preserved below for projects built on older mxcli versions.

**Fix applied:** Binary search-replace of all `XPathConstraint` (capital P) → `XpathConstraint` (lowercase p) bytes across all mxunit files in `mprcontents/`. The fix was applied with mxcli v0.12.0 installed but the bug was NOT fixed in v0.12.0 — the binary patch was applied manually.

**Result:** 265 mxunit files patched, 45,615 occurrences fixed. 0 CE errors after patch. All XPath constraints written by mxcli are now visible in Studio Pro.

**How the patch works:**
- The MPR SQLite file (`.mpr`) is only an index — the actual BSON data lives in the `mprcontents/*.mxunit` files
- `XPathConstraint` and `XpathConstraint` are the same byte length (15 chars) — safe binary replacement, no length prefix changes needed
- Studio Pro writes/reads `XpathConstraint`; after the patch mxcli-written files match

**If the bug reappears after a future mxcli update:** re-run this PowerShell to reapply the patch:
```powershell
cd <project-root>
$search  = [System.Text.Encoding]::ASCII.GetBytes("XPathConstraint")
$replace = [System.Text.Encoding]::ASCII.GetBytes("XpathConstraint")
$totalFiles = 0; $totalOccurrences = 0
Get-ChildItem mprcontents -Recurse -Filter "*.mxunit" | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $count = 0
    for ($i = 0; $i -le $bytes.Length - $search.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $search.Length; $j++) {
            if ($bytes[$i+$j] -ne $search[$j]) { $match = $false; break }
        }
        if ($match) {
            for ($j = 0; $j -lt $replace.Length; $j++) { $bytes[$i+$j] = $replace[$j] }
            $count++; $i += $search.Length - 1
        }
    }
    if ($count -gt 0) { [System.IO.File]::WriteAllBytes($_.FullName, $bytes); $totalFiles++; $totalOccurrences += $count }
}
Write-Host "Patched $totalFiles files, $totalOccurrences occurrences"
```

**Studio Pro action required after any mxcli exec that writes retrieves with XPath:** reload the project in Studio Pro (File → Recent Projects or close/reopen) so it picks up the updated mxunit files. Then open and verify the Constraint fields are populated.

---

## BUG-16: `datagrid` (DataGrid 2) with `ShowContentAs: customContent` columns corrupts pluggable widget BSON

**Severity:** High — `mx check` crashes on project load with NullReferenceException; page is unloadable  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No — v0.13.0 unified the datagrid engine (#529 Phase 4); worth retesting before routing to Studio Pro  
**Discovered:** 2026-05-26, an OS 11 reference migration Script 77 (OrderRegistration_Overview_DG2)

### Steps to reproduce

```mdl
create or modify page Module."PageName" (...) {
  datagrid dgName (DataSource: database from Module.Entity) {
    column colCustom (
      Caption: 'Label',
      ShowContentAs: customContent,
      Sortable: false
    ) {
      dynamictext txtWidget (Content: '{1}', ContentParams: [{1} = Attribute])
    }
    column colAction (
      Caption: 'Action',
      ShowContentAs: customContent,
      Sortable: false
    ) {
      actionbutton btnName (Caption: 'Details', Action: show_page Module.Page)
    }
  }
}
```

### Expected behavior

DataGrid 2 page created with custom content columns. `mx check` passes.

### Actual behavior

mxcli reports success and `DESCRIBE PAGE` looks correct. But `mx check` (mxbuild) crashes on MPR load with:

```
System.NullReferenceException: Object reference not set to an instance of an object.
   at CustomWidget.GetCustomDescription(DescriptionType descriptionType)
   at UnitContentsLoader.SetPropertyValue(...)
   at UnitContentsLoader.FillProperties(...)
```

The crash fires during pluggable widget (CustomWidget) deserialization — the BSON written by mxcli for the custom content column's nested widgets does not match the DataGrid 2 widget's schema.

### Root cause (inferred)

DataGrid 2 is a pluggable widget. Its custom content column schema (`ShowContentAs: customContent`) has a specific internal BSON structure for nested widgets that differs from the standard page widget tree. mxcli serializes the nested widgets (dynamictext, actionbutton) using the standard page widget BSON format, which is incompatible with the pluggable widget's slot schema. The pluggable widget loader dereferences a null pointer when it encounters the mismatched structure.

### Does NOT affect

- `datagrid` with direct attribute columns (no `ShowContentAs`) — those serialize correctly and `mx check` passes.
- `gallery` with template columns containing any widget type — gallery is not a pluggable widget and serializes differently.

### Workaround

1. Use only **direct attribute columns** via mxcli (no `ShowContentAs: customContent`).
2. For custom content columns (status badges, action buttons, association-path fields): configure them manually in Studio Pro after mxcli creates the base datagrid with direct-attribute columns.

**Recovery if already corrupted:** restore the affected page's `.mxunit` from git:

---

## BUG-17: `[%BeginOfToday%]` / `[%EndOfToday%]` tokens in `retrieve ... where` are serialised with single quotes → CE0161

**Severity:** Medium — today-date filters are broken; workaround required  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.12.0  
**mxcli version when found:** v0.12.x (pre-v0.13.0 codec engine)  
**Retested on v0.13.0:** No — XPath token serialization may be fixed by codec engine; worth a quick retest  
**Discovered:** 2026-07-03, a Java/Angular analysis project Phase 3a (script 14)

### Steps to reproduce

```mdl
create or replace microflow "Module"."MyFlow" ()
returns Boolean as $R
begin
  retrieve $Items from "Module"."Entity"
    where TransactionDate >= [%BeginOfToday%] and TransactionDate < [%EndOfToday%];
  -- or with outer brackets:
  -- where [TransactionDate >= [%BeginOfToday%] and TransactionDate < [%EndOfToday%]]
  return true;
end;
/
```

### Expected behavior

Retrieve filters by server-local calendar day. `mx check` passes.

### Actual behavior

mxcli serialises both token forms into the MPR with single quotes around the token:
`TransactionDate >= '[%BeginOfToday%]'`. Mendix treats single-quoted values as string
literals — the tokens are never evaluated. `mx check` fails with:
```
[error] [CE0161] "Error(s) in XPath constraint." at Retrieve object(s) activity 'Retrieve list of ...'
```

`DESCRIBE MICROFLOW` always shows the single-quote form regardless of whether you wrote the tokens with or without outer `[...]`.

### Root cause (inferred)

mxcli's MDL-to-BSON compiler quotes `[%Token%]` expressions when they appear in XPath WHERE
constraints, storing them as string literals instead of Mendix runtime token references.
The same tokens work correctly in expression contexts (e.g. `declare $Now datetime = [%CurrentDateTime%]`)
— the bug is XPath-specific.

### Workaround

**Option A (POC):** Filter inside the microflow loop instead of in the XPath:
```mdl
retrieve $AllItems from "Module"."Entity"
  where SomeRequiredAttr != empty;  -- limit to "has been set" as proxy

loop $Item in $AllItems begin
  -- DateTime comparison works fine in microflow IF expressions
  if $Item/TransactionDate != empty then
    -- ... process only today's items (POC: no strict midnight boundary)
  end if;
end loop;
```

**Option B (production):** Create a Java action that returns today's start-of-day as a DateTime parameter, then pass it to a microflow and use `where TransactionDate >= $StartOfDay` — **but note that local microflow variables cannot be used in XPath WHERE** (page params and constants only); the Java-action result must be the parameter passed from a calling context or a module constant.

**Option C (also broken):** Datetime arithmetic for midnight via `addHours` / `hour()` etc. fails with CE0117 because `hour()` / `minuteOfHour()` / `secondsOfMinute()` return Long but `addHours()` expects Integer — type mismatch. This option requires careful casting and is not viable without a helper Java action.

### Does NOT affect

- `[%CurrentDateTime%]` in expression contexts (`declare $Now datetime = [%CurrentDateTime%]`) — works correctly.
- Static string filters (`where Code = 'ABC'`) — work correctly.

**Recovery (already-exec'd script):** Re-exec with the loop-filter workaround. The BSON
is not corrupted — it's just logically wrong (CE0161 blocks running anyway).
```bash
git show HEAD:mprcontents/xx/yy/<uuid>.mxunit > /tmp/clean.mxunit
cp /tmp/clean.mxunit mprcontents/xx/yy/<uuid>.mxunit
```
Find the correct mxunit by running `git diff --name-only` and reading each changed file for its `$Type = Forms$Page` + `Name` field.


---

## BUG-18: `visible: [expr]` on CONTAINER inside datagrid customContent column corrupts MPR

**Affects:** mxcli v0.12.x–v0.13.0 on Mendix 11.12.0 — confirmed still present on v0.13.0 (2026-07-09 retest)  
**mxcli version when found:** v0.12.x  
**Retested on v0.13.0:** Yes — still corrupts. preflight rule 1 STOP remains valid for this specific case.

**Symptom:** After executing a `CREATE OR REPLACE PAGE` or `CREATE PAGE` script that includes `container ctn (visible: [expr]) { ... }` widgets inside a `column (ShowContentAs: customContent)` datagrid column, `mx check` reports `StorageLoadException`:

> `Conditional visibility settings in <blank> has an invalid value '' for property Attribute. The text '   ' is not a valid AttributeIdentifier.`

Studio Pro itself cannot open the MPR. Gate 2 (javac) still passes because it does not load the BSON.

**Root cause:** mxcli writes blank/whitespace into the `Attribute` field of the `ConditionalSettings` unit when the visibility expression is applied to a container inside a datagrid customContent column. The expression is silently dropped and a blank `AttributeIdentifier` is written instead.

**Does NOT affect:** `visible: [expr]` on containers in regular dataviews and regular page containers — those work correctly.

**Also affects (BUG-18b): snippets with no declared entity context.** If a snippet is created with no params (`create or replace snippet Module.Name { ... }`) and contains `container ctn (visible: [$currentObject/"Attr" = ...]) { ... }`, mxcli cannot resolve the attribute GUID (no entity context declared) and writes an empty `AttributeIdentifier` — same crash, same error message. The previous "Does NOT affect snippets" claim was wrong.

**Workaround:**
- Datagrid customContent columns: wire conditional visibility manually in Studio Pro.
- Snippets with no entity context: remove `visible:` expressions entirely — show all content statically, or declare an explicit entity param if the snippet needs it.

**Recovery:** Restore from snapshot immediately — the MPR is load-broken. Run `bash bin/restore-mpr.sh`.

**Discovered:** 2026-07-03, IVM project (datagrid). 2026-07-05, a large-source WMS project script 18 (snippet with no entity context).

---

## BUG-19: `ALTER PAGE` — REPLACE wrapping existing widget in CONTAINER corrupts BSON (DivContainer/WidgetObject type clash)

**Severity:** Critical — project becomes unopenable in Studio Pro with InvalidCastException  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.12.0 Beta  
**mxcli version when found:** v0.12.x (pre-v0.13.0)  
**Retested on v0.13.0:** No — codec engine may address type-tag handling; worth a quick retest  
**Discovered:** 2026-07-05, a Java/Angular analysis project sprint4-visual-polish.mdl

### Steps to reproduce

```mdl
-- Inside an existing dataview with a textbox:
alter page Module."PageName" {
  replace txtCost with {
    container cCostAffix (Class: 'input-affix') {
      dynamictext lblEur (Content: '€', RenderMode: Paragraph)
      textbox txtCost (Label: 'Cost *', Attribute: Cost)
    }
  }
};
```

Also triggered by inserting a container block before a widget inside a dataview body:

```mdl
alter page Module."PageName" {
  insert before txtConfirm {
    container cHeader (Style: '...') {
      dynamictext txtIcon (Content: '🗑', RenderMode: Paragraph)
    }
  }
};
```

### Expected behavior

Widget is replaced/inserted. `mx check` passes. SP loads the project.

### Actual behavior

mxcli reports success (`Altered page Module.PageName`). But SP crashes on project load with:

```
System.InvalidCastException: Unable to cast object of type
  'Mendix.Modeler.WebUI.Forms.Widgets.LayoutWidgets.DivContainers.DivContainer'
  to type
  'Mendix.Modeler.WebUI.Forms.Widgets.CustomWidgets.WidgetObject'
  at StreamingBsonUnitReader.AddListItem(...)
```

### Root cause (inferred)

The dataview's widget children list in BSON is typed to hold `WidgetObject` (custom/pluggable widget references). When mxcli writes a `CONTAINER` (`DivContainer`) into that list, it uses the wrong BSON type tag. The SP model reader enforces the typed list at load time and throws `InvalidCastException`.

Standard dataviews in Atlas use pluggable input widgets (TextBox, TextArea, etc.) — the widget list is typed for pluggable `WidgetObject`s, not layout containers. A `CONTAINER` is a `DivContainer`, not a `WidgetObject`, so it cannot be stored in that slot.

### Does NOT affect

- Inserting CONTAINER widgets at the page level (outside a dataview) — works correctly.
- Inserting CONTAINER widgets inside a LAYOUTGRID column (not a dataview widget list) — works correctly.
- Inserting ACTION BUTTONs, TEXTBOXES, DYNAMICTEXT widgets inside a dataview — those are pluggable widget types and serialize correctly.

### Workaround

**Never wrap a widget in a new CONTAINER via ALTER PAGE inside a dataview body.**

For input affixes (e.g. € prefix on Cost/Price):
- Use pure SCSS: position a `::before` pseudo-element or use a CSS `input-affix` class that overlays the prefix visually without changing the widget tree.

For decorative header blocks (e.g. danger icon before confirm text):
- Add as a `DYNAMICTEXT` sibling (not wrapped in a container), or
- Do it in Studio Pro manually after the MDL exec.

### Recovery

Restore `mprcontents/` from the last clean git commit:
```bash
git checkout HEAD -- mprcontents/ Project.mpr
```
Then restart SP.

---

## BUG-20: Cross-module association traversal as widget datasource writes null `DestinationEntityId`

**Severity:** Critical — project becomes unopenable in Studio Pro with `StorageLoadException`  
**Status:** Open — no fix in mxcli; workaround: use MCP after exec  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.12.0 Beta  
**mxcli version when found:** v0.13.0 (confirmed on codec engine)  
**Retested on v0.13.0:** Yes — still corrupts. Preflight rule 7 STOP remained valid.  
**Retested on v0.16.0:** **Still BROKEN — 2026-07-13**, a WMS conversion project (`1146version` branch). Script created page `ZZ_Retest16.Retest_BUG07_Page` with DataGrid datasource `$currentObject/ZZ_Retest16.Widget_Category` (cross-module, `ZZ_Retest16.Widget` → `ZZ_Retest16B.Category`). mxbuild gate: **0 errors** — but SP crashed on open with the identical `ArgumentNullException: value at EntityRefStep.set_DestinationEntityId`. **Critical new finding: mxbuild does NOT catch this BSON corruption — only Studio Pro's project load does.** Preflight rule 7 STOP remains in effect.  
**Discovered:** 2026-07-06

### Steps to reproduce

1. Define an association between two modules: `ModuleA.Assoc` from `ModuleA.EntityA` to `ModuleB.EntityB`
2. In a page with a `ModuleB.EntityB` parameter, add a datagrid using the back-traversal as datasource:
   ```mdl
   datagrid dgItems (
     datasource: $currentObject/ModuleA.Assoc,
     ...
   ) { ... }
   ```
3. Exec the script — mxcli reports success with no errors
4. Open the project in Studio Pro

### Expected behavior
The datagrid loads objects on the other side of the association from the current context object.

### Actual behavior
Studio Pro crashes on project open with:
```
AggregateException: An error occurred when trying to set the 'DestinationEntity' property
of a Entity ref step in a Page with ID <page-unit-uuid>.
  --> ArgumentNullException: ArgumentNull_Generic Arg_ParamName_Name, value
   at EntityRefStep.set_DestinationEntityId(EntityIdentifier value)
   at StreamingBsonUnitReader.SetValue(...)
```

### Root cause (inferred)
mxcli's page-widget writer does not correctly resolve cross-module entity identifiers when
writing the `EntityRefStep` that makes up a traversal path (`$currentObject/OtherModule.Assoc`).
The `DestinationEntityId` field in the BSON is written as null/empty, which SP rejects hard on load.

Same-module traversals work correctly. The bug is isolated to cross-module association paths
in widget datasource expressions.

### Affected widget types
Confirmed: `datagrid` with `datasource: $currentObject/OtherModule.Assoc`.  
Likely also: `dataview`, `listview` — any widget datasource that traverses a cross-module association.

### Workaround
1. Write the page via MDL **without** the cross-module association datasource widget
2. Exec and verify SP opens cleanly
3. Add the cross-module datasource widget via MCP (`pg_patch_page`) while SP is open

### Recovery
Restore from the `.mpr-snapshots/` directory created automatically before the failing exec:
```bash
SNAP=".mpr-snapshots/<timestamp-before-bad-exec>"
cp "$SNAP/<project>.mpr" <project>.mpr
rsync -a --delete "$SNAP/mprcontents/" mprcontents/
```

---

## BUG-21: Inline association-set in CHANGE/CREATE activity writes invalid `AttributeIdentifier` BSON → SP rejects on load

**Severity:** Critical — project becomes unopenable in Studio Pro  
**Reproducible:** Yes, consistently  
**Confirmed:** Mendix 11.12.0 Beta, 2026-07-06  
**mxcli version when found:** v0.13.0 (confirmed on codec engine)  
**Retested on v0.13.0:** Disk write path still corrupts. **`mxcli --mcp` path confirmed safe — retested 2026-07-09, `ped_check_errors` 0 errors.** Preflight rule 9 updated: use `mxcli --mcp` instead of hand-rolled MCP.  
**Retested on v0.16.0:** **Still corrupts — 2026-07-13**, a WMS conversion project (`main` and `1146version` branches). Variant A (`change $NewAccount (System.User_UserRoles = $Role);`) reproduced the identical error on both branches: `"The text 'System.User_UserRoles' is not a valid AttributeIdentifier"` — a project-load-level failure. v0.14.0's "$ID-first BSON ordering fix" does not address this. **Preflight rule 9 (use `mxcli --mcp`) remains in effect.**

### Symptom
`mxcli exec` (disk write path) reports success. Studio Pro refuses to open the project on the next load. The error is in the CHANGE or CREATE activity's BSON, where the association name was written as an `AttributeIdentifier` field instead of a proper association reference.

### Affected patterns (disk write path only)
```mdl
-- All three of these corrupt the MPR via mxcli disk write:
change $Obj (Module.AssocName = $Other);
create Module.Entity (Module.AssocName = $Other);
-- Also: ReferenceSet assignments (System.User_UserRoles) — different surface, same root cause
change $Account (System.User_UserRoles = $Role);
```

**Reading through an association is safe on any path** — only setting one inline in a CHANGE/CREATE via disk write is affected:
```mdl
-- This is fine on any path:
$value = $Obj/Module.AssocName/TargetEntity/Attribute;
```

### Workaround
Use `mxcli --mcp http://localhost/mcp --mcp-dial localhost:7782 exec script.mdl` (SP must be open). The `--mcp` path routes writes through SP's own model engine, bypassing mxcli's BSON serializer entirely — the bug cannot occur. Hand-rolled MCP (`ped_create_document`/`ped_update_document`) still works as a fallback. See `skills/learned-mcp-patterns.md`.

### Recovery
Restore from the `.mpr-snapshots/` snapshot taken by exec.sh before the failing exec. If no snapshot: `git checkout` the `.mpr` and `mprcontents/` back to the last clean commit, then replay scripts one at a time with `mxbuild` verification between each.

---

## BUG-22: `alter settings configuration` / `alter settings model` / `alter project security level` — deterministic BSON stream-desync on the Settings unit

**Severity:** Critical — deterministic corruption, confirmed across multiple retry attempts  
**Reproducible:** Yes, 100% — not flaky  
**Confirmed:** Mendix 11.12.0 Beta, 2026-07-06  
**mxcli version when found:** v0.13.0 (confirmed on codec engine)  
**Retested on v0.13.0:** Yes — still corrupts. Preflight rule 2 STOP (SP GUI only) remains valid.

### Symptom
The statement executes and reports success ("Updated configuration 'Default'"). On the next SP open or `mx check`, the project fails to load with `AggregateException` / "Expected '$ID' as the first property..." in the Settings unit. The *field* where corruption manifests varies between attempts (seen on `EnableMicroflowReachabilityAnalysis`, `EnableNewWidgetGeneration`, `UrlPrefix`) — this shift is the signature of a BSON stream-desync: once one object is written malformed, the next object in the same write batch inherits the corruption, appearing as an unrelated field error.

### Affected statements
- `alter settings configuration 'Name' DatabaseType = ..., DatabaseUrl = ...`
- `alter settings model ...`
- `alter project security level ...`

### Workaround
**Change these settings via Studio Pro's GUI only** — App menu → Settings/Configurations. Neither mxcli nor MCP has a safe path for these operations (MCP's `ped_read_document` and `ped_get_schema` reject every known Settings document type name).

### Recovery
`git checkout` the two tracked `mprcontents/*.mxunit` files for the Settings unit back to the last clean commit. No full project revert needed — only those unit files are corrupted.

---

## BUG-23: `ContentParams` with an explicit `$currentObject/` prefix resolves as a literal (broken) attribute path → CE1613

**Severity:** High — silent, repeat offender. Passes `mxcli check`/`describe page` every time; only fails on a real `mx check`/`docker check`/SP compile. Estimated to have caused this exact mistake ~500 times across sessions before the root cause was isolated.
**Reproducible:** Yes, consistently
**Confirmed:** Mendix 11.12.0, mxcli v0.13.0, 2026-07-20 (WMS-App)
**Retested on v0.13.0:** N/A — first isolation of root cause; previously misattributed to "any function call" (see Rule 12 correction below)

### Symptom
A `dynamictext`'s `ContentParams` entry that includes an explicit `$currentObject/` prefix on the attribute — whether inside a wrapping function or completely bare — is accepted by `mxcli check` and shows up looking correct in `describe page`. It then fails a real compile with:

```
[CE1613] "The selected attribute '<Entity>.<literal ContentParams text>' no longer exists."
```

mxcli/mxbuild does not evaluate `$currentObject/Attr` as an expression inside `ContentParams` — it treats the *entire* ContentParams value as an attribute-path suffix and concatenates the dataview's qualified entity name onto it verbatim, producing a nonsense path that can never resolve.

### Confirmed failing forms (all `dynamictext` `ContentParams`, all real-compile CE1613)
- `ContentParams: [{1} = toString($currentObject/State)]` → `Common.TransportUnit.toString($currentObject/State)` no longer exists
- `ContentParams: [{1} = toString($currentObject/State)]` → `Transportation.TransportOrder.toString($currentObject/State)` no longer exists
- `ContentParams: [{1} = toString($currentObject/Priority)]` → `...toString($currentObject/Priority)` no longer exists
- `ContentParams: [{1} = $currentObject/CreatedOn]` (bare, no function at all) → `...$currentObject/CreatedOn` no longer exists

Also confirmed as a dead end: setting `Attribute: "AttrName"` directly on the `dynamictext` (previously believed to be the safe alternative — see Rule 12 in `skills/learned-mdl-preflight.md`, now corrected). For a non-string attribute type (e.g. DateTime), mxcli silently re-serializes this shorthand back into `Content: '{1}', ContentParams: [{1} = toString($currentObject/Attr)]` — i.e. it round-trips into the exact same broken form, confirmed via `describe page` showing the expanded (broken) version after the fact.

### Confirmed working forms, on the same pages, never throwing CE1613
- `ContentParams: [{1} = GroupName]`
- `ContentParams: [{1} = ExternalId]`

### Workaround (the fix that actually works)
**Inside `ContentParams` (including inside a wrapping function like `toString()`/`formatDateTime()`), never write `$currentObject/` at all — use the bare attribute name.** The current dataview/gallery/listview object is already the implicit context; re-stating it as a path prefix is what breaks the serializer.

```sql
-- Broken (CE1613 on real compile, passes mxcli check):
DYNAMICTEXT txt (Content: '{1}', ContentParams: [{1} = toString($currentObject/State)])

-- Fixed:
DYNAMICTEXT txt (Content: '{1}', ContentParams: [{1} = toString(State)])
```

**Important counterpart — do not over-apply this fix.** `DynamicClasses`, `Visible`, and other conditional/comparison expressions use the *opposite* convention and genuinely require the `$currentObject/` prefix — this is the already-established, working pattern used throughout this project's badge widgets:

```sql
-- Correct in DynamicClasses/Visible (keep the prefix here):
DynamicClasses: 'if $currentObject/State = Transportation.ENUM_TransportOrderState.CREATED then ''neo-badge--created'' else ...'
```

Writing bare `State = ...` (no `$currentObject/`) inside `DynamicClasses` is the mirror-image mistake — not confirmed to throw CE1613, but inconsistent with the working convention and should be avoided.

**Rule of thumb:** `ContentParams` = bare attribute, no `$currentObject/`. `DynamicClasses`/`Visible` = prefixed, with `$currentObject/`. These look like the same kind of expression but take opposite forms — that resemblance is exactly why this bug keeps recurring.

### Verification
Only a real compiler pass catches this — `mxcli check` / `mxcli check --references` / `describe page` all pass on every broken form above. Always confirm with `./mxcli docker check -p <project>.mpr` (or `mx check` directly) before considering a ContentParams/DynamicClasses fix done.

### Cross-reference
Supersedes/corrects `skills/learned-mdl-preflight.md` Rule 12, which blamed "any function call" as the trigger and recommended `Attribute: "AttrName"` as a safe alternative — both are wrong; see the updated rule text.

---

## `marketplace install` fails on modules that ship `themesource/` styling (exit 112, "Importing theme module is not supported")

**Discovered:** 2026-07-22 (a PLM parts-flow project, mxcli v0.16.0, mxbuild 11.12.0), importing **Conversational UI** (content-id 239450, v7.0.0, a Mendix Platform *Module*).

### Symptom
```
$ ./mxcli marketplace install 239450 -p app.mpr
mx module-import failed: exit status 112
Importing theme module is not supported
```
The `.mpk` manifest declares `"type": "Module"` — it is NOT a theme package — but it bundles `themesource/conversationalui/**` (SCSS + design-properties). The offline `mx module-import` command refuses any package carrying theme content.

### Scope of the probe (capability-probe rule — all exhausted, none work)
- `mxcli marketplace install <id>` → exit 112
- `mxcli docker check`-style path → docker subcommand is build/deploy only, no import
- `mxcli module-import` → no such subcommand
- direct `~/.mxcli/mxbuild/<v>/modeler/mx` binary → not runnable on this arch (`exec format error`; mxcli invokes it internally)

### Workaround (the only one that works)
**Studio Pro GUI import.** Download the .mpk first so it's local:
```
./mxcli marketplace download <id> -p app.mpr   # writes <Name>_vX_Y_Z.mpk to project root
```
Then in Studio Pro: **App → Import module package →** select that `.mpk`. Studio Pro handles merging `themesource/` into the app theme, which `mx module-import` cannot.

### Detection / impact
- After importing the module's *dependents* via CLI (GenAI/Agent/MCP Commons), `mxbuild check` reports `CE1613 "... no longer exists"` for every `ConversationalUI.*` element they reference — a hard dependency, not optional. All such errors clear once the module is GUI-imported.
- General rule: before assuming a marketplace module is CLI-importable, note that **AI/chat/UI-widget modules commonly ship `themesource/`** and will hit this. Domain/logic modules (GenAI Commons, Agent Commons, MCP Server/Client, Workflow Commons, Teamcenter connector, Community Commons) imported cleanly via CLI.

### Bonus finding (same session)
`mxcli marketplace search "AgentCommons"` (no space) returns nothing, which led to a wrong "AgentCommons is bundled" conclusion. The module is listed as **"Agent Commons"** (with a space), content-id **240371**. Lesson: search by display name / browse ids, don't probe with an assumed camelCase identifier.

---

## 🚨 CRITICAL: `mxcli marketplace install` collapses a split-model project to monolithic `.mpr` and deletes `mprcontents/` — breaks Studio Pro

**Severity:** Critical — corrupts the on-disk project format; Studio Pro's Git integration then fails to open/reconcile.
**Discovered:** 2026-07-22 (a PLM parts-flow project, mxcli v0.16.0, mxbuild 11.12.0, Mendix 11 split-model project).
**Supersedes the theme-import entry above** — the theme error was a symptom encountered on one module; THIS is the real, general failure.

### What happens
`mxcli marketplace install <id>` calls `mx module-import` (the mxbuild tool) under the hood. On a project stored in the **Mendix 11 split-model format** (a small ~70 KB `.mpr` index + hundreds of `mprcontents/*.mxunit` BSON files), `mx module-import`:
- **rewrites the entire project as a single monolithic `.mpr`** (in this case 68 KB → **49 MB**), and
- **deletes the whole `mprcontents/` directory** (here: 369 `.mxunit` files gone).

The imported modules ARE in the resulting model (mxbuild `check` loads it, reports only genuine missing-dep errors), so it looks like it worked. But:

### The Studio Pro symptom
Opening the project in Studio Pro throws (from its **Git provider**, not model load):
```
System.InvalidOperationException: Arg_InvalidOperationException
  at ...ObjectUtil.ThrowIfNull[T](T value)
  at ...LibGit2RepositoryProvider.WriteBaseFile(String versionedFilePath, String destinationPath)
```
Cause: git tracked 369 `mprcontents/*.mxunit` that vanished + a 49 MB binary `.mpr` swapped in; SP's LibGit2 integration can't write base files for the missing tracked paths. `git status` shows ~370 `D` (deletions) + `M Project.mpr`.

### Why it matters beyond SP
The entire toolkit workflow assumes split format: mxcli's own MDL exec writes *into* `mprcontents/`, `exec.sh` commits `mprcontents/`, BUG-19 recovery does `git checkout HEAD -- mprcontents/`. A monolithic `.mpr` is off-workflow. **Normal `mxcli exec` (MDL) preserves the split format; only `marketplace install` / `mx module-import` collapses it.**

### Prevention (the rule)
**On a split-model project (has an `mprcontents/` dir), do NOT use `mxcli marketplace install`.** Import marketplace modules through **Studio Pro** (Marketplace panel, or App → Import module package), which preserves `mprcontents/`. Reserve mxcli for MDL exec only.
- Safe to use `mxcli marketplace download <id>` (writes a `.mpk` to disk, touches nothing in the model) — then GUI-import that `.mpk`.
- Detection before it bites: if `find mprcontents -name '*.mxunit' | wc -l` drops to 0 and the `.mpr` balloons to MBs after an install, you hit this.

### Recovery (proven, non-destructive)
1. **Close Studio Pro** (never restore files under an open SP — split-brain, see learned-mcp-patterns §2).
2. Restore the pre-import split snapshot (both `.mpr` + `mprcontents/`):
   ```bash
   bash bin/restore-mpr.sh .mpr-snapshots/<pre-import-stamp>   # or: git checkout HEAD -- <app>.mpr mprcontents/
   ```
   (Prefer the snapshot if there were uncommitted model changes before the import — HEAD may be behind.)
3. Verify: `.mpr` back to ~KB, `find mprcontents -name '*.mxunit' | wc -l` back to prior count, `git status` deletions gone.
4. Re-import the modules via Studio Pro GUI instead.

### Toolkit-fix candidate
`exec.sh`-style guard: before/after `marketplace install`, assert `mprcontents/` file count is non-decreasing and `.mpr` size stays in KB range; abort+restore otherwise. Better: `learned-mdl-preflight.md` STOP row — "marketplace install on a split-model project → use Studio Pro, not mxcli."

---

## Studio Pro Git integration crashes on project open (Team Server repo) — detach .git to open

**Discovered:** 2026-07-22 (a PLM parts-flow project, Studio Pro 11.12.1 Beta, Mendix Team Server Git repo, working branch `pipeline-artifacts`).

### Symptom
Opening the project in Studio Pro throws during project-open, from the VC layer (not model load):
```
System.InvalidCastException: Unable to find 'system' property in 'system'
  at ...Core.State.PropertyBag.GetProperty[T](String key, String path)
  at ...VersionControl.Git.VersionControlAnalyticScopeFactory.OnProjectOpened(IProject project)
```
(A related earlier crash on a broken working tree: `LibGit2RepositoryProvider.WriteBaseFile ... ThrowIfNull`.)

The project is a Team Server project (remote `https://git.api.mendix.com/<id>.git/`, `mendix.sprintr-project-id` in git config, git notes `refs/notes/mx_metadata`). SP's Git analytics scope factory runs on open and throws. Likely a Beta-specific VC bug; not reproduced on GA (unconfirmed — could not web-verify).

### Workaround (reliable)
SP activates its Git integration only when it detects a `.git` at/above the project. Temporarily detach it:
```bash
mv .git .git.disabled-for-sp-import     # before opening SP
# ... open SP, do model work (imports, edits), Save, close SP ...
mv .git.disabled-for-sp-import .git     # restore
git add -A && git commit ...            # commit from terminal (SP closed)
```
Terminal git/mxcli work fine with `.git` attached — the crash is ONLY Studio Pro opening a project while `.git` is present. So: **git detached whenever SP is open; git attached for terminal commits with SP closed.**

### Related launch gotcha (same session)
- `open -a "<Studio Pro app>" file.mpr` (handing the .mpr to macOS) → "couldn't open item of data type". Instead launch bare `open -a "Mendix Studio Pro 11.12.1 Beta"` then File→Open inside SP.
- A half-launched SP can jam further launches — `pkill -f "Mendix Studio Pro"` before relaunching.
- Double-clicking .mpr routes through Mendix Version Selector, which may silently do nothing → use bare-launch + File→Open.

## GRANT: association names silently dropped from member lists; multiple rules per role on one entity not supported

**Discovered:** 2026-07-22 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1).

### Symptom 1 — association as a grant member
Adding an association name to a `READ (...)`/`WRITE (...)` member list in a `GRANT` statement execs with 0 errors and passes `mxcli check --references` (which does not validate grant-member names at all — even a totally nonexistent field name like `"TotallyMadeUp12345"` passes `--references` clean). But the association never appears in the resulting grant. Confirmed via `DESCRIBE ENTITY` after real exec, both forms tested:
```sql
GRANT Administration."User" ON Administration."Account" (READ ("FullName", "Account_Supplier"));      -- dropped
GRANT Administration."User" ON Administration."Account" (READ ("FullName", "TFC.Account_Supplier"));  -- also dropped (module-qualified)
```
Exec's own echoed `Result:` line is the only signal — it omits the association from the granted member list even though the statement reported success.

### Symptom 2 — same role, multiple rules on one entity
mxcli cannot represent two separate access rules for the *same* module role on the *same* entity. A later `GRANT` for a role that already has any rule (from a prior `GRANT` in this or an earlier exec) silently **replaces** that role's rule rather than adding a second one — confirmed:
- Two `GRANT Administration.User ON X (...)` statements in the same script → only the last is kept.
- Same two statements split across two separate `exec` invocations (with a git commit between) → same result, only the last is kept.
- Even with **no** `REVOKE` at all beforehand → a second `GRANT` for an already-granted role still replaces the first.

This contradicts real Mendix, which fully supports multiple rules per role on one entity (visible in Studio Pro's access-rule editor, and present in this project's own marketplace-provided `Administration.Account` entity, which shipped with 2 separate `Administration.User` rules — one unscoped read, one self-scoped read/write — before any mxcli edit touched it).

### Workaround
- **Association-as-member:** don't try to grant an association explicitly via mxcli. If the association is only used inside an XPath constraint (`[Assoc = '[%CurrentUser/OtherAssoc%]']`), no member-level grant is needed — Mendix's security engine resolves `[%CurrentUser/Assoc%]` independent of the user's own read permission on that member. Only add the explicit member grant (via Studio Pro GUI) if a microflow/page actually needs to *display* the associated object's data to that role.
- **Multiple rules per role:** if the entity didn't originate with multiple same-role rules already in the BSON, mxcli cannot construct a second one for you. Either (a) merge the intended rules into one (e.g. combine an unscoped read + a self-scoped read/write into one self-scoped rule, accepting the narrower scope — verify nothing in the app depends on the broader access first), or (b) add the second rule via Studio Pro GUI (its editor is unaffected by this mxcli limitation).
- `mxcli check --references` gives **zero** signal for either symptom — it doesn't validate GRANT member names or detect rule collapse. The only reliable verification is `DESCRIBE ENTITY <name>` immediately after every access-rule-touching exec, comparing the actual member/rule list against what the script intended.

### Related preflight rule
Builds on `learned-mdl-preflight.md` rule 14 (revoke-all/regrant-all when patching one role's rule) — that rule assumes mxcli can construct N rules per role from N GRANT statements. It cannot. Rule 14's guidance to rebuild the *whole entity's* security in one script is still correct for avoiding cross-role collapse, but does not extend to multiple rules for the *same* role — that case has no mxcli-only fix.

## CRITICAL: mxcli exec of association + GRANT script corrupted the MPR's BSON storage (unrecoverable except by restore)

**Discovered:** 2026-07-22 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1).

### Symptom
After `mxcli exec` of a script creating an association (`Account_Supplier`, Administration↔TFC) plus `GRANT` rules referencing it (the same script documented in the "association names silently dropped from member lists" entry above), the `.mpr` became unopenable — both in Studio Pro GUI and in `mxbuild` (any platform, any architecture):
```
System.AggregateException: ... System.Collections.Generic.KeyNotFoundException:
The given key '562830a8-ff20-4507-8d13-d435c347d2bd' was not present in the dictionary.
  at Mendix.Modeler.Storage.Operations.StreamingBsonUnitReader.ResolvePostponedProperties()
```
This is a **postponed-property BSON resolution failure** — the storage layer wrote a unit referencing another unit's GUID that was never actually persisted (or was persisted incompletely), so on next load the reference can't resolve. It reproduces identically on Studio Pro's native macOS mxbuild (11.12.1, Mach-O arm64) and is not an artifact of any particular mxbuild binary — the `.mpr`/`mprcontents` on disk are genuinely corrupt at the storage level, not just at the model-semantics level `mxcli check` would catch.

### How it was root-caused
`bin/exec.sh`'s mxbuild gate (see "gate never ran" note below) had not actually been validating anything, so the corruption went uncaught for several subsequent commits. Root-caused by bisecting `.mpr-snapshots/` (which `exec.sh` takes before every script) with a working native `mxbuild`: the snapshot taken immediately before the association+GRANT script's exec loaded clean; the snapshot taken ~5s after that script's commit was already corrupt with the identical GUID-not-found error. No other script touched the model in between.

### Workaround / recovery
There is no known in-place repair — the fix is **restore from the last snapshot that predates the corrupting exec** (confirmed clean via a real mxbuild run, not just "the previous snapshot" — see gate-fix note below) and redo the association + GRANT via Studio Pro GUI instead of mxcli.

### Related gate failure (compounding factor, not the root cause)
Separately discovered in the same incident: this project's cached `~/.mxcli/mxbuild/<version>/modeler/mxbuild` was a **Linux ELF binary** (from a `setup mxbuild --force` at some point, intended for Docker builds) sitting on a macOS/arm64 host — every native invocation failed with `exec format error` (exit 126). `bin/exec.sh` has a branch that should hard-fail loudly on a nonzero mxbuild exit, but the gate's "0 errors" claims still made it into several commit messages/PROJECT.md — meaning either the gate wasn't actually the path used for those commits, or a past session recorded gate success without checking its actual exit status. Either way: **`mxcli setup mxbuild -p <project>.mpr` (no `--force`) will correctly prefer Studio Pro's bundled native binary if Studio Pro is installed** — but it only resolves the path at call-time, it does *not* cache/symlink it into `~/.mxcli/mxbuild/`, so any script (like `bin/exec.sh`) that does a naive `ls ~/.mxcli/mxbuild/*/modeler/mxbuild` will keep finding the stale wrong-arch binary. Any exec-gate script should either shell out to `mxcli` for binary resolution or sanity-check the cached binary (`file`, or run `--version` and check exit 0) before trusting it as a gate.

## Any GRANT/REVOKE exec in a module fails once ANY entity there has an Account_Supplier-style cross-module XPath — 3rd occurrence, this time caught cleanly

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1), same project/association as the two entries above — this is the 3rd data point on the same root cause, refining the scope of the unsafe operation.

### Symptom
`Administration.Account_Supplier` (Administration↔TFC, Reference, Default owner) was added cleanly via Studio Pro GUI per the workaround above, confirmed present via `SHOW ASSOCIATIONS`. A subsequent, unrelated mxcli script (`03b-tfc-domain-revision.mdl`) then dropped/recreated two non-persistent-to-persistent entities, added two new entities, added a new same-module association (`TFC.TFCStub_Supplier`), and — per STOP rule 14 — rebuilt **all four** role grants on `TFC.TFCStub` in one block (revoke all, regrant all), including a new Vendor XPath `[TFCStub_Supplier = '[%CurrentUser/TFC.Account_Supplier%]']` copying the already-existing `FeasibilityDecision` pattern.

`bin/exec.sh`'s `mx check` gate caught 2 errors post-exec, both `CE0161` "Error(s) in XPath constraint":
- `Access rule of entity 'TFC.TFCStub'` (the one this script actually touched)
- `Access rule of entity 'TFC.FeasibilityDecision'` (**untouched by this script** — a pre-existing rule from a prior, already-committed exec, broken as collateral damage)

Auto-restore worked correctly this time (unlike the BSON-corruption entry above) — rolled back to the last known-good snapshot and reported clearly. But that snapshot predated *both* this script *and* the `Account_Supplier` GUI addition, so the association was lost from the working tree again too (the git commit recording it still exists in history, but `.mpr`/`mprcontents` on disk reverted under it — a real, visible working-tree/HEAD mismatch, not silently reconciled).

### Root cause (refined from the two entries above)
The failure isn't scoped to "creating the association + a grant referencing it in the same script" (the original 2026-07-22 finding) — it's that **once any entity access rule anywhere in a module has an XPath referencing this association, mxcli cannot successfully write *any* GRANT/REVOKE touching *any* entity in that module**, even when the script never mentions the broken rule. mxcli's domain-model write path appears to reserialize the whole `Domain model` unit on any access-rule change, not just the targeted entity — so a previously-fine `FeasibilityDecision` rule gets re-touched and re-broken purely as a side effect of an unrelated `TFCStub` grant rewrite in the same exec.

### Workaround (updated)
Once a module contains **any** entity access rule with a cross-module `[%CurrentUser/OtherModule.Assoc%]` XPath, treat **all** subsequent GRANT/REVOKE work on **any** entity in that module as Studio-Pro-GUI-only — not just the rule that references the association. Structural changes (entities, attributes, non-security associations) in the same module remain mxcli-safe; only the access-rule layer is affected. Verify with `DESCRIBE ENTITY` + a real `mx check` (not just `mxcli check --references`, which gives zero signal for this) after every grant-touching exec in an affected module.

### Related preflight rule
Extends STOP-table rule 14 (`learned-mdl-preflight.md`) — rule 14's "rebuild the whole entity's grants in one script" guidance is still correct for avoiding cross-role collapse *within* a single entity, but does not protect against this failure mode, which crosses entities within the same module. New STOP-table entry added (rule 16) generalizing this.

### Correction (2026-07-23, same day) — root cause was invalid XPath syntax, not mxcli corruption
Re-diagnosed after the user manually fixed the `FeasibilityDecision` Vendor rule in Studio Pro and shared before/after screenshots. The actual bug: `[Assoc = '[%CurrentUser/Module.OtherAssoc%]']` — a path expression *inside* the `[%CurrentUser/...%]` substitution token, crossing module boundaries — is invalid Mendix XPath. `CE0161` was Mendix correctly rejecting it every time, not mxcli corrupting the domain model. The "unrelated `FeasibilityDecision` rule also broke" symptom above was actually two independently-broken rules (both written with this same invalid form) surfacing together the first time a full `mx check` ran on both — not evidence of one grant rewrite damaging an unrelated rule.

**Confirmed working fix**, applied manually in Studio Pro:
```
-- Broken:
[FeasibilityDecision_Supplier = '[%CurrentUser/TFC.Account_Supplier%]']
-- Fixed — keep CurrentUser bare, walk the whole chain on the left,
-- qualifying the entity name at each module crossing:
[TFC.FeasibilityDecision_Supplier/TFC.Supplier/Administration.Account_Supplier = '[%CurrentUser%]']
```
This means the "Studio Pro GUI only, module-wide" conclusion above was too broad. Once an access-rule XPath uses the correct bare-CurrentUser/full-LHS-chain form, there's no known reason it can't be written via mxcli directly. **Confirmed same day**: `test-05-currentuser-xpath-chain.mdl` rebuilt all 4 `FeasibilityDecision` role grants via mxcli exec, reproducing the corrected Vendor XPath verbatim — `mx check: 0 errors`. The corrected form is genuinely mxcli-safe, not just Studio-Pro-GUI-safe. See STOP-table rule 16 (updated) for the corrected pattern — no GUI-only restriction remains for this specific XPath shape.

## Inline association-set (STOP rule 9): same-module confirmed safe via plain CLI on v0.16.0 -- cross-module remains broken

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1). Scoping clarification of rule 9, not a reversal -- the pre-existing 2026-07-13 finding on this same mxcli version (`System.User_UserRoles`, cross-module, a WMS conversion project) still stands.

### What was tested
1. Isolated throwaway test: two brand-new entities in the same project module (`TFC`), new `Reference` association between them, set inline via `CHANGE` inside a microflow, executed via plain `bin/exec.sh`. `mx check` and full `mxcli docker check`: 0 errors. Cleaned up via the same plain-CLI path -- also clean.
2. Real production script: `06-tfcint-bomstub.mdl`, a 176-activity microflow with 46 inline association-sets, all entirely within `TFC`. Ran via plain `bin/exec.sh` after MCP mode proved unreliable. `mx check`: 0 errors.

### What this does and does not mean
- Same-module inline association-sets (both sides in one module, including a marketplace module's own internal associations) are safe via plain CLI on v0.16.0.
- Cross-module inline association-sets remain a confirmed STOP -- the `System.User_UserRoles` finding is untouched by this entry. Do not extrapolate; the two were tested separately and behave oppositely on the identical mxcli version.
- When unclear whether an association is same-module or cross-module, default to treating it as cross-module and use `--mcp`.

### MCP reliability note (same session)
Before falling back to plain CLI for `06`, MCP mode failed twice on a stale module-container reference, then hung unresponsive after a fresh Studio Pro reopen (required a hard kill). MCP itself is not consistently available even when it's technically the correct choice.

### Related preflight rule
STOP-table rule 9 updated to reflect the same-module/cross-module split precisely, rather than a blanket "use MCP" for all inline association-sets.

## Compound boolean `AND`/`OR` (uppercase) + `!=` in the same expression → CE0117/CE0161 (mxcli bug)

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1).

### Symptom

A microflow with a compound boolean condition mixing an uppercase `AND` and a `!=` comparison — in a Decision/IF activity, or in a `retrieve ... where` clause — passes `mxcli check` (with or without `--references`) cleanly, but a real `mx check` (or Studio Pro compile) fails:

```
[error] [CE0117] "Error(s) in expression." at Decision '$Flag = Enum.HIGH AND $Outcome != Enum.ReleaseHold'
[error] [CE0161] "Error(s) in XPath constraint." at Retrieve object(s) activity '...'
```

### What was tested (isolated throwaway microflows, each executed via plain `bin/exec.sh` + a real `mx check`)

1. `IF $Flag = Enum.HIGH AND $Outcome != Enum.ReleaseHold THEN` → **CE0117**.
2. Same expression wrapped in explicit parens per comparison (`($Flag = Enum.HIGH) AND ($Outcome != Enum.ReleaseHold)`) → **still CE0117**. Parens are not the fix.
3. Same expression with lowercase `and` (no parens): `$Flag = Enum.HIGH and $Outcome != Enum.ReleaseHold` → **0 errors**.
4. Isolation of the actual trigger: uppercase `AND` combined with two `=` comparisons (no `!=`) → **0 errors**. Uppercase `OR` combined with two `=` comparisons → **0 errors**.
5. Same bug reproduced in a `retrieve ... where` clause, not just a Decision activity: `where PartId = 'x' AND PlantCode = $P AND "Status" != Enum.Archived` → CE0161. Switching to lowercase `and` → 0 errors.
6. **Correction (2026-07-23, same session):** the write-up originally claimed uppercase `OR` + `!=` fails "by symmetry" with `AND` + `!=`, without actually testing that combination — step 4 above only tested `OR` with two `=` comparisons. Flagged by the user as an unconfirmed assumption before it could harden into a toolkit rule. Retested directly: `IF $Outcome = Enum.Release OR $Outcome != Enum.ReleaseHold THEN` → **CE0117**, confirming the symmetry claim was correct, but it is now evidence-backed rather than inferred. Lesson: don't write a toolkit rule broader than what was literally executed through a real `mx check` — test every named combination (`AND`+`!=`, `OR`+`!=` are two separate claims), even when a pattern seems obviously symmetric.

### Fix

Use lowercase `and`/`or` for boolean keyword operators in microflow expressions and retrieve WHERE clauses. Confirmed safe in every tested combination (lowercase + `!=`, uppercase + only `=`). Since the exact trigger boundary is narrow and easy to miss, treat lowercase `and`/`or` as the default habit rather than trying to remember which combination is safe.

### Root cause (inferred, not confirmed against mxcli source)

Likely an mxcli expression/XPath serializer bug in how it tokenizes `!=` after an uppercase `AND`/`OR` keyword — not a real Mendix expression-language restriction. Studio Pro itself has no issue with lowercase `and` + `!=`, and accepts uppercase `AND`/`OR` fine when no `!=` is present in the same expression, which rules out a genuine grammar restriction on operator case.

### Related preflight rule

Added as STOP-table rule 17 in `learned-mdl-preflight.md`.

---

## BUG-WF01: `ANNOTATION` in workflow body → BSON constructor crash (MX 11.12.1, mxcli v0.16.0)

**Severity:** High — mx check hard-crashes (MPR won't load), not a CE error  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.12.1  
**mxcli version:** v0.16.0  

### Symptom

After executing a `CREATE WORKFLOW` script that contains `ANNOTATION` statements in the workflow body, `mx check` crashes before reporting any model errors:

```
Type Mendix.Modeler.Workflows.Model.Annotation does not contain a constructor
with a parameter of type Mendix.Modeler.Workflows.Model.Flow
```

The MPR appears to load (no SQLite error), but mxbuild can't construct the workflow's annotation objects — the project is broken. `bin/exec.sh`'s size guard is not triggered (the file isn't truncated, just corrupted).

### Fix

Remove all `ANNOTATION` statements from workflow bodies. Annotations in workflows must be added via Studio Pro after the workflow exists.

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1), during Phase 3c script 09.

---

## BUG-WF02: `WITH (...)` parameter mapping in workflow `CALL MICROFLOW` → null ParameterId BSON

**Severity:** High — silent at exec, fails at runtime  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.12.1  
**mxcli version:** v0.16.0  

### Symptom

`CALL MICROFLOW TFC.MyMF WITH (TFC.MyMF.Param = '$workflowContext')` in a workflow body causes mxcli to write a null `ParameterId` into the BSON unit. `mxcli check` and `mx check` both pass (0 errors), but at runtime the parameter binding is invalid and the call fails.

**Status (retested 2026-08-03): RESOLVED on RnD, PARTIALLY RESOLVED on Engalar.** Repro'd against
RnD `bin/mxcli` (HEAD `504aec67`) and Engalar `bin/mxcli` (`26f2866`) on a fresh pristine project.
`CALL MICROFLOW ... with (Item = '$workflowContext')` (lowercase, exactly as written above) now
round-trips correctly through `DESCRIBE WORKFLOW` and passes a real `mx check` with 0 errors on
**RnD** — three dated fixes landed 2026-07-29 (in HEAD, not yet in the tagged v0.16.0 release):
`253d60d8` (version-gate call-microflow storage name at Mendix 11.9), `08746d00` (flag unmapped
workflow call-microflow parameters, FINDINGS #40), `1b390dce` (match outcomes to return type +
**normalize the context variable's case**, FINDINGS #39 regression), `b6a5043a` (parse
CallMicroflowActivity storage name on read). The case-normalization fix (`1b390dce`) is the load-bearing
one here: RnD silently rewrites a lowercase `'$workflowContext'` to the actual param name
`$WorkflowContext` before storing it.
**Engalar does not have that normalization fix.** The identical lowercase `with (Item =
'$workflowContext')` — i.e. exactly the syntax this bug's own "no WITH" fix note assumes is safe —
fails a real `mx check` with `CE0161`/`CE0117` ("Error(s) in expression") on Engalar, isolated and
confirmed reproducible. Using the capitalized `'$WorkflowContext'` instead passes cleanly on
Engalar too (0 errors) — so Engalar's WITH-clause path itself works, it just never got RnD's
case-insensitivity fix. See BUG-WF04 below for the consolidated, corrected guidance — this entry's
"remove all WITH clauses" fix advice is now superseded and should not be followed as written.

### Fix (superseded — see BUG-WF04)

Remove all `WITH (...)` clauses from `CALL MICROFLOW` statements inside workflow bodies. The workflow runtime automatically binds the workflow context object to the called microflow's first entity-typed parameter that matches the context type — no explicit mapping is needed or supported via MDL.

Confirmed from the engalar/mxcli fork's `24-workflow-examples.mdl`: workflow `CALL MICROFLOW` statements use bare form with no argument list.

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1), Phase 3c script 09.

---

## BUG-WF03: `DECISION` with enum comparison in workflow body → CE0117 (MX 11.12.1, mxcli v0.16.0)

**Severity:** Medium — blocks scripting workflow branching via mxcli  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.12.1  
**mxcli version:** v0.16.0  

### Symptom

`DECISION '$workflowContext/Status = TFC.ENUM_TFCStatus.Release'` in a workflow body produces CE0117 "Error(s) in expression" regardless of quoting style tried (`TFC.ENUM_TFCStatus.Release`, `'Release'`, quoted attribute). `mxcli check` passes; `mx check` reports CE0117.

Note: this is a plain `=` comparison (no `!=`), so it is distinct from the AND/OR + `!=` bug (BUG in learned-mdl-preflight rule 17). The trigger here appears to be the DECISION context itself in workflow scope, not the operator combination.

### Fix

Remove DECISION gateways from the MDL script. Wire the decision gateway manually in Studio Pro after the workflow exists. Studio Pro can add a gateway via drag-and-drop with no CE errors.

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1), Phase 3c script 09.

---

## Bare `Status` attribute name in a `retrieve ... where` clause → CE0161 (reserved-word conflict)

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1), same debugging session as the AND/OR bug above.

`retrieve $X from TFC.TFCStub where ... and Status != Enum.Archived` passes `mxcli check` but fails a real `mx check` with CE0161. Quoting the attribute (`"Status" != Enum.Archived`) fixes it. Notably, this project's own domain model already quotes `"Status"` specifically in `TFCStub`'s access-rule read lists, while every sibling attribute in the same list is unquoted — a pre-existing signal (visible via `DESCRIBE ENTITY`) that this specific attribute name needs quoting, which would have shortened the debugging cycle if checked first. Added to the "Keyword collisions" bullet in `learned-mdl-preflight.md`.

---

## BUG-24: `CALL MICROFLOW` in a workflow without `WITH` clause → broken activity (red pin) + runtime crash

**Discovered:** 2026-07-24 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1 Beta), Phase 3c script 09.

**Status (retested 2026-08-03): NOT REPRODUCIBLE on RnD or Engalar.** This is the exact "no WITH
clause, microflow has a required param" case from the sibling BUG-WF02 entry above. On both current
binaries (RnD `504aec67`, Engalar `26f2866`), omitting the `WITH` clause entirely does **not**
produce a broken activity or crash — both CLIs auto-bind the microflow's sole entity-typed
parameter to the workflow context automatically, and `DESCRIBE WORKFLOW` shows the resulting
`with (Item = '$WorkflowContext')` mapping was inserted for you. A real `mx check` passes with 0
errors on both forks for the no-WITH case. This directly contradicts this entry's original "always
use WITH, or the model won't load" claim — likely stale from before the auto-binding path existed,
or from a case where the microflow had more than one entity-typed parameter (untested here; worth
retrying if seen again with a multi-param microflow). RnD additionally now warns proactively at
`mxcli check --references` time (FINDINGS #40, commit `08746d00`) if a required param is left
unmapped — Engalar has no equivalent warning, but the auto-bind still succeeds regardless of the
warning being present. See BUG-WF04 below for the consolidated guidance replacing both this entry
and BUG-WF02's original fix advice.

### Symptom

Writing a `CALL MICROFLOW` activity inside a `CREATE WORKFLOW` body **without** a `WITH (...)` parameter mapping clause creates a broken activity in the model when the target microflow has parameters. In Studio Pro, the activity shows as a red pin and cannot be double-clicked. At runtime the app crashes immediately:

```
java.lang.RuntimeException: No new model classes have arrived within ten seconds,
aborting model initialization (Class 'Workflows$CallMicroflowTask' could not be found).
```

`mxcli check` and `mxcli check --references` both pass clean — the corruption is invisible until SP open or runtime.

### Root cause

mxcli creates the `CallMicroflowTask` model object but leaves the parameter bindings empty when no `WITH` clause is provided. The runtime model loader then cannot deserialize the incomplete object, causing the entire model load to abort.

### Fix

Always use the `WITH` clause when the target microflow has parameters:

```sql
-- WRONG (no WITH → broken activity, red pin, runtime crash)
CALL MICROFLOW TFC."WF_ACT_RiskAgent_RiskFlag";

-- CORRECT
CALL MICROFLOW TFC."WF_ACT_RiskAgent_RiskFlag"
  WITH (TFC."WF_ACT_RiskAgent_RiskFlag"."TFCStub" = '$workflowContext');
```

The `WITH` key format is `Module."MicroflowName"."ParameterName" = '$workflowContext'` where `$workflowContext` is the workflow's context variable. Microflows with no parameters do not need a `WITH` clause.

**Added STOP rule to `learned-mdl-preflight.md`** (rule 18).

**Recovery:** `CREATE OR REPLACE WORKFLOW` with correct `WITH` clauses on all `CALL MICROFLOW` steps. Drop-and-recreate is safer than `ALTER WORKFLOW REPLACE` when multiple activities are broken.

---

## BUG-25: `CREATE WORKFLOW` writes null ContentsBlob in SQLite — mx check crashes with InvalidCastException

**Severity:** Critical — workflow unit is unusable; mx check crashes on project load  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.12.1 Beta  
**mxcli version when found:** v0.16.0  
**Discovered:** 2026-07-24, a PLM parts-flow project Phase 3c (script 09g)

### Symptom

`CREATE WORKFLOW` reports success. `SHOW WORKFLOWS` returns 0 workflows. mx check crashes:

```
System.InvalidCastException: Unable to cast object of type 'System.DBNull' to type 'System.Byte[]'.
  at MprV1UnitRepository.GetUnitContents(...)
```

### Root cause

mxcli v0.16.0 inserts the workflow unit into the SQLite `Unit` table but writes a null `ContentsBlob`. For the split-format MPR (v2), the BSON should be written to `mprcontents/{uuid}.mxunit` with a null blob in SQLite. For the v1 format, the BSON goes in the blob. mxcli writes neither — the blob is null and no mxunit file is created. mx check's MPR loader casts the null blob to `byte[]` and crashes.

### Workaround

Create the workflow in Studio Pro:
1. Detach git first: `mv .git .git-bak`
2. Open SP → App Explorer → Right-click module → Add other → Workflow
3. Set the context entity, drag WF_ACT_* microflows onto canvas (SP auto-wires params on drop)
4. Save, close SP, reattach: `mv .git-bak .git`
5. Commit `.mpr` + `mprcontents/`

### Does NOT affect

- `ALTER WORKFLOW set display/description` — scalar updates work
- `ALTER WORKFLOW insert after ... call microflow` — inserts into existing workflow work (but WITH clause has separate bug, see BUG-24)

### STOP rule

Added to preflight rule 18: `CREATE WORKFLOW` — use Studio Pro, not MDL.

---

## BUG-26: `--mcp exec` unreliable for `ALTER PAGE` writes — widget-not-found on valid live anchors, malformed patch on trivial SET

**Severity:** High — blocks the entire MCP page-patching workflow this project relies on for DG2/pluggable-widget work
**Reproducible:** Yes, 3/3 attempts across 2 different failure modes
**Mendix version:** 11.12.1
**mxcli version when found:** v0.16.0
**Discovered:** 2026-07-25, a PLM parts-flow project Phase 4 MCP pass, live SP session open the whole time (lock file confirmed live PID)

### Symptom 1 — "widget not found" on anchors confirmed present via `DESCRIBE PAGE`

Three separate `ALTER PAGE ... INSERT AFTER "<widget>"` attempts, on 3 different pages/anchor types, all failed:

```
./mxcli --mcp http://localhost:7782/mcp exec 39-....mdl -p Project.mpr
Error: failed to insert: widget "CreatedOn" not found
```
(anchor was a DG2 datagrid column, name confirmed via `DESCRIBE PAGE TFC.TFC_PMODashboard` immediately beforehand)

```
Error: failed to insert: widget "SupplierName" not found
```
(same page, a different DG2 column)

```
Error: failed to insert: widget "row6" not found
```
(TFC_SupplierOverview — a plain top-level LAYOUTGRID row, NOT a DG2-internal widget, ruling out "DG2 columns aren't addressable" as the sole explanation)

`--mcp-verbose` printed no PED tool-call trace before any of these errors — the failure happens before a `pg_patch_page` call is even logged, suggesting local anchor resolution (against the `-p` disk file) disagrees with whatever the live SP in-memory model actually has, OR the widget-name lookup path used for `INSERT AFTER` targeting is broken independent of the anchor's real existence.

### Symptom 2 — malformed patch on a trivial single-property SET

```sql
ALTER PAGE "TFC"."TFC_SupplierOverview" {
  SET Title = 'Vendor Portal'
};
```
```
Error: failed to save modified page: pg_patch_page TFC.TFC_SupplierOverview: Error invoking tool 'pg_patch_page':
Error executing tool pg_patch_page: Operation at index 1 failed.
Details: {"errors":[{"code":"PROP_NOT_PRIMITIVE","message":"Property 'widgets' is not a primitive property", ...}]}
```
This got further than Symptom 1 (a real `pg_patch_page` call was made — "Operation at index 1" implies mxcli generated ≥2 patch operations for a single `SET Title` MDL statement), but operation 1 apparently touches `widgets` as a whole (a non-primitive/array property) rather than the scalar `Title` field — looks like a bug in mxcli's MDL→JSON-Patch translation layer itself, not anything specific to this project's page structure.

### Impact

Blocks the `--mcp exec` path entirely for `ALTER PAGE` writes on this project/version combo — both the DG2-column-append use case (expected to need raw `pg_patch_page`, per `learned-mcp-patterns.md`) AND plain structural inserts/SETs that were expected to work per `mxcli mcp capabilities`' own claim ("Pages — CREATE + ALTER (widget coverage grows per type)").

### Not yet tried

- Whether reads via `--mcp` (not `-p`) would resolve the anchor mismatch (mxcli's own `--help` says "reads come from -p" always, so this may not be possible without a mxcli change).
- Whether a freshly-reopened SP session (git-reattach → close → sp-open.sh cycle) changes anything — not attempted, to avoid disrupting an in-progress session's unsaved state.
- Whether this repros on a page with zero DG2 grids / zero customContent columns at all (all 3 test pages here have at least one DG2 grid elsewhere on the page, even when the failing target itself wasn't DG2-internal).

### Workaround

None found yet. Recommend Studio Pro GUI for all `ALTER PAGE` structural work on this mxcli/SP version pair until root-caused. Reserve `--mcp exec` retries for a narrow, disposable throwaway page to binary-search whether it's a project-specific anchor-resolution issue or a global mxcli v0.16.0 regression.

**Update 2026-07-26 — ruled out disk/live-model drift as the cause.** Fetched the MCP server's `mendix://studio-pro/system-prompt` resource (the one it says all callers must read first) — confirms `pg_patch_page` expects JSON Patch operations against numeric JSON Pointer paths (e.g. `/widgets/0/widgets/2`), resolved by index, not by widget name. Hypothesized this was disk (`-p` reads) vs. live-SP-memory (write target) divergence — a stale on-disk path computed from `-p` could easily miss the live tree if SP had unsaved edits. Tested by triggering a real Studio Pro save via AppleScript (`osascript ... keystroke "s" using command down`, no accessibility-permission error, so it plausibly landed) immediately before retrying the exact same `SET Title` sanity script. **Result: byte-identical failure** — same `PROP_NOT_PRIMITIVE` on `widgets`, same `elementId: f0e9b2e3-b7c7-4d56-a2e1-486e1d43a12b`, operation index 1. This rules out drift as the cause: the bug is deterministic and reproduces regardless of save state, pointing at a genuine bug in mxcli v0.16.0's `ALTER PAGE SET` → `pg_patch_page` JSON-Patch translation (it appears to always emit an operation touching the whole `widgets` array/property for even a single scalar `Title` SET). Root cause still not isolated to a specific line/commit in mxcli — flagging for upstream report.

### STOP rule

Added to preflight: treat `--mcp exec` on `ALTER PAGE` as unverified/high-risk on mxcli v0.16.0 + SP 11.12.1 until this is root-caused — do not chain multiple live attempts against an open SP session without confirming with the user first (each failed call is still a real request against the live model).

---

## Cross-project sweep, 2026-07-31 — findings below are reported, not independently re-reproduced

The following (BUG-27 through BUG-55) were mined from local docs/scripts/bug-logs across 6
other Mendix projects with an mxcli install (a WMS conversion project, a PLM parts-flow project, a large-source WMS project,
a Java/Angular analysis project, a WMS reference app — a third project excluded per project decision). Each entry cites
its source file. None were re-run against a fresh repro in this pass — treat as leads to verify
before filing upstream. Full consolidation notes: `a WMS demo project/bug-logs/uncentralized-findings-2026-07-31.md`.

## BUG-27: Cross-module `grant execute` → CE0148 (distinct trigger from BUG-04)

**Status: DOWNGRADED 2026-08-03** — retested against RnD `504aec67`; RnD now gives a clear
pre-emptive exec-time error rather than a silent/raw CE0148 failure. Not fully clean, but no
longer the hidden-corruption class bug originally reported. Engalar instead crashes on the
broader "multiple Security$ModuleSecurity units" defect — see the new consolidated Engalar
entry below. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-27.md`.
**Reproducible:** Reported only, not re-verified in this pass
**Discovered:** a WMS conversion project, `MIGRATION-PROGRESS.md`

`grant execute` on a microflow fails with CE0148 when the granting role and the microflow's
module differ, in a way not covered by the existing BUG-04 (which is about modules with no
roles at all). Needs a fresh repro to confirm this is a distinct code path from BUG-04.

## BUG-28: `reset layout` accepts invalid MDL at `check` time, fails at `exec`

**Status: RECLASSIFIED 2026-08-03** — not a check/exec disagreement. RnD never implemented
`RESET LAYOUT` at all (no such token in its grammar); Engalar built it from scratch
(commit `2fabbac31`, including a since-fixed coordinate-corruption bug of their own). This is
a feature gap in RnD, not a bug — worth an enhancement request rather than a bug report, if
wanted. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-28.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, project-local `bug-logs/mxcli-bugs.md`

`mxcli check` passes a `reset layout` statement that then fails when actually executed —
syntax checker and executor disagree, same family as BUG-10.

## BUG-29: Double-quoted attribute paths in nav expressions pass `check`, fail CE0117 at mxbuild

**Status: CONFIRMED STILL OPEN 2026-08-03** — reproduced identically on RnD `504aec67` and
Engalar `26f2866`; root cause traced to a shared grammar rule (`attributePath` reuses the
generic `qualifiedName` rule instead of an unquoted-only attribute rule). Draft issue ready:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/01-BUG-29-quoted-attribute-segment.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:153-161` (project-local)

`$Obj/"Attr"` (quoting the attribute segment of a navigation expression) is accepted by
`mxcli check` but rejected by mxbuild with CE0117. Attribute segments in nav expressions must
stay unquoted even under this project's "always quote identifiers" convention.

## BUG-30: `currentDeviceType()` function-call form accepted by grammar, rejected by mxbuild

**Status: PARTIAL FIX 2026-08-03** — RnD `504aec67`'s `check` now catches this via lint rule
MDL044 and exits non-zero, but `exec` run directly still writes the invalid microflow (the
same-family "check vs exec disagree" gap persists at the exec layer). Engalar has no
equivalent lint at all — still fully broken there. Draft issue ready (targets the RnD
exec-side gap): `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/02-BUG-30-currentdevicetype-exec-gap.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:153-161`

The grammar accepts `currentDeviceType()` as a function call, but mxbuild rejects it with
CE0117. Only the bracket-percent token form `[%CurrentDeviceType%]` works.

## BUG-31: Void/boolean-returning JS actions in nanoflows write malformed BSON

**Status: RESOLVED 2026-08-03** — not reproducible on RnD `504aec67` or Engalar `26f2866`.
Safe to remove from the active list. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-31.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:153-161`

A JS action with a `void` or boolean return type, called from a nanoflow, produces BSON that
fails CE0008/CE0109 checks.

## BUG-32: `CREATE` document in an MCP-touched module leaves a dangling unregistered `.mxunit`

**Reproducible:** Reported only
**Discovered:** a WMS conversion project, project-local `bug-logs/mxcli-bugs.md` (BUG-LOCAL-06)

After using MCP against a module, `CREATE` of a document leaves an orphaned `.mxunit` file
that is never registered in the module's unit list — invisible to `DESCRIBE`/`check`/mxbuild,
but causes Studio Pro to hang on open.

## BUG-33: Cross-module association nav-through requires fully-qualified target-entity path

**Status: CONFIRMED STILL OPEN 2026-08-03** — reproduced byte-for-byte identically on RnD
`504aec67` and Engalar `26f2866` (CE0117 on real mxbuild); short form parses and writes
cleanly on both, only the fully-qualified form compiles. Draft issue ready:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/03-BUG-33-cross-module-assoc-nav-unqualified.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:153-161`

`$Item/Module.Assoc/TargetEntity/Attr` (short form) fails for cross-module association
traversal; must fully qualify as `$Item/Module.Assoc/TargetModule.TargetEntity/Attr`.

## BUG-34: MCP `pg_patch_page` rejects `AttributeRef[]` arrays for DataGrid2 external filter-bar widgets

**Reproducible:** Reported only, seen independently in both a WMS conversion project and a WMS conversion project (same underlying project)
**Discovered:** a WMS conversion project, project-local `bug-logs/mxcli-bugs.md`

Setting a typed `AttributeRef[]` array property (DG2 external filter bar attribute list) via
`pg_patch_page` fails with `PROP_NOT_PRIMITIVE`. Same failure family as the `widgets`-array
patch bug in the BUG-26 entry above, but on a different property type.

## BUG-35: `AutoChangedBy`/`AutoChangedDate` binding → CE1613

**Status: ENGALAR-ONLY 2026-08-03** — RnD `504aec67` fully supports `autochangedby`/
`autocreateddate`/`autochangeddate` (plus its own MDL022 lint guard); this only reproduces on
Engalar `26f2866`, whose grammar/lexer never wired up these three token types (only
`AUTONUMBER_TYPE` is implemented). Report to Engalar directly, not upstream to RnD.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:153`

## BUG-36: Scalar parameter from page button to microflow silently fails to bind

**Status: RESOLVED (at check/exec layer) 2026-08-03** — passes on both RnD `504aec67` and
Engalar `26f2866` at the check/exec layer; the runtime layer was not independently retested
(no live app launch in this pass). Safe to downgrade; re-verify at runtime before fully
closing. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-36.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:154`

A non-entity (scalar) parameter passed from a page action button to a microflow silently
fails to bind — no error at `exec` or `check` time, only discoverable at runtime.

## BUG-37: COMBOBOX in association mode rejected by mxcli despite Studio Pro requiring it

**Status: ENGALAR-ONLY 2026-08-03** — RnD `504aec67` already fixed this (commit `240e7d2c`:
reads the association ref from `Association:`/`attribute:`, adds an `MDL-WIDGET16`
incomplete-binding check). Engalar `26f2866` has older, divergent combobox work that
regresses it. Report to Engalar directly with a pointer to RnD's `240e7d2c` as the reference
fix.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:155`

Rejected with internal tag `MDL-WIDGET01`, for a configuration Studio Pro itself requires.

## BUG-38: `DatagridDropdownFilter` in association/ref mode uncreatable via MDL

**Status: CONFIRMED STILL OPEN 2026-08-03** — fails on both RnD `504aec67` and Engalar
`26f2866` (CE1613, association written as a plain attribute path); Engalar additionally
silently drops the nested filter widget entirely, worse than RnD. Draft issue ready:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/04-BUG-38-dropdownfilter-association-mode.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:156`

Workaround: MCP `pg_patch_page` with an explicit `refOptions`/`refEntity`/
`Pages$MicroflowSource` shape.

## BUG-39: XPath filter cannot use an association-traversal expression as the comparand

**Status: CONFIRMED STILL OPEN 2026-08-03** — reproduced on both RnD `504aec67` and Engalar
`26f2866`, verified against real mxbuild (CE0161), not just mxcli's own check. Draft issue
ready: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/05-BUG-39-xpath-association-traversal-rhs.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:161`

Workaround: retrieve the target object first, then filter, instead of filtering directly on
the traversal expression.

## BUG-40: `ALTER WORKFLOW INSERT` does not support USER TASK activities

**Status: RESOLVED 2026-08-03** — passes on both RnD `504aec67` and Engalar `26f2866`; stale.
Safe to remove from the active list. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-40.md`.
**Reproducible:** Reported only
**Discovered:** a PLM parts-flow project, `mdlsource/3c-workflow/archived/09f-tfc-workflow-build.mdl` comment

Only `CALL MICROFLOW` activities can be inserted into a workflow via `ALTER WORKFLOW INSERT`;
USER TASK activities require Studio Pro.

## BUG-41: Pluggable DataGrid2 `textfilter.attributes:` binding accepted but not persisted → CE1613

**Status: RESOLVED (RnD) 2026-08-03** — passes on RnD `504aec67`; not directly comparable on
Engalar `26f2866` (divergent filter architecture). Safe to downgrade for RnD purposes.
Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-41.md`.
**Reproducible:** Reported only
**Discovered:** a PLM parts-flow project, `PROJECT.md:140,170`, `done-18-kt-filterbar-dg2.mdl`

Distinct from BUG-10 and BUG-23 (both about the `Attributes` list generally) — this is
specifically the pluggable-widget `textfilter.attributes` binding.

## BUG-42: Pluggable DataGrid2 cannot combine row-click `Action:` with `DynamicCellClass` + TEXTFILTER/DROPDOWNFILTER

**Status: ENGALAR-ONLY 2026-08-03** — RnD `504aec67` handles this combination cleanly; only
reproduces on Engalar `26f2866`, where the combination reports success but `Action:` and both
filters silently vanish from the widget (only `DynamicCellClass` survives). Report to Engalar
directly, using RnD's datagrid-builder handling as the reference implementation.
**Reproducible:** Reported only
**Discovered:** a PLM parts-flow project, `PROJECT.md:117`

A capability gap rather than corruption — the combination is simply not expressible via MDL.

## BUG-43: `ALTER SETTINGS CONSTANT` corrupts the Settings unit BSON

**Status: RESOLVED 2026-08-03** — passes on both RnD and Engalar; likely mis-attributed to
BUG-22's family originally. Safe to remove from the active list (note: this group's RnD-side
retest substituted the v0.16.0 release binary for a from-source build due to a sandbox
restriction — see `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-43.md` for detail).
**Reproducible:** Reported only
**Discovered:** a large-source WMS project, `handoff/scripts/phase-3-complex-logic/transportation/DONE-17-flip-stubs.mdl:19`

Same corruption family as BUG-22 (`ALTER SETTINGS CONFIGURATION`/`ALTER SETTINGS MODEL`/
`ALTER PROJECT SECURITY LEVEL`), but BUG-22 doesn't list `ALTER SETTINGS CONSTANT` — worth
folding in if confirmed to be the same code path.

## BUG-44: CE0070 — validation rule on a non-persistent entity's attribute rejected

**Status: CONFIRMED STILL OPEN 2026-08-03** — reproduced on both RnD and Engalar (silently
accepted by check/exec, CE0070 on real compile). Draft issue ready:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/06-BUG-44-ce0070-nonpersistent-validation.md`.
**Reproducible:** Reported only
**Discovered:** a large-source WMS project, `DONE-23b-barcode-scanner-fixes.mdl:1-5`, `DONE-23c-scaninput-recreate.mdl:1`

## BUG-45: CE0161 — XPath `id=` lookups fail via mxcli/MDL retrieve

**Status: CONFIRMED STILL OPEN (fix unreleased) 2026-08-03** — reproduced on both forks;
notably, RnD's own unreleased source already has a targeted lint rule (MDL048, "ledger #42")
that would catch this at check time, but it isn't in any tagged release through v0.16.0.
Draft issue frames this as "please ship MDL048":
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/07-BUG-45-ce0161-id-string-mismatch-mdl048.md`.
**Reproducible:** Reported only
**Discovered:** a large-source WMS project, `DONE-25b-mfc-rest-fixes.mdl:1-16`, `DONE-25c-mfc-rest-final.mdl:1-16`

Workaround: add a dedicated `ExternalId` business-key attribute instead of retrieving by
system `id`.

## BUG-46: CE0066 — security-hash reconciliation failure after a GRANT/security exec

**Status: RESOLVED (RnD) / ENGALAR HAS WORSE BUG 2026-08-03** — passes on RnD `504aec67`.
Engalar `26f2866` doesn't hit this specific CE0066 but instead crashes with the broader
"multiple Security$ModuleSecurity units" defect on the same GRANT-execution path — see the
new consolidated Engalar entry below. Safe to remove from RnD's active list.
**Reproducible:** Reported only, seen independently in both a Java/Angular analysis project and a third, excluded project
**Discovered:** a Java/Angular analysis project, `mdlsource/02-inventory-security.mdl:9`, `architecture/build-plan.md:75,136`, `architecture/open-issues.md:13`

## BUG-47: CE0639 — validation-feedback `Variable` property not wired

**Status: RESOLVED (as originally described) / NARROWER ENGALAR BUG REMAINS 2026-08-03** —
passes on both forks for the reported attribute-path form. Engalar separately has a known,
narrower issue (object-only `validation feedback` form emits a blank Attribute, CE0091) that
Engalar already tracks internally per their own bug-test file. Safe to remove this entry;
flag the narrower Engalar issue to them if not already open.
**Reproducible:** Reported only, seen independently in both a Java/Angular analysis project and a third, excluded project
**Discovered:** a Java/Angular analysis project, `architecture/build-plan.md:118,136`, `architecture/open-issues.md:13`

## BUG-48: Silent microflow-datasource drop on pluggable datagrids

**Status: RESOLVED 2026-08-03** — passes on both RnD `504aec67` and Engalar `26f2866`; this is
RnD's own historical fix (#795), already shipped and inherited by Engalar. Safe to remove from
the active list. (Note: a related but distinct new defect — parameter-binding loss on a
parameterized DG2 microflow datasource, not datasource-drop — was found adjacent to BUG-51;
see the new entry filed separately below.)
**Reproducible:** Reported only
**Discovered:** a Java/Angular analysis project, `mdlsource/12-inventory-history-delete.mdl:6-7`

Workaround: use a `database` datasource via association XPath instead of a microflow
datasource on pluggable datagrids.

## BUG-49: `CREATE OR REPLACE PAGE` silently resets/drops existing view-access grants

**Status: RESOLVED 2026-08-03** — passes on both RnD `504aec67` and Engalar `26f2866`. Safe to
remove from the active list. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-49.md`.
**Reproducible:** Reported only
**Discovered:** a Java/Angular analysis project, `mdlsource/09-regrant-page-access.mdl:4-6` (references CE0557)

No error at write time; grants must be manually reapplied after any `CREATE OR REPLACE PAGE`.

## BUG-50: `ALTER PAGE` cannot reach widgets nested inside a datagrid `customContent` column (broader than BUG-18)

**Status: CONFIRMED STILL OPEN 2026-08-03** — fails on both RnD `504aec67` (hard parse error
past 2 dotted path segments) and Engalar `26f2866` (parses 3 levels but misroutes to
layout-grid-column logic). No working addressing scheme on either fork. Draft issue ready:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/08-BUG-50-alter-page-customcontent-nested-widget.md`.
**Reproducible:** Reported only
**Discovered:** a Java/Angular analysis project, `mdlsource/20-ux-popup-manage-fixes.mdl:12-13`

BUG-18 covers `visible:` on a CONTAINER inside customContent corrupting BSON; this report is
broader — `ALTER PAGE` can't address anything nested inside customContent at all, not just
the `visible:` case.

## BUG-51: Quoting a reference-target identifier before a parenthesized param list breaks parsing

**Status: RESOLVED (as described) — NEW BUG FOUND ADJACENT 2026-08-03** — not reproducible as
originally described on RnD `504aec67` or Engalar `26f2866` across 3 tested contexts (show_page
action, microflow action, microflow datasource; quoted and unquoted). Safe to remove this
entry. However, retesting surfaced a genuine new defect: a DataGrid2 whose parameterized
`microflow` datasource silently drops the parameter binding (CE1571), reproducing regardless of
quoting — tracked as its own new issue, not a continuation of this one. Detail:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-51.md`; new draft issue:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/09-NEW-dg2-parameterized-datasource-ce1571.md`.
**Reproducible:** Reported only
**Discovered:** a Java/Angular analysis project, `mdlsource/05-inventory-pages.mdl:9-10`

`"Target"(Param: value)` fails to parse — reference targets must stay unquoted immediately
before a param list, even though attribute names should generally be quoted per this
project's convention.

## BUG-52: CHANGE-activity attribute quoting → `StorageLoadException` on Studio Pro open (passes mxbuild/check clean)

**Status: RESOLVED 2026-08-03** — passes on both RnD and Engalar; the original source lines no
longer exist to replay exactly, so treat as stale/unreproducible rather than definitively
fixed. Safe to remove from the active list. (Note: this group's RnD-side retest substituted
the v0.16.0 release binary due to a sandbox restriction — see
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-52.md`.)
**Reproducible:** Reported only
**Discovered:** a WMS reference app, `mdlsource/phase-4/fix-18-actualocation-bug.mdl:6`, `fix-14-trigger-state-change.mdl`

## BUG-53: `Visible:` expression on an action button inside a plain DataView corrupts BSON

**Status: RESOLVED (RnD) / ENGALAR HAS DIFFERENT BUG 2026-08-03** — passes on RnD `504aec67`,
which correctly qualifies the bare attribute reference as `$currentObject/Attr`. Engalar
`26f2866` writes it unqualified instead, causing a real CE0117 — report that to Engalar
directly as its own issue, distinct from this one. Safe to remove this entry for RnD.
**Severity:** blank `AttributeIdentifier` written → `StorageLoadException` on Studio Pro open
**Mendix version:** 11.12.0
**mxcli version:** v0.13.0
**Discovered:** 2026-07-16, a WMS reference app, `mdlsource/phase-4/SUPERSEDED-04-state-conditional-buttons.mdl`

Distinct from the already-logged datagrid-customContent `visible:` corruption (BUG-18) — this
one hits a plain DataView, not a grid.

## BUG-54: `--mcp exec` silently renames entities/associations before failing mid-script

**Reproducible:** Reported only
**Discovered:** a WMS reference app, `mdlsource/phase-4/10-rest-mfc-cleanup-rebuild.mdl` header

E.g. `MFC_Simulator.ExRouteItem` renamed to `"Root"` before the script fails on an
unsupported activity type — the rename is committed even though the script as a whole
fails, leaving misnamed objects behind.

## BUG-55: `ALTER PAGE ... DROP ... REPLACE ...` combined in one script → transient duplicate-name collision; and cross-module GRANT EXECUTE/page-view grants silently dropped

**Status: SPLIT AND RETESTED 2026-08-03** — the two findings below were retested separately as
BUG-55a and BUG-55b. **BUG-55a (DROP+REPLACE collision): RESOLVED**, passes on both RnD and
Engalar. **BUG-55b (cross-module GRANT EXECUTE silently no-ops): RESOLVED on RnD** (now
persists correctly); **Engalar instead crashes** on the "multiple Security$ModuleSecurity
units" defect — see the new consolidated Engalar entry below. Safe to remove this entry from
the active list. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-55a.md`,
`BUG-55b.md`.
**Reproducible:** Reported only
**Discovered:** a WMS reference app, `mdlsource/phase-4/DONE-06-mfc-dashboard-new-route-button.mdl` header; session memory `feedback_mdl_patterns.md:36-38`

Two related a WMS reference app findings grouped here:
- `ALTER PAGE` applies a `DROP` + `REPLACE` in one script atomically rather than
  sequentially, causing a transient duplicate-name collision. Workaround: use a full
  `CREATE OR REPLACE PAGE` instead of combining DROP+REPLACE.
- `GRANT EXECUTE ON MICROFLOW` and page-view GRANTs targeting a cross-module role report
  success but are never persisted — unlike entity-access grants, which throw a clear CE
  error for cross-module roles instead of silently no-op'ing.

---

## Engalar-fork-only bugs found during the 2026-08-03 retest

The following do NOT reproduce on RnD (`mendixlabs/mxcli` @ `504aec67`) — they are specific to
the Engalar community fork (`engalar/mxcli` @ `26f2866`) and should be reported to Engalar
directly, not filed upstream. Full detail and per-bug repro scripts:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/`.

### BUG-ENGALAR-01: "multiple Security$ModuleSecurity units" crash on module-role/GRANT operations

**Discovered:** consolidated from retesting BUG-27, BUG-46, BUG-48, BUG-49, BUG-55b
(2026-08-03)

Any `create module role` immediately after `create module` in one script, or any
`GRANT EXECUTE ON MICROFLOW` (even same-module), crashes `exec` with this error on Engalar.
RnD does not have this bug at all. This is the single most impactful Engalar-only defect found
in this retest pass — it acted as a blocking precondition for 5 of the 29 originally-mined
bugs, making several of them look "still broken" on Engalar when the real defect is this one,
more fundamental crash. Two existing Engalar commits touch the same area but don't cover this
path: `4b60e8c56` and `ac7edbea8` ("SOLID-I" ModuleSecurity/ModuleSettings gen-typed API
fixes). Likely location: the module-security-unit lookup in `mdl/executor/security_v2.go`.

### BUG-ENGALAR-02: missing `autochangedby`/`autocreateddate`/`autochangeddate` attribute types

**Discovered:** consolidated from retesting BUG-35 (2026-08-03)

RnD fully supports these three system-audit attribute types (plus an MDL022 lint guard);
Engalar's grammar only wires up `AUTONUMBER_TYPE`, leaving the other three dead in the lexer.

### BUG-ENGALAR-03: COMBOBOX association-mode regression vs RnD's `240e7d2c` fix

**Discovered:** consolidated from retesting BUG-37 (2026-08-03)

RnD fixed association-bound comboboxes in commit `240e7d2c` (reads the association ref from
`Association:`/`attribute:`, adds an `MDL-WIDGET16` incomplete-binding check). Engalar has
older, divergent combobox work that doesn't include this and currently regresses it.

### BUG-ENGALAR-04: pluggable DataGrid2 `Action:`/`DynamicCellClass`/filter combination silently drops properties

**Discovered:** consolidated from retesting BUG-42 (2026-08-03)

Combining a row-click `Action:`, `DynamicCellClass`, and a TEXTFILTER/DROPDOWNFILTER on the
same pluggable DataGrid2 reports success on exec/check, but `DESCRIBE` afterward shows the
action and both filters silently vanished — only `DynamicCellClass` survives. RnD handles the
same combination cleanly.

### BUG-ENGALAR-05: validation feedback, object-only form → blank Attribute (CE0091)

**Discovered:** consolidated from retesting BUG-47 (2026-08-03)

Narrower than the original BUG-47 report and already known to Engalar (documented in their own
`358-validation-feedback-targets.mdl` bug-test): the object-only form of `validation feedback`
(no attribute) parses/describes fine but the builder emits a blank `Attribute`, which Studio
Pro rejects with CE0091. Confirm with Engalar whether it's still open on their end.

### BUG-ENGALAR-06: `$currentObject/` qualifier dropped on `Visible:` expression

**Discovered:** consolidated from retesting BUG-53 (2026-08-03)

RnD correctly qualifies a bare attribute reference in a `Visible:` expression as
`$currentObject/IsActive`; Engalar writes it unqualified, causing a real CE0117 at mxbuild.

---

## New bug found during the 2026-08-03 retest (not one of the original 29)

### BUG-56: DataGrid2 parameterized microflow datasource silently loses its parameter binding (CE1571)

**Discovered:** surfaced while retesting BUG-51, RnD `504aec67` (Engalar not yet checked)

A DataGrid2 `datasource: microflow Module.MF(Param: $value)` calling a **parameterized**
source microflow silently drops the parameter mapping — `mx check` reports
`[CE1571] No argument has been selected for parameter '<name>'` even though the MDL script
supplied one, and `DESCRIBE PAGE` shows the datasource microflow but no parameter mapping.
Reproduces identically whether the target is quoted or unquoted, so unrelated to BUG-51's
original quoting claim (BUG-51 itself is not reproducible — see above). Adjacent to BUG-48
(pluggable DataGrid2 microflow datasource) but a distinct symptom (parameter-binding loss, not
datasource-drop). Draft issue ready:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/09-NEW-dg2-parameterized-datasource-ce1571.md`.

---

## New bug found during the 2026-08-03 workflow-microflow retest (consolidates BUG-WF02 + BUG-24)

### BUG-WF04: `CALL MICROFLOW` in a workflow — corrected, current guidance (supersedes BUG-WF02 and BUG-24)

**Discovered:** retest triggered 2026-08-03 in response to a direct user question about why this
gap wasn't covered by the main 29-bug retest; BUG-WF02 and BUG-24 above were explicitly excluded
from that pass and left stale/contradictory until now.

**The two entries above (BUG-WF02, BUG-24) directly contradicted each other**: one said "always
add a `WITH` clause or the model won't load," the other said "never add a `WITH` clause, it
corrupts the parameter ID." Neither is correct against current binaries. Verified empirically
against RnD `bin/mxcli` (HEAD `504aec67`) and Engalar `bin/mxcli` (`26f2866`) on a fresh pristine
11.12.1 project, using `mxcli exec` + `DESCRIBE WORKFLOW` + a real `mx check`:

| Form | RnD | Engalar |
|---|---|---|
| No `WITH` clause (single-param microflow) | ✅ auto-binds, 0 errors | ✅ auto-binds, 0 errors |
| `with (Item = '$workflowContext')` (lowercase, as BUG-WF02's own "fix" recommended) | ✅ normalized, 0 errors | ❌ `CE0117` — Engalar never got RnD's case-normalization fix (`1b390dce`) |
| `with (Item = '$WorkflowContext')` (correct case) | ✅ 0 errors | ✅ 0 errors |
| Old fully-qualified form `Module."MF"."Param" = '$workflowContext'` | ✅ still parses, normalizes correctly, 0 errors | not retested |

**Current correct guidance:** on RnD, all three forms above work — a `WITH` clause is optional for
a single-param microflow (auto-bound) and, if present, is case-normalized regardless of how you
write `$workflowContext`. **On Engalar specifically, always capitalize the context variable as
`$WorkflowContext`** when writing an explicit `WITH` clause — the lowercase form used throughout
mxcli's own documentation and this log's prior "CORRECT" example will fail a real `mx check` with
CE0117 on that fork. RnD also has a proactive `mxcli check --references` warning
(`08746d00`, FINDINGS #40) for a genuinely unmapped required parameter that Engalar lacks — not
dangerous (auto-bind still succeeds on both), just a smaller safety net on Engalar.

Only tested with a single entity-typed parameter on the target microflow — multi-parameter
microflows (where auto-bind can't pick a single match) are untested and may behave differently;
retest if this comes up.
