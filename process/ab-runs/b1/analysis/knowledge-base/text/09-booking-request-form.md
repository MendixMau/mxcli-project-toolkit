<!-- html-to-md: raw=13171 words=287 images=2 inline=0 sections=6 -->
**Source:** `sources/09-booking-request-form.html` — *Booking request form · Harbour Berth Booking documentation*
**Raw size:** 12.9 KB · **Words:** 287 · **Images:** 2 · **Chrome regions dropped:** 3

**Sections (6)** — the denominator: a read covers all of them, by line number:
- L20: Booking request form
- L24:   5.1 Mandatory fields
- L37:   5.2 Validation
- L43:   6.0 Introduction
- L47:   6.9 Notes
- L51:   Figure: booking form validation

---
[Home](01-home.html)Documentation

Search

Signed in as **documentation reader**

# Booking request form

Revision 7 · chapter 09 · functional description

## 5.1 Mandatory fields

Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins. Paragraphs marked as guidance are explanatory and do not add obligations. Where the text says 'the system', it means the Harbour Berth Booking application as a whole. Questions about this chapter can be raised through the usual documentation feedback channel.

- Wording aligned with the stakeholder overview.
- No open comments on this item.
- The booking form requires vessel, berth, ETA, ETD and cargo class before it can be submitted.
- See also the appendix data dictionary.

![Figure 1 (photo)](sources/09-booking-request-form_files/img-01.jpg)

Figure 1: Container terminal at dawn (stock illustration)

## 5.2 Validation

Nothing in this chapter changes the responsibilities described in the stakeholder overview. Diagrams are provided for orientation only. The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated. Paragraphs marked as guidance are explanatory and do not add obligations.

ETD must be later than ETA, and the system rejects a stay longer than 30 days. For the history of this chapter see the release notes page.

## 6.0 Introduction

The behaviour described here was demonstrated in the prototype walkthrough. Paragraphs marked as guidance are explanatory and do not add obligations.

## 6.9 Notes

The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated. This section was reviewed with the operations team during the second documentation workshop.

## Figure: booking form validation

Nothing in this chapter changes the responsibilities described in the stakeholder overview.

![Figure 2 (screenshot)](sources/09-booking-request-form_files/fig-booking-form-validation.png)

Figure 2: the booking request form in the prototype.
