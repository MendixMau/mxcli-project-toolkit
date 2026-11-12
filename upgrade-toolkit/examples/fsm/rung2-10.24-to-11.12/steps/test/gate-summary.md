# Gate summary

Overall: **FAIL** (exit 1): 7 PASS/PASS*, 0 EXCEPT, 1 FAIL, 0 INVALID, 1 required NOT RUN.
Grade: 78% (7 of 9 required rungs done): proven 5, accepted 2, waiting on a person 2, not testable here 0, open regression 0 | verdict FAIL
Progress: 7 of 10 checks closed (70%). 0 with REGRESSIONS to fix, 2 need a decision, 1 not measured yet, owner sign-off pending. Proposal not signed.
Changes: 40 (toolkit 29, agent 11, person 0, unlabelled 0)
Change ledger: `<run>/work/rung2/CHANGES.md`
heal: 248 failing row(s) classified, 3 accepted with a written reason, 0 journey(s) pass after the heal, 0 stay open (0 real-regression, 0 likely-real); classes: startup-noise 3, no-click-path 2, test-setup 243 (details: `<run>/work/rung2/heal.md`)
Classes: build=closed idcheck=closed const=closed data=closed rest=none logdiff=closed smoke=closed journeys=decision screens=closed release=unmeasured apis=none widgets=none trail=none
Work: `<run>/work/rung2`, evidence: `<run>/work/rung2`, instruments: `<toolkit>/upgrade-toolkit/bin`, run 20261112153638. 2026-11-12T15:38Z

proposal not signed: <run>/work/rung2/PROPOSAL.md has no Signed-off line, so this verdict is not an owner-approved upgrade (steps/propose.md)

| # | rung | verdict | rc | one line |
|---|---|---|---|---|
| 1 | build | PASS | 0 | BUILD SUCCEEDED and 0 "ERROR at" lines: yes in <run>/work/rung2/build-11.12.7.log |
| 2 | idcheck | PASS | 0 | findings: 2 total, 1 RED (data-bearing), 1 of them approved, 0 open;verdict: PASS  (FAIL = open data-bearing GUID change; REVIEW = open data-bearing removals or persistence loss only: confirm each is  |
| 3 | const | PASS | 0 | FAIL 0 \| REVIEW 0 \| PASS* 0 \| INFO 1 \| PASS 48 |
| 4 | data | PASS* | 0 | INVALID 0 \| FAIL 0 \| REVIEW 0 \| NEW_ENDPOINT 0 \| PASS* 9 \| PASS 622 \| INFO 217 |
| 5 | rest | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys) (optional rung) |
| 6 | logdiff | PASS | 0 | FAIL 0 \| REVIEW 0 \| PASS* 0 \| INFO 0 |
| 7 | smoke | PASS | 0 | steps: PASS 73, FAIL 6, INVALID 0, SKIPPED 15; roles not run (INVALID): 0 |
| 8 | journeys | FAIL | 1 | journeys: 277 PASS, 0 FAIL, 2 INVALID, 243 PASS* (baseline defect), 1 CONTAMINATED (login failed after a destructive journey on the same database), 265 INFO (covered, unreachable or out of scope, list |
| 9 | screens | PASS* | 0 | pairs 79: INVALID 0 \| REVIEW 0 \| PASS* 35 \| PASS 44;screens: 44 PASS, 35 PASS*, 0 REVIEW, 0 INVALID |
| 10 | release | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys) |
| 11 | apis | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys) (optional rung) |
| 12 | widgets | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys) (optional rung) |
| 13 | trail | NOT RUN | - | WARNING: trail: 64 gap(s) in 35 steps. First: S-1 (Review the stand-ins for outside calls) has no change recorded and no note that none was needed. 35 step(s) wait for the owner's OK. (optional rung) |

Report words: PASS = verified; PASS* = verified with accepted differences; FAIL = REGRESSION to fix only when something that passed on the old app fails on the new one, needs a decision when only REVIEW lines are open; INVALID / NOT RUN = not measured yet (or needs a decision when a human item is open).

Not closed, in report words (REGRESSIONS first):
- journeys: needs a decision: journeys: 277 PASS, 0 FAIL, 2 INVALID, 243 PASS* (baseline defect), 1 CONTAMINATED (login failed after a destructive journey on the same database), 265 INFO (covered, unreachable or out of scope, list (steps/decide.md, or the accept file named in the rung's report)
- release: not measured yet: not selected (--only build,idcheck,const,data,logdiff,screens,smoke,journeys)
- notes: needs a decision: journeys 2 INVALID + 1 CONTAMINATED, judged by the upgrading developer 2026-11-12 03:10 (unattended): 0 FAIL, 0 regression, 382 baseline defects with OLD-APP evidence (baseline-evidence.txt). INVALID page:NativeMobile.Login and client_microflow:Synchronization.OfflineAction_ProcessList are native-profile only, unreachable from the web menu; covered by hand on the Android emulator (native-lab: login + Planned list + appointment on 10.24 MiN and on a Mendix 11 native-template build, rec/native-*.mp4). CONTAMINATED role Mechanic~destructive1: login fails after a destructive journey on the shared DB (test artefact, run apart, not in coverage). Owner: confirm, or ask for a separate destructive DB run. (from <run>/work/rung2/gate-notes-effective.txt)

PASS* = accepted in writing (allow or accept file; each reason is in the rung's report). FAIL = an open FAIL or REVIEW.
INVALID = the rung could not judge (instrument rc 2, journeys rc 3, timeout, failed PRE command); it blocks DONE and is never PASS.
NOT RUN = the rung was skipped or its inputs were not given; for a required rung that blocks DONE too.
EXCEPT = the rung's only non-PASS items failed on a call into an excluded system (EXCLUDE_SYSTEMS): NOT CHECKED, listed above; the overall verdict is then PASS (except ...), exit 4, never plain PASS.
PASS (on stand-in APIs: ...) = APIMOCK answered for the listed endpoints; exit 4, never plain PASS: plain PASS needs the real (test) systems.
