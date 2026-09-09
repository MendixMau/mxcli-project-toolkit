<!-- html-to-md: raw=15481 words=497 images=1 inline=0 sections=10 -->
**Source:** `sources/12-berth-master-data.html` — *Berth master data · Harbour Berth Booking documentation*
**Raw size:** 15.1 KB · **Words:** 497 · **Images:** 1 · **Chrome regions dropped:** 3

**Sections (10)** — the denominator: a read covers all of them, by line number:
- L24: Berth master data
- L28:   8.1 Berth attributes
- L42:   9.0 Introduction
- L48:   9.9 Notes
- L54:   Data: Berth
- L58:     Berth
- L70:   Data: Terminal
- L74:     Terminal
- L84:   Relationships
- L88:   Gallery

---
[Home](01-home.html)Documentation

Search

Signed in as **documentation reader**

# Berth master data

Revision 7 · chapter 12 · functional description

## 8.1 Berth attributes

The examples given are illustrative and use fictional vessel names throughout. This chapter does not describe the technical implementation; see the architecture notes for that. The numbering of headings follows the master table of contents and is stable across revisions. Diagrams are provided for orientation only.

| Aspect | Statement |
|---|---|
| Related chapter | See the navigation sidebar |
| Guidance | Explanatory text, no obligations added |
| Status | Agreed |
| Illustration | Figure on this page |
| Requirement | Each berth records a code, a name, a maximum vessel length, a maximum draught, shore power availability and a status of Available, Closed or Maintenance. |

Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout. The behaviour described here was demonstrated in the prototype walkthrough.

## 9.0 Introduction

For the history of this chapter see the release notes page. This chapter does not describe the technical implementation; see the architecture notes for that. Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout. The behaviour described here was demonstrated in the prototype walkthrough.

The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated. Questions about this chapter can be raised through the usual documentation feedback channel.

## 9.9 Notes

This section was reviewed with the operations team during the second documentation workshop. Diagrams are provided for orientation only.

Figures on this page are numbered per page, not per document. The examples given are illustrative and use fictional vessel names throughout.

## Data: Berth

Questions about this chapter can be raised through the usual documentation feedback channel.

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

## Data: Terminal

Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins.

### Terminal

| Attribute | Type | Required |
|---|---|---|
| `Code` | Text, up to 6 characters | Required |
| `Name` | Text, up to 80 characters | Required |
| `OperatingHoursStart` | Text, up to 5 characters | Optional |
| `OperatingHoursEnd` | Text, up to 5 characters | Optional |
| `HasCustomsOffice` | Yes/No | Required |

## Relationships

BookingRequest refers to Berth (BookingRequest_Berth, many-to-one). Berth refers to Terminal (Berth_Terminal, many-to-one). Tariff refers to Terminal (Tariff_Terminal, many-to-one).

## Gallery

![Figure 1 (photo)](sources/12-berth-master-data_files/img-01.jpg)

Figure 1: Container terminal at dawn (stock illustration)
