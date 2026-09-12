# Build Plan — Harbour Berth Booking

Per `skills/brd-to-build-plan.md`. Consumes `architecture/blueprint.md` (dependency graph, layer
diagram) and `architecture/fit-gap.md` (Buy/Build verdicts). Contains no MDL — script content is
drafted per phase, after the prior phase's gate, at Stage 5 (not run in this pass).

## Step 0 — Import confirmed marketplace dependencies

One confirmed **Buy**: the inspection-calendar drag-drop widget (`architecture/fit-gap.md`).

| # | Action | State |
|---|---|---|
| 0.1 | `mxcli marketplace search "calendar"` — pick a concrete content id; `mxcli marketplace install <id> -p app.mpr` before any HB_Inspection script | not built — requires a live machine/mxcli session; deferred to Stage 5 kickoff, named here so it is never discovered mid-script |

## Step 1 — Module dependency graph + test shape

| Module | Dep. order | Test shape | Calls out? |
|---|---|---|---|
| HB_MasterData | 1 | UI + Data | no |
| HB_Reporting | 1 | UI + Data | no |
| HB_Booking | 2 | UI + Data + Unit (fee/reference/validation logic is dense enough to warrant it) | yes (stub) — AIS feed poll |
| HB_Finance | 3 | UI + Data + Unit (fee calculation chain: length×days×rate, VAT, surcharges) | no |
| HB_Inspection | 3 | UI + Data | no |

HB_Finance and HB_Inspection are both dependency-order 3 (both depend only on HB_Booking +
HB_MasterData, not on each other) — buildable in either order or in parallel once HB_Booking is
done.

## Step 2 — Architecture questions resolved before scripting

| # | Question | Resolution |
|---|---|---|
| 1 | Iteration granularity | Per-layer (Step 3) |
| 2 | Cross-module association ownership | `Invoice_BookingRequest` → HB_Finance's domain script; `Inspection_BookingRequest` → HB_Inspection's domain script (both peer feature-to-feature, per `architecture/blueprint.md`) |
| 3 | Stub vs real scope | AIS feed = stub this phase (no contract documented); inspection-calendar widget = real (Buy, Step 0); everything else = real |
| 4 | Demo user / role mapping | See Step 7 below — 1:1, no source system to map from (requirements-driven) |
| 5 | Acceptance criteria per module | See per-module rows below and `coverage-ledger.md` — "done" = CE-error-free AND every `claims` leaf discharged AND the module's business-rule checklist (below) passes |
| 6 | Environment / DTAP | Single environment this phase (no DTAP signal in the source or intake) — ASSUMED, run-authorized (Ruling R12); revisit if a real deployment target is named later |

## Step 3 — Iteration granularity

**Per-layer** for every module (`0N-<module>-domain.mdl` / `-microflows.mdl` / `-pages.mdl`) — all
five modules are small (2-4 entities, 1-4 pages), well under the per-page-cluster or per-domain
thresholds either way.

## Step 4 — Scope boundary (this phase)

- **In scope, real:** all 5 modules, all entities/microflows/pages listed in the 7 BRDs; the
  inspection-calendar widget (real Buy).
- **In scope, stubbed:** the AIS position feed (`STUB_AIS_PollPositions` — poll+geofence
  behaviour only, no protocol/auth/failure-mode).
- **Out of scope:** pilotage and tug scheduling (explicit source boundary, ch04); nothing else —
  Stage 0's slice is the whole documented app, ordered not excluded.

## Step 4b — StyleGallery UI module ✋

**Decision: Yes — build a StyleGallery.** Three feature modules (HB_Booking, HB_Finance,
HB_Inspection) share one visual language already established in `design/ds.css` /
`design-system.html`, and it diverges from Atlas defaults (dark-navy header, monospace field
labels, specific badge/callout system lifted from the prototype screenshots) — both "Yes"
signals in `brd-to-build-plan.md` Step 4b's table. Recorded `CONFIRMED` (Ruling R12).

```
Phase 1 — App Scaffold
Phase 2 — UI Scaffold (StyleGallery, confirmed Yes)
Phase 3 — Feature Modules, in dependency order
```

## Step 5 — Numbered script sequence

### Script 00 — project scaffold

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 00 | BUILD | `mxcli new` scaffold, layout, theme frame, project security (production), guest access off, nav shell (5 items: Booking Board, My Bookings, Inspections, Tariffs, Reports + Config) | project frame + nav shell | — | `skills/learned-mdl-preflight.md` | not built |

### Phase 1 — App Scaffold (domain skeleton, all modules)

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 1 | BRIEF | Check/create `architecture/modules/HB_MasterData/module-brief.md` | brief exists | 00 | `skills/module-brief.md` | not built |
| 2 | BUILD | `01-hb_masterdata-roles.mdl` — module role creation | HB_MasterData module role | 00 | `skills/learned-mdl-preflight.md` | not built |
| 3 | BUILD | `02-hb_masterdata-domain.mdl` — Vessel, ShippingAgent, Terminal, Berth + associations + entity access grants at the end | 4 entities | 2 | `skills/security-is-not-a-later-script.md` | not built |
|   | claims: |||||| |
|   | `/domainEntities/*` (4) — F002 |||||| |
| 4 | BRIEF | Check/create `architecture/modules/HB_Reporting/module-brief.md` | brief exists | 00 | `skills/module-brief.md` | not built |
| 5 | BUILD | `01-hb_reporting-roles.mdl` | HB_Reporting module role | 00 | — | not built |
| 6 | BUILD | `02-hb_reporting-domain.mdl` — AuditEntry + entity access grants | 1 entity | 5 | `skills/security-is-not-a-later-script.md` | not built |
|   | claims: `/domainEntities/*` (1) — F007 |||||| |
| 7 | BRIEF | Check/create `architecture/modules/HB_Booking/module-brief.md` | brief exists | 00 | `skills/module-brief.md` | not built |
| 8 | BUILD | `01-hb_booking-roles.mdl` | HB_Booking module role | 00 | — | not built |
| 9 | BUILD | `02-hb_booking-domain.mdl` — BookingRequest, ApprovalDecision + assocs into HB_MasterData + entity access grants | 2 entities | 8, 3 | `skills/security-is-not-a-later-script.md` | not built |
|   | claims: `/domainEntities/*` (2) — F003, F004 |||||| |
| 10 | BRIEF | Check/create `architecture/modules/HB_Finance/module-brief.md` | brief exists | 00 | `skills/module-brief.md` | not built |
| 11 | BUILD | `01-hb_finance-roles.mdl` | HB_Finance module role | 00 | — | not built |
| 12 | BUILD | `02-hb_finance-domain.mdl` — Tariff, Invoice + `Invoice_BookingRequest` (owned here) + entity access grants | 2 entities | 11, 9, 3 | `skills/security-is-not-a-later-script.md` | not built |
|   | claims: `/domainEntities/*` (2) — F005 |||||| |
| 13 | BRIEF | Check/create `architecture/modules/HB_Inspection/module-brief.md` | brief exists | 00 | `skills/module-brief.md` | not built |
| 14 | BUILD | `01-hb_inspection-roles.mdl` | HB_Inspection module role | 00 | — | not built |
| 15 | BUILD | `02-hb_inspection-domain.mdl` — Inspection, InspectionItem + `Inspection_BookingRequest` (owned here) + entity access grants | 2 entities | 14, 9 | `skills/security-is-not-a-later-script.md` | not built |
|   | claims: `/domainEntities/*` (2) — F006 |||||| |
| 16 | PROVE | `mxcli check --references` across all 5 modules; `SHOW ENTITIES` read-back — 11 entities, 0 dangling associations | domain skeleton proven | 3,6,9,12,15 | — | not built |

### Phase 2 — UI Scaffold (StyleGallery)

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 17 | BUILD | Port `design/ds.css` tokens → `themesource/stylegallery/web/main.scss` | SCSS token port | 16 | `skills/design-artifacts.md`, `skills/learned-stylegallery.md` | not built |
| 18 | BUILD | `mdlsource/gallery/00-05` — StyleGallery module + demo data | gallery module | 17 | `skills/learned-stylegallery.md` | not built |
| 19 | BUILD | `mdlsource/gallery/11-19` — one snippet per component (badges, callouts, field/validation pattern) | component snippets | 18 | `skills/learned-stylegallery.md` | not built |
| 20 | BUILD | `mdlsource/gallery/90-home.mdl` | gallery home page, wired under Config | 19 | `skills/module-folder-convention.md` | not built |
| 21 | PROVE | `project-bin/check-design-reaches-app.sh` | tokens/classes actually bound, not just present | 17-20 | — | not built |

### Phase 3 — Feature modules (per-layer, dependency order)

**HB_Booking** (dep. order 2):

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 22 | BUILD | `03-hb_booking-microflows.mdl` — `ACT_BookingRequest_Submit`, `SUB_BookingRequest_AssignReference`, `ACT_BookingRequest_OpenForReview`, `ACT_ApprovalDecision_Decide`, `ACT_BookingRequest_Cancel`, `SUB_AuditEntry_Log` calls + grant execute | microflows | 9, 6, 21 | `skills/learned-microflow-patterns.md`, `skills/module-brief.md` | not built |
|   | claims: `/useCases/*` (15) — F003; `/useCases/*` (8) — F004 |||||| |
| 23 | BUILD | `04-hb_booking-stub-pages.mdl` — forward-reference stubs (BookingBoard, MyBookings, BookingRequest_NewEdit, OfficerReview) | 4 page stubs | 22 | `skills/ui-preflight-pages.md` | not built |
| 24 | BUILD | `05-hb_booking-pages.mdl` — the 4 pages built to their wireframes + grant view | 4 pages | 23 | `skills/ui-preflight-pages.md`, `skills/design-spacing.md` | not built |
| 25 | BUILD | `06-hb_booking-stub-ais.mdl` — `STUB_AIS_PollPositions` scheduled event (stub, per Step 4 scope) | 1 scheduled stub | 22 | — | not built |
| 26 | PROVE | UI (Playwright) + Data (OQL) + wiring-sweep for HB_Booking | mechanical rungs green | 24, 25 | `skills/testing-shape.md` | not built |
| 27 | RUN | Happy path as demo Shipping Agent: draft → submit → officer decide (as demo Berth Officer) | walked, screenshotted | 26 | — | not built |

**HB_Finance** (dep. order 3):

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 28 | BUILD | `03-hb_finance-microflows.mdl` — `CAL_BerthFee_Calculate`, `CAL_LateArrivalSurcharge_Calculate`, `CAL_LateCancellationFee_Calculate`, `ACT_Invoice_GenerateOnComplete`, `SCHED_Invoice_MarkOverdue`, `ACT_Invoice_MarkPaidOrVoid` + grant execute | microflows | 12, 26 | `skills/learned-microflow-patterns.md` | not built |
|   | claims: `/useCases/*` (11) — F005 |||||| |
| 29 | BUILD | `04-hb_finance-stub-pages.mdl` then `05-hb_finance-pages.mdl` — Tariffs, Invoices + grant view | 2 pages | 28 | `skills/ui-preflight-pages.md` | not built |
| 30 | PROVE | UI + Data + Unit (fee-calc test suite: 30-day cap, VAT 21%, shore power 250/day, 15%/50% surcharges) for HB_Finance | mechanical rungs green | 29 | `skills/testing-shape.md` | not built |

**HB_Inspection** (dep. order 3):

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 31 | BUILD | `03-hb_inspection-microflows.mdl` — `ACT_Inspection_Schedule`, `VAL_DangerousGoods_RequireInspection`, `ACT_InspectionItem_Record`, `ACT_Inspection_Complete`, `VAL_DepartureClearance_Check` + grant execute | microflows | 15, 26 | `skills/learned-microflow-patterns.md` | not built |
|   | claims: `/useCases/*` (8) — F006 |||||| |
| 32 | BUILD | `04-hb_inspection-stub-pages.mdl` then `05-hb_inspection-pages.mdl` — InspectionCalendar (using Step 0's imported widget), Inspection_Checklist + grant view | 2 pages | 31, 0.1 | `skills/ui-preflight-pages.md` | not built |
| 33 | PROVE | UI + Data for HB_Inspection | mechanical rungs green | 32 | `skills/testing-shape.md` | not built |

**HB_Reporting** (Reports page, cross-cutting):

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 34 | BUILD | `03-hb_reporting-microflows.mdl` — `ACT_Report_BerthOccupancy_ExportCsv` + grant execute | 1 microflow | 6, 26, 30, 33 | — | not built |
|   | claims: `/useCases/*` (2) — F007 |||||| |
| 35 | BUILD | `04-hb_reporting-pages.mdl` — Reports_Overview + grant view | 1 page | 34 | `skills/ui-preflight-pages.md` | not built |
| 36 | PROVE | UI + Data for HB_Reporting | mechanical rungs green | 35 | `skills/testing-shape.md` | not built |

**Demo data:**

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 37 | BUILD | `06-<module>-seed-data.mdl` per module — idempotent demo Vessel/ShippingAgent/Berth/Terminal + a few BookingRequests across statuses | seed data | 3,6,9,12,15 | `skills/fixture-seeding.md` | not built |

**Cross-module coherence + app-wide close-out (deferred to Stage 5/6, listed for completeness):**

| # | Kind | Step | Produces / Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 38 | HARNESS | `walking-skeleton.md` — one entity/microflow/page/nav/user/journey/screenshot, before module 1 build truly begins | skeleton proven | 00 | `skills/walking-skeleton.md` | not built (must run FIRST at Stage 5 kickoff, listed here for completeness of the sequence) |
| 39 | HARNESS | `process-coherence-pass.md` after every 2-3 modules close | seam check | 27, 30, 33 | `skills/process-coherence-pass.md` | not built |

## Step 6 — Role-to-access roll-up

| Element type | ShippingAgent | BerthOfficer | HarbourMaster | Inspector |
|---|---|---|---|---|
| Vessel, Berth, Terminal (HB_MasterData) | read | read | read, write | read |
| ShippingAgent | read (own) | read + activate | read + reactivate/suspend | — |
| BookingRequest (own company only, F001) | create/edit Draft+Submitted, read own | read all, transition to UnderReview | all + override | read (for inspection context) |
| ApprovalDecision | read (own bookings) | create | create + override | — |
| Tariff | read | — | create/edit, waive surcharge | — |
| Invoice | read (own) | waive late-arrival surcharge | mark Paid/Void, full read | — |
| Inspection, InspectionItem | read (own bookings) | grant departure clearance (reads Outcome) | read | create/edit |
| AuditEntry / Reports | — | read | read | — |

No gap found in the roll-up: every element above has at least one role with access, and every
role has a defined level (never silently inherited).

## Step 7 — Demo users and navigation wiring

| Target role | Maps to | Notes |
|---|---|---|
| ShippingAgent | source "Shipping Agent" | primary happy-path demo user |
| BerthOfficer | source "Berth Officer" | review/decide demo user |
| HarbourMaster | source "Harbour Master" | override/finance demo user, never used for happy-path-only testing |
| Inspector | source "Inspector" | inspection demo user |

Demo users created with role only, no password (MxAdmin untouched, per `brd-to-build-plan.md`
Step 7 rule). Navigation: all 5 top-level nav items (Booking Board, My Bookings, Inspections,
Tariffs, Reports) wired in script 00's nav shell; the StyleGallery home page wired under `Config`
(script 20).

## Step 9 — CONFIRMED-decision reconciliation

Every `CONFIRMED` row in `PROJECT.md` from Stages 0-3 maps to a build-plan row:

| PROJECT.md CONFIRMED decision | Build-plan disposition |
|---|---|
| Module boundaries (5 modules) | Rows 1-15 (Phase 1 domain scaffold, one BRIEF+roles+domain triplet per module) |
| Architecture decision: AuditEntry drops its BookingRequest association | Row 6 (`02-hb_reporting-domain.mdl` has no such association) |
| 6a Security/role model | Step 6 roll-up table |
| 6b Data volumes/NFRs | Step 2 row 6 (single environment, standard Data Grid pagination — no special script needed) |
| 6c Integration contracts (AIS stub) | Row 25 |
| Fit-gap "Buy" (inspection calendar) | Row 0.1, consumed at row 32 |
| Architecture review sign-off | No separate row — a review, not a buildable artifact |

No CONFIRMED decision from Stages 0-3 is without a build disposition.

## Coverage ledger

See `architecture/coverage-ledger.md` — every `claims` block above is cross-checked against the 7
BRDs' leaves (`bin/coverage-check.sh` equivalent walk, done by hand below since this is a
single-app, multi-module project — see that file's "Where the ledger lives").
