**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-116` — found 2026-09-05 (mxcli v0.19.0-nightly.c836f01, Mendix 11.14.0)
**Suggested labels:** enhancement, mdl, pages, round-trip

---

**Title:** MDL cannot author a File Manager widget — `DESCRIBE PAGE` reads one and emits a comment,
so describe → edit → `CREATE OR REPLACE PAGE` silently drops it and `check` reports clean

**Body:**

## Summary

`Forms$FileManager` is a Studio Pro built-in widget. mxcli **reads** it (`SHOW WIDGETS` lists it,
`DESCRIBE PAGE` reaches it) but has **no grammar production to write one**, so a file-upload
control cannot be placed from MDL at all. Six plausible spellings all fail at the parser with
the same message:

```
filemanager    mismatched input 'filemanager' expecting '}'
fileuploader   mismatched input 'fileuploader' expecting '}'
fileupload     mismatched input 'fileupload' expecting '}'
filedropzone   mismatched input 'filedropzone' expecting '}'
filedocument   mismatched input 'filedocument' expecting '}'
fileinput      mismatched input 'fileinput' expecting '}'
```

The second half is the part that costs data. `DESCRIBE PAGE` of a page that *does* contain one
emits it as a comment, and **that script passes `mxcli check --references` clean** — so the
standard describe → edit → `CREATE OR REPLACE PAGE` loop removes the widget with no error at
any gate.

## Environment

- mxcli: `v0.19.0-nightly.c836f01+jdk25patch+distpatch` (2026-08-27)
- Mendix: 11.14.0
- Reproducible: yes, 100%

## Steps to reproduce

**1. Writing one is impossible.** Any of the six spellings above, e.g.:

```sql
create or replace page MyModule."Probe" (
  Title: 'probe', Layout: Atlas_Core.PopupLayout,
  Params: { $Doc: MyModule.MyFileDocument }
) {
  dataview dv (DataSource: $Doc) {
    filemanager wProbe (Label: 'File')
  }
}
```
→ `mismatched input 'filemanager' expecting '}'`

**2. Reading one works.** `AgentCommons.AgentImportExportFile_NewEdit` (shipped in the
AgentCommons Marketplace module v4.2.0) contains `fileManager1`. `SHOW WIDGETS` lists it as
`Forms$FileManager`, and `DESCRIBE PAGE` renders the page — with the widget replaced by:

```
container container2 (DesignProperties: [...]) {
  -- Forms$FileManager (fileManager1)  -- NOT re-executable: mxcli cannot author this widget, so re-running this script would drop it
}
```

**3. The round trip loses it, and nothing objects.** Save that `DESCRIBE PAGE` output to a file
and run:

```
mxcli check <file>.mdl -p <project>.mpr --references
→ Check passed!
```

Executing it would recreate the page without the File Manager.

## Credit where it is due

**The comment mxcli emits is good behaviour and should be kept.** It names the widget, says
plainly that the script is not re-executable, and says what would be lost. That is better than
most tools do, and this report is not asking for it to be removed.

## Why it still matters

The warning is addressed to a human reading the script. The describe → edit → replace loop is
the documented way to modify a page that `ALTER PAGE` cannot reach, and in an agent-driven or
CI pipeline nothing reads a `--` comment: `check` is the gate, `check` says clean, and the
widget is gone. The failure is silent at exactly the layer that is supposed to catch it.

The authoring gap on its own is also load-bearing rather than cosmetic. File upload is not an
exotic control — on the project that found this, "attach a document to a deal" is a core
requirement, and it is the one part of the feature that had to be handed back to Studio Pro.
The rest of the screen (the entity, the association, the validation, the list, the form) was
built from MDL without trouble.

## Expected — any one of these would resolve it, in decreasing order of value

1. **A grammar production for the File Manager**, matching the other built-ins:
   `filemanager wDoc (Label: 'File', ...)` inside a data view over a `System.FileDocument`
   specialisation. Same for the Image Uploader if it has the same gap.
2. **Failing that, make the round trip loud instead of quiet:** have `check` emit a WARNING
   (or an error under a `--strict-roundtrip` flag) when a script contains a
   `-- NOT re-executable` marker, so a pipeline can fail on it. The information is already
   there — it is only in a form no gate reads.
3. **At minimum, document the unauthorable-widget set** so an author knows before designing a
   screen around a control that cannot be written.

Option 2 is cheap and would have turned a silent drop into a caught one, independently of
whether option 1 is ever done.
