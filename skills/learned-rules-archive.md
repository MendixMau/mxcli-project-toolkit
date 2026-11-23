# Learned MDL rules retired on mxcli v0.32.0-374 / Mendix 11.8

**Applies to:** any mxcli project running an mxcli **older than v0.32.0-374** (or, where a row says so, a Mendix older than 11.8). On v0.32.0-374 or newer these rules are fixed or changed — the live files say what holds now.

**Purpose:** the full text of every `learned-mdl-preflight.md`, `learned-detection-gaps.md` and `learned-microflow-patterns.md` rule that the 2026-11-20 retest found fixed or changed, kept word for word so a project pinned to an older binary still has it. Projects pin different binaries; a rule deleted outright strands them (`retesting-learned-rules.md`, "Keep the old rule underneath").

**Version guard:** `v0.32.0-374` is the build 374 commits after the v0.32.0 release (`mxcli version v0.32.0-374-g591bcd73e`); v0.32.0 itself and every earlier release count as older.

**Evidence:** retest 2026-11-20 on mxcli `v0.32.0-374-g591bcd73e` (source build) against real MxBuild `mx check` 11.8.0, every probe on a fresh blank Mendix 11.8.0 app, rungs 1–4 (`check`, `exec`, `describe`/BSON read-back, `mx check`). Verdicts and the probe MDL: `bug-logs/mxcli-v0.32.0-retest-2026-11-20.md`. Studio Pro's loader and the runtime were not available, so a rule whose failure lived there is kept in the live file.

**How to read an entry:** the verdict and the v0.32.0-374 proof line, then the rule as it stood before the retest. Your mxcli is older → the old rule applies as written. Not sure → `./mxcli --version`, then the probe in `retesting-learned-rules.md`.

## From `learned-mdl-preflight.md`

### Workflow `DECISION` (header line)

**FIXED on v0.32.0-374.** The unqualified outcome is refused at `check` (`decision outcome 'Draft' is not fully qualified — Mendix cannot load a project whose EnumerationValueConditionOutcome.Value is not Module.Enumeration.Value` [MDL-WF03]) and a missing empty outcome too (MDL-WF06, CE6686). Qualified outcomes plus `'' -> { }`: `mx check` 0 errors. A Boolean decision: 0 errors. The restart defect (BUG-141) was not testable.

Before the retest:

**Still a STOP:** workflow `DECISION` activities (BUG-76) — `learned-workflow-patterns.md` §8 Warning 1; never force one with `--no-check`. Before a first `marketplace install`, read the #879 entry in `bug-logs/mxcli-bugs.md`.

### STOP #1, its ContentParams clause

**CHANGED (clause only) on v0.32.0-374.** `ContentParams: ({1} = toString(Status))` inside a customContent column still fails — `mx check` CE0117 at `Expression of text template parameter {1}`, no longer CE1613 — while `toString($currentObject/Status)` builds at 0 errors. The live STOP #12 row now carries that rule. The row's main rule (conditional Visible/Editable inside customContent) stays: `mx check` is 0 errors on v0.32.0-374, but its symptom was on Studio Pro open, which was not retested.

Before the retest:

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 1 🔎 | Use `visible:` or `editable:` **conditional expressions** on containers **inside a `datagrid customContent` column** | **STOP → Studio Pro by hand** | mxcli writes blank `AttributeIdentifier` → `StorageLoadException` on SP open; mxbuild passes clean (BUG-18). Safe CLI alternative: `dynamictext (Attribute: "State")` renders enum caption natively. Do NOT use `ContentParams: [{1} = toString("State")]` inside customContent — resolves as attribute path → CE1613. Per-value colours: set them in Studio Pro. | page |

### STOP #12 — expressions in ContentParams

**CHANGED on v0.32.0-374.** An expression builds when every attribute in it is written `$currentObject/Attr`: `$currentObject/Name`, `toString($currentObject/Status)` and `if $currentObject/Name = '' then 'none' else $currentObject/Name` pass `check`, are stored as expressions, and give `mx check` 0 errors. A bare attribute inside a function — `toString(Status)`, in a data view, in a customContent column, or in the `[ … ]` list spelling — still passes `check` and `exec` and fails `mx check` with CE0117 (was CE1613). A format-string function, `formatDecimal($currentObject/Amount, '0.00')`, also passes `check` and fails CE0117 (behaviour A/B, 2026-11-20). The live row now states the v0.32.0-374 rule.

Before the retest:

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 12 🔎 | Put anything but a bare attribute or a quoted literal in a `dynamictext`'s `ContentParams` — `toString(Attr)`, `$currentObject/Attr`, `if … then … else`, any function | **Bind a bare attribute (`{1} = Attr`) or a quoted literal, nothing else.** A computed label becomes data: a stored or derived String attribute, bound bare. Tone variants go in `DynamicClasses`, which takes a real expression (and there *needs* the prefix: `'if $currentObject/State = Enum.Value then ...'`). | An expression is stored as an attribute path → CE1613 at mxbuild; `if … then … else` passes `check` and `exec` (BUG-142). | page |

### STOP #18 — callee in the same script as the workflow

**CHANGED on v0.32.0-374.** Callee and workflow in one script: `check` passes, exec auto-fills `(Order = $WorkflowContext)`, `mx check` 0 errors (was CE0117). An existing callee left unmapped is refused at `check` (`parameter 'Order' is not mapped`).

Before the retest:

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 18 | Write **any workflow MDL** — `CREATE`/`ALTER WORKFLOW`, a `CALL MICROFLOW` step, a `JUMP TO`, user-task outcomes | **STOP → read [[learned-workflow-patterns]] first, then script. Create every callee microflow in an EARLIER script than the workflow that calls it.** Read the BRD lifecycle + wireframe before writing a single outcome. | Callee created in the same script: `check --references` skips the call, `exec` auto-fills the `WITH` mapping, `mx check` CE0117. | workflow |

### STOP #16 — path inside `[%CurrentUser/…%]`

**CHANGED on v0.32.0-374.** Refused at `check` and `exec`: `[%CurrentUser/Administration.Account_Language%] is not a Mendix token (mxbuild: CE0161 "Error(s) in XPath constraint.") [MDL-TOKEN01]`. The prescribed bare-token fix builds.

Before the retest:

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 16 🔎 | Write an access-rule XPath constraint with a **path expression inside the `[%CurrentUser/...%]` substitution token** — `[Assoc = '[%CurrentUser/Module.OtherAssoc%]']`, especially crossing module boundaries | **Never put a path inside the CurrentUser substitution. Keep it bare (`'[%CurrentUser%]'`) and do the ENTIRE multi-hop/cross-module traversal on the left-hand side instead**, qualifying the entity name at every module crossing (same rule as the "cross-module association expression paths" MDL gotcha, extended here to access-rule XPath constraints, not just microflow expressions). Was: `[Decision_Partner = '[%CurrentUser/PLM.Account_Partner%]']`. **Fix (confirmed working):** `[PLM.Decision_Partner/PLM.Partner/Administration.Account_Partner = '[%CurrentUser%]']` — walk Partner→Account fully on the left, compare directly to the (already-an-Account) CurrentUser token. | Invalid Mendix XPath, not an mxcli bug: `CE0161` every time. The fixed form is mxcli-safe — no GUI fallback. | access |

### STOP #23 — `create or modify` drops members

**CHANGED on v0.32.0-374.** `check` now warns before exec: `applying this script to the project removes 2 member(s) from entity Shop.Line that it does not restate: Qty, PF22Extra … [MDL087]`; exec warns and writes. The false `- Attribute` lines of `diff` (BUG-146) did not reproduce.

Before the retest:

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 23 | Name any document or entity that **might already exist** — `create or modify` on an entity, or any `create or replace` on a page, layout or microflow | **STOP → run `mxcli diff -p <app>.mpr <script>.mdl --format struct` FIRST.** It is read-only, it takes a second, and it prints exactly what the script would add and what it would REMOVE. (`exec` itself only warns — v0.24.0: `create or modify entity Mod.Order drops 6 existing member(s)` — and then writes.) Read the `-` lines before you exec, every time. Rules 21 and 22 tell you to write `create or modify` and to give each document one owner; this is the check that the name you chose is actually free. | `create or modify` on an entity **replaces** its attribute set; `mx check` stays clean. `diff` also prints false `- Attribute` lines (BUG-146): check each against `DESCRIBE ENTITY`. | any |

### STOP #24 — design property not in the theme

**CHANGED on v0.32.0-374.** A `check` error and exec refuses: `widget "dv1" (dataview) sets design property "Form orientation", which is not defined for this widget type — mxbuild reports CE6083 … [MDL-WIDGET11]`. The row said `check` only warns and exec writes.

Before the retest:

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 24 | Put a `DesignProperties: [...]` entry on a widget (Form orientation, Label width, Spacing, …) in an app scaffolded by `mxcli new` (any `--theme`) | **STOP → grep the theme first: `grep -l '<property name>' themesource/*/web/design-properties.json`. If it is not there, use the Atlas class instead (`Class: 'form-vertical'`, `spacing-outer-bottom-large`).** `mxcli new`'s theme layer ships a `design-properties.json` that does not carry Atlas's FormBase entries, so mxbuild rejects the property with CE6083 "not supported by your theme". v0.24.0: `check` only warns (MDL-WIDGET11), `exec` writes, `mx check` fails; lint does not flag it. `design-spacing.md` says design properties and classes write the identical model; that holds only when the theme declares the property. | CE6083 at the gate. `Class: 'form-vertical'` then built clean but changed nothing on screen where the theme's dataview rules decide the layout — the look caught it, no gate could. | page |

### STOP #31 — data-view binding across 2+ associations

**FIXED on v0.32.0-374.** `check` warns MDL-ATTRPATH01 and stores `Shop.Line_Order/Shop.Order_Customer/Name`; `mx check` 0 errors.

Before the retest:

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 31 | Bind a data-view widget's attribute across 2+ associations | **One hop per step: nest a data view.** | `check` passes; mxbuild CE1613. A database-sourced Gallery allows it: `learned-page-patterns.md` §ContentParams Multi-Hop. #445 | page |

### STOP #32 — `show page` argument outside a data view

**CHANGED (row was over-broad) on v0.32.0-374.** Passing the page's own parameter (`show page Shop.Order_Edit (Order = $Order)`) builds: stored as `Forms$PageVariable PageParameter: "Order"`, `mx check` 0 errors. Only `$currentObject` is refused (MDL-PAGEARG01).

Before the retest:

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 32 | Give a widget's `show page` any argument outside a data view/list/grid row, or besides its context object | **Call a microflow that shows the page.** | v0.26.0 `check` refuses: MDL-PAGEARG01. BUG-70/95. #445 | page |

### Gotcha — cross-module short association path

**CHANGED on v0.32.0-374.** Refused at `check`/`exec`: "Order_Customer is an association: an expression names it qualified, `$Order/Shop.Order_Customer/…` — mxbuild rejects the expression with CE0117". Same for a same-module short path.

Before the retest:

- **Cross-module association paths need the module prefix on every step:** `$Item/ModA.Item_Other/ModB.OtherEntity/Attr`, not `$Item/Item_Other/Attr`. v0.24.0: `check` and `exec` pass the short form, `mx check` gives `[CE0117] Change object …`. The prefixed form builds at 0 errors. (Association-step rules: `learned-microflow-patterns.md`.)

### Gotcha — changing a DataGrid 2 column (failure mode was WRONG)

**CHANGED on v0.32.0-374.** `REPLACE` and `INSERT AFTER` on any DG2 column, even a plain `datasource: database Shop.Line` grid, are refused at `check`: "the insertion point (`Qty`) is in no data container, so no entity is in scope and these bindings cannot be qualified …" — logged as BUG-DRAFT-dg2-column-alter-refused. The whole-page re-emit stays the right advice.

Before the retest:

- **Changing an existing DataGrid 2 column (insert or new `Attribute:`) is a whole-page re-emit, never `ALTER PAGE`.** v0.26.0: `REPLACE … column` passes `check`, fails mxbuild (`learned-dg2-patterns.md` rule 1).

### Gotcha — enumeration values named with reserved words

**FIXED on v0.32.0-374.** `alter enumeration Shop.G03_Enum modify value Receive caption 'Receive goods'` → `Altered enumeration`; `describe` shows the new caption.

Before the retest:

- **Enumeration values named with reserved words** (`Receive`, `Move`, `Count`, `Open`, …) cannot be targeted by `alter enumeration … modify value` — v0.24.0 gives a parse error (`mismatched input 'Receive' expecting IDENTIFIER`), quoted or not, before any write. Use `create or modify enumeration` — which **replaces** the enum, so restate the full value set and the doc comment. Change captions only; renaming a value NAME silently breaks every reference and `mxcli check` will not say so.

### Gotcha — `elseif` in a page expression

**CHANGED on v0.32.0-374.** A parse error at `check`: `line 5:93 missing ELSE at 'elseif'`.

Before the retest:

- **No `elseif` in page/widget expressions** (DynamicClasses, Visible, ContentParams, …): nest `else if … then … else …`. Microflow `IF/ELSEIF` compiles into decision splits; a page expression passes through to Mendix's parser, which has no `elseif` token. v0.24.0: `check` and `exec` pass it, `mx check` gives `[CE0117] Error(s) in expression at Container '…'`; lint does not flag it.

### Gotcha — mxcli v0.25 dialect, "never add `mdl 1;`" (retired 2026-11-23)

**CONTRADICTED on v0.32.0-374.** mxcli's own generated `CLAUDE.md` says "Each starts with `mdl 1;`. A headerless one is `mdl 0`: upgrade it first", and the MDLBENCH run of 2026-11-20 (122 runs, real `mx check`) found every agent script in every arm starting with `mdl 1;` and building. The two hazards the gotcha named are now caught or warned: a headerless script parses as `mdl 0` with `MDL-DEPR*` deprecation warnings (retest probe M01), and under `mdl 1;` a `retrieve … limit 1` used as one object is refused at `check` ("$O was retrieved as a list (under `mdl 1;` `limit 1` is a list of one) …" [MDL-RETRIEVE03], probe M02). The `create or replace` spelling it told agents to keep is flagged MDL-DEPR001; write `create or modify`. Still true for a team that also runs mxcli v0.24: v0.24 rejects the header (`line 1:4 extraneous input '1'`), so keep such a team's scripts headerless until it upgrades.

Before the retirement:

- **mxcli v0.25 — keep the skills' spellings, never add `mdl 1;`.** The spellings in these skills (`count($L)`, `on error { … }`, `show page M.P($Obj = $Obj)`, `create or replace`) parse on v0.24.0 *and* v0.25.0; v0.25 only warns (`MDL-DEPR*`, "refused from `mdl 2`"). The new spellings (`count $L`, `on error begin … end error`, `P(Obj = $Obj)`) fail `check` on v0.24 — don't "modernise" a script the team may still run there. The hazard is the dialect header: v0.24 rejects it (`line 1:4 extraneous input '1'`), and under it v0.25 changes meanings — `show entity M.E` becomes an error (use `describe entity` / `list entities`; `-c` and the REPL already read this way), and `retrieve … limit 1` returns a *list* (use `first`; v0.32.0-374 `check` catches it). So strip the `mdl 1;` line from `describe` output before pasting it into a script, and never mix dialects in one file. Moving a whole file to mdl 1 on purpose: `mxcli fmt --upgrade -w -p <app>.mpr <script>`, then `check -p --references`, then exec once and run `bin/idempotence-check.sh <script>` (one `mxcli diff`; must say PASS, never a second exec).

### STOP #21 and #23 — the `create or replace` spelling (reworded 2026-11-23)

**REWORDED on v0.32.0-374.** `create or replace` is deprecated there (`MDL-DEPR001`: write `create or modify`), and the live rows now name only `create or modify`. The rule itself is unchanged; on an mxcli that does not flag `create or replace`, the old wording reads the same.

Before the rewording:

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 21 | `DROP` + `CREATE`, `create or modify` or `create or replace` any document **another script also edits** — an aggregator microflow, an after-startup chain, a navigation profile | **STOP → `describe` the live document first, diff your restatement against that dump, and name in the script header which call sites you preserved. A new owner adds `-- supersedes: <script>`; drafting ahead of unrun scripts, `bin/describe-baseline.sh stamp <script>` after the DESCRIBE (exec.sh only warns).** Prefer an in-place edit where your mxcli has one: `alter navigation` / `alter menu` (v0.28+, mendixlabs/mxcli#1522; below it a parse error, `no viable alternative at input 'alternavigation'`), and `alter microflow` (v0.25+; inside loop bodies and `replace body of` v0.29+, ako/mxcli#1693). Whole-document restatement makes losing a sibling script's edit the *default* outcome, not an unlikely one. | A sibling script's call silently vanished; `mx check` 0 errors, lint's orphan rule exempts `ACT_` (2026-08-26). | any |
| 23 | Name any document or entity that **might already exist** — `create or modify` on an entity, or any `create or replace` on a page, layout or microflow | **STOP → run `mxcli diff -p <app>.mpr <script>.mdl --format struct` FIRST** (read-only) and read every `-` line before you exec. | `create or modify` on an entity **replaces** its attribute set; `mx check` stays clean. Only warnings say so: `exec`, and `check` from v0.32.0-374 (MDL087). Older `diff` prints false `- Attribute` lines (BUG-146): check each against `DESCRIBE ENTITY`. | any |

## From `learned-detection-gaps.md` (the register)

### `CREATE` result discarded → CE6005

**FIXED on v0.32.0-374.** Exec names the result `$NewOrder`; `mx check` 0 errors.

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| `CREATE Entity (...) COMMIT;` with the result **discarded** (no `$Var =`) | rungs 1–3 | native `mx check`: `CE6005 "The 'Entity' property is required."` | Always assign every CREATE's result, even to a variable nothing reads: `$Row = CREATE ...` | exam-prep app project, 2026-08-25; found by bisection of a seeding script |

### `elseif` in a page expression

**CHANGED on v0.32.0-374.** A `check` parse error (`missing ELSE at 'elseif'`).

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| `elseif` in a page/widget expression (DynamicClasses, Visible, …) | rungs 1–3 | native `mx check`: CE0117 | Nested `else if` — the native page-expression parser has no `elseif` token (microflows compile it away; page expressions pass through). Already a preflight bullet: `learned-mdl-preflight.md` | a product-provisioning PoC project, 2026-08-13 |

### Quoted association paths / `$Obj/"Attr"`

**SPLIT on v0.32.0-374.** The DG2 column form is still CE1613 (`The selected attribute 'Shop.Line."Line_Order/Name"' no longer exists.`); `$Order/"Name"` in `change` and call arguments builds at 0 errors (BUG-75/77 fixed).

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| **Quoted** association-path / attribute bindings: `attribute: "Assoc/Attr"`, quoted names in `attributes: [...]`, `$Obj/"Attr"` | rungs 1–3 (`DESCRIBE` round-trips the corrupted binding as if fine) | native `mx check`: CE1613 / CE0117 naming the literal quoted string | Association paths and member accesses go **unquoted** — the one place an "always quote identifiers" convention must break. `resolveAssociationAttributePath` doesn't strip quotes before splitting on `/` | a martial-arts-academy PoC project 2026-08-14 + independently a product-provisioning PoC (BUG-75 family) |

### `calculated by` dropped

**FIXED (static) on v0.32.0-374.** `describe` shows `calculated by Shop.L98_Calc`, `show callers of Shop.L98_Calc` lists `Shop.L98`, `mx check` 0 errors. The runtime value was not retested.

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| `calculated by` on an attribute | rungs 1–4 **and** BSON looks like a normal attribute unless decoded | live retrieve: value always empty; `SHOW CALLERS` of the microflow: none | Don't use it this mxcli version: stored attribute + explicit compute-change-commit. Verify with a live retrieve (`mxcli oql --direct`, `learned-db-assertions.md` — `mx.data.get` is disabled in the React client) before anything depends on it | BUG-98 |

### `PARALLEL SPLIT` terminator

**FIXED (static) on v0.32.0-374.** The unit holds 4 `EndOfParallelSplitPath` markers. A live run was not possible.

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| A **`PARALLEL SPLIT` path with no terminator node** — every split written by mxcli **< v0.22**; v0.22+ writes the marker itself, and v0.29+ leaves it out below Mendix 10.21, where the type does not exist (ako/mxcli#1163) | rungs 1–4, and in **both directions**: `check`, `exec`, `DESCRIBE WORKFLOW`, `mxbuild` and native `mx check` report identically on the broken and the repaired model | a **live run**: count the tasks the engine opens at the split. Consecutive *End of parallel split path* rows with no task between them | `bin/wf-add-path-terminators.py <unit> --apply` after the script, and after every later script that rewrites the workflow; verify by running it, never by building it | BUG-121, `learned-workflow-patterns.md` §23 |

### Cross-module `ALTER PAGE … INSERT` of a DG2 column (BUG-96)

**CHANGED on v0.32.0-374.** Refused at `check` like every DG2 column INSERT (row merged with the next).

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| Cross-module `ALTER PAGE ... INSERT` of a DG2 column | rungs 1–3 (`DESCRIBE` *omits* the malformed column) | rung 5: Studio Pro loader `InvalidCastException`; `mx check` also crashes | Forbidden construct; recovery is `create or replace page` | BUG-96 |

### `ALTER PAGE … REPLACE` of a DG2 column

**CHANGED (failure mode) on v0.32.0-374.** Refused at `check`, not passed: see the preflight gotcha above.

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| `ALTER PAGE ... REPLACE` of an existing DG2 column with a new `Attribute:` (same module). The `SET (Attribute: …)` form is refused by `check` | rungs 1–2: `check --references` prints "Check passed!", exec applies it | rung 4: mxbuild, "An attribute is required when 'Show' is set to 'Attribute'" plus its sorting variant | Any change to a DG2 column is a whole-page `create or modify page` re-emit (`learned-dg2-patterns.md` rule 1) | BUG-DRAFT-dg2-replace-column-attribute-passes-check; an Ollama connector app, 2026-10-14 |

### `if` without `else` in an `on error` handler

**FIXED on v0.32.0-374.** As the row said for mxcli ≥ v0.29: `mx check` 0 errors.

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| An `if` with no `else` inside an `on error { }` handler body — **mxcli < v0.29** (fixed by ako/mxcli#1455) | rungs 1–3 (mxcli v0.24.0) | mxbuild: CE0079 / CE0773 — the `if`'s false flow is not configured | Keep handler bodies straight-line calls; move the branching into a sub-microflow the handler calls | card-disbursement requirements-driven build, 2026-09-26 |

### Reserved names `Case` / `Context`

**SPLIT on v0.32.0-374.** `Context` as an attribute is refused at `check` (`attribute 'Context' is a reserved word (CE7247) [MDL021]`). `Case` as an entity still passes `check` and `exec` and fails `mx check`: `CE7247 The name 'Case' is a reserved word.`

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| An entity, attribute or Java action parameter named with a Mendix-reserved word — `Case` failed as both an entity and a Java action parameter; `Context` as an attribute | rungs 1–3 (mxcli v0.24.0) | mxbuild: CE7247 | Qualify the name (`CustomerCase`, `ApprovalContext`). The reserved list is Mendix's, not MDL's, so quoting does not help — mxcli's bundled `check-syntax` skill lists what it knows (`syntax domain-model keywords` lists MDL's keywords, not these) | lab run, 2026-09-26; BUG-149 |

### Enumeration value `New`

**CHANGED on v0.32.0-374.** Refused at `check`: `enumeration value 'New' is a reserved word (CE7247) [MDL010]`.

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| An **enumeration value** named `New` (a brief often says "New") | rungs 1-3 (v0.26.0) | mxbuild: CE7247 (reserved words cover enumeration values too) | Name it `Queued` and keep `New` as its caption | lab run, 2026-10-15 |

### Expression in `ContentParams:`

**CHANGED on v0.32.0-374.** See STOP #12 above. The bare-attribute-inside-a-function case keeps a live register row.

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| Expression in `ContentParams:` on any `dynamictext` in an object context (customContent column, list view, data view) | rungs 1–3 — on v0.24.0 `check --references` refuses the parenthesised forms but **passes `if … then … else`**; `DESCRIBE` hides the difference | mxbuild / Studio Pro error pane: CE1613 | Bind a bare attribute (`Attribute:`) or a quoted literal only; a computed label becomes a String attribute, tone goes in `DynamicClasses` | BUG-142; `learned-datagrid-customcontent-binding.md` |

### XPath `= null`

**CHANGED on v0.32.0-374.** Refused at `check`: `retrieve from Shop.Order: the constraint names "null", which is neither an attribute nor an association of it — mxbuild rejects the constraint (CE0161 …)`.

Before the retest:

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| `Title = null` (or any `= null`) as an **XPath retrieve constraint** | rungs 1–3 — `check --references` clean, exec succeeds, and mxcli's **own OQL engine evaluates the query** and returns rows, so even a read-back looks right | native `mx check` / mxbuild: CE0161 | XPath has no `= null`; write `not(Title)` / `Title != ''` for the empty test. Note what makes this one expensive: mxcli's query engine is more permissive than the model loader, so "I ran the query and it worked" is **not** evidence the constraint is legal | field build (Maurits Visser), 2026-09 |

## From `learned-microflow-patterns.md`

### Module-prefix every association step

**CHANGED on v0.32.0-374.** The short form is refused at `check` (`Line_Order is an association: an expression names it qualified …`), no longer "passes check and exec".

Before the retest:

**Rule:** In a Mendix expression, write each association step **and** each entity step with its module prefix: `$Line/Shop.Line_Order/Shop.Order/Name`. The unprefixed form `$Line/Line_Order/Name` passes `mxcli check` and `exec`, then fails `mx check` with CE0117 (v0.24.0, measured in a microflow expression; `mxcli lint` does not flag it). Only a bare `= empty` test does not need the long form.

### Microflow header needs `()` (error text was WRONG)

**CHANGED on v0.32.0-374.** One precise error: "line 3:36 a microflow header needs its parameter list in parentheses, even when it is empty — they are not optional: write `create microflow Shop.MP01_NoParens () returns boolean as $r`".

Before the retest:

- **Microflow header:** `create microflow M.N ()` keeps its `()` even when empty, then `returns`, then `folder '…'` (not `in`). The `check` errors point at `returns`/`List of`. BUG-DRAFT-microflow-header-grammar.

### Enum attribute in a String context

**CHANGED on v0.32.0-374.** `check` flags the `change` (E009) and the concatenation (E004), not the `return`; `exec` still writes all three and `mx check` gives CE0117 at each.

Before the retest:

**Rule:** Wrap an enum attribute read in `toString()` when the result is used as a String. v0.24.0: `return $Order/Status` from a String microflow and `change $Order (Note = $Order/Status)` pass `check` and `exec`, then fail `mx check` with CE0117 (`mxcli lint` does not flag it). The concatenation form is flagged E004 by `check`, but `exec` still writes it.
