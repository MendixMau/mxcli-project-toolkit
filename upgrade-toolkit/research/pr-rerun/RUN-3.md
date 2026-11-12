# Purchase Request, run 3: journeys stage with the new journey engine (toolkit pr-rebuild = main 7fdee04e + 2 fixes)

Stage run: `upgrade-pipeline.sh --from journeys` only (old 10.24 baseline first, then new 11.12.5 app at app HEAD 99a533d, mx check 0 errors).
Gate not weakened (DEFECT_MAX 0.30), no `--bar processes`, no hand edits to verdicts, no baseline-evidence file written.
Exit 11 (INVALID: coverage), as expected while 49 > 43.

## Numbers
| | run 2 | run 3 |
|---|---|---|
| baseline defects D of generated G | 68 of 146 (46%) | **49 of 145 (33.8%)** |
| limit 30% | 43 | **43** (0.30 x 145 = 43.5) |
| new-app regressions | 1 (top bar logo) | **1** (MyRequests.container6, see below) |
| processes compiled / pass on baseline | 3 / 3 | 13 / 12 (P10 FAIL on both apps) |
| destructive (own line) | n/a | `destructive: 1/0 of 1 (identity 1; shared database ...)` on both apps: 1 pass, 0 fail |
| park | 3/4/6/8 | 5/4/6/8 all walked (23 of 23) |

G fell 146 -> 145: B1 supersede moved the covered act-* journeys into the legs; 134 todo unchanged.
Progress line: not produced. It comes from `bin/gate.sh` (PV-POS-1) and the stage stopped at journeys (exit 11) before diff/gate; I did not run the gate step (task: journeys only).
Coverage line: `actions 280 found - 145 generated - 96 pass on baseline (49 defect) - 95 pass on new - 1 regression - coverage 96/279 (34%)`.

## What moved the number (68 -> 49)
Toolkit (main): park/unassigned guard, B1 supersede, double-click rows, destructive tiers. Spec (processes.md, all `confirmed (agent-written, needs key-user confirmation)`): P02 leg 4 (Receiver completes the line: Complete, Invoice number, Invoice date, Save, Received), P04/P04b (UI-seeded .jpeg and .pdf workflow attachments), P12/P13 (preview/download), P05, P06/P06b/P06c, P07, P08, P10. Field-proof debug loop on the old app (3 passes) is in DECISIONS R31.

## Instrument findings fixed in this run (commits dab66496, eabf2510)
1. journey-verbs.js `topmost`: the click right after a tab-page click prefers the same-named element inside that tab's pane when 2+ are shown (Admin instance view: header Back and the comment row's Add attachment are both `actionButton7`; cluster 11 was this, not an old-app limit; Add attachment is a per-comment button and only exists once a comment exists). One-shot after a first version broke Pause (a snippet's `actionButton16`).
2. process_journeys.py: a pinned popup action right after a microflow-opened page is taken in place (P05 had compiled to 5 legs); the step before a Pop-up menu item gets the `.mx-page` guard (a closed menu has no named element).
Controls: `run-controls.sh --only '^(process-|verbs-|journey-verbs|journeys-verb)'` ran (exit 0, no FAIL in the tail shown); I did not add new controls or FEEDBACK rows (parked).

## Per-cluster: what still fails and why (49)
- Assign to me, 6+: Task_{Approver,POCreator,Receiver,InvoiceProcessor}.actionButton19 and TaskInbox.8/12. Park leaves the NEWEST task per user unassigned, but the one-click journey opens another (assigned) task; needs the journey to open the unassigned one. Not a process fix.
- Admin Task details / assign, 7: Snip_UserTaskView_Details.5/9/11, UserTask_Assign.2/7/8/9: need a task with no targets or non-Single completion; none exists (FIXTURE).
- Audit trail / activity, 7: Snip_AuditTrailViewer_Toolbar.1-5, Snip_WorkflowActivityRecord_Details.4, Snip_Workflow_ActivityTimelineOnly_Full.5: only via "open parent workflow"; no sub-workflows (OLD-APP/FIXTURE).
- Workflow ops, 4 + P10: MoreActions.13 (Continue), .18 (Retry), Workflow_Retry_Options.1/2 need Incompatible/Failed (no UI route). P10 leg FAILs at "Unpause Workflow" on both apps: after Pause the pop-up menu trigger does not open ("none of the 1 pop-up menu trigger(s) opened") although Pause itself passed; probably the blocking progress/refresh after Pause. Its covered units 14-17 count as defects through the failed leg. Next try: wait for the page to settle between menu steps.
- Comment/attachment row, ~9: Snip_Admin.3/4/6/8, listView6, WorkflowAttachment_View.16/17, WorkflowComment_Edit_Admin.5, WorkflowCommentHelper_Edit.5. Attachments and comments now exist (seeded), but the row buttons were not walked: a delete click in the Admin comment row opened the attachment view in my debug pass, so P10 does not delete. Needs a per-row verb (scoped to the row that has the button).
- Own comment, 2: Comments_TaskInbox.16/17 (P09, see PARKED).
- Task pages, 5: PurchaseApprovals.Attachments.actionButton6/container12 (task-page attachment snippet, needs an attachment on the open task), Task_Receiver.actionButton5 (edit of an already completed line), Task_Approver.10/11 (second approver), Task_POCreator.actionButton13 (Decline at the first state: the one-click journey opens a task in another state; P06 covers 11, P06b 12, P06c 14, a P06d for 13 would close it).
Not closed: 49 - 43 = 6 over the limit. Cheapest known moves: P06d (-1), P10 menu settle (-4), assign-to-me journey picks the unassigned task (-6, toolkit).

## Regression
act-PurchaseApprovals.MyRequests.container6 (attachment tile on My Requests): old reached it, new did not. The selected (newest) request on the new app has no attachment ("No items found") while the DB holds one attachment on both sides (jold/jnew copies each count 1). Looks like data order (which request is selected first), not a model change; not proven. PARKED.
Also 119 screen REVIEW lines (Atlas 4 top bar/layout), shot-accept not written (needs both images opened).

## PARKED (needs a stronger model or the owner)
1. P09 (Approver own comment: write, edit, delete): the compiler refuses `Fill "Content"` because textArea3 sits under a conditionally visible data view (State = InProgress) and an empty Submit saves nothing. Policy question: may a confirmed process assert a conditionally visible field? Left `status: draft`.
2. P11 (second approver): the model has the route (SumTotalPrice >= 2500, FindTargetUsers_SecondApprover excludes the first approver) but the fixture has one Approver user, so the 2nd task has no target. Needs a second Approver user in users.json and a leg for it (same role twice).
3. Regression MyRequests.container6 (above).
4. P10 menu step after Pause (above).
5. The .pdf seed is a text file named .pdf (journey-verbs upload); fine for the UI, not a valid PDF.
6. Gate/Progress line not produced; FEEDBACK/controls for the two instrument fixes not written.
Files here: journeys-before-picked.run3.out, journeys-after.run3.out, processes.run3.md, DECISIONS.run3.md (R29-R31), NEEDS-JUDGMENT.run3.md.
