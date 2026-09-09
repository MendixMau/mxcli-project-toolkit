# Build Plan — Harbour Berth Booking

## Execution Order (Dependency-Driven)

### Phase 1: Foundation (Prerequisite for all others)
1. **SecurityMgmt** — User roles, access control, authentication
   - 2 entities, 1 page, 2 microflows
   - Est. 40 hours

2. **MasterDataMgmt** — Berth and vessel reference data
   - 2 entities, 2 pages, 2 microflows
   - Est. 35 hours

### Phase 2: Core Business Processes (Parallel-buildable)
3. **BookingMgmt** — Booking request, lifecycle, status tracking
   - 2 entities, 3 pages, 5 microflows
   - Depends: SecurityMgmt, MasterDataMgmt
   - Est. 50 hours

4. **OfficerMgmt** — Officer review queue, approval decisions
   - 2 entities, 1 page, 3 microflows
   - Depends: BookingMgmt
   - Est. 40 hours

5. **FinanceMgmt** — Tariff configuration, invoice generation
   - 2 entities, 2 pages, 3 microflows
   - Depends: BookingMgmt
   - Est. 45 hours

### Phase 3: Supporting Operations
6. **InspectionMgmt** — Inspection scheduling, checklists, outcomes
   - 2 entities, 2 pages, 3 microflows
   - Depends: MasterDataMgmt, BookingMgmt
   - Est. 50 hours

### Phase 4: Cross-Cutting & Integration
7. **ComplianceMgmt** — Reporting, audit trails, compliance dashboards
   - 2 entities, 2 pages, 2 microflows
   - Depends: All operational modules
   - Est. 40 hours

8. **IntegrationMgmt** — AIS feed integration
   - 1 entity, 0 pages, 2 microflows
   - Depends: MasterDataMgmt
   - Est. 25 hours

## Total Effort
- 8 modules
- 15 entities
- 14 pages
- 22 microflows
- **Est. 325 hours (~8 weeks at 5-day/40-hour sprints)**

## Key Decisions
- Single Mendix app (no multi-app decomposition)
- Atlas UI framework for pages
- Persistent entities with audit fields
- Synchronous microflows for business rules validation
- OData integration for AIS feed (stub for demo)

## Coverage Ledger
(See architecture/coverage-ledger.md per module)

## Placeholder for Role-to-Access Table
(Generated per module during build loop)
