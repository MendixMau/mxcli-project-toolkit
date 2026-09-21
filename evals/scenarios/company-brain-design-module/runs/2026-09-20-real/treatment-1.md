## Design system

**Atlas UI (Atlas Core / Atlas_Default), unmodified — no custom design system for this build.**

Evidence, in order of weight:
1. The BRD (`analysis/knowledge-base/brd/F001-routing-overview.brd.json`) already specifies both screens' layout as `Atlas_Core.Atlas_Default` for `Routing_Overview` and `Routing_View` — this was decided at KB-generation time, not invented here.
2. Per the toolkit's `design-artifacts.md` (Step 0b, "Establish the Branding Basis"), this decision is a gated interview with three options: client branding guidelines / Atlas defaults / neutral placeholder palette. I searched every source document (`sources/` via the KB extracts) and `PROJECT.md`'s decision register for a brand name, logo, palette, or style guide reference and found **none** — no `design/brand.md` or `design/target-ui.md` exist yet either.
3. `PROJECT.md`'s own driver decision is `(a) POC/demo — speed over completeness, throwaway output` (row P/2, CONFIRMED), and fidelity is `port as-is` (ASSUMED, ties to the POC driver). `design-artifacts.md` states explicitly: "For a faithful rebuild POC, Atlas defaults are usually right."
4. There is no legacy app and no client mockup (`requirements-driven` entry mode, no screenshots anywhere in the project) — so there is nothing to be faithful *to* besides the spec, and no reason to invest in a bespoke `ds.css`/brand layer for a throwaway POC.

Conclusion: use stock Atlas Core, no custom theme, no `design/ds.css`/`brand.md` token layer, no StyleGallery module. This is a recommendation for the ✋ gate the skill requires — see Open Questions; it has not yet been asked/confirmed in chat, so nothing here is written to `PROJECT.md` and no design files have been created.

## Brand colours

None — because "Atlas defaults, unbranded POC" is the recommended basis, there is no brand palette to source. The **only** colours used are Atlas Core's stock semantic tokens, taken as-is (not hand-picked, not overridden):

| Token | Atlas default | Use |
|---|---|---|
| `$brand-primary` | Atlas Core default blue (`#2C64EE` in current Atlas Core release) | Primary buttons, links, active nav |
| `$brand-success` | Atlas Core default green | "Released" status badge |
| `$brand-warning` | Atlas Core default amber | "InReview" / "Approved" (pending) status badges |
| `$brand-danger` | Atlas Core default red | "Retired" status badge, error toasts |
| `$text-color-*`, `$background-color`, greys | Atlas Core defaults | Body text, page/card backgrounds |

Source: Atlas Core's own `custom-variables.scss` defaults, not a client document — because no client palette exists in the source pack. If a real brand appears later, only this table (and the Atlas mapping) needs to change; nothing in the page plan below depends on specific hex values.

Status-badge colour **mapping**, not the colours themselves, does come from the source: the lifecycle states `Draft → InReview → Approved → Released → Retired` are attested in `analysis/knowledge-base/share/KB_MES20_APIBehaviorSpec.md` (state-transition rows SB-001/SB-003/SB-004) and the `LifecycleState` attribute on the `Routing` entity in the F001 BRD.

## Page plan

Scope per `PROJECT.md`: **`Routing_Overview` only** (F001/UC001, search + monitor; drilldown `Routing_View` is a separate screen, out of scope for this sketch). Structure taken directly from the BRD's `pages[0]` entry (sections: `SearchFilters`, `ResultGrid`, `ReleasedContextSummary`; actions: `GET_Routing_List`, `GET_ReleasedRoutingContext`, `GET_Routing_Detail`) and the `Routing` entity's attributes.

**`RoutingManagement.Routing_Overview`** — Atlas_Core.Atlas_Default layout:

1. **Page header** — title "Routing Overview", breadcrumb (home > Routing).
2. **SearchFilters** (top card, LAYOUTGRID row of filter controls, matching `SearchRoutes` query capability):
   - Site (COMBOBOX, bound to `SiteId` / site reference)
   - Product family (COMBOBOX/TEXTBOX, `ProductFamilyCode`)
   - Lifecycle state (COMBOBOX enum: Draft / InReview / Approved / Released / Retired)
   - Free-text search (TEXTBOX, matches `RoutingCode`/`RoutingName`)
   - "Search" ACTIONBUTTON (primary, triggers `GET_Routing_List` / `SearchRoutes`)
3. **ResultGrid** (DATAGRID, DataSource: database `RoutingManagement.Routing`, one row per routing header):
   - Columns: Routing Code (`RoutingCode`), Routing Name (`RoutingName`), Type (`RoutingType`), Product Family (`ProductFamilyCode`), Site (`SiteId`), Owner Team (`OwnerTeam`), Lifecycle State (`LifecycleState`, rendered as a coloured status badge per the mapping above), Modified On (`ModifiedOn`)
   - Row click → `GET_Routing_Detail`, opens `Routing_View` (out of scope to build now, but the nav target)
4. **ReleasedContextSummary** (card/panel beside or below the grid, populated by `GET_ReleasedRoutingContext` for the selected row): shows canonical ID, released version, and released-context status as a small KPI/stat-tile row (green/amber/red dot per state) — no data mutation, read-only.
5. **Empty/loading/error states**: empty-search placeholder, spinner while `SearchRoutes` is in flight, and an error banner using the `ProblemDetails` envelope shape (`errorCode` + `messageKey`) attested in `KB_MES20_APIBehaviorSpec.md`.

All widget choices are read-only (no CREATE/CHANGE actions) — matching the confirmed scope (F001 UC001 only; UC002–UC006 and F002–F004 are deferred, not built).

## Files I read

1. `<scratch>/cb-eval2/treatment/USI_Routing_Workshop/AGENTS.md` (diffed identical to CLAUDE.md)
2. `<scratch>/cb-eval2/treatment/USI_Routing_Workshop/CLAUDE.md`
3. `<scratch>/cb-eval2/treatment/USI_Routing_Workshop/PROJECT.md`
4. `<scratch>/cb-eval2/treatment/USI_Routing_Workshop/intake.md`
5. `<scratch>/cb-eval2/treatment/USI_Routing_Workshop` directory listing (`find analysis -type f`)
6. Grep of `analysis`, `intake.md`, `triage.md`, `widgets-inventory.txt`, `CLAUDE.md` for color/brand/theme/design-system keywords
7. `<scratch>/cb-eval2/treatment/USI_Routing_Workshop/analysis/knowledge-base/share/KB_MES20_FunctionalSpec.md` (grepped)
8. `<scratch>/cb-eval2/treatment/USI_Routing_Workshop/analysis/knowledge-base/share/KB_MES20_APIBehaviorSpec.md` (grepped, multiple passes)
9. `<home>/mxcli-project-toolkit/skills/design-artifacts.md` (full read)
10. `<home>/mxcli-project-toolkit/skills/` directory listing (ls, to locate design-related skills)
11. `<scratch>/cb-eval2/treatment/USI_Routing_Workshop/analysis/knowledge-base/brd/F001-routing-overview.brd.json` (full + targeted `pages`/`integrations` sections via python)

(Not opened: `.mpr` file, `triage.md` full body, `widgets-inventory.txt` full body, `AGENTS.md` full body — all confirmed via grep/diff to carry no design/brand content beyond what's captured above. No task instructs modifying the project or the toolkit repos, and none were touched.)

## Open questions for the user

1. **Branding basis gate (`design-artifacts.md` Step 0b) has not actually been asked yet.** I'm recommending "Atlas defaults, no custom brand" based on the POC driver and absence of any brand material in sources — but the skill requires this as an explicit ✋ interview question, not a silent default. Confirm: Atlas defaults, or do you have brand guidelines (logo/palette) I should use instead?
2. **Dark mode** — build it now, or Atlas light-only for this POC?
3. **Navigation layout** — top-bar vs. side-nav for the app shell (the skill flags this as a first-class question, not a background default)?
4. Should I still produce `design/brand.md`, `design/ds.css`, and a wireframe file for `Routing_Overview`, or is this chat-level sketch sufficient before Stage 2/3 formally starts (project is currently Stage 1 complete → Stage 2 next per `PROJECT.md`)?
5. Open BRD questions D1–D3 in `PROJECT.md` (conflicting API counts, document-control version, Artifact 14 availability) are unrelated to design but still open — flagging since they block later gates.
