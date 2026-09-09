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

Answered (ASSUMED): requirements-driven — corpus contains 36 HTML requirement pages (01-36-*.html) with supporting Markdown files (README, decisions-log, glossary, roles, workshop-notes); text-native, no legacy code. Runbook classification rule 2: "any requirements artifacts exist" → requirements-driven.

## 2. What is this project, and what is driving it?

Answered (ASSUMED): Production replacement, open-ended modernisation — "Harbour Berth Booking" system (per corpus README). Full platform modernisation with Mendix, scope to improve as we go.

## 3. Fidelity: port as-is, or improve as we go?

Answered (ASSUMED): Improve as we go — inherited from Q2 (production replacement, open-ended).

## 4. Scope boundary: the whole application, or a slice?

Answered (ASSUMED): Whole application — Harbour Berth Booking system as completely described in the requirements corpus (booking lifecycle, vessel registry, officer review, tariffs, invoicing, inspection, compliance, audit, reporting, integrations). No external system dependencies identified as out-of-scope.

## 5. What must NOT change?

Answered (ASSUMED): External integrations (AIS feed integration per requirements). Data contracts with vessel registry and tariff systems. Notification delivery contracts. Audit/compliance reporting contracts to external systems. These are identified in requirements documents 33 (AIS integration), 20 (invoicing), 17 (notifications), 26 (audit/compliance).

## 6. Are there licence/security constraints on storing this client's source in this workspace?

Answered (ASSUMED): No constraints — this is a test/evaluation corpus in an isolated environment. Requirements document covers security framework (35-security-and-access.html) but no proprietary restrictions on analysis.

## 7. Is an SME available — who, and at what cadence?

Answered (ASSUMED): No external SME — requirements fully documented in corpus. Stakeholders and roles defined in document 05 (stakeholders-and-roles.html). Knowledge base extracted from requirements documents serves as SME proxy; no external consultation required for Stage 1–4 work.

## 8. Anything else — scope, priorities, or worries?

Answered (ASSUMED): Complete requirements provided; no gaps or worries identified beyond the corpus scope. Assessment and build proceed on documented requirements as written.

## 9. Interview mode: attended (default) or unattended?

Answered (CONFIRMED): Unattended — as specified in the pipeline task. All gate decisions recorded as ASSUMED with Ruling ledger in PROJECT.md.

## 10. Is any of this already done outside the toolkit — and where does the pipeline pick up?

Answered (ASSUMED): Starting from scratch here. No prior analysis, architecture, or design system. Pipeline begins at Stage P with this corpus as the sole source of requirements.
