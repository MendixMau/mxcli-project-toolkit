# mxcli v0.24 field notes from an integration module: REST calls, JSON structures, mappings, page hooks, OQL, test endpoint

**From:** card-disbursement requirements-driven build (build-plan phase 4, rows 4.2–4.7)
**Date:** 2026-09-26
**Kind:** bug
**Field evidence:** each item below was probed on a scratch copy of the model (mxcli v0.24.0, Mendix 11.13.0) and checked with `mx check` and/or a BSON read of the unit; the working rule was then used on the real model.
**Proposed target:** `bug-logs/mxcli-bugs.md` (one entry each), plus the skill named per item

---

1. **`mxcli run --local --test-endpoint` writes into the working model while the app runs.** It adds
   a temporary `MxTest` module (a `RegisterEndpoint` microflow), `javasource/mxtest/`,
   `themesource/mxtest/` and several `mprcontents/` units, and edits the Project settings unit.
   `git status` shows about 9 extra model paths, and lint reads CUSTOM002 +1 / CONV013 +1, so a lint gate sees a rise.
   A clean stop prints "test endpoint removed; project restored" and reverts all of it. Verified by
   `SHOW MICROFLOWS IN MxTest` → module not found, no `javasource/mxtest/`, and the settings unit back to its value.
   An exec or commit made while it is up carries MxTest into the model.
   Working rule: no exec and no commit until the app is stopped cleanly. Target: `skills/learned-mdl-preflight.md` STOP table.
   Separately, every `mxcli test --attach` run rewrites the `.mpr` (it creates, then removes, the test
   microflows). The units stay byte-identical (only `_Transaction` changes), but the mtime moves. See the verify-module note of the same date.

2. **`rest call … body $Var` sends the literal text `$Var`.** The bare-expression body form writes a
   StringTemplate "$Var" with an empty parameter list. `body '{1}' with ({1} = $Var)` round-trips
   correctly (BSON read + DESCRIBE).

3. **REST call custom error handlers are accepted now, but not inside a loop.** `on error { … }` and
   `on error without rollback { … }` on a `rest call` pass `mx check` (Mendix 11.13). The REST skill's
   "only `on error continue` (CE6035)" is stale; restamp it. Inside a WHILE loop, any custom handler is
   CE0644 ("must be 'Rollback' inside a looped activity"). Working shape: the attempt is its own
   sub-microflow, called from the retry loop.

4. **lint CONV013 false positive also hits REST calls.** Two REST-calling microflows are reported as "uses ''
   error handling instead of Custom", while the BSON holds `ErrorHandlingType: CustomWithoutRollBack`. This is
   the same false positive already known for other activities.

5. **`create or modify entity` replaces the attribute list.** Any attribute left out of the statement
   is removed, with a warning naming CE1613 for anything still bound to it. On a persistent entity with data, that is a
   drop. Target: STOP table ("rename via `alter entity … rename attribute`").

6. **A JSON structure key named `CONTEXT` is CE9524 at `mx check` only.** It passes `mxcli check` and
   exec. `custom name map ('CONTEXT' as 'ApprovalContext')` fixes it; the wire key stays `CONTEXT`.
   Hypothesis: other reserved-looking keys behave the same way. Only `CONTEXT` was probed.

7. **`import from mapping` needs a variable as its source.** `… ($Call/ResponseBody)` is a parse error
   ("mismatched input '/'"). `declare $Body String = $Call/ResponseBody;` then `($Body)` works. It was also
   re-confirmed on 0.24 that a doc comment before `create or modify … mapping` is ignored ("already in sync").

8. **`alter page … replace <widget> with { … }` is not re-run safe.** The replacement is built while
   the old widget's children still hold their names. A replacement that reuses any child name (the natural
   case: the same grid with one column added) is refused as a duplicate widget name, and a second run of
   the same script always fails. Working shape: `drop widget X; insert into <anchor> { … }` passed mx
   check and ran twice on the probe and twice on the model. Target: `skills/learned-mdl-preflight.md` or the page-alter recipe.

9. **`oql --direct` rejects `HAVING` without `GROUP BY`** ("mismatched input 'HAVING'"). A journey
   seed that must resolve only when a precondition holds can use a scalar subquery in the WHERE clause:
   `… WHERE … AND (SELECT COUNT(x.ID) FROM M.E AS x) = 2`. It returns no row when the condition fails, so the
   seed reports INVALID, never a feature FAIL. Target: `skills/journey-proof.md` (seed recipes).
