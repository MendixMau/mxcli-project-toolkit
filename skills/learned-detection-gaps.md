# Detection gaps — what each verification rung is blind to

**Applies to:** any mxcli project
**Purpose:** the cross-project register of MDL constructs that pass one or more verification
rungs and still fail later — with, for each, the **first oracle that actually catches it**.
Use it two ways: before trusting a green result ("what is this rung known to miss?"), and
when a runtime symptom appears over a fully green model ("which known gap looks like this?").

Every row here was found in the field, most of them independently in more than one project.
The point is not the individual bugs (each has its own entry) — it is the pattern: **the
verification rungs form a ladder, and a green result only certifies what that rung can see.**

## The ladder

1. `mxcli check --references` — MDL grammar and reference syntax. Catches the least.
2. `mxcli exec` "success" — the write completed; says nothing about what was written.
3. `DESCRIBE ...` read-back — mxcli's own lenient reader; normalises, and omits what it
   cannot represent (so it can hide the very corruption you are checking for).
4. Native `mx check` / mxbuild — the real model loader. Catches structural and expression
   errors; blind to runtime wiring.
5. Studio Pro's own GUI loader — catches BSON-structural corruption `mx check` sometimes
   passes (see `scriptable-sp-verification.md`).
6. **Live runtime observation** — a browser retrieve, `/xas/` traffic, a DB row count. The
   only rung that verifies *behaviour*. Some defect families are invisible to everything
   above this line.

## The register

| Construct that looks fine | Green through | First oracle that catches it | Rule / fix | Ref |
|---|---|---|---|---|
| A **Java action's body**, in a project driven by `bin/exec.sh` | rungs 1–4, all of them, including exec.sh's own mxbuild gate | a real `mxbuild --target=deploy` — the one that prints `Compiling Java...` | exec.sh's gate runs `mxbuild --target=deploy --write-errors=…` and **does not compile Java actions**. A Java action with `cannot find symbol: variable Core` reported `0 errors` on every exec and failed on the first `mxcli run --local`. **Any script containing a Java action needs a real build before it is called done**, and the from-empty replay in a project's REBUILD doc is the cheapest place to get one | a dashboard-publishing migration, 2026-08-31 |
| A Java action whose generated **import list is smaller than you assumed** | rungs 1–3 | real mxbuild with Java compilation | mxcli generates the skeleton's imports from the action's SIGNATURE. An action taking an entity parameter gets `IMendixObject` for free; one taking only strings gets exactly `IContext` and `UserAction`, and a bare `IMendixObject` fails in every place it appears. **Assume nothing beyond those two is imported** — fully qualify the rest | same |
| `String.valueOf(obj.getValue(context, "Attr"))` and any other generic Mendix API call at an overloaded call site | rungs 1–4 **and the real Java compile** | clicking the button | `IMendixObject.getValue` is `<T> T getValue(…)`, so javac infers T from what the call site wants — and picks a T that makes an overload fit. Here it chose `T = char[]` to bind `String.valueOf(char[])`, compiled clean, and threw `class java.lang.String cannot be cast to class [C` at runtime. **Read into an `Object` first**; that pins T and leaves nothing to infer. Note the ladder position: this one survives the strongest static gate the toolkit has | same |
| A non-idempotent statement anywhere in a script — `alter entity … add attribute`, bare `CREATE ASSOCIATION`, `CREATE MICROFLOW` on a name that exists | rungs 1–4 **on the re-run**, because the model is still valid | reading the model back and counting against the plan (`DESCRIBE MICROFLOW`, `SHOW MICROFLOWS`), or a from-empty replay | mxcli is **not transactional across statements**: the failing statement stops the script and **every statement below it is silently skipped**, while the mxbuild gate reports 0 errors on a model that is merely missing work. Found when a microflow quietly lost a call it had had an hour earlier. Use `create or modify` everywhere; see `skills/learned-mdl-preflight.md` STOP row 22 | same |
| A `commit` or `delete` with no `refresh`, on a page whose list reads a **microflow datasource** | rungs 1–5 **and an OQL assertion**, which reports the write as correct | a browser journey — and only when run *alongside* the OQL check | The write lands; the client is never told, so the datasource is never re-evaluated. The screen says nothing happened. Note this row is the register's mirror image: **the UI reports failure over a correct database.** A screenshot test alone calls the feature broken; an OQL test alone calls it working. Only the pair is a check | same |
| `CREATE Entity (...) COMMIT;` with the result **discarded** (no `$Var =`) | rungs 1–3 | native `mx check`: `CE6005 "The 'Entity' property is required."` | Always assign every CREATE's result, even to a variable nothing reads: `$Row = CREATE ...` | exam-prep app project, 2026-08-25; found by bisection of a seeding script |
| DataGrid2 `DataSource: database from ...` with **no `sort by`** | rungs 1–4 (mx check, static MDL inspection and access-grant review all clean) | live `/xas/` traffic: `attributes:{}` for every row but the first — grid renders blank | Every DG2 database source carries an explicit `sort by`. Reproduced across three modules built at different times | a WMS conversion project, 2026-08-19/20 |
| `dropdownfilter (attributes: [...])` via mxcli | rungs 1, 2, 4 | rung 3 for once **does** show it (`DESCRIBE PAGE`: no attribute at all) — otherwise runtime: "Unable to get filter store", parent grid blanks | After any FILTER-widget write, re-read `DESCRIBE PAGE` and confirm the binding survived; the sibling `TEXTFILTER` persists fine. No MDL wording fixes it — drop the widget until fixed upstream | a martial-arts-academy PoC project, BUG-005, 2026-08-16 |
| `elseif` in a page/widget expression (DynamicClasses, Visible, …) | rungs 1–3 | native `mx check`: CE0117 | Nested `else if` — the native page-expression parser has no `elseif` token (microflows compile it away; page expressions pass through). Already a preflight bullet: `learned-mdl-preflight.md` | a product-provisioning PoC project, 2026-08-13 |
| **Quoted** association-path / attribute bindings: `attribute: "Assoc/Attr"`, quoted names in `attributes: [...]`, `$Obj/"Attr"` | rungs 1–3 (`DESCRIBE` round-trips the corrupted binding as if fine) | native `mx check`: CE1613 / CE0117 naming the literal quoted string | Association paths and member accesses go **unquoted** — the one place an "always quote identifiers" convention must break. `resolveAssociationAttributePath` doesn't strip quotes before splitting on `/` | a martial-arts-academy PoC project 2026-08-14 + independently a product-provisioning PoC (BUG-75 family) |
| `calculated by` on an attribute | rungs 1–4 **and** BSON looks like a normal attribute unless decoded | live retrieve: value always empty; `SHOW CALLERS` of the microflow: none | Don't use it this mxcli version: stored attribute + explicit compute-change-commit. Verify with `mx.data.get` before anything depends on it | BUG-98 |
| `create import mapping` array-to-child binding | rungs 1–4; `DESCRIBE IMPORT MAPPING` looks correct | live retrieve after a real `import from mapping`: child list empty | Unverified-until-proven-live; severity not yet classified — read BUG-99's hold before blaming mxcli | BUG-99 |
| Cross-module `ALTER PAGE ... INSERT` of a DG2 column | rungs 1–3 (`DESCRIBE` *omits* the malformed column) | rung 5: Studio Pro loader `InvalidCastException`; `mx check` also crashes | Forbidden construct; recovery is `create or replace page` | BUG-96 |
| Expression in `ContentParams:` inside a customContent column | rungs 1–3 (`DESCRIBE` normalises correct and broken forms to the same text) | mxbuild / Studio Pro error pane: CE1613 | Bind with `Attribute:`, never an expression | `learned-datagrid-customcontent-binding.md` |

## Operating rules that fall out of this table

1. **A green rung certifies only what that rung reads.** "Passes check and exec" is a claim
   about syntax and about a write completing — never about what was stored, and never about
   runtime behaviour.
2. **Read-back is not ground truth either.** `DESCRIBE` hides three rows of this table
   (omits, round-trips corruption, normalises). It is one more lenient reader, not an oracle
   — `skills/tool-output-is-not-ground-truth.md` is the general form.
3. **For anything that wires behaviour** (calculated attributes, import mappings, filters,
   datasources), the acceptance test is a **live observation**: a runtime retrieve, the
   `/xas/` payload, a row count — not any static check. `testing-shape.md`'s false-green
   register is the verification-side companion of this authoring-side table.
4. **Add a row when the family grows.** The entry condition is exactly: "passed rung N,
   failed at rung >N, confirmed in the field." File the bug in `bug-logs/mxcli-bugs.md`
   first; this table carries the one-line lesson and the pointer.
