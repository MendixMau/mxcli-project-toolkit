# exec.sh --patch: deleting a Unit row is refused by `mxcli fix hashes --repair` (ORPHAN file); rename-then-drop is the route that works

**From:** a field project (anonymised)
**Date:** 2026-10-12
**Kind:** learning
**Field evidence:** two pages with the same qualified name (a live one and an excluded, archived copy in
another folder). mxcli v0.25.0, Mendix 11.14.0 Beta, MPR v2, toolkit c1efcb3. The failed patch was
rolled back by exec.sh; the second route built at 0 errors.
**Proposed target:** `skills/learned-mdl-preflight.md` (a workaround row) or `skills/learned-mdl-cannot-express.md`;
an upstream mxcli ask

---

## Situation

`MyModule.Detail` existed twice: the live page and an archived copy (excluded from the project) with
the same name in `Archive/Pages`. mxcli addresses documents by qualified name only, and different
commands resolved the name to different copies: `DESCRIBE PAGE` found the live one, `SHOW ACCESS ON PAGE`
the archived one, so a `grant view` by name landed on the archived copy. There is no `drop page … in
folder '…'` and no drop by unit id.

## Route 1, refused (finding)

A gated patch through `./bin/exec.sh --patch` deleted the archived page's row from the `.mpr` `Unit`
table and left its `.mxunit` file on disk (file removal being left to the owner). The patch's
`mxcli fix hashes --repair` step then reported the file as **ORPHAN** (present on disk, not indexed)
and failed; exec.sh restored the snapshot. Afterwards both pages were present and 3161 units verified.

## Route 2, worked (finding)

1. A gated patch renamed only the archived unit's top-level `Name` to `Detail_Archived`, after a
   byte-identical decode/encode round-trip check of that unit. mxbuild stayed at 0 errors.
2. Then plain MDL, through exec.sh: `drop page if exists "MyModule"."Detail_Archived";`

## Rule proposed

To remove one of two same-named documents: rename it by patch, then drop it by MDL. Never delete a
`Unit` row by hand; `fix hashes --repair` treats the leftover file as an orphan and the gate rolls back.

Ask for upstream mxcli: warn when a qualified name resolves to more than one document, make every
command resolve it the same way, and add `drop page … in folder '…'` or a drop by unit id.

Related, not the same: #294 (a shared patch helper) and #295 (adopt `mxcli fix hashes` in `--patch`).
