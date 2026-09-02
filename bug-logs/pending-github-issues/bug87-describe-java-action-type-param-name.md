**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-87: DESCRIBE JAVA ACTION drops the type-parameter
name, printing entity <>` (originally discovered 2026-08-20 on a scratch project, mxcli v0.17.0
and v0.18.0, while retesting BUG-61; retested and confirmed still open 2026-08-31 on v0.20.0 —
see `bug-logs/mxlabs-v0.20.0-retest-2026-08-31.md`)
**Status:** NOT YET FILED
**Suggested labels:** bug, java-action, describe, round-trip

---

**Title:** `DESCRIBE JAVA ACTION` drops the type-parameter name (prints `entity <>` instead of
`entity <pEntity>`) — the declaration does not round-trip

**Body:**

## Summary

A Java action parameter declared with a named type parameter — `ContextObject: ENTITY <pEntity>
not null` — is printed back by `DESCRIBE JAVA ACTION` as `ContextObject: entity <>`, i.e. the
type-parameter name `pEntity` is silently lost. Feeding the described form back into mxcli does
not reconstruct the original declaration, so any workflow that reads a Java action's declaration
via `DESCRIBE` and rewrites it (a common read-modify-write pattern for other document types in
mxcli) is broken for this one property.

## Environment

- mxcli: `v0.20.0` (tag, built from source, `git describe --tags` = `v0.20.0`, clean tree)
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: Linux amd64
- Baseline: a blank Mendix 11.13.0 project scaffolded fresh by `mxcli new`
- Originally discovered: 2026-08-20, mxcli v0.17.0 and v0.18.0 (confirmed on both), Mendix
  11.12.0, while retesting BUG-61. Reproduced independently since on v0.20.0 (2026-08-31): still
  prints `entity <>` for a named type parameter; does not round-trip.

## Steps to reproduce

```sql
create java action Test.JA_WithTypeParam (
  ContextObject: entity <pEntity> not null
) returns boolean as $$
  return true;
$$;
```

```
$ ./mxcli exec ja.mdl -p Test.mpr
Created java action: Test.JA_WithTypeParam

$ ./mxcli describe java action Test.JA_WithTypeParam -p Test.mpr
...
ContextObject: entity <>
...
```

The type-parameter name `pEntity` is missing from the output entirely — `entity <>` instead of
`entity <pEntity>`. Feeding that described text back to `mxcli check`/`exec` as a new declaration
does not reconstruct the original parameter (the type-parameter name is simply gone from the
round-trip).

## Expected vs. actual

**Expected:** `DESCRIBE JAVA ACTION` prints the parameter's type-parameter name exactly as
declared, so the described form is a faithful, re-executable MDL declaration — `ContextObject:
entity <pEntity> not null`.

**Actual:** the type-parameter name is dropped, printing `entity <>`, breaking the round-trip.

## Severity

**Low.** Cosmetic in isolation (the action still builds and functions correctly as originally
created), but it breaks any read-back-and-rewrite workflow — a script that inspects an existing
Java action's declaration via `DESCRIBE` in order to regenerate or extend it cannot recover the
original type-parameter name from mxcli's own output.

## Related trap worth noting

A parameter declared to fill in a type parameter but *without* `not null` — e.g. `ContextObject:
entity <pEntity>` (optional) — is accepted silently by mxcli at declare/check time, and only fails
at real build with:

```
[CE0163] "Parameter 'ContextObject' fills in a type parameter and cannot be optional."
```

`mxcli check`/`exec` do not flag this in advance; only a native build catches it. Not the same bug
as the describe round-trip issue above, but adjacent (same type-parameter feature), and worth
fixing alongside it or at minimum documenting.

## Suggested fix

Fix `DESCRIBE JAVA ACTION`'s parameter-printing logic to include the type-parameter name captured
at creation time, so the described output is a faithful round-trip of the original declaration.
Separately, consider having `mxcli check` flag the optional-type-parameter case ahead of a native
build, matching the `CE0163` that mxbuild already raises.

---

**Status: DRAFTED 2026-08-31, not yet filed.**
Duplicate-check: searched `mendixlabs/mxcli` issues (open and closed) for "DESCRIBE JAVA ACTION
drops type-parameter name entity" and "DESCRIBE JAVA ACTION type parameter round trip" — no
existing issue found as of 2026-08-31. The closest hit, closed issue #282 ("change with qualified
association loses member name on describe when variable entity type is unknown"), concerns a
different document type (microflow `change` statement describe) and a different symptom (member
name loss on an unresolved variable type, not a Java action parameter's type-parameter name) —
not a duplicate.
