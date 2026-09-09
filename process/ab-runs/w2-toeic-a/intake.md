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

Answered (CONFIRMED): Migration — source is a self-contained HTML/JS application (TOEIC Buddy) with supporting technical documentation (Markdown). Classification rule 1 applies: any legacy source code exists.

## 2. What is this project, and what is driving it?

Answered (ASSUMED): POC/demo — Mendix migration assessment run: convert TOEIC Buddy (a self-contained learning application) to a Mendix baseline model to demonstrate feasibility of the mxcli conversion pipeline on a modern HTML/JS single-page app. Speed and pipeline validation are primary; completeness secondary.

## 3. Fidelity: port as-is, or improve as we go?

Answered (ASSUMED): Port as-is. As a POC, the goal is faithful mechanical translation; improvements are descoped. Architecture and UI should maintain the original's structure and look-and-feel.

## 4. Scope boundary: the whole application, or a slice?

Answered (ASSUMED): Whole application. TOEIC Buddy is self-contained: no external dependencies, integrations, or data sources beyond the app's local state. Scope includes all lessons, quiz logic, scoring, progress tracking, and UI.

## 5. What must NOT change?

Answered (ASSUMED): User quiz workflow and scoring logic. The learning experience (lesson progression, question presentation, answer validation, score calculation) must be mechanically equivalent to the original.

## 6. Are there licence/security constraints on storing this client's source in this workspace?

Answered (ASSUMED): No. TOEIC Buddy is an open-source POC learning app; no confidential data, credentials, or third-party intellectual property constraints.

## 7. Is an SME available — who, and at what cadence?

Answered (ASSUMED): No live SME. The technical guide (Markdown) is the single source of truth for semantics and behavior. Decisions from the source docs take precedence.

## 8. Anything else — scope, priorities, or worries?

Answered (ASSUMED): Nothing further. This is an assessment run; all decisions are procedural (following the stage gates). The output is the stage-4 artifacts: architecture, design system, module brief, and build plan.

## 9. Interview mode: attended (default) or unattended?

Answered (CONFIRMED): Unattended — autonomous assessment run w2-toeic-a, no human gate interaction.

## 10. Is any of this already done outside the toolkit — and where does the pipeline pick up?

Answered (ASSUMED): Starting from scratch here. No prior analysis, architecture, or design system exists. The toolkit pipeline starts at Stage P and runs through Stage 4 only (no Stage 5 model build).
