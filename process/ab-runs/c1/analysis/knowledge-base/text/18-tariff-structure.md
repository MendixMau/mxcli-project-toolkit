<!-- html-to-md: raw=51165 words=540 images=1 inline=0 sections=8 -->
**Source:** `sources/18-tariff-structure.html` — *Tariff structure · Harbour Berth Booking documentation*
**Raw size:** 50.0 KB · **Words:** 540 · **Images:** 1 · **Chrome regions dropped:** 3

**Sections (8)** — the denominator: a read covers all of them, by line number:
- L22: Tariff structure
- L26:   14.1 Rate cards
- L34:   14.2 Fee calculation
- L45:   14.3 VAT
- L53:   14.4 Shore power
- L57:   15.0 Introduction
- L63:   15.9 Notes
- L67:   Gallery

---
[Home](01-home.html)Documentation

Search

Signed in as **documentation reader**

# Tariff structure

Revision 7 · chapter 18 · functional description

## 14.1 Rate cards

This chapter does not describe the technical implementation; see the architecture notes for that. This section was reviewed with the operations team during the second documentation workshop. Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout. Nothing in this chapter changes the responsibilities described in the stakeholder overview.

For the history of this chapter see the release notes page. Tariffs are defined per terminal with a rate per metre of vessel length per day, a currency and a validity period.

Questions about this chapter can be raised through the usual documentation feedback channel. The review comments from the previous round have been incorporated into this revision.

## 14.2 Fee calculation

The behaviour described here was demonstrated in the prototype walkthrough. The numbering of headings follows the master table of contents and is stable across revisions. Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins.

| Aspect | Statement |
|---|---|
| Requirement | The berth fee is vessel length times days alongside times the tariff rate, with days alongside rounded up to whole days and a minimum of one day. |
| Status | Agreed |
| Last reviewed | Revision 7 |
| Owner | Documentation team, port operations |

## 14.3 VAT

Diagrams are provided for orientation only. Where the text says 'the system', it means the Harbour Berth Booking application as a whole.

VAT of 21% is added to all berth fees. Nothing in this chapter changes the responsibilities described in the stakeholder overview.

For the history of this chapter see the release notes page. The wording below reflects the agreed position at the time of writing and may be refined in a later revision.

## 14.4 Shore power

Nothing in this chapter changes the responsibilities described in the stakeholder overview. The behaviour described here was demonstrated in the prototype walkthrough. Readers new to port operations should first consult the glossary for the terms used here. Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout.

## 15.0 Introduction

Where the text says 'the system', it means the Harbour Berth Booking application as a whole. Questions about this chapter can be raised through the usual documentation feedback channel. Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins.

The behaviour described here was demonstrated in the prototype walkthrough. Nothing in this chapter changes the responsibilities described in the stakeholder overview.

## 15.9 Notes

Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins. Figures on this page are numbered per page, not per document. Readers new to port operations should first consult the glossary for the terms used here. The numbering of headings follows the master table of contents and is stable across revisions.

## Gallery

![Figure 1 (photo)](sources/18-tariff-structure_files/img-01.jpg)

Figure 1: Container terminal at dawn (stock illustration)

Berth occupancy heatmap (prototype data)

Shore power is billed at a flat 250 per day when the berth offers it and the agent requested it.
