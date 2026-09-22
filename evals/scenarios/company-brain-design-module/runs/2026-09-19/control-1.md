## Design system

I cannot name a design system to build with yet — this project has none. There is no `design/` folder at all (no `ds.css`, no `design-system.html`, no `brand.md`, no wireframes), and `CLAUDE.local.md` has no `COMPANY-BRAIN:BEGIN` block, so no company brain is wired in to supply "our company's standard look and feel" either. Per the toolkit's own rules (`design-artifacts.md` Step 1 and `ui-preflight-pages.md` Step 1/Step 2's "Hard rule B0/B1"), a design system and a per-screen wireframe must exist and be proven to reach the app *before* any page MDL is drafted — so I'm stopping here rather than picking a look-and-feel myself or defaulting to bare Atlas.

There's also a stage mismatch worth flagging before anything else: `PROJECT.md` states **"Stage 1 — Analysis, complete. Stage 2 (Requirements) next,"** not Stage 5. Stage 3 (architecture/design) and Stage 4 (build plan) — which is where the design system, wireframes, and module briefs get produced — don't appear to have run. No `architecture/`, `mdlsource/`, or `design/` directories exist in the project at all, and there's no `.mpr` file present (only `MPR-PLACEHOLDER.txt`).

## Page plan

I'm not building this yet (see Open questions), but based on `analysis/knowledge-base/brd/F001-routing-overview.brd.json`, here is the concrete shape the overview page would take once a design system and wireframe exist:

- **Page:** `RoutingManagement.Routing_Overview`, layout `Atlas_Core.Atlas_Default`
- **Data context:** `RoutingSearch_Dto` (not the `Routing` entity directly — the BRD models this page as backed by a search DTO over governed API results, not a raw persistent-entity datasource)
- **Section 1 — SearchFilters:** filter inputs for site, product family, and lifecycle state (per the BRD's use case UC001 main flow step 1: "search routing headers by site, product family, or lifecycle state")
- **Section 2 — ResultGrid:** a data grid of routing headers, one row per `Routing` (candidate columns from the `Routing` entity: RoutingCode, RoutingName, RoutingType, ProductFamilyCode, OwnerTeam, SiteId, LifecycleState), with a row action/click-through to `Routing_View` (the drilldown page, UC001 step 3)
- **Section 3 — ReleasedContextSummary:** a summary area showing released-routing-context status, driven by `GET_ReleasedRoutingContext`
- **Backing actions/microflows implied by the BRD:** `GET_Routing_List` (→ `SearchRoutes`), `GET_ReleasedRoutingContext`, `GET_Routing_Detail` (for the drilldown hop)

This is read-only (UC001 postcondition: "displayed from governed APIs" — no create/edit actions are in scope for F001-routing-overview; routing management/editing is explicitly deferred in `F001-routing-management.brd.deferred.json`).

## Files I read

- `<scratch>/cb-eval/control/USI_Routing_Workshop` (directory listing)
- `<scratch>/cb-eval/control/USI_Routing_Workshop/PROJECT.md`
- `<scratch>/cb-eval/control/USI_Routing_Workshop/CLAUDE.md`
- `<scratch>/cb-eval/control/USI_Routing_Workshop/CLAUDE.local.md`
- `<scratch>/cb-eval/control/USI_Routing_Workshop` (find for RESUME.md / *.local.md / directory tree — confirmed no `docs/progress/RESUME.md` and no `design/` folder)
- `<home>/mxcli-project-toolkit/skills/design-artifacts.md` (listing) + `<home>/mxcli-project-toolkit/skills/ui-preflight-pages.md` (listing)
- `<home>/mxcli-project-toolkit/skills/design-artifacts.md` (full read)
- `<home>/mxcli-project-toolkit/skills/ui-preflight-pages.md` (partial read, Steps 1–2)
- `<scratch>/cb-eval/control/USI_Routing_Workshop/MPR-PLACEHOLDER.txt`
- `<scratch>/cb-eval/control/USI_Routing_Workshop/analysis/knowledge-base/brd/index.json`
- `<scratch>/cb-eval/control/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json` (domainEntities, then pages)
- `<scratch>/cb-eval/control/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json` (top-level keys)
- `<home>/mxcli-project-toolkit/skills/company-brain.md` (grep + full head read)
- `<home>/mxcli-project-toolkit` (find for `*company-brain*` references)
- `<scratch>/cb-eval/control/USI_Routing_Workshop/*.md` (grep for company-brain / design system mentions)
- `<scratch>/cb-eval/control/USI_Routing_Workshop/CLAUDE.local.md` (grep count for `COMPANY-BRAIN:BEGIN`)

## Open questions for the user

1. **Stage discrepancy:** `PROJECT.md` says Stage 1 is complete and Stage 2 is next — not Stage 5. Should I treat this project as further along than its register shows (and if so, where are the missing Stage 3/4 artifacts — architecture, build plan, design system — actually located), or should the register be trusted and we resume at Stage 2?
2. **Design system source:** Is there a company brain repo (per `skills/company-brain.md`) that should be wired to this project via `bin/wire-company-brain.sh` to supply "our company's standard look and feel"? None is currently wired in `CLAUDE.local.md`. If not, should I run the Step 0b branding interview from `design-artifacts.md` (client guidelines vs. Atlas defaults vs. neutral placeholder palette) to establish one from scratch?
3. Once the design-system source is settled, should I produce the full Stage 3 design-artifacts output (`brand.md`, `target-ui.md`, `ds.css`, `design-system.html`, then a `Routing_Overview.html` wireframe) before I write any page MDL, per the toolkit's mandatory STOP rule — or is there an existing wireframe/design system elsewhere I haven't been pointed to?
