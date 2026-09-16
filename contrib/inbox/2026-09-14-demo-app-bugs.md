**From:** demo-app
**Date:** 2026-09-14
**Kind:** bug
**Field evidence:** bug-log entries in demo-app not found (by heading) in bug-logs/mxcli-bugs.md — verify each against the toolkit log before filing; heading match is a heuristic
**Proposed target:** see per-item notes below

---

## [candidate — from bug-logs/2026-08-14-mpr-recovery-postmortem.md] What happened

1. Live project was down to 1 remaining CE1613 error (20/21 fixed) after a session of
   scripted `mxcli exec` fixes.
2. A 15th scripted write to the same `.mpr` tripped **BUG-004** (mxcli corrupts the
   whole project after ~14-15 cumulative writes) — live project went to 70 errors.
3. Rollback attempted by copying a saved `.mpr` file back over the live one. This did
   **not** work, because Mendix's real project data lives in a separate `mprcontents/`
   directory (a hex-sharded store of `.mxunit` files) — the `.mpr` file is just an index.
   Only the index had been snapshotted; the unit data had already been overwritten.
4. `mprcontents/` was mistakenly deleted, believing it was a disposable cache. It is not
   — it is required primary storage. This crashed the loader outright.
5. The one FULL backup available (`.mpr` + `mprcontents/` together, from a prior session)
   was restored — and turned out to **itself be broken** (BUG-001's fatal
   `InvalidCastException` crash), a pre-existing defect that had never been verified to
   actually load before being trusted as "the clean state."
6. No git repository and no Mendix Team Server connection exist for this project, so
   there was no independent version history to fall back on either.

Net result: no working copy of the project existed anywhere at the point of failure.
Recovery requires rebuilding from `mdlsource/*.mdl` (the build scripts), not restoring
a binary snapshot.


## [candidate — from bug-logs/mxcli-bugs.md] BUG-001: ALTER PAGE ... INSERT AFTER col { column ... } can produce a
malformed widget structure that crashes Studio Pro's loader — FIXED

**Severity:** Fatal. Blocks the entire project from loading in Studio Pro / mxbuild.
**Status:** Fixed (recreate via `create or replace page`).

### Trigger
`Community`'s script 20 ran:
```
alter page "AcademyManagement"."Roster_Overview" {
  insert after Actions {
    column colMessage (caption: 'Message') {
      actionbutton btnMessage (...)
    }
  }
}
```
This is a cross-module `ALTER PAGE` inserting a new DataGrid2 column (with an action
button) into an existing page owned by a *different* module than the one whose script
performed the alter.

### Reproduction
Any full-project load via Studio Pro's own tooling crashes:
```
"<Studio Pro path>/Contents/modeler/mx" check demo-app.mpr
```
```
System.InvalidCastException: Unable to cast object of type
'Mendix.Modeler.WebUI.Forms.Widgets.LayoutWidgets.DivContainers.DivContainer'
to type 'Mendix.Modeler.WebUI.Forms.Widgets.CustomWidgets.WidgetObject'
   at ...StreamingBsonUnitReader...
   at ...UnitLoader.ConstructUnits()
```
Every `mxcli exec` / `mxcli check` / `DESCRIBE PAGE` operation on this same file
succeeds throughout — **`DESCRIBE PAGE AcademyManagement.Roster_Overview` silently
omits the malformed column entirely** from its export. The column is invisible to
mxcli's own reader while still present-and-corrupt in the raw BSON, which is what
Studio Pro's stricter loader chokes on. `DROP PAGE` on the affected page does **not**
clear the crash either — the malformed unit survives in storage; only `DROP MODULE`
(which removes the whole module's folder) or a full `create or replace page` of that
exact page clears it.

### Fix
`create or replace page` (full overwrite, not `create or modify`) of the affected page,
built from a `DESCRIBE PAGE`-derived MDL statement. Since `DESCRIBE` can't even
represent the malformed column, the replacement necessarily drops it.

**Known regression from this fix:** the "Message" quick-action column/button that
`Community`'s script 20 was wiring into `AcademyManagement.Roster_Overview` is lost
once this fix is applied, since there is no way to recover its intended (correct,
non-malformed) structure from the corrupted original. Needs to be re-added from
scratch with a plain, single-module `CREATE OR REPLACE PAGE` (not a cross-module
`ALTER PAGE ... INSERT` column) as a follow-up.

---


