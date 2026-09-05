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

**RESOLVED (FIXED in ≤v0.20.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

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

> ### ⚠️ PARTIALLY FIXED in mxcli v0.18.0 — retested 2026-08-20
>
> Retested on v0.18.0, Mendix 11.12.0 (MPR v2), throwaway sandbox of a scratch reference app.
> **Core symptom fixed:** `ALTER PAGE … SET DataSource = $Param ON dv` now retypes a DataView
> from a microflow datasource to a page-parameter datasource in place, nested widgets preserved;
> the reverse retype works too. v0.17.0 fails the identical statement with
> `unsupported DataSource type for alter page set: parameter`. Idempotent, and confirmed under
> `MXCLI_ALWAYS_WRITE=1`, so this is not ADR-0008 write-elision. Zero new errors over the
> sandbox's 3 pre-existing unrelated ones.
> **Still open, narrower:** the *association* form `SET DataSource = $currentObject/Module.Assoc`
> is still refused — but now with an actionable error naming `REPLACE`, which does perform the
> retype and builds clean. Severity stays **Low**.
> **New defect found while retesting, logged separately:** `SET DataSource = DATABASE Module.Entity`
> on a DATAVIEW reports success while silently clearing the datasource, surfacing later as
> `CE7007`. See [mxlabs-v0.18.0-retest-2026-08-20.md](mxlabs-v0.18.0-retest-2026-08-20.md).

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

> ### ⚠️ CORRECTION — "does NOT affect" claim narrowed (2026-08-20)
>
> The claim below, "**Does NOT affect:** `visible: [expr]` on containers in regular dataviews and
> regular page containers — those work correctly," is **wrong for the sibling `Editable`
> property**, and the same root cause is now confirmed to reach plain, non-datagrid widgets too.
>
> Confirmed 3x with a controlled A/B (mxcli project-local build, Mendix 11.13.0), including a
> negative-control replay of the page's own pre-existing, already-working expression: `ALTER PAGE
> Module.Page { SET Editable = ["Attr" = '' or "Attr" = empty] ON widget }` on a plain `textbox`
> inside a plain `dataview` (not a datagrid, not a customContent column, not a container) passes
> `mxcli check --references` cleanly, executes with no error from `mxcli exec`, but writes a
> corrupt `ConditionalEditabilitySettings` unit with a blank `Attribute` reference:
> ```
> Mendix.Modeler.Storage.StorageLoadException: One or more invalid values were detected while
> loading the project: ... Conditional editability settings in  has an invalid value '' for
> property Attribute. The text 'Forms$ConditionalEditabilitySettings' is not a valid
> AttributeIdentifier.
> ```
> Studio Pro cannot reopen the project afterward. `mxcli check --references` gives zero warning —
> this is a storage-level (BSON) defect entirely invisible to the syntax/reference checker.
>
> **What makes this a correction and not a suspicion:** re-issuing the exact same expression the
> page already had *before* the edit (`SET Editable = ["Attr" = ''] ON widget`, verbatim, no
> compound `or`, no `empty` keyword) through the same `ALTER PAGE SET` path, on a fresh sandbox
> copy, produced **identical corruption, identical error** — ruling out the compound boolean
> expression or the `empty` keyword as the cause. The defect is `ALTER PAGE ... SET Editable =
> [...]` itself on this Mendix version, independent of expression content, and independent of
> datagrid/customContent/container as claimed below.
>
> Whether the same widening also applies to `Visible` (not just `Editable`) on a plain-dataview
> widget is untested — this correction covers only `Editable`.
>
> **Workaround confirmed to work:** a full `CREATE OR MODIFY PAGE` rebuild of the entire page
> (reproducing the unaffected widgets unchanged) with the new `Editable: [...]` expression written
> directly in the `CREATE OR MODIFY` body, never through `ALTER PAGE SET`. Verified via sandbox
> copy + `mxcli docker check`: no `StorageLoadException`, only pre-existing unrelated noise.
>
> **Method:** per-arm sandbox copy (`cp Project.mpr /tmp/sandbox-N.mpr`), `mxcli exec
> candidate.mdl -p /tmp/sandbox-N.mpr`, then `mxcli docker check -p /tmp/sandbox-N.mpr`, grep for
> `StorageLoadException`. Never touch the real project file — prove the gate is sensitive to the
> defect before trusting a green result from it.

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

**Discovered:** 2026-07-03, PROJECT-H (an inventory pilot, datagrid). 2026-07-05, a large-source WMS project script 18 (snippet with no entity context).

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

**RESOLVED (FIXED in v0.17.0, upstream #854) — archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md).**

## BUG-21: Inline association-set in CHANGE/CREATE activity writes invalid `AttributeIdentifier` BSON → SP rejects on load

**RESOLVED (FIXED in v0.17.0, upstream #838) — archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md).**

## BUG-22: `alter settings configuration` / `alter settings model` / `alter project security level` — deterministic BSON stream-desync on the Settings unit

**RESOLVED (FIXED in ≤v0.20.0; guest access newly scriptable in v0.19.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**
**Independently re-confirmed 2026-09-01 by a second retest, different method** — 18 executions via `tests/retests/retest-bug22-settings-writes.sh` (re-runnable), values round-tripped, full deploy build clean; preflight STOP rule 2 retired for ≥ v0.20.0 (old binaries keep it). That retest's full text is preserved in the archive alongside this entry's.


## BUG-23: `ContentParams` with an explicit `$currentObject/` prefix resolves as a literal (broken) attribute path → CE1613

**Severity:** High — silent, repeat offender. Passes `mxcli check`/`describe page` every time; only fails on a real `mx check`/`docker check`/SP compile. Estimated to have caused this exact mistake ~500 times across sessions before the root cause was isolated.
**Reproducible:** Yes, consistently
**Confirmed:** Mendix 11.12.0, mxcli v0.13.0, 2026-07-20 (PROJECT-D)
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
reconfirmed twice before filing: on PROJECT-F (mxcli v0.17.0, mxbuild/Studio Pro 11.13.0, real
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

## 🚨 CRITICAL: `mxcli run --local` also collapses split-model `.mpr` to monolithic — second trigger, same failure as marketplace install

**Discovered:** 2026-09-01, a dashboard-publishing migration project, mxcli run --local via
`project-tests/app.sh start` (`./mxcli run --local -p PuffinDashboards.mpr --ensure-db`),
Mendix 11.12.1, split-model project (219 tracked `mprcontents/*.mxunit`, ~78 KB `.mpr`).

This is the SAME failure as the `marketplace install` entry above (collapse to monolithic
`.mpr`, `mprcontents/` deleted from disk) but from a **different, much more commonly used
trigger**: simply running the app locally. `.mpr` went 77,824 bytes → 15,446,016 bytes;
`git status` showed 438 `D` + 2 `M` after a single `app.sh start` / `app.sh restart`. Caught
before commit only because this project's own build discipline runs `git status` before any
commit — a session that trusts `git add -A` blindly would have committed the collapse and lost
git's ability to diff every future model change file-by-file.

**Why it matters more than the marketplace-install trigger:** `mxcli marketplace install` is a
rare, occasional operation a session is likely to pause before. Running the app locally to
verify a fix on screen is routine — the toolkit's own field-proof discipline in this repo's
`CLAUDE.md` (§ "Shipping an instrument") requires it ("one field run, cited"). A workflow that
requires routine local runs and silently corrupts the git-friendly format on every one of them
is a landmine directly on the path the toolkit itself mandates.

**Prevention (the rule, until upstream fixes it or a flag is found):** `project-bin`/
`project-tests` start scripts for a split-model project MUST snapshot (`bin/snapshot-mpr.sh` or
equivalent) before every `mxcli run --local` / `mxcli run --local --watch`, and the session MUST
run `git status` — never a blind `git add -A` — before any commit that follows a local app run.
Restore split format after verifying on screen, before committing anything else:
```bash
git checkout HEAD -- <project>.mpr mprcontents/   # or bin/restore-mpr.sh <pre-run-snapshot>
```
Not yet confirmed whether a `run --local` flag avoids the collapse, or whether it is specific to
`--ensure-db` / a particular mxbuild version — retest and update this entry if found.

### Toolkit-fix candidate
`project-tests/app.sh`'s `start` action should call `bin/snapshot-mpr.sh` unconditionally before
launching `mxcli run --local`, the same way `bin/exec.sh` already does before an MDL exec — this
trigger is not covered by that existing guard because it is a different code path.

---

## BUG-101: mxcli-authored Gallery widget fails mxbuild CE0463 even after full regeneration ⚠️ NOT YET FILED — `add_repo` denied access to `mendixlabs/mxcli`

**NOT YET FILED.** The filing session already had `mxcli-project-toolkit` (owner `mendixmau`)
attached and `add_repo` refused a cross-owner attach: `cross-tier adds are not supported in v1:
requested "mendixlabs/mxcli" but session already has repos from owner(s) [mendixmau]`. A session
started fresh with `mendixlabs/mxcli` as its initial source should be able to file this
directly. Full repro and suggested fix:
`bug-logs/pending-github-issues/gallery-widget-ce0463-survives-regeneration.md`.

**Severity:** High — a Gallery page authored entirely through mxcli passes every mxcli-side
check yet permanently fails headless `mxbuild`, and no mxcli command (`check`, `widget sync`,
full page regeneration, or single-widget regeneration with a fresh element ID) repairs it.
**Discovered:** 2026-09-01, a dashboard-publishing migration project, mxcli v0.20.0
(2026-08-28T13:22:53Z), Mendix 11.12.1, Gallery pluggable widget package 3.4.0
(`com.mendix.widget.web.gallery.Gallery`), split-model project.
**Reproducible:** Yes, consistently — retested same day, identical `elementId`/`unitId` and
message.

### What happens
Any Gallery widget mxcli authors via `CREATE PAGE` (or `ALTER PAGE ... REPLACE` with a brand-new
instance/element ID) fails headless `mxbuild` on that specific instance with:
```
CE0463: "The definition of this widget has changed. Update this widget by right-clicking it
and selecting 'Update widget', or select 'Update all widgets' to update all widgets in the app."
```
It is the only error in the build — everything else is Warning/Deprecation. Repro:
```bash
./mxcli docker check -p <project>.mpr        # 0 errors — looks fine
timeout 60 ./mxcli run --local -p <project>.mpr --ensure-db 2>&1   # mxbuild --serve; CE0463 fires
```

### Why it is not stale/corrupted instance data
1. `mxcli check <script>.mdl -p <project>.mpr --references` passes clean.
2. `mx check` (Studio Pro's own headless modeler) reports **0 errors** on the same `.mpr` — it
   appears to tolerate/auto-normalize the mismatch in-memory rather than surface it.
3. `mxcli widget sync -p <project>.mpr` reports "nothing to do", or fixes unrelated widgets
   (Image widgets elsewhere in the project) — it never detects or fixes this Gallery instance.
4. Regenerating the **entire containing page** from scratch does **not** fix it — identical
   error persists.
5. Regenerating **just the one widget instance** (fresh element ID) via `ALTER PAGE ... REPLACE`
   **still** produces the identical CE0463 error, on the new element ID.

(4) and (5) rule out stale data: a fresh element, freshly written, in a freshly regenerated
page, fails the same way. The defect is in what mxcli serializes for a Gallery widget's stored
configuration — likely a missing/mismatched property or version stamp that headless `mxbuild`'s
stricter widget-definition check enforces but `mx check` does not.

### Prevention
Treat `Gallery` (and other pluggable widgets with template/child-slot bodies) as risky
`CREATE PAGE` targets: verify with a real `mxcli run --local` / headless `mxbuild` pass, not
just `mxcli check` or `mx check` — both of those report clean on this exact defect.

### Recovery
No mxcli-side fix found. Workaround is to place/repair the Gallery widget in Studio Pro's GUI
("Update widget"), which resolves CE0463 directly, then re-export/keep working in split format.

### Toolkit-fix candidate
`learned-mdl-preflight.md` / `learned-detection-gaps.md` STOP or WARN row: "Gallery (and other
child-slot pluggable widgets) placed via CREATE/ALTER PAGE must be verified with a real
`mxcli run --local` pass before being trusted — `mxcli check` and `mx check` both pass CE0463
clean."

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

**RESOLVED (symptom 1 FIXED in v0.17.0 as BUG-59; symptom 2 — additive merge and one rule per XPath constraint — FIXED in v0.19.0, #936) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## CRITICAL: mxcli exec of association + GRANT script corrupted the MPR's BSON storage (unrecoverable except by restore)

**Discovered:** 2026-07-22 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1).

### Symptom
After `mxcli exec` of a script creating an association (`Account_Supplier`, Administration↔PLM) plus `GRANT` rules referencing it (the same script documented in the "association names silently dropped from member lists" entry above), the `.mpr` became unopenable — both in Studio Pro GUI and in `mxbuild` (any platform, any architecture):
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
`Administration.Account_Supplier` (Administration↔PLM, Reference, Default owner) was added cleanly via Studio Pro GUI per the workaround above, confirmed present via `SHOW ASSOCIATIONS`. A subsequent, unrelated mxcli script (`03b-plm-domain-revision.mdl`) then dropped/recreated two non-persistent-to-persistent entities, added two new entities, added a new same-module association (`PLM.PLMStub_Supplier`), and — per STOP rule 14 — rebuilt **all four** role grants on `PLM.PLMStub` in one block (revoke all, regrant all), including a new Vendor XPath `[PLMStub_Supplier = '[%CurrentUser/PLM.Account_Supplier%]']` copying the already-existing `FeasibilityDecision` pattern.

`bin/exec.sh`'s `mx check` gate caught 2 errors post-exec, both `CE0161` "Error(s) in XPath constraint":
- `Access rule of entity 'PLM.PLMStub'` (the one this script actually touched)
- `Access rule of entity 'PLM.FeasibilityDecision'` (**untouched by this script** — a pre-existing rule from a prior, already-committed exec, broken as collateral damage)

Auto-restore worked correctly this time (unlike the BSON-corruption entry above) — rolled back to the last known-good snapshot and reported clearly. But that snapshot predated *both* this script *and* the `Account_Supplier` GUI addition, so the association was lost from the working tree again too (the git commit recording it still exists in history, but `.mpr`/`mprcontents` on disk reverted under it — a real, visible working-tree/HEAD mismatch, not silently reconciled).

### Root cause (refined from the two entries above)
The failure isn't scoped to "creating the association + a grant referencing it in the same script" (the original 2026-07-22 finding) — it's that **once any entity access rule anywhere in a module has an XPath referencing this association, mxcli cannot successfully write *any* GRANT/REVOKE touching *any* entity in that module**, even when the script never mentions the broken rule. mxcli's domain-model write path appears to reserialize the whole `Domain model` unit on any access-rule change, not just the targeted entity — so a previously-fine `FeasibilityDecision` rule gets re-touched and re-broken purely as a side effect of an unrelated `PLMStub` grant rewrite in the same exec.

### Workaround (updated)
Once a module contains **any** entity access rule with a cross-module `[%CurrentUser/OtherModule.Assoc%]` XPath, treat **all** subsequent GRANT/REVOKE work on **any** entity in that module as Studio-Pro-GUI-only — not just the rule that references the association. Structural changes (entities, attributes, non-security associations) in the same module remain mxcli-safe; only the access-rule layer is affected. Verify with `DESCRIBE ENTITY` + a real `mx check` (not just `mxcli check --references`, which gives zero signal for this) after every grant-touching exec in an affected module.

### Related preflight rule
Extends STOP-table rule 14 (`learned-mdl-preflight.md`) — rule 14's "rebuild the whole entity's grants in one script" guidance is still correct for avoiding cross-role collapse *within* a single entity, but does not protect against this failure mode, which crosses entities within the same module. New STOP-table entry added (rule 16) generalizing this.

### Correction (2026-07-23, same day) — root cause was invalid XPath syntax, not mxcli corruption
Re-diagnosed after the user manually fixed the `FeasibilityDecision` Vendor rule in Studio Pro and shared before/after screenshots. The actual bug: `[Assoc = '[%CurrentUser/Module.OtherAssoc%]']` — a path expression *inside* the `[%CurrentUser/...%]` substitution token, crossing module boundaries — is invalid Mendix XPath. `CE0161` was Mendix correctly rejecting it every time, not mxcli corrupting the domain model. The "unrelated `FeasibilityDecision` rule also broke" symptom above was actually two independently-broken rules (both written with this same invalid form) surfacing together the first time a full `mx check` ran on both — not evidence of one grant rewrite damaging an unrelated rule.

**Confirmed working fix**, applied manually in Studio Pro:
```
-- Broken:
[FeasibilityDecision_Supplier = '[%CurrentUser/PLM.Account_Supplier%]']
-- Fixed — keep CurrentUser bare, walk the whole chain on the left,
-- qualifying the entity name at each module crossing:
[PLM.FeasibilityDecision_Supplier/PLM.Supplier/Administration.Account_Supplier = '[%CurrentUser%]']
```
This means the "Studio Pro GUI only, module-wide" conclusion above was too broad. Once an access-rule XPath uses the correct bare-CurrentUser/full-LHS-chain form, there's no known reason it can't be written via mxcli directly. **Confirmed same day**: `test-05-currentuser-xpath-chain.mdl` rebuilt all 4 `FeasibilityDecision` role grants via mxcli exec, reproducing the corrected Vendor XPath verbatim — `mx check: 0 errors`. The corrected form is genuinely mxcli-safe, not just Studio-Pro-GUI-safe. See STOP-table rule 16 (updated) for the corrected pattern — no GUI-only restriction remains for this specific XPath shape.

## Inline association-set (STOP rule 9): same-module confirmed safe via plain CLI on v0.16.0 -- cross-module remains broken

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1). Scoping clarification of rule 9, not a reversal -- the pre-existing 2026-07-13 finding on this same mxcli version (`System.User_UserRoles`, cross-module, a WMS conversion project) still stands.

### What was tested
1. Isolated throwaway test: two brand-new entities in the same project module (`PLM`), new `Reference` association between them, set inline via `CHANGE` inside a microflow, executed via plain `bin/exec.sh`. `mx check` and full `mxcli docker check`: 0 errors. Cleaned up via the same plain-CLI path -- also clean.
2. Real production script: `06-plmint-bomstub.mdl`, a 176-activity microflow with 46 inline association-sets, all entirely within `PLM`. Ran via plain `bin/exec.sh` after MCP mode proved unreliable. `mx check`: 0 errors.

### What this does and does not mean
- Same-module inline association-sets (both sides in one module, including a marketplace module's own internal associations) are safe via plain CLI on v0.16.0.
- Cross-module inline association-sets remain a confirmed STOP -- the `System.User_UserRoles` finding is untouched by this entry. Do not extrapolate; the two were tested separately and behave oppositely on the identical mxcli version.
- When unclear whether an association is same-module or cross-module, default to treating it as cross-module and use `--mcp`.

### MCP reliability note (same session)
Before falling back to plain CLI for `06`, MCP mode failed twice on a stale module-container reference, then hung unresponsive after a fresh Studio Pro reopen (required a hard kill). MCP itself is not consistently available even when it's technically the correct choice.

### Related preflight rule
STOP-table rule 9 updated to reflect the same-module/cross-module split precisely, rather than a blanket "use MCP" for all inline association-sets.

## Compound boolean `AND`/`OR` (uppercase) + `!=` in the same expression → CE0117/CE0161 (mxcli bug)

**RESOLVED (FIXED in ≤v0.20.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

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

`CALL MICROFLOW PLM.MyMF WITH (PLM.MyMF.Param = '$workflowContext')` in a workflow body causes mxcli to write a null `ParameterId` into the BSON unit. `mxcli check` and `mx check` both pass (0 errors), but at runtime the parameter binding is invalid and the call fails.

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

**RESOLVED (FIXED in v0.17.0, upstream #845) — archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md).**

## Bare `Status` attribute name in a `retrieve ... where` clause → CE0161 (reserved-word conflict)

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1), same debugging session as the AND/OR bug above.

`retrieve $X from PLM.PLMStub where ... and Status != Enum.Archived` passes `mxcli check` but fails a real `mx check` with CE0161. Quoting the attribute (`"Status" != Enum.Archived`) fixes it. Notably, this project's own domain model already quotes `"Status"` specifically in `PLMStub`'s access-rule read lists, while every sibling attribute in the same list is unquoted — a pre-existing signal (visible via `DESCRIBE ENTITY`) that this specific attribute name needs quoting, which would have shortened the debugging cycle if checked first. Added to the "Keyword collisions" bullet in `learned-mdl-preflight.md`.

---

## BUG-24: `CALL MICROFLOW` in a workflow without `WITH` clause → broken activity (red pin) + runtime crash

**SUPERSEDED — misdiagnosed; the real cause is BUG-WF06 (pre-11.9 `$Type` storage name for workflow call-microflow activities), fixed in v0.17.0 — archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md).**

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

> ### ⚠️ PARTIALLY FIXED in mxcli v0.18.0 — retested 2026-08-20 against Studio Pro 11.13.0 Beta
>
> **Root-caused.** Studio Pro 11.13's `pg_read_page` defaults to `depth: 4`, collapsing a real page
> to `{"widgets":[{"$Type":"Pages$Content","slot":"Main","widgets":["..."]}]}` — measured live,
> 162 bytes vs 18,356 at `depth: 1000`. Because ALTER PAGE is read-modify-replace-whole-page, that
> truncated body was **both** the tree the anchor lookup searched (symptom 1, "widget not found" on
> anchors that plainly exist) **and** the body written back (symptom 2, `PROP_NOT_PRIMITIVE` on
> `widgets`). One defect, both symptoms. v0.18.0 (`a359f95e`) requests `depth: 1000` when the tool
> advertises the argument, and refuses the read outright when a sentinel survives.
> **Symptom 1 fixed** — v0.17.0 reproduces `failed to insert: widget "buttonsCard" not found`
> verbatim; v0.18.0 inserts correctly with all 52 widgets preserved.
> **Symptom 2 NOT confirmed end-to-end** — the emitted payload is now well-formed but no live write
> was performed, so Studio Pro's acceptance is unverified. Not build-verified (no `.mpr` mutated).
> **Also note:** on v0.17.0 `SET Title` does not merely fail — it reports "Altered page" while
> writing `widgets:["..."]` back. **Silent whole-page destruction.**
> **Version gap:** this entry was filed against Studio Pro **11.12.1**, where the `depth` argument
> does not exist. Whether 11.12.x truncates is undetermined; if it does, v0.18.0 will safely refuse
> rather than fix. **Keep the STOP rule for Studio Pro 11.12.x**; on 11.13, re-enable
> `--mcp exec ALTER PAGE` only after one supervised write to a disposable page.

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
(anchor was a DG2 datagrid column, name confirmed via `DESCRIBE PAGE PLM.PLM_PMODashboard` immediately beforehand)

```
Error: failed to insert: widget "SupplierName" not found
```
(same page, a different DG2 column)

```
Error: failed to insert: widget "row6" not found
```
(PLM_SupplierOverview — a plain top-level LAYOUTGRID row, NOT a DG2-internal widget, ruling out "DG2 columns aren't addressable" as the sole explanation)

`--mcp-verbose` printed no PED tool-call trace before any of these errors — the failure happens before a `pg_patch_page` call is even logged, suggesting local anchor resolution (against the `-p` disk file) disagrees with whatever the live SP in-memory model actually has, OR the widget-name lookup path used for `INSERT AFTER` targeting is broken independent of the anchor's real existence.

### Symptom 2 — malformed patch on a trivial single-property SET

```sql
ALTER PAGE "PLM"."PLM_SupplierOverview" {
  SET Title = 'Vendor Portal'
};
```
```
Error: failed to save modified page: pg_patch_page PLM.PLM_SupplierOverview: Error invoking tool 'pg_patch_page':
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

**RESOLVED (FIXED in v0.17.0, upstream #836) — archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md).**

## BUG-28: `reset layout` accepts invalid MDL at `check` time, fails at `exec`

**RECLASSIFIED as an enhancement request, not a bug — `RESET LAYOUT` was never implemented in RnD's grammar; Engalar built it fork-specific from scratch — archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md).**

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

> ### ⚠️ PARTIAL FIX 2026-08-20 — microflow half CLOSED, nanoflow half OPEN
>
> Retested on mxcli v0.18.0, Mendix 11.12.0. MDL044 is now a write barrier
> (`execEnforcedMicroflowRules`, `mdl/executor/validate.go`), so `exec` **refuses**
> `currentDeviceType()` in a `create microflow` (exit 1, not written; identical under
> `MXCLI_ALWAYS_WRITE=1`). A/B: v0.17.0 wrote the same script and the app then checked with CE0117.
> The fix did **not** go the opposite way — the three built-ins un-flagged by #828 are
> `isNew`/`isSynced`/`isSyncing`, and an `isNew($Obj)` control adds 0 errors.
> **RESIDUAL, newly found:** the barrier is **microflow-only**. `validateMicroflowRules` is called
> from `cmd_microflows_create.go` and never from `execCreateNanoflow`, so the same expression in a
> `create nanoflow` passes `check`, is written by `exec`, and fails the build with CE0117 —
> `check` does not even lint it. The bracket-percent workaround `[%CurrentDeviceType%]` **also**
> fails CE0117 inside a nanoflow expression (it is a page/XPath token, not a flow-expression
> token), so the workaround recorded below does not apply in flow contexts.
> Page conditional-visibility expressions not retested.

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

**RESOLVED (FIXED in mxcli v0.18.0) — retested and archived 2026-08-20, see [archive-resolved-2026-08-20.md](archive-resolved-2026-08-20.md) and [mxlabs-v0.18.0-retest-2026-08-20.md](mxlabs-v0.18.0-retest-2026-08-20.md).**

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

**RESOLVED (FIXED in mxcli v0.18.0) — retested and archived 2026-08-20, see [archive-resolved-2026-08-20.md](archive-resolved-2026-08-20.md) and [mxlabs-v0.18.0-retest-2026-08-20.md](mxlabs-v0.18.0-retest-2026-08-20.md).**

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

**Confirmed via isolated sandbox A/B, 2026-08-20** — per `skills/sandbox-ab-tool-defect-probe.md`,
byte-identical DataGrid2/column/filter/action MDL run through RnD `v0.17.0` and Engalar
`bc3d94ef4` against two independently-baselined (0-error) sandbox copies of `TestCLIApp-main`
(Mendix 11.12.0). RnD's `describe page` roundtrip preserved `onClick`, `DynamicCellClass`,
`textfilter`, and `dropdownfilter` intact; Engalar's — from the same MDL block — dropped
`onClick`, `textfilter`, and `dropdownfilter` entirely, keeping only `DynamicCellClass`. Both
arms reported exec success and gated at 0 errors, so the loss is silent end-to-end on Engalar.
This raises **Reproducible** from "Reported only" to **confirmed, isolated, fork-specific**.
Full write-up (commands, exact `mx check`/`describe page` output, diff of the two probe scripts)
was produced as `test-assessments/dg2-bug42-probe/RESULT.md` — that folder is gitignored scratch
per `test-assessments/README.md`, so the evidence lives here in this entry, not in a tracked file.

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

**RESOLVED (FIXED in v0.17.0, upstream #835) — archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md).**

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
**Reproducible:** Yes, first attempt, on the real PROJECT-E project.
**Mendix version:** 11.13.0 Beta (project format 11.13.0)
**mxcli version:** v0.16.0 (tagged release, built 2026-07-12)
**Discovered:** 2026-08-04, PROJECT-E, isolated probe `mdlsource/3c-workflow/probe-wf-callmf-11.13.mdl`.

### Why this entry exists

BUG-WF04 (2026-08-03) retested this area and found it green — but **only against RnD HEAD
`504aec67` and Engalar `26f2866`**, both of which post-date the four workflow fixes that landed
2026-07-29 (`253d60d8`, `08746d00`, `1b390dce`, `b6a5043a`). Projects still running the **tagged
v0.16.0 release** have none of those fixes. BUG-WF04's "resolved" verdict does not transfer to them.
This entry records what v0.16.0 actually does on 11.13.

### Trigger

```sql
CREATE WORKFLOW PLM."WF_ProbeCallMF"
  PARAMETER $WorkflowContext: PLM."PLMStub"
BEGIN
  CALL MICROFLOW PLM.WF_ACT_TCCopilot_Prefill
    WITH (PLM.WF_ACT_TCCopilot_Prefill.PLMStub = '$workflowContext');
END WORKFLOW;
```

Target microflow has a **single** entity-typed parameter (`$PLMStub: PLM.PLMStub`) — i.e. squarely
inside BUG-WF04's verified envelope. The fully-qualified `Module.Microflow.Param` WITH-key form is
the one BUG-24 recommended as "CORRECT".

### Symptom

`mxcli check` passes. `mxcli exec` reports `Created workflow: PLM.WF_ProbeCallMF`. Then `mx check`:

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
`PROJECT-E/mdlsource/3c-workflow/archived/09j-plm-workflow-correct.mdl` already documents.
Upgrading to a post-`1b390dce` binary is the real fix — **now verified on 11.13**, see below.

### RESOLVED on RnD `504aec67` — controlled A/B on 11.13 (2026-08-04, same day)

Re-tested as a clean two-arm experiment: two throwaway `rsync` copies of the real PROJECT-E project in
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
call microflow PLM.WF_ACT_TCCopilot_Prefill with (PLMStub = '$WorkflowContext')
  outcomes
    DEFAULT -> { };
```

- WITH-key stored **short** (`PLMStub`), not fully-qualified — `253d60d8`'s 11.9+ version gate.
- context var normalized `'$workflowContext'` → `'$WorkflowContext'`, and `outcomes DEFAULT -> { }`
  synthesized from the target's return type — `1b390dce`.
- read back at all — `b6a5043a` (parse `CallMicroflowActivity` storage name on read).

**Conclusion: BUG-WF05 is a binary-version defect, not a Mendix 11.13 limitation.** The
drag-in-Studio-Pro workaround is only required for projects still on the tagged v0.16.0 release.
Note the input form is unchanged — the *same* fully-qualified `Module.Microflow.Param` WITH-key
that crashes v0.16.0 is accepted and normalized by `504aec67`; no script rewrite is needed, only a
binary swap.

### Confirmed on the REAL production workflow, not just a probe (2026-08-05)

The above used a 1-activity throwaway. Re-run with PROJECT-E's actual
`09b-plm-workflow-fix-callmf.mdl` — `CREATE OR REPLACE`, **5 × `CALL MICROFLOW` with WITH clauses,
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

**RESOLVED (FIXED in official tag v0.17.0, upstream #846) — archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md).**

## BUG-58: `ALTER PAGE ... SET Editable = [...] ON widget` writes a blank `AttributeIdentifier` regardless of expression complexity → `StorageLoadException` on Studio Pro open

**RESOLVED (FIXED in ≤v0.20.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-59: `GRANT ... (READ (...), WRITE (...))` silently drops an association name it doesn't already know about — cannot add a new association `MemberAccess` entry to an access rule, so `CE0066` on a bidirectional (`Owner: Both`) association has no mxcli fix

**RESOLVED (FIXED in mxcli v0.17.0, NOT v0.18.0) — retested and archived 2026-08-20, see [archive-resolved-2026-08-20.md](archive-resolved-2026-08-20.md) and [mxlabs-v0.18.0-retest-2026-08-20.md](mxlabs-v0.18.0-retest-2026-08-20.md).**

## BUG-60: `./mxcli docker check` collapses a v2 split-tree `.mpr` back to v1 single-file and deletes `mprcontents/` — on a plain read-only check, no exec involved

**RESOLVED (FIXED in mxcli v0.17.0, NOT v0.18.0) — retested and archived 2026-08-20, see [archive-resolved-2026-08-20.md](archive-resolved-2026-08-20.md) and [mxlabs-v0.18.0-retest-2026-08-20.md](mxlabs-v0.18.0-retest-2026-08-20.md).**

## BUG-61: `CALL JAVA ACTION` on a marketplace action with generic/typed parameters (`MicroflowType`, `EntityTypeParameterType`) writes plain string/expression values instead of the special parameter-value shapes — Studio Pro reports `CE0115`/`CE0126`

**RESOLVED (FIXED in mxcli v0.18.0) — retested and archived 2026-08-20, see [archive-resolved-2026-08-20.md](archive-resolved-2026-08-20.md) and [mxlabs-v0.18.0-retest-2026-08-20.md](mxlabs-v0.18.0-retest-2026-08-20.md).**

## BUG-62: `ALTER PAGE ... SET Snippet = ... ON <snippetcall-widget>` passes `--references` but fails at exec time — `SNIPPETCALL` widgets need `REPLACE` with an explicit `Params` map, not `SET`

> ### ⚠️ PARTIALLY FIXED in mxcli v0.18.0 — retested 2026-08-20
>
> Retested on v0.18.0, Mendix 11.12.0, graded with Studio Pro 11.12.0's `mx`, A/B'd against v0.17.0.
> **The CE0115 half is fixed.** A `SNIPPETCALL` whose parameter is satisfied by the enclosing data
> context now takes **no** `Params` mapping: `REPLACE widget WITH { SNIPPETCALL n (Snippet: M.S) }`
> is accepted (v0.17.0 refused it) and builds clean, and `Params: { X: $currentObject }` is now
> normalised to the empty `ParameterMappings` list Studio Pro writes instead of producing CE0115.
> **The 2026-08-11 CORRECTION below is therefore OBSOLETE** — an in-mxcli form exists and Studio
> Pro's *Refresh snippet parameters* step is no longer needed.
> **Still open:** the entry's title symptom. `ALTER PAGE … SET Snippet = M.S ON <snippetcall>`
> passes `check --references` then fails at exec with
> `property "Snippet" not found (widget has no pluggable Object)`. Use `REPLACE`, without `Params`.
> Severity revised **Medium-High → Low**.

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
> `PROJECT-E/docs/gh-issues-ready/04-snippetcall-params-mandatory-but-invalid.md`.
> Lesson repeat: `DESCRIBE PAGE` never renders `Params:` for this widget kind, so it cannot detect
> the bug either way — grade snippet-call writes with `mx check`, not with a reader.

**Severity:** ~~Low~~ **Medium-High** (see correction above) — no in-mxcli workaround exists
**Reproducible:** Yes, consistently
**Confirmed:** Mendix 11.13.0, mxcli v0.16.0 **and v0.17.0**, 2026-08-07 / re-tested 2026-08-11, PROJECT-E
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

Verified on `PLM.PLM_GraphAgentChat` (`mxcli bson dump -p <project>.mpr --type page --object
"PLM.PLM_GraphAgentChat"`): the resulting `Forms$SnippetCall` object has a
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

**Discovered:** 2026-08-07, PROJECT-E, Batch 5 item 3 (D-UI1) of the audit
remediation — `PLM.PLM_GraphAgentChat`'s `snippetCall1` re-target.

---

## BUG-63: `write-lint-rules.md` documents API values that do not exist — every `action_type` example is wrong, and `source_type` case is wrong — so rules written from the guide silently match nothing

> **CONFIRMED STILL OPEN on v0.20.0 — verified 2026-08-31 by inspection: same fictional `action_type` row, now at line 318 of the directory-shaped `write-lint-rules/SKILL.md`.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

> ### ⚠️ CONFIRMED STILL OPEN on mxcli v0.18.0 — verified 2026-08-20
>
> Verified by direct inspection of the skill shipped in the v0.18.0 binary
> (`.claude/skills/mendix/write-lint-rules.md`): line 313 still gives
> `` `"CreateChangeAction"`, `"CommitAction"`, `"ShowFormAction"` `` as the `action_type` examples,
> and line 359 still gives `source_type` as lowercase `` `"microflow"`, `"page"` ``. Unchanged.
> v0.18.0's "every `mxcli syntax` example is now held to actually parsing" work covers the
> **syntax registry**, not this generated skill file — a different surface.

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

**RESOLVED (FIXED in v0.20.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-65: *(mis-filed — a toolkit bug, not an mxcli bug)* `gate-check.sh` could not discover a second, parallel decision register — **RESOLVED 2026-08-20**

> ### ⚠️ RE-FILED AND CLOSED — reassessed 2026-08-20
>
> **This entry never belonged in `mxcli-bugs.md`.** It reports a defect in this repo's own
> `bin/gate-check.sh`, not in mxcli. It is kept here as a stub rather than deleted so the
> BUG-65 number stays resolvable; the fix itself is in this repo's git history, not upstream.
>
> **Its headline claim — "can't gate-check the second track at all" — was already false when
> retested.** `bin/gate-check.sh:224-244` implements exactly the override the entry asked for
> (documented at :192-193): `GATE_REGISTER=<file>` selects a register explicitly and wins over
> any inference, and a bad one fails loudly (`Error: selected decision register does not exist:
> …`, exit 2). The persistent form is the `CLAUDE.local.md` "## Wiring | Decision register |" row.
>
> **The dangerous half did survive, and is now fixed.** The discovery glob at :209 listed only
> `"$PROJECT_DIR/PROJECT.md"` and `"$PROJECT_DIR"/analysis/*/PROJECT.md`, so a sibling
> `PROJECT-<track>.md` was never a *candidate*: with both registers present and no override,
> `REG_COUNT` stayed 1, `REG_DIFFER` stayed 0, the existing ambiguity path (:258) never fired,
> and the run graded the primary track **in silence** — precisely the wrong-register read the
> entry described. Fixed 2026-08-20 by adding `"$PROJECT_DIR"/PROJECT-*.md` to that glob, which
> reuses the ambiguity machinery already present: both candidates are named, both remedies are
> printed, register-dependent gates degrade to "cannot evaluate", nothing is blocked.
>
> Verified against a two-register fixture (`PROJECT.md` + a sibling track register): before the
> change, a no-override run printed no register warning at all; after, it prints
> `⚠ 2 differing decision registers`, names both, and exits 0.

### Original report (2026-08-12, a multi-track conversion project)

A project directory was running two parallel conversion tracks against the same root — the
original track in `PROJECT.md` and a second, deliberately-separate track for a newly shared
source corpus in `PROJECT-<track>.md`. Stage 1 for the second track completed and needed a
Stage 2 validation gate. `bin/gate-check.sh <project-dir> <stage>` had no flag or convention
for pointing at a non-default register, so running it as-is would silently validate against the
*other* track's decisions and artifacts rather than failing loudly.

**Workaround at the time (no longer needed):** self-attest the stage by hand and log the
self-attestation in the track's own register, as for other unattested-mode stages.

### Related

Same "tool assumes a single project shape and fails silently rather than loudly" class as
[[BUG-60]] — a structural assumption baked into a tool that doesn't hold for a valid project
layout, with no detection for the mismatch.

**Discovered:** 2026-08-12, a multi-track conversion project, Stage 1→2 gate.
**Reproducible:** was yes, deterministically. **Fixed:** 2026-08-20 in this repo.

## BUG-66: `ALTER ENTITY ... ADD ATTRIBUTE "X": autocreateddate;` silently no-ops — no error, no confirmation line, no attribute added

**RESOLVED (FIXED in ≤v0.20.0 — plus new MDL022 warning on a name mismatch) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-67: `CREATE SNIPPET ... (Params: { $X: String })` — a primitive-typed snippet parameter, documented in `mxcli syntax snippet.create`'s own example, fails at exec time with "entity not found"

> **CONFIRMED STILL OPEN on v0.20.0 — verified 2026-08-31: `Params: { $X: String }` still fails at exec with `entity not found: String`.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Sighted:** PROJECT-A, main build track Stage 5 Phase 11, script 56 (2026-08-12).

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

**Workaround used in PROJECT-A:** introduced a small non-persistent "parameter holder" entity
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

**Sighted:** PROJECT-A, main build track Stage 5 Phase 11, script 56 (2026-08-12).

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

**Workaround used in PROJECT-A:** don't reference the system/generalized attribute in the snippet
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

**RESOLVED (FIXED in ≤v0.20.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-70: A widget-level `action: show_page Page(Param: value, ...)` action property unconditionally drops ALL params — not just in the `create_object ... then show_page(...)` chained form previously logged; this is a general defect in the plain, non-chained widget-action form too

> **CONFIRMED STILL OPEN on v0.20.0 — verified 2026-08-31. v0.19's MDL-PAGEARG01 refusal does NOT cover a page-level button in CREATE PAGE: args are silently rebound to `$currentObject`, CE1571 per param + CE0117 at build. See also BUG-95.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Sighted:** PROJECT-A, main build track Stage 5 Phase 11, script 56d gate-check follow-up (2026-08-12).
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

**Decision applied in PROJECT-A:** `Common.SNIPPET_Remarks`'s `btnEditRemark` needs its own
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

**RESOLVED (FIXED in v0.19.0, #891 — bare column name now refused, `grid.column` form replaces in place) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-72: `mxcli --mcp exec` fails on ANY `CREATE MICROFLOW` statement — wrong ModelSDK property shape for the flow's return type and action nodes

**Sighted:** PROJECT-A, main build track Stage 5 Phase 12, script 57b (2026-08-12).

**Symptom:** `./mxcli --mcp http://localhost/mcp --mcp-dial localhost:<port> exec <file.mdl> -p
PROJECT-A.mpr` (Studio Pro running, MCP session live, correct port confirmed via a working
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

**Workaround used in PROJECT-A:** abandoned mxcli's `--mcp exec` wrapper entirely for this write.
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

> **CONFIRMED STILL OPEN on v0.20.0 — verified 2026-08-31: `raise error` in a main flow (inside IF) still builds to CE0710 on native mxbuild 11.13.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Project:** PROJECT-F. **mxcli version:** same pinned build used for BUG-59 through BUG-72 (not
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

**Workaround used in PROJECT-F:** stopped using `raise error;` in the main flow entirely. Added a
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

**RESOLVED (FIXED in ≤v0.20.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-75: a quoted attribute path used as a call-microflow argument value keeps its literal quotes in the compiled expression, causing native mxbuild CE0117 — invisible to `mxcli check`/`describe microflow`

> **PARTIALLY RESOLVED in ≤v0.20.0 — verified 2026-08-31 for the call-argument form: `"P" = $Item/"StatusCode"` now builds at 0 errors. The BUG-77 create/change extension was not separately retested.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Project:** PROJECT-F, script 02 (CheckSystemStatus). **mxcli version:** same pinned build used for
BUG-70 through BUG-74.

**Symptom:** a call-microflow argument whose value is a quoted member-access expression —
`"Param" = $Var/"Attribute"` — round-trips cleanly through `mxcli check --references` and
`describe microflow` (both show it as valid, and `describe microflow` even prints it back with the
quotes intact as if that were normal MDL). But the quotes are NOT stripped when this specific
expression shape is compiled into the actual flow-graph node: the literal string `$Var/"Attribute"`
(quote characters and all) lands in the call activity's argument expression, which is not valid
Mendix expression syntax (member access does not take a quoted attribute name — quotes denote a
string literal). Native mxbuild fails with `CE0117 "Error(s) in expression."` pointing at the call
activity. `mxcli check` never sees this because its reference/syntax validation does not compile
expressions to Mendix's actual expression grammar.

**Scope — confirmed NOT a general quoting problem:** the exact same quoted path
(`$Item/"StatusCode"`) used as a *create*/*change* statement's attribute value, or on the
right-hand side of a `set`/`if` condition, compiles fine — `describe microflow` shows the quotes
correctly stripped there. The defect is narrow: quoted member-access specifically as a
call-microflow **argument value**. Two independent repros in one build unit:
`"StatusCode" = $Item/"StatusCode"` (call to `SUB_EvaluateAvailability`) and
`"CallingApplication" = $Request/"CallingApplication"` (call to `GET_BR_ChekedSystemsApp`) — both
fixed by dropping the quotes on the attribute segment: `$Item/StatusCode`, `$Request/CallingApplication`.

**Workaround used in PROJECT-F:** when passing a member-access expression (`$Var/Attribute`) as a
call-microflow argument value, do not quote the attribute segment, even though this project's
general convention (CLAUDE.md) is to always quote identifiers. This is a second, narrower exception
to that convention, alongside the existing `textfilter (attributes: [...])` exception from the
BUG-41 refinement (2026-08-13 note in `archive-resolved-2026-08-06.md`) — that one is about a
*list of quoted 3-part identifiers*, this one is about a *quoted attribute segment inside a
member-access expression used as a call argument*. Different syntax position, same underlying
class of bug: mxcli's quote-stripping pass does not cover every place a quoted identifier can
legally appear in MDL.

**Detection:** only native `mx check` (or `mxbuild`) catches this — the BUG-60 rsync-scratch-copy
workaround is required to run it on Darwin. `mxcli check --references` and `describe microflow`
both give false confidence that the script is correct.

**Not yet isolated** in mxcli's Go source — not traced to the specific quote-stripping function
that misses this expression position. Whether it's limited to `call microflow`/`call nanoflow`
argument values specifically, or extends to other statement-argument positions not yet tried
(e.g. `call javascript action` params, `import from mapping` inputs), is unconfirmed — treat any
quoted member-access expression passed as a value into a call-style statement as suspect until
proven otherwise, and verify with native `mx check`, not `mxcli check`.

**Related:** same general family as BUG-41 (quoting round-trips through `mxcli check`/`describe`
but silently breaks native mxbuild) — that one was about a list of quoted identifiers in
`textfilter (attributes: [...])`, this one is about a quoted identifier inside a member-access
expression in a call argument. Both are reminders that "always quote identifiers" (this project's
default) has real, narrow exceptions that only a native `mx check` surfaces.

### Extension (confirmed 2026-08-20): the defect is general to any argument-list value and to page expression strings, not just call-microflow arguments

Well-evidenced, ready to file. Found on a second project while debugging a page-building script:

1. **`create (...)` argument lists**, not just `call microflow (...)` ones. `$Var/"Attribute"`
   as a value inside `create Module.Entity ("Attr" = $Var/"Other")` hits the identical CE0117.
2. **Quoted enum literals as argument values**, in either position: `"Module"."ENUM_X"."Value"`
   used as a call-microflow argument value or a create argument value also keeps literal quotes
   and fails the same way.
3. **The "safe precedent" trap:** quoted enum literals had been assumed universally safe because
   they'd been seen working cleanly elsewhere — but every one of those clean sightings was inside
   a call-microflow **parameter declaration list** (`$P: Enumeration("Module"."ENUM_X")`), never
   an **argument value**. Declaration-position quoting and argument-value-position quoting are
   different code paths in mxcli's compiler; one is safe, the other isn't. Don't generalize
   "safe" from one syntactic position to another that merely looks similar.

**Revised general rule:** inside any argument-list VALUE (call-microflow args or create args),
never use a quoted qualified path — not for member access, not for enum literals. Use the fully
unquoted dotted form: `Module.Entity.Attribute`, `Module.ENUM_X.Value`, `$Var/Attribute`. Quoting
stays necessary (and safe) for: DDL identifiers, `set`/`declare` RHS, `if` conditions,
`retrieve ... where` clauses, and call-microflow *parameter declarations*.

**Confirmed reproduction (positions 1–2):**
1. Create any persistent entity `Mod.Foo` with a String attribute `Bar` and an enumeration
   `Mod.ENUM_X` with at least one value.
2. Write a microflow containing either `$Item = create Mod.Foo ("Bar" = $Other/"Bar");` or
   `$Result = call microflow Mod.SUB_Do ("Bar" = $Other/"Bar");` (substitute
   `"Mod"."ENUM_X"."SomeValue"` for the quoted member-access to hit variant 2).
3. `mxcli check --references` → 0 errors. `mxcli exec` → succeeds, `describe microflow`
   round-trips the quotes without complaint.
4. Native check (`mxcli docker build`, or `mx check` with the matching `--mxbuild-path`) →
   **fails with CE0117 "Error(s) in expression"** on the exact activity.
5. Fix: replace `$Other/"Bar"` with `$Other/Bar` (or the enum path with `Mod.ENUM_X.SomeValue`)
   and re-run step 4 → 0 errors.

**A third position — page-level dynamic-class expression strings:** `DynamicClasses`/
`DynamicCellClass` properties on page widgets (dataview containers, DATAGRID columns) take an
expression string, and the same quoted-member-access / quoted-enum-path forms inside that string
trigger the identical CE0117 at native `mxbuild`, invisible to `mxcli check --references` in
exactly the same way:

```mdl
alter page Mod.Foo_Overview {
  SET DynamicCellClass = 'if ($currentObject/"BusState" = "Mod"."ENUM_BusState"."Error") then '
    + '"danger" else "plain" endif' ON "col1";
}
```

`mxcli check --references`: 0 errors. `mxcli exec`: succeeds (note: this exact `ALTER PAGE SET
DynamicCellClass` form fails for a *different* reason first on `DynamicCellClass` specifically —
see BUG-91 — so this quoting repro was actually confirmed while fixing pages via `create or
replace page` instead). Native `mx check`/`docker build`: **CE0117** on the page's dynamic-class
expression. Fix: same as always — `$currentObject/BusState` and `Mod.ENUM_BusState.Error`, fully
unquoted dotted form, no quotes anywhere in the expression string.

**Conclusion:** the defect is general to **any** expression-string compilation path in mxcli's
codegen, not specific to call/create argument lists — treat every expression string (page dynamic
classes, validation conditions, anywhere else a raw expression is embedded as a string literal) as
suspect until proven otherwise with a native build, not just `mxcli check`.

**Diagnostic method:** `mxcli check --references` and `describe microflow`/`describe page` cannot
detect this class of bug at all — only native `mx check` (via `--mxbuild-path "<Studio Pro
app>/Contents" --no-update-widgets`) surfaces it. To isolate which of several candidate fixes
actually resolves a given CE0117, use a scratch copy (`rsync -a --exclude='.git' <project>/
/tmp/<project>-scratch/`) and iterate `mxcli exec` + native `mx check` against the scratch `.mpr`
before touching the live one.

## BUG-76: `DECISION` activities in a native `WORKFLOW` are unconditionally storage-corrupted — mxcli writes the outcome label as a raw string into a field that must be a real `EnumerationValueIdentifier`, on every DECISION regardless of the underlying expression's type

> **CONFIRMED STILL OPEN on v0.20.0 — CRITICAL, verified 2026-08-31 with the byte-exact original signature: `StorageLoadException … The text 'OutcomeA' is not a valid EnumerationValueIdentifier`, project unloadable by mxbuild. Keep the STOP rule: no DECISION activities in CREATE WORKFLOW via mxcli.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Project:** PROJECT-A, Phase 15 (Approval native Workflow build), script 65
(`Approval.ApprovalWorkflow`). **mxcli version:** v0.17.0 (`2026-08-10T05:12:17Z`).

**Symptom:** a `.mpr` containing one or more `DECISION` activities inside a `CREATE WORKFLOW` (or
`CREATE OR MODIFY WORKFLOW`) round-trips cleanly through every mxcli-native validation path —
`mxcli check --references`, `DESCRIBE WORKFLOW`, `DESCRIBE MICROFLOW` — all report success. But the
project **fails to load at all** in real Mendix tooling (Studio Pro, native `mxbuild`, and
`mxcli docker check`, which shells out to the same native loader). The failure is a hard
`Mendix.Modeler.Storage.StorageLoadException` thrown before any check/build logic even runs:

```
ERROR: Mendix.Modeler.Storage.StorageLoadException: One or more invalid values were detected while loading the project: Mendix.Modeler.Projects.Project:
 - Enumeration value condition outcome in  has an invalid value '' for property Value. The text 'Reject' is not a valid EnumerationValueIdentifier.
 - Enumeration value condition outcome in  has an invalid value '' for property Value. The text 'Skip' is not a valid EnumerationValueIdentifier.
 - Enumeration value condition outcome in  has an invalid value '' for property Value. The text 'Applies' is not a valid EnumerationValueIdentifier.
 - Enumeration value condition outcome in  has an invalid value '' for property Value. The text 'Continue' is not a valid EnumerationValueIdentifier.
```

One error line per `DECISION` outcome in the project. The flagged text is always the outcome's own
label — i.e. mxcli is writing the literal outcome name (`'Reject'`, `'Continue'`, `'Applies'`,
`'Skip'`) straight into a storage field (`ConditionOutcome.Value`, per the stack trace) that Mendix's
loader requires to deserialize as an `EnumerationValueIdentifier` object, not a bare string. This
went undetected in this project from script 65's execution (2026-08-13) through script 66's
execution and gate-pass, silently blocking Studio Pro and any real build the entire time — surfaced
only because the user reported "mpr error" and asked whether Studio Pro had been tried.

**Scope — confirmed to be unconditional, not tied to enum-valued expressions:** the four corrupted
outcomes in this project came from two different `DECISION` activities with genuinely different
expression shapes:
- `WFST040`'s decision, whose condition expression reads an actual enumeration attribute
  (`SamplingDecision`), outcomes `'Continue'` / `'Reject'`.
- `CoarseClassification`'s decision, whose condition expression reads a plain **String** attribute
  (no enumeration involved at all), outcomes `'Applies'` / `'Skip'`.

Both corrupt identically. This rules out any theory that the bug is specific to enum-typed decision
expressions (e.g. "outcome label happens to not match a real enum value name") — it is a systemic,
unconditional defect in the DECISION-outcome serializer that fires for every DECISION regardless of
what the expression evaluates over.

**Minimal reproduction** (confirmed against a full sandbox copy of the live project — the `.mpr`
v2 store keys its `mprcontents/` to the original filename, so the copy must keep the exact same
filename in its own directory, not just be renamed/copied to `/tmp`):

```sql
create workflow Approval."TestDecisionWF"
  parameter $Context: Approval."ApprovalRun"
begin
  decision '1 = 1'
    outcomes 'OutcomeA' -> { }
             'OutcomeB' -> { };
end workflow;
/
```

- `mxcli check --references` → clean, "All references valid".
- `mxcli exec` → "Created workflow: Approval.TestDecisionWF", no errors.
- `mxcli docker check` (native loader) → the pre-existing 4 errors become **6**: the same 4 plus
  two new ones for `'OutcomeA'` and `'OutcomeB'` — brand-new, never-before-used outcome labels,
  added to a brand-new decision on a trivial literal boolean expression (`1 = 1`, no attribute or
  enumeration involved at all). This confirms the defect is universal to `DECISION` activity
  codegen, not sensitive to naming, expression type, or workflow context — there is no MDL-only
  workaround (naming the outcomes differently, changing the expression shape, etc. all corrupt
  identically).

**Detection gap:** identical to BUG-75/BUG-41/BUG-70/BUG-71 in kind but worse in degree — this one
is not just invisible to `mxcli check`, it is invisible to *every* mxcli-native command including
`mxcli exec` itself (which reports success) and `DESCRIBE WORKFLOW`/`DESCRIBE MICROFLOW` (which
print the outcomes back correctly, with no indication of the underlying storage-type mismatch).
Only a real native `mxbuild`/Studio Pro load — via `mxcli docker check` or an actual Studio Pro
open — surfaces it, and by the time it does, the corruption may already be several scripts and
commits deep (it was, here: scripts 65 and 66 both executed and gate-passed on top of it before
discovery).

**Workaround used in PROJECT-A:** do not use `DECISION` activities in mxcli-authored `WORKFLOW`
definitions at all, for any expression type, until this is fixed upstream. Build the native
workflow with the decision points left out entirely (a documented gap), then add the `DECISION`
gateways manually in Studio Pro after the fact. This matches prior precedent from the PROJECT-E project's
own DECISION+enum issues (see BUG-WF03 below) of avoiding mxcli-authored DECISION gateways in favor
of a manual Studio Pro add.

**Related:** distinct from BUG-WF03 (CE0117 from lowercase `AND`/`!=` operator casing inside
DECISION expressions) — that one is a parse/casing defect caught by mxbuild's expression compiler;
this one is a storage-serialization defect that native mxbuild's *loader* rejects before compilation
even starts, and is unconditional rather than casing-dependent. Also notable: `mxcli syntax workflow
--json`'s own documented DECISION grammar (`DECISION ['<caption>'] OUTCOMES '<outcome>' { ... }
...;`, no arrow) is independently wrong/incomplete — the real required grammar needs
`DECISION '<boolean-expression>' OUTCOMES 'name' -> { } ...;` (arrow required). `mxcli -c "HELP
DECISION"` returns no help text at all. Neither the wrong docs nor the missing help contributed to
this specific corruption (the corruption reproduces with correct arrow syntax too), but both should
be fixed alongside it.

## BUG-77: BUG-75's "create/change attribute values are safe" scope claim is wrong — quoted attribute segments (`$Var/"Attr"`) DO cause CE0117 in create/change statements too, just not consistently

**Project:** PROJECT-A, script 64 (`Approval.ACT_ApprovalRun_CreateVersion`, part of the same
Phase 15 Approval-workflow rebuild as BUG-76). **mxcli version:** v0.17.0 (`2026-08-10T05:12:17Z`).

**Symptom:** BUG-75 asserted, based on two repros in a different project, that a quoted
member-access expression (`$Var/"Attribute"`) used as a **create/change statement's attribute
value** "compiles fine" and is only broken as a call-microflow argument value. This project
disproves that as a general claim. `ACT_ApprovalRun_CreateVersion` had three activities using the
identical `$Var/"Attribute"` shape purely as create/change attribute values:

1. A `create Approval.ApprovalRun (...)` with 14 members, each value a quoted nav path like
   `"ArticleNumber" = $ApprovalRun/"ArticleNumber"` — **passed** native `mx check` (0 errors on
   this activity).
2. A `change $NewStation (...)` with 11 members, same shape (`"IsNotApplicable" =
   $OldStation/"IsNotApplicable"`, etc.) — **failed** with `CE0117 "Error(s) in expression."`.
3. A `create Common.Attachment (...)` with 3 members, same shape (`"Category" =
   $OldAttachment/"Category"`, etc.) — **failed** with `CE0117`.

All three activities used the exact same MDL shape (quoted attribute segment on the RHS of a
member-access expression, as a create/change value). Only two of three failed. The only fix that
resolved both failures — unquoting every attribute segment across all three activities
(`$Var/Attribute` everywhere, including the one that had already been passing) — took the whole
microflow from 2 `CE0117` errors to 0 with no other change. `mxcli check --references` never
flagged any of this (same detection gap as BUG-75/BUG-29).

**What this means:** the trigger is NOT "create/change is always safe, call-microflow-argument is
always broken" as BUG-75 concluded. Something else determines whether a given quoted `$Var/"Attr"`
in a create/change value actually corrupts the compiled expression — number of members in the same
statement, attribute type, entity generalization (the failing Attachment create was on an entity
`extends System.FileDocument`; the passing ApprovalRun create was on a plain persistent entity —
untested whether generalization is the actual variable), or something else not yet isolated. Given
two different projects have now each found a context they believed was "safe" and been wrong, **do
not trust ANY context as safe for a quoted attribute segment on the right-hand side of a
member-access expression** — treat `$Var/"Attr"` as unconditionally suspect in every position
(create, change, call-microflow argument, decision condition, retrieve WHERE, anything) and default
to `$Var/Attr` (unquoted attribute segment) everywhere, verified with a real `mx check`, not
`mxcli check`.

**Recommendation:** supersede BUG-75's narrow "only call-microflow arguments" framing and BUG-29's
"only nav expressions" framing with a single blanket rule in `learned-mdl-preflight.md`: attribute
segments in `$Var/Attr`-style member-access expressions are NEVER quoted, full stop, regardless of
statement context — this is the one confirmed safe exception to this project's general "always
quote identifiers" convention, and the boundary of when quoting silently corrupts vs. silently
no-ops is not worth memorizing since it isn't reliable.

**Related:** same underlying quote-stripping gap as BUG-29 and BUG-75; this entry narrows/corrects
BUG-75's scope claim rather than describing a new mechanism.

## BUG-78: CE0161 on a reference-set-to-string-literal retrieve WHERE clause (`where [Assoc = 'Value']`) — fixed by comparing the association to a retrieved object instead

**Project:** PROJECT-A, script 64 (`Approval.ACT_ApprovalWorkflow_TargetEngineering`, same Phase
15 rebuild). **mxcli version:** v0.17.0.

**Symptom:** filtering `System.User` by role membership via a reference-set association compared
directly to a role-name string literal fails `mx check` with `CE0161 "Error(s) in XPath
constraint."`, in every one of three tried forms (`mxcli check --references` passes all three
cleanly — same detection gap as every other entry in this file):

```mdl
retrieve $Users from System.User where [UserRoles/Name = 'Engineering'];        -- CE0161
retrieve $Users from System.User where [UserRoles = 'Engineering'];             -- CE0161
retrieve $Users from System.User where [System.UserRoles = 'Engineering'];      -- CE0161
```

**Fix:** retrieve the role object first with a plain single-attribute comparison (the
already-proven-safe form), then compare the reference-set association directly to that **object**,
not a string:

```mdl
retrieve $Role from System.UserRole where "Name" = 'Engineering' limit 1;
retrieve $Users from System.User where System.UserRoles = $Role;
```

0 errors. This is a real, if narrow, syntax constraint (not merely an mxcli detection gap like
BUG-29/75/77 above): a reference-set/many-to-many association in an XPath WHERE clause must be
compared to an object reference, not to a bare string identifier — mxcli's grammar accepts the
string-literal form without complaint, but mxbuild's XPath constraint compiler rejects it.

**Related:** distinct from BUG-45 (`id=` lookups) — this is specifically about comparing a
reference-set association to a scalar in a bracket-predicate retrieve, not an ID lookup.

## BUG-79: `GRANT`/`REVOKE` cannot target any `System`-module entity — no local domain-model file to write into

**RESOLVED (BY-DESIGN — the limitation is Mendix's; clean explanatory refusal since v0.20.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-80: no MDL/mxcli syntax exists to start a native Workflow *instance* from a microflow

**RESOLVED (feature shipped in ≤v0.20.0: `call workflow Mod.WF ($Ctx);` microflow activity) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-81: `create or modify microflow` corrupts attribute-identifier serialization in existing `change $Object (...)` activities — the .mpr then fails to load with fabricated `AttributeIdentifier` errors

**NOT REPRODUCED on v0.20.0 (minimal shape, independent cold load clean; likely the v0.19/v0.20 canon.TransplantIDs rework) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-82: neither `create or modify entity` (full redeclare) nor `ALTER ENTITY MODIFY ATTRIBUTE` can clear an existing "not null error" validation rule — silent no-op with a misleading success message

**RESOLVED (FIXED in ≤v0.20.0 — the working removal spelling is `MODIFY ATTRIBUTE … NULLABLE`; redeclare-without-constraint now deliberately preserves) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-83: reverse cross-module association traversal is silently mis-qualified — the target entity is inserted regardless of direction, leaving a dangling four-step path

**Severity:** Low (the reverse form appears to be invalid Mendix anyway) — but the *silence* is the defect
**mxcli version:** v0.18.0
**Mendix version:** 11.12.0, MPR v2
**Discovered:** 2026-08-20, purpose-built cross-module scratch project, while retesting [[BUG-33]]
**Reproducible:** yes, deterministic

v0.18.0 correctly normalises a *forward* cross-module traversal on write (that is the BUG-33 fix).
The same normaliser runs unconditionally on the reverse direction and inserts the association's
**target** entity rather than the one the step actually lands on:

```
input   $Supplier/MyFirstModule.Item_Supplier/Item/Code
stored  $Supplier/MyFirstModule.Item_Supplier/RouteShowcase.Supplier/Item/Code
```

The original `Item` step is left dangling, producing a four-step path. `mxcli check` and `mxcli exec`
are both silent; the failure surfaces only at build.

The hand-qualified reverse form also fails `CE0117`, which suggests reverse traversal of a Reference
association may not be valid Mendix regardless — so the practical impact is low. The path mangling
without a warning is real either way: the correct behaviour is to reject the reverse form at MDL
time, not to rewrite it into something else.

**Workaround:** traverse forward, or retrieve by association in a separate activity.

---

## BUG-84: `ALTER PAGE … SET DataSource = DATABASE Module.Entity` on a DataView silently wipes the datasource and reports success

> **CONFIRMED STILL OPEN on v0.20.0 — verified 2026-08-31: `SET DataSource = DATABASE Mod.Entity ON <dataview>` (braced ALTER PAGE form) still reports success and wipes the datasource; CE7007 downstream.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** High — silent success, corrupted widget, surfaces only at check time
**mxcli version:** v0.18.0
**Mendix version:** 11.12.0
**Discovered:** 2026-08-20, scratch page project, while retesting [[BUG-11]]
**Reproducible:** yes, deterministic

```
ALTER PAGE Mod.MyPage SET DataSource = DATABASE Mod.Customer ON dvCust;
→ "Altered page Mod.MyPage"        (no error, exit 0)
```

The DataView is left with **no DataSource at all** (`dataview dvCust {` with the property gone).
The only downstream signal is `[CE7007] Selected value is not valid for entity 'Customer'` at
check time.

A DataView cannot legitimately take a database datasource. mxcli already rejects the *association*
form at MDL time with an actionable error naming `REPLACE` as the supported route — the database
form should be rejected the same way, rather than half-applied.

**Workaround:** use `REPLACE`, or set a microflow/page-parameter datasource. Never issue the
`DATABASE` form against a DataView.

---

## BUG-85: `ALTER ENTITY … DROP ATTRIBUTE` never deletes the attribute's validation rule — orphaned rule (`CE1613`), resurrected constraints, and a total silent no-op on a single-attribute entity

**RESOLVED (FIXED in v0.19.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-86: MDL044's new write barrier is microflow-only — the identical expression in a `create nanoflow` passes `check`, is written, and fails the build with `CE0117`

> **PARTIALLY RESOLVED / STILL OPEN on v0.20.0 — verified 2026-08-31: `currentDeviceType()` in a CREATE NANOFLOW still passes check+exec and fails the build CE0117 (isolated by drop-and-recheck). The `[%CurrentDeviceType%]` token form now builds CLEAN in a nanoflow on 11.13, so the remediation note stands corrected.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** High — `check` does not even lint the nanoflow case, so this is worse than the
microflow situation was before the barrier landed
**mxcli version:** v0.18.0
**Mendix version:** 11.12.0
**Discovered:** 2026-08-20, while retesting [[BUG-30]]
**Reproducible:** yes, deterministic

`validateMicroflowRules` (`mdl/executor/validate.go:1081`) takes `*ast.CreateMicroflowStmt` and is
called from exactly one site, `cmd_microflows_create.go:50`. `execCreateNanoflow`
(`cmd_nanoflows_create.go:18`) never calls it. So for `create nanoflow`:

1. `currentDeviceType()` → `check` **passes**, `exec` **writes**, build fails `CE0117` — the
   original BUG-30 symptom, one statement kind over.
2. `[%CurrentDeviceType%]` → same, `CE0117`. This matters because BUG-30's own remediation says
   "only the bracket-percent token form works" — true for **page conditional visibility**, false
   inside a **nanoflow expression**. Anyone applying the logged workaround in a flow context swaps
   one `CE0117` for another.

**Fix wanted:** call the same rule set from `execCreateNanoflow` (and from `check`'s nanoflow path).

**Workaround:** compute the device type outside the nanoflow, or gate on a page conditional
visibility expression where the token form is genuinely valid.

---

## BUG-87: `DESCRIBE JAVA ACTION` drops the type-parameter name, printing `entity <>` — the declaration does not round-trip

> **CONFIRMED STILL OPEN on v0.20.0 — verified 2026-08-31: DESCRIBE JAVA ACTION still prints `entity <>` for a named type parameter; does not round-trip.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** Low (cosmetic, but breaks read-back-and-rewrite workflows)
**mxcli version:** v0.18.0 **and v0.17.0**
**Mendix version:** 11.12.0
**Discovered:** 2026-08-20, while retesting [[BUG-61]]
**Reproducible:** yes, deterministic

A parameter declared `ContextObject: ENTITY <pEntity> not null` is printed by `DESCRIBE JAVA ACTION`
as `ContextObject: entity <>` — the type-parameter name `pEntity` is lost. Feeding the described
form back to mxcli does not reconstruct the original declaration. Orthogonal to the `CE0115`
MicroflowType defect that BUG-61 tracked (that half is fixed in v0.18.0).

**Related trap worth folding into the skills:** declaring a type-parameter-filling parameter
*without* `not null` yields `[CE0163] Parameter 'X' fills in a type parameter and cannot be
optional.` mxcli accepts the optional declaration silently; only a real build catches it.

---

## BUG-88: v0.17.0 `--mcp exec … ALTER PAGE SET Title` reports success while writing a truncated page body back — silent whole-page destruction

**Severity:** Critical on v0.17.0 — silent, unrecoverable-in-place loss of a page's widget tree
**mxcli version:** v0.17.0. **Fixed in v0.18.0** (which sends `depth: 1000` when the server
advertises the argument, and otherwise *refuses* the read rather than writing a partial page).
**Mendix version:** Studio Pro 11.13
**Discovered:** 2026-08-20, replay of a live 11.13 server's captured `tools/list` and real page
bodies, while root-causing [[BUG-26]]
**Reproducible:** yes, deterministic against an 11.13 server

Studio Pro 11.13's `pg_read_page` defaults to `depth: 4`, collapsing a real page to
`{"widgets":[{"$Type":"Pages$Content","slot":"Main","widgets":["..."]}]}` — measured live,
read-only: **162 chars at default depth vs 18,356 at `depth: 1000`** on the same page. Because
`ALTER PAGE` is read-modify-**replace-whole-page**, v0.17.0 writes that truncated body straight
back:

```
v0.17.0  "Altered page …"   valuelen=176   sentinels=1   value has widgets:["..."]
v0.18.0  "Altered page …"   valuelen=20181 sentinels=0   all 52 widgets preserved
```

On an anchor-based insert v0.17.0 at least errors (`widget "buttonsCard" not found`). On
`SET Title` there is no anchor lookup, so nothing fails — it reports success and destroys the page.

**Action for anyone still on v0.17.0:** do not use `--mcp exec ALTER PAGE` at all. Upgrade, or edit
in the Studio Pro GUI.

---

## BUG-89: v0.17.0 writes a DropdownFilter in attribute mode when association mode was asked for — silently, with a green build, producing a filter that does not filter

**Severity:** High on v0.17.0 — silent wrong-mode write, no error, clean build
**mxcli version:** v0.17.0. **Fixed in v0.18.0.**
**Mendix version:** 11.12.0
**Discovered:** 2026-08-20, while retesting [[BUG-38]]
**Reproducible:** yes, deterministic

Given an identical script asking for a reference-mode DropdownFilter, v0.18.0 writes the four
properties mxbuild actually reads (`baseType = "ref"`, `refEntity` → `IndirectEntityRef` with the
association step, `refOptions`, `refCaption`). v0.17.0 writes the widget but **stays in attribute
mode**: `baseType` absent (so `attrChoice="auto"` stands), no `IndirectEntityRef`, no association
step, no `refCaption` — only a stray `refOptions` XPathSource survives. The result is a drop-down
that does not filter by the reference, authored with no error and a build reporting 0 errors.

**Documentation gap that makes this easy to hit:** association mode is entered **implicitly**, by
giving the filter a `DataSource:`. There is no explicit mode keyword. A `DROPDOWNFILTER` without a
`DataSource:` stays in attribute mode. This is discoverable only from
`sdk/widgets/definitions/dropdownfilter.def.json`; `mxcli syntax page widgets` says nothing about it.

**Cosmetic residue (v0.18.0):** `describe` emits the association under key `Attribute:` rather than
`Association:` for a ref-mode dropdown filter. It round-trips losslessly but reads misleadingly —
to an agent it looks like exactly the "association in an attribute-typed property" that mxcli now
refuses elsewhere.

---

## BUG-90: loop-variable association-path member access inlined into a `call microflow` parameter corrupts codegen

**RESOLVED (FIXED in ≤v0.20.0) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-91: `DynamicCellClass` (DATAGRID column property) can only be set at CREATE time — `ALTER PAGE SET` silently fails at exec

**RESOLVED (FIXED in ≤v0.20.0 — `SET DynamicCellClass … ON grid.col` now lands) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**

## BUG-92: `ALTER PAGE INSERT` silently no-ops against a wrong-but-plausible anchor, and drops the whole INSERT on an empty caption — both can leave invisible orphaned duplicate widgets

**Severity:** High — the actually-costly failure mode is not the no-op itself but that repeated
retries against it leave orphaned duplicate widgets invisible to `DESCRIBE PAGE`, which native
`mx check` then rejects
**Reproducible:** Yes, consistently (isolated via disposable scratch-file A/B testing)
**Mendix version:** 11.13.0

**Distinct from BUG-18/BUG-18's `ConditionalXSettings` blank-AttributeIdentifier corruption** —
this is an `ALTER PAGE INSERT` targeting/validation gap plus a storage-tree accumulation issue,
not a blank-AttributeIdentifier writer.

### Trap 1 — wrong-but-plausible target silently no-ops

`insert after dgCases.ApplicationCount` (a column whose derived name matched `describe page`'s own
printed output exactly) completed with `mxcli exec`'s normal "Altered page ..." success message
and **no error**, but added nothing — confirmed via `DESCRIBE PAGE` showing no new widget,
reproduced twice across two separate full-script executions. The *identical* `insert after`/
`insert before` statement targeting a different, working column (`dgCases.colOpen`) succeeded
immediately. Root cause not fully isolated — the working hypothesis is that `ApplicationCount` is
a plain attribute-bound column (`Attribute: ApplicationCount`, no nested widgets) while `colOpen`
is a `customContent` column with a nested `actionbutton`, and `INSERT AFTER/BEFORE` may require
the anchor to itself be a customContent-style column — untested against a plain attribute-bound
anchor elsewhere to confirm this generalizes.

### Trap 2 — an empty `caption: ''` on the new column silently drops the entire INSERT

Even after retargeting to the working anchor (`colOpen`), a column declared with `caption: ''`
(matching the column header's actual intended blank appearance) still silently inserted nothing —
no error, no widget. Giving the same column a real non-empty caption (matching `colOpen`'s own
precedent, which is non-empty for the same customContent-column reason, even though its rendered
header is expected to read as blank/icon-only) made the insert succeed immediately.

### Trap 3 — the actually-costly one: repeated debugging attempts do NOT cleanly no-op; they leave orphaned duplicate widgets invisible to `DESCRIBE PAGE`

After finally getting a real, visible INSERT to work (confirmed via a single `DESCRIBE PAGE` call
showing exactly one clean `column`/`actionbutton` pair), native `mx check` (NOT
`mxcli check --references`, NOT `mxcli exec`, NOT a single `DESCRIBE PAGE` call — all four were
silent) reported:

```
[error] [CE0495] "Duplicate name 'btnStartSigning'." at Action button 'btnStartSigning',
Action button 'btnStartSigning', Action button 'btnStartSigning', Action button 'btnStartSigning',
Action button 'btnStartSigning'
```

Five instances, matching the five `mxcli exec` attempts made against the same target widget name
across the Trap 1 → Trap 2 → working-version debugging sequence (two silent-per-`DESCRIBE`
"no-ops" against the wrong anchor, one silent-per-`DESCRIBE` "no-op" with the empty caption, and
two of the final working-caption version). **The lesson: what a single `DESCRIBE PAGE` call
reports as "nothing happened, safe to retry with a fix" is not reliable evidence that nothing was
written** — some or all of those apparent no-ops actually wrote a widget into a part of the page's
storage tree that `DESCRIBE PAGE`'s serializer does not walk/render, but that native mxbuild's
uniqueness check still sees and collides on.

### Workaround

If an `ALTER PAGE INSERT` against the same widget name has been retried more than once while
debugging Trap 1/Trap 2-style failures, do **not** trust a clean `DESCRIBE PAGE` as proof the page
is now duplicate-free. Rebuild the whole page via `create or replace page` with the full widget
tree written out literally (copied from the last known-good `DESCRIBE PAGE` output, plus the one
new widget). `create or replace` regenerates the entire tree from the literal definition, so it
cannot contain orphans — unlike `ALTER PAGE`, there is no accumulation risk. Confirmed via native
`mx check`: 0 errors after the rebuild, versus 5x CE0495 before it.

### Bonus false-positive noted along the way

`mxcli check --references` flagged the rebuilt page's pre-existing `col1`/`col2` layoutgrid column
names (reused identically across three separate `row`s, completely unchanged from the page's
already-live, already-passing-native-check state) as `"duplicate widget name 'col1' (used 3
times)"` / `'col2' (used 2 times)"`. This is a **false positive of the checker's own
`--references` validation** — native `mx check` has never flagged this pre-existing pattern,
meaning `column` names are actually scoped to their parent `row`, not page-wide, contrary to what
the checker's stricter duplicate-name rule assumes. Don't treat every `--references` "duplicate
widget name" report as ground truth for whether a page will actually fail native `mx check` —
cross-check against native `mx check` before treating it as blocking.

**Discovered:** 2026-08-14/15, PROJECT-I (a mock-API integration POC project, `PackageCase_Overview` datagrid).

---

## BUG-93: `ALTER PAGE REPLACE` of a `DATAGRID` column with `ShowContentAs: customContent` silently drops any nested `dropdownfilter` widget

**Severity:** High — passes every automated gate (`mxcli check --references`, `mxcli exec`, `mxcli docker check`) with no error, but the filter widget never lands in the model; the only way to catch it is a targeted `DESCRIBE PAGE` diff against sibling columns
**Reproducible:** Yes, consistently (isolated via disposable scratch-file A/B testing: a plain non-customContent column with only a `dropdownfilter` round-trips fine; the identical `dropdownfilter` becomes silently unreadable the moment its column also carries `ShowContentAs: customContent`, regardless of what else is in the column)
**Mendix version:** 11.13.0

### Symptom

`ALTER PAGE ... REPLACE <column>` on an existing customContent `DATAGRID` column (e.g. a
`RunStatus` pill column rendered via a nested `container`/`dynamictext`), adding a `dropdownfilter`
alongside the existing customContent widgets, completes cleanly:

- `mxcli check --references` — 0 errors
- `mxcli exec` — reports success, no error
- `mxcli docker check` (mxbuild gate) — 0 errors

But a follow-up `DESCRIBE PAGE` on the executed result shows the customContent pill container
intact, with **no `dropdownfilter` anywhere on the page**. This is a genuine silent drop, not a
`DESCRIBE`-emitter rendering gap — confirmed by cross-checking that pre-existing filters on
sibling, non-customContent columns (`fKind`, `fSequence`, `fCoarse` in the reproducing case) DO
render correctly in the same `DESCRIBE PAGE` output.

### Root cause (as isolated)

Not fully diagnosed at the BSON level, but narrowed via two throwaway scratch-file tests: a plain
column (no `ShowContentAs: customContent`) containing only a `dropdownfilter` writes and reads
back correctly every time. The same `dropdownfilter`, added to a column that also declares
`ShowContentAs: customContent`, is silently discarded on write — regardless of what other widgets
share the customContent column. This looks like an mxcli MDL-writer gap specific to the
customContent `DATAGRID` column type, distinct from the already-logged `dg2-grid-pattern.md`
"filtersPlaceholder"/pluggable-DG2 filter gaps — this is an MDL-native `DATAGRID` (v1-style)
customContent column, not a pluggable DG2 form.

### Workaround

Do not add a `dropdownfilter` inside an existing customContent column. Leave the customContent
column completely untouched (zero risk of the drop) and `INSERT AFTER` (or `BEFORE`) it a new
sibling column bound to the same attribute, whose only content is the `dropdownfilter`. Confirmed
via native `mx check`: 0 errors, and a follow-up `DESCRIBE PAGE` shows the new column's filter
intact alongside the original, unmodified customContent column. Tradeoff: the attribute's plain
enum-caption text now appears twice (once inside the original customContent rendering, once as
the new column's default cell text) — a minor, accepted visual duplication in exchange for not
risking the silent-drop path.

**Discovered:** 2026-08-20, a workflow-tracking project (`ProductNumberWorkflow.ProductNumberWorkflow_Overview`,
`dgRuns` datagrid, `RunStatus` pill column), rehearsed before execution per
`skills/learned-mdl-preflight.md`.

## BUG-94: `hasRole('Module.Role')` is not a valid Mendix expression-language function — MDL has no syntax to set a widget's module-role-scoped `Visible` condition

**Severity:** Medium — `mxcli check --references` passes clean (it doesn't validate expression-language function names, only references), so the failure is invisible until a real `mxbuild`/native `mx check` or Studio Pro open
**Reproducible:** Yes, consistently — every use of `hasRole(...)` in a `SET Visible = [...]` expression fails native `mx check` with `CE0117` ("Error(s) in expression")
**Mendix version:** 11.13.0

### Symptom

A script of the shape:

```
ALTER PAGE Module.Page {
  SET Visible = [hasRole('Module.SomeRole')] ON someTile;
};
```

writes and passes `mxcli check --references` cleanly (0 errors), and even passes a plain
`mxcli exec` against a live `.mpr` with no reported error — the write itself succeeds, because
`Visible` accepts an arbitrary expression string and mxcli's writer does not validate it as
Mendix expression syntax. Only a subsequent **native** `mx check`/mxbuild gate catches it:

```
CE0117: Error(s) in expression '[hasRole('Module.SomeRole')]'
```

`hasRole()` does not exist anywhere in the Mendix client/microflow expression grammar (no such
function in the documented expression library), is not present in any prior working MDL in this
project's history, and is not documented in any toolkit skill as a real construct — it appears to
be a plausible-sounding hallucinated function name, not a shorthand or deprecated alias.

### Reproduction

1. Write any `ALTER PAGE { SET Visible = [hasRole('Some.Role')] ON widgetName; }` script.
2. `mxcli check script.mdl -p Project.mpr --references` → passes, 0 errors.
3. `./mxcli exec script.mdl` (or `bin/exec.sh` if the project has one) → reports success, no error.
4. Run a **native** `mx check` (the real macOS/Windows/Linux Studio Pro `mx`/`mxbuild` binary
   matching the project's Mendix version, not just mxcli's own gate if it silently no-ops) →
   `CE0117` fires immediately.
5. Isolated via sandbox rehearsal (full project-tree copy in `/tmp`, native `mx check` on the
   sandbox) before ever touching the real `.mpr` — confirmed the failure is in the expression
   text itself, not a corruption/serialization issue (direct BSON inspection of the resulting
   `Forms$ConditionalVisibilitySettings` showed a well-formed document with the expression string
   correctly serialized verbatim — the document is valid, the *content* of the expression is not).

### Root cause

There is no MDL syntax today to populate `ConditionalVisibilitySettings.ModuleRoles` — the
first-class BSON field backing Studio Pro's actual "Visible for these module roles" checkbox
list on a widget. That field is a list of module-role references, not an expression. mxcli's
`SET Visible = [...]` only writes to the `Expression`-based visibility path (data-context boolean
expressions, e.g. `[$SomeDataViewEntity/BooleanAttr = true]`), which has no access to the current
user's roles as a first-class expression construct in this Mendix version. Someone reaching for
"visible only to role X" naturally guesses at a `hasRole()`-shaped function; it does not exist.

### Workaround

Role-scoped widget visibility must be done one of two ways:
1. **Studio Pro GUI or MCP `pg_patch_page`** — directly set `ConditionalVisibilitySettings.ModuleRoles`
   on the widget (the real, first-class mechanism). MDL cannot express this today.
2. **Data-context workaround, MDL-only** — add a non-persistent entity holding the current user's
   relevant roles as boolean attributes, retrieve/create one instance into a dataview on the page,
   and drive `Visible` off an `[$CurrentUserRoles/IsSomeRole = true]`-style expression instead.
   This is materially more design work than a one-line `SET Visible`, not a drop-in substitute.

**Discovered:** 2026-08-21, a client project (a Home/dashboard page, 4 tiles needing per-role
visibility per its own design wireframe), caught in sandbox rehearsal before ever touching
the real `.mpr`, per `skills/learned-mdl-preflight.md`.

## BUG-95: `show_page` action on a widget outside a `dataview` always binds an entity-typed argument to `$currentObject`, ignoring the variable named in the MDL

> **CONFIRMED STILL OPEN on v0.20.0 — verified 2026-08-31, same probe as BUG-70: page-level button args rebound to `$currentObject`, CE1571 + CE0117.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

### Symptom

Adding an `actionbutton` (outside any `dataview`, i.e. no `currentObject` in scope) with an
`Action: show_page Module.TargetPage(SomeEntityParam: $SomeVariable)` clause round-trips clean
through `mxcli check --references` and `mxcli exec` reports success with no error — but native
`mx check` / `docker check` then fails:

```
[CE1571] "No argument has been selected for parameter 'SomeEntityParam' and no default is
available."
```

Confirmed via `DESCRIBE PAGE` on the button after exec: the stored action's argument is
`$currentObject`, not the variable actually named in the MDL script — silently rewritten by
mxcli's writer at write time. Since the button lives outside a dataview, there is no
`currentObject` in scope, so the argument is genuinely unbound at runtime, hence CE1571.

### What was tried, and ruled out

1. `Action: show_page Module.Page(Param: $WorkflowRun)` (colon form) — round-trips to
   `$currentObject`.
2. `Action: show_page Module.Page($Param = $WorkflowRun)` (microflow-style `=` form, in case the
   two documented forms hit different codegen paths) — round-trips to `$currentObject` as well.
3. Re-`SET`ting the action directly via `ALTER PAGE ... SET action = ... ON btnName` (bypassing
   the `INSERT ... { }` path entirely, in case the bug was specific to insert-then-parse) — same
   result.

All three attempts validated clean against `.ai-context/skills/create-page.md` /
`alter-page.md`'s own documented `show_page` syntax (both `Param: value` and `Param = value`
forms are listed as accepted) — this rules out an MDL authoring mistake; the writer itself does
not thread the argument through for this specific widget/context combination.

### Root cause

mxcli's `show_page` action writer appears to special-case the entity-typed argument as
`$currentObject` whenever the action is attached outside a dataview context, rather than
resolving the variable expression the script actually specifies. This is a different code path
from BUG-56 (DataGrid2 *datasource* parameterized-microflow binding loss, resolved in v0.17.0) —
this is a `show_page` *action* argument binding on a plain, non-dataview action button.

### Workaround

None found via MDL. Either:
1. Place the target button inside a `dataview` scoped to the entity the target page needs (so
   `$currentObject` is the correct, in-scope binding) — only viable if the page's layout already
   has (or can acceptably gain) such a dataview.
2. Add the button via Studio Pro GUI or MCP `pg_patch_page` directly, then leave it alone —
   MDL cannot safely round-trip further edits to it until this is fixed upstream.
3. If neither is acceptable for the page in question, drop the button and route the feature to a
   manual Studio Pro GUI step instead of retrying variations of the MDL syntax — further syntactic
   variation will not help, since the defect is in the writer's argument-resolution logic, not in
   how the argument is spelled.

**Discovered:** 2026-08-21, a client project (a workflow-run "Station" page needing an
action button to open a related detail page with the current run passed as a parameter,
outside any dataview), confirmed via `DESCRIBE PAGE` round-trip and two independent rewrite
attempts before reverting the widget to restore a green build.

---

## BUG-96: cross-module `ALTER PAGE ... INSERT AFTER <col> { column ... }` into a DataGrid2 writes a malformed widget unit — Studio Pro loader crashes, `DESCRIBE` hides the evidence, `DROP PAGE` does not clear it

**Severity:** Fatal — whole project refuses to load in Studio Pro / `mx check`
**Reproducible:** Yes (single occurrence, but mechanism confirmed via recovery)
**mxcli / Mendix version:** not recorded in the source log (build ran 2026-08 on Mendix 11.x)
**Discovered:** 2026-08-14, a martial-arts-academy PoC project
**Related:** BUG-19 — same `InvalidCastException` (DivContainer → WidgetObject typed-list clash), different write path: BUG-19 is a CONTAINER inserted inside a dataview body; this is a DataGrid2 `column {}` block inserted cross-module.

### Trigger

A module's script ran a **cross-module** alter — inserting a new DataGrid2 column (with a
nested actionbutton) into a page owned by a *different* module:

```mdl
alter page "OtherModule"."SomePage" {
  insert after Actions {
    column colMessage (caption: 'Message') {
      actionbutton btnMessage (...)
    }
  }
}
```

### Actual behavior

- Every `mxcli exec` / `mxcli check` / `DESCRIBE PAGE` on the file keeps succeeding.
- Studio Pro's own loader (`mx check`, full project load) crashes:
  ```
  System.InvalidCastException: Unable to cast object of type
  'Mendix.Modeler.WebUI.Forms.Widgets.LayoutWidgets.DivContainers.DivContainer'
  to type 'Mendix.Modeler.WebUI.Forms.Widgets.CustomWidgets.WidgetObject'
     at ...StreamingBsonUnitReader... at ...UnitLoader.ConstructUnits()
  ```
- **`DESCRIBE PAGE` silently omits the malformed column** from its export — the corrupt
  widget is invisible to mxcli's own lenient reader while still present in the raw BSON.
- **`DROP PAGE` does not clear the crash** — the malformed unit survives in storage. Only
  `DROP MODULE` (removes the whole module folder) or a full `create or replace page` of
  that exact page clears it.

### Fix / recovery

`create or replace page` (full overwrite, NOT `create or modify`) of the affected page,
built from `DESCRIBE PAGE` output. Since `DESCRIBE` cannot represent the malformed column,
the replacement necessarily drops it — the intended new column is lost and must be re-added
via a plain single-module `CREATE OR REPLACE PAGE`, never a cross-module
`ALTER PAGE ... INSERT` column.

### Operating rule until fixed upstream

Treat cross-module `ALTER PAGE ... INSERT` of DataGrid2 columns as forbidden. The lenient
reader means a green `mxcli check` proves nothing here — run Studio Pro's own `mx check`
before trusting any session that used this construct.

---

## BUG-97: `.mpr` write path corrupts the entire project on the ~15th cumulative write operation — content-, order-, transaction- and engine-independent

**NOT REPRODUCED on v0.20.0 (16 sequential mixed writes, native mx check clean at cumulative writes 14/15/16; write-count cap downgraded to snapshot-plus-read-back — recovery lessons preserved in the archive) — retested and archived 2026-08-31, see [archive-resolved-2026-08-31.md](archive-resolved-2026-08-31.md) and [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).**


---

## BUG-98: `calculated by` on an attribute is silently dropped at write time — the attribute is stored as a plain stored value, BSON-verified

**Severity:** High — silent write-path data loss; every check is green while the feature simply does not exist in the model
**Reproducible:** Yes — isolated scratch-project repro plus three real project attributes
**mxcli / Mendix version:** mxcli v0.17.0 / Mendix 11.12.0 (isolated repro); first seen on Mendix 11.13.0, mxcli as of 2026-08-13
**Discovered:** 2026-08-13, a product-provisioning PoC project; confirmed and upgraded 2026-08-18

### Trigger

`alter entity ... add|modify attribute X: <type> calculated by Module.Microflow [default V];`
— and equally the CREATE-time form. **Both forms fail identically; there is no working form.**

### What every check says vs. what is stored

`mxcli check --references`: 0 errors. `mxcli exec`: "Added attribute"/"Modified attribute".
Native `mx check`: 0 errors. But BSON decode of the domain-model unit shows the attribute
stored as `DomainModels$StoredValue` with **no** calculated value type and **no reference to
the microflow**. `SHOW CALLERS OF <the microflow>` reports zero callers post-wiring. At
runtime every retrieve of the attribute returns empty/null, never the microflow's value —
indistinguishable from a stored attribute nobody set.

The confound (a mis-signed calculation microflow) was explicitly ruled out: the isolated
repro used a correctly-signed microflow (entity-typed parameter, returns the attribute's
type) and the clause was still dropped. This reclassifies the finding from "runtime never
computes" to **write-path data loss, BSON-verified** — a stronger and narrower claim.

Note: `CATALOG.ATTRIBUTES.IsCalculated` read `0` for all 355 attributes project-wide,
including known-broken ones — the catalog builder may never populate that column, so it is
not evidence in either direction.

### Detection

The only reliable check found: create a row, then read the attribute back through the live
runtime (`mx.data.get({xpath, callback})` in-browser, or an OQL/API round-trip). A genuinely
calculated attribute recomputes on every retrieve; a victim of this bug returns `""`.

### Workaround

Drop `calculated by` entirely: plain stored attribute + actively compute-`change`-`commit`
at the points where the underlying data changes, reusing the same (already-correct)
microflows called explicitly. For derived counts on a detail page, wrap the opening button's
`show_page` in a refresh-then-show microflow rather than changing the page's DataSource.

**Rule until fixed upstream:** never trust `mxcli check`, `mxcli exec` success, or native
`mx check` as evidence a `calculated by` wiring took effect — verify with a live retrieve
before any UI condition, downstream logic, or test assertion depends on it.

---

## BUG-99: `create import mapping` array-to-child-entity binding — child association observed empty at runtime ⚠️ SEVERITY NOT ESTABLISHED

> **⚠️ Do not file upstream yet — two known non-defect causes were never ruled out.** Either
> fully explains an empty child list with no mxcli defect: (1) the `import from mapping`
> *activity* silently not running — documented behaviour, invisible to `DESCRIBE`, BSON,
> `check --references` and mxbuild, and specifically triggered by dropping and recreating a
> mapping by script while its callers are left untouched, which the discovering session
> records doing; (2) the entity-name-must-equal-JSON-element-name rule, which the repro's
> scratch entity is not stated to satisfy. The decisive observation — whether the *root
> scalar* fields populated — was never recorded; it is what separates "the activity didn't
> run" from "the array binding is broken." Kept here because the *symptom* is real and
> expensive; the classification is not settled.

**Severity:** unclassified (see hold above); if real, High — the array binding is mxcli's only supported way to turn a JSON array field into child objects
**Reproducible:** symptom yes (three independent flows); root cause not isolated
**mxcli / Mendix version:** Mendix 11.13.0, mxcli as of 2026-08-13/14
**Discovered:** 2026-08-14, a product-provisioning PoC project

### Symptom

The `create <Association>/<ChildEntity> = <JsonArrayField> { ... }` sub-clause nested in a
`create <RootEntity> { ... }` block passes `mxcli check --references`, `mxcli exec`, and
native `mx check` with 0 errors, and `DESCRIBE IMPORT MAPPING` looks structurally correct —
but every `retrieve $Items from $Root/<ChildAssoc>` after an `import from mapping` returned
an empty list. Seen on: a live flow with `LOG INFO`-confirmed valid 3-item JSON immediately
before the import; a structurally identical mapping in an unrelated module whose target
entity had 0 rows for its entire history despite logged successful calls; and a from-scratch
scratch-entity repro invoked via `mx.data.action` against a fresh container (`count=0`).
Re-issuing via `create or modify import mapping` did not change the symptom.

### Operating rule regardless of classification

Treat any `create import mapping` that binds a JSON array to a child entity as **unverified
until proven with a live runtime retrieve** after an actual `import from mapping` call —
static checks validate the mapping's structure, never its runtime behaviour (same rule and
same reason as BUG-98). Workarounds if it bites: a JavaScript action that `JSON.parse`s the
array field and returns a list, or manual parsing in the microflow; the mapping can still
handle the root object's scalar fields.

### To settle it

Run the discriminating test: one importing microflow, untouched callers (no drop/recreate),
entity names exactly matching JSON element names at every level, and record whether the root
scalars populate while the child list stays empty. Root scalars populated + empty children =
real array-binding defect; nothing populated = the activity never ran (cause 1).

---

## BUG-100: every mxcli-scaffolded project resolves to Compose project name `docker` — unrelated projects share containers and one Postgres volume ⚠️ mechanism secondhand

> **Mechanism trusted-but-unverified:** the root cause was reported by a peer session on the
> same machine and matches observed behaviour; it was not independently verified against
> Compose's own docs/source. The FIX below was confirmed to resolve the symptoms.

**Severity:** High — cross-project data loss: whichever project's runtime syncs its schema last can silently alter/wipe tables belonging to a different app's domain model
**Reproducible:** Yes (symptoms; see repro)
**mxcli version:** any that ships `mxcli docker init` writing `.docker/` without `COMPOSE_PROJECT_NAME`
**Discovered:** 2026-08-14, a product-provisioning PoC project, via a cross-session tip from a WMS demo project on the same machine

### Mechanism

`mxcli docker init` writes compose files into `<project-root>/.docker/`. Compose derives its
project name from the containing directory when `COMPOSE_PROJECT_NAME` is unset — and every
mxcli project names that directory `.docker`, so **every project on the machine resolves to
the same Compose project `docker`**: identical container names (`docker-mendix-1`,
`docker-db-1`), one shared named volume (`docker_postgres-data`), one default network.
Starting project B's stack tears down project A's containers as "stale" and B's schema sync
runs against A's data.

### Symptoms (none look like a naming collision at first)

App container silently "replaced" mid-session with someone else's domain model; a
previously-green e2e suite failing basic persistence assertions ("0 rows where there should
be 3"); containers gone from `docker ps` without being stopped; manually-started sidecars
(`docker run --network container:<old-id>`) silently orphaned — they keep running but proxy
into a dead network namespace. If more than one mxcli project exists on the machine, check
this FIRST before chasing an application-code theory.

### Diagnosis

```bash
docker ps -a --format '{{.Names}}: {{.Label "com.docker.compose.project.working_dir"}}'
# a docker-mendix-1 whose working_dir points at a DIFFERENT project's .docker = this bug
docker volume ls   # one docker_postgres-data doing double duty confirms it
```

### Fix

`COMPOSE_PROJECT_NAME=<short-project-slug>` in `<project>/.docker/.env`, then tear down and
redeploy. Caveats: `compose down` after the env change resolves to the NEW name and won't see
the old containers — stop/remove them explicitly; and the rename creates a **brand-new empty
volume** (`<slug>_postgres-data`) — dump first (`pg_dump`) if the current data matters.
Re-verify every manually-managed sidecar against the new container afterwards.

### Recommended upstream fix

`mxcli docker init` should set `COMPOSE_PROJECT_NAME` at scaffold time (prompt for a slug or
derive one from the `.mpr` filename) — this is a scaffolding-template gap, not a per-project
judgment call.

## BUG-102: `ALTER PAGE … SET DataSource = … ON widget` silently no-ops on a native DataGrid — reports success, passes the mxbuild gate, XPath never changes

**Severity:** High — silent success, stale runtime behavior, surfaces only by testing the running app
**mxcli version:** built from source at `4b58b89` (2026-08-26)
**Mendix version:** 11.13.0
**Discovered:** 2026-08-26, TFC-TCXGraphPOC-main, fixing a live security/behavior defect in a
task-inbox page's DataGrid XPath
**Reproducible:** yes, deterministic — reproduced twice in a row against the same page

```
ALTER PAGE TFC.TFC_MyTasks {
  SET DataSource = DATABASE FROM System.WorkflowUserTask
    WHERE [System.WorkflowUserTask_Assignees = '[%CurrentUser%]' or System.WorkflowUserTask_TargetUsers = '[%CurrentUser%]']
          [State = 'InProgress']
    SORT BY StartTime ASC
} ON "dgMyTasks";
→ "Altered page TFC.TFC_MyTasks"     (no error, exit 0)
→ mxbuild: 0 errors                  (gate passes)
```

The DataGrid's actual persisted `DataSource` XPath **never changes**. `DESCRIBE PAGE` immediately
after this exec still showed the pre-exec XPath verbatim. Confirmed twice, independently:

1. Ran once to add a `TargetUsers` clause the grid was missing (it had `Assignees` only). Exec
   reported success, gate passed. `DESCRIBE PAGE` on the resulting commit — via a scratch copy of
   the `.mpr` extracted with `git show <commit>:TFC-TCXGraphPOC.mpr` into an isolated temp
   directory, bypassing any running process, catalog cache, or working-tree state — showed the
   `TargetUsers` clause **absent**.
2. Ran again immediately after, this time to *remove* a different clause
   (`.../WorkflowDefinition/Name = '...'`) that a live `SecurityRuntimeException` had traced to.
   Same result: "Altered page", gate passed, and the same isolated-extraction check on that commit
   showed the clause **still present**.

Two consecutive silent no-ops on the identical widget, in the identical page, back to back — not a
one-off. The live running app kept throwing the exact same `SecurityRuntimeException:
No access rights for System$WorkflowDefinition/Name` after the "fix" that was supposed to remove
that XPath clause, because the clause was never actually removed.

**Distinct from [[BUG-84]]** (`SET DataSource = DATABASE Module.Entity` on a *DataView* silently
**wipes** the datasource to nothing). This is a native **DataGrid**, the datasource *type* was
never changing (`DATABASE System.WorkflowUserTask` before and after — only the WHERE clause
differed), and the property **kept its old value** rather than being wiped. A different failure
shape from the same family: `SET DataSource` on a widget's `WHERE` constraint appears to be a
write that mxcli accepts syntactically, reports as applied, and passes structurally through
mxbuild — but never actually reaches the persisted unit for at least the DataGrid case.

**Workaround:** `CREATE OR REPLACE PAGE` for the whole page instead of `ALTER PAGE … SET
DataSource` on a DataGrid. Verified reliable: the same page, entirely recreated with the corrected
XPath, showed the correct value in `DESCRIBE PAGE` immediately after exec.

**Process note:** this defect would have shipped silently if the fix hadn't been tested against
the *running app* — `mx check`/mxbuild's "0 errors" and mxcli's own "Altered page" success message
were both wrong signals, agreeing with each other and both wrong. Only clicking through the actual
UI (twice, since the first re-test still showed the bug because the exec before it had *also*
silently no-op'd) surfaced it. Recorded per this project's own `tool-output-is-not-ground-truth.md`
discipline.

## BUG-103: `DESCRIBE MICROFLOW` emits `log` strings with embedded doubled quotes that `mxcli check` then rejects — round-trip asymmetry

**Severity:** Medium — breaks the describe→edit→exec loop for any microflow whose log message quotes a name
**mxcli version:** built from source at `4b58b89` (2026-08-26)
**Mendix version:** 11.13.0
**Discovered:** 2026-08-28, TFC-TCXGraphPOC-main, rebuilding `TFC.WF_ACT_GraphAgent_RiskFlag` from its own `DESCRIBE` output
**Reproducible:** yes, deterministic — isolated with a two-probe bisection

`DESCRIBE MICROFLOW` round-trips a log activity whose message contains a quoted name as:

```
log warning node 'WF_GraphAgent' 'No agent titled ''Graph Agent'' configured';
```

Feeding that exact output back through `mxcli check` fails with
**"Unexpected token after expression"** (reported as glued keywords at the doubled quotes).
The identical `''…''` escape inside a `@caption` annotation in the same script parses fine —
the escape is only rejected in `log` message strings. So a microflow that `DESCRIBE` prints
cannot be re-executed unmodified: the CLI's own output is not valid input to its own parser.

Bisection (probe scripts, one construct each): `@caption` with `''X''` → passes;
`replaceAll` with a bracketed regex → passes; `log … '…''X''…'` → **fails**;
the same `change`/`commit` body with the log line reworded → passes.

**Workaround:** reword log message strings to avoid embedded quotes entirely
(e.g. `…no AgentCommons.Agent titled Graph Agent configured…`). Purely cosmetic loss.

**Related:** same describe→check round-trip family as [[BUG-84]]/[[BUG-96]] in spirit (tool
output disagreeing with tool input), but this one is a parser gap, not a silent write no-op.

## BUG-104: quoting a microflow parameter as `"$Name"` silently keeps the `$` in the parameter name — CE1613 at mxbuild while `check --references` passes

**Severity:** High — the always-quote-identifiers house rule, applied to a parameter, produces a corrupt parameter name that only surfaces at the mxbuild gate
**mxcli version:** built from source at `4b58b89` (2026-08-26)
**Mendix version:** 11.13.0
**Discovered:** 2026-08-31, TFC-TCXGraphPOC-main, writing a microflow taking a `TFC.TFCStub`
**Reproducible:** yes

The documented quoting rule ("always quote identifiers; quotes are stripped automatically")
does not extend to the `$` sigil on a microflow parameter. Declaring

```
create microflow M.Flow ("$TFCStub": TFC.TFCStub) ...
```

strips the quotes but keeps the `$` **inside** the stored parameter name, so the model holds a
parameter literally named `$TFCStub` whose body references `$TFCStub` — which now resolves as
`$` + name `TFCStub` and matches nothing. `mxcli check --references` passes; the failure is
CE1613 at mxbuild. Correct form: `$TFCStub: TFC.TFCStub` (sigil unquoted; quote only the
bare-name identifiers).

**Workaround:** never wrap the `$`-prefixed form in quotes. If already written, regenerate the
microflow with the unquoted sigil.

## BUG-105: `ALTER PAGE … REPLACE`/multi-root `INSERT` can register the same widget name twice, then fail every later edit with duplicate-name errors

**Severity:** Medium — page becomes uneditable through mxcli for the affected names
**mxcli version:** built from source at `4b58b89` (2026-08-26)
**Mendix version:** 11.13.0
**Discovered:** 2026-08 (TFC-TCXGraphPOC-main, iterating on agent-panel page edits)
**Reproducible:** intermittent but recurred across sessions

A `REPLACE widget WITH { … }` (and an `INSERT` whose block carries more than one root widget)
can leave the page holding two registrations of one widget name. Later `ALTER PAGE`
operations naming any widget on that page then fail with a duplicate-name error even though
`DESCRIBE PAGE` renders a single occurrence.

**Workaround:** `CREATE OR REPLACE PAGE` from a clean `DESCRIBE` dump under fresh names, or
edit via MCP `pg_patch_page`. Prefer single-root blocks in `REPLACE`/`INSERT`.

## BUG-106: widget names stay burned after a rolled-back exec — a restore of the `.mpr` does not free names the failed script had claimed

**Severity:** Medium — retrying a failed page script verbatim fails on names that no longer exist in the model
**mxcli version:** built from source at `4b58b89` (2026-08-26)
**Mendix version:** 11.13.0
**Discovered:** 2026-08 (TFC-TCXGraphPOC-main, exec.sh auto-restore path)
**Reproducible:** yes within a session

After an exec fails mxbuild and the snapshot is restored, re-running the corrected script can
still be rejected with duplicate-widget-name errors for names that only ever existed in the
rolled-back attempt — the name registry appears to survive the restore (cache keyed on the
project path, not the file contents). `DESCRIBE PAGE` on the restored model shows the names
absent.

**Workaround:** bump the widget names (suffix `2`), or clear/refresh the mxcli catalog cache
before retrying. Renaming is the reliable path; it is why several TFC pages carry `_v2`
widget names.

---

## BUG-107: an **unquoted** value in a workflow `CALL MICROFLOW … WITH (…)` segfaults the binary instead of erroring

**Severity:** High — SIGSEGV with no diagnostic, on the natural spelling of the most common workflow activity; a one-character workaround exists but is undiscoverable
**mxcli version:** v0.20.0 (2026-08-28)
**Mendix version:** 11.14.0
**Discovered:** 2026-09-03, workflow construct probe on a blank scratch app (a PLM approval-migration project's toolkit probe)
**Reproducible:** yes, 100%, minimal repro below

The `WITH` clause's **value** must be a quoted string. Give it a bare variable — which is how
the same expression is written everywhere else in MDL — and the process dies:

```sql
CREATE WORKFLOW Probe.T PARAMETER $Context: Probe.Request
BEGIN
  CALL MICROFLOW Probe.ACT_Noop WITH (Ctx = $WorkflowContext);   -- SIGSEGV
END WORKFLOW;
```

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x2 addr=0x58 pc=0x1059e618c]
github.com/mendixlabs/mxcli/mdl/visitor.buildWorkflowCallMicroflow(...)
	github.com/mendixlabs/mxcli/mdl/visitor/visitor_workflow.go:565 +0x5ec
```

**The discriminator is the quoting of the value, nothing else.** Probed four spellings:

| Written | Result |
|---|---|
| `WITH (Ctx = $WorkflowContext)` | **PANIC** |
| `WITH (Probe.ACT_Noop.Ctx = $WorkflowContext)` | **PANIC** |
| `WITH ("Ctx" = '$WorkflowContext')` | works |
| `WITH (Probe."ACT_Noop"."Ctx" = '$Context')` | works |

Verified end-to-end on the quoted form: `exec` writes it, native `mx check` reports **0
errors**, and `DESCRIBE WORKFLOW` reads it back as
`call microflow Probe.ACT_Noop with (Ctx = '$WorkflowContext')`.

The panic fires on plain `check`, on `check --references`, and on `exec`. It happens before
any write, so the `.mpr` is left intact (confirmed by a native `mx check` afterwards).

**What makes this worth fixing rather than documenting.** The error path that *should* catch
this is already there and already correct — omit the clause entirely and `--references` says:

```
- call microflow 'Probe.ACT_Noop': parameter 'Ctx' is not mapped — Mendix requires every
  parameter of a workflow call-microflow to be mapped (add `with (Ctx = ...)`)
```

That hint tells the author to write `with (Ctx = ...)`, i.e. an unquoted left side and an
unquoted right side, which is the spelling that crashes. The tool talks the user into the
segfault.

**Workaround:** quote the value — `WITH ("Ctx" = '$WorkflowContext')`.

## BUG-108 (**SUPERSEDED BY BUG-76** — keep as an addendum, do not file separately): enumeration `DECISION` outcomes — mxcli accepts only the form that writes an unloadable `.mpr`, and rejects both forms Mendix accepts (CRITICAL)

> **Filed in ignorance of BUG-76, found immediately after.** BUG-76 (2026-08-13, re-confirmed
> on v0.18.0 and v0.20.0) already states the general defect: mxcli writes every `DECISION`
> outcome label as a raw string into a field that must hold an `EnumerationValueIdentifier`, so
> **every** decision corrupts — a `1 = 1` condition as surely as an enum attribute. This entry
> stands only as an addendum contributing two facts BUG-76 does not carry: (a) the enum-valued
> case has *no* writable spelling, because mxcli rejects both fully-qualified forms and accepts
> only the bare value that corrupts, so the defect is unavoidable rather than merely unguarded;
> (b) recovery is `DROP WORKFLOW` — mxcli can still read what mxbuild cannot load, verified back
> to a 0-error `mx check`. Merge both into the BUG-76 GitHub issue; do not open a second one.

**Severity:** Critical — silent project corruption; the `.mpr` cannot be opened afterwards
**mxcli version:** v0.20.0 (2026-08-28)
**Mendix version:** 11.14.0
**Discovered:** 2026-09-03, workflow construct probe on a blank scratch app
**Reproducible:** yes, 100%

The validator is inverted. Given `Probe.StatusEnum` with values `Draft`/`Sent`:

| Outcome value written | `mxcli check --references` | Result |
|---|---|---|
| `'Probe.StatusEnum.Draft'` (the form Mendix requires) | **rejected** — "is not a valid enumeration value identifier — MxBuild rejects outcome names with spaces or punctuation" | cannot be written |
| `'StatusEnum.Draft'` | **rejected**, same message | cannot be written |
| `'Draft'` (bare) | **Check passed!** | **corrupts the project** |

The bare form execs cleanly and `DESCRIBE WORKFLOW` reads it back happily. The native
toolchain then cannot load the file at all — this is a load failure, not a validation error,
so every downstream tool and Studio Pro itself is locked out:

```
ERROR: Mendix.Modeler.Storage.StorageLoadException: One or more invalid values were detected
while loading the project:
 - Enumeration value condition outcome in  has an invalid value '' for property Value.
   The text 'Draft' is not a valid EnumerationValueIdentifier.
   at Mendix.Modeler.Enumerations.EnumerationValueIdentifier.FromString(String text)
```

**Consequence:** an enumeration-based `DECISION` cannot be expressed in MDL at all on this
binary. Every available path either fails at check time or produces an unopenable project.

**Recovery:** `mxcli` can still *read* the corrupt model, so `DROP WORKFLOW <the workflow>`
repairs it in place — verified, the project returned to 0 errors. Do not restore from a
snapshot before trying the drop.

**Note for the fix:** the message "MxBuild rejects outcome names with spaces or punctuation"
is treating a fully-qualified enumeration value as a free-text outcome caption. Boolean and
free-text outcomes are unaffected; only the enumeration path is wrong.

---

## BUG-109: `JUMP TO` inside a boundary-event body writes a Jump with no Target, named after its own target

**Severity:** High — the only legal terminator for an interrupting boundary event is unusable
**mxcli version:** v0.20.0 (2026-08-28)
**Mendix version:** 11.14.0
**Discovered:** 2026-09-03, workflow construct probe on a blank scratch app
**Reproducible:** yes, 100%

```sql
USER TASK A 'A' PAGE Probe.WF_TaskPage OUTCOMES 'Done' { }
  BOUNDARY EVENT INTERRUPTING TIMER 'addDays([%CurrentDateTime%], 3)' { JUMP TO A; };
```

`mxcli check --references` passes, `exec` writes, `DESCRIBE WORKFLOW` reads it back as
`jump to A;`. Native `mx check`:

```
[error] [CE0495] "Duplicate name 'A'." at User task 'A', Jump 'A'
[error] [CE6680] "The 'Target' property is required." at Jump 'A'
```

The generated Jump activity is *named* after its target instead of *pointing* at it, so it
collides with the target and carries no `Target`.

**Scope — the same statement is fine elsewhere.** `JUMP TO A;` inside a **user-task outcome**
writes correctly and passes `mx check` with 0 errors (verified in isolation). The defect is
specific to a boundary-event body.

**Consequence, combined with the grammar:** an **interrupting** boundary event cannot be
expressed correctly in MDL. Mendix requires its path to end in *End workflow* or *Jump to*
(CE0105 otherwise, which fires on an empty body); `END WORKFLOW`, `END`, `END FLOW` and
`END OF BOUNDARY EVENT PATH` are all parse errors as statements, and `JUMP TO` is this bug.
Non-interrupting boundary events are unaffected and work correctly.

---

## BUG-110: `DESCRIBE WORKFLOW` emits MDL it cannot re-parse when a targeting XPath contains quotes

**Severity:** Medium — breaks the documented round-trip; an agent using DESCRIBE as ground truth gets un-executable output
**mxcli version:** v0.20.0 (2026-08-28)
**Mendix version:** 11.14.0
**Discovered:** 2026-09-03, workflow construct probe on a blank scratch app
**Reproducible:** yes, 100%

Written (correctly, with doubled quotes):

```sql
TARGETING XPATH '[System.UserRoles = ''[%UserRole_User%]'']'
```

`DESCRIBE WORKFLOW` emits it with the inner escaping dropped:

```
targeting users xpath '[System.UserRoles = '[%UserRole_User%]']'
```

Feeding that back to `mxcli check` fails:

```
- line 9:48 mismatched input '[%UserRole_User%]' expecting ';'
```

`DESCRIBE` is documented as round-trippable and is the toolkit's recommended way to read
current state before editing (`query-the-model.md`), so this silently produces a script that
looks authoritative and cannot run.

---

## BUG-111: `mxcli syntax` drill-down rejects the example printed in its own help text

**Severity:** Low — costs a discovery round-trip; pushes agents to guess grammar
**mxcli version:** v0.20.0 (2026-08-28)
**Discovered:** 2026-09-03
**Reproducible:** yes, 100%

`mxcli syntax` prints, under Examples:

```
mxcli syntax workflow user-task targeting     # Drill down to targeting
```

Running it returns `Unknown topic: workflow user-task targeting`. So do
`mxcli syntax workflow user-task` and `mxcli syntax workflow parallel-split`, although
`mxcli syntax workflow` lists all of those as sub-topics. Only `mxcli syntax workflow --json`
returns the per-construct syntax and examples.

---

## BUG-112: `mxcli new` warns that the path is too long, then hangs forever instead of failing

**Severity:** Medium — an unattended run loses the whole session with no error
**mxcli version:** v0.20.0 (2026-08-28)
**Mendix version:** 11.14.0
**Discovered:** 2026-09-02/03
**Reproducible:** yes, on any output path over the limit

`mxcli new` correctly detects and reports the condition at step 2:

```
Warning: this project's path is 49 characters longer than Mendix tooling allows.
  Total 308 exceeds the 259-character limit MxToolset enforces.
  ... `mx` commands against it can fail with PathTooLongException.
```

It then proceeds to *"Step 6/7: Running the first build"* and **never returns** — observed
hung for ~10 hours, no output, no timeout, no non-zero exit. The project itself is created
and usable; only the settle-build hangs.

**Consequence for unattended work:** a background `mxcli new` in a deep scratch directory
(Claude Code session scratchpads are ~126 chars before the project name) consumes the entire
run silently.

**Fix shape:** having detected the over-length path, either refuse before step 6 or bound the
build with a timeout. A warning followed by an unbounded blocking call is the worst of both.

**Workaround:** create in a short path (`/tmp/<short>/`), or pass `--skip-build` — the project
`mxcli new` produces without step 6 is fully usable for MDL work (verified: `SHOW MODULES`,
`exec`, and native `mx check` all work against it).
## BUG-113: `ALTER PAGE … REPLACE` of a pluggable widget silently drops properties you omit — a Combobox comes back with no `Attribute` and still renders

**Severity:** High — the widget draws normally and binds to nothing; only `DESCRIBE PAGE` shows it
**mxcli version:** v0.19.0-nightly.c836f01 (2026-08-27)
**Mendix version:** 11.14.0
**Discovered:** 2026-09 (a sales-coaching build, adding an OnChange to an existing filter control)
**Reproducible:** yes

`REPLACE cbStageFilter WITH { combobox cbStageFilter (Label: …, Attribute: "StageFilter",
OnChange: MICROFLOW …) }` emitted a pluggable Combobox carrying `Label` and `OnChange` and
**no `Attribute`** — with the attribute name written both quoted and unquoted. `mxcli check
--references` passed, mxbuild reported 0 errors, and the page rendered a normal-looking
dropdown that was bound to nothing and could not filter anything.

This is not "REPLACE rebuilds from what you write" behaving as documented: the property WAS
written and was dropped. It appears specific to pluggable widgets, where an unset required
property is not a model error.

**Workaround:** use a built-in widget where one will do (`RADIOBUTTONS` for a short enum), or
`DESCRIBE PAGE` after every `REPLACE` of a pluggable widget and compare property-by-property.
Do not trust the render — an unbound combobox looks identical to a bound one.

## BUG-114: `CREATE MODULE ROLE` is not idempotent, and the abort silently discards every statement after it

**Severity:** High — a re-run of a mixed script logs nothing about the statements it skipped
**mxcli version:** v0.19.0-nightly.c836f01 (2026-08-27)
**Mendix version:** 11.14.0
**Discovered:** 2026-09 (a sales-coaching build, re-applying a script after a failed first run)
**Reproducible:** yes

Every other creating statement in MDL has a `CREATE OR MODIFY` / `CREATE OR REPLACE` form.
`CREATE MODULE ROLE` has neither and no `IF NOT EXISTS`, so re-running a script that creates a
role fails with `Error: module role already exists: <Module>.<Role>` and **everything after
that statement does not run**. The exit is 1 and the message names the role, so the failure
itself is visible — what is not visible is the list of documents that were therefore never
created. A script whose role statement sits at the top loses all of its real work on a re-run.

**Workaround:** keep non-idempotent statements (`CREATE MODULE ROLE`, `CREATE ASSOCIATION`) in
their own script, applied once, separate from the documents that get edited and re-applied.

## BUG-115: `exec` can log `Created microflow: …` for documents that are not in the model afterwards, and still exit 0

**Severity:** High — the tool's own success output is not evidence the work landed
**mxcli version:** v0.19.0-nightly.c836f01 (2026-08-27)
**Mendix version:** 11.14.0
**Discovered:** 2026-09 (a sales-coaching build)
**Reproducible:** NOT reproduced on demand — observed once, root cause not established

An `exec` of a mixed security-plus-documents script logged `Created module role: …`,
`Granted access on …` (×6), `Created microflow: …` (×7) and `Created page …`, ran the mxbuild
gate clean and exited 0. Afterwards the module role and all six grants were in the model and
**none of the seven microflows or the page were**. `SHOW MICROFLOWS IN <Module>` returned the
pre-run count.

Cause not established. The plausible candidate is that `mxbuild` was run directly against the
same `.mpr` shortly afterwards, which is the split-`mprcontents` consolidation hazard this
toolkit already warns about — but that was not proven, and it does not obviously explain why
the security changes survived and the documents did not. Logged as observed rather than
diagnosed, because the practice it forces is worth having either way.

**Workaround, and it should be the default practice regardless of this bug:** after every
`exec`, read the model back (`SHOW MICROFLOWS IN <Module>`, `SHOW PAGES IN <Module>`) and
count. Exit 0 plus a log of `Created …` lines is a claim about what the tool tried to do, not
a fact about the model.
