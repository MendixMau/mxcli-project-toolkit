# KB_HARBOUR_DomainModel

## Document Overview

Harbour Berth Booking System — complete requirements specification for the Port Authority's vessel booking, berth allocation, and operational management system. Covers booking lifecycle, tariff calculation, allocation rules, AIS integration, approval workflows, and reporting. 36 specification documents covering domain, business rules, integrations, and user workflows.

---

## Core Business Capabilities

### 1. Vessel Registry & Management
- **Entity:** Vessel
  - Name (mandatory)
  - IMO Number (unique, international identifier)
  - Type (Tanker, Container, General Cargo, etc.)
  - Length, Beam, Draft (physical dimensions)
  - Capacity (TEU for containers, tonnage for general cargo)
  - Flag State (country of registration)
  - OwnerAgent (booking contact)
  - AIS Feed Status (active/inactive)

- **Entity:** VesselType
  - Code, Name, Description
  - Default tariff category
  - Handling rules (crane requirements, berth type compatibility)

- **Business Rules:**
  - Rule VR01: Vessel uniqueness by IMO number
  - Rule VR02: AIS feed auto-populates vessel master data when available
  - Rule VR03: Flag state determines customs/security rules (not modeled in MVP)

---

### 2. Berth Master Data & Allocation
- **Entity:** Berth
  - BerthID (A1, A2, B1, B2, etc.)
  - Name, Location (port zone)
  - Length, Depth (suitability constraints)
  - EquipmentCapability (crane type, fender type)
  - Status (Available, Reserved, Maintenance, Blocked)
  - OperationalCost per day

- **Entity:** BerthSlot
  - BerthID + DateRange (unique constraint)
  - AvailableFrom, AvailableTo (time window)
  - ReservedFor (BookingID or maintenance)
  - Status (Open, Allocated, Hold)

- **Entity:** AllocationRule
  - Priority (vessel type → berth type preference)
  - Constraint (vessel max-length ≤ berth length, etc.)
  - Tariff modifier (premium for off-peak, penalty for wait)

- **Business Rules:**
  - Rule BA01: Allocation engine runs nightly; prefers earliest available berth matching vessel type
  - Rule BA02: Allocation respects wait time minimization for high-priority vessels
  - Rule BA03: No double-booking (SlotAllocated blocks future allocations during window)
  - Rule BA04: Berth unavailability enforced (maintenance windows block all bookings)

---

### 3. Booking Lifecycle
- **Entity:** Booking
  - BookingID (unique identifier)
  - VesselIMO (foreign key to Vessel)
  - RequestedFrom, RequestedTo (arrival/departure window)
  - Status (Draft, Submitted, Allocated, ConfirmedSchedule, Arrived, Completed, Cancelled)
  - BerthID (assigned after allocation)
  - AgentID (booking contact)
  - CreatedAt, SubmittedAt, CancelledAt (audit trail)

- **Entity:** BookingRequest
  - RequestID (unique)
  - BookingID (parent)
  - Status (Open, Accepted, Rejected, Superseded)
  - RequestType (New, Modification, Cancellation, Extension)
  - Reason/Justification (for priority requests)

- **Screens:**
  - Booking Request Form (Agent portal)
    - Vessel selector (IMO lookup via AIS feed)
    - Date/time range input
    - Special requirements (cargo type, equipment, certifications)
    - Submit button
  - Booking Status View
    - Current allocation, estimated arrival, berth assignment
    - Tariff estimate, cost breakdown
    - Cancel/modify buttons (if status permits)
  - Allocations Dashboard (Port Operations)
    - Gantt chart of berth utilization
    - Manual reallocation interface
    - Conflict detection alerts

- **Business Rules:**
  - Rule BK01: Request window must be ≥ 6 hours, ≤ 30 days in advance
  - Rule BK02: Cancellation within 24 hours of ETAssignment incurs 25% penalty
  - Rule BK03: Allocation engine respects "Hold Request" (crew change, fuel stop) priority
  - Rule BK04: Double-booking prevention (overlapping time windows reject automatically)
  - Rule BK05: Booking request submitted → automatic allocation attempt within 30 minutes

---

### 4. Tariff & Charges
- **Entity:** TariffRate
  - RateID (unique)
  - EffectiveFrom, EffectiveTo (versioning)
  - VesselTypeCategory (Tanker, Container, etc.)
  - BasisUnit (per day, per ton, per TEU)
  - BaseRate (currency amount)
  - DiscountRules (volume, frequency, season)

- **Entity:** ServiceCharge
  - ChargeType (Harbour dues, Pilotage, Towage, Crane rental, Waste disposal)
  - Amount, Unit (per day, per occurrence)
  - AppliesTo (vessel type, berth type, cargo type)

- **Tariff Calculation:**
  - Harbour dues = BaseRate × StayDays × (1 + SizeModifier) × (1 - VolumeDiscount)
  - Service charges apply based on vessel/cargo type
  - Exempt vessels: Government, Emergency, Scheduled ferry (exempt on registration)

- **Screens:**
  - Tariff Estimation
    - Displays estimated charges before booking confirmation
    - Breakdown by component (harbour, services, penalties/discounts)
  - Tariff Admin (Port Finance)
    - Maintain TariffRate, ServiceCharge, DiscountRule records
    - Version control on rate changes
    - Historical lookup

- **Business Rules:**
  - Rule TR01: Tariff recalculated nightly; booked charges locked at submission
  - Rule TR02: Exempt vessels (gov't, scheduled) require certification/registration flag
  - Rule TR03: Tariff includes GST (if applicable) at display time, calculated on final charges

---

### 5. Officer Review & Approval
- **Entity:** ApprovalStep
  - StepID, BookingID
  - Stage (Initial Triage, Safety Review, Environmental Check, Finance Review)
  - Status (Pending, Approved, Rejected, OnHold)
  - AssignedTo (OfficerID)
  - CreatedAt, ResolvedAt

- **Entity:** ApprovalDecision
  - DecisionID, StepID
  - Verdict (Approve, Reject, Defer, RequestMoreInfo)
  - Notes (reason for decision)
  - DecidedBy (OfficerID), DecidedAt

- **Screens:**
  - Officer Review Queue
    - List of pending approvals by stage
    - Booking details summary (vessel, berth, dates, cargo)
    - Review form with checklist + notes
    - Approve/Reject buttons
  - Review History
    - All past approval decisions and notes (audit log)

- **Business Rules:**
  - Rule AP01: Booking enters Initial Triage automatically on submission
  - Rule AP02: Safety Review required for hazardous cargo (flagged by cargo type)
  - Rule AP03: Environmental approval required if discharge planned
  - Rule AP04: Finance review required if charges exceed threshold (e.g., >50K)
  - Rule AP05: Approval chain blocks progression (all stages must approve before Confirmed)
  - Rule AP06: Rejection returns booking to Draft; agent must resubmit

---

### 6. AIS Integration
- **System:** AIS (Automatic Identification System) Feed
- **Source:** External maritime data provider
- **Frequency:** Hourly updates for vessels within 50nm of port
- **Fields Populated:**
  - Vessel Name, Position (lat/lon)
  - Course, Speed, Draught (current)
  - Destination (port code)
  - ETA (estimated time of arrival, calculated from speed and course)
- **Integration Method:** REST API polling
- **Authentication:** API key (stored in credentials vault, not visible to agents)
- **Stubability:** YES — can return mock vessel data for testing

- **Business Rules:**
  - Rule AIS01: AIS feed updates populate VesselMasterData on IMO match
  - Rule AIS02: Automated ETA comparison against booking request dates triggers alerts if mismatch >2 hours
  - Rule AIS03: No direct UI access to raw AIS data (aggregate summary only for ops)

---

### 7. Reporting & Analytics
- **Report 1: Daily Allocations Report**
  - Berth utilization by day
  - Vessel count, total cargo
  - Revenue by tariff category
  - Allocation conflicts/penalties

- **Report 2: Financial Report**
  - Revenue (by vessel type, berth, service charge)
  - Collections status
  - Bad debt (unpaid invoices >30 days)
  - Forecast (based on booked ETAs)

- **Report 3: Operational Report**
  - On-time arrival rate (actual vs booked)
  - Cancellation rate (with reasons)
  - Average berth turnaround time
  - Equipment utilization (cranes, tugs, etc.)

---

## Roles & Permissions

| Role | Booking Request | Allocation | Tariff View | Officer Approval | Master Data | Reports |
|------|-----------------|-----------|-------------|------------------|-------------|---------|
| **Agent** | Create/View/Modify own | View own | View estimate | Monitor status | Lookup only | N/A |
| **Ops Manager** | View all | Create/Modify/View | View all | Assign/Monitor | View | View all |
| **Officer** (Triage/Safety/Env/Finance) | View assigned | N/A | N/A | Approve/Reject | Lookup | N/A |
| **Finance** | View | View | Manage | Approve finance checks | N/A | Manage/View |
| **Admin** | Full access | Full access | Manage rates | Override | Manage | Manage |

---

## Open Questions / Decisions

- **D01:** Should "Hold Request" vessels (crew change, repairs) be prioritised equally with commercial bookings, or separate queue? **Status: Deferred** → design decision
- **D02:** Is berth reallocation allowed within 48 hours of ETAssignment? **Status: Deferred** → ops policy
- **D03:** Should tariff discounts cascade (e.g., volume discount + seasonal)? **Status: Deferred** → finance policy
- **D04:** ETA mismatch tolerance: 2 hours or 10% of voyage time? **Status: Deferred** → business rule

---

## Integration Touchpoints Summary

- **AIS Feed:** Inbound, hourly, updates vessel data, triggers ETA alerts
- **Payment Gateway:** Outbound, collects tariff charges (stub for MVP)
- **Email Notification:** Booking confirmation, approval status, alerts (external SMTP, stub for MVP)
- **Reporting Export:** On-demand PDF/CSV export (file system, stub for MVP)

