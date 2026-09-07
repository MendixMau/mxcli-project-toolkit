**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-113` — observed 2026-09-03 building scripts `78`
and `79` of VB-USI-main (Mendix 11.13.0)
**Status:** DRAFT — not yet filed
**Suggested labels:** bug, mdl, check, grant, association, alter-entity

---

**Title:** Three write-path asymmetries: `grant` role qualification, `create association`
idempotency, and silently partial access-rule reconciliation on `ALTER ENTITY … ADD ATTRIBUTE`

**Body:**

## Summary

Three independent defects found in one build session. They share a shape: **`mxcli check
--references` accepts the script and only `exec` decides** — or, in the third case, nothing
decides and the model quietly ends up wrong.

### (a) `grant` needs the module qualifier on the role, but the checker does not

`grant <Role> on <Module>.<Entity> (...)` with an unqualified role name passes
`check --references` and is rejected at exec. Either the checker should require the qualifier or
the executor should accept the bare name; today the two disagree, so a script is only validated
by running it against the real `.mpr`.

### (b) `create association` is not idempotent, unlike every other `create` in the same script

`create or modify entity`, `create or modify page`, `create or modify microflow` are all
idempotent and re-runnable. `create association` is not — it needs `create or modify
association`. In a numbered, re-runnable build script where every other statement is safe to
replay, this one statement is not, and the failure mode is a duplicate rather than an error.

### (c) `ALTER ENTITY … ADD ATTRIBUTE` reconciles SOME access rules, silently

This is the serious one. When an attribute is added to an entity with several access rules, the
new member is added to the rule with the **widest** member list and **silently skipped on
narrower ones**.

Observed: `Administration.User` gained `Department`; `Administration.Administrator` did not.
mxbuild stays green. The attribute then renders **blank in the UI for the one role that is
supposed to maintain it** — a data-visibility bug that looks like a page defect, with nothing
in the toolchain pointing at the `ALTER ENTITY` that caused it.

## Impact

(a) and (b) cost a failed exec each. (c) produces a **structurally valid model with wrong
security**, discoverable only by opening the app as the affected role. Every gate in the chain —
`check --references`, `mxbuild`, `mx check` — passes it.

## Expected

(a) Checker and executor agree on role qualification.
(b) `create association` behaves like its `create or modify` siblings, or errors clearly on
    re-run rather than duplicating.
(c) `ALTER ENTITY … ADD ATTRIBUTE` adds the new member to **every** access rule that already
    grants member-level access to that entity — or, at minimum, prints which rules it skipped.

## Environment

mxcli against Mendix 11.13.0, Linux container, project with security level PRODUCTION.
