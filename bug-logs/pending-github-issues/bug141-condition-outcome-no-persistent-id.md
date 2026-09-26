**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-141`. Observed 2026-09-26 on a card-disbursement
requirements-driven build (Mendix 11.13.0, mxcli v0.24.0).
**Status:** NOT YET FILED. Before filing, check the issue tracker for a duplicate and re-read
`conditionOutcomeToGen()` on current `main`.
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

## Suggested fix

One line in each of the three `case` arms of `conditionOutcomeToGen()`, before `return g`:

```go
addFreshPersistentID(g)
```

`WorkflowsBooleanConditionOutcome.PersistentID` is already in `generated/metamodel/types.go`.

## A related question

`addFreshPersistentID`'s comment says it mints a new GUID on every save. If
`create or replace workflow` re-mints the IDs of outcomes and activities that already have
one, re-running a workflow script against a database with live instances would cause the same
`Incompatible` state, for user-task outcomes too. We have not probed that. Could the writer keep
an existing `PersistentId` when it rewrites a unit?
