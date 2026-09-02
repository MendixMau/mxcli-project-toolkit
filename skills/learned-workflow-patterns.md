# Mendix Native Workflows in MDL

**Applies to:** any mxcli project scripting a Mendix native Workflow (definition, task
pages, targeting, starting instances) from MDL. Everything here is scriptable **on mxcli
v0.18.0 or later**; on older binaries a `DECISION` gateway must still be added by hand in
Studio Pro, because emitting it from MDL corrupts the `.mpr` (§8 Warning 1 — BUG-76, a
version gate, not an absolute prohibition). A visual check in Studio Pro is never optional
(§8, Warning 3).

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

**Five more activity forms, all proven on mxcli v0.20.0 / Mendix 11.14.0 (2026-09-03).**
None of them appear in `mxcli syntax workflow`; absence there is not evidence (§7). Each was
run through `mxcli check --references` → `exec` → native `mx check` (0 errors) → `DESCRIBE`
round-trip:

```sql
-- multi-user task. The ACTIVITY is scriptable; its decision method and completion timing
-- are NOT (no grammar for them) — those are a Studio Pro hand-add, and a build-plan row.
MULTI USER TASK "Board" 'Board review'
  PAGE MyModule."WF_Task_ApproveReject"
  OUTCOMES 'Approve' { } 'Reject' { };

-- jump to, inside a user-task outcome. Must be the last statement of its path.
-- Inside a BOUNDARY EVENT body it writes a targetless, name-colliding Jump — BUG-109.
USER TASK "Review" 'Review'
  PAGE MyModule."WF_Task_ApproveReject"
  OUTCOMES 'Ok' { } 'Redo' { JUMP TO "Review"; };

-- non-interrupting boundary timer. The duration is a Mendix EXPRESSION, not an ISO period.
USER TASK "Review" 'Review'
  PAGE MyModule."WF_Task_SingleOutcome"
  OUTCOMES 'Complete' { }
  BOUNDARY EVENT NON INTERRUPTING TIMER 'addDays([%CurrentDateTime%], 3)' {
    CALL MICROFLOW MyModule."SUB_Remind" WITH ("Request" = '$WorkflowContext');
  };

-- wait for timer / wait for notification. WAIT FOR NOTIFICATION takes NO name --
-- 'WAIT FOR NOTIFICATION ''Ping'';' is a parse error; the name is a Studio Pro property.
WAIT FOR TIMER 'addDays([%CurrentDateTime%], 1)';
WAIT FOR NOTIFICATION;
```

**The `WITH` clause's value must be quoted.** `WITH ("Ctx" = '$WorkflowContext')` works;
`WITH (Ctx = $WorkflowContext)` **segfaults the binary** — and the "parameter is not mapped"
hint `--references` prints talks you straight into the crashing spelling. BUG-107.

**Never script a decision on an enumeration.** `mxcli check` rejects both fully-qualified
forms and accepts the bare value `'Draft'`, which writes an `.mpr` the Mendix loader cannot
open at all (`StorageLoadException`, not a validation error). Boolean and free-text decisions
are fine. BUG-108 — hand-add enum decisions in Studio Pro. Recovery from an already-corrupted
model is `DROP WORKFLOW`, which still works because mxcli can read what mxbuild cannot load.

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

**`DESCRIBE MICROFLOW` reads `call workflow` back since v0.20.0 — but the catalog still
does not see it.** The describe half of this warning is retired: on mxcli v0.20.0 the round
trip closes — `DESCRIBE` emits `call workflow Mod.WF ($Var);` (the positional form, added to
the grammar precisely so describe output parses back), and that output checks, execs, and
survives a re-describe (verified 2026-08-31 on a scratch 11.13 project). On pre-v0.20
binaries the old failure stands: the activity rendered as `-- Empty action` and re-executing
a description deleted the workflow start. What is **still true on v0.20.0, measured the same
day**: the call appears in neither `SHOW CALLEES` nor `CATALOG.REFS` even after
`refresh catalog full` — so a microflow that starts a workflow still reads as making no
calls, and dead-asset sweeps (`GRAPH_DEAD_ASSETS`, QUAL004-style rules) can still misreport
around it. **Audit MDL source, not the catalog,** when checking whether a workflow gets
started.

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
- **The parameter mapping: named on old binaries, positional accepted since v0.20.0.**
  `(WorkflowContext = $Request)` works everywhere. On pre-v0.20 mxcli a bare `($Request)`
  fails with `mismatched input ')' expecting '='`; v0.20.0 added the positional form (a
  workflow has exactly one context parameter, so it is unambiguous) and it is what
  `DESCRIBE` emits — verified parse + exec 2026-08-31.

Then **wire the back-reference** on the very next line, as above — see §3 for why.

---

## 8. Warnings

### Warning 1 — `DECISION` corrupts the `.mpr` on old binaries; check your version

**This is a `bug-logs/mxcli-bugs.md` BUG-76 defect and it corrupts your `.mpr` silently —
but it is a *version gate*, not an absolute prohibition.** Reconciled 2026-08-26 against
mxcli **v0.18.0**, where `DECISION` writes correctly.

| mxcli binary | `DECISION` in a native `WORKFLOW` |
|---|---|
| `v0.16.0` | **corrupts the `.mpr`** — do not emit |
| `v0.17.0` | **corrupts the `.mpr`** — confirmed, BUG-76 (binary `2026-08-10T05:12:17Z`) |
| `v0.18.0`+ | writes correctly; verify what was stored anyway |

Two half-right versions of this warning coexisted for four days from 2026-08-21. One said
"absolute prohibition, confirmed on v0.17.0" and never learned about the v0.18.0 fix — follow
it and you hand-build gateways you no longer need. The other said "corrected on v0.18.0" but
named only v0.16.0 as affected, quietly implying v0.17.0 was safe — follow *that* on v0.17.0
and you silently corrupt a `.mpr`. Both failure directions are real. The affected set is
everything before v0.18.0.

**The defect, on affected builds (v0.16.0, v0.17.0):**

- **Symptom:** the `.mpr` becomes unloadable. Studio Pro, native `mxbuild`, and
  `mxcli docker check` all fail with `Mendix.Modeler.Storage.StorageLoadException`,
  thrown *before* any check or build logic runs.
- **Cause:** mxcli writes the decision's outcome label as a raw string into
  `ConditionOutcome.Value`, a field the native loader requires to deserialize as a real
  `EnumerationValueIdentifier`. One error line per DECISION outcome in the project.
- **Unconditional on those binaries.** It does not depend on the expression's type. BUG-76
  reproduced it on a decision over an enumeration attribute, on a decision over a plain
  String attribute, and on `decision '1 = 1'` with brand-new outcome labels in a throwaway
  workflow. Renaming outcomes or reshaping the expression does not help.
- **Why it is invisible:** `mxcli check --references`, `mxcli exec` *itself*, and
  `DESCRIBE WORKFLOW`/`DESCRIBE MICROFLOW` all report success and print the outcomes back
  correctly. Nothing in the mxcli toolchain sees it. In BUG-76's project it survived two
  scripts and a gate pass before a user reported "mpr error."
- **On affected binaries there is no MDL-only workaround.**

**What to do — run `mxcli --version` first and treat it as a gate, not a folk rule:**

- **On v0.18.0 or later:** write the `DECISION` from MDL. Use §15 to decide whether a given
  gate should be a `DECISION` at all, then **verify what was actually stored** — §13's
  `strings`-on-the-storage-unit check, plus a real `mx check` and a Studio Pro open — before
  moving on. A passing `mxcli check` still proves nothing here, for exactly the reason above.
- **On anything before v0.18.0, or an unverified binary:** the old rule stands in full.
  Express the branch as **user task outcomes** (§6) — an outcome with a nested activity block
  *is* an exclusive branch, and covers most real gateways. Where you genuinely need a
  data-driven gateway with no user decision behind it, flatten the flow to its happy path in
  MDL, leave a plain MDL comment at the insertion point describing the gateway precisely, and
  add that one activity by hand in Studio Pro. §15 tells you which gates are worth adding by
  hand at all.

**To re-verify on any binary you have not personally tested**, in a sandbox copy that keeps
the exact original `.mpr` filename (the v2 store keys `mprcontents/` to it):

```sql
create workflow Module."TestDecisionWF"
  parameter $Context: Module."SomeEntity"
begin
  decision '1 = 1'
    outcomes 'OutcomeA' -> { } 'OutcomeB' -> { };
end workflow;
/
```

then `mxcli docker check` and count `EnumerationValueIdentifier` error lines against the
pre-existing baseline. Two new ones means BUG-76 is live on that binary. Record the binary
and the result in BUG-76 either way.

Neither `PARALLEL SPLIT` (§18) nor a lowercase `$workflowContext` inside a decision
expression is affected — the latter was BUG-WF03, a separate casing defect, fixed in
v0.17.0. BUG-WF03 being fixed did **not** make `DECISION` safe on v0.17.0; it fixed the
expression compiler, not the storage serializer.

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

## 14. Referencing a not-yet-created microflow from a workflow body corrupts the stored workflow

**This is a distinct defect class from Warning 1 and §13.** Those are binary-version bugs
in how an activity is *written*. This one is a corruption of the stored workflow object
that survives fixing the thing that caused it.

**Incident** (a QA-sampling approval project, mxcli v0.18.0, 2026-08-20/21): a fix script
rebuilt a workflow with a `call microflow Module.DEC_CoarseClassification` activity, but
that microflow did not exist in the project yet — its `create or modify microflow`
statement lived only in an earlier, superseded script that was never executed. `mxcli
check --references` passed clean and `mxcli exec` completed with no error. Only a later,
separate native `mx check` caught CE1613 (`… no longer exists`). Creating the missing
microflow afterward cleared CE1613 — but **not** the underlying damage. Roughly a day
later the workflow failed with `CE0495 "Duplicate name '<ActivityName>'"` across 8 sibling
`CALL MICROFLOW` activities that the fix had never touched.

**Root cause, confirmed by elimination, not assumed.** It is not a workflow-grammar limit
and not a shared naming namespace between branch subtrees — both theories were disproven
by cloning the exact 17-call nested structure fresh into a throwaway `_TEST` workflow (0
errors), and separately by retargeting all 17 calls to a project-unique dummy microflow
(still 0 errors). The corruption lives inside the specific stored workflow object's own
Unit-blob storage tree: an orphaned/duplicated activity record left behind by the original
bad write, surviving even after the dangling reference was repaired. **Same defect class
as `bug-logs/mxcli-bugs.md` BUG-92** (orphaned widgets surviving page edits, invisible to
`DESCRIBE`) — here in a workflow instead of a page. The exact write-sequence trigger could
not be reproduced fresh in an isolated `_TEST` object, so treat this as a strong candidate
mechanism, not a nailed-down repro.

**The reference-checker gap that lets it happen:** `mxcli check --references` and `mxcli
exec` do **not** validate `CALL MICROFLOW` targets inside a workflow body against the live
model. A workflow written against a genuinely nonexistent microflow — not "created later
in the same script," which mxcli's checker does correctly special-case, but never created
anywhere at all — passes both clean. Only native `mx check` catches it (CE1613), once,
well after the damage is done.

> **Hard rule.** Within any single script that writes a workflow calling one or more
> microflows, the `create/modify microflow` statements for every callee must come
> **before** the `create or modify/replace workflow` statement that references them — same
> file, same exec. Never split "create the workflow" and "create a microflow it calls"
> across two exec passes, even if you intend to run the second immediately after.
> `mxcli check --references` will not catch the ordering mistake; only `mx check`, and even
> then only the symptom, not the corruption it leaves behind.

**If you suspect this has already happened** (a `CE0495`/duplicate-name error appears on a
workflow that was *not* the target of your most recent edit): don't assume the most recent
script caused it. Bisect via mxcli's auto-snapshots (`.mpr-snapshots/<timestamp>/`) — swap
each candidate snapshot's `.mpr` **in place** into the live project directory (preserving
relative paths such as `theme/`, or you get spurious `CE6083` errors from an incomplete
sandbox) and run a real `./mxcli docker check` against each — never `--references`, which
cannot see it — working backward until you find the first clean one. The corrupted state
can predate the change you were about to fix.

**Recovery — untested against a real corrupted object as of 2026-08-21.** Try `create or
replace workflow` with the byte-identical current definition (same control flow, no
behavior change) first: this is the mechanism BUG-92's page-rebuild precedent uses to force
full regeneration of the stored activity tree. It could not be verified in isolation
because a throwaway copy could not be driven into the corrupted state to test the fix. If
that doesn't clear it, the fallback is `DROP WORKFLOW` + recreate from the same literal
definition — higher risk to inbound references (role grants, `CALL WORKFLOW` start sites,
WF task pages). Either way: **verify with native `mx check` afterward, not
`--references`**, and confirm first that no deployed runtime paired with this `.mpr` has
in-flight instances — a full regeneration can orphan in-flight tasks, and that cannot be
determined from the design-time `.mpr` alone.

---

## 15. `DECISION` vs. `CALL MICROFLOW` — which gates would belong in the workflow

> **Read Warning 1 first — BUG-76 is a version gate.** On mxcli **v0.18.0 or later** this
> section is directly actionable: script the `DECISION` from MDL, then verify what was
> stored. On **anything before v0.18.0** it is design guidance only — those gates must be
> added by hand in Studio Pro after the workflow exists. The analysis below is
> binary-independent either way, and the alternative — a microflow-wrapped gate — is a real
> design choice with its own cost (§17), not a free fallback.

Native workflow has a `DECISION` activity — an inline exclusive
gateway — that needs no microflow at all:

```
DECISION ['<caption>'] [COMMENT '<text>']
  OUTCOMES '<outcome>' -> { <activities> } ...;
```

It evaluates an expression directly against the workflow's context data. What decides
whether a boolean gate should be a `DECISION` or stay a `CALL MICROFLOW … OUTCOMES true ->
{} false -> {}` is **not** "is the logic simple" — it's **what the expression needs to
reach**:

- **Direct attribute access on the context parameter** (`$WorkflowContext/SomeField =
  'SomeValue'` — no association hop, no filter predicate) → belongs in a `DECISION`
  (scriptable on v0.18.0+, hand-added before that — Warning 1). No side effects, no
  commit, nothing a microflow buys you, and one fewer stored microflow artifact referenced
  by the workflow (§17 for why that matters beyond style).
- **Anything needing a `RETRIEVE` with a `WHERE` predicate, a bracketed
  association-traversal filter, a commit, or multi-step logic** → stays a `CALL MICROFLOW`.
  Confirmed empirically (2026-08-21): workflow expressions reject the bracket-predicate
  traversal form (`$Context/Module.Assoc_Entity[SomeAttr = 'X']`) with `CE0117` — the same
  constraint already noted for `CALL MICROFLOW … WITH` binding expressions in §7, and it
  applies just as hard inside a `DECISION` expression. A decision that must find "the one
  child row matching a key" (filtering a to-many association down to a single row by an
  enum/string key) **cannot** be expressed as a `DECISION` — write it as a microflow with a
  real `RETRIEVE … WHERE … LIMIT 1`.

In short: `DECISION` replaces a microflow whose entire body is "read one field, no
retrieve, return a bool." It does not replace a microflow that has to go find the field
first.

---

## 16. `OUTCOMES` is optional — the dead-branch smell

`CALL MICROFLOW`'s outcome clause is optional in the grammar:

```
CALL MICROFLOW Module.MF [COMMENT '<text>']
  [OUTCOMES '<outcome>' { <activities> } ...];
```

Whether a workflow needs outcome branches at all is driven entirely by the called
microflow's **return type**, not by habit:

- Returns **Void** → no `OUTCOMES` clause needed. The workflow runs the activity and moves
  on.
- Returns **Boolean** → the workflow is forced into a two-outcome `true -> { } false -> { }`
  shape, whether or not either branch does anything.
- Returns an **enumeration** → one outcome per enum value the workflow actually branches on.

**The smell:** a `CALL MICROFLOW` whose microflow returns Boolean and whose `true -> { }`
and `false -> { }` outcomes are *both* empty. The workflow computed a boolean and threw it
away — nothing is decided by the branch. This is easy to miss because it looks structurally
identical to a real decision point; only reading the outcome *bodies*, not the outcome
names, reveals it's dead.

Two legitimate fixes — pick based on whether the boolean carries real business consequence:

1. **The result genuinely doesn't affect control flow** (a denormalization/stamping helper
   whose only failure mode is "no matching row found," already logged internally) → change
   the microflow's return type from Boolean to Void, delete its `$Success` variable, and
   drop the `OUTCOMES` clause at every call site. Move any error handling that depended on
   the boolean (a `LOG ERROR` on the not-found path) **inside** the microflow body first —
   the caller can no longer react to it.
2. **The result does carry consequence** ("did the version-fork actually get created," "did
   the terminal status-close actually commit") → don't silently drop it. Either make the
   `false` branch do something (log at ERROR, escalate, retry, route to a recovery task) or,
   at minimum, confirm via `SHOW CALLERS OF` and a read of the callee that failure is
   already unreachable before flattening to Void. A boolean quietly discarded on a
   *terminal* activity is a different risk profile than one discarded on a per-station
   stamp — the same "empty branches" shape can be a harmless no-op or a swallowed failure,
   depending entirely on what the callee does on the false path.

**Signature-change risk:** Boolean → Void is a public signature change. Always run `SHOW
CALLERS OF Module.TheMicroflow` first. If the workflow is the only caller — common for
`ACT_*_ByKey`/shim microflows built specifically for one workflow's `WITH`-clause
limitations — the change is low-risk, but every `CALL MICROFLOW` call site must be updated
**in the same script and the same exec** as the signature change. Same discipline as §14's
create-before-reference rule, and for the same reason: never leave a workflow definition and
a microflow signature out of sync between two execs.

---

## 17. Fewer moving parts is a corruption-risk criterion, not a style preference

§14's corruption class has a direct design-time countermeasure: **every separately-created
microflow a workflow references is one more chance to get create-before-reference ordering
wrong — across one more script, one more exec, one more future edit.** Collapsing a
microflow-wrapped boolean gate into a native `DECISION` (§15 — hand-added while BUG-76 is
open) doesn't just read cleaner; it permanently removes an artifact-and-reference pair from
the workflow's dependency surface.

Treat "does this activity need to be a separate stored microflow at all, or can it be a
native construct" as a concrete corruption-risk question when auditing an existing workflow
or planning a new one — not only a readability one. This is not a licence to collapse
everything: a microflow doing a real `RETRIEVE`/commit/multi-step mutation still has to be a
microflow (§15). But a pure attribute-equality gate wrapped in a microflow *only* because
that's how the workflow was first drafted is exactly the avoidable moving part this targets.

---

## 18. `PARALLEL SPLIT` — confirm it isn't already there before flagging a fan-out

Don't assume a set of sibling human tasks described informally as "done in parallel" (in a
module brief, BRD, or prose) is modeled sequentially just because they're adjacent in a
script or listed one after another in a doc. Read the live `DESCRIBE WORKFLOW` output before
flagging a missing `PARALLEL SPLIT`. Confirmed 2026-08-21 on a three-station sub-review: the
workflow already had a genuine `parallel split` with three `path N { user task … }`
branches, each independently completable. `DESCRIBE WORKFLOW` renders nested `path` blocks
clearly, so this is a cheap check — do it before recommending a structural change that
already exists.

---

## 19. `BOUNDARY EVENT TIMER` — don't add one without a documented business trigger

> **CORRECTION, 2026-09-03 (probed, mxcli v0.20.0 / Mendix 11.14.0).** The `'P3D'` form below
> is **wrong** and was recorded here as proven on a `mxcli check` alone. The timer takes a
> Mendix **expression**, not an ISO 8601 period: `'P3D'` passes `mxcli check` and `exec`, then
> fails native `mx check` with **CE0117 "Error(s) in expression"**. Write
> `'addDays([%CurrentDateTime%], 3)'`. Two further limits found in the same probe: only the
> **non-interrupting** form is usable from MDL (the interrupting one needs an *End* or *Jump*
> terminator, CE0105 — and neither is expressible, see §11 of `workflow-structure-rules.md`),
> and there is **no notification boundary event** in the grammar at all.
>
> This entry is the reason the rule exists: a construct "used in a real build" was verified by
> the tool that cannot see the defect. `mxcli check` is not evidence for workflows.

`BOUNDARY EVENT TIMER` (Mendix 10.6.0+) is available and syntactically simple:

```
user task ReviewTask 'Review'
  outcomes 'Done' { }
  boundary event non interrupting timer 'addDays([%CurrentDateTime%], 3)' {
    call microflow Module.WF_Escalate with ("Request" = '$WorkflowContext');
  };
```

or after the fact: `ALTER WORKFLOW <wf> INSERT BOUNDARY EVENT ON <task> TIMER '<duration>'
{ <activities> }`. Availability is not a reason to add one to every long-running human task.
Before recommending it, search the actual requirements evidence — BRDs, blueprint,
source-migration triage notes — for SLA/timeout/escalation/deadline language tied to *that
specific task*. Absence of that evidence is a legitimate "no action" finding. Don't invent
an SLA the business never asked for because the construct exists and the task is
human-facing. (Confirmed practice, 2026-08-21: a full-text search across an approval
module's BRDs and migration-triage notes for SLA/timeout/escalation/deadline/overdue
language turned up nothing tied to any of its 15 user tasks — correctly documented as "no
boundary event needed," not silently skipped.)

This partly supersedes the "Notes on scope" caveat below: boundary-event body syntax has now
been used in a real build.

---

## 20. `= empty` on an association: valid in an `IF`, invalid in a `RETRIEVE WHERE`

Found 2026-08-21 writing a utility to find context rows with no wired `System.Workflow`.

```
RETRIEVE $Runs FROM Module.Entity WHERE RunStatus = X and Assoc_Ref = empty;
```

passed both `mxcli check` and `mxcli check --references` clean, but native `mx check` failed
with `CE0161 "Error(s) in XPath constraint"`. A `RETRIEVE … WHERE` clause compiles to an
XPath constraint, and **XPath has no `= empty` comparison for an association reference** —
that syntax exists only in the microflow expression language (IF conditions, decisions).
Fix: filter the retrieve on plain attributes only, then check `$Var/Module.Association =
empty` inside an `IF` in the loop body.

Separately, that `IF` check itself first failed with `CE0117 "Error(s) in expression"` when
written bare as `$Run/AssocName = empty`. Association references in microflow expressions
need the **module-qualified** association name: `$Run/Module.Entity_Other = empty`. Same
silent-pass-then-native-fail pattern — `mxcli check`/`--references` caught neither defect,
only a real `mx check` run did.

---

## Notes on scope

**Structure rules for every construct below — path termination, boundary-event type vs
terminator, event sub-processes, parallel-split limits, multi-user decision methods, versioning
against running instances — are in `workflow-structure-rules.md` (platform semantics from the
Mendix MCP team, 2026-09-02, with an MDL proven/unprobed table). This file stays the syntax and
defect record.**

Workflow **timer** and **wait-for-notification** activities are referenced by
`NOTIFY WORKFLOW` above but their `CREATE WORKFLOW` body syntax has **not been verified**
here; likewise **boundary events** and **sub-workflow** invocation from inside a workflow
body. Probe with `mxcli check` before relying on any form for these.

Access rules: a workflow definition itself carries no access rule. Reachability comes from
the user-task targeting plus the view grants on the task pages.

See [[learned-mdl-preflight]] for the pre-flight STOP-table entries this skill informs
(#18 CALL MICROFLOW without WITH inside a workflow body, #19 any workflow MDL script).
