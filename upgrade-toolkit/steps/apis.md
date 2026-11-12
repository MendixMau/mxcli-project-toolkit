# External APIs, tested directly (the `apidirect` step and the `apis` rung)

Why: the `apis` rung used to count an outside endpoint as tested only when a browser journey happened to call it. In a
field run 16 of 170 stand-in endpoints were hit: the calls sit deep in flows the UI cannot reach. What an upgrade can
break in a REST integration is invisible to a page click anyway: the request that is built (location template, query
and path parameters, headers, export mapping, body JSON), the response that is read (import mapping, object graph, date
and number parsing) and the error handling. So each consumed REST call is run directly, on the old and the new app,
against the same stand-in, and what was SENT and what was READ are compared.

Pipeline step `apidirect`, between `heal` and `diff` (`UPG_APIDIRECT=0` turns it off; it also needs `original.mpr` and the
stand-in inventory of the proposal). Scripts: `bin/apidirect.py` (inventory, prepare, drive, split-log, compare, check),
`bin/apimock.py` (the stand-in, its control endpoint and fault modes, `check --direct`). Output in `work/apidirect/`:
`calls-old.json` and `calls-new.json` (the inventory), `results-old.jsonl` and `results-new.jsonl` (one row per call and
run), `standin/requests.jsonl` (what the stand-in received), `direct.json` and `direct.md` (the verdict per endpoint).

## How a call is driven (the app is not changed)

1. Inventory: every microflow with a Call REST action (and the other external call actions the stand-in lists) is read
   from the model: parameters and types, return type, location template, headers, export and import mapping, error
   handling. The endpoint ids are the stand-in's (`rest:Module.Microflow`, `#n` when a microflow has several).
2. A throwaway COPY of the old app (the `original` commit) and of the new app gets one module, `ApiDirectTest`: a wrapper
   microflow per REST-calling microflow, a helper per persistable input entity, one module role, granted to ONE user
   role of the copy. The copy is built and run, then deleted; nothing is committed to the app repository.
3. The wrapper builds the inputs, calls the ORIGINAL microflow and returns its result. Inputs are the same on both sides:
   a persistable entity gets its first seeded row (sorted by its first attribute), else a fresh object (not committed);
   a String, enumeration or date attribute without a default gets a fixed sample; a primitive parameter gets 'TEST_<name>',
   1, 1.5, true or a fixed date.
4. The runtime's own client API (`/xas/`: login, session start, `executeaction`) runs the wrapper as the test user. The
   returned objects with their attribute values are the "parsed result". A failed run carries only a code in the
   response, so the driver also reads the runtime log (`docker logs`) for the error and the microflow activity it stopped in.
5. Three runs per call: `ok` (the stand-in answers as the model describes), `500` (the stand-in answers every call with
   a server error) and `malformed` (a 200 whose body is not JSON). Before each run the driver tells the stand-in which
   call, side and mode it is (`/__ad/call`), and the stand-in logs method, path, query, headers (secret values reduced to
   their scheme) and body of every request of that run.

## The classes (per endpoint)

| class | meaning | gate |
|---|---|---|
| PASS | the old and the new app sent the same requests, read the same result and took the same error path, in all three runs | counts as measured |
| FAIL | they differ: a CANDIDATE regression (request, response mapping or error path difference, named with the first differing path) | rung FAIL |
| INVALID | could not be measured, with the reason: needs input recipe (an input has no sample), the wrapper did not apply, the microflow is excluded from the build, no request reached the endpoint in the `ok` run | rung INVALID |
| INFO | a system a `--classify ... EXCLUDED <System> # reason` line excludes (an identity provider): nothing stands in for it | rung stays PASS, "check at deploy" |
| INFO | an activity disabled in Studio Pro, or a microflow excluded from the build, in both apps: it never runs | nothing to test |

Volatile values (object ids, timestamps, durations, the stand-in's host) are normalised before comparing.

## Reading a FAIL

A FAIL is never a finding until the evidence says so. Test artefacts first:

1. A route shared by several calls: the stand-in picked another endpoint for the same request (look at `endpoint` in
   `standin/requests.jsonl`, and `apimock.py` pick rules).
2. A padded or trimmed recorded response (`work/apimock-recorded/`): the same body, so no difference; if the bodies differ
   the recording is the cause.
3. A seed mismatch: the first seeded row differs between the two databases (the databases are copies of one frozen
   baseline, so it should not).
4. The sample input takes a branch the real data never takes: add an input recipe (`--recipes`, JSON
   `{"Module.Microflow": {"params": {"Name": "'value'"}}}`, MDL expressions).

Only then is it the upgrade: a small mechanical fix goes into the app as its own commit; a larger one is recorded as an
open decision with a recommendation.

## Input recipes

A microflow whose input cannot be built is listed INVALID with its reason, never skipped. Give it an input with a recipe
file passed to `apidirect.py prepare --recipes FILE`: for an entity with no model (a System or add-on entity) or an input
the sample cannot satisfy.

## What the compare ignores (and nothing else)

The object `hash` (it differs on every run), the order of returned objects and the guids (objects are labelled by type and
attributes), volatile times and ids, and the runtime's log layout (Mendix 10 and 11 print an error differently: the compare keeps the
first line of the message and the first microflow activity it stopped in). A call that no request reached on either app is
INVALID even when the two apps print different text before the call: the difference is in the flow around the endpoint.
