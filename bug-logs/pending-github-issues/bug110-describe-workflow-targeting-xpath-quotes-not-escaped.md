**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-110` — found 2026-09-03 during a workflow
construct probe on a blank scratch app (mxcli v0.20.0 / Mendix 11.14.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, workflow, describe, round-trip

---

**Title:** `DESCRIBE WORKFLOW` drops the quote-escaping inside a targeting XPath, emitting MDL
that `mxcli check` cannot parse

**Body:**

## Summary

A user task whose targeting XPath contains string literals must be written with doubled
single quotes. `exec` accepts that and writes the correct model. `DESCRIBE WORKFLOW` then
emits the XPath with the inner escaping removed, and the output fails to parse when fed back —
breaking the documented round-trip.

## Environment

- mxcli: `v0.20.0` (2026-08-28)
- Mendix / mxbuild: `11.14.0`
- Reproducible: yes, 100%

## Steps to reproduce

Written (correctly):

```sql
TARGETING XPATH '[System.UserRoles = ''[%UserRole_User%]'']'
```

`DESCRIBE WORKFLOW Probe.T` emits:

```
targeting users xpath '[System.UserRoles = '[%UserRole_User%]']'
```

Feeding that back:

```
mxcli check described.mdl
- line 9:48 mismatched input '[%UserRole_User%]' expecting ';'
```

## Why it matters

`DESCRIBE` is documented as round-trippable and is the natural way for an agent to read
current state before editing. Here it silently produces a script that looks authoritative and
cannot run; a describe → edit → exec loop on any workflow with a role-constrained target breaks.

## Expected

`DESCRIBE WORKFLOW` re-escapes embedded single quotes (`''`) so its output parses.
