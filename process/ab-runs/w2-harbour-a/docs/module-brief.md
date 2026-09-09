# Module Brief: VesselRegistry

**Module Name:** VesselRegistry  
**Owner:** Developer (TBD)  
**Build Sequence:** Phase 1.1 (Week 1, MVP)  
**Effort:** 5 days  
**Deliverable:** Vessel and VesselType master data with CRUD, AIS feed stub

---

## Module Scope

### Entities
1. **Vessel** - Master data for each vessel (IMO-keyed, 12 attributes including dimensions, type, flag state)
2. **VesselType** - Reference data for vessel categories (Tanker, Container, General, etc.)

### Screens (Mendix Pages)
1. Vessel Search (IMO lookup, filter by type)
2. Vessel Detail (view/edit master data, AIS status)
3. VesselType Lookup (reference-data-only read)
4. VesselType Admin (create/edit types) — optional for MVP, defer to Slice 2

### Microflows
1. CreateVessel (validation: IMO uniqueness)
2. UpdateVessel (from AIS feed or manual edit)
3. SearchVesselByIMO (lookup service, used by booking form)
4. AISFeedPolling (stub: returns mock vessel data for next 5 vessels)
5. SyncAISUpdate (on feed arrival: upsert vessel, update LastAISUpdate)

### Data Model
```
Entity Vessel {
  VesselID: Integer (primary key, autonumber)
  IMONumber: String[7] (unique, mandatory)
  Name: String[255] (mandatory)
  VesselTypeID: Integer (FK to VesselType)
  Length, Beam, Draft: Decimal
  Capacity: String[50]
  FlagState: String[2] (ISO country code)
  OwnerAgent: String[255]
  AISFeedActive: Boolean (default true)
  LastAISUpdate: DateTime
}

Entity VesselType {
  VesselTypeID: Integer (primary key)
  Code: String[10] (unique)
  Name: String[100]
  TariffCategory: String[50]
  Description: String[255]
}
```

---

## Constraints & Assumptions

- IMO is globally unique; no duplicates allowed
- AIS feed provides Name, Position, ETA, Draft (stub returns mock)
- Vessel lookup by IMO happens during booking request (dependency: booking form calls SearchVesselByIMO)
- No delete allowed if vessel has active bookings (enforce in handler)

---

## Build Dependencies

- **Upstream:** None (foundation module)
- **Downstream:** BerthAllocation (reads VesselType for allocation rules), BookingLifecycle (reads Vessel for booking request)

---

## Testing Checklist

- [ ] Create Vessel with valid IMO: succeeds, generates VesselID
- [ ] Create Vessel with duplicate IMO: rejected with error
- [ ] Search by IMO: returns correct vessel
- [ ] AIS stub polling: returns 5 mock vessels
- [ ] AIS sync upsert: creates new vessel if IMO new, updates if exists
- [ ] Vessel detail screen: displays all attributes, edit form works
- [ ] Delete vessel with bookings: rejected with referential integrity error
- [ ] Type lookup: reads all reference types

---

## Acceptance Criteria (Definition of Done)

- All entities created with correct attributes and constraints
- All screens render correctly, form inputs work
- All microflows execute without errors
- All test cases pass
- Zero UNVERIFIED execs (mxbuild gates clean)
- Module exports, imports into Stage 2 integration point

