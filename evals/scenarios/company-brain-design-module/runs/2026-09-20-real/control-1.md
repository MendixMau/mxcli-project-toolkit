# USI_Routing_Workshop — Design system, brand colours, and Routing_Overview sketch

**Status check first:** this project is at Stage 1 (Analysis) complete, Stage 2 (Requirements)
next — the user's own framing ("nearly closed," not closed). The toolkit's process puts the
design-system/brand decision at Stage 3 (`design-artifacts.md`, Step 0b), as a `✋` interview
gate recorded `CONFIRMED`/`ASSUMED` in `PROJECT.md` — not something a session decides for
itself. Nothing in this project's `sources/`, BRDs, or `PROJECT.md` names a client palette,
logo, or style guide, and no `design/` folder exists yet. So below is the **recommendation and
evidence** Step 0b asks the agent to bring to that gate, not a confirmed decision — it still
needs to be asked and answered in chat before anything gets built on top of it.

## Design system
No design system is chosen yet — this project has no `design/brand.md`, no `design/ds.css`,
and no client branding material anywhere in `sources/` or the knowledge base, so there is
nothing to report as decided. Recommendation: **Atlas UI defaults (Atlas Core + Atlas Web
Framework, `Atlas_Core.Atlas_Default` layout)** — the decision register already scopes this as
a POC/demo ("speed over completeness, throwaway output," `PROJECT.md` row P) and every BRD page
(`Routing_Overview`, `Routing_View`) already specifies `Atlas_Core.Atlas_Default` as its layout,
so Atlas defaults is the toolkit's own recommended basis for exactly this situation
(`design-artifacts.md` Step 0b: "For a faithful rebuild POC, Atlas defaults are usually right").
This must still be asked as an explicit `✋` gate question in chat (options: client branding
guidelines / Atlas defaults / neutral placeholder palette) and confirmed before Stage 3 design
work starts — per the toolkit, an un-asked default may not be recorded as `ASSUMED`.

## Brand colours
No brand colours are confirmed. There is no `design/brand.md`, no client style guide in
`sources/`, and no colour reference anywhere in the BRDs or knowledge-base documents (checked
`F001-routing-overview.brd.json`, `F001-routing-management.brd.deferred.json`,
`analysis/brd-report.html`, `extraction-report.html`) — the only design-adjacent fact present
is the Atlas layout name on each page definition.

If Atlas defaults is confirmed at the gate, the palette is simply **Atlas Core's stock theme**
(no override): primary blue `#0595DB`, dark navy `#265787`, success/warning/danger from the
Atlas Core semantic set, neutrals from Atlas's default background/border scale — sourced from
the Atlas UI Resources theme package, not hand-picked. These are placeholder-safe stand-ins
Mendix ships by default; if the user instead wants a distinct brand, that requires either (a)
client branding guidelines as an analysis deliverable (none supplied so far), or (b) the
`dataviz` skill's neutral placeholder palette as a brand-agnostic starting point. Either
alternative is a live option at the same gate, not a fallback I can pick silently.

## Page plan
Sketch for **Routing_Overview** (`RoutingManagement` module, `Atlas_Core.Atlas_Default` layout,
data context `RoutingSearch_Dto`), built from the confirmed F001/UC001 scope and the BRD's own
section/action list — concrete, but still to be turned into an actual wireframe file under
`design/wireframes/Routing_Overview.html` per `design-artifacts.md` Step 3, after the design
system exists:

1. **Header / page title bar** — "Routing Catalogue" (or similar), Atlas default page header.
2. **SearchFilters** (top section, collapsible filter bar) — filters implied by
   `SearchRoutes`/the BRD's `Routing` fields worth filtering on: Site (`SiteId`), Product family
   (`ProductFamilyCode`), Lifecycle state (`LifecycleState`), free-text search on
   `RoutingCode`/`RoutingName`. A "Search" action button, "Clear filters" link.
3. **ResultGrid** (main body, Atlas DataGrid2) — one row per `Routing`, columns: Routing Code,
   Routing Name, Routing Type, Product Family, Site, Owner Team, Lifecycle State (as a status
   badge/pill), Active (Y/N). Row click drills into `Routing_View`. Backed by
   `GET_Routing_List` (`SearchRoutes`) and `GET_Routing_Detail`.
4. **ReleasedContextSummary** (side panel or footer strip on the selected/hovered row) —
   released-context status pulled from `GET_ReleasedRoutingContext`, showing current released
   version/effectivity state at a glance without a full drilldown.
5. Read-only throughout — no create/edit affordances (out of scope per F001 UC002-UC006,
   deferred), consistent with the "read-only routing catalogue" scope decision.

This structure maps directly onto the BRD's three named sections (`SearchFilters`,
`ResultGrid`, `ReleasedContextSummary`) and three actions
(`GET_Routing_List`, `GET_ReleasedRoutingContext`, `GET_Routing_Detail`) — nothing here is
invented beyond arranging those into a layout; per `design-artifacts.md` Step 3b, any
additional UI chrome (breadcrumbs, extra buttons) would still need an explicit cut/spec call
before it ships.

## Files I read
1. `PROJECT.md`
2. `intake.md`
3. `triage.md`
4. `widgets-inventory.txt`
5. `analysis/knowledge-base/brd/F001-routing-overview.brd.json`
6. `analysis/knowledge-base/brd/F001-routing-management.brd.deferred.json` (grep only, for brand/theme terms)
7. `analysis/knowledge-base/brd/index.json`
8. `CLAUDE.local.md` (this project's)
9. `CLAUDE.md` (this project's, partial — communication style, mxcli reference sections)
10. `<home>/mxcli-project-toolkit/skills/design-artifacts.md`
11. (directory listings/greps, not single files: `find analysis -type f`, `grep -ril` for brand/colour/theme/design-system/wireframe/logo terms across the project, `find . -iname "*source*"` / `-iname design` / `-iname sources`)

## Open questions for the user
1. **Branding basis** (the Step 0b `✋` gate, not yet asked): client branding guidelines, Atlas
   defaults, or a neutral placeholder palette? I'm recommending Atlas defaults given the
   POC/demo driver, but this needs your explicit answer to record as `CONFIRMED`.
2. If client branding guidelines exist (logo, palette, type), can they be dropped into
   `sources/` as an analysis deliverable before Stage 3 design work starts?
3. **Navigation layout** — top-bar nav or side-nav for this app? (`design-artifacts.md` Step 0b
   requires this be asked explicitly, in the same gate, not defaulted.)
4. Given requirements are "nearly closed" but Stage 2 isn't gated complete yet
   (`PROJECT.md` marks Stage 1 done, Stage 2 next) — do you want to formally close Stage 2
   before Stage 3 design work (design system + wireframes) begins, or proceed with both
   in parallel?
