## Design system

**Recommendation (not yet confirmed): Atlas UI (Atlas Core `Atlas_Default` layout), styled with Atlas defaults — no client brand exists to target.**

Sources checked for a brand basis: `intake.md`, `triage.md`, `PROJECT.md`, and the four
source-of-truth documents in `analysis/knowledge-base/share/` (functional spec, API behavior
spec, OpenAPI contract, DB schema). None contain a palette, logo, typography spec, or brand
guideline — the source is a pure back-end/API description (MES 2.0), not a UI mockup. The
only UI signal in the BRD itself is the layout each page already declares:
`"layout": "Atlas_Core.Atlas_Default"` on both `Routing_Overview` and `Routing_View` in
`analysis/knowledge-base/brd/F001-routing-overview.brd.json` — i.e. whoever wrote the BRD
already assumed stock Atlas, sidebar layout.

Per the toolkit's `skills/design-artifacts.md` Step 0b ("Establish the Branding Basis"), the
branding basis is itself a `✋` gate that must be asked in chat, not defaulted silently. Given
this project's own decisions — POC/demo driver (`PROJECT.md` row "Project driver: (a)
POC/demo"), no SME, document-only source, no brand material anywhere in `sources/` or the KB
— **"Atlas defaults"** is the option the skill's own guidance table recommends for exactly
this situation ("POC / no brand yet — matches the actual build target 1:1, zero effort"). I
am treating that as my recommendation, not a confirmed decision — see Open Questions.

## Brand colours

No client-supplied colours exist anywhere in the source material, so there are no hex values
to report as "the brand's own." Recommended path, pending the Step 0b confirmation above:
**use Atlas Core's out-of-the-box palette untouched** (no `custom-variables.scss` overrides),
so the values below are Atlas's shipped defaults, not project-chosen brand colours:

| Token | Atlas variable | Typical Atlas default | Use |
|---|---|---|---|
| Primary | `$brand-primary` | `#0595db` (Mendix blue) | Primary buttons, links, active nav |
| Success | `$brand-success` | `#67c157` | Positive status badges (e.g. "Released") |
| Warning | `$brand-warning` | `#f99e1c` | In-progress / pending status |
| Danger | `$brand-danger` | `#dd3145` | Errors, "Obsolete"/blocked status |
| Background | `$background-color` | `#f5f5f5` | Page background |
| Text | `$font-color` | `#5e5e5e` / `#000` | Body copy |

These are Atlas Core's shipped tokens (per `design-artifacts.md`'s Atlas mapping table
convention), not measured from this project's `.mpr` — I did not open the `.mpr` or any
`theme/` folder because neither exists yet in this checkout (no `design/`, `architecture/`,
or `themesource/` directories present). If the app already has a customized Atlas theme
checked in elsewhere, that would supersede this and should be confirmed before I write
`design/ds.css`.

**If the user instead wants a placeholder brand** (Option 3 in Step 0b — "design-forward but
brand-agnostic, swap later"), I'd pull from the `dataviz` skill's validated reference palette
for any status/data colours rather than hand-picking, and record the choice + rationale in
`design/brand.md` as the skill requires. I have not done this because it's a decision, not a
default.

## Page plan

Concrete structure for **`RoutingManagement.Routing_Overview`**, built from the BRD's own
`sections`/`actions`/`dataContext` (F001-routing-overview.brd.json) and the widgets already
vendored in this project (`widgets-inventory.txt`):

- **Layout:** `Atlas_Core.Atlas_Default` (left sidebar nav, per the BRD's own layout field —
  also the layout-pattern question `checkpoint-design.md` Q1 would ask; "left sidebar" is the
  Atlas_Default recommendation whenever there's no other nav signal to override it).
- **Data context:** `RoutingSearch_Dto` (non-persistent search/filter object).

1. **Page header** — title "Routing Overview", breadcrumb-free (top-level nav item).
2. **`SearchFilters` section** (BRD section 1) — a filter bar above the grid:
   - Route code / name text filter (`DatagridTextFilter`)
   - Status combobox filter (`Combobox` + `DatagridDropdownFilter`) — values driven by
     whatever status enum the domain model defines (not yet extracted into this BRD's
     `domainEntities` in the excerpt I read — flag for the architect)
   - "Search" action button, calling `GET_Routing_List`
3. **`ResultGrid` section** (BRD section 2) — the primary surface:
   - `Datagrid` widget (already vendored) bound to the search results
   - Columns: Route code, Route name, Version (current), Status (as a `Badge`/`BadgeButton`
     status pill — both widgets are vendored), Last released date
   - Row click → navigates to `Routing_View` (drilldown), calling `GET_Routing_Detail`
   - Empty-state and loading-state per Atlas defaults
4. **`ReleasedContextSummary` section** (BRD section 3) — a summary strip/panel, likely above
   or beside the grid: aggregate counts (e.g. "X routes released", "Y pending") sourced from
   `GET_ReleasedRoutingContext`. Rendered as KPI/stat tiles per `design-artifacts.md`'s
   component list, using the `dataviz` skill's palette if any of these become chart/KPI colour
   choices rather than plain text.

This is a **DESIGN FROM BRD** tier-2 wireframe (per `design-artifacts.md` Step 2's
input-priority ladder) — there is no source screenshot in this project, only the BRD's field
list, so the wireframe is derived from that BRD plus sibling-screen conventions, not from a
mockup. Before this becomes an actual `design/wireframes/Routing_Overview.html` file, Step 3b
of the same skill requires walking it for chrome with no requirement behind it (e.g. a "clear
filters" link, a status legend) and either cutting it or specifying what triggers it — I have
not built that file, per this task's "preparation only" scope.

## Files I read

1. `<scratch>/cb-eval2/control/USI_Routing_Workshop/CLAUDE.md`
2. `<scratch>/cb-eval2/control/USI_Routing_Workshop/CLAUDE.local.md`
3. `<scratch>/cb-eval2/control/USI_Routing_Workshop/PROJECT.md`
4. `<scratch>/cb-eval2/control/USI_Routing_Workshop/intake.md`
5. `<scratch>/cb-eval2/control/USI_Routing_Workshop/triage.md`
6. `<scratch>/cb-eval2/control/USI_Routing_Workshop/widgets-inventory.txt`
7. `<scratch>/cb-eval2/control/USI_Routing_Workshop/analysis/knowledge-base/share/KB_MES20_APIBehaviorSpec.md` (grep only, then targeted read)
8. `<scratch>/cb-eval2/control/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`
9. `<home>/mxcli-project-toolkit/skills/design-artifacts.md`
10. `<home>/mxcli-project-toolkit/skills/conversion-runbook.md` (Stage 3 section, via grep)
11. `<home>/mxcli-project-toolkit/skills/checkpoints/checkpoint-design.md`

Also listed (not opened as content, only directory-checked): `analysis/knowledge-base/brd/*.deferred.json` filenames, `analysis/knowledge-base/reports/validation-report.md` filename, `analysis/knowledge-base/share/*.md` filenames (grepped for brand/color/theme keywords, no matches beyond the Atlas layout hit above and an unrelated "styled" match in the API spec).

## Open questions for the user

1. **Branding basis (Step 0b gate — not yet asked or confirmed):** no client palette, logo,
   or design guideline exists anywhere in this project's sources. Confirm: (A) Atlas defaults
   — recommended, matches the POC/demo driver and zero-brand-material reality, or (B) a
   neutral placeholder brand palette (swap later), or (C) you have branding material not yet
   dropped into `sources/` — if so, where should I look?
2. **Atlas layout pattern (checkpoint-design.md Q1):** the BRD already assumes
   `Atlas_Default` (left sidebar). Confirm that's the intended nav pattern rather than
   `Atlas_TopBar`, or a custom layout.
3. **Platform target (checkpoint-design.md Q2):** web-only desktop, or responsive
   web/tablet? Nothing in the source material states this.
4. **Status enum for the routing header** (needed for the status badge/filter on the
   overview grid): the BRD excerpt I read doesn't enumerate the status values (e.g.
   Draft/Released/Obsolete) — should I pull these from `MES_2.0_C01_Core_DB_Table_Schema` in
   the KB, or do you want to specify them directly?
5. This project's `PROJECT.md` currently records **Stage 1 (Analysis) complete, Stage 2
   (Requirements) next** — Stage 3 (Architecture & Design, where this design-system work
   formally lands) hasn't opened as a gate yet. Do you want to formally open Stage 3 now (via
   the toolkit's checkpoint-design.md brainstorm-first protocol), or is this look-and-feel
   conversation meant to run ahead of that gate as informal prep?
