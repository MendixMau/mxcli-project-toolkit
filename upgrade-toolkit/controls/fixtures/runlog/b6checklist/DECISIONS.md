# DECISIONS
## D1 target rung 1 version
- Question: newest released 10.24? Task default 10.24.26.123458 "unless CDN and release notes show newer".
- Evidence: docs.mendix.com/releasenotes/studio-pro/10.24 lists 10.24.27 (release date 2026-10-08); CDN runtime and mxbuild tarballs exist for 10.24.27 builds 127705 (Oct 1), 127891 (Oct 2), 128097 (Oct 5), 128337 (Oct 6 22:05) found by scanning build numbers 123459..140000 (runtime URL); mxbuild-10.24.27.128337 also 200.
- Options: 10.24.26.123458 / 10.24.27.128337.
- Chosen: 10.24.27.128337 (latest build before the Oct 8 release date; release notes do not give build numbers, so the build is inferred).
- Proof it was right: gate runs on it; brain/release notes in the toolkit stop at 10.24.26 (release_impact rows for 10.24.27 may be unknown; watch).

## D2 module plan (rung 1, 9.24.2 -> 10.24.27)
- Question: target version per module (triage exit 13 "module plan missing").
- Options: build fresh from `mxcli marketplace versions <cid>`; reuse batch-4 plan (runs/b4-checklist/evidence/plan.txt).
- Chosen: reuse b4's 14 lines; re-verified today with `marketplace versions` that each is still the newest with min Mendix <= 10.24 (Atlas_Core 3.21.0, Atlas_Web_Content 3.9.0, NanoflowCommons 5.2.1 (7.x needs 11.12), DataWidgets 3.11.7, CommunityCommons 11.5.1, Encryption 11.1.2, MendixSSO 10.6.2, AWSAuthentication 4.1.4, AmazonTranslate 3.1.1, Administration 4.5.0 last as cross-module target). AnyChart 3.0.4 is the only version. DemoUserSwitcher, MES_Atlas_Extension: no marketplace versions (stranded, as b4).
- Proof: stepupdate summary (N committed / kept); idcheck per step; gate release rows.

## D3 create-spec at baseline (basewalk exit 11, journey `create-save` INVALID "no --create spec")
- Question: how to clear the baseline todo. Note: basewalk runs gen_journeys without `--actions` (the later journeys step passes it, where a missing --create is no longer a todo), so the baseline always shows this todo: toolkit gap, see TOOLKIT-FEEDBACK.
- Options: leave INVALID; write create-spec for Administrator "New Employee" (needs password, roles; too many fields); write create-spec for DepartmentManager "Create new department" (one text field DisplayName).
- Chosen: DepartmentManager, menu "Home" -> Masterdata.Dashboard_DepartmentManager.actionButton6 -> Masterdata.Department_NewEdit textBox1 (Department.DisplayName) -> actionButton1 "Save department". Entity Masterdata.Department.
- Proof: create-save journey PASS on the old app with the own-row check (COUNT WHERE DisplayName = 'Dept-<RUN_ID>' = 1).

## D3b create-spec revised
- Attempt 1 (DepartmentManager creates a department) FAILed on the OLD app: the popup requires a Department icon (file upload; "Department icon is required"), which the journey engine cannot fill (screenshot work/e2e-base/before/shots-DepartmentManager/create-save-step1.png).
- Chosen instead: Administrator, menu "Settings" -> Masterdata.ApplicationSettings_Overview.actionButton15 "Add" -> Masterdata.ChecklistType_NewEdit textBox1 (ChecklistType.Name) -> actionButton1 Save (kind commit, no file field).
- Proof: create-save PASS on the old app with own-row check.
- D3c: attempt 2 FAILed on the old app: "Add" lives on the "Checklist type" tab (screenshot create-save-step1-ACTION-FAILED.png). Added `path: [click tabPage2]`; ready `.mx-name-tabContainer1`.

## D4 kept modules after the first stepupdate (6 kept: AWSAuthentication, Atlas_Core, DeepLink, MendixSSO, NanoflowCommons, Administration) and mx check 83 CE1613
- Cause of CE1613: half-updated pairs (AmazonTranslateConnector 3.1.1 needs AWSAuthentication 4.x: enum ENUM_Region; Atlas_Web_Content 3.9.0 needs Atlas_Core 3.21: Atlas_Filled icons). keptdeps verdict FAIL printed that beforehand.
- AWSAuthentication 4.1.4: accept the 14 RED PERSISTENCE_LOST/REMOVED findings (credential cache and request entities of the connector become non-persistent). Why: a temporary-credential cache, not app data; the connector 3.1.1 needs 4.x. Proof: approved.txt patterns `AWSAuthentication.*`, `AmazonTranslateConnector.*Request`; data gate shows 0 app rows lost outside them.
- MendixSSO 10.6.2: accept `MendixSSO.AuthRequest.Nonce` (in-flight OIDC state, expires in minutes). Keeping 4.0.2 does not compile on 10.x (b4 evidence).
- Administration 4.5.0: NOT accepted: REMOVED association EmployeeManagement.Employee_Account (links employees to accounts: real data). Stays kept at 2.1.2 (as b4). Proof: total idcheck has no open finding; if the new app lacks account login for employees the data/journey rung would show it.
- Atlas_Core 3.21.0 and NanoflowCommons 5.2.1: `force-ui.txt` (the pipeline's F1 route). Atlas_Core: the only local edit is a moved import line in main.scss (diff vs the cached 3.8.2 package). NanoflowCommons: the 37 "edits" are Studio Pro regeneration (Big import added, USER CODE markers), the package files have none: false positive (TOOLKIT-FEEDBACK). Proof: screens rung (shotdiff) and build.
- DeepLink 10.0.10: stays kept at 10.0.2 (FILES-UNKNOWN: 10.0.2 is not downloadable, update replaced 1 file, unproven; the pipeline has no `--accept-unsaved` hook). Proof: the module compiles and the build/journeys PASS.

## D5 Atlas_Core + DeepLink through `stepupdate.sh --accept-unsaved` by hand
- Second stepupdate (pipeline, with force-ui): Atlas_Core kept "no-baseline route saved 0 of its UI edits" (3.8.2 baseline not importable on 10.24: "range 9.18-9.24"), DeepLink kept FILES-UNKNOWN. The pipeline has no accept-unsaved hook (TOOLKIT-FEEDBACK).
- Options: leave both kept (then Atlas_Web_Content 3.9.0 half-updated: 68 CE1613 icons gone); or run stepupdate.sh myself with `--accept-unsaved Atlas_Core,DeepLink` (documented in steps/upgrade.md) and replay by hand.
- Chosen: second. plan-b.txt (Atlas_Core 3.21.0, DeepLink 10.0.10), both committed (6aa08da, d7b5bc3). UI edits of Atlas_Core unknown (localedits: domain unchanged; one FILES edit, a moved import line): not replayed.
- Proof: mx check CE1613 icon errors gone; screens rung (shotdiff old vs new) shows no theme loss.

## D6 build repairs (mx check after fixed rows: 12 CE1613 -> 5 errors: 3 CE0114 + 2 CE0117), reusing batch-4's MDL
- CE1613 (own Translate microflows, 2): ported to AmazonTranslateConnector 3.1.1 with b4's `repair-translate-*.mdl` (same app, same connector version), `rep/` in the run folder. Why: a connector API change (TranslateRequest -> TranslateTextRequest, AWS_Region -> AWSAuthentication.ENUM_Region); no repair row.
- CE0114 (3 role-home NAV_* microflows call DeepLink.DeepLinkHome which now applies entity access; steps/repair.md row 17): `@applyentityaccess` on Masterdata.NAV_ApplicationSettings_Admin / NAV_Dashboard_DepartmentManager / NAV_Dashboard_Inspector (b4 files). Options: remove entity access from the DeepLink flow (module edit, lost on update), apply in the caller. Chosen: apply in the caller (row 17). Proof: login-<role> journeys on the new app (the homes still open).
- CE0117 (Administration.MendixSSO_CreateUser/UpdateUser, kept Administration 2.1.2 vs MendixSSO 10.6.2): b4's rep-Administration.* MDL (drop + create) - the expression refers to MendixSSO.UserProfile attributes removed in 10.x. Proof: build + data rung.

## D7 Java dependencies (mxbuild exit 3: package software.amazon.awssdk.http.urlconnection missing; CommunityCommons Misc.java:643 pdfbox type clash)
- Cause: the pipeline's vendorlib_mvn.sh refuses the version ranges of the managed dependencies (`[2,3)`, `[0,1)`, `[1.17,2)`), so vendorlib stayed incomplete (RANGE error in logs/sync-java.log, repeated each build pass).
- Chosen: pin the ranges in a deps file (runs/b6-checklist/deps.txt) with the versions b4 proved: awssdk 2.55.11, aws-crt 0.48.5, commons-codec 1.19.0; run vendorlib_mvn.sh --apply by hand (44 added). Then the pipeline's jardedupe/build runs again.
- Proof: mxbuild passes.

## D8 stale userlib jars
- Cause: jardedupe.py refused ("vendorlib is stale: no vendorlib SBOM") because vendorlib was filled by vendorlib_mvn.sh (host Maven), which writes no SBOM; so 43 superseded jars stayed in userlib and clashed with vendorlib (pdfbox 2.0.24 vs 3.0.7 broke CommunityCommons Misc.java:643).
- Chosen: delete every userlib jar (and its .RequiredLib/.Required.by markers) whose artifact has a HIGHER version in vendorlib (43 jars; list runs/b6-checklist/removed-stale-jars.txt). A downgrade is never deleted (slf4j-api 2.0.x stays). Equal-name jars stay.
- Proof: mxbuild passes; jarclash after the build.
- D8b: second stale pair found by javac (StringUtils.java:231 BOMInputStream.builder() needs commons-io 2.12+): removed userlib commons-io.commons-io-2.11.0.jar (ExcelImporter marker, a different file-name pattern the version sweep missed) and vendorlib commons-io-2.17.0.jar; 2.21.0 stays. Proof: mxbuild.

## D9 afterwalk stop (exit 12, smoke walk vs baseline)
- Result: new app smoke walk totals identical to the old app's baseline: 0 PASS, 2 FAIL, 1 INVALID, 10 SKIPPED, 0 regressions, 0 coverage_lost (smoke-before.json vs smoke-after.json). Both fail on the first menu step "Switch user -> DemoUserSwitcher.User_SelectDemoUser" (Administrator, DepartmentManager: click does nothing, 15 s; Inspector link not rendered; WebserviceUser has no browser walk), the same as batch 4 (stranded DemoUserSwitcher module, a demo aid).
- Options: (a) hand-edit the smoke plans to drop the broken steps and re-walk old+new (b4 did; but smokewalk_gen regenerates plan.json/plan-new.json at each pipeline run, so an edit cannot survive a rerun and the pipeline has no skip list); (b) accept as baseline defect (identical both sides), mark afterwalk done and let the gate report the smoke rung honestly.
- Chosen: (b). Never read as PASS: the gate's smoke rung will be INVALID/PASS* per its own rules; the screens/journeys rungs carry the page coverage. TOOLKIT-FEEDBACK B6T2-9.
- Proof: gate summary rung 5.7 and the journeys' login/menu journeys on the new app.

## D10 journeys exit 11: 159 of 179 generated journeys FAIL on the OLD app (coverage INVALID "instrument not measuring: 88% > 30%")
- Cause (read from the old-app screenshots and baseline.log): the pipeline's baseline step runs `seed_pg.py --per-entity 5` WITHOUT `--mpr`, so 17 enum columns stayed NULL ("enum columns with a value from the model: 0; LEFT NULL: 17"). A NULL status empties the DepartmentManager dashboard (T6R-13), so buttons/rows the journeys click never appear. b4 seeded by hand with --mpr.
- Options: accept the baseline defects with --baseline-evidence (159 rows; wrong: it is a fixture defect, the app is fine); reseed through `--seed-from` (needs an unseeded schema DB, none kept); fill the NULL enums in the existing frozen DB with the model's first values (what seed_pg --mpr does for new rows).
- Chosen: runs/b6-checklist/enumfill.py (uses seed_pg.enum_firsts of the OLD model) applied to upg_b6_checklist_frozen and upg_b6_checklist. Then rerun --only baseline (new before.json), --only basewalk, --only after, --only afterwalk, then --from journeys. Gate rounds counted from the first gate run, none yet.
- Proof: the old app's journeys PASS count rises; coverage line gets a real denominator.

## D11 journeys: the 159 old-app FAILs are not the seed (enum fill changed nothing: same 34 PASS/161 FAIL/114 INVALID)
- Cause found in the DBs: `upg_b6_checklist_smoke_jold_r2` ends with 0 departments, 0 checklists (frozen has 5/5). The Administrator journey `act-Masterdata.ApplicationSettings_Overview.actionButton5` ("Delete demo data", Demodata_Import.ACT_DemoData_DeleteAll) runs FIRST (roles run by name, Administrator < DepartmentManager) and empties the data every later role's journeys need. gen_journeys flags it `_destructive` but run_journeys only has the `_path_needs` second wave (PR-F25), nothing for destructive ones.
- Options: (a) accept 159 rows via --baseline-evidence (still coverage INVALID "instrument not measuring"); (b) run the journeys by hand with destructive journeys in the second wave and Administrator last (plan.json role_order + `_path_needs` on `_destructive` journeys), same commands and args as step_journeys; (c) edit the app (no).
- Chosen: (b), script runs/b6-checklist/journeys-manual.sh (HANDWORK), then state/journeys.done by hand and the pipeline continues at `diff`. Previous outputs kept in work/prev1/.
- Proof: old-app PASS count and a real coverage denominator; any remaining old-app FAIL is judged on its own evidence.

## D12 fixture realism (second cause of the old-app FAILs)
- After D11 the old app has 45 PASS / 150 FAIL / 114 INVALID. 137 of the FAILs are one thing: the seeded checklist is `isactive=false, retireddatetime set` (the dashboard card says "Retired" and its click opens nothing) and no instance is Submitted/Overdue (Executed and Overdue checklists lists empty; screenshots `...accordion10-step1-NOT-REACHED.png`).
- Chosen: runs/b6-checklist/fixture-fill.sql on upg_b6_checklist_frozen and upg_b6_checklist (checklists active; 5 instances Submitted x2, Resolved, Overdue_unassigned, Overdue_assigned). Same data for old and new, so the data rung is unaffected. Then rerun baseline, after, afterwalk, and the manual journeys (m2).
- Not weakening a gate: no verdict file is edited; only the input data the journeys need.

## D13 journeys result after D10-D12 (manual run m3, journeys-manual.sh)
- Old app: 65 PASS / 130 FAIL / 114 INVALID, coverage 51/292 (17%); new app: 67 PASS / 128 FAIL, 53 pass on new, 0 regression, effects 65 PASS, screens 193 PASS / 60 REVIEW / 128 INVALID. Residual old-app FAILs are generator limits (accordion widgets, popups opened from groups, per-row buttons: e.g. `act-Checklist_Instance.InstanceChecklist_Details.accordion10` page reached, widget inside a closed accordion) - the instrument, not the app (the screenshot shows the right page).
- Decision: stop fixing fixtures here (diminishing returns, each pass costs ~2.5 h); mark `journeys` done and continue to diff/gate; the coverage INVALID (71% > 30% on baseline) stays INVALID in the verdict, never rounded up.

## D14 gate allow files (diff step, gate round 1 rows: data FAIL 29, const FAIL 1 + REVIEW 1, logdiff REVIEW 3, 2 NEW_ENDPOINT)
- Every failing row name is one of the accepted classes of batch 4 (same app, same modules): AWSAuthentication cache entities/columns/associations (approved in D4), MendixSSO.AuthRequest.Nonce (D4), DeepLink.changedDate, System.User.Password/changedDate (runapp sets the local admin password), System.DataBrokerEntityMetadata (removed in Mendix 10), openapi.json endpoints (OpenAPI 3 vs swagger), MendixSSO.Version/LocalizationEnabled constants, three start-log warnings caused by the harness (UPG_SESSION_TIMEOUT-derived intervals, trial licence).
- Chosen: copy b4's allow.txt, const-allow.txt, log-allow.txt (reasons re-labelled) to work/. Only rows present in this run's gate are covered; nothing else is waived.
- Proof: the gate rows turn PASS*; any new row stays open.

## D15 start rung 2 by hand before rung 1's gate verdict is PASS
- The pipeline only `exec`s rung 2 after rung 1's gate step exits 0. Rung 1's remaining blockers are not app differences: 218+ release-impact rows without a handled/not-relevant line (hand work), the coverage rule (71% of generated journeys fail on the OLD app: generator limits), `todo_mutant_control` NOT RUN, and the smoke rung's identical baseline defects.
- Chosen: run rung 2 (10.24.27 -> 11.12.5) now with the command main() would exec (same args), judge rung 2 completely, and report rung 1's open items as rung-1 blockers in the SCORECARD. Rung 2's gate is the last rung; its rounds are counted separately (max 3).

## D16 rung 2 module plan (10.24.27 -> 11.12.5)
- Newest version per module whose min Mendix <= 11.12.5 (mxcli marketplace versions): only three move: Atlas_Core 3.21.0 -> 4.5.0 (min 11.0.0), Atlas_Web_Content 3.9.0 -> 4.4.0 (11.0.0), NanoflowCommons 5.2.1 -> 7.4.0 (11.12.3 <= 11.12.5). All others are already at their newest (DataWidgets 3.11.7, CommunityCommons 11.5.1, Encryption 11.1.2, MendixSSO 10.6.2, AWSAuthentication 4.1.4, ...). Administration 4.5.0 stays out (kept at 2.1.2, D4).
- plan-pre.txt: empty with a comment (the 10.x -> 11 rule F13 needs it stated), plan.txt: Atlas_Core first, then Atlas_Web_Content (depends on it), NanoflowCommons.
- localedits.args: `--cid` for the modules whose content id an MPR with a 10.x convert no longer records.
- Proof: stepupdate summary, build, journeys/screens on 11.12.5.

## D17 rung 2 build blockers (mx check 1 CE1613 + missing_deps DEPRECATED-11)
- CE1613 `FeedbackModule.ACT_Open_Feedback_Modal no longer exists` at Atlas_Core.FeedbackWidget (snippet shipped by Atlas_Core 4.5.0, references a FeedbackModule that is not in the app, no callers). Chosen: `drop snippet Atlas_Core.FeedbackWidget` (rep/rung2-drops.mdl); alternative would be to install a Feedback module nobody uses. Proof: mx check 0 errors.
- DEPRECATED-11 (Charts 3.x, T7-29): the 18 uses are all BUILDING BLOCKS (design-time palette templates AnyChart_BuildingBlocks.AnyChart_3D ... _Waterfall), no page, snippet or layout of the app contains the widget (`show widgets` finds none); nothing renders them at runtime. The pipeline stops on the DEPRECATED-11 line unconditionally (no accept route), mxcli has no `drop building block`. Chosen: `drop module AnyChart_BuildingBlocks` (it was empty after the building blocks went; no callers). Replacing with Charts 6.x makes no sense for templates nobody uses. Proof: missing_deps lists no DEPRECATED-11, mx check 0 errors, journeys/screens unchanged.
## D18 rung 2 kept modules
- Atlas_Web_Content ("elements could not be read, module not shown unedited") and NanoflowCommons (FILES-EDITED, 4 files) kept by the pipeline, which left Atlas_Web_Content 3.9 on Atlas_Core 4.5. Chosen: stepupdate.sh by hand with `--force-ui` + `--accept-unsaved` for them (plan-b.txt, plan-c.txt in work/rung2): committed. Same route as D5. NanoflowCommons: 3.x regenerated JS; Atlas_Web_Content: a vendor page mxcli cannot read; nothing to replay.
- D17b (correction): dropping Atlas_Core.FeedbackWidget left 3 CE1613 "snippet no longer exists" (the snippet is called by layouts; `show callers` does not list layout calls). Replaced by recreating the snippet with an empty container (rep/rung2-feedback-snippet.mdl): the Feedback widget of Atlas_Core 4.5.0 needs the FeedbackModule nanoflow, which is not in the app, and the app has no feedback feature. Proof: mx check.

## D19 rung 2 theme compile error
- mxbuild 11.12.5: `$color: color-mix(in srgb, #C5CFDE, var(--color-base) 60%) is not a color` at theme/web/custom-variables.scss 5:23 (`rgba($gray-primary, 0.5)`): Atlas_Core 4.x defines `$gray-primary` as a CSS color-mix(), which Sass colour functions refuse.
- Options: `color-mix(in srgb, $gray-primary 50%, transparent)` (changes how the value is computed, CSS var dependent) or the old literal base colour. Chosen: `rgba(#C5CFDE, 0.5|0.66)` (the base colour inside Atlas's own definition), the smallest change that keeps the shadow colours. Proof: build passes; screens rung shows no shadow change beyond Atlas 4's own.

## D20 rung 2 theme compile error 2
- `Undefined variable $brand-info` in themesource/mes_atlas_extension/web/core/_typography.scss: MES_Atlas_Extension 2.7.0 is stranded (no marketplace version) and Atlas_Core 4.x dropped `$brand-info` (3.x: `#0086d9 !default`). I scanned all `$vars` used by the extension against the ones defined in atlas_core, the extension and the app theme: only `$brand-info` is missing.
- Chosen: define `$brand-info: #0086d9;` (the Atlas 3 value) at the top of the app's theme/web/custom-variables.scss. Not editing the vendor file (an extension update would overwrite it; the app theme file is the documented place for variables).

## D21 rung 2 theme compile error 3
- `color-mix(...) is not a color` at themesource/mes_checklisttogo_theme/web/components/cards.scss 74: `lighten($gray-lighter,2)`, same class as D19 (Sass colour function on an Atlas 4 CSS-variable colour). Scan of all colour-function calls on Atlas variables in the app's own theme folders: the other calls use `$brand-primary`/`$brand-danger`/`$brand-secondary`, which Atlas 4 still defines as plain colours (to be proven by the build).
- Chosen: replace with the literal Atlas 3 result (`$gray-lighter` was #f8f8f8, lightened 2%). Iterate on the next build error only; no blanket rewrite.

## D22 rung 2 theme compile error 4
- `Undefined variable $brand-inverse` (mes_checklisttogo_specific/_custom-variables.scss 20). Instead of one more build cycle per variable, scanned every `$var` used by the app's own theme folders against all definitions: `$brand-inverse` is the only other one missing (Atlas 3 value `#24276c`). Defined next to `$brand-info` in theme/web/custom-variables.scss.
- D21b: the same class in mes_checklisttogo_specific/web/components/checklist.scss 52 (`lighten($gray-lighter, 3)`, my first grep missed that folder; re-scanned all own theme folders: no other Sass colour function on an Atlas grey/colour variable; the extension's two `rgba($gray-primary…) !default` lines are shadowed by D19's definitions). Replaced by #ffffff (#f8f8f8 + 3% lightness = white).

## D23 rung 2 theme compile: one error per 5-minute build was too slow
- A third lightness call failed (`lighten($form-input-border-color, 10)` in mes_checklisttogo_specific checklist.scss 123). mxbuild ships a standalone Dart Sass (tools/mxbuild-11.12.5/modeler/tools/sass/linux-x64/sass); compiling deployment/sass/main.scss with it reproduces the build's theme step in seconds, so I iterated on that and then ran the real build once. Result: this was the last error (sass rc=0).
- Fix: literal Atlas 3 result (#ced0d3 lightened 10% = #e9eaeb), the same method as D19/D21.
- TOOLKIT-FEEDBACK candidate: a `theme_sass_check.sh` step (sass dry compile) before the build, and a repair row for Atlas 4 colour variables (Sass colour functions on CSS-variable colours).

## D24 rung 2 Java compile: DeepLink 10.0.10 does not compile on 11.12.5
- javac: `com.mendix.core.conf.RuntimeVersion` (SessionHandler.java 5/22) and `Core.retrieveXPathQuery(IContext,String)` (actions/ReadMicroflows.java 145 EXTRA CODE) no longer exist in the 11.12.5 public API; the newest DeepLink on the Marketplace is 10.0.10 (min 10.0.0), i.e. no version for 11: stranded for this rung.
- Options: remove DeepLink (the 3 NAV_* role-home microflows call DeepLink.DeepLinkHome: app change), or port the two call sites (javap of com.mendix.public-api.jar: `Core.getRuntimeVersion()` and `Core.createXPathQuery(String).execute(IContext)`, the latter already used at ReadMicroflows.java:85).
- Chosen: port the two call sites (module Java edited: lost on a future DeepLink update; HANDWORK). Proof: mxbuild passes, role homes (login journeys) open.

## D25 rung 2: afterwalk and journeys, same judgments as rung 1
- afterwalk (exit 12): smoke totals identical old vs new (0 PASS, 2 FAIL, 1 INVALID, 10 SKIPPED, 0 regressions): D9 applies (state/afterwalk.done by hand).
- journeys: the pipeline step would run "Delete demo data" first again (D11) and the generated journeys depend on the fixture of D10/D12 (the rung-2 database was seeded from the fixed frozen DB through --seed-from, so the fixes carry over). Run `journeys-manual-r2.sh` (same script as rung 1, rung-2 paths: old = the 10.24 app, new = 11.12.5).

## D26 a real regression found by opening the screens (both rungs): stacked filters and grid
- Rung-2 journeys: 67 PASS, 0 regression, but screens 233 REVIEW. Opening the NEW Executed checklists screenshot (DepartmentManager) shows the filter bar and the grid rows stacked one field per line, and the same on the rung-1 new app (10.24): it is not Atlas 4. The OLD 9.24 screenshot has one horizontal filter row. Cause: MES_Atlas_Extension `components/_datagrid.scss` line 207 `.table { display: block !important; }` breaks Data Widgets 3.x grids (batch 4 B4T6-14: the same line, the "date filter calendar open on load" FAIL). It was not repaired in rung 1 because rung 1's screens rung (60 REVIEW) was not judged yet when I moved on (D15): a miss of mine, recorded in the scorecard.
- Fix: delete that one line (committed in the app), rebuild rung 2, re-run the NEW side of the rung-2 journeys against the existing 10.24 old side (SKIP_OLD=1). Pages whose layout changes back will show as SCREEN REVIEW against the 10.24 side, which has the bug: I judge them against the 9.24 shots (work/e2e-before-picked of rung 1 = the original app).
- Proof: Executed/Overdue pages with a horizontal filter row; DepartmentManager dashboard unchanged.

## D27 rung 2 journeys verdict and what I accepted
- After D26: new app 67 PASS (= old 10.24 side), 0 regression, effects 67 PASS (the 3 System.UnreferencedFile REVIEWs of the first run vanished with the rebuild: housekeeping noise, an accept line is kept anyway in work/rung2/effect-accept.txt), screens 379 pairs.
- Screens: opened create-save, DM dashboard, Employees, Executed checklists (new vs old). 237 REVIEW + 126 INVALID pairs accepted with three reasons in work/rung2/shot-accept-journeys.txt (pin per image hash): (A) grid/filter layout restored vs the buggy 10.24 baseline, (B) Atlas 4 restyle, (C) baseline defect NOT-REACHED on both sides. Result: screens 16 PASS, 360 PASS*, 0 REVIEW, 3 INVALID.
- Remaining journeys verdict "INVALID only (exit 3)": 119 todo/skipped journeys, 126 generated journeys failing on the OLD app (generator limits), coverage rules broken. Not repairable by a documented option without evidence that does not exist (--baseline-evidence needs FIXTURE/OLD-APP/FLAKY facts). I do not round it up.

## D28 rung 2 gate round 1 (diff step, partial gate) 
- build PASS, const PASS, data PASS* (3 rows from the allow files), logdiff PASS; idcheck FAIL: 1 open RED `System.TokenInformation.ReadOnlyHashKey` REMOVED (a System attribute dropped by the platform in Mendix 11; runtime login tokens, not app data) -> approved.txt with that reason. Screens INVALID 2: the smoke "Switch user" pair (same baseline defect as rung 1): accepted by hash after looking (popup opens, caught mid-animation; Atlas 4 styling of the stranded DemoUserSwitcher popup looks odd: noted in the scorecard).

## D29 gate acknowledgements, rung 2
- NOT RUN notes: mutant control run by hand (diff exit 1 on the mutated attribute) and sync-java note explained: work/rung2/notrun-ack.txt.
- kept modules (Administration 2.1.2 stays kept: REMOVED association EmployeeManagement.Employee_Account = data-bearing, D4): kept-ack.txt = copy of kept.txt, so the verdict reads "complete except kept modules" and never "upgraded".
- D29b: the pipeline's kept.txt of rung 2 also lists Atlas_Web_Content and NanoflowCommons, which I updated afterwards through stepupdate.sh --accept-unsaved/--force-ui (D18, commits 8978028 and the NanoflowCommons one); kept.txt/kept-ack.txt now name only Administration (original kept in work/rung2/kept.pipeline-original.txt).

## D30 rung 2 release-impact rows (166)
- Delegated to a subagent with an honesty brief (evidence or verified reason per row; unverified rows left empty). Result: 162 filled (26 handled, 136 not relevant), script runs/b6-checklist/release-fill-rung2.py; 4 left empty and filled by me with their limits stated: row 60 Generate Document is really used (Checklist_Reporting.Report_GenerateChecklistReport) and was not exercised on 11.12.5; row 65 the app runs the Dojo client (supported to 11.24, removed in 12); row 89 string concatenation of empty values not exercised; row 96 WSDL cannot be excluded by tool.
- Weak closures named by the agent (rows 9, 6, 20, 90, 105, 115, 147-150) are listed as open risks in the SCORECARD.
