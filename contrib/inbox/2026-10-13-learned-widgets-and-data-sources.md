# Learned entries from a legacy-widget rebuild: File Uploader image mode, native-mapped keywords, tab pages, XPath comparands, multi-hop data sources

**From:** a field project (anonymised)
**Date:** 2026-10-13
**Kind:** learning
**Field evidence:** each entry below was hit while restating 34 pages of an existing app, through
`bin/exec.sh` (mxbuild delta gate) on mxcli v0.25.0, Mendix 11.14.0 Beta, Classic (Dojo) client,
toolkit c1efcb3. Error texts are verbatim; module/entity names are genericised.
**Proposed target:** per entry below (`skills/learned-file-upload-widget.md`,
`skills/learned-mdl-cannot-express.md`, `skills/learned-page-patterns.md`, `bug-logs/mxcli-bugs.md`)

---

## 1. File Uploader: image mode fails the build; files mode against a `System.Image` subtype works

Target: `skills/learned-file-upload-widget.md` §7 ("Image mode … was not tested").
Status: files mode is ALREADY covered there (PR #139); this adds image mode and the image-preview pattern.

```sql
fileuploader upPictures (
  uploadMode: 'images',
  associatedImages: association $currentObject/MyModule.Picture_Asset,
  readOnlyMode: true,
  enableCustomButtons: false
)
```

`mxcli check` passed. mxbuild: `CE0463 The definition of this widget has changed.` on
`File uploader upPictures`; the gate rolled back (rollback verified by DESCRIBE). The same widget with
`uploadMode: 'files'` builds clean (finding).

What built clean instead (finding, mxbuild 0 errors): uploads in **files** mode against an entity that
extends `System.Image` (which extends `FileDocument`), with a separate `dynamicimage` preview beside it;
read-only picture lists as a `listview` whose template holds a `dynamicimage`.

Also stale: `skills/learned-mdl-cannot-express.md` row 1 still says "A file upload control — nothing …
⛔ not buildable", which contradicts `learned-file-upload-widget.md`. Suggest pointing that row at the
File Uploader skill.

Related (finding): the installed FileDropper widget's definition lists `dataFileEntity` and
`dataContextAssociation` as known properties with no mapping; `check` accepts them, exec does not write
them, and mxbuild then fails. Upstream ask: refuse unmapped definition properties with MDL-WIDGET07.

## 2. `radiobuttons` and `image` can resolve to NATIVE mobile widgets on a web page

Target: `skills/learned-page-patterns.md` (or the widgets section of `learned-mdl-cannot-express.md`).
Status: NEW (no toolkit mention).

In this project `DESCRIBE WIDGET TYPE radiobuttons` resolves to `com.mendix.widget.native.radiobuttons`,
and `check` warns MDL-WIDGET10 that the label is dropped. The project's `image.def.json` maps `image` to
`com.mendix.widget.native.image.Image`; a probe wrote `image` with no properties. DESCRIBE prints existing
**web** radio groups with the same `radiobuttons` keyword, so re-running DESCRIBE output writes a native
widget into a web page (finding for the resolution and the warning; the radiobuttons case was not taken
through mxbuild).

Rule used: Boolean → `checkbox`, enumeration → `combobox`, images → `dynamicimage`. Before relying on a
keyword in an existing app, run `DESCRIBE WIDGET TYPE <keyword>` and check the id is a `web` widget.

## 3. Tab pages: `CaptionParams` and `Visible:` pass every gate and are not written

Target: `bug-logs/mxcli-bugs.md` as `## BUG-DRAFT-tabpage-captionparams-visible-dropped:`, plus a row in
`learned-mdl-cannot-express.md` next to the existing "count badge on a tab" row.
Status: NEW. (The existing row covers `Badge:`, which `check` refuses; these two are accepted.)

```sql
tabpage tpDue (Caption: 'Due today or earlier · {1}', CaptionParams: ({1} = DueCount)) { … }
tabpage tpOther (Caption: 'Unassigned · {1}', Visible: $currentObject/ShowOtherTab) { … }
```

`check`, exec and mxbuild all passed, with no MDL-WIDGET07. The stored caption is literal text (the tab
reads `· {1}`), and the tab page has no visibility setting: `ShowOtherTab` occurs 0 times in the unit.
Found by a BSON read-back after exec (finding).

Rule: no dynamic captions and no visibility on tab pages; put the count in a line inside the tab, and
put anything conditional in a container with `Visible:` (container visibility is written correctly).

## 4. DESCRIBE omits module-role visibility and layout-grid row visibility

Target and detail: see the inbox note "Durable rebuild of legacy-widget pages" (same date). Listed
here so triage sees it among the learned entries. Status: PARTLY (role visibility is known to be
unwritable; that DESCRIBE also hides it is not recorded).

## 5. Page XPath with a `$currentObject/<association>` comparand → CE0161 (BUG-39 on widgets)

Target: `bug-logs/mxcli-bugs.md` BUG-39 (add a confirmation), `learned-page-patterns.md`.
Status: PARTLY. BUG-39 records it for microflow retrieves only.

```sql
combobox cbLevel2 (
  Attribute: Helper_Level2,
  DataSource: database from "MyModule"."Level2"
    where [MyModule.Level2_Level1 = $currentObject/MyModule.Helper_Level1]
)
```

`check --references` passed; mxbuild: 3 × `CE0161 Error(s) in XPath constraint`, one per cascading combo
box; rolled back (finding). Studio Pro accepts the same constraint.

Workaround that built: each combo box takes its options from a microflow data source that retrieves the
parent into a variable and filters on it.

## 6. Two-hop association data source: neither path form is writable → use a microflow data source

Target: `learned-page-patterns.md` (next to the BUG-04 multi-hop ContentParams section), and
`bug-logs/mxcli-bugs.md` as `## BUG-DRAFT-two-hop-datasource-path:`.
Status: NEW. BUG-20 (cross-module traversal writing a null `DestinationEntityId`) was fixed in v0.17.0;
this is a same-module, two-hop path on v0.25.0.

Short form, exactly as DESCRIBE prints it:

```sql
DataSource: $Parent/MyModule.A_B/MyModule.B_C
```

mxcli stored the last segment as an entity:
`CE1613 The selected entity 'MyModule.B_C' no longer exists.` (5 errors); rolled back.

Full form:

```sql
DataSource: $Parent/MyModule.A_B/MyModule.B/MyModule.B_C/MyModule.C
```

`check` passed; the mxbuild loader crashed:
`An error occurred when trying to set the 'DestinationEntity' property of a Entity ref step in a Page.`
(This crash is what exposed the exec.sh gap in the separate inbox note.)

So DESCRIBE output containing such a path is not re-executable. Rule: no multi-hop association path as a
data-view source; use a microflow data source that retrieves over each association in turn (built clean).

## Not included here

Other cases from the same run (Data grid 2 custom-content column losing its Attribute; XPath through a
reverse association needing read access mxbuild does not check; names `check --references` does not
validate) are upstream mxcli material and are left for a separate note.
