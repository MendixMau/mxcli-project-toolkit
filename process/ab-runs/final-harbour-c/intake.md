# intake.md — Stage P Kickoff Interview

Replace each "_Not yet asked._" line below with a real answer, in one of two forms:

  Answered (CONFIRMED): ...          the question was asked and answered
  Unverified — how to verify: ...    the question WAS asked, the answer is not known yet,
                                     and this line says how it will be established

Both forms pass gate-check's Stage P. "_Not yet asked._" passes nothing, deliberately: this
file is generated before the interview happens, and a scaffold must never be able to certify
an interview that never took place. Per conversion-runbook.md's interview protocol, every
question is asked in chat and the turn ends to wait for the answer; unknowns the user hands
back ("you decide") are recorded as ASSUMED in PROJECT.md rather than blocking Stage P.

**Run identifier: final-harbour-c — Interview mode: unattended** (see PROJECT.md). Nobody is
available to answer in chat; per conversion-runbook.md §1 "Unattended mode" every question below
was still posed (in the session transcript) before being answered, and each answer is recorded
`ASSUMED` in PROJECT.md's Rulings ledger with a cost-if-wrong, never silently defaulted.

## 1. Entry mode: migration, requirements-driven, or greenfield?

Answered (ASSUMED): **Requirements-driven, docs-ready corpus.** Evidence: `sources/` holds 36
saved-webpage HTML pages (with `_files/` sidecars) and 4 Markdown files, no legacy application
code, no `.docx`/`.pptx`/`.pdf` containers — the exact trigger for
conversion-runbook.md's "Requirements-driven, docs-ready corpus" fast path. Consented by: nobody
(unattended); cost if wrong: the whole pipeline shape (Stage 1 waiver, thin BRD transform) would
need to be redone under ordinary requirements-driven or migration rules.

## 2. What is this project, and what is driving it?

Answered (ASSUMED): (c) Production replacement, open-ended — no hard date or licence-expiry
signal anywhere in the corpus (ADR log and workshop notes read as an in-progress functional spec,
not a cutover deadline). Cost if wrong: Stage 3/4 fidelity and effort trade-offs may be tuned for
the wrong urgency; low cost to revisit since no build has started.

## 3. Fidelity: port as-is, or improve as we go?

Answered (ASSUMED): Port the documented behaviour faithfully; do not invent capabilities beyond
what a chapter, workshop note or screenshot states. Where the source itself conflicts (see the
four contradictions logged in `analysis/source-sufficiency.json` / CAC-1 below), record an
explicit resolution as its own decision rather than silently picking one side. Cost if wrong: a
"faithful port" reading might under-deliver against an implicit modernisation expectation; low
cost, reversible at Stage 3.

## 4. Scope boundary: the whole application, or a slice?

Answered (ASSUMED): Whole documented application (booking request → officer review → tariffs/
invoicing → inspections → departure clearance → audit/reporting), explicitly EXCLUDING pilotage
and tug scheduling (ch04 "Vision and scope": "Pilotage and tug scheduling are out of scope and
remain in the existing marine operations system."). Build-plan ORDERING (Stage 4) sequences this
into phases; nothing documented is dropped. Cost if wrong: low — a slice is an ordering, not an
exclusion, so a re-priority is a build-plan edit, not a rescoping.

## 5. What must NOT change?

Answered (ASSUMED): The booking reference format `HB-YYYY-NNNNN`, permanent even after
cancellation (ADR-004); the AIS feed's 5-minute poll / geofence-arrival semantics as far as they
are documented (ch33); the tariff/VAT/invoice due-date arithmetic (21% VAT, 30-day due, Overdue
the day after — ADR-006). Cost if wrong: these are exactly the numbers a Mendix build would
otherwise have to invent; getting one wrong is a rework of one microflow, not a redesign.

## 6. Are there licence/security constraints on storing this client's source in this workspace?

Answered (ASSUMED): None — the corpus is fictional throughout (ADR-003: "All examples use
invented vessel names, agents and people"; `sources/27-privacy-and-cookies.html`: "The
documentation export contains no personal data"). Cost if wrong: negligible; there is no real
client behind this fixture.

## 7. Is an SME available — who, and at what cadence?

Answered (ASSUMED): No SME available this run (unattended mode, run identifier
`final-harbour-c`). Every `openQuestions`/contradiction/shape-changing-gap this run could not
resolve from the source is logged (source-sufficiency `conflicts`/`choices`, and PROJECT.md's
Open questions table) for a human to answer later rather than silently guessed. Cost if wrong:
the four contradictions and three shape-changing gaps carry through the BRDs as recorded
`ASSUMED` positions until a real SME overturns them.

## 8. Anything else — scope, priorities, or worries?

Answered (ASSUMED): Nothing beyond what the source-sufficiency report already surfaced (4
contradictions, 3 shape-changing gaps, 2 dimensions with no source coverage — `tenancy` and
`data_migration`, both `absent` for a plausible reason: single deployment, fictional data only).

## 9. Interview mode: attended (default) or unattended?

Answered (CONFIRMED): **Unattended** — set at the run's authorization (run identifier
`final-harbour-c`); recorded in PROJECT.md's `Interview mode:` line.

## 10. Is any of this already done outside the toolkit — and where does the pipeline pick up?

Answered (CONFIRMED): Starting from scratch here — nothing adopted, nothing waived at the
project level. (Stage 1's extraction-report gate IS waived by name, per the docs-ready path —
see PROJECT.md Decisions and `triage.md`.)
