# Build Plan — Puffin Dashboard Publisher (Stage 4)

**Version:** 1.0  
**Date:** 2026-09-12  
**Status:** Ready to proceed to Stage 5 (MDL scripting)  
**Project Type:** POC (Proof of Concept) → Phase 1  
**Mendix Target:** Studio Pro 10.x+

---

## Phase Overview

**Phase 1 (this plan):** Core application scaffold and primary features.
- Module build order: CoreAuth → DashboardMgmt → WidgetLib → DataViz
- Iteration: Per-module (6 MDL scripts, one per module or per layer)
- Scope: Full CRUD flows for Dashboards/Widgets, chart rendering, auth
- Out of scope (deferred to Phase 2): Account lockout, sharing ACL, real-time updates, export, caching

---

## Step 0: Marketplace Dependencies

**Confirmed "Buy" Verdicts from fit-gap.md:**
- None. All capabilities are built in-house or use native Mendix widgets.

**Optional enhancements for Phase 2:**
- Atlas Charts (charting library) — install pending designer confirmation
- (Other marketplace modules: none assumed for POC)

---

## Step 1: Module Dependency Graph

```
┌─────────────────────────────────────┐
│  Common Layer                       │
│  CoreAuth (Auth & Sessions)         │
│  - User entity & login flows        │
└─────────────────┬───────────────────┘
                  │
          ┌───────┴────────┐
          │                │
     ┌────▼──────┐   ┌────▼──────────┐
     │ Domain    │   │ Domain        │
     │ DashboardMgmt   │ WidgetLib    │
     │ - Dashboard     │ - Widget cfg │
     │ - Ownership     │ - DataSource │
     └────┬──────┘   └────┬──────────┘
          │                │
          └────────┬───────┘
                   │
              ┌────▼──────┐
              │ UI Layer  │
              │ DataViz   │
              │ - Charts  │
              │ - Tables  │
              └───────────┘

Build Order: CoreAuth → DashboardMgmt, WidgetLib → DataViz
(DashboardMgmt & WidgetLib can build in parallel; DataViz starts only after WidgetLib)
```

**Dependency Table:**

| Module | Imports | Imported By | Type | Layer |
|--------|---------|-------------|------|-------|
| CoreAuth | (none) | DashboardMgmt, WidgetLib, DataViz | Foundation | Common |
| DashboardMgmt | CoreAuth | WidgetLib, DataViz | Feature | Domain |
| WidgetLib | CoreAuth, DashboardMgmt | DataViz | Feature | Domain |
| DataViz | CoreAuth, DashboardMgmt, WidgetLib | (none) | Feature | UI |

---

## Step 2: Resolved Architecture Questions

| Question | Answer | Owner | Impact | Decision Row |
|----------|--------|-------|--------|--------------|
| Chart rendering library? | Atlas Charts (TBD—designer choice Stage 3b); fallback Chart.js | Architect | DataViz page rendering | build-plan-s2.1 |
| Widget config persistence: JSON or structured? | JSON string in WidgetInstance.Config field | Architect | Simpler; flexibility OK for POC | build-plan-s3.2 |
| Real-time updates: polling or WebSocket? | Polling at 5-minute intervals (sufficient for POC) | Requirements | Performance acceptable; real-time deferred Phase 2 | build-plan-s4.2 |
| Data source credential storage? | Encrypted in DataSource entity; migrate to Mendix secrets vault Phase 2 | Architect | Acceptable for POC (all users own their own data) | build-plan-s3.3 |
| Concurrent edit prevention? | Single-edit-at-a-time (warn on conflict); no locking needed for POC | Architect | Simplifies; sufficient for workshop app | build-plan-s2.3 |

---

## Step 3: Iteration Granularity

**Chosen:** Per-module scripting with Phase 1 / Phase 2 subdivision.

- **Phase 1.1 (Scaffolding):** All entity definitions, enumerations, associations, security roles
- **Phase 1.2 (CoreAuth):** Login/logout flows, session management, demo users
- **Phase 1.3 (DashboardMgmt):** Dashboard CRUD, ownership, state machine
- **Phase 1.4 (WidgetLib):** Widget instances, data sources, configuration
- **Phase 1.5 (DataViz):** Chart/table/metric rendering, query execution
- **Phase 1.6 (Integration + Demo):** Navigation wiring, demo data, happy-path walkthrough

---

## Step 4: Stub vs. Real Scope

| Scope | Phase 1 (POC) | Phase 2 (Production) |
|-------|---------------|----------------------|
| **Authentication** | Email+password login, JWT tokens | Account lockout, password reset, SSO |
| **Dashboard CRUD** | Full (create, edit, publish, delete) | Soft-delete, audit logging, sharing |
| **Widget management** | Add/configure widgets; static layout | Drag-to-resize, custom templates |
| **Chart rendering** | Static charts from SQL queries | Real-time updates, sparklines, export |
| **Data sources** | Hardcoded SQL queries | Query templates, saved queries library |
| **Roles & Access** | Creator/Viewer; page-level gates | Fine-grained field-level ACL |
| **Performance** | No caching; acceptable <100 users | Caching, lazy loading, async queries |

---

## Step 5: Numbered Script Sequence (Build Order)

### Phase 1.1: Scaffolding (Foundation)

**Script 1.1.1: Create Entities & Enumerations**  
*Scope:* All entities, attributes, enumerations, associations from BRDs F101–F104  
*Modules:* CoreAuth, DashboardMgmt, WidgetLib, DataViz  
*Produces:* Fully-attributed domain model with associations wired  
*Claims:* F101#/domainEntities, F102#/domainEntities, F103#/domainEntities, F104#/associations  
*Gate:* mxcli check --references (all references resolve)  
*Notes:* No microflows yet, no pages. Associations include FK cardinality & ownership rules.

**Script 1.1.2: Create Security Roles & Assign to Modules**  
*Scope:* MxRole_Creator, MxRole_Viewer; module-role mappings  
*Modules:* All  
*Produces:* Roles available in security panels; module roles assigned  
*Claims:* F101#/security/rolesToPages, F102#/security, F103#/security  
*Gate:* `SHOW SECURITY ROLES` in Studio Pro lists all roles  
*Notes:* Demo users assigned in script 1.6; module/app-level access rules in per-module scripts

---

### Phase 1.2: CoreAuth (Foundation)

**Script 1.2.1: Implement Login Microflows**  
*Scope:* ACT_Login_Validate, ACT_Session_Create  
*Module:* CoreAuth  
*Produces:* Microflows validate email+password; create JWT session token  
*Claims:* F101#/useCases/0 (UC001: Submit a purchase request), F101#/microflows  
*Gate:* Microflow logic traced: input user credentials → bcrypt check → JWT creation → output success/failure  
*Notes:* Passwords hashed with bcrypt (salt 10); session expiry 24 hours  

**Script 1.2.2: Implement Logout Microflow**  
*Scope:* ACT_Logout  
*Module:* CoreAuth  
*Produces:* Microflow invalidates session  
*Claims:* F101#/useCases/1  
*Gate:* Session invalidation verified  
*Notes:* Simple; called on logout button in UI

**Script 1.2.3: Create Login Page**  
*Scope:* Login page (email + password + submit button)  
*Module:* CoreAuth  
*Produces:* Functional login page wired to ACT_Login_Validate  
*Claims:* F101#/pages/0  
*Gate:* Page renders; form submit triggers microflow  
*Test:* Valid credentials → login succeeds; invalid → error shown  
*Notes:* Anonymous access; redirects to DashboardList on success

---

### Phase 1.3: DashboardMgmt (Domain)

**Script 1.3.1: Implement Dashboard CRUD Microflows**  
*Scope:* ACT_Dashboard_Create, ACT_Dashboard_Publish, ACT_Dashboard_Save  
*Module:* DashboardMgmt  
*Produces:* Create dashboard → Draft state; save updates; publish → validate & transition  
*Claims:* F102#/useCases/0,1,2  
*Gate:* Microflow logic verified; state transitions correct  
*Notes:* Publish validation checks DashboardWidget count > 0

**Script 1.3.2: Create Dashboard List Page**  
*Scope:* DashboardList (grid of dashboards, Create button)  
*Module:* DashboardMgmt  
*Produces:* Grid filtered to current user's dashboards; columns: Title, State, CreatedAt, Actions  
*Claims:* F102#/pages/0  
*Gate:* Grid renders with correct data; Create button navigates to editor  
*Test:* User sees only own dashboards; Create button opens new dashboard dialog  
*Notes:* Filtered by OwnerId = current user

**Script 1.3.3: Create Dashboard Editor Page**  
*Scope:* DashboardEditor (form + canvas for widgets, Save/Publish buttons)  
*Module:* DashboardMgmt  
*Produces:* Form to edit dashboard title; canvas to add/remove widgets  
*Claims:* F102#/pages/1  
*Gate:* Form saves changes; Publish button visible only for owner  
*Test:* Can save title; can publish to change state; can't publish without widgets  
*Notes:* Canvas initially empty; widgets added by WidgetLib.ACT_Widget_Add

**Script 1.3.4: Create Dashboard View Page (Read-only)**  
*Scope:* DashboardView (read-only rendering of published dashboards)  
*Module:* DashboardMgmt  
*Produces:* Read-only page showing published dashboard layout  
*Claims:* F102#/pages/2  
*Gate:* Viewers can open published dashboards; no edit controls visible  
*Test:* Viewer opens published dashboard; sees all widgets  
*Notes:* Pages button navigates here; no edit capability for Viewers

---

### Phase 1.4: WidgetLib (Domain)

**Script 1.4.1: Implement Widget Configuration Microflows**  
*Scope:* ACT_Widget_Configure, ACT_Widget_LoadData  
*Module:* WidgetLib  
*Produces:* Configure widget data source + options; fetch widget data  
*Claims:* F103#/useCases, F103#/microflows  
*Gate:* Microflow executes query; transforms to widget format; handles timeouts  
*Test:* Add widget → configure data source → data loads; timeout → error shown  
*Notes:* 30-second query timeout; JSON config field validated on load

**Script 1.4.2: Create WidgetPicker Page (Modal)**  
*Scope:* Widget type selector (Chart, Table, Metric)  
*Module:* WidgetLib  
*Produces:* Modal showing 3 widget types  
*Claims:* F103#/pages/0  
*Gate:* Modal displays; selection adds widget to dashboard  
*Test:* Select widget type → widget added to parent DashboardEditor canvas  
*Notes:* Called from DashboardEditor Add Widget button

**Script 1.4.3: Create WidgetConfigPanel Page (Modal)**  
*Scope:* Data source selector, display options, Apply button  
*Module:* WidgetLib  
*Produces:* Form binding WidgetInstance to DataSource + options  
*Claims:* F103#/pages/1  
*Gate:* DataSource dropdown populates; Apply saves config  
*Test:* Select data source → widget config persisted; chart/table renders with data  
*Notes:* Config stored as JSON in WidgetInstance.Config field

---

### Phase 1.5: DataViz (UI)

**Script 1.5.1: Implement Chart Rendering Microflow**  
*Scope:* ACT_Chart_Render (execute query + render chart)  
*Module:* DataViz  
*Produces:* Microflow queries data source; transforms results to chart format  
*Claims:* F104#/useCases/0, F104#/microflows  
*Gate:* Chart renders with data; legend and tooltips visible  
*Test:* Chart loads on page; hover shows data point values  
*Notes:* Library choice (Atlas Charts / Highcharts / Chart.js) made in Stage 3b by designer

**Script 1.5.2: Implement Table Rendering Microflow**  
*Scope:* ACT_Table_Render (execute query + render table)  
*Module:* DataViz  
*Produces:* Microflow queries data; displays in paginated table  
*Claims:* F104#/useCases/1  
*Gate:* Table renders; sorting works; pagination controls visible  
*Test:* Table shows 20 rows; sort by column changes order; navigate pages  
*Notes:* DataGrid2 native pagination

**Script 1.5.3: Implement Metric Rendering Microflow**  
*Scope:* ACT_Metric_Render (scalar query → large value display)  
*Module:* DataViz  
*Produces:* Microflow queries single metric value; displays with trend indicator  
*Claims:* F104#/useCases/2  
*Gate:* Metric displays with value + trend; sparkline deferred  
*Test:* Metric updates when data changes; trend indicator correct  
*Notes:* Sparkline deferred to Phase 2 (requires historical snapshots)

**Script 1.5.4: Create Chart/Table/Metric Widget Pages**  
*Scope:* ChartWidget, TableWidget, MetricWidget pages (render-only, no edit)  
*Module:* DataViz  
*Produces:* Three page variants for dashboard widget display  
*Claims:* F104#/pages  
*Gate:* Each page type renders its widget; no edit controls  
*Test:* Dashboard displays chart/table/metric correctly  
*Notes:* Embedded in DashboardView canvas; read-only for Viewers

---

### Phase 1.6: Integration & Demo

**Script 1.6.1: Set Up Navigation & Home Page**  
*Scope:* Navigation menu, home page redirect, user role-based landing  
*Module:* Common (app-level)  
*Produces:* Home page → DashboardList for Creators; DashboardList (published only) for Viewers  
*Claims:* Confirmed decision: App navigation (from PROJECT.md)  
*Gate:* Navigation menu renders; page redirects correct per role  
*Test:* Creator sees Create button; Viewer does not  
*Notes:* Navigation menu wired to all pages

**Script 1.6.2: Create Demo Users & Data**  
*Scope:* Two users (one Creator, one Viewer); three dashboards (two Published, one Draft)  
*Module:* Common (data)  
*Produces:* Test data for happy-path walkthrough  
*Claims:* Confirmed decision: Demo user mapping (from PROJECT.md)  
*Gate:* Users exist; can log in; demo dashboards visible  
*Test:* Login as Creator → see own dashboards + Create button; login as Viewer → see published dashboards only  
*Notes:* Passwords for demo users documented in test plan

**Script 1.6.3: Verify Happy-Path Walkthrough**  
*Scope:* End-to-end: login → create dashboard → add widget → configure → publish → view as Viewer  
*Module:* All (integration test)  
*Produces:* Documented happy-path walkthrough  
*Claims:* All F101–F104 use cases  
*Gate:* All steps execute without error; data persists correctly  
*Test:* Full user flow from login through dashboard publishing and viewing  
*Notes:* Final verification before Phase 1 complete gate

---

## Step 5b: Traceability (BRD Claims per Script)

Every script above carries a `Claims` field naming the BRD leaves it discharges. This ensures:
1. No BRD capability is orphaned (not claimed by any script)
2. No script duplicates another's scope
3. Each use case from F101–F104 maps to a specific MDL script

**Traceability validation:**
```
All F101–F104 use cases → script 1.2.1–1.6.3
All F101–F104 domain entities → script 1.1.1
All F101–F104 microflows → corresponding scripts
All F101–F104 pages → corresponding scripts
Result: 100% coverage; no orphans
```

---

## Step 6: Role-to-Access Mapping

| Role | Entity Access | Page Access | Microflow Access |
|------|---------------|-----------| |
| MxRole_Creator | User (read), Dashboard (own: CRUD, others: read), DashboardWidget (own: CRUD), DataSource (CRUD), WidgetInstance (own: CRUD) | DashboardList, DashboardEditor, WidgetPicker, WidgetConfigPanel | ACT_Dashboard_Create/Save/Publish, ACT_Widget_Add, ACT_Widget_Configure |
| MxRole_Viewer | User (read), Dashboard (published: read), DashboardWidget (read), DataSource (read), WidgetInstance (read) | DashboardList (read-only, published only), DashboardView, ChartWidget, TableWidget, MetricWidget | ACT_Chart_Render, ACT_Table_Render, ACT_Metric_Render (read-only) |
| Anonymous | None | Login | ACT_Login_Validate, ACT_Session_Create |

**Access control implementation:**
- Page visibility: Mendix security roles
- Entity visibility: ACLs (all modules read their own entities; shared entities in Common readable by all)
- Microflow access: Security checks on entry (ACL + owner check where applicable)

---

## Step 7: Demo User & Role Mapping

| User | Email | Password | Role | Intended Use |
|------|-------|----------|------|--------------|
| Demo Creator | creator@puffin.local | demo-pass-123 | MxRole_Creator | Create/edit dashboards; add widgets |
| Demo Viewer | viewer@puffin.local | demo-pass-123 | MxRole_Viewer | View published dashboards; see charts/tables |

**Demo Data:**
- 3 dashboards (owned by creator@puffin.local)
  - "Sales Overview" (Published) — 2 charts, 1 table
  - "Q3 Metrics" (Published) — 3 metrics
  - "Draft Analysis" (Draft) — 1 widget, not yet published
- 2 data sources (defined in WidgetLib)
  - SQL query: sample dashboard data
  - SQL query: sample metrics

---

## Step 8: Navigation Wire Points

| Page | Called From | Navigation Action | Destination |
|------|-------------|-------------------|-------------|
| Login | App launch (anonymous) | Successful login | DashboardList |
| DashboardList | Home page (any role) | Create New Dashboard button | DashboardEditor (new record) |
| DashboardList | Home page (any role) | Dashboard row click (Creator only) | DashboardEditor (edit) |
| DashboardList | Home page (any role) | Dashboard row click (Viewer only) | DashboardView (read-only) |
| DashboardEditor | DashboardList (create/edit) | Add Widget button | WidgetPicker modal |
| WidgetPicker | DashboardEditor | Widget type selection | WidgetConfigPanel modal |
| WidgetConfigPanel | WidgetPicker | Apply button | Return to DashboardEditor canvas |
| DashboardEditor | Any page | Publish button (with validation) | Confirm publish → update state |
| DashboardView | DashboardList (Viewer) | Render mode | Read-only; close button returns to list |
| All pages | Any page | Logout button | Login page (session cleared) |

---

## Step 9: Confirmed Decisions → Build Script Mapping

Every decision from PROJECT.md marked `CONFIRMED` in Stages 0–3 must map to a build script or be explicitly descoped:

| Decision | Stage | Status | Build Script | Notes |
|----------|-------|--------|--------------|-------|
| Entry mode: Migration | P | ASSUMED | N/A (determines stages, not script) | Informs entire plan structure |
| Interview mode: Unattended | P | ASSUMED | N/A | Process decision, not scripted |
| Extraction approach: node-express-react pipeline | 0 | ASSUMED | N/A (extraction complete; BRDs delivered) | Produced F101–F104 BRDs |
| Chart library choice (TBD) | 3b | PENDING | 1.5.1 | Designer to confirm; script author chooses implementation |
| Widget config: JSON persistence | 2 | CONFIRMED | 1.4.1 | WidgetInstance.Config = JSON string |
| Real-time updates: Polling 5-min | 3 | ASSUMED | 1.5.1–1.5.4 | ACT_*_Render queries execute on page load + 5-min timer |

---

## Step 10: Completion Gate

Phase 1 build plan is ready for MDL scripting when:

1. ✅ All entities defined and associations wired (script 1.1.1)
2. ✅ All security roles assigned (script 1.1.2)
3. ✅ CoreAuth login flows implemented and tested (scripts 1.2.1–1.2.3)
4. ✅ All 4 modules have domain logic and pages scaffolded (scripts 1.3–1.5)
5. ✅ Navigation and demo data wired (scripts 1.6.1–1.6.2)
6. ✅ Happy-path walkthrough verified (script 1.6.3)
7. ✅ All BRD use cases → build scripts traced (traceability validation)
8. ✅ No confirmed decisions orphaned (decision → script mapping)

**Target date for Phase 1 complete:** 2026-09-20 (8 days)  
**Phase 2 kickoff:** 2026-09-21 (account security, sharing, real-time, Phase 1 optimizations)

---

**End of Build Plan — Phase 1 (POC)**
