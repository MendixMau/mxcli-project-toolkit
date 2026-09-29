## Design system

This is a Acme app, wired to the Acme company brain
(`<scratch>/acme-brain-real`, pointed to from
`CLAUDE.md`'s Company-brain block). Its routing table says: "Choosing a design system, theme, brand
colour or page shell for a Acme app → `components/Acme_Theme_Module.md`", and the house rule is explicit:
**never hand-roll a theme or a second design system for a Acme app.**

The design system to use is **`Acme_Theme_Module`** — a Mendix theme module package
(`components/Acme_Theme_Module.mpk`, 56 MB, build `0319`/2024-03-19, approved 2026-09-20). It ships:
- Brand SCSS variables (`themesource/acme_theme_module/web/acme-custom-variables.scss`)
- An Atlas layout override (`layouts/_layout-atlas.scss`)
- Per-component SCSS overrides (`_navigation-bar`, `_button`, `_card`, `_input`, `_list-view`,
  `_headings`, `_footer`, `_tab-container`, `_radio-button`, `_lang-selector`, `_base`)
- A `Button` design property with two options: `Acme blue` / `Acme red`

It is not currently imported into this project (no `themesource/acme_theme_module/` folder exists yet
under `Acme_Routing_Workshop`). Importing it is a prerequisite build step before the routing overview
page can be styled correctly — and the manifest flags that its own import method is **not yet verified
on any mxcli version** ("Proven in" table is empty), so the import needs a probe
(`./mxcli --help`, then the import subcommand's help) before it's attempted, not an assumed CLI command.

The theme's typeface is **Open Sans** (bundled with the module), not the corporate print typeface
(Helvetica LT Std) and not Atlas's default stack — this is a deliberate web/print split, not
something to "correct."

## Brand colours

All values and names below come from `components/Acme_Theme_Module.md`
(`acme-custom-variables.scss`), cross-referenced against the corporate brand guide
(`components/Acme-UI-UX-Guide-v2.0.pdf`, not opened page-by-page here — the manifest already states
the reconciliation). No hex value is hand-typed into any page per house convention #2; these are
theme variables to be referenced, not literals to copy into widget properties.

| Variable | Value | Meaning | Source |
|---|---|---|---|
| `$brand-primary` | `#0C4C8A` | UI primary — Pantone 541C, "Bright" palette | `Acme_Theme_Module.md` |
| `$brand-success` | `#437242` | Acme green (357C) | `Acme_Theme_Module.md` |
| `$brand-warning` | `#ed6d0f` | Acme orange (1565C) | `Acme_Theme_Module.md` |
| `$brand-danger` | `#e60012` | Acme red (485C) | `Acme_Theme_Module.md` |
| `$sidebar-bg` | `#24276c` | side navigation background | `Acme_Theme_Module.md` |
| `$topbar-bg` | `#FFFFFF` (70px height) | top bar | `Acme_Theme_Module.md` |
| `$bg-color` | `#f8f8f8` | page background | `Acme_Theme_Module.md` |
| `$font-family-base` | `"Open Sans", sans-serif` | typography | `Acme_Theme_Module.md` |
| `$border-radius-default` | `4px` | corner radius | `Acme_Theme_Module.md` |

**Deliberate deviation, do not "fix":** the brand guide's Corporate colour is Acme Blue, Pantone
655C, `#002662` — that is the logo/print blue. `$brand-primary` (`#0C4C8A`, Pantone 541C) is the
correct on-screen primary; all four theme brand colours are consistently drawn from the guide's
Extended → Bright row, not the Corporate row. `#002662` should never be substituted into
`$brand-primary`.

Buttons use the theme's **Button Style** design property (`acme-blue` / `acme-red`), never Atlas's
default button styles and never a hand-rolled class, per house convention #3.

## Page plan

Sketch of **Routing_Overview**, per BRD `F001-routing-overview.brd.json` (UC001) and house page
naming convention #7 (`<Entity>_Overview`):

- **Layout:** `Atlas_Core.Atlas_Default`, with the Acme theme's Atlas layout override applied
  (top bar white/70px, sidebar `#24276c`, page background `#f8f8f8`).
- **Header / title bar:** "Routing Catalogue" heading, styled by the theme's `_headings.scss`.
- **SearchFilters section** (top): filter by Site, Product Family, and Lifecycle State — the three
  fields UC001's main flow names ("search routing headers by site, product family, or lifecycle
  state"). A primary "Search" action button using the **Acme blue** button style.
- **ReleasedContextSummary section**: a status banner above or beside the grid, sourced from
  `GET_ReleasedRoutingContext` (bound to `RouteResolverReadModel`), using `$brand-success` /
  `$brand-warning` / `$brand-danger` for released/pending/blocked state indicators rather than any
  hand-typed colour — open question F001-RO-1 (below) affects exactly what this banner shows.
- **ResultGrid section**: a data grid over `RoutingReadModel` (via `GET_Routing_List`), columns
  drawn from its BRD attributes: RoutingCode, RoutingNameDefault, LifecycleState, ReleaseStatus,
  IsCurrent, ProductFamilyCode, CustomerCode, EffectiveFrom/EffectiveTo. Row click drills into
  `Routing_View` via `GET_Routing_Detail`, per house page-naming convention (`Routing_View`
  already named in the BRD).
- **Empty/loading states**: styled by the theme's `_list-view.scss`, no custom CSS.

This is a page *plan* only — no MDL has been written or executed, per the task's preparation-only
scope. Before the first widget is actually built, `skills/ui-preflight-pages.md` (wireframe → tokens
→ StyleGallery) and `skills/module-brief.md` still apply on top of this theme choice, and a proper
annotated wireframe under `design/wireframes/Routing_Overview.html` is the toolkit's expected
Stage-3 deliverable (not yet produced — `design/` doesn't exist in this project yet).

## Files I read

1. `<scratch>/cb-eval3/treatment/Acme_Routing_Workshop/PROJECT.md`
2. `<scratch>/cb-eval3/treatment/Acme_Routing_Workshop/intake.md`
3. `<scratch>/cb-eval3/treatment/Acme_Routing_Workshop/CLAUDE.md`
4. `<scratch>/cb-eval3/treatment/Acme_Routing_Workshop/CLAUDE.local.md`
5. `<scratch>/cb-eval3/treatment/Acme_Routing_Workshop` (directory listing — no `docs/progress/RESUME.md` present)
6. `<scratch>/acme-brain-real` (directory listing)
7. `<scratch>/acme-brain-real/ROUTING.md`
8. `<scratch>/acme-brain-real/README.md`
9. `<scratch>/acme-brain-real/components/Acme_Theme_Module.md`
10. `<scratch>/acme-brain-real/components/` and `<scratch>/acme-brain-real/skills/` (directory listings)
11. `<scratch>/acme-brain-real/skills/house-page-conventions.md`
12. `<scratch>/cb-eval3/treatment/Acme_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`

(The corporate brand-guide PDF, `components/Acme-UI-UX-Guide-v2.0.pdf`, was not opened directly — the
`Acme_Theme_Module.md` manifest already states the reconciliation between the guide's Corporate blue
and the theme's on-screen primary; flagged as an open question below in case the user wants it
opened directly.)

## Open questions for the user

1. **Theme import not yet verified for this mxcli version.** `Acme_Theme_Module.md` says the import
   method (CLI / MCP / Studio Pro) has never been confirmed working on any mxcli version, and this
   would be the first project to do it. Should I probe `./mxcli --help` / the import subcommand's
   help now and report back before anyone attempts the import, or do you want to import it via
   Studio Pro yourself first?
2. **F001-RO-1 (already open in `PROJECT.md`):** should `GetReleasedRoutingContext` populate both
   `Routing_Overview`'s `ReleasedContextSummary` banner and `Routing_View`'s released-context
   banner with the same data, or is one of those meant to be route-specific? This changes what the
   ReleasedContextSummary section on the overview page actually shows.
3. Do you want the full annotated wireframe (`design/wireframes/Routing_Overview.html`) built next,
   per the toolkit's `ui-preflight-pages.md` / `design-artifacts.md` convention, before any MDL is
   written for this page — or is this plain-language sketch sufficient to move straight to build?
4. Should I open the corporate `Acme-UI-UX-Guide-v2.0.pdf` directly to confirm the Bright-palette
   reconciliation myself, or is the manifest's stated deviation (already verified 2026-09-20)
   sufficient?
