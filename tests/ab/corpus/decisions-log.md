# Decisions log

Architecture-decision-record style. One entry per decision, newest last.

## ADR-001 — Documentation lives in the portal

**Status:** accepted

**Decision:** All functional documentation is published through the documentation portal and exported for offline review.

**Consequences:** Where the text says 'the system', it means the Harbour Berth Booking application as a whole.

## ADR-002 — Chapters are numbered once

**Status:** accepted

**Decision:** Heading numbers are allocated by the master table of contents and never re-used.

**Consequences:** The numbering of headings follows the master table of contents and is stable across revisions.

## ADR-003 — Fictional example data

**Status:** accepted

**Decision:** All examples use invented vessel names, agents and people.

**Consequences:** This section was reviewed with the operations team during the second documentation workshop.

## ADR-004 — Booking references are permanent

**Status:** accepted

**Decision:** Booking references are never reused, even after a request is cancelled or deleted. A cancelled request keeps its reference for the audit trail.

**Consequences:** The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated.

## ADR-005 — Screenshots come from the prototype

**Status:** accepted

**Decision:** Figures are exported from the clickable prototype, not drawn by hand.

**Consequences:** The numbering of headings follows the master table of contents and is stable across revisions.

## ADR-006 — Invoice due dates

**Status:** accepted

**Decision:** Invoices are due 30 days after the issue date and become Overdue on the day after the due date. This was agreed with the finance team in the third workshop.

**Consequences:** For the history of this chapter see the release notes page.

## ADR-007 — Workshop notes are kept verbatim

**Status:** accepted

**Decision:** Workshop notes are stored as written during the session; clean-up happens in the chapters.

**Consequences:** This chapter does not describe the technical implementation; see the architecture notes for that.

## ADR-008 — Release notes per revision

**Status:** accepted

**Decision:** Every published revision gets a release notes entry.

**Consequences:** Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout.

