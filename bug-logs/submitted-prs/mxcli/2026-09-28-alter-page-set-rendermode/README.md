Status: OPENED mendixlabs/mxcli#1229 2026-09-28 (make test 84 packages ok, 0 FAIL; make lint clean; on 95091765) · closes mendixlabs/mxcli#1228 (filed 2026-09-28) · base upstream main 95091765 · supersedes MendixMau/mxcli#1 (closed)

# mxcli PR: ALTER PAGE/SNIPPET SET RenderMode on a dynamic text

Per `skills/upstream-feedback.md` §3a. Already sent; this package is the record. The patch is
`0001-fix-pages-ALTER-PAGE-SNIPPET-SET-RenderMode-on-a-dyn.patch` (8 files, +216/-2: the `setRawWidgetPropertyMut` case in
`mdl/backend/pagemutator/mutator.go`, a unit test, a bug-test script, and four doc touches).

History: first written on the fork (MendixMau/mxcli#1, 2026-09-22, base 31eee45) but never sent upstream.
On 2026-09-28 it was rebased on main 95091765 (one conflict in the `page.alter` syntax help, resolved by
keeping upstream's text and adding the RenderMode line), squashed to one commit, and re-proved:

- The new unit tests fail without the mutator change (8 subtests) and pass with it.
- Fresh blank Mendix 11.12.2 app: the bug-test script exits 1 on main and applies on the branch; `mx check` 0 errors;
  `H7` refused with nothing written; at runtime the home-page heading set to H5 renders as `<h5>` (0 `<h1>` left).
- Not tested: opening the model in Studio Pro.

## Issue body (as filed, #1228)

**Environment:** mxcli upstream `main` at `95091765` (built from source), Mendix 11.12.2 (`mx check` from mxbuild 11.12.2). Fresh blank app from `mx create-project`, macOS.

**Summary:** `alter page` / `alter snippet` cannot set `RenderMode` on a dynamic text. `create page` and `replace … with { … }` both accept `RenderMode` on a `dynamictext`, and `describe` prints it, but `set RenderMode = … on <dynamictext>` is refused. The message says it is "not a property of this built-in widget". RenderMode is a real property of `Forms$DynamicText`, not a design property, so the hint to use design properties does not help either.

**Steps to reproduce**

```mdl
create entity MyFirstModule.RmRow ( Name: String );

create or replace page MyFirstModule.P_SetRenderMode
(
  Title: 'Set RenderMode',
  Layout: Atlas_Core.Atlas_Default,
  Params: { $Row: MyFirstModule.RmRow }
)
{
  dataview dv (datasource: $Row) {
    dynamictext title (content: 'Title {1}', contentparams: [{1} = Name], rendermode: H1)
    dynamictext body (content: 'Body')
  }
}

alter page MyFirstModule.P_SetRenderMode {
  set RenderMode = H2 on title;
}
```

**Actual** (exit 1; the page keeps `RenderMode: H1`)

```
Created entity: MyFirstModule.RmRow
Created page MyFirstModule.P_SetRenderMode
Error: failed to set: failed to set RenderMode on title: property "RenderMode" is not a property of this built-in widget, and not an Atlas design property your theme declares for it — `set` writes its own properties (Caption, Class, Style, DynamicClasses, Visible, Editable, …) and any design property of this widget's type. Run `mxcli show design properties for <widget type>` to see which those are
```

The same happens with `alter snippet … { set RenderMode = H4 on <dynamictext> }`.

**Expected:** `Altered page`, and `describe page` shows `RenderMode: H2`, as it does when the page is created with `rendermode: H2` directly.

**Cause:** `setRawWidgetPropertyMut` (`mdl/backend/pagemutator/mutator.go`) has no case for `RenderMode`, so the statement falls through to the pluggable-widget property setter. The MCP backend's mutator already handles it.

**Workaround:** `replace <widget> with { dynamictext … (RenderMode: H2) }`, which rewrites the whole widget.

I have a fix with tests and will open a PR that references this issue.

## PR body (as sent, #1229)

Closes #1228

**What it does**

`alter page` / `alter snippet` can now set `RenderMode` on a dynamic text:

    alter page Mod.Page { set RenderMode = H2 on txtTitle };

`create page` already writes this property and the MCP backend's mutator already sets it. The MPR backend's fixed property list in `setRawWidgetPropertyMut` did not include it, so the statement fell through to the pluggable-widget setter and was refused. The new case:

- applies only to a dynamic text (`Forms$DynamicText`); other widgets keep the previous path
- accepts `Text`, `Paragraph` and `H1`–`H6` in any casing, and stores the canonical spelling
- refuses anything else and writes nothing, e.g. `invalid RenderMode "H7" for dynamic text "title": expected one of Text, Paragraph, H1, H2, H3, H4, H5, H6`

`check -p` picks this up too, since it dry-runs the same setter.

**Testing**

- `make test` on upstream `main` 95091765: 84 packages ok, 0 FAIL
- `make lint`: clean (exit 0)
- New unit tests in `mdl/backend/pagemutator/dynamictext_rendermode_test.go`. They fail without the `mutator.go` change and pass with it.
- Bug-test `mdl-examples/bug-tests/alter-page-set-rendermode-dynamictext.mdl` covers a page and a snippet.

**Mendix validation (11.12.2, fresh blank app)**

- The bug-test script: on `main` 95091765 it stops at the first `set RenderMode` (exit 1). With this branch it prints `Altered page` and `Altered snippet`, and `describe` shows `RenderMode: H2`, `Paragraph` and `H4`.
- `mx check`: 0 errors.
- `set RenderMode = H7`: refused with the message above, exit 1, and the page still reads `H2`.
- Runtime (`mxcli run --local --db-type hsqldb`): `set RenderMode = H5` on the blank app's home-page heading (`text1`, H1). In the browser, "Welcome to your homepage" renders as an `<h5>`, and the page has no `<h1>` left.

**Docs:** skill `alter-page`, docs-site `alter-page.md`, `MDL_QUICK_REFERENCE.md`, `mxcli syntax page.alter`, and a finding in `.claude/skills/fix-issue/findings/mdl-backend.jsonl`.

**Out of scope:** `set Content` / `ContentParams` on a dynamic text (grammar-level), `RenderMode` on a container, `RenderType` on a button.

**Not tested:** opening the model in Studio Pro.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
