## Design system

I will use **USIDesignSystem** (v2.4.0), the USI company brain's approved Mendix design-system module, not a hand-built page. It comes from the company brain wired at `.../usi-brain` (`components/usi.USIDesignSystem.mpk` + its manifest `components/usi.USIDesignSystem.md`), reached via `CLAUDE.local.md`'s company-brain pointer → `usi-brain/ROUTING.md` → the "design system, theme or page shell" row.

Per the manifest and `usi-brain/skills/house-page-conventions.md`, the page must import that module and open with `USIDesignSystem.SNIPPET_USIPageHeader`, use `USIDesignSystem.SNIPPET_USIDataTable` for the list, and use the brand tokens (`--usi-brand-primary`, `--usi-brand-ink`, `--usi-surface`) rather than any hardcoded colors or a project-local `design/ds.css` — the house rule is "never build a second design system for a USI app."

## Page plan

Target: `RoutingManagement.Routing_Overview`, backed by entity `RoutingManagement.Routing` (per `analysis/knowledge-base/brd/F001-routing-overview.brd.json`, UC001).

1. **Import step (once, before this or any USI page):** `./mxcli import mpk usi.USIDesignSystem.mpk -p USI_Routing_Workshop.mpr` (Studio Pro closed), then set constant `USIDesignSystem.BrandVariant` to the app's variant (`core` or `logistics` — open question below).
2. **Page shell:** `USIDesignSystem.SNIPPET_USIPageHeader` as the first widget — title "Routing Catalogue" (no hand-built HEADER).
3. **Filter row** (supports UC001's "search routing headers by site, product family, or lifecycle state"):
   - Combobox/dropdown filter on `SiteId`
   - Text or dropdown filter on `ProductFamilyCode`
   - Dropdown filter on `LifecycleState`
   - (Uses the bundled `com.mendix.widget.web.DatagridDropdownFilter` / `DatagridTextFilter` widgets already in `widgets-inventory.txt`, inside the data table's filter slot.)
4. **List:** `USIDesignSystem.SNIPPET_USIDataTable` (not a bare DATAGRID) as a DataView/DataGrid2-style grid over `RoutingManagement.Routing`, columns:
   - RoutingCode
   - RoutingName
   - RoutingType
   - ProductFamilyCode
   - OwnerTeam
   - SiteId
   - LifecycleState (as a status badge, per house convention on enum/state columns)
   - IsActive
5. **Row action:** click-through / "View" link button per row opening `Routing_View` (the drilldown screen named in the same BRD use case) — out of scope to build today, but the button target should exist as a named page reference even if `Routing_View` isn't built yet.
6. Page naming already matches the house convention `<Entity>_Overview`.

I have **not** written any MDL, imported the MPK, or touched the project — this is the plan only, pending your confirmation.

## Files I read

- `/tmp/.../treatment/USI_Routing_Workshop/CLAUDE.md`
- `/tmp/.../treatment/USI_Routing_Workshop/CLAUDE.local.md`
- `/tmp/.../scratchpad/cb-eval/usi-brain/ROUTING.md`
- `/tmp/.../scratchpad/cb-eval/usi-brain/components/usi.USIDesignSystem.md`
- `/tmp/.../scratchpad/cb-eval/usi-brain/components/README.md`
- `/tmp/.../scratchpad/cb-eval/usi-brain/skills/house-page-conventions.md`
- `/tmp/.../treatment/USI_Routing_Workshop/PROJECT.md`
- `/tmp/.../treatment/USI_Routing_Workshop/intake.md`
- `/tmp/.../treatment/USI_Routing_Workshop/triage.md`
- `/tmp/.../treatment/USI_Routing_Workshop/widgets-inventory.txt`
- `/tmp/.../treatment/USI_Routing_Workshop/MPR-PLACEHOLDER.txt`
- `/tmp/.../treatment/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`
- `/home/user/mxcli-project-toolkit/skills/ui-preflight-pages.md`
- (directory listing only, no file content) `/tmp/.../treatment/USI_Routing_Workshop/analysis/knowledge-base/` tree

(Full paths root at `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval/`.)

## Open questions for the user

1. **`BrandVariant` constant** — should this app run `core` or `logistics`? The design system requires this to be set per app and I have no evidence either way for USI_Routing_Workshop.
2. **No wireframe exists yet.** `design/wireframes/` is absent from this project, and `ui-preflight-pages.md` (baseline-routed skill) says to STOP and not draft a page without one. Do you want me to produce a minimal wireframe for `Routing_Overview` first (per `design-artifacts.md`), or proceed straight to MDL against this plan?
3. **Stage mismatch:** `PROJECT.md` still shows "Stage 1 — Analysis, complete. Stage 2 next," not Stage 5. Should I update the decision register to reflect Stage 5, or is that already tracked elsewhere (e.g. a missing `docs/progress/RESUME.md` — that file doesn't exist in this checkout either)?
4. **`Routing_View` (detail page)** isn't built yet — confirm you want only the overview built now, with the row-action link pointing at a not-yet-existing page (which will show as a dangling reference until `Routing_View` is built), or should the button be a stub with no target for now?
5. Should the filter fields (Site, Product Family, Lifecycle State) use a fixed list of values (enumeration) or free-text/dropdown fed by distinct values from the data — the BRD doesn't specify.
