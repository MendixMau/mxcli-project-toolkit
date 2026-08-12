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

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

---

## BUG-03: MDL `retrieve ... where [AssocName = $Param]` XPath syntax not documented / not obvious

**DOC-FEATURE — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

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

**DOC-FEATURE — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

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

> ### ⚠️ PARTIALLY CORRECTED — filed as mxcli#855 (2026-08-06), re-verified on v0.16.0
>
> Retested fresh in an isolated scratch sandbox against the current tagged `v0.16.0` release
> (Mendix 11.12.0 Beta `mx`), never touching a real project (Gate 0). Two changes from the
> original finding below:
> 1. The "Additional finding" section's core claim — CE6705 blocks creating *any* DataView with
>    an association-traversal datasource — **did not reproduce**. Both `dataview (DataSource:
>    $Param/Module.Assoc)` and the nested `$currentObject/Module.Assoc` form now create
>    successfully and build with 0 related errors. This half appears fixed (no fix-commit
>    attributed; not verified by reading a diff).
> 2. The `ALTER PAGE SET` limitation still reproduces, but the original claim that "there is no
>    MDL syntax" for the datasource-type change was **wrong** — `ALTER PAGE ... REPLACE`
>    (rebuilding the widget with a renamed nested child to dodge an unrelated "duplicate widget
>    name" quirk) achieves it entirely in MDL, no Studio Pro step required. Severity downgraded
>    from Medium to **Low** accordingly. How the original conclusion was reached: the write-up
>    tested `SET` and Studio Pro's manual picker, but never tried `ALTER PAGE ... REPLACE` as a
>    third option — a case for testing every ALTER PAGE verb before concluding "no MDL syntax
>    exists," not just the one that seems most natural for a property change.
>
> Full details, exact repro commands and outputs: filed issue
> [mxcli#855](https://github.com/mendixlabs/mxcli/issues/855) and local draft
> `bug-logs/pending-github-issues/bug11-dataview-datasource-type.md`. Original entry preserved
> below.

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

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

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

> **Filed 2026-08-06:** re-verified clean on the tagged v0.16.0 release binary (Mendix 11.12.0 Beta)
> in an isolated scratch sandbox — BSON-decoded `DestinationEntity: ""` directly on the
> `EntityRefStep`, reproduced the crash via `mxcli docker check` (mxbuild's own loader) and via a
> live, freshly-launched Studio Pro instance (separate from any open project). Filed as
> [mxcli#854](https://github.com/mendixlabs/mxcli/issues/854). One nuance vs. the note below: this
> retest saw `mxcli docker check` crash outright rather than report "0 errors" — noted in the
> filed issue as consistent with the same root cause (loader throws before the error-counter runs).

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

> **RESOLVED in v0.17.0 — verified 2026-08-11.** Filed upstream as #854; unlike most of the
> v0.17.0 release-sweep closures this one has a real traceable fix: PR `ako/mxcli#119` ("Fix an
> unqualified association datasource that wrote an unloadable page (#854 follow-on)"), merge
> commit `6195c52a4566d73d0262c25ac3ec0e15d7b70a0a`, confirmed an ancestor of the v0.17.0 tag
> (`gh api compare/v0.17.0...6195c52a` → `status: behind, ahead_by: 0`). Empirically retested with
> a minimal two-module cross-module datagrid-datasource repro against a fresh EmptyTest.mpr
> scratch copy: on v0.16.0, exec succeeds silently and `docker check` crashes on load with the
> identical `StorageLoadException`. On v0.17.0, the same script execs cleanly and `docker check`
> ends on the standard 3-error EmptyTest baseline (PASS) — the project loads in Studio Pro too.
> **Preflight rule 7 STOP and the MCP-only workaround for this widget shape can be retired once the
> project's own `mxcli` binary is upgraded to v0.17.0** (not yet done on WMS-Demo-main as of
> 2026-08-11). See `WMS-Demo-main/bug-logs/mxcli-bugs.md` BUG-LOCAL-07 for the project-local mirror
> of this finding.

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

> **RESOLVED in v0.17.0 — verified 2026-08-11.** Filed upstream as #838, closed 2026-08-10 in an
> unverified bulk sweep alongside #839/#844/#846 with no linked fix commit (`closer: null` on the
> GraphQL timeline) — not trusted on GitHub state alone, so this was retested empirically instead.
> Against a fresh EmptyTest.mpr scratch copy: on v0.16.0 the exact Variant A statement
> (`change $Acc (System.User_UserRoles = $Role);`) still corrupts identically — `docker check`
> fails with the same `StorageLoadException`, `"is not a valid AttributeIdentifier"`. On v0.17.0
> the same statement is now **rejected at exec time** with a clear pre-write validation error
> (`"is not a known association ... create the association first or fix the name"`) instead of
> writing bad BSON — no corruption occurs either way. Using the entity's correct association name
> (`System.UserRoles`, not the repro's typo'd `System.User_UserRoles`) on v0.17.0, the disk-write
> path executes cleanly and `docker check` ends on the standard 3-error EmptyTest baseline (PASS).
> **Preflight rule 9 (route inline association-set writes through `mxcli --mcp`) can be relaxed to
> the disk-write path once the project's own `mxcli` binary is upgraded to v0.17.0** (not yet done
> on WMS-Demo-main as of 2026-08-11) — the `--mcp` route remains valid as a fallback but is no
> longer required for this construct. See `WMS-Demo-main/bug-logs/mxcli-bugs.md` BUG-LOCAL-01 for
> the project-local mirror of this finding.

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

**FILED — https://github.com/mendixlabs/mxcli/issues/879 (2026-08-13).** Independently
reconfirmed twice before filing: on SonnyPOC (mxcli v0.17.0, mxbuild/Studio Pro 11.13.0, real
project — installing Workflow Commons 117066 deleted all 401 tracked `mprcontents/*.mxunit`
files and grew the `.mpr` from 74 KB to 35 MB; recovered via `git checkout HEAD --`), and again
on a fresh disposable scratch project created solely for the issue repro (same module, same
result: 369 → 0 `.mxunit` files, 70 KB → 35 MB `.mpr`). See
`bug-logs/pending-github-issues/marketplace-install-collapses-split-model.md` for the full repro
used in the filed issue.

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

### Fix (SUPERSEDED — see the correction below; do NOT drop your DECISION gateways)

Remove DECISION gateways from the MDL script. Wire the decision gateway manually in Studio Pro after the workflow exists. Studio Pro can add a gateway via drag-and-drop with no CE errors.

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1), Phase 3c script 09.

### CORRECTION 2026-08-05: this is a CASING bug, not "DECISION is broken"

Retested on Mendix 11.13 across both binaries, isolating the decision from the `CALL MICROFLOW`
defect (branches use user tasks, no microflow calls — otherwise BUG-WF05 fires first and masks it):

| Expression | v0.16.0 | `504aec67` |
|---|---|---|
| `'$WorkflowContext/Status = TFC.ENUM_TFCStatus.DieGo'` — **capital W** | ✅ 0 errors | ✅ 0 errors |
| `'$workflowContext/...'` — **lowercase w** | — | ❌ **CE0117** |
| `TFC.ENUM_TFCStatus.Release` — value not in the enum | — | ❌ CE1613 (correct, honest error) |

**An enum DECISION works fine, including on v0.16.0.** The CE0117 comes from the lowercase context
variable. The original 2026-07-23 report additionally used `ENUM_TFCStatus.Release`, which is not a
value in that enumeration — so that entry likely conflated two separate mistakes and neither is an
mxcli DECISION defect.

**Still live on `504aec67`:** `1b390dce` normalizes `$workflowContext` casing inside a
`CALL MICROFLOW` WITH clause, but **not** inside a DECISION expression. So decisions must be written
`$WorkflowContext`. This is a genuine, unreported, still-unfixed inconsistency — worth an upstream
issue on its own (mxcli writes the expression verbatim; mxbuild then rejects it).

**Cost of the original misdiagnosis:** TFC dropped DECISION gateways from its workflow design
entirely (see `09b-tfc-workflow-fix-callmf.mdl` header, "ALSO removes the Decision gateway") on the
basis of a lowercase `w`. Gateways are usable — reinstate them if the design wants them.

> **RESOLVED in v0.17.0 — verified 2026-08-11.** Upstream GitHub issue #845, closed 2026-08-10
> alongside the same PR that fixed the sibling `CALL MICROFLOW` WITH-clause casing bug
> (commit `c68177e9`, part of PR #853, confirmed an ancestor of the v0.17.0 tag). Empirically
> retested a DECISION with `'$workflowContext/Status = Mod.ENUM_X.Value'` (lowercase `w`) against
> a fresh 11.13-equivalent scratch project: on v0.16.0 this still produces `CE0117` exactly as the
> "Still live on `504aec67`" note above describes. On v0.17.0 the lowercase `$workflowContext` is
> now normalized inside DECISION expressions too, matching the casing normalization that already
> existed for `CALL MICROFLOW` WITH clauses — `mx check`/`docker check` pass with 0 errors, and
> uppercase `$WorkflowContext` continues to work unchanged. **This closes the "genuine, unreported,
> still-unfixed inconsistency" flagged in the 2026-08-05 correction.** DECISION gateways can be
> written with either casing once the project's own `mxcli` binary is upgraded to v0.17.0 (not yet
> done); recommend TFC and similar projects reconsider reinstating dropped DECISION gateways at
> that point, per the "Cost of the original misdiagnosis" note above.

---

## Bare `Status` attribute name in a `retrieve ... where` clause → CE0161 (reserved-word conflict)

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1), same debugging session as the AND/OR bug above.

`retrieve $X from TFC.TFCStub where ... and Status != Enum.Archived` passes `mxcli check` but fails a real `mx check` with CE0161. Quoting the attribute (`"Status" != Enum.Archived`) fixes it. Notably, this project's own domain model already quotes `"Status"` specifically in `TFCStub`'s access-rule read lists, while every sibling attribute in the same list is unquoted — a pre-existing signal (visible via `DESCRIBE ENTITY`) that this specific attribute name needs quoting, which would have shortened the debugging cycle if checked first. Added to the "Keyword collisions" bullet in `learned-mdl-preflight.md`.

---

## BUG-24: `CALL MICROFLOW` in a workflow without `WITH` clause → broken activity (red pin) + runtime crash

> ### ⚠️ MISDIAGNOSED — see BUG-WF06 (2026-08-05)
>
> **The red pin and the runtime `Class 'Workflows$CallMicroflowTask' could not be found` have
> nothing to do with the `WITH` clause.** They are caused by mxcli v0.16.0 writing the pre-Mendix-11.9
> `$Type` for the activity. The symptoms recorded below are real and accurately described; the
> attribution to a missing `WITH` clause, and therefore this entry's "Fix", are wrong.
>
> **Do not follow this entry's fix.** Adding a fully-qualified `WITH` key makes things worse — that
> is BUG-WF05, a *second*, independent defect. Reproduced 2026-08-05 on TFC-TCXGraphPOC with correct
> short `WITH` keys, with fully-qualified keys, and with no `WITH` at all: red pin in every case.
>
> The "NOT REPRODUCIBLE on RnD or Engalar" note below is consistent with this — both binaries
> post-date `253d60d8`, which version-gates the storage name. It was the binary that fixed it, not
> the `WITH` clause. See **BUG-WF06** for the root cause and the A/B.

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

> **RESOLVED in v0.17.0 — verified 2026-08-11.** Upstream GitHub issue #836. Empirically retested
> a cross-module `grant execute` statement against a fresh EmptyTest.mpr scratch copy: on v0.16.0
> the statement still surfaces the raw `CE0148` only at `mxcli check --references`/`docker check`
> time, exactly as this entry's 2026-08-03 downgrade describes. On v0.17.0, `mxcli check` now
> catches the cross-module GRANT issue **at plain-check time**, via a new dedicated lint rule
> (`MDL-GRANT01`), before any exec is attempted — a further improvement on the 2026-08-03
> "clear pre-emptive exec-time error" finding, not a regression of it. No corruption at any point
> in either version; this has always been a hard-fail class, not a silent one. Recommend treating
> `MDL-GRANT01` findings from `mxcli check` as authoritative once the project's own `mxcli` binary
> is upgraded to v0.17.0 (not yet done).

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

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

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

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

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

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

## BUG-41: Pluggable DataGrid2 `textfilter.attributes:` binding accepted but not persisted → CE1613

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

## BUG-42: Pluggable DataGrid2 cannot combine row-click `Action:` with `DynamicCellClass` + TEXTFILTER/DROPDOWNFILTER

**Status: ENGALAR-ONLY 2026-08-03** — RnD `504aec67` handles this combination cleanly; only
reproduces on Engalar `26f2866`, where the combination reports success but `Action:` and both
filters silently vanish from the widget (only `DynamicCellClass` survives). Report to Engalar
directly, using RnD's datagrid-builder handling as the reference implementation.
**Reproducible:** Reported only
**Discovered:** a PLM parts-flow project, `PROJECT.md:117`

A capability gap rather than corruption — the combination is simply not expressible via MDL.

## BUG-43: `ALTER SETTINGS CONSTANT` corrupts the Settings unit BSON

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

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

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

## BUG-47: CE0639 — validation-feedback `Variable` property not wired

**Status: RESOLVED (as originally described) / NARROWER ENGALAR BUG REMAINS 2026-08-03** —
passes on both forks for the reported attribute-path form. Engalar separately has a known,
narrower issue (object-only `validation feedback` form emits a blank Attribute, CE0091) that
Engalar already tracks internally per their own bug-test file. Safe to remove this entry;
flag the narrower Engalar issue to them if not already open.
**Reproducible:** Reported only, seen independently in both a Java/Angular analysis project and a third, excluded project
**Discovered:** a Java/Angular analysis project, `architecture/build-plan.md:118,136`, `architecture/open-issues.md:13`

## BUG-48: Silent microflow-datasource drop on pluggable datagrids

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

## BUG-49: `CREATE OR REPLACE PAGE` silently resets/drops existing view-access grants

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

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

> **PARTIALLY RESOLVED in v0.17.0 — verified 2026-08-11, bare-name-only.** Upstream GitHub issue
> #834. Empirically retested `ALTER PAGE ... SET` targeting a widget nested inside a datagrid
> `customContent` column against a fresh EmptyTest.mpr scratch copy, at multiple path depths: on
> v0.16.0, both the hard parse error (>2 dotted segments) and the layout-grid-column misroute
> (3-level paths) still reproduce exactly as documented above. On v0.17.0, addressing a
> customContent-nested widget **by its bare name alone** (no dotted path) now resolves correctly
> and the `ALTER PAGE` statement applies to the right widget. **Multi-level dotted paths into
> nested customContent still fail on v0.17.0** — the parse error is clearer and no longer misroutes
> to layout-grid-column logic, but there is still no working addressing scheme for anything past
> one level of nesting. **Do not fully retire this STOP rule.** Once the project's own `mxcli`
> binary is upgraded to v0.17.0 (not yet done), a single bare-name-addressable customContent widget
> can be reached by CLI; anything requiring a nested/dotted path still requires Studio Pro or a
> full page recreation, per `feedback-datagrid-customcontent.md`.

## BUG-51: Quoting a reference-target identifier before a parenthesized param list breaks parsing

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

## BUG-52: CHANGE-activity attribute quoting → `StorageLoadException` on Studio Pro open (passes mxbuild/check clean)

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

## BUG-53: `Visible:` expression on an action button inside a plain DataView corrupts BSON

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

## BUG-54: `--mcp exec` silently renames entities/associations before failing mid-script

**Reproducible:** Reported only
**Discovered:** a WMS reference app, `mdlsource/phase-4/10-rest-mfc-cleanup-rebuild.mdl` header

E.g. `MFC_Simulator.ExRouteItem` renamed to `"Root"` before the script fails on an
unsupported activity type — the rename is committed even though the script as a whole
fails, leaving misnamed objects behind.

## BUG-55: `ALTER PAGE ... DROP ... REPLACE ...` combined in one script → transient duplicate-name collision; and cross-module GRANT EXECUTE/page-view grants silently dropped

**RESOLVED — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

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

> **RESOLVED in v0.17.0 — verified 2026-08-11.** Upstream GitHub issue #835. Empirically retested
> a DataGrid2 `datasource: microflow Module.MF(Param: $value)` against a parameterized source
> microflow, on a fresh EmptyTest.mpr scratch copy: on v0.16.0 the parameter mapping is still
> silently dropped and `mx check`/`docker check` still report `CE1571` for the un-bound parameter,
> exactly as documented above. On v0.17.0 the same script's `DESCRIBE PAGE` read-back shows the
> full parameter mapping persisted, and `docker check` ends on the standard 3-error EmptyTest
> baseline (PASS) with no `CE1571`. Confirmed with both a quoted and unquoted target, matching the
> original finding that quoting is unrelated. Recommend retiring this STOP once the project's own
> `mxcli` binary is upgraded to v0.17.0 (not yet done); note BUG-48 (pluggable DataGrid2 datasource
> drop) is a separate defect and was not part of this verification.

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

---

## BUG-WF05: `CALL MICROFLOW` fully-qualified `WITH` writes a null `ParameterId` → **MPR will not load** on Mendix 11.13

> ### ⚠️ CORRECTION (2026-08-05) — this entry is right, but incomplete, and its workaround is not sufficient
>
> The defect described below is real and correctly root-caused. **What is wrong is the conclusion
> added on 08-05 that "v0.16.0 can author `CALL MICROFLOW` as long as you use a short `WITH` key or
> omit it."** It cannot. Fixing the `WITH` key clears *this* bug and leaves **BUG-WF06** — the
> pre-11.9 `$Type` storage name — fully in place: the model loads and passes `mx check`, but every
> call activity is a red pin in Studio Pro and the app will not boot.
>
> **How the wrong conclusion was reached:** the six-variant trigger-boundary probe that produced it
> graded every arm with `mx check` alone. `mx check` returns `0 errors` on both `$Type` names, so all
> six arms "passed" — and all six were broken. A gate that cannot fail for the defect you have will
> confirm whichever hypothesis you brought.
>
> **Corrected guidance for tagged v0.16.0:** there is no MDL-level workaround for authoring
> `CALL MICROFLOW`. Build from `main` ≥ `253d60d8`, or hand-drag the activity in Studio Pro. The
> short-`WITH`/omit-`WITH` advice remains correct *for this bug specifically*, and is still needed on
> top of a fixed binary if you write the key by hand.

**Severity:** Critical — the model becomes unloadable. `mx check` hard-crashes; Studio Pro cannot
open the project at all. This is an escalation of BUG-WF02's severity, not a new trigger.
**Reproducible:** Yes, first attempt, on the real TFC project.
**Mendix version:** 11.13.0 Beta (project format 11.13.0)
**mxcli version:** v0.16.0 (tagged release, built 2026-07-12)
**Discovered:** 2026-08-04, TFC-TCXGraphPOC, isolated probe `mdlsource/3c-workflow/probe-wf-callmf-11.13.mdl`.

### Why this entry exists

BUG-WF04 (2026-08-03) retested this area and found it green — but **only against RnD HEAD
`504aec67` and Engalar `26f2866`**, both of which post-date the four workflow fixes that landed
2026-07-29 (`253d60d8`, `08746d00`, `1b390dce`, `b6a5043a`). Projects still running the **tagged
v0.16.0 release** have none of those fixes. BUG-WF04's "resolved" verdict does not transfer to them.
This entry records what v0.16.0 actually does on 11.13.

### Trigger

```sql
CREATE WORKFLOW TFC."WF_ProbeCallMF"
  PARAMETER $WorkflowContext: TFC."TFCStub"
BEGIN
  CALL MICROFLOW TFC.WF_ACT_TCCopilot_Prefill
    WITH (TFC.WF_ACT_TCCopilot_Prefill.TFCStub = '$workflowContext');
END WORKFLOW;
```

Target microflow has a **single** entity-typed parameter (`$TFCStub: TFC.TFCStub`) — i.e. squarely
inside BUG-WF04's verified envelope. The fully-qualified `Module.Microflow.Param` WITH-key form is
the one BUG-24 recommended as "CORRECT".

### Symptom

`mxcli check` passes. `mxcli exec` reports `Created workflow: TFC.WF_ProbeCallMF`. Then `mx check`:

```
ERROR: System.AggregateException: One or more errors occurred. (An error occurred when trying to
set the 'Parameter' property of a Microflow call parameter mapping in a Workflow with ID
4bf42a2c-d50d-4e26-abb2-27f0c06190cc.)
 ---> System.InvalidOperationException: ...
 ---> System.ArgumentNullException: Value cannot be null. (Parameter 'value')
   at Mendix.Modeler.Workflows.Model.MicroflowCallParameterMapping.set_ParameterId(MicroflowParameterIdentifier value)
   at Mendix.Modeler.Storage.Operations.StreamingBsonUnitReader.SetValue(...)
   at Mendix.Modeler.Storage.Operations.StreamingBsonUnitReader.FillProperties(...)
   at Mendix.Modeler.Storage.Operations.UnitLoader.ConstructUnits()
```

`set_ParameterId` receives null — the same null `ParameterId` BUG-WF02 described, now confirmed at
the BSON loader level.

### What changed versus BUG-WF02

BUG-WF02 (11.12.1) recorded this as **silent**: "`mxcli check` and `mx check` both pass (0 errors),
but at runtime the parameter binding is invalid." On **11.13 the loader is stricter** — the null is
rejected at model load, so the failure surfaces as an unloadable MPR rather than a runtime fault.
Strictly better (fails loud, not silent) but far more disruptive: SP cannot open the project until
the offending workflow is removed.

### Recovery (proven, non-destructive — used here)

**mxcli can still read the model even though SP's loader cannot.** No full restore needed:

```bash
./mxcli -p <project>.mpr -c "DROP WORKFLOW <Module>.<BadWorkflow>"
```

Then re-run `mx check` to confirm — went straight back to `0 errors` here, with the unrelated
production workflow (10 activities / 3 user tasks, including hand-placed microflow activities)
fully intact. Prefer this over `restore-mpr.sh` / `git checkout`: it is surgical and preserves any
Studio-Pro work done since the last snapshot.

### Guidance for v0.16.0 projects

Until the binary is upgraded past 2026-07-29, **do not script `CALL MICROFLOW` inside a workflow
body on v0.16.0**. Create the workflow with user tasks only and drag the microflow activities onto
the canvas in Studio Pro (SP auto-wires the context parameter on drop) — the workaround
`TFC-TCXGraphPOC/mdlsource/3c-workflow/archived/09j-tfc-workflow-correct.mdl` already documents.
Upgrading to a post-`1b390dce` binary is the real fix — **now verified on 11.13**, see below.

### RESOLVED on RnD `504aec67` — controlled A/B on 11.13 (2026-08-04, same day)

Re-tested as a clean two-arm experiment: two throwaway `rsync` copies of the real TFC project in
`/tmp` (full project dir — `theme/`+`themesource/` are required or `mx check` reports 1337 spurious
CE6083s), the **same** probe script, the **same** gate (`Mendix Studio Pro 11.13.0 Beta.app/
Contents/modeler/mx`). Only the mxcli binary differed. The real `.mpr` was never touched.

| | v0.16.0 (tagged, 2026-07-12) | RnD `504aec67` (2026-07-31) |
|---|---|---|
| `mxcli check --references` | pass | pass |
| `mxcli exec` | `Created workflow` | `Created workflow` |
| `mx check` | **CRASH**, `ArgumentNullException` on `set_ParameterId`, MPR unloadable | **0 errors** |
| roundtrip `DESCRIBE WORKFLOW` | n/a — unloadable | correct (below) |

RnD roundtrip is faithful, and shows both post-fix behaviours:

```sql
call microflow TFC.WF_ACT_TCCopilot_Prefill with (TFCStub = '$WorkflowContext')
  outcomes
    DEFAULT -> { };
```

- WITH-key stored **short** (`TFCStub`), not fully-qualified — `253d60d8`'s 11.9+ version gate.
- context var normalized `'$workflowContext'` → `'$WorkflowContext'`, and `outcomes DEFAULT -> { }`
  synthesized from the target's return type — `1b390dce`.
- read back at all — `b6a5043a` (parse `CallMicroflowActivity` storage name on read).

**Conclusion: BUG-WF05 is a binary-version defect, not a Mendix 11.13 limitation.** The
drag-in-Studio-Pro workaround is only required for projects still on the tagged v0.16.0 release.
Note the input form is unchanged — the *same* fully-qualified `Module.Microflow.Param` WITH-key
that crashes v0.16.0 is accepted and normalized by `504aec67`; no script rewrite is needed, only a
binary swap.

### Confirmed on the REAL production workflow, not just a probe (2026-08-05)

The above used a 1-activity throwaway. Re-run with TFC's actual
`09b-tfc-workflow-fix-callmf.mdl` — `CREATE OR REPLACE`, **5 × `CALL MICROFLOW` with WITH clauses,
3 user tasks, nested `Required`/`WaveOff` branching** — same two-arm sandbox method:

| | v0.16.0 | `504aec67` |
|---|---|---|
| `mx check` (11.13) | **CRASH**, MPR unloadable | **0 errors** |
| roundtrip | n/a | all 5 mappings + nested branches intact; 10 activities / 3 user tasks |

The rebuilt workflow's activity/user-task counts match the hand-dragged production workflow exactly.
So the fix holds at full scale, not just for a single activity.

**Still unverified:** nothing has been opened in Studio Pro or run at runtime. `mx check` passing is
the Mendix *loader* accepting the model — on 11.12.1 BUG-WF02 was a *silent* failure where checks
passed and the runtime binding was still wrong. 11.13's loader is strict about the null so this is
stronger evidence, but "loader accepts" is not "runtime binds correctly."

### v0.16.0 is the LATEST OFFICIAL RELEASE — this bug is live for everyone (2026-08-05)

`gh release list --repo mendixlabs/mxcli`: `v0.16.0` is tagged **Latest**; `Nightly 2026-08-03`
(`689e8ce4`) is a **Pre-release**. So BUG-WF05 affects the current official release on Mendix 11.13,
and **is not filed upstream** — no workflow issue exists in the tracker or in any local
`gh-issues-ready/` folder. Worth reporting, and easy for a maintainer to action since the fix
commits are already in `main` (it is effectively a "please cut a release" report).

Also note `504aec67` **predates 11.13 being in upstream CI at all** — Mendix 11.13 was only added
to the nightly matrix on 2026-08-02 (`6100e4c`, which also fixed real 11.13 drift:
`DatabaseConnector$DatabaseQuery.QueryType` int → string enum, CE5277 per query activity). Any
future swap should target the published nightly (`689e8ce4`), not `504aec67`, and re-run this A/B —
the evidence here does not transfer between binaries.

### Secondary finding: the exec.sh gate does not roll back a BSON crash

`bin/exec.sh`'s mx-check gate parses error JSON to count CEs. A BSON loader crash emits a **stack
trace, not JSON**, so the parse fails and the gate falls through to:

```
(could not parse error JSON: Expecting value: line 1 column 1 (char 0))
✓ Script applied to MPR (with CE errors — see above).
```

It treats "gate could not read the result" as "applied with errors" and **keeps the change**, when a
crash is precisely the case that most needs an automatic rollback. Any exec.sh variant that parses
`--write-errors` JSON has this hole. Fix: treat unparseable gate output as a hard failure and
restore, rather than as a soft warning.


---

## BUG-57: `assess-quality.md` prescribes `HTMLSanitize()`, a Community Commons function that does not exist

**DOC-FEATURE — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

---

## BUG-SP01: one pluggable-widget warning with a non-code `code` field kills Studio Pro's entire Errors pane

**NOT-MXCLI — archived 2026-08-06, see [archive-resolved-2026-08-06.md](archive-resolved-2026-08-06.md).**

---

## BUG-WF06: v0.16.0 writes the pre-11.9 `$Type` for workflow call-microflow activities → red pin in SP, app will not boot

**Severity:** Critical — affects **every** MDL-authored `CALL MICROFLOW` on any Mendix ≥ 11.9,
independent of syntax. Both checkers report success.
**Reproducible:** Yes, every time, on any project format ≥ 11.9.
**Mendix version:** 11.13.0 (reproduced); applies from 11.9 onward
**mxcli version:** `v0.16.0` (tagged release, 2026-07-12). Fixed on `main` by `253d60d8` (2026-07-29).
**Discovered:** 2026-08-05, TFC-TCXGraphPOC, after Studio Pro rendered a scripted 5-activity workflow
as five red pins despite `mx check` reporting `0 errors`.

### Why this entry exists

It supersedes the attribution in **BUG-24** (which blamed a missing `WITH` clause for the red pin)
and completes **BUG-WF05** (which is a real but *separate* defect in the same statement). Both of
those entries now carry correction banners pointing here.

### Symptom

A workflow written from MDL containing `CALL MICROFLOW`:

- **Studio Pro:** each call activity is a **red pin**, cannot be double-clicked or configured. User
  tasks, outcomes, and branching in the same workflow render perfectly, so it reads as a modelling
  error rather than a tool defect.
- **Runtime:** `Failed to load model: ... Class 'Workflows$CallMicroflowTask' could not be found` —
  the entire app fails to boot, not just the workflow.
- **`mxcli check --references`:** passes. **`mxcli exec`:** `Created workflow`. **`mx check`:**
  `0 errors`. **Studio Pro opens the project** without complaint.

### Root cause

Mendix 11.9 (**WOR-2802**) split `MicroflowBasedActivity` into `CallMicroflowActivity` +
`AIAgentTaskActivity`, renaming the on-disk `$Type` from `Workflows$CallMicroflowTask` to
`Workflows$CallMicroflowActivity`. Tagged v0.16.0 predates the version gate and emits the pre-11.9
name unconditionally.

Evidence from the fix commit (`253d60d8`): the 11.6.3 modeler knows only `CallMicroflowTask`; the
11.10 modeler carries both (the old one marked *"Removed due to code refactoring … WOR-2802"*, plus
a conversion routine); the 11.10+ runtime metamodel jars know only `CallMicroflowActivity`.

**Independent of the `WITH` clause** — reproduced with a short key, a fully-qualified key, and no
`WITH` at all.

### Controlled A/B — only the binary varied

Same MDL, same `.mpr` (rsync copy in `/tmp`), same gate
(`Mendix Studio Pro 11.13.0 Beta.app/Contents/modeler/mx`). BSON read straight out of
`mprcontents/*.mxunit`.

| binary | stored `$Type` (×5) | `mx check` | Studio Pro |
|---|---|---|---|
| `v0.16.0` (tagged) | `Workflows$CallMicroflowTask` | 0 errors | **red pins, not clickable** |
| `504aec67` (main, 2026-07-31) | `Workflows$CallMicroflowActivity` | 0 errors | renders, opens normally |

### Why every gate missed it

`mx check` is not sensitive to this `$Type`. The upstream commit message says so directly: *"Both
checkers passed (mxcli check ✓, mx check → 0 errors), but on an 11.9+ project the runtime refused
to load the ENTIRE model at boot."*

Do not use `DESCRIBE WORKFLOW` to verify either — v0.16.0's read path folds both `$Type` names into
one semantic type, so a broken model reads back looking correct.

**The cheapest gate that catches it: open the workflow in Studio Pro and look at the activity icons.**

### Detection

```bash
u=$(LC_ALL=C grep -rla "<WorkflowName>" mprcontents/ | head -1)
LC_ALL=C strings -n 4 "$u" | grep -oE 'Workflows\$Call[A-Za-z]+'
# want: Workflows$CallMicroflowActivity
```

### Fix

Build from `main` ≥ `253d60d8`. There is no MDL-level workaround. If you must stay on tagged
v0.16.0, hand-drag call-microflow activities in Studio Pro.

**RESOLVED in official tag `v0.17.0` (2026-08-10).** Confirmed `253d60d8` is an ancestor of
`v0.17.0` via `git merge-base --is-ancestor`, then reran the sandbox A/B from scratch against the
tagged release (not an RnD/dev commit this time — TFC-TCXGraphPOC's 2026-08-05 "never use the 504"
ruling was specifically about `504aec67` being unofficial; it named "an official release containing
`253d60d8` + `2099bbe1`" as the exit condition). Same probe
(`probes-v016-boundary/A-fq-lower.mdl`), same `.mpr`, same `mx check` gate:

| binary | stored `$Type` | Verdict |
|---|---|---|
| `v0.16.0` (tagged) | `Workflows$CallMicroflowTask` | reproduces the bug |
| `v0.17.0` (tagged, official) | `Workflows$CallMicroflowActivity` | fixed |

A leftover `WF_ProbeA` object with the broken `$Type` in the same sandbox also demonstrated a
**worse failure mode than previously recorded**: on this SP loader build, the malformed
`$Type` doesn't degrade to a red pin — it throws `System.ArgumentNullException` in
`MicroflowCallParameterMapping.set_ParameterId` and makes the **entire model unloadable**
(`mx check` returns a .NET stack trace, not JSON). Same root cause, more severe symptom than the
"red pin, app won't boot" description above — worth knowing if you're triaging a hard mxbuild crash
rather than a red pin.

TFC-TCXGraphPOC-main upgraded its bundled `./mxcli` to `v0.17.0` on 2026-08-11 on the strength of
this result (plus independent confirmation that it also fixes BUG-59 below and the DECISION-casing
gap tracked as issue #845 — `DESCRIBE WORKFLOW` on v0.16.0 echoes an authored lowercase
`$workflowContext` unchanged; v0.17.0 normalizes it to `$WorkflowContext` on write).

### Recovery

mxcli reads models Studio Pro's loader rejects, so no restore is needed:

```bash
./mxcli -p App.mpr -c "DROP WORKFLOW <Module>.<Bad>"
# re-create with a fixed binary
```

Verified on TFC-TCXGraphPOC: dropped and rebuilt with `504aec67`, `mx check` `0 errors`, split model
format preserved, exactly one unit swapped, the unrelated production workflow untouched.

### How it was found (method worth reusing)

The project contained a **hand-dragged workflow that worked**, in the same model, with the same
microflows. Diffing the two BSON units reduced a day of syntax hypotheses to one line:

```bash
LC_ALL=C strings -n 3 <hand-built>.mxunit > /tmp/good.txt
LC_ALL=C strings -n 3 <scripted>.mxunit   > /tmp/bad.txt
diff /tmp/good.txt /tmp/bad.txt
# < Workflows$CallMicroflowActivity
# > Workflows$CallMicroflowTask
```

Everything the two units shared was exonerated at a stroke. When a known-good twin exists, diff it
before theorising.

### Where to report

`mendixlabs/mxcli`. Already fixed on `main`; the report is effectively *"please cut a release"* —
`v0.16.0` is still tagged **Latest** while the 2026-08-03 nightly is a Pre-release, so every user on
the official release hits this. Draft prepared at
`TFC-TCXGraphPOC-main/docs/gh-issues-ready/03-workflow-callmicroflow-storage-name-pre-11.9.md`
(not filed).

> **RESOLVED, the requested release has now shipped, confirmed 2026-08-11.** Filed upstream as
> #846, closed 2026-08-10 in the same unverified bulk sweep as #838/#839/#844 (`closer: null`, no
> linked commit), so GitHub state alone was not trusted; verified independently instead. v0.17.0
> IS the release this report was asking for: repeated the exact controlled A/B from the table
> above with `v0.17.0` substituted for `504aec67`, BSON read straight out of the resulting
> `.mxunit` shows `Workflows$CallMicroflowActivity` (x5), matching `main`, not the broken tagged
> `Workflows$CallMicroflowTask`. `mx check` 0 errors, and, the gate that actually matters here per
> "Why every gate missed it" above, Studio Pro opens the workflow with normal, clickable activity
> icons, no red pins. **This lifts the project-wide CALL MICROFLOW ban recorded for
> TFC-TCXGraphPOC-main** (commit `504aec67` banned hand-dragging requirement project-wide) once
> that project's `mxcli` binary is upgraded to v0.17.0 (not yet done as of 2026-08-11), CALL
> MICROFLOW activities can then be authored from MDL again instead of hand-dragged in Studio Pro.

---

## BUG-58: `ALTER PAGE ... SET Editable = [...] ON widget` writes a blank `AttributeIdentifier` regardless of expression complexity → `StorageLoadException` on Studio Pro open

**Severity:** Critical — project becomes unopenable in Studio Pro
**Reproducible:** Yes, consistently — reproduced with both a compound and the plain
single-condition form of the expression
**Confirmed:** Mendix 11.13.0, 2026-08-07, a PLM parts-flow project
**mxcli version when found:** current (disk write path, `mxcli exec`)

### Symptom

`mxcli exec` on a script of the form:

```mdl
alter page Module."SomePage"
{
  set Editable = ["Attr" = ''] on txtWidget;
}
```

reports success (`Altered page Module.SomePage`, no error) and `mxcli check --references`
passes clean beforehand. The corruption is invisible at both the syntax-check layer and the
`exec` layer — it only surfaces when something actually loads the model's BSON. A subsequent
`mxbuild`/Studio Pro open fails:

```
Mendix.Modeler.Storage.StorageLoadException: One or more invalid values were detected while
loading the project: Mendix.Modeler.Projects.Project:
 - Conditional editability settings in  has an invalid value '' for property Attribute. The
   text 'Forms$ConditionalEditabilitySettings' is not a valid AttributeIdentifier.
```

### Root cause

`ALTER PAGE ... SET Editable = [...] ON widget` is unsafe on this Mendix version **regardless
of the expression's complexity**. Initial hypothesis was that a compound boolean
(`"Attr" = '' or "Attr" = empty`) was the trigger, but a controlled sandbox retest (disposable
copy of the live `.mpr`, never the original) disproved that: re-issuing the exact original
*working* single-condition expression (`SET Editable = ["Attr" = ''] ON txtWidget` — the same
form already in production on this same page) through `ALTER PAGE SET` reproduced the
identical `StorageLoadException`. The `ALTER PAGE SET` mechanism itself blanks the
`ConditionalEditabilitySettings` unit's `Attribute` field when targeting `Editable` on a plain
dataview textbox — expression content is irrelevant.

### Does NOT affect

The same `Editable = ["Attr" = '']` expression written via a full `CREATE OR MODIFY PAGE`
rebuild (not `ALTER PAGE SET`) — that loads and builds cleanly. The bug is in the `ALTER PAGE
SET` write path for this property, not in the expression itself.

### Detection

`mxcli check --references` and `mxcli exec` are both insufficient — this only surfaces via an
actual model load. Sandbox technique that reliably catches it before touching the live model:
`cp` the `.mpr` to a disposable path, `mxcli exec` the candidate script there, then `mxcli
docker check` (or `mxbuild`) the sandbox copy and grep for `StorageLoadException`. Confirm the
technique actually detects the corruption first (reproduce a known-bad case in the same
sandbox) before trusting a clean result on the real candidate.

### Workaround

Do not use `ALTER PAGE SET` to touch conditional `Editable` (and, per BUG-18/BUG-53, `Visible`)
properties at all on this Mendix version — rebuild the whole page via `CREATE OR MODIFY PAGE`
instead, reproducing the page's current `DESCRIBE PAGE` output with only the target property
changed. Matches this project's own `17`→`17d` DataGrid2 precedent in `docs/BUILD-LOG.md`.

### Recovery

`git checkout -- <Project>.mpr` back to the last clean commit — confirmed via `git status
--short` / `git diff --stat HEAD` (binary diff) that the corruption was isolated to the single
exec.

### Related

Same failure signature (blank `AttributeIdentifier` in a `Conditional*Settings` BSON unit →
`StorageLoadException`, invisible to `check`/`exec`, only caught on model load) as [[BUG-21]]
(association assignment in CHANGE/CREATE) and BUG-18/the archived BUG-53 (`Visible:` on a
datagrid customContent container / an action button in a DataView). **BUG-18's text currently
claims regular dataviews are unaffected — that claim needs updating: this finding shows
`Editable` (not just `Visible`) on a plain dataview textbox hits the same defect via `ALTER
PAGE SET`.** Treat any `ALTER PAGE SET` targeting a conditional `Visible`/`Editable` property as
needing a sandboxed model-load check before trusting it, on any widget, not just datagrid
customContent columns.

**Discovered:** 2026-08-07, a PLM parts-flow project, `mdlsource/5-fixes/21-productnumber-newedit-editable-fix.mdl` (initial compound-expression attempt) and the same project's sandboxed retest of the plain single-condition form.

## BUG-59: `GRANT ... (READ (...), WRITE (...))` silently drops an association name it doesn't already know about — cannot add a new association `MemberAccess` entry to an access rule, so `CE0066` on a bidirectional (`Owner: Both`) association has no mxcli fix

**Severity:** Medium — real mxbuild gate-blocker (`CE0066`), no data-loss risk, workaround is a
single Studio Pro click
**Reproducible:** Yes, consistently
**Confirmed:** Mendix 11.13.0, mxcli v0.16.0, 2026-08-07, TFC-TCXGraphPOC-main
**mxcli version when found:** v0.16.0 (`GRANT`/`REVOKE` write path)

### Symptom

A bidirectional association (`Owner: Both` in the BSON — created between two entities in
different modules, e.g. `TFC.DrawingDocs` ←→ `TFC.FeasibilityDecision`) requires a
`MemberAccess` entry for that association in **both** entities' access rules. If one side's
access rules were authored (or GRANT'd) before the association existed, or the association
was added without updating that side's rules, real `mxbuild`/Studio Pro reports:

```
[error] [CE0066] "Entity access is out of date. Please update security by clicking the
'Update security' button in the domain model editor." at Domain model of module '<Mod>'
```

The error is reported against the whole domain model document, not a specific entity —
`elementId` is empty in `.mpr-snapshots/last-mxbuild-errors.json`. `mxcli check` and `mxcli
check --references` do not catch it (same blind spot as BUG-58: both are silent at the
syntax/reference layer, only real `mxbuild`/SP-load surfaces it — confirmed via
`./mxcli docker check`).

### Root cause (confirmed via direct BSON decode)

Verified by decoding the domain model `.mxunit` with Python's `bson` module (`pymongo`
package) and diffing each entity's `AccessRules[].MemberAccesses[]` against every association
where that entity is `ParentPointer`/`ChildPointer` with `Owner: Both`. One side had the
association's `MemberAccess` row (`Attribute: ''`, `Association: '<Mod>.<AssocName>'`), the
other did not, on every one of that entity's 4 role rules.

### What does NOT fix it

- `GRANT Mod.Role ON Mod.Entity (READ *, WRITE *)` (the `*` shorthand) — regenerates the
  existing member list unchanged; does not enumerate the entity's associations from the
  domain model, so a never-granted association is never added.
- `GRANT Mod.Role ON Mod.Entity (READ ("Attr1", "AssocName"), WRITE (...))` — syntax is
  accepted (`mxcli check` passes, `--references` passes), and `mxcli exec` reports success,
  but the unrecognized association name is **silently dropped** from the written rule — the
  echoed `Result:` line omits it, and a BSON re-decode after exec confirms the `MemberAccess`
  row for that association was never created. No error, no warning — a true silent no-op.
  Confirmed the rule set was otherwise correctly rewritten (attribute-level rights all
  landed as specified).
- Re-running `mxbuild`/`docker check` after the above exec: `CE0066` still present, unchanged.

### Workaround

Click "Update security" in Studio Pro's domain model editor (regenerates all entities'
`MemberAccesses` from the current attribute/association list in one pass) — this is the
message's own literal instruction and is, as far as this investigation could determine, the
only way to add a missing association `MemberAccess` row. No `HELP`-documented mxcli command
performs this refresh, and `GRANT`'s member-list parser only round-trips members it already
recognizes; it does not discover new ones from the domain model.

### Detection

Same technique as BUG-58: `mxcli check`/`--references` are both blind. Confirm via `./mxcli
docker check -p <project>.mpr` (or a same-version `mx check`) in a disposable sandbox copy
before trusting any script that touches an entity access rule on an entity with a bidirectional
association. To find the specific gap ahead of time: decode the domain model `.mxunit` and diff
each `Owner: Both` association against both sides' `AccessRules[].MemberAccesses[]` — a missing
row on either side predicts `CE0066` before you even run `mxbuild`.

### Related

Same "silent at check/exec, only real mxbuild/SP-load catches it" shape as [[BUG-58]] and
[[BUG-21]]. Distinct from either — this is a **gap in `GRANT`'s coverage of association
members**, not a corruption of a written value.

**Discovered:** 2026-08-07, TFC-TCXGraphPOC-main, Batch 4 of the 2026-08-06 audit
remediation (`FeasibilityDecision_FileDocument` association, added earlier the same
remediation pass without a matching `FeasibilityDecision`-side access-rule update).

### RESOLVED in official tag `v0.17.0` (2026-08-10)

Changelog claims "a `GRANT` now covers every entity member, including both-owner associations."
Verified with a controlled A/B, not taken on faith: two fresh sandbox copies of
TFC-TCXGraphPOC-main (rsync to `/tmp`, real `.mpr` untouched), identical minimal probe —
two new entities, a fresh `Owner: Both` `ReferenceSet` association between them, then
`GRANT Mod.Role ON Entity (CREATE, DELETE, READ *, WRITE *)` on both sides, varying only the
binary — gated with the matching `Mendix Studio Pro 11.13.0` `mx check`:

| binary | `mx check` result |
|---|---|
| `v0.16.0` (tagged) | `[error] [CE0115]`-class `CE0066` reproduced on the new association |
| `v0.17.0` (tagged, official) | 0 new errors (only an unrelated, pre-existing `CE0115` on the project remained) |

TFC-TCXGraphPOC-main upgraded to `v0.17.0` on 2026-08-11 on the combined strength of this and the
[[BUG-WF06]] result above. The manual "Update security" click workaround should no longer be
needed on `v0.17.0` for this specific gap — not yet retested on a pre-existing, previously-broken
association (only on a newly-created one), so leave the detection technique above in place as a
guard until that's confirmed too.

### New sighting, 2026-08-12, VB-USI-main, mxcli v0.16.0 — reproduces with ZERO associations

Broader trigger than originally documented: `CE0066` on the whole `Common` domain-model document
after script 51 (`create persistent entity Common.Remark`, `create persistent entity
Common.Attachment extends System.FileDocument`, then two `grant Common.User on ... (create,
delete, read *, write *)` statements) — **no association exists anywhere in this script or in
`Common` at all** (`SHOW ASSOCIATIONS IN Common` → 0 rows). So the trigger isn't limited to a
bidirectional-association `MemberAccess` gap as BUG-59 originally characterized it; a brand-new
entity + an entity-level `GRANT` in the same exec session is enough on its own, at least when the
entity `EXTENDS System.FileDocument` (untested whether a plain new entity without `EXTENDS`
would also trigger it).

`mxcli check`/`--references` and `mxcli exec` were both silent/successful, same blind spot as
before — only real mxbuild (`--target=deploy`) surfaced it. Coverage-checklist verification
(`DESCRIBE ENTITY`, `SHOW SECURITY MATRIX`) confirmed the actual model content was correct and
complete; this is a pure build-gate false positive, not model damage.

VB-USI-main is still pinned to `v0.16.0` (not yet upgraded, unlike TFC-TCXGraphPOC-main above) —
left as-is rather than upgrading mid-build, since an unattended DafNe build session is not the
moment to change the pipeline's tool version. Logged and continuing the build per this project's
"tool bugs get logged, not fought" standing execution mode; the outstanding "Update security"
click (or a `v0.17.0` upgrade + re-verify) needs a human in Studio Pro before Stage 5's final
deploy-readiness gate, not before every intermediate script.

## BUG-60: `./mxcli docker check` collapses a v2 split-tree `.mpr` back to v1 single-file and deletes `mprcontents/` — on a plain read-only check, no exec involved

### Symptom

Running `./mxcli docker check -p <project>.mpr` against a project already saved in the v2
split-tree format (small `.mpr` index + `mprcontents/*.mxunit` files) silently rewrites the
`.mpr` back into a single monolithic v1 file (all unit content embedded) and deletes the
entire `mprcontents/` directory from disk — even though `docker check` is a read-only
validation command; no `mxcli exec` or model write was involved.

Reproduced twice in a row on the same session, both times immediately after a clean
`git checkout HEAD -- <project>.mpr mprcontents/` restored a known-good v2 state:

```
$ git status --short *.mpr mprcontents/    # clean, 0 diff
$ ./mxcli docker check -p TFC-TCXGraphPOC.mpr
...
The app contains: 0 errors.
Project check passed.
$ git status --short *.mpr mprcontents/
 M TFC-TCXGraphPOC.mpr                      # 352K -> 107M
 D mprcontents/00/09/....mxunit             # x2627 (every unit)
 D mprcontents/00/22/....mxunit
 ...
```

Since git HEAD still describes the v2 tree, this leaves the working tree in exactly the
"disk and git disagree" split-brain state that `bin/exec.sh`'s own gate refuses to
auto-restore from (its snapshot step copies `mprcontents/` alongside the `.mpr`, but a
snapshot taken **after** this flip has already lost the split-tree structure it was meant
to preserve). Studio Pro is expected to crash on open in this state per the project's own
`bin/exec.sh` warning (`WriteBaseFile null ref`) until manually resaved.

### Root cause (not fully isolated)

`docker check` invokes real `mx check`/mxbuild via a Docker mount; something in that
round-trip (likely mxbuild loading the project and writing back a normalized/default-format
copy before or after validation) always produces v1 single-file output regardless of the
input format. Not yet confirmed whether a non-Docker `mx check` (direct binary) does the
same — this project's `mx` is normally invoked exclusively via `./mxcli docker check`, so
that comparison hasn't been run.

### Impact

**Any verification step is destructive to the on-disk split-tree format**, independent of
whether it also mutates model content. A batch-verification workflow that does:
"exec.sh writes → its own gate runs a check → contradicts an earlier known-good check" can
be explained entirely by this — the *earlier* "known-good" check itself already flipped
the format and wiped `mprcontents/`, so the very next mxbuild invocation (exec.sh's
internal gate) is reading a `.mpr` that git still tracks as v2 but which now embeds
mismatched/incomplete content, producing spurious errors (e.g. `CE0066` reappearing on an
association that was independently confirmed present moments earlier via direct BSON
decode).

### Workaround

Never run `./mxcli docker check` (or presumably any real-mxbuild-backed check) directly
against a tracked v2-format project you intend to keep in that format — only run it in a
disposable `/tmp` scratch copy, or immediately follow it with `git checkout HEAD --
<project>.mpr mprcontents/` to discard the flip if you were only verifying (not applying
a real change). If a real change genuinely needs mxbuild verification before commit,
expect the format flip and either accept v1-as-committed (breaks the project's `mprcontents/`-tracking
convention) or open the flipped `.mpr` in Studio Pro afterward and let it re-save as v2
before committing.

### Detection

Compare `git status --short *.mpr mprcontents/` immediately before and after any
`docker check`/`mx check` invocation — a clean-to-2627-deletions transition is the
signature. `ls mprcontents | wc -l` dropping to 0 and `.mpr` file size jumping from
~350K to 100+MB is the fast visual tell.

### Related

Explains, retroactively, an apparent "CE0066 regression" seen in a `bin/exec.sh` internal
gate run on TFC-TCXGraphPOC-main directly after a Batch-4 script exec that did not touch
the affected entity at all — the regression was an artifact of this bug, not a real
defect introduced by that script. Distinct from [[BUG-59]] (a `GRANT` coverage gap) though
discovered while investigating the same CE0066 incident.

**Discovered:** 2026-08-07, TFC-TCXGraphPOC-main, while diagnosing a spurious CE0066
recurrence during Batch 4 of the 2026-08-06 audit remediation.

## BUG-61: `CALL JAVA ACTION` on a marketplace action with generic/typed parameters (`MicroflowType`, `EntityTypeParameterType`) writes plain string/expression values instead of the special parameter-value shapes — Studio Pro reports `CE0115`/`CE0126`

**Severity:** High — action executes/checks clean via `mxcli`/`--references` but Studio Pro
rejects the call on open/build; requires a manual Studio Pro rewire to recover
**Reproducible:** Yes, consistently, for this specific marketplace Java action
**Confirmed:** Mendix 11.13.0, mxcli v0.16.0, 2026-08-07, TFC-TCXGraphPOC-main
**mxcli version when found:** v0.16.0 (`CALL JAVA ACTION` write path, `addCallJavaActionAction`)

### Symptom

`AgentCommons.ChatContext_Create_ForAgent` (an AgentCommons/marketplace Java action) has two
special parameters: `ActionMicroflow` (a microflow reference, `MicroflowType`) and
`ContextObject` (a generic entity-type parameter, `EntityTypeParameterType`/`T`). A microflow
written via MDL like:

```
$ChatContext = call java action AgentCommons.ChatContext_Create_ForAgent(
  Agent = $Agent, ActionMicroflow = 'TFCIntegrations.ACT_Agent_ChatAction',
  ContextObject = $SomeEntity, OverwritingDeployedModel = $DeployedModel
) on error rollback;
```

passes `mxcli check --references` and `mxcli exec` cleanly, but opening/building the project
in Studio Pro reports:

```
[error] [CE0115] The arguments that are passed to java action 'AgentCommons.ChatContext_Create_ForAgent' don't match ...
[error] [CE0126] Missing value for parameter 'ActionMicroflow'
```

### Root cause (confirmed via direct BSON decode + mxcli source read)

`mxcli`'s own builder (`~/Mendix/mxcli/mdl/executor/cmd_microflows_builder_calls.go`,
`addCallJavaActionAction`) has dedicated logic to detect `MicroflowType` and
`EntityTypeParameterType` java-action parameters and emit the correct value shapes:

- `MicroflowType` → `microflows.MicroflowParameterValue{Microflow: "..."}`
- `EntityTypeParameterType` (generic `T`) → `microflows.EntityTypeCodeActionParameterValue{Entity: "..."}`
- everything else → the default `microflows.BasicCodeActionParameterValue{Argument: "..."}`

Dumped the actual stored BSON for the call activity (`./mxcli bson dump -p <project>.mpr
--type microflow --object "TFCIntegrations.DS_GraphAgent_ChatContext"`) and confirmed **both**
`ActionMicroflow` and `ContextObject` were written using the plain default
`Microflows$BasicCodeActionParameterValue` — e.g. `ActionMicroflow` holds the literal string
`"'TFCIntegrations.ACT_Agent_ChatAction'"` (a quoted string expression), not a
`MicroflowParameterValue` with a `Microflow` field. There is no `GenericType`/`TypeParameter`
binding anywhere in the dump. This means the parameter-type switch in `addCallJavaActionAction`
fell through to the `default:` branch for both parameters — i.e. `p.ParameterType` was not
recognized as `*javaactions.MicroflowType` / `*javaactions.EntityTypeParameterType` for this
specific Java action, most likely because the Java-action-definition lookup
(`ReadJavaActionByName("AgentCommons.ChatContext_Create_ForAgent")`) either failed/returned nil
for this marketplace-imported action, or returned a definition whose parameter types aren't
being classified correctly by the switch.

### What does NOT fix it

- Quoting/not-quoting the `ActionMicroflow` string literal — the value shape written is wrong
  regardless (`BasicCodeActionParameterValue` vs. the required `MicroflowParameterValue`), no
  MDL-level phrasing change routes around it.
- `--references` and `mxcli check` are both blind to this — same "silent at check/exec, only
  real Studio Pro load catches it" shape as [[BUG-58]] and [[BUG-59]].

### Workaround

Hand-rewire the affected `CALL JAVA ACTION` activities in Studio Pro: open each one, clear and
re-set the `ActionMicroflow` parameter using Studio Pro's own microflow picker (not a typed
string) and confirm `ContextObject`'s generic entity binding. No mxcli/MDL route currently
produces the correct BSON shape for this Java action's typed parameters.

### Detection

Any `CALL JAVA ACTION` against a Java action with a `MicroflowType` or generic
(`EntityTypeParameterType`) parameter should be verified via `mxcli bson dump --type microflow
--object <Module.Microflow>` after exec — grep the `ParameterMappings` for the parameter name
and confirm it landed as `Microflows$MicroflowParameterValue` / an
`EntityTypeCodeActionParameterValue` with an `Entity` field, not
`Microflows$BasicCodeActionParameterValue`. If it's the latter, expect `CE0115`/`CE0126` in
Studio Pro regardless of clean `mxcli check`.

### Related

Same "clean `mxcli check`, real Studio Pro/mxbuild catches it" blind spot as [[BUG-58]] and
[[BUG-59]]. Distinct from either — this is a **parameter-type misclassification in the
`CALL JAVA ACTION` builder**, not an association-grant gap or a bad attribute-expression shape.

**Discovered:** 2026-08-07, TFC-TCXGraphPOC-main, while diagnosing recurring CE0115/CE0126 on
`AgentCommons.ChatContext_Create_ForAgent` calls added in Batch 5 of the audit remediation
(`DS_GraphAgent_ChatContext`, `DS_TCCopilot_ChatContext`, `DS_TFCAssistant_ChatContext`).

## BUG-62: `ALTER PAGE ... SET Snippet = ... ON <snippetcall-widget>` passes `--references` but fails at exec time — `SNIPPETCALL` widgets need `REPLACE` with an explicit `Params` map, not `SET`

> ⚠️ **CORRECTION 2026-08-11 — the "workaround" below is WRONG and produces a hard CE0115.**
> Re-tested on **v0.17.0** with Studio Pro 11.13.0's `mx check` as the gate (the 08-07 entry was
> graded by `bson dump` alone — mapping *presence* was mistaken for *correctness*). Actual behaviour:
> `REPLACE` **with** `Params` writes a `Forms$SnippetParameterMapping` that Mendix rejects with
> `CE0115 "arguments … need to be refreshed"`; `REPLACE` **without** `Params` is refused by `exec`
> outright. The shape Studio Pro writes — and that Conversational UI's shipped pages use — is an
> **empty `ParameterMappings` list**, which mxcli cannot emit. **There is no working MDL form**;
> the only fix is Studio Pro → right-click → *Refresh snippet parameters*.
> Severity revised **Low → Medium-High**. Filed upstream as
> [mendixlabs/mxcli#868](https://github.com/mendixlabs/mxcli/issues/868); full test matrix in
> `TFC-TCXGraphPOC-main/docs/gh-issues-ready/04-snippetcall-params-mandatory-but-invalid.md`.
> Lesson repeat: `DESCRIBE PAGE` never renders `Params:` for this widget kind, so it cannot detect
> the bug either way — grade snippet-call writes with `mx check`, not with a reader.

**Severity:** ~~Low~~ **Medium-High** (see correction above) — no in-mxcli workaround exists
**Reproducible:** Yes, consistently
**Confirmed:** Mendix 11.13.0, mxcli v0.16.0 **and v0.17.0**, 2026-08-07 / re-tested 2026-08-11, TFC-TCXGraphPOC-main
**mxcli version when found:** v0.16.0 (`ALTER PAGE ... SET` write path)

### Symptom

```
ALTER PAGE Mod.SomePage {
  SET Snippet = OtherMod.SomeSnippet ON snippetCall1
}
```

passes `mxcli check script.mdl -p <project>.mpr --references` (the referenced snippet exists),
but fails at real execution/Studio-Pro-load time with:

```
property "Snippet" not found (widget has no pluggable Object)
```

`--references` only validates that the named entities/pages/snippets exist — it does not
validate that the requested operation (`SET` on this property) is actually supported for this
widget kind. Same error-message family as [[BUG-07]] (`SET content` on a `DYNAMICTEXT` widget
with `ContentParams`), but for `SNIPPETCALL`'s `Snippet` property specifically.

### Workaround (confirmed correct via BSON decode)

Use `REPLACE` with the full widget body, including an explicit `Params` map for every
parameter the target snippet declares:

```
ALTER PAGE Mod.SomePage {
  REPLACE snippetCall1 WITH {
    SNIPPETCALL snippetCall1 (
      Snippet: OtherMod.SomeSnippet,
      Params: { SnippetParamName: $currentObject }
    )
  }
}
```

Verified on `TFC.TFC_GraphAgentChat` (`mxcli bson dump -p <project>.mpr --type page --object
"TFC.TFC_GraphAgentChat"`): the resulting `Forms$SnippetCall` object has a
`Forms$SnippetParameterMapping` entry correctly binding
`ConversationalUI.Snippet_ChatContext_ConversationalUI.ChatContext` to a `Forms$PageVariable`
with `PageParameter: "currentObject"` — i.e. the enclosing `DATAVIEW`'s `$currentObject`. Note
`DESCRIBE PAGE` does not render the `Params:` map in its MDL output for this widget kind — the
binding is present in the BSON even when `DESCRIBE`'s text output looks like a bare
`SNIPPETCALL snippetCall1 (Snippet: ...)` with no params shown. Confirm via `bson dump`, not
`DESCRIBE`, when in doubt (same "DESCRIBE can omit stored detail" caution as prior sessions'
BUG-59/BUG-WF05 investigations).

### Detection

Any `SNIPPETCALL` widget whose target snippet declares `Params` must be written/altered with
`REPLACE ... WITH { SNIPPETCALL ... (Snippet: ..., Params: { ... }) }`, never `SET Snippet = ...
ON widget`. If a snippet call is added and the target snippet takes parameters, verify via
`bson dump --type page` that a `SnippetParameterMapping` exists for each one before trusting a
clean `mxcli check --references` result.

### Related

Same widget class of "`--references` passes, `SET` isn't a supported operation for this
property" issue as [[BUG-07]]; consider both when authoring a `write-lint-rules` check that
flags `SET <prop> ON <widget>` for known-unsupported widget/property combinations.

**Discovered:** 2026-08-07, TFC-TCXGraphPOC-main, Batch 5 item 3 (D-UI1) of the audit
remediation — `TFC.TFC_GraphAgentChat`'s `snippetCall1` re-target.

---

## BUG-63: `write-lint-rules.md` documents API values that do not exist — every `action_type` example is wrong, and `source_type` case is wrong — so rules written from the guide silently match nothing

### Symptom

`.ai-context/skills/write-lint-rules.md` is mxcli-generated and is the only documentation of
the Starlark rule API. Two of its tables give values the API never returns. Both failure modes
are silent: a rule built on them matches nothing, returns zero violations, and reports a clean
pass. Nothing warns.

**`action_type` (guide line ~311).** The guide's three examples are all fictional:

| Guide says | Actually returned |
|---|---|
| `CreateChangeAction` | `CreateObjectAction` (298), `ChangeObjectAction` (483) |
| `CommitAction` | `CommitObjectsAction` (129) |
| `ShowFormAction` | `ShowPageAction` (120) |
| `CloseFormAction` (from the scaffolded project `CLAUDE.md`) | `ClosePageAction` (69) |
| `ShowHomeFormAction` (same source) | no counterpart exists |

**`source_type` (guide line ~357).** Guide says `"microflow"`, `"page"`. The API returns
uppercase: `PAGE`, `MICROFLOW`, `SNIPPET`, `NANOFLOW`, `ENTITY`, `ASSOCIATION`, `NAVIGATION`.

### Evidence

Counts above are from `.mxcli/catalog.db` on a WMS demo project — 294 entities, 1,177
microflows, 10,012 activities, 6,312 typed reference edges:

```
$ sqlite3 .mxcli/catalog.db "SELECT DISTINCT SourceType FROM refs ORDER BY 1;"
ASSOCIATION / ENTITY / MICROFLOW / NANOFLOW / NAVIGATION / PAGE / SNIPPET

$ sqlite3 .mxcli/catalog.db \
    "SELECT ActionType, COUNT(*) FROM activities GROUP BY 1 ORDER BY 2 DESC;"
MicroflowCallAction|1031   RetrieveAction|775    ChangeObjectAction|483
CreateObjectAction|298     LogMessageAction|292  CommitObjectsAction|129
ShowPageAction|120         ShowMessageAction|105 ClosePageAction|69
...
```

Zero rows for `CreateChangeAction`, `CommitAction`, `ShowFormAction`, `CloseFormAction`,
`ShowHomeFormAction`.

### Impact — this is not theoretical, it silently broke a shipped rule

The `CONV010` rule scaffolded into projects ("ACT_ microflows should only contain UI
actions") took its allowlist verbatim from that table. Because the real `ShowPageAction` and
`ClosePageAction` were absent from the allowlist, the single most common thing an `ACT_`
microflow does — showing or closing a page — was flagged as undelegated business logic.

Measured on the same project: **138 of 282 `ACT_` microflows flagged, 49% false positives.**
The rule was not merely inert; it was inverted. Lint on that project was subsequently
demoted to "optional, non-blocking" and then stopped being run at all — a wrong rule
discredited the whole gate.

### Suggested fix

1. Correct both tables in the generator for `write-lint-rules.md`, and the `action_type`
   list in the scaffolded project `CLAUDE.md`, against the values the API actually emits.
2. Ship `CONV010` with the corrected allowlist — it is inverted in every project scaffolded
   to date.
3. Consider generating the tables from the same enum the adapter emits, so they cannot drift
   again.

### Workaround

Probe the catalog before using any API string; never take one from the guide:

```bash
sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActionType FROM activities;"
sqlite3 .mxcli/catalog.db "SELECT DISTINCT SourceType FROM refs;"
```

Corrected `CONV010` and a `CONV020` written against probed values are in this repo under
[`lint-rules/`](../lint-rules/), with the trap and the fail-loudly self-check pattern
documented in [`lint-rules/README.md`](../lint-rules/README.md).

### Related

Same "documentation is not ground truth" class as the `assess-quality.md` finding in
[[BUG-57]] — a prescribed function that does not exist. Both are doc-generation defects
whose failure mode is a confident clean result.

**Discovered:** 2026-08-11, a WMS demo project, while writing a `CONV020` user-feedback rule;
the probe that disproved the guide also revealed `CONV010`'s inversion.
**Reproducible:** yes — deterministic, verifiable in two `sqlite3` one-liners against any
project with a FULL catalog.

## BUG-64: `ALTER SETTINGS CONFIGURATION 'Name' HttpPortNumber = ..., ServerPortNumber = ...` reports success but silently no-ops — value stays unchanged on disk

**Severity:** Medium — blocks Studio Pro's local "Run" (crashes with `HTTP Port number 0 is
not between 1 and 65535`) whenever the model's port fields are `0`; does not affect `mxcli
docker run`, which manages ports itself
**Reproducible:** Yes, consistently
**Confirmed:** Mendix 11.13.0, 2026-08-12, VB-USI-main
**mxcli version when found:** v0.16.0

### Symptom

```
./mxcli -p Project.mpr -c "alter settings configuration 'Default' HttpPortNumber = 8080, ServerPortNumber = 8081;"
```

prints `Updated configuration 'Default'` (no error, exit 0), and the `.mpr` file's mtime
changes. But an immediate re-read shows the old value unchanged:

```
./mxcli -p Project.mpr -c "SHOW SETTINGS"
| Configuration 'Default' | PostgreSql, localhost:5432, db=mendix, http=0 |
```

Ruled out file-lock contention: reproduced identically both while Studio Pro held the file
open (`Project.mpr.lock` present, PID confirmed via `ps aux`) and again after fully quitting
Studio Pro and confirming the lock file was gone — same silent no-op both times. Also ruled
out catalog staleness (`REFRESH CATALOG` before the read made no difference).

### Root cause

Unknown — not narrowed further. `DESCRIBE SETTINGS` proves the property name
(`HttpPortNumber`/`ServerPortNumber`) is real and readable; the write path for these two
specific keys on `ALTER SETTINGS CONFIGURATION` appears to be a no-op despite the success
message. Other keys on the same statement type (`DatabaseType`, `DatabaseUrl`, etc.) were not
retested here to confirm they aren't affected too — treat any `ALTER SETTINGS CONFIGURATION`
write as unverified until read back.

### Detection

Always read back with `SHOW SETTINGS` (or `DESCRIBE SETTINGS`) immediately after any `ALTER
SETTINGS CONFIGURATION` — do not trust the "Updated configuration" success message alone.

### Workaround

Set the port fields directly in Studio Pro's UI (App menu → Settings → Configurations →
select configuration → Port fields) instead of via mxcli. This is a plain GUI field edit and
was not attempted as part of this finding but is the standard fallback for any confirmed
mxcli write no-op.

### Related

Another instance of "exec reports success, disk state doesn't match" alongside BUG-59 (GRANT
silently drops an association) and BUG-62 (SNIPPETCALL SET passes but fails at exec) — a
recurring class where `ALTER`'s success message is not sufficient evidence a write actually
landed.

**Discovered:** 2026-08-12, VB-USI-main, while trying to fix a Studio Pro local-run crash
caused by `HttpPortNumber = 0` left over from Docker-oriented project setup.

## BUG-65: `gate-check.sh` has no concept of a second, parallel decision register — hardcoded to `PROJECT.md` (or `analysis/*/PROJECT.md`), so a project running two tracks (e.g. `PROJECT.md` + `PROJECT-DAFNE.md`) can't gate-check the second track at all

### Symptom

VB-USI-main is running two parallel conversion tracks against the same project directory:
the original CCS track (`PROJECT.md`) and a second, explicitly-separate track for a newly
shared source corpus (`PROJECT-DAFNE.md`, per the user's own instruction to keep them
separate — see that file's own header). Stage 1 (7 BRDs, F006-F012) for the DafNe track
completed and needed a Stage 2 validation gate.

`bin/gate-check.sh <project-dir> <stage>` has no flag or convention for pointing it at a
non-default decision register. Its discovery logic (`bin/gate-check.sh` lines ~209, ~474,
~553, ~568, ~599) globs `"$PROJECT_DIR/PROJECT.md" "$PROJECT_DIR"/analysis/*/PROJECT.md` —
`PROJECT-DAFNE.md` is invisible to it. Running it as-is would silently validate against the
*other* track's decisions and artifacts (wrong CONFIRMED rows, wrong artifact paths), not
fail loudly with "can't find a register for this track."

### Evidence

```
$ grep -n "Usage:" bin/gate-check.sh
# Usage: bin/gate-check.sh [--html|--no-html] [--ack-protocol|--force-stale] <project-dir> [stage]
$ grep -n 'PROJECT_DIR/PROJECT.md\|analysis/\*/PROJECT.md' bin/gate-check.sh
for candidate in "$PROJECT_DIR/PROJECT.md" "$PROJECT_DIR"/analysis/*/PROJECT.md; do
```

No `--register <path>` or similar override exists.

### Impact

Any project running more than one tracked initiative in parallel (a real, sanctioned pattern
per the toolkit's own "second index/tracker" precedent — see `PROJECT-DAFNE.md`'s own
history) cannot use `gate-check.sh` for the second track's stages without either (a) risking
a false pass/fail against the wrong register, or (b) hand-copying decisions into the primary
`PROJECT.md` just to satisfy the tool, defeating the point of keeping them separate.

### Suggested fix

Add a `--register <path>` override (or auto-glob for `PROJECT-*.md` and prompt/fail when more
than one is found with no override given) so multi-track projects can gate-check each track
independently.

### Workaround

Self-attest the stage manually: do the equivalent checks by hand (JSON/artifact validity,
cross-BRD consistency, a CONFIRMED decision row for the stage) and log the self-attestation
directly in the track's own register (e.g. `PROJECT-DAFNE.md`'s Decisions table), same as the
existing precedent for other unattested-mode stages. Do not run `gate-check.sh` against a
project directory that has more than one `PROJECT*.md` register until the fix above lands —
it will silently read the wrong one.

### Related

Same "tool assumes a single project shape and fails silently rather than loudly" class as
[[BUG-60]] (docker check collapsing v2 split-tree back to v1 on a plain read) — both cases
where a structural assumption baked into the tool doesn't hold for a valid project layout,
and the tool has no detection for the mismatch.

**Discovered:** 2026-08-12, VB-USI-main, DafNe track, Stage 1→2 gate for BRDs F006-F012.
**Reproducible:** yes — any project directory with both `PROJECT.md` and a second
`PROJECT-<name>.md` register reproduces the wrong-register read deterministically.

## BUG-66: `ALTER ENTITY ... ADD ATTRIBUTE "X": autocreateddate;` silently no-ops — no error, no confirmation line, no attribute added

**Sighted:** VB-USI-main, DafNe track Stage 5 Phase 11, script 55b (2026-08-12).

**Symptom:** `alter entity "Common"."Attachment" add attribute "CreatedDate": autocreateddate;` passes
`mxcli check` (syntax + `--references`) cleanly, and `mxcli exec` prints only the connection banner —
no `Added attribute ...` confirmation line, no error, no warning. `DESCRIBE ENTITY` afterward shows the
attribute was never added. Confirmed not a fluke: re-ran in isolation, same silent no-op. Confirmed the
`ALTER ENTITY ADD` code path itself works — an ordinary `string(10)` attribute added via the identical
statement shape in the same session succeeded and showed its confirmation line.

**Root cause (inferred, not confirmed against source):** `CREATE ENTITY ... "X": autocreateddate` works
fine (used successfully in script 51 for `Common.Remark.CreatedDate`). The `ALTER ENTITY ADD ATTRIBUTE`
code path appears not to implement the `autocreateddate` pseudo-type at all, and fails open (silently
does nothing) rather than erroring, instead of falling back to an unsupported-type error.

**Impact:** Medium — silent data loss of intent. A script author who doesn't manually re-`DESCRIBE
ENTITY` after every `ALTER ENTITY ADD` involving `autocreateddate` will believe the attribute exists
when it does not, with zero error signal anywhere in the exec output.

**Workaround:** Only add `autocreateddate` attributes via `CREATE ENTITY` at entity-creation time. If an
existing entity needs one added later, there is no working `ALTER ENTITY` path — either recreate the
entity via `CREATE OR REPLACE ENTITY` (data-loss risk if rows exist) or use a plain `datetime` attribute
with manual stamping in a microflow instead (e.g. `CreatedDate: datetime` + `change $Entity (CreatedDate
= [%CurrentDateTime%])` on the create path) rather than relying on the auto-managed pseudo-type.

**Decision applied in VB-USI-main:** skipped `Common.Attachment.CreatedDate` entirely rather than
work around it — it was a "nice to have, matches Remark's shape" cosmetic audit field, not required by
the actual fix in flight (F012 open question S3's author-or-admin lock only needed `CreatedBy`, which
added successfully as a plain `string` attribute). `CreatedBy` alone is sufficient for the delete-lock
logic in `ACT_Attachment_Delete`.

## BUG-67: `CREATE SNIPPET ... (Params: { $X: String })` — a primitive-typed snippet parameter, documented in `mxcli syntax snippet.create`'s own example, fails at exec time with "entity not found"

**Sighted:** VB-USI-main, DafNe track Stage 5 Phase 11, script 56 (2026-08-12).

**Symptom:** `mxcli syntax snippet.create` documents this as valid:
```
CREATE SNIPPET Module.Name
  ( Params: { $P: Module.Entity, $Label: String } )
  { ... }
```
i.e. a mix of entity-typed and primitive-typed (`String`) params. A snippet declared with a
primitive-typed param — either case, `string` or `String` — passes `mxcli check` (syntax +
`--references`) cleanly, then fails at `mxcli exec` with:
```
Error: failed to build snippet: failed to resolve entity string: entity not found: string
```
i.e. the exec-time snippet-builder unconditionally tries to resolve every param's type name as an
entity reference, regardless of whether it's a primitive keyword. Confirmed via a minimal isolated
repro (single snippet, one `dynamictext`, one `$RefID: string`/`String` param, both cases fail
identically).

**Scope of the bug:** PAGE params with a primitive type (`$RefID: string`) work fine — two pages in
the same script (`Common.Remark_NewEdit`, `Common.Attachment_NewEdit`) executed successfully with
exactly that param shape. The defect is specific to the `CREATE SNIPPET` code path, not param-typing
in general.

**Impact:** Medium — blocks a documented, seemingly-ordinary feature (passing a plain string into a
reusable snippet) with no workaround at the syntax level; the tool's own syntax reference is actively
misleading here since it shows an example that cannot execute.

**Workaround used in VB-USI-main:** introduced a small non-persistent "parameter holder" entity
(`Common.RefIDHolder`, single `RefID: String` attribute) purely to carry a string value into a
snippet as an entity-typed param, which does work. The embedding page must create/populate a
`RefIDHolder` object before calling the snippet and pass that object in as the snippet param instead
of the raw string. Adds one throwaway non-persistent entity and one extra object-creation step per
call site — acceptable overhead, no data-loss/security implications since it's never persisted.

**Root cause, fully diagnosed:** `CREATE SNIPPET ... Params: { $X: Type }` does not strip quotes from
the type name before resolving it, unlike `CREATE PAGE` param resolution which does. Quoting a
qualified entity type per this project's own "always quote identifiers" convention —
`{ $Context: "Common"."RefIDHolder" }` — fails with `entity not found: "Common"."RefIDHolder"`
(quote characters included literally in the failed lookup string). The exact same param, unquoted —
`{ $Context: Common.RefIDHolder }` — succeeds immediately. This is true for entity types AND for the
primitive-type case described above (`string`/`String` are never valid regardless of quoting, since
there's no entity by that name either way — so the primitive case looks identical from the outside
but has a second, independent cause layered under it: no primitive-type special-casing at all).

**Corrected workaround:** in a `CREATE SNIPPET`'s `Params: { ... }` clause specifically, leave the
type name UNQUOTED (`Common.RefIDHolder`, not `"Common"."RefIDHolder"`) even though every other
identifier position in this project's scripts is quoted per convention. This is the one exception.
Primitive types in snippet params still cannot be used at all (no workaround beyond the
parameter-holder-entity pattern above).

**No fix exists at the MDL/CLI level** for the primitive-type gap — needs an mxcli code fix (special-
case primitive keywords) or a docs fix (remove the misleading `$Label: String` example) upstream. The
quote-stripping gap is a separate, narrower mxcli parser fix (snippet param-type resolution should
strip quotes the same way page param resolution already does).

## BUG-68: Snippet datagrid columns/sort bars cannot reference system (`autocreateddate`) or generalized (inherited) attributes — resolves fine in a PAGE datagrid, fails under native mxbuild in a SNIPPET datagrid

**Sighted:** VB-USI-main, DafNe track Stage 5 Phase 11, script 56 (2026-08-12).

**Symptom:** A snippet's datagrid column or sort bar bound to either (a) a `autocreateddate` system
attribute (e.g. `Common.Remark.CreatedDate`, added via `CREATE ENTITY ... "CreatedDate":
autocreateddate` — stored as `MaybeGeneralization.HasCreatedDateAttr`, not a normal `Attributes[]`
entry), or (b) an attribute inherited from a generalization (e.g. `Common.Attachment.Name`, inherited
from `System.FileDocument`) — passes `mxcli check`, `mxcli exec`, and even round-trips cleanly through
`DESCRIBE SNIPPET`. Native mxbuild (`mx check`) then rejects it:
```
[CE1613] "The selected attribute 'Common.Remark.CreatedDate' no longer exists." at Sort bar of data grid 'dgRemarks'
[CE1613] "The selected attribute 'Common.Remark.CreatedDate' no longer exists." at Columns (3/4) of data grid 'dgRemarks'
[CE1613] "The selected attribute 'Common.Attachment.Name' no longer exists." at Columns (1/3) of data grid 'dgAttachments'
```

**Isolated confirmation:** built a throwaway PAGE (not snippet) with an identical datagrid — same
entity, same `sort by "CreatedDate" desc`, same attribute-bound column — and it passed native mxbuild
with zero CE1613 errors. The attribute references themselves are fine; the defect is specific to how
a SNIPPET document stores/resolves attribute references for system/generalized attributes, not a
general attribute-resolution problem.

**Not CREATE-SNIPPET-specific:** confirmed the same failure occurs via `ALTER SNIPPET ... INSERT`
adding the same column to an already-created snippet — so this isn't a quirk of the `CREATE SNIPPET`
builder alone (unlike BUG-67); it's a property of snippet documents generally versus page documents.

**Impact:** Medium-high — any reusable snippet that wants to show/sort by a Mendix-managed creation
timestamp or any attribute inherited from a system generalization (very common: `FileDocument.Name`,
`FileDocument.Size`, any `autocreateddate`/`autochangeddate` audit column) will build "successfully"
per mxcli's own tooling and then fail real Studio Pro validation, with no warning at MDL-authoring
time.

**Workaround used in VB-USI-main:** don't reference the system/generalized attribute in the snippet
at all. Add a plain, ordinary (non-system, non-inherited) duplicate attribute on the entity instead,
and stamp it manually from the existing create-path microflow:
- `Common.Remark.LoggedDate: DateTime` (plain), stamped to `[%CurrentDateTime%]` alongside `CreatedBy`
  in `ACT_Remark_Save`'s create branch. The real `CreatedDate` (autocreateddate) is left in place,
  simply unused by any snippet UI.
- `Common.Attachment.DisplayName: String(280)` (plain), copied from `$Attachment/Name` (set by the
  upload widget before the microflow runs) in `ACT_Attachment_Upload`.

Both snippets were then dropped and recreated pointing at the duplicate attributes. Verified clean
under native mxbuild after the swap (pending final gate confirmation).

**No fix exists at the MDL/CLI level.** This needs an mxcli code fix to either (a) resolve
system/generalized attribute references correctly inside snippet documents the same way it does for
pages, or (b) at minimum have `mxcli check`/`exec` warn when a snippet datagrid column/sort binds to
a system or inherited attribute, since the tool currently reports success right up until real
Studio Pro validation.

## BUG-69: `ALTER ENTITY ... DROP ATTRIBUTE "RefID";` silently no-ops — prints a success line but the attribute is never actually removed, specific to the attribute name "RefID"

**Sighted:** VB-USI-main, DafNe track Stage 5 Phase 11, script 56d (2026-08-12).

**Symptom:** `alter entity "Common"."RefIDHolder" drop attribute "RefID";` prints `Dropped attribute
'RefID' from entity Common.RefIDHolder` (a normal success line, not an error), but a `DESCRIBE ENTITY`
run immediately afterward shows the attribute — including its `not null` validation constraint —
completely unchanged. Discovered while trying to fix a genuine CE0070 ("validation rule not allowed on
non-persistent entity") on `Common.RefIDHolder.RefID` by dropping and re-adding the attribute without
the constraint; the re-add step then failed with `Error: attribute 'RefID' already exists on entity
Common.RefIDHolder`, revealing the drop had never actually happened.

**Investigation — three independent reproductions, ruling out live-reference explanations:**
1. On `Common.RefIDHolder` itself, with `SNIPPET_Remarks`/`SNIPPET_Attachments` (the only two documents
   referencing `RefIDHolder.RefID`) still live — initial hypothesis was a live-reference block.
2. Re-tried after dropping both referencing snippets first and confirming via
   `REFRESH CATALOG FULL` + `SHOW REFERENCES TO Common.RefIDHolder` that reference count was zero —
   **same silent no-op recurred**, ruling out the live-reference hypothesis entirely.
3. Minimal isolated repro: created a throwaway scratch entity `Common.ZZTest_RefIDProbe` with a single
   `"RefID": string(50) not null` attribute and nothing else in the project referencing it. Dropping
   just that attribute **also silently no-op'd** (success message printed, `DESCRIBE ENTITY` showed the
   attribute unchanged) — confirming this has nothing to do with references at all.

**Control (proves the DROP ATTRIBUTE code path works in general):** dropping an attribute named
`"ZZProbe"` (a project-unique name) on the same `RefIDHolder` entity, earlier in the same session,
worked correctly and was reflected in `DESCRIBE ENTITY` immediately afterward.

**Root cause (inferred, not confirmed against source):** the attribute name `RefID` is reused as an
attribute name on many other entities throughout this project (`Common.Remark.RefID`,
`Common.Attachment.RefID`, etc.). The drop code's safety/reference-checking logic appears to match by
bare attribute name project-wide rather than by fully-qualified entity+attribute, and silently aborts
the drop without surfacing an error when *any* other entity in the project happens to have an
attribute with the same name — regardless of whether that other entity's attribute is actually
related or referenced.

**Impact:** Medium — silent no-op with a misleading success message, on a plausible everyday shape
(a discriminator/foreign-key-style attribute name reused across many entities, which is normal domain
modeling). Combined with BUG-66's similar "silent no-op with a success-looking message" failure mode
on `ALTER ENTITY ADD`, this suggests `ALTER ENTITY` add/drop code paths generally under-report failure.

**Workaround used in VB-USI-main:** whole-entity `DROP ENTITY` + `CREATE ... ENTITY` recreate instead
of an attribute-level drop, once all referencing documents are confirmed dropped/absent
(`SHOW REFERENCES TO` returning zero). Reliable pattern already established earlier in this same build
effort for other drop+recreate scenarios (see script 56's own RE-RUN CLEANUP notes).

**No fix exists at the attribute-drop level.** This needs an mxcli code fix to key its drop-safety
check off fully-qualified `Entity.Attribute`, not bare attribute name, and to surface a real error
(not a false-success message) when a drop is refused for any reason.

## BUG-70: A widget-level `action: show_page Page(Param: value, ...)` action property unconditionally drops ALL params — not just in the `create_object ... then show_page(...)` chained form previously logged; this is a general defect in the plain, non-chained widget-action form too

**Sighted:** VB-USI-main, DafNe track Stage 5 Phase 11, script 56d gate-check follow-up (2026-08-12).
**Supersedes/broadens** the narrower framing recorded in script 56d's header comment, which believed
only the `create_object Entity then show_page Page(Param: val)` chained form was affected. It is not:
the defect is in the `show_page(...)` action-with-params mechanism itself, chained or not.

**Symptom:** `Common.SNIPPET_Remarks`'s `btnEditRemark` was fixed in script 56d to use a plain
(non-chained) `action: show_page "Common"."Remark_NewEdit"(Remark: $currentObject, RefID:
$Holder/RefID)`. `mxcli check`/`exec` reported zero errors. A post-fix gate-check (native mxbuild)
still raised `CE1571 "No argument has been selected for parameter 'RefID'"` on this exact button.
`DESCRIBE SNIPPET` confirmed why: the compiled action is `Action: show_page Common.Remark_NewEdit`
with **no arguments at all** — both params were silently dropped, despite being present, correctly
spelled, and referencing valid in-scope values in the source script.

**Isolated reproductions, systematically ruling out every plausible narrowing factor — all still
dropped every param:**
1. Same construct as a plain page datagrid column button (not a snippet) — ruling out
   snippet-vs-page (unlike BUG-68, this is not snippet-specific).
2. Same construct with literal values (`RefID: 'literal'`) instead of `$currentObject`/attribute-path
   expressions — ruling out expression-complexity as the trigger.
3. Same construct in a datagrid's `controlbar` (not nested in a column) with no `$currentObject`
   reference at all (`Remark: empty, RefID: $Holder/RefID`) — ruling out datagrid-column nesting and
   `$currentObject`-in-controlbar scoping as the trigger.
4. A completely standalone page-level `actionbutton`, outside any datagrid whatsoever — ruling out
   datagrid nesting entirely.
5. The alternate documented syntax form (`show_page Page($Param = value, ...)` instead of
   `show_page Page(Param: value, ...)`) — both forms drop identically.
6. A brand-new, never-before-used target page and two brand-new params (`$Remark: Entity`,
   `$Note: string`), fully isolated from `Remark_NewEdit`/`RefIDHolder` — ruling out anything
   page-specific to `Remark_NewEdit` itself.
7. A single-param case (`show_page Page(Note: 'hi')`) — ruling out "only multi-param calls break";
   even one param is dropped.

Every one of the 7 variants compiled with zero mxcli errors and, in every case, `DESCRIBE
PAGE`/`DESCRIBE SNIPPET` afterward showed the action with zero arguments.

**Contrast — proof the underlying page/params are fine and only this specific action form is
broken:** a *microflow-level* `show page Page(Param1: v1, Param2: v2)` statement (used in
`Common.ACT_Remark_New`/`ACT_Attachment_New`, added earlier in this same script 56d) compiles and
wires both params correctly — confirmed via `DESCRIBE MICROFLOW`. The bug is specific to the
widget-property `action: show_page(...)` syntax on a button/tile, not to `show_page`/param-passing
in general.

**Impact:** High — this invalidates any button in this project (or built going forward) that uses
`action: show_page Page(Param: value)` with one or more params; the action silently opens the page
with all params unbound, which for a required-param page like `Remark_NewEdit` produces a hard
CE1571 under native mxbuild, and for a page with optional/defaultable params would silently show the
wrong (empty/default) data with no error at all — worse than a compile failure.

**Workaround — the only reliable option:** never use `action: show_page Page(Param: value, ...)`
directly on a widget when the target page takes params. Instead, always route through a microflow
that does a microflow-level `show page Page(Param1: v1, Param2: v2)` statement, and point the
widget's `action:` at that microflow instead (`action: microflow Module.SomeAction(...)`). A
`show_page` widget action with **zero** params is unaffected (confirmed fine, e.g. the plain
navigation tiles in `mdlsource/9-nav-and-seed/41-navigation-and-home-regroup.mdl`, which pass no
params and compile/wire correctly).

**Decision applied in VB-USI-main:** `Common.SNIPPET_Remarks`'s `btnEditRemark` needs its own
microflow (`Common.ACT_Remark_Edit($Remark)`, mirroring the existing `ACT_Remark_New` pattern) that
does the `show page` internally — this was not caught in script 56d because the header comment's
working theory (downstream artifact of the `$Context` rename) was wrong; only a live gate-check
against native mxbuild surfaced it, since `mxcli check`/`exec` never flag this defect. Follow-up
fix script: 56e.

**No fix exists at the MDL/CLI level.** This needs an mxcli code fix so the widget-level `show_page`
action property actually serializes its param bindings into the compiled action, matching what the
microflow-level `show page` statement already does correctly.

---

## BUG-71: `ALTER SNIPPET|PAGE ... replace "<Column>" with { column ... }` on a datagrid column silently deletes the column instead of replacing it — and once emptied, the datagrid has no anchor left for `INSERT AFTER` to recover it

**Sighted:** VB-USI-main, DafNe track Stage 5 Phase 11, script 56e follow-up verification (2026-08-12).

**Symptom:** Script 56e ran `alter snippet "Common"."SNIPPET_Remarks" { replace "Actions" with { column
colRemarkActions (caption: 'Actions') { actionbutton btnEditRemark (...), actionbutton btnDeleteRemark
(...) } } };` to repoint `btnEditRemark` at a new microflow (the BUG-70 workaround). `mxcli exec`
reported success (`Altered snippet Common.SNIPPET_Remarks`), with zero errors. A `DESCRIBE SNIPPET`
run immediately afterward showed the datagrid's `"Text"`, `CreatedBy`, and `LoggedDate` columns intact
but the entire `"Actions"` column — old or new — **completely absent**. Not reverted to the old
content, not replaced with the new content: gone.

**Isolated reproduction (scratch snippet, `Common.ZZTest_ReplaceProbe`, cleaned up after):**
1. Created a snippet with a datagrid holding two columns: an attribute-bound `"Text"` column and a
   non-attribute-bound column declared as `colActionsNamed (caption: 'Actions')` containing one
   actionbutton. `DESCRIBE SNIPPET` confirmed mxcli normalizes a non-attribute-bound column's stored
   name to its **sanitized caption** regardless of the declared name — the column shows up as `"Actions"`,
   not `colActionsNamed` (this matches the previously-documented ALTER-addressing rule, and was
   correctly applied in the real script's `replace "Actions" with {...}` targeting).
2. Ran `alter snippet ... { replace "Actions" with { column colNewActions (caption: 'Actions') {
   actionbutton btnNew (...) } } };` — reported success. `DESCRIBE SNIPPET` afterward showed the
   datagrid with **only the `"Text"` column left** — the `"Actions"` column, old or new, was gone
   entirely.
3. Repeated against the **other** column (`replace "Text" with { column colTextNew (attribute: "Text",
   caption: 'Remark Text v2') } }`) to rule out anything specific to non-attribute-bound/custom-content
   columns — same result: `DESCRIBE SNIPPET` afterward showed **zero columns at all** on the datagrid
   (the datagrid itself remained, just entirely empty of columns).
4. Control, to isolate this to datagrid columns specifically: ran the identical `replace <name> with {
   <same-widget-type> <name2> (...) }` pattern on a plain, non-datagrid widget (a `dynamictext` sibling
   inside a layoutgrid column, not nested in any datagrid) — this **worked correctly**, producing the
   expected replaced widget with its new content. So plain widget replace is fine; the defect is
   specific to widgets that are themselves columns of a datagrid.
5. Attempted recovery via `INSERT AFTER` once a datagrid had been emptied of all columns by the bug:
   `insert after dg1 { column ... }` does not insert the column *into* the datagrid — since `dg1` (the
   datagrid itself) is a sibling-level widget name from the enclosing layoutgrid column's point of
   view, "insert after" placed the new content as a sibling *after* the datagrid, not as a child column
   of it — and it built as a `container`/nested `layoutgrid`, not a datagrid column at all. There is no
   widget name left *inside* the datagrid to anchor an `INSERT AFTER`/`INSERT BEFORE` once all its
   columns are gone — the datagrid is left in an unrecoverable, columnless state via ALTER alone.

**Root cause (inferred):** `ALTER SNIPPET|PAGE ... replace` correctly removes the targeted datagrid
column, but building/inserting the replacement column back into the datagrid's specific
column-list BSON slot fails silently — the same widget-tree-vs-pluggable-widget-slot mismatch pattern
already seen in BUG-16 (datagrid `customContent` column BSON) and BUG-19 (dataview widget-list type
clash), but manifesting here as a silent no-op/drop rather than a corrupt-BSON crash. `replace` clearly
has a different (and broken) code path for datagrid columns vs. ordinary page/snippet widgets, since
the exact same operation shape works for the latter.

**Impact:** High — any attempt to modify a datagrid column's contents via `ALTER ... replace` silently
destroys the column with no error, and the resulting empty-of-that-column datagrid cannot be repaired
via any further ALTER operation (no anchor widget remains for INSERT AFTER/BEFORE once a datagrid's
columns are gone). Combined with BUG-69 and BUG-70, this is the third silent-success-but-actually-lossy
`ALTER`/`DROP` code path found in this one build phase alone.

**Workaround used in VB-USI-main:** abandon `ALTER SNIPPET ... replace` for datagrid column changes
entirely. Drop and recreate the whole snippet (`drop snippet ...; / create snippet ... { ... full
datagrid, all columns ... };`) with the corrected column content included from the start — the same
whole-document-recreate pattern already established for BUG-67/BUG-68 snippet fixes. Follow-up fix
script: 56f (supersedes 56e's broken `alter snippet replace` step; 56e's new `ACT_Remark_Edit`
microflow itself is correct and unaffected — only the snippet-repoint step needs redoing via
drop+recreate).

**Does NOT affect:** `ALTER ... replace` on ordinary (non-datagrid-column) widgets — confirmed working
via the plain-`dynamictext`-sibling control test above. Datagrid column changes made as part of a
`CREATE`/`CREATE OR MODIFY` (i.e., building the whole datagrid from scratch in one statement, not
altering an existing one) are also unaffected — this is specific to the `ALTER ... replace` code path
applied to an existing column.

**No fix exists at the ALTER level for datagrid columns.** This needs an mxcli code fix so `ALTER
SNIPPET|PAGE replace` on a datagrid column writes the replacement into the same BSON slot type the
column removal read from, instead of dropping the slot's content silently. Until fixed, any datagrid
column change must go through a full snippet/page drop+recreate.

---

## BUG-72: `mxcli --mcp exec` fails on ANY `CREATE MICROFLOW` statement — wrong ModelSDK property shape for the flow's return type and action nodes

**Sighted:** VB-USI-main, DafNe track Stage 5 Phase 12, script 57b (2026-08-12).

**Symptom:** `./mxcli --mcp http://localhost/mcp --mcp-dial localhost:<port> exec <file.mdl> -p
VB-USI.mpr` (Studio Pro running, MCP session live, correct port confirmed via a working
`initialize` handshake) fails on every `CREATE MICROFLOW` statement tested, regardless of
complexity or return type, with:

```
Error: failed to create microflow: ped_create_document <Module>.<Name>: Creating documents failed (1 of 1):
ERROR: '<Module>.<Name>': Validation errors in form {path: message}: {"/flows/0/$Type":"Expected an element with $Type property.", ..., "/returnType":"Expected one of [Void, Boolean, Binary, Decimal, Integer, Float, DateTime, String, Enumeration, Object, List], got {\"type\":\"Boolean\"}"}
  hint: <Module>.<Name> is defined later in this script — move its create statement before this one
```

**Isolated reproduction:** two throwaway single-microflow files in `/tmp`, tested independently and
not committed to project MDL history:

```sql
-- test 1: trivial typed return
create microflow ProductNumberWorkflow.ZZ_MCPTest ()
returns boolean as $Result
begin
  declare $Result boolean = true;
  return $Result;
end;
/
```

```sql
-- test 2: trivial void return
create microflow ProductNumberWorkflow.ZZ_MCPTestVoid ()
begin
  log info 'test';
end;
/
```

Both failed identically via `--mcp exec` — test 1 reported `"/returnType":..., got {"type":"Boolean"}"`,
test 2 reported the same shape mismatch for `{"type":"Void"}`. Confirmed byte-identical failure under
both `--engine modelsdk` (default) and `--engine legacy` — ruling out `--engine` as a workaround.
Neither test document was confirmed to persist in the model afterward (the error is a validation
failure, apparently before any commit) — spot-checked via `ped_find_document` on the module after the
fact and neither `ZZ_MCPTest` nor `ZZ_MCPTestVoid` appeared, so the failure does appear to be atomic,
not partially-applied.

**mxcli version:** v0.16.0 (2026-07-12T11:44:17Z) — same pinned version as BUG-59 through BUG-71.

**Root cause (inferred by diffing against a real, correctly-created microflow's JSON, read via the
MCP server's own `ped_read_document`/`ped_get_schema` tools):** mxcli's `--mcp exec` code path
serializes the microflow document with the wrong property name and shape for the return type —
emitting `returnType: {"type": "..."}` instead of the ModelSDK's actual expected
`microflowReturnType: {"$Type": "DataTypes$BooleanType"}` (or `DataTypes$VoidType`, etc.) — and
appears to omit `$Type` on at least some flow/object elements entirely (per the `/flows/0/$Type`
validation error). This is a distinct defect from BUG-59 (`CE0066`, a stale-security-metadata issue)
and from the datagrid/ALTER bugs (BUG-66–71) — this one is in mxcli's own MCP-mode document
construction for `CREATE MICROFLOW`, not in a specific ALTER/GRANT code path.

**Impact:** High for any project relying on `learned-mdl-preflight.md` STOP rule 9 (cross-module
inline association writes must go through MCP, not plain CLI, on this pinned mxcli version) —
`--mcp exec` was the intended safe path for exactly this case, and it cannot create the microflow
at all, typed or void, simple or complex. This forces a full bypass of mxcli's MCP wrapper for any
such microflow.

**Workaround used in VB-USI-main:** abandoned mxcli's `--mcp exec` wrapper entirely for this write.
Used direct, hand-rolled MCP JSON-RPC calls (`curl` against the Studio Pro MCP server's `/mcp`
endpoint) instead, calling `ped_get_schema` (constructor schemas for `Microflows$Microflow`,
`Microflows$MicroflowParameterObject`, `Microflows$StartEvent`/`EndEvent`, `Microflows$ActionActivity`,
`Microflows$ChangeObjectAction`, `Microflows$CommitAction`, `Microflows$SequenceFlow`,
`Microflows$MemberChange`) to learn the correct shapes, then `ped_create_document` directly with a
hand-built document using the correct `microflowReturnType`/`$Type`-tagged shapes mxcli's wrapper gets
wrong. This is a viable but much higher-effort fallback — see `learned-mcp-patterns.md` for the
general hand-rolled-MCP pattern; this bug is the reason it was needed at all for a case
`learned-mdl-preflight.md` otherwise documents as "just use `--mcp exec`".

**Also noted (separate, MCP-server-side, not mxcli):** the Studio Pro MCP server's own
`ped_create_document` sometimes lands `Microflows$ActionActivity.action` as `null` even when the
action was included correctly in the submitted document content — confirmed reproducible once in this
session (two `ActionActivity` nodes both landed with `action: null` on first create, fixed via one
`ped_update_document` `set` operation per node, since `set` is permitted on a currently-null element
property; `ped_check_errors` was clean after the fix). Not yet isolated to a minimal repro or reported
upstream — flagging here since it was hit in the same session, but this is a Studio Pro MCP server
defect, not an mxcli defect, so it does not get its own BUG number pending further isolation.

**No fix exists at the mxcli level.** This needs an mxcli code fix to its `--mcp exec` microflow
document serialization (`microflowReturnType` instead of `returnType`, correct `$Type` tagging on all
flow/object elements) before `--mcp exec` can be trusted for `CREATE MICROFLOW` again. Until fixed,
any project hitting STOP rule 9 (cross-module inline association write) must use hand-rolled direct
MCP JSON-RPC calls instead of `--mcp exec` to create the affected microflow.

## BUG-73: `raise error;` in a microflow's main flow always fails mxbuild with CE0710 — a genuine flow-graph codegen defect, not an MDL authoring issue

**Project:** SonnyPOC. **mxcli version:** same pinned build used for BUG-59 through BUG-72 (not
re-checked against a newer release before filing).

**Symptom:** any microflow that uses `raise error;` anywhere in its main flow — including as the
sole statement of an otherwise-empty microflow — fails native mxbuild with CE0710 ("The main flow
cannot join an error flow or end in an error event"). This is NOT the same defect as the earlier
MDL003 linter gap (that one only affects `mxcli check`'s "does this path return" warning, and is
worked around with `SKIP_CHECK=1`). CE0710 is a real, native mxbuild error against a genuinely
invalid generated model — no MDL authoring pattern avoids it.

**Repro, isolated by bisection (least-to-most minimal, each confirmed against a disposable scratch
`.mpr` + direct `mxbuild --write-errors=... --target=deploy` invocation, bypassing mxcli's own
`check`/lint entirely):**
- A microflow whose ENTIRE body is `raise error;` (no `if`, no return type) — fails with CE0710.
- Same, but with a declared return type — fails identically.
- `if $X then return $Result; else raise error; end if;` as the sole statement — fails identically,
  even though both branches are individually "terminal" by any reasonable definition.
- A guard-clause shape (`if $X = false then raise error; end if; return $Result;`) — fails
  identically.
- Nesting depth, if/elsif/else flattening, and the presence/absence of a trailing `return` after
  the `raise error;` statement all make no difference — every shape produces the same CE0710.

**Root cause (confirmed by reading mxcli's own Go source, not inferred):** in
`mdl/executor/cmd_microflows_builder_graph.go`, `buildFlowGraph()` unconditionally appends a
trailing `EndEvent` (and wires an outgoing `SequenceFlow` to it from whatever the last-processed
node was) unless `fb.endsWithReturn` is `true`. `fb.endsWithReturn` is set `true` only by the
`ReturnStmt` handling paths (`cmd_microflows_builder_annotations.go`, `cmd_microflows_builder_actions.go`)
and by the `bothReturn` special case inside `addIfStatement()` in `cmd_microflows_builder_control.go`
(fires only when an enclosing `IfStmt`'s own bookkeeping determines both branches are terminal —
and even that fix does not save the `if/else` repro above, which does hit that code path and still
fails, meaning the per-branch statement loop inside `addIfStatement` itself does not treat a
branch's `RaiseErrorStmt` as "already closed" the way it treats `ReturnStmt`). The `RaiseErrorStmt`
dispatch itself (`case *ast.RaiseErrorStmt: return fb.addErrorEvent()`, same file, ~line 548) never
sets `fb.endsWithReturn = true`. So whenever a `raise error;`-created `ErrorEvent` ends up being the
last node in any statement-processing scope (top-level or per-branch), the closing logic wrongly
appends a second `EndEvent` and wires an illegal outgoing `SequenceFlow` FROM the terminal
`ErrorEvent` — an `ErrorEvent` cannot legally have an outgoing flow in real Mendix semantics, which
is exactly CE0710.

**Confirmed NOT broken:** `raise error;` used *inside* an `on error { ... }` handler block (e.g.
attached to a REST call's error handler) builds cleanly — that construct goes through a different,
correctly-implemented code path (`addErrorHandlerFlow`/`handleErrorHandlerMergeWithSkip`, which
already treats `RaiseErrorStmt` as terminal via `bodyTerminates`). The bug is specific to
`raise error;` appearing directly in the main flow.

**Workaround used in SonnyPOC:** stopped using `raise error;` in the main flow entirely. Added a
tiny Java action (`create java action Module.JA_RaiseTechnicalError(Message: string not null)
returns boolean as $$ throw new com.mendix.systemwideinterfaces.MendixRuntimeException(Message); $$;`)
and call it as an ordinary activity where `raise error;` was wanted, followed by a normal `return`
statement (unreachable at runtime — the Java action always throws — but required to satisfy
Mendix's static "every path returns" check). Calling a Java action is regular activity codegen, not
touched by this bug, and the thrown exception terminates the microflow with a runtime error exactly
like a native `raise error` activity would, visible to the caller's own `ON ERROR` handling the same
way. No design/architecture change was needed — this is purely a codegen substitution.

**No fix exists at the mxcli level.** `RaiseErrorStmt`'s dispatch in `cmd_microflows_builder_graph.go`
needs to set `fb.endsWithReturn = true` (mirroring `ReturnStmt`), and/or the per-branch statement
loops inside `addIfStatement()` need to treat a branch ending in `RaiseErrorStmt` as already-closed
the same way they treat one ending in `ReturnStmt`, before `raise error;` can be trusted anywhere in
a microflow's main flow. Until fixed, any project needing "propagate a technical failure to caller"
semantics from generated MDL should use the Java-action-throw workaround above instead.

## BUG-74: `on error { ... }` handler with no explicit terminal statement silently gets `return;` appended — breaks any "log and continue" error-handling pattern

### Symptom

An `on error { ... }` block attached to a `call microflow` activity, whose body is just a
`log warning ...;` statement (no `return`, no `raise error`, no other terminator), builds with
0 mxbuild errors — but the *live model* the script produced is not what was authored. Reading it
back with `DESCRIBE MICROFLOW` shows mxcli silently appended a `return;` as the handler's last
statement, even though the source MDL never wrote one:

Source (`01b-3-orchestration.mdl`, as authored):
```
call microflow "SharedPlumbing"."STUB_DO_SYNCH_PCG_STATE" (
  "SyncContext" = $SyncContext
)
on error {
  log warning node 'SUB_StateSynchronization' 'STUB_DO_SYNCH_PCG_STATE (NAS) raised for ApplicationKey ''' + $SyncContext/ApplicationKey + ''' -- swallowed, B-4 no cross-abort.';
};
```

Live model, round-tripped via `mxcli -p SonnyPOC.mpr -c "DESCRIBE MICROFLOW SharedPlumbing.SUB_StateSynchronization"`:
```
call microflow SharedPlumbing.STUB_DO_SYNCH_PCG_STATE(SyncContext = $SyncContext
) on error {
  log warning node 'SUB_StateSynchronization' '{1}' with ({1} = '...');
  return;
};
```

Because a bare `return;` in Mendix always exits the **entire** microflow (not just the enclosing
`if`/error-handler scope), this silently converts an intended "log the fault and keep going to the
next branch" pattern into "log the fault and abort everything after it." In `SUB_StateSynchronization`
(three independent `if <ShouldSync> then call ... on error { log ... }; end if;` blocks in sequence,
one per channel — NAS, ODS, CBL — explicitly designed so a fault in one channel's stub call can never
block the others, per this project's documented B-4 "no cross-abort" decision), this means: if the
NAS branch's stub call faults, the appended `return;` terminates the microflow immediately, and the
ODS and CBL branches are never attempted at all. `mxbuild` reports 0 errors throughout — this is a
purely semantic/structural defect, invisible to the compiler, only caught by manually diffing
source MDL against the live model's round-tripped serialization (or by a reviewer who knows to
check for it).

### Detection

Caught by a review pass that inspected `SUB_StateSynchronization`'s error-handler shape and flagged
that each `on error {}` block terminated the whole flow instead of just the branch — then confirmed
by direct comparison of the authored source against `DESCRIBE MICROFLOW` output on the live model.

**Minimal repro**, confirmed on this same mxcli build: a single-call microflow with one `on error {
log warning '...'; }` handler (no other statements in the handler) followed by more logic in the
main flow (`log info 'reached after first branch'; return;`). Reading the microflow back after
exec shows the `on error {}` handler now contains `log warning ...; return;` — an unconditional
insertion, not something specific to multi-branch microflows or to this project's particular shape.

### Root cause

Not yet isolated in mxcli's Go source (unlike BUG-73, this has not been traced to a specific
function/line). Suspected to be the same family as BUG-73: codegen for a statement block that
lacks an explicit terminal statement defaults to closing the block with an `EndEvent`/`return`
rather than merging control flow back to the point after the enclosing `if`/error-handler
structure. Whether this happens for *every* terminator-less `on error {}` block unconditionally,
or only under some condition (e.g. only in main-flow scope, only for void microflows), has not been
fully mapped — the one minimal repro above is enough to confirm it is not specific to this
project's exact microflow shape, but the general boundary of the defect is unconfirmed.

### Workaround used in SonnyPOC

Do not rely on an `on error {}` handler's fall-through to continue past a caught fault within the
*same* microflow when more logic follows in the main flow. Instead, extract each
call-with-error-handler into its own tiny wrapper microflow (one per branch). The wrapper's own
body is *only* the call + its `on error { log ...; }` handler — so the auto-appended `return;` is
now correct (it was already about to be the wrapper's last action) instead of destructive. The
caller (e.g. `SUB_StateSynchronization`) then just calls each wrapper microflow in sequence, with no
error handler of its own needed at that level, since each wrapper already fully swallows its own
fault internally and never raises to its caller. This preserves the "independent error boundary per
branch" design (B-4) without depending on any specific `on error {}` fall-through behavior.

### Related

Same general class of defect as [BUG-73](#bug-73-raise-error-in-a-microflows-main-flow-always-fails-mxbuild-with-ce0710--a-genuine-flow-graph-codegen-defect-not-an-mdl-authoring-issue)
(terminal-statement bookkeeping in the flow-graph builder is incomplete for statement forms other
than an explicit `return`), but distinct: BUG-73 causes a hard mxbuild failure (CE0710); BUG-74
causes a *silent* structural change that mxbuild accepts as valid, making it strictly more
dangerous — there is no compiler signal to catch it, only a source-vs-live-model diff or a reviewer
who knows to look for the appended `return;`.
