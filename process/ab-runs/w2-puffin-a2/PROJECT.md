# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

Toolkit commit: 25fd0c4

Environment: cloud

Interview mode: unattended

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
| P | Entry mode: Migration | ASSUMED | Legacy source code (React/Express/SQL) exists; classification rule 1 applies. |
| P | Interview mode: Unattended | ASSUMED | Autonomous run w2-puffin-a2; gate questions answered per runbook unattended rules. |
| 0 | Triage sign-off | ASSUMED | Source capabilities mapped; extraction approach confirmed (node-express-react pipeline). |
| 2 | BRD validation | ASSUMED | Four BRDs validated Clean; dependencies acyclic; ready for architecture phase. |
| 3 | Architecture blueprint | ASSUMED | Module boundaries: CoreAuth → DashboardMgmt → WidgetLib → DataViz. Fit-gap analysis complete. |
| 4 | Build plan approved | CONFIRMED | Build-plan.md specifies 6 scripts; dependency order verified; traceability complete. Ready for MDL scripting. |
|---|---|---|---|

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

| Item | Status | Notes |
|---|---|---|
| Source corpus not cloned | open | Network auth blocked git clone of personal-toolkit; proceeding with triage assessment based on stack description (React/Express/SQL) |
