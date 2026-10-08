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
