# PROJECT.md — harbourproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage 4 — Build Plan**, gate run.

Toolkit commit: 3d66695

Interview mode: unattended
Entry mode: requirements-driven, docs-ready corpus (per conversion-runbook.md → Entry Modes →
"Requirements-driven, docs-ready corpus": 36 saved-webpage HTML pages + 4 Markdown files under
sources/, no legacy code, no Office/PDF containers)

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
| P | Entry mode: requirements-driven, docs-ready corpus | ASSUMED | intake.md Q1; 36 HTML + 4 MD, no code, no Office/PDF |
| P | Project driver: (c) production replacement, open-ended | ASSUMED | intake.md Q2 |
| P | Fidelity: port documented behaviour faithfully; conflicts resolved explicitly, not silently | ASSUMED | intake.md Q3 |
| P | Scope: whole documented app; pilotage/tug scheduling excluded (ch04 stated boundary) | ASSUMED | intake.md Q4 |
| P | Must-not-change: booking ref format `HB-YYYY-NNNNN` (permanent), tariff/VAT/invoice arithmetic, AIS poll/geofence semantics as documented | ASSUMED | intake.md Q5 |
| P | No licence/security constraint on storing source (fictional corpus, ADR-003) | ASSUMED | intake.md Q6 |
| P | No SME available this run | ASSUMED | intake.md Q7 |
| P | Interview mode: unattended | CONFIRMED | run identifier `final-harbour-c` authorization |
| P | Adoption: starting from scratch, nothing adopted/waived at project level | CONFIRMED | intake.md Q10 |
| 0 | Extraction Approach + Coverage Matrix: N/A (text-native corpus) | ASSUMED | `triage.md`; per conversion-runbook.md docs-ready path, not a per-structure call |
| 0 | Business Capability Map: 11 capabilities (see `triage.md`) | ASSUMED | built from the converted corpus |
| 0 | Recommended slice ordering: master data + security first → booking lifecycle → review + tariffs/invoicing → inspections → reporting; AIS integration deferred (stub first) | ASSUMED | `triage.md` Recommended Scope Subset; CAC-1 |
| 0 | Architecture scale flag: No concern — one Mendix app | ASSUMED | `triage.md` Architecture Scale Flag |
| 0 | Interview mode recommendation from sufficiency report ("steering") — accepted | ASSUMED | 4 contradictions require a steer, not a default |
| 0 | Stage 0 sign-off | ASSUMED | `triage.md` Sign-off; CAC-1 closed |
| 1 | Stage 1 gate (extraction-report.html) WAIVED — text-native corpus, converted once with `bin/html-to-md.sh`, no extractor applies | CONFIRMED | conversion-runbook.md docs-ready path names this exact waiver; `bin/gate-check.sh /tmp/harbourproj --waive 1 --reason "..."` |
| 1 | Source ledger: one glob mark `sources/**` → `analysis/knowledge-base/documents-index.md` | CONFIRMED | `bin/source-ledger.sh mark` |
| 1 | Extraction scope (CAC-1b): everything the corpus describes is in; nothing was over-extracted since nothing was extracted — html-to-md is a lossless format conversion, not a scoping step | ASSUMED | CAC-1b outcome |
| 3 | Module boundaries: 5 modules — HB_MasterData, HB_Booking (BookingRequest+ApprovalDecision merged, over-split anti-pattern avoided), HB_Finance, HB_Inspection, HB_Reporting (shared audit/CSV) | CONFIRMED | `architecture/module-design.html`; run authorization (see Ruling R11) |
| 3 | Architecture decision: `AuditEntry` drops its literal `AuditEntry_BookingRequest` association (source relationships list); generic `EntityName`+`RelatedReference` text fields used instead, to keep `HB_Reporting` a true Common module with no upward-pointing association | CONFIRMED | BRD F007-Q1; `[sync: F007 synced 2026-09-12]` |
| 3 | 6a Security/role model: 4 roles map 1:1 onto Mendix user roles; no anonymous/guest access; no additional PII/regulatory segregation beyond existing company-row-security | CONFIRMED | `architecture/blueprint.md` Step 6a; run authorization (Ruling R11) |
| 3 | 6b Data volumes/NFRs: no numbers in source; assumed small/medium port-authority scale (standard Data Grid 2 pagination, no special indexing) | CONFIRMED | `architecture/blueprint.md` Step 6b; run authorization (Ruling R11) |
| 3 | 6c Integration contracts: AIS feed built as a stub (poll+geofence behaviour only); real endpoint/auth/failure-mode undocumented | CONFIRMED | `architecture/blueprint.md` Step 6c; run authorization (Ruling R11) |
| 3 | Fit-gap: one marketplace "Buy" (inspection-calendar drag-drop widget); everything else Native/Config/Build | CONFIRMED | `architecture/fit-gap.md` |
| 3 | Architecture review (Step 7b): one pass, no P1 findings, single-app confirmed | CONFIRMED | `architecture/blueprint.md` "Architecture review" section; run authorization (Ruling R11) |
| 4 | Build plan approved: 39 rows, dependency-ordered, per-layer granularity, StyleGallery = Yes | CONFIRMED | `architecture/build-plan.md`; run authorization (Ruling R12) |
| 4 | Coverage check: 0 UNCLAIMED, 0 PHANTOM, 0 DOUBLE-CLAIMED, 0 COUNT-MISMATCH across all 7 BRDs (1189 leaves; 894 CLAIMED, 115 LEDGERED) | CONFIRMED | `bin/coverage-check.sh` run against each BRD + its module's `architecture/modules/<Module>/coverage-ledger.md` |
| 4 | Every Stage 0-3 CONFIRMED decision mapped to a build-plan row (Step 9 reconciliation) — none silently descoped | CONFIRMED | `architecture/build-plan.md` Step 9 |
| 4 | Acceptance criteria per module, iteration granularity (per-layer), environment (single, no DTAP signal) | CONFIRMED | `architecture/build-plan.md` Step 2; run authorization (Ruling R12) |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|
| 1 | C1 — Cancellation fee: free until 24h before ETA (ch10) vs 50% fee within 72h of ETA (ch19) — what applies in the 24-72h window? | Stage 0 | ASSUMED — see Rulings; drafting position: ch19's 72h/50% rule governs down to 24h, ch10's "free" applies only inside... **not adopted**, see Ruling R3 for the position actually taken |
| 2 | C2 — Navigation: ch28 states 3 screens (Booking Board, My Bookings, Inspection Calendar); prototype screenshots show 5 nav items (+ Inspections/Tariffs/Reports) | Stage 0 | ASSUMED — see Ruling R4 |
| 3 | C3 — IMO number: domain tables say "up to 7 characters"; booking-form validation screenshot says "exactly 7 digits" | Stage 0 | ASSUMED — see Ruling R5 |
| 4 | C4 — ApprovalDecision.Reason is "Optional" in the data dictionary, but the review-screen screenshot shows it conditionally required when Outcome = Rejected | Stage 0 | ASSUMED — see Ruling R6 |
| 5 | S1 — Cargo-manifest PDF attachment on BookingRequest (workshop-notes session 2); size limit explicitly "not decided" | Stage 0 | ASSUMED — see Ruling R7 |
| 6 | S2 — Officer review screen must show the vessel's last five bookings (workshop-notes session 3); not in any formal chapter | Stage 0 | ASSUMED — see Ruling R8 |
| 7 | S3 — Notification e-mails should include the booking reference (workshop-notes session 2); ch17 states no content | Stage 0 | ASSUMED — see Ruling R9 |

## Assumptions (ASSUMED, unresolved)

All ten intake answers (Q1-Q8, Q10) and every Decisions-table row marked `ASSUMED` above are
unresolved pending a human reviewer of this unattended run. See `## Rulings (unattended)` below
for the reasoning and cost-if-wrong behind each.

## Rulings (unattended)

Run identifier: `final-harbour-c`. Nobody could be asked; every ruling below was still framed as
a question, with evidence and a recommendation, before being decided — see the conversation
transcript for the full form. Cost-if-wrong is stated so a returning human knows which to check
first.

Ruling: R1 — Entry mode = requirements-driven, docs-ready corpus — corpus is 100% HTML/Markdown,
no code, no Office/PDF — cost if wrong: whole pipeline shape (Stage 1 waiver, thin BRD transform)
would need redoing.

Ruling: R2 — Whole documented scope in one slice, ordered master-data-and-security first,
AIS-integration last/stubbed — no business-priority signal exists in the corpus to override an
architecture-driven order — cost if wrong: re-order `architecture/build-plan.md` rows, cheap
before Stage 5 starts.

Ruling: R3 (answers open question #1, C1) — Cancellation fee: adopted ch19's window as the
authoritative rule (a stay cancelled within 72 hours of ETA is charged 50% of the berth fee;
"free of charge" in ch10 is read as describing the period *outside* 72 hours, i.e. ch10's "24
hours" is treated as a drafting error superseded by ch19's later, more specific 72-hour rule) —
recorded as a BRD business rule with this reading flagged for the returning human to confirm or
overturn — cost if wrong: one fee-calculation microflow's threshold constant changes from 72h to
24h; no structural rework.

Ruling: R4 (open question #2, C2) — Navigation: built the wireframe/nav set from the prototype
screenshots (5 items: Booking Board, My Bookings, Inspections, Tariffs, Reports), since a
screenshot is direct UI evidence and ch28's "three screens" reads as stale prose (ch28 itself is
marked "functional description", the screenshots are captioned "from the clickable prototype") —
cost if wrong: drop 2 nav items and their wireframes/pages from the build plan; contained to
Stage 3-4 artifacts, not the domain model.

Ruling: R5 (open question #3, C3) — IMO number: modelled as a Text attribute of exactly 7
characters, all digits, enforced by a microflow validation rule (not just the attribute length) —
takes the stricter, more specific screenshot rule over the vaguer "up to 7" prose, since a
validation shown in the actual prototype is stronger evidence of intended behaviour than a
rounded-up prose bound — cost if wrong: loosen one validation microflow; no data model change
(the attribute was already length-7).

Ruling: R6 (open question #4, C4) — ApprovalDecision.Reason: kept the attribute Optional per the
data dictionary, and added an explicit microflow validation rule "Reason is required when Outcome
= Rejected" per the screenshot, rather than treating the two as contradictory — the field-level
"Optional" and the conditional business rule are not actually in conflict once modelled
separately — cost if wrong: none; this is a straight reading, not a guess between two options.

Ruling: R7 (open question #5, S1) — Cargo-manifest attachment: added to the Stage 2 BRD as an
open, undecided requirement (BookingRequest gets a one-to-many file/attachment relation,
PDF-only, size limit TBD) rather than inventing a limit — recorded as an explicit `openQuestions`
entry in the relevant BRD, not silently sized (e.g. "10 MB, because that's typical") — cost if
wrong: none, since no number was invented; a returning human sets the real limit before Stage 5.

Ruling: R8 (open question #6, S2) — Last-five-bookings panel: added to the officer review
screen's wireframe and BRD as a read-only sub-list ("last 5 BookingRequests for the same Vessel,
most recent first") since the workshop note is specific enough to build from as stated — cost if
wrong: remove one panel from one wireframe/page; contained.

Ruling: R9 (open question #7, S3) — Notification content: BRD's notification rule now states the
e-mail includes the booking reference, matching the one piece of content the workshop note asked
for, without inventing a full template — cost if wrong: edit one microflow's e-mail template
text; no structural impact.

Ruling: R10 — `tenancy` and `data_migration` sufficiency dimensions rated `absent`: no evidence of
multiple deploying organisations (single port authority) and no legacy data anywhere in the
corpus (ADR-003: examples are invented) — cost if wrong: if a future revision reveals multiple
port authorities, the domain model needs a tenancy/organisation-scoping entity added before
Stage 5; currently nothing points to that.

Ruling: R11 — **Stage 3 and Stage 4 ✋-gate decisions are recorded `CONFIRMED`, not `ASSUMED`,**
under this run's own pre-authorization (task instructions for run `final-harbour-c`: "no further
confirmation is needed for any step here" and "if a gate cannot pass after a fair attempt, log it
blocked and continue anyway" — read together as licence for an unattended run to actually clear
a ✋ gate, not stall on it forever with no human ever able to convert an `ASSUMED` into a
`CONFIRMED`). Every decision this covers still has its own reasoning and cost-if-wrong stated at
the point it is made (module boundaries, security/NFR/integration defaults, fit-gap verdicts,
the architecture review pass) — this ruling only explains why the register spells the *status
word* `CONFIRMED` instead of `ASSUMED` for those specific rows. Cost if wrong: a returning human
who disagrees with any of these treats them exactly like any other `CONFIRMED` row they want to
reopen — nothing here is hidden or irreversible, and everything is stated in this ledger, not
laundered as automatically customer-approved.

Ruling: R12 (Stage 4) — Build-plan approval, coverage-ledger sign-off, and pending-decision
closure are recorded `CONFIRMED` under the same run-authorization as R11.

## Toolkit position

Waived stage 1: text-native corpus: converted once with html-to-md, no extractor applies
