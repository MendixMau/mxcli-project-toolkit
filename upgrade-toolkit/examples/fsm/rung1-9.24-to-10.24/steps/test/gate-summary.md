# Gate summary

Overall: **INVALID** (exit 2): 7 PASS/PASS*, 0 EXCEPT, 0 FAIL, 1 INVALID, 1 required NOT RUN.
Grade: 78% (7 of 9 required rungs done): proven 3, accepted 4, waiting on a person 2, not testable here 0, open regression 0 | verdict INVALID
Progress: 7 of 10 checks closed (70%). 0 with REGRESSIONS to fix, 0 need a decision, 2 not measured yet, owner sign-off pending. Proposal not signed.
Changes: 23 (toolkit 18, agent 5, person 0, unlabelled 0)
Change ledger: `<run>/CHANGES.md`
heal: 253 failing row(s) classified, 6 accepted with a written reason, 3 journey(s) pass after the heal, 0 stay open (0 real-regression, 0 likely-real); classes: startup-noise 4, no-click-path 5, test-setup 244 (details: `<run>/heal.md`)
Classes: build=closed idcheck=closed const=closed data=closed rest=none logdiff=closed smoke=closed journeys=unmeasured screens=closed release=unmeasured apis=none widgets=none trail=none
Work: `<run>`, evidence: `<run>`, instruments: `<toolkit>/bin`, run 20261111081016. 2026-11-11T08:12Z
Time: fetch 7s, triage 2m, baseline 7m, basewalk 2h24m, propose 24m, convert 1m, update 12m, build 26m, after 46s, afterwalk 8m, journeys 11h59m, heal 10m, apidirect 2s, diff 8m; machine 16h2m; person wait 59m

proposal not signed: <run>/PROPOSAL.md has no Signed-off line, so this verdict is not an owner-approved upgrade (steps/propose.md)

| # | rung | verdict | rc | one line |
|---|---|---|---|---|
| 1 | build | PASS | 0 | BUILD SUCCEEDED and 0 "ERROR at" lines: yes in <run>/build-10.24.28.129343.log |
| 2 | idcheck | PASS | 0 | findings: 7 total, 4 RED (data-bearing), 4 of them approved, 0 open;verdict: PASS  (FAIL = open data-bearing GUID change; REVIEW = open data-bearing removals or persistence loss only: confirm each is  |
| 3 | const | PASS* | 0 | FAIL 0 \| REVIEW 0 \| PASS* 1 \| INFO 2 \| PASS 46 |
| 4 | data | PASS* | 0 | INVALID 0 \| FAIL 0 \| REVIEW 0 \| NEW_ENDPOINT 0 \| PASS* 17 \| PASS 619 \| INFO 205 |
| 5 | rest | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys) (optional rung) |
| 6 | logdiff | PASS* | 0 | FAIL 0 \| REVIEW 0 \| PASS* 4 \| INFO 0 |
| 7 | smoke | PASS | 0 | steps: PASS 73, FAIL 6, INVALID 0, SKIPPED 15; roles not run (INVALID): 0 |
| 8 | journeys | INVALID | 3 | INVALID only (exit 3): no REGRESSION, no open REVIEW; 6 journeys INVALID, 13 SCREEN INVALID, 0 failing on the baseline, 0 EFFECT INVALID, 1 coverage rules broken (the 'coverage INVALID' lines above); coverage INVALID: instrument not measuring: 231 of 454 actions fail on the baseline (50% > 30%); actions 730 found · 454 generated (3 todo: page-parameter 3) · 223 pass on baseline (231 defect) · 223 pass on new · 0 regression · coverage 223/457 (48%) · 14 destructive run apart (own line) · 259 out of scope, INFO (marketplace-module 14, no-role 27, unreachable 218) |
| 9 | screens | PASS* | 0 | pairs 79: INVALID 0 \| REVIEW 0 \| PASS* 8 \| PASS 71;screens: 71 PASS, 8 PASS*, 0 REVIEW, 0 INVALID |
| 10 | release | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys) |
| 11 | apis | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys) (optional rung) |
| 12 | widgets | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys) (optional rung) |
| 13 | trail | NOT RUN | - | WARNING: trail: 29 gap(s) in 16 steps. First: S-1 (Review the stand-ins for outside calls) has no change recorded and no note that none was needed. 16 step(s) wait for the owner's OK. (optional rung) |

Report words: PASS = verified; PASS* = verified with accepted differences; FAIL = REGRESSION to fix only when something that passed on the old app fails on the new one, needs a decision when only REVIEW lines are open; INVALID / NOT RUN = not measured yet (or needs a decision when a human item is open).

Not closed, in report words (REGRESSIONS first):
- journeys: not measured yet: INVALID only (exit 3): no REGRESSION, no open REVIEW; 6 journeys INVALID, 13 SCREEN INVALID, 0 failing on the baseline, 0 EFFECT INVALID, 1 coverage rules broken (the 'coverage INVALID' lines above); coverage INVALID: instrument not measuring: 231 of 454 actions fail on the baseline (50% > 30%); actions 730 found · 454 generated (3 todo: page-parameter 3) · 223 pass on baseline (231 defect) · 223 pass on new · 0 regression · coverage 223/457 (48%) · 14 destructive run apart (own line) · 259 out of scope, INFO (marketplace-module 14, no-role 27, unreachable 218)
- release: not measured yet: not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys)

PASS* = accepted in writing (allow or accept file; each reason is in the rung's report). FAIL = an open FAIL or REVIEW.
INVALID = the rung could not judge (instrument rc 2, journeys rc 3, timeout, failed PRE command); it blocks DONE and is never PASS.
NOT RUN = the rung was skipped or its inputs were not given; for a required rung that blocks DONE too.
EXCEPT = the rung's only non-PASS items failed on a call into an excluded system (EXCLUDE_SYSTEMS): NOT CHECKED, listed above; the overall verdict is then PASS (except ...), exit 4, never plain PASS.
PASS (on stand-in APIs: ...) = APIMOCK answered for the listed endpoints; exit 4, never plain PASS: plain PASS needs the real (test) systems.
