**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-rename-page-renames-folder` — found 2026-09-25 (field report on v0.23.0, reproduced on v0.24.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, rename
**Duplicate check:** searched 2026-09-25 (`rename page renames folder with the same name`). No match (#426, #154 are unrelated).

---

**Title:** `rename page` renames a folder with the same name instead of the page, and reports success

**Body:**

## Summary

`RenameDocumentByName` (`mdl/backend/modelsdk/infrastructure_write.go`) walks every unit in the module's container set and rewrites the first unit whose top-level `Name` equals the old name. It never checks `$Type`. Folders are units too, so when a folder with the page's name comes first in unit order, the folder is renamed, the command prints "Renamed page", and callers are repointed to a page name that does not exist (CE1613 at build).

**Version:** mxcli v0.24.0 (also v0.23.0), Mendix 11.12.1, MPR v2. Same code on `main` as of 2026-09-24.

## Repro

The folder must be older than the page:

```
create page RenA.Other (Title: 'Other', Layout: Atlas_Core.Atlas_Default) {
  container c1 { dynamictext t1 (Content: 'y') }
};
move page RenA.Other to folder 'Pages/Same';
create page RenA.Same (Title: 'Same', Layout: Atlas_Core.Atlas_Default) {
  container c1 { dynamictext t1 (Content: 'x') }
};
```

```
mxcli exec repro.mdl -p App.mpr
mxcli rename -p App.mpr page RenA.Same Same_Overview
mxcli -p App.mpr -c "show pages in RenA"
```

## Measured (v0.24.0)

```
Renamed page: RenA.Same → RenA.Same_Overview
| RenA.Other | RenA | Other | false | Pages/Same_Overview | ...
| RenA.Same  | RenA | Same  | false |                     | ...
```

`git status` shows one changed unit, and its `$Type` is `Projects$Folder`. If the folder is created *after* the page, the page is renamed correctly, which is why this looks intermittent.

## Expected

`rename page` only matches `Forms$Page` units (and the other `rename <type>` variants only their own type).

## Workaround

Move the folder's documents out, drop the folder, rename the page, move them back. Always read the model back after a rename.
