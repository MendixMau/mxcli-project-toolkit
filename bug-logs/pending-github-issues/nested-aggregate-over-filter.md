**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-nested-aggregate-over-filter` — found 2026-09-15
**Status:** NOT YET FILED
**Suggested labels:** bug, microflows, codegen

---

**Title:** `COUNT(FILTER(…))` writes an Aggregate activity with no `List` property — passes `check`, fails the build with CE0012

**Body:**

## Summary

An aggregate applied directly to a list-operation result is accepted by the grammar and by
`check`, written by `exec`, and rejected by mxbuild: the inner list is never wired into the
Aggregate activity's `List` property.

## Environment

- mxcli: `v0.22.0-15-g7b42100d` (`main` HEAD, 2026-09-15)
- Mendix: 11.13.0, blank `mxcli new` scaffold
- Reproducible: yes, 100%

## Steps to reproduce

```mdl
-- fails: check passes, exec writes, native build gives CE0012
CREATE OR MODIFY MICROFLOW Probe.SUB_NestedCount () RETURNS Integer
BEGIN
  RETRIEVE $reqs FROM Probe.Request;
  $n = COUNT(FILTER($reqs, $currentObject/Status = Probe.ENUM_Status.Approved));
  RETURN $n;
END;
```

→ `[error] [CE0012] "The ‘List’ property is required." at Aggregate list activity 'Count'`

**Control — the same logic split across two variables builds at 0 errors:**

```mdl
CREATE OR MODIFY MICROFLOW Probe.SUB_SplitCount () RETURNS Integer
BEGIN
  RETRIEVE $reqs FROM Probe.Request;
  $approved = FILTER($reqs, $currentObject/Status = Probe.ENUM_Status.Approved);
  $n = COUNT($approved);
  RETURN $n;
END;
```

One error per nested aggregate: a microflow with three such expressions produced exactly three
CE0012s, one per `Count` activity.

## Impact

`FILTER` + `COUNT` is the ordinary way to answer "how many of these match", and the nested
spelling is the one an author — or an LLM — writes first, because it reads like every other
language. It is silently unbuildable, and the build error names a BSON property the author
never wrote, so it is not diagnosable from the MDL.

## Workaround

Never nest an aggregate over a list operation; assign the list operation to its own variable
first.

## Suggested fix

Either lower the nested form correctly (materialise the inner list into an implicit variable
and point the Aggregate's `List` at it), or refuse it at `check` time with a rule that names
the two-variable rewrite. Refusing would be a large improvement over the current silence.
