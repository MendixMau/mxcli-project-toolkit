# Module: HB_Finance

**Layer:** Domain + Logic
**Responsibility:** Tariffs and invoicing — rate cards, fee calculation, VAT, surcharges, and the
invoice lifecycle through to Paid/Void.

## Entities

| Entity | Persistent? | Key attributes | Notes |
|---|---|---|---|
| Tariff | Yes | Code, RatePerMetrePerDay, Currency, ValidFrom/To, SurchargePercent | Per terminal |
| Invoice | Yes | InvoiceNumber, IssuedOn, DueOn, TotalAmount, VatPercent, Status (enum) | Due = Issued+30d (ADR-006); Overdue the day after; Paid is read-only |

## Key microflows

| Microflow | Kind | Purpose |
|---|---|---|
| CAL_BerthFee_Calculate | CAL_ | length × days-alongside (round up, min 1) × rate |
| CAL_LateArrivalSurcharge_Calculate | CAL_ | 15% of berth fee if arrival > ETA+2h; officer-waivable under 80m LOA |
| CAL_LateCancellationFee_Calculate | CAL_ | 50% of berth fee if cancelled within 72h of ETA (resolves conflict C1, Ruling R3) |
| ACT_Invoice_GenerateOnComplete | ACT_ | Fires when HB_Booking's BookingRequest.Status → Completed |
| SCHED_Invoice_MarkOverdue | ACT_ (scheduled) | Issued + past DueOn + not Paid/Void → Overdue |
| ACT_Invoice_MarkPaidOrVoid | ACT_ | Harbour Master only; Paid becomes read-only |

## Pages / snippets

| Page | Type | Source screen |
|---|---|---|
| Tariffs_Overview | Overview | ch18 |
| Invoices_Overview | Overview | ch20 |

## Security

Harbour Master: tariff maintenance, mark Paid/Void, waive surcharges. Berth Officer: waive
late-arrival surcharge only (<80m). Shipping Agent: view own invoices only (F001 row-security).

## Dependencies

- **Imports (calls into):** HB_MasterData (Terminal via Tariff, ShippingAgent via Invoice),
  HB_Booking (`BookingRequest` — reads Status/ETA/ETD/dimensions to compute fees; listens for
  Status→Completed), HB_Reporting (`SUB_AuditEntry_Log`).
- **Exposes (called by):** none currently.
- **Cross-module associations:** `Invoice_BookingRequest` (one-to-one, owned by HB_Finance,
  pointing into HB_Booking — a peer feature-to-feature association, flagged and justified: an
  invoice cannot exist without the booking it bills), `Invoice_ShippingAgent` and
  `Tariff_Terminal` (owned by HB_Finance, pointing down into HB_MasterData — correct direction).
