# Harbour Berth Booking - Architecture Blueprint

## Module Structure

### Module 1: VesselRegistry
- Entities: Vessel, VesselType
- Responsibility: Master data management, AIS integration
- Dependencies: None
- Screens: Vessel search, Type maintenance

### Module 2: BerthAllocation  
- Entities: Berth, BerthSlot, AllocationRule
- Responsibility: Berth management, slot allocation logic
- Dependencies: VesselRegistry (read)
- Screens: Utilization dashboard, Manual allocation

### Module 3: BookingLifecycle
- Entities: Booking, BookingRequest
- Responsibility: Booking submission, status tracking
- Dependencies: VesselRegistry, BerthAllocation
- Screens: Request form, Status view, Booking list

### Module 4: Tariff
- Entities: TariffRate, ServiceCharge, TariffCalculation
- Responsibility: Rate management, charge calculation
- Dependencies: BookingLifecycle (read)
- Screens: Tariff estimation, Admin screens

### Module 5: Approvals
- Entities: ApprovalStep, ApprovalDecision
- Responsibility: Multi-stage approval workflow
- Dependencies: BookingLifecycle (read/update)
- Screens: Review queue, Review history, Configuration

## Architecture Decisions

- **Single Mendix app**: All modules in one app, unified database
- **Shared database**: All modules access shared entities
- **API boundaries**: Each module has internal APIs for cross-module calls
- **AIS integration**: Pull-based, hourly sync from external feed (stubbed in MVP)

## Fit-Gap Analysis

| Area | Source | Target | Verdict |
|------|--------|--------|---------|
| Booking lifecycle | Complete specification | 1:1 mapping | Ready |
| Berth allocation logic | Rules specified | Algorithmic implementation | Build |
| Tariff calculation | Formula specified | Microflow implementation | Build |
| Approval workflow | Process documented | State machine implementation | Build |
| AIS integration | API contract named | REST integration stub | Build |

All fit-gap items are build candidates (no buy/reuse options in scope).

## Security Model

- Role-based access control: Agent, Ops, Officer, Finance, Admin
- Encryption: TBD per ops policy
- Audit trail: ApprovalDecision records all approvals

## Performance & Scale

- Estimated: 500 bookings/day peak, 50 concurrent users
- Allocation algorithm: Nightly batch, <5 min execution target
- Database indexes: On Booking.Status, Berth allocation lookup paths
