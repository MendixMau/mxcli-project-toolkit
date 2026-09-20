## Design system

This is a USI app, so the design system question is already answered by the company brain, not something to re-derive: import **`USI_Theme_Module`** (`usi-brain-real/components/USI_Theme_Module.mpk`, module package, dated build `0319`) and build the routing overview on top of it — no hand-rolled theme or second design system is permitted for a USI app (`skills/house-page-conventions.md` rule 1). It adds `themesource/usi_theme_module/`: brand SCSS variables, an Atlas layout override, and per-component overrides for navigation bar, buttons, cards, inputs, list view, headings, footer, tab container, radio button and language selector — plus a Button Style design property with two approved options (`usi-blue`, `usi-red`).

Install note for whoever builds this: the module is a full project export (bundles CommunityCommons, Email Connector, Encryption, OIDC, OQL, several Datagrid widgets, ~40 userlib jars), not a plain widget — probe `./mxcli --help` / the import subcommand's own help before choosing CLI, MCP or Studio Pro, since the manifest says this has not yet been verified against any mxcli version.

## Brand colours

Source: `usi-brain-real/components/USI_Theme_Module.md` (the manifest, which documents `themesource/usi_theme_module/web/usi-custom-variables.scss`), cross-checked against `USI-UI-UX-Guide-v2.0.pdf` beside it.

| Token | Value | Use |
|---|---|---|
| `$brand-primary` | `#0C4C8A` | UI primary (buttons, links, active states) |
| `$brand-success` | `#437242` | success/positive status |
| `$brand-warning` | `#ed6d0f` | warning status |
| `$brand-danger` | `#e60012` | error/danger status |
| `$sidebar-bg` | `#24276c` | side navigation background |
| `$topbar-bg` | `#FFFFFF` (70px height) | top bar |
| `$bg-color` | `#f8f8f8` | page background |
| `$font-family-base` | "Open Sans", sans-serif | all text |
| `$border-radius-default` | `4px` | buttons, cards, inputs |

**Deliberate deviation — do not "fix":** the brand guide's print Corporate colour is USI Blue, Pantone 655C, `#002662` (logo/print use only). The theme's on-screen `$brand-primary` is `#0C4C8A`, Pantone 541C from the guide's Extended → Bright row, and all four theme brand colours (541C blue, 485C red, 1565C orange, 357C green) are consistently drawn from that Bright row. This is verified/approved (2026-09-20), not a bug to reconcile. Same logic for typography: the guide's print typeface is Helvetica LT Std; the web theme intentionally ships Open Sans instead.

No hex value gets typed directly into a page or page stylesheet — every colour is used via the theme's brand variables or Button Style design property (`house-page-conventions.md` rules 2–3). The USI logo is artwork only (master files from the corporate identity download); it is never recreated, re-typeset, or altered on the overview page.

## Page plan

Screen: **`Routing_Overview`** (module `RoutingManagement`, layout `Atlas_Core.Atlas_Default`), per the confirmed F001/UC001 BRD (`analysis/knowledge-base/brd/F001-routing-overview.brd.json`). Naming follows the house convention `<Entity>_Overview`.

Data context: `RoutingSearch_Dto`. Actors: Manufacturing Process Engineer, Supervisor, Line Leader (read-only, `C01.ROUTE.READ` scope).

1. **Top bar / nav shell** — USI theme top bar (`$topbar-bg` #FFFFFF, 70px) with the USI logo artwork left-aligned; side navigation in `$sidebar-bg` (#24276c) per the imported theme, not custom-built.
2. **Page header** — "Routing Overview" heading (theme `_headings` override, Open Sans), short description line.
3. **Search / filter bar** (BRD section `SearchFilters`) — filters routing headers by Site, Product Family, and Lifecycle State, feeding `GET_Routing_List (RoutingSearch_Dto)`. Built with the theme's `_input` styling; a primary "Search" action button uses Button Style `usi-blue`.
4. **Released-context summary strip** (BRD section `ReleasedContextSummary`) — a compact status banner sourced from `GET_ReleasedRoutingContext`, using status badges (Badge widget is available per `widgets-inventory.txt`) coloured via `$brand-success` / `$brand-warning` / `$brand-danger` for lifecycle/release state, never raw hex. Open question F001-RO-1 (below) affects exactly this section.
5. **Result grid** (BRD section `ResultGrid`) — Data Grid 2 (`com.mendix.widget.web.Datagrid` + its Text/Dropdown/Date/Number filter widgets, all present in `widgets-inventory.txt`) over `RoutingReadModel`, columns: Routing Code, Routing Name, Routing Type, Product Family, Owner Team, Site, Lifecycle State (as a status badge), Current Version, Release Status. Row click drills into `Routing_View` via `GET_Routing_Detail`.
6. **Empty/loading states** — theme `_card` styling for a "no routes match your filters" empty state; no custom colours.

Buttons throughout: theme's `usi-blue` for primary actions (Search, row navigation), `usi-red` reserved for destructive/reset actions only — this screen is read-only, so `usi-red` likely only appears on a "Clear filters" action if styled that way, otherwise a secondary/neutral style.

## Files I read

1. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/CLAUDE.md`
2. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/CLAUDE.local.md`
3. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/ROUTING.md`
4. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/components/USI_Theme_Module.md`
5. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/PROJECT.md`
6. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/analysis` (directory listing)
7. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`
8. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/skills/house-page-conventions.md`
9. `/home/user/mxcli-project-toolkit/skills/design-artifacts.md` (partial, for wireframe/branding-interview convention — superseded here by the company brain's fixed theme)
10. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/widgets-inventory.txt`

(Also listed, not fully read: `usi-brain-real/` top-level directory and `components/` directory for file inventory.)

## Open questions for the user

1. **F001-RO-1 (already logged, unresolved):** should `GetReleasedRoutingContext` populate both `Routing_Overview`'s `ReleasedContextSummary` and `Routing_View`'s released-context banner, or is one of those meant to be route-specific? This decides whether the overview's summary strip is a global/site banner or reacts to the current filter/selection.
2. The `USI_Theme_Module.mpk` install method has never been verified against this project's mxcli version (manifest says "not yet verified on any mxcli version, first project to import it fills this in"). Before build starts: should we probe CLI/MCP import support now, or default to Studio Pro import if the probe comes back negative?
3. Requirements are "nearly closed" but Stage was last recorded as Stage 1 complete / Stage 2 next in `PROJECT.md`, and no `architecture/`, `design/wireframes/`, or `design/ds.css` directories exist yet in this project. Do you want me to run this as a formal Stage 3 design-artifacts pass (wireframe HTML + ds.css referencing the theme tokens) before any page gets built, or is this plain-language sketch sufficient to proceed straight to `Routing_Overview` construction?
4. Three open data-provenance questions (D1 API count conflict, D2 document-version conflict, D3 whether Artifact 14 supersedes processed docs) are still unresolved in `PROJECT.md` — none of them block the look-and-feel decision, but they may affect exact field/column names on the grid before build. Confirm these can stay open through the design pass?
