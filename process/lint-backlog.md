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
(error severity) · `blocked: <why>` · `skill` (not lintable, lives in a skill instead)

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
| 16 | Generalization deeper than two levels (PERF001) | performance | Recommender MXP009; General Dev BP; Community perf #9 | `entities().generalization`; how System ancestors count | idea |
| 17 | Data view / list view nested two or more levels (PERF002) | performance | Recommender MXP011 | `widgets()` widget_type strings, parent_widget_id | idea |
| 18 | Commit without events on an entity with event handlers or validation rules (CORR001) | correctness | Setting Up Data Validation ("set With events to Yes") | `activities_for()` with_events / commit_type values; `entities().has_event_handlers` | idea |
| 19 | Page title empty or default (UX003) | design | Accessibility introduction → meaningful page titles | `pages().title` default value (probe) | idea |
| 20 | Page URL starts with a parameter, or two URLs conflict (CONV021) | correctness | General Dev BP → URLs | `pages().url` | idea |
| 21 | Microflow prefix outside the Mendix list; MPR001 checks only the leading capital (CONV022) | naming | Naming Conventions BP prefix table | `microflows().name`; prefix list as config | idea |
| 22 | Event-handler and scheduled-event microflow names match their trigger (CONV023) | naming | Naming Conventions BP (BCO_…ARO_, SCE_) | `entity_event_handlers()` moment/event; `scheduled_events()` microflow_name | idea |
| 23 | Microflow returns System.Error / HttpResponse / SoapFault (ERR002) | correctness | Error Handling in Microflows | `microflows().return_type` spelling (probe) | idea |
| 24 | Binary attribute instead of System.Image / FileDocument specialisation (DESIGN002) | design | Configuring a Domain Model | `attributes_for().data_type` value for binary (probe) | idea |
| 25 | User role holds more than one module role of the same module (SEC013) | security | App Setup BP → user roles | `role_mappings()` | idea |
| 26 | Exact-duplicate access rules on one entity (PERF003) | performance | Recommender MXP010 | `permissions()` grouped by entity + xpath_constraint | idea |
| 27 | Non-persistable entity associated with System.User / System.Session (PERF004) | performance | Recommender MXP008 | `associations()` from/to; `entities().entity_type` | idea |
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

- 2026-10-08 — file created from the UX001/UX002 work and a brain scan of `skills/`; no rule from
  this list exists yet. UX001/UX002 themselves are `drafted` (PR open, 35 unit cases, field run
  pending).
