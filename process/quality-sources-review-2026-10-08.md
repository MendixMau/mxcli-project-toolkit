# Quality-source review — 2026-10-08

Review of Mendix quality-tooling sources (Best Practice Recommender, QSM/AQM public docs, ATS public docs,
Menditect public docs, docs.mendix.com) against what the toolkit already enforces. Lintability was read from
the mxcli lint source and no rule has been probed on a real model. Scan quotes were paraphrased, thresholds
for QSM/Sigrid and Omnext rule text were not captured, and long pages were cut off, so "no source" means
"not captured". The 19 proposed rows are in `process/lint-backlog.md` (Batch 4); the section letters below
keep the original review's lettering.

## B. Already covered

| Practice | Source(s) | Covered by |
|---|---|---|
| Commit (and create/change-with-commit) inside a loop, batch at 1000 | aqm b1 MXP004/005, b6 #25; men S2 | CONV011 (stock); `microflow-loop-antipatterns.md`, `mdl-cookbook-microflows.md` |
| Retrieve / delete / REST / Java call inside a loop | aqm b6 #26-27; men S1 | LOOP001 (Batch 1, in-flight); backlog row 4 |
| Error handling on integration and Java calls | aqm b4; men S1; docs S1 | CONV013 (stock) |
| Avoid Continue error handling | docs S1 | CONV014 (stock); ERR001 (in-flight) |
| Always log the error, even when the process continues | aqm b4; men S1; docs S1, S2 | ERR001 (in-flight); backlog rows 1, 5, 6 |
| Calculated attributes: on pages, unused, in general | aqm b1 MXP001/002, b4, b6 #4; docs S4 | CONV017 bans them outright (stricter than MXP001/002) |
| Event handlers: use with caution | aqm b4, b6 #5; men S1 | CONV016 |
| Validation via VAL_ flows, not entity rules | docs S12; aqm b5 VAL_ | CONV015; backlog extra "VAL_ returns Boolean"; `mdl-cookbook-microflows.md` |
| Microflow size 25 elements / complexity | aqm b4; men S1, S22 | QUAL003 (25), CONV009 (15), QUAL001 McCabe |
| Annotate complex microflows (>10 activities or >2 decisions) | aqm b4; men S1 | UX002 (in-flight, threshold 8 activities); CONV012 split captions; QUAL002 docs |
| Unused / excluded documents | aqm b4; men S1 | QUAL004 orphaned elements; backlog row 3 (ACT_/page entry points) |
| Anonymous users enabled (MXS003) | aqm b2 | SEC004 guest access |
| Anonymous unconstrained read (MXS010), anonymous read on sensitive entities (MXS004, partly) | aqm b2 | SEC007; SEC008 for PII |
| Security overview complete / entity without access rules | aqm b4; men S1 | SEC001, MPR007 nav page roles, backlog row 11 |
| Strict mode / XPath on every access rule | aqm b6 #38 (adjacent) | SEC005, CONV007 |
| Module role mapping (each module role → one user role) | aqm b7 #10 (reverse direction) | CONV008; backlog row 10 |
| Naming: PascalCase entities/pages, ENUM_, page suffixes, booleans | aqm b5 | MPR001, CONV003, CONV004, CONV001 (see the SNIP_ conflict in F) |
| Folder organisation | aqm b5 Folders | CONV018; `module-folder-convention.md` |
| Domain model size per module, app size | aqm b4 App size | MPR003 per module (app-wide ceiling not checked, see C-29) |
| ACT_ flows delegate, page actions give feedback | aqm b5 page microflows | CONV010, CONV020 (shipped) |
| Data changes through microflows; business key | community perf, docs S3 | ARCH002, ARCH003 (shipped) |
| Cross-module data access, module coupling (QSM "architecture") | men S6/S7 | ARCH001; graph builtins; `module-dependency-review.md`, `layering-review.md` |
| Writes late in the flow (MXP014) | aqm b1; men S2 | `microflow-preflight.md` (not lintable, see C-30) |
| Secrets in constant defaults / exposed to client | aqm b7 #11-13 | `project-bin/constants-audit.sh` + `learned-constants-and-secrets.md` |
| Missing translations, required captions | docs S11 i18n | QUAL005, QUAL006 |
| Studio Pro warnings, consistency | aqm b4; men S1 | `mx check` in `bin/exec.sh` / gates |
| Overlapping activities, canvas layout | aqm b4 flow layout | MPR008, MPR011, `microflow-preflight.md` → Layout |
| Workflow enum branches carry an Empty outcome | docs S10 (adjacent) | `workflow-structure-rules.md` |
| Confirm before destructive action | docs S9 descriptive buttons (adjacent) | UX001 (in-flight) |
| Unit testing exists, test levels | ats S24-S26; men S10, S17 | `testing-shape.md`, `learned-db-assertions.md` |
| REST: log the response, then rethrow | docs S2 | `rest-integration-first-time-right.md` |

## C. Candidates (deduplicated, by priority)

Severity is `warning` for every proposed rule (lint-backlog rule 2). Rule IDs are placeholders.

| id | practice | sources | lintable | proposal | prio | notes |
|---|---|---|---|---|---|---|
| C-01 | Anonymous user role is the administrator role | aqm b2 MXS005 | yes: `project_security()` anonymous_user_role, admin_user_role, enable_guest_access | Rule **SEC010 AnonymousRoleHygiene** (security), check 1 of 3 | P1 | Mendix calls it "almost certainly a configuration error"; zero false-positive risk; one comparison |
| C-02 | Anonymous user role mapped to an Administration module role | aqm b2 MXS009 | yes: `user_roles()` is_anonymous, module_roles | SEC010, check 2 | P1 | Lets visitors manage accounts (also covers most of MXS007, which is not lintable on its own) |
| C-03 | A non-System module role mapped to both anonymous and another user role | aqm b2 MXS008 | yes: `role_mappings()` + `user_roles().is_anonymous` | SEC010, check 3 | P1 | Granting the logged-in role silently grants the anonymous visitor too; FP only for deliberate public modules → `SKIP_MODULES` |
| C-04 | Anonymous role can create, delete or write a member of a persistable entity | aqm b2 MXS006 | yes: `permissions()` access_type, member_name; `entities()` entity_type; role mapping | Rule **SEC011 AnonymousWrite** (security) | P1 | Probe the access_type vocabulary (CREATE/DELETE/WRITE spelling). Sign-up forms are the legitimate case, so report and let the project waive |
| C-05 | Entity access grants default rights to new members | aqm b4 Default rights; men S1 | yes: `permissions()` default_member_access_rights | Rule **SEC012 DefaultMemberRights** (security) | P1 | New attributes silently inherit read/write; probe the value strings (None/ReadOnly/ReadWrite) |
| C-06 | Generalization deeper than 2 levels | aqm b1 MXP009, b4, b6 #9; men S1/S2; docs S4 | yes: `entities()` generalization (walk the chain) | Rule **PERF001 InheritanceDepth** (performance) | P1 | Decide whether System.User → Administration.Account counts as a level (probably not: count from the first non-System ancestor). Joins grow per level |
| C-07 | Data view / list view nested 2+ levels deep | aqm b1 MXP011; men S2 | yes: `widgets()` widget_type, parent_widget_id | Rule **PERF002 NestedDataContainers** (performance) | P1 | Mendix's own Recommender check. Probe the widget_type strings (DataView, ListView, Gallery?). `learned-page-patterns.md` already prefers a Context source for nested views, so cite it in the suggestion |
| C-08 | Commit without events on an entity that has event handlers or validation rules | docs S12 | yes: `activities_for()` action_type, with_events, commit_type, entity_ref; `entities()` has_event_handlers, validation_rule_count | Rule **CORR001 CommitSkipsEntityLogic** (correctness) | P2 | Matters on existing apps (CONV015/016 keep new ones clean). FP: deliberate bulk imports → suggestion text names the trade-off |
| C-09 | Page title empty or left as default | docs S8 Meaningful page titles | yes: `pages()` title | Rule **UX003 PageTitle** (design) | P2 | Accessibility and the browser tab. Probe what "default" looks like (empty string or "Page"?) |
| C-10 | Page/microflow URL starts with a parameter, or two URLs conflict (same segment count, parameters in the same places) | aqm b4 URLs; men S1 | yes: `pages()` url | Rule **CONV021 PageUrlShape** (correctness) | P2 | Pairs with CONV019 (navigation pages addressable). Normalise `{x}` to `{}` before comparing |
| C-11 | Microflow uses an UPPER_ prefix outside the Mendix list | aqm b5 (full prefix table) | yes: `microflows()` name | Rule **CONV022 MicroflowPrefixVocabulary** (naming), list configurable | P2 | MPR001's regex lets any capitalised prefix through: its prefix list is a comment, not a check. Missing from it: SCE_, CAL_, OEN_, OLE_, WFA_/WFS_/WFC_, TEST_/UT_, CWS_/CRS_/POS_, DCM_, BSD_, HCH_ |
| C-12 | Event-handler microflow prefix matches its moment+event (BCO_/ACO_/BCR_/ACR_/BDE_/ADE_/BRO_/ARO_); scheduled-event microflow is SCE_ and named after its event | aqm b5 | yes: `entity_event_handlers()` moment, event, microflow; `scheduled_events()` name, microflow_name | Rule **CONV023 LifecycleMicroflowNames** (naming) | P2 | Mechanical and precise. Tells a reader that a flow fires implicitly |
| C-13 | Microflow returns System.Error / HttpResponse / SoapFault | docs S1 | yes: `microflows()` return_type (probe its spelling) | Rule **ERR002 ErrorObjectReturned** (correctness) | P2 | Runtime supports one System.Error instance; returning one to a page/nanoflow breaks. Rare but cheap |
| C-14 | Binary attribute instead of a System.Image / FileDocument specialisation | docs S3 | yes: `attributes_for()` data_type | Rule **DESIGN002 BinaryAttribute** (design) | P2 | Also a migration smell (legacy BLOB columns). Low FP |
| C-15 | User role holds more than one module role of the same module | aqm b7 #10 | yes: `role_mappings()` | Rule **SEC013 OneModuleRolePerModule** (security) | P2 | Complements CONV008. FP: marketplace modules with additive roles → vendor exclusion at the gate |
| C-16 | Duplicate access rules on one entity (same role set and XPath) | aqm b1 MXP010; men S2; docs S4 | yes for exact duplicates; partly for "overly varied" (`permissions()` xpath_constraint) | Rule **PERF003 DuplicateAccessRules** (performance) | P2 | Each rule adds an OR branch to every query |
| C-17 | Non-persistable entity associated with System.User or System.Session | aqm b1 MXP008; men S2 | yes: `associations()` + `entities()` entity_type | Rule **PERF004 SessionCachedNPE** (performance) | P2 | Recommender check; FP when the NPE really is a per-session cache, which is exactly what Mendix warns about |
| C-18 | Log node empty, or not the module name | aqm b4 Log node; men S1; docs S7 | yes: `activities_for()` log_node_expression, module_name | Rule **LOG001 LogNodeIsModule** (quality) | P2 | Configurable: accept a constant or `'Module'` literal. Supports ERR001 (a log nobody can filter is half a trace) |
| C-19 | Widgets left on generated names (`actionButton3`, `textBox12`) | ats community "unique widget names", third-party "mx-name over generated IDs" | yes: `widgets()` name, widget_type | Rule **TEST001 StableWidgetNames** (quality), action buttons and inputs only | P2 | The e2e harness and ATS both locate by mx-name. Existing apps will report many; MDL-built pages report few. Ship scoped to buttons first |
| C-20 | Index on sort, XPath and OData-key attributes of large entities | aqm b1 MXP003/007/016, b6 #3, #13-17; men S2; docs S4 | **no**: no index accessor, no record counts | Skill (E-1) + upstream ask for `indexes()` | P2 | The most-cited performance item across all scans, and the toolkit has no check at all ("none" in the best-practices index) |
| C-21 | Scheduled events: chunked commits, idempotent, ≤10 in parallel per node, rename resets enabled state, UTC, no session edits, ProcessedQueueTask cleanup | aqm b6 #33; docs S6 | partly: `scheduled_events()` time_zone, on_overlap, interval_seconds | Skill (E-2); later maybe a rule on time_zone ≠ UTC | P1 (skill) | Backlog already lists "Scheduled events … nothing yet". These scans give the content |
| C-22 | Atlas 4 theming: `$use-css-variables: true`, globals in `:root`, `var(--x)` not `$x`, color-mix() not darken() | docs S5 | no (SCSS files; shell grep possible) | Skill (E-3) | P2 | `design-artifacts.md` maps tokens to Atlas **SASS** variables (`$brand-primary`). That is Atlas 3 shape and breaks on Atlas 4 apps |
| C-23 | Accessibility: alt text, no positive tabindex, labels, contrast 4.5:1 text / 3:1 non-text, visible focus, link text | docs S8 | no (no alt, tabindex or caption fields); contrast checkable in ds.css | Skill (E-4); contrast check is a ds.css shell candidate | P2 | No toolkit skill states contrast or focus rules today |
| C-24 | Workflow targeting: group targeting by default, group tokens not Name, guard empty target lists, return type | docs S10 | no (workflow XPath not in `xpath_expressions()` document types) | Skill (E-5) | P2 | Empty target list fails the workflow at runtime |
| C-25 | Test design: independent tests, teardown undoes changes, keep rollback on, no fixed sleeps | ats S7, S17, S24, S25, third-party | no | Skill (E-6) | P2 | Only `e2e-harness-base.md` mentions sleeps; nothing states teardown/isolation |
| C-26 | Error-handling semantics: do not commit rolled-back objects; external calls are not reversed by rollback; Continue only on call/loop | docs S1 | no | Skill (E-7) | P2 | Behaviour facts agents get wrong; they fit the existing rollback section |
| C-27 | Unit-test microflow shape: UT_/TEST_, returns nothing/Boolean/String, 0 params or one UnitTestContext | ats S24, S27; aqm b5 | partly: name, return_type, parameter_count (no parameter type) | Rule **TEST002 UnitTestShape** (correctness), only when a UnitTesting module exists | P3 | Wrong shape = test silently not discovered |
| C-28 | More than 9 action buttons on a page | docs S9 | partly: `widgets()` widget_type per container (no visibility) | Rule **UX004 ButtonCount** (design) | P3 | Conditional visibility inflates the count |
| C-29 | App beyond 3000 microflows / 750 entities | aqm b4; men S1 | yes: counts | Rule **DESIGN003 AppSize** (design), info-level | P3 | One finding per app; useful mainly in `app-analysis.md` |
| C-30 | CUD activities near the start event | aqm b1 MXP014 | no: no activity order/position | stays in `microflow-preflight.md` | P3 | Upstream ask: expose sequence index |
| C-31 | Negating access-rule pair (`not()` / `= false()` only difference) | aqm b1 MXP013; docs S4 | partly: `parse_xpath()` on xpath_constraint | Rule PERF005 | P3 | Parser edge cases; low frequency |
| C-32 | XPath `not` / `!=` and costly parts left of `and` | aqm b1 MXP015, b6 #34; docs S4 | partly: `xpath_expressions()` + `parse_xpath()`; no volumes | Rule PERF006, or skill note | P3 | Only matters at 100k+ rows; noisy without volume data |
| C-33 | Two associations between the same entity pair | aqm b6 #11 | yes: `associations()` | Rule DESIGN004 | P3 | Many legitimate (CreatedBy/AssignedTo → User); exclude System targets |
| C-34 | Nested `if` inside one expression | aqm b4; men S1 | partly: split condition_expression only | Rule QUAL007 | P3 | Change/assign expressions not exposed |
| C-35 | Drop-down for an enum of 2-5 values (use radio buttons) | docs S9 | partly: widget_type + attribute_ref; enum name per attribute unclear | Rule UX005 | P3 | Design preference, not a defect |
| C-36 | Pop-up opened from a pop-up | docs S9 | partly: `pages()` has no layout; `refs_from()` page→layout may work | Rule UX006 after probing refs | P3 | Real UX defect, but needs a probe first |
| C-37 | Debug never in production, Critical reserved, own log node names | docs S7 | no (runtime levels are environment config) | Skill note in `mdl-cookbook-microflows.md` logging | P3 | |
| C-38 | Marketplace modules not modified | aqm b4; men S1 | no (needs a reference MPK) | Skill note in `existing-app-assurance.md` | P3 | |

## E. Skill-only additions (non-lintable P1/P2)

- **E-1 → `modularize-domain.md`** (indexes; also update the "none" cell in `mendix-best-practices-index.md`):
  "Index every attribute used as a sort item, in an XPath on an entity expected past ~10k rows, or as a
  published OData key. Lead with the most selective attribute, keep indexes under 3 attributes (max 5),
  never two indexes with the same leading attribute, and skip Boolean/enum (MXP003/007/016)."
- **E-2 → `microflow-loop-antipatterns.md` (new 'Scheduled events' section; route from `learned-microflow-patterns.md`)**:
  "A scheduled-event flow commits in batches, survives a rerun after a crash (idempotent) and finishes
  well inside its interval. No more than 10 events run at once per node. Renaming an event resets its
  enabled state per environment, so re-check it after deploy. Use UTC, never change the session object, and
  clean System.ProcessedQueueTask."
- **E-3 → `design-artifacts.md`** (Atlas mapping table):
  "On Atlas 4 (Atlas Core ≥4), map tokens to CSS custom properties in `:root` with
  `$use-css-variables: true` first in `custom-variables.scss`. Use `var(--x)`, not `$x`, and `color-mix()`, not
  darken()/lighten(). Declare only the values you override. The SASS-variable table is Atlas 3 only."
- **E-4 → `ui-preflight-pages.md`** (and the wireframe checklist in `design-artifacts.md`):
  "Every page has a meaningful title, every input a visible label, every informative image alt text, and every
  decorative image `alt=''`. Text contrast is ≥4.5:1, buttons and inputs ≥3:1, focus is always visible and never
  colour-only, there is no positive tabindex, and link text names its destination."
- **E-5 → `learned-workflow-patterns.md`**:
  "Target user tasks at workflow groups by default, and constrain on group tokens `[%WorkflowGroup_X%]`, not
  Name. A targeting XPath or microflow that returns 0 objects fails the workflow, so guard the empty case. A due
  date is a stored deadline, not a reminder."
- **E-6 → `testing-shape.md`** (and `e2e-harness-base.md`):
  "Tests share no data and run in any order. Setup only opens and logs in. Teardown undoes what the test changed.
  Keep the Unit Testing rollback on. Wait for a condition, never a fixed sleep. Locate by mx-name and nothing else."
- **E-7 → `learned-microflow-patterns.md`** (rollback section):
  "A rollback does not undo REST/SOAP/Java calls already made. Do not commit an object the error flow just
  rolled back, because Mendix no longer sees it as changed. Continue is only allowed on a call-microflow or a
  loop, and the failing activity's own changes are always lost."

## F. Not worth it / out of scope

| Item | Source | Reason |
|---|---|---|
| Convert eligible microflows to nanoflows (MXP006) | aqm b1 | Eligibility needs a client-side call-site analysis; high FP; offline/security trade-offs |
| Scheduled-event interval divisors, parameter-free flow, unique user-task names | docs S6, S10 | Studio Pro / `mx check` already refuse these; a rule duplicates a CE |
| Line crossings, left-to-right layout | aqm b4 | Cosmetic; MPR008/MPR011 cover the harmful part |
| Input validation on all microflow inputs | aqm b4 | Not checkable without data-flow analysis; VAL_/CONV015 route covers intent |
| Microflow parameter count | aqm b4 | No threshold stated anywhere; would be invented |
| Technical attributes with leading underscore; entities singular | aqm b5 | "Technical" and "plural" are not decidable from the model |
| App/config naming, configuration DB passwords | aqm b7 | Settings/Portal concerns; constants-audit covers secrets |
| Keep up with Mendix releases; community-supported components; open-source health | aqm b4; men S6/S7 | Portfolio/dependency scanning (QSM/Snyk), not model lint; `jar_dependencies()` has no vulnerability data |
| QSM/Sigrid star ratings, ISO 25010 maintainability metrics | aqm b8; men S7-S9 | No thresholds were published or reachable, and benchmark recalibration makes them unportable |
| ATS tool mechanics (recorder, selectors, SOAP CI API, schedules, licensing) | ats S3-S22 | About the end-of-sale tool, not the app model |
| Maia units, network hosts, Logic/Workflow Recommender | docs S13; men S4/S5 | Product usage, not quality practice |
| Denormalise, archive, more App Engines, proxy in front | aqm b6 #7-8, #43-44 | Architecture/ops judgement, no model signal |
| Line length ≤9 words, single-column forms, green forward buttons | docs S9 | Style guidance; belongs in the wireframe review loop, not lint |

**Contradictions surfaced (settle before the touching rule):**
- Snippet prefix: the Mendix Naming Conventions say `SNIP_`, but stock CONV005 enforces `SNIPPET_`. Every Mendix-conventional app fails CONV005.
- Microflow prefixes: MPR001 lists `SCH_`/`SE_` and its regex accepts any capitalised prefix. Mendix says `SCE_` and has about 15 prefixes that MPR001 does not list (C-11).
- Size threshold: Mendix says 25 elements, CONV009 says 15 and QUAL003 says 25, and both rules ship. The index explains this, but anyone reading only a finding sees two thresholds.
