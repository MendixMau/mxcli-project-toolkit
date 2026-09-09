<!-- html-to-md: raw=13305 words=313 images=1 inline=0 sections=8 -->
**Source:** `sources/26-audit-and-compliance.html` — *Audit and compliance · Harbour Berth Booking documentation*
**Raw size:** 13.0 KB · **Words:** 313 · **Images:** 1 · **Chrome regions dropped:** 3

**Sections (8)** — the denominator: a read covers all of them, by line number:
- L22: Audit and compliance
- L26:   22.1 Audit trail
- L34:   23.0 Introduction
- L38:   23.9 Notes
- L42:   Data: AuditEntry
- L46:     AuditEntry
- L56:   Relationships
- L60:   Gallery

---
[Home](01-home.html)Documentation

Search

Signed in as **documentation reader**

# Audit and compliance

Revision 7 · chapter 26 · functional description

## 22.1 Audit trail

Nothing in this chapter changes the responsibilities described in the stakeholder overview. Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout. The behaviour described here was demonstrated in the prototype walkthrough.

Every status change on a booking, decision, invoice or inspection is written to an audit trail with actor, timestamp and action.

The review comments from the previous round have been incorporated into this revision. The behaviour described here was demonstrated in the prototype walkthrough.

## 23.0 Introduction

Diagrams are provided for orientation only. Questions about this chapter can be raised through the usual documentation feedback channel. The wording below reflects the agreed position at the time of writing and may be refined in a later revision.

## 23.9 Notes

This section was reviewed with the operations team during the second documentation workshop. Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout. The numbering of headings follows the master table of contents and is stable across revisions. The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated.

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

AuditEntry refers to BookingRequest (AuditEntry_BookingRequest, many-to-one).

## Gallery

![Figure 1 (photo)](sources/26-audit-and-compliance_files/img-01.jpg)

Figure 1: Container terminal at dawn (stock illustration)
