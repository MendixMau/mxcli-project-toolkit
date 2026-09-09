<!-- html-to-md: raw=18521 words=735 images=1 inline=0 sections=14 -->
**Source:** `sources/07-domain-overview.html` — *Domain overview · Harbour Berth Booking documentation*
**Raw size:** 18.1 KB · **Words:** 735 · **Images:** 1 · **Chrome regions dropped:** 3

**Sections (14)** — the denominator: a read covers all of them, by line number:
- L28: Domain overview
- L32:   3.1 Core concepts
- L40:   4.0 Introduction
- L44:   4.9 Notes
- L50:   Data: Vessel
- L54:     Vessel
- L67:   Data: ShippingAgent
- L71:     ShippingAgent
- L82:   Data: Berth
- L86:     Berth
- L98:   Data: BookingRequest
- L102:     BookingRequest
- L115:   Relationships
- L119:   Gallery

---
[Home](01-home.html)Documentation

Search

Signed in as **documentation reader**

# Domain overview

Revision 7 · chapter 07 · functional description

## 3.1 Core concepts

Figures on this page are numbered per page, not per document. Where the text says 'the system', it means the Harbour Berth Booking application as a whole. Questions about this chapter can be raised through the usual documentation feedback channel. The behaviour described here was demonstrated in the prototype walkthrough.

Readers new to port operations should first consult the glossary for the terms used here. Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins. A booking request always refers to exactly one vessel, one shipping agent and one berth. Diagrams are provided for orientation only.

Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins. This chapter does not describe the technical implementation; see the architecture notes for that.

## 4.0 Introduction

For the history of this chapter see the release notes page. The review comments from the previous round have been incorporated into this revision. The wording below reflects the agreed position at the time of writing and may be refined in a later revision.

## 4.9 Notes

Nothing in this chapter changes the responsibilities described in the stakeholder overview. The wording below reflects the agreed position at the time of writing and may be refined in a later revision.

Paragraphs marked as guidance are explanatory and do not add obligations. Nothing in this chapter changes the responsibilities described in the stakeholder overview.

## Data: Vessel

This chapter does not describe the technical implementation; see the architecture notes for that.

### Vessel

| Attribute | Type | Required |
|---|---|---|
| `IMONumber` | Text, up to 7 characters | Required |
| `Name` | Text, up to 100 characters | Required |
| `LengthOverall` | Decimal number | Required |
| `Beam` | Decimal number | Optional |
| `Draught` | Decimal number | Required |
| `FlagState` | Text, up to 2 characters | Optional |
| `VesselType` | One of: Container, Bulk, Tanker, RoRo, Cruise, GeneralCargo | Required |
| `GrossTonnage` | Whole number | Optional |

## Data: ShippingAgent

The wording below reflects the agreed position at the time of writing and may be refined in a later revision.

### ShippingAgent

| Attribute | Type | Required |
|---|---|---|
| `CompanyName` | Text, up to 120 characters | Required |
| `LicenceNumber` | Text, up to 20 characters | Required |
| `ContactEmail` | Text, up to 200 characters | Required |
| `Phone` | Text, up to 30 characters | Optional |
| `IsSuspended` | Yes/No | Required |
| `CreditLimit` | Decimal number | Optional |

## Data: Berth

Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout.

### Berth

| Attribute | Type | Required |
|---|---|---|
| `Code` | Text, up to 10 characters | Required |
| `Name` | Text, up to 80 characters | Required |
| `MaxLength` | Decimal number | Required |
| `MaxDraught` | Decimal number | Required |
| `HasShorePower` | Yes/No | Required |
| `Status` | One of: Available, Closed, Maintenance | Required |
| `Notes` | Text, up to 500 characters | Optional |

## Data: BookingRequest

Paragraphs marked as guidance are explanatory and do not add obligations.

### BookingRequest

| Attribute | Type | Required |
|---|---|---|
| `Reference` | Text, up to 13 characters | Required |
| `ETA` | Date and time | Required |
| `ETD` | Date and time | Required |
| `Status` | One of: Draft, Submitted, UnderReview, Approved, Rejected, Cancelled, Completed | Required |
| `CargoClass` | One of: General, Perishable, DangerousGoods, Empty | Required |
| `ShorePowerRequested` | Yes/No | Required |
| `SubmittedOn` | Date and time | Optional |
| `Remarks` | Text, up to 500 characters | Optional |

## Relationships

BookingRequest refers to Vessel (BookingRequest_Vessel, many-to-one). BookingRequest refers to ShippingAgent (BookingRequest_ShippingAgent, many-to-one). BookingRequest refers to Berth (BookingRequest_Berth, many-to-one). ApprovalDecision refers to BookingRequest (ApprovalDecision_BookingRequest, many-to-one). Invoice refers to BookingRequest (Invoice_BookingRequest, one-to-one). Invoice refers to ShippingAgent (Invoice_ShippingAgent, many-to-one). Inspection refers to BookingRequest (Inspection_BookingRequest, many-to-one). Berth refers to Terminal (Berth_Terminal, many-to-one). AuditEntry refers to BookingRequest (AuditEntry_BookingRequest, many-to-one). Vessel refers to ShippingAgent (Vessel_ShippingAgent, many-to-many).

## Gallery

![Figure 1 (photo)](sources/07-domain-overview_files/img-01.jpg)

Figure 1: Container terminal at dawn (stock illustration)
