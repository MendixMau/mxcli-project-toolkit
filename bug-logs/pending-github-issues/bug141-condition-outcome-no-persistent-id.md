**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-141`. Observed 2026-09-26 on a card-disbursement
requirements-driven build (Mendix 11.13.0, mxcli v0.24.0).
**Status:** NOT YET FILED. Before filing, check the issue tracker for a duplicate and re-read
`conditionOutcomeToGen()` on current `main`. The fix and a regression test are ready as one
commit: `bug141-fix.patch` next to this file (`git am` on `main` 95091765). Open it as a PR that
references the issue, or attach it to the issue.
**Suggested labels:** bug, workflow, silent-corruption

---

**Title:** Workflow condition outcomes are written without a `PersistentId`, so in-flight
instances go `Incompatible` on every deploy

**Body:**

## Summary

`conditionOutcomeToGen()` in `mdl/backend/modelsdk/workflow_write.go` writes
`Workflows$BooleanConditionOutcome`, `Workflows$EnumerationValueConditionOutcome` and
`Workflows$VoidConditionOutcome` without a `PersistentId`. Activities, `UserTaskOutcome` and
`ParallelSplitOutcome` all get one through `addFreshPersistentID(g)`.

The runtime identifies an outcome by its persistent ID. The 11.13.0 workflow metamodel builds
`ModelBooleanConditionOutcome(id, value, persistentId, flow, container)`. With none stored, the
outcome is a new outcome after every load. So every workflow instance that has already passed a
decision is marked **`Incompatible`** on the next deploy, with
*"A selected outcome has been replaced in the already executed path"*. That includes a restart
with no model change at all.

## Reproduction

1. `create workflow` with a call-microflow task that has Boolean or enumeration outcomes (or a
   `DECISION`; both reach `conditionOutcomeToGen()`, lines 511 and 556), followed by a user
   task.
2. `mxcli run --local`, start an instance, and let it stop at the user task (`InProgress`).
3. Stop the app and start it again without changing the model.
4. The instance is now `Incompatible`.

Reproduced three times on one model: across a no-change restart, across a redeploy that
changed only unrelated pages, and across a one-line page change. A BSON dump of the workflow
unit shows `PersistentId` on every activity and user-task outcome and on none of the condition
outcomes.

## Why nothing catches it

`check`, `exec`, `describe workflow`, `lint`, mxbuild and `mx check` are all clean. Any test that
starts and finishes an instance within one run passes. It only shows when an instance outlives
a restart, which means in production.

## Fix

One line in each of the three `case` arms of `conditionOutcomeToGen()`, before `return g`:

```go
addFreshPersistentID(g)
```

`WorkflowsBooleanConditionOutcome.PersistentID` is already in `generated/metamodel/types.go`.
The attached commit adds that and `TestConditionOutcomeToGen_HasPersistentID`, which fails on all
three outcome types without the fix and passes with it. `go test ./mdl/backend/modelsdk/
./modelsdk/canon/` is green, and gofmt and vet are clean.

## Verified on a real model

This was v0.24.0 plus the three lines, on the model that reproduced the bug (Mendix 11.13.0):

- Condition outcomes carrying a `PersistentId` went from 0/30 to 30/30. `mx check` reports 0
  errors.
- An instance paused at a user task after the decisions stayed `InProgress` across a restart
  with no model change. The released binary turns it `Incompatible`. After the restart the
  instance ran on to `Completed`.

## Re-running `create or replace workflow`

We worried that `addFreshPersistentID` ("a fresh GUID on every save") would re-mint the IDs
each time a workflow script is re-run. It does not. `canon.CarryPersistentIDs` keeps the stored
IDs. The patched `create or replace` kept all 54 IDs the released binary had written, and a
second re-run kept 84/84. So the fix re-IDs condition outcomes once, on the first write after
upgrading, and the IDs are stable from then on. The release notes might say so: instances paused
past a decision at that one deploy still go `Incompatible`.
