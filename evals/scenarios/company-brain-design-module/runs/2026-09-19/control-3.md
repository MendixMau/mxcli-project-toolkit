## Design system

**No design system exists for this project yet, and none is wired in as "the company's standard."** `PROJECT.md`'s Decision register shows the project at **Stage 1 (Analysis), complete — Stage 2 (Requirements) next** — not Stage 5. There is no `design/` folder, no `architecture/` folder, no `ds.css`, no `design-system.html`, no wireframes, and `CLAUDE.local.md` has no `COMPANY-BRAIN:BEGIN` wiring block, so there is no company-brain repo attached to this project that could hold an approved "standard look and feel."

Per the toolkit's own rule (`skills/conversion-runbook.md` Stage 3 + `skills/design-artifacts.md` Step 0b), a design system is produced *at Stage 3* only after a branding-basis interview is asked and answered in chat (options: client branding guidelines / Atlas defaults / neutral placeholder), and pages are never built before that checkpoint runs. Since this project hasn't reached Stage 3 and no branding interview has happened, I can't yet tell you which design system will be used — that has to be answered first, in chat, before I build anything.

## Page plan

Assuming the branding-basis question above gets answered and a `design/ds.css` + wireframe exist (or, if you want to fast-track just this one page, Atlas defaults with no custom theme), the overview page for the routing catalogue entity (`RoutingManagement.Routing`, per BRD `F001-routing-overview.brd.json`, use case UC001) would be:

- **Page name:** `Routing_Overview` (module `RoutingManagement`), Atlas `Atlas_Default` layout, per source naming convention `Routing_Overview` / `Routing_View`.
- **Header/control bar:** page title "Routing Catalogue", search/filter bar reflecting UC001's main flow — filters for **Site**, **Product Family** (`ProductFamilyCode`), and **Lifecycle State** (`LifecycleState`), plus a free-text search box.
- **Data grid** (Datagrid2) bound to `RoutingManagement.Routing`, columns:
  - `RoutingCode`
  - `RoutingName`
  - `RoutingType`
  - `ProductFamilyCode`
  - `OwnerTeam`
  - `SiteId`
  - `LifecycleState` (as a status badge/pill once the design system defines one)
  - `ModifiedOn`
- **Row action:** a "View" link/button per row navigating to `Routing_View` (the drilldown page from UC001, out of scope for this build step but the nav target this page must wire to).
- No create/edit/delete actions — F001 UC001 is explicitly read-only (governed API-backed, `SearchRoutes` / `GetReleasedRoutingContext`).
- Empty-state and loading-state treatment per whatever component set the chosen design system defines (component names TBD until Stage 3 exists).

This is a plan, not a build — no MDL was written and the project was not modified.

## Files I read

- `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval/control/USI_Routing_Workshop/PROJECT.md`
- `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval/control/USI_Routing_Workshop/CLAUDE.local.md`
- `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval/control/USI_Routing_Workshop/intake.md`
- (directory listing) `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval/control/USI_Routing_Workshop/` — searched for `design`, `wireframe`, `*.css`, `*brd*`
- `/home/user/mxcli-project-toolkit/skills/design-artifacts.md`
- `/home/user/mxcli-project-toolkit/skills/company-brain.md`
- (directory listing) `/home/user`, `/home/user/mxcli-project-toolkit` top-level
- `/home/user/mxcli-project-toolkit/skills/conversion-runbook.md` (grepped for Stage 3/4/5 sections)
- `/tmp/claude-0/-home-user/290fe318-2e84-5498-9083-13e06ee724da/scratchpad/cb-eval/control/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`

(Note: `CLAUDE.md` and `AGENTS.md` in the project root were present but not opened directly — their content is identical to the toolkit-generated `CLAUDE.md`/`CLAUDE.local.md` pattern already covered via `CLAUDE.local.md` and the toolkit's own `CLAUDE.md`, which was supplied in the system context rather than re-read from disk.)

## Open questions for the user

1. **Stage mismatch:** `PROJECT.md` shows Stage 1 complete / Stage 2 next, but you said "we are at Stage 5." Which is correct — has Stage 2–4 work (BRD validation, architecture, module boundaries, design system + wireframes) actually happened somewhere not reflected in `PROJECT.md`, or should the register be corrected/caught up first?
2. **Branding basis** (the Stage 3 gate question this project has never been asked): client branding guidelines, Atlas defaults, or a neutral placeholder palette — which should this app use?
3. Is there a company-brain repo for "our company's standard look and feel" that should be wired to this project (`bin/wire-company-brain.sh`), and if so, where does it live?
4. Given F001 UC001 also names a drilldown screen (`Routing_View`), do you want that scoped now too, or is this task deliberately just the overview page?
