# Gate summary

Overall: **INVALID** (exit 2): 8 PASS/PASS*, 0 EXCEPT, 0 FAIL, 1 INVALID, 0 required NOT RUN.
Work: `work`, evidence: `/nonexistent/remedy-fixture`, instruments: `bin`, run 20261013000000.

| # | rung | verdict | rc | one line |
|---|---|---|---|---|
| 1 | build | PASS | 0 | BUILD SUCCEEDED |
| 7 | smoke | PASS | 0 | steps: PASS 36, FAIL 0 |
| 9 | screens | PASS* | 0 | pairs 36: INVALID 0 \| REVIEW 0 \| PASS* 13 \| PASS 23 |
| 10 | release | INVALID | 1 | release-impact check: 3 of 5 rows handled or not relevant, 2 open |
| 11 | apis | NOT RUN | - | not configured (no APIMOCK given) (optional rung) |
