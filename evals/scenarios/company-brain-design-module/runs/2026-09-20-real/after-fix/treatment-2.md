# Routing overview — design system, brand and page plan

## Design system

This is a USI app, so it uses the company brain's design system, not a bespoke one:
**`USI_Theme_Module`** (`.../usi-brain-real/components/USI_Theme_Module.mpk`), imported as its
own Mendix module. It's an Atlas layout override plus brand SCSS variables and per-component
SCSS overrides (`_navigation-bar`, `_button`, `_card`, `_input`, `_list-view`, `_headings`,
`_footer`, `_tab-container`, `_radio-button`, `_lang-selector`, `_base`,
`layouts/_layout-atlas.scss`) living under `themesource/usi_theme_module/`. Typography is
**Open Sans**, shipped by the module — not the brand guide's print typeface (Helvetica LT Std),
which is intentionally not used on the web.

House rule (`house-page-conventions.md`): never hand-roll a theme, never type a hex value into
a page — every colour comes from the module's brand variables or a documented extended-palette
entry — and buttons use the theme's own **Button Style** design property (`USI blue` /
`USI red`), not Atlas defaults or a custom class.

**Not yet verified**: the manifest flags that this package has never been imported by any
project via mxcli (`Proven in` table is empty) and that the import method (CLI/MCP/Studio Pro)
must be probed against this project's actual `mxcli --help` / import-subcommand help before
attempting it — "not yet verified" is a real gap, not boilerplate.

## Brand colours

All values are asserted, none hand-picked, and all come from one source:
`usi-brain-real/components/USI_Theme_Module.md` (`themesource/usi_theme_module/web/usi-custom-variables.scss`), cross-checked against the deviation note in that same file.

| Token | Value | Source / role |
|---|---|---|
| `$brand-primary` | `#0C4C8A` | On-screen primary. **Not** the print corporate blue — see deviation note below. |
| `$brand-success` | `#437242` | USI green |
| `$brand-warning` | `#ed6d0f` | USI orange |
| `$brand-danger` | `#e60012` | USI red |
| `$sidebar-bg` | `#24276c` | Side navigation |
| `$topbar-bg` | `#FFFFFF` (height `70px`) | Top bar |
| `$bg-color` | `#f8f8f8` | Page background |
| `$border-radius-default` | `4px` | |
| Font | "Open Sans", sans-serif | Bundled with the module |

**Deviation to leave alone**: the corporate brand guide's print "Corporate" colour is USI Blue
Pantone 655C, `#002662` — that's the logo/print blue, not what the theme uses on screen. The
theme's `$brand-primary` (`#0C4C8A`) is Pantone 541C from the guide's Extended → Bright row, and
all four brand colours above are consistently drawn from that same Bright row (541C blue, 485C
red, 1565C orange, 357C green). The manifest explicitly warns against "correcting" this — doing
so would break, not fix, the theme. I'm using the theme's values as-is.

Logo: artwork only, from the corporate identity download — never recreated or re-typeset
(`USI-UI-UX-Guide-v2.0.pdf`, section 01, referenced from the manifest).

## Page plan

Scope, per `PROJECT.md` and `analysis/knowledge-base/brd/F001-routing-overview.brd.json`
(UC001): a read-only routing catalogue overview + drilldown, backed by 7 governed GET endpoints,
for actors ManufacturingProcessEngineer / Supervisor / LineLeader.

**`Routing_Overview`** (module `RoutingManagement`, naming per house convention
`<Entity>_Overview`)
- Top bar / side nav: theme defaults (`$topbar-bg` white 70px, `$sidebar-bg` `#24276c`), no
  custom styling.
- Search/filter bar: site, product family, lifecycle state — backs `SearchRoutes`. Standard
  Atlas input styling from the theme's `_input` override, no inline colours.
- Data grid (list of `Routing` headers): columns RoutingCode, RoutingName, RoutingType,
  ProductFamilyCode, SiteId, LifecycleState, OwnerTeam. Uses the theme's `_list-view`/card
  styling; lifecycle-state values could map to badge colours drawn only from
  `$brand-success`/`$brand-warning`/`$brand-danger` (e.g. Released = success, Draft = warning,
  Retired = danger) — to be confirmed with the user, not invented here.
- Row click → navigates to `Routing_View` (drilldown), per UC001 main flow step 3.
- Primary actions on this screen are navigation-only (read-only scope C01.ROUTE.READ) — no
  create/edit buttons; if any button is needed (e.g. "Refresh", "Export") it uses the theme's
  `USI blue` button style.

**`Routing_View`** (drilldown, per house naming `<Entity>_View`)
- Header section (DataView on `Routing`): RoutingCode/Name/Type, OwnerTeam, SiteId,
  LifecycleState, CanonicalId — theme `_headings`/`_card` styling.
- Version summary (list of `RoutingVersion`): VersionNo, RevisionCode, IsCurrent,
  EffectiveFrom/To, ReleaseStatus — backs `ListRouteVersions` / `GetRouteVersionDetail`.
- Released/effective context panel — backs `GetReleasedRoutingContext` and
  `ListRoutingEffectivities`.
- Route graph detail — backs `GetRouteGraphReadModel`; likely a tab (theme's
  `_tab-container` override) alongside version/effectivity, exact widget TBD once the graph
  read-model shape is reviewed.
- Back-navigation to `Routing_Overview`.

Nothing here is built yet — this is a sketch to confirm before any MDL is written, per the
task's "preparation only" instruction.

## Files I read

1. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval3/treatment/USI_Routing_Workshop/CLAUDE.md`
2. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/ROUTING.md`
3. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/components/USI_Theme_Module.md`
4. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/usi-brain-real/skills/house-page-conventions.md`
5. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval3/treatment/USI_Routing_Workshop/PROJECT.md`
6. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval3/treatment/USI_Routing_Workshop/intake.md`
7. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval3/treatment/USI_Routing_Workshop/triage.md`
8. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval3/treatment/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`

(`CLAUDE.local.md`, `AGENTS.md`, and `widgets-inventory.txt` exist in the project root but were
not opened — `CLAUDE.md` states it is the canonical instruction file and the others are pointers
to it; the company-brain block inside `CLAUDE.md` was the operative pointer for this task, and it
was followed directly.)

## Open questions for the user

1. **Import method for `USI_Theme_Module.mpk`** — it's a full module export (`.mpr` + brand
   assets + ~40 bundled jars/widgets), never imported by any project via mxcli before. Should I
   probe `./mxcli --help` / the import subcommand for this project's mxcli version before doing
   the actual import, or would you rather do that import yourself in Studio Pro?
2. **Lifecycle-state → colour mapping** on `Routing_Overview`'s grid (e.g. Released=success,
   Draft=warning, Retired=danger) — I proposed one above but the BRD doesn't specify it; please
   confirm or correct the mapping.
3. **Route graph widget** on `Routing_View` — is a simple read-only list/tree acceptable for the
   `GetRouteGraphReadModel` data, or does this need an actual graph-rendering widget? The BRD
   doesn't specify presentation, only that the data must be shown.
4. Should the theme import (and any resulting jar/widget bloat it brings — CommunityCommons,
   Email Connector, Encryption, OIDC, OQL, several Datagrid widgets) be flagged as a decision to
   record in `PROJECT.md`, given this is a POC/demo project favouring speed and a minimal
   footprint?
