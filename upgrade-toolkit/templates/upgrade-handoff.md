# Upgrade completion and human handoff

App: <generic app name and stable app ID>
Run: <run ID and date>
Requested path: <source version to target version, including intermediate targets>
Delivery status: <COMPLETED / COMPLETED WITH HANDOFF / IN PROGRESS / BLOCKED, per target>
Artifact: <local branch, commit and package path>
Owner sign-off: <pending, or decision reference and date>

## Upgrade work completed

Describe the target reached, build and start evidence, module and widget changes, retained modules, and data-preservation
evidence. State any incomplete requested target. Cite local evidence without copying customer data or credentials.

## Bugs found and repaired

| Bug ID | Feature and symptom | Upgrade regression or baseline defect | Fix and commit | Recheck and result | Remaining action |
|---|---|---|---|---|---|
| <stable ID> | <concrete behavior> | <classification and baseline evidence> | <repair, or still open> | <evidence, or not yet rerun> | <none, repair or owner decision> |

List a repeated observation under the existing bug ID. Report accepted exclusions with their scope and decision reference.
Confirmed open bugs stay visible; a missing test does not create a bug.

## Verification performed

| Check or process | Old-app evidence | New-app evidence | Measured result | Coverage and environment limits |
|---|---|---|---|---|
| <check, role and process> | <reference> | <reference> | <PASS / PASS* / FAIL / INVALID / NOT RUN / EXCEPT / PASS (except ...), with reason> | <real service, stand-in, fixture or unavailable prerequisite> |

Include the original overall gate verdict and grade with their scope. Explain confirmed regressions and unmeasured
checks separately. Do not replace missing evidence with a pass or change machine verdicts in this report.
For EXCEPT or PASS (except ...), name the excluded systems and add the real-system closure tests to the handoff below.

## Human checks and decisions

| Action ID | Feature, role and target version | Exact steps and expected result | Attempts and evidence | Why it needs a human or external access | Owner | Closure evidence |
|---|---|---|---|---|---|---|
| <ID> | <specific process> | <reproducible test, or precise decision and recommendation> | <tests, probes and repairs tried> | <specific prerequisite> | <person or team> | <result, screenshot, log or written decision required> |

Write "No remaining human checks" only when justified. Keep owner sign-off pending until supplied. An available test
or feasible toolkit repair belongs in the run's work queue before handoff.

## History and toolkit learnings

Record this run under the existing app ID with its attempted and completed version hops. Give each reusable lesson its
evidence, toolkit change or backlog item, and validation. Keep attempt counts, unique bugs, upgrade delivery,
verification and owner closure separate in the across-session summary.
