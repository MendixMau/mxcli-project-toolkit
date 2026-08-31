# Resolved mxcli bugs — archived 2026-08-31

Entries retested against mxcli **v0.20.0** (tag `v0.20.0`, built from source on Linux amd64)
on a blank Mendix 11.13.0 project scaffolded by `mxcli new` itself, with every build verdict
from a real native Linux mxbuild `mx check` — the layer the macOS v0.18.0 retest could not
run. Full method, environment and probes:
[mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

Version attribution: entries stamped "≤v0.20.0" were verified fixed on v0.20.0 without
bisecting the fixing release (the last confirmed-broken version is in each entry's own
provenance fields); v0.19.0/v0.20.0 attributions come from the mendixlabs/mxcli changelog
naming the defect. **BUG-81 and BUG-97 are NOT REPRODUCED rather than confirmed-fixed** —
both were filed against unrecorded versions on a much larger real project, so their
verdicts are bounded by the blank-app probe described in the retest report.

---

## BUG-01: `alter entity drop attribute` causes MPR corruption when entity has access rules

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31 on a real Linux mxbuild. Dropping a granted attribute now prints `Removed N access rule member reference(s)`, grants are updated, cold load clean (0 errors).** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** Critical — project becomes unopenable in Studio Pro and mxbuild  
**Reproducible:** Yes, consistently  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact version unrecorded)  
**Retested on v0.13.0:** No — not yet verified fixed or open

### Steps to reproduce
1. Apply security GRANTs on a persistent entity with `read *, write *` (e.g. via `grant Role on Module.Entity (create, read *, write *)`)
2. Run `alter entity "Module"."Entity" drop attribute "AttrName";` via mxcli

### Expected behavior
Attribute is dropped cleanly; project remains loadable.

### Actual behavior
mxbuild and Studio Pro fail to load the project with:
```
KeyNotFoundException: The given key 'd01b1aff-6cf9-49bb-887f-1b5ba49b953c' was not present in the dictionary.
   at UnitContentsLoader.ConstructObjectInternalAndResolvePendingPointers(...)
```

### Root cause (inferred)
Entity access rules store per-attribute UUID pointers in the BSON unit file.
`alter entity drop attribute` removes the attribute from the entity definition but does NOT
update the access rule's internal attribute pointer list. mxbuild fails when it tries to
resolve the now-dead UUID pointer during project load.

Studio Pro's own "delete attribute" UI operation handles this correctly (updates all
references atomically). mxcli does not.

### Workaround
Do not drop attributes that have access rules applied to them via mxcli.
Drop attributes manually in Studio Pro instead.

---

## GRANT: association names silently dropped from member lists; multiple rules per role on one entity not supported

> **RESOLVED — verified 2026-08-31 on v0.20.0. Symptom 1 fixed in v0.17.0 (BUG-59); symptom 2 fixed in v0.19.0 (#936): a second GRANT now merges additively, and two GRANTs with different XPath constraints yield two coexisting rules.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Discovered:** 2026-07-22 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1).

### Symptom 1 — association as a grant member
Adding an association name to a `READ (...)`/`WRITE (...)` member list in a `GRANT` statement execs with 0 errors and passes `mxcli check --references` (which does not validate grant-member names at all — even a totally nonexistent field name like `"TotallyMadeUp12345"` passes `--references` clean). But the association never appears in the resulting grant. Confirmed via `DESCRIBE ENTITY` after real exec, both forms tested:
```sql
GRANT Administration."User" ON Administration."Account" (READ ("FullName", "Account_Supplier"));      -- dropped
GRANT Administration."User" ON Administration."Account" (READ ("FullName", "PLM.Account_Supplier"));  -- also dropped (module-qualified)
```
Exec's own echoed `Result:` line is the only signal — it omits the association from the granted member list even though the statement reported success.

### Symptom 2 — same role, multiple rules on one entity
mxcli cannot represent two separate access rules for the *same* module role on the *same* entity. A later `GRANT` for a role that already has any rule (from a prior `GRANT` in this or an earlier exec) silently **replaces** that role's rule rather than adding a second one — confirmed:
- Two `GRANT Administration.User ON X (...)` statements in the same script → only the last is kept.
- Same two statements split across two separate `exec` invocations (with a git commit between) → same result, only the last is kept.
- Even with **no** `REVOKE` at all beforehand → a second `GRANT` for an already-granted role still replaces the first.

This contradicts real Mendix, which fully supports multiple rules per role on one entity (visible in Studio Pro's access-rule editor, and present in this project's own marketplace-provided `Administration.Account` entity, which shipped with 2 separate `Administration.User` rules — one unscoped read, one self-scoped read/write — before any mxcli edit touched it).

### Workaround
- **Association-as-member:** don't try to grant an association explicitly via mxcli. If the association is only used inside an XPath constraint (`[Assoc = '[%CurrentUser/OtherAssoc%]']`), no member-level grant is needed — Mendix's security engine resolves `[%CurrentUser/Assoc%]` independent of the user's own read permission on that member. Only add the explicit member grant (via Studio Pro GUI) if a microflow/page actually needs to *display* the associated object's data to that role.
- **Multiple rules per role:** if the entity didn't originate with multiple same-role rules already in the BSON, mxcli cannot construct a second one for you. Either (a) merge the intended rules into one (e.g. combine an unscoped read + a self-scoped read/write into one self-scoped rule, accepting the narrower scope — verify nothing in the app depends on the broader access first), or (b) add the second rule via Studio Pro GUI (its editor is unaffected by this mxcli limitation).
- `mxcli check --references` gives **zero** signal for either symptom — it doesn't validate GRANT member names or detect rule collapse. The only reliable verification is `DESCRIBE ENTITY <name>` immediately after every access-rule-touching exec, comparing the actual member/rule list against what the script intended.

### Related preflight rule
Builds on `learned-mdl-preflight.md` rule 14 (revoke-all/regrant-all when patching one role's rule) — that rule assumes mxcli can construct N rules per role from N GRANT statements. It cannot. Rule 14's guidance to rebuild the *whole entity's* security in one script is still correct for avoiding cross-role collapse, but does not extend to multiple rules for the *same* role — that case has no mxcli-only fix.

---

## Compound boolean `AND`/`OR` (uppercase) + `!=` in the same expression → CE0117/CE0161 (mxcli bug)

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31: uppercase `AND` + `!=` in one expression builds at 0 errors on native mxbuild 11.13.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Discovered:** 2026-07-23 (a PLM parts-flow project, mxcli v0.16.0, Mendix 11.12.1).

### Symptom

A microflow with a compound boolean condition mixing an uppercase `AND` and a `!=` comparison — in a Decision/IF activity, or in a `retrieve ... where` clause — passes `mxcli check` (with or without `--references`) cleanly, but a real `mx check` (or Studio Pro compile) fails:

```
[error] [CE0117] "Error(s) in expression." at Decision '$Flag = Enum.HIGH AND $Outcome != Enum.ReleaseHold'
[error] [CE0161] "Error(s) in XPath constraint." at Retrieve object(s) activity '...'
```

### What was tested (isolated throwaway microflows, each executed via plain `bin/exec.sh` + a real `mx check`)

1. `IF $Flag = Enum.HIGH AND $Outcome != Enum.ReleaseHold THEN` → **CE0117**.
2. Same expression wrapped in explicit parens per comparison (`($Flag = Enum.HIGH) AND ($Outcome != Enum.ReleaseHold)`) → **still CE0117**. Parens are not the fix.
3. Same expression with lowercase `and` (no parens): `$Flag = Enum.HIGH and $Outcome != Enum.ReleaseHold` → **0 errors**.
4. Isolation of the actual trigger: uppercase `AND` combined with two `=` comparisons (no `!=`) → **0 errors**. Uppercase `OR` combined with two `=` comparisons → **0 errors**.
5. Same bug reproduced in a `retrieve ... where` clause, not just a Decision activity: `where PartId = 'x' AND PlantCode = $P AND "Status" != Enum.Archived` → CE0161. Switching to lowercase `and` → 0 errors.
6. **Correction (2026-07-23, same session):** the write-up originally claimed uppercase `OR` + `!=` fails "by symmetry" with `AND` + `!=`, without actually testing that combination — step 4 above only tested `OR` with two `=` comparisons. Flagged by the user as an unconfirmed assumption before it could harden into a toolkit rule. Retested directly: `IF $Outcome = Enum.Release OR $Outcome != Enum.ReleaseHold THEN` → **CE0117**, confirming the symmetry claim was correct, but it is now evidence-backed rather than inferred. Lesson: don't write a toolkit rule broader than what was literally executed through a real `mx check` — test every named combination (`AND`+`!=`, `OR`+`!=` are two separate claims), even when a pattern seems obviously symmetric.

### Fix

Use lowercase `and`/`or` for boolean keyword operators in microflow expressions and retrieve WHERE clauses. Confirmed safe in every tested combination (lowercase + `!=`, uppercase + only `=`). Since the exact trigger boundary is narrow and easy to miss, treat lowercase `and`/`or` as the default habit rather than trying to remember which combination is safe.

### Root cause (inferred, not confirmed against mxcli source)

Likely an mxcli expression/XPath serializer bug in how it tokenizes `!=` after an uppercase `AND`/`OR` keyword — not a real Mendix expression-language restriction. Studio Pro itself has no issue with lowercase `and` + `!=`, and accepts uppercase `AND`/`OR` fine when no `!=` is present in the same expression, which rules out a genuine grammar restriction on operator case.

### Related preflight rule

Added as STOP-table rule 17 in `learned-mdl-preflight.md`.

---

## BUG-58: `ALTER PAGE ... SET Editable = [...] ON widget` writes a blank `AttributeIdentifier` regardless of expression complexity → `StorageLoadException` on Studio Pro open

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31. `SET Editable = [expr] ON widget` stores the expression, describes back, and the project cold-loads with 0 errors.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** Critical — project becomes unopenable in Studio Pro
**Reproducible:** Yes, consistently — reproduced with both a compound and the plain
single-condition form of the expression
**Confirmed:** Mendix 11.13.0, 2026-08-07, a PLM parts-flow project
**mxcli version when found:** current (disk write path, `mxcli exec`)

### Symptom

`mxcli exec` on a script of the form:

```mdl
alter page Module."SomePage"
{
  set Editable = ["Attr" = ''] on txtWidget;
}
```

reports success (`Altered page Module.SomePage`, no error) and `mxcli check --references`
passes clean beforehand. The corruption is invisible at both the syntax-check layer and the
`exec` layer — it only surfaces when something actually loads the model's BSON. A subsequent
`mxbuild`/Studio Pro open fails:

```
Mendix.Modeler.Storage.StorageLoadException: One or more invalid values were detected while
loading the project: Mendix.Modeler.Projects.Project:
 - Conditional editability settings in  has an invalid value '' for property Attribute. The
   text 'Forms$ConditionalEditabilitySettings' is not a valid AttributeIdentifier.
```

### Root cause

`ALTER PAGE ... SET Editable = [...] ON widget` is unsafe on this Mendix version **regardless
of the expression's complexity**. Initial hypothesis was that a compound boolean
(`"Attr" = '' or "Attr" = empty`) was the trigger, but a controlled sandbox retest (disposable
copy of the live `.mpr`, never the original) disproved that: re-issuing the exact original
*working* single-condition expression (`SET Editable = ["Attr" = ''] ON txtWidget` — the same
form already in production on this same page) through `ALTER PAGE SET` reproduced the
identical `StorageLoadException`. The `ALTER PAGE SET` mechanism itself blanks the
`ConditionalEditabilitySettings` unit's `Attribute` field when targeting `Editable` on a plain
dataview textbox — expression content is irrelevant.

### Does NOT affect

The same `Editable = ["Attr" = '']` expression written via a full `CREATE OR MODIFY PAGE`
rebuild (not `ALTER PAGE SET`) — that loads and builds cleanly. The bug is in the `ALTER PAGE
SET` write path for this property, not in the expression itself.

### Detection

`mxcli check --references` and `mxcli exec` are both insufficient — this only surfaces via an
actual model load. Sandbox technique that reliably catches it before touching the live model:
`cp` the `.mpr` to a disposable path, `mxcli exec` the candidate script there, then `mxcli
docker check` (or `mxbuild`) the sandbox copy and grep for `StorageLoadException`. Confirm the
technique actually detects the corruption first (reproduce a known-bad case in the same
sandbox) before trusting a clean result on the real candidate.

### Workaround

Do not use `ALTER PAGE SET` to touch conditional `Editable` (and, per BUG-18/BUG-53, `Visible`)
properties at all on this Mendix version — rebuild the whole page via `CREATE OR MODIFY PAGE`
instead, reproducing the page's current `DESCRIBE PAGE` output with only the target property
changed. Matches this project's own `17`→`17d` DataGrid2 precedent in `docs/BUILD-LOG.md`.

### Recovery

`git checkout -- <Project>.mpr` back to the last clean commit — confirmed via `git status
--short` / `git diff --stat HEAD` (binary diff) that the corruption was isolated to the single
exec.

### Related

Same failure signature (blank `AttributeIdentifier` in a `Conditional*Settings` BSON unit →
`StorageLoadException`, invisible to `check`/`exec`, only caught on model load) as [[BUG-21]]
(association assignment in CHANGE/CREATE) and BUG-18/the archived BUG-53 (`Visible:` on a
datagrid customContent container / an action button in a DataView). **BUG-18's text currently
claims regular dataviews are unaffected — that claim needs updating: this finding shows
`Editable` (not just `Visible`) on a plain dataview textbox hits the same defect via `ALTER
PAGE SET`.** Treat any `ALTER PAGE SET` targeting a conditional `Visible`/`Editable` property as
needing a sandboxed model-load check before trusting it, on any widget, not just datagrid
customContent columns.

**Discovered:** 2026-08-07, a PLM parts-flow project, `mdlsource/5-fixes/21-productnumber-newedit-editable-fix.mdl` (initial compound-expression attempt) and the same project's sandboxed retest of the plain single-condition form.

---

## BUG-64: `ALTER SETTINGS CONFIGURATION 'Name' HttpPortNumber = ..., ServerPortNumber = ...` reports success but silently no-ops — value stays unchanged on disk

> **RESOLVED in v0.20.0 — verified 2026-08-31 (changelog: configuration upserts + ALTER SETTINGS name resolution). `HttpPortNumber`/`ServerPortNumber` land and read back via SHOW SETTINGS; 0 errors.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** Medium — blocks Studio Pro's local "Run" (crashes with `HTTP Port number 0 is
not between 1 and 65535`) whenever the model's port fields are `0`; does not affect `mxcli
docker run`, which manages ports itself
**Reproducible:** Yes, consistently
**Confirmed:** Mendix 11.13.0, 2026-08-12, PROJECT-A
**mxcli version when found:** v0.16.0

### Symptom

```
./mxcli -p Project.mpr -c "alter settings configuration 'Default' HttpPortNumber = 8080, ServerPortNumber = 8081;"
```

prints `Updated configuration 'Default'` (no error, exit 0), and the `.mpr` file's mtime
changes. But an immediate re-read shows the old value unchanged:

```
./mxcli -p Project.mpr -c "SHOW SETTINGS"
| Configuration 'Default' | PostgreSql, localhost:5432, db=mendix, http=0 |
```

Ruled out file-lock contention: reproduced identically both while Studio Pro held the file
open (`Project.mpr.lock` present, PID confirmed via `ps aux`) and again after fully quitting
Studio Pro and confirming the lock file was gone — same silent no-op both times. Also ruled
out catalog staleness (`REFRESH CATALOG` before the read made no difference).

### Root cause

Unknown — not narrowed further. `DESCRIBE SETTINGS` proves the property name
(`HttpPortNumber`/`ServerPortNumber`) is real and readable; the write path for these two
specific keys on `ALTER SETTINGS CONFIGURATION` appears to be a no-op despite the success
message. Other keys on the same statement type (`DatabaseType`, `DatabaseUrl`, etc.) were not
retested here to confirm they aren't affected too — treat any `ALTER SETTINGS CONFIGURATION`
write as unverified until read back.

### Detection

Always read back with `SHOW SETTINGS` (or `DESCRIBE SETTINGS`) immediately after any `ALTER
SETTINGS CONFIGURATION` — do not trust the "Updated configuration" success message alone.

### Workaround

Set the port fields directly in Studio Pro's UI (App menu → Settings → Configurations →
select configuration → Port fields) instead of via mxcli. This is a plain GUI field edit and
was not attempted as part of this finding but is the standard fallback for any confirmed
mxcli write no-op.

### Related

Another instance of "exec reports success, disk state doesn't match" alongside BUG-59 (GRANT
silently drops an association) and BUG-62 (SNIPPETCALL SET passes but fails at exec) — a
recurring class where `ALTER`'s success message is not sufficient evidence a write actually
landed.

**Discovered:** 2026-08-12, PROJECT-A, while trying to fix a Studio Pro local-run crash
caused by `HttpPortNumber = 0` left over from Docker-oriented project setup.

---

## BUG-66: `ALTER ENTITY ... ADD ATTRIBUTE "X": autocreateddate;` silently no-ops — no error, no confirmation line, no attribute added

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31. `ALTER ENTITY ADD ATTRIBUTE … autocreateddate` adds the system member; a non-matching declared name now gets warning MDL022 explaining the rename instead of a silent no-op.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Sighted:** PROJECT-A, main build track Stage 5 Phase 11, script 55b (2026-08-12).

**Symptom:** `alter entity "Common"."Attachment" add attribute "CreatedDate": autocreateddate;` passes
`mxcli check` (syntax + `--references`) cleanly, and `mxcli exec` prints only the connection banner —
no `Added attribute ...` confirmation line, no error, no warning. `DESCRIBE ENTITY` afterward shows the
attribute was never added. Confirmed not a fluke: re-ran in isolation, same silent no-op. Confirmed the
`ALTER ENTITY ADD` code path itself works — an ordinary `string(10)` attribute added via the identical
statement shape in the same session succeeded and showed its confirmation line.

**Root cause (inferred, not confirmed against source):** `CREATE ENTITY ... "X": autocreateddate` works
fine (used successfully in script 51 for `Common.Remark.CreatedDate`). The `ALTER ENTITY ADD ATTRIBUTE`
code path appears not to implement the `autocreateddate` pseudo-type at all, and fails open (silently
does nothing) rather than erroring, instead of falling back to an unsupported-type error.

**Impact:** Medium — silent data loss of intent. A script author who doesn't manually re-`DESCRIBE
ENTITY` after every `ALTER ENTITY ADD` involving `autocreateddate` will believe the attribute exists
when it does not, with zero error signal anywhere in the exec output.

**Workaround:** Only add `autocreateddate` attributes via `CREATE ENTITY` at entity-creation time. If an
existing entity needs one added later, there is no working `ALTER ENTITY` path — either recreate the
entity via `CREATE OR REPLACE ENTITY` (data-loss risk if rows exist) or use a plain `datetime` attribute
with manual stamping in a microflow instead (e.g. `CreatedDate: datetime` + `change $Entity (CreatedDate
= [%CurrentDateTime%])` on the create path) rather than relying on the auto-managed pseudo-type.

**Decision applied in PROJECT-A:** skipped `Common.Attachment.CreatedDate` entirely rather than
work around it — it was a "nice to have, matches Remark's shape" cosmetic audit field, not required by
the actual fix in flight (F012 open question S3's author-or-admin lock only needed `CreatedBy`, which
added successfully as a plain `string` attribute). `CreatedBy` alone is sufficient for the delete-lock
logic in `ACT_Attachment_Delete`.

---

## BUG-69: `ALTER ENTITY ... DROP ATTRIBUTE "RefID";` silently no-ops — prints a success line but the attribute is never actually removed, specific to the attribute name "RefID"

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31: an attribute literally named `RefID` (with a not-null rule, as the entity's only attribute) drops for real; `Removed 1 validation rule(s)`; 0 errors.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Sighted:** PROJECT-A, main build track Stage 5 Phase 11, script 56d (2026-08-12).

**Symptom:** `alter entity "Common"."RefIDHolder" drop attribute "RefID";` prints `Dropped attribute
'RefID' from entity Common.RefIDHolder` (a normal success line, not an error), but a `DESCRIBE ENTITY`
run immediately afterward shows the attribute — including its `not null` validation constraint —
completely unchanged. Discovered while trying to fix a genuine CE0070 ("validation rule not allowed on
non-persistent entity") on `Common.RefIDHolder.RefID` by dropping and re-adding the attribute without
the constraint; the re-add step then failed with `Error: attribute 'RefID' already exists on entity
Common.RefIDHolder`, revealing the drop had never actually happened.

**Investigation — three independent reproductions, ruling out live-reference explanations:**
1. On `Common.RefIDHolder` itself, with `SNIPPET_Remarks`/`SNIPPET_Attachments` (the only two documents
   referencing `RefIDHolder.RefID`) still live — initial hypothesis was a live-reference block.
2. Re-tried after dropping both referencing snippets first and confirming via
   `REFRESH CATALOG FULL` + `SHOW REFERENCES TO Common.RefIDHolder` that reference count was zero —
   **same silent no-op recurred**, ruling out the live-reference hypothesis entirely.
3. Minimal isolated repro: created a throwaway scratch entity `Common.ZZTest_RefIDProbe` with a single
   `"RefID": string(50) not null` attribute and nothing else in the project referencing it. Dropping
   just that attribute **also silently no-op'd** (success message printed, `DESCRIBE ENTITY` showed the
   attribute unchanged) — confirming this has nothing to do with references at all.

**Control (proves the DROP ATTRIBUTE code path works in general):** dropping an attribute named
`"ZZProbe"` (a project-unique name) on the same `RefIDHolder` entity, earlier in the same session,
worked correctly and was reflected in `DESCRIBE ENTITY` immediately afterward.

**Root cause (inferred, not confirmed against source):** the attribute name `RefID` is reused as an
attribute name on many other entities throughout this project (`Common.Remark.RefID`,
`Common.Attachment.RefID`, etc.). The drop code's safety/reference-checking logic appears to match by
bare attribute name project-wide rather than by fully-qualified entity+attribute, and silently aborts
the drop without surfacing an error when *any* other entity in the project happens to have an
attribute with the same name — regardless of whether that other entity's attribute is actually
related or referenced.

**Impact:** Medium — silent no-op with a misleading success message, on a plausible everyday shape
(a discriminator/foreign-key-style attribute name reused across many entities, which is normal domain
modeling). Combined with BUG-66's similar "silent no-op with a success-looking message" failure mode
on `ALTER ENTITY ADD`, this suggests `ALTER ENTITY` add/drop code paths generally under-report failure.

**Workaround used in PROJECT-A:** whole-entity `DROP ENTITY` + `CREATE ... ENTITY` recreate instead
of an attribute-level drop, once all referencing documents are confirmed dropped/absent
(`SHOW REFERENCES TO` returning zero). Reliable pattern already established earlier in this same build
effort for other drop+recreate scenarios (see script 56's own RE-RUN CLEANUP notes).

**No fix exists at the attribute-drop level.** This needs an mxcli code fix to key its drop-safety
check off fully-qualified `Entity.Attribute`, not bare attribute name, and to surface a real error
(not a false-success message) when a drop is refused for any reason.

---

## BUG-71: `ALTER SNIPPET|PAGE ... replace "<Column>" with { column ... }` on a datagrid column silently deletes the column instead of replacing it — and once emptied, the datagrid has no anchor left for `INSERT AFTER` to recover it

> **RESOLVED in v0.19.0 (#891) — verified 2026-08-31. A bare column name is now REFUSED with a message naming the `grid.column` form; the qualified form replaces in place. Note: DataGrid2 columns are addressed by DERIVED name (attribute or caption — MDL-WIDGET16), not the authored name.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Sighted:** PROJECT-A, main build track Stage 5 Phase 11, script 56e follow-up verification (2026-08-12).

**Symptom:** Script 56e ran `alter snippet "Common"."SNIPPET_Remarks" { replace "Actions" with { column
colRemarkActions (caption: 'Actions') { actionbutton btnEditRemark (...), actionbutton btnDeleteRemark
(...) } } };` to repoint `btnEditRemark` at a new microflow (the BUG-70 workaround). `mxcli exec`
reported success (`Altered snippet Common.SNIPPET_Remarks`), with zero errors. A `DESCRIBE SNIPPET`
run immediately afterward showed the datagrid's `"Text"`, `CreatedBy`, and `LoggedDate` columns intact
but the entire `"Actions"` column — old or new — **completely absent**. Not reverted to the old
content, not replaced with the new content: gone.

**Isolated reproduction (scratch snippet, `Common.ZZTest_ReplaceProbe`, cleaned up after):**
1. Created a snippet with a datagrid holding two columns: an attribute-bound `"Text"` column and a
   non-attribute-bound column declared as `colActionsNamed (caption: 'Actions')` containing one
   actionbutton. `DESCRIBE SNIPPET` confirmed mxcli normalizes a non-attribute-bound column's stored
   name to its **sanitized caption** regardless of the declared name — the column shows up as `"Actions"`,
   not `colActionsNamed` (this matches the previously-documented ALTER-addressing rule, and was
   correctly applied in the real script's `replace "Actions" with {...}` targeting).
2. Ran `alter snippet ... { replace "Actions" with { column colNewActions (caption: 'Actions') {
   actionbutton btnNew (...) } } };` — reported success. `DESCRIBE SNIPPET` afterward showed the
   datagrid with **only the `"Text"` column left** — the `"Actions"` column, old or new, was gone
   entirely.
3. Repeated against the **other** column (`replace "Text" with { column colTextNew (attribute: "Text",
   caption: 'Remark Text v2') } }`) to rule out anything specific to non-attribute-bound/custom-content
   columns — same result: `DESCRIBE SNIPPET` afterward showed **zero columns at all** on the datagrid
   (the datagrid itself remained, just entirely empty of columns).
4. Control, to isolate this to datagrid columns specifically: ran the identical `replace <name> with {
   <same-widget-type> <name2> (...) }` pattern on a plain, non-datagrid widget (a `dynamictext` sibling
   inside a layoutgrid column, not nested in any datagrid) — this **worked correctly**, producing the
   expected replaced widget with its new content. So plain widget replace is fine; the defect is
   specific to widgets that are themselves columns of a datagrid.
5. Attempted recovery via `INSERT AFTER` once a datagrid had been emptied of all columns by the bug:
   `insert after dg1 { column ... }` does not insert the column *into* the datagrid — since `dg1` (the
   datagrid itself) is a sibling-level widget name from the enclosing layoutgrid column's point of
   view, "insert after" placed the new content as a sibling *after* the datagrid, not as a child column
   of it — and it built as a `container`/nested `layoutgrid`, not a datagrid column at all. There is no
   widget name left *inside* the datagrid to anchor an `INSERT AFTER`/`INSERT BEFORE` once all its
   columns are gone — the datagrid is left in an unrecoverable, columnless state via ALTER alone.

**Root cause (inferred):** `ALTER SNIPPET|PAGE ... replace` correctly removes the targeted datagrid
column, but building/inserting the replacement column back into the datagrid's specific
column-list BSON slot fails silently — the same widget-tree-vs-pluggable-widget-slot mismatch pattern
already seen in BUG-16 (datagrid `customContent` column BSON) and BUG-19 (dataview widget-list type
clash), but manifesting here as a silent no-op/drop rather than a corrupt-BSON crash. `replace` clearly
has a different (and broken) code path for datagrid columns vs. ordinary page/snippet widgets, since
the exact same operation shape works for the latter.

**Impact:** High — any attempt to modify a datagrid column's contents via `ALTER ... replace` silently
destroys the column with no error, and the resulting empty-of-that-column datagrid cannot be repaired
via any further ALTER operation (no anchor widget remains for INSERT AFTER/BEFORE once a datagrid's
columns are gone). Combined with BUG-69 and BUG-70, this is the third silent-success-but-actually-lossy
`ALTER`/`DROP` code path found in this one build phase alone.

**Workaround used in PROJECT-A:** abandon `ALTER SNIPPET ... replace` for datagrid column changes
entirely. Drop and recreate the whole snippet (`drop snippet ...; / create snippet ... { ... full
datagrid, all columns ... };`) with the corrected column content included from the start — the same
whole-document-recreate pattern already established for BUG-67/BUG-68 snippet fixes. Follow-up fix
script: 56f (supersedes 56e's broken `alter snippet replace` step; 56e's new `ACT_Remark_Edit`
microflow itself is correct and unaffected — only the snippet-repoint step needs redoing via
drop+recreate).

**Does NOT affect:** `ALTER ... replace` on ordinary (non-datagrid-column) widgets — confirmed working
via the plain-`dynamictext`-sibling control test above. Datagrid column changes made as part of a
`CREATE`/`CREATE OR MODIFY` (i.e., building the whole datagrid from scratch in one statement, not
altering an existing one) are also unaffected — this is specific to the `ALTER ... replace` code path
applied to an existing column.

**No fix exists at the ALTER level for datagrid columns.** This needs an mxcli code fix so `ALTER
SNIPPET|PAGE replace` on a datagrid column writes the replacement into the same BSON slot type the
column removal read from, instead of dropping the slot's content silently. Until fixed, any datagrid
column change must go through a full snippet/page drop+recreate.

---

## BUG-74: `on error { ... }` handler with no explicit terminal statement silently gets `return;` appended — breaks any "log and continue" error-handling pattern

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31: describe shows the on-error handler without an injected `return;`, execution continues past the call, 0 errors.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

> ### 🔎 Second sighting — candidate/unconfirmed, NOT ready to file (2026-08-20)
>
> A second, differently-shaped manifestation was found in a REST-call `on error without
> rollback { ... }` handler (a shared plumbing microflow that calls a mock API, retries, and
> logs). Root-caused with high confidence from **runtime/behavioral evidence only** — the
> `.mxunit` BSON was not inspected, and no isolated scratch-copy repro (new microflow, zero
> shared project history) has been built yet, unlike the minimal repro already confirmed above.
> **Do not treat this second sighting as confirmed or promote its specifics further until that
> isolation step is done.**
>
> Evidence: the handler's own literal error string appeared in runtime logs (proving the handler
> ran), but a direct Postgres check (bypassing OQL/M2EE) showed a downstream logging microflow's
> row was never written — even though that microflow commits inside its own independent `on error
> without rollback` boundary. The only explanation consistent with both facts is that a bare
> `return;` silently appended to the REST-call handler (which sets two variables but has no
> explicit terminal statement) exited the whole microflow before reaching the trailing `change`/
> log-call statements — same defect shape as the confirmed case below, on a different microflow.
> `mxcli check --references` and native `mx check` both passed with 0 errors, consistent with the
> family.
>
> **Open question, deliberately left open:** whether the fix validated for the confirmed case
> (give the handler its own explicit `return`) generalizes to this microflow's "handle the fault
> and continue in the same flow" shape, or whether that shape needs a different fix — this
> distinction was not resolved before the finding was deferred.

### Symptom

An `on error { ... }` block attached to a `call microflow` activity, whose body is just a
`log warning ...;` statement (no `return`, no `raise error`, no other terminator), builds with
0 mxbuild errors — but the *live model* the script produced is not what was authored. Reading it
back with `DESCRIBE MICROFLOW` shows mxcli silently appended a `return;` as the handler's last
statement, even though the source MDL never wrote one:

Source (`01b-3-orchestration.mdl`, as authored):
```
call microflow "SharedPlumbing"."STUB_DO_SYNCH_PCG_STATE" (
  "SyncContext" = $SyncContext
)
on error {
  log warning node 'SUB_StateSynchronization' 'STUB_DO_SYNCH_PCG_STATE (NAS) raised for ApplicationKey ''' + $SyncContext/ApplicationKey + ''' -- swallowed, B-4 no cross-abort.';
};
```

Live model, round-tripped via `mxcli -p PROJECT-F.mpr -c "DESCRIBE MICROFLOW SharedPlumbing.SUB_StateSynchronization"`:
```
call microflow SharedPlumbing.STUB_DO_SYNCH_PCG_STATE(SyncContext = $SyncContext
) on error {
  log warning node 'SUB_StateSynchronization' '{1}' with ({1} = '...');
  return;
};
```

Because a bare `return;` in Mendix always exits the **entire** microflow (not just the enclosing
`if`/error-handler scope), this silently converts an intended "log the fault and keep going to the
next branch" pattern into "log the fault and abort everything after it." In `SUB_StateSynchronization`
(three independent `if <ShouldSync> then call ... on error { log ... }; end if;` blocks in sequence,
one per channel — NAS, ODS, CBL — explicitly designed so a fault in one channel's stub call can never
block the others, per this project's documented B-4 "no cross-abort" decision), this means: if the
NAS branch's stub call faults, the appended `return;` terminates the microflow immediately, and the
ODS and CBL branches are never attempted at all. `mxbuild` reports 0 errors throughout — this is a
purely semantic/structural defect, invisible to the compiler, only caught by manually diffing
source MDL against the live model's round-tripped serialization (or by a reviewer who knows to
check for it).

### Detection

Caught by a review pass that inspected `SUB_StateSynchronization`'s error-handler shape and flagged
that each `on error {}` block terminated the whole flow instead of just the branch — then confirmed
by direct comparison of the authored source against `DESCRIBE MICROFLOW` output on the live model.

**Minimal repro**, confirmed on this same mxcli build: a single-call microflow with one `on error {
log warning '...'; }` handler (no other statements in the handler) followed by more logic in the
main flow (`log info 'reached after first branch'; return;`). Reading the microflow back after
exec shows the `on error {}` handler now contains `log warning ...; return;` — an unconditional
insertion, not something specific to multi-branch microflows or to this project's particular shape.

### Root cause

Not yet isolated in mxcli's Go source (unlike BUG-73, this has not been traced to a specific
function/line). Suspected to be the same family as BUG-73: codegen for a statement block that
lacks an explicit terminal statement defaults to closing the block with an `EndEvent`/`return`
rather than merging control flow back to the point after the enclosing `if`/error-handler
structure. Whether this happens for *every* terminator-less `on error {}` block unconditionally,
or only under some condition (e.g. only in main-flow scope, only for void microflows), has not been
fully mapped — the one minimal repro above is enough to confirm it is not specific to this
project's exact microflow shape, but the general boundary of the defect is unconfirmed.

### Workaround used in PROJECT-F

Do not rely on an `on error {}` handler's fall-through to continue past a caught fault within the
*same* microflow when more logic follows in the main flow. Instead, extract each
call-with-error-handler into its own tiny wrapper microflow (one per branch). The wrapper's own
body is *only* the call + its `on error { log ...; }` handler — so the auto-appended `return;` is
now correct (it was already about to be the wrapper's last action) instead of destructive. The
caller (e.g. `SUB_StateSynchronization`) then just calls each wrapper microflow in sequence, with no
error handler of its own needed at that level, since each wrapper already fully swallows its own
fault internally and never raises to its caller. This preserves the "independent error boundary per
branch" design (B-4) without depending on any specific `on error {}` fall-through behavior.

### Related

Same general class of defect as [BUG-73](#bug-73-raise-error-in-a-microflows-main-flow-always-fails-mxbuild-with-ce0710--a-genuine-flow-graph-codegen-defect-not-an-mdl-authoring-issue)
(terminal-statement bookkeeping in the flow-graph builder is incomplete for statement forms other
than an explicit `return`), but distinct: BUG-73 causes a hard mxbuild failure (CE0710); BUG-74
causes a *silent* structural change that mxbuild accepts as valid, making it strictly more
dangerous — there is no compiler signal to catch it, only a source-vs-live-model diff or a reviewer
who knows to look for the appended `return;`.

---

## BUG-79: `GRANT`/`REVOKE` cannot target any `System`-module entity — no local domain-model file to write into

> **RESOLVED (BY-DESIGN, better refusal) in v0.20.0 — verified 2026-08-31: the grant is refused up front with Mendix's own reason (System domain model is never stored) and named workarounds. The limitation is the platform's; the leaky error is gone.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Project:** PROJECT-A, script 69b (`GRANT Approval.Reader ON System.WorkflowUserTask (READ *)`).
**mxcli version:** v0.17.0.

**Symptom:** any `GRANT`/`REVOKE` statement whose target entity lives in the built-in `System`
module fails identically, regardless of which `System` entity is targeted:

```
Error: failed to grant entity access: load domain model
00000000-0000-0000-0000-000000000002: open
mprcontents/00/00/00000000-0000-0000-0000-000000000002.mxunit: no such file or directory
```

Confirmed general, not specific to `WorkflowUserTask`: a control test against `System.User`
(`GRANT SomeRole ON System.User (READ *)`) fails with the exact same error and the exact same
missing-file path.

**Root cause:** `System` is a built-in/read-only module with no local domain-model `.mxunit` file
unpacked under `mprcontents/` in the v2 split-format project — mxcli's grant path always tries to
load and rewrite the *target entity's own module's* domain-model file, and for `System` that file
simply does not exist on disk to write into. Read paths (`DESCRIBE ENTITY System.X`,
`SHOW ACCESS ON ... System.X`) are unaffected — those don't need to write anything.

**Distinct from the working `EXTENDS System.X` pattern**: `CREATE PERSISTENT ENTITY MyModule.Foo
EXTENDS System.Image (...)` works fine and is used elsewhere in this project, because that grant
would be written into the *extending* entity's own module (`MyModule`), never into `System` itself.
This bug is only about a grant whose target entity IS a `System` entity directly.

**Workaround:** none via mxcli. Add the access rule manually in Studio Pro's Security editor
(Domain Model → right-click the System entity being consumed, e.g. via a reference or the page
that uses it → Access rules), or grant it on the referencing custom entity/association instead if
the design allows avoiding a direct `System` entity dependency.

**Related:** none identified yet — first sighting of a `System`-module write-path limitation
distinct from BUG-59/60/62 (which are all Studio-Pro/format-compatibility issues, not grant-path
issues).

---

## BUG-80: no MDL/mxcli syntax exists to start a native Workflow *instance* from a microflow

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31: `call workflow Mod.WF ($Ctx);` now exists as a microflow activity, execs and builds at 0 errors (v0.20 also fixed its multi-line parameter mapping, CE0109).** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Project:** PROJECT-A, script 68a (`Approval.ACT_ApprovalRun_Start`). **mxcli version:** v0.17.0.

**Symptom:** `CREATE/ALTER/DROP WORKFLOW` only model the workflow *definition* (the canvas of
`USER TASK`/`DECISION`/etc. activities). There is no MDL statement, and no `mxcli syntax` entry,
for the microflow-side activity that starts a *new instance* of a workflow definition (Mendix
Studio Pro's own "Start workflow" activity, which binds a `Context` object and returns the created
`System.Workflow`).

**Confirmed exhaustively, not just "not found in the docs"**: `./mxcli syntax microflow --json`
and `./mxcli syntax workflow --json` both enumerate every supported activity type with no
workflow-start entry; `SHOW JAVA ACTIONS IN System` shows no callable Java action wrapping it
either; a full-text catalog search for "start" + "workflow" across skill files and `SEARCH
'workflow'` turned up nothing beyond the definition-authoring commands.

**Workaround:** none via mxcli — this is a genuine gap in the modelable activity surface, not a
detection/quoting bug. Every microflow that needs to start a workflow instance must be built via
mxcli up to the point right before the start (parameter/preparation logic, all scriptable), then
finished with one manual Studio Pro step: drag in a "Start workflow" activity, bind
`Context = $YourContextObject`, capture its result into a `System.Workflow` variable, and continue
scripting from there (e.g. `CHANGE` a companion entity to store the returned workflow reference).

**Related:** none — first sighting. Worth checking whether a future mxcli version adds this
activity type before re-deriving the same manual-step workaround on another project.

---

## BUG-81: `create or modify microflow` corrupts attribute-identifier serialization in existing `change $Object (...)` activities — the .mpr then fails to load with fabricated `AttributeIdentifier` errors

> **NOT REPRODUCED on v0.20.0 — verified 2026-08-31 on the minimal shape (2 change activities, create-or-modify rewrite, independent cold load 0 errors). Never minimised originally; likely cured by the v0.19/v0.20 `canon.TransplantIDs`/identity-preservation rework. Downgrade the STOP rule to a read-back.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

> ### ⚠️ TITLE AND ATTRIBUTION CORRECTED — 2026-08-20
>
> **This is not an mxbuild bug.** The original title blamed the mxbuild *model loader* and called
> the failure nondeterministic, which is how it looked before it was bisected. Updates 1–3 below
> (2026-08-14) settle it: the corruption is written by mxcli's `create or modify microflow`
> full-rewrite path, and once written it reproduces **deterministically** on every cold load —
> confirmed against both the CLI mxbuild binary and Studio Pro's own interactive loader. The
> apparent nondeterminism was the *set of attribute names reported*, not whether it fired.
>
> The load-time symptom is mxbuild faithfully refusing a genuinely corrupt model. The defect is
> upstream of it, in the write path. Not retested against v0.18.0 — no changelog line addresses
> this, and reproducing it needs a project carrying the affected microflow shape.

**Project:** PROJECT-E. **mxcli/mxbuild version:** confirmed on both v0.17.0's bundled
Studio Pro 11.13.0 Beta mxbuild AND the separately-downloaded `~/.mxcli/mxbuild/11.12.0` binary.

**Symptom:** `mxbuild --target=deploy <project>.mpr` throws `Mendix.Modeler.Storage.
StorageLoadException` at "Reading project file" — before any real model validation runs — citing
`Mendix.Modeler.DomainModels.AttributeIdentifier.FromString` failures against a *deterministic* set
of otherwise real, valid, correctly-used attributes (`AgentRiskSummary`, `AgentRiskFlag`,
`AgentPrefillSummary`, `ToolResponsibility`, `SupplyCondition`, `PartName` on this run). Confirmed
via `mxcli SEARCH` (after `REFRESH CATALOG` + `REFRESH CATALOG SOURCE`) that every named attribute
genuinely exists and is correctly referenced — this is not a real modeling defect.

**Confirmed reproducible, confirmed NOT session/on-disk-state related:**
1. `bin/exec.sh`'s own mxbuild gate (SP 11.13.0's bundled binary) reported **0 errors, clean** for
   two scripts (`09-...`, `10-...`) executed minutes apart, each immediately followed by a commit.
2. Minutes later, with the working tree showing **zero diff** against that same commit (`git
   status` clean on `PROJECT-E.mpr`/`mprcontents/`), re-running the *identical* `mxbuild
   --target=deploy` invocation against the on-disk tree failed **5/5 times**, always with the same
   6 attribute names.
3. A completely fresh `git archive HEAD` extraction into an isolated `/tmp` directory — no shared
   state with the working tree at all — **also failed**, same error set. Rules out any on-disk-only
   corruption, lock file, or journal artifact specific to the working copy.
4. `mxcli docker build --skip-check` (which only skips the separate `mx check` pre-validation step)
   hits the identical failure, because the deploy build still invokes mxbuild's own loader.
5. A separate isolated test earlier in the same investigation, against an *older* pre-session
   commit extracted into its own `/tmp` copy, reproduced the same failure class but with a
   **different random set** of fabricated invalid-attribute names each of 3 runs — i.e. the
   nondeterminism is real and not tied to any specific commit's content.

**Working theory:** the mxbuild loader's replay of the MPR v2 split-tree journal
(`mprcontents/`-format incremental change log) has a race condition — some attribute references
get read before their identifier GUID resolution is fully in scope, so the loader falls back to
resolving by an empty/interned name string and fails. Whether this fires, and which attributes it
picks, appears to depend on load-order/threading timing, not on the actual model content. This
would explain why `exec.sh`'s gate can report a clean pass immediately after a `mxcli exec` write
(when the freshly-in-memory journal state happens to align) while a cold re-load of the exact same
committed bytes minutes later fails.

**Impact — significant, not yet fully resolved:** this makes `bin/exec.sh`'s own mxbuild gate
**not a reliable green light** — a script can pass the gate and be committed, then fail to load on
the very next `mxcli docker reload`/`docker build`/CLI `mxbuild` invocation, with no way to tell
from the gate result alone. Studio Pro's own interactive "Run Locally" load path has NOT yet been
tested against this exact failure (GUI automation is not available in this environment to verify
independently) — it's unconfirmed whether SP's loader shares this bug or only the CLI mxbuild path
does.

**Workaround:** none found yet that's reliable. Retrying the identical build a handful of times did
not produce a clean pass in this session (5/5 failures). Not yet tried: reopening in Studio Pro
interactively (GUI, to see if SP's own loader is affected) — flagged as the next diagnostic step.

**Related:** distinct from BUG-60 (`docker check` collapsing v2→v1 tree) and CE0066 (SP
security-cache staleness, which is a semantic-check-level issue, not a load-time
`StorageLoadException`). This is the first sighting of the model *failing to load at all*
nondeterministically. Given the severity (undermines trust in the exec.sh gate itself), this should
be escalated/filed upstream once reproduced against a minimal repro case, not just documented here.

### BUG-81 update (2026-08-14) — root cause confirmed, bisected to a specific script

**Root cause found:** bisecting PROJECT-E's git history commit-by-commit (`git archive`
+ fresh `mxbuild --target=deploy` per commit) pinpointed the exact first-bad commit: a
`create or modify microflow` (full-rewrite) statement against two existing, non-trivial
microflows (`WF_ACT_GraphAgent_RiskFlag`, `WF_ACT_TCCopilot_Prefill`) that changed only a
one-line string literal inside each (an `AgentCommons.Agent` title lookup). The rewrite corrupted
the attribute-identifier serialization of **every** `change $Object (...)` activity in both
rewritten microflows — not just the one containing the intentional edit, and not specific to any
one attribute type (hit a String, an Enumeration, and several other String attributes across two
unrelated `change` activities in a second microflow that had no direct relationship to the edited
line). `exec.sh`'s own mxbuild gate passed clean immediately after the write (in-memory model still
had references resolved); only a cold reload — confirmed independently via both the CLI mxbuild
binary AND Studio Pro's own interactive load (screenshot of the identical error dialog) — exposes
the corruption.

**Practical implication:** `create or modify microflow` (full replace) is not safe to trust from a
single post-write mxbuild gate pass when the microflow contains multiple `change $Object (...)`
activities touching entity attributes — this looks like a genuine mxcli/mxbuild write-path
serialization bug in how attribute GUIDs get resolved during a full-microflow re-serialize pass on
an existing (not brand-new) microflow, distinct from a load-time-only race. Recommended mitigation
until this is understood/fixed upstream: after any `create or modify microflow` touching existing
`change` activities, do a SECOND, independent cold-load verification (fresh `git archive` of the
just-committed state + direct `mxbuild`) before trusting the change as landed — a single gate pass
right after the write is not sufficient proof.

**Fix applied this session:** reverted the .mpr to the last commit before this write landed; the
underlying one-line Title-string fix was small enough to be worth re-deriving from scratch with
this new verification step, rather than attempting a repair-in-place.

### BUG-81 update 2 (2026-08-14) — confirmed 100% reproducible, not intermittent

Re-ran the EXACT same `create or modify microflow` statement (identical MDL, identical target
microflows `WF_ACT_GraphAgent_RiskFlag`/`WF_ACT_TCCopilot_Prefill`) a second time against a freshly
reverted, confirmed-clean baseline. Result: **identical corruption reproduced**, confirmed via an
independent cold-load immediately after the write (not just `exec.sh`'s own gate, which again
reported 0 errors). This rules out one-off nondeterminism for THIS specific case — the statement is
deterministically unsafe against this project's model, every time. Reverted again (uncommitted this
time, so a plain `git checkout HEAD --` sufficed). **This script's fix (a one-line Title-string
correction inside two existing microflows) cannot currently be landed via mxcli's
`create or modify microflow` at all** — needs either a different mxcli approach (untried: smaller,
single-microflow-only script; different statement ordering; single microflow per exec instead of
two in one script) or a manual Studio Pro edit.

### BUG-81 update 3 (2026-08-14) — single-microflow-per-exec does NOT avoid it either

Tested the leading untried hypothesis from update 2: split the combined script into two, one
`create or modify microflow` statement per exec (`09a-riskflag-title-fix-only.mdl`, touching ONLY
`WF_ACT_GraphAgent_RiskFlag`, nothing else in the same script/exec). `bin/exec.sh`'s own gate again
reported 0 errors, clean. An independent cold-load (fresh scaffold copy, direct
`mxbuild --target=deploy`, `--java-home`/`--java-exe-path` set explicitly) immediately reproduced
the **identical** `AttributeIdentifier.FromString` corruption on `AgentRiskSummary`/`AgentRiskFlag`
— same signature as the combined script. **This rules out "touching two microflows in one exec" as
the trigger.** The defect is in `create or modify microflow`'s full-rewrite serialization of THIS
microflow's `change $Object (...)` activities specifically (both early-return branches use
`change $PLMStub ("AgentRiskFlag" = ..., "AgentRiskSummary" = ...)`), independent of how many other
microflows are touched in the same script/exec.

Reverted the uncommitted write (`git checkout HEAD -- PROJECT-E.mpr mprcontents`), reconfirmed
clean via cold-load (0 `AttributeIdentifier` errors; the only residual errors were `CE0462` missing-
widget noise from the isolated scaffold's stale `widgets/` folder, a known artifact of this test
method, not a real defect — see update 1).

**Current status: this specific fix cannot be landed via any `create or modify microflow` variant
tried so far (combined, split, single-exec).** Remaining untried options, in order of preference:
1. A manual Studio Pro GUI edit of the Title-lookup string literal in both microflows (lowest risk
   now — proven mxcli path is unsafe for this element).
2. If mxcli exposes a narrower "modify one activity in place" statement (not a full microflow
   rewrite) — untested, may not exist in this binary's grammar.
3. Delete-and-recreate the two specific `change` activities via separate DROP/ADD-style statements,
   if such granularity exists — untested.
Do not retry `create or modify microflow` against this microflow again without a new mitigating
theory backed by evidence — three consecutive reproductions (combined ×2, single-exec ×1) is enough
to call this deterministic and closed pending a real fix, not something to keep probing blindly.

---

## BUG-82: neither `create or modify entity` (full redeclare) nor `ALTER ENTITY MODIFY ATTRIBUTE` can clear an existing "not null error" validation rule — silent no-op with a misleading success message

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31: `MODIFY ATTRIBUTE Email string(200) NULLABLE` now really removes the not-null rule (read back via DESCRIBE). NB the redeclare-without-constraint form reports `Unchanged` and preserves the rule — that is v0.20's omitted-clause-preserves semantics, not the bug.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

> ### ⚠️ CONFIRMED STILL OPEN on mxcli v0.18.0 — retested 2026-08-20
>
> Reproduced on a clean scratch Mendix 11.12.0 project: an attribute declared
> `String(50) not null error 'req'` survives both `create or modify persistent entity …
> (Field: String(50))` and `alter entity … modify attribute Field string(50) nullable` (colon and
> no-colon spellings), each printing a success line while `DESCRIBE ENTITY` and
> `CATALOG.ENTITIES.ValidationRuleCount` stay unchanged. Re-run under `MXCLI_ALWAYS_WRITE=1` with
> identical results, so this is **not** ADR-0008 write-elision. v0.17.0 behaviour is byte-identical.
> **Narrowed:** `MODIFY ATTRIBUTE` correctly **adds** a rule and correctly **changes** an existing
> rule's message (`'req'` → `'CHANGED MSG'` applied). Only **removal** is dropped — the
> diff-and-apply has no delete branch. Same for clearing `UNIQUE`.
> v0.18.0's new `CREATE VALIDATION RULE FOR Mod.Ent.Attr REGEX|RANGE … FEEDBACK` grammar does not
> help: it creates and replaces only, `DROP VALIDATION RULE` is a hard parse error, and
> `mxcli syntax validation-rule` explicitly routes REQUIRED/UNIQUE back to this broken path.
> `DROP ENTITY` + recreate remains the only working clear.
> **Related defect found in the same session, present in v0.17.0 too:** `ALTER ENTITY … DROP
> ATTRIBUTE` never deletes the attribute's validation rule — it orphans it (`CE1613`), re-adding a
> plain attribute of the same name silently resurrects the constraint, and when the rule-bearing
> attribute is the entity's only one the drop is a total silent no-op. The drop-and-recreate
> workaround is therefore only safe at **entity** granularity.

**Sighted:** PROJECT-G, mobile-UI-fixes cycle, fix-65 (2026-08-18).

**Symptom:** `TechniquesLibrary.TechniqueNote.NoteText` was declared `String(2000) not null error 'Note text is required'`. Attempting to remove the constraint two ways both printed a normal success line but left the constraint completely unchanged (confirmed via `DESCRIBE ENTITY` immediately after, and via `SELECT ValidationRuleCount FROM CATALOG.ENTITIES` staying at 1 throughout):

1. `create or modify persistent entity TechniquesLibrary."TechniqueNote" ("NoteText": String(2000));` (attribute redeclared with no constraints at all) → prints `Modified entity: TechniquesLibrary.TechniqueNote`, but `DESCRIBE ENTITY` afterward still shows `NoteText: String(2000) not null error 'Note text is required'` unchanged.
2. `alter entity TechniquesLibrary."TechniqueNote" modify attribute "NoteText": string(2000) nullable;` → prints `Modified attribute 'NoteText' on entity TechniquesLibrary.TechniqueNote`, but `DESCRIBE ENTITY` afterward is again completely unchanged.

Note: `mxcli syntax domain-model.entity.alter` reveals `ALTER ENTITY ... MODIFY ATTRIBUTE` only officially supports `SET DEFAULT val` — it does not document a NULLABLE/NOT NULL clause at all, despite `.ai-context/skills/generate-domain-model.md` in this project documenting `modify attribute X: type nullable;` and `not null` as supported MODIFY clauses. The tool accepted the unsupported clause without a parse error and silently did nothing to the constraint, rather than rejecting it — an under-report-failure pattern consistent with BUG-66/69.

**Isolated repro (rules out live-reference explanations):** created a throwaway scratch entity `TechniquesLibrary.ZZProbe_NotNull (Field: string(50) not null error 'req')` with zero other references. Both `create or modify entity` redeclare-without-constraint and `alter entity modify attribute ... nullable` reproduced the exact same silent no-op on this isolated entity.

**Confirmed workaround:** `DROP ENTITY` + recreate clears the constraint reliably (verified on the same isolated probe: drop, then `create persistent entity ... (Field: string(50));` with no constraint → `DESCRIBE ENTITY` correctly shows the plain attribute, constraint gone).

**Caveat on the workaround for a non-isolated entity:** per BUG-01 (`migrate-general.md`), dropping an entity/attribute that is already referenced by existing microflows/pages leaves dangling UUIDs in their BSON (`KeyNotFoundException` on load) even after recreating an entity/attribute with the identical name — a fresh create gets a fresh UUID, not the old one. For an entity like `TechniqueNote` with live associations, microflows, and a page referencing it, the safe form of this workaround requires dropping and recreating the entire dependent chain (associations → microflows → pages, in dependency order) and re-verifying any external caller (e.g. an action-button `Action:` on a different, unrelated page) that resolves to the recreated microflow/page by UUID, not just by name.

**Impact:** Medium-high — any project that sets `not null` on a persistent attribute (a very common, ordinary domain-modeling choice) has no working non-destructive way via mxcli to later relax that constraint. Combined with BUG-66/69, this strongly suggests `ALTER ENTITY`/`create or modify entity`'s diff-and-apply logic under `ValidationRule`-backed constraints (not null, unique, with a custom error message) generally fails silently rather than actually diffing and applying the removal, while succeeding correctly for pure attribute-property changes (type, length) and additions.

**No fix exists at the MDL/CLI level for a referenced entity.** Needs an mxcli code fix so `ALTER ENTITY MODIFY ATTRIBUTE` genuinely supports (and diffs/applies) NOT NULL/NULLABLE/UNIQUE constraint removal, or at minimum makes the currently-silent no-op a hard error when the requested constraint change doesn't take effect.

---

## BUG-85: `ALTER ENTITY … DROP ATTRIBUTE` never deletes the attribute's validation rule — orphaned rule (`CE1613`), resurrected constraints, and a total silent no-op on a single-attribute entity

> **RESOLVED in v0.19.0 — verified 2026-08-31 (changelog: 'DROP ATTRIBUTE left orphaned validation rules behind'). Both the orphan mode and the sole-attribute silent no-op mode are gone; drop prints `Removed 1 validation rule(s)`; 0 errors.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** High — three distinct silent-success failure modes from one missing delete branch
**mxcli version:** v0.18.0 **and v0.17.0** — pre-existing, not a v0.18.0 regression
**Mendix version:** 11.12.0
**Discovered:** 2026-08-20, isolated scratch entities, while retesting [[BUG-82]]
**Reproducible:** yes, deterministic

`DROP ATTRIBUTE` removes the attribute but never the `ValidationRule` that referenced it. Three
outcomes, depending on the entity's shape:

1. **Entity has other attributes** → attribute removed, rule **orphaned**:
   `[CE1613] The selected attribute 'Mod.Ent.B' no longer exists.` at *Validation rule of entity*.
2. **Re-adding a plain attribute of the same name** → the old constraint is **silently
   resurrected**. The new attribute is declared with no constraints and comes back required.
3. **The rule-bearing attribute is the entity's only attribute** → `DROP ATTRIBUTE` (and
   `DROP ATTRIBUTE … IF EXISTS`) is a **total silent no-op**: prints `Dropped attribute 'F'`, the
   attribute survives in `DESCRIBE ENTITY` and in a freshly rebuilt `CATALOG.ATTRIBUTES`
   (`IsRequired 1`), and re-adding it errors `already exists`.

Same missing-delete-branch root cause as [[BUG-82]]: the diff-and-apply computes additions and
changes but never removals.

**Consequence for the BUG-82 workaround:** drop-and-recreate is only safe at **entity**
granularity. Dropping just the attribute to shed a constraint leaves a `CE1613` that `mx check`
catches but mxcli reports as success.

---

## BUG-90: loop-variable association-path member access inlined into a `call microflow` parameter corrupts codegen

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31: loop-variable attribute path inlined into a call-microflow parameter builds at 0 errors.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** High — a real build-breaker mxcli's own validation never catches
**Reproducible:** Yes, consistently
**Mendix version:** 11.13.0

### Symptom

`mxcli check --references` and `mxcli exec` both report success for a `call microflow` activity
whose parameter directly inlines a **loop variable's association-path member access**, e.g.:

```mdl
loop $Item in $Items
begin
  $IsOnline = call microflow "Mod"."SUB_EvaluateAvailability" (
    "StatusCode" = $Item/"StatusCode"
  );
  ...
end loop;
```

Both mxcli static checks pass (0 errors), but native `mx check` (mxbuild) flags the exact activity
with:

```
[error] [CE0117] "Error(s) in expression."
```

...and the resulting `mxcli docker build` fails outright.

### Isolated bisection

Re-executed the EXACT unmodified MDL for the affected microflow (byte-for-byte, taken verbatim
from `DESCRIBE MICROFLOW` output) against a freshly reset `.mpr` — it still failed native
`mx check` with the identical CE0117 at the identical call activity. This proves the defect is in
how mxcli's own codegen represents this specific parameter-mapping shape (loop-var →
association-path → inline call param), not a symptom of stale/corrupted prior edits or model
history. Also confirmed via `CATALOG.ATTRIBUTES` that the types line up exactly on both sides
(`$Item/StatusCode` is String(10), the callee's `$StatusCode` parameter is String) — ruling out a
genuine type mismatch as the cause.

### Fix

Bind the association-path expression to an intermediate `declare`d variable first, then pass that
variable as the call parameter, instead of inlining the association-path access directly:

```mdl
loop $Item in $Items
begin
  declare $ItemStatusCode string = $Item/"StatusCode";
  $IsOnline = call microflow "Mod"."SUB_EvaluateAvailability" (
    "StatusCode" = $ItemStatusCode
  );
  ...
end loop;
```

Verified: `mxcli docker build` succeeds (0 errors) with the intermediate-variable form, where the
byte-identical inlined form failed identically every time.

### General rule going forward

Never inline a loop variable's association-path member access (`$Item/"Attr"`) directly as a
`call microflow`/`call nanoflow` parameter value. Always bind it to an intermediate `declare`d
primitive variable first, then pass the variable. Apply this prophylactically to any new
loop-body call activity, not just when CE0117 is observed — `mxcli check`/`mxcli exec` give no
warning before the native build fails.

### Related

Same general class of defect as BUG-75/BUG-77 (mxcli's own static checks pass but native
`mx check`/runtime behavior diverges) — verify with the native toolchain or live runtime
behavior, not mxcli's own check output, whenever a construct is unusual.

**Discovered:** 2026-08-13/14, PROJECT-I (a mock-API integration POC project).

---

## BUG-91: `DynamicCellClass` (DATAGRID column property) can only be set at CREATE time — `ALTER PAGE SET` silently fails at exec

> **RESOLVED in ≤v0.20.0 — verified 2026-08-31: `SET DynamicCellClass = '…' ON grid.col` lands and describes back (columns addressed by derived name).** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** Medium — fails one step later than `check --references`, so a script can look
validated and still fail when actually run
**Reproducible:** Yes, consistently
**Mendix version:** 11.13.0

**Distinct from BUG-42.** BUG-42 is a capability gap on **pluggable DataGrid2** — it cannot
combine a row-click `Action:` with `DynamicCellClass` plus TEXTFILTER/DROPDOWNFILTER on one
widget, and is reported as Engalar-fork-specific (not reproducing on RnD `504aec67`). BUG-91 is a
different defect on a **plain (non-pluggable) DATAGRID column**: `DynamicCellClass` alone, with no
filter/action combination involved at all, simply cannot be *set* via `ALTER PAGE` once the column
already exists — a targeting/verb gap in the ALTER code path, not a widget-combination capability
gap. The two share only the property name.

### Symptom

`mxcli check --references` validates `ALTER PAGE ... SET DynamicCellClass = '<expr>' ON <col>`
against an EXISTING DATAGRID column with 0 errors — but running it with `mxcli exec` fails at
execution time with:

```
Error: failed to set: failed to set DynamicCellClass on <Col>: column property "DynamicCellClass" not found
```

This is the opposite failure shape from most of this bug family: it's not silent (it does error),
but the error only surfaces at `exec` time, one full step later than `check --references`. The
same property set inline as part of a brand-new column definition inside a `create or replace
page` statement works with no error at all.

### Reproduction

1. Create any page with a DATAGRID bound to an entity, with at least one plain column (no
   `DynamicCellClass` set):
   ```mdl
   create page Mod.Foo_Overview (Title: 'Foo') {
     datagrid dgFoo (DataSource: DATABASE Mod.Foo) {
       column col1 (Attribute: Status, Caption: 'Status')
     }
   }
   ```
   `mxcli exec`: succeeds.
2. Attempt to add `DynamicCellClass` to the EXISTING column via `ALTER PAGE`:
   ```mdl
   alter page Mod.Foo_Overview {
     SET DynamicCellClass = 'if $currentObject/Status = "Error" then "danger" else "plain" endif' ON "col1";
   }
   ```
3. `mxcli check --references` → **0 errors** (validates cleanly).
4. `mxcli exec` → **fails**: `Error: failed to set: failed to set DynamicCellClass on Col: column
   property "DynamicCellClass" not found`
5. Confirmed via a disposable scratch page (created then dropped — don't leave scratch objects in
   the live model) that the identical property, when included directly in a fresh `create page`/
   `create or replace page` statement's column definition from the start, applies with no error:
   ```mdl
   create or replace page Mod.Foo_Overview (Title: 'Foo') {
     datagrid dgFoo (DataSource: DATABASE Mod.Foo) {
       column col1 (
         Attribute: Status,
         Caption: 'Status',
         DynamicCellClass: 'if $currentObject/Status = "Error" then "danger" else "plain" endif'
       )
     }
   }
   ```
   → `mxcli exec`: succeeds, property applies and renders correctly.

### Root cause (as observed, not verified against mxcli source)

`DynamicCellClass` appears to be handled by mxcli's `create page`/`create or replace page`
column-construction path, but has no corresponding "alter existing column" handler wired into the
`ALTER PAGE SET ... ON <col>` code path — the ALTER command's validator (used by
`check --references`) doesn't distinguish "this property exists but isn't settable via ALTER" from
"this property is generally valid," so it passes the check but the executor then can't find a
handler for it.

### Workaround

Any page needing a NEW or CHANGED `DynamicCellClass` on an EXISTING column requires a full
`create or replace page` rewrite of that page, grounded in the current live `DESCRIBE PAGE` output
(never a stale saved `.mdl` file — the live page may have drifted from any prior script via later
ALTERs). A full rewrite also risks resurfacing unrelated legacy issues that a narrower ALTER would
have tolerated — e.g. duplicate layoutgrid column widget names (`col1`/`col2`/`col3` reused across
multiple rows) that years of incremental ALTERs never flagged, but `create or replace page`'s
CREATE-time validator rejects outright as `duplicate widget name 'col1' (used N times) — Mendix
requires unique widget names per page (CE0495)`. Rename to unique names per row before attempting
the rewrite.

### General rule going forward

Never assume `mxcli check --references` passing on an `ALTER PAGE SET <Property> ON <widget>`
means the property is actually settable via ALTER — some page/column properties (confirmed so
far: `DynamicCellClass`) are CREATE-time only despite validating cleanly. If an ALTER unexpectedly
fails at exec with "`<property>` not found", the fix is a full `create or replace` rewrite, not a
syntax correction.

**Discovered:** 2026-08-14, PROJECT-I (a mock-API integration POC project).

---

## BUG-97: `.mpr` write path corrupts the entire project on the ~15th cumulative write operation — content-, order-, transaction- and engine-independent

> **NOT REPRODUCED on v0.20.0 — verified 2026-08-31: 16 sequential mixed write-class execs against one lineage, native mx check clean at cumulative writes 14, 15 and 16. Lighter content mix than the original incident; relax the hard 10–12 cap to snapshot-plus-read-back until a real project confirms.** See [mxlabs-v0.20.0-retest-2026-08-31.md](mxlabs-v0.20.0-retest-2026-08-31.md).

**Severity:** Critical — silent, project-wide corruption; surfaces only on the next full `mx check`, as ~70 errors across entities/microflows/pages never touched in the session
**Reproducible:** Yes — 6 independent disposable copies, corruption at the same cumulative count every time
**mxcli / Mendix version:** not recorded in the source log (build ran 2026-08 on Mendix 11.x)
**Discovered:** 2026-08-14, a martial-arts-academy PoC project

### Trigger

The 15th sequential write-class `mxcli exec` operation (`create or replace microflow/page`,
`alter page`, `grant`/`revoke` — any content) against the same `.mpr`, counting cumulatively
from a clean baseline.

### Ruled out (each reproduced identically)

1. **Content** — three unrelated 15th operations (heavy microflow recreation, the same with
   the logic stripped, a one-widget `alter page`) all corrupt.
2. **Order** — the complex operation placed 1st, 12th or 15th; corruption always at count 15.
3. **Transaction boundaries** — 15 separate `mxcli exec` invocations vs one invocation with
   48 statements: identical.
4. **Write engine** — `modelsdk` and `--engine legacy`: identical.
5. **External cache** — corruption follows the `.mpr` file's own lineage across fresh `/tmp`
   copies; nothing project-keyed found outside the file. Points at something in the file's
   own structure (hypothesis, labelled as such: an incremental-write delta counter/index a
   full Studio Pro save would compact and reset — unconfirmed).

At exactly 14 operations `mx check` is clean (verified 3 times across orderings); at 15 it
reports ~70 errors with a project-wide signature (CE0066/CE0069/CE0109/CE0156/CE1571/CE7247
spanning untouched modules) — a global ID/reference-table corruption, not a local defect.

### Workaround / operating rule

Cap sequential `mxcli exec` writes at **10–12 per session** against any given `.mpr` (14 is
the measured cliff edge; leave margin), then have a human do one interactive Studio Pro save
before resuming scripted work. The counter-reset theory is unconfirmed — re-test after a
manual save and update this entry.

### Recovery hard lessons (from the same incident's postmortem)

- A saved `.mpr` file alone is **not a backup** — on split-model projects the real unit data
  lives in `mprcontents/` (hex-sharded `.mxunit` store); the `.mpr` is an index. Snapshot
  both together or the rollback restores an index over already-lost data.
- `mprcontents/` is primary storage, never a disposable cache — deleting it kills the project.
- **Verify a backup actually loads (`mx check`) before trusting it as the clean state** — the
  incident's one full backup turned out to carry a pre-existing fatal loader crash (BUG-96's
  class) that had never been load-verified.
