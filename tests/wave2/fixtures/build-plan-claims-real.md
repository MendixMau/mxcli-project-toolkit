# Build Plan — SampleDashboards

**Module:** `DashboardPublishing` (one module + folders, CONFIRMED Stage 3).
**App:** `app/SampleDashboards.mpr`, Mendix 11.12.1, created 2026-08-31 with `--theme none`.
**Row kinds:** `BRIEF` · `BUILD` · `PROVE` · `RUN` · `HARNESS`. One number sequence, dependency
ordered, never reused. A row may say `not built`; it may never be absent.

Marketplace/bundled dependencies already present in the created app (verified via `SHOW MODULES`,
not assumed): `Administration` 4.3.2, `Atlas_Core` 4.1.3, `Atlas_Web_Content` 4.1.0,
`DataWidgets` 3.5.0, `NanoflowCommons` 6.0.0, `WebActions` 2.11.0. Nothing further to import.

---

## Phase 1 — Foundation (security, settings, domain)

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 1 | BRIEF | Check `architecture/modules/DashboardPublishing/module-brief.md` covers phase 1 | brief exists and is current | — | `module-brief.md` | built |
| 2 | BUILD | `01-module-and-settings.mdl` | Module `DashboardPublishing`; project languages EN + TH; default EN | 1 | `project-settings.md`, `organize-project.md` | built |
| 3 | BUILD | `02-security-roles.mdl` | Module roles Owner/Viewer/Administrator + matching user roles; security level Production | 2 | `manage-security.md`, `security-is-not-a-later-script.md` | built |
| 4 | BUILD | `03-entities.mdl` | `Dashboard`, `DashboardVersion` (extends System.FileDocument), `DashboardViewer`, all three associations, **and their access rules in the same script** | 3 | `mdl-entities.md`, `system-module.md`, `security-is-not-a-later-script.md`, `xpath-constraints.md` | built |
| 5 | PROVE | `./mxcli -p app/SampleDashboards.mpr -c "SHOW SECURITY MATRIX IN DashboardPublishing"` | every entity carries rules for all three roles; no entity without access | 4 | `security-is-not-a-later-script.md` | built |

```
claims:
  F001/domainEntities/Dashboard/attributes/* (3)
  F001/domainEntities/Dashboard/associations/Dashboard_Owner
  F002/domainEntities/DashboardVersion/attributes/* (4)
  F002/domainEntities/DashboardVersion/generalisation
  F003/domainEntities/DashboardViewer/attributes/Email
  F003/domainEntities/DashboardViewer/associations/DashboardViewer_Dashboard
  F005/domainEntities/Account (Administration, not created here)
  F005/businessRules/BR020 (requireSelf → owner XPath)
  F003/businessRules/BR012 (viewer grant conveys read on every version)
```

## Phase 2 — Logic

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 6 | BRIEF | Check the brief covers phase 2 | brief current for logic rows | 5 | `module-brief.md` | built |
| 7 | BUILD | `04-common-access.mdl` | `SUB_Access_RequireOwner`, `SUB_Access_RequireViewAccess` | 5 | `write-microflows.md`, `learned-microflow-patterns.md`, `learned-mdl-preflight.md` | built |
| 8 | BUILD | `05-dashboard-microflows.mdl` | `GET_Dashboard_ListForOwner`, `ACT_Dashboard_Create`, `VAL_Dashboard`, `GET_Dashboard_Detail`, `ACT_Dashboard_Delete` | 7 | `patterns-crud.md`, `validation-microflows.md` | built |
| 9 | BUILD | `06-version-microflows.mdl` | `ACT_Version_Upload`, `VAL_Version_Upload`, `SUB_Version_NextNumber`, `GET_Version_ListForDashboard`, `ACT_Version_Delete` | 7 | `patterns-crud.md`, `system-module.md` | built |
| 10 | BUILD | `07-viewer-microflows.mdl` | `ACT_Viewer_Add`, `VAL_Viewer_Email`, `ACT_Viewer_Remove` | 7 | `patterns-crud.md`, `regular-expressions.md` | built |
| 10b | BUILD | `07b-list-microflows.mdl` | The four read-side flows rows 8/9/10 each promised and none delivered: `GET_Dashboard_ListForOwner`, `GET_Dashboard_Detail`, `GET_Version_ListForDashboard`, `GET_Viewer_ListForDashboard`. Caught by counting `SHOW MICROFLOWS` (12) against what rows 8–10 claim (16), not by any gate — `mxcli check` and the mxbuild gate are both perfectly happy with a microflow nobody wrote | 7 | `patterns-crud.md` | built |
| 10c | BUILD | `07c-created-at-and-list-fix.mdl` | `CreatedDate` enabled on `Dashboard` and `DashboardViewer` so the source's `ORDER BY created_at` survives the port, plus both entities' access rules rebuilt whole (preflight rule 14) | 10b | `mdl-entities.md`, `xpath-constraints.md` | built |
| 11 | BUILD | `08-viewing-microflows.mdl` | `GET_Version_ViewContext`, `GET_Version_Content`, `JA_ReadFileDocumentAsText` (ruling R9), and the DashboardVersion security rebuild that lets a listed viewer read `Contents` at all | 7 | `write-microflows.md`, `java-actions.md` | built |
| 12 | PROVE | `./mxcli check` on every phase-2 script with `--references`, then `bin/exec.sh` mxbuild gate | **7 of 7 scripts PASS, 0 syntax errors, 0 reference errors; every script exec'd with `mxbuild: 0 errors`.** `SHOW MICROFLOWS IN DashboardPublishing` = 18, matching rows 7–11 item for item | 8,9,10,10b,10c,11 | `check-syntax.md`, `learned-detection-gaps.md` | built |

**Every phase-2 script uses `create or modify`, not `create`.** Row 12 re-checks the scripts
against the model they already built; with bare `create` each one fails "microflow already
exists", so the PROVE row could only ever pass before its own BUILD rows ran and fail
afterwards — a check that inverts on use proves nothing. Idempotent scripts also mean a
rebuild from an empty model is `for f in mdlsource/*.mdl; do ./bin/exec.sh $f; done`.

```
claims:
  F001/microflows/* (5)
  F002/microflows/* (5)
  F003/microflows/* (4)
  F004/microflows/* (3)
  F005/microflows/SUB_Access_RequireOwner
  F001/businessRules/BR001..BR004
  F002/businessRules/BR005..BR009
  F003/businessRules/BR010..BR013
  F004/businessRules/BR017
```

## Phase 3 — UI

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 13 | BRIEF | Check the brief covers phase 3 | brief current for page rows | 12 | `module-brief.md` | built |
| 14 | BUILD | `09-snippets.mdl` | `SNIPPET_LanguageSwitcher` | 12 | `create-page.md`, `translations.md` | not built |
| 15 | BUILD | `10-page-overview.mdl` | `Dashboard_Overview` — header, create form, dashboard list, empty state | 14 | `ui-preflight-pages.md`, `design-spacing.md`, `overview-pages.md` | not built |
| 16 | BUILD | `11-page-detail.mdl` | `Dashboard_Detail` — version table, upload form, viewer manager | 15 | `ui-preflight-pages.md`, `master-detail-pages.md` | not built |
| 16b | BUILD | The upload file picker — **BLOCKED, not built** | A working file input on `Dashboard_Detail`'s upload card | 16 | `create-page.md` | **blocked** |
| 17 | BUILD | `12-page-view.mdl` | `Version_View` — header, version label, access-checked `ViewerContext`; the preview frame itself is **blocked**, see row 20 | 16 | `ui-preflight-pages.md`, `custom-widgets.md` | built |
| 18 | BUILD | `13-navigation.mdl` | Navigation profile, **home page per role**, 3 demo users | 17 | `manage-navigation.md`, `manage-security.md` | built |
| 18b | BUILD | `Viewer_Home` (in `13-navigation.mdl`) | A landing page for a signed-in viewer — required because a profile's default home must be openable by every role | 18 | `manage-navigation.md` | built |
| 19 | PROVE | `project-bin/check-page-shell.sh` + `project-bin/page-fidelity.js` against each wireframe | **Shell gate: 3 pages across 21 files, 0 violations.** Fidelity: Dashboard_Detail **90%** (target met), Dashboard_Overview 57%, Version_View 23% — all three logged to `docs/PAGE-FIDELITY.tsv`, both shortfalls diagnosed below | 15,16,17 | `ui-preflight-pages.md` | built |

**Row 19's two sub-80% scores, and why neither is a page defect.** `page-fidelity.js` scores a
page's MDL against the literal text and classes of its wireframe. That works when a wireframe
draws structure; it degrades when a wireframe draws *sample data*, because a page that correctly
BINDS a value contains none of its text.

| Page | Score | Structural dimensions | What the misses actually are |
|---|---|---|---|
| Dashboard_Detail | **90%** | headings 3/4, actions 10/10, classes 33/35 | sample title/description; `.file-input` (row 16b); `.active` (Mendix marks its own selected row `mx-selected`) |
| Dashboard_Overview | 57% | headings 1/1, **classes 18/18** | the wireframe draws THREE sample cards; one correct gallery template can match at most 2/5 actions and 0/2 content |
| Version_View | 23% | headings 0/0, classes 6/7 | a nine-item denominator, of which two are bound sample values and one is `.lang`, which lives in a snippet the single-file scorer cannot see |

Every structural dimension the scorer measures reliably — the page column, the layout shell, the
one page title, the class vocabulary — is at or near full marks on all three, and the shell gate
is 0 violations. The next step for these two is a screenshot at Gate: UI (`ui-loop.md`), not more
MDL: there is no edit to the page scripts that would raise the number without inventing static
copy the design does not have.

**Row 16b is blocked and the block is structural, not a to-do.** MDL has no file widget —
`mxcli syntax page.widgets` lists every keyword it accepts and there is no
filemanager/fileuploader/imageuploader among them. The platform's pluggable FileUploader
parses but fails at exec with "no definition for widget
com.mendix.widget.web.fileuploader.FileUploader"; `mxcli widget init` extracts definitions
from the project's own `widgets/*.mpk` and found 42, and FileUploader is not one of them —
it is a Studio-Pro-bundled widget, counted among that command's "9 skipped (built-in)".
Clearing it needs Studio Pro or the `.mpk` dropped into `app/widgets/`, neither of which
exists in this container. Everything behind the picker is built and gate-clean; the upload
card ships with a labelled gap rather than a control that looks real and does nothing.

```
claims:
  F001/pages/Dashboard_Overview/sections/* (3)
  F001/pages/Dashboard_Detail/sections/* (4)
  F002/pages/Dashboard_Detail/sections/UploadForm
  F003/pages/Dashboard_Detail/sections/ViewerManager
  F004/pages/Version_View/sections/* (3)
  F005/pages/SignIn (Administration login page, configured not authored)
  design/wireframes/*.html binding rows (31 across 4 screens)
```

## Phase 4 — The custom widget (parallel track)

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 20 | BUILD | The sandboxed frame — **BLOCKED, not built.** No custom widget is needed: the platform's `com.mendix.widget.web.htmlelement.HTMLElement` renders an arbitrary tag with arbitrary attributes, so `tagNameCustom: 'iframe'` + a `sandbox` attribute + a `srcdoc` attribute IS the component. What is missing is a way to *write* it | iframe `srcDoc` + `sandbox="allow-scripts"`, **no** `allow-same-origin` | 17 | `custom-widgets.md`, `learned-mcp-patterns.md` | **blocked** |
| 21 | PROVE | Widget renders a known HTML fixture; DOM assert the sandbox attribute is present and `allow-same-origin` is absent | the security property is verified, not assumed | 20 | `testing-shape.md`, `measured-claims.md` | blocked by 20 |

**Why row 20 is blocked, with the probes that establish it.** A pluggable widget's `attributes`
is an OBJECT LIST, and mxcli v0.20.0's MDL grammar has no way to write one inside a
`pluggablewidget` block. Three forms were tested against the real model:

| Form | Result |
|---|---|
| `attribute a (attributeName: 'sandbox', …)` | parse error — `mismatched input 'attribute'` |
| `attributes { attribute a (…) }` | parse error — `mismatched input 'attributes'` |
| `item a (attributeName: 'sandbox', …)` | **parses**, `mxcli check --references` clean, then fails at exec: `item must be a direct child of navigationlist` |

The one keyword that parses belongs to another widget. Clearing this needs Studio Pro or an
MCP write session (`learned-mcp-patterns.md` — three co-equal write modes, and this is the case
the CLI mode cannot serve).

**What was deliberately NOT done.** `tagContentMode: 'innerHTML'` with `tagContentHTML` bound to
the HTML is a plain property, so it parses and would render the dashboard today — inside the
Mendix page, same-origin, where the uploaded document's JS could call client APIs as the
signed-in user. That is precisely the regression the Stage 3 decision rejected when it turned
down a plain iframe to a file URL. `Version_View` renders an explicit unavailable state instead:
the feature is visibly incomplete rather than invisibly unsafe.

Everything behind the frame is built and gate-clean — `GET_Version_ViewContext`,
`GET_Version_Content`, `JA_ReadFileDocumentAsText`, and the `ViewerContext` that already carries
the HTML to the page. The remaining change is one widget swap.

```
claims:
  F004/businessRules/BR014 (served unmodified)
  F004/businessRules/BR015 (sandbox is the boundary)
  F004/businessRules/BR016 (no-store/nosniff)
  fit-gap row 10 (the only Build-new item)
```

## Phase 6 — Cutover (Stage 7)

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 26 | BUILD | `16-cutover.mdl` | `JA_Cutover_ImportFromDump`, `ACT_Cutover_Import`, and the Administrator-only `Admin_Cutover` screen (dry run + import) | 25 | `java-actions.md`, `demo-data.md` | built |
| 26b | BUILD | `16b-cutover-accounts.mdl` | The account decision the import refuses to make for you | 26 | `manage-security.md` | built |
| 27 | PROVE | `bin/cutover-precheck.sh`, then the import, then OQL | **PRECHECK PASS** (1 referenced file, size and SHA-256 verified; 6 orphans listed). **Import: 1 dashboard, 1 version, 0 skipped.** Verified from the database: `Size` 105812 and `ContentHash` both match the dump exactly, `VersionCount` 1 written by the rollup, `NextVersionNumber` 2 carried | 26b | `verify-with-oql.md`, `testing-shape.md` | built |

```
claims:
  Stage-0 gate G3 (data carry-over baseline: pg_dump + its matching HTML files)
  Stage-0 gate G2 (retired old-lineage columns are NOT carried)
  F005/businessRules/BR020 (every carried dashboard has an owner)
```

**The precheck hashes; it does not just look.** `content_hash` is in the source schema because
the source app computed it on upload. Carrying files over without checking it would migrate
corruption silently and discover it when a viewer opens a broken dashboard months later. The
check costs a second. Full mapping, known gaps and the two defects the first run surfaced:
`docs/CUTOVER.md`.

## Phase 5 — Prove the app

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 22 | RUN | `./mxcli run --local` | app boots; home page renders for a demo Owner | 18,19 | `run-local.md` | not built |
| 23 | HARNESS | Playwright journey: create → upload → share → view as viewer | the end-to-end capability, per journey rung | 22 | `test-app.md`, `journey-proof.md`, `testing-shape.md` | not built |
| 24 | PROVE | `mxcli oql` assertions behind the journey | rows actually landed; the UI is not lying about the write | 23 | `verify-with-oql.md`, `learned-db-assertions.md` | not built |
| 25 | HARNESS | `project-bin/verify-module.sh DashboardPublishing` + `mxcli lint` | instrument-faulted kept apart from feature-failed; 0 P1 | 23,24 | `module-review.md`, `testing-shape.md` | not built |

```
claims:
  F001/useCases/UC001..UC003
  F002/useCases/UC004..UC005
  F003/useCases/UC006..UC007
  F004/useCases/UC008
  F005/useCases/UC009..UC010
```

---

## Pending decisions

**None blocking.** Every Stage 0–3 `✋` decision is CONFIRMED in `PROJECT.md`; the one open
`ASSUMED` (F002/Q2, atomic version-number allocation) is a build-time technique choice, not a
scope question, and row 9 is where it gets implemented and row 12 where it gets proven.

## Role-to-access table

| Element | Owner | Viewer | Administrator |
|---|---|---|---|
| `Dashboard` | CRUD, XPath owner = current user | Read, XPath: granted-viewer | Read |
| `DashboardVersion` | CRUD via owned dashboard | Read via granted dashboard | Read |
| `DashboardViewer` | CRUD via owned dashboard | none | Read |
| `Dashboard_Overview` | view | view (own list is empty) | view |
| `Dashboard_Detail` | view | no | view |
| `Version_View` | view | view | view |
| every `ACT_*` / `GET_*` microflow | execute | execute only the four read flows | execute read flows |
