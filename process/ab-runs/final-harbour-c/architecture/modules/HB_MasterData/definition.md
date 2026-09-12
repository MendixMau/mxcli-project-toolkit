# Module: HB_MasterData

**Layer:** Common
**Responsibility:** Reference/master data for the whole app — vessels, shipping agents, terminals
and berths. Owned by nobody else; every other module reads it, none of it reads back.

## Entities

| Entity | Persistent? | Key attributes | Notes |
|---|---|---|---|
| Vessel | Yes | IMONumber (String 7, unique, required), Name, LengthOverall, Draught, VesselType (enum) | IMONumber has an additional exactly-7-digit microflow validation beyond the length-7 attribute (F002-Q1, conflict C3) |
| ShippingAgent | Yes | CompanyName, LicenceNumber, ContactEmail, IsSuspended, CreditLimit | Auto-suspend at 3 overdue invoices; reactivation is Harbour-Master-only (F002 UC002-4/5) |
| Terminal | Yes | Code, Name, OperatingHoursStart/End, HasCustomsOffice | |
| Berth | Yes | Code, Name, MaxLength, MaxDraught, HasShorePower, Status (enum) | |

## Key microflows

| Microflow | Kind | Purpose |
|---|---|---|
| ACT_ShippingAgent_Register | ACT_ | Creates a ShippingAgent, IsSuspended = false |
| ACT_ShippingAgent_Activate | ACT_ | Berth Officer activates a registered agent |
| ACT_ShippingAgent_Suspend | ACT_ | System-triggered: 3+ Overdue invoices → IsSuspended = true |
| ACT_ShippingAgent_Reactivate | ACT_ | Harbour Master only |
| VAL_BerthAllocation_FitCheck | VAL_ | Vessel length ≤ Berth.MaxLength, Vessel draught ≤ Berth.MaxDraught − 0.5m |

## Pages / snippets

| Page | Type | Source screen |
|---|---|---|
| VesselRegistry_Overview | Overview | ch14 |
| ShippingAgent_Overview | Overview | ch11 |
| BerthMasterData_Overview | Overview | ch12 |

## Security

No dedicated module role — every one of the four app roles (Shipping Agent, Berth Officer,
Harbour Master, Inspector) reads this module; write access to Berth/Terminal is Harbour
Master only, ShippingAgent activation/reactivation per F002's role rules.

## Dependencies

- **Imports (calls into):** none — this is the bottom of the dependency graph.
- **Exposes (called by):** HB_Booking (Vessel, ShippingAgent, Berth), HB_Finance (Terminal,
  ShippingAgent), HB_Inspection (indirectly, via HB_Booking's BookingRequest).
- **Cross-module associations:** none owned here — every association FROM a feature module TO
  this module is owned by the feature module (BookingRequest_Vessel, BookingRequest_Berth,
  BookingRequest_ShippingAgent, Tariff_Terminal, Invoice_ShippingAgent). HB_MasterData owns no
  outbound association to a feature module — that is the point of it being Common.
