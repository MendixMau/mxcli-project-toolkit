## Design system

I will use **USIDesignSystem** (`usi.USIDesignSystem.mpk`, v2.4.0), the company's approved Mendix
design-system module, not a hand-rolled or generic Atlas theme. It comes from the USI company
brain wired into this project's `CLAUDE.local.md` (`COMPANY-BRAIN` block →
`.../usi-brain/ROUTING.md`), specifically `components/usi.USIDesignSystem.md`, and is governed by
`skills/house-page-conventions.md` in the same brain. Per that manifest, the page must open with
`USIDesignSystem.SNIPPET_USIPageHeader`, use `USIDesignSystem.SNIPPET_USIDataTable` for the list
grid (not a bare DATAGRID), and use only the brand tokens (`--usi-brand-primary`,
`--usi-brand-ink`, `--usi-surface`) — no hardcoded colors. It has not yet been imported into
`USI_Routing_Workshop.mpr`; that import (`./mxcli import mpk ...`, binary-probed first) is a
prerequisite build step, not something I've done as part of this prep.

## Page plan

Target: `RoutingManagement.Routing_Overview`, backed by entity `RoutingManagement.Routing` (per
`analysis/knowledge-base/brd/F001-routing-overview.brd.json`), layout `Atlas_Core.Atlas_Default`
per the BRD's stub but restyled through USIDesignSystem tokens/snippets per house convention.

Structure (top to bottom):

1. **`USIDesignSystem.SNIPPET_USIPageHeader`** — page title ("Routing Catalogue"), replaces any
   hand-built HEADER widget (mandatory per house convention).
2. **Search/filter section (`SearchFilters`)** — a small filter bar sourced from
   `RoutingSearch_Dto`: site, product family, lifecycle state filter inputs (COMBOBOX/TEXTBOX),
   feeding `GET_Routing_List`.
3. **`USIDesignSystem.SNIPPET_USIDataTable`** wrapping a DATAGRID over `RoutingReadModel`
   (`ResultGrid` section) — the BRD's overview reads through the read-model, not `Routing`
   directly. Columns: `RoutingCode`, `RoutingNameDefault`, `VersionNo`, `LifecycleState`,
   `ReleaseStatus`, `IsCurrent`, `EffectiveFrom`/`EffectiveTo`. Row click opens `Routing_View`
   (drilldown, out of scope for this first build but the action target per the BRD).
4. **Released-context summary (`ReleasedContextSummary`)** — a small DATAVIEW/CONTAINER showing
   `GET_ReleasedRoutingContext` output (released routing context banner), placed below or beside
   the grid per the BRD's page sections list.

Data source microflow: `GET_Routing_List` (search) and `GET_ReleasedRoutingContext` (context
banner), both already defined in the BRD as `query-read-model` microflows calling the stub REST
actions.

**This plan is not build-ready as written.** House convention and the toolkit's
`ui-preflight-pages.md` both require a wireframe (`design/wireframes/Routing_Overview.html`)
before the first widget is drafted — see Open questions.

## Files I read

- `<scratch>/cb-eval/treatment/USI_Routing_Workshop/CLAUDE.md`
- `<scratch>/cb-eval/treatment/USI_Routing_Workshop/CLAUDE.local.md`
- `<scratch>/cb-eval/treatment/USI_Routing_Workshop/PROJECT.md`
- `<scratch>/cb-eval/treatment/USI_Routing_Workshop/` (directory listing, `find`)
- `<scratch>/cb-eval/usi-brain/` (directory listing, `ls`)
- `<scratch>/cb-eval/usi-brain/ROUTING.md`
- `<scratch>/cb-eval/usi-brain/components/usi.USIDesignSystem.md`
- `<scratch>/cb-eval/usi-brain/skills` (directory listing)
- `<scratch>/cb-eval/usi-brain/skills/house-page-conventions.md`
- `<scratch>/cb-eval/usi-brain/components/README.md`
- `<scratch>/cb-eval/treatment/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json`
- `<scratch>/cb-eval/treatment/USI_Routing_Workshop/widgets-inventory.txt`
- `<scratch>/cb-eval/treatment/USI_Routing_Workshop/triage.md`
- `<home>/mxcli-project-toolkit/skills/ui-preflight-pages.md`

## Open questions for the user

1. **Stage mismatch.** You said "we are at Stage 5," but `PROJECT.md`'s "Current stage" line
   reads "Stage 1 — Analysis, complete. Stage 2 (Requirements) next," and the project has no
   `architecture/`, `design/`, or `mdlsource/` directories yet — only Stage 0/1 artifacts
   (`intake.md`, `triage.md`, the BRD set). Which is correct — should I treat this as Stage 5
   (and if so, where are the Stage 2–4 artifacts I'm not seeing), or is `PROJECT.md` accurate and
   we're really still pre-build?
2. **No wireframe exists.** `design/wireframes/` doesn't exist in this project. Both the USI
   house conventions and the toolkit's `ui-preflight-pages.md` treat "no wireframe" as a hard
   STOP before drafting any page MDL. Do you want me to produce a `Routing_Overview` wireframe
   first (per `design-artifacts.md`), or do you consider the page plan above sufficient to build
   from directly?
3. **USIDesignSystem import status.** The `.mpk` is approved in the company brain but I found no
   evidence it's been imported into `USI_Routing_Workshop.mpr` yet (no `mdlsource/` scripts, no
   module listing available since I did not run any MDL/mxcli commands as part of this prep). Can
   you confirm whether it's already imported, or should that be step 1 of the build?
4. **Overview data source.** The BRD's `Routing_Overview.sections` names `ResultGrid` against the
   search flow (`GET_Routing_List` → `RoutingReadModel`), while the entity you called out is
   "the routing catalogue entity" — did you mean `Routing` (the header entity) or
   `RoutingReadModel` (what the BRD's overview microflow actually returns) as the grid's source?
5. **Open BRD question F001-RO-1** (unresolved): should `GetReleasedRoutingContext` populate both
   `Routing_Overview`'s `ReleasedContextSummary` and `Routing_View`'s banner, or is one of those
   meant to be route-specific? This affects whether I build the context summary section now or
   defer it.
