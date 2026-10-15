# Lint backlog — best practices the brain already knows, turned into rules one batch at a time

**Created:** 2026-10-08
**Purpose:** the single list of lint-rule candidates, where each came from, what blocks it, and
where it is in the rollout. Chat is where this plan lived until today; this file is where it lives
now. Every rule PR links a row here and moves it.

## Why rules at all

A skill is read by whoever happens to load it; a rule runs on every model, every time, and says a
number. `lint-rules/README.md` has the mechanics (header, blindness finding, how rules reach a
project). This file has the *what* and the *order*.

## Rollout rules

1. **Two or three rules per PR**, never a pack. Each with Starlark unit fixtures under
   `tests/lint-rules/` (the UX001/UX002 suite is the template), so the logic is proven before the
   rule meets a model.
2. **Ships as a warning.** A new rule runs at warning severity on its first projects. The gate
   fails only on errors, so a noisy rule produces counts, not blocked sessions.
3. **One field run before merge.** The rule runs on one real model; the PR cites the count and
   three sample findings. Vocabulary (field names, type strings) is probed there, never assumed —
   see "Probe, don't trust" in `lint-rules/README.md`.
4. **Promote after two clean projects.** Warning becomes error, the README row moves from
   *candidate* to *proven*.
5. **Blind rules say so.** Every rule emits a `_rule` finding when its probe fails; the gate reports
   it. A rule that silently matches nothing is the one defect this whole effort exists to prevent.

## Status legend

`idea` → `drafted` (PR open, fixtures pass) → `warning` (merged, on first projects) → `proven`
(error severity) · `blocked: <why>` · `skill` (not lintable, lives in a skill instead) ·
`covered: <where>` (another check already catches it) · `not lintable` (runtime or CSS; named so
the source issue's list is complete)

## Batch 1 — incident evidence and known catalog fields

| # | Rule | Category | Evidence | Needs | Status |
|---|---|---|---|---|---|
| 1 | Error silently swallowed: activity error handling set to continue/custom and no Log activity in the flow | quality | `learned-microflow-patterns.md` error-handling rules; CONV013/014 cover only the *presence* of handling on external calls | `error_handling_type` value strings (probe) | idea |
| 2 | Inline `style` on a widget, or a class not present in the compiled design system | design | `learned-css-that-never-applied.md`, `learned-stylegallery.md` (real: an entire app rendered unstyled) | `style`, `class_name`; class list from `themesource/<module>/web/main.scss` via config | idea |
| 3 | Page or `ACT_` flow with no entry point (QUAL004 exempts `ACT_`) | quality | `wiring-sweep.md`, obligation check "wiring" | `refs_from` / refs table | idea |
| 4 | Retrieve, delete, REST or Java call inside a loop body (CONV011 covers commit only) | performance | `microflow-loop-antipatterns.md` | `parent_loop_id` / `loop_depth` actually populated (brain says activities were flat 2026-09-15 — probe) | idea |

## Batch 2 — strong evidence, one unconfirmed field each

| # | Rule | Category | Evidence | Needs | Status |
|---|---|---|---|---|---|
| 5 | Page-triggered external call left on default rollback handling, no handler | quality | same as 1 | `error_handling_type` | idea |
| 6 | Custom error handler that neither logs nor gives feedback | quality | `learned-popup-feedback-pattern.md` | `error_handling_type`, `log_*` | idea |
| 7 | Page-triggered commit or delete without refresh | correctness | `learned-page-patterns.md` | refresh flag on commit (unconfirmed) | blocked: field unconfirmed |
| 8 | DataGrid 2 database source without a sort | correctness | `learned-dg2-patterns.md` | datasource sort in projection (unconfirmed) | blocked: field unconfirmed |
| 9 | Page top container missing the shell/page-column class | design | `ui-preflight-pages.md`, `oneshot-page-structure-patterns.md` | `class_name`, `depth`; class name per project config | idea |

## Batch 3 — security and navigation

| # | Rule | Category | Evidence | Needs | Status |
|---|---|---|---|---|---|
| 10 | Module role mapped to no user role (CONV008 checks the reverse) | security | `security-is-not-a-later-script.md` | roles in projection | idea |
| 11 | Widget-bound entity with zero access rules at production level | security | SEC001 variant scoped to entities pages actually touch | entity access in projection | idea |
| 12 | Navigation item without icon | design | `learned-sidebar-collapse-icons.md` | navigation in projection (unconfirmed) | blocked: field unconfirmed |

## Batch 4 — Mendix quality-source review

Sources: Mendix Best Practice Recommender, QSM/AQM public docs, ATS public docs, Menditect public docs,
docs.mendix.com; reviewed 2026-10-08. Rule ids are placeholders. Lintability was read from the mxcli lint
source (Starlark accessors), and no rule below has been probed on a real model yet, so every "Needs" cell
is still the vocabulary probe from rollout rule 3. The full review is
`process/quality-sources-review-2026-10-08.md`. Suggested PR grouping: {13, 14, 15} · {16, 17, 27} ·
{21, 22} · {18, 23, 28} · {19, 20, 29} · {24, 25, 26}.

| # | Rule | Category | Evidence | Needs | Status |
|---|---|---|---|---|---|
| 13 | Anonymous role hygiene: anonymous = admin role; anonymous mapped to an Administration module role; a module role shared by anonymous and another user role (SEC010) | security | Recommender MXS005, MXS008, MXS009 | `project_security()` anonymous/admin role names; `user_roles().is_anonymous`; `role_mappings()` | idea |
| 14 | Anonymous role can create, delete or write members of a persistable entity (SEC011) | security | Recommender MXS006 | `permissions()` access_type vocabulary (probe) | idea |
| 15 | Entity access grants default rights to new members (SEC012) | security | General Development Best Practices → Security | `permissions().default_member_access_rights` values (probe) | idea |
| 16 | Generalization deeper than two levels (PERF001) | performance | Recommender MXP009; General Dev BP; Community perf #9 | `entities().generalization`; how System ancestors count | drafted (Batch 2) |
| 17 | Data view / list view nested two or more levels (PERF002) | performance | Recommender MXP011 | `widgets()` widget_type strings, parent_widget_id | drafted (Batch 2) |
| 18 | Commit without events on an entity with event handlers or validation rules (CORR001) | correctness | Setting Up Data Validation ("set With events to Yes") | `activities_for()` with_events / commit_type values; `entities().has_event_handlers` | idea |
| 19 | Page title empty or default (UX003) | design | Accessibility introduction → meaningful page titles | `pages().title` default value (probe) | idea |
| 20 | Page URL starts with a parameter, or two URLs conflict (CONV021) | correctness | General Dev BP → URLs | `pages().url` | idea |
| 21 | Microflow prefix outside the Mendix list; MPR001 checks only the leading capital (CONV022) | naming | Naming Conventions BP prefix table | `microflows().name`; prefix list as config | idea |
| 22 | Event-handler and scheduled-event microflow names match their trigger (CONV023) | naming | Naming Conventions BP (BCO_…ARO_, SCE_) | `entity_event_handlers()` moment/event; `scheduled_events()` microflow_name | idea |
| 23 | Microflow returns System.Error / HttpResponse / SoapFault (ERR002) | correctness | Error Handling in Microflows | `microflows().return_type` spelling (probe) | idea |
| 24 | Binary attribute instead of System.Image / FileDocument specialisation (DESIGN002) | design | Configuring a Domain Model | `attributes_for().data_type` value for binary (probe) | idea |
| 25 | User role holds more than one module role of the same module (SEC013) | security | App Setup BP → user roles | `role_mappings()` | idea |
| 26 | Exact-duplicate access rules on one entity (PERF003) | performance | Recommender MXP010 | `permissions()` grouped by entity + xpath_constraint | idea |
| 27 | Non-persistable entity associated with System.User / System.Session (PERF004) | performance | Recommender MXP008 | `associations()` from/to; `entities().entity_type` | drafted (Batch 2) |
| 28 | Log node empty or not the module name (LOG001) | quality | General Dev BP → logging; Logging refguide | `activities_for().log_node_expression` shape (literal vs constant) | idea |
| 29 | Action buttons and inputs left on generated widget names (TEST001) | quality | ATS community + harness locator practice (mx-name) | `widgets().name`, widget_type | idea |
| 30 | Index on sort / XPath / OData-key attributes | performance | Recommender MXP003, MXP007, MXP016 | an `indexes()` accessor (does not exist; upstream) | blocked: no index accessor |
| 31 | Scheduled event not in UTC | correctness | Scheduled Events refguide | `scheduled_events().time_zone` values | skill (rule later, maybe) |

### Notes from the 2026-10-08 review

- CONV005 demands a `SNIPPET_` prefix, while Mendix's naming-conventions page says `SNIP_`. Every
  Mendix-conventional app fails CONV005; settle before touching naming rules 21 and 22.
- MPR001's prefix regex accepts any capitalised prefix (its prefix list is a comment, not a check), and the
  list names `SCH_`/`SE_` where Mendix uses `SCE_`.
- Stock rule ids are now MPR001-012 in the mxcli source; the generated project CLAUDE.md tables still say
  MDL001-007.

## Batch 5 — UI and user-text traps from the 2026-10-12 UX-fix run

Source: issues #276, #280, #282 (retros of one 20-task UX-fix run over three apps built from
this toolkit). Every candidate the three issues name is listed, lintable or not; runtime, watch-
mode and journey-assertion halves belong to another PR and appear only to say where they live.
Lint Batch 3 shipped rows 32–35 (`TXT001`, `TXT002`, `UI001`); the field-run counts are in
`lint-rules/README.md`. "Seen in" counts apps out of three.

| # | Rule | Category | Evidence | Needs | Status |
|---|---|---|---|---|---|
| 32 | Build-process words in user-visible text: `Stage N`, `BR-10`, `F004`, TODO, version tag, "(local, …)", project code names (TXT001) | quality | #280: 3 of 3 apps (page subtitles in 5 scripts, captions, live titles); the glossary grep missed the same lines in 2 of 3 | `strings()` (mxcli >= 0.25.0, FULL catalog) — probed 2026-10-13 | drafted (Batch 3) |
| 33 | Non-ISO literal date or day/month format pattern in user-visible text (TXT002) | quality | #280: 2 of 3 apps (`dd MMM` in 5 places, `dd MMM HH:mm` in 8, a raw `M/d/yyyy`); "33 of 33 ISO" grep was wrong | `strings()` — probed; sees texts and templates only, see row 36 | drafted (Batch 3) |
| 34 | List view inside a Data grid 2 column: its own "Load more" / "No items found" per cell (UI001 trap a) | design | #282 | `widgets()` parent walk; Datagrid type string — probed 2026-10-13 | drafted (Batch 3) |
| 35 | Inline `width` on an Atlas input without `flex`: ignored, even with !important (UI001 trap b) | design | #282 | `widgets().style` — probed | drafted (Batch 3) |
| 36 | Non-ISO format string inside an expression (`formatDateTime($d, 'dd MMM')`, a CHANGE writing an audit text) | quality | #280: the larger half of the date misses (8 microflow literals in one app) | expression literals in the catalog; `strings()` indexes only `Texts$Text` | blocked: expressions not indexed (upstream) |
| 37 | DateTime attribute rendered with the locale default (shows `M/d/yyyy`) instead of an explicit format | quality | #280: one admin page | widget date-format setting in `widgets()` | blocked: field not in projection |
| 38 | Atlas spacing class that the theme does not define (`spacing-outer-left-small`): passes check and mxbuild, renders nothing | design | #276 item 3; #282 (unverified 48px gap) | the theme's class list. A rule cannot read SCSS, and the valid set is per Atlas version: the 2026-10-13 probe found `-small`, `-smaller`, `-smallest` used 90+ times in marketplace modules | blocked: needs class list — shell check against `design-properties.json` instead |
| 39 | Inline Style on a dynamic text (crashes MxBuild) | correctness | #282 | — | covered: `mxcli check` MDL-WIDGET03 (error at script time); model-level copies exist in Studio-Pro-authored marketplace modules, so a lint rule would flag working pages |
| 40 | Dynamic text at the top level of a snippet, outside any data view on the parameter: no context object | correctness | #282 | `widgets()` gives the ancestry; whether the text uses the parameter is a template parameter source, not projected | idea (probe template parameters) |
| 41 | Data grid 2 column whose content walks 2+ associations: writes a null attribute reference | correctness | #282 | column attribute path (a column property, not a widget) | blocked: field not in projection |
| 42 | Data grid 2 column layout: stored manual width not applied; right alignment only on the header; sort arrow at the far left | design | #282 (CE0463 on ALTER PAGE width is a tooling bug, not lint) | column properties | blocked: field not in projection — skill |
| 43 | One canonical empty-state sentence and widget, not re-invented per page | design | #280: 3 of 3 apps, plain text on one page and an alert on another | judgement | skill |
| 44 | "yet" on a terminal state ("not approved yet" on a rejected item) | quality | #280 | judgement over state | skill (TXT001 `PROJECT_WORDS` can carry a fixed list) |
| 45 | Empty-state text authored in CSS `::before` / `::after`: invisible to innerText checks | — | #276 item 1: 3 of 17 journey steps failed on a working feature | SCSS + journey runner | not lintable — journey check (other PR) |
| 46 | Outline, background or `scrollIntoView` on a Data grid 2 row paints nothing (rows are `display: contents`) | — | #276 item 2, #282: 3 takes in two films | CSS / runtime | not lintable — skill (`learned-css-that-never-applied.md`) |
| 47 | `:focus-visible` ring painted on the script-focused first control at every landing | — | #276 item 4 | theme SCSS / JS | not lintable — skill + review checklist |
| 48 | `--watch` drops `dist/pages` on an SCSS edit; calculated attributes added while running read empty; trial-licence session cap hangs logins | — | #282: 15 NEEDS_RESTART events; 2 of 3 apps hit the cap | runtime | not lintable — runner / skill (other PR) |

## Batch 6 — external-role writes and a tunable threshold

Source: issues #268 and #267. Row 14 covers writes by the anonymous role only; row 49 is the
same defect for a named external role, which a project has to name, because no catalog field
says a role is external. Lint Batch 4 shipped both rows; the field-run counts are in
`lint-rules/README.md`.

| # | Rule | Category | Evidence | Needs | Status |
|---|---|---|---|---|---|
| 49 | External role (configured) can write all members, a state enumeration (`Status`/`State`/`Result`/`Stage`/`Phase`), an audit `…At`/`…By` attribute, or the association its own XPath scopes ownership on (SEC014) | security | #268: a partner role held `create, read *, write *` on two self-owned entities with a state attribute; lint showed only CONV006 +4, re-baselined; a manual review found it five days later | `permissions_for()` `MEMBER_WRITE` rows, `attributes_for().data_type` (`Enumeration`), `user_roles()` / `role_mappings()`; `external_roles` option, text not list; absent = sync NOTE, not a `_rule` finding. Probed 2026-10-13 | drafted (Batch 4) |
| 50 | CONV009 threshold read from `lint-config.yaml` (`maxObjects`, `countLoopBodies`) instead of the stock hard-coded 15 | quality | #267: the generated config's own example does nothing; three apps at 36 / 30 / 5 findings, one app split flows only to satisfy the 15 | `get_option()`; `total_activity_count` (mxcli >= 0.25.0) for loop bodies. Default kept at 15: raising it for every project is a maintainer call | drafted (Batch 4) |

## Batch 7 — modelling errors that hit both arms, and stock-rule false positives

Source: issue #169, from a field comparison on 2026-09-29: an mxcli + toolkit build and a Studio Pro
MCP build of the same frozen spec, about 75 defects between them. Four or five modelling errors
appeared in both builds independently, so they come from the spec or the platform, not the authoring
tool. Hypothesis: these rules would have prevented 6–8 of the 75. The page-button refresh candidate
is row 7. The other four are below.

| # | Rule | Category | Evidence | Needs | Status |
|---|---|---|---|---|---|
| 51 | Reference-selector / picker XPath that reads rows the current role cannot read under entity access (e.g. through `System.UserRoles` or an account association) | security | #169: a reassign picker listed only the user, or nothing, in both builds | widget selectable-objects XPath; `permissions()` per entity and role (probe) | idea |
| 52 | `change` with no later `commit` in a microflow reached from a scheduled event or a workflow (no client to commit it) | correctness | #169: an escalation change was lost, found only by a timer run | `activities_for()` order and `commit` targets; callers from `scheduled_events()` / workflow refs (probe) | idea |
| 53 | `addDays`/`addHours`/`trim`/`length` on an attribute that can be empty, with no empty guard before it | correctness | #169: a null runtime error | expression text in the catalog: same blocker as row 36 | blocked: expressions not indexed (upstream) |
| 54 | Navigation profile with no logout item, or a home page whose role has no read access to its entity (CE2729) | security | #169: caught late in both builds | navigation in projection (row 12's blocker) | blocked: field unconfirmed |

Two spec-level items from the same comparison are not lint rules: legal-suffix matching on company
names, and workflow admin-centre access for an approver role.

**Stock-rule false positives.** These are not candidates. They are findings on the toolkit's own conventions. The
answer for each is in `skills/lint-that-actually-runs.md` → "Stock rules against the toolkit's own
conventions". The rules are mxcli's own, so any Starlark change waits for fixtures and a toolkit replacement rule (rollout rule 1).

| Rule | Issue | Disposition |
|---|---|---|
| QUAL004 on a `DS_` Data grid 2 datasource | #360 | baseline with reason; upstream `bug-logs/pending-github-issues/qual004-dg2-datasource-ref.md`; BUG-DRAFT-qual004-dg2-datasource |
| QUAL004 on `TEST_` helpers; CUSTOM002 on `TEST_`/`GET_`/`PRS_`/`STUB_` | #241 | CUSTOM002 `enabled: false` (user decision, recorded in `PROJECT.md`) or baseline with reason; QUAL004 baseline with reason; upstream `lint-naming-prefixes-as-options.md` |
| QUAL002 on import mappings / published REST services (MDL089) | #246 | QUAL002 per-kind options in `lint-config.yaml`; upstream `qual002-skip-mdl089-types.md` |

## Cheap extras (one afternoon each, when a batch has room)

Microflow not in a folder · non-persistent entity committed to the database · many-to-many
without a junction entity · `VAL_` flow not returning Boolean · log level ERROR with an empty
message · error handler that only re-raises.

## Not lintable from the catalog — lives in a skill, maybe a shell check

| Topic | Where | Check |
|---|---|---|
| Theme: never edit `themesource/atlas_core`, overrides in the app theme or one UI module; variables over literals in SCSS | `design-artifacts.md` (to add) | grep for hex literals outside `custom-variables.scss`; diff of `atlas_core` against the shipped version |
| Theme: design properties over free-text classes; must exist in `design-properties.json` (CE6083) | `learned-mdl-preflight.md` row 24 | already a STOP row |
| Logging conventions: node name = module, message codes | `mdl-cookbook-microflows.md` | prose; rule 1 above covers the absence |
| Scheduled events: idempotent, batched, disabled per environment | nothing yet | `app-analysis.md` counts them; best practice to write |
| Localization: hard-coded captions | nothing yet | needs a research pass first |

## Brain contradictions to settle before the rule that touches them

- Sidebar caption-less vs icon+label: `learned-page-patterns.md` vs `learned-sidebar-collapse-icons.md` (blocks 12).
- Empty state required (`ui-preflight-pages.md`) vs MDL cannot write one (`learned-mdl-cannot-express.md`).
- `_Dto` suffix standard vs avoid Dto, both in `learned-microflow-patterns.md`.
- mxbuild blind to grants (`iterative-build-loop.md`) vs CE0106 (`learned-file-upload-widget.md`).

## Still to research (not needed to start)

Mendix's own published rule set (Application Quality Monitor), its performance and
error-handling pages, naming conventions. Output: a mapping table against the ids above and
a second backlog section. Forum only to weight by incident frequency.

## History

- 2026-10-14 — Batch 7 added from #169 (rows 51–54), plus dispositions for the stock-rule false
  positives in #360, #241 and #246. The 2026-09-29 inbox file for #169 was promoted here and deleted.
- 2026-10-13 — Batch 6 added from #268 / #267 (rows 49–50). Lint Batch 4 shipped them as `SEC014`
  and a toolkit-owned `CONV009` (status `drafted`, 32 unit cases). First field run, mxcli 0.26.0:
  SEC014 1 finding with the one external role configured, positive control 7 that a SQL replay
  matches; CONV009 5 / 5 / 10 at 15 / 20 / 10, while stock CONV009 stayed at 5 with `maxObjects: 20`.
- 2026-10-13 — Batch 5 added from #276 / #280 / #282 (rows 32–48). Lint Batch 3 shipped rows
  32–35 as `TXT001`, `TXT002`, `UI001` (status `drafted`, 23 unit cases); first field run 0 / 0 / 0
  with positive controls 27 / 50 / 17 — counts in `lint-rules/README.md`.
- 2026-10-08 — file created from the UX001/UX002 work and a brain scan of `skills/`; no rule from
  this list exists yet. UX001/UX002 themselves are `drafted` (PR open, 35 unit cases, field run
  pending).
