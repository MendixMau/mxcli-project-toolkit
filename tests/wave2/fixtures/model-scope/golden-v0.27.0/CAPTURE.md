# golden-v0.27.0 — provenance (captured 2026-10-21, macOS arm64)

A real `alter entity … rename attribute` by mxcli v0.27.0 on a public model, before and after.
Nothing here was hand-written except this file, the two MDL scripts and `add-linebreaks.py`
(they told mxcli and mxpatch what to do). The unit files and `.mpr` dumps are what the tools
wrote. It reproduces mendixlabs/mxcli#1596.

## Binary

`mxcli version v0.27.0 (2026-10-15T13:45:04Z)`, the public release binary.

## Model

Base: `tests/wave2/fixtures/mxpatch/model/` of this repo (MPR v2, Mendix 11.14.0; its own
provenance is in `fixtures/mxpatch/CAPTURE.txt`), with the `.mpr` rebuilt from its sqlite dump.
On a copy, in a fresh git repository:

1. `mxcli exec capture-base.mdl -p TestApp.mpr`. It creates module `Other`, the entities
   `MyFirstModule.Item` (with an attribute `Unused` that no XPath names) and `Other.Thing`, and
   one microflow in each module that retrieves with a two-condition XPath. mxcli stores those
   XPaths on one line, `[Label = 'A'][Flag != 'B']` (mendixlabs/mxcli#1542).
2. `python3 -I add-linebreaks.py <toolkit>/project-bin TestApp.mpr`. Through `mxpatch.py`, this
   puts `\n` between the bracket groups of both stored `XpathConstraint` values and writes each
   unit and its ContentsHash row together. That gives `[Label = 'A']\n[Flag != 'B']`, the
   two-line form the Studio Pro-authored XPaths of the field incident had. `mxcli describe microflow
   Other.ACT_Thing_Fetch` then shows the condition on two lines, and `mxcli fix hashes` reports
   that the index matches every unit file. This state was committed. It is `before/`.
3. `mxcli exec capture-rename.mdl -p TestApp.mpr` renames `MyFirstModule.Item.Unused` to
   `Unused2`. Its stdout is `rename-v0.27.0.out` and its exit code is `rename-v0.27.0.exit`
   (stderr was empty). It prints "Updated 2 XPath constraint(s) in 2 document(s)".
   `git status` then lists `TestApp.mpr` and three unit files. That state is `after/`.

## Files

- `before/TestApp.mpr.sql` and `after/TestApp.mpr.sql`: the `.mpr` as a sqlite dump. `*.mpr`
  is gitignored here, so the test rebuilds the file with `executescript`.
- `before/mprcontents/`: the three units the rename rewrote, plus the two module units
  (`16747dc6-…` MyFirstModule, `f83ca969-…` Other) that the module walk reads.
- `after/mprcontents/`: the same three units as the rename left them.
  - `84776610-…` is the MyFirstModule domain model. This change is real: the attribute's
    `Name` changed.
  - `c2e900a8-…` is `MyFirstModule.ACT_Item_Fetch`. This change is noise:
    `[Status = 'Open']\n[Code = 'X']` became `[Status = 'Open'][Code = 'X']`.
  - `ce321a44-…` is `Other.ACT_Thing_Fetch`, in a module the script never named. This change is
    noise: `[Label = 'A']\n[Flag != 'B']` became `[Label = 'A'][Flag != 'B']`.
- `restore-v0.27.0.out`: `model-scope.py restore` run on a copy of `after/` in that repository.
- `fix-hashes-after-restore-v0.27.0.out`: `mxcli fix hashes -p TestApp.mpr` run right after that
  restore, with blank lines dropped. It exited 0, and the output says the index matches every
  unit file. `describe microflow Other.ACT_Thing_Fetch` showed the two-line XPath again.

## Not checked

The capture did not run `mx check` / mxbuild on the restored model. Mendix 11.14.0 mxbuild was
not available on the capture machine.
