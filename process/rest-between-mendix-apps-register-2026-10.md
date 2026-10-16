# REST between Mendix apps: failure register, 2026-10

The evidence behind `skills/rest-between-mendix-apps.md`. Three demo apps built with mxcli
v0.24 to v0.26 on Mendix 11.15, 2026-10-07 to 2026-10-12: an **order app**, a **stock app** and a
**customer app**, with nine published APIs and five consumer directions. Domain names in this file
and in the skill are generic placeholders, not the apps' real domain.

"Caught by" is the rung of the skill's test ladder (§3) that found the failure. "Would have" is the
cheapest rung that could have. Source: **F** = a FINDINGS line in one of the three apps; **D** =
another project document (a proof file or the UX scan of 2026-10-12).

| # | Failure | Caught by | Cheapest rung that would have | Src |
|---|---|---|---|---|
| 1 | Unset String query parameter arrives as `''`, rejected as invalid (7 of 29 → 29 of 29) | 1 | 1 | F |
| 2 | Per-test rollback removed a seed the later tests needed | 1 | 1 | F |
| 3 | Published REST has no auth clause in MDL; an auth property is ignored (BUG-152) | 4 | 4 | F |
| 4 | Malformed cursor gets runtime 560 before the microflow; the mock answered 200 | 3 | 3 | F |
| 5 | Mock rejected empty `limit=`; the publisher treats it as not given | 3 | 3 | F |
| 6 | Consumer never pruned rows the publisher stopped serving | the publisher team's confirmation request (cross-app, by hand) | 1b | F |
| 7 | Demo reset left stored copies hanging off recreated records | 6 (journey) | 1b | F |
| 8 | Non-2xx handler lost the status (401 logged as 0) and rolled back the endpoint row | 2 | 2 | D |
| 9 | Cache columns 30 characters, live feed sends 40 | 2, run against the live publisher instead of the mock | 3 | D |
| 10 | `LastError = ''` matched `!= empty`; healthy feeds shown as unreachable | live UI review | 1b | F |
| 11 | Producer hardcoded version and state; `since` missed the cancellation timestamp; consumer cursor skipped the cancellation | 6 (fresh cross-app story) | 1 | F |
| 12 | Stale mock process on the old port served old records; false test failure | 2 | 2 (reset fixtures first) | F |
| 13 | Two consumer tests pass on the mock and fail on the live publisher | 3 (by accident: run against both) | 3 | F |
| 14 | Consumer fallback seeded "Approved, now" on a failed read; owner holds the order Open | cross-app process trail and UX scan | 5 | F |
| 15 | Same order: 5 support cases in one app, 6 in another | recorded video, UX scan | 5 | F |
| 16 | Status card "Reachable · ok" from a 3-day-old probe while live calls returned 400 | UX scan | 1b (card fed by the call path) | D |
| 17 | "Last success" days old on APIs polled every 5 minutes; no last-error shown (cause not investigated) | UX scan | 1b + a stale marker | D |
| 18 | Eligibility checked once at publish while the other app was down; never retried | live page review | 2 (`down` mode at first call) | F |
| 19 | Field sign in the contract example opposite to what the database stores | building rung 1 | 1 | F |
| 20 | Rows with an empty `updatedAt` never match the cursor | building rung 1 | 1 | F |
| 21 | Date-shaped JSON sample inferred DateTime; String mapping failed mxbuild (CE5015) | exec gate (mxbuild) | exec gate | F |
| 22 | Two apps on one host shared the session cookie; one login signed the other out | 6 | 6 | F |
| 23 | StackOverflowError at startup: a test run stopped by a signal left after-startup on the injected `MxTest` flow, and the next injection chained it to itself (BUG-157) | 1 | — (process rule) | F |
| 24 | A machine-wide exec guard refused one app's exec while another app wrote (fixed by the per-project exec lock, #304; no longer applies) | any exec | — | F |
| 25 | Consumed-test wrapper read only the first verdict | audit of the wrapper | — (read every verdict) | F |
| 26 | Journey order load-bearing: a mock reset in one journey broke the next (4 false failures) | 6 | — (order in the suite) | F |

**What the register says.** Rungs 1–4 caught 12 of 26; a journey (rung 6) caught 4; a human
looking (page review, UX scan, recorded video, another team's question) caught 7; the exec gate
or an audit of a runner caught 3. Of the 11 found by a journey or a human, 9 had a cheaper rung
that would have caught them, and two of those — the cross-app contradictions, 14 and 15 — needed
the one rung nobody ran: rung 5.

Row 23 was first recorded as "`test --local` while the same model runs with `--test-endpoint`".
The 2026-10 review matched it to BUG-157, whose mechanism (a signal-stopped run skips the restore)
is the one stated above.
