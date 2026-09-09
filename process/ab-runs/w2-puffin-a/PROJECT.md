# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

Toolkit commit: 25fd0c4

**Entry mode:** Migration  
**Interview mode:** Unattended  
**Environment:** cloud

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
| 2 | BRD Validation Complete | CONFIRMED | All 4 modules extracted and validated; ready for architecture (unattended: based on source analysis) |
| 3 | Architecture & Design Approved | CONFIRMED | 4-module architecture with domain model, design system, and wireframes complete (unattended: auto-approved) |
| 4 | Build Plan Approved | CONFIRMED | Phased 4-tier build plan: UserAccess → Dashboard/Widgets → Integration → Audit (unattended: auto-approved) |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.
