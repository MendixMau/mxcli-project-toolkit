**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-102` (discovered 2026-08-26 on a real project, mxcli built from source at `4b58b89`; Mendix 11.13.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, alter-page, silent-success
**Duplicate check:** searched `ALTER PAGE DataSource DataGrid` 2026-09-03 — #891 (DataGrid2 column edits silently destructive) and #919 (DynamicCellClass) are siblings, not this. Distinct from our #-pending BUG-84 (DataView datasource *wiped*).

---

**Title:** `ALTER PAGE … SET DataSource = DATABASE … WHERE … ON <datagrid>` reports "Altered page", passes mxbuild, and never changes the persisted XPath

**Body:**

## Summary

On a native (classic) DataGrid, `ALTER PAGE { SET DataSource = DATABASE FROM <Entity> WHERE [...] ON <widget> }` exits 0 with `Altered page <Module.Page>`, the model passes `mxbuild` with 0 errors, and `DESCRIBE PAGE` immediately afterwards shows the **pre-exec XPath verbatim**. Reproduced twice in a row on the same widget: once adding a clause, once removing a different clause. Both times nothing changed.

The running app kept throwing the same `SecurityRuntimeException: No access rights for System$WorkflowDefinition/Name` after the "fix" that was supposed to remove that XPath clause, because the clause was never removed.

## Environment

- mxcli: built from source at `4b58b89` (2026-08-26)
- Mendix: 11.13.0
- Page: a task-inbox page with a native `datagrid` whose datasource is `DATABASE System.WorkflowUserTask` plus an XPath constraint
- Verification: `DESCRIBE PAGE` on the committed `.mpr`, extracted with `git show <commit>:<App>.mpr` into an isolated temp directory (no running process, no catalog cache, no working-tree state)

## Steps to reproduce

1. Create a page with a native DataGrid on `System.WorkflowUserTask` with `WHERE [System.WorkflowUserTask_Assignees = '[%CurrentUser%]']`.
2. Run:

```sql
ALTER PAGE M.Tasks {
  SET DataSource = DATABASE FROM System.WorkflowUserTask
    WHERE [System.WorkflowUserTask_Assignees = '[%CurrentUser%]' or System.WorkflowUserTask_TargetUsers = '[%CurrentUser%]']
          [State = 'InProgress']
    SORT BY StartTime ASC
} ON "dgTasks";
```

3. Observe `Altered page M.Tasks`, exit 0; `mxbuild` 0 errors.
4. `DESCRIBE PAGE M.Tasks` → the `TargetUsers` clause is absent; the XPath is byte-identical to step 1.

Run a second `ALTER PAGE … SET DataSource` that *removes* a clause: same result, clause still present.

## Expected vs. actual

**Expected:** the DataGrid's persisted datasource XPath changes, or the command errors out saying the property is not alterable on this widget type.

**Actual:** success reported, mxbuild clean, XPath unchanged. Two success signals agree and both are wrong.

## Severity

High. Silent success on a security-relevant property (the XPath decides which rows a user sees). It only surfaces by running the app.

## Workaround

`CREATE OR REPLACE PAGE` with the corrected XPath. Verified reliable: `DESCRIBE PAGE` shows the new value immediately after exec.

## Suggested fix

Either make `SET DataSource` on a native DataGrid actually rewrite the datasource unit, or reject it with an explicit message the way the DataView type change (#855) does. A no-op that prints "Altered page" is the worst of the three.
