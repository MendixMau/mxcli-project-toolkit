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

Answered (ASSUMED): Requirements-driven, docs-ready corpus. Source: TOEIC Buddy (toeic-buddy.html + TOEIC-BUDDY-GUIDE.md). The application is a legacy HTML/JS app with comprehensive technical documentation. No existing Mendix model to migrate from. Documentation sufficient for BRD extraction without SME interviews.

## 2. What is this project, and what is driving it?

Answered (ASSUMED): Feasibility proof + modernization. Rebuild TOEIC Buddy (test-prep learning platform) in Mendix to demonstrate platform suitability for interactive educational applications. Combines production replacement intent with opportunity for UX/feature improvements during rebuild.

## 3. Fidelity: port as-is, or improve as we go?

Answered (ASSUMED): Port as-is first (faithful rebuild), then optimize. UI/UX, navigation, and quiz logic ported exactly as designed. Post-launch can include: persistent progress storage, audio features, adaptive difficulty, mobile app.

## 4. Scope boundary: the whole application, or a slice?

Answered (ASSUMED): Complete application. Scope includes all 5 major sections: Home Dashboard, Lessons, Vocabulary Builder, Practice Quiz, Progress Tracking. OUT: Persistence backend (Phase 2), audio playback system (Phase 2), mobile native apps (Phase 2+). Desktop web only for Phase 1.

## 5. What must NOT change?

Answered (ASSUMED): Quiz scoring algorithm, question order determinism, progress calculation (study hours, streak logic, weak area identification), vocabulary item order, lesson content structure. No external integrations exist in legacy app. No backward data compatibility required (greenfield persistence).

## 6. Are there licence/security constraints on storing this client's source in this workspace?

Answered (ASSUMED): No constraints. Application contains only sample educational content (TOEIC exam prep material, public business vocabulary). No PII, no production data, no proprietary algorithms. Source may be committed to the project repository.

## 7. Is an SME available — who, and at what cadence?

Answered (ASSUMED): SME = source code + technical documentation. Legacy app is fully self-documenting (UI code comments, design rationale in TOEIC-BUDDY-GUIDE.md). No external subject matter expert required. Documentation is sufficient for BRD extraction and architecture decisions. Turnaround: immediate (documents at hand).

## 8. Anything else — scope, priorities, or worries?

Answered (ASSUMED): Priority is feature parity (exact rebuild before enhancement). Concern: session persistence not present in original app should be added in Mendix (user data loss on refresh is poor UX). Consider data model design early to support future phases (audio, mobile, analytics).

## 9. Interview mode: attended (default) or unattended?

Answered (CONFIRMED): unattended. This is a measured autonomous run (w2-toeic-b). All gate questions answered per conversion-runbook unattended rules. Decisions logged as ASSUMED and recorded in PROJECT.md for post-run reconciliation.

## 10. Is any of this already done outside the toolkit — and where does the pipeline pick up?

Answered (CONFIRMED): Starting from scratch here. No prior analysis, no existing Mendix model, no design system. All work (Stage P through Stage 6) conducted within this toolkit instance. Source capture is complete (toeic-buddy.html + documentation).
