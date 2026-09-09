# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, in progress.

Interview mode: unattended

Entry mode: requirements-driven

Toolkit commit: 25fd0c4

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
| P | Entry mode: requirements-driven | ASSUMED | Corpus contains 36 HTML requirement pages, no source code. Classification: specs/BRDs exist, no legacy source → requirements-driven |
| P | Interview mode: unattended | ASSUMED | Autonomous run, no user availability for real-time gate questions |
| P | Project scope: full application (Harbour Berth Booking) | ASSUMED | Complete system from specs, no explicit out-of-scope sections |
| P | Fidelity: improve as we go | ASSUMED | Open-ended modernisation licenses fit-gap opportunities |
| 4 | Build plan: 8-week delivery, 2 slices, MVP pilot Week 4 | ASSUMED | Slice 1 core booking (4 weeks), Slice 2 enhancements (4 weeks) |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Rulings (unattended)

- Ruling: Entry mode = requirements-driven — 36 HTML specs, no legacy code — cost if wrong: skipped Stage 1 Path A extraction
- Ruling: Interview mode unattended — autonomous run with no user for gate questions — cost if wrong: ASSUMED decisions not reviewed
- Ruling: Full app scope — all 36 requirement pages in corpus, nothing explicit out — cost if wrong: Stage 4 build plan underscopes
- Ruling: Improve as we go — modernisation goal allows fit-gap opportunities — cost if wrong: late rework of design choices

## Assumptions (ASSUMED, unresolved)

None yet.
