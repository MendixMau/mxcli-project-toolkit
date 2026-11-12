# Repair rows missing from steps/repair.md: Purchase Request (WorkflowCommons 3.12.1 -> 4.10.0, Mendix 11.12.5)

Evidence: run1 work/check-10..19.log, fix-wc*.mdl, DECISIONS R14-R18, app git 383c57b/c763e19/793c1b8/1cb10b6; read-only mxcli
on copies of work/original.mpr (old) and the final app .mpr (new). Main toolkit read: steps/repair.md rows 0-20, replacements.tsv
R22/R32, release_impact.py, rolecheck.py, BACKLOG #25.

## Cross-cutting finding (why none of this was flagged before the build)
- release_impact.py `DEFAULT_TYPES = breaking, removal, requirement, deprecation`: type `migration-step` is dropped. WorkflowCommons 4.0.0 has
  24 migration-step rows in the brain ("Replace snippet Snip_WorkflowView_CommentsAndAttachments with Snip_Workflow_CommentsAndAttachments",
  "Added migration logic for one-off data migration"); release-impact.md rows 188-208 contain none of them. Fix: module rows default to
  all types incl. migration-step (Studio Pro rows may keep the filter). Control: PR plan -> release-impact.md lists the 4.0.0 replace rows.
- idcheck approved `REMOVED WorkflowComment_WorkflowView` with "the publisher's migration microflow moves the data". False: 4.x ships only
  ASU_UserTaskView_Migrate (UserTaskView -> WorkflowEndedUserTask), and the app's AfterStartup (MendixSSO.MendixSSO_AfterStartup) never calls
  it. Open finding: completed-task history is not migrated. An approval must name the migration flow and its caller, not assume one.
- BACKLOG #25 then logs all three as "missed" once crosscalls/release rows run against the NEW model.

## Row 21 CE6779 view entity needs OQL version 2
- Signal: `[CE6779] "View Entity '<E>' is only allowed ... 'OQL version 2' ..." at Runtime settings, Entity '<Module>.<E>'`. Seen: 5x WorkflowCommons
  (WorkflowUserTaskView, MyInitiatedWorkflowView, WorkflowGroupView, ConflictedWorkflowView, ConflictedWorkflowDefinitionView) in 4.10.0. Model
  pattern: the NEW model has a view entity in any module AND `UseOQLVersion2` false/absent (old .mpr: false). First WorkflowCommons version with
  view entities: UNVERIFIED.
- Row text: | 21 | CE6779 view entity with OQL v1 (WorkflowCommons 4.x) | `mxcli -p app/<app>.mpr -c "alter settings runtime (UseOQLVersion2: true)"`,
  mx check, `checkdiff.py --fixed CE6779` (here CASCADE: revealed CE2729) | app-wide behaviour change, a decision: list the app's own OQL
  (test_inventory oql facts: datasets, OQL actions, own view entities, Java Core.retrieveOQL*/createOQLTextGetRequest, OQL-module strings) and
  close replacements R32 with it; 0 own OQL = mechanical (PR had none); else a journey or data compare per query |
- Safety: one switch for the whole app; there is no v1-for-own/v2-for-module split. User accepts R32's v2 differences: GROUP BY over associations
  and JOIN without ON rejected, aliases in WHERE rejected, ROUND returns Decimal, numeric type precedence (11.0 COALESCE), no dots in aliases.
  No other runtime setting changed (OptimizeSecurityColumns not in this settings dump: nothing to accept there). Never hold the module back to v1.
- Pre-build: stepupdate/triage: `modver:WorkflowCommons:>=4.0.0` in the plan (or any view entity in the target package) with UseOQLVersion2 off
  -> PREDICTED CE6779. Add as replacements row (coupling, like R22) and do not let `--auto` close OQL rows with oql=0 when the TARGET modules
  bring view entities. Control: fixture = this app's .mpr at 383c57b: predictor says CE6779 x5; after the alter, 0 and setting=true.

## Row 22 CE1613 WorkflowCommons 4.x comment API in own documents
- Signal: CE1613 at own pages/flows naming `WorkflowCommons.SUB_WorkflowView_FindOrCreate`, `ACT_WorkflowCommentHelper_SaveNew.WorkflowView`
  or association `WorkflowComment_WorkflowView` (7 here); module WorkflowCommons <4.0 -> >=4.0. Pre-build: OLD model
  `show callers of WorkflowCommons.SUB_WorkflowView_FindOrCreate` lists own callers (PR: DS_GetWorkflowView_FromUserTask,
  SubmitCommentRequester) and pages whose source walks WorkflowComment_WorkflowView; idcheck REMOVED of that association.
- Recipe (carrier = System.Workflow, as the publisher's Snip_Workflow_CommentsAndAttachments): (1) `DS_GetWorkflow_FromUserTask($WorkflowUserTask)`
  = retrieve over System.WorkflowUserTask_Workflow; (2) snippet parameter WorkflowView -> System.Workflow; list view source
  `database from WorkflowCommons.WorkflowComment where WorkflowCommons.WorkflowComment_Workflow = $Workflow sort by changedDate desc`;
  submit `ACT_WorkflowCommentHelper_SaveNew(WorkflowCommentHelper, Workflow = $Workflow)`; (3) own flows that found the view retrieve the
  Workflow from their own context (Request_Workflow); (4) page data views use DS_GetWorkflow_FromUserTask; drop the dead DS flows. Alternative:
  replace the own snippet by Snip_Workflow_CommentsAndAttachments when it was a copy. Template: final fix-wc7/fix-wc8.mdl. A bin/repair script
  (wc4_comments.py) can generate it: callers from OLD model -> MDL per site, dry run, apply via alter_guard.py.
- Safety: (a) WorkflowView trap: keeping WorkflowView as carrier passes mx check and empties the panel. 4.x read rule on WorkflowView =
  initiator OR UserTaskView assignee/target, and nothing in 4.x creates WorkflowView or UserTaskView (FindOrCreate gone). Rule: refuse a carrier
  entity with zero create sites in the NEW model. (b) Use a database/association source, not a microflow: the run's DS_CommentsOnWorkflow skips
  the publisher's read rule (WorkflowComment_Workflow/.../WorkflowUserTask) and shows comments to anyone given the flow. (c) Change only sources
  and actions (`set ... on <widget>`); `replace`/`create or modify snippet` re-authors every binding (that is how text17 lost DisplayName).
  Control: describe the snippet before/after; only the parameter, source and action lines may differ.
- Control: journey per task role "add comment, comment visible on reload, visible to the next role's task page" (R18 caught it only this way);
  static: no own page opened by a task role reads WorkflowCommons.WorkflowView after repair (WARN).

## Row 8 add-on CE2729 Atlas_Core roles (existing row 8 has the rule, not the tooling)
- Signal: `[CE2729] "No access to microflow 'Atlas_Core.DS_Account_CurrentUser' for user role '<R>' (with no roles defined in module 'Atlas_Core')"`;
  Atlas_Core <3.21 -> >=3.21. mx check named only Administrator (2 errors); the other five roles fail only at runtime (HTTP 560), so count from
  rolecheck.py (stepupdate runs it in main; this run's older worktree lacked it), not from CE2729.
- Recipe: rolecheck.py --json proposals -> `bin/repair/map_roles.py` emits per user role `alter user role <R> add module roles (Atlas_Core.User)`
  (+ Atlas_Core.Administrator for holders of Administration.Administrator / the app admin role), dry run, mxcli exec, rerun rolecheck (exit 0),
  write the mapping table into the report. MDL keyword form: verify against mxcli before shipping (rolecheck notes ALTER USER ROLE writes
  dangling refs silently, MC-8).
- Safety: security change, report each line; no Atlas_Core.User for anonymous/guest or API-only roles (NR1-18); access_matrix.py OLD vs NEW must
  show only Atlas_Core rows added. Control: rolecheck 0 UNMAPPED + smoke 560 count 0 for every role.

## Comment author shows username (System.owner/Name) instead of DisplayName
- Not a 4.x change: the old binding `System.owner/DisplayName` went through the MendixSSOUser specialization; mxcli re-authoring wrote
  `System.owner/MendixSSO.MendixSSOUser/DisplayName`, check rejected it (CE1613, check-13/14) and the run fell back to Name. Name is often an
  opaque id or e-mail: a visible regression and possibly a privacy change, not cosmetic. Fix: put the author text inside dataView6 (already
  sourced by DS_GetOwnerOfComment -> MendixSSOUser) as `{1} = DisplayName`, or avoid re-authoring text17 at all (safety c). Gate: shotdiff text
  compare must flag the changed author string; do not accept.

## Old comment data
- Facts: 3.12.x ACT_WorkflowCommentHelper_SaveNew sets BOTH WorkflowComment_WorkflowView and WorkflowComment_Workflow; the 4.x read rule goes over
  WorkflowComment_Workflow. So comments made under 3.12 survive and show after the repair; "old comment data not migrated" (R12d/R14) overstates it.
- At risk: comments whose WorkflowComment_Workflow is empty (made by older WorkflowCommons versions or own/admin code setting only the view link);
  their only link is dropped with the association table at the first 4.x sync.
- Correct migration, on the OLD module version before the update step: for each WorkflowComment with WorkflowComment_Workflow empty and
  WorkflowComment_WorkflowView set, set WorkflowComment_Workflow = WorkflowView/WorkflowView_Workflow; counts before/after, orphans after = 0.
- Toolkit should offer it: triage runs a count of such orphans on the DB snapshot; 0 closes the row "not relevant: 0 orphan comments"; >0 adds a
  pre-update migration step (MDL microflow run once, or SQL on the snapshot copy). Also wire or report ASU_UserTaskView_Migrate (see top).
