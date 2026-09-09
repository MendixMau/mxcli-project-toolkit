# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

Toolkit commit: 25fd0c4

Interview mode: unattended
Entry mode: requirements-driven

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
| P | Entry mode: requirements-driven | CONFIRMED | No legacy code in sources/; documentation-portal export with prototype screenshots. Intake Q1. |
| P | Project driver: (c) production build, open-ended | ASSUMED | No deadline/legacy stated in corpus. Intake Q2. |
| P | Fidelity: build as-documented, least-surprising default where silent | ASSUMED | No legacy app to diverge from. Intake Q3. |
| P | Scope: whole documented app; pilotage/tug scheduling OUT (existing marine ops system) | ASSUMED | Source's own stated boundary, ch.04 §1.3. Intake Q4. |
| P | Must-not-change constraints: booking ref format/permanence, invoice due-date math, AIS 5-min cadence, 4 fixed roles | ASSUMED | ADR-004, ADR-006, ch.33, roles.md. Intake Q5. |
| P | SME: none available this run | ASSUMED | Unattended mode; Path C declared not-available for this run. Intake Q7. |
| P | Interview mode: unattended | CONFIRMED | Set by run instructions. Intake Q9. |
| P | Adoption: starting from scratch, nothing waived | CONFIRMED | Intake Q10. |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|
| 1 | Licence/security constraints on storing this source? | Stage P | UNRAISED — no human present; see Ruling ledger |
| 2 | Anything else — scope, priorities, worries? | Stage P | UNRAISED — no human present; standing open-floor question |
| 3 | D1: Cargo-manifest PDF attachment size limit | Stage 2 | RAISED — posed in chat via `bin/open-questions.sh --stage 2`, 2026-09-09; no human present to reply |
| 4 | D2: Officer review screen must show last 5 bookings of same vessel | Stage 2 | RAISED — same batch |
| 5 | D3: AIS feed integration contract (endpoint/auth/failure-mode) | Stage 2 | RAISED — same batch |
| 6 | D4: Licence/security constraints + SME availability | Stage 2 | RAISED — same batch (restates Stage P Q1/Q2 UNRAISED rows above, now also carried as a Stage 2 BRD open question) |
| 7 | D5: Data-migration source (spreadsheet process) — no schema/sample/volume | Stage 2 | RAISED — same batch |

## Assumptions (ASSUMED, unresolved)

All ASSUMED rows above are unresolved pending the next attended session.

| 0 | Extraction approach: build small custom extractor for embedded entity tables | ASSUMED | `analysis/extract-entities.py`; validated 11/11 entities against glossary.md |
| 0 | Business capability map + coverage matrix: 11 capabilities, 7 with Ready entity extraction, 4 Manual | ASSUMED | See triage.md |
| 0 | Recommended scope subset: whole app, master-data-first build order, AIS stubbed | ASSUMED | See triage.md |
| 0 | Architecture scale flag: No concern (single app) | ASSUMED | See triage.md |
| 0 | Sign-off recorded (unattended) | ASSUMED | triage.md `## Sign-off` |
| 1 | CAC-1b scope-out: accept — extraction covered exactly the Stage 0 scope (whole app, pilotage/tug excluded), no over-reach | ASSUMED | 41 files extracted into KB_HarbourBerthBooking_Functional.md; 159 waived (site chrome/decorative only); 0 pending/fault |
| 1 | Extraction scope: whole documented app extracted via Path B (LLM read) + small custom entity-table extractor (Path B variant); Path A N/A (no code); Path C N/A (no SME this run) | CONFIRMED | analysis/harbour-berth-booking/knowledge-base/share/ |
| 2 | BRD scope: 6 feature-scoped BRDs (F001-F006) covering all 11 entities, 31 business rules, 28 use cases; validated Clean | CONFIRMED | analysis/harbour-berth-booking/knowledge-base/brd/, reports/validation-report.md |
| 2 | 5 open questions (D1-D5) raised in chat via bin/open-questions.sh, none answerable without a human; recorded RAISED, carried to next attended session | ASSUMED | See close-out block; questions-report at docs/open-questions.html |

## Rulings (unattended)

Ruling: entry mode = requirements-driven — no legacy source in corpus, only documents/images — cost if wrong: whole pipeline misrouted, but evidence is unambiguous (no code anywhere in sources/).
Ruling: project driver = (c) open-ended production build — corpus reads as a full production spec, no deadline stated — cost if wrong: over-invested completeness vs a POC; low, since the spec itself is production-shaped.
Ruling: fidelity = build as-documented — no legacy app exists to diverge from — cost if wrong: none (there is no "as-is" alternative to lose).
Ruling: scope = whole app, pilotage/tug OUT — ch.04 §1.3 states this exclusion verbatim — cost if wrong: none, it is the source's own boundary.
Ruling: SME = unavailable this run, Path C not-run — no human present — cost if wrong: any question that only an SME could resolve is recorded ASSUMED and stays open for the next attended session rather than silently decided.
Ruling: Q6 (licence/security) and Q8 (open-floor) left UNRAISED rather than defaulted — answering them requires a human decision, not evidence — cost if wrong: N/A, nothing was assumed in their place.
Ruling: Stage 0 extraction approach = build a small custom extractor (analysis/extract-entities.py) for the "Data: <Entity>" tables in ch07/12/14/26/36, rather than N/A-ing extraction on the requirements-driven label — cost if wrong: low; the extractor is 100 lines, validated 11/11 entities and their attribute counts against glossary.md, and its output is cross-checked, not blindly trusted.
Ruling: Stage 0 scope brainstorm (CAC-1) = whole documented app, master-data-first build order (Berth/Terminal + Agent/Vessel, then Booking, then Review, with Security woven in from module 1), AIS stubbed pending real feed contract — cost if wrong: build-plan reordering at Stage 4, not a scope change (source-triage.md: "a slice is an ordering, not an exclusion").
Ruling: Architecture Scale Flag = No concern, single Mendix app — cost if wrong: none identified; 11 entities/11 capabilities are well under the 8-10+ module trigger.
Ruling: Stage 0 sign-off recorded as agent-ASSUMED (no human to confirm) rather than left blank — cost if wrong: none; explicitly flagged for the next attended session rather than presented as a real confirmation.

## Toolkit position

Waived source site.css: documentation-portal stylesheet, identical on all 36 chapter pages, no functional content

## Toolkit position

Waived source app.js: documentation-portal client script (sidebar collapse etc.), identical on all 36 chapter pages, no functional content

## Toolkit position

Waived source print.css: documentation-portal print stylesheet, no functional content

## Toolkit position

Waived source font-harbour-sans.woff: documentation-portal web font, no functional content

## Toolkit position

Waived source img-01.jpg: decorative stock illustration ('Container terminal at dawn'), reused on every chapter's Gallery section, no functional content

## Toolkit position

Waived source img-02.png: decorative illustration (quay wall and mooring bollards) on ch21, no functional content — distinct from fig-booking-form-validation.png which IS extracted (image-only IMO validation rule)
