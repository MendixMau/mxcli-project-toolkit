# Gate summary

Overall: **FAIL** (exit 1): 5 PASS/PASS*, 0 EXCEPT, 2 FAIL, 0 INVALID, 2 required NOT RUN.
Grade: 56% (5 of 9 required rungs done): proven 3, accepted 2, waiting on a person 3, not testable here 0, open regression 1 | verdict FAIL
Progress: 5 of 10 checks closed (50%). 1 with REGRESSIONS to fix, 1 need a decision, 2 not measured yet, owner sign-off pending.
Classes: build=closed idcheck=closed const=closed data=closed rest=none logdiff=closed smoke=unmeasured journeys=regression screens=decision release=unmeasured apis=none widgets=none
Changes: 16 (toolkit 13, agent 2, person 0, unlabelled 1)
Change ledger: `/tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/night/druns/APPR/work/CHANGES.md`
Work: `/tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/night/druns/APPR/work`, evidence: `/tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/night/druns/APPR/work`, instruments: `/tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/night/drive/upgrade-toolkit/bin`, run 20261023054240. 2026-10-23T05:42Z

| # | rung | verdict | rc | one line |
|---|---|---|---|---|
| 1 | build | PASS | 0 | BUILD SUCCEEDED and 0 "ERROR at" lines: yes in /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/night/druns/APPR/work/build-10.24.0.73019.log |
| 2 | idcheck | PASS | 0 | findings: 14 total, 7 RED (data-bearing), 7 of them approved, 0 open;verdict: PASS  (FAIL = open data-bearing GUID change; REVIEW = open data-bearing removals or persistence loss only: confirm each is |
| 3 | const | PASS | 0 | FAIL 0 \| REVIEW 0 \| PASS* 0 \| INFO 3 \| PASS 23 |
| 4 | data | PASS* | 0 | INVALID 0 \| FAIL 0 \| REVIEW 0 \| NEW_ENDPOINT 0 \| PASS* 6 \| PASS 82 \| INFO 81 |
| 5 | rest | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) (optional rung) |
| 6 | logdiff | PASS* | 0 | FAIL 0 \| REVIEW 0 \| PASS* 1 \| INFO 0 |
| 7 | smoke | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) |
| 8 | journeys | FAIL | 1 | journeys: 7 PASS, 70 FAIL, 43 INVALID, 1 PASS* (unreachable in the OLD UI, evidence checked), 9 INFO (covered or unreachable, listed only);actions 115 found · 72 generated (43 todo: no-click-path 41, |
| 9 | screens | FAIL | 1 | pairs 7: INVALID 0 \| REVIEW 7 \| PASS* 0 \| PASS 0;screens: 0 PASS, 0 PASS*, 7 REVIEW, 0 INVALID |
| 10 | release | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) |
| 11 | apis | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) (optional rung) |
| 12 | widgets | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) (optional rung) |

Report words: PASS = verified; PASS* = verified with accepted differences; FAIL = REGRESSION to fix only when something that passed on the old app fails on the new one, needs a decision when only REVIEW lines are open; INVALID / NOT RUN = not measured yet (or needs a decision when a human item is open).

Not closed, in report words (REGRESSIONS first):
- journeys: REGRESSION to fix: journeys: 7 PASS, 70 FAIL, 43 INVALID, 1 PASS* (unreachable in the OLD UI, evidence checked), 9 INFO (covered or unreachable, listed only);actions 115 found · 72 generated (43 todo: no-click-path 41,; worked on the old app, not on the new one
- smoke: not measured yet: not selected (--only build,idcheck,const,data,logdiff,screens,journeys)
- screens: needs a decision: pairs 7: INVALID 0 | REVIEW 7 | PASS* 0 | PASS 0;screens: 0 PASS, 0 PASS*, 7 REVIEW, 0 INVALID (steps/decide.md, or the accept file named in the rung's report)
- release: not measured yet: not selected (--only build,idcheck,const,data,logdiff,screens,journeys)
- changes: needs a decision: 1 commit(s) in the app repo carry no Changed-By / Upgrade-Change trailers (listed as unlabelled in /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/night/druns/APPR/work/CHANGES.md; say who made them and why, steps/decide.md)

PASS* = accepted in writing (allow or accept file; each reason is in the rung's report). FAIL = an open FAIL or REVIEW.
INVALID = the rung could not judge (instrument rc 2, journeys rc 3, timeout, failed PRE command); it blocks DONE and is never PASS.
NOT RUN = the rung was skipped or its inputs were not given; for a required rung that blocks DONE too.
EXCEPT = the rung's only non-PASS items failed on a call into an excluded system (EXCLUDE_SYSTEMS): NOT CHECKED, listed above; the overall verdict is then PASS (except ...), exit 4, never plain PASS.
PASS (on stand-in APIs: ...) = APIMOCK answered for the listed endpoints; exit 4, never plain PASS: plain PASS needs the real (test) systems.
