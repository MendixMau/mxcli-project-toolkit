<!-- html-to-md: raw=58276 words=697 images=1 inline=0 sections=17 -->
**Source:** `sources/36-appendix-data-dictionary.html` — *Appendix: data dictionary · Harbour Berth Booking documentation*
**Raw size:** 56.9 KB · **Words:** 697 · **Images:** 1 · **Chrome regions dropped:** 3

**Sections (17)** — the denominator: a read covers all of them, by line number:
- L31: Appendix: data dictionary
- L35:   33.0 Introduction
- L39:   33.9 Notes
- L45:   Data: ApprovalDecision
- L49:     ApprovalDecision
- L59:   Data: Tariff
- L63:     Tariff
- L75:   Data: Invoice
- L79:     Invoice
- L90:   Data: Inspection
- L94:     Inspection
- L105:   Data: InspectionItem
- L109:     InspectionItem
- L119:   Data: AuditEntry
- L123:     AuditEntry
- L133:   Relationships
- L137:   Gallery

---
[Home](01-home.html)Documentation

Search

Signed in as **documentation reader**

# Appendix: data dictionary

Revision 7 · chapter 36 · functional description

## 33.0 Introduction

The wording below reflects the agreed position at the time of writing and may be refined in a later revision. Where the text says 'the system', it means the Harbour Berth Booking application as a whole. Nothing in this chapter changes the responsibilities described in the stakeholder overview.

## 33.9 Notes

The wording below reflects the agreed position at the time of writing and may be refined in a later revision. The behaviour described here was demonstrated in the prototype walkthrough. Paragraphs marked as guidance are explanatory and do not add obligations.

Nothing in this chapter changes the responsibilities described in the stakeholder overview. The examples given are illustrative and use fictional vessel names throughout.

## Data: ApprovalDecision

The review comments from the previous round have been incorporated into this revision.

### ApprovalDecision

| Attribute | Type | Required |
|---|---|---|
| `DecidedOn` | Date and time | Required |
| `Outcome` | One of: Approved, Rejected, ReturnedForInformation | Required |
| `Reason` | Text, up to 400 characters | Optional |
| `OfficerName` | Text, up to 100 characters | Required |
| `IsOverride` | Yes/No | Required |

## Data: Tariff

Where the text says 'the system', it means the Harbour Berth Booking application as a whole.

### Tariff

| Attribute | Type | Required |
|---|---|---|
| `Code` | Text, up to 10 characters | Required |
| `Description` | Text, up to 120 characters | Required |
| `RatePerMetrePerDay` | Decimal number | Required |
| `Currency` | Text, up to 3 characters | Required |
| `ValidFrom` | Date | Required |
| `ValidTo` | Date | Optional |
| `SurchargePercent` | Decimal number | Optional |

## Data: Invoice

Where the text says 'the system', it means the Harbour Berth Booking application as a whole.

### Invoice

| Attribute | Type | Required |
|---|---|---|
| `InvoiceNumber` | Text, up to 16 characters | Required |
| `IssuedOn` | Date | Required |
| `DueOn` | Date | Required |
| `TotalAmount` | Decimal number | Required |
| `VatPercent` | Decimal number | Required |
| `Status` | One of: Draft, Issued, Paid, Overdue, Void | Required |

## Data: Inspection

Paragraphs marked as guidance are explanatory and do not add obligations.

### Inspection

| Attribute | Type | Required |
|---|---|---|
| `ScheduledFor` | Date and time | Required |
| `CompletedOn` | Date and time | Optional |
| `Outcome` | One of: Pending, Passed, Failed, Deferred | Required |
| `InspectorName` | Text, up to 100 characters | Required |
| `Findings` | Text, up to 1000 characters | Optional |
| `FollowUpRequired` | Yes/No | Required |

## Data: InspectionItem

Where the text says 'the system', it means the Harbour Berth Booking application as a whole.

### InspectionItem

| Attribute | Type | Required |
|---|---|---|
| `Category` | One of: Safety, Environmental, Documentation, Security | Required |
| `Description` | Text, up to 300 characters | Required |
| `IsCompliant` | Yes/No | Required |
| `Severity` | One of: Low, Medium, High | Optional |
| `Note` | Text, up to 300 characters | Optional |

## Data: AuditEntry

Nothing in this chapter changes the responsibilities described in the stakeholder overview.

### AuditEntry

| Attribute | Type | Required |
|---|---|---|
| `OccurredOn` | Date and time | Required |
| `Actor` | Text, up to 200 characters | Required |
| `Action` | Text, up to 100 characters | Required |
| `EntityName` | Text, up to 60 characters | Required |
| `Detail` | Text, up to 1000 characters | Optional |

## Relationships

ApprovalDecision refers to BookingRequest (ApprovalDecision_BookingRequest, many-to-one). Invoice refers to BookingRequest (Invoice_BookingRequest, one-to-one). Invoice refers to Tariff (Invoice_Tariff, many-to-one). Invoice refers to ShippingAgent (Invoice_ShippingAgent, many-to-one). Inspection refers to BookingRequest (Inspection_BookingRequest, many-to-one). InspectionItem refers to Inspection (InspectionItem_Inspection, many-to-one). Tariff refers to Terminal (Tariff_Terminal, many-to-one). AuditEntry refers to BookingRequest (AuditEntry_BookingRequest, many-to-one).

## Gallery

![Figure 1 (photo)](sources/36-appendix-data-dictionary_files/img-01.jpg)

Figure 1: Container terminal at dawn (stock illustration)

Berth occupancy heatmap (prototype data)
