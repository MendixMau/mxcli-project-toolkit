# Microflow Patterns — MDL Microflow & Association Rules for This Project

---

## Parameter Naming — No `$` in Declarations

Parameter names are declared WITHOUT `$`. The `$` is only used in the body as a reference sigil.

```mdl
-- CORRECT
create microflow Module.ACT_DoSomething ("Name": String, "Customer": Module.Customer)
begin
  declare $Result String = $Name;
end;

-- WRONG — $ becomes part of the stored parameter name
create microflow Module.ACT_DoSomething ("$Name": String)
```

Also applies to `@param` in doc comments: write `@param Name`, not `@param $Name`.

---

## Current User — Two Separate Mechanisms

### `$currentUser` — microflow expression variable

Always in scope in every microflow. Use for audit fields and expressions:

```mdl
$Record = create Module.MyEntity (
  "CreatedBy" = $currentUser/Name,
  "CreatedOn" = [%CurrentDateTime%]
);
```

### `[%CurrentUser%]` — XPath constraint token (GUID only)

Valid only inside XPath constraint strings in `retrieve` WHERE clauses:

```mdl
retrieve $MyItems from Module.MyEntity
  where [System.owner = '[%CurrentUser%]']
  limit 1;
```

**Never** use `[%CurrentUser%]` as a string expression value — it stores as the literal text.

---

## Page → Microflow Data Passing: Objects Only

A page can ONLY pass entity objects (persistent or NPE) to a microflow — not individual String/Integer/Decimal values. This is a hard Mendix platform constraint.

```mdl
-- WRONG: microflow takes strings (cannot be called from a page button)
create microflow Module.ACT_Save ("Name": String, "PostalCode": String)

-- CORRECT: microflow takes an entity object
create microflow Module.ACT_Save ("Input": Module.InputDto)
begin
  declare $Name String = $Input/Name;
  ...
end;
```

With nested DataViews, a button has access to objects from all enclosing DataViews — each is wired to the corresponding microflow parameter automatically.

---

## NPE as Form Backing Object ("Dto" Pattern)

Non-Persistent Entities (NPEs) used as form backing objects are named with the `_Dto` suffix. They are in-memory only — never committed.

1. Init microflow creates a new NPE, sets defaults, returns it. Page calls this on load via data source.
2. Page DataView binds to the NPE. Widgets bind to its attributes.
3. Button calls microflow passing the NPE. Microflow reads `$Dto/AttributeName` and creates/updates persistent entities.
4. The NPE is never committed.

**NPE association retrieval — mxcli limitation:**
`declare $Var NPE.Entity = $Other/Assoc` generates a "Create Variable" activity (not "Retrieve by Association"), causing type errors. mxcli cannot generate a correct "Retrieve by Association" for NPEs. Fix in Studio Pro: delete the "Create Variable" activity, replace with "Retrieve" configured as "By Association".

**Cross-module NPE associations:** must be created in Studio Pro — BUG-02 applies equally.

---

## Association Direction — Reading SHOW ASSOCIATIONS Correctly

Mendix association terminology is **opposite** to most ORMs:

| Mendix term | Mendix meaning | ORM meaning |
|-------------|---------------|-------------|
| Parent | MANY side — owns the FK column | ONE side |
| Child | ONE side — referenced entity | MANY side |

```
SHOW ASSOCIATIONS: Parent=ChoiceOrg, Child=PayerApplicationHeader
→ Many ChoiceOrg → One PayerApplicationHeader. ChoiceOrg has the FK.

DESCRIBE ASSOCIATION: from ChoiceOrg to PayerApplicationHeader
→ from = MANY (owner), to = ONE (referenced)

Studio Pro visual (ground truth): ChoiceOrg (*) ──► (1) PayerApplicationHeader
```

**Never propose flipping an association based solely on SHOW ASSOCIATIONS output** — the Parent/Child labels are misleading. Verify from the Studio Pro visual (`*` = many, `1` = one) before any association change.

---

## Association Paths in Expressions — No Module Prefix

**Rule:** In Mendix expressions (microflow expressions, dynamic class, XPath, contentparams), association path traversal uses just the **association name** — no module prefix.

```
-- CORRECT
$currentObject/PayerDetail_PayerApplicationHeader/PayerApplicationHeader_ApplicationCommonHeader/Status

-- WRONG — module prefix causes expression error
$currentObject/PayerRegistration.PayerDetail_PayerApplicationHeader/PayerRegistration.PayerApplicationHeader_ApplicationCommonHeader/Status
```

This applies in: dynamic class expressions, XPath constraints, microflow expressions, contentparams paths.

---

## Association Direction — Setting in Microflows

An association can be set from either side when both objects are in scope:

```mdl
-- Standard: change the child (FK owner)
change $SearchResult (PayerRegistration.PayerDetail_Dto_CompanySearchResult = $Dto)

-- Fallback: change the parent (same effect)
change $Dto (PayerRegistration.PayerDetail_Dto_CompanySearchResult = $SearchResult)
```

If the child-side `change` fails, try the parent-side before diagnosing further.

---

## NPE → PE Data Transfer — Pass as Parameter, Never Retrieve

**Rule:** When a microflow needs to read data from an NPE Dto (e.g. to copy fields into a persistent entity), always accept the NPE as a **direct parameter** — never attempt to retrieve it via association inside the microflow.

mxcli silently translates `retrieve $Var from $Obj/NPE_Assoc limit 1` into a database retrieve, which fails with CE0056 because NPEs have no database table. The correct Mendix activity type would be "Retrieve by Association" (in-memory), but mxcli cannot generate that for NPEs.

**Correct pattern:**
```mdl
create or replace microflow Module.ACT_Save (
  "Dto": Module.PayerDetail_Dto,
  "AreaDto": Module.PayerArea_Dto      -- pass NPE directly; do NOT retrieve inside
)
```

**Wrong pattern (generates CE0056):**
```mdl
retrieve $AreaDto from $Dto/Module.AreaDto_Assoc limit 1;  -- mxcli drops the association path
```

Apply this proactively — don't wait for CE0056. If you're about to write a retrieve for an NPE, switch to parameter passing before writing the script.

---

## XPath Retrieve Guards — Always Add When XPath Storage Is Uncertain

**Rule:** Any `retrieve ... where [...]` that uses a cross-module association path MUST include a post-retrieve guard and a `@annotation` with the exact XPath string. mxcli (BUG-15b) cannot reliably write complex XPath constraints into Studio Pro's constraint field — the retrieve may run as an unfiltered table scan at runtime without any visible error.

**When to apply:** any retrieve whose WHERE clause uses an association path (e.g. `[AssocModule.Assoc/Module.Entity/Attr = $X]`). Simple direct-attribute XPath (`where Attr = $X`) appears to work for same-entity conditions.

**Pattern — post-retrieve guard for direct attribute:**
```mdl
@annotation 'BUG-15b: XPath may be empty in Studio Pro. Required constraint: [CustomerCode = $ExistingCustomerCode]'
retrieve $ExistingPayerDetail from PayerRegistration.PayerDetail
  where [CustomerCode = $ExistingCustomerCode]
  limit 1;

if $ExistingPayerDetail/CustomerCode != $ExistingCustomerCode then
  log error node 'PayerRegistration'
    'WRONG RECORD -- got CustomerCode=' + $ExistingPayerDetail/CustomerCode + ' expected=' + $ExistingCustomerCode
    + '. Fix: open retrieve in Studio Pro, set Constraint=[CustomerCode = $ExistingCustomerCode]';
  return empty;
end if;
```

**Pattern — guard when no direct attribute is available (cross-entity association path):**
```mdl
@annotation 'BUG-15b: XPath may be empty. Required constraint: [PayerRegistration.PayerDetail_PayerCustomerBase/PayerRegistration.PayerDetail/CustomerCode = $CCode]'
retrieve $ExistingBase from Customer_Common.PayerCustomerBase
  where [PayerRegistration.PayerDetail_PayerCustomerBase/PayerRegistration.PayerDetail/CustomerCode = $CCode]
  limit 1;

if $ExistingBase = empty then
  log error node 'PayerRegistration'
    'No record found for CustomerCode=' + $CCode
    + '. If Studio Pro Constraint field is empty, add: [PayerRegistration.PayerDetail_PayerCustomerBase/PayerRegistration.PayerDetail/CustomerCode = $CCode]';
  return empty;
end if;
```

**Annotation strings:** MDL annotation strings are single-line only. Newlines inside `@annotation '...'` cause parse errors. Keep annotations to one line per `@annotation` statement.

**Notify user:** when a script contains a retrieve with XPath that may not store correctly, explicitly state in the session output: "STUDIO PRO ACTION REQUIRED — check Constraint field of retrieve X". Do not silently continue.

---

## Annotations — Add Proactively on Every Key Activity

**Rule:** Add `@annotation` above every meaningful activity in generated microflows. Mendix microflows have no inline comments — annotations are the only in-flow documentation available to developers reviewing Studio Pro.

Annotate especially:
- Activities that interact with cross-module microflows (explain what the external MF does and why)
- Any activity that involves an NPE → PE copy (explain: "copying from in-memory Dto — cannot commit Dto directly because it is an NPE")
- Any activity where a known mxcli limitation applies (explain the intent and the workaround)
- Loop bodies (explain what each iteration produces)
- Status transitions (explain what the new status means)

When a CE error fires on an activity, the annotation should preserve the original intent: "Was trying to retrieve AreaDto via association — failed CE0056 (NPE); now passed as parameter instead."

---

## Mendix-First Design — Avoid the OutSystems Dto Pattern

**Rule:** For new functionality, default to Mendix-native data flow — persistent entities bound directly to DataViews, committed on save. Only introduce a `_Dto` NPE when genuinely necessary (e.g. aggregating fields from multiple unrelated entities into one flat form).

**Why the Dto pattern exists in this codebase:** inherited from OutSystems, where data flows through screen-local variables (typed copies, not live object references). OS always requires an explicit field-by-field copy on save. Mendix does not — a PE edited in a DataView is committed in place, no copy needed.

**The Dto pattern costs:** extra entity, extra copy-on-save microflow, CE0056 on every NPE retrieve, no ability to commit Dto directly. These costs are unnecessary in Mendix for most forms.

**When designing new features:** ask first — can the page bind directly to the real PE and commit it? If yes, do that. Skip the Dto.

---

## Additional MDL Syntax Rules

- **RETRIEVE syntax:** `retrieve $Var from Module.Entity where [...];` — NOT `$Var = retrieve from ...`
- **Microflow datasource in page:** `datasource: microflow Module.MF` — no `()` after name
- **DataView cannot use association datasource** — CE6705. Use `dynamictext contentparams` with association traversal path for read-only display.
- **`datagrid` = old widget** — Mendix 11.10 flags CE0463. Use `gallery datasource: database from Module.Entity`. Other list widget types with association/microflow datasource also get CE0463 when created via mxcli; fix with Studio Pro "Update All Widgets".
- **Cross-module association `change`:** always `change` from the MANY/Parent side (FK owner). Setting from the ONE/Child side causes CE0854.
- **NPE RETRIEVE from DB (CE0056):** `retrieve $Var from NPE.Entity` is invalid — NPEs have no database table. Pass NPE as parameter instead (see rule above).
- **contentparams cross-module NPE traversal (CE0402):** `[{1} = Module.Assoc/Attribute]` fails when the target entity is an NPE in another module. Denormalize the field onto the source entity instead.
- **`show message` in microflows → CE0720 (mxcli bug):** `show message 'literal text'` generates `show message '{1}' objects ['literal text']`. Mendix rejects string literals in the objects list (only variable refs allowed) → CE0720. Even `show message '{1}' objects [$Var]` is broken: mxcli inserts a rogue `'{1}'` literal as the first objects item. **Workaround:** use `log error` for server-side recording + wire the Show Message activity manually in Studio Pro if user-visible feedback is needed.
- **`validation feedback $Dto/Attr message '...'` → CE0639 (mxcli bug):** mxcli stores the attribute path string but does NOT wire the Variable property in the underlying BSON → CE0639 "No variable selected". **Workaround:** use `log error` + configure Validation Feedback manually in Studio Pro (open the activity, set Variable = $PayerDetail_Dto, Member = AttributeName, Message = 'text').
- **`not expr` → CE0117:** Mendix requires parentheses: `not(expr)`. `not $IsValid` is rejected. Always write `not($IsValid)`.
- **LESSON-03:** Always use fully-qualified `Module.EntityName` in the `returns` clause. Unqualified entity names (e.g. `returns PayerDetail as $Var`) cause CE1613 "entity no longer exists" because the model checker cannot resolve the type. Always write `returns PayerRegistration.PayerDetail as $PayerDetail`.
- **LESSON-04 — `retrieve $X from $obj/Assoc limit 1` → CE0018 + CE0136 (mxcli BUG):** mxcli generates a "Retrieve by Association" BSON activity with empty `Association` and `Entity` properties. Mendix rejects these with CE0018 ("Association property required") and CE0136 ("Entity property required"). **Fix:** replace with XPath DB retrieve: `retrieve $X from Module.Entity where [AssocPath/Module.Entity/Attr = $var] limit 1;`. **Pre-flight before using XPath:** (1) target entity is persistent (not an NPE), (2) all entities in the XPath path are persistent, (3) all objects being filtered on are committed to the DB — XPath queries the database, not in-memory objects. If any condition fails, use a different approach (pass as parameter, loop retrieve, etc.).
- **Microflow canvas layout — RESET LAYOUT, not @position (LESSON-01+02):**
  - `@position(x, y)` stores coordinates for individual activities but does NOT position the start event, end events, or merge nodes. Those are placed by mxcli at default coordinates that conflict with manual @position values, producing stacked or misaligned flows. `@position` is effectively useless for controlling visual layout.
  - **Correct approach:** add `reset layout` between the signature and `begin`. This clears all `relativeMiddlePoint` positions. Studio Pro re-runs its auto-layout on next open, producing a clean horizontal flow automatically.
  - **Syntax:** `create or modify microflow Module.Name (...) returns ... reset layout begin ... end;`
  - **Rule:** always add `reset layout` to any `create or replace` / `create or modify` microflow script. Never rely on `@position` for layout control.
  - **If/else branch geometry (for future reference when @position is fixed):** true branch (abort) → X > decision, Y < decision (goes up); false branch (main path) → X > decision, Y > decision (goes down). Both branches must have X > the decision diamond's X.

---

## Validation Feedback — Correct Pattern (from ACT_PayerDetail_Save)

**Rule:** Use `validation feedback` directly — no `log error` alongside it, no annotations.

```mdl
IF trim($Dto/FieldName) = '' THEN
  SET $IsValid = false;
  VALIDATION FEEDBACK $Dto/FieldName MESSAGE 'Japanese message';
END IF;
```

**GRANT syntax:** Short role names only — `Admin, User` NOT `PayerRegistration.Admin`.

**CE0639 is unavoidable via mxcli:** mxcli does not wire the Variable property in validation feedback BSON. After exec, open the microflow in Studio Pro → for each feedback activity → set Variable = $Dto, Member = attribute. One Studio Pro session fixes all.

**Do NOT add `log error` before validation feedback** — it is not the project pattern and adds noise.

---

## Retrieve by Association — Never Use `$Dto/Module.Assoc` Form

`retrieve $Var from $Obj/Module.AssocName` generates CE0018 (Association property empty in BSON). Always use XPath retrieve instead:

```mdl
-- WRONG (CE0018)
retrieve $SearchResult from $Dto/PayerRegistration.PayerDetail_Dto_CompanySearchResult;

-- CORRECT
retrieve $SearchResult from PayerRegistration.CompanySearchResult
  where [PayerRegistration.PayerDetail_Dto_CompanySearchResult = $Dto]
  limit 1;
```
