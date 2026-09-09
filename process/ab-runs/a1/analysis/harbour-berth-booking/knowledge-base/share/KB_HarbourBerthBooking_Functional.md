# Harbour Berth Booking — Functional Knowledge Base

**Source:** `sources/` — 36-chapter documentation-portal export (revision 7), plus
`glossary.md`, `roles.md`, `decisions-log.md`, `workshop-notes.md`.
**Category:** A (requirements-driven — no legacy code; Path B, this file)
**Processed:** 2026-09-09, unattended run
**Method:** full read of all 36 chapters (noise-stripped text dump), `glossary.md`,
`roles.md`, `decisions-log.md`, `workshop-notes.md`; visual read of the two unique
prototype images; entity/attribute tables cross-extracted by `analysis/extract-entities.py`
(see `entities.json` in this folder) and verified against `glossary.md`.

---

## 0. Source Chapter Mapping

Every citation below (e.g. "ch08 §4.1") refers to the corresponding source file:

| ch | file | ch | file |
|---|---|---|---|
| 01 | `01-home.html` | 19 | `19-tariffs-cancellation-fees.html` |
| 02 | `02-about-the-port-authority.html` | 20 | `20-invoicing.html` |
| 03 | `03-release-notes.html` | 21 | `21-officer-review-screen.html` |
| 04 | `04-vision-and-scope.html` | 22 | `22-inspection-scheduling.html` |
| 05 | `05-stakeholders-and-roles.html` | 23 | `23-inspection-checklist.html` |
| 06 | `06-news-and-events.html` | 24 | `24-inspection-outcomes.html` |
| 07 | `07-domain-overview.html` | 25 | `25-departure-clearance.html` |
| 08 | `08-booking-lifecycle.html` | 26 | `26-audit-and-compliance.html` |
| 09 | `09-booking-request-form.html` | 27 | `27-privacy-and-cookies.html` |
| 10 | `10-cancellation-and-changes.html` | 28 | `28-navigation-and-screens.html` |
| 11 | `11-agent-onboarding.html` | 29 | `29-booking-board-screen.html` |
| 12 | `12-berth-master-data.html` | 30 | `30-my-bookings-screen.html` |
| 13 | `13-berth-allocation-rules.html` | 31 | `31-inspection-calendar-screen.html` |
| 14 | `14-vessel-registry.html` | 32 | `32-reporting.html` |
| 15 | `15-officer-review-process.html` | 33 | `33-integration-ais-feed.html` |
| 16 | `16-approval-decisions.html` | 34 | `34-contact-and-support.html` |
| 17 | `17-notifications.html` | 35 | `35-security-and-access.html` |
| 18 | `18-tariff-structure.html` | 36 | `36-appendix-data-dictionary.html` |

Plus `glossary.md`, `roles.md`, `decisions-log.md`, `workshop-notes.md`, and
`09-booking-request-form_files/fig-booking-form-validation.png` (the image-only IMO rule).

---

## 1. Document Structure

36 numbered chapters exported as "Webpage, complete" from a documentation portal, each
carrying the same navigation sidebar, footer and revision banner (repeated boilerplate,
stripped for this KB). Four supporting markdown files: `glossary.md` (11 domain terms),
`roles.md` (4 roles), `decisions-log.md` (8 ADRs), `workshop-notes.md` (3 raw session
logs). Two chapters carry unique prototype screenshots beyond the one repeated decorative
stock photo: ch09 (booking form, including a validation-error state) and ch21 (review
screen decision panel + a decorative quay illustration).

---

## 2. Business Overview

**What it is:** "Harbour Berth Booking" — a fictional Port Authority's application
letting licensed shipping agents request berths online for vessels they represent (ch04).
Berth officers review every request and record an approval decision with a reason; there
is no automatic approval path except one named fast-track exception (ch15 §11.4, ch08
§4.4). The application also covers inspections, departure clearance, tariffs/invoicing,
notifications, an AIS position feed, audit trail, and three operational screens.

**Out of scope (source's own words, ch04 §1.3):** "Pilotage and tug scheduling are out
of scope and remain in the existing marine operations system."

**Replaces:** a spreadsheet-based booking process (ch01/34/35 footer text) — no further
detail on that spreadsheet appears anywhere in the corpus.

**Users/roles:** four fixed roles, one per user (`roles.md`): Shipping Agent, Berth
Officer, Harbour Master, Inspector.

---

## 3. Screens

Three named navigation screens (ch28 §23.1) plus two prototype-only screens shown in
figures.

### Booking Board (ch29)
**Purpose:** officers' work queue. Lists Submitted and Under Review requests ordered by
ETA (ch15 §11.1). Filterable by terminal, status and ETA date range (ch29 §24.1).

### My Bookings (ch30)
**Purpose:** an agent's own view. Shows the agent's own requests only, Draft requests
listed first (ch30 §25.1).

### Inspection Calendar (ch31)
**Purpose:** inspector's schedule view. Shows inspections per day and per inspector;
supports drag-and-drop rescheduling (ch31 §26.1).

### Officer review screen (ch21, prototype screenshot)
**Purpose:** the decision panel an officer uses when reviewing a request. Shows the
vessel's dimensions next to the berth's limits and highlights any exceedance in red
(ch21 §17.1). Workshop session 3 (`workshop-notes.md`) additionally requires it to show
the last five bookings of the same vessel — **not yet reflected in any numbered
chapter**, logged as an open question below.

### Booking request form (ch09, prototype screenshot — see image-only rule)
**Purpose:** the form an agent fills in to submit a request.

| Field | Mandatory | Rules |
|---|---|---|
| Vessel | Yes | must exist in the vessel registry |
| Berth | Yes | subject to the allocation fit-check (ch13) |
| ETA | Yes | booking cannot be submitted more than 90 days before, or less than 48 hours before, ETA (ch08 §4.5) |
| ETD | Yes | must be later than ETA; stay must not exceed 30 days (ch09 §5.2) |
| Cargo class | Yes | one of General, Perishable, DangerousGoods, Empty |
| IMO number (on Vessel) | Yes | **exactly 7 digits — visible only in `fig-booking-form-validation.png`, stated nowhere in the text chapters.** The glossary/data dictionary only say "Text, up to 7 characters", which is weaker than the image's rule. |

---

## 4. Business Rules

1. **Draft privacy:** an agent can save a request as Draft and complete it later; drafts
   are invisible to officers (ch08 §4.1).
2. **Reference format:** on submission the system assigns a unique reference in the
   format `HB-YYYY-NNNNN` (ch08 §4.2). References are never reused, even after
   cancellation or deletion (`decisions-log.md` ADR-004).
3. **Status model:** Draft -> Submitted -> Under Review -> Approved | Rejected |
   Cancelled -> Completed (ch08 §4.3).
4. **Fast-track auto-approval:** a request is automatically approved when the requested
   berth is free for the whole stay AND the vessel is shorter than 120 metres (ch08 §4.4).
5. **Submission timing:** cannot submit more than 90 days before ETA; must submit at
   least 48 hours before ETA (ch08 §4.5).
6. **Booking-form validation:** ETD must be later than ETA; stay longer than 30 days is
   rejected (ch09 §5.2). IMO number must be exactly 7 digits (image-only, see Screens).
7. **Edit lock:** an agent may edit a Submitted request until an officer opens it for
   review, after which it is locked (ch10 §6.1).
8. **Cancellation:** free of charge until 24 hours before ETA; an Approved booking may be
   cancelled by the agent; a Completed booking cannot be (ch10 §6.2). Cancellation within
   72 hours of ETA is charged 50% of the berth fee (ch19 §15.2).
9. **Agent suspension:** an agent with 3+ overdue invoices is automatically suspended; no
   self-service reactivation — only the Harbour Master reactivates (ch11 §7.2). A
   suspended agent cannot submit new requests; already-Approved bookings remain valid.
10. **Berth allocation fit-check:** a berth can be assigned only if the vessel's length
    does not exceed the berth's maximum length AND the vessel's draught is at least 0.5m
    below the berth's maximum draught (ch13 §9.1).
11. **Surcharge waiver authority:** only the Harbour Master may waive a tariff surcharge
    (ch13 §9.3).
12. **Manual review only:** no automatic approval except rule 4; every request is
    reviewed by a berth officer before it can become Approved (ch15 §11.4).
13. **Review outcomes:** Approved, Rejected, or Returned for Information (ch16 §12.1). A
    Returned-for-Information request goes back to the agent, who may amend and resubmit
    it **once** (ch16 §12.2).
14. **Override authority:** only the Harbour Master may override a Rejected decision, and
    the override is recorded with a reason (ch16 §12.3).
15. **Agent notification:** the agent receives an e-mail whenever their request's status
    changes (ch17 §13.1).
16. **Officer digest:** officers receive a daily digest at 06:00 listing requests with an
    ETA within the next 48 hours (ch17 §13.2).
17. **Fee formula:** berth fee = vessel length x days-alongside x tariff rate; days
    alongside rounds up to whole days, minimum one day (ch18 §14.2).
18. **VAT:** 21% is added to all berth fees (ch18 §14.3).
19. **Shore power fee:** billed at a flat 250 per day when the berth offers shore power
    and the agent requested it (ch18 §14.4).
20. **Late-arrival surcharge:** a vessel arriving more than 2 hours after ETA incurs a
    15% surcharge on the berth fee (ch19 §15.1). A berth officer may waive this surcharge
    for vessels shorter than 80 metres (ch24 §20.3).
21. **Invoice creation:** generated automatically when a booking is marked Completed
    (ch20 §16.1).
22. **Invoice immutability:** a Harbour Master can mark an invoice Paid or Void; a Paid
    invoice cannot be edited (ch20 §16.3). Due 30 days after issue; Overdue the day after
    the due date (`decisions-log.md` ADR-006).
23. **Dangerous-goods gate:** a booking with cargo class Dangerous Goods cannot be
    Approved until an inspection has been scheduled (ch22 §18.2).
24. **Inspection checklist categories:** Safety, Environmental, Documentation, Security
    (ch23 §19.1). Each item records compliant/not-compliant, a severity of Low/Medium/
    High, and an optional note (ch23 §19.2).
25. **Inspection outcome:** Failed if the checklist contains any non-compliant item of
    High severity (ch23 §19.3).
26. **Departure blocked by failed inspection:** a Failed inspection blocks departure
    clearance until a follow-up inspection has Passed (ch24 §20.1).
27. **Departure clearance:** granted by a Berth Officer; requires every inspection on the
    booking to be Passed or Deferred (ch25 §21.1).
28. **Audit trail:** every status change on a booking, decision, invoice or inspection is
    written to an audit entry with actor, timestamp and action (ch26 §22.1).
29. **Access scoping:** agents can only see bookings, invoices and inspections belonging
    to their own company (ch35 §29.1).
30. **AIS auto-arrival:** vessel positions are imported from the AIS feed every 5 minutes;
    a booking is flagged Arrived when the vessel enters the port geofence (ch33 §28.2).
    No endpoint, auth, or failure-mode detail is given anywhere in the corpus.
31. **Reporting:** a monthly berth-occupancy report per terminal can be exported as CSV
    (ch32 §27.1).

**Open/undecided (from `workshop-notes.md`, Session 2):** attachment size limit for the
cargo manifest PDF an agent attaches to a booking request — explicitly "not decided".
Agents must be able to attach the cargo manifest as a PDF (a requirement with no chapter
of its own — not covered in ch08/09/10 text, workshop-only).

---

## 5. Roles and Permissions

| Role | Can do |
|---|---|
| Shipping Agent | create/edit/cancel own company's booking requests (rules 1,3,6,7,8); attach cargo manifest PDF; see only own company's bookings/invoices/inspections (rule 29) |
| Berth Officer | review requests, record approval decisions (rules 12,13); grant departure clearance (rule 27); waive late-arrival surcharge for vessels <80m (rule 20) |
| Harbour Master | everything a Berth Officer can, plus: override a Rejected decision (rule 14), reactivate a suspended agent (rule 9), waive a tariff surcharge (rule 11), mark an invoice Paid/Void (rule 22) |
| Inspector | schedule inspections, record checklist outcomes (rules 23-25) |

Role names are shown in the header of every screen (`roles.md`). Every user has exactly
one role — no multi-role users in this spec.

---

## 6. Integration Points

| System | Action | Parameters | Stub-able? |
|---|---|---|---|
| AIS feed | import vessel positions, flag booking Arrived on geofence entry | none specified — no endpoint, auth, or payload schema in the corpus | Yes — must be stubbed; this is a **named but unspecified** integration (rule 30). Failure/retry behaviour is not described anywhere. |
| Agent e-mail | status-change notification | booking reference (workshop-notes.md: agents want the reference included) | Yes — standard Mendix email connector; not an external system contract in the source sense |
| Officer digest e-mail | daily 06:00 digest | ETA within 48h | Yes — same as above |

---

## 7. Entities

Full attribute tables cross-extracted mechanically and verified against `glossary.md` —
see `entities.json` in this same folder for the machine-readable form (11 entities, 13
relationships, all counts matching the glossary exactly). Entity list: Vessel,
ShippingAgent, Terminal, Berth, BookingRequest, ApprovalDecision, Tariff, Invoice,
Inspection, InspectionItem, AuditEntry.

Relationships (from ch07/ch12/ch26/ch36, all many-to-one unless noted):
BookingRequest->Vessel, BookingRequest->ShippingAgent, BookingRequest->Berth,
ApprovalDecision->BookingRequest, Invoice->BookingRequest (one-to-one),
Invoice->ShippingAgent, Invoice->Tariff, Inspection->BookingRequest,
InspectionItem->Inspection, Berth->Terminal, Tariff->Terminal,
AuditEntry->BookingRequest, Vessel->ShippingAgent (many-to-many).

---

## 8. Open Questions / Decisions

- D1: Cargo-manifest PDF attachment size limit — **Open** (`workshop-notes.md` Session 2,
  explicitly "not decided"). No chapter covers this attachment feature at all.
- D2: Officer review screen must show the last five bookings of the same vessel
  (`workshop-notes.md` Session 3) — **Open**, not reflected in ch21's own text.
- D3: AIS feed integration contract (endpoint, auth, failure/retry behaviour) — **Open**,
  named in ch33 but never specified; recommend stub-with-manual-fallback per triage.md.
- D4: Licence/security constraints on storing this source, and SME availability —
  **Open**, human-only questions raised at Stage P and left UNRAISED in this unattended
  run (see `PROJECT.md`).
- D5: Data-migration source (the spreadsheet process being replaced) — **Open**, no
  schema, sample or volume is given anywhere in the corpus (source-sufficiency: `named`,
  not `specified`).
