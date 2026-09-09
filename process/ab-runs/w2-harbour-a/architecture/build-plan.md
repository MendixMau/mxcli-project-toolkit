# Harbour Berth Booking - Build Plan

## Build Slice 1: Core Booking Flow (MVP)

### Phase 1.1: Foundation (Week 1)
- Module: VesselRegistry
  - Vessel entity and CRUD screens
  - VesselType reference data
  - AIS feed stub (returns mock data)
  
- Module: BerthAllocation  
  - Berth entity and master data screens
  - Slot allocation logic (simple FIFO for MVP)

**Deliverable:** Vessel and Berth master data functional, ready for booking requests

### Phase 1.2: Booking Workflow (Week 2)
- Module: BookingLifecycle
  - Booking and BookingRequest entities
  - Request form (Agent portal)
  - Automatic allocation on submission
  - Status dashboard
  
**Deliverable:** Agents can submit bookings, system allocates to berths

### Phase 1.3: Tariff & Approval (Week 3)
- Module: Tariff
  - TariffRate and ServiceCharge entities
  - Tariff calculation microflow
  - Estimation screen
  
- Module: Approvals (stub)
  - ApprovalStep, ApprovalDecision entities
  - Initial Triage stage only
  
**Deliverable:** Booking includes tariff estimate; basic approval queue

### Phase 1.4: Testing & Hardening (Week 4)
- E2E journey: Agent submits booking → system allocates → approval
- Load test: 500 bookings/day simulation
- Fix critical issues
- User acceptance testing

**Deliverable:** MVP ready for pilot deployment

---

## Build Slice 2: Enhanced Features (Post-MVP)

### Phase 2.1: Advanced Approval (Week 5-6)
- Complete approval chain: Safety, Environment, Finance reviews
- Conditional routing based on cargo/charges
- Rejection/revision workflow

### Phase 2.2: Tariff Enhancements (Week 6)
- Discount rules and volume pricing
- Exempt vessel handling
- Tariff versioning & historical lookup

### Phase 2.3: Reporting (Week 7)
- Daily allocations report
- Financial report (revenue, collections)
- Operational report (on-time rate, utilization)

### Phase 2.4: AIS Real Integration (Week 8)
- Replace stub with real AIS feed
- Real-time ETA updates
- Vessel data auto-population

---

## Module Build Order

1. VesselRegistry (Foundation)
2. BerthAllocation (Foundation)
3. BookingLifecycle (Core value)
4. Tariff (Core value)
5. Approvals (Quality gate)
6. Reporting (Post-MVP)

---

## Estimated Effort & Duration

**Slice 1 (MVP):** 4 weeks, 2-3 developers
- VesselRegistry: 1w (3 days setup, 2 days testing)
- BerthAllocation: 1.5w (allocation logic, gantt chart)
- BookingLifecycle: 1.5w (2-entity workflow)
- Tariff + Approvals: 1w (calculation, simple approval)
- Testing & hardening: 1w

**Slice 2:** 4 weeks additional
- Advanced approvals: 1.5w
- Tariff enhancements: 1w
- Reporting: 1.5w
- AIS integration: 1w

**Total Project:** 8 weeks

---

## Go-Live Plan

**MVP Pilot (End of Week 4):**
- Limited berths (2-3 test berths)
- Internal staff only (agents + ops)
- Real vessel traffic, real tariffs
- Monitor & collect feedback

**Full Rollout (End of Week 8):**
- All berths enabled
- External agent access
- Full tariff & approval chain
- Historical reporting available
