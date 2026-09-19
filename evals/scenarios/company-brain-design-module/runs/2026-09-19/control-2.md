## Design system

There isn't one to use yet: this project has no `design/ds.css`, no `design/design-system.html`, no `design/wireframes/`, and no company-brain wired into `CLAUDE.local.md` (no `COMPANY-BRAIN:BEGIN` block, no path to a private design-system repo). Per the toolkit (`conversion-runbook.md` Stage 3 / `design-artifacts.md`), "our standard look and feel" has to come from one of those two sources — a company brain's design system, or this project's own Stage 3 tokens-and-wireframes deliverable — and this project's own record (`PROJECT.md`) says Stage 1 is complete and Stage 2 is next, not Stage 5, so neither exists here yet.

## Page plan

Not built yet — this is a plan only, pending the design-system question below. For the routing catalogue overview (BRD `F001-routing-overview.brd.json`, UC001, screen `Routing_Overview`, entity `RoutingManagement.Routing`), once a design system is confirmed:

- **Page** `RoutingManagement.Routing_Overview` (Atlas-style list page, using whatever layout the confirmed design system specifies)
  - **Header/title bar**: "Routing Catalogue"
  - **Search/filter row**: filter controls over `RoutingCode`, `RoutingName`, `ProductFamilyCode`, `SiteId`, `LifecycleState` (matches UC001 main flow step 1: "search routing headers by site, product family, or lifecycle state")
  - **DATAGRID** (`com.mendix.widget.web.Datagrid`, already in `widgets-inventory.txt`) bound to `DATABASE RoutingManagement.Routing`, columns: `RoutingCode`, `RoutingName`, `RoutingType`, `ProductFamilyCode`, `OwnerTeam`, `SiteId`, `LifecycleState`, `IsActive`
  - **Row action**: link/button to drill into `Routing_View` (out of scope for this page, per UC001 step 3 — separate build)
  - No create/edit/delete controls — UC001 and the confirmed scope (`PROJECT.md`, 2026-08-20) are explicitly read-only (F001 UC002–UC006 deferred)

## Files I read

- `CLAUDE.md`
- `CLAUDE.local.md`
- `PROJECT.md`
- `intake.md`
- `triage.md`
- `analysis/knowledge-base/brd/F001-routing-overview.brd.json`
- `/home/user/mxcli-project-toolkit/skills/company-brain.md`
- `/home/user/mxcli-project-toolkit/skills/conversion-runbook.md` (grep on Stage 3/Stage 5/design system)
- `widgets-inventory.txt`
- directory listing (no `design/`, `architecture/`, `mdlsource/`, `mxcli` binary, or `.mpr` file present — only `MPR-PLACEHOLDER.txt`)

## Open questions for the user

1. **Stage mismatch:** `PROJECT.md` records "Stage 1 — Analysis, complete. Stage 2 (Requirements) next," but you said we're at Stage 5. Which is correct — has Stage 2–4 work (BRD validation, architecture, design system, build plan) happened somewhere not reflected in this project's files, or should we back up and run those stages first?
2. **"Our company's standard look and feel"** — is there a company brain repo (per `skills/company-brain.md`) this project should be wired to, so I pull the design tokens/components from there? If so, what's its path/URL?
3. If there is no company brain, should I run the Stage 3 design-artifacts process now (branding interview → `design/ds.css` + `design-system.html` + wireframes) before building this page, per the toolkit's build-ready gate (which requires a design system and wireframes present before Stage 5 build starts)?
