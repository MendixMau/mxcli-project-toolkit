# Gate summary

Overall: **FAIL** (exit 1): 5 PASS/PASS*, 0 EXCEPT, 2 FAIL, 0 INVALID, 2 required NOT RUN.
Grade: 56% (5 of 9 required rungs done): proven 2, accepted 3, waiting on a person 2, not testable here 0, open regression 2 | verdict FAIL
Progress: 5 of 10 checks closed (50%). 1 with REGRESSIONS to fix, 1 need a decision, 2 not measured yet, owner sign-off pending.
Changes: 29 (toolkit 5, agent 0, person 0, unlabelled 24)
Change ledger: `/tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/CHANGES.md`
Work: `/tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work`, evidence: `/tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work`, instruments: `/tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/night/prrebuild/upgrade-toolkit/bin`, run 20261019194836. 2026-10-19T19:50Z

| # | rung | verdict | rc | one line |
|---|---|---|---|---|
| 1 | build | PASS | 0 | BUILD SUCCEEDED and 0 "ERROR at" lines: yes in /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/build-11.12.5.log |
| 2 | idcheck | PASS | 0 | findings: 12 total, 8 RED (data-bearing), 8 of them approved, 0 open;verdict: PASS  (FAIL = open data-bearing GUID change; REVIEW = open data-bearing removals or persistence loss only: confirm each is |
| 3 | const | PASS* | 0 | FAIL 0 \| REVIEW 0 \| PASS* 1 \| INFO 2 \| PASS 25 |
| 4 | data | PASS* | 0 | INVALID 0 \| FAIL 0 \| REVIEW 0 \| NEW_ENDPOINT 0 \| PASS* 20 \| PASS 175 \| INFO 86 |
| 5 | rest | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) (optional rung) |
| 6 | logdiff | PASS* | 0 | FAIL 0 \| REVIEW 0 \| PASS* 4 \| INFO 0 |
| 7 | smoke | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) |
| 8 | journeys | FAIL | 1 | journeys: 120 PASS, 31 FAIL, 142 INVALID, 71 INFO (covered or unreachable, listed only);actions 280 found · 138 generated (141 todo: no-click-path 126, combobox 7, assign-to-me-dead 6, external-call  |
| 9 | screens | FAIL | 1 | pairs 17: INVALID 0 \| REVIEW 17 \| PASS* 0 \| PASS 0;screens: 0 PASS, 0 PASS*, 17 REVIEW, 0 INVALID |
| 10 | release | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) |
| 11 | apis | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) (optional rung) |
| 12 | widgets | NOT RUN | - | not selected (--only build,idcheck,const,data,logdiff,screens,journeys) (optional rung) |

Report words: PASS = verified; PASS* = verified with accepted differences; FAIL = REGRESSION to fix, or needs a decision when only REVIEW lines are open; INVALID / NOT RUN = not measured yet (or needs a decision when a human item is open).

Not closed, in report words (REGRESSIONS first):
- journeys: REGRESSION to fix: journeys: 120 PASS, 31 FAIL, 142 INVALID, 71 INFO (covered or unreachable, listed only);actions 280 found · 138 generated (141 todo: no-click-path 126, combobox 7, assign-to-me-dead 6, external-call ; worked on the old app, not on the new one
- smoke: not measured yet: not selected (--only build,idcheck,const,data,logdiff,screens,journeys)
- screens: needs a decision: pairs 17: INVALID 0 | REVIEW 17 | PASS* 0 | PASS 0;screens: 0 PASS, 0 PASS*, 17 REVIEW, 0 INVALID (steps/decide.md, or the accept file named in the rung's report)
- release: not measured yet: not selected (--only build,idcheck,const,data,logdiff,screens,journeys)
- changes: needs a decision: 24 commit(s) in the app repo carry no Changed-By / Upgrade-Change trailers (listed as unlabelled in /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/CHANGES.md; say who made them and why, steps/decide.md)

PASS* = accepted in writing (allow or accept file; each reason is in the rung's report). FAIL = an open FAIL or REVIEW.
INVALID = the rung could not judge (instrument rc 2, journeys rc 3, timeout, failed PRE command); it blocks DONE and is never PASS.
NOT RUN = the rung was skipped or its inputs were not given; for a required rung that blocks DONE too.
EXCEPT = the rung's only non-PASS items failed on a call into an excluded system (EXCLUDE_SYSTEMS): NOT CHECKED, listed above; the overall verdict is then PASS (except ...), exit 4, never plain PASS.
PASS (on stand-in APIs: ...) = APIMOCK answered for the listed endpoints; exit 4, never plain PASS: plain PASS needs the real (test) systems.
