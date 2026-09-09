# Business rules extracted from the documentation corpus

Working notes for Stage 0/2 — each rule as stated, with its source chapter/section. Used to
populate BRD `microflows[].validations` and use-case flows with `sourceRef`s. Not itself a
gate artifact.

| # | Rule | Source |
|---|---|---|
| 1 | Booking reference format `HB-YYYY-NNNNN`, assigned on submission; references are never reused, even after cancellation (kept for the audit trail) | 08-booking-lifecycle.md §4.2; decisions-log ADR-004 |
| 2 | Status model: Draft → Submitted → Under Review → Approved / Rejected / Cancelled → Completed | 08-booking-lifecycle.md §4.3 |
| 3 | **[CONTRADICTED by #16]** Fast-track: booking auto-approved when berth is free for the whole stay and vessel LOA < 120m | 08-booking-lifecycle.md §4.4 |
| 4 | Submission window: not more than 90 days before ETA, at least 48 hours before ETA | 08-booking-lifecycle.md §4.5 |
| 5 | Draft bookings are invisible to officers; agent completes and submits later | 08-booking-lifecycle.md §4.1 |
| 6 | Submit requires vessel, berth, ETA, ETD, cargo class | 09-booking-request-form.md §5.1 |
| 7 | ETD must be later than ETA; stay longer than 30 days is rejected | 09-booking-request-form.md §5.2 |
| 8 | IMO number must be exactly 7 digits (screenshot; data dictionary only says "up to 7 characters" — screenshot is the more specific rule, adopted) | 09-booking-request-form_files/fig-booking-form-validation.png |
| 9 | Agent may edit a Submitted request until an officer opens it for review, then it locks | 10-cancellation-and-changes.md §6.1 |
| 10 | Cancellation free of charge until 24h before ETA | 10-cancellation-and-changes.md §6.2 |
| 11 | Approved booking may be cancelled by the agent; Completed cannot be cancelled | 10-cancellation-and-changes.md §6.2 |
| 12 | Agent registers with company name, licence number, contact e-mail; activated by a Berth Officer | 11-agent-onboarding.md §7.1 |
| 13 | Agent with 3+ overdue invoices is automatically suspended | 11-agent-onboarding.md §7.2 |
| 14 | Suspended agent cannot submit; already-Approved bookings remain valid; reactivation only by Harbour Master (no self-service) | 11-agent-onboarding.md §7.2 |
| 15 | Berth fit check: vessel length ≤ berth max length AND vessel draught ≤ (berth max draught − 0.5m) | 13-berth-allocation-rules.md §9.1 |
| 16 | **[CONTRADICTS #3, adopted]** No automatic approval; every booking request is reviewed by a Berth Officer before it can become Approved | 15-officer-review-process.md §11.4 |
| 17 | Only the Harbour Master may waive a tariff surcharge | 13-berth-allocation-rules.md §9.3 |
| 18 | Booking Board lists Submitted + Under Review requests ordered by ETA | 15-officer-review-process.md §11.1 |
| 19 | Opening a request for review moves it to Under Review and records the reviewing officer | 15-officer-review-process.md §11.2 |
| 20 | Approval decision outcomes: Approved, Rejected, Returned for Information | 16-approval-decisions.md §12.1 |
| 21 | Returned for Information goes back to the agent, who may amend and resubmit ONCE | 16-approval-decisions.md §12.2 |
| 22 | Only the Harbour Master may override a Rejected decision; override recorded with a reason | 16-approval-decisions.md §12.3 |
| 23 | Rejection reason is required when outcome = Rejected | 21-officer-review-screen.md inline screenshot |
| 24 | Agent receives an e-mail whenever their booking's status changes | 17-notifications.md §13.1 |
| 25 | Officers receive a daily digest at 06:00 listing requests with ETA within the next 48 hours | 17-notifications.md §13.2 |
| 26 | Tariff defined per terminal: rate per metre of vessel length per day, currency, validity period | 18-tariff-structure.md §14.1 |
| 27 | Berth fee = vessel length × days-alongside × tariff rate; days rounded up, minimum 1 day | 18-tariff-structure.md §14.2 |
| 28 | VAT of 21% added to all berth fees | 18-tariff-structure.md §14.3 |
| 29 | Shore power billed at a flat 250/day when the berth offers it and the agent requested it | 18-tariff-structure.md (footer note) |
| 30 | Vessel arriving more than 2h after ETA incurs a 15% late-arrival surcharge on the berth fee | 19-tariffs-cancellation-fees.md §15.1 |
| 31 | Cancellation within 72h of ETA charged 50% of the berth fee | 19-tariffs-cancellation-fees.md §15.2 |
| 32 | Invoice auto-generated when a booking is marked Completed | 20-invoicing.md §16.1 |
| 33 | Harbour Master can mark an invoice Paid or Void; a Paid invoice cannot be edited | 20-invoicing.md §16.3 |
| 34 | Invoice due 30 days after issue date; becomes Overdue the day after the due date | decisions-log ADR-006 |
| 35 | Review screen shows vessel dimensions next to berth limits, highlights any exceedance in red | 21-officer-review-screen.md §17.1; workshop-notes session 3 |
| 36 | Inspector schedules an inspection against an Approved booking; agent is notified of the time slot | 22-inspection-scheduling.md §18.1 |
| 37 | Dangerous Goods cargo class cannot be Approved until an inspection has been **scheduled** (a carve-out on rule #16's approval gate for DG bookings — read together, not a contradiction: for DG the officer schedules the inspection while Under Review, then approves) | 22-inspection-scheduling.md §18.2 |
| 38 | Inspection checklist item categories: Safety, Environmental, Documentation, Security | 23-inspection-checklist.md §19.1 |
| 39 | Per checklist item: compliant/not compliant, severity Low/Medium/High, optional note | 23-inspection-checklist.md §19.2 |
| 40 | Inspection with any non-compliant High-severity item has outcome Failed | 23-inspection-checklist.md §19.3 |
| 41 | Failed inspection blocks departure clearance until a follow-up inspection has Passed | 24-inspection-outcomes.md §20.1 |
| 42 | Berth officer may waive the late-arrival surcharge for vessels shorter than 80m | 24-inspection-outcomes.md §20.3 |
| 43 | Departure clearance granted by a Berth Officer, requires every inspection on the booking Passed or Deferred | 25-departure-clearance.md §21.1 |
| 44 | Every status change on a booking, decision, invoice or inspection is written to an audit trail (actor, timestamp, action) | 26-audit-and-compliance.md §22.1 |
| 45 | Agents can only see bookings, invoices and inspections belonging to their own company | 35-security-and-access.md §29.1 |
| 46 | System imports vessel positions from the AIS feed every 5 minutes; flags a booking Arrived when the vessel enters the port geofence | 33-integration-ais-feed.md §28.2 |
| 47 | Monthly berth occupancy report per terminal, exportable as CSV | 32-reporting.md §27.1 |
| 48 | Navigation offers three top-level screens: Booking Board, My Bookings, Inspection Calendar | 28-navigation-and-screens.md §23.1 |
| 49 | Booking Board filterable by terminal, status, ETA date range | 29-booking-board-screen.md §24.1 |
| 50 | My Bookings shows the agent's own requests only, Draft listed first | 30-my-bookings-screen.md §25.1 |
| 51 | Inspection Calendar shows inspections per day/inspector, drag-and-drop rescheduling | 31-inspection-calendar-screen.md §26.1 |

## Workshop-only items never promoted into a numbered chapter (7 revisions later)

These are real requirements voiced in the workshop but absent from the formal chapters —
`decisions-log.md` ADR-007 says workshop notes are raw input and clean-up happens in the
chapters, so their absence after 7 revisions is itself a signal, not an oversight to silently
fix. Raised as Stage 2 open questions, resolved ASSUMED (deferred) in this unattended run.

- Agents must be able to attach the cargo manifest as a PDF to a booking request; attachment
  size limit explicitly "not decided" (workshop-notes.md, session 2).
- E-mail notifications should include the booking reference (workshop-notes.md, session 2) —
  low-risk, adopted as a detail of rule #24, not deferred.
- The officer review screen must show the last five bookings of the same vessel
  (workshop-notes.md, session 3).
