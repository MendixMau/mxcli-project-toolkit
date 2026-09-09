# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage 2 — Requirements**, gate PASSED (2026-09-09). Run task boundary stops here; Stage 3
not started.

Toolkit commit: 5ffbda6

Entry mode: requirements-driven (docs-ready corpus fast path — conversion-runbook.md
"Requirements-driven, docs-ready corpus")

Interview mode: unattended

Environment: cloud container (Linux, no Studio Pro, no Docker daemon — per `bin/doctor.sh`
output at scaffold time; mxbuild gate will report skipped for any exec, not relevant to
Stages 0-2 of this run)

Run: A/B evaluation, run **b1** (arm B). No human respondent available this session.

<!-- Where this project joins the pipeline: nothing recorded, so it starts at Stage P — the
     usual case. If work was already done outside the toolkit, record it once and the earlier
     stages report WAIVED instead of a red row nobody can clear:
       bin/gate-check.sh <project> --adopt 5 --reason "..."     every stage before 5
       bin/gate-check.sh <project> --waive 2 --reason "..."     just that one (one line per stage)
     Intake Q10 asks this. Never infer it from what happens to be on disk. (No example line is
     written out here on purpose: gate-check reads these labels back out of this file, and a
     sample value would waive stages in every project that never deleted it.) -->

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
| P | Entry mode: requirements-driven, docs-ready corpus | ASSUMED | corpus is 36 HTML pages + 4 md files, no legacy code, no Office/PDF containers — conversion-runbook.md classification rule 2 |
| P | Project driver: production replacement, open-ended; fidelity: port-as-documented | ASSUMED | corpus reads as a workshopped spec (8 ADRs, 3 workshop sessions), not a POC; no hard date stated |
| P | Scope boundary: whole documented application, this run through Stage 2 only | ASSUMED | nothing in the corpus is marked out of scope |
| P | Interview mode: unattended | ASSUMED | explicit run instruction, no human respondent available |
| 0 | Source sufficiency: SPECIFICATION, 70% build-ready, 2 contradictions + 2 shape-changing gaps | ASSUMED | source-sufficiency.json; each contradiction/gap resolved with its own Ruling below |
| 0 | Extraction approach: N/A (text-native corpus) | ASSUMED | no schema/code/contract anywhere in `sources/` — html-to-md.sh conversion only |
| 1 | Stage 1 waived: text-native corpus, html-to-md conversion is the whole of Stage 1 | CONFIRMED | conversion-runbook.md docs-ready-corpus fast path; ledger PASS 200/200 |
| 2 | 7 BRDs written (F001-F007), brd-validation Stop condition = Clean | CONFIRMED | analysis/knowledge-base/brd/*.json; analysis/knowledge-base/reports/validation-report.md; bin/gate-check.sh 2 → PASS |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.

## Rulings (unattended)

Ruling: entry mode = requirements-driven, docs-ready-corpus fast path — the source folder holds
only a documentation-portal HTML export plus glossary/roles/decisions/workshop markdown, no
legacy code, no Office/PDF containers — cost if wrong: stages 0-1 mis-scoped, would need
re-triage as Migration or plain requirements-driven (re-running Stage 0/1 is cheap, nothing
downstream would have been built yet).

Ruling: project driver taken as production replacement (open-ended), fidelity as port-as-documented
— the corpus is an internally-consistent, workshopped specification (ADRs + 3 workshop sessions),
treated as the single source of truth per ADR-001 — cost if wrong: Stage 3 fit-gap calls made on
the wrong default (as-is vs improve), rework limited to that stage's fit-gap framing.

Ruling: no SME available, no licence/security constraint on storing the corpus — the corpus
declares its own data fictional (ADR-003, glossary) — cost if wrong: none; this is a low-risk
default confirmed by the source itself, not merely assumed.

Ruling: CAC-1 scope brainstorm (Stage 0 close) — whole documented application in scope, build
order Vessel/Berth master data -> Booking lifecycle -> Officer review -> Inspections/departure
-> Tariffs/invoicing -> Notifications/audit -> Reporting -> Security -> AIS integration
(stub/deferred, no endpoint named). This run's own task boundary stops at the Stage 2 BRD gate.
Full reasoning in triage.md "Recommended Scope Subset" — cost if wrong: Stage 4 build-plan
reorders capabilities, no rework of Stage 2 BRDs.

Ruling: source-sufficiency band = SPECIFICATION, 70% build-ready, 2 contradictions + 2
shape-changing gaps found (source-sufficiency.json `conflicts`/`choices`). Tool recommends
interview mode "steering" (a contradiction should be put to a human) — this run proceeds
unattended per its explicit authorization; each contradiction/gap is resolved ASSUMED below,
not silently averaged into the score. Cost if wrong is stated per item.

Ruling: contradiction — 08-booking-lifecycle.md §4.4 fast-track auto-approval (<120m LOA,
berth free whole stay) vs. 15-officer-review-process.md §11.4 "no automatic approval; every
booking is reviewed by a berth officer". Resolved ASSUMED in favour of §11.4 (the more
explicit, unambiguous statement) — the fast-track text is treated as stale/superseded and not
built. Cost if wrong: officers manually approve cases that could have auto-approved —
conservative, reversible at Stage 5 by adding one microflow branch.

Ruling: contradiction — 22-inspection-scheduling.md §18.1 (inspection scheduled against an
Approved booking, general case) vs. §18.2 (Dangerous Goods cannot be Approved until an
inspection has been scheduled). Resolved ASSUMED as a DG-specific carve-out on the approval
gate, not a true contradiction: for DG cargo the officer schedules the inspection while the
booking is Under Review, then approves once scheduled. Cost if wrong: reverse the
schedule/approve ordering in one microflow at Stage 5.

Ruling: shape-changing gap — cargo manifest PDF attachment (workshop-notes.md session 2,
attachment size limit explicitly undecided) never promoted into any of 7 chapter revisions.
Resolved ASSUMED deferred/out of Stage 2 BRD scope — ADR-007 treats the chapters, not raw
workshop notes, as where requirements settle. Cost if wrong: retrofit one file-association
entity + one page control at Stage 3/5.

Ruling: shape-changing gap — "review screen must show the last five bookings of the same
vessel" (workshop-notes.md session 3) never promoted into any chapter. Resolved ASSUMED
deferred/out of Stage 2 BRD scope, same reasoning. Cost if wrong: one extra list widget on one
page at Stage 5.

Ruling: field-level conflict — BookingRequest/Vessel IMO number is "Text, up to 7 characters"
in the domain-overview/appendix data-dictionary tables (ch07, ch36) vs. "must be EXACTLY 7
digits" in the booking-form validation screenshot (fig-booking-form-validation.png). Resolved
ASSUMED in favour of the screenshot (more specific, and a validation rule is more authoritative
than a field-length note) — adopted as: fixed-length 7-digit numeric string. Cost if wrong: one
validation microflow rule changes width at Stage 5.

Ruling: CAC-1b scope-out (Stage 1 close) — `bin/html-to-md.sh` converted all 36 pages + 4
markdown files, no extractor ran (N/A, text-native corpus), so there is no extraction-scope
delta to reconcile against Stage 0's slice — what came out of conversion is exactly the input
corpus, 1:1. Extraction scope: everything in `sources/` is in, nothing narrowed. Cost if wrong:
none — conversion is lossless by construction (html-to-md preserves every section; verified by
reading the full converted text end to end for BRD-writing, immediately below).

## Toolkit position

Waived stage 1: text-native corpus: converted once with html-to-md, no extractor applies
