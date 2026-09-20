## Design system

**`USI_Theme_Module`** — the company-brain-approved Mendix theme module, not a bespoke or Atlas-default theme.

- Source of the rule: this project's `CLAUDE.local.md` wires a USI company brain at
  `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real`, whose `ROUTING.md` routes
  "choosing a design system, theme, brand colour or page shell for a USI app" to
  `components/USI_Theme_Module.md`.
- That manifest and `skills/house-page-conventions.md` are explicit: **never hand-roll a theme
  or a second design system for a USI app** — import `USI_Theme_Module.mpk` and build on
  `themesource/usi_theme_module/`. It's a full module export (brand SCSS variables, an Atlas
  layout override, per-component SCSS, a two-value Button Style design property), approved
  2026-09-20, not yet imported into this project.
- Import method is not yet decided: the manifest says to probe `./mxcli --help` / the import
  subcommand before choosing CLI, MCP, or Studio Pro — "not yet verified on any mxcli version."
  This is preparation only, so no import was performed.
- Typography: **Open Sans**, shipped by the module — not the brand guide's print typeface
  (Helvetica LT Std), which is intentional and documented as a deviation not to "fix."

## Brand colours

All values are from `USI_Theme_Module.md` → `themesource/usi_theme_module/web/usi-custom-variables.scss`
(the theme's actual SCSS variables — never hand-typed hex in a page):

| Use | Variable | Value |
|---|---|---|
| Primary / on-screen brand blue | `$brand-primary` | `#0C4C8A` |
| Success | `$brand-success` | `#437242` |
| Warning | `$brand-warning` | `#ed6d0f` |
| Danger | `$brand-danger` | `#e60012` |
| Side navigation background | `$sidebar-bg` | `#24276c` |
| Top bar background / height | `$topbar-bg` | `#FFFFFF` / `70px` |
| Page background | `$bg-color` | `#f8f8f8` |
| Border radius | `$border-radius-default` | `4px` |

**Deliberate deviation, do not "correct":** the corporate print/logo blue in the brand guide
(`USI-UI-UX-Guide-v2.0.pdf`, section on the Corporate palette) is Pantone 655C, `#002662`. The
theme's on-screen `$brand-primary` is `#0C4C8A` (Pantone 541C), because the theme uses the
guide's *Extended → Bright* row for all four brand colours (541C blue, 485C red `#e60012`,
1565C orange `#ed6d0f`, 357C green `#437242`) — verified consistent across all four, and
flagged in the manifest as a documented, intentional deviation. `#002662` stays reserved for
the logo/print artwork.

Buttons use the theme's **Button Style** design property (`usi-blue` / `usi-red`), not raw
colour classes.

## Page plan

**`Routing_Overview`** (module `RoutingManagement`), scope per `PROJECT.md` / `intake.md` /
BRD `F001` UC001 — read-only routing catalogue overview backed by `SearchRoutes` and
`GetReleasedRoutingContext`. Naming follows the house convention
`<Entity>_Overview` / `<Entity>_View`, matching the BRD's own screen names.

Layout, top to bottom, on the USI Atlas layout override:

1. **Page header** — title "Routing Catalogue", USI top bar (`$topbar-bg` white, 70px).
2. **Search / filter bar** (`Fieldset` widget, USI theme `_input`/`_fieldset` styling):
   - Site (`SiteId`) — dropdown filter (`DatagridDropdownFilter`)
   - Product family (`ProductFamilyCode`) — text filter (`DatagridTextFilter`)
   - Lifecycle state (`LifecycleState`) — dropdown filter (`DatagridDropdownFilter`)
   - free-text search on `RoutingCode` / `RoutingName`
3. **Routing list** — `Datagrid` (com.mendix.widget.web.Datagrid, already in
   `widgets-inventory.txt`), one row per `Routing`, columns:
   - `RoutingCode`, `RoutingName`, `RoutingType`, `ProductFamilyCode`, `OwnerTeam`, `SiteId`
   - `LifecycleState` rendered as a **Badge** (`Badge.mpk`), colour mapped to the theme's
     semantic variables (e.g. Released → `$brand-success`, Draft/Pending → `$brand-warning`,
     Retired/Rejected → `$brand-danger`), never a typed hex.
   - Row click → opens `Routing_View` passing the selected `Routing` (drilldown per BRD
     mainFlow step 3).
4. **Empty/loading states** styled with the theme's `_list-view` overrides, USI page background
   (`$bg-color`).
5. Primary actions (e.g. "Search") use the **USI blue** button style; no destructive actions on
   this page (read-only scope — no create/edit/delete per the confirmed scope cut).

`Routing_View` (drilldown target) is out of scope for this sketch — user asked specifically
for the overview screen — but is named and referenced above for continuity since BRD UC001
treats the two as one flow.

## Files I read

1. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/CLAUDE.md`
2. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/CLAUDE.local.md`
3. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/PROJECT.md`
4. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/README.md`
5. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/ROUTING.md`
6. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/components/USI_Theme_Module.md`
7. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/skills/house-page-conventions.md`
8. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/intake.md`
9. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`
10. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/treatment/USI_Routing_Workshop/widgets-inventory.txt`

(Directory listings of the project root and `analysis/` were also run but are not file reads.)

## Open questions for the user

1. **`USI_Theme_Module` is not yet imported into this project.** Import it before building any
   page — confirm CLI vs MCP vs Studio Pro import method (the manifest says to probe the
   installed `mxcli` binary first; it's "not yet verified on any mxcli version").
2. **Requirements aren't actually closed yet** — `PROJECT.md` shows Stage 1 complete, Stage 2
   next, plus three open questions (D1–D3, e.g. which API-count document is authoritative) and
   one unresolved `ASSUMED` (fidelity). Confirm you want design work to proceed in parallel
   with Stage 2 rather than gating on it.
3. **Lifecycle-state → badge colour mapping** — I proposed Released/Draft/Retired →
   green/orange/red by convention; confirm against the actual `LifecycleState` enum values
   once modeled (BRD only types it as a 30-char string, no enum list given yet).
4. Should `Routing_View` (the drilldown screen) be sketched now too, or only after
   `Routing_Overview` is confirmed?
