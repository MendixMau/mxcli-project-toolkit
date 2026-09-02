**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-70` (originally discovered 2026-08-12 on a main
build-track project, Stage 5) and `## BUG-95` (same defect, isolated further 2026-08-21 on a
different client project — the two entries were merged as one issue per the log's own
cross-reference); retested and confirmed still open 2026-08-31 on v0.20.0 — see
`bug-logs/mxlabs-v0.20.0-retest-2026-08-31.md`
**Status:** NOT YET FILED
**Suggested labels:** bug, page, action-button

---

**Title:** A page-level `actionbutton` (outside any dataview) with `Action: show_page
Page(Param: $Var)` silently drops the argument and rebinds every target-page parameter to
`$currentObject` — CE1571 at build

**Body:**

## Summary

A widget-level `action: show_page Module.TargetPage(SomeParam: $SomeVariable)` clause on an
`actionbutton` (or equivalent) that is **not** inside a `dataview` — i.e. there is no
`$currentObject` in scope at that point in the page — round-trips clean through `mxcli check
--references` and `mxcli exec` reports success with no error. But `DESCRIBE PAGE` afterward shows
the compiled action's argument silently rewritten to `$currentObject` (not the variable actually
named in the MDL script), and native `mx check`/`mxbuild` then fails with one `CE1571` per
parameter:

```
[CE1571] "No argument has been selected for parameter '<Param>' and no default is available."
```

plus a `CE0117` on the page overall. Since the button lives outside a dataview, `$currentObject`
is genuinely unbound at that point, so the rewritten argument can never resolve — this is not a
cosmetic describe-only issue, it is a real writer defect that produces a page that cannot build.

v0.19.0 added a related refusal (`MDL-PAGEARG01`: "a SHOW_PAGE widget argument that is not the
context object is refused instead of ignored") for a different shape — that guard does **not**
cover this one; it appears to treat "no enclosing data widget" like `ALTER PAGE`'s unknown-context
case and stand down instead of refusing.

## Environment

- mxcli: `v0.20.0` (tag, built from source, `git describe --tags` = `v0.20.0`, clean tree)
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: Linux amd64
- Baseline: a blank Mendix 11.13.0 project scaffolded fresh by `mxcli new`
- Verdict source: native `mxbuild`/`mx check` (`mxcli docker check`), plus `DESCRIBE PAGE`
  read-back confirming the rewritten argument
- Originally discovered: 2026-08-12 (as BUG-70, mxcli v0.16.0/v0.17.0-era) and independently
  again 2026-08-21 (as BUG-95, same-era mxcli, different client project, page-level button
  outside any dataview). Reproduced independently since on v0.20.0 (2026-08-31).

## Steps to reproduce

Setup: a module with an entity `Item`, a target page `Detail` taking one entity-typed parameter,
and a page-level `actionbutton` outside any dataview referencing a page variable of that type:

```sql
create page Test.Detail (
  params: { $Item: Test.Item },
  title: 'Detail',
  layout: Atlas_Core.Atlas_Default
) {
  dataview dv (datasource: $Item) {
    textbox txt (label: 'Name', attribute: 'Name')
  }
};

create page Test.List (
  params: { $SomeRef: Test.Item },
  title: 'List',
  layout: Atlas_Core.Atlas_Default
) {
  actionbutton btnOpen (
    caption: 'Open',
    action: show_page Test.Detail(Item: $SomeRef)
  )
};
```

```
$ ./mxcli check list.mdl -p Test.mpr
All references valid.

$ ./mxcli exec list.mdl -p Test.mpr
Created page: Test.List

$ ./mxcli describe page Test.List -p Test.mpr
...
Action: show_page Test.Detail(Item: $currentObject)
...

$ ./mxcli docker check -p Test.mpr
[error] [CE1571] "No argument has been selected for parameter 'Item' and no default is
available." at Action button 'btnOpen'
[error] [CE0117] "Error(s) in expression." at Page 'Test.List'
```

`btnOpen` is not inside any `dataview` — `$currentObject` is not in scope on `Test.List` at all —
yet `DESCRIBE PAGE` shows the argument rewritten to it.

**Variants confirmed to fail identically** (all isolated across a systematic bisection ruling out
every plausible narrowing factor):
- Colon form (`Param: value`) and the alternate microflow-style form (`$Param = value`) — both
  round-trip to `$currentObject`.
- Literal values (`Param: 'literal'`) instead of a variable/attribute-path expression — same
  result, ruling out expression complexity.
- Both inside a datagrid `controlbar` and as a fully standalone page-level `actionbutton` — same
  result, ruling out datagrid-column nesting.
- Re-`SET`ting the action directly via `ALTER PAGE ... SET action = ... ON btnName` (bypassing
  `INSERT ... { }` entirely) — same result.
- A single-param case — even one param is dropped/rewritten, not just multi-param calls.

**Contrast confirming the underlying page/params are fine:** a *microflow-level* `show page
Page(Param1: v1, Param2: v2)` statement compiles and wires both params correctly (confirmed via
`DESCRIBE MICROFLOW`). The bug is specific to the widget-property `action: show_page(...)` syntax
on a button/tile, not to `show_page`/param-passing in microflows.

## Expected vs. actual

**Expected:** the widget-level `show_page` action serializes the actual argument expression the
script specifies, the same way the microflow-level `show page` statement already does — or, if the
target page's parameter genuinely cannot be resolved outside a dataview context, `mxcli
check`/`exec` refuse the statement with an actionable error (the way v0.19's `MDL-PAGEARG01` guard
already does for a related shape), rather than silently rewriting to `$currentObject`.

**Actual:** the argument is unconditionally rewritten to `$currentObject` whenever the action is
attached outside a dataview context, with no warning, and no refusal from the `MDL-PAGEARG01`
guard.

## Severity

**High.** This invalidates any button using `action: show_page Page(Param: value)` with one or
more params outside a dataview: for a required-param target page it produces a hard `CE1571` under
native mxbuild; for a page with optional/defaultable params it would silently show the wrong
(empty/default) data with no error at all — worse than a compile failure. A `show_page` widget
action with zero params is unaffected.

## Workaround

Never use `action: show_page Page(Param: value, ...)` directly on a widget outside a dataview when
the target page takes params. Route through a microflow instead: point the widget's `action:` at a
microflow (`action: microflow Module.SomeAction(...)`) that does a microflow-level `show page
Page(Param1: v1, ...)` statement internally — that code path wires params correctly.

## Suggested fix

Fix the widget-level `show_page` action writer to serialize the script's actual argument
expression instead of hardcoding `$currentObject` whenever no enclosing dataview is present. At
minimum, extend the `MDL-PAGEARG01` refusal (already shipped for a related shape) to cover this
one, so the failure is a clear refusal at `check`/`exec` time instead of a silent corruption caught
only by native mxbuild.

---

**Status: DRAFTED 2026-08-31, not yet filed.**
Duplicate-check: searched `mendixlabs/mxcli` issues (open and closed) for "show_page argument
dropped currentObject CE1571" and "CE1571 show_page currentObject" — no existing issue found as
of 2026-08-31. One superficially similar open issue, #122 ("SHOW_PAGE with parameter binding
generates invalid expression (CE0117)"), was inspected directly: it describes `$currentObject`
being *undefined* inside a DATAGRID CONTROLBAR (no DataView in scope) producing CE0117 from an
unresolvable expression — a different mechanism (an author-supplied `$currentObject` reference
that has no binding) from this bug (mxcli's writer *substituting* `$currentObject` for a
different, valid variable the author supplied). Not a duplicate.
