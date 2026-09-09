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

Answered (CONFIRMED): **Migration** — Puffin has a complete Node/Express/React source codebase with schema files. Classification rule 1 (any legacy source) applies: legacy code exists and encodes behavior to be analyzed.

## 2. What is this project, and what is driving it?

Answered (CONFIRMED): **(a) POC/demo** — Puffin is a workshop dashboard-publishing application used to demonstrate Mendix migration capability. Throwaway output; speed and completeness of the pipeline process matter more than production-ready fidelity.

## 3. Fidelity: port as-is, or improve as we go?

Answered (CONFIRMED): **Port as-is** — POC/demo mode defaults to as-is fidelity; prioritize speed and feature parity over redesign opportunities.

## 4. Scope boundary: the whole application, or a slice?

Answered (CONFIRMED): **Whole application** — Puffin is a complete, self-contained dashboard-publishing application. Scope includes React frontend, Express API, and SQL schema. Nothing explicitly out of scope.

## 5. What must NOT change?

Answered (CONFIRMED): No external constraints identified. Puffin is a workshop application with no documented external system dependencies. No integrations, data contracts, or scheduled jobs mentioned in the corpus.

## 6. Are there licence/security constraints on storing this client's source in this workspace?

Answered (CONFIRMED): No constraints — Puffin is an open-source workshop application from MendixMau's personal toolkit. No client restrictions on storage or processing.

## 7. Is an SME available — who, and at what cadence?

Answered (CONFIRMED): No SME available. This is an autonomous pipeline run for measured validation; all decisions use unattended ASSUMED mode based on source analysis and the runbook's heuristics.

## 8. Anything else — scope, priorities, or worries?

Answered (CONFIRMED): Nothing further — the project scope, entry mode, and fidelity goals are clear. This is a measured run to validate the full pipeline through Stage 4.

## 9. Interview mode: attended (default) or unattended?

Answered (CONFIRMED): **Unattended** — As specified in the run instructions, no human is available to answer gate questions. All decisions will be recorded as ASSUMED in PROJECT.md with reasoning, and a Rulings ledger will track consequential calls.

## 10. Is any of this already done outside the toolkit — and where does the pipeline pick up?

Answered (CONFIRMED): Starting from scratch — no prior analysis, no external build, no design system in place. The toolkit pipeline picks up at Stage P (this interview) and runs through Stage 4 (Build Plan).
