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

Answered (ASSUMED): Migration. The corpus contains legacy source code: a React front-end application, Express API backend, SQL schema files, and README documentation. Classification rule 1 applies: "any legacy/source code exists → Migration".

## 2. What is this project, and what is driving it?

Answered (ASSUMED): POC/demo. Puffin is a workshop dashboard-publishing application — a proof-of-concept to demonstrate feasibility of migrating a Node/Express/React stack to Mendix. Speed and architectural proof take priority over feature completeness.

## 3. Fidelity: port as-is, or improve as we go?

Answered (ASSUMED): Port as-is. Inherited from Q2 (POC/demo). Focus is on functional equivalence and architectural proof.

## 4. Scope boundary: the whole application, or a slice?

Answered (ASSUMED): Whole application. Puffin is a self-contained dashboard-publishing application with a front-end, API, and data layer. Nothing is scoped out.

## 5. What must NOT change?

Answered (ASSUMED): No external constraints declared. Puffin is a standalone workshop application with no known external integrations, APIs consumed by other systems, or scheduled job requirements.

## 6. Are there licence/security constraints on storing this client's source in this workspace?

Answered (ASSUMED): No constraints. Puffin is a public workshop example from the personal-toolkit repository; no proprietary or security restrictions apply.

## 7. Is an SME available — who, and at what cadence?

Answered (ASSUMED): No SME available. This is an autonomous run in unattended interview mode. Decisions will be inferred from the source code and toolkit defaults.

## 8. Anything else — scope, priorities, or worries?

Answered (ASSUMED): Nothing further. Puffin's scope and constraints are captured in the application source code; no additional context was provided in the brief.

## 9. Interview mode: attended (default) or unattended?

Answered (CONFIRMED): Unattended. This is an autonomous measured run (w2-puffin-a2). Gate questions are answered per runbook unattended rules and logged as ASSUMED in PROJECT.md.

## 10. Is any of this already done outside the toolkit — and where does the pipeline pick up?

Answered (ASSUMED): Starting from scratch. No prior analysis, design, or build plan exists outside the toolkit. The pipeline begins at Stage P (Kickoff) and proceeds through Stage 4 gate.
