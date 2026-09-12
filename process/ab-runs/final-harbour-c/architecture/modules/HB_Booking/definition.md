# Module: HB_Booking

**Layer:** Domain + Logic
**Responsibility:** The booking request lifecycle end to end — creation through submission,
officer review and approval/rejection, cancellation, and the AIS arrival flag. Owns the two
entities that are always used together (`BookingRequest`, `ApprovalDecision`), which is why
they are one module and not two (`modularize-domain.md`'s over-split anti-pattern — see
`architecture/blueprint.md` §"Rejected alternatives").

## Entities

| Entity | Persistent? | Key attributes | Notes |
|---|---|---|---|
| BookingRequest | Yes | Reference (String 13, unique, permanent), Status (enum, 7 values), ETA/ETD, CargoClass (enum) | Reference format `HB-YYYY-NNNNN`, assigned on submit, never reused (ADR-004) |
| ApprovalDecision | Yes | DecidedOn, Outcome (enum: Approved/Rejected/ReturnedForInformation), Reason (optional), IsOverride | Reason is conditionally required when Outcome=Rejected — a microflow validation, not an attribute-level requirement (F004-Q2, conflict C4) |

## Key microflows

| Microflow | Kind | Purpose |
|---|---|---|
| ACT_BookingRequest_Submit | ACT_ | Validates timing rules, assigns Reference, fast-track check |
| ACT_BookingRequest_OpenForReview | ACT_ | Submitted → UnderReview, records officer |
| ACT_ApprovalDecision_Decide | ACT_ | Records outcome; Reason-required-on-Reject; Harbour-Master-only override |
| ACT_BookingRequest_Cancel | ACT_ | Approved → Cancelled; late-cancellation fee call into HB_Finance |
| SCHED_AIS_PollPositions | ACT_ (scheduled) | Polls AIS feed every 5 min, flags Arrived on geofence entry (stub — no contract documented) |
| SUB_BookingRequest_AssignReference | SUB_ | Generates next `HB-YYYY-NNNNN`, checked for permanence |

## Pages / snippets

| Page | Type | Source screen |
|---|---|---|
| BookingBoard_Overview | Overview | ch28/29 (5-item nav — Ruling R4) |
| MyBookings_Overview | Overview | ch30 |
| BookingRequest_NewEdit | NewEdit | ch09 |
| OfficerReview_Decide | View | ch15/16/21 |

## Security

Shipping Agent: create/edit own Draft & Submitted, view own. Berth Officer: view/open-for-review
queue, decide. Harbour Master: everything a Berth Officer can, plus override.

## Dependencies

- **Imports (calls into):** HB_MasterData (Vessel, ShippingAgent, Berth), HB_Reporting
  (`SUB_AuditEntry_Log` on every status change).
- **Exposes (called by):** HB_Finance (`Invoice_BookingRequest`), HB_Inspection
  (`Inspection_BookingRequest`).
- **Cross-module associations:** `BookingRequest_Vessel`, `BookingRequest_ShippingAgent`,
  `BookingRequest_Berth` — all owned by HB_Booking, pointing down into HB_MasterData (correct
  direction). `Invoice_BookingRequest` and `Inspection_BookingRequest` are owned by HB_Finance
  and HB_Inspection respectively (peer feature-to-feature associations, not Common).
