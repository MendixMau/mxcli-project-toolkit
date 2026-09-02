# Workflow Structure Rules — what the Mendix engine accepts, stated for an MDL author

**Applies to:** any mxcli project designing, extending or reviewing a Mendix native Workflow.
**Purpose:** the platform rules a workflow must satisfy *regardless of tool* — where a path may
end, what a boundary event or event sub-process may contain, how many outcomes an activity
needs, who a task may target, which edits break running instances. `learned-workflow-patterns.md`
is the MDL syntax and the mxcli defect record; this file is the shape the model must have before
any syntax is written. Read this at design time (architecture blueprint, module brief) and again
when a Studio Pro error code in §10 shows up after a clean `mxcli check`.

**Source:** the Mendix MCP team's `workflow-common` / `workflow-update` skills (received
2026-09-02), written for Studio Pro's model-SDK lane (`Workflows$…` types, `ped_update_document`).
Translated here to construct names an MDL author sees; the SDK mechanics were deliberately dropped
— this toolkit keeps MDL and the CLI as the writing path. **What is NOT verified here:** that mxcli
can express every construct below. §11 says which forms are proven in MDL and which are not — a
rule in this file is a constraint on the *model*, never evidence that a given MDL form exists.
Probe with `mxcli check` before relying on an unproven form (`learned-workflow-patterns.md` §11
is the methodology); where it fails, flatten to the happy path and hand-add in Studio Pro.

---

## 1. Every path ends exactly once

A flow is a list of activities. **Nothing may follow a terminal activity**, and a path counts as
ended when its last activity is one of:

- an explicit end — *End workflow*, *Jump to*, or the path-specific ends in §2/§4;
- an outcome-bearing activity (user task, decision, call microflow) **every** outcome of which is
  itself ended, recursively.

Two failures this prevents, both invisible to `mxcli check`:

- **Unreachable activity** (CE6689): an activity written after an *End* or *Jump* in the same
  flow. In MDL this is any statement after the branch that terminated — move it inside the
  branch that should reach it (`learned-workflow-patterns.md` §11), or into an event
  sub-process if it is cancellation logic (§3).
- **Multiple ends**: force-appending an *End* to a flow whose last outcome activity already
  ends on every branch. If every outcome ends, the activity ends — do not add another.

The main flow is `Start → … → End`. New activities go after the start and before the end (or
before a *Jump*, when the main flow ends on one).

## 2. Boundary events — type decides the terminator

A boundary event hangs on one parent activity. Only these can carry one: *wait for
notification*, single-user task, multi-user task, *call microflow*, *call workflow*.

| The request says | Type | Its path MUST end with |
|---|---|---|
| "cancel / abort the task if…", "time out and stop", "escalate and close" | **Interrupting** — aborts the parent | *End workflow* or *Jump to* (Jump may return to the main path) |
| "if it times out, go to <other task>" | **Interrupting** | *Jump to* the named target |
| "send a reminder while waiting", "log status during…", "notify but continue" | **Non-interrupting** — parent keeps running | *End of boundary event path* — waits for the parent to complete, then continues |

Wrong pairings are rejected by Studio Pro: an interrupting path ending in *end of boundary
event path*, or a non-interrupting one ending in *End workflow*. Decide the type **before**
writing the body; the terminator follows from it. Whether the task deserves a timer at all is a
separate question — `learned-workflow-patterns.md` §19: no SLA in the requirements, no timer.

## 3. Event sub-processes — cancellation lives outside the main flow

An event sub-process is a **sibling of the main flow, not part of it**. It has its own flow,
which begins with exactly one start event, of one of four kinds: {notification, timer} ×
{interrupting, non-interrupting}.

- **Notification-triggered** — fired by the `NOTIFY WORKFLOW` microflow statement, matched on
  the *notification name*, not the sub-process name. The payload is visible inside.
- **Timer-triggered** — fired at `firstExecutionTime` (a workflow expression, §8; Studio Pro's
  default is `addDays([%CurrentDateTime%], 1)`). Only the **non-interrupting timer** may recur:
  `interval ≥ 1`, unit one of Minute/Hour/Day/Week/Month (Second and Year exist in the enum and
  are refused), `maxExecutions ≥ 2` counting the first fire. A value outside those bounds is
  refused, not rounded — say so, offer the nearest legal value, never report it as applied.
- **Interrupting** cancels the main flow *and every other running sub-process* first, then
  runs. Use for abort/override. **Non-interrupting** runs in parallel: notifications, audit,
  monitoring.

Hard constraints: one live instance per defined sub-process (a second trigger returns `false`
and starts nothing); the workflow stays *In Progress* until the main flow **and** every active
sub-process have ended; no nesting; jumps never cross between the main flow and a sub-process
or between two sub-processes (within one: jump to its start aborts and re-arms, jump to its end
completes). A sub-process sees the context object, its own variables and the trigger payload —
**not** main-flow variables or decision outcomes; read from the database or pass it in the
notification. The sub-process flow ends by §1's rule; *end of boundary event path* is never
legal inside one — that activity belongs to §2 only.

Replacing the start event (timer ↔ notification, interrupting ↔ not) is a remove-then-add;
removing the start event *alone* leaves an invalid sub-process. Ask which the user meant —
change the trigger, or delete the whole sub-process. A recurrence does not survive the switch
to an interrupting timer; say that it is lost.

Naming: `ESP_<Purpose>`.

## 4. Parallel split — branches end locally, never the instance

- At least **two** paths (CE1845 below that).
- No *End workflow* anywhere inside a branch, at any depth — including outcomes of a user task
  nested in the branch (CE1844).
- No *Jump to* inside a branch (MW0012), and a jump placed under a split may never target
  *End workflow*.
- Each branch closes with *end of parallel split path*.

"End the workflow from inside a branch" is not expressible; end the branch and model global
cancellation as an interrupting event sub-process (§3). Before flagging a missing split, read
`DESCRIBE WORKFLOW` — `learned-workflow-patterns.md` §18.

## 5. Outcomes

- A single- or multi-user task always has **≥ 1** outcome; a parallel split **≥ 2**. A request
  to "remove all outcomes" removes the extras and keeps the minimum.
- **A lone outcome carries no body.** When an activity has exactly one outcome, the activities
  belong after the activity in the parent flow, not nested inside the outcome. That is the rule
  behind the CE1876 inconsistency noted in `learned-workflow-patterns.md` §6: the single-outcome
  form that passes is the empty block.
- **Enumeration decisions always include the Empty path**, routed somewhere sensible (typically
  a user task to supply the missing value). An unassigned enum with no Empty outcome stalls the
  instance. Enum outcome values are fully qualified: `Module.Enumeration.Value`.
- A *call microflow* branches on what the microflow returns: void → no outcomes; boolean → two;
  enumeration → one per value acted on (`learned-workflow-patterns.md` §16 for the dead-branch
  smell).

## 6. User targeting — derive it from the sentence, then confirm

| The request says | Mechanism |
|---|---|
| a role or attribute is named ("managers", "admins", "active reviewers") | XPath over users, filtered on role |
| a noun *performs the action* ("the manager approves", "team lead signs off") — the subject **is** the target | XPath over users — a role in an approval sentence is targeting, not colour |
| "HR **or** manager can approve" | **one** task, one XPath with `or` — never two tasks |
| a workflow *group* is named ("the Finance group") | XPath over `System.WorkflowUserGroup` |
| conditional logic ("the employee's direct manager") | targeting microflow returning `List of System.User` (or of groups) |
| nothing is said | **ask** — `interview-protocol.md`. The MCP team's default is "no targeting, never guess"; in this toolkit the silence is a gate question, and *no targeting* is the recorded `ASSUMED` answer only when the user says "you decide" |

Two rules that do not depend on the mechanism:

- **An empty targeting result fails the instance.** XPath or microflow returning zero users or
  groups is a runtime error, not an unassigned task. Every user task needs an error handler —
  a *change workflow state* (abort / restart / recovery) plus a log line — or a targeting
  expression that provably cannot be empty (an `or` with the Administrator role is the toolkit's
  usual guard, `learned-workflow-patterns.md` §5).
- Prefer **group** targeting for team work: membership is evaluated live, user targeting is
  snapshotted at task creation. Turn on *auto-assign when targeting yields one user* where the
  logic guarantees exactly one.

An unfamiliar role name ("vendor", "inspector") is still a role: target it and tell the user to
confirm the role exists — do not downgrade to no targeting because the word is unusual.

XPath syntax note: the MCP team writes role filters as `System.UserRoles = '[%UserRole_X%]'`;
the form field-proven from MDL is `System.UserRoles/System.UserRole/Name = 'X'` (three
segments, CE0161 below that — `learned-workflow-patterns.md` §5). Both are legal Mendix XPath;
the token form has not been probed through mxcli's single-quoted string, so use the proven one.

## 7. Multi-user tasks

Pick the decision method from the business rule, not the default: **consensus** (all agree),
**veto** (one dissent decides), **majority** (absolute > 50 % or relative), **threshold** (a
count or percentage — quorum), **microflow** (custom aggregation). Completion timing: *when the
outcome is known* (default — 6 of 10 cast and the majority is already decided) versus *when all
participants completed* (you need every response on record). A microflow decision method that
returns no outcome fails the instance — always return a default.

## 8. Expressions — two variables, nothing else

Workflow expressions (decision conditions, due dates, timer `firstExecutionTime`, wait-for-timer
delay, name/description parameters `{1}`, `{2}`) see exactly `$WorkflowContext` (your context
entity) and `$WorkflowInstance` (`System.Workflow`). `$currentUser`, `$currentSession` and any
microflow variable are **not** available — anything that needs them goes in a called microflow.
Non-string values are converted (`toString`, `formatDateTime`) before use in captions.
`learned-workflow-patterns.md` §15 adds the mxcli-side limit: no bracketed association filter in
a decision expression — that is a microflow with a `RETRIEVE`.

## 9. Versioning — which edits break running instances

Relevant the moment a workflow is redeployed with live cases (migration cutover, any Stage 6+
change). **Safe:** adding activities to paths not yet executed; removing activities from the
path currently executing; reordering within an active path; changing properties (names,
microflows, pages, due dates, completion conditions); adding outcomes to a decision.
**Conflicting:** replacing the context entity; deleting the definition; removing the activity an
instance is *on*; introducing a parallel split into an active path; moving activities out of
their original scope. Conflicts surface per instance as *abort / restart / mark resolved* — plan
a *Jump to* based migration or accept the manual resolution, and rehearse against a copy with
in-flight instances before touching production. `learned-workflow-patterns.md` §14's recovery
note carries the same warning for a full regeneration.

## 10. Studio Pro error codes this file explains

| Code | Meaning | Section |
|---|---|---|
| CE6689 | activity unreachable — written after a terminal | §1, §3 |
| CE1844 | *End workflow* inside a non-linear path (parallel branch) | §4 |
| CE1845 | parallel split with fewer than two paths | §4 |
| MW0012 | *Jump to* inside a parallel branch | §4 |
| CE1834 | user task has no page | task page rules, `learned-workflow-patterns.md` §4 |
| CE1876 | single-outcome shape | §5 |
| CE0161 | targeting XPath malformed | §6 |

`learned-workflow-patterns.md` §9 holds the MDL-side codes (CE7412, CE1571, CE0111, …).

## 11. MDL coverage — proven versus unprobed

| Construct | MDL status (as of 2026-09-02) |
|---|---|
| user task, outcomes, targeting XPath / microflow, call microflow, call workflow from a microflow, notify workflow, parallel split | **proven** — `build/workflow-example.mdl`, `learned-workflow-patterns.md` §6–§7 |
| decision | proven on mxcli ≥ v0.18.0, corrupts the `.mpr` below that — `learned-workflow-patterns.md` §8 Warning 1 |
| boundary event timer | proven body syntax, §19 there |
| jump to, end of parallel split path, end of boundary event path as explicit statements | **unprobed** — the example builds branch termination by nesting, never by an explicit end |
| multi-user task, decision method, completion timing | **unprobed** |
| event sub-process (all four start kinds), recurrence | **unprobed** |
| wait for notification, wait for timer, boundary event on notification | **unprobed** — `learned-workflow-patterns.md` "Notes on scope" |
| AI agent task activity | **unprobed** — the MCP team's rules (companion microflow first, outcomes mirror its return values) are model rules and hold whichever tool writes it |

Probe result → update this table and `learned-workflow-patterns.md` in the same commit. A row
that stays *unprobed* is a legitimate "hand-add in Studio Pro" at build time, never a silent
omission from the module's checklist.
