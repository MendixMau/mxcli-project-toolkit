# Retry an external call in a microflow: a loop shape that lints clean, and a decision flow that tests without the call

**From:** a field project (anonymised) — a Mendix 10.24 app built with mxcli v0.27.0 and this toolkit
**Date:** 2026-10-21
**Kind:** skill-draft
**Field evidence:** the shape retries a call to an external service up to N times in a field app
(68 of 68 of that app's microflow tests passed). It was rebuilt on a synthetic Shop module and
re-run: `mxcli check`, `mxcli lint`, `mx check` in Docker, `mxcli test` in Docker. Mendix 10.24.18,
mxcli v0.27.0.
**Proposed target:** `skills/learned-microflow-patterns.md`, a new section after "Per-row
isolation in a loop" (same family: keep the loop body small)

---

## The problem

"Call the service; if the reply is bad, call again, up to N times" is usually written as
`while true` with a `return` inside the loop. On mxcli v0.27.0:

- `mxcli lint` reports MDL-FLOW01 once per `return` inside the loop. Re-run here: two `return`s,
  two hits. `mxcli check` and `mx check` (0 errors) were clean, so lint is the only warning.
- A statement placed after a `while true` that has no `break` can never run. `check` accepts it,
  `exec` writes it, `mx check` fails with CE0104 (upstream mendixlabs/mxcli#1491, open when this
  was written; not re-run for this note).

## The shape

Put every decision in one sub-microflow that returns a status string. The loop only repeats the
calls until the status says stop. `Shop.RetryState` is a non-persistent entity with `Attempt`
(Integer, default 0) and `MaxRetries` (Integer, default 3); the counter lives there, so a test can
hand the decision flow any `Attempt`.

```
Shop.SUB_CallService()                 -> String    the external call; empty means it failed
Shop.SUB_HandleResponse(Body, State)   -> String    'stored' | 'retry' | 'failed'
Shop.ACT_CallWithRetry()               -> Boolean   the loop
```

`SUB_HandleResponse` is the only place the counter changes:

```
if $Body != empty and $Body != '' then return 'stored';
if $State/Attempt < $State/MaxRetries then
  change $State (Attempt = $State/Attempt + 1);
  return 'retry';
return 'failed';
```

`ACT_CallWithRetry` has no `return` in the loop:

```
$State = create Shop.RetryState ();
declare $Outcome String = 'retry';
while $Outcome = 'retry'
begin
  $Body = call microflow Shop.SUB_CallService ();
  $HandleOutcome = call microflow Shop.SUB_HandleResponse (Body = $Body, State = $State);
  set $Outcome = $HandleOutcome;
end while;
return $Outcome = 'stored';
```

With `MaxRetries = 3` the service is called at most 4 times: the first call plus 3 retries.

## What was checked (synthetic module in a copy of a 10.24.18 app)

- `mxcli check` passed; `mxcli lint` had no hit on the three flows; the `while true` version with
  `return true` / `return false` inside gave 2 MDL-FLOW01 hits.
- `mx check` in Docker on a model holding both versions: `The app contains: 0 errors.`
- `mxcli test` in Docker: 5 passed, 0 failed, exit 0. Four tests call `SUB_HandleResponse` with
  a chosen `Attempt` and a body of `'ok'` or `''`, and assert the string and the counter: success
  (counter stays 0), a retry (counter up), the last allowed retry (`'retry'`, counter 3), the
  limit (`'failed'`, counter stays 3). The fifth runs the whole loop against a stub that succeeds.
- With one expectation flipped in a copy, exactly that test failed (`expected $State/Attempt = 2,
  actual: 1`) and the exit was 1.

## Limits

The tests do not exercise the loop's repeat path, because the stub always succeeds; they prove
the decisions and the wiring. Not checked: how Studio Pro draws the loop.
