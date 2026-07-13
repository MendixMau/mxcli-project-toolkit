# mxcli Bug Report — M-0022 POC session

Issues encountered during AI-assisted Mendix development using mxcli + MDL.
Collected for reporting to the mxcli team.

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

**Status: FIXED in mxcli v0.13.0** — `CREATE ASSOCIATION` for cross-module associations works correctly. Verified 2026-07-04 on WMS-LargeSource-main (Mendix 11.12.0): 0 CE errors, project loads cleanly in mxbuild. **No Studio Pro handoff required.**

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

**Discovered:** 2026-05-17, M-0022 POC Phase 1 (payer-registration.mdl).

---

## CE0854: `set` association called on wrong entity (direction error)

**Not a mxcli bug** — a valid Mendix model error, but included here because it appears consistently in AI-generated scripts that don't check association direction.

**Symptom:** CE0854 "Association X not reachable from entity Y" at `mx check`.

**Root cause:** `set $Entity/Module.AssocName = $Other` must be called on the entity that holds the FK column. With `owner Default`, the FK is on the `from` entity in the association definition.

**Diagnosis:** Run `DESCRIBE ASSOCIATION Module.AssocName` — the `from` entity is the one you must call `set` on.

```mdl
-- Association: PayerAreaData_PayerDetail
-- FROM = PayerAreaData (FK here), TO = PayerDetail

-- CORRECT: set on the FROM entity
set $PayerAreaData/PayerRegistration.PayerAreaData_PayerDetail = $PayerDetail;

-- WRONG: set on the TO entity → CE0854
set $PayerDetail/PayerRegistration.PayerAreaData_PayerDetail = $PayerAreaData;
```

**Also check creation order:** the FK-owning entity (`from`) must be committed after the entity it points to (`to`) already exists in the database.

**Discovered:** 2026-05-18, M-0022 POC script 11 (ACT_PayerDetail_SaveDraft).

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

**Discovered:** 2026-05-21, M-0022 POC script 34 (fixing CE0720 on lblHdrAction).

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

**Discovered:** 2026-05-21, M-0022 POC script 34 (fixing CE0720 on lblHdrAction).

---

## BUG-09: Gallery `filter {}` block cannot express association-path filter attributes

**Severity:** Medium — limits AI-assisted filter configuration; requires Studio Pro for association-based filters  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No

### Context

Mendix Gallery filters **fully support** filtering over associated entities, including multi-hop paths (e.g. `PayerDetail → PayerApplicationHeader → ApplicationCommonHeader → Status`). This works correctly at runtime and is configurable in Studio Pro.

### Issue

MDL `filter {}` block syntax only accepts **direct entity attribute names** (short or fully-qualified) in filter widget definitions:

```mdl
-- Works: direct attribute on datasource entity
filter filter1 {
  textfilter txtKeyword (Attributes: [PayerRegistration.PayerDetail.CustomerCode])
  dropdownfilter statusFilter (Attributes: [PayerRegistration.PayerDetail.Status])
}
```

There is no MDL syntax for specifying an association-path as a filter attribute:

```mdl
-- NOT expressible in MDL — cannot write association-path filter attributes
filter filter1 {
  dropdownfilter statusFilter (Attributes: [
    PayerDetail_PayerApplicationHeader/PayerApplicationHeader_ApplicationCommonHeader/Status
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
- For filters on **associated entity attributes**: document the filter as a Studio Pro manual step; note the association path (e.g. `PayerDetail → [PayerDetail_PayerApplicationHeader] → PayerApplicationHeader → [PayerApplicationHeader_ApplicationCommonHeader] → ApplicationCommonHeader.Status`)

**Discovered:** 2026-05-22, M-0022 POC PayerRegistration_Overview (Status filter via 2-hop cross-module association).

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

**Discovered:** 2026-05-22, M-0022 POC script 35 (PayerRegistration_Overview gallery filter extension).

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
dataview dvTest (DataSource: $PayerDetail/PayerRegistration.PayerDetail_PayerCustomerBase) { ... }

-- Tested inside parent DataView (currentObject traversal) → CE6705
dataview dvTest (DataSource: $currentObject/PayerRegistration.PayerDetail_PayerCustomerBase) { ... }
```

When Studio Pro manually sets Type = Context and traverses via the association tree picker, it writes a different internal type that does NOT trigger CE6705. mxcli has no syntax that produces this internal type.

**Conclusion:** mxcli cannot create a valid DataView datasource that retrieves an associated entity. Use microflow datasource (current approach) or configure manually in Studio Pro.

**Discovered:** 2026-05-22, M-0022 POC PayerDetail_View (`dvPayerCustomerBase`, `dvPaymentTermData`).

---

## CE0056 / CE0161: `retrieve` on a Non-Persistent Entity (NPE) — must use association action

**Not a mxcli bug** — a Mendix model constraint, but a common MDL authoring error.

**Symptom:** `CE0056 "Entity X cannot be retrieved from the database because it is non-persistable."` and `CE0161 "Error(s) in XPath constraint."` when a `retrieve` statement targets an NPE entity.

**Root cause:** MDL `retrieve $Var from Module.Entity where [...]` always generates a "Retrieve from database" activity. NPEs have no database table — they live only in memory. The database retrieve fails.

**Fix option A (MDL — change microflow signature):** Pass the NPE as a direct microflow parameter instead of navigating via association. If the page has both the parent and child NPE in scope via nested data views, the button can pass both objects directly. This eliminates the need to retrieve the associated NPE inside the microflow.

**Fix option B (Studio Pro manual):** In Studio Pro, open the microflow and replace the "Retrieve from database" activity with a "Retrieve by association" activity. Set the association and the starting object. This is the correct Mendix pattern for NPE-to-NPE traversal and does not require changing the microflow signature.

**Discovered:** 2026-05-18, M-0022 POC script 11 (ACT_PayerDetail_SaveDraft — CompanySearchResult NPE retrieve).

---

## BUG-14: `ALTER PAGE DROP + INSERT BEFORE` with MICROFLOW action corrupts page BSON

**Severity:** High — MPR becomes unloadable by `mx` after execution  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No — v0.13.0 fixed several page-authoring BSON issues; worth retesting before routing to SP  
**Discovered:** 2026-05-25, M-0022 POC Script 56

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
**Discovered:** 2026-05-26, M-0022 POC scripts 62 + 63

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
-- In ACT_Payer_ExpansionApply_Save (script 63):
retrieve $OldPayerDetail from PayerRegistration.PayerDetail
  where [PayerDetail/CustomerCode = $Dto/CustomerCode]
  limit 1;

-- Then: Broken retrieve — association path from variable
retrieve $ExistingBase from $OldPayerDetail/PayerRegistration.PayerDetail_PayerCustomerBase
  limit 1;
```

The second `retrieve` (via object-variable association path) is the broken form.

```mdl
-- In ACT_Payer_ExpansionApply_InitNew (script 62):
retrieve $Base from $ExistingPayerDetail/PayerRegistration.PayerDetail_PayerCustomerBase
  limit 1;
```

Same pattern — both cause CE0018 + CE0136.

### Expected behavior

mxcli generates a "Retrieve by Association" activity with `Association = PayerRegistration.PayerDetail_PayerCustomerBase` and `Entity = Customer_Common.PayerCustomerBase` properties wired correctly.

### Actual behavior

mxcli generates a "Retrieve by Association" activity where both `Association` and `Entity` BSON properties are empty GUIDs. The activity is stored but is invalid — Studio Pro cannot render it and the model checker rejects it.

### Root cause (inferred)

mxcli's MDL compiler parses `retrieve $X from $ObjVar/Module.AssocName limit 1` but fails to resolve and serialize the association and entity references into the underlying BSON `InternalId` fields. The association name and target entity are lost during compilation.

### Workaround

Replace the association-path retrieve with an XPath DB retrieve against the target entity:

```mdl
-- BROKEN (generates empty BSON):
retrieve $ExistingBase from $OldPayerDetail/PayerRegistration.PayerDetail_PayerCustomerBase
  limit 1;

-- FIXED (XPath cross-entity filter):
declare $CCode String = $Dto/CustomerCode;
retrieve $ExistingBase from Customer_Common.PayerCustomerBase
  where [PayerRegistration.PayerDetail_PayerCustomerBase/PayerRegistration.PayerDetail/CustomerCode = $CCode]
  limit 1;
```

**Pre-conditions required for XPath workaround:**
1. The target entity (`PayerCustomerBase`) must be a **persistent** entity (not an NPE).
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
- `retrieve $ExistingPayerDetail from PayerRegistration.PayerDetail where [PayerDetail/CustomerCode = $ExistingCustomerCode]` (simple attribute XPath)
- `retrieve $Base from Customer_Common.PayerCustomerBase where [PayerRegistration.PayerDetail_PayerCustomerBase/.../CustomerCode = $ExistingCustomerCode]` (cross-module association XPath)

**Root cause confirmed (2026-05-26) via `mxcli bson dump` comparison:**

mxcli writes the BSON key as **`XPathConstraint`** (capital P), but Studio Pro writes and reads **`XpathConstraint`** (lowercase p). BSON field lookup is case-sensitive. The XPath value IS stored in the file — just under the wrong key name. Studio Pro cannot find it and renders the constraint field as empty. The runtime executes with no filter.

Evidence from BSON dump:
```
Working (GET_Sequence_NextId — written by Studio Pro):  "Key": "XpathConstraint"
Broken  (ACT_Payer_ExpansionApply_* — written by mxcli): "Key": "XPathConstraint"
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
**Discovered:** 2026-05-26, M-0022 POC Script 77 (PayerRegistration_Overview_DG2)

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
**Discovered:** 2026-07-03, IVM-MxCLI-main Phase 3a (script 14)

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

**Discovered:** 2026-07-03, IVM project (datagrid). 2026-07-05, WMS-LargeSource-main script 18 (snippet with no entity context).

---

## BUG-19: `ALTER PAGE` — REPLACE wrapping existing widget in CONTAINER corrupts BSON (DivContainer/WidgetObject type clash)

**Severity:** Critical — project becomes unopenable in Studio Pro with InvalidCastException  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.12.0 Beta  
**mxcli version when found:** v0.12.x (pre-v0.13.0)  
**Retested on v0.13.0:** No — codec engine may address type-tag handling; worth a quick retest  
**Discovered:** 2026-07-05, IVM-MxCLI sprint4-visual-polish.mdl

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
git checkout HEAD -- mprcontents/ IVM-MxCLI.mpr
```
Then restart SP.

---

## BUG-20: Cross-module association traversal as widget datasource writes null `DestinationEntityId`

**Severity:** Critical — project becomes unopenable in Studio Pro with `StorageLoadException`  
**Status:** Open — no fix in mxcli; workaround: use MCP after exec  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.12.0 Beta  
**mxcli version when found:** v0.13.0 (confirmed on codec engine)  
**Retested on v0.13.0:** Yes — still corrupts. Preflight rule 7 STOP remains valid.  
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
