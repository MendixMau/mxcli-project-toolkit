<!-- html-to-md: raw=15304 words=461 images=1 inline=0 sections=9 -->
**Source:** `sources/14-vessel-registry.html` — *Vessel registry · Harbour Berth Booking documentation*
**Raw size:** 14.9 KB · **Words:** 461 · **Images:** 1 · **Chrome regions dropped:** 3

**Sections (9)** — the denominator: a read covers all of them, by line number:
- L23: Vessel registry
- L27:   10.1 Vessel record
- L33:   10.2 Vessel types
- L43:   11.0 Introduction
- L49:   11.9 Notes
- L53:   Data: Vessel
- L57:     Vessel
- L70:   Relationships
- L74:   Gallery

---
[Home](01-home.html)Documentation

Search

Signed in as **documentation reader**

# Vessel registry

Revision 7 · chapter 14 · functional description

## 10.1 Vessel record

Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins. Paragraphs marked as guidance are explanatory and do not add obligations.

This section was reviewed with the operations team during the second documentation workshop. Where the text says 'the system', it means the Harbour Berth Booking application as a whole. A vessel is identified by its IMO number, which is unique across the vessel registry.

## 10.2 Vessel types

The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated. Where the text says 'the system', it means the Harbour Berth Booking application as a whole. Diagrams are provided for orientation only.

- Vessel type is one of Container, Bulk, Tanker, RoRo, Cruise or General Cargo.
- Cross-referenced from the glossary.
- Illustrated in the prototype.

Nothing in this chapter changes the responsibilities described in the stakeholder overview. The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated.

## 11.0 Introduction

Where the text says 'the system', it means the Harbour Berth Booking application as a whole. The review comments from the previous round have been incorporated into this revision. Readers new to port operations should first consult the glossary for the terms used here. Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins.

The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated. The examples given are illustrative and use fictional vessel names throughout.

## 11.9 Notes

Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout. This chapter does not describe the technical implementation; see the architecture notes for that. Diagrams are provided for orientation only. The numbering of headings follows the master table of contents and is stable across revisions.

## Data: Vessel

Paragraphs marked as guidance are explanatory and do not add obligations.

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

## Relationships

BookingRequest refers to Vessel (BookingRequest_Vessel, many-to-one). Vessel refers to ShippingAgent (Vessel_ShippingAgent, many-to-many).

## Gallery

![Figure 1 (photo)](sources/14-vessel-registry_files/img-01.jpg)

Figure 1: Container terminal at dawn (stock illustration)
