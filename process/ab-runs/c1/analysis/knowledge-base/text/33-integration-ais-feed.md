<!-- html-to-md: raw=44771 words=237 images=1 inline=0 sections=5 -->
**Source:** `sources/33-integration-ais-feed.html` — *Integration: AIS feed · Harbour Berth Booking documentation*
**Raw size:** 43.7 KB · **Words:** 237 · **Images:** 1 · **Chrome regions dropped:** 3

**Sections (5)** — the denominator: a read covers all of them, by line number:
- L19: Integration: AIS feed
- L23:   28.2 AIS position feed
- L27:   30.0 Introduction
- L31:   30.9 Notes
- L37:   Gallery

---
[Home](01-home.html)Documentation

Search

Signed in as **documentation reader**

# Integration: AIS feed

Revision 7 · chapter 33 · functional description

## 28.2 AIS position feed

Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins. The wording below reflects the agreed position at the time of writing and may be refined in a later revision.

## 30.0 Introduction

This chapter does not describe the technical implementation; see the architecture notes for that. Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins. Paragraphs marked as guidance are explanatory and do not add obligations. For the history of this chapter see the release notes page.

## 30.9 Notes

The numbering of headings follows the master table of contents and is stable across revisions. The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated. Diagrams are provided for orientation only. The wording below reflects the agreed position at the time of writing and may be refined in a later revision.

The behaviour described here was demonstrated in the prototype walkthrough. Figures on this page are numbered per page, not per document.

## Gallery

![Figure 1 (photo)](sources/33-integration-ais-feed_files/img-01.jpg)

Figure 1: Container terminal at dawn (stock illustration)

Berth occupancy heatmap (prototype data)

The system imports vessel positions from the AIS feed every 5 minutes and flags a booking as Arrived when the vessel enters the port geofence.
