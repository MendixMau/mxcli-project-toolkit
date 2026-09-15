**From:** approval-app-main
**Date:** 2026-09-14
**Kind:** bug
**Field evidence:** bug-log entries in approval-app-main not found (by heading) in bug-logs/mxcli-bugs.md — verify each against the toolkit log before filing; heading match is a heuristic
**Proposed target:** see per-item notes below

---

## [candidate — from bug-logs/mxcli-bugs.md] Confirmed tool defects

### 1. `project-bin/exec.sh` — mxbuild auto-detection assumes a macOS Studio Pro install
**Found:** 2026-08-19, executing `hotfix-grid-blank-attributes.mdl`.
`exec.sh`'s post-write gate tries to auto-locate `mxbuild`/`java` and fails on this Linux sandbox
with `ERROR: no 'Mendix Studio Pro *.app' in /Applications` / `mxbuild or java not found — GATE
SKIPPED`, even though a working `mxbuild` is sitting right at
`~/.mxcli/mxbuild/{version}/modeler/mx` (the same path `CLAUDE.md`'s own quick-start section
documents). The gate silently downgrades to skipped instead of finding it.
**Impact:** every `exec.sh` run on this project's sandbox has been executing MDL against the live
`.mpr` with **no automatic build gate** — the operator has to remember to run
`~/.mxcli/mxbuild/*/modeler/mx check <project>.mpr` by hand afterward every time. This happened
again this session (the grid-blank-attributes fix) and was caught only because it was checked
manually.
**Suggested fix:** before falling back to the macOS-app-bundle lookup, check
`~/.mxcli/mxbuild/*/modeler/mx` (mxcli's own cache convention, already documented in
`CLAUDE.md`) and `$MXTK_ROOT`/project-local install paths. Treat "gate skipped" as a loud warning
requiring an explicit `--allow-unverified` flag, not a silent default.

### 2. `project-bin/test-stack-up.sh` — false negative on mxcli-local (non-docker) ownership
**Found:** repeatedly this session (every e2e/journey/monkey/verify-module invocation).
Its app-ownership auto-detection does not recognize an app started via `./mxcli run --local`
(this project's actual run mode) as "owned" by the current session, and refuses with "REFUSING TO
RUN — app ownership is unverified" unless `ALLOW_UNVERIFIED_APP=1` is passed.
**Impact:** every single e2e script invocation and every `bin/verify-module.sh` run needs the env
var bolted on, every time, forever, on this project. Not a one-off — it's load-bearing tribal
knowledge that isn't written down anywhere in the toolkit itself.
**Suggested fix:** either teach the detector to recognize the mxcli-local run mode (check for the
`runtimelauncher.jar` process + the port mxcli itself just published, same signal
`test-stack-up.sh --check` already resolves), or make `ALLOW_UNVERIFIED_APP=1` a project-level
config default (e.g. read from `.mxcli` config) instead of an every-invocation env var.

### 3. `project-bin/graph-sweep.sh` — GNU `stat` silently returns garbage instead of erroring
**Found:** 2026-08-19.
The BSD mtime-format branch (`stat -f "%Sm" -t ... || stat -c ...`) assumes `stat -f` either
succeeds with a BSD-style timestamp or fails outright so the `stat -c` GNU fallback fires. On
Linux, GNU `stat -f` doesn't fail — it interprets `-f`/`-t` as *filesystem-info* flags and prints
plausible-looking garbage, so the fallback never triggers and every run FAULTs as "catalog is
stale" even when it's fresh.
**Status:** patched locally in this project's copy — try `stat -c` (GNU/Linux) first, `stat -f`
(BSD/macOS) only as fallback. **Not yet reported/merged upstream.** Whoever picks this up should
just swap the try-order in the toolkit source and re-`sync-project.sh` this project to drop the
local patch.

### 4. `project-tests/e2e/design-audit.js` — always exits 0, can't be gated on
**Found:** 2026-08-20, while scoping out wiring this into `verify-module.sh`.
`main()` writes its JSON report and prints a console summary but never calls `process.exit()`
based on the `fail`/`fault` tally — it only exits non-zero (`1`) if the whole script crashes. A
run with real findings recorded in the JSON still exits `0`.
**Impact:** this is exactly the kind of instrument `verify-module.sh`'s own header warns about
("a suite that reports clean because half of it never executed is the exact false green the loop
exists to retire") — except here it's not a skip, it's a *finding that ran and still reports
green* if you gate on exit code alone, which is how every other instrument in the chain is gated
(`run()`'s `kind=gate` maps `rc=0→PASS`).
**Suggested fix:** exit 1 when `tally.fail > 0`, exit 2 when `tally.fault > 0` (fault takes
precedence — matches the FAULT≠FAILED distinction the rest of the harness already enforces), exit
0 only when everything is clean. This one change is the actual blocker for wiring `design-audit.js`
into `verify-module.sh` as a real gated rung instead of a manual side-script.

### 5. `project-tests/e2e/design-audit.js` — single shared default output path, not module-scoped
**Found:** 2026-08-20, same investigation as #4.
No `--out` defaults to the same `tests/e2e/artifacts/design-audit.json` every time, and its page
list is read from one fixed `.claude/loop/page-scope.json`, not a `--module` argument. Two
sequential (or worse, concurrent) invocations for different modules clobber each other's output
unless the caller remembers `--out` and manually curates `page-scope.json` per run.
**Suggested fix:** accept a `--module <Name>` flag that (a) auto-derives the output path as
`tests/e2e/artifacts/design-audit-<Module>.json` when `--out` is omitted, and (b) filters
`page-scope.json`'s page list to that module instead of requiring the caller to hand-edit the
scope file. This is what would make #4 + #5 together safe to wire into a per-module loop.

### 5b. `format (dateFormat: ...)` is silently inert on a page-parameter path (2026-08-28)

`ALTER PAGE ... REPLACE` a dynamic text whose ContentParams bind a **page-parameter path**
and give it a date format:

```
ContentParams: [{1} = $ApprovalRun.StartedOn format (dateFormat: Custom, customDateFormat: 'dd-MM-yyyy')]
```

`mxcli check --references` passes, `exec` reports "Altered page", `DESCRIBE PAGE` reads the
format back verbatim, and mxbuild reports 0 errors — and the running page renders the locale
default (`8/20/2026, 12:11 AM`). The format is accepted and stored but never reaches the
runtime. The identical clause on a **bare attribute** (`{1} = StartMonth format (...)`) works:
verified live as `01-2026`.

**Workaround:** put the object in context with a `dataview` on the parameter so the attribute
binds bare. Verified live afterwards as `20-08-2026` (`mdlsource/40-task-page-ux/14-*.mdl`).

**Why this one matters beyond dates:** DESCRIBE reading your own input back is the trap. Four
independent signals agreed the change had landed and all four were wrong; only the rendered
page disagreed. Cf. `tool-output-is-not-ground-truth.md`.

### 5c. `ALTER PAGE ... SET` accepts properties the widget does not have (2026-08-28)

`mxcli check --references` passes `set Zzz = 'x' on dgMine.StartedOn` — a property that
exists nowhere. SET is not validated against the widget's real property set at check time;
only `exec` reports `column property "Zzz" not found`. A clean `check` on an ALTER PAGE SET
script therefore carries almost no information. Related: when a SET names an ambiguous
widget, the ambiguity error fires *before* the property lookup, so "ambiguous column" can
look like evidence that the property is valid. It is not — disambiguate, re-run, and only
then believe the property exists.

Concretely, none of these are settable from MDL (all proven by exec, all passing `check`):
date format on a DataGrid2 attribute column, date format on a DATEPICKER, and
`alter settings language DefaultLanguageCode` to a language the project does not already
have. There is no project-level date format in MDL at all.

---

### 5d. A `parallel split` is written to the `.mpr` but dropped from the deployed model (2026-08-29)

`Approval.ApprovalWorkflow` defines a parallel split after WFST060 with three paths, one
user task each (WFST070/080/090, the delegated sub-reviews).

* `DESCRIBE WORKFLOW Approval.ApprovalWorkflow` reads the split back in full: `parallel split
  -- Parallel split`, three `path N { user task WFST0N0 ... }` blocks, each with `Complete`
  and `Not relevant` outcomes.
* `mxbuild` reports **0 errors** on the model.
* The deployed model contains no trace of it:

```
select count(*) from "system$workflowsubprocessdefinition";   -> 0
select name from "system$workflowusertaskdefinition";         -> 12 rows, WFST070/080/090 absent
```

* At runtime the chain goes WFST060 -> WFST100 directly. Across the entire database history
  (7 completed runs) `system$workflowendedusertask` has **zero** rows for those three stations,
  and `system$workflowsubprocess` has zero rows overall.

So the split round-trips through `DESCRIBE`, passes the model check, and then does not exist.
Nothing in the toolchain reports it — the only way to see it is to complete a run and notice
three stations never appeared.

**Detection:** after building any workflow with a parallel split, count
`system$workflowusertaskdefinition` against the number of `user task` statements in the script.
A mismatch is this defect. `mxbuild` clean is not evidence.

**Workaround until fixed:** model the branch as sequential user tasks, or build the split in
Studio Pro.

### 5e. `mxcli run --local` never builds `deployment/web/dist`, so the app serves a blank page (2026-08-29)

`deployment/web/index.html` loads `dist/index.js?<hash>`. `rollup.config.mjs` (which mxbuild
writes into `deployment/web/`) begins with `del({ targets: "dist", runOnce: true })`. `mxcli run
--local` deploys the model and starts the runtime but never runs the rollup bundling step, so
after every start the directory is simply absent.

Symptom, and why it is easy to misdiagnose: the app answers **HTTP 200** on `/`, `curl
/mxclientsystem/mxui/mxui.js` also answers 200, the runtime log says "Mendix Runtime successfully
started" — and the browser shows an empty white page with `document.title === "Mendix"`. The only
signal is one line in the runtime log:

```
ERROR - Connector: 404 - file not found for file: dist%2Findex.js
```

Every Playwright helper then fails with "login form did not render", which reads like a test-harness
fault rather than a deploy fault.

**Fix / workaround:** `bin/bundle-web.sh` (added this session) runs rollup against the config
mxbuild already wrote. Run it after every `mxcli run --local` and after any exec + restart, before
pointing a browser or a test at the app.

### #5f — `alter page { set label = ... }` on an input widget is a silent no-op

`set label = 'New label' on txtSomeTextbox` is documented as supported in
`.ai-context/skills/alter-page.md` (property table, row `label`, applying to
TEXTBOX / TEXTAREA / DATEPICKER / COMBOBOX / CHECKBOX / RADIOBUTTONS). mxcli
accepts it, prints `Altered page <Page>`, exits 0, and the label is unchanged.
Both `set Label = ...` and `set label = ...` behave this way.

The same statement with `Caption` at least fails honestly:
`failed to set Caption on txtSamplingPhase010b: widget has no Caption property`.
So the setter knows how to reject an unknown property — `label` is reaching a
handler that does nothing.

Detection: `mxcli check` says nothing useful here (it does not validate
property names against the widget's real property set), and exec's success
line is not evidence. `DESCRIBE PAGE` after the exec is the only check.

Workaround: `replace <widget> with { <widget re-stated with the new label> }`.
Re-using the same widget name is safe — REPLACE removes the old widget first,
so CE0495 does not fire — and sibling widgets in the same container survive.

Found 2026-08-31 while putting required markers on the three station fields
that script 46/01 made mandatory.

### 5g. ALTER PAGE INSERT/REPLACE cannot bind ContentParams — every parameter comes out empty (CE0402)

A `dynamictext` added through `alter page { insert after ... }` or
`{ replace ... with ... }` gets its `Content` template but NOT its
`ContentParams`. mxbuild then fails with

    CE0402 No value specified.
      Page 'X' | Value of text template parameter {1} of text 'txtY'

one error per parameter. The same widget written inside a
`create or modify page` binds correctly, so the defect is in the ALTER path,
not the parser.

Reproduced four ways, all identical:

    -- inside a listview, bare attribute
    insert after txtStation { dynamictext t (Content: 'x{1}', ContentParams: [{1} = DurationMinutes]) }
    -- inside a listview, explicitly rooted
    insert after txtStation { dynamictext t (Content: 'x{1}', ContentParams: [{1} = $currentObject/DurationMinutes]) }
    -- inside a datagrid custom-content column, rooted
    insert after txtStatus  { dynamictext t (Content: 'y{1}', ContentParams: [{1} = $currentObject/RunStatus]) }
    -- and the same three as `replace <name> with { ... }`

Detection: `mxcli check --references` passes clean — it validates that the
attribute exists, not that the binding survived the write. Only mxbuild
catches it, which on this project means `bin/exec.sh` execs, fails the gate,
and auto-restores the snapshot. Nothing is lost, but the script is dead.

Workaround: write the page as a full `create or modify page`. Round-tripping
through `DESCRIBE PAGE` is safe only when the page has no microflow datasource
arguments and no snippet-parameter dataviews, both of which DESCRIBE drops
(see the DESCRIBE lossiness note above) — check the describe output against
the page before trusting it.

Found 2026-08-31 while splitting the Approval evaluation station pill so a
station that has not run yet reads "pending" instead of ": min".

### 5h. `sort by <attr> desc` on a datagrid datasource is written as ascending

A `datagrid` whose datasource is declared

    database from ProductNumberWorkflow.WorkflowRun sort by RunStatus desc

renders ascending. The proof is not in the model — `DESCRIBE PAGE` faithfully
reads back `desc`, and `mxcli check --references` passes clean — it is in the
rendered DOM: the Status column header carries `aria-sort="ascending"`, and the
row order is byte-for-byte identical to the same page built with `asc`.

So only ascending is actually reachable through the datasource declaration.
There is no MDL-side workaround; a descending default has to be modelled some
other way (a sortable helper attribute whose ascending order is the order you
want) or set in Studio Pro.

Detection: read `aria-sort` off the rendered header, or compare the row order
of an `asc` build and a `desc` build of the same page. Trusting `DESCRIBE PAGE`
here ships the wrong sort silently.

Found 2026-08-31 while trying to put in-progress runs above archived ones on
`ProductNumberWorkflow_Overview`.

### 5i. `ALTER PAGE … REPLACE <datagrid column> WITH { column … }` corrupts the .mpr

Replacing a DataGrid2 column through `ALTER PAGE` writes a `DivContainer` into
the grid's column list, where the schema requires a `WidgetObject`. The file is
then unreadable: mxbuild aborts before any CE check with

    System.InvalidCastException: Unable to cast object of type
    'Mendix.Modeler.WebUI.Forms.Widgets.LayoutWidgets.DivContainers.DivContainer'
    to type 'Mendix.Modeler.WebUI.Forms.Widgets.CustomWidgets.WidgetObject'

This is not a CE error and it is not caught upstream. `mxcli check` reports
`✓ Syntax OK`, `--references` reports `✓ All references valid`, and the exec
itself reports success. The corruption only surfaces when something tries to
*read* the result — and because mxbuild fails to run rather than failing a
check, `bin/exec.sh` lands in its "gate could not run" branch, which preserves
the snapshot but does **not** auto-restore. The working copy is left with a
broken model that mxcli can still read. Run `./bin/restore-mpr.sh`.

Isolated 2026-08-31 by elimination, three statements run separately against a
restored model:

| statement | result |
|---|---|
| `set Visible = […] on <dynamictext>` (station page) | clean |
| `replace <dynamictext> with { dynamictext, dynamictext }` (archive detail) | clean |
| `replace <column> with { column }` (overview grid) | **corrupt** |

So `REPLACE` is fine on ordinary widgets. It is columns specifically — the same
class of problem as 5g, where `ALTER PAGE` cannot bind `ContentParams`: the
ALTER path builds a generic container and the grid-column schema will not take
one.

Workaround, and the one used: round-trip the whole page. `DESCRIBE PAGE` the
grid, edit the column line in the text, and re-apply as a full
`create or modify page`. That path handles columns correctly. Only safe on a
page whose `DESCRIBE` is lossless — no microflow-datasource arguments and no
snippet-call parameters (see the note on lossy DESCRIBE above).

### BUG-108. `mxcli run --local` on macOS points you at a flag that does not exist (2026-09-03)

`mxcli run --local` refuses to boot on an Apple-silicon Mac, because `mxcli setup mxbuild` caches
the **Linux** mxbuild the Mendix CDN publishes:

```
Error: starting mxbuild serve: mxbuild at ~/.mxcli/mxbuild/11.13.0/modeler/mxbuild
  is a linux binary and cannot run on darwin
  ... Install Mendix Studio Pro for this project's Mendix version, or pass --mxbuild-path
  pointing at its bundled mxbuild.
```

Studio Pro **was** installed at the exact matching version. So the second half of the advice is
the one to follow — except:

```
$ ./mxcli run --local -p App.mpr --mxbuild-path "/Applications/Mendix Studio Pro 11.13.0 Beta.app/Contents/modeler/mxbuild"
unknown flag: --mxbuild-path
```

**`--mxbuild-path` is not a flag on any mxcli command.** `mxcli run --help` lists 30-odd flags and
none is it. `strings` on the binary shows why: the real thing is a *library* field —
`"mxbuild not found; run 'mxcli setup mxbuild -p <app.mpr>' or pass ServeOptions.MxBuildPath"` —
and the user-facing error prose was written as if that Go struct field were a CLI flag. The
message is a dead end in both directions: the first suggestion is already satisfied, and the
second cannot be typed.

**Workaround (what actually booted this project).** The cache layout under
`~/.mxcli/mxbuild/<version>/` is `modeler/` + `runtime/`, and Studio Pro's `.app/Contents/` has
those same two directories. So point the cache at Studio Pro and leave mxcli none the wiser:

```bash
SP="/Applications/Mendix Studio Pro 11.13.0 Beta.app/Contents"
C=~/.mxcli/mxbuild/11.13.0
mv "$C" "$C.linux-bak"          # reversible; keeps the Linux copy for devcontainer use
mkdir -p "$C"
ln -s "$SP/modeler" "$C/modeler"
ln -s "$SP/runtime" "$C/runtime"
```

Then boot with a **JDK 21** `JAVA_HOME` — Mendix 11.13 requires 21, and this machine's default is
25, which the runtime rejects:

```bash
JAVA_HOME=$(/usr/libexec/java_home -v 21) ./mxcli run --local -p App.mpr --db-name approval_app
```

Cold boot ~70s (24s of that is the web-client bundle), then `http://127.0.0.1:8080/`.

Two cautions. Use the **exact** Studio Pro version — symlinking a newer modeler (11.14 is also
installed here) is how an `.mpr` gets silently upgraded. And this is a symlink into an
application bundle, so it breaks when that Studio Pro is updated or removed; the `.linux-bak`
directory is kept precisely so the devcontainer path can be restored with an `mv` back.

**Fix worth filing upstream:** either add the `--mxbuild-path` flag the error already documents,
or have `setup mxbuild` detect a matching local Studio Pro on darwin and cache-link it itself —
it has the version in hand and the layouts already match.


### 1b. `bin/_common.sh` `find_mxbuild` returns the NEWEST Studio Pro, not the project's — and the gate then passes a failing model (2026-09-03)

**Fixed in this repo the same day; recorded because the failure mode is silent and expensive.**

`find_sp_app()` returns the newest installed Studio Pro. Its comment shows the author thinking
carefully about *sort order* — `sort -V` so 11.13 outranks 11.9 — and not at all about *version
matching*. `find_mxbuild()` then builds the path from it. With 11.12.x, 11.13.0 and 11.14.0 all
installed and an **11.13.0** project, the gate ran **11.14.0's** mxbuild.

What that cost, concretely. Script `76` renamed five attributes. mxcli rewrote stored references
and left microflow expression text alone, exactly as it warned. `exec.sh` then reported:

```
→ Running mxbuild model check (catches BSON corruption before SP opens)...
  (mxbuild: /Applications/Mendix Studio Pro 11.14.0 Beta.app/Contents/modeler/mxbuild)
  ✓ mxbuild: 0 errors — model is clean.
```

The project's own 11.13.0 mxbuild, on the same `.mpr`, seconds later:

```
BUILD FAILED
```

**9 errors** — CE0117 ×3 in `VAL_ApprovalStationData_WFST010`, CE0117 ×4 in
`ACT_ApprovalRun_CreateVersion`, CE0161 ×2 in the two `SUB_MandatoryFieldRule_*` XPaths. Four
microflows with dangling attribute references, waved through as clean.

This is a **false pass**, not a marginal disagreement, and it is the worst possible shape for a
gate defect: it is silent, it looks like success, and the next script in the build loop lands on
top of a model nobody knows is broken. The guard chain's whole purpose — *catch it before Studio
Pro opens* — inverts.

**Fix applied.** `project_mendix_version()` reads the version straight out of the `.mpr` (it is
SQLite; `select * from _metadata`, with a `strings` fallback), and `find_mxbuild()` prefers the
Studio Pro whose version matches exactly. When there is no exact match it still falls back to the
newest — but says so, loudly, on stderr, naming the risk. `MXBUILD_PATH` still overrides.

**Worth checking in any project that copies this bin/.** The bug is invisible while only one
Studio Pro is installed, and appears the day a second one is. Nothing about the output changes
except a version number in a parenthetical nobody reads.



## [candidate — from bug-logs/toolkit-bugs.md] source-ledger.sh name-verification produces FALSE FAULTS on non-ASCII filenames

**Found** 2026-09-02, approval-app-main, toolkit branch `claude/approval-app-intake-gates-ngy1w3` @ `1f654f7`.
**Severity: material on this corpus** — every DafNe/CCS source filename with an umlaut is affected,
and the whole corpus is German.

`bin/source-ledger.sh check` reports

```
FAULT  Form_CCS-Artikel-Entfall-Übersicht.cls
       — artifact analysis/knowledge-base/KB_CCS-05_ArticleDiscontinuation.md never names it
```

but the artifact **does** name it, byte-identically:

```
filename : 2d45 6e74 6661 6c6c 2dc3 9c62 6572 7369   -Entfall-..bersi
in KB doc: 2d45 6e74 6661 6c6c 2dc3 9c62 6572 7369   -Entfall-..bersi
```

Both are NFC (`c3 9c` = U+00DC), so this is **not** an HFS+ NFD-vs-NFC normalisation issue.
Reproduced with a single direct `mark` (not via a shell loop), so it is not caller quoting.

**Blast radius, measured twice.** First pass: 7 of 8 reported faults false, all 7 with umlauts.
Second pass after dispositioning the full corpus: **19 faults, of which 18 have non-ASCII filenames
and exactly 1 is genuine** (the deck, legitimately short on accounted-for images). Correlation is
18/18 — every single non-ASCII filename faults, and no ASCII filename faults spuriously across 77
name-verified rows. On this corpus the check is unusable for German filenames.

**Why it matters beyond the count:** a gate that cries wolf on a German corpus trains the operator
to wave faults through — the precise failure mode the ledger exists to prevent. It also inflates
the apparent extraction gap: the true unread set here is **38 pending**, not 45.

**Suspected cause:** the filename is interpolated into a `grep` pattern where the high bytes are
not treated literally, or `LC_ALL`/`LANG` is unset so the match runs under the C locale. Likely fix:
`grep -F --` with the name passed as an argument, not built into a pattern string.

**Workaround until fixed:** treat umlaut-filename faults as unverified rather than failed, and
confirm by hand with `grep -c '<name>' <artifact>`.

