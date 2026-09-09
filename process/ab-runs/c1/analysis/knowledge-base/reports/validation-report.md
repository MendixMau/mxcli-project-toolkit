# BRD validation report — abproj

Hand-written, doc-derived BRDs (provenance: documents) — checks 4-6 of `brd-validation.md`
(broken relationships, low-confidence rollup, code/doc flow reconciliation) do not apply, since
there is no code extraction here. Checks run:

## 1. Duplicate entities/concepts — CLEAN
11 domain entities (BookingRequest, ShippingAgent, Berth, Terminal, Vessel, ApprovalDecision,
Tariff, Invoice, Inspection, InspectionItem, AuditEntry), each defined in exactly one BRD, no
attribute-set overlap across BRDs.

## 2. Conflicting business rules — 3 found, NONE silently resolved
Every contradiction found while reading the corpus (source-sufficiency.json `conflicts`, 3
entries) has a corresponding `openQuestions` entry in the owning BRD, `status: ASSUMED` with
`consentBy`/`consentAt` recording the unattended run's self-consent, and the drafting position
taken is stated in the affected use case's `notes`:
- F001 OQ-1 / F004 UC003 — fast-track auto-approval vs manual-review-only
- F001 OQ-2 — cancellation fee window overlap
- F003 UC003 / F007 OQ-3 — surcharge waiver authority

## 3. Orphaned concepts — CLEAN
Every association target (Vessel, ShippingAgent, Berth, Terminal, Tariff, BookingRequest,
Inspection) is defined as a `domainEntities` entry in some BRD in this set; no BRD entity or
rule lacks a `sourceRef`.

## 7. Negative claims and unearned numbers — CLEAN
Every numeric threshold in every BRD (30-day max stay, 48h/90d submission window, 0.5m draught
clearance, 120m fast-track length, 21% VAT, 15%/50% surcharges, flat 250/day shore power,
3-overdue-invoice suspension, 80m surcharge-relief threshold, 5-minute AIS poll) carries a
`sourceRef` to the exact chapter section it was lifted from — none are estimates or bare counts.

## Stop condition
Clean — no findings outside the 3 recorded, non-silently-resolved contradictions above. Two additional
open items (OQ-4 cargo manifest attachment, OQ-5 last-five-bookings, OQ-6 reference-in-email)
are workshop-notes-only requirements, also carried as `openQuestions` with an ASSUMED drafting
position rather than silently added to or omitted from scope. OQ-7 (AIS integration contract)
is left `RAISED` rather than `ASSUMED` — the corpus states no protocol/auth/payload detail to
draft a position from, and inventing one would be a guess, not a drafting position.
