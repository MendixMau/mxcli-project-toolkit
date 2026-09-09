# Architecture Blueprint — Harbour Berth Booking

## Module Structure

8 modules organizing the 8 business capabilities:

- **BookingMgmt** — Booking lifecycle (F001)
- **OfficerMgmt** — Officer review & approval (F002)
- **MasterDataMgmt** — Berth & vessel data (F003)
- **FinanceMgmt** — Tariffs & invoicing (F004)
- **InspectionMgmt** — Inspection workflows (F005)
- **ComplianceMgmt** — Reporting & audit (F006)
- **SecurityMgmt** — User roles & security (F007)
- **IntegrationMgmt** — External integrations (F008)

## Layer Diagram

```
[Presentation] — Pages, forms, dashboards
   ↓
[Business Logic] — Microflows, validations
   ↓
[Data Layer] — Entities, associations
```

## Dependencies

- SecurityMgmt (prerequisite) → all others
- MasterDataMgmt (prerequisite) → BookingMgmt, InspectionMgmt
- BookingMgmt → OfficerMgmt, FinanceMgmt, InspectionMgmt
- OfficerMgmt → FinanceMgmt
- FinanceMgmt, InspectionMgmt → ComplianceMgmt
- IntegrationMgmt (parallel) → all modules

## Fit-Gap Analysis

No legacy system to fit-gap against. All capabilities built to requirements.
