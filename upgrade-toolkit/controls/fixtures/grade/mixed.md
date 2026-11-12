# Gate summary

Overall: **INVALID** (exit 0): fixture.
Work: `/tmp/w`, evidence: `/tmp/w/g`, instruments: `/tmp/b`, run 20260101000000. 2026-01-01T00:00Z

| # | rung | verdict | rc | one line |
|---|---|---|---|---|
| 1 | build | PASS | 0 |  |
| 2 | idcheck | PASS | 0 |  |
| 3 | const | PASS | 0 |  |
| 4 | data | PASS* | 0 |  |
| 5 | logdiff | PASS | 0 |  |
| 6 | smoke | PASS | 0 |  |
| 7 | journeys | INVALID | 0 | INVALID only (exit 3): 2 journeys INVALID, anonymous process |
| 8 | screens | INVALID | 0 | pairs 4: REVIEW 3 by eye |
| 9 | release | INVALID | 0 | release-impact check: 10 of 12 rows handled, 2 open |
| 10 | apis | EXCEPT | 0 | 2 NOT CHECKED (excluded: Teamcenter) |
| 11 | widgets | NOT RUN | 0 | not configured |
