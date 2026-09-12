# Fit-Gap Analysis — Harbour Berth Booking

One row per source capability. Verdict vocabulary: **Native** (ships with Mendix/Atlas) ·
**Config** (native, needs setup) · **Buy** (marketplace) · **Build** (we script it) ·
**Workaround** (mxcli limitation → Studio Pro/manual) · **Gap** (unresolved, in `PROJECT.md`).

| Source capability | Mendix approach | Verdict | Open issue? |
|---|---|---|---|
| CRUD grids (Booking Board, My Bookings, Invoices, Tariffs, Reports lists) | Data Grid 2 | **Native** | — |
| Booking Board filters (terminal/status/ETA range) | Data Grid 2 filter widgets | **Native** | — |
| Role-based access (4 roles + company-scoped row security) | Built-in Administration module + entity access XPath constraint on ShippingAgent-owned entities | **Config** | — |
| Officer review "last 5 bookings of vessel" panel | Data Grid 2 sub-list, sorted, limited to 5 | **Native (Config)** | — |
| Inspection Calendar, drag-and-drop reschedule | No native Mendix calendar with drag-drop | **Buy** — marketplace calendar widget (e.g. a scheduler/calendar module) | yes — confirm which marketplace module at Stage 4 Step 0 before scripting |
| Monthly berth-occupancy CSV export | Native export-to-CSV / Data export widget | **Native (Config)** | — |
| E-mail notifications (status-change, daily digest) | Native Email connector + scheduled microflow (digest) | **Config** | — |
| Cargo-manifest PDF attachment | Native FileDocument entity + FileManager widget | **Config** | yes — size limit not decided (F003-Q3) |
| Audit trail (AuditEntry, generic log) | Hand-built entity + `SUB_AuditEntry_Log`, called from every status-changing microflow | **Build** | — (architecture decision F007-Q1 already resolved the association shape) |
| AIS position feed integration | No marketplace connector for a fictional feed; scheduled microflow stub | **Workaround (stub first)** | yes — no protocol/auth/failure-mode documented (sufficiency `integrations` = named, not specified) |
| Booking reference generator (`HB-YYYY-NNNNN`, permanent, never reused) | Custom microflow (sequence + uniqueness check) | **Build** | — |
| IMO-number exactly-7-digit validation | Attribute length 7 + regex/microflow validation | **Build** | resolved — see F002-Q1 |
| Fee calculation (length × days × rate, VAT, shore power, surcharges) | Custom microflow chain (`CAL_*`) | **Build** | — |
| Conditional rejection-reason requirement | Microflow validation on `ACT_ApprovalDecision_Decide` | **Build** | resolved — see F004-Q2 |
| Cancellation-fee threshold (72h / 50%) | Custom microflow constant | **Build** | resolved — see F003-Q1 (Ruling R3) |

**Marketplace rule of thumb applied:** only one "Buy" row (the inspection calendar drag-and-drop
widget) — everything else is native/config or a small custom microflow, consistent with "for a
small CRUD app, import almost nothing." The Administration module and Atlas/Data Grid 2 ship by
default and are not separately counted as imports.

**Deciding "Buy" here is not installing it** — the calendar widget import happens at
`brd-to-build-plan.md` Step 0, before any domain-model script.
