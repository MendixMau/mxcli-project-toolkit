# Re-architecture catalogue: patterns where an upgrade cannot be done as it is

Use when a stuck item (steps/decide.md) cannot be kept, pinned or swapped one for one. A pattern answered once is
reused on every next app: bin/proposal.py prefills a section-3 item from the entry whose `match` fits it and cites the RA id.

Relation to the other files (this file builds on them, it does not replace them):
- `remedies.tsv` stays the machine card per blocker (one row per option, AUTO-TRY or HUMAN, read by bin/remedy.py). An RA entry
  is the level above: the pattern, the recipe in steps, the evidence. Where a remedies key exists the entry names it (`cards:`).
- `replacements.tsv` / `dojo-successors.tsv` stay the detectors and one-for-one successors. An RA entry starts where they say
  "no successor" or "needs a redesign".
- `widgets.md`, `deprecated-components.md`, `research/design-2026-10-14/` are the evidence the entries cite.

## Entry format (read by bin/proposal.py; keep one line per field)
```
### RA-<n> <short title>
- topic: widget-gone | atlas | dojo | module-api
- match: <Python regex, case-insensitive search on the section-3 item text: kind, name, evidence>
- trigger: <which tool/file/line detects it>
- why: <why it cannot be upgraded as it is>
- options: <keep | replace | rebuild | hand off, each "name (effort S/M/L, risk)"> separated by " | "
- recommendation: <one option and why>
- effort: S|M|L        (of the recommended option)
- recipe: <numbered steps; design properties over custom CSS>
- evidence: <apps by code name, FEEDBACK ids, decision ids, result>
- status: proven | tried once | idea
- cards: <remedies.tsv keys, or none>
```
`proven` = worked on two or more runs or on a gate that measured it. `tried once` = one run, result stated. `idea` = no field result.
Never raise a status without a run; a new pattern from a stuck item enters as `tried once` or `idea` (steps/decide.md).

---
## Topic 1: a widget that no longer exists or has no successor
A widget disappears in three ways: its package is not supported on the new platform (Dojo-only), the Marketplace dropped it, or
it still loads but breaks on the new client or resets on `update-widgets`. A one-for-one swap exists for few of them; the rest
need the feature rebuilt from platform widgets, or kept alive on the old platform.

### RA-1 Tree table widget with no pluggable successor (MxTreeTable)
- topic: widget-gone
- match: mxtreetable|tree.?table
- trigger: dojo_report.py "can't move" row for `com.mendix.widget.custom.mxtreetable.MxTreeTable` (dojo-successors.tsv status none-found); replacement_check widget row; the widget id on a used page.
- why: the package is Dojo-only (no pluginWidget in its source), unsupported on 10.24 and later; neither listed candidate (Tree Node, React Complex Tree) is a tree-table, so no swap keeps the columns plus expand.
- options: keep on the last Dojo-capable version (S, blocks the React client and Mendix 12) | replace by Data grid 2 with a parent-child expand: a Gallery or Data grid 2 per level in a list-view-in-row (M, look changes, one level of depth per widget) | rebuild as a pluggable widget with the same properties (L, own code) | drop the feature if the page is dead per impact_map (S) | hand off to a named person
- recommendation: replace by nested Data grid 2 when the tree is 2 levels deep or less; rebuild only if deeper; keep only while the app stays on the Dojo client.
- effort: M
- recipe: 1) list the pages that hold the widget (`dojo_report.py`, impact_map; skip dead pages). 2) Per page read the tree: entity, parent association, columns, the on-click action. 3) Build the top level as Data grid 2 on the root entity; for each child level add a Data grid 2 (or Gallery) in a conditionally visible container bound to the association of the row, opened by a design-property-styled toggle (Atlas 4 design properties, no custom CSS). 4) Move the on-click action onto the row. 5) Run mx check, then smoke and a by-eye look at the page. 6) Record the decision and update this entry.
- evidence: PFEP (detector only, no repair run yet); dojo-successors.tsv row (research 2026-10-08); B6-4. No field result.
- status: idea
- cards: generic-dojo

### RA-2 Container widget with a removed library call, no React build (DropdownContainer)
- topic: widget-gone
- match: dropdowncontainer
- trigger: replacement_check row R35 or R36 / remedies key `react19-dropdowncontainer` (findDOMNode, Mendix 11.6+ React 19).
- why: the widget calls findDOMNode, removed in React 19; the private publisher has no build, and the container holds buttons or text, which a Combo box cannot.
- options: keep on the source version (S, ends with its support window) | replace by Pop-up menu where the container opens a list of actions (M) | replace by Combo box where it only offers one choice (M) | ask the owner for a React 19 build (S, date not ours) | rebuild as a small pluggable widget (M)
- recommendation: Pop-up menu per instance, driven by a script, not by hand.
- effort: M
- recipe: 1) dump each instance (ddc_dump: caption, items, actions, confirmation, parameter mappings). 2) Generate the Pop-up menu with ddc_to_popup. 3) `mxcli describe` drops ConfirmationInfo, parameter mappings and Data grid 2 columns without an attribute: re-set these from the dump (RT-7). 4) mx check, build, smoke, by-eye screens. 5) Keep the old widget out of widgets/ afterwards.
- evidence: notif RT r2: 19 instances, smoke and screens PASS, menu opens, Edit works (RT-7, RT-10); the move needs a unit-level tool, MPR v2 only so far.
- status: proven
- cards: react19-dropdowncontainer

### RA-3 Widget that bundles its own React (3D Viewer, react-loading 2.x)
- topic: widget-gone
- match: viewer3d|3dviewer
- trigger: replacement_check R36 (bundled react-loading, React 16 copy; error #525 on React 19); remedies key `react-bundled-viewer3d`.
- why: the widget loads platform React but renders its spinner with a bundled React 16 copy; React 19 throws. Only some versions are licensed, 5.3.0 is no fix.
- options: install 3D Viewer 7.1.2 or another licensed version after R36 passes (S, licence) | patch the bundled spinner on the kept package (S, edits a licensed vendor file, not shipped) | hide the 3D panel behind a visibility condition (M) | stay on the source line, whose client is React 18.2.0 (S)
- recommendation: a version that R36 clears; else stay on 10.24 until one exists.
- effort: S
- recipe: 1) run R36 against the candidate mpk FIRST (`--accept FILE` for a patched one). 2) `mx update-widgets`, mx check, build. 3) Probe the page that holds the viewer in a browser (the crash is at render). 4) If none clears: hide the panel with a visibility condition and record the feature loss.
- evidence: MC (Asset Console 11.12.6): V3D-1 to V3D-5; patch proven on mock data.
- status: tried once
- cards: react-bundled-viewer3d

### RA-4 Pluggable-widget properties reset under an unchanged widget id
- topic: widget-gone
- match: update-widgets|MxDock|properties? reset
- trigger: nothing detects it before the build (AM-U2, backlog #29); seen as a lost caption, child widget or header setting after `mx update-widgets`.
- why: the new widget version redefines a property; `update-widgets` resets it silently and mx check flags only required ones. mxcli has no registry for some widgets (MxDock 11: Properties (0), AM-U8), so the fix is a direct model edit.
- options: keep the old widget version (S, pinned widgets drift from the module) | re-set the properties by hand or direct model edit from a before-dump (M) | rebuild the area with platform widgets (L)
- recommendation: dump the properties of each used instance before the update, re-set afterwards from the dump.
- effort: M
- recipe: 1) Before `update-widgets`, dump every property of each instance of the widget (mprmodel). 2) Update. 3) Dump again, diff by instance. 4) Re-set each lost value (mxcli where the registry has the widget, a direct model edit where not). 5) By-eye screen of one page per widget. 6) Add the pair to the report.
- evidence: AM (Academy run): 30 Link captions, a lost child widget, MxDock header settings; AM-U2 backlog, AM-U8 closed. No automated diff yet.
- status: idea
- cards: none

---
## Topic 2: Atlas 3 to Atlas 4
Atlas Core 4 swaps SASS variables for CSS variables and renames the layout helpers. Own layouts copied from Atlas 3, vendor theme
files edited in place, and role-less Atlas_Core are what breaks. Rule of this topic: rebuild from the Atlas 4 original and use
design properties; no compat stylesheet, no Atlas 3 pin on Mendix 11 (decision 14 Oct, research/design-2026-10-14/README.md).

### RA-5 Custom top bar or layout copied from Atlas 3
- topic: atlas
- match: atlas_?topbar|derived layout|flexcontainer|top.?bar layout
- trigger: smoke or screens regression on the layout; `Class:` tokens such as `flexcontainer`, `topbar-content`, `justify-content-between` on an own layout; (planned) theme_clash.py classes layer, BACKLOG #11 (PR-F20).
- why: Atlas 4's Atlas_TopBar is `topbar-wrapper` (grid `1fr auto 1fr`) with no `flexcontainer` helpers; the Atlas 3 copy keeps names that no longer exist, so nothing pushes the right slot and the menu is not drawn.
- options: keep Atlas_Core 3.x on 11 (S, unsupported pairing, blocks role mapping and newer DataWidgets) | compat stylesheet with the old helper names (S, keeps Atlas 3 names alive, restyles Atlas 4 widgets) | fix classes in the copy: `Style: 'flex: 1;'` plus `justify-between` / `justify-end` (S, still an Atlas 3 skeleton) | rebuild from the Atlas 4 top bar (M, look changes, needs visual sign-off)
- recommendation: rebuild from the Atlas 4 top bar with design properties only (owner decision 14 Oct).
- effort: M
- recipe: 1) describe the Atlas 4 Atlas_TopBar and the own layout. 2) Create the own layout again from the Atlas 4 one (brand | menu | right slot); move title, help icon, profile picture and Sign Out into the slots. 3) Set look through design properties only (row-center, hide-icons, hide-phone and so on); no custom SCSS. 4) Point the pages' layout at the new one, delete the copy. 5) Re-baseline the journey that clicked a layout widget (scope it to `.region-topbar`). 6) by-eye screens, visual sign-off.
- evidence: PR (Purchase Request): R19 report (root cause, three repair routes), run R22/R23 rebuilt the top bar from the Atlas 4 top bar with design properties only; FIELD-RUNS PR rows 2026-10-19. Result of the rebuild itself is not recorded in this file.
- status: tried once
- cards: atlas-sr-only-base

### RA-6 Vendor theme file edited locally, replayed onto the new package
- topic: atlas
- match: themesource|vendor theme|replay.{0,20}patch|hero|navbar|min-height
- trigger: localedits.json FILES-EDITED rows in `themesource/atlas_*`; the replay patch (`replay/<Module>.patch`) selectors.
- why: the edit was tuned to the old package's CSS (`min-height:500%` on `.region-topbar .mx-navbar`; hero image `top:-200%`); the new package or a widget update (Image 1.5.0 `.mx-image-viewer{height:100%}`) changes the parent, so the same edit now hides the element.
- options: replay as is (S, repeats the break) | restore the package file and move wanted styling to the app's `theme/web/main.scss` (S) | express it with design properties of the widget (M, best) | hand off
- recommendation: drop the replayed vendor edit, use the widget's design property (for the hero: Image fit Cover).
- effort: S
- recipe: 1) restore the package file from the new package. 2) For each removed hunk ask what it did; find the design property or Atlas 4 default that does it. 3) Anything left goes to the app's own theme folder, never a vendor file. 4) Build, by-eye screen of the pages that carry the class.
- evidence: PR: R19 root cause A (hero not visible and not clickable, Image 1.5.0 vs the replayed `top:-200%`); repair R1 proposed. Not proven by a second app. TOUR (batch-templates, 2026-10-22): proposal item P-1 matched on Atlas_Core 3.0.2 FILES-EDITED rows (2 scss files, 3 font/image files under themesource); recipe not run, no decision taken. The match is loose: this entry's recommendation (hero Image fit) does not describe those edits. COLLAB (batch-templates): proposal item P-3 matched on DataWidgets 2.3.0 FILES-EDITED row (1 themesource file); recipe not run, no decision taken; loose match again (the recommendation text is about the hero image). CMPL (batch-templates): proposal item P-6 matched on PushNotifications 5.3.0 FILES-EDITED rows (4 themesource files); recipe not run, no decision taken; loose match (hero image text).
- status: tried once
- cards: none

### RA-7 Renamed or dropped Atlas helper classes on own pages
- topic: atlas
- match: justify-content-|helper class|GONE .*class|renamed class|class(es)? .*(gone|dropped)
- trigger: (planned) theme_clash.py classes layer rows `GONE <class>` / `CHANGED <class> lost <prop>`; until then a visual regression after the Atlas step.
- why: `justify-content-between` / `-end` became `justify-between` / `justify-end`; `.flexcontainer` lost `flex:1` and overflow. The model still builds, so only the look breaks.
- options: rename per Atlas 4 synonym (S) | compat stylesheet (S, keeps old names alive) | replace the container by an Atlas 4 layout grid / design property (M)
- recommendation: replace by the design property of the Atlas 4 container; rename only where no design property exists.
- effort: S
- recipe: 1) list the `Class:` tokens of own layouts, pages and snippets (mxcli DESCRIBE or mprmodel.py). 2) For each, check it exists in the new compiled CSS. 3) Replace gone ones by design properties; else rename per the Atlas 4 name. 4) by-eye screens.
- evidence: PR R19 (class table, the compat stylesheet route is what D17 took and is "to prove"); instrument is backlog.
- status: idea
- cards: none

### RA-8 Atlas_Core without roles (CE2729 on every microflow of the module)
- topic: atlas
- match: CE2729|atlas_core.{0,40}role|no roles defined in module
- trigger: mx check CE2729 (names only one role); rolecheck.py lists every unmapped role (the others fail at runtime with HTTP 560).
- why: Atlas_Core 3.21 and later define module roles; app user roles that map none cannot call `DS_Account_CurrentUser`.
- options: keep Atlas_Core below 3.21 (S, blocks the 11 line) | map roles by script (S) | hand-map in Studio Pro (S)
- recommendation: map by script from rolecheck proposals, rerun rolecheck to exit 0.
- effort: S
- recipe: 1) `rolecheck.py --json` proposals. 2) `bin/repair/map_roles.py` emits `alter user role <R> add module roles (Atlas_Core.User)` plus Atlas_Core.Administrator for admin holders; dry run. 3) mxcli exec, rolecheck rerun (exit 0). 4) write the mapping table into the report.
- evidence: PR repair rows (repair-rows.md, row 8 add-on); rolecheck control `rolecheck-unmapped-catch`. Script keyword form to verify against mxcli.
- status: tried once
- cards: none

---
## Topic 3: Dojo client to React client
Mendix 11 still runs the Dojo client and advises the React client; Mendix 12 removes Dojo. Per widget package dojo_report.py says
ready / delete / can move / can't move / not researched. Clear what blocks on 11.x before any Mendix 12 attempt.

### RA-9 Dojo widget with a React successor (can move)
- topic: dojo
- match: (?s)^(?!widget (?:html ?snippet|snippetjs)).*(?:newer-pluggable|dojo.{0,40}can move)
- trigger: dojo_report.py "can move" row; dojo-successors.tsv status newer-pluggable, successor or platform.
- why: the package is Dojo-only, but a pluggable version or a platform widget does the job; the swap changes property names and sometimes the look.
- options: keep (S, advisory on 11, blocking on 12) | swap to the successor (S-M) | hand off
- recommendation: swap to the successor named by the row.
- effort: M
- recipe: 1) take the successor from dojo-successors.tsv; read its properties. 2) install the successor module, add it to the page next to the old widget, copy the property values. 3) delete the old widget and package. 4) mx check, smoke, by-eye screens.
- evidence: B6-4 (dojo_report.py, dojo-successors.tsv, 45 rows researched 2026-10-08); widgets.md for the chart widgets swapped in T3. No count of apps.
- status: tried once
- cards: generic-dojo

### RA-10 Dojo widget with no React path (can't move)
- topic: dojo
- match: dojo.{0,40}(can.t move|not researched)|none-found|core-unsupported
- trigger: dojo_report.py "can't move" or "not researched"; remedies key `generic-dojo`.
- why: no pluggable version and no platform widget; Mendix 12 removes the client.
- options: stay on 11 with the Dojo client (S, until the 11 LTS window ends) | rebuild as a pluggable widget (L) | rebuild the feature with platform widgets (M-L) | drop the feature (S)
- recommendation: stay on 11 and schedule the rebuild when the Mendix 12 move is decided; do not rebuild for an 11 target.
- effort: S
- recipe: 1) decision recorded with the date the choice must be revisited. 2) For the rebuild: write down what the widget does on each page (properties, events) before touching it. 3) Prefer platform widgets; a pluggable widget only where no platform widget fits. 4) Never remove the old package before the replacement passes smoke.
- evidence: B6-4; RA-1 is the first worked instance (not run yet).
- status: idea
- cards: generic-dojo

### RA-11 Widget package that calls the removed client logger (mx.logger)
- topic: dojo
- match: mx\.logger|logger shim|widget-mxlogger|replacement: R38
- trigger: replacement_check R38 (`mpkjs:\bmx\.logger\b`, widgets a page uses); remedies key `widget-mxlogger`; the scanner misses this.context() calls inside .mpk packages (AM-M4, backlog #25).
- why: the 11.12 client no longer defines mx.logger; a widget that calls it throws, so the page never renders.
- options: newer widget version without mx.logger, checked with R38 first (S) | local shim defining mx.logger (no-op debug/info, console warn/error) in the theme or index.html (S, proven in a browser only) | rebuild the part on platform widgets (M) | fork the widget (M) | stay on 10.24 (S)
- recommendation: newer version if R38 clears it; else the shim, with a recorded owner and a removal date.
- effort: S
- recipe: 1) R38 on the candidate mpk. 2) If none: put the shim in the app's own theme `index.html` hook before the widget loads; keep it out of vendor files. 3) Smoke the page that holds the widget; walk one journey through it. 4) List the shim in the report as a debt item.
- evidence: QI (Quality Inspection): QI-3, QI-4 (LVC 1.3.16 calls it in 6 files); shim proven in a browser only (QI A37); AM-M4 and AC-9 for the scanner gap.
- status: tried once
- cards: widget-mxlogger

### RA-12 Dojo JavaScript in own actions (dojo, dijit, mx.modulePath, mx.ui.openForm)
- topic: dojo
- match: mx\.ui\.openform|dijit|dojo/|mx\.modulepath|javascript action.{0,30}dojo
- trigger: replacement_check R8 js clause / R19.
- why: dojo globals are unavailable in the React client; Mendix 12 removes Dojo.
- options: rewrite with Client API / mx.data (M) | replace by a nanoflow with Show Page (S) | keep until 12 (S)
- recommendation: Show Page nanoflow for openForm; Client API for the rest.
- effort: S
- recipe: 1) grep the javascriptsource of own modules for the clause. 2) Replace openForm by a nanoflow Show Page action. 3) Replace dojo helpers by plain DOM or Client API. 4) Smoke the pages that call the action.
- evidence: replacements.tsv R8, R19, R24 (research only). No run applied it.
- status: idea
- cards: none

### RA-13 Mendix 12 look-ahead: what to clear on 11 first
- topic: dojo
- match: r24|horizon
- trigger: replacements.tsv R24 (rows R4, R6, R8, R19) and dojo_report.py "blocks 12" lines.
- why: Dojo client removal is confirmed for 12; Document Templates and Deep Link removal in 12 is UNVERIFIED.
- options: clear R8 and R19 on 11.x now (M-L) | wait for the 12 release notes (S, risk of one big step)
- recommendation: clear the confirmed blockers (RA-1, RA-9, RA-10, RA-11, RA-12) on 11.x; re-check the unverified ones against the 12 notes.
- effort: L
- recipe: 1) one list of all dojo_report "can't move" and R8/R19 hits. 2) Per item an RA entry and an owner. 3) Re-run the report to 0 before any 12 trial.
- evidence: R24 (checked 2026-10-07, no Studio Pro 12 release notes then).
- status: idea
- cards: generic-dojo

---
## Topic 4: module API breaks that force a redesign
A module major changes the data model or removes the API the app's own pages and flows call. The build passes or fails on a
symptom (CE1613, CE6779); the redesign is in what carries the data.

### RA-14 Workflow Commons 4: comments move onto System.Workflow
- topic: module-api
- match: workflowcommons|workflowview|workflowcomment|CE1613.{0,60}workflow
- trigger: CE1613 naming `WorkflowCommons.SUB_WorkflowView_FindOrCreate`, `ACT_WorkflowCommentHelper_SaveNew.WorkflowView` or association `WorkflowComment_WorkflowView`; pre-build: `show callers of ...FindOrCreate` on the OLD model; idcheck REMOVED of that association.
- why: 4.x drops WorkflowView as the carrier; nothing in 4.x creates it. Keeping it as carrier passes mx check and empties the panel.
- options: keep 3.x/4.2 with Atlas 3 (S, ends with Atlas) | rebuild comments on System.Workflow as the publisher's snippet does (M) | replace the own snippet by Snip_Workflow_CommentsAndAttachments where it was a copy (S-M) | hand off
- recommendation: carrier = System.Workflow, publisher snippet where the own one was a copy.
- effort: M
- recipe: 1) `DS_GetWorkflow_FromUserTask($WorkflowUserTask)` = retrieve over System.WorkflowUserTask_Workflow. 2) Snippet parameter WorkflowView becomes System.Workflow; list source `database from WorkflowCommons.WorkflowComment where WorkflowComment_Workflow = $Workflow sort by changedDate desc`; submit via `ACT_WorkflowCommentHelper_SaveNew(WorkflowCommentHelper, Workflow = $Workflow)`. 3) Own flows retrieve the Workflow from their context. 4) Change only sources and actions (`set ... on <widget>`); `replace` or `create or modify snippet` re-authors every binding. 5) Journey per task role: add comment, visible on reload, visible on the next role's task page. Refuse a carrier entity with zero create sites in the NEW model; use a database/association source, not a microflow (it skips the read rule).
- evidence: PR: repair-rows.md row 22, fix-wc7/fix-wc8, R14-R18, R18 caught it only by the role journey. One app.
- status: tried once
- cards: none

### RA-15 Workflow Commons 4: completed-task history is not migrated
- topic: module-api
- match: UserTaskView_Migrate|migration.step|REMOVED.{0,40}workflow
- trigger: release_impact migration-step rows (24 for WorkflowCommons 4.0.0, dropped by the default type filter); idcheck REMOVED with the reason "the publisher's migration microflow moves the data".
- why: 4.x ships only `ASU_UserTaskView_Migrate` (UserTaskView to WorkflowEndedUserTask); nothing calls it from the app's AfterStartup.
- options: call the migration from the app's AfterStartup once and verify counts (M) | accept the history loss with a recorded decision (S) | export the history before, import after (L)
- recommendation: call it and compare counts; an approval must name the migration flow and its caller.
- effort: M
- recipe: 1) include migration-step rows in release-impact. 2) Name the flow and its caller in the approval. 3) Add the call to the AfterStartup, run on a data copy, compare row counts old vs new. 4) Write the count into the report.
- evidence: PR repair-rows.md cross-cutting finding; open finding there. Not applied.
- status: idea
- cards: none

### RA-16 Legacy MendixSSO to OIDC
- topic: module-api
- match: mendixsso|sso module|openid
- trigger: replacements.tsv R3 (`module:MendixSSO`), R2 for OIDC shape; release-impact deprecation rows.
- why: MendixSSO is deprecated; the user specialisation lives in the module's tables, and the IdP is an organisation decision.
- options: keep the module (S, until it leaves the Marketplace) | OIDC SSO with the IdP (M-L) | SAML / LDAP / local credentials (M) | OIDC Provider for custom SSO
- recommendation: OIDC with the IdP once the IdP decision is made; keep until then.
- effort: L
- recipe: 1) settle the IdP with the owner of identity. 2) Install OIDC with UserCommons. 3) Map the MendixSSO user specialisation rows to the new users (match on the stable id, dry run, count). 4) Switch login pages and the after-startup flow. 5) Journey per role. Do not delete the old module before login works for every role.
- evidence: R3 research only; MendixSSO seen in fsm, kanban, pfep (kept); AM-T4/AM-T9 are harness items on an SSO app. No migration run.
- status: idea
- cards: none

### RA-17 Document Templates (Generate Document action) removed
- topic: module-api
- match: documenttemplate|generate document|GenerateDocumentAction
- trigger: replacements.tsv R6 (`type:DocumentTemplates$DocumentTemplate`, `Microflows$GenerateDocumentAction`).
- why: removed after Studio Pro 10.24; output layout is defined per template, not as a page.
- options: keep on 10.24 (S) | PDF Document Generation from pages (M-L) | partner module for Word/RTF/ODT (M) | hand off
- recommendation: PDF Document Generation per template; compare output with the old documents.
- effort: L
- recipe: 1) list templates and the flows that generate them. 2) One page per template as the PDF source. 3) Replace the action. 4) Compare output side by side with a saved old document.
- evidence: R6, R24 research only.
- status: idea
- cards: none

### RA-18 Legacy scheduled events and queue modules
- topic: module-api
- match: scheduled ?event|processqueue|queue module|MicroflowScheduledEventManager
- trigger: replacements.tsv R20 (ScheduledEvent.Schedule=null), R28.
- why: a legacy scheduled event stops the runtime from starting; the queue modules are deprecated.
- options: repeating scheduled event with a Schedule (S) | Task Queue for queued work (M) | hand off
- recommendation: repeating scheduled events for timed work, Task Queue for queued work.
- effort: M
- recipe: 1) list events and queue uses. 2) Recreate each with a Schedule; check time zone and overlap. 3) Move queue modules to Task Queue, drain the old queue first.
- evidence: R20, R28 research only; no field app held them.
- status: idea
- cards: none

### RA-19 HTML / JavaScript Snippet widgets on the React client, judged per snippet
- topic: dojo
- match: ^widget (?:html ?snippet|snippetjs)
- trigger: dojo_report.py "can move" row for `HTMLSnippet.widget.HTMLSnippet` or `snippetjs.widget.snippetjs` (dojo-successors.tsv status successor); bin/proposal.py lists these two packages as section-3 items because the successor depends on what each snippet holds, not on the widget.
- why: both snippet widgets are Dojo-only; an app that uses them throughout (large JavaScript volume, high UX impact) has no one-for-one swap. HTML Element covers markup only; script in a snippet runs against the Dojo page DOM and must move to a JavaScript action or a widget. Mendix 11 still runs the Dojo client, so this is a Mendix 12 deadline, not an 11 blocker.
- options: pure HTML to the HTML Element widget (S per snippet) | JavaScript with behaviour to a JavaScript action called from a nanoflow, triggered by the Events widget (M per snippet) | DOM-heavy or reusable UI to a pluggable (React) widget (L per snippet) | keep on the Dojo client for now (S, until Mendix 12)
- recommendation: classify every snippet first; HTML-only to HTML Element, JS-light to a JavaScript action behind Events, JS-DOM to a pluggable widget when it is reused or else rebuilt with platform widgets; keep on the Dojo client on an 11 target and schedule the rest before Mendix 12.
- effort: M
- recipe: 1) Inventory: for each page, snippet and layout count the snippet widgets, read each one's content from the model (a page dump such as mxcli describe prints the widget without its content; read the widget's text property), noting content type and Refresh on context change and classify it HTML-only (markup, no script tag, no on-event attribute), JS-light (a few statements that read or set a value, call a service, open a URL or log) or JS-DOM (queries or mutates elements, injects scripts, loads a library, listens to events). Write the table: page, count, class. `bin/jquery_classify.py` does the lexical part: point it at the snippet contents (a JSON list of name and content), the `javascriptsource/` of own modules and the theme JS; it prints the class per unit and, for jQuery (`$(`, `jQuery`, `$.ajax`, `.on(`, `.click(`, `.show/.hide/.toggle`, `.addClass/.removeClass`, `.val(`, `.animate`, plugin calls), the count per purpose and which need code: visibility and classes become conditional visibility or dynamic classes, event handlers become the Events widget or an on-change nanoflow, `$.ajax` becomes a microflow REST call, field values become attribute binding, animations become CSS or Atlas, plugins become a Marketplace pluggable widget, the rest is a plain-JS JavaScript action or a React widget (only plugins and the rest need code). The denominator is the count of snippet widgets in the model; a snippet not in the table is not done. jQuery that edits a page the React client renders is undone at the next re-render: a page that still loads is not a page that works, so every converted behaviour gets its own journey. The classifier also flags a snippet with Refresh on context change = No that binds handlers (they bind once and are lost when the page redraws), a click made by code (call the button's nanoflow, or NanoflowCommons Set Storage Item for a hidden store button) and a function whose only calls are commented out (likely dead; confirm, then drop). `mx check` is silent about snippets, so only the inventory finds them. 2) HTML-only: add an HTML Element widget with the same markup, delete the snippet. 3) JS-light: write a JavaScript action (Client API, no dojo or dijit, see RA-12), call it from a nanoflow, trigger the nanoflow from the Events widget (on load / on interval). 4) JS-DOM: reusable UI becomes a pluggable widget; page-specific scraping becomes platform widgets and a class on the container; a third-party library goes behind a pluggable widget, never a script tag. 5) On an 11 target keep what is not converted on the Dojo client and record the date to revisit (Mendix 12). 6) Smoke every page that held a snippet, then walk one journey over each converted behaviour: the snippet's effect is often invisible to the page check.
- evidence: dojo-successors.tsv rows HTMLSnippet and snippetjs (docs.mendix.com React client guide, HTML/JavaScript Snippet page); RA-9, RA-12; replacements.tsv R8; research/snippet-oidc/proof-snippet.md: a public showcase app with 28 identical JS-DOM snippets, convert, detect, propose and the recipe applied and `mx check`ed (5 errors before and after, none a snippet); no build, no screen comparison, no gate, so the behaviour is not measured.
- status: idea
- cards: generic-dojo

### RA-20 OIDC SSO module version upgrade across its breaking versions
- topic: module-api
- match: ^(?:module|re-architecture) (?:R2\b.*\boidc\b|oidc\b)
- trigger: replacements.tsv R2 (`modver:OIDC:<3.0.0`, OIDC without UserCommons, `startup:^OIDC\.Startup$`, `ref:Administration.Account@OIDC`); not MendixSSO to OIDC, that is RA-16.
- why: the OIDC module breaks at several versions and the build errors do not say which step is missing. 3.0.0 adds UserCommons as a dependency and the OIDC.Startup after-startup microflow becomes mandatory; 3.1.0 renames it OIDC.ASU_OIDC_Startup (the old name in the app settings is then a dangling reference and nobody authenticates); 4.0.1 and 4.1.0 replace Administration.Account by System.User, so custom token-parsing microflows that use Administration.Account stop compiling; 4.2.0 no longer runs the UserCommons migration at startup (it moves to a dedicated microflow) and 4.2.1 removes it, so skipping 4.2.0 loses data; 4.4.0 drops the Encryption and Nanoflow module dependencies; 4.5.0 enables PKCE by default and removes the Anonymous module role. The 4.x line needs Mendix 10.12.10 or later; the 3.x line is the Mendix 9.24 line.
- options: stay on the last 3.x line while the app is on 9.24 or 10 (S) | step through the breaking versions to a Mendix 11 compatible 4.x (M) | rebuild the login on another provider (L) | hand off
- recommendation: step through the breaking versions in order; do not jump from below 3.0 straight to 4.x. Target the newest version the target Mendix supports (4.1.1 for 10.21.0 and Mendix 11, 4.5.0 and later need 10.24.0); the Marketplace lists OIDC SSO 5.0.0 and UserCommons 3.0.0, whose release notes the brain does not hold (it stops at 4.7.0 and 2.4.0): read them before choosing.
- effort: M
- recipe: 1) Read the installed version (R2 modver) and the app's Mendix version; run `bin/localedits.py --module OIDC --mxcli-diff` BEFORE any update and list every flow that differs from the published package (in the field template: three claim-handling microflows SUB_CreateOrUpdate_UserProvisioning, SUB_HandlingClaims, handleAuthorizationCode and the nanoflow ACT_StartWebSignIn, i.e. the code that decides who may log in, plus six pages and Snip_Login_Button); `bin/stepupdate.sh` stops on logic edits and nothing is forced, so the owner decides: keep the module, or save the edits (`--save-edits`) and port them by hand after the update. A cross-version diff is refused (UNKNOWN), so run it on the version the module was installed at, before the convert. A project below 10.24 takes the 10.24 rung first (11.12.5 refuses to open a 10.15 project). List the other customisations: the after-startup setting, custom token-parsing microflows (prefix OIDC_CustomUserParsing or custom ATP), snippets from the module on own pages, and whether the app relies on the module's Anonymous role. 2) Before each module import delete the old module's Java libraries from userlib (the release notes list this step for 1.0.1 to 3.5.0 and 4.2.0): leftover jars give duplicate-class errors at start. 3) Below 3.0: update to 3.x. Without it the module's own microflows fail the check on missing UserCommons entities: import UserCommons 1.x; set the after-startup microflow to OIDC.Startup; assign UserProvisioning to each existing IdP configuration; replace Snip_Login_Automatic by Snip_Login_Button (removed in 3.0.1). 4) To 3.1 or later: set after-startup to OIDC.ASU_OIDC_Startup (error: microflow OIDC.Startup not found, or the app starts and no IdP is provisioned). 5) To 4.0.1 or 4.1.0: replace Administration.Account by System.User in your own token-parsing microflows (the check fails on the removed Administration.Account member; the error text is the symptom, the module is the cause); UserCommons 2.x goes with 4.x. 6) Go to 4.2.0 first, run the UserCommons migration microflow it provides (_USE ME, Migration) on a data copy, compare user counts, only then move on to 4.2.1 or later. 7) To 4.5.0 or later: UserCommons 2.3.0 or later; the IdP must support PKCE (or PKCE is switched off in the client configuration); if the app used the Anonymous role as role-based home page or sign-in page, set both to none first, then re-check landing pages. 8) After each step: mx check clean, start clean, login page loads. 9) At the end validate authentication (login at the IdP, new and existing user), authorization (role from the token, default role), redirects (return URL with and without query parameters, deep link into a page), session handling (sign out, session timeout, second tab). IdP flows need a real IdP; without one say not measured.
- evidence: brain oidc-sso (Marketplace 120371) and usercommons (223053) release notes; docs.mendix.com/appstore/modules/oidc upgrade sections; replacements.tsv R2; research/snippet-oidc/proof-oidc.md: a public starter app on OIDC 3.1.0 (no public template holds one below 3.0), converted to 10.24, then stopped at step 1 by stepupdate on 4 logic edits in the module; nothing after that ran, the IdP side is not measured.
- status: idea
- cards: none
