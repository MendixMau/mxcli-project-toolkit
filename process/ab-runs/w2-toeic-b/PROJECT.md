# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

Toolkit commit: 5ffbda6

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
| P | Entry mode: Requirements-driven, docs-ready corpus | ASSUMED | TOEIC Buddy HTML/JS + technical guide; no legacy model |
| 0 | Triage: Manual extraction, single monolithic module, no multi-app decomposition | CONFIRMED | Scope and capability ordering validated per triage.md |
| 1 | Analysis: Knowledge base generated from source documents; extraction clean | CONFIRMED | KB_TOEIC_ApplicationRequirements.md created and verified |
| 2 | Requirements: BRD validation-clean; Phase 2 decisions deferred | CONFIRMED | Validation report: 1 BRD, 100% completeness, no SME follow-up needed |
| 3 | Architecture: Monolithic Mendix module TOEICBuddy; Mendix platform fit 100% | CONFIRMED | Module design, architecture blueprint, fit-gap analysis complete |
| 4 | Build Plan: Phase 1 MVP in 4 slices, 85-90 hours, 100% BRD coverage | CONFIRMED | Build plan approved; ready to proceed to Stage 5 (build) |
|---|---|---|---|

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.
