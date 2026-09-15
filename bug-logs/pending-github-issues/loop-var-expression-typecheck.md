**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-loop-var-expression-typecheck` — found 2026-09-15
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1100 (2026-09-15)
**Suggested labels:** bug, check, expressions

---

**Title:** The expression type checker is skipped inside a `LOOP` body — `E004` fires on a parameter and is silent on a loop variable (CE0117 at build)

**Body:**

## Summary

`mxcli check` already has the rule and states it well. Concatenating an `Enumeration` into a
`String` is refused with a named fix:

```
✗ The '+' operator concatenates Strings. The other operand is Enumeration, which cannot be
  concatenated with a String directly.  [E004]
    → Wrap the non-String operand in toString().
```

**The same expression one line deeper, inside a `LOOP`, is not checked at all** — it passes
`check`, is written by `exec`, and fails the native build with `CE0117`.

The interesting part is not the enum rule, which works. It is that loop-variable member access
appears to be untyped for the whole expression checker, so every rule the checker enforces is
silently off inside the construct where list processing actually happens.

## Environment

- mxcli: `v0.22.0-15-g7b42100d` (`main` HEAD, 2026-09-15)
- Mendix: 11.13.0, blank `mxcli new` scaffold
- Reproducible: yes, 100%

## Steps to reproduce

Given `Probe.Request(Status: Enumeration(Probe.ENUM_Status))`:

```mdl
-- A: caught correctly at check time, E004, never written
CREATE OR MODIFY MICROFLOW Probe.SUB_Param ($Req: Probe.Request) RETURNS String
BEGIN
  DECLARE $out String = '';
  $out = 'status=' + $Req/Status;
  RETURN $out;
END;

-- B: passes check, execs, and fails the native build
CREATE OR MODIFY MICROFLOW Probe.SUB_LoopNormal () RETURNS String
BEGIN
  DECLARE $out String = '';
  RETRIEVE $reqs FROM Probe.Request;
  LOOP $r IN $reqs BEGIN
    $out = $out + $r/Status;      -- Enumeration into a String
  END LOOP;
  RETURN $out;
END;
```

| Shape | `mxcli check` | native `mx check` |
|---|---|---|
| `$Req/Status` on a **parameter** | **refused, E004** | — (never written) |
| `$r/Status` on a **loop variable** | **Check passed!** | **CE0117** |

For B: `mxcli check` → `Check passed!`; `exec` → `Created microflow: Probe.SUB_LoopNormal`;
native → `[error] [CE0117] "Error(s) in expression." at Change variable activity 'Change
variable out'`. Dropping the microflow returns the project to 0 errors.

## Expected

The loop variable is typed from the list it iterates — `RETRIEVE $reqs FROM Probe.Request` is
in the same flow and already resolved — so `E004` should fire inside the `LOOP` exactly as it
does outside it.

## Suggested fix

Type the loop variable from its source list and run the existing expression checks over `LOOP`
bodies. Worth auditing whether other block-scoped variables have the same hole — `FILTER`'s
`$currentObject` and `on error` handlers are the obvious candidates.
