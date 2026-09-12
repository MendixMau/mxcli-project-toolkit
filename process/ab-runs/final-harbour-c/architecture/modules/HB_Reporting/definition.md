# Module: HB_Reporting

**Layer:** Common
**Responsibility:** The one shared audit-logging service every other module calls, plus the
monthly berth-occupancy CSV report. Deliberately a "reuse" module (`modularize-domain.md` Step 2
criterion 2) even though it owns a single entity — the audit-log pattern is the kind of thing
that would be lifted into another app as-is.

## Entities

| Entity | Persistent? | Key attributes | Notes |
|---|---|---|---|
| AuditEntry | Yes | OccurredOn, Actor, Action, EntityName, Detail, RelatedReference | **Architecture decision (F007-Q1):** dropped the source's literal `AuditEntry_BookingRequest` association — one FK cannot cover the four entity types ch26 says are audited (booking/decision/invoice/inspection), and a Common module holding an association into a feature module is the exact upward-arrow the layer rule forbids. `EntityName` + the new `RelatedReference` text attribute (natural key, e.g. a `BookingRequest.Reference`) carry the same information generically. |

## Key microflows

| Microflow | Kind | Purpose |
|---|---|---|
| SUB_AuditEntry_Log | SUB_ | Called from every status-changing microflow in HB_Booking/HB_Finance/HB_Inspection; params: Actor, Action, EntityName, RelatedReference, Detail |
| ACT_Report_BerthOccupancy_ExportCsv | ACT_ | Monthly berth occupancy per terminal, CSV |

## Pages / snippets

| Page | Type | Source screen |
|---|---|---|
| Reports_Overview | Overview | ch32 |

## Security

Harbour Master + Berth Officer can view reports; AuditEntry itself has no UI beyond an
Administration-style read-only grid (no chapter documents a dedicated audit-trail screen).

## Dependencies

- **Imports (calls into):** none — bottom of the graph alongside HB_MasterData.
- **Exposes (called by):** HB_Booking, HB_Finance, HB_Inspection (all call `SUB_AuditEntry_Log`).
- **Cross-module associations:** none. This is the point of the F007-Q1 decision above — a
  Common module must never own an association pointing into a feature module.
