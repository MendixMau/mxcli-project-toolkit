# Mendix Native Workflows in MDL

**Applies to:** any mxcli project scripting a Mendix native Workflow (definition, task
pages, targeting, starting instances) from MDL. Everything here is scriptable; the two
exceptions are a data-driven `DECISION` gateway, which must still be added by hand (§8),
and a visual check in Studio Pro, which is not optional (§8, Warning 3).

**Verified on:** Mendix 11.13.0, mxcli v0.17.0/v0.18.0. Every MDL form that appears in
`build/workflow-example.mdl` was confirmed with `mxcli check`. Forms discussed only in
this document, and every *runtime* and *Studio-Pro-load* claim, rest on build experience
rather than on a re-run verification — they are flagged inline where that matters. Treat
`build/workflow-example.mdl` as the syntax authority; treat this document as reasoning.

**Older mxcli binaries are not safe for this.** On builds predating the Mendix 11.9
`CallMicroflowActivity` rename (notably tagged `v0.16.0`), a `CALL MICROFLOW` inside a
`CREATE WORKFLOW` is written under the pre-11.9 storage type name. Studio Pro then shows a
**red pin** instead of the activity and the app fails to boot — while `mxcli check` and the
native `mx check` both pass. Check `mxcli --version` before scripting any workflow that
calls a microflow. See [[learned-mdl-preflight]] STOP #18/#19 for the pre-flight version
of this rule.

**Companion file:** `build/workflow-example.mdl`, in this same repo. It is a complete,
self-contained, check-clean build of a purchase-request approval used as the running
example throughout this document — context entity, step rows, two reusable task pages,
the workflow, and the microflow that starts it. Read this document for the reasoning;
copy from the example file for the syntax.

---

## 1. What a workflow is in this toolchain

A Mendix workflow is four things wired together:

1. **One context entity.** A workflow definition takes exactly one persistent entity as its
   parameter. Every user task, page and condition in the definition receives that same
   object. It is the case file for the process.
2. **A tree of user tasks, each with named outcomes.** An outcome is a string label
   (`'Approve'`, `'Reject'`, `'Complete'`). Branching happens on outcomes.
3. **Targeting.** Each user task decides which users may pick it up — by XPath over user
   roles, or by a microflow returning a `List of System.User`.
4. **A page bound to each task.** The page shows the case, lets the user edit it, and
   carries one button per outcome.

Nothing else is required. In particular you do **not** need the WorkflowCommons marketplace
module — it supplies convenient inbox and task-chrome snippets, but every mechanism in this
document is native.

The three things people most often assume are Studio-Pro-only, and are not:

- Starting an instance from a microflow — `CALL WORKFLOW` (§7).
- Completing a task with a named outcome — the `complete_task` page button action (§4).
- Role-based targeting — inline XPath on the user task (§5).

---

## 2. Concept: the workflow context entity

**Why it matters.** Everything the workflow can see, it sees through this one object. Get
its shape wrong and you end up either with a bloated entity carrying one column per process
step, or with pages that cannot reach the data they need to edit.

**The rule:** the context entity holds what the *process* reasons about. Per-step detail
goes on a **child entity**, one row per step, created up front when the instance starts.

```
PurchaseRequest          <- the context entity (the case)
  RequestNumber, Description, Amount, SubmittedOn

StepData                 <- one row per process step (the per-step detail)
  StepKey (enum), Comment, BudgetCode, CompletedOn
  -> StepData_PurchaseRequest
```

That child entity is not just tidiness — it is what makes one page serve many steps (§4).
Create every step row at instance start, so the resolver in §3 always finds one.

---

## 3. Concept: the context ⇄ System.Workflow back-reference

**Why it matters.** This is the single most expensive omission in the whole pattern.

Mendix gives you `System.WorkflowUserTask_Workflow` — a task knows its instance. It does
**not** give you the other direction: an instance does not know your context object, and
**nothing populates that link for you**. You must model the association yourself and set it
in the microflow that starts the workflow.

```sql
CREATE ASSOCIATION MyModule."PurchaseRequest_Workflow"
  FROM MyModule."PurchaseRequest" TO System."Workflow"
  TYPE Reference OWNER Default
  DELETE_BEHAVIOR DELETE_BUT_KEEP_REFERENCES;
```

**The failure mode is silent.** Skip the `CHANGE` that populates it and: the project
compiles, `mx check` passes, the workflow starts, tasks appear in the inbox, the user clicks
one — and **every task page renders blank, forever**. There is no error anywhere. The page's
data source microflow simply walked task → workflow → *nothing* and returned empty, and a
dataview over an empty object renders nothing.

If a task page is blank, check this association first, before anything else.

With it in place, a task page can find its way home:

```
$WorkflowUserTask
  -> System.WorkflowUserTask_Workflow    (given by Mendix)
  -> MyModule.PurchaseRequest_Workflow   (yours — the one above, reversed)
  -> the step row
```

---

## 4. Concept: task-driven page reuse

**Why it matters.** The naive build is one page per step. An N-step process becomes N
near-identical pages, and every layout change is N edits. Grouped by outcome shape, a
long process usually needs only two or three pages in total.

**Group pages by OUTCOME SHAPE, not by step.** The only thing that structurally differs
between task pages is the set of buttons. Every step whose task ends in a single `'Complete'`
outcome can share one page. Every Approve/Reject step can share another.

Three mechanisms make that work:

**(a) Resolve the per-step row from the task itself.** The page receives a
`$WorkflowUserTask` and no step parameter. A data-source microflow walks the chain in §3 and
picks the step row using a key derived from the task's own `Name`:

```sql
IF $WorkflowUserTask/Name = 'Finance' THEN
  SET $Key = MyModule."StepKey"."Finance";
END IF;
```

`Name` is the task's name as written in the workflow definition, so **name your user tasks
deliberately — the name is your routing key.**

The page binds that microflow as a dataview datasource. Note the **colon** in the parameter
binding — a microflow *datasource* uses `"Param": $value`, unlike a button's
`Action: MICROFLOW …("Param" = $value)`, which uses `=`:

```sql
DATAVIEW "dvStep" (DataSource: MICROFLOW MyModule."SUB_StepData_ForTask"("WorkflowUserTask": $WorkflowUserTask)) {
  TEXTAREA "taComment" (Label: 'Comment', Attribute: "Comment")
}
```

`System.WorkflowUserTask` has exactly these attributes and no others:

| Attribute | Type |
|---|---|
| `Name` | String |
| `Description` | String |
| `StartTime` | DateTime |
| `DueDate` | DateTime |
| `EndTime` | DateTime |
| `Outcome` | String |
| `State` | Enum (`System.WorkflowUserTaskState`) |
| `CompletionType` | Enum (`System.WorkflowUserTaskCompletionType`) |

There is no "current step key", no context reference, no custom attribute. `Name` is the
only routing handle you get.

**(b) Gate step-specific fields on the step enum with `Visible:`.** Fields that belong to
only one step live in a container conditioned on the resolved row's enum:

```sql
CONTAINER "ctnFinance" (Visible: [StepKey = MyModule.StepKey.Finance]) {
  TEXTBOX "tbBudget" (Label: 'Budget code', Attribute: "BudgetCode")
}
```

Bare attribute names inside the expression auto-root to `$currentObject`; enum *values* must
be fully qualified. **An empty CONTAINER compiles but crashes at runtime** — never leave one
behind while iterating.

**(c) Complete the task from a button, not a microflow.** `complete_task` is a first-class
page button action:

```sql
ACTIONBUTTON "btnApprove" (
  Caption: 'Approve',
  Action: complete_task 'Approve',
  ButtonStyle: Success
)
```

One button does three things: **commits the form, completes the task with that outcome, and
closes the page.** No microflow required. The string must exactly match an outcome declared
on the task in the workflow definition.

**Four structural rules for any workflow task page:**

1. `Params:` must declare **both** `$WorkflowUserTask: System."WorkflowUserTask"` **and**
   `$WorkflowContext: <your context entity>`. Omit either and the workflow's reference to
   the page fails with **CE7412**.
2. The `complete_task` button must sit **inside a DATAVIEW bound to `$WorkflowUserTask`**.
   The engine resolves the completion from that dataview's context. Data-editing buttons
   that pass the context object go in the context dataview instead — a button outside the
   dataview scoped to its parameter entity fails **CE1571** ("no argument selected").
3. One `complete_task` button per outcome. A missing button means the workflow can never
   advance down that path.
4. Wrap widgets in a `LAYOUTGRID` — otherwise lint rule MPR010 fires.

Enum attributes need `RADIOBUTTONS` (editable) or `DYNAMICTEXT` with `ContentParams`
(read-only). A `TEXTBOX` on an enum is **CE2421** — `TEXTBOX` accepts only
string/int/decimal/long/hashed.

See `build/workflow-example.mdl` §3 for both pages in full.

---

## 5. Concept: target by role composition, not by role name

**Why it matters.** A targeting microflow that retrieves the user role literally named
`'Manager'` and returns its members hides every task from an Administrator who holds the
same *module* role through a different user role. That surfaces as "my inbox is empty" for
exactly one persona, usually long after you shipped, and it is very hard to attribute.

Prefer **inline XPath targeting** on the user task, enumerating the roles that should see it:

```sql
TARGETING USERS XPATH '[(System.UserRoles/System.UserRole/Name = ''Manager'') or (System.UserRoles/System.UserRole/Name = ''Administrator'')]'
```

Two syntax requirements:

- **All three path segments are required**: `System.UserRoles/System.UserRole/Name`.
  Two-segment forms — `[UserRoles = "Manager"]`, `[UserRoles/Name = "Manager"]` — are
  rejected with **CE0161**.
- **Inner quotes are doubled** (`''Manager''`), because the whole XPath is a single-quoted
  MDL string.

A targeting microflow remains available and is the fallback when the rule genuinely cannot
be expressed in XPath:

```sql
TARGETING MICROFLOW MyModule."SUB_TargetReviewers"
```

Such a microflow takes `$Workflow: System.Workflow` and `$Context: <your entity>`, and
returns `List of System.User`.

---

## 6. Syntax reference: the workflow definition

```sql
CREATE WORKFLOW MyModule."PurchaseApproval"
  PARAMETER $Context: MyModule."PurchaseRequest"
BEGIN

  USER TASK "Manager" 'Manager review'
    PAGE MyModule."WF_Task_ApproveReject"
    TARGETING USERS XPATH '[(System.UserRoles/System.UserRole/Name = ''Manager'') or (System.UserRoles/System.UserRole/Name = ''Administrator'')]'
    OUTCOMES
      'Approve' { }
      'Reject' {
        CALL MICROFLOW MyModule."SUB_PurchaseRequest_Close"
          WITH (MyModule."SUB_PurchaseRequest_Close"."Request" = '$Context');
      };

  USER TASK "Finance" 'Finance check'
    PAGE MyModule."WF_Task_SingleOutcome"
    TARGETING USERS XPATH '[(System.UserRoles/System.UserRole/Name = ''Finance'') or (System.UserRoles/System.UserRole/Name = ''Administrator'')]'
    OUTCOMES 'Complete' { };

END WORKFLOW;
```

**Outcome block semantics** — this is the mechanism you branch with. The behaviour below
was established by probing (build a two-outcome task, run it, see where each path lands);
it is *not* stated in any tool's documentation, so re-probe if your Mendix version differs:

| Form | Meaning |
|---|---|
| `OUTCOMES 'X' { }` — empty block | That outcome **rejoins the enclosing flow** and continues to whatever comes next. |
| `OUTCOMES 'X' { activities }` — nested block | That outcome becomes a **private terminal branch**: it runs those activities and the instance's path ends there. |

So a linear process is a series of tasks whose outcomes are all empty blocks, and a real
fork is one outcome carrying its own nested activities. A common shape is *N-1 empty, 1
terminal*: several outcomes fall through to shared downstream work, one peels off.

One caveat to watch: **CE1876** polices single-outcome tasks. Reports of what exactly it
rejects are inconsistent (single outcome with no body vs. single outcome *with* a body), so
if it fires on a one-outcome task, try the other form rather than assuming the pattern
above is wrong.

**Other statements in a workflow body:**

- `PARALLEL SPLIT PATH 1 { ... } PATH 2 { ... } PATH 3 { ... };` — concurrent branches,
  one or more activities each. Unaffected by the `DECISION` defect in §8.
- `CALL MICROFLOW Mod."Name" WITH (Mod."Name"."Param" = '<value>');` — see below.
- `OVERVIEW PAGE Mod."Page"` — optional clause after `PARAMETER`, naming the instance
  overview page.
- **No `ANNOTATION` statements inside a workflow body.** A standalone annotation placed in
  the activity flow produces a model Studio Pro cannot load (mxcli check flags MDL-WF04).
  Carry notes as plain MDL comments instead.
- The body closes with `END WORKFLOW;`, not `END;`.
- Capitalize `$Context` / `$WorkflowContext` consistently. Lowercase inside an activity
  expression has been observed to produce CE0117 (seen in a `DECISION` expression, on an
  older binary — unverified for other activity types).

**`CALL MICROFLOW` inside a workflow:**

```sql
CALL MICROFLOW MyModule."SUB_PurchaseRequest_Close"
  WITH (MyModule."SUB_PurchaseRequest_Close"."Request" = '$Context');
```

The parameter key is **fully qualified** (`Module."Microflow"."Param"`) and the value is a
**quoted string** — `'$Context'`, or a literal like `'MyModule.StepKey.Finance'` or
`'empty'`. Omitting the `WITH` clause entirely is safe when the target has exactly one
entity-typed parameter; mxcli synthesizes the mapping.

On v0.17.0+ the fully-qualified key is correct. On older binaries it was double-prefixed
into a null `ParameterId` and an unloadable model — one more reason to check
`mxcli --version` before scripting this (see the header note).

Two hard constraints on any microflow called from a workflow:

- **It must return Boolean, an enumeration, or nothing.** Returning an entity is rejected.
  Wrap entity-returning logic in a boolean shim.
- **It runs headless.** It cannot `SHOW PAGE`. Anything the user must see or choose has to
  happen on a task page *before* the outcome is submitted, and be persisted somewhere the
  headless microflow can retrieve.

---

## 7. Syntax reference: the 11 workflow microflow statements

All eleven parse and reference-check on mxcli v0.17.0+. **None of them appear in
`mxcli syntax workflow --json` or in `HELP`.** Absence from the syntax topic index is not
evidence of non-support — probe with `mxcli check` before concluding anything is
unsupported. That single inference error is expensive: it leads to stub microflows and
manual Studio Pro steps built around a blocker that never existed.

| Purpose | Statement |
|---|---|
| Start an instance | `$Wf = CALL WORKFLOW Mod."Wf" (WorkflowContext = $Ctx);` (bare form, without `$Wf =`, is also valid) |
| Complete a task | `SET TASK OUTCOME $Task 'OutcomeName';` |
| Open an instance | `OPEN WORKFLOW $Wf;` (client action) |
| Open a task | `OPEN USER TASK $Task;` (client action) |
| Lock / unlock | `LOCK WORKFLOW $Wf;` · `UNLOCK WORKFLOW $Wf;` · `LOCK WORKFLOW ALL;` · `UNLOCK WORKFLOW ALL;` |
| Release a wait | `$R = NOTIFY WORKFLOW $Wf;` (releases a *wait for notification* activity) |
| Instances for a context object | `$Wfs = GET WORKFLOWS FOR $Ctx;` |
| Instance metadata | `$D = GET WORKFLOW DATA $Wf AS Mod."Entity";` |
| Audit trail | `$Recs = GET WORKFLOW ACTIVITY RECORDS $Wf;` |
| Lifecycle control | `WORKFLOW OPERATION ABORT\|PAUSE\|UNPAUSE\|RETRY\|RESTART\|CONTINUE $Wf;` |
| Abort with a reason | `WORKFLOW OPERATION ABORT $Wf REASON 'Superseded by v2';` |

**Prefer the `complete_task` page button over `SET TASK OUTCOME` in a microflow.** The
button also commits the form and closes the page; the statement does neither, so choosing it
means rebuilding both by hand. Use `SET TASK OUTCOME` only when you must validate or mutate
first in a flow that has no page.

**`DESCRIBE MICROFLOW` cannot read `call workflow` back — do not trust it.** The round trip
is broken in one direction: `CALL WORKFLOW` *writes* correctly and builds and runs, but
`DESCRIBE MICROFLOW` renders the activity as `-- Empty action`, and it appears in neither
`SHOW CALLEES` nor `CATALOG.REFS`. A microflow that genuinely starts a workflow therefore
reads back as though the start is missing — which reads convincingly as "this must have
been hand-built in Studio Pro." It wasn't. **Audit your MDL source, not `DESCRIBE` output,**
when checking whether a workflow gets started, or confirm at runtime that the back-reference
association is populated. This is the [[tool-output-is-not-ground-truth]] pattern again, in
its nastiest form: the tool doesn't error, it silently renders a comment where a real
activity lives. Leave an `@annotation` on that microflow activity saying so, for whoever
reads it next.

### Starting an instance — two gotchas

```sql
$Workflow = CALL WORKFLOW MyModule."PurchaseApproval" (WorkflowContext = $Request);
CHANGE $Request (MyModule."PurchaseRequest_Workflow" = $Workflow);
COMMIT $Request;
```

- **You cannot `DECLARE` the variable first.** `DECLARE $Wf System.Workflow;` fails
  MDL043 / CE0053 — Mendix does not allow a Create Variable activity to hold an object.
  Assign straight from the call; the assignment creates the variable. The same restriction
  applies to lists: use `$L = CREATE LIST OF Mod."Entity";`, not
  `DECLARE $L List of ... = empty;` (MDL040 / CE0053).
- **The parameter mapping must be named.** `(WorkflowContext = $Request)`. A bare `($Request)`
  fails with `mismatched input ')' expecting '='`, despite mxcli's own internal deparse
  template reading `call workflow %s ($%s);`.

Then **wire the back-reference** on the very next line, as above — see §3 for why.

---

## 8. Warnings

### Warning 1 — do not emit a `DECISION` activity inside a workflow

**This is a known open mxcli defect, and it corrupts your `.mpr` silently.**

- **Symptom:** the `.mpr` becomes unloadable. Studio Pro and the native `mx` loader fail
  with `Mendix.Modeler.Storage.StorageLoadException`.
- **Cause:** mxcli writes the decision's outcome label as a raw string into a field the
  native loader requires to be a real `EnumerationValueIdentifier`. This is unconditional —
  it does not depend on the expression's type.
- **Repro:** something as trivial as `DECISION '1 = 1'` inside a `CREATE WORKFLOW` body.
- **Why it is invisible:** `mxcli check`, `mxcli exec` and `DESCRIBE WORKFLOW` all report
  success. Nothing in the mxcli toolchain sees it. You find out when someone opens the
  project.
- **There is no MDL-only workaround.**

**What to do instead:** express the branch as **user task outcomes** (§6) — an outcome with
a nested activity block *is* an exclusive branch, and covers most real gateways. Where you
genuinely need a data-driven gateway with no user decision behind it, flatten the flow to
its happy path in MDL, leave a plain MDL comment at the insertion point describing the
gateway precisely, and add that one activity by hand in Studio Pro.

`PARALLEL SPLIT` is unaffected.

### Warning 2 — `DESCRIBE MICROFLOW` lies about `CALL WORKFLOW`

See §7 above — this is the same defect stated once, in context.

### Warning 3 — a passing `mxcli check` is not a working model

After building any workflow, run the **native** check and then open the workflow in Studio
Pro and look at the activity icons:

```bash
<StudioPro install>/modeler/mx check YourApp.mpr
```

`mxcli check`, `mxcli exec` and `DESCRIBE` all pass happily on models whose loader-level
structure is malformed — Warning 1 is exactly that class of defect, and only the native
loader sees it. The eyeball step is not optional either: a microflow-call icon means the
activity stored correctly, whereas a **red pin** means the stored type name is wrong (the
old-binary defect in the header note) — and `mx check` reports 0 errors on both.

If you do produce an unloadable workflow, no restore is needed — mxcli reads models the
Studio Pro loader rejects:

```bash
mxcli -p App.mpr -c "DROP WORKFLOW MyModule.BadWorkflow"
```

### Verifying what was actually stored

When you suspect a storage-level defect, read the BSON rather than the tool's own output:

```bash
u=$(LC_ALL=C grep -rla "<WorkflowName>" mprcontents/ | head -1)
LC_ALL=C strings -n 4 "$u" | grep -oE 'Workflows\$[A-Za-z]+'
```

If a hand-built equivalent of the broken element exists in the same model, diff the two
units' strings — everything shared is irrelevant, and the difference is the bug. That
technique has reduced a day of syntax theorising to about a minute. Confirm any fix by
varying **only** the suspected cause — see [[sandbox-ab-tool-defect-probe]].

---

## 9. Common errors

| Error | Cause | Fix |
|---|---|---|
| **CE7412** | Task page missing `$WorkflowUserTask` (or `$WorkflowContext`) in `Params:` | Declare both parameters |
| **CE1571** "no argument selected" | Button sits outside the dataview scoped to its parameter entity | Move the button inside the correct `DATAVIEW` |
| **CE2421** | `TEXTBOX` bound to an enum attribute | Use `RADIOBUTTONS` (editable) or `DYNAMICTEXT` + `ContentParams` (read-only) |
| **CE0111** | `complete_task 'WrongName'` — outcome string does not match the definition | Check `DESCRIBE WORKFLOW` for the exact outcome strings |
| **CE0161** | Targeting XPath with fewer than three path segments | Use `System.UserRoles/System.UserRole/Name` in full |
| **CE0053 / MDL043** | `DECLARE $Wf System.Workflow;` | Assign straight from `CALL WORKFLOW` |
| **CE0053 / MDL040** | `DECLARE $L List of Mod.Entity = empty;` | Use `$L = CREATE LIST OF Mod."Entity";` |
| **CE0108** | A `RETRIEVE` inside an `IF` shadows the named return variable, leaving it out of scope on the `ELSE` path | Use early `RETURN empty;` on failure branches so only the success path reaches the named-return retrieve |
| **MDL-WF04** | Standalone `ANNOTATION` in a workflow activity flow (produces an unloadable model) | Use a plain MDL comment |
| **MPR006** | Empty container — compiles, crashes at runtime | Give every container content, or drop it |
| **MPR010** | Widgets not wrapped in a `LAYOUTGRID` | Wrap them |
| Workflow stuck | No `complete_task` button for one of the task's outcomes | Add the missing outcome button |
| Task page renders blank | Context ⇄ `System.Workflow` back-reference never populated | Set it in the starting microflow (§3, §7) |

---

## 10. Build order

1. **Domain model** — context entity, step enum, per-step child entity, the step→context
   association, and the context→`System.Workflow` back-reference association.
2. **Resolver microflow** — task → workflow → context → step row, keyed off
   `$WorkflowUserTask/Name`.
3. **Task pages** — one per outcome shape, not one per step.
4. **Workflow-callable microflows** — Boolean/enum/void returns only, headless.
5. **Workflow definition** — user tasks, outcomes, targeting XPath, parallel splits. No
   `DECISION`.
6. **Starting microflow** — create the step rows, `CALL WORKFLOW`, wire the back-reference,
   commit.
7. **Native `mx check` + open in Studio Pro** and inspect the activity icons.
8. **Run it.** Click one task through end to end. The two silent failures in this pattern —
   the missing back-reference and an unloadable `DECISION` — are both invisible to every
   static gate.

---

## 11. Divergent outcome branches — reconvergence is not a grammar limit

**Wrong conclusion, reached more than once before being corrected:** "every workflow
outcome/CALL MICROFLOW branch reconverges to the next main-flow activity regardless of
content — this grammar has no way to make one branch end the instance early." That
conclusion was drawn by reading `DESCRIBE WORKFLOW` output and generalizing from one
pattern (a branch that happened to share its post-outcome activities with its siblings),
not by probing the grammar itself. It is **false**, and cost a full investigation round
before being disproven empirically.

**The actual rule:** what a branch reconverges onto is determined by what MDL text is
physically written *after* the outcomes/decision block in the script — not by anything
inherent to the branch construct. Two branches converge only because the same
continuation was written outside/after both of them. To make one branch end the workflow
instance and the other continue normally:

- Nest the **entire** downstream continuation (every remaining task, decision, and
  outcome) *inside* the branch that should reach it.
- Leave the terminating branch with **nothing following it, at any nesting level** — the
  workflow instance simply ends when that branch's activities run out.

This is not a hack — real production workflows have shipped with outcomes that prove the
grammar supports divergent branches: one outcome ends via a `CALL MICROFLOW` to a "close"
microflow, while a sibling outcome ends via a different call with a different downstream
shape — because that outcome sat last in the file, this had never been recognized as
evidence the same technique works **mid-file**, ahead of other tasks. Nesting the
continuation earlier in the script proves it does.

**Verified pattern (a `DEC_SamplingDecision` gateway mid-workflow):**

```
call microflow Module."DEC_SamplingDecision" with (...) outcomes
  true -> {
    <every remaining task/decision from the rest of the process, unchanged, nested here>
  }
  false -> {
    call microflow Module."ACT_CreateVersion_WF" with (...) outcomes true -> { } false -> { };
    -- nothing follows — this branch (and the workflow instance) ends here
  }
;
```

`mxcli check --references` validates this clean; it is not rejected by the parser.

**Methodology lesson — probe before declaring an MDL construct impossible.** This is the
workflow-specific instance of a general failure mode ([[tool-output-is-not-ground-truth]]
covers the read side of it). When a "this construct
can't do X" conclusion is about to be reported, write the smallest possible test script
proving or disproving it and run `mxcli check --references` before reporting — reading
`DESCRIBE` output or reasoning from one existing example is not a substitute for a probe.

---

## 12. `WORKFLOW OPERATION ABORT` — semantic scope, not a generic early-exit

`WORKFLOW OPERATION ABORT $Wf [REASON '...'];` (§7) is a real, working alternative to the
divergent-branch pattern above — called from a wrapper microflow via
`GET WORKFLOWS FOR $WorkflowContext`, outside the workflow definition entirely. It
validates syntactically for any early-termination need. **But it is not semantically
neutral**: if a project's business rules distinguish a genuine user-initiated abort (e.g.
`RunStatus = Abandoned`) from a normal completes-early-by-design branch (e.g. a
reject-and-fork-new-version path that should read as a completed, not abandoned, run),
reusing `ABORT` for the latter will mislabel it unless something afterward explicitly
overwrites the status field. Prefer the in-definition divergent-branch pattern (§11) when
the early-exit path is a normal, documented business outcome; reserve
`WORKFLOW OPERATION ABORT` for actual user/administrative abort actions, or be prepared to
correct the resulting status as a second step.

---

## 13. `$Type` corruption is a *binary-version* defect, not universal — always confirm which binary

Warning 1's `DECISION`-corruption class is one defect; a related but distinct one affects
`CALL MICROFLOW`: `mxcli v0.16.0` writes the wrong `CallMicroflowActivity`/
`CallMicroflowTask` `$Type` on Mendix ≥ 11.9, invisible to `mx check` (see the header note
and §8 Warning 3). Before assuming a project is affected: run `mxcli --version` and
compare against build `253d60d8` (2026-07-29) — confirmed clean on `v0.18.0`. But always
**verify the actual executed result**, not just the binary version, for any workflow write
that used `CALL MICROFLOW`:

```bash
u=$(LC_ALL=C grep -rla "<WorkflowName>" mprcontents/ | head -1)
LC_ALL=C strings -n 4 "$u" | grep -oE 'Workflows\$Call[A-Za-z]+' | sort | uniq -c
# want: only Workflows$CallMicroflowActivity, zero Workflows$CallMicroflowTask
```

This is cheap (a few seconds) and closes the one gap `mx check` cannot see for this class
of write, regardless of which binary produced it.

---

## Notes on scope

Workflow **timer** and **wait-for-notification** activities are referenced by
`NOTIFY WORKFLOW` above but their `CREATE WORKFLOW` body syntax has **not been verified**
here; likewise **boundary events** and **sub-workflow** invocation from inside a workflow
body. Probe with `mxcli check` before relying on any form for these.

Access rules: a workflow definition itself carries no access rule. Reachability comes from
the user-task targeting plus the view grants on the task pages.

See [[learned-mdl-preflight]] for the pre-flight STOP-table entries this skill informs
(#18 CALL MICROFLOW without WITH inside a workflow body, #19 any workflow MDL script).
