# Skill: load-test — record the real page, replay it, and say what the number does not prove

**Applies to:** any mxcli project with a runnable app, pipeline or not. On request only: a
load test is never a build-plan step and never a gate.
**Purpose:** answer "does this page hold up under N at once" without correlating Mendix's
client protocol by hand, and without a report that overclaims.
**Source:** a field implementation on a warehouse demo app (Mendix 11, `mxcli run --local`
with OTel to Jaeger), 16 recorded runs from 2026-09-09 to 2026-10-08, bursts of 1000 and
2000 concurrent calls. Every trap below was hit in those runs.

**Instrument:** none ships in `project-tests/` yet. Build it in the project's `tests/e2e/` on
top of the shipped `helpers.js` (login, nav) and `otel.js` (`capture`, `liveness`). This file
holds the method and every judgement; the script fetches facts only (`skills-over-scripts.md`).

---

## Why record and replay, not hand-written requests

A Mendix page does not call a public API. The client posts to `/xas/`, and in Mendix 11 every
client-invoked microflow is action `runtimeOperation` with an opaque `operationId`. Writing
that payload by hand is a guess, and it changes between versions. Classic protocol tools hit
the same wall: dynamic ids and the CSRF token must be correlated, again after every release.

The recipe skips correlation entirely:

```
1. Playwright logs a real persona in and opens the page      (helpers.js login, navTo)
2. record every POST to /xas/ while the page loads           (page.on('request'))
3. probe: fire each recorded call once, read Jaeger          (otel.js capture)
   → which microflow did it run, does it write?
4. replay the chosen call with that session's cookie and the
   token: mx.session.sessionData.csrftoken (Mendix 11 has no
   getCSRFToken), refuse to fire if empty, as helpers.js does   (raw node:http)
5. ramp → burst → optional ladder → one lone request after
```

After a release you re-record, one command. Nothing to re-correlate.

A k6 script fed from a HAR export works too, but the HAR carries one live session cookie:
replayed as-is, 1000 virtual users are one session, and the cookie expires mid-run. Each VU
must log in itself. Delete the HAR afterwards; it holds a live session.

## When to run it

| Situation | Run? |
|---|---|
| The user asks "will this hold N users", before a go-live or a sizing talk | **Yes**, on the page they name |
| Journeys for that page are red | No. A broken page under load measures the breakage. |
| As evidence a module is done | **No.** Load is not correctness. |
| Against a shared or production environment | Only with the owner's written yes. A burst is indistinguishable from an attack. |
| The chosen call writes (create, commit, move, submit, import) | **Refuse** unless the user explicitly allows writes on a throwaway database |

## The traps, each paid for

**1. HTTP 200 on a failed action.** Mendix answers 200 and puts the failure in the JSON body
under `error`. Counting status codes reported 0% errors over a broken service. Count
transport errors and application errors separately; parse every body.

**2. A caught failure leaves the microflow green.** A handler that catches an upstream REST
error lets the page render and the microflow span end OK; only its activity spans are ERROR.
Walk activity-level spans, not just the microflow span.

**3. The wrong call gets hammered.** Every recorded call reads `runtimeOperation`, so a label
regex cannot tell the grid's data fetch from a keep-alive. Measured: the most frequent call
was a 771-byte no-op; replaying it measured the HTTP dispatcher and reported it as the page.
Choose by the probe (which microflow ran), and when the probe finds nothing, by the biggest
response, and say in the report that the choice was not evidence-backed.

**4. The tape holds the previous page.** Login and the page you parked on fire microflows too.
Measured: without clearing, six dashboard microflows topped the candidate list of a list-page
test. Park on another page, clear the recording, navigate, then prove you landed (a ready
selector, not caption text that sits in the nav on every page).

**5. Tracing looks on when it is off.** Jaeger keeps a service name in its list long after the
process is gone. Two full runs printed `serverSide: null` because the check was "the name is
listed". The gate is: spans for this service arrived after the page was opened. No spans after
a real navigation is an **instrument FAULT** (exit 2), not a clean run. Usually the cause is a
`--trace-service` override; mxcli's default (the .mpr name) already matches.

**6. The harness throttles itself.** Node's `fetch` pools sockets, so "1000 concurrent" became
"N concurrent, queued" and the app got the credit. Use `http.Agent({ maxSockets: Infinity })`
and fire the whole burst before awaiting any answer. No socket timeout: a 90 s answer is a
finding, a 30 s cut-off relabels it as a harness error.

**7. Whose limit was hit.** On the ladder, classify every stop:

| Error | Who broke |
|---|---|
| `ECONNRESET`, `ECONNREFUSED`, `EPIPE`, 5xx, error body | **the app** |
| `EADDRNOTAVAIL`, `EMFILE`, `ENFILE` | **the harness** (~28k ports per destination, TIME_WAIT ~60 s carries across rungs) |

After each rung send one lone request. A rung that answered thousands and then cannot answer
one is a server that fell over late, and the rung's percentiles called it a pass.

**8. Requests are not users.** One recorded cookie replayed by every worker is N concurrent
*requests* on one session. For users: log in K separate sessions and round-robin their
cookie and token pairs, from K **distinct** accounts. Two live sessions on one account can
degrade each other (measured: both lost their navigation menu), which reads as "the app got
slow". End every session afterwards with `helpers.logout` (the xas logout action, with the token); closing the browser context
leaves it alive against the runtime's session cap.

**9. A local app without a licence caps sessions at 6.** A trial runtime allows 6 concurrent
users ("Maximum number of sessions exceeded!") and stops itself after a random 2 to 4 hours
("LicenseService: Maximum run time exceeded"). Both read as the app failing under load. On a
local trial, more than 6 sessions is not a test: use a licensed runtime or a cloud sandbox for
user counts above 6, and check uptime before a long run. Concurrent *requests* on one session
hit no such cap in the field runs: the 1000 and 2000 bursts ran on one session.

**10. The trace store samples.** Jaeger's query caps at a few hundred traces; one burst makes
far more. Read server-side percentiles, never counts, and never read "0 ERROR spans" as "no
request failed" above the cap.

**11. An empty database is a different app.** A p95 on 50 rows says nothing about 5 million.
State the row counts of the entities the page reads, and look at the query plan or missing
indexes before blaming the runtime. This is the honest half of "load testing is theatre".

## Reading the result

| Run says | Verdict |
|---|---|
| 0 transport, 0 app errors, lone request after answers, spans arrived | **PASS for this call, this data, this host**: nothing more |
| App errors > 0 or 5xx | **FAIL**, name the microflow from the probe |
| Stopped on `EADDRNOTAVAIL`/`EMFILE` | **Harness limit**, not a finding about the app |
| No spans after navigation | **FAULT**, no server-side claim may be made |
| Target picked by size, not by probe | Report it, with that caveat in the first line |

Field numbers, for scale: bursts of 1000 on one session gave p95 between 0.2 s and 4.6 s
across runs with 0 errors; 2000 gave 1.2 to 11.5 s. All local, one account, one replayed call.
That is "the runtime absorbs 1000 calls at once on a laptop", not "1000 people can use it".

## Reporting

Four lines, every time:

```
load · <page> → <microflow> · <host> · <data: rows in the entities read>
  burst <N>: p50/p95/p99 <..> · transport <t> · app errors <a> · lone request after: <ok|fail>
  sessions: <K> on <A> distinct accounts   [or: one session, so concurrent requests, not users]
  Read as: <the PASS row above, verbatim>. Not: production capacity.
```

Write the full run to `tests/e2e/artifacts/loadtest-<timestamp>.json`, with the recorded
calls, the probe mapping (operationId to microflow) and the chosen target, so a reader can
check what was hammered.

## Related

- `skills/testing-shape.md`: the module shape this sits outside of
- `skills/monkey-test.md`: the same "what a clean run is not allowed to mean" discipline
- `skills/e2e-harness-base.md`: login, persona and the no-unapproved-fix rule
- `skills/tool-output-is-not-ground-truth.md`: why a quiet run is not a passing one
