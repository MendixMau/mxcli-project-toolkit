# File upload widget — a file upload mxcli can author, and proof that it uploads

**Applies to:** any mxcli project
**Purpose:** putting a working file upload on a page: the Mendix File Uploader 2.5.0 pluggable
widget bound to a `System.FileDocument` specialisation, with its create/delete microflows, grants
and allowed formats. Covers which upload widgets mxcli cannot author, the two CE0463 / round-trip
traps with their workarounds, and the instrument that proves an upload works end to end. Load it
before adding any upload/attachment/document field, when an uploader page fails `mx check` with
CE0463, or when a DESCRIBE of an uploader page will not re-execute.
**Source:** a Mendix app-rebuild project, 2026-09-25 (research, then a 6-iteration e2e loop, then a
v0.24.0 re-test).

---

Field-proven 2026-09-25 on Mendix 11.12.2, in throwaway apps made with `mxcli new`, on stock
mxcli **v0.23.0** and again on stock **v0.24.0**. On v0.24.0 the MDL in section 4 was run exactly as
written, taken straight from this file, with only a wrapper around it (module, role, page, menu microflow,
demo user). Result: `mxcli check --references` passed, exec reported 0 errors, `mx check` said
`The app contains: 0 errors.`, and the app booted. A non-admin user uploaded 2/2 files (1024 B .txt,
244 B .zip), both rows had `HasContents true`, both downloads were sha256-equal to the source (2/2
`MATCH`), and a `.csv` was rejected with 0 rows created. Both traps in section 5 reproduce unchanged on
v0.24.0.

## 1. Pick the widget

| Widget | mxcli can author it? | Use it? |
|---|---|---|
| **Mendix File Uploader 2.5.0** (`com.mendix.widget.web.fileuploader.FileUploader`, keyword `fileuploader`) | Yes, on stock v0.23 and v0.24, with the rules below | **Yes.** Proven end to end |
| Classic `Forms$FileManager` (Studio Pro "File manager") | No. No keyword. A `.def.json` gives a false-green `mxcli check`, then exec fails with `template not found: filemanager` | No, until mxcli gets a native `filemanager` (upstream #151) |
| `mendix.PDSFileUploader` | Writes, but stock mxcli gives CE0463 (action variables not written). It also posts to a REST endpoint, not to a FileDocument | Only with a REST backend and a patched mxcli |

## 2. What the File Uploader needs (it is not a FileManager)

The File Uploader does not fill the data view's own object. It works on a **context object** and
creates one FileDocument per dropped file:

1. The widget calls `createFileAction` with the context object. That microflow creates the file
   entity, sets the association to the context, and commits it.
2. The widget watches `associatedFiles` (an association path from the context) for the new
   object, then POSTs the bytes to `/file?guid=<id>`.
3. On failure it calls `onUploadFailureFile` with the file object, so that microflow can delete it.

So the domain model is: a context entity, a `System.FileDocument` specialisation, and a reference
from the file to the context.

## 3. Install

1. Get the widget `.mpk`. The Marketplace module package (`FileUploader.mpk`, 2.5.0, sha256
   `9e592629…`) contains `widgets/com.mendix.widget.web.FileUploader.mpk`. Copy only that inner file
   into the project's `widgets/`. The module's own entities and nanoflows are not needed.
2. Run `mxcli widget init -p App.mpr`. Without it you get `MDL-WIDGET25 fileuploader is not a widget in this project`.

## 4. The working MDL shape

```sql
create persistent entity "Uploads"."UploadRequest" ("Title": String(200));
create persistent entity "Uploads"."Attachment" extends System.FileDocument ("Note": String(200));
create association "Uploads"."Attachment_UploadRequest"
  from "Uploads"."Attachment" to "Uploads"."UploadRequest" type reference;

-- tested with write * (includes Name and Contents). The module's own reference grant writes Name, Contents and the association; a narrower grant was not tested
grant "Uploads"."User" on "Uploads"."UploadRequest" (create, delete, read *, write *);
grant "Uploads"."User" on "Uploads"."Attachment"    (create, delete, read *, write *);

create microflow "Uploads"."ACT_CreateAttachment" ($UploadRequest: "Uploads"."UploadRequest")
returns "Uploads"."Attachment" as $Attachment
begin
  $Attachment = create "Uploads"."Attachment" ("Attachment_UploadRequest" = $UploadRequest);
  commit $Attachment with events refresh;
  return $Attachment;
end;
/
create microflow "Uploads"."ACT_DeleteAttachment" ($Attachment: "Uploads"."Attachment")
begin
  delete $Attachment;
end;
/

-- inside a dataview on the context object:
fileuploader "upFiles" (
  uploadMode: 'files',
  associatedFiles: association $currentObject/Uploads.Attachment_UploadRequest,
  readOnlyMode: false,
  createFileAction: microflow Uploads.ACT_CreateAttachment,
  onUploadFailureFile: microflow Uploads.ACT_DeleteAttachment,
  maxFileSize: 5,
  objectCreationTimeout: 10,
  enableCustomButtons: false
) {
  allowedfileformat "fmtTxt" (configMode: 'advanced', mimeType: 'text/plain', extensions: '.txt', typeFormatDescription: 'Text file')
  allowedfileformat "fmtZip" (configMode: 'advanced', mimeType: 'application/zip', extensions: '.zip', typeFormatDescription: 'ZIP archive')
}
```

Also grant `execute` on both microflows to the user's module role. Missing grants give CE0106 at `mx check`.

**Commit the context object before you open the page.** The menu microflow creates the
`UploadRequest`, commits it, then shows the page. The Save button then only has to commit it again
(or commit and show a result page). An uncommitted context was not tested.

## 5. The traps, and what to do on stock v0.23 / v0.24

Both of the first two traps reproduce unchanged on v0.24.0, which was re-tested 2026-09-25. v0.24's CE0463 fix (#1161) is for
Barcode Scanner's seeded object lists, a different cause. Both are filed upstream: the simple-mode CE0463 as mendixlabs/mxcli#1198, the DESCRIBE round trip as #1199
(closed #999 and #574 are related but not the same). When a newer mxcli ships, re-probe both on a copy before trusting this table:
(1) change one format to `configMode: 'simple', predefinedType: 'plainTextFile'`, exec, run `mx check`;
(2) `describe page` the uploader page and exec the output unchanged on a copy that differs from it.

| Trap | Symptom | Stock v0.23 / v0.24 workaround | Proposed fix (proven on a local mxcli build, not upstream yet) |
|---|---|---|---|
| `allowedfileformat` in the default `configMode: 'simple'` (`predefinedType: 'plainTextFile'`) | `mx check`: `[CE0463] "The definition of this widget has changed. ..." at File uploader 'upFiles'`, `The app contains: 1 errors.` | Write every format as `configMode: 'advanced'` with `mimeType`, `extensions` and `typeFormatDescription` | Nested visibility rules applied to object-list items: the hidden required `typeFormatDescription` is written as null (Studio Pro's shape), not as a filled template |
| DESCRIBE of an uploader page, then re-exec | exec: `` widget `upFiles` (fileuploader) exposes 2 datasources, so a generic `datasource:` clause is ambiguous — name the one you mean: associatedFiles, associatedImages `` | Hand-edit the DESCRIBE output: change `DataSource:` to `associatedFiles:` | DESCRIBE names the key when the widget's schema declares more than one datasource |
| Object-list item names | DESCRIBE prints `allowedfileformat1`, not the name you wrote, so `drop widget "fmtTxt"` has nothing to hit later | Replace the whole page (`create or replace page`) to change formats | Not fixed |
| DESCRIBE prints `predefinedType: 'pdfFile'` on advanced items | Re-exec warns `MDL-WIDGET10 ... predefinedType is hidden when its own configMode is not "simple" — the value will be ignored` (a warning; mx check stays 0 errors) | Delete that line from advanced items | Not fixed |
| `mxcli check` says "Check passed!" | Proves nothing for widgets: CE0463 only shows at `mx check` | Always run `mx check` after exec | n/a |
| Re-exec of an identical page | `Unchanged page ...`: nothing was written, so `0 errors` proves nothing about the round trip | Run a round-trip test against a copy where the page differs | n/a |

With the locally patched build, a simple-mode `.txt` format is shown at runtime as "Plain Text (.txt)" in
the rejection message, so the predefined type does reach the widget.

## 6. The instrument: what counts as "the upload works"

`mx check` 0 errors only proves the model is valid. The upload counts as working only when all of these hold:

1. `mx check`: `The app contains: 0 errors.`
2. The app boots: `mxcli run --local ... --db-type hsqldb --app-port <free> --admin-port <free> --serve-port <free>`.
   The default serve port 6543 collides with Studio Pro's own `mxbuild --serve`, so pick a free one.
3. Playwright, logged in as a **non-admin** demo user: open the page, then
   `page.locator('.mx-name-<widget> input[type=file]').setInputFiles([...])`. Wait until the widget text
   shows `Uploaded successfully.` once per file, then click Save.
4. OQL on your own admin port: `mxcli oql -p App.mpr --direct --port <admin> "select a.Name, a.Size, a.HasContents from Mod.Attachment a"`.
   The default `--port` is 8090. Never let it default when another app is running.
5. Download the file back as the same user (`GET /file?guid=<id>&target=internal` in the logged-in
   browser context) and compare its sha256 with the source file. This catches a HasContents=true row that holds the wrong bytes.
6. Negative check: drop a format you did not allow. The widget must show `File format is not supported, ...`, and no row may be created.

Measured result, stock v0.23 (advanced formats): 1/1 file stored, 1024 bytes, `HasContents true`, sha256 match.
Stock v0.24.0 (advanced .txt and .zip, fresh app): 2/2 files stored (1024 B and 244 B), 2/2 sha256 match, `.csv`
rejected with 0 rows created.
Patched build (simple .txt plus advanced .zip, written from a DESCRIBE round trip): 2/2 files stored
(1024 B and 244 B), both sha256 match, `.csv` rejected with 0 rows created.

## 7. Not covered

- Image mode (`uploadMode: 'images'`, `associatedImages`, `System.Image`) was not tested.
- Custom buttons, `maxFilesPerUpload`, and the delete-from-widget path were not tested.
- Only the `mxcli run --local` runtime with HSQLDB was used. Not tested on PostgreSQL, in Docker, or opened in Studio Pro.
- The proposed fixes in section 5 exist only as a local mxcli patch with unit tests (#1198, #1199 describe them). When those issues close,
  re-run the simple-mode format and the DESCRIBE round trip before dropping the workarounds.
