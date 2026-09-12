# Module: HB_Inspection

**Layer:** Domain + Logic
**Responsibility:** Scheduling and recording inspections, checklist outcomes, and gating
departure clearance and dangerous-goods approval.

## Entities

| Entity | Persistent? | Key attributes | Notes |
|---|---|---|---|
| Inspection | Yes | ScheduledFor, CompletedOn, Outcome (enum), InspectorName, FollowUpRequired | Failed blocks departure until a follow-up Passes |
| InspectionItem | Yes | Category (enum: Safety/Environmental/Documentation/Security), IsCompliant, Severity | Any non-compliant High-severity item ⇒ Inspection.Outcome = Failed |

## Key microflows

| Microflow | Kind | Purpose |
|---|---|---|
| ACT_Inspection_Schedule | ACT_ | Against an Approved BookingRequest; notifies agent |
| VAL_DangerousGoods_RequireInspection | VAL_ | Blocks Approval when CargoClass=DangerousGoods and no Inspection exists |
| ACT_InspectionItem_Record | ACT_ | Records compliant/severity/note per checklist item |
| ACT_Inspection_Complete | ACT_ | Derives Outcome from checklist items |
| VAL_DepartureClearance_Check | VAL_ | All Inspections on the booking Passed or Deferred |

## Pages / snippets

| Page | Type | Source screen |
|---|---|---|
| InspectionCalendar_Overview | Overview | ch31 — per-day/per-inspector, drag-drop reschedule |
| Inspection_Checklist | NewEdit | ch23 |

## Security

Inspector: schedule, record checklist, complete. Berth Officer: grant departure clearance
(reads Inspection.Outcome, does not edit it).

## Dependencies

- **Imports (calls into):** HB_Booking (`BookingRequest` — reads CargoClass/Status; departure
  clearance gates BookingRequest), HB_Reporting (`SUB_AuditEntry_Log`).
- **Exposes (called by):** HB_Finance (late-arrival surcharge relief is officer-driven, not a
  call into this module — no import).
- **Cross-module associations:** `Inspection_BookingRequest` (owned by HB_Inspection, pointing
  into HB_Booking — peer feature-to-feature, justified: an inspection is always scheduled
  against exactly one booking).
