# Wengao fork (engalar/mxcli) — Section A retest against newest build `bc3d94ef4-dirty` — 2026-08-07

Investigation only. No GitHub issues filed. No real Mendix project touched — all testing done
in scratch sandboxes copied from `/private/tmp/mx-baseline/`.

## Why this report exists

The shareable bakeoff writeup (`~/Mendix/personal-toolkit/share/wengao-mxcli-bakeoff-2026-08-05/README.md`)
Section A lists 6 fork-only defects found on Wengao's **old** build (`26f2866`, 2026-07-31/08-05
bakeoff). Only 1 of the 6 (ENGALAR-01 / BUG-46+BUG-55b, the security `GRANT EXECUTE ON MICROFLOW`
crash) has been retested against his **newest** build, `bc3d94ef4-dirty` — confirmed FIXED in
`wengao-5aug-retest-2026-08-06.md`. The other 5 had never been retested against
`bc3d94ef4-dirty` at all. This report closes that gap for all 5, so the shared README isn't
updated on a partial picture.

**Net result: all 5 are still broken, with symptoms identical to the original `26f2866`
findings.** Only ENGALAR-01 has been fixed so far.

## Gate 0 — binary tested

- Location: `/tmp/wengao-mxcli-5aug-test/mxcli` — reused as-is, not re-extracted. Still present
  from the prior 2026-08-06 retest session (`wengao-5aug-retest-2026-08-06.md`, Gate 0), which
  itself extracted it from `~/Downloads/mxcli-engalar-5Aug.zip`.
- **Verified with `--version`** (checked once, then re-verified per-sandbox after copying):
  ```
  $ /tmp/wengao-mxcli-5aug-test/mxcli --version
  mxcli version bc3d94ef4-dirty (2026-08-05T04:41:15Z) commit bc3d94ef46be725503363e38239aaa0bd0306ee8
  ```
  Matches the exact identity string expected going in — Wengao's own local build (`-dirty`
  suffix = uncommitted changes on top of `bc3d94ef4`), not a tagged release.
- Fork: `engalar/mxcli` (third-party fork of `mendixlabs/mxcli`). Uses `{ }` brace syntax for
  microflow bodies, not RnD's `begin ... end` (relevant to BUG-47's repro below).

## Sandbox setup

Five fresh copies of the clean baseline project (`/private/tmp/mx-baseline/EmptyTest.mpr` +
`mprcontents/` etc.), each with the binary copied in, one per bug:

- `/tmp/wengao-sectionA-2026-08-07/bug35/`
- `/tmp/wengao-sectionA-2026-08-07/bug37/`
- `/tmp/wengao-sectionA-2026-08-07/bug42/`
- `/tmp/wengao-sectionA-2026-08-07/bug47/`
- `/tmp/wengao-sectionA-2026-08-07/bug53/`

Same ambient baseline noise as every prior retest in this series applies here too:
`EmptyTest.mpr` already carries a pre-existing `CE0066` on module `RouteShowcase` and two
`CE5015` "Root" MinOccurs/MaxOccurs errors, present in every `mx check` run below regardless of
which repro ran — baseline noise, not a finding. Baseline `mx check` total is **3 errors**;
anything beyond 3 is attributable to the repro under test.

Never touched a real/live project `.mpr` — scratch copies only, per instruction.

---

## BUG-35 / ENGALAR-02 — `autochangedby`/`autocreateddate`/`autochangeddate` grammar — **FAIL (still broken)**

**Sandbox:** `/tmp/wengao-sectionA-2026-08-07/bug35/`

**Repro (`repro-35.mdl`, identical to `BUG-35.md`):**
```
create module ZKT35;
/
create persistent entity ZKT35.Widget (
  "Name": String(100),
  "ChangedBy": autochangedby,
  "CreatedDate": autocreateddate,
  "ChangedDate": autochangeddate
);
```

This bug is a hard parse failure, not a write-path/read-back distinction — nothing is ever
written, so no BSON check applies (per the detail file's own framing).

**`check`:**
```
$ ./mxcli check repro-35.mdl -p EmptyTest.mpr
Checking syntax: repro-35.mdl
Syntax errors found:
  - line 5:15 mismatched input 'autochangedby' expecting {...long token list..., IDENTIFIER, QUOTED_IDENTIFIER}
  - line 6:17 mismatched input 'autocreateddate' expecting {...}
  - line 7:17 mismatched input 'autochangeddate' expecting {...}
parse failed with 3 error(s)
EXIT: 1
```

**`exec` (same parse failure, nothing written):**
```
$ ./mxcli exec repro-35.mdl -p EmptyTest.mpr
Connected to: /tmp/wengao-sectionA-2026-08-07/bug35/EmptyTest.mpr (Mendix 11.12.0)
Parse error: line 5:15 mismatched input 'autochangedby' expecting {...}
Parse error: line 6:17 mismatched input 'autocreateddate' expecting {...}
Parse error: line 7:17 mismatched input 'autochangeddate' expecting {...}
parse failed with 3 error(s)
EXIT: 1
```

**Confirmed nothing was written (fresh process, separate from the one that ran `exec`):**
```
$ ./mxcli -p EmptyTest.mpr -c "DESCRIBE ENTITY ZKT35.Widget"
Connected to: /tmp/wengao-sectionA-2026-08-07/bug35/EmptyTest.mpr (Mendix 11.12.0)
Error: entity not found: ZKT35.Widget (duration: 1.022958ms)
EXIT: 1
```

**Result: FAIL — bug still present, identical symptom.** Same 3 parse errors, same tokens
rejected as on `26f2866`. `AUTOCHANGEDBY_TYPE`/`AUTOCREATEDDATE_TYPE`/`AUTOCHANGEDDATE_TYPE`
still not wired into the grammar's `dataType`/`nonListDataType` rules on this build. Not fixed.

---

## BUG-37 / ENGALAR-03 — COMBOBOX in association mode — **FAIL (still broken)**

**Sandbox:** `/tmp/wengao-sectionA-2026-08-07/bug37/`

**Repro (`repro-37.mdl`, identical to `BUG-37.md`):** creates `ZKT37.Customer`/`ZKT37.Order` +
association, then a page with a `combobox` bound via `Association:` + `datasource: database` +
`CaptionAttribute:`.

This is a write-path bug (the binding is dropped while writing, not rejected at parse time), so
both `describe` (independent read, fresh process) and `mx check` (an entirely separate tool —
Studio Pro's `mx`) were used as two independent oracles.

**`check --references`:**
```
$ ./mxcli check repro-37.mdl -p EmptyTest.mpr --references
  ✓ Check passed! (5 statements)
EXIT: 0
```

**`exec`:**
```
$ ./mxcli exec repro-37.mdl -p EmptyTest.mpr
Connected to: /tmp/wengao-sectionA-2026-08-07/bug37/EmptyTest.mpr (Mendix 11.12.0)
Created module: ZKT37
Created entity: ZKT37.Customer
Created entity: ZKT37.Order
Created association: ZKT37.Order_Customer
Created page ZKT37.OrderEdit
EXIT: 0
```

**`describe` (fresh process, separate from the one that ran `exec`):**
```
$ ./mxcli -p EmptyTest.mpr -c "DESCRIBE PAGE ZKT37.OrderEdit"
create or modify page ZKT37.OrderEdit (
  title: 'Order',
  layout: Atlas_Core.Atlas_Default,
  params: { $Order: ZKT37.Order }
) {
  dataview dv (datasource: $Order) {
    -- Context: $currentObject (Order)
    pluggablewidget 'com.mendix.widget.web.combobox.Combobox' cmbCustomer (label: 'Customer')
  }
}
EXIT: 0
```
`Association:`, `DataSource:`, and `CaptionAttribute:` are silently absent — identical to the
`26f2866` symptom (bare pluggable widget with only `label:`).

**`mx check` (independent tool — Studio Pro's own `mx`, with `--update-widgets` used to get past
a benign CE0463 false-positive on v2-format projects, per the tool's own warning):**
```
$ ./mxcli docker check -p EmptyTest.mpr --update-widgets
[error] [CE0066] ... 'RouteShowcase'                                          <- baseline, unrelated
[error] [CE0642] "Property 'Entity' is required." at Combo box 'cmbCustomer'  <- NEW, caused by this script
[error] [CE5015] ... 'MinOccurs' ... 'Root'                                    <- baseline, unrelated
[error] [CE5015] ... 'MaxOccurs' ... 'Root'                                    <- baseline, unrelated
The app contains: 4 errors.
EXIT: 1
```
`CE0642` confirms independently (via a completely separate loader) that the association binding
never reached the model — exact same signature as the original `26f2866` finding.

**Result: FAIL — bug still present, identical symptom.** Wengao's combobox-association write
path is still dropping `Association:`/`DataSource:`/`CaptionAttribute:`. Not fixed.

---

## BUG-42 / ENGALAR-04 — Pluggable DataGrid2: `Action:` + `DynamicCellClass` + filters — **FAIL (still broken)**

**Sandbox:** `/tmp/wengao-sectionA-2026-08-07/bug42/`

**Repro (`repro-42.mdl`):** native `DATAGRID` variant from `BUG-42.md` (Engalar's own docs mark
the pluggablewidget+filter+attributes path as gallery-only, so the native-keyword form is the
correct dialect choice here, same as the original retest did) — one column with `DynamicCellClass`
+ `textfilter`, one column with `dropdownfilter`, and a row-click `Action:`.

This is a **silent write-path drop** (no error at any stage), so BSON was inspected directly in
addition to `describe` and `mx check`, per the write-path/read-back distinction called out in the
detail file.

**`check --references` and `exec` — both clean, no warnings:**
```
$ ./mxcli check repro-42.mdl -p EmptyTest.mpr --references
  ✓ Check passed! (5 statements)

$ ./mxcli exec repro-42.mdl -p EmptyTest.mpr
Created module: ZPLM42
Created enumeration: ZPLM42.Status
Created entity: ZPLM42.Item
Created page ZPLM42.ItemDetail
Created page ZPLM42.NativeGridTest
EXIT: 0
```

**`describe` (fresh process):**
```
$ ./mxcli -p EmptyTest.mpr -c "DESCRIBE PAGE ZPLM42.NativeGridTest"
create or modify page ZPLM42.NativeGridTest (title: 'Native Grid Test', layout: Atlas_Core.Atlas_Default) {
  datagrid dgNative (datasource: database from ZPLM42.Item sort by Code asc) {
    -- Context: $currentObject (ZPLM42.Item), $dgNative (selection)
    column colCode (
      attribute: Code,
      caption: 'Code',
      DynamicCellClass: 'if ($currentObject/Status = ZPLM42.Status.Closed) then ''text-danger'' else '''' '
    )
    column colStatus (attribute: Status, caption: 'Status')
  }
}
EXIT: 0
```
`Action:` (row-click) and **both** `textfilter fCode` / `dropdownfilter fStatus` are gone. Only
`DynamicCellClass` survived — identical shape to the `26f2866` finding.

**`mx check` — clean, exactly the 3-error baseline (no error at `dgNative`, confirming the drop
is silent, not a rejection):**
```
$ ./mxcli docker check -p EmptyTest.mpr
[error] [CE0066] ... 'RouteShowcase'   <- baseline
[error] [CE5015] ... x2 ... 'Root'      <- baseline
The app contains: 3 errors.
EXIT: 1
```

**BSON verification (source of truth):**
```
$ FILE=$(find mprcontents -iname "*.mxunit" | xargs grep -l "dgNative")
$ strings "$FILE" | grep -n -A40 "^dgNative$"
...
Action
$Type
Forms$NoAction        <-- the row-click Action: was written as an explicit "no action", not dropped-then-defaulted
DisabledDuringExecution
AttributeRef
DataSource
EntityRef
...
```
The widget's `Action` object is stored with `$Type: Forms$NoAction` — direct BSON confirmation
that the row-click action never made it into the model. A further grep for `colCode`/`colStatus`
as literal strings in the same `.mxunit` returns nothing (DataGrid2 column config is
JSON-serialized, not plaintext, inside the widget's embedded properties) and no `TextFilter`/
`DropdownFilter` tokens appear anywhere in the file — consistent with both filters never being
written either.

**Result: FAIL — bug still present, identical symptom (silent drop, not a rejection).** `Action:`
and both filters still vanish from the write path when combined with `DynamicCellClass`. Not fixed.

---

## BUG-47 / ENGALAR-05 — validation feedback attribute-path `Variable` binding — **PASS (works correctly, consistent with prior finding)**

**Sandbox:** `/tmp/wengao-sectionA-2026-08-07/bug47/`

**Repro (`repro-47.mdl`):** used the **Engalar-dialect** variant from `BUG-47.md` (`{ }`
microflow body, `ZBUG47B`) since this build uses brace syntax, not `begin...end`.

This is a check-time claim (`CE0639`/blank `Attribute`), not a write-path/read-back distinction
per the detail file's oracle — `describe` (a fresh-process read) plus `mx check` (independent
tool) are sufficient, matching the original detail file's own methodology.

**`check`, `exec` — clean:**
```
$ ./mxcli check repro-47.mdl -p EmptyTest.mpr
  ✓ Check passed! (3 statements)

$ ./mxcli exec repro-47.mdl -p EmptyTest.mpr
Created module: ZBUG47B
Created entity: ZBUG47B.Product
Created microflow: ZBUG47B.M001_ValidateProduct
EXIT: 0
```

**`describe` (fresh process):**
```
$ ./mxcli -p EmptyTest.mpr -c "DESCRIBE MICROFLOW ZBUG47B.M001_ValidateProduct"
create or modify microflow ZBUG47B.M001_ValidateProduct (
  $Product: ZBUG47B.Product
)
{
  if $Product/Code = '' {
    validation feedback $Product/Code message 'Product code is required';
  }
  if $Product/Name = '' {
    validation feedback $Product/Name message 'Product name is required';
  }
  return;
}
EXIT: 0
```
Both `validation feedback` statements round-trip with their attribute target intact — not blank.

**`mx check` — exactly the 3-error baseline, no `CE0639` anywhere:**
```
$ ./mxcli docker check -p EmptyTest.mpr
[error] [CE0066] ... 'RouteShowcase'   <- baseline
[error] [CE5015] ... x2 ... 'Root'      <- baseline
The app contains: 3 errors.
EXIT: 1
```

**Result: PASS — attribute-path `validation feedback` still wires correctly, consistent with the
original `26f2866` finding for this exact shape (`BUG-47.md` scored this PASS on both forks
already — no regression, no change).** Note: this was never a "fork-only defect that got fixed";
`BUG-47.md` already found the attribute-path form worked on `26f2866` too. Wengao's narrower,
self-documented gap (object-only `validation feedback $Object message '...'` with no attribute,
which its own fixture `358-validation-feedback-targets.mdl` flags as producing a blank
`Attribute` / `CE0091`) was **not** retested here — out of scope for BUG-47/ENGALAR-05, which is
specifically about the attribute-path form.

---

## BUG-53 / ENGALAR-06 — `Visible:` expression on ACTIONBUTTON inside a plain DataView — **FAIL (still broken)**

**Sandbox:** `/tmp/wengao-sectionA-2026-08-07/bug53/`

**Repro (`repro-53.mdl`, identical to `BUG-53.md`):** entity with `IsActive: boolean`, a page
with a plain `dataview`, an `actionbutton` with `visible: [IsActive = true]`.

This is a write-path bug (the `$currentObject/` qualifier is lost while writing, not a
`StorageLoadException` as originally speculated), so BSON was inspected directly in addition to
`describe` and `mx check`.

**`exec` — clean:**
```
$ ./mxcli exec repro-53.mdl -p EmptyTest.mpr
Created module: ZWA53
Created entity: ZWA53.Widget
Created page ZWA53.Widget_Edit
EXIT: 0
```

**`describe` (fresh process):**
```
$ ./mxcli -p EmptyTest.mpr -c "DESCRIBE PAGE ZWA53.Widget_Edit"
create or modify page ZWA53.Widget_Edit (
  title: 'Widget Edit',
  layout: Atlas_Core.PopupLayout,
  params: { $entity: ZWA53.Widget }
) {
  dataview dv1 (datasource: $entity) {
    -- Context: $currentObject (entity)
    textbox txtName (label: 'Name', attribute: Name)
    actionbutton btnConditional (
      caption: 'Conditional',
      action: save_changes,
      buttonstyle: primary,
      visible: [IsActive=true]          <-- NOT qualified with $currentObject/
    )
    footer footer1 { ... }
  }
}
EXIT: 0
```

**`mx check`:**
```
$ ./mxcli docker check -p EmptyTest.mpr
[error] [CE0066] ... 'RouteShowcase'                                              <- baseline
[error] [CE0117] "Error(s) in expression." at Action button 'btnConditional'      <- NEW, caused by this script
[error] [CE5015] ... x2 ... 'Root'                                                 <- baseline
The app contains: 4 errors.
EXIT: 1
```

**BSON verification (source of truth):**
```
$ FILE=$(find mprcontents -iname "*.mxunit" | xargs grep -l "btnConditional")
$ strings "$FILE" | grep -n -B2 -A18 "btnConditional"
Forms$ActionButton
Name
btnConditional
Appearance
$Type
...
Conditions
Expression
IsActive=true      <-- stored verbatim, unqualified, no $currentObject/ prefix
SourceVariable
ModuleRoles
```
The raw BSON confirms the stored `Expression` is the literal unqualified string `IsActive=true` —
matches both the `describe` echo and the `CE0117` at `mx check` exactly.

**Result: FAIL — bug still present, identical symptom.** Wengao's DATAVIEW-scoped
`ACTIONBUTTON`/`Visible:` expression resolver still fails to qualify bare attribute references
against `$currentObject`. Not fixed. (As before: this is a genuine `CE0117` validation error, not
the originally-speculated silent BSON corruption / `StorageLoadException` — that theory still
does not reproduce on either fork.)

---

## Summary table

| # | Bug | Detector | `26f2866` (original) | `bc3d94ef4-dirty` (this retest) | Verdict |
|---|---|---|---|---|---|
| 1 | BUG-35 / ENGALAR-02 — `autochangedby`/`autocreateddate`/`autochangeddate` grammar | parse error | FAIL | **FAIL** — identical 3 parse errors | Still broken |
| 2 | BUG-37 / ENGALAR-03 — COMBOBOX association mode | `CE0642`, silent drop on write | FAIL | **FAIL** — identical `CE0642`, `describe` shows bare widget | Still broken |
| 3 | BUG-42 / ENGALAR-04 — DataGrid2 `Action:`+`DynamicCellClass`+filters | silent drop, no error | FAIL | **FAIL** — `Action:`+both filters still silently dropped, BSON shows `Forms$NoAction` | Still broken |
| 4 | BUG-47 / ENGALAR-05 — validation feedback attribute-path | `CE0639` (not reproduced on either fork) | PASS | **PASS** — no change, attribute wires correctly | No regression, was never broken for this shape |
| 5 | BUG-53 / ENGALAR-06 — ACTIONBUTTON `Visible:` qualifier in DataView | `CE0117`, unqualified expression | FAIL | **FAIL** — identical `CE0117`, BSON shows literal `IsActive=true` | Still broken |

**Net: 4 of 5 still broken (BUG-35, BUG-37, BUG-42, BUG-53), 1 was never broken for this exact
shape (BUG-47 — already PASS on `26f2866`, no regression).** Combined with the separately-tracked
ENGALAR-01 (security `GRANT` crash, confirmed fixed in `wengao-5aug-retest-2026-08-06.md`), the
full Section A picture on `bc3d94ef4-dirty` is: **1 of 6 fixed, 4 of 6 still broken, 1 of 6 was
a non-issue for the tested shape all along.**

## Net correction for the shared README

Before sharing anything further with Wengao: Section A currently lists 6 items as confirmed
broken on the old build with no `bc3d94ef4-dirty` data point except ENGALAR-01. This report
supplies that missing data for the other 5 — the README should be updated (in a separate pass,
not by this report) to state explicitly, per item, whether it was retested against
`bc3d94ef4-dirty` and what the result was, rather than leaving 5 of 6 items silently implying
"status unknown on the newest build."

## Build/toolchain notes

No toolchain issues. Binary reused from `/tmp/wengao-mxcli-5aug-test/mxcli` (present from the
2026-08-06 retest session) without re-extracting from `~/Downloads/mxcli-engalar-5Aug.zip`.
`--version` re-verified in every sandbox after copying, per Gate 0 discipline. One incidental
note: running `mxcli docker check --update-widgets` on the BUG-37 sandbox converted its
`EmptyTest.mpr` from v2 (`mprcontents/`) to monolithic v1 format, as documented by the tool's own
warning — this was necessary to get past a benign `CE0463` false-positive and see the real
`CE0642`, and is isolated to that one scratch sandbox (not the baseline, not other sandboxes, not
any real project).
