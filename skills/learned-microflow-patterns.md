# Microflow Patterns — MDL Microflow & Association Rules for This Project
**Applies to:** any mxcli project.

Re-probed on mxcli v0.24.0 / Mendix 11.13.0 (2026-09-30); rules that now work or that `mxcli check` catches were removed.

---

## Microflow Size — Split Into Sub-Microflows Before Drafting, Not After

Decide this **before** writing a microflow, not after a lint pass catches it. A single seed/stub
microflow with dozens of create-object-per-record blocks (e.g. one CREATE+COMMIT per row of a
16-row dataset) balloons past any reasonable size fast — this project hit ~93 activities in one
microflow (`PLM_GetExclusiveParts`, a PLM parts-flow project, 2026-07-23) before anyone noticed.

**Guideline, not a hard cap:** the Mendix docs limit is 25 elements; lint's `QUAL003` warns at 25 and
`CONV009` (mxcli-bundled `assess-quality` skill) flags at 15 — but both count **top-level activities
only**, so loop bodies are invisible to them: count those by hand (`microflow-preflight.md`). If a
task naturally produces more (bulk seed data, a long linear pipeline), prefer splitting into
sub-microflows by responsibility — e.g. one sub-microflow per entity/record-type being created,
called in sequence from a thin orchestrating microflow — over one flat monolith. But some
microflows genuinely can't be meaningfully shrunk (a single cohesive validation/decision sequence
with real branching, for instance) — don't force an artificial split that just adds indirection
without improving anything — treat the numbers as signals to *consider* a split, not a rule to
satisfy mechanically.

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

**Never** use `[%CurrentUser%]` as a string expression value. v0.24.0: `check` and `exec` pass it and `mx check` gives `[CE0117] Error(s) in expression` — it is not stored as literal text. In an expression write `$currentUser/Name`; `$currentUser` also works directly inside XPath.

**Nor in any microflow a system session can reach** — a published REST operation without
platform authentication, a scheduled event, a Java action's system context. The runtime refuses
the retrieve (*"token cannot be used in a system session"*) and the call fails; check, exec,
mxbuild, lint and every UI journey stay green, because a browser always has a user. Field case
(a card-disbursement requirements-driven build, Mendix 11.13.0, 2026-09-27): a shared
state-change sub-microflow gained the token, and the REST start operation went from 201 to 500.
In shared microflows look the account up by login instead:

```mdl
declare $LoginName String = if $currentUser = empty then '' else $currentUser/Name;
retrieve $Account from Administration.Account where [Name = $LoginName] limit 1;
```

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

**`delete` needs it too, and a microflow DATASOURCE makes the rule sharper.** Measured on a
dashboard-publishing migration, 2026-08-31, where the same omission produced two symptoms in
opposite directions on one screen:

| Action | What the screen said | What OQL said |
|---|---|---|
| Create a dashboard | "No dashboards yet", form still filled | the row was there, correct in every field |
| Revoke a viewer | the email still listed | `0 rows` |

Both were bare `commit`/`delete`. The list in each case read a **microflow** datasource, which
the client re-evaluates only when something tells it to — so the write landed and the screen
never heard. `delete $X refresh;` is legal and is the fix for the second row.

The reason this is worth the table: **a browser test alone would have called both features
broken, and a database assertion alone would have called both working.** Neither instrument is
the check; the pair is. It is the argument for keeping the journey rung and the OQL rung as two
separate rungs rather than trusting whichever one is cheaper to run.

**Rollback semantics.** A rollback does not undo REST/SOAP/Java calls already made. Do not commit an object the error flow just rolled back, because Mendix no longer sees it as changed. Continue is only allowed on a call-microflow or a loop, and the failing activity's own changes are always lost. Scheduled-event flows: see `microflow-loop-antipatterns.md` -> "Scheduled-event flows".

---

## Every Required Attribute Is Set BEFORE the Commit — One COMMIT, as Late as Possible

`COMMIT` runs the entity's validation rules at commit time. A `NOT NULL`/required attribute set
*after* an earlier `COMMIT` in the same flow means that first commit always fails validation —
and in a page-triggered flow the failure is swallowed, so the user's first save silently
persists nothing. Order every flow: CREATE/CHANGE sets **all** required attributes and
associations → then a single `COMMIT`. If a value genuinely cannot exist before commit, the
attribute cannot be `NOT NULL` — fix the domain model, not the order. Measured consequence
(2026-08-23, sibling project): a flow committed the new object before setting `CreatedOn`
(`NOT NULL`), so the first save always failed and nothing persisted; every visual review
passed, and only a live walkthrough with a data assertion (journey rung 4 delta) found it.

---

## NPE as Form Backing Object ("Dto" Pattern)

Non-Persistent Entities (NPEs) used as form backing objects are named with the `_Dto` suffix. They are in-memory only — never committed.

1. Init microflow creates a new NPE, sets defaults, returns it. Page calls this on load via data source.
2. Page DataView binds to the NPE. Widgets bind to its attributes.
3. Button calls microflow passing the NPE. Microflow reads `$Dto/AttributeName` and creates/updates persistent entities.
4. The NPE is never committed.

**NPE retrieve from the database — CE0056.** `retrieve $Var from NPE.Entity` is invalid — NPEs have no database table. v0.24.0: `check` and `exec` pass it and `mx check` gives `[CE0056] Entity '…' cannot be retrieved from the database because it is non-persistable`. Pass the NPE to the microflow as a parameter instead. A by-association retrieve from an NPE (`retrieve $O from $Dto/Mod.Assoc`) is stored correctly.
---

## Association Direction — Reading SHOW ASSOCIATIONS Correctly

Mendix association terminology is **opposite** to most ORMs:

| Mendix term | Mendix meaning | ORM meaning |
|-------------|---------------|-------------|
| Parent | MANY side — owns the FK column | ONE side |
| Child | ONE side — referenced entity | MANY side |

```
SHOW ASSOCIATIONS: Parent=ChoiceOrg, Child=OrderApplicationHeader
→ Many ChoiceOrg → One OrderApplicationHeader. ChoiceOrg has the FK.

DESCRIBE ASSOCIATION: from ChoiceOrg to OrderApplicationHeader
→ from = MANY (owner), to = ONE (referenced)

Studio Pro visual (ground truth): ChoiceOrg (*) ──► (1) OrderApplicationHeader
```

**Never propose flipping an association based solely on SHOW ASSOCIATIONS output** — the Parent/Child labels are misleading. Verify from the Studio Pro visual (`*` = many, `1` = one) before any association change.

---

## Association Paths in Expressions — Module-Prefix Every Step

**Rule:** In a Mendix expression, write each association step **and** each entity step with its module prefix: `$Line/Shop.Line_Order/Shop.Order/Name`. The unprefixed form `$Line/Line_Order/Name` passes `mxcli check` and `exec`, then fails `mx check` with CE0117 (v0.24.0, measured in a microflow expression; `mxcli lint` does not flag it). Only a bare `= empty` test does not need the long form.

---

## Association Direction — Setting in Microflows

An association can only be set from its **owner** side — the entity it goes `from` in `DESCRIBE ASSOCIATION`, the one that holds the FK. Setting it from the other side passes `check` and `exec` and fails `mx check` with CE0854 (`Association not reachable from entity '…'`; v0.24.0, `mxcli lint` does not flag it). Same-module and cross-module associations alike. For `Line` → `Order` (Line owns the FK):

```mdl
-- Correct: set it from the owner
change $Line (Shop.Line_Order = $Order)

-- CE0854: the same association set from the non-owner side
change $Order (Shop.Line_Order = $Line)
```

If a `change` fails with CE0854, set the association from the other entity — read the direction off `DESCRIBE ASSOCIATION` first.

---

## Annotations — Selectively, on Complex or Non-Obvious Activities Only

### First: only `@annotation` shows on the canvas (the three "comment" forms)

If annotations "aren't showing up in the microflow," it's almost always because the note was
written in a form that doesn't render on the canvas. Three distinct forms land in three
different places:

| Form | Where it lands | On the canvas? |
|------|----------------|----------------|
| `@annotation 'text'` | A note on the microflow canvas (AnnotationFlow to the next statement) | **Yes — the only one that does** |
| `/** ... */` above the signature | The microflow's **Documentation** property (properties pane / right-click → Documentation) | No |
| `-- text` | MDL script comment only — **stripped on exec** | No — appears nowhere in Studio Pro |

**Rule:** For anything a reviewer should see *on the canvas*, use `@annotation`. Use `/** */`
for the formal spec-facing summary (params/returns) that belongs in the Documentation field,
and `--` only for notes to whoever reads the `.mdl`. Writing `/**` or `--` and expecting a
canvas note is the usual cause of "we're not seeing annotations." After exec, verify with
`describe microflow Module.Name` — `@`-annotations appear in its output; if they're missing
there, they weren't written as `@annotation`.

### `@annotation` binds to the next statement

An `@annotation` sits immediately before the statement it explains — an activity, an `if`, or the first statement of the flow. v0.24.0: all of these persist (`describe` shows every one). A free-floating `@annotation` at the end of the flow, before `end;`, does not parse. MDL annotation strings are single-line: a newline inside `@annotation '...'` is a parse error.

**Verify after exec:** run `DESCRIBE MICROFLOW Module.ACT_Save` and confirm the `@annotation` text appears in the output.

### Then: apply `@annotation` selectively

**Rule:** Add `@annotation` where an activity's *why* isn't obvious from its name and parameters alone — not on every activity. Mendix microflows have no inline comments, so annotations are the only in-flow documentation available to developers reviewing Studio Pro, but that makes them worth protecting from noise: an annotation on every `commit` and every simple `retrieve` trains reviewers to skip them all, including the ones that actually matter.

**Two annotation shapes, used differently:**

- **Microflow-level summary** — an `@annotation` before the first statement of a genuinely complex microflow, stating the overall approach in a sentence or two. Complements, doesn't replace, the `/** ... */` doc-comment above the microflow signature: the doc-comment is the formal spec-facing summary (params, returns, what it validates); the annotation is the in-canvas one a reviewer sees without opening the properties panel. Reserve this for microflows whose logic isn't a straightforward linear read — a 3-activity CRUD save doesn't need one.
- **Per-activity note** — attached to one specific activity, only when that activity's purpose or behavior would otherwise surprise a reviewer.

**Annotate especially (per-activity):**
- Activities that interact with cross-module microflows (explain what the external MF does and why)
- Any activity that involves an NPE → PE copy (explain: "copying from in-memory Dto — cannot commit Dto directly because it is an NPE")
- Any activity where a known mxcli limitation applies (explain the intent and the workaround)
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

- **Cross-module association `change` from the non-owner side (CE0854):** `check` and `exec` pass it; `mx check` gives `[CE0854] Cross-module association 'Mod.Assoc' is not reachable from entity 'ModB.Entity'`. Change from the owner side — see "Association Direction — Setting in Microflows".
- **`validation feedback $Obj message '...'` with no attribute → CE0091:** `check` and `exec` pass it; `mx check` gives `[CE0091] No member selected.` Always name the attribute: `validation feedback $Obj/Attr message '...'` (that form builds at 0 errors). **Where it goes:** in a `VAL_`/`SUB_` microflow, never an `ACT_` one — see the next section.
- **Microflow canvas layout — omit layout annotations (LESSON-01+02, corrected 2026-09-25):**
  - **Rule:** write no `@position` at all; mxcli's auto-layout places every statement (start, merges and ends included — `@start`/`@merge` exist and `describe` emits them). Partial hand placement is what breaks: auto-placed neighbours are not measured against hand-placed ones (MPR008/MPR011). If repairing a described flow by hand, annotate every canvas statement or none.
  - **If/else branch geometry (for future reference when @position is fixed):** true branch (abort) → X > decision, Y < decision (goes up); false branch (main path) → X > decision, Y > decision (goes down). Both branches must have X > the decision diamond's X.

---

## Validation Feedback — Correct Pattern (VAL_/SUB_ gives it, ACT_ calls and branches)

**Trigger:** writing any VAL_/SUB_/ACT_ microflow that puts `validation feedback` on user input.

**Rule 1 — placement.** `validation feedback` lives in a `VAL_` or `SUB_` microflow that returns a
verdict. The `ACT_` microflow the button calls only calls it and branches on the result: close the
page, stay open, or show a message. Name the attribute, and write no `log error` beside the
feedback, no annotations.

**Rule 2 — collect every field error, then stop once.** Inside the VAL_/SUB_: declare
`$IsValid Boolean = true`; give each field its own independent `if` that fires `validation
feedback` and `set $IsValid = false` — no `return` inside it, no `else` chaining. After the last
check, return `$IsValid`. A cross-field check guards on *its own* inputs being non-empty, never on
`$IsValid`.

**Why (placement):** CONV010 (the ACT_ content rule, `lint-rules/conv010_act_microflow_content.star`) allows
page actions, messages, sub-microflow calls, logging and control flow in `ACT_`.
`ValidationFeedbackAction` is not on that list, in the toolkit's rule or in upstream's. So feedback
written straight into `ACT_` lints red on every save flow. This section used to recommend exactly
that (the old `ACT_OrderDetail_Save` example). A field project's guest-groups build
(2026-09-27) reported that the pattern lints red.

**Why (collect-all):** early return flags one field per submit — an empty form turns the first
input red, the user fixes it, resubmits, and only then sees the second (a requirements-driven RFQ
project, 2026-09-25, reported by the product owner; a grep found 44 feedback-then-`return` sites
across 11 of its scripts).

```mdl
-- WRONG (placement): feedback inside the ACT_ (CONV010: "contains 'ValidationFeedbackAction' action")
create microflow Mod."ACT_Order_Save" ($Order: Mod."Order")
begin
  if trim($Order/Reference) = '' then
    validation feedback $Order/Reference message 'Reference is required.';
    return;
  end if;
  commit $Order;
  close page;
end;

-- WRONG (early return): the second check never runs while the first field is empty
create microflow Mod."VAL_Quote" ($Quote: Mod."Quote") returns Boolean as $IsValid
begin
  declare $IsValid Boolean = true;
  if $Quote/TotalPrice = empty then
    validation feedback $Quote/TotalPrice message 'Total price is required.';
    return false;
  end if;
  if $Quote/ValidUntil = empty then
    validation feedback $Quote/ValidUntil message 'Valid until is required.';
    return false;
  end if;
  return $IsValid;
end;

-- RIGHT: VAL_ flags every field on the same submit and returns a verdict; ACT_ calls and branches
create microflow Mod."VAL_Quote" ($Quote: Mod."Quote") returns Boolean as $IsValid
begin
  declare $IsValid Boolean = true;
  if $Quote/TotalPrice = empty then
    validation feedback $Quote/TotalPrice message 'Total price is required.';
    set $IsValid = false;
  end if;
  if $Quote/ValidUntil = empty then
    validation feedback $Quote/ValidUntil message 'Valid until is required.';
    set $IsValid = false;
  end if;
  -- cross-field: guard on ValidUntil itself, not on $IsValid
  if $Quote/ValidUntil != empty and $Quote/ValidUntil < [%CurrentDateTime%] then
    validation feedback $Quote/ValidUntil message 'Valid until must be in the future.';
    set $IsValid = false;
  end if;
  return $IsValid;
end;

create microflow Mod."ACT_Quote_Submit" ($Quote: Mod."Quote")
begin
  $IsValid = call microflow Mod."VAL_Quote"(Quote = $Quote);
  if $IsValid then
    call microflow Mod."SUB_Quote_Save"(Quote = $Quote);
    close page;
  end if;
end;
```

When the SUB_ does more than validate (the field instance was `SUB_AddGuestsToGuestGroup`,
which gives `validation feedback … 'You can add up to 50 addresses at a time.'` and returns
`'TooMany'`), return an outcome String or enumeration. The ACT_ branches on it:
`TooMany` keeps the popup open, and any other outcome shows a message and closes it.

Early return stays right for **state guards** that are not about a field (wrong status, record
missing, deadline passed → `show message`, `return false`) — run those first, then the
collect-all field block. Attribute paths stay unquoted (`$Quote/TotalPrice`); see
`learned-mdl-preflight.md`. `mxcli check` passes both shapes — only a reader or a browser
submit of an empty form tells them apart.

**GRANT syntax:** qualify the module role — `Module.Admin`, never bare `Admin`. `mxcli check` refuses the bare name (MDL-GRANT02).

---

## Enum Attribute in String Context — Use `toString($Obj/Attr)`

**Rule:** Wrap an enum attribute read in `toString()` when the result is used as a String. v0.24.0: `return $Order/Status` from a String microflow and `change $Order (Note = $Order/Status)` pass `check` and `exec`, then fail `mx check` with CE0117 (`mxcli lint` does not flag it). The concatenation form is flagged E004 by `check`, but `exec` still writes it.

```mdl
-- WRONG: enum used as string directly
set $Result = $Result + $Item/Status + '\n';

-- CORRECT
set $Result = $Result + toString($Item/Status) + '\n';
```

This applies anywhere an enum value flows into a String context: concatenation, `return`, `set`, `declare`, function arguments expecting String. Confirmed on a live project (2026-07-07).

---

## Per-row isolation in a loop: three Mendix facts, one afternoon (2026-09-07, a sales-coaching build)

The pattern "loop over rows, one bad row must not sink the file" costs three failed runs if you
do not know these; each was learned from the runtime log of an import of 222 Salesforce rows.

1. **No custom error handling inside a loop body — CE0644.** `on error continue` and
   `on error { ... }` on a call inside `loop ... end loop` both fail `mx check` (`[CE0644] Error handling type must be 'Rollback' inside a looped activity`). Move the guarded
   call into a wrapper microflow (`SUB_X_Safe` that calls `SUB_X on error ...`) and have the
   loop call the wrapper. `mxcli check` warns MDL006 for this; the warning is right.
2. **`on error { ... }` is custom WITH rollback, and the rollback is the whole outer
   transaction.** With it in the wrapper, the last row of the file failing undid 158
   successfully created deals while the run's own counters (changed in the outer flow after the
   fact) said "Succeeded, 158 created". Use `on error without rollback { ... }`: the failing
   call's changes are discarded, everything before it stays.
3. **`substring($s, 0, 200)` throws when `$s` is shorter than 200** ("Range [0, 200) out of
   bounds for length 53"). Guard it: `if length($s) > 200 then substring($s, 0, 200) else $s`.
   A truncation added for one long row broke every short one.

And the diagnostic that made 2 and 3 visible: a custom handler swallows the exception, so log
`$latestError/Message` inside it. Sixty-four rows failed with no message anywhere until then.

Count a "rejected" outcome from the rows after the loop (`retrieve ... where State = Rejected`
+ aggregate), not by incrementing in the loop: a row whose sub-transaction rolled back is both
"returned Rejected" and "still Pending", and gets counted twice.
