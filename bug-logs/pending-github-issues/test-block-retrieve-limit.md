**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-test-block-retrieve-limit` — found 2026-09-15
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1103 (2026-09-15)
**Suggested labels:** bug, test, grammar

---

**Title:** Inside a `.test.mdl` block, `RETRIEVE … WHERE … LIMIT n` is parsed by the OQL grammar and rejected

**Body:**

## Summary

The statement is the one `mxcli syntax microflow.retrieve` prints in its own example. Inside a
`CREATE MICROFLOW` body it parses fine. Inside a `.test.mdl` test block the same statement
fails:

```
Parse error: line 7:52 mismatched input 'LIMIT' expecting {GROUP_BY, SELECT, HAVING}
```

`{GROUP_BY, SELECT, HAVING}` is the **OQL** grammar's expectation set, so the test-block path is
routing a microflow `RETRIEVE` into the OQL statement parser once it reaches `LIMIT`.

## Environment

- mxcli: `v0.22.0-15-g7b42100d` (`main` HEAD, 2026-09-15)
- Mendix: 11.13.0, blank `mxcli new` scaffold
- Reproducible: yes, 100%

## Steps to reproduce

```
/**
 * @test retrieve with a limit
 * @cleanup none
 */
DECLARE $result Boolean = false;
RETRIEVE $reqs FROM Probe.Request WHERE Status = Probe.ENUM_Status.Approved LIMIT 1;
$req = HEAD($reqs);
$result = $req != empty;
/
```

`mxcli test <file> -p app.mpr --attach` → the parse error above.

**Two controls, both observed:**

| Where | Statement | Result |
|---|---|---|
| `CREATE MICROFLOW` body | `RETRIEVE … WHERE … LIMIT 1;` | `✓ Syntax OK`, execs, builds |
| `.test.mdl` block | `RETRIEVE … WHERE … LIMIT 1;` | **parse error above** |
| `.test.mdl` block | `RETRIEVE … WHERE …;` (no `LIMIT`) | parses, runs, returns a verdict |

## Impact

Mild on its own — drop the `LIMIT` — but it costs a debugging cycle precisely because the
statement is copied from mxcli's own syntax help and works everywhere else, so the author looks
for a mistake that is not there. It also compounds the sibling issue on `mxcli test` cleanup:
the failed injection leaves the project modified, and every later run fails opaquely until the
leftover is found by hand.

## Suggested fix

Parse a test block's body with the microflow statement grammar — which is what the generated
`MxTest.Test_*` microflow actually is.
