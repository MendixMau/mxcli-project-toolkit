## Design system

I will use **USIDesignSystem** (v2.4.0), the company's approved Mendix design-system module, documented at `usi-brain/components/usi.USIDesignSystem.md` and routed to from `usi-brain/skills/house-page-conventions.md`. It is wired into this project via the "company brain" pointer block in `CLAUDE.local.md`, which points at the brain repo and its `ROUTING.md`.

Concretely, once imported (`./mxcli import mpk usi.USIDesignSystem.mpk -p USI_Routing_Workshop.mpr`, Studio Pro closed — probe the local mxcli binary's import subcommand first since the flag moved between versions), the overview page must open with `USIDesignSystem.SNIPPET_USIPageHeader`, use `USIDesignSystem.SNIPPET_USIDataTable` instead of a bare DATAGRID for the list, and pull colors only from the brand tokens (`--usi-brand-primary`, `--usi-brand-ink`, `--usi-surface`) — never hardcoded hex values. House convention also fixes the page name as `Routing_Overview` (already the name used in the BRD).

**Caveat found during prep, not yet resolved (see Open questions):** `widgets-inventory.txt` shows the design-system module is **not yet imported** into this .mpr, and the manifest itself is explicitly flagged as an eval stand-in ("the real USI design module had not landed when this ran"). It also requires a `USIDesignSystem.BrandVariant` constant (`core` | `logistics`) to be set per app, which is not yet decided for this project.

## Page plan

Target: overview page for the routing catalogue entity, per BRD `F001-routing-overview.brd.json` (use case UC001, page `Routing_Overview`, entity `RoutingManagement.Routing`).

1. **`USIDesignSystem.SNIPPET_USIPageHeader`** — first widget on the page (house convention #2), titled "Routing Catalogue" or similar.
2. **SearchFilters section** (LAYOUTGRID row) — filter controls matching the BRD's main flow ("search routing headers by site, product family, or lifecycle state"):
   - COMBOBOX/TEXTBOX for `SiteId`
   - COMBOBOX/TEXTBOX for `ProductFamilyCode`
   - COMBOBOX for `LifecycleState`
   - ACTIONBUTTON "Search" wired to microflow `GET_Routing_List` (params: `RoutingSearch_Dto`)
3. **ReleasedContextSummary section** — a small summary/banner DATAVIEW bound to the result of `GET_ReleasedRoutingContext` (open question F001-RO-1 in the BRD asks whether this belongs here or is route-specific — see below).
4. **ResultGrid section** — **`USIDesignSystem.SNIPPET_USIDataTable`** (house convention #3, not a bare DATAGRID) as a DATAGRID2-style grid, `DataSource: DATABASE RoutingManagement.RoutingReadModel` (or via `GET_Routing_List`), columns: `RoutingCode`, `RoutingNameDefault`, `RoutingType` (if surfaced), `ProductFamilyCode`, `LifecycleState`, `ReleaseStatus`, `IsCurrent`.
   - Row click action: open `Routing_View` via `GET_Routing_Detail` (drilldown per BRD main flow step 3) — out of scope for "first overview page" but the grid's row action should be wired for it since the BRD's postcondition covers both screens.
5. Colors/spacing entirely from USI brand tokens; no hand-rolled HEADER, no inline styles/hex values (house convention #1, #4).

**This plan cannot be scripted yet** — per the toolkit's `ui-preflight-pages.md` (Step 1, mandatory, STOP condition): *"If no wireframe exists: STOP. Report to the main session that the wireframe is missing... Do not proceed, do not guess layout or bindings."* This project has no `design/wireframes/` directory at all (see Open questions).

## Files I read

- `<scratch>/cb-eval/treatment/USI_Routing_Workshop` (directory listing)
- `.../USI_Routing_Workshop/CLAUDE.md`
- `.../USI_Routing_Workshop/CLAUDE.local.md`
- `.../USI_Routing_Workshop` — searched for `docs/progress/RESUME.md` (does not exist)
- `<scratch>/cb-eval/usi-brain/` (directory listing)
- `usi-brain/ROUTING.md`
- `usi-brain/README.md`
- `usi-brain/components/` and `usi-brain/skills/` (directory listing)
- `usi-brain/components/usi.USIDesignSystem.md`
- `usi-brain/components/README.md`
- `usi-brain/skills/house-page-conventions.md`
- `.../USI_Routing_Workshop/PROJECT.md`
- `.../USI_Routing_Workshop/MPR-PLACEHOLDER.txt`
- `.../USI_Routing_Workshop/widgets-inventory.txt`
- `.../USI_Routing_Workshop/analysis/` (recursive file listing)
- `.../USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`
- `<home>/mxcli-project-toolkit/skills/ui-preflight-pages.md`
- `<home>/mxcli-project-toolkit/skills/conversion-runbook.md` (grepped for stage headings)

## Open questions for the user

1. **Stage mismatch:** `PROJECT.md` says "Stage 1 — Analysis, complete. Stage 2 (Requirements) next" — Stages 3 (Architecture & Design, which produces the design system wiring + wireframes) and 4 (Build Plan) show no artifacts at all (no `architecture/`, no `design/`, no module briefs, no build plan). You said we're at Stage 5. Which is correct — should I run/confirm the Stage 2–4 gates first, or has that work happened outside this checkout?
2. **No wireframe exists** for `Routing_Overview`. Per the toolkit's mandatory pre-flight rule, I cannot draft the page MDL without one. Do you want me to produce a wireframe first (Stage 3 deliverable), or do you have one elsewhere I should use?
3. **USIDesignSystem.mpk is not yet imported** into `USI_Routing_Workshop.mpr` (not in `widgets-inventory.txt`). Should I import it as part of this task, and is it available/expected to be present already?
4. **`BrandVariant` constant** (`core` vs `logistics`) required by the design system is not set anywhere I can find for this project — which value applies here?
5. The component manifest itself is marked as an eval stand-in ("the real USI design module had not landed when this ran") — should I treat it as authoritative anyway, or flag this to the platform team first?
6. BRD open question **F001-RO-1** is unresolved: should `GetReleasedRoutingContext` populate the overview's `ReleasedContextSummary`, or is that element route-specific (belongs only on `Routing_View`)? This affects whether I include that section on the overview page.
