**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-system-enumerations-undiscoverable` — found 2026-09-15
**Status:** NOT YET FILED
**Suggested labels:** enhancement, cli, discoverability

---

**Title:** `System` enumerations are invisible to `show` / `describe` / `search`, so their values can only be found by guessing until CE1613

**Body:**

## Summary

`describe entity` happily prints attributes typed against System enumerations, but the
enumerations themselves cannot be inspected through any mxcli command — so there is no way to
learn their valid values before the native build rejects a guess.

## Environment

- mxcli: `v0.22.0-15-g7b42100d` (`main` HEAD, 2026-09-15)
- Mendix: 11.13.0, blank `mxcli new` scaffold
- Reproducible: yes, on any scaffold

## Steps to reproduce

```
$ mxcli -p app.mpr describe entity System.WorkflowActivityRecord
  ...
  ActivityType: Enumeration(System.WorkflowActivityType),
  State:        Enumeration(System.WorkflowActivityExecutionState),
  ...

$ mxcli -p app.mpr describe enumeration System.WorkflowActivityType
Error: enumeration not found: System.WorkflowActivityType

$ mxcli -p app.mpr show enumerations          # 8 listed, none from System
$ mxcli -p app.mpr search "WorkflowActivityType"
No matches found.
```

A reasonable guess is then only caught by the native build:

```
[error] [CE1613] "The selected enumeration value
  'System.WorkflowActivityExecutionState.Finished' no longer exists."
```

## Impact

Any MDL that branches on a System enumeration — workflow activity state, user-task completion
type, and anything else the platform models as an enum — has to be written by guess-and-build.
This blocked writing a diagnostic microflow over `GET WORKFLOW ACTIVITY RECORDS` entirely.

Same class as mendixlabs/mxcli#1071 (`check --references` cannot resolve enumerations in an
attribute declaration), from the other direction: mxcli can read the model but will not tell you
what it read.

## Suggested fix

Include System-module enumerations in `show enumerations` and `describe enumeration` — read-only
is fine, nobody needs to write them — and let `search` index them. Failing that, have the
MDL-side rule behind CE1613 list the values that do exist.
