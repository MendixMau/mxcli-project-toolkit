**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-107` (probe on a blank scratch app, 2026-09-03, mxcli v0.20.0, Mendix 11.14.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, crash, workflow
**Duplicate check:** searched `workflow segfault panic` 2026-09-03 — #1005 (dangling jump target), #945, #948 are workflow issues but none is a panic. New.

---

**Title:** Workflow `CALL MICROFLOW … WITH (Param = $Var)` with an unquoted value panics with SIGSEGV in `buildWorkflowCallMicroflow` — and the `--references` hint tells the user to write exactly that form

**Body:**

## Summary

Inside `CREATE WORKFLOW`, the value in a `WITH (…)` mapping must be a quoted string. Writing it the way every other MDL expression is written crashes the binary:

```sql
CREATE WORKFLOW Probe.T PARAMETER $Context: Probe.Request
BEGIN
  CALL MICROFLOW Probe.ACT_Noop WITH (Ctx = $WorkflowContext);   -- SIGSEGV
END WORKFLOW;
```

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x2 addr=0x58 pc=0x1059e618c]
github.com/mendixlabs/mxcli/mdl/visitor.buildWorkflowCallMicroflow(...)
	github.com/mendixlabs/mxcli/mdl/visitor/visitor_workflow.go:565 +0x5ec
```

The panic fires on plain `check`, on `check --references`, and on `exec`, before any write, so the `.mpr` is left intact.

## Environment

- mxcli v0.20.0 (2026-08-28 release); Mendix 11.14.0; fresh `mxcli new` scratch app

## What discriminates

| Written | Result |
|---|---|
| `WITH (Ctx = $WorkflowContext)` | **panic** |
| `WITH (Probe.ACT_Noop.Ctx = $WorkflowContext)` | **panic** |
| `WITH ("Ctx" = '$WorkflowContext')` | works |
| `WITH (Probe."ACT_Noop"."Ctx" = '$Context')` | works |

The quoted form writes, native `mx check` reports 0 errors, and `DESCRIBE WORKFLOW` reads it back as `call microflow Probe.ACT_Noop with (Ctx = '$WorkflowContext')`.

## Why this is worth fixing rather than documenting

Omit the `WITH` clause and the error path that should catch it already works:

```
- call microflow 'Probe.ACT_Noop': parameter 'Ctx' is not mapped — Mendix requires every
  parameter of a workflow call-microflow to be mapped (add `with (Ctx = ...)`)
```

That hint tells the author to write `with (Ctx = ...)`, unquoted on both sides, which is the spelling that crashes. The tool talks the user into the segfault.

## Expected

Either accept the unquoted expression (consistent with microflow MDL), or reject it with a parse error naming the required quoted form. Never a nil-pointer panic.

## Workaround

Quote the value: `WITH ("Ctx" = '$WorkflowContext')`.
