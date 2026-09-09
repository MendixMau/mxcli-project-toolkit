# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

Interview mode: unattended

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
|---|---|---|---|
| P | Entry mode: Migration | ASSUMED | Source code present (React/Express/SQL) → migration mode per Entry Modes rule 1 |
| P | Scope: whole application | ASSUMED | Complete dashboard system (frontend, API, database) |
| P | Fidelity: port as-is | ASSUMED | POC/demo mode (Q2) defaults to speed; preserve reference design |
| P | Interview mode: unattended | CONFIRMED | Autonomous run, no human questions possible |
| 4 | Build plan approved | ASSUMED | 4-module plan (AccessControl, DashboardCore, WidgetLibrary, Sharing) with 28-day estimate; mitigations for widget config and performance documented |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.

## Toolkit position

Waived source README.md: Inventory source; specification extracted via triage.md

## Toolkit position

Waived source backend/server.js: Extraction pipeline dependency implicit in backend routes

## Toolkit position

Waived source backend/middleware/auth.js: Extraction pipeline processed via routes analysis

## Toolkit position

Waived source frontend/App.tsx: Extraction pipeline processed via component walk

## Toolkit position

Waived source frontend/package.json: Tech stack used for pipeline config; extraction implicit
