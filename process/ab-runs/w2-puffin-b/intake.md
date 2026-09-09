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

Answered (ASSUMED): **Migration**. 

Rationale: Corpus contains legacy source code (React frontend, Express API, SQL schema) encoding application behavior to migrate to Mendix. Classification rule 1 applies: any legacy source code → migration. This is the analyzable source for extraction stages.

## 2. What is this project, and what is driving it?

Answered (ASSUMED): **(a) POC/demo — prove feasibility, speed over completeness**.

Rationale: Puffin is a workshop example application (Thai-No-Code corpus). No production date or urgency signals present in source. This is a proof-of-concept migration to test extraction and build procedures on a Node/Express/React stack.

## 3. Fidelity: port as-is, or improve as we go?

Answered (ASSUMED): **Port as-is**.

Rationale: Q2 is POC/demo mode (a), which defaults to speed over improvement. Puffin is a workshop reference implementation; preserve its design and behavior as-is during migration.

## 4. Scope boundary: the whole application, or a slice?

Answered (ASSUMED): **Whole application**.

Rationale: Puffin corpus includes complete dashboard publishing system: React frontend, Express REST API, PostgreSQL schema. All three tiers are present and in scope. Nothing explicitly out.

## 5. What must NOT change?

Answered (ASSUMED): **Core dashboard CRUD operations, user authentication, role-based access control, data persistence semantics**.

Rationale: Puffin is a workshop app with no documented external dependencies. Architecture focuses on core functionality: dashboard creation/editing/publishing, user authentication, permission management. No integrations, scheduled jobs, or external data contracts visible in source.

## 6. Are there licence/security constraints on storing this client's source in this workspace?

Answered (ASSUMED): **No constraints**.

Rationale: Puffin is a public workshop example from MendixMau/personal-toolkit, designed for educational use. No client IP, no export control, no licence restrictions on analysis or storage.

## 7. Is an SME available — who, and at what cadence?

Answered (ASSUMED): **N/A — no SME available**.

Rationale: Puffin is a workshop reference implementation. No product owner, business analyst, or domain expert is available to provide clarification on business rules or intent beyond what is in the source code and README. Stage 1 Path C (SME interview) will be marked N/A.

## 8. Anything else — scope, priorities, or worries?

Answered (ASSUMED): **Nothing further**.

Rationale: Workshop POC with clear scope. No additional priorities or concerns beyond standard extraction and validation procedures.

## 9. Interview mode: attended (default) or unattended?

Answered (CONFIRMED): **Unattended**.

Rationale: Autonomous pipeline run (w2-puffin-b): no human available to answer gate questions. Recommended defaults applied as ASSUMED per conversion-runbook.md unattended rules.

## 10. Is any of this already done outside the toolkit — and where does the pipeline pick up?

Answered (CONFIRMED): **Starting from scratch here**.

Rationale: Puffin source is being analyzed for the first time in this run. No prior extraction, design, or build plan exists. Pipeline starts at Stage P and proceeds through all applicable stages.
