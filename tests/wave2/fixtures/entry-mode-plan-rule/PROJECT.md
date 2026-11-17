# PROJECT.md — Fixture Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage P — Kickoff**, needs attention — gates passed: none yet (derived by gate-check on 2026-11-17; re-run it rather than editing this line).

Toolkit commit: ff4103b
Exec approval: auto
Permission profile: project
Unit tests default: no
Gate mode: check
Pipeline mode: balanced
Build type: full

<!-- Build type (intake Q16, asked FIRST at kickoff; this line is only the default until it is answered; no line = full): full | poc. poc = skills/poc-build.md. -->

<!-- Pipeline mode (intake Q15; no line = balanced): high-speed = per row the exec gate only;
     balanced = plus one LOOK at 1280 of a changed page; high-quality = journeys + LOOK at 390 and
     1280 and unit tests per row. All three run journeys and the polish loop at module close
     (skills/iterative-build-loop.md § Pipeline mode). -->

<!-- Gate mode: check (the default, also without this line) = bin/exec.sh runs `mx check` per
     script and the full mxbuild at module close (every push in the high-quality pipeline mode)
     and when Java/theme files change (mxcli's own advice). `Gate mode: full` = a full mxbuild on every exec. -->

<!-- Bug filing: auto — take this line out of the comment to let agents post this project's open
     toolkit/mxcli bugs (docs/bugs.jsonl) as public GitHub issues with your own gh login, redacted and
     deny-list checked, without a y/N per bug (bin/file-bugs.sh --auto). Left commented, a human files. -->

<!-- The bold line above is a READOUT: bin/gate-check.sh rewrites it on every full run from the
     verdicts it just produced (first stage neither PASS nor WAIVED). Do not edit it by hand.
     Where this project joins the pipeline: nothing recorded, so it starts at Stage P — the
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

## Change log

Feedback and change requests, one row each, written BEFORE any edit (`skills/change-intake.md`). Status: open → refined → agreed → applied → proven, or rejected (reason); Closed-by cites the commit, journey or test. Escape a `|` inside the ask as `\|`.

| CR | Date | Source | Verbatim ask | Class | Size | Entry artifact | Status | Closed-by |
|---|---|---|---|---|---|---|---|---|

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.
