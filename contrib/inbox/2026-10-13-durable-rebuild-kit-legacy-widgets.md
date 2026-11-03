# Durable rebuild of legacy-widget pages: a four-part kit, and "restate from DESCRIBE" as a STOP item

**From:** a field project (anonymised) — an existing Mendix app (old widgets throughout) changed with mxcli + this toolkit
**Date:** 2026-10-13
**Kind:** process
**Field evidence:** 79 non-writable widgets on 40 live documents (DESCRIBE `-- NOT re-executable` count)
and 97 role-locked widgets in 16 documents (BSON scan; DESCRIBE showed none). 34 pages and snippets
were restated whole; the read-back afterwards found 0 non-writable widgets and 0 role locks on them.
Two drafted scripts would have silently dropped role or row visibility had they run. Mendix 11.14.0
Beta (Classic client, Production security), mxcli v0.25.0, toolkit c1efcb3.
**Proposed target:** `skills/existing-app-change.md` (a "legacy-widget pages" section), a STOP row in
`skills/learned-mdl-preflight.md`, possibly a `project-bin/` scan once field-proven as a file

**Currency check:** 2026-10-16 against master d1cbd41: partly stale. STOP row 21 in `skills/learned-mdl-preflight.md` now covers restating a document another script also edits. Still open: the legacy-widget section in `skills/existing-app-change.md` and the scan for role locks that DESCRIBE does not show.
---

## What is already covered

- `bug-logs/mxcli-bugs.md` BUG-115 addendum: "Grep a generated script for `NOT re-executable` before
  executing it" (for the File Manager widget).
- `bug-logs/mxcli-bugs.md` (the `hasRole()` entry): no MDL syntax writes `ConditionalVisibilitySettings.ModuleRoles`.
- `skills/learned-mdl-cannot-express.md` (master bda5bed, #277): "A widget visible to one role and not
  another — nothing", with the execute-grant recipe for action buttons.

## What is not covered (findings)

1. **DESCRIBE does not print module-role visibility.** One portal page had 19 role-locked widgets; DESCRIBE
   printed none of them (nor a hidden "show page" action behind 9 image widgets). A page restated from that
   DESCRIBE builds clean and shows every widget to every role.
2. **A drafted restatement said "the snippet has no visibility rules".** It restated a side-menu snippet
   from DESCRIBE (navigation-list items have no names, so one item cannot be dropped alone). A BSON audit
   found 13 role-locked items. Running the draft would have exposed all of them, with a clean build.
3. **DESCRIBE does not print layout-grid row visibility.** Two form pages had nine detail sections shown
   by type through row visibility; a snippet had 56 row-level "show only when it has a value" rules. None
   appear in DESCRIBE. The drafters re-wrote them as container `Visible:` (which DESCRIBE does print and
   mxcli does write); an audit confirmed every rule was carried over.
4. **Tab-page `Visible:` and `CaptionParams` are accepted and not written** (see the learned-entries note).
   Found only by reading the unit back after exec.

So "copy the page from DESCRIBE, edit, `create or replace`" is silently lossy on any app built in Studio Pro.

## Proposed STOP row (learned-mdl-preflight.md)

| # | Operation | Why STOP | Do instead |
|---|---|---|---|
| new | Restate an existing page, snippet or layout from `describe` output (`create or replace`, or `alter … replace` of a container) | DESCRIBE omits module-role visibility, layout-grid row/column visibility and legacy-widget internals; check, exec and mxbuild all pass while the rules vanish | Run the visibility scan (below) on the unit first. Zero role locks and zero row rules: go. Otherwise rewrite each rule as container `Visible:` or flow access, or leave the page to `alter page` / Studio Pro |

Probe that falsifies it: in Studio Pro, set one widget visible to one module role and one layout row
visible on an attribute; `describe page`; grep the output for the role name and the attribute. Today
(v0.25.0): 0 hits for both.

## The kit (each part was done by hand in the field; none is a toolkit file yet)

1. **BSON visibility scan, per document.** Decode each page/snippet/layout unit under `mprcontents/`
   (the toolkit's `project-bin/mxunit_bson.py` codec is enough) and count (a) any
   `ConditionalVisibilitySettings` whose `ModuleRoles` list is non-empty, (b) any
   `ConditionalVisibilitySettings` on a `Forms$LayoutGridRow` or `Forms$LayoutGridColumn`. Report per
   document: widget name, kind, roles or attribute. The field scans were inline one-offs, not a saved
   script; a shipped version needs its own fixture.
2. **Non-writable count, per document.** `describe` every page, snippet and layout in the app's own
   modules (Marketplace modules excluded) and count `-- NOT re-executable` lines, grouped by the BSON
   type in the comment. Field result: `Forms$DropDown` 29, `Forms$ReferenceSelector` 27,
   `Forms$DataGrid` 16, sign-in widgets 4, `Forms$TemplateGrid` 1, `Forms$ImageUploader` 1,
   `Forms$SidebarToggleButton` 1.
3. **Rebuild brief per document.** Inventory first (DESCRIBE plus the scan), then each widget marked
   KEEP / CUT / MOVED / NEW against the wireframe, then the restatement. Replacements used:
   drop-down → `combobox` on the enumeration; reference selector → `combobox` on the association (a
   microflow data source when the filter needs the context object); old data grid → Data grid 2;
   template grid → `listview`; image uploader → File Uploader in files mode plus a `dynamicimage`;
   role-only visibility → a per-viewer flag from a data-source microflow, or flow access (Mendix hides a
   button whose flow the user cannot run). The restating script becomes the document's single owner;
   older `alter page` blocks on it are marked superseded (compare #269).
4. **Post-exec read-back.** After each exec: DESCRIBE again (0 `NOT re-executable`), rerun the scan
   (0 role locks unless intended), and grep the unit for every `Visible:` / `CaptionParams` the script
   wrote. Item 4 above was caught only this way.

Cost, for scale: six drafting agents in parallel; one gated exec per document (about 5–10 minutes each
with mxbuild and lint), serial because there is one writer to the `.mpr`.

Upstream asks (mxcli), for the maintainer to file or link: print module-role and row/column visibility in
DESCRIBE (or at least a `-- role-based visibility not shown (N roles)` comment), accept it on write, give
navigation-list items stable names, and a legacy-widget migration (`DataGrid` → Data grid 2,
`ReferenceSelector`/`DropDown` → combobox) behind a dry run.
