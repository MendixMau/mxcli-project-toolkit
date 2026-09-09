# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

Toolkit commit: 25fd0c4

**Interview mode: unattended** — autonomous assessment run w2-toeic-a, no human gate interaction.
**Environment: cloud** — ephemeral container, commit and push at every gate.

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
| P | Entry mode: Migration | CONFIRMED | TOEIC Buddy is self-contained HTML/JS source (classification rule 1) — no SME, technical guide is single source of truth |
| P | Project scope: POC/demo assessment | ASSUMED | Mendix conversion pipeline validation; speed over completeness; mechanical port, no improvements |
| P | Fidelity: port as-is | ASSUMED | As a POC, faithful translation of original structure and look-and-feel |
| P | Scope: whole application | ASSUMED | TOEIC Buddy is self-contained; includes lessons, quiz logic, scoring, progress tracking |
| P | Must NOT change: quiz workflow and scoring | ASSUMED | Learning experience (progression, presentation, validation, calculation) must be mechanically equivalent |
| 0 | Extraction approach | ASSUMED | No automated extraction — single HTML/JS file with no structured codebase. Manual BRD generation from source inspection and technical guide. |
| 0 | Capabilities & coverage | ASSUMED | Three manual BRDs: Lesson Navigation, Quiz Engine, User Progress Tracking. All "Manual" verdict. Single app, 1–2 modules. |
| 0 | Scope: whole app, three capabilities in order | ASSUMED | All lesson/quiz/progress features in scope. No multi-app concern. |
| 0 | Triage sign-off | ASSUMED | Scope confirmed by autonomous assessment process, 2026-09-09. |
| 4 | Build plan approval | CONFIRMED | Three-phase build plan (Phases 1-3); 13+34+34=81 total SP; 100% BRD coverage; all use cases claimed. |
| 4 | Module briefs & coverage ledger | CONFIRMED | Module-brief.md with three modules (LessonEngine, QuizEngine, ProgressTracking). Coverage-ledger.md: 23 BRD leaves, 23 claimed, 100%. |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.
