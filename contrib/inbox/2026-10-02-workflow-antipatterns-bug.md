# Workflow anti-patterns an agent build produces and no gate catches — plus an mxcli defect: condition outcomes have no PersistentId, so every restart breaks in-flight instances

**From:** BIA approval-chain prototype (Mendix 11.15.0, mxcli v0.21.0)
**Date:** 2026-10-02
**Kind:** bug
**Field evidence:** found by the owner opening the workflow in Studio Pro; every gate was green — mx check 0 errors, lint 0 errors, journey e2e 14/14, coverage e2e 14/14. The workflow works; it does not read as the process it implements, and nothing in the pipeline looks at that.
**Proposed target:** `skills/workflow-patterns.md` or a new `skills/learned-workflow-shape.md` (rules) · two lint rules (below) · `skills/learned-detection-gaps.md` (gap row) · BUG-76 retest with qualified enum outcomes · **new ledger entry + `project-bin/` patcher for §4**

Three anti-patterns, one workflow. Each is noise or a hole a human sees in five seconds on the
canvas and no gate sees at all. Fixing them surfaced a fourth item that is not a shape problem
but an mxcli serialisation defect with runtime consequences (§4).

---

## 1. A Call Microflow with true/false outcomes that both do nothing

### What happened

```
'Kesinlestir' {
  call microflow App.WFA_Finalise with (Process = '$WorkflowContext')
    outcomes
      true -> { }
      false -> { };
}
```

The script never wrote those outcomes (the build script is a bare
`call microflow ...;`). They exist because `WFA_Finalise` was declared `returns Boolean` and ends
in `return true;` — and a workflow Call Microflow activity whose microflow returns a Boolean or
an enumeration **gets one outcome per value automatically**. Studio Pro does the same.

### Why it is noise, not harmless

- The canvas draws a **split**. A reader assumes the `false` path handles a failure. There is no
  failure path: the microflow cannot return false, and a real failure throws, which a `false`
  outcome would never see.
- Both branches re-join immediately, so the split carries zero information and costs a level of
  diagram height on every view.
- The `return true` is dead code that looks like a success flag. The next agent "fixes" the empty
  `false` branch by adding error handling that can never run.
- Root habit, visible across the same script: 3 of the 8 microflows in the workflow script are declared
  `returns Boolean`, and all 3 end in `return true`. Microflow-land "return a success flag" habit,
  carried into a context where the return value becomes **control flow**.

### The rule

> **A microflow called from a workflow returns nothing unless the workflow branches on its
> result.** If it returns a Boolean or enumeration, at least two of its outcomes must lead to
> different activities. Empty-or-identical outcomes on every value = change the microflow to
> return nothing.

Lint candidate (workflow catalog has the activities): flag a `CallMicroflowTask` whose outcomes
are all empty or all structurally identical. Severity: warning.

---

## 2. One user task that loops — every outcome jumps back to itself

### What happened

```
user task Adim 'Approval step'
  targeting users microflow App.TGT_Step
  outcomes
    'Ileri' { jump to Adim; }
    'Iade'  { jump to Adim; }
    'Kesinlestir' { ... }
```

Owner → unit manager → Risk & Compliance → executive is a four-role chain. On the canvas it is
**one box** with "Forward" and "Return" both pointing back at that same box. Whose turn it is
lives in an attribute (`Process.Step`); a targeting microflow reads it. The routing — the actual
business process — is invisible in the workflow and lives in decision microflows behind pages.

### Why it was built that way (and why that is now suspect)

The script header records it as a workaround for mxcli v0.21.0: workflow `DECISION` corrupted
the model (BUG-76) and forward `JUMP TO` failed (CE6681), so a chain that can be entered
mid-way (seeded data already at the Risk step; units without a manager skipping step 2) could
not branch.

**Status of the workaround's reasons:** the ledger has BUG-76 **confirmed still open on v0.21.0**
(2026-09-14, project unloadable). The current `mxcli syntax workflow` now documents enum
decisions (qualified `Module.Enum.Value` outcomes, plus a `''` outcome; a bare value is called
out as making the project unloadable), `end workflow`, boundary timers and event handlers. A
four-task workflow with an enum entry decision, a forward jump, a Boolean decision and an
`end workflow` **passed `mxcli check`** on a throwaway copy (2026-10-02). Apply + `mx check` was
not run, so this is a hypothesis to retest, not a fix claim: BUG-76's original signature used
bare outcome labels (`'OutcomeA'`), and the qualified-value form may be the way through.

### What it costs

- A business reviewer — the audience the workflow exists for — sees nothing of the process.
- The Workflow Admin / task inbox shows every task as "Approval step"; you cannot tell an
  executive sign-off from an owner's survey without opening it.
- Per-step features hang off distinct tasks: a deadline timer on the owner step, a different
  page per role, step-level reporting. One task gets none of them.
- The decision screens set the outcome *and* the next Step by hand; the workflow is reduced to a
  task dispenser. Two sources of truth for "where is this process".

### The rule

> **One user task per role or decision point, named for it.** A jump is for a loop the business
> recognises (a return to the owner), never the only edge out of a task. If every outcome of a
> task jumps to the same task, the workflow is a dispatcher and the process is hiding in
> microflows — STOP and redesign.

Lint candidate: flag a user task where every outcome ends in `jump to <itself>`.

---

## 3. No way to stop it

The only path to the End is final approval. There is no withdraw, no cancel, no expiry, so a
process that is retired from the inventory or never approved stays an open workflow with an open
task forever — in the inbox, in counts, in the Workflow Admin.

> **Every workflow names how it stops besides success** — at minimum a cancel outcome on the
> step that owns the decision (`end workflow comment 'Cancelled'`), and an interrupting timer
> where there is a deadline.

---

## Detection gap (why every gate was green)

| Gate | Sees it? |
|---|---|
| `mxcli check` / mx check | no — all three are valid models |
| `mxcli lint` (all rules, incl. CONV020) | no — no workflow-shape rules |
| `mxcli report` | no |
| e2e journey + coverage (28 steps) | no — behaviour is correct |
| A human opening the workflow in Studio Pro | **yes, in seconds** |

Add to `learned-detection-gaps.md`: *workflow shape is unchecked; render or DESCRIBE the
workflow and read it as the business would before calling a workflow done.*

## 4. mxcli defect: condition outcomes are written without a PersistentId

### What happened

Rebuilding the workflow as one task per role, each behind a step check (a Call Microflow with
Boolean outcomes, chosen because a scripted DECISION is BUG-76), passed every gate: mx check 0
errors, journey e2e 14/14. Then the app was restarted on the same model, and coverage dropped to
**9/14**. Every in-flight instance (7/7) had gone `Incompatible`:

> *The workflow can not be run due to the following conflicts: A selected outcome has been
> replaced in the already executed path.*

`system$workflowversion` had gained a second row, though the model had not changed between the
two starts (unit file mtime older than both runs).

### Root cause, measured

- Diffing the two stored version JSONs: exactly **9** `modelId`s differed. They were the 8
  true/false outcomes of the 4 call-microflow step checks and the 1 void outcome of the final call.
- The runtime keys workflow elements on **`PersistentId` only**: of 30 runtime ids, 21 matched a
  `PersistentId` in the unit, **0** matched an `$ID`, and 9 matched nothing.
- In the unit BSON, `Workflows$UserTaskOutcome` carries `$ID, $Type, Flow, PersistentId, Value`.
  `Workflows$BooleanConditionOutcome` carries `$ID, $Type, Flow, Value`, with **no `PersistentId`**.
  The same goes for `VoidConditionOutcome`, and by the same writer presumably for
  `EnumerationValueConditionOutcome` (not probed).
- With no stored id, a fresh random one is generated on every build. So **every redeploy changes
  the definition**, and every instance whose executed path already includes a condition outcome is
  marked Incompatible.

### Why it hid until now

A Boolean outcome on the *last* step (the original design's Finalise call) is never in an
in-flight instance's executed path: the instance completes right after it. The defect only shows
once a condition outcome sits mid-flow, which is exactly where the rules in §1–§2 push you while
BUG-76 rules out DECISION. **Every gate is blind to it:** mxcli check, mx check, mxbuild and a
first-run e2e all pass. Only a *restart with live instances* shows it. In production that means
the first deploy after go-live strands every open case.

### Fix (proven in the project)

A BSON pass, in the shape of `wf-add-path-terminators.py`. It inserts
`PersistentId: Bin(0, uuid4)` into every `Workflows$*ConditionOutcome` lacking one. It is
idempotent and runs via `exec.sh --patch`. Verified:

| Check | Before patch | After patch |
|---|---|---|
| native mx check | 0 errors | 0 errors |
| seeded DB, then restart ×2: `system$workflowversion` rows | 2 after one restart | **1** |
| instance states after restart | Incompatible:7 | **InProgress:7** |
| coverage e2e on restored data | 9/14 | **14/14** |

**Like the terminator pass, it must re-run after any script that rewrites the workflow.**

### Proposed

1. Ledger entry in `bug-logs/mxcli-bugs.md` and upstream issue: the writer should emit
   `PersistentId` on condition outcomes, as it does on user-task outcomes.
2. Promote the patcher to `project-bin/wf-add-outcome-persistent-ids.py`.
3. Add a row to `learned-detection-gaps.md`: *workflow versioning is only tested by a restart with
   live instances; add "restart, then assert `system$workflowversion` did not grow and nothing
   is Incompatible" to the workflow verification step.*
4. Add to `learned-workflow-patterns.md`: until fixed, any call-microflow or decision outcome
   mid-flow needs the patcher.

---

## Fix in the project (done 2026-10-02)

- `WFA_Finalise` returns nothing (no outcomes on its call).
- One user task per role: owner submit → unit approval → risk review → executive approval →
  Finalise. Each task sits behind a call-microflow step check with Boolean outcomes that really
  branch. **No DECISION** (BUG-76).
- The decision microflow moves the process step before setting the task outcome. So unit-skip,
  manager-filled surveys and mid-chain seeded processes all route without forward jumps.
- Returns jump back to the owner check.
- 14 activities, 4 user tasks, 0 decisions; mx check 0 errors; journey 14/14, coverage 14/14
  after the §4 patch.
- **Still open:** §3. No cancel path yet, deliberately: an outcome with no UI to trigger it would
  be another dead outcome. It should land together with a cancel action that requires a reason.
