**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-107` — found 2026-09-03 during a workflow
construct probe on a blank scratch app (mxcli v0.20.0 / Mendix 11.14.0), while validating
`skills/workflow-structure-rules.md` §11
**Status:** NOT YET FILED
**Suggested labels:** bug, workflow, crash

---

**Title:** Workflow `CALL MICROFLOW … WITH (Param = $Var)` — an unquoted value segfaults the
binary (nil-pointer panic in `buildWorkflowCallMicroflow`) instead of reporting an error

**Body:**

## Summary

In a `CREATE WORKFLOW` body, the `WITH (…)` clause of `CALL MICROFLOW` only accepts a **quoted
string** as the value. Writing the value as a bare variable — the spelling used for the same
expression everywhere else in MDL — crashes the process with a SIGSEGV. The crash fires on
`check`, on `check --references` and on `exec`, and it produces no diagnostic beyond the Go panic.

The error path that *should* catch this already exists and is correct: omitting the clause
entirely makes `--references` print a helpful hint. But that hint recommends the exact spelling
that crashes (see below), so the tool talks the author into the segfault.

## Environment

- mxcli: `v0.20.0` (release build dated 2026-08-28)
- Mendix / mxbuild: `11.14.0`
- Baseline: a blank Mendix 11.14.0 project scaffolded by `mxcli new`
- Reproducible: yes, 100%

## Steps to reproduce

```sql
CREATE WORKFLOW Probe.T PARAMETER $Context: Probe.Request
BEGIN
  CALL MICROFLOW Probe.ACT_Noop WITH (Ctx = $WorkflowContext);   -- SIGSEGV
END WORKFLOW;
```

```
mxcli check probe.mdl            # panics
mxcli check probe.mdl -p App.mpr --references   # panics
mxcli exec  probe.mdl -p App.mpr # panics
```

Output:

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x2 addr=0x58 pc=0x1059e618c]
github.com/mendixlabs/mxcli/mdl/visitor.buildWorkflowCallMicroflow(...)
	github.com/mendixlabs/mxcli/mdl/visitor/visitor_workflow.go:565 +0x5ec
```

## What discriminates the crash

Only the quoting of the value. Four spellings probed:

| Written | Result |
|---|---|
| `WITH (Ctx = $WorkflowContext)` | **panic** |
| `WITH (Probe.ACT_Noop.Ctx = $WorkflowContext)` | **panic** |
| `WITH ("Ctx" = '$WorkflowContext')` | works |
| `WITH (Probe."ACT_Noop"."Ctx" = '$Context')` | works |

The quoted form is verified end-to-end: `exec` writes it, native `mx check` reports 0 errors,
and `DESCRIBE WORKFLOW` reads it back as `call microflow Probe.ACT_Noop with (Ctx = '$WorkflowContext')`.

The panic happens before any write, so the `.mpr` is left intact (confirmed with a native
`mx check` afterwards).

## Why this is worth fixing rather than documenting

Omit the clause and `check --references` says:

```
- call microflow 'Probe.ACT_Noop': parameter 'Ctx' is not mapped — Mendix requires every
  parameter of a workflow call-microflow to be mapped (add `with (Ctx = ...)`)
```

That hint models an unquoted left side and an unquoted right side — the spelling that crashes.

## Expected

Either accept the bare-variable value (consistent with the rest of MDL), or reject it with a
parse/validation error naming the required quoted form. Never a panic.

## Workaround

Quote the value: `WITH ("Ctx" = '$WorkflowContext')`.
