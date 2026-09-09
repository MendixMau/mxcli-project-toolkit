# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

Toolkit commit: 5ffbda6

Entry mode: requirements-driven, docs-ready corpus
Interview mode: unattended
Environment: cloud

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
| P | Entry mode: requirements-driven, docs-ready corpus | CONFIRMED | Corpus is 36 HTML pages + `_files/` sidecars + 4 .md files, no legacy code — matches Entry Modes rule 2 and the docs-ready trigger |
| P | Interview mode: unattended | CONFIRMED | Explicitly requested for this run; no human available to answer gate questions |
| P | What's driving this project: (c) production replacement, open-ended | ASSUMED | No stated deadline in the corpus; full requirements set reads as a from-scratch build, not a POC |
| P | Fidelity: follow the written spec, flag contradictions as open questions | ASSUMED | Requirements-driven — no legacy system to port "as-is" from |
| P | Scope: whole application per the 36-page corpus | ASSUMED | Revisited at Stage 0 CAC-1 scope brainstorm against effort signals |
| P | Licence/security constraints: none | CONFIRMED | Synthetic corpus, no real client data (tests/ab/README.md) |
| P | SME available: no | CONFIRMED | Unattended run |
| P | Prior work outside toolkit: none, starting at Stage P | CONFIRMED | — |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.

## Rulings (unattended)

Ruling: Entry mode = requirements-driven, docs-ready corpus — 36 HTML + 4 MD, no code in sources/ — cost if wrong: whole pipeline mis-sequenced (skips/runs wrong stages)
Ruling: Project driver = production replacement, open-ended (no deadline signal in corpus) — cost if wrong: Stage 0 scope brainstorm assumes full-build pacing instead of POC pacing
Ruling: Fidelity = follow spec as stated, flag contradictions rather than resolve them silently — cost if wrong: a Stage 3 fit-gap finding is mistreated as a gap instead of a flagged improvement opportunity
Ruling: Scope = whole application (all 36 pages) — cost if wrong: Stage 4 build plan includes a capability that should have been deferred
Ruling: Source sufficiency = OUTLINE band, 60% build-ready, 3 real contradictions found (not silently resolved) — interview mode set to `steering` per bin/interview-mode.sh — cost if wrong: n/a, this is a measurement not a decision
Ruling (contradiction 1/3): Fast-track auto-approval (08-booking-lifecycle.html §4.4) vs "no automatic approval, manual review only" (15-officer-review-process.html §11.4) — ASSUMED: manual review governs (ch15's unhedged negation); ch8's Fast-track section is read as expedited QUEUE PRIORITY, not a bypass of officer review — cost if wrong: an auto-approval microflow is missing from the build, and every booking needs officer action even when it need not
Ruling (contradiction 2/3): Surcharge waiver authority — "only the Harbour Master" (13-berth-allocation-rules.html §9.3) vs "a berth officer may waive the late-arrival surcharge for vessels <80m" (24-inspection-outcomes.html §20.3) — ASSUMED: the specific rule (ch24) is a scoped exception to the general one (ch13) — Berth Officers may waive only the late-arrival surcharge for vessels under 80m; every other surcharge still requires the Harbour Master — cost if wrong: the security matrix grants a waiver permission to the wrong role
Ruling (contradiction 3/3): Cancellation fee window — "free until 24h before ETA" (10-cancellation-and-changes.html §6.2) vs "within 72h of ETA charged 50%" (19-tariffs-cancellation-fees.html §15.2) overlap in the 24-72h band — ASSUMED: the specific fee schedule (ch19) governs the overlap — free only when cancelled more than 72h before ETA, 50% charged from 72h down to ETA; ch10's "24 hours" is treated as an imprecise restatement — cost if wrong: cancellation fee microflow over/under-charges agents in the 24-72h window
Ruling: 3 hidden requirements found only in workshop-notes.md (raw, uncleaned per ADR-007), not reflected in any numbered chapter — carried into BRDs as open questions rather than silently added to scope: (a) agents must be able to attach a cargo manifest PDF to a booking request, attachment size limit undecided; (b) e-mail notifications must include the booking reference; (c) the officer review screen must show the vessel's last five bookings — cost if wrong: build omits a feature the actual stakeholders asked for in workshop, or adds scope nobody signed off on

## Toolkit position

Waived stage 1: text-native corpus: converted once with html-to-md, no extractor applies
