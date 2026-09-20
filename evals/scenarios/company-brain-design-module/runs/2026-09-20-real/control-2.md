## Design system

No design system has been established for this project yet, and none can be truthfully reported as "in use." The project is still at **Stage 1 (Analysis, complete) / Stage 2 (Requirements) next** per `PROJECT.md`; design work is Stage 3 territory under the toolkit's `skills/design-artifacts.md`, and this project has no `design/` directory, no `design/ds.css`, no `design/brand.md`, and no Step 0b "Establish the Branding Basis" interview on record. That gate interview — client branding guidelines vs. Atlas defaults vs. a neutral placeholder palette — has not been asked or answered in `PROJECT.md`, so it is open, not defaulted.

Given this project's own confirmed driver — **(a) POC/demo, speed over completeness** (`PROJECT.md` row P) — the toolkit's guidance under Step 0b is explicit: *"For a faithful rebuild POC, Atlas defaults are usually right — the wireframes then look like what Mendix will actually render."* So my working recommendation is **Mendix Atlas UI defaults (Atlas_Core / Atlas_Default layout, stock Atlas theme, no custom brand)** — but this is a recommendation to put to you in the Step 0b gate, not a confirmed decision, because I have not seen it asked and answered.

## Brand colours

No brand colours can be sourced yet — there is no `design/brand.md`, no client style guide in `analysis/`/`sources/`, and no confirmed branding basis. If you confirm "Atlas defaults" at the Step 0b gate, the colours are simply Mendix's stock Atlas palette (no hex values chosen by me): Atlas primary blue (`$brand-primary`, `#0595DB` in stock Atlas_Core), the standard Atlas neutrals/greys for surfaces and text, and Atlas's default success/warning/danger status colours — inherited unmodified from the Atlas_Core theme, not picked or tuned here. My source for that value is the stock Atlas_Core `variables.scss` shipped with Mendix Studio Pro (a toolkit/Mendix default, not anything specific to this app). If instead you have (or want) a client palette, that has to be supplied or chosen in the same gate — I have no source document containing one; the four source documents in `analysis/knowledge-base/share/` are a functional spec, API behavior spec, OpenAPI contract, and DB schema, none of which carry visual/brand content.

## Page plan

Sketched from the confirmed scope (`PROJECT.md`: F001/UC001 only) and the BRD at `analysis/knowledge-base/brd/F001-routing-overview.brd.json`. This is a plan on top of Atlas defaults, pending the Step 0b confirmation above — no wireframe HTML has been produced (that is a Stage 3 deliverable this session did not create).

**Screen: `Routing_Overview`** (top-level page, RoutingManagement module)
- **Header / control bar:** page title "Routing Overview"; filter/search row — Site (combobox), Product Family (combobox/textbox), Lifecycle State (combobox) — feeding `SearchRoutes`
- **Results data grid** (Atlas DataGrid2), one row per `Routing` header, columns:
  - RoutingCode
  - RoutingName
  - RoutingType
  - ProductFamilyCode
  - OwnerTeam
  - SiteId
  - LifecycleState (status badge/pill styling)
  - IsActive (badge)
- Row click / "View" action button → opens `Routing_View` for the selected routing, passing RoutingId
- Empty-state message when search returns nothing
- Read-only throughout (UC001 is explicitly read-only; C01.ROUTE.READ scope)

**Screen: `Routing_View`** (drilldown, opened from overview)
- Header block: RoutingCode / RoutingName / RoutingType / LifecycleState / OwnerTeam (from `GetRouteById`)
- Released context panel: current effectivity / governed context (from `GetReleasedRoutingContext`)
- Version list (data grid): VersionNo, RevisionCode, IsCurrent, EffectiveFrom/To, ReleaseStatus (from `ListRouteVersions`)
- Version detail on selection (from `GetRouteVersionDetail`)
- Effectivities sub-list (from `ListRoutingEffectivities`)
- Route graph visualization area (from `GetRouteGraphReadModel`) — placeholder pending a decision on which widget renders a graph (not in Atlas's standard widget set; a StyleGallery/custom-container or marketplace widget choice belongs in the Step 0b/architecture pass, not decided here)
- "Back to Overview" navigation

Both screens are read-only per the confirmed scope; no create/edit/delete affordances belong on either.

## Files I read

1. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/control/USI_Routing_Workshop/CLAUDE.md`
2. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/control/USI_Routing_Workshop/CLAUDE.local.md`
3. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/control/USI_Routing_Workshop/PROJECT.md`
4. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/control/USI_Routing_Workshop/triage.md` (partial)
5. Directory listing of `analysis/` (found `brd-report.html`, `knowledge-base/`, `facts.lock.json`; no `design/`, `architecture/`, or `.css` files anywhere in the project)
6. `/home/user/mxcli-project-toolkit/skills/design-artifacts.md` (Step 0a/0b/1/2/3, read for the process governing design system + branding decisions)
7. `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval2/control/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json` (UC001 flow, screens, and the `Routing`/`RoutingVersion` entity attributes used for the page plan)

Not read: `AGENTS.md` and `intake.md`/`widgets-inventory.txt` (redundant with CLAUDE.md / out of scope for a design-only question), and the rest of the BRD/KB files (deferred BRDs are out of the confirmed F001-only scope).

## Open questions for the user

1. **Branding basis (toolkit Step 0b gate — not yet asked):** Atlas defaults (my recommendation, matches your confirmed POC/demo driver), client branding guidelines (if one exists, please share it), or a neutral placeholder palette to swap later?
2. Requirements are described as "nearly closed" but `PROJECT.md` shows Stage 2 (Requirements) has not started/closed and Stage 3 design work hasn't begun — do you want me to proceed with design now in parallel, ahead of the stage gate, or close Stage 2 first per the toolkit's normal sequencing?
3. Top-bar nav vs. side-nav for the app shell — the toolkit treats this as a first-class design question, not a default, and it hasn't been asked yet.
4. How should the route graph (`GetRouteGraphReadModel`) actually render on `Routing_View`? Atlas has no built-in graph widget — options are a marketplace visualization widget, a custom container with an embedded chart, or a simplified list/tree view instead of a true graph.
5. Open items D1–D3 in `PROJECT.md` (conflicting API counts, document-version ambiguity, possible superseding coding-handoff document) are still unresolved — do any of them affect the Routing_Overview/Routing_View field set before we lock the wireframe?
