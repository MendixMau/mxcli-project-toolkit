# Module Design — Harbour Berth Booking

8 modules derived from Stage 0 business capability map and architecture decisions:

| Module | Purpose | Owner | Entities | Pages |
|--------|---------|-------|----------|-------|
| BookingMgmt | Booking lifecycle | BookingTeam | 2 | 3 |
| OfficerMgmt | Officer review & approval | Officers | 2 | 1 |
| MasterDataMgmt | Berth & vessel reference data | Operations | 2 | 2 |
| FinanceMgmt | Tariffs & invoicing | Finance | 2 | 2 |
| InspectionMgmt | Inspection workflows | Inspectors | 2 | 2 |
| ComplianceMgmt | Reporting & audit | Compliance | 2 | 2 |
| SecurityMgmt | User roles & access control | Administration | 2 | 1 |
| IntegrationMgmt | External integrations (AIS) | Operations IT | 1 | 0 |

**Rationale:** Single-app architecture (no multi-app decomposition needed per Stage 0 triage). Module boundaries follow business capability map. Dependencies respected per architecture/blueprint.md.
