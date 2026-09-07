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

**Where this file deliberately differs from that source** (a conflict is resolved toward what a
probe or a field run proved, never toward whichever text is newer):

- *Due dates.* The source lists "missing due dates" as an anti-pattern. This toolkit does not add
  a due date or a timer to a task with no SLA in the requirements — `learned-workflow-patterns.md`
  §19, a field finding from a 15-task approval module where a full-text search of the BRDs turned
  up no deadline language at all. Absence of an SLA is a legitimate "no timer" finding.
- *Targeting XPath form.* ~~The source writes role filters with the token
  `System.UserRoles = '[%UserRole_X%]'`; the form field-proven through mxcli is the three-segment
  path.~~ **Conflict withdrawn, 2026-09-03:** the token form was probed on mxcli v0.20.0 /
  Mendix 11.14.0 and passes `check`, `exec` and native `mx check`. Both forms are proven; the
  source was not wrong. §6.
- *Empty-outcome scope.* Extended here to call-microflow-returning-enum and AI agent task, and
  separated from the dead-branch smell it was being confused with — §5.

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
- **Every enumeration-branching activity carries one outcome per value *plus* an Empty path.**
  This holds for all three: the *decision* activity, a *call microflow* returning an enum, and
  the *AI agent task*. Enum outcome values are fully qualified: `Module.Enumeration.Value`; the
  Empty outcome carries no value. Route Empty somewhere sensible — usually a user task that
  supplies the missing value.

  The failure: an entity attribute left unassigned reaches a decision with no Empty branch and
  the instance **stalls with no error** — it is not an exception, the token simply has nowhere
  to go, so it surfaces days later as "the workflow is stuck" with a green model behind it.

  Do not confuse *outcomes* with *outcome bodies*. `learned-workflow-patterns.md` §16's
  dead-branch smell is about an outcome whose **body** is empty and pointless; it is not
  licence to omit the outcome. Declare every value, leave the bodies you do not act on empty.
- A *call microflow* branches on what the microflow returns: void → no outcomes; boolean → two;
  enumeration → per the rule above.
- An **AI agent task** may only carry `BooleanConditionOutcome`, `EnumerationValueConditionOutcome`
  or `VoidConditionOutcome`, its outcomes must mirror the companion microflow's return values
  exactly, and it may have outcomes at all only once that microflow is assigned. Re-generate the
  outcomes whenever the microflow's return type changes.

## 6. User targeting — derive it from the sentence, then confirm

| The request says | Mechanism |
|---|---|
| a role or attribute is named ("managers", "admins", "active reviewers") | XPath over users, filtered on role |
| a noun *performs the action* ("the manager approves", "team lead signs off") — the subject **is** the target | XPath over users — a role in an approval sentence is targeting, not colour |
| "HR **or** manager can approve" | **one** task, one XPath with `or` — never two tasks |
| a workflow *group* is named ("the Finance group") | XPath over `System.WorkflowUserGroup` |
| conditional logic ("the employee's direct manager") | targeting microflow returning `List of System.User` (or of groups) |
| the assignee is **data on the record**, not a rule ("the person nominated on the request", "whoever the requester picked") | **either** a targeting microflow returning the nominee as a one-element list (proven, §11), **or** no targeting + an *On created* workflow event handler. See "Assignment carried in data" below |
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

**Assignment carried in data.** Where the legacy system stores *who* on the record rather than
deriving it from a role, the four mechanisms above all fit badly — XPath and targeting microflows
answer "which users match this rule", and the answer here is "the one this row names". The
supported shape is: targeting = **none**, plus an *On created* handler on the workflow (the
`onWorkflowEvent` slot, a sibling of the flow — not an activity in it) running a microflow that
reads the nominee off `$WorkflowContext` and writes the task's user association. Roles do not
disappear in that model, they become **eligibility**: keep the role check as a validation on
nomination, not as the targeting expression.

**The other supported shape, and usually the better one: a targeting microflow returning a
one-element list.** "Which users match this rule" and "the one this row names" are not different
questions to a targeting microflow — a microflow that reads the nominee off the context object and
returns `[that user]` is a faithful expression of assignment-by-data, and it is **proven in MDL**
(§11, targeting-microflow row) where the *On created* handler is **not writable from MDL at all** —
probed 2026-09-03, rejected at parse by a grammar that enumerates its own alternatives (§11). It is
reachable over MCP, as a per-task property rather than one workflow-level handler, but that needs a
live Studio Pro. Prefer the microflow
unless something specifically needs the handler. Two things fall out of it for free:

- **The empty-result rule above is satisfied structurally**, without a separate error handler. Write
  the resolver as a fallback chain — nominee if set, else the eligibility list, else a wide backstop
  with a `LOG WARNING` — and it cannot return zero users while any backstop user exists. It also
  tells you in the log when it degraded, which an XPath cannot.
- **One shared resolver, N thin wrappers.** Give the shared microflow a station/step key parameter
  and let each task call a one-line wrapper passing its own literal. Adding a station is then one
  wrapper, not a new rule.

The handler shape stays correct and stays documented — take it when the assignment must be written
onto the task *as a side effect* rather than merely computed, or when a probe shows the slot writes
cleanly from MDL. Recording either choice needs the sentence it came from, per this section's rule.

The failure this avoids: modelling a nominated assignee as an XPath over a role delivers the task
to *everyone* holding that role. On a 15-station process with ~700 nominations per station that is
not a near miss, it is a different application.

An unfamiliar role name ("vendor", "inspector") is still a role: target it and tell the user to
confirm the role exists — do not downgrade to no targeting because the word is unusual.

XPath syntax note: **both role-filter forms are proven from MDL** on mxcli v0.20.0 /
Mendix 11.14.0 (§11) — the MCP team's token `System.UserRoles = '[%UserRole_X%]'` and this
toolkit's three-segment path `System.UserRoles/System.UserRole/Name = 'X'`. The earlier "use the
three-segment form, the token is unprobed" instruction is withdrawn. Do not write a *two*-segment
path: that is the CE0161 this rule was built around (`learned-workflow-patterns.md` §5).

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

The failure, verbatim — these are the two forms agents actually write, and both are rejected:

```
$currentUser/Name                 ← WRONG. Not available in a workflow expression.
$Order/Amount                     ← WRONG. A microflow-style object variable; there is none here.
$WorkflowContext/Order/Amount     ← right: everything hangs off the context entity
$WorkflowInstance/DueDate         ← right: instance metadata
```

Anything genuinely needing `$currentUser` is a *call microflow*, which has it.
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

An operator acting on a running instance also acts on its event sub-processes (§3), which is
easy to miss when writing the runbook for cutover:

| Operation on the workflow | Effect on each active event sub-process |
|---|---|
| Abort | stops permanently — it cannot be re-triggered |
| Restart | aborted and reset to waiting |
| Pause | halted, resumes when the workflow is unpaused |
| Error in the main flow | stops; resumes once the error is corrected |

## 10. Studio Pro error codes this file explains

| Code | Meaning | Section |
|---|---|---|
| CE6689 | activity unreachable — written after a terminal | §1, §3 |
| CE1844 | *End workflow* inside a non-linear path (parallel branch) | §4 |
| CE1845 | parallel split with fewer than two paths | §4 |
| MW0012 | *Jump to* inside a parallel branch | §4 |
| CE1834 | user task has no page | task page rules, `learned-workflow-patterns.md` §4. The page's parameter must be **`System.WorkflowUserTask`** — `System.UserTask` does not exist, and a page built against it never satisfies the check no matter how many times it is re-set |
| CE1876 | single-outcome shape | §5 |
| CE0161 | targeting XPath malformed | §6 |

`learned-workflow-patterns.md` §9 holds the MDL-side codes (CE7412, CE1571, CE0111, …).

## 11. MDL coverage — proven versus unprobed

**Do not trust the date on this table — check the binary.** Every row was established against a
specific mxcli build, and "proven" means proven *on or after* the version named in the row. Run
`mxcli --version` and `mxcli syntax workflow` before relying on a row; absence from `syntax` /
`HELP` is not evidence of non-support (`learned-workflow-patterns.md` §7), but a version below a
row's stated floor is evidence against it.

| Construct | MDL status — probed on **mxcli v0.20.0 / Mendix 11.14.0, 2026-09-03** |
|---|---|
| user task, outcomes, targeting XPath (**both** the three-segment path form and the `[%UserRole_X%]` token form), targeting microflow, call workflow, notify workflow, parallel split (branches terminated **by nesting**) | **proven** |
| **multi-user task** — the activity itself | **proven**. Undocumented in `mxcli syntax workflow`; works anyway |
| **`JUMP TO <activity>`** inside a user-task outcome | **proven** |
| **`WAIT FOR TIMER '<expression>'`** and **`WAIT FOR NOTIFICATION;`** | **proven**. Both undocumented; the notification takes **no name** — that is a Studio Pro property |
| **boundary event timer, non-interrupting** | **proven**, with an **expression**, not an ISO period |
| ~~decision on a **boolean or free-text** outcome~~ | **RETRACTED 2026-09-03 — see the CORRUPTING row below.** This row read "proven on mxcli ≥ v0.18.0" and it was wrong: BUG-76's v0.20.0 retest corrupts on a condition of literal `1 = 1`. The condition never mattered; the defect is in how the *outcome label* is written. Left visible with a strikethrough rather than deleted, because "a boolean decision is the safe kind" is the belief this table has to actively kill |
| call microflow, with or without parameters | **proven** — but the `WITH` clause's **value must be quoted**: `WITH ("Ctx" = '$WorkflowContext')`. Unquoted (`= $WorkflowContext`) segfaults the binary, BUG-107 |
| — | — |
| **decision on an enumeration** | **CORRUPTING — BUG-76**, of which this probe is a re-confirmation on 11.14 (first logged as BUG-108 before the older entry was found). BUG-76 is the general case: *every* `DECISION` with outcomes corrupts, whatever its condition reads. The enum case is the worse one — it has no writable spelling at all, since mxcli rejects both fully-qualified forms and accepts only the bare value that corrupts. Hand-add every decision in Studio Pro; never script one. Recovery: `DROP WORKFLOW` |
| **boundary event timer, interrupting** | **hand-add in Studio Pro.** Its path must end in *End* or *Jump* (CE0105); `END WORKFLOW` does not parse and `JUMP TO` is BUG-109 |
| **boundary event on notification** | **hand-add** — the grammar admits `{TIMER, INTERRUPTING, NON}` only |
| **event sub-process** (all four start kinds), recurrence | **hand-add** — no construct in the grammar, in any position |
| **multi-user decision method / completion timing** | **hand-add** — the activity is scriptable, its decision rule is not |
| **explicit `END WORKFLOW`, end-of-parallel-split-path, end-of-boundary-event-path** | **not expressible, and not needed.** MDL terminates by nesting, which `mx check` accepts. A consequence worth knowing: **CE1844 cannot be triggered from MDL** — §4 governs the diagram and anything hand-added, not the script |
| **user-task `onCreatedEvent`** (the *On created* handler — the mechanism §6 names for assignment carried in data) | **not expressible in MDL, and this is grammar-level, not a docs gap.** The parser enumerates its own alternatives: after `PARAMETER` it accepts only `{BEGIN, EXPORT, DUE, OVERVIEW, DESCRIPTION, DISPLAY}`, and after a user task's `PAGE` only `;`. Four spellings probed (`ON CREATED CALL MICROFLOW`, `ON WORKFLOW EVENT`, task-level `ON CREATED`, `ONCREATEDEVENT`), all rejected at parse. **But it IS on the MCP write path** — `mxcli`'s `CreateWorkflow`/`UpdateWorkflow` payload carries `json:"onCreatedEvent"` on the *user-task* struct, beside `taskPage`, `outcomes` and `boundaryEvents`, and without `omitempty`. So it is a **per-task** property, not one workflow-level handler. End-to-end MCP write **not verified** — that needs a live Studio Pro. Treat as: hand-add, or MCP if you have Studio Pro up (`learned-mcp-patterns.md`) |
| **AI agent task activity** | **unprobed** — its model rules (companion microflow first, outcomes mirror its return values, Boolean/Enum/Void only) hold whichever tool writes it |

**The one thing to take from this table.** `mxcli check` was **wrong on 5 of the 12 constructs
probed**. Three of them passed `mxcli check --references`, passed `exec`, and read back
correctly from `DESCRIBE WORKFLOW` — and were still broken under `mx check`, one of them
leaving the project unopenable. For workflows specifically, **a clean `mxcli check` is not
evidence of anything.** Run native `mx check` after every workflow write, before you believe it.

Probe result → update this table and `learned-workflow-patterns.md` in the same commit. A row
that stays *unprobed* is a legitimate "hand-add in Studio Pro" at build time, never a silent
omission from the module's checklist.

## 12. Before you call a workflow designed — count it

Run this against the drawn diagram (Stage 3) and again against the written MDL (Stage 5). Every
line ends on a number, and the number has a denominator taken from the workflow itself. Write the
counts down; "checked" with no count is the unfalsifiable-checklist failure this list exists to
prevent.

| # | Check | Bound |
|---|---|---|
| 1 | Paths that end exactly once (§1) | N of N paths; 0 activities after a terminal |
| 2 | Boundary events whose type is named **and** whose terminator matches that type (§2) | N of N boundary events |
| 3 | Parallel splits with ≥ 2 paths, and 0 *End workflow* / 0 *Jump to* at **any** depth inside a branch (§4) | N of N splits |
| 4 | Enum-branching activities carrying every value **plus** Empty (§5) | N of N decisions + call-microflows-returning-enum + AI agent tasks |
| 5 | User tasks whose targeting mechanism is named, with the sentence it came from quoted (§6) | N of N user tasks — `ASSUMED: no targeting` is a legal entry, blank is not |
| 6 | User tasks that either have an error handler for empty targeting, or a targeting expression that provably cannot be empty (§6) | N of N user tasks |
| 7 | Multi-user tasks with decision method **and** completion timing stated, sourced to a business rule (§7) | N of N multi-user tasks |
| 8 | Expressions referencing only `$WorkflowContext` / `$WorkflowInstance` (§8) | N of N expressions |
| 9 | Event sub-processes with exactly one start event, correct family, and recurrence within bounds (§3) | N of N sub-processes |
| 10 | Constructs checked against §11 and marked *proven* or *hand-add in Studio Pro* | N of N constructs used; every hand-add is a build-plan checklist row |

A workflow going into a build plan with row 10 unfilled is the omission this file exists to stop:
the model builds, `mx check` is green, and a construct the requirements asked for is simply not
there.
