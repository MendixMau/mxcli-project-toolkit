# Microflow Patterns — MDL Microflow & Association Rules for This Project
**Applies to:** any mxcli project.

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

## Commit / Change / Rollback — Use `refresh` in Page-Triggered Microflows

**Rule:** Any microflow invoked from a **page** (action button, on-change, or a save/edit flow
the page returns to) that `commit`s or `change`s an object shown on that page **must** use the
`refresh` keyword so the Mendix client re-renders the updated object. Same for `rollback`.
Without it, the database updates but the client keeps the stale in-memory object — the
grid/DataView won't reflect the change until a manual reload.

```mdl
-- Page-triggered save: refresh so the calling page / grid updates immediately
commit $Item with events refresh;

-- Change that must show immediately in the client
change $Item ("Active" = false) refresh;

-- Reverting an uncommitted edit shown on the page
rollback $Item refresh;
```

**Applies to:** save / create / update / delete actions wired to a page button; anything whose
result is visible on the page the user stays on or returns to.

**Do NOT add `refresh` (it's meaningless there):**
- Before/after-commit **event handlers** and other server-side-only microflows — no client to refresh.
- Scheduled / batch / integration microflows with no page context.
- An object that is not displayed on any current page.

**Position:** `refresh` goes at the **end** of the statement, after `with events` —
`commit $X with events refresh;` (never `commit refresh $X`).

---

## NPE as Form Backing Object ("Dto" Pattern)

Non-Persistent Entities (NPEs) used as form backing objects are named with the `_Dto` suffix. They are in-memory only — never committed.

1. Init microflow creates a new NPE, sets defaults, returns it. Page calls this on load via data source.
2. Page DataView binds to the NPE. Widgets bind to its attributes.
3. Button calls microflow passing the NPE. Microflow reads `$Dto/AttributeName` and creates/updates persistent entities.
4. The NPE is never committed.

**NPE association retrieval — mxcli limitation:**
`declare $Var NPE.Entity = $Other/Assoc` generates a "Create Variable" activity (not "Retrieve by Association"), causing type errors. mxcli cannot generate a correct "Retrieve by Association" for NPEs. Fix in Studio Pro: delete the "Create Variable" activity, replace with "Retrieve" configured as "By Association".

**Cross-module NPE associations:** can be created via mxcli — BUG-02 fixed in v0.13.0.

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

## Annotations — Selectively, on Complex or Non-Obvious Activities Only

### First: only `@annotation` shows on the canvas (the three "comment" forms)

If annotations "aren't showing up in the microflow," it's almost always because the note was
written in a form that doesn't render on the canvas. Three distinct forms land in three
different places:

| Form | Where it lands | On the canvas? |
|------|----------------|----------------|
| `@annotation 'text'` | A note on the microflow canvas (AnnotationFlow to the next activity, or free-floating) | **Yes — the only one that does** |
| `/** ... */` above the signature | The microflow's **Documentation** property (properties pane / right-click → Documentation) | No |
| `-- text` | MDL script comment only — **stripped on exec** | No — appears nowhere in Studio Pro |

**Rule:** For anything a reviewer should see *on the canvas*, use `@annotation`. Use `/** */`
for the formal spec-facing summary (params/returns) that belongs in the Documentation field,
and `--` only for notes to whoever reads the `.mdl`. Writing `/**` or `--` and expecting a
canvas note is the usual cause of "we're not seeing annotations." After exec, verify with
`describe microflow Module.Name` — `@`-annotations appear in its output; if they're missing
there, they weren't written as `@annotation`.

### Critical: `@annotation` placement — never before an `if` or decision

**This is the most common cause of annotations silently not persisting.** mxcli binds an `@annotation` to the *next activity* in the flow via an `AnnotationFlow` edge. When the next element is an `if` / decision / split — not a real activity — mxcli drops the annotation entirely. The script applies and reports success, but the canvas note never appears.

**Confirmed failure at scale:** in one session, 12 annotations were written, all before `if` statements — 0 of 12 persisted. Same mxcli version annotates correctly on other flows where placement is correct.

**Safe placements:**
- At the **end of the flow**, after the last activity, before `end` — free-floating, no following element required
- Immediately **before a real activity** (create / change / retrieve / commit / call microflow / log)

**Unsafe placement (annotation silently dropped):**
- Before `if` / `else if`
- Before a decision or split
- At the very start of the flow before any activity

**Pattern — summary annotation at end:**
```mdl
create microflow Module.ACT_Save ("Input": Module.InputDto)
begin
  -- ... activities ...
  commit $Result;
  @annotation 'Saves the InputDto to the database. Validates required fields before commit.';
end;
```

**Verify after exec:** run `DESCRIBE MICROFLOW Module.ACT_Save` and confirm `@annotation` text appears in the output. Syntax-check passing does not mean the annotation persisted.

### Then: apply `@annotation` selectively

**Rule:** Add `@annotation` where an activity's *why* isn't obvious from its name and parameters alone — not on every activity. Mendix microflows have no inline comments, so annotations are the only in-flow documentation available to developers reviewing Studio Pro, but that makes them worth protecting from noise: an annotation on every `commit` and every simple `retrieve` trains reviewers to skip them all, including the ones that actually matter.

**Two annotation shapes, used differently:**

- **Microflow-level summary** — a free-floating `@annotation` (no following activity) placed once, near the start of a genuinely complex microflow, stating the overall approach in a sentence or two. Complements, doesn't replace, the `/** ... */` doc-comment above the microflow signature: the doc-comment is the formal spec-facing summary (params, returns, what it validates); the free-floating annotation is the in-canvas one a reviewer sees without opening the properties panel. Reserve this for microflows whose logic isn't a straightforward linear read — a 3-activity CRUD save doesn't need one.
- **Per-activity note** — attached to one specific activity, only when that activity's purpose or behavior would otherwise surprise a reviewer.

**Annotate especially (per-activity):**
- Activities that interact with cross-module microflows (explain what the external MF does and why)
- Any activity that involves an NPE → PE copy (explain: "copying from in-memory Dto — cannot commit Dto directly because it is an NPE")
- Any activity where a known mxcli limitation applies (explain the intent and the workaround — e.g. BUG-15b's XPath annotation pattern above)
- Loop bodies whose per-iteration effect isn't obvious from the loop variable name alone
- Status transitions whose new status value isn't self-explanatory
- **The fix for a CE error**, once resolved (see below)

**Don't annotate:** a plain `commit`/`retrieve`/`change` whose activity name and parameters already say what it does. If the annotation would just restate the activity, skip it.

**CE-error fixes must preserve the original intent, not just the fix.** When a CE error fires on an activity and gets resolved, the annotation on the fixed activity should record what was tried and why it changed: *"Was trying to retrieve AreaDto via association — failed CE0056 (NPE); now passed as parameter instead."* This is the same discipline as `iterative-build-loop.md`'s CE Error Triage — trace to requirements, don't just silence the error — the annotation is where that trace gets recorded for the next person (or agent) who reads this microflow.

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

---

## Enum Attribute in String Context — Always Use `toString($Obj/Attr)`

**Bug:** Using an enum attribute directly where a string is expected (e.g. string concatenation, `set $Str = $Obj/Status`, loop body building a result string) silently writes the raw enum key name without the module prefix, which Mendix rejects at runtime or produces a CE error.

**Rule:** Always wrap enum attribute reads in `toString()` when the result is used as a String.

```mdl
-- WRONG: enum used as string directly
set $Result = $Result + $Item/Status + '\n';

-- CORRECT
set $Result = $Result + toString($Item/Status) + '\n';
```

This applies anywhere an enum value flows into a String context: concatenation, `return`, `set`, `declare`, function arguments expecting String. Confirmed on a live project (2026-07-07).
