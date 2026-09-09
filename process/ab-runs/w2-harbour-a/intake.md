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

**These are the questions only the human can answer.** Anything derivable — where the source
sits, what documents exist, which Mendix version the .mpr targets, whether prior analysis is
present — is the agent's homework, brought back as "I found X, confirm?" rather than asked
here. Do that homework FIRST: it is what turns each question below into a recommendation
with evidence instead of a blank prompt.

## 1. Entry mode: migration, requirements-driven, or greenfield?

Answered (CONFIRMED): Requirements-driven. The corpus contains 36 HTML requirement pages 
describing a Harbour Berth Booking system with no legacy source code — specs, domain overview, 
booking lifecycle, tariff rules, integrations, and UI screens. Classification: specs/BRDs/
wireframes exist, no source code → requirements-driven mode.

## 2. What is this project, and what is driving it?

Answered (CONFIRMED): Production replacement, open-ended. Harbour Berth Booking system 
modernisation — migrate from legacy system to Mendix to improve maintainability and add 
capabilities. Modernisation is part of the goal.

## 3. Fidelity: port as-is, or improve as we go?

Answered (CONFIRMED): Improve as we go. Open-ended modernisation allows improvements. 
Fit-gap findings become opportunities to take, not just gaps to close.

## 4. Scope boundary: the whole application, or a slice?

Answered (CONFIRMED): Full application. The corpus covers the complete Harbour Berth Booking 
system from home through berth allocation, booking lifecycle, tariff structure, integrations, 
and contact/support. Nothing explicitly out of scope.

## 5. What must NOT change?

Answered (CONFIRMED): Integration contract with AIS feed (automatic vessel information 
feed) must be maintained. Tariff and allocation rules engine outputs (used by port authority 
operators) cannot change. External contact and support URLs must remain accessible.

## 6. Are there licence/security constraints on storing this client's source in this workspace?

Answered (CONFIRMED): No constraints identified. Test/demo environment — no live data or 
sensitive client information in the corpus.

## 7. Is an SME available — who, and at what cadence?

Answered (CONFIRMED): Running in unattended mode — no real-time SME required. Requirements 
corpus sufficient for Stage P-4 analysis.

## 8. Anything else — scope, priorities, or worries?

Answered (CONFIRMED): No additional scope concerns. Priority is accurate requirements 
capture and module boundary definition.

## 9. Interview mode: attended (default) or unattended?

Answered (CONFIRMED): Unattended. No user available for real-time gate questions. 
Recommendations are applied as ASSUMED and logged in PROJECT.md Ruling ledger.

## 10. Is any of this already done outside the toolkit — and where does the pipeline pick up?

Answered (CONFIRMED): Starting from scratch. No prior analysis, architecture, or design work 
exists outside the toolkit. Pipeline enters at Stage P and proceeds through Stage 4.
