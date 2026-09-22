# Look-and-feel for Routing_Overview — preparation only, no MDL written

## Design system

This is a USI app, wired to the company brain (`projects.tsv` lists this project root). The
brain's `ROUTING.md` is explicit: "Choosing a design system, theme, brand colour or page shell for
a USI app" → `components/USI_Theme_Module.md`. That manifest is equally explicit: **"Never
hand-roll a theme or a second design system for a USI app."** So there is no design-system
*decision* to make here — the design system is the imported Mendix module `USI_Theme_Module`
(`USI_Theme_Module.mpk`, 56 MB, model timestamp 2024-03-19), which adds an Atlas layout override
plus per-component SCSS under `themesource/usi_theme_module/`. The house rule
(`skills/house-page-conventions.md`) reinforces it: never type a hex value into a page — every
colour comes from the module's brand variables or a documented extended-palette entry, and
buttons use the module's own "USI blue" / "USI red" Button Style property rather than Atlas
defaults.

**Status check:** the module is not yet imported into this project — no `design/` folder,
`themesource/usi_theme_module/`, or `architecture/` exists yet (this project is at Stage 1 done /
Stage 2 next per `PROJECT.md`), and the manifest's own "Proven in" table is empty — no project has
imported it on any mxcli version yet. Import is a real step (full module export bundling
CommunityCommons, Email Connector, Encryption, OIDC, OQL, several Datagrid widgets, ~40 userlib
jars — not a plain widget), and the manifest says to probe `./mxcli --help` / the import
subcommand's help before picking CLI vs MCP vs Studio Pro rather than assuming from memory.

## Brand colours

All values are read directly out of `components/USI_Theme_Module.md`
(`themesource/usi_theme_module/web/usi-custom-variables.scss`) in the company brain — not
invented, not taken from the print brand guide:

| Token (SCSS variable) | Value | Use |
|---|---|---|
| `$brand-primary` | `#0C4C8A` | UI primary — Pantone 541C, the *on-screen* brand blue |
| `$brand-success` | `#437242` | USI green |
| `$brand-warning` | `#ed6d0f` | USI orange |
| `$brand-danger` | `#e60012` | USI red |
| `$sidebar-bg` | `#24276c` | side navigation |
| `$topbar-bg` | `#FFFFFF` (70px height) | top bar |
| `$bg-color` | `#f8f8f8` | page background |
| `$font-family-base` | `"Open Sans", sans-serif` | typography, shipped by the module |
| `$border-radius-default` | `4px` | |

**One documented, deliberate deviation, not to be "corrected":** the corporate print guide
(`USI-UI-UX-Guide-v2.0.pdf`, beside the manifest) names Corporate = USI Blue, Pantone 655C,
`#002662`. The theme's `$brand-primary` is `#0C4C8A` (Pantone 541C) instead — all four theme
brand colours are taken from the guide's Extended → Bright row (541C blue / 485C red `#e60012` /
1565C orange `#ed6d0f` / 357C green `#437242`), consistently. `#002662` is the logo/print blue;
`#0C4C8A` is the correct on-screen primary. Likewise typography: the guide's print typeface is
Helvetica LT Std, the web theme intentionally ships Open Sans instead. Both are confirmed
deviations per the manifest (verified 2026-09-20), not gaps to fill.

## Page plan

Sketch for `RoutingManagement.Routing_Overview`, on `Atlas_Core.Atlas_Default` + the USI theme
override, built from the confirmed BRD (`F001-routing-overview.brd.json`, UC001) and the module's
`pages[0]` entry, which already names the three sections:

1. **Top bar / shell** — USI theme top bar (`$topbar-bg` white, 70px) with the USI logo (master
   artwork only, never redrawn) and side navigation in `$sidebar-bg` (`#24276c`), per the house
   convention.
2. **SearchFilters** (page header block) — filter row over `RoutingSearch_Dto`: Site, Product
   Family, Lifecycle State (the BRD's "search routing headers by site, product family, or
   lifecycle state"). Built from the project's own filter widgets already in
   `widgets-inventory.txt` (`DatagridTextFilter`, `DatagridDropdownFilter`, `DatagridDateFilter`)
   rather than a custom filter bar. Primary "Search" action uses the theme's `usi-blue` button
   style.
3. **ReleasedContextSummary** — a status/context strip above or beside the grid, sourced from
   `GET_ReleasedRoutingContext` (open question F001-RO-1 below affects exactly this section).
   Lifecycle-state chips coloured via the theme's semantic variables only (`$brand-success` for
   released/current, `$brand-warning` for pending/superseded-soon, `$brand-danger` for
   deprecated/blocked) — never a hand-typed hex per state.
4. **ResultGrid** — `com.mendix.widget.web.Datagrid` bound to `GET_Routing_List` (
   `RoutingReadModel`), columns: RoutingCode, RoutingName(Default), RoutingType,
   ProductFamilyCode, OwnerTeam, SiteId, LifecycleState, VersionNo/IsCurrent, EffectiveFrom.
   Row click → `GET_Routing_Detail` → `Routing_View` (drilldown, out of scope for this sketch).
5. Empty/loading/error states styled with the theme's card and list-view overrides (`_card`,
   `_list-view`), not custom CSS, consistent with "style a component by using its class, never a
   competing rule."

This is a sketch for discussion, not a wireframe artifact — no `design/wireframes/` file has been
written, and no MDL/pages were created or modified.

## Files I read

1. `<scratch>/cb-eval3/treatment/USI_Routing_Workshop` (ls)
2. `<scratch>/cb-eval3/treatment/USI_Routing_Workshop/CLAUDE.md`
3. `<scratch>/cb-eval3/treatment/USI_Routing_Workshop/CLAUDE.local.md`
4. `<scratch>/cb-eval3/treatment/USI_Routing_Workshop/PROJECT.md`
5. `<scratch>/cb-eval3/treatment/USI_Routing_Workshop/AGENTS.md` (diffed against CLAUDE.md — identical)
6. `<scratch>/cb-eval3/treatment/USI_Routing_Workshop/analysis` (find, listing)
7. `<scratch>/usi-brain-real` (ls) and `ROUTING.md`
8. `<scratch>/usi-brain-real/components/` (ls)
9. `<scratch>/usi-brain-real/components/USI_Theme_Module.md`
10. `<scratch>/usi-brain-real/skills/` (ls)
11. `<scratch>/usi-brain-real/skills/house-page-conventions.md`
12. `<scratch>/usi-brain-real/components/README.md`
13. `<scratch>/cb-eval3/treatment/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`
14. `<home>/mxcli-project-toolkit/skills/design-artifacts.md` (read-only, to check the generic branding-interview process this company brain overrides)
15. `<scratch>/cb-eval3/treatment/USI_Routing_Workshop/widgets-inventory.txt`
16. `<scratch>/cb-eval3/treatment/USI_Routing_Workshop/intake.md` and `triage.md` (grepped for brand/design/colour/theme/logo — no hits)
17. `<scratch>/usi-brain-real/projects.tsv`

## Open questions for the user

1. **Import order.** `USI_Theme_Module.mpk` has never been imported into any project yet (its
   "Proven in" table is empty). Should I probe this project's `./mxcli` import surface and get the
   module imported as the first concrete step of Stage 2/3 design work, before any wireframe is
   turned into real pages?
2. **Stage discipline.** Requirements are "nearly closed" but `PROJECT.md` still shows Stage 1
   complete / Stage 2 next, and no `design/` or `architecture/` artifacts exist yet. This sketch is
   informal prep, not the Stage 3 `design-artifacts.md` deliverable set (design system doc,
   `brand.md`, one wireframe per screen, Atlas variable mapping). Do you want me to treat this as
   the real Stage 3 kickoff (open the branding interview per the runbook, even though the brand
   basis is already fixed by house convention) once Stage 2 closes, or keep it purely exploratory
   for now?
3. **ReleasedContextSummary scope (F001-RO-1, already an open BRD question):** does
   `GET_ReleasedRoutingContext` populate this Overview summary and the `Routing_View` banner
   identically, or is one of them meant to be route-specific? That decides whether the summary
   strip in the plan above is global-context or per-row.
4. **Grid density/columns** — the BRD's `RoutingReadModel` has ~20 fields; I picked 9 for the grid
   based on the BRD's stated search criteria (site/product family/lifecycle state) plus obvious
   identifying fields. Confirm the column set before it's locked into a wireframe.
