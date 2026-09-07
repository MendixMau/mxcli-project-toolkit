**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-109` — found 2026-09-03 during a workflow
construct probe on a blank scratch app (mxcli v0.20.0 / Mendix 11.14.0), while validating
`skills/workflow-structure-rules.md` §11
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1024 (2026-09-04)
**Suggested labels:** bug, workflow, codegen

---

**Title:** `JUMP TO <activity>` inside a boundary-event body writes a Jump with no `Target`,
named after its target — so an interrupting boundary event cannot be expressed correctly

**Body:**

## Summary

A `JUMP TO A;` statement placed inside a `BOUNDARY EVENT … { }` body passes `mxcli check
--references`, is written by `exec`, and reads back from `DESCRIBE WORKFLOW` as `jump to A;`.
But the generated Jump activity is *named* `A` instead of *targeting* `A`, so native `mx check`
reports a duplicate name and a missing `Target`.

The same statement inside a **user-task outcome** writes correctly and passes `mx check` with
0 errors (verified in isolation). The defect is specific to the boundary-event body.

## Environment

- mxcli: `v0.20.0` (2026-08-28)
- Mendix / mxbuild: `11.14.0`
- Baseline: blank Mendix 11.14.0 project from `mxcli new`
- Reproducible: yes, 100%

## Steps to reproduce

```sql
USER TASK A 'A' PAGE Probe.WF_TaskPage OUTCOMES 'Done' { }
  BOUNDARY EVENT INTERRUPTING TIMER 'addDays([%CurrentDateTime%], 3)' { JUMP TO A; };
```

`mxcli check --references` → clean. `mxcli exec` → written. Native `mx check`:

```
[error] [CE0495] "Duplicate name 'A'." at User task 'A', Jump 'A'
[error] [CE6680] "The 'Target' property is required." at Jump 'A'
```

## Consequence

Mendix requires an **interrupting** boundary event's path to end in *End workflow* or *Jump
to* (CE0105 fires on an empty body). In MDL, `END WORKFLOW`, `END`, `END FLOW` and
`END OF BOUNDARY EVENT PATH` are all parse errors as statements, and `JUMP TO` is this bug —
so there is currently no way to write a valid interrupting boundary event. Non-interrupting
boundary events are unaffected.

## Expected

The Jump inside a boundary-event body gets a generated name and `Target = A`, exactly as the
outcome-body form already does.

## Workaround

None in MDL. Add the interrupting boundary event by hand in Studio Pro after the rest of the
workflow is scripted.
