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

> **mxcli does not emit that terminator — and nothing in the toolchain tells you.**
> (Confirmed 2026-09-14 against Studio Pro controls, mxcli v0.21.0 / Mendix 11.13.0.)
> A scripted `PARALLEL SPLIT` passes `mxcli check --references`, `mxbuild --target=deploy`,
> native `mx check` **and** a `DESCRIBE WORKFLOW` round-trip with every task correctly nested
> — and then the runtime skips every path in the same millisecond, because a path with no
> terminator has no resolvable continuation. On a 16-station approval workflow this silently
> voided 8 stations with no error anywhere.
>
> The MDL grammar has **no keyword** for the terminator, so this is not a script that can be
> written correctly. Either add one node per path by hand in Studio Pro (a palette drop; the
> node has no outbound references), or patch the `.mxunit` BSON directly —
> `bin/wf-add-path-terminators.py` is that pass, and `learned-workflow-patterns.md` §23 is how
> to operate it, including the part that bites: **any later script that rewrites the workflow
> drops the terminators again.** **Count paths, not
> branches** — a nested split needs terminators for its inner paths too.
>
> Verify a split with a **live run** and `system$workflowactivity`. Both build gates pass the
> broken model and the fixed model identically, so a green build is not evidence in either
> direction. See `learned-workflow-patterns.md` §18.

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

Anything genuinely needing `$currentUser` is a *call microflow*, which has it — **but a call microflow does not have `$WorkflowUserTask`.** Its scope is `$currentUser` plus whatever you pass in `WITH`, and what you can pass is `$WorkflowContext` / `$WorkflowInstance` only. See the *call microflow* row in §11.
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

> **Current as of 2026-09-15**, rewritten against mxcli **v0.22.0** (tag `e771f490`) and **`main` HEAD**
> (`7b42100d`) — `bug-logs/mxlabs-v0.22.0-retest-2026-09-15.md` carries the probe log. **Say the exact
> binary, never a release or branch name:** `end workflow` and the two signature checks merged *after* the
> v0.22.0 tag and are on `main` only — the `nightly` tag is itself a day stale and has neither, so a binary
> built from it fails to parse `end workflow`. Since the 14 September briefing: **BUG-76 and BUG-121 are
> closed** (decision spelling; split terminators, live-run verified), **forward `JUMP TO`** was never broken
> after v0.21.0, a workflow-body **`annotation` is refused** rather than hand-added, and the five hand-add
> rows were probed rather than inferred — including the **AI agent task**, unprobed since July.

**Do not trust the date on this table — check the binary.** Every row was established against a
specific mxcli build, and "proven" means proven *on or after* the version named in the row. Run
`mxcli --version` and `mxcli syntax workflow` before relying on a row; absence from `syntax` /
`HELP` is not evidence of non-support (`learned-workflow-patterns.md` §7), but a version below a
row's stated floor is evidence against it.

| Construct | MDL status. **Rewritten 2026-09-15 against mxcli v0.22.0 (tag `e771f490`) and `main` HEAD (`7b42100d`)** — see `bug-logs/mxlabs-v0.22.0-retest-2026-09-15.md`. Rows marked **CTRL** were probed that day with a known-bad control in the same batch; **UPSTREAM** means upstream's own mxbuild measurement, not re-run here. Older rows carry the binary they were proven on |
|---|---|
| user task, outcomes, targeting XPath (**both** the three-segment path form and the `[%UserRole_X%]` token form), targeting microflow, call workflow, notify workflow | **proven**. Re-probed on **v0.21.0 / Mendix 11.14.0, 2026-09-09** — but see the two SIGNATURE rows immediately below, which are not about whether the construct writes and are how a clean `mxcli check` still yields a project that will not build |
| **a user task's `PAGE`** | **proven, and since `main` HEAD the wrong shape is refused BEFORE it is written — CTRL 2026-09-15.** The page must take `System.WorkflowUserTask`; a page parameterised on the context entity only used to pass `mxcli check --references` clean and fail the native build with CE7412. On `main` it is refused at `check --references`, naming CE7412 and the fix. Upstream's measured shapes: no parameters → CE7410; context entity only (multi-user task too) → CE7412; **`WorkflowUserTask` plus an extra parameter → 0 errors** — extra parameters are legal. Build order consequence stands: **task pages are a prerequisite of the workflow row**, not a later UI row |
| **a targeting microflow's signature** | **exactly TWO parameters — `System.Workflow` and the context entity — and CORRECTION 2026-09-15: the ORDER IS FREE.** This row previously said "in that order"; upstream's mxbuild measurement shows `(System.Workflow, Ctx)` and `(Ctx, System.Workflow)` both at 0 errors, and a **generalization** of the context entity is also accepted (a *specialization* is CE6677). One parameter, none, or a third is CE6677. On `main` HEAD this is refused at `check --references` before anything is written — CTRL 2026-09-15, with a correct pair as the passing control. `mxcli syntax workflow.user-task.targeting` now documents the signature |
| **a called microflow `EXPOSED AS WORKFLOW ACTION`** | **proven 2026-09-15 on `v0.22.0-15-g7b42100d`.** `EXPOSED AS WORKFLOW ACTION '<caption>' IN '<category>'` puts the microflow in the **workflow editor's** toolbox — a different clause from `EXPOSED AS MICROFLOW ACTION`, which fills the *microflow* editor's. Probed end to end: writes, native `mx check` 0 errors on a microflow the workflow also `CALL`s, and `DESCRIBE MICROFLOW` emits the clause back. **It survives a rewrite that omits it** — a later `create or modify` without the clause preserved the stored exposure (measured), so this is not the drop-on-rewrite hazard that bites elsewhere. See `learned-workflow-patterns.md` §25 for when to set it |
| **multi-user task** — the activity itself | **proven**. Undocumented in `mxcli syntax workflow`; works anyway |
| **`JUMP TO <activity>`** inside a user-task outcome | **proven** |
| **`WAIT FOR TIMER '<expression>'`** and **`WAIT FOR NOTIFICATION;`** | **proven**. Both undocumented; the notification takes **no name** — that is a Studio Pro property |
| **boundary event timer, non-interrupting** | **proven**, with an **expression**, not an ISO period |
| decision on a **boolean** outcome | **proven on v0.22.0+.** `OUTCOMES TRUE -> { } FALSE -> { }`; a boolean decision needs **no** empty outcome (that requirement is enumeration-only — `MDL-WF06`). This row was retracted on 2026-09-03 while BUG-76 was open and every DECISION was suspect; BUG-76 is fixed in v0.22.0, so decisions are writable again — see the enumeration row |
| call microflow, with or without parameters | **proven** — with two limits. (1) The `WITH` clause's **value must be quoted**: `WITH ("Ctx" = '$WorkflowContext')`. Unquoted (`= $WorkflowContext`) segfaults the binary, BUG-107. (2) **`$WorkflowUserTask` is NOT in scope here** — only `$WorkflowContext` and `$WorkflowInstance` are. Passing it is a **CE0117** that `mxcli check --references` passes completely clean; only mxbuild catches it. A microflow that needs the task looks it up by name off `$WorkflowInstance` through `System.WorkflowEndedUserTask`. Proven by sandbox A/B on a full project copy, 2026-09-04 — this corrects an earlier reading of §8 that treated *call microflow* as having the task |
| — | — |
| **decision on an enumeration** | **FIXED in v0.22.0 — BUG-76 closed, STOP rule lifted. CTRL 2026-09-15 with two known-bad controls.** Two rules now bind, both enforced at `check`: the outcome must be **fully qualified** `Module.Enumeration.Value` (`MDL-WF03` — the bare label is what made the project unloadable, and it is now refused rather than written), **and** the set must carry an empty `'' -> { }` outcome (`MDL-WF06`/CE6686) — required **even when the attribute is `NOT NULL`**, which is the counter-intuitive half. Both controls fired: bare spelling refused, missing-empty refused; the correct form writes, execs and round-trips through `describe`. **No `--no-check` anywhere** — that workaround is now wrong advice |
| **parallel split**, incl. **nested** | **FIXED in v0.22.0 — BUG-121 closed. No patcher. CTRL 2026-09-15, including a live run.** The builder now writes `Workflows$EndOfParallelSplitPathActivity` on every path itself (verified in the raw `.mxunit`), native `mx check` is clean, and — the part a clean build was never sufficient to prove — **a live instance executed both legs**: `mxcli run --local --ensure-db --test-endpoint`, instance started via `mxcli test --attach`, result read back externally with `mxcli oql`, one completion row per leg from a cold boot. **`bin/wf-add-path-terminators.py` is retired for v0.22.0+** and stays only as the procedure for pre-v0.22.0 binaries (`learned-workflow-patterns.md` §23). One migration step remains unexercised: a split **definition written by a pre-v0.22.0 binary** needs one `create or modify` pass to gain its markers; running **instances** are not migrated by that |
| **forward `JUMP TO`** (target later in the flow than the outcome jumping to it) | **proven — and this row was stale from 2026-09-06 to 2026-09-15.** Upstream `825873d6`, already in **v0.21.0**, fixed the real cause: the jump activity took its *target's* name, and because deduplication renames the second activity with a given name, **forward order was the broken case** while backward accidentally worked. Jumps are now named `JumpTo`/`JumpTo2`. CTRL 2026-09-15: forward jump to a real activity → 0 native errors; the known-bad control, a **dangling** jump, is refused at `check` as `MDL-WF05` naming the real fault. Our v0.21.0 field CE6681 was that dangling case, not direction |
| **boundary event timer, interrupting** | **expected cleared on v0.22.0 — UPSTREAM, NOT PROBED HERE.** The old blocker was that its path must end and MDL had no end-activity: interrupting was CE0105 at build, non-interrupting built at 0 errors and then the **runtime refused to start the app**. v0.22.0 writes `EndOfBoundaryEventPathActivity` on every boundary-event path, and on `main` HEAD `end workflow` is legal inside an interrupting path at any depth. We did not build one — treat as hand-add until somebody does |
| **boundary event on notification** | **hand-add — PROBED 2026-09-15.** `BOUNDARY EVENT NOTIFICATION 'note' { }` on a user task is `mismatched input 'NOTIFICATION' expecting {TIMER, INTERRUPTING, NON}`. **Control in the same batch:** the identical activity with `BOUNDARY EVENT NON INTERRUPTING TIMER '<expr>' { }` parses and checks clean — so the refusal is the clause, not the shape. Note the clause **order**: `OUTCOMES` comes before `BOUNDARY EVENT`, and the reverse is a parse error that looks like the boundary event is unsupported |
| **event sub-process** (all four start kinds), recurrence | **hand-add — PROBED 2026-09-15.** `EVENT SUBPROCESS es1 ON WORKFLOW ABORTED { … }` is `mismatched input 'EVENT' expecting END` — the parser will not begin the statement in any position |
| **multi-user decision method / completion timing** | **hand-add — PROBED 2026-09-15.** `COMPLETION RULE CONSENSUS` on a `MULTI USER TASK` is `mismatched input 'COMPLETION' expecting ';'` — the task statement simply ends where the rule would go. The activity is scriptable; its rule is not |
| **ending a branch — `end workflow`** | **EXPRESSIBLE on `main` HEAD ONLY (`7b42100d`), NOT in the v0.22.0 tag and NOT in the `nightly` tag. CTRL 2026-09-15 with two known-bad controls.** `end workflow [comment '<caption>'];` is legal in any `{ }` block and round-trips through `describe`. Placement is measured: an outcome, a decision branch, a call-microflow outcome or an **interrupting** boundary path → 0 errors; **under a parallel split, at any depth → CE1844 `MDL-WF08`** (control fired); an activity after it in the same block → CE6671 `MDL-WF09` (control fired); `return;` → refused, `MDL-WF11`. **Correction to the 2026-09-14 briefing:** the split fault and this were reported as one grammar gap. They are two — a split path ends *locally and can never end the instance*, which is §4 confirmed independently, so the split was a **writer** defect (fixed in the release) and only this was grammar. The end-of-path markers are no longer an MDL concern at all: the builder writes them |
| **user-task `onCreatedEvent`** (the *On created* handler — the mechanism §6 names for assignment carried in data) | **hand-add — re-probed 2026-09-15 on `main` HEAD, CTRL.** Two spellings tried again: `ON CREATED CALL MICROFLOW …` and `ONCREATEDEVENT …`, both `mismatched input … expecting ';'` — the user-task statement simply ends where the handler would go, so this is grammar-level, not a docs gap. **It IS on the MCP write path** (`onCreatedEvent` on the user-task struct) — end-to-end MCP write still unverified, needs a live Studio Pro. **New on `main`: a rewrite can no longer silently destroy it** — `create or modify` and `REPLACE ACTIVITY` refuse a workflow holding an on-created microflow rather than resetting it to `NoEvent` |
| **`ANNOTATION` in a workflow body** | **REFUSED, and the direction of this row was wrong until 2026-09-15. CTRL.** It was carried as "hand-add"; in fact the annotation lands in the activity flow, which accepts only flow elements, so the written `.mpr` **cannot be LOADED at all** — Studio Pro will not open the project and `mx check` dies before validating anything. `MDL-WF04` now refuses it at `check` **and** at `exec` (probed: both refuse, nothing written). Keep the note as an MDL comment (`-- …`), or add a real annotation in Studio Pro after the last scripted rewrite |
| **AI agent task activity** | **hand-add — PROBED 2026-09-15 on `v0.22.0-15-g7b42100d`, and this row is no longer "unprobed".** `AI AGENT TASK a1 'Assess' OUTCOMES 'Done' { };` inside a `CREATE WORKFLOW` body fails at parse: `mismatched input 'AI' expecting END` — the parser will not begin the statement, so this is grammar-level, not a spelling question. It had carried "unprobed, not broken" since July, which reads as *might work* and quietly kept it out of every hand-add checklist; it is now a known hand-add. Its **model** rules (companion microflow first, outcomes mirror its return values, Boolean/Enum/Void only) still hold whichever tool writes it — §5 |

**HISTORICAL — the v0.21.0 round, 2026-09-09, WITH A KNOWN-BAD CONTROL.** Kept because it is the
method this file asks for, and because the control is why the round was worth having. Its BUG-76
verdict is superseded: fixed in v0.22.0. Four constructs a real approval
chain needs — user task with a targeting microflow, multi-user task, `CALL MICROFLOW` with a quoted
`WITH`, and a backward `JUMP TO` inside an outcome — all build clean on v0.21.0 once the two
signature rows above are respected. That result is only worth having because the same run included
the construct known to be broken: a scripted `DECISION` passed `mxcli check`, reported
`Created workflow`, and left the project **unopenable** —
`Mendix.Modeler.Storage.StorageLoadException: One or more invalid values were detected while
loading the project`, then `BUILD FAILED`. So BUG-76 is open on v0.21.0, and the probe can
distinguish a working construct from a broken one. **A probe with no known-bad control cannot tell
"it works" from "the probe is blind"** — this repo has already published one wrong conclusion for
exactly that reason (BUG-121, where a sequentially-built control only showed that a task looks like
a task).

**The one thing to take from this table — and how much it changed on 2026-09-15.** On v0.21.0
`mxcli check` was **wrong on 5 of the 12 constructs probed**: three passed `check --references`,
passed `exec`, read back correctly from `DESCRIBE WORKFLOW`, and were still broken under
`mx check`, one of them leaving the project unopenable. **On v0.22.0 / `main` HEAD that specific
list is largely closed** — the decision spelling, the split terminators, the task-page and
targeting signatures and the dangling jump are all now refused *before* anything is written.

**Do not read that as "the checker can be trusted now."** Two things keep the rule alive. The
checker still has real holes — the `LOOP`-body gap found the same day (`E004` fires on a
parameter and is silent on a loop variable, reaching mxbuild as CE0117) is the same disease one
layer down, in the microflows a workflow calls. And a *clean build was never sufficient for a
parallel split anyway*: BUG-121 shipped green through every gate including `mx check`, and only a
live run found it. So: **native `mx check` after every workflow write, and for a split, a live run
counting what actually executed.**

**Field run, 2026-09-14 — a shipped approval chain, mxcli v0.21.0 / Mendix 11.14.** The rows
above are probes. This is the first production workflow in this toolkit's record written
entirely from MDL and shipped: `WF_MOCApproval`, 14 activities over a project entity — Start →
user task *Initial review* → user task *Initial approval* → **multi-user task** *Expert
assessment* fanning to eight assessment topics → user task *Director approval* → End. Every
construct it uses is a *proven* row above, and it needed no hand-add in Studio Pro. Two
findings from building it that the probe rows do not carry:

**It has zero `DECISION` activities — forced by BUG-76 at the time, and still the better shape.**
A four-stage approval chain with approve/reject at every stage was built with **outcomes on the
user tasks themselves** and no exclusive split anywhere, because on v0.21.0 every scripted
`DECISION` corrupted the model. **BUG-76 is fixed in v0.22.0**, so that constraint is gone — but
keep the shape by choice, not by necessity: a user task's outcomes already branch, so an approval
chain does not need a `DECISION`. Reach for one where the branch is on **data** rather than on a
human's answer, and on v0.22.0+ you can now script it (qualified outcome + the empty `''`
outcome).

**A reject ends the workflow — and on `main` HEAD you can finally say so.** The first task has
nothing behind it, so a backward `JUMP TO` from its reject outcome is a *dangling* jump: no valid
target exists. On v0.21.0 that passed `check --references` and `exec`, read back through
`DESCRIBE WORKFLOW`, and the native build refused it with **CE6681**, *"not possible to jump to
end activities or jump-to activities"* — a message about jump **targets**, which sends you looking
at the target's type when the actual fault is that there is no target at all. **Two things changed
on 2026-09-15.** A dangling jump is now refused at `check` as `MDL-WF05`, naming the real fault and
listing the valid targets. And `end workflow` exists on `main` HEAD, so "reject ends the instance"
is now something MDL can state directly instead of being redesigned into a jump. Read `CE6681` as
**"this jump does not resolve"** on any older binary.

**Targeting is a microflow per stage, never a role XPath, whenever roles are collapsed.** This
project mapped five approver populations onto one `Approver` user role, so
`[%UserRole_Approver%]` would have put every stage in every approver's inbox — an
all-green workflow that assigns the wrong people. Each stage got its own targeting microflow,
and each wrapper carries the platform's **two-parameter** signature (`System.Workflow` **and**
the context entity): one parameter passes `mxcli check` clean and the native build refuses it.

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
| 12 | Called microflows carrying `EXPOSED AS WORKFLOW ACTION` — the workflow editor's toolbox, so a human hand-adding a row-10 construct can find them (`learned-workflow-patterns.md` §25) | N of N called microflows that are **not** `SUB_` prefixed; get N from `mxcli callers <Module.MF>`, which reports the workflow at depth 1 |
| 11 | **If the source is a BPMN/swimlane diagram:** pools counted, lanes carried into row 5's targeting, and every element screened against §13 | N pools = N workflows; N of N source elements screened; every NOT-SUPPORTED element has a `fit-gap.md` row. *"Source is not a process diagram"* is a legal entry |

A workflow going into a build plan with row 10 unfilled is the omission this file exists to stop:
the model builds, `mx check` is green, and a construct the requirements asked for is simply not
there.

---

## 13. Reading a BPMN source — pools, lanes, and the elements Mendix cannot express

**Read this whenever the source of a process is a BPMN diagram, a Visio/drawio process map, or any
"swimlane" picture** — which is most migrations of a real approval or case process. §11 answers
*what can mxcli write*; this section answers the question before it, *what can the engine express
at all*, and it is the one an unsupported source element fails at.

Mendix publishes its own element-by-element verdict:
[BPMN coverage](https://docs.mendix.com/refguide/bpmn-coverage/). Read the live page rather than
trusting the table below to stay current — this is a summary as of 2026-09-14, and the platform
moves. **Two hops, never one:** BPMN element → Mendix construct (this section) → MDL writability
(§11). A native element that mxcli cannot script is a hand-add, not a gap; a BPMN element Mendix
does not support is a *redesign*, and it belongs in `fit-gap.md` at Stage 3, not in a build log at
Stage 5.

### Pools and lanes are implementation, not decoration

This is the mapping most often lost, because a swimlane picture reads as documentation:

- **One pool = one workflow.** The workflow *is* the process boundary. A source diagram with
  three pools is **three workflows** with messages between them, not one workflow with three
  regions. Count the pools before you count anything else — a three-pool source collapsed into a
  single workflow is a different application, and no gate downstream will notice.
- **A lane = a targeting statement.** Mendix implements lanes as user-task assignment via roles
  and workflow groups, so every lane boundary a task sits inside is a claim about *who works it*.
  Carry the lane name into §6's targeting derivation as the requirement sentence, then choose the
  mechanism by §6's rules — and heed §6's warning: a lane labelled with a role name is **not**
  evidence that a role XPath is the right mechanism, because a lane often names a *population*
  whose members are data on the record.
- **Cross-pool arrows are `CALL WORKFLOW` or `NOTIFY WORKFLOW`**, never a transition. A message
  flow that crosses a pool boundary in the source is an integration point in the build plan.

`architecture-blueprint.md` Step 3d draws cross-persona journeys as a *documentation* artifact.
That is a different thing from this, and does not discharge it: a journey diagram shows handoffs
between people, this decides how many workflows exist and who each task targets.

### The mapping table

| BPMN element | Mendix | Then check §11 for |
|---|---|---|
| Exclusive gateway (XOR) | **Native** — Decision | **BUG-76.** Qualified outcome spelling, `exec --no-check`. Often better expressed as outcomes on the preceding user task — §15 |
| Parallel gateway (AND) | **Native** — Parallel Split | **BUG-121.** Path terminators after every write — `learned-workflow-patterns.md` §18, §23 |
| **Inclusive gateway (OR)** | **Workaround** — parallel split *with a decision on each path* | Both damaged constructs at once. **Cost this explicitly in `fit-gap.md`**; do not let it enter a build plan as one row |
| User task | **Native** — User Task | proven. Page takes `System.WorkflowUserTask`; targeting microflow takes two parameters |
| Multi-instance parallel user task | **Native** — Multi-User Task | proven; decision method + completion timing are a hand-add (§7) |
| Service / script / business-rule / manual task | **Native or workaround** — Call Microflow | proven; quote the `WITH` value |
| Send task | **Workaround** — Call Microflow + Notify Workflow | proven |
| Receive task | **Native** — Wait for Notification | proven; takes no name |
| Call activity / reusable subprocess | **Native** — Call Workflow | proven |
| Event sub-process | **Native** | **hand-add** — no MDL construct, in any position (§3, §11) |
| Timer: intermediate catch, boundary interrupting/non-interrupting | **Native** | non-interrupting proven; **interrupting is a hand-add** (§2, §11) |
| Message / signal / conditional / escalation / compensation / cancel events | **Workaround** — microflow combinations | per-case; §11 has no row, so probe before promising |
| Link events (throw/catch) | **Native** | unprobed in MDL |
| None start / none end | **Native** | end-of-branch is **not expressible** — §4, §11 |
| Text annotation | **Native** | **not writable** — `MDL-WF04`, mxcli#1007 |
| Data object / input / output / store | **Workaround** — domain entity + workflow parameter | the context entity, §2 of `learned-workflow-patterns.md` |
| **Event-based gateway** | **NOT SUPPORTED** | redesign |
| **Complex gateway** | **NOT SUPPORTED** | redesign |
| **Embedded / transaction / ad-hoc subprocess** | **NOT SUPPORTED** | redesign |
| **Terminate end event** | **NOT SUPPORTED** | redesign — and note this is the platform's own statement of the same hole §4 and §11 describe from the MDL side |
| **Multiple / multiple-parallel events** (all variants) | **NOT SUPPORTED** | redesign |
| **Group artifact** | **NOT SUPPORTED** | drop; it carries no behaviour |

### What to do with an unsupported element

Never silently drop it and never approximate it in the build. Each one is a `fit-gap.md` row at
Stage 3 naming the source element, why Mendix cannot express it, and the redesign chosen — and if
the redesign changes what the business process *does*, that is a `PROJECT.md` decision to confirm
with a human, not an architecture call (`interview-protocol.md`).

Two that reliably cost more than they look:

- **Event-based gateway** ("whichever happens first: a reply, or the timer") has no construct.
  The usual redesign is a user task with a non-interrupting boundary timer, which changes the
  semantics — both branches can run. Say so out loud.
- **Terminate end event** ("stop the whole instance from here") is unsupported platform-side *and*
  inexpressible in MDL. Model global cancellation as an interrupting event sub-process (§3) —
  which is itself a Studio Pro hand-add. One source element, two hand-adds, and a redesign.
