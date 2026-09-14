# Resolved mxcli bugs — archived 2026-09-14

Entries retested against mxcli **v0.21.0** (tag `v0.21.0`, built from source on Linux amd64)
on a blank Mendix 11.13.0 project scaffolded by `mxcli new` itself, with every build-verified
verdict resting on a real native Linux mxbuild `mx check` (auto-resolved by `mxcli docker
check` even with no Docker daemon reachable in this container). Full method, environment and
probes: [mxlabs-v0.21.0-retest-2026-09-14.md](mxlabs-v0.21.0-retest-2026-09-14.md).

Version attribution: entries stamped "≤v0.21.0" were verified fixed on v0.21.0 by this
round's own probe (DESCRIBE round-trip, `SHOW CALLERS OF`, or a full check→exec→mxbuild
pass) without a changelog line naming the fix or bisecting to the exact fixing release.
**BUG-15, BUG-68 and BUG-77 are NOT REPRODUCED rather than confirmed-fixed** — each was
re-probed from its own original repro shape in a disposable blank scratch app and came back
clean (0 errors, correct read-back), but no v0.21.0 changelog line explains why; their
verdicts are bounded by that blank-app probe, the same caveat the 2026-08-31 archive round
applied to BUG-81/BUG-97. **BUG-125 carries the same caveat.**

---

## BUG-15: `retrieve $X from $ObjVar/Module.AssocName limit 1` generates broken "Retrieve by Association" BSON

> **NOT REPRODUCED on v0.21.0 — verified 2026-09-14. `RETRIEVE $Result FROM $Detail/Retest.Detail_Order LIMIT 1;` (association-path retrieve from an object variable) execs, checks, and passes native mxbuild at 0 errors on a disposable blank-app probe. No v0.21.0 changelog line explains it — this is a clean probe, not a confirmed fix.** See [mxlabs-v0.21.0-retest-2026-09-14.md](mxlabs-v0.21.0-retest-2026-09-14.md).


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

## BUG-23: `ContentParams` with an explicit `$currentObject/` prefix resolves as a literal (broken) attribute path → CE1613

> **RESOLVED in v0.21.0 — verified 2026-09-14. Both failing forms (`toString($currentObject/State)` and the bare `$currentObject/CreatedOn`) are now refused at `mxcli check` time with a named diagnostic (MDL-WIDGET14/MDL-WIDGET24) instead of silently accepted. Changelog: "MDL-WIDGET14 claimed Mendix forbids an expression parameter. It does not."** See [mxlabs-v0.21.0-retest-2026-09-14.md](mxlabs-v0.21.0-retest-2026-09-14.md).


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

## BUG-68: Snippet datagrid columns/sort bars cannot reference system (`autocreateddate`) or generalized (inherited) attributes — resolves fine in a PAGE datagrid, fails under native mxbuild in a SNIPPET datagrid

> **NOT REPRODUCED on v0.21.0 — verified 2026-09-14. Both failing shapes (a snippet datagrid column bound to an `autocreateddate` system attribute, and one bound to an attribute inherited via `EXTENDS System.FileDocument`) build clean at 0 errors on a disposable blank-app probe. No v0.21.0 changelog line explains it.** See [mxlabs-v0.21.0-retest-2026-09-14.md](mxlabs-v0.21.0-retest-2026-09-14.md).


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

## BUG-77: BUG-75's "create/change attribute values are safe" scope claim is wrong — quoted attribute segments (`$Var/"Attr"`) DO cause CE0117 in create/change statements too, just not consistently

> **NOT REPRODUCED on v0.21.0 — verified 2026-09-14. Both a plain `CHANGE $Dst ("Name" = $Src/"Name")` and a `CREATE` on an entity extending `System.FileDocument` with a quoted attribute segment build clean at 0 errors, and `DESCRIBE` shows the quotes correctly stripped. No v0.21.0 changelog line explains it.** See [mxlabs-v0.21.0-retest-2026-09-14.md](mxlabs-v0.21.0-retest-2026-09-14.md).


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

## BUG-98: `calculated by` on an attribute is silently dropped at write time — the attribute is stored as a plain stored value, BSON-verified

> **RESOLVED in ≤v0.21.0 — verified 2026-09-14. `ALTER ENTITY … ADD ATTRIBUTE … CALCULATED BY` now wires for real: `DESCRIBE ENTITY` round-trips the clause, native mxbuild reports 0 errors, and `SHOW CALLERS OF` the calc microflow — the exact check this bug named as unreliable — now reports 1 real caller. No v0.21.0 changelog line names this fix; verdict rests on this round's own probe.** See [mxlabs-v0.21.0-retest-2026-09-14.md](mxlabs-v0.21.0-retest-2026-09-14.md).


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

## BUG-103: `DESCRIBE MICROFLOW` emits `log` strings with embedded doubled quotes that `mxcli check` then rejects — round-trip asymmetry

> **RESOLVED in v0.21.0 — verified 2026-09-14. The exact original repro (a `DESCRIBE MICROFLOW` log string with a doubled-quote escape, fed back into `mxcli check -p`) now round-trips clean. Changelog: "mxcli check no longer rejects Mendix's own apostrophe escape … It reproduced only with -p."** See [mxlabs-v0.21.0-retest-2026-09-14.md](mxlabs-v0.21.0-retest-2026-09-14.md).


**Severity:** Medium — breaks the describe→edit→exec loop for any microflow whose log message quotes a name
**mxcli version:** built from source at `4b58b89` (2026-08-26)
**Mendix version:** 11.13.0
**Discovered:** 2026-08-28, a change-governance conversion project, rebuilding a workflow-agent microflow from its own `DESCRIBE` output
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

## BUG-124: `DESCRIBE MICROFLOW` omits `without events`, so a DESCRIBE → exec round-trip silently turns event handlers back on

> **RESOLVED in ≤v0.21.0 — verified 2026-09-14. `DESCRIBE MICROFLOW` now correctly emits `commit $Obj without events;` when the stored activity has events off, closing the silent describe→exec round-trip flip this bug named. No v0.21.0 changelog line names this fix; verdict rests on this round's own probe.** See [mxlabs-v0.21.0-retest-2026-09-14.md](mxlabs-v0.21.0-retest-2026-09-14.md).


**Found:** 2026-09-07, re-emitting four start microflows in a conversion-project script.

mxcli's bare `commit $X;` now defaults to **WITH EVENTS**, matching Studio Pro. It previously
meant events OFF. That change is defensible on its own; the defect is that `DESCRIBE MICROFLOW`
prints a **bare `commit $X;` for both settings**. The events flag is not round-tripped.

So the standard repoint workflow — `DESCRIBE` a microflow, change one activity, re-exec it —
**silently flips the commit semantics of every commit in the flow that had events off**. Nothing
in the pipeline reports it: `mxcli check --references` passes, mxbuild passes, and the model is
structurally valid. The behaviour change only shows up at runtime, in whatever the handlers do.

On this project it happened to be inert — no entity in any of the seven modules declares an event
handler, checked — which is exactly why it would have shipped unnoticed on a project where one
does. mxcli's own `MDL067` info message is what flagged it, and only because the re-emitted flow
was large enough to trip the check.

**Ask:** emit `commit $X without events;` from `DESCRIBE` whenever the stored activity has events
off. A round-trip must not change behaviour. Failing that, `MDL067` should fire on **every** bare
commit in a script that also contains a `create or modify microflow`, not on a heuristic.

**Related:** BUG-103 (`DESCRIBE MICROFLOW` emits `log` strings that `mxcli check` then rejects) —
same class: `DESCRIBE` output that is not a faithful, re-executable representation of the model.

---

## BUG-125: `mxcli check --references` cannot resolve ANY enumeration in an attribute declaration

> **NOT REPRODUCED on v0.21.0 — verified 2026-09-14. Both a CREATE-time enumerated attribute and the original's exact `ALTER ENTITY … ADD ATTRIBUTE IF NOT EXISTS` form pass `mxcli check --references` clean against an enum created in an earlier, separate script. No v0.21.0 changelog line explains it.** See [mxlabs-v0.21.0-retest-2026-09-14.md](mxlabs-v0.21.0-retest-2026-09-14.md).


**Found:** 2026-09-07, a Phase-19 conversion project script `88`, mxcli against Mendix 11.13.0.

**Symptom.** Declaring an enumerated attribute makes `--references` report the enumeration missing:

```
alter entity Approval."ApprovalRun"
  add attribute if not exists "CriticalPathStation": Enumeration(Approval.StationKey);
```
```
Reference errors:
  statement 4: attribute 'CriticalPathStation': enumeration not found: Approval.StationKey
```

**The enumeration exists.** `DESCRIBE ENUMERATION Approval.StationKey` returns all 19 values, and
`SHOW ENUMERATIONS IN Approval` lists it.

**A/B probe — the fault is not the enum, the statement form, or the folder.** Four variants, one
result each:

| Probe | Result |
|---|---|
| `alter entity … add attribute … Enumeration(Approval.StationKey)` | not found |
| same, with the enum name quoted — `Approval."StationKey"` | not found |
| `create or modify non-persistent entity … ("K": Enumeration(Approval.StationKey))` | not found |
| same, with `Approval.RunStatus` — an enum a dozen live attributes already use | **not found** |

The last row is the one that settles it. `Approval.RunStatus` is referenced by
`ApprovalRun.RunStatus` in the shipped model; if the checker could resolve enumerations at all it
would resolve that one. It resolves entities, associations, microflows and pages in the same
script correctly — enumerations alone fall through.

**Impact.** Any script that declares an enumerated attribute — which is most domain-model scripts —
cannot reach a clean `--references` run. That trains the reader to skim past reference errors,
which is exactly how a real CE1613 gets shipped. On this project the same command is the pre-flight
gate for every script, so the noise is not incidental.

**Workaround.** None for the checker. Treat `enumeration not found` as noise and let mxbuild be the
gate: it validates the same declaration correctly and reports 0 errors on the applied script.

**Expected.** `--references` resolves an enumeration the same way it resolves an entity, or — if the
checker genuinely cannot see enumerations — it stays silent about them rather than reporting a
false negative.
