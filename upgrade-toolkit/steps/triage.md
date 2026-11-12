# Step 1: triage (no changes yet)

Goal: know the version path, the module plan and the traps before anything changes.

Paths: `B=~/Mendix/mxcli-project-toolkit/upgrade-toolkit/bin`,
`EA=$UPG_SCANNER` (the optional upgrade scanner's folder; also read from `UPG_SCANNER=` in `~/.config/upgrade-toolkit/local.env`),
`BR=~/Mendix/<company>-brain` (company brain, plain markdown).

1. Full versions of the project and of every toolset you will use:
   `python3 $B/mxversion.py app/` and `python3 $B/mxversion.py tools/mxbuild-<ver>` (and `tools/runtime-<ver>`).
   Write them into `$W/versions.txt`. mxcli and the container wrappers refuse a near match.
   Then `python3 $B/appshape.py app/` (BT-2): exit 1 means a module-only template (no navigation home page, no theme): there is no
   old app to freeze, the pipeline stops here with exit 13 and "needs a host app" (`UPG_ALLOW_MODULE_ONLY=1` goes on anyway).
2. Target = latest released LTS, newest patch (SKILL rule LTS-1; 11.12 as of 2026-10, read the LTS/MTS page to confirm). Grep the chosen patch's release notes for "do not upgrade to this version" and take the patch it names instead (NR2-1: 11.12.5 told you to use 11.12.6). Then mark the run start so convertmade.sh does not take the 2014 Team Server root as the start (NR2-13): `git -C app commit --allow-empty -m "original: run start"` before any step.
   A source already on a newer non-LTS 11.x is parked. Read that patch's breaking changes and known issues into `$W/versions.txt`. Version path (SKILL rules) and the playbook: 9.x to 10.x [9-to-10](../playbooks/9-to-10.md), 10.24 to 11
   [10-to-11](../playbooks/10-to-11.md), 11.x to a newer 11.y [11-to-11](../playbooks/11-to-11.md). Edited Marketplace modules: [edited-modules](../playbooks/edited-modules.md).
3. Modules: `mxcli -p app.mpr -c "REFRESH CATALOG FULL"`, then the module list with content id and installed version
   (localedits.py prints both). Then `python3 $B/renamed_modules.py $W/localedits.json` (BT-6; the pipeline writes `$W/renamed.md`): a module the Marketplace renamed or republished (DataGrid to DataWidgets, ApprontoLicenser to Emixa Licenser; data in `playbooks/module-renames.tsv`, matched by content id) is NOT a version update: leave it out of plan.txt; the proposal makes it a decision item. For each module: target version per rung from `$BR/baseline/versions/modules-index.md`
   and `modules/<module>.md`; the index has no per-target selection, so take the newest version whose min Mendix is
   not above the target from `mxcli marketplace versions <content id>` (E6-5). "Min Mendix" in that table does not mean importable: packages made before 9.18 fail
   `mx module-import` on 10.x ("open it in 9.18 to 9.24 first", exit 117); see the 9-to-10 playbook. Five packages in
   E5b and one in E4 were pre-9.18 (NanoflowCommons 2.1.0 was made with 9.6.0). stepupdate.sh recognises the refusal:
   for the installed version it retries with `--no-baseline`, for a pre-9.18 TARGET it skips the line and keeps the
   module (E4-16, E5b-26). Drop pre-9.18 target versions from the pre-convert plan when the release notes say so.
   STRANDED modules: no version at all whose min Mendix fits the target major (Academy: PDFReader, only 1.0.0, AC-5).
   List them in `$W/stranded.md` with their jars (the userlib `<jar>.<Module>.RequiredLib` markers) and their Java
   actions. The update cannot help them: plan the port (own Java on the new library), a replacement module, or
   removal, before step 3. Their old jars are the usual source of a jarclash CLASH after the other modules move on.
   ORDER for an 11.x source going to 11.y: no 10.24 rung; plan1 = newest version with min Mendix at or below the
   SOURCE (pre-convert pass), plan2 = the ones whose newest fit is above the source (post-convert); see the 11-to-11
   playbook section 1 (N1-14). The 11.x MPR carries no content ids: `localedits.py --cid` (N1-1).
   ORDER for a 10.x below 10.24 going to 11: the 11-ready module versions need 10.24 or later, and Mendix 11 will not
   import packages made with older Studio Pro, so the module updates belong to the 10.24 rung, between the two
   converts (Academy, AC-2; the team did the same). A 10.24 source is the same rung: Mendix 11 refuses any package made
   before Studio Pro 10.21 ("range from 10.21.0 to 10.24.99", exit 117), and that includes the INSTALLED baseline
   package stepupdate re-imports first (Purchase Request: the refusals named 9.24 to 10.17, the installed versions,
   not the targets). Split each module: its newest version that installs on 10.24 goes to `$W/plan-pre.txt`; the
   version that needs 11 stays in `$W/plan.txt`, and post-convert it then has a 10.21+ baseline. The pipeline stops before the convert when a 10.x to 11 run has no plan-pre.txt (F13).
   ADD-ON modules (`modules/*.mxmodule`, a vendor binary; not in the catalog, so mxcli, localedits, stepupdate and
   the module list do not see them, T2-2): `python3 $B/test_inventory.py app/` lists each with the Studio Pro version
   that built it (`mxversion.py modules/<x>.mxmodule` for one file); `missing_deps.py` says "ADD-ON (.mxmodule, built
   with X)" instead of MISSING for their modules. One built before 10.21 blocks Mendix 11 (CE1893) and cannot be
   reopened: put "add-on built before 10.21" on the blocker list ([10-to-11](../playbooks/10-to-11.md) row 9) and
   plan a newer vendor build on the 10.24 rung, idcheck, then convert. Write them into `$W/stranded.md` if the vendor
   has no newer build.
   "OWN" modules that are really Marketplace (NS-4): a module without a content id or the FromAppStore flag is not
   always the team's own code. notification-service REST_Responses read as own 1.1.1 at 9.24 (29e084c5), yet
   4d625b84 updated it from the Marketplace to 2.0.0. Before you mark a module own, search the catalog for its name
   (`mxcli marketplace search <Module>`) and compare its javasource package (`javasource/<module lower case>/`) with
   the package the Marketplace version ships. A match is a Marketplace module that lost its link: plan it like one
   (release notes, target version, localedits against the installed version), never leave it out of the plan.
4. Targets of cross-module associations: `python3 $B/idcheck.py app/ --xmod`. Those modules go LAST in the plan
   (MxModelReflection is the usual one); their update drops associations other modules own. The exception (PV-2): a
   target goes BEFORE a planned module that owns an association into it, because the owner's import restores it;
   `python3 $B/planorder.py app/ $W/plan.txt` lists each pair in the wrong order and `--write` reorders the plan.
   Callers of the OLD API (T5-15, T5F-4): a module that stays kept (stranded, edited, refused) keeps calling the API it
   was built against. Once the plan and the kept/stranded list exist: `python3 $B/crosscalls.py app/ --kept <A,B> --planned <C,D>`
   (or `--kept-file .stepupdate/kept.txt --plan-file $W/plan.txt`; `--kept ''` when nothing stays). A `CAP <P> at <newest
   version of current major>` line (exit 1) means hold P at that version, or update the caller too; Bedrock 3.0.0 on
   AWSAuthentication 4.x broke at javac, Administration on MendixSSO at mx check (CE0117). Rerun it whenever the plan changes.
   crosscalls judges kept callers against the plan; the reverse (an updated module that needs what a kept one lacks, T6R-7)
   is checked after the steps by `keptdeps.py` (steps/upgrade.md, step 1).
   Theme of kept modules (MC-11): a kept module's themesource styling can hit platform widgets the plan updates (a rule on
   `.widget-datagrid`, `.mx-listview` and so on): the markup changes with the widget major, the model check and the build see
   nothing. `python3 $B/keptstyle.py app/ --kept <A,B>` (or `--kept-file .stepupdate/kept.txt`) prints `RISK <Module>
   <file>:<line> <selector>` per hit (exit 1 = REVIEW). Treat each module with hits as a visual risk: add a page that
   shows the widget to the screens step and read the screenshot. Rerun it whenever the kept list changes.
5. Local edits in Marketplace modules, BEFORE any update:
   `python3 $B/localedits.py app/ --md $W/localedits.md --json $W/localedits.json`
   - RED = data-bearing local edit (added attribute or association, changed storage): a stop rule (SKILL).
   - Exit 2 = some modules UNKNOWN (also a module `--mxcli-diff` could not judge). Never read that as "no edits".
     NETWORK modules (a download that kept timing out after 3 retries) are listed apart, with a `rerun:` line that
     names them: run it, they are not judged yet (batch 1: T3-2, T7-2, T8-5). No mxcli and a package not cached: exit 2
     with one line, set UPG_MXCLI.
     Content id 0 in the MPR (Administration often): `--cid Administration=23513`. Installed version not
     downloadable (HTTP 500, an unpublished label, a package made before 9.18): `--proxy Module=<nearest downloadable
     version>` (probe `mxcli marketplace versions <id>`); lines then say "compared with" that version, and a
     difference is drift OR edit, decide per line. A proxy a major version away says so: expect much drift (E5b-5,
     E4-1, E4-6). `--mxcli-diff` does not follow `--proxy` (mxcli has no base-version option, E4-8).
   - Layers it compares offline: domain model (RED), pages, layouts and snippets (`ui` lines: added, deleted, page
     layout changed, E5b-19), and logic documents present on one side only (`logic` lines: microflows, nanoflows,
     rules, Java and JavaScript actions, scheduled events, E5b-28). A changed validation rule on a persistent
     System.User specialization is RED. Microflow contents are not compared offline: add `--mxcli-diff` (needs the
     exact mxbuild; on macOS through `$B/mxcli-container.sh` with `UPG_ROOT=<run folder>`). Its `verified=false` and
     jar-only edits are printed in the module line and the md (E4-15).
   - Files outside the model (T5-17): `FILES-EDITED <path>` lines compare `themesource/<m>/`, `javascriptsource/<m>/` and
     the Java USER CODE blocks with the cached installed package (a vendor `_variables.scss` with the brand colours is the
     usual one; the model layers say "unchanged" for it). Any such line makes the exit code 1: the update replaces
     those files and nothing else reports it. Theme and JavaScript files are UI edits (`force-ui:`), Java user code is a logic edit.
   - The `force-ui:` line lists modules whose only edits are UI, jar-only or unverified: pass it to
     `stepupdate.sh --force-ui` (E4-13). A module with RED or logic lines is never on it.
6. Breaking changes:
   `python3 $EA/scripts/scan.py --project app --target <ver> --from-version auto --data $EA/data --out $W/findings.json`
   (scan.py exits 4 without a catalog: run step 3's `REFRESH CATALOG FULL` from the app folder first, so its relative
   mpr path resolves; E6-4) then ALWAYS `python3 $B/scancover.py $W/findings.json`. NO COVERAGE (exit 1) means the scanner checked nothing for
   this rung (its catalog holds Mendix 11 blockers only); do the manual checks it prints instead. For 9 to 10 that
   includes `python3 $B/javafinal.py app/` (final Java action parameters, a javac error that mx check misses).
7. Brain field notes for the versions on the path:
   `grep -rl "topic: upgrade" $BR/internal | grep -v -e '/_snapshot-' -e '/_prefix' | xargs grep -l "versions:.*<major.minor>"`
   Frontmatter `applies_to` says what kind of note it is; `versions` says where it is valid. A note outside its range
   is a hint, not a fact. Read titles first; open only the notes for modules on your plan.
8. Test inventory for step 2: `python3 $B/test_inventory.py app/ --md $W/test-inventory.md --endpoints $W/endpoints.txt`
   (after a FULL catalog build). It counts jars from the files and groups duplicates by artifact, inside userlib too
   (commons-lang3 3.12 and 3.14 in E5b): those are "present BEFORE the upgrade", so they are not blamed on it (E5b-4).
   It flags published operations whose name suggests a side effect: take those out of endpoints.txt. It does not yet
   read the published base path or check that a listed service answers at runtime (E5b-3): probe each endpoint once
   on the old app (on a copy, recorded in the ledger) and drop the 404s.
   Then `python3 $B/repair/jarclash.py app/ --md $W/jarclash-before.md`: class clashes BEFORE the upgrade (also a
   library hidden inside another jar, which no file-name check sees). The upgrade does not own these, but a module
   update that brings a newer copy of the same library turns them into compile errors (AC-6).
8b. Journey scope (after localedits.json and actions.json exist): `python3 $B/journey_scope.py $W/actions.json
   --model $W/original.mpr --localedits $W/localedits.json --code-root app/ --out $W/journey-scope.json --md $W/journey-scope.md`
   (the pipeline's propose step does this). Only what is used and reachable is tested. Print its two lines into the plan:
   `journeys in scope: N reachable, M out of scope (unreachable X, marketplace Y, no-role Z)` and `testability work: K
   reachable actions have no click path yet`. Out of scope is listed in journey-scope.md with a reason and is INFO in the
   gate, never INVALID; the K reachable ones stay INVALID and are real work: record a click path (a hand-written journey
   or `create-spec.json`), or test them at deploy. Optional `$W/usage.json` (format and how to get it: the docstring of
   journey_scope.py) adds class `unused`; without it nothing is said about usage. `$W/vendor-modules.txt` (one module
   per line) names own-looking modules that are really vendor code (item 3, NS-4). Read the `--md` list once: an
   "unreachable" page that a customer says they open is a finding about the model (a page opened only by a widget
   setting the scan cannot see), not about the toolkit: add it to the click paths by hand.
9. mxcli writes a `.claude/` folder into the app; stepupdate.sh puts it in .gitignore (E5b-17). Check
   `git -C app status` is clean before step 2.
10. Release impact (required, V31-RI): the brain holds the official Studio Pro and Marketplace release notes; read
   them for every version jump, never pick a module version without its notes (E6 and E7 did; E5b looked for a Java
   11 error the 10.x table explains). Write the module jumps as `<Module> <installed> -> <target>` lines (or a copy of
   plan.txt with the installed version as a fourth field; stepupdate.sh ignores it), then
   `python3 $B/release_impact.py --from <full ver> --to <full ver> --plan $W/module-jumps.txt --out $W/release-impact.md`
   Studio Pro rows from < version <= to across majors (10.24.16 to 11.12.2 reads the 11 table and the 10.24 rows above
   10.24.16), module rows old < version <= new; default types breaking, removal, requirement, deprecation (add
   `--types ...,security,known-issue` when the notes matter for the app). Exit 2 = something is not covered: an
   UNKNOWN module has no brain file (or the name matched several; give the slug as a third field, or `--slug
   Module=slug`, which also works with `--from-mpr/--to-mpr`), so read its Marketplace release notes by hand and fill
   its row. `--from-mpr old.mpr --to-mpr new.mpr` builds the module plan from the two projects (a module mxcli updated
   has no content id in the new one; the old one's is used, T6R-4), but it does not give the Studio Pro jump:
   `--from`/`--to` are still required (the error prints the versions the two .mpr files hold). Then open `$BR/baseline/versions/modules/<slug>.md` for every
   module on the plan and read the rows of the jump, improvements included, before you fix the target version. Each
   row gets `handled: <evidence path or commit>` or `not relevant: <reason>` in its last column as the run goes on;
   a rerun keeps those entries. The gate needs `release_impact.py --check $W/release-impact.md` clean.
   Exit 2 with `rows for <to> not in brain (newest <x>)`: the brain table is older than the target; read the
   release notes of the versions above `<x>` on docs.mendix.com and fill that Not covered row (T1-8, T2-19, T7-6);
   refreshing the brain's table is the brain owner's data update (T2F-1), not something to patch here. An entry that no
   longer matches a row after a refresh is listed under "Entries that matched no row", never dropped (T2F-4).
   A 9 to 10 or 10.x to 10.24 jump gives 200 to 370 rows, about half of them other database vendors and IDE-only
   (batch 1: T3-4, T4-10, T6-18, T7-23). Pre-fill those by rule instead of by hand or with your own script:
   `python3 $B/release_impact.py --facts-from-mpr app/<App>.mpr --db-vendor postgresql --db-version 16 --runtime-os linux
   --facts-out $W/facts.json` (N1-9, T2F-2: it counts OData (also `odata_consumed_connector`: references into connector modules such as SAPODataConnector, which the built-in client count misses; T3F-11), REST (services, not element types, plus REST call actions; T2R3-3, T8R-11), web services, workflows, document templates, OQL, native
   (from the navigation profiles only: a NativeNavigationProfile; Atlas_Core's native building blocks and a Phone profile are no native use; T2R3-3, N1R2-5),
   languages, own Java, own JDBC and the dev servlet from the model and `javasource`; no catalog or mxcli needed; the database
   and OS flags are what the app RUNS on, the model cannot tell: leave one out and its rows stay open, and the command lists
   what it left out). Add by hand only what you checked and it does not count (`kept`, `stranded`: module names; or a fact the
   model cannot see: check it in the model, a fact you did not check stays out: unknown fires no rule). Then
   `--auto --facts $W/facts.json`. (`test_inventory.py app --json inv.json` is still read as a second `--facts`.) The
   `--auto` run may also name the original project alone (`--from-mpr <original>.mpr`) and derives the facts itself, but
   then it has no module pairing: it prints `auto cannot use: ...` for each thing that costs (module rows, kept/stranded,
   unknown facts). The rules cover the .NET host rows, language codes, database vendors and versions, JDBC drivers, the
   development servlet, other IDE-only requirement and deprecation rows, and the features the facts show absent; a
   breaking or removal row of the IDE area stays open on purpose (some change the model). T6R-5: the same holds for
   the tool areas `git-teamserver` and `mxbuild-cli` (the SVN removal closes only with `vcs: git`, which the facts read
   from a `.git` folder above the mpr). With `javasource` next to the mpr the facts also carry `project_dir`, and two
   grep rules use it, citing what they read: a java-actions removal whose `affected` items are all Java symbols found
   nowhere in `javasource` (proxies excluded) or in a userlib jar (`java-symbol-absent`), and a Marketplace module's
   "library upgraded to x" requirement row whose libraries no Java outside that module's own folder imports
   (`module-library-bump`; jar copies stay jardedupe's, `steps/repair.md` row 3). Without `project_dir` (a hand facts
   file) both stay open: run `--facts-from-mpr` on the real project, or add `"project_dir": "app"` by hand.
   Replacements (B6): release impact keys on version windows, so a deprecated module kept at its version (DeepLink,
   MendixSSO) or a deprecated feature in use (Document Templates, legacy scheduled events, mx.logger) gives no row. Run
   `python3 $B/replacement_check.py app/ --to <full ver> --out $W/replacements.md` (the table is
   `playbooks/replacements.tsv`). Every row is listed: HIT and UNKNOWN are open (exit 1), clear and NOT APPLICABLE carry
   their reason; exit 2 = the app could not be read. Each open row gets `handled: <evidence or commit>` or
   `not relevant: <reason>` in its handled column, and its unchecked column (database rows, a forked native template)
   is checked by hand or by a journey.
   WorkflowCommons 3.x to 4.x: comment data and the history migration (PRR-4, Purchase Request). The step drops the association
   `WorkflowComment_WorkflowView` and ships ONE migration, `ASU_UserTaskView_Migrate` (UserTaskView in a final state to
   `System.WorkflowEndedUserTask`); nothing calls it, so an idcheck approval "the publisher's migration moves the data" is false
   until someone wires it. Two rows, both with a number in the handled column:
   (1) Count the orphan comments on the OLD database snapshot, before the update step (module still 3.x):
   `select count(*) as comments, count(*) filter (where w."workflowcommons$workflowcommentid" is null) as empty_workflow from "workflowcommons$workflowcomment" c left join "workflowcommons$workflowcomment_workflow" w on w."workflowcommons$workflowcommentid" = c.id;`
   (the 4.x read rule goes over `WorkflowComment_Workflow`; 3.12.x set BOTH links, so comments made on 3.12 survive; older versions
   and own code that set only the view link do not). 0 closes the row `not relevant: 0 orphan comments`. More than 0: for each, check
   `WorkflowComment_WorkflowView` then `WorkflowView_Workflow`; where the workflow is known, set `WorkflowComment_Workflow` on the OLD
   module version before the update step (counts before and after, orphans after 0); where it is not, the comment is lost at the
   first 4.x sync: say so in the report as a decision (Purchase Request: 5 of 5 seeded comments, all view-linked, none with a workflow).
   (2) `ASU_UserTaskView_Migrate`: call it from the app's OWN after-startup microflow (a new own `ASU_Main` that calls the vendor's
   after-startup, e.g. `MendixSSO.MendixSSO_AfterStartup`, then the migration; set `AfterStartupMicroflow` with `alter settings model`),
   or write `history not migrated` in the report. The vendor microflow's module is never edited. The run log shows `Finished execution
   of after-startup UserTaskView migration` after the start. `release_impact.py` drops `migration-step` rows by default
   (BACKLOG 84), so read WorkflowCommons 4.0.0's rows in the brain by hand until that is fixed. Companion prediction: replacements.tsv R37
   (OQL v2, steps/repair.md row 21).
   React 19 blocker (NR2-24, row R35): for a target of 11.6 or above the check reads the JavaScript of every widgets/*.mpk
   for `findDOMNode`, `unmountComponentAtNode` and `ReactDOM.render` (a call, not an import binding or the guarded
   react-onclickoutside fallback inside the Data Widgets filters), joins it with the widgets pages, snippets and layouts
   use, and prints the instance count. Run it with `--no-newer <widget or module names>`: the widgets and the stranded
   modules (`$W/stranded.md`, the step 3 version table) that have NO newer version. A hit on one of them says BLOCKER and
   the run prints a `blockers:` line: it goes on the blocker list of the plan (replace the widget with a platform widget
   or rebuild it BEFORE the upgrade; `mx update-widgets` cannot fix it, and the build, `mx check` and idcheck stay green).
   A hit on a widget that has a newer version is the plan's widget update on the 10.24 rung. Notification-service 11.12.6:
   mendix.DropdownContainer 1.2.0, 19 instances on 9 pages, owned by the stranded private PlatformDesignSystem.
   Bundled older React (MC-19, row R36, target 11.0 or above): a kept widget built before the Mendix 11 tooling can carry its OWN
   React 17/18 runtime (element symbol, `reactjs.org/docs/error-decoder` and the shared internals together in its runtime
   JavaScript; `*.editorPreview.js` is Studio Pro only and skipped). On the React 19 client it fails with React error #525 and
   the widget shows "Could not render widget"; build, check and the walks stay green unless a walked page holds it (Material
   Cockpit, a 2024 3D viewer package: gate exit 0). Same `--no-newer` handling as R35. A package that only compares against
   the element symbol (Data Widgets 3.x) is not a hit. Which widget has a licensed or private source is a human download:
   name it on the blocker list. Whether the gate WALKS a page with each widget is the gate's `widgets` rung
   (steps/gate.md, `bin/widgetcover.py`).
   The R36 evidence names the bundled library when it knows the marker (V3D-1: 3D Viewer 3.x to 5.x carry react-loading 2.x, a UMD file
   with its own React 16, and render its spinner while a model loads; React 18.2.0 renders it, React 19 does not, so the page works
   on the 10.24 rung). A newer version number is no evidence (5.3.0 still crashes; 2.2.2 and 2.7.0 mount): check any other copy of
   the package with row R36 BEFORE you swap it. A package a person patched keeps the dead copy in its file and still matches:
   `--accept <file>` with a line `<sha256 of that .mpk> <reason>` stops the report for exactly that file.
   Widget calls mx.logger (QI-3, row R38, target 11.0 or above): the same reading for `\bmx\.logger\b` in widgets/*.mpk that a page
   uses (Quality Inspection: List view controls 1.3.16, the newest release, throws a TypeError on 11.12.6 and its page never renders,
   while every gate rung passes). Own JavaScript is row R19. The remedy card is `widget-mxlogger`. A 10.x runtime log line
   DEPRECATED mx.logger names the same use (BACKLOG #102). A hit on an unrendered page is a risk the gate does not see (BACKLOG #101).
   Dojo to React client (B6-4): `python3 $B/dojo_report.py app/ --to <full ver> --out $W/dojo-react.md` lists every
   widget package as ready, delete (unused), can move (React path and source from `playbooks/dojo-successors.tsv`),
   can't move (no React path found) or not researched, plus legacy core widgets, Marketplace modules not React-ready and Dojo JavaScript. On an 11.x target
   it is ADVISORY (exit 0): put its open items in the report as the plan for the React switch. On 12 or above it is
   BLOCKING (exit 1). A "not researched" package gets a researched row in the table (cite the source), never a guess.
   Every auto entry reads `not relevant (auto): <rule>: <fact>`; read them, and replace one with
   your own entry where the fact is wrong for that row (a rerun never overwrites a human entry). Rows about a
   feature the app uses stay open: a breaking, removal or runtime row needs a scan (grep the model for the
   `affected` tokens) or a journey as its evidence, not "handled: build" (T3-22).
   Closure rule (QJ-2): for a row about a removed setting or a flipped default, "the setting is not set, so not
   relevant" is never a valid closure. The app ran with the OLD default; removing the setting or flipping the default
   changes behaviour exactly because it was not set. The only valid `not relevant` is "the source version already had
   the new default: <version, release note>". Otherwise the row stays open until a scan (replacement_check, a model
   grep) or a journey shows the behaviour is not used. Real miss: b5-forms closed the 11.0.0 removal of
   `Objects.SetSystemAttributesOnChange` this way on a 9.24.3 source, and Forms.SubmitForm then read a changedDate that
   is no longer set before the commit (now row R30). `release_impact.py --check` enforces this: such a row prints
   `UNSOUND` and counts as open, so the gate is INVALID until the entry cites the source default, a scan or a journey.
   After repair, rerun with `--from-mpr <original app>.mpr --to-mpr app/<app>.mpr` instead of a hand plan: the
   installed module versions of both projects, paired by content id (a renamed module such as DataGrid to
   DataWidgets keeps its id), so modules kept, installed by missing_deps or held back are what really happened
   (T1-31). Hand plan lines take a content id as an extra field: `DataGrid 1.3.2 -> 3.11.7 116540` (T1-9, T8-6).
11. Packages that make an entity non-persistent in the target version (Atlas_Web_Content 3.7.0 LoginContext, E4-19):
   no triage tool yet; read the release notes of every module on the plan for "non-persistent" and "removed entity",
   and expect the step idcheck REVIEW line.
12. Connector apps (TC-5, TC-3, TC-2; apps that call an external system through a connector module such as TcConnector
   or TeamcenterToolkit). Write `$W/connectors.md`, one block per connector:
   - Version and shape (TC-5): the connector module and its installed version. They differ per app (TcConnector 3.5,
     3.6.1, 2412, 2512, TeamcenterToolkit), and so do the config entity, the credentials page and the step that sets the
     default config. Record which, so baseline seeds the right entity and journeys open the right page.
   - Flows, each marked READ or WRITE (TC-3): by service or operation name, `create*`, `update*`, `revise*`, `set*`,
     `delete*`, anything workflow, and a BOM window (opening one is a write) are WRITE. Anything unclear is WRITE. When
     the external system is shared, only READ flows may be driven; journeys exclude every WRITE flow (backlog #45 for
     the generator filter; until then drop them by hand from the journey set).
   - Read-only services and mock signs (MC-17): per connector, the exact service operations the read-only guard has to
     allow (a full-text search is READ even though it is a POST; a call listed as allowed but never made is fine to
     leave out), and the signs that the app fell back to a LOCAL MOCK instead of the server (a denied or failing call
     that leaves the page showing sample data without any error, e.g. a 3D panel that shows the app's bundled model when
     the BOM window call is refused). A journey that only checks "something shows" passes on mock data: every
     connector-backed journey asserts a value only the server returns, and the mock signs are listed here so the
     reviewer can tell the two apart.
   - Reset traps (TC-2): list every "Reset to default" button and demo-data reset microflow that touches the
     connection config; baseline must not click them.
   - Proof value per connector-backed page (TC-1): the value only the real source returns, found on the old app. If the
     app shows mock data on a failed call, name the fallback too.
   - One account, one session (TC-6): note the account the connector logs in with; connector checks run one at a time.
13. Test readiness (RD-1), last, before any upgrade work and before the baseline: `python3 $B/readiness.py $W --app app/`
   (add `--test-systems FILE` with lines `<System> <url>` when the customer has test systems, `--data FILE` for a demo
   data snapshot). It reads what triage wrote (test inventory, connectors.md, processes.md, the apimock inventory of
   the model) and writes `$W/readiness.md` and `.json`: per gate rung READY, NEEDS <input> or CANNOT JUDGE, what the
   customer must supply, and the top line `best reachable verdict: PASS | PASS (on stand-in APIs ...) | INVALID unless
   <inputs>`. Exit 0 plain PASS, 4 qualified PASS, 3 INVALID unless inputs, 2 an input not read. Send the NEEDS rows
   to the customer now: in the 13 and 14 Oct runs, UNKNOWN consumed endpoints (notif R1), guest access without a
   confirmed anonymous process (PLM, PV360) and connector pages without proof values (MC) were all knowable here and
   surfaced only at the gate. A rung that blocks stays INVALID however well the upgrade goes; do not start step 2
   promising PASS. Baseline item 9 runs it again on what the baseline measured.

Output: `$W/versions.txt`, `$W/plan.txt` (stepupdate format: `<content id> <version> <Module>` per line, targets last),
`$W/localedits.md`, `$W/release-impact.md` (required), `$W/replacements.md`, `$W/dojo-react.md`, `$W/stranded.md`, `$W/jarclash-before.md`, `$W/readiness.md`, scanner result plus scancover verdict, the playbook to follow.
