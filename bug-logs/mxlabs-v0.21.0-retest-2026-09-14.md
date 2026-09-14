# mxlabs mxcli v0.21.0 retest — 2026-09-14

Open and untested bugs retested against a freshly built v0.21.0, cross-checked against the
v0.21.0 changelog (2026-09-06) — one release landed since the last retest baseline (v0.20.0,
2026-08-31). Investigation only; no GitHub issues filed; no real project touched — every probe
ran in a disposable copy of a scratch app created for this retest, in a container with no
outbound Docker daemon.

## Gate 0 — binary tested

- Repo: local clone of `mendixlabs/mxcli`, `git checkout v0.21.0` (detached; branch restored to
  its prior `fix/workflow-with-unquoted-value-segfault` afterward)
- **Commit tested: tag `v0.21.0`**, `git describe --tags` = `v0.21.0` (clean tree, not `-dirty`)
- Built with `make build` on Linux amd64, go1.26.6. The ANTLR 4.13.2 jar was already cached
  locally (`antlr4 -Dlanguage=Go ...` reported "Found version '4.13.2', this version may be out
  of date" and proceeded) — the egress-proxy block noted in the v0.20.0 retest did not need to be
  exercised this round.
- Verified: `mxcli version v0.21.0 (2026-09-14T06:12:49Z)`

Note on provenance: this repo's working tree was on branch `fix/workflow-with-unquoted-value-segfault`
before checkout — a fix for exactly BUG-107 below, not yet merged/tagged. The binary under test is
the tagged v0.21.0 release, which does **not** include that unreleased branch; BUG-107 is verified
STILL OPEN against the actual release, not against the fix-in-progress.

## Test environment

- Baseline: **blank Mendix 11.13.0 app scaffolded by `mxcli new TestApp --version 11.13.0`**
  itself (v0.21's own scaffold; first build settled by `new`), plus one `Retest` module created
  once and reused as the base copy (`baseline/`) for every probe.
- **`mxcli docker check` on Linux amd64 auto-resolves to a native mxbuild binary**
  (`~/.mxcli/mxbuild/11.13.0/modeler/mx`) even though the Docker daemon itself is unreachable in
  this container (`docker ps` fails to connect to the socket) — confirmed once at the top of the
  session. Every verdict below marked `build-verified: yes` rests on this **real native mxbuild
  consistency check**, not a mocked or skipped one.
- Disposable copies: the whole scaffolded project tree (`cp -r`) per probe group, never the live
  worktree, never a real project.
- Every FIXED/STILL OPEN verdict rests on `check`/`exec` plus a `DESCRIBE` read-back and/or a
  native `mxcli docker check` pass, never on a success message alone.

## Verdicts

### Round A — the 8 entries the v0.20.0 retest left STILL OPEN

| Bug | Verdict | Build-verified |
|---|---|---|
| BUG-76 workflow DECISION storage corruption | **STILL OPEN — CRITICAL, byte-exact original signature** | yes |
| BUG-73 `raise error;` in main flow → CE0710 | **STILL OPEN** | yes |
| BUG-86 nanoflow write barrier: `currentDeviceType()` | **STILL OPEN** | yes |
| BUG-70/95 `show_page` args on a page-level button | **STILL OPEN** | yes |
| BUG-84 `SET DataSource = DATABASE` on a DataView wipes it | **STILL OPEN** | yes |
| BUG-67 snippet primitive param `{ $X: String }` | **STILL OPEN** | n/a (exec error) |
| BUG-63 write-lint-rules skill fictional API values | **STILL OPEN** | n/a (inspection + live catalog query) |
| BUG-87 DESCRIBE JAVA ACTION drops type-param name | **STILL OPEN** | n/a (describe: `entity <>`) |

### Round B — the "not retested this round" list from the v0.20.0 file, plus the pre-v0.17 backlog

| Bug | Verdict | Fixed in / reason | Build-verified |
|---|---|---|---|
| BUG-94 `hasRole('Module.Role')` invalid function | **STILL OPEN** | — | yes |
| BUG-17 `[%BeginOfToday%]`/`[%EndOfToday%]` tokens quoted in XPath | **STILL OPEN** | — DESCRIBE round-trips unquoted, native mxbuild still CE0161 | yes |
| BUG-23 `ContentParams` with `$currentObject/` prefix | **FIXED** | v0.21.0 (changelog: "MDL-WIDGET14 claimed Mendix forbids an expression parameter. It does not" — the whole WIDGET14/WIDGET24 refusal area) | n/a (now refused at check time, MDL-WIDGET14/24) |
| BUG-15 `retrieve $X from $ObjVar/Module.AssocName limit 1` | **NOT REPRODUCED** | — no changelog line found | yes — 0 errors |
| BUG-68 snippet datagrid columns on system/generalized attrs | **NOT REPRODUCED** | — no changelog line found; both `autocreateddate` and `EXTENDS System.FileDocument`-inherited shapes build clean | yes — 0 errors |
| BUG-77 quoted attr segments (`$Var/"Attr"`) in create/change | **NOT REPRODUCED** | — no changelog line found; plain CHANGE and FileDocument-extends CREATE both clean | yes — 0 errors |
| marketplace install collapses split-model project | **NOT RETESTED** | already independently reconfirmed **FIXED** on v0.21.0 by a separate real-project probe dated 2026-09-10, documented in-ledger with full before/after numbers; this container has no marketplace auth to reprobe independently | n/a |
| BUG-93 ALTER PAGE REPLACE customContent column drops dropdownfilter | **NOT RETESTED** | current `mxcli syntax page` no longer documents `ShowContentAs: customContent` as an explicit property (DATAGRID now routes through the DataGrid2 pluggable engine per the v0.21.0 changelog's "DataGrid construction unified" note); a control probe (FILTER block on a **plain**, non-customContent column) also silently dropped the whole FILTER on CREATE, which does not match the original bug's own control (plain columns' filters round-tripped fine) — insufficient certainty this round's probe exercises the same code path as the original v1-DATAGRID-shaped repro | — |
| BUG-92 ALTER PAGE INSERT wrong-anchor no-op / orphaned duplicates | **NOT RETESTED** | multi-trap repro (customContent-column anchor + 5 retry sequence) needs more fixture-building time than this round had | — |
| BUG-96 cross-module ALTER PAGE INSERT into DataGrid2 | **NOT RETESTED** | needs a second module + cross-module column insert fixture | — |
| BUG-14 ALTER PAGE DROP+INSERT BEFORE with MICROFLOW action corrupts BSON | **NOT RETESTED** | pre-v0.13.0 vintage; needs the specific DROP+INSERT-BEFORE sequence fixture | — |
| BUG-16 DataGrid 2 customContent columns corrupt pluggable widget BSON | **NOT RETESTED** | pre-v0.13.0 vintage; overlaps BUG-93's grammar-shape uncertainty above | — |
| BUG-18 `visible: [expr]` on CONTAINER in customContent column corrupts MPR | **NOT RETESTED** | pre-v0.13.0 vintage; needs a customContent-column-with-visible-container fixture | — |
| BUG-25 CREATE WORKFLOW writes null ContentsBlob, SQLite InvalidCastException | **NOT RETESTED** | needs direct SQLite/BSON unit inspection, not just `check`/`exec`/`docker check` | — |
| BUG-WF01 ANNOTATION in workflow body → BSON constructor crash | **NOT RETESTED** | needs the specific workflow-ANNOTATION shape; time did not allow | — |

### Round C — entries carrying no v0.18/v0.20 verdict at all (25-candidate cap; 11 attempted, highest-value first)

| Bug | Verdict | Fixed in / reason | Build-verified |
|---|---|---|---|
| BUG-107 unquoted value in workflow `CALL MICROFLOW WITH(...)` segfaults | **STILL OPEN — CRASH** | — SIGSEGV reproduced byte-for-byte at the same source line (`visitor_workflow.go:565`) | n/a (crashes before any write) |
| BUG-98 `calculated by` silently dropped at write time | **FIXED** | ≤v0.21.0 (own probe: DESCRIBE round-trips `calculated by`, `SHOW CALLERS OF` shows the wiring, native mxbuild 0 errors — no changelog line found) | yes — 0 errors |
| BUG-103 DESCRIBE MICROFLOW doubled-quote log strings rejected by check | **FIXED** | v0.21.0 (changelog: "mxcli check no longer rejects Mendix's own apostrophe escape") | n/a (full describe→check round-trip now clean) |
| BUG-104 quoted `"$Name"` microflow param keeps `$` in the stored name | **STILL OPEN** | — DESCRIBE shows `$$Stub`, body reference resolves wrong, CE0109 at native mxbuild | yes |
| BUG-124 DESCRIBE MICROFLOW omits `without events` | **FIXED** | ≤v0.21.0 (own probe: DESCRIBE now correctly emits `commit $Obj without events;` — no changelog line found) | n/a (describe round-trip) |
| BUG-125 `check --references` cannot resolve any enumeration in an attribute decl | **NOT REPRODUCED** | — no changelog line found; both CREATE-time and the original's exact ALTER ENTITY ADD ATTRIBUTE form pass `--references` clean | n/a |
| BUG-126 `ALTER PAGE … SET Label` reports success, discards the value | **STILL OPEN** | — "Altered page" printed, DESCRIBE shows the old Label unchanged | n/a (describe read-back) |
| BUG-128 `CREATE MODULE ROLE` not idempotent, aborts script silently | **STILL OPEN** | — re-run fails identically (`module role already exists`), no `IF NOT EXISTS`/`OR MODIFY` form exists, and a later statement in the same script is confirmed never applied | n/a |
| BUG-117 widget-property writer silently drops unsupported property names | **STILL OPEN (narrowed)** | — v0.21.0 changelog fixed only the two named properties (`editable`, `contentparams` — MDL-WIDGET20/21); the general case is unfixed: LISTVIEW's undocumented `Pagination`/`PagingPosition` are still silently dropped with no MDL-WIDGET07 warning, only `PageSize` (a real LISTVIEW property) survives | n/a (describe read-back) |
| BUG-122 `ALTER PAGE … SET PageSize` rejected on a DataGrid 2 that CREATE accepts | **STILL OPEN** | — identical error (`pluggable property "PageSize" not found`) | n/a (exec error) |
| BUG-102 `ALTER PAGE … SET DataSource = DATABASE FROM … WHERE […] SORT BY …` no-ops on a native DataGrid | **NOT RETESTED** | current `mxcli syntax page.alter` documents only `SET DataSource = $Param` (variable form) — no `DATABASE FROM … WHERE … SORT BY` form is in the syntax reference at all, and DATAGRID now routes through the DataGrid2 engine (same v0.21.0 changelog note as BUG-93); unclear whether the original repro shape is still constructible without deeper investigation than this round had time for | — |

**Skipped this round for the next one** (no verdict yet, listed so the next retest starts here
rather than re-picking at random): BUG-99, BUG-100 (toolkit/Docker-Compose naming, not mxcli),
BUG-101 (blocked — `add_repo` denied on the upstream repo, not retestable from here), BUG-105,
BUG-106, BUG-108 (superseded by BUG-76, no separate filing needed), BUG-109, BUG-110, BUG-111,
BUG-112, BUG-113, BUG-114, BUG-115, BUG-116 (deploy-API docs gap, not a probe), BUG-118, BUG-119,
BUG-120, BUG-121, BUG-123, BUG-127, BUG-129, BUG-130/131 (toolkit `exec.sh`, not mxcli), BUG-132,
BUG-133, BUG-140.

## Notes per verdict

### Round A — every STILL OPEN entry reproduced with the same signature as v0.20.0

No Round A entry moved. Each was re-probed from a fresh scratch app rather than trusted from the
v0.20.0 write-up:

- **BUG-76**: `CREATE WORKFLOW … DECISION '1 = 1' OUTCOMES 'OutcomeA' -> {} 'OutcomeB' -> {};`
  execs clean ("Created workflow"), then native `mx check` throws
  `Mendix.Modeler.Storage.StorageLoadException` — *"The text 'OutcomeA' is not a valid
  EnumerationValueIdentifier"*, one line per outcome, project unloadable. Byte-exact match to the
  v0.20.0 finding.
- **BUG-73**: a microflow whose entire body is `RAISE ERROR;` passes `mxcli check`/`exec` and
  fails native mxbuild with `[CE0710] "The main flow cannot join an error flow or end in an error
  event."` — same signature.
- **BUG-86**: `check` still does not lint a `CREATE NANOFLOW` using `currentDeviceType()` (no
  MDL044 warning fires outside microflows); `exec` writes it; native mxbuild fails
  `[CE0117] "Error(s) in expression."` at the Create-variable activity.
- **BUG-70/95**: a page-level `ACTIONBUTTON` (no enclosing data widget) with
  `Action: SHOW_PAGE Detail(Item: $SomeRef)`, `$SomeRef` a page **Variable**, execs and checks
  clean; `DESCRIBE PAGE` shows the argument silently rebound to `$currentObject`; native mxbuild:
  `[CE1571] "No argument has been selected for parameter 'Item'…"`. `mxcli syntax page`'s own
  MDL-PAGEARG01 note ("naming any other variable is refused") does not fire for this page-level,
  no-enclosing-widget shape.
- **BUG-84**: `ALTER PAGE … { SET DataSource = DATABASE Retest.Customer ON dvCust; }` on an
  existing param-bound DataView reports `Altered page`; DESCRIBE shows the DataSource gone
  entirely (`dataview dvCust { … }`, no DataSource clause); native mxbuild:
  `[CE7007] "Selected value is not valid for entity 'Customer'."`
- **BUG-67**: `CREATE SNIPPET … (Params: { $Label: String })` — still `mxcli syntax
  snippet.create`'s own documented example — passes `check`, fails `exec`:
  `Error: failed to build snippet: failed to resolve entity String: entity not found: String`.
- **BUG-63**: the shipped `write-lint-rules/SKILL.md` (line 318) still lists `action_type`
  examples (`CreateChangeAction`, `CommitAction`, `ShowFormAction`) that a live `SELECT DISTINCT
  ActionType FROM CATALOG.ACTIVITIES`-style query never returns, and line 364 still gives
  `source_type` as lowercase (`"microflow"`, `"page"`); a live `SELECT DISTINCT SourceType FROM
  CATALOG.REFS` on the scaffolded app returns the real, uppercase values
  (`ASSOCIATION/ENTITY/MICROFLOW/NANOFLOW/NAVIGATION/PAGE/SNIPPET`).
- **BUG-87**: `CREATE JAVA ACTION … (ContextObject: ENTITY <pEntity> NOT NULL) …` describes back
  as `ContextObject: entity <> not null` — the type-parameter name `pEntity` is still dropped.

### BUG-23 — reclassified FIXED, same pattern as v0.20.0's BUG-79 "better refusal"

Both confirmed-failing forms from the original finding (`toString($currentObject/State)` and the
bare `$currentObject/CreatedOn`) are now **refused at `mxcli check` time** with a named,
actionable diagnostic (`MDL-WIDGET14`/`MDL-WIDGET24`) rather than silently accepted and only
failing at a real compile. This matches the v0.21.0 changelog's own "Checks that were wrong about
Mendix" section: *"MDL-WIDGET14 claimed Mendix forbids an expression parameter. It does not."*
The silent-corruption trap this entry named is gone; nothing was probed that still slips through
uncaught.

### BUG-98 — calculated-by wiring now verifiably real, not just describe-cosmetic

`ALTER ENTITY … ADD ATTRIBUTE "DoubledBase": Integer CALCULATED BY Retest.CALC_Double;` against a
correctly-signed calc microflow: `exec` succeeds, `DESCRIBE ENTITY` round-trips the `calculated
by` clause, native mxbuild reports 0 errors, and — the check the original finding specifically
named as unreliable — `SHOW CALLERS OF Retest.CALC_Double` now reports **1 caller**
(`Retest.CalcHolder`), proving the microflow is genuinely wired into the entity rather than just
echoed back by `DESCRIBE`. No v0.21.0 changelog line names this fix explicitly; verdict rests on
this round's own probe.

### BUG-103 — exact changelog match

The original repro (`log warning node '…' '…''Graph Agent''…';` from `DESCRIBE MICROFLOW`, fed
straight back into `mxcli check`) now passes end to end. The v0.21.0 changelog names the root
cause verbatim: *"an expression containing '', which is how the Mendix expression language
escapes an apostrophe inside a string literal, was reported as 'Unexpected token after
expression'… It reproduced only with `-p`"* — matching this bug's own note that the failure needs
a live project (`mxcli check script.mdl -p Project.mpr`).

### BUG-107 — still crashes, and the fix is visibly in flight but not released

`CREATE WORKFLOW … CALL MICROFLOW Retest.ACT_Noop WITH (Ctx = $WorkflowContext);` (unquoted left
and right sides — the spelling the tool's own MDL-PAGEARG01-style unmapped-parameter hint talks
an author into) still panics `mxcli check` with the identical SIGSEGV at
`mdl/visitor/visitor_workflow.go:565`, `buildWorkflowCallMicroflow`. The mxcli source clone used
for this build was sitting on a branch named `fix/workflow-with-unquoted-value-segfault` before
checkout — direct evidence a fix for this exact defect is in progress upstream — but that branch
is not part of the tagged v0.21.0 release under test, and the crash is confirmed against the
actual release binary, not the in-progress fix.

### BUG-117 — the changelog fix is real but narrower than the bug's own claim

v0.21.0 explicitly fixed two named properties silently dropped on the wrong widget type
(`editable`, `contentparams` — MDL-WIDGET20/MDL-WIDGET21) and diagnosed the shared root cause
(`isBuiltinPropName` is one flat, widget-agnostic list). It did not generalize the fix: this
round's LISTVIEW probe (`PageSize: 1, Pagination: buttons, PagingPosition: bottom`) still drops
`Pagination` and `PagingPosition` silently — `DESCRIBE PAGE` shows only `PageSize` (a property
LISTVIEW genuinely has) surviving, with no MDL-WIDGET07 warning at check time. The ledger's own
upstream note ("file it citing #928 as the acknowledged root cause") called this outcome in
advance.

### BUG-125 / BUG-15 / BUG-68 / BUG-77 — four NOT REPRODUCED verdicts, no changelog line to explain any of them

All four probes were built from the original bug's own exact repro shape (not a simplified
approximation) and passed both `check --references` and native mxbuild at 0 errors:

- BUG-125: `ALTER ENTITY … ADD ATTRIBUTE IF NOT EXISTS "K2": Enumeration(Retest.Kind);` against an
  enum created in an earlier, separate script (not in the same statement batch) — clean.
- BUG-15: `RETRIEVE $Result FROM $Detail/Retest.Detail_Order LIMIT 1;` (association-path retrieve
  from an object variable) — clean, 0 errors.
- BUG-68: both failing shapes (a snippet datagrid column bound to an `autocreateddate` system
  attribute, and one bound to an attribute inherited via `EXTENDS System.FileDocument`) — both
  clean, 0 errors.
- BUG-77: both a plain `CHANGE $Dst ("Name" = $Src/"Name")` and a `CREATE` on an entity extending
  `System.FileDocument` with a quoted attribute segment — both clean, 0 errors, and `DESCRIBE`
  shows the quotes correctly stripped (`change $Dst (Name = $Src/Name);`).

None of these fixes are named in the v0.21.0 changelog, so — per this round's own vocabulary —
they are NOT REPRODUCED rather than confirmed FIXED. Treat them the same way the v0.20.0 archive
treated BUG-81/BUG-97: moved out of the open ledger, but flagged in the archive file as resting on
a blank-app probe, not a bisected fix.

### BUG-93 / BUG-102 — grammar-shape uncertainty, not a clean probe

Both entries assume a native/v1-style `DATAGRID` shape (`ShowContentAs: customContent`, a
`WHERE […] SORT BY …` clause on `ALTER PAGE SET DataSource`) that no longer appears in
`mxcli syntax page`'s reference text; the v0.21.0 changelog's "DataGrid construction unified on
the pluggable widget engine" entry says the `datagrid` keyword now always routes through the same
DataGrid2 engine. A control probe built for BUG-93 (a `FILTER` block on a plain, non-customContent
column, which the original bug's own text says round-trips fine) also silently dropped the entire
`FILTER` block on `CREATE PAGE` in this round — inconsistent with the original bug's own control,
which means this round's probe likely is not exercising the same code path the bug names. Both are
left NOT RETESTED rather than reported as NOT REPRODUCED off an uncertain probe.
