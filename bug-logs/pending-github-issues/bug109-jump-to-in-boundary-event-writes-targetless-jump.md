**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-109` (probe on a blank scratch app, 2026-09-03, mxcli v0.20.0, Mendix 11.14.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, workflow, codegen
**Duplicate check:** #1005 covers a *dangling* jump target stored as self-reference (CE6681). This is a *valid* target inside a boundary-event body written with no Target and a colliding name (CE0495 + CE6680). Related, not the same; cite #1005 when filing.

---

**Title:** `JUMP TO <task>` inside an interrupting boundary-event body writes a Jump activity named after its target with no `Target` property — native `mx check` fails CE0495 + CE6680; the same statement in a user-task outcome is fine

**Body:**

## Summary

```sql
USER TASK A 'A' PAGE Probe.WF_TaskPage OUTCOMES 'Done' { }
  BOUNDARY EVENT INTERRUPTING TIMER 'addDays([%CurrentDateTime%], 3)' { JUMP TO A; };
```

`mxcli check --references` passes, `exec` writes, `DESCRIBE WORKFLOW` reads it back as `jump to A;`. Native `mx check`:

```
[error] [CE0495] "Duplicate name 'A'." at User task 'A', Jump 'A'
[error] [CE6680] "The 'Target' property is required." at Jump 'A'
```

The generated Jump is *named* after its target instead of *pointing* at it.

## Scope

`JUMP TO A;` inside a **user-task outcome** writes correctly and passes `mx check` with 0 errors (verified in isolation). The defect is specific to a boundary-event body.

## Consequence

An **interrupting** boundary event cannot be expressed correctly in MDL at all. Mendix requires its path to end in *End workflow* or *Jump to* (CE0105 otherwise, which fires on an empty body). `END WORKFLOW`, `END`, `END FLOW` and `END OF BOUNDARY EVENT PATH` are all parse errors as statements inside the body, and `JUMP TO` is this bug. Non-interrupting boundary events are unaffected.

## Environment

- mxcli v0.20.0 (2026-08-28); Mendix 11.14.0; fresh `mxcli new` scratch app

## Expected

The Jump activity in a boundary-event body gets a generated unique name and `Target = <task id>`, the same as the user-task-outcome path.
