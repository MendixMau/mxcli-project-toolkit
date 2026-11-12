# Purchase Request 3.3.0, 10.24.0 -> 11.12.5 (run1, resumed)

Stage reached: build, after, afterwalk done (mx check 0 errors, QUICK START PASS, afterwalk 17 PASS / 0 regressions); journeys
ran on both apps and stopped at exit 11 (gate stays INVALID, not weakened). Decisions: DECISIONS.run1.md (R13-R21).

## Numbers (journeys-before-picked.run1.out / journeys-after.run1.out)
- Baseline (OLD 10.24 app): 68 of 146 generated actions fail = 46% (limit 43 = 30%): coverage INVALID. First run was 81 (55%);
  13 of those were the P02 spec error (R17) and the cascade it caused. No baseline-evidence file was written.
- New app: 77 pass, 1 REGRESSION (Atlas_TopBar_Customized.image2, logo click times out; R19), screens 492 REVIEW / 39 INVALID (not accepted).
- Processes: P01 pass, P02 legs 1-4 pass on old and new (park 3/4/6/8 all walked), leg 5 fails on both, P04 fails on both.

## F43 / F44 live
- F43 (list-row required inputs): PASS live on the NEW app. P02 leg 3 (PurchaseOrderCreator: select vendor, Create PO(s), PromiseDate in
  the PO list row, Save, Finish) walked 39 steps with 0 FAIL, for 6 parked requests (e2e-after park.log, 6x "PASS 39 FAIL 0").
- F44 (file upload): PASS live on the NEW app for Attachment_NewEdit (Approver uploads upg-seed.jpeg; FileDocument row hascontents=t).
  The Admin path (P04 WorkflowAttachment_New "Add attachment") does not work on EITHER app: no click path/instrument (see cluster 5).

## Repairs made in the build stage (all own-document or settings, in app git log)
1. CE1613 x7: WorkflowCommons 4.10.0 dropped SUB_WorkflowView_FindOrCreate / WorkflowComment_WorkflowView. Comments now on System.Workflow
   (snippet Comments_TaskInbox param System.Workflow; DS_GetWorkflow_FromUserTask, DS_CommentsOnWorkflow, ACT_SaveComment_OnWorkflow;
   SubmitCommentRequester passes Workflow). First attempt (WorkflowView carrier) was a real regression found by the journeys (panel gone):
   nothing creates WorkflowView in 4.x and task users cannot read it. Cosmetic loss: comment author shows System.owner/Name, not DisplayName.
   Old comment data is not migrated.
2. CE6779: `alter settings runtime (UseOQLVersion2: true)` (view entities of WorkflowCommons 4.x). Toolkit has no row for it (BACKLOG 25 only lists it).
3. CE2729: Atlas_Core roles (none before 3.21): Administrator -> Atlas_Core.Administrator + User; the five other roles -> Atlas_Core.User. SECURITY CHANGE, review.
4. Java deps: Gradle CycloneDX failure in sync-java.log is not fatal: vendorlib_mvn.sh fallback resolved them.

## Remaining failure clusters (68 baseline defects + 1 regression), cause
1. Task page buttons (Task_Approver/POCreator/Receiver/InvoiceProcessor, Vendor_Select, PurchaseOrder_Edit, ProductLine_Edit_*; 19 + 8 todo-closed): DATA. Single-action journeys need an open, assigned task in a given state; fixtures park in other states ("Assign to me" never exists, the task is auto-assigned).
2. WorkflowCommons admin snippets, comments and attachments tab (Snip_WorkflowView_CommentsAndAttachments_Admin, WorkflowAttachment_*; 9): DATA (empty lists: no comment/attachment seeded on a workflow) plus NO CLICK PATH.
3. Admin_Workflow_Instance_View tabs and pop-up menu (UserTask_Assign, Snip_UserTaskView_Details, Snip_Workflow_MoreActions, Workflow_*_Options, audit-trail tab; 7+7+5): INSTRUMENT (tab/pop-up menu not opened by the click recipe: ".mx-name-pop_upMenu5 not on screen and no .popupmenu-trigger").
4. Overview grid1 open-page (MendixSSOUserOverview, Product_Overview, Vendor_Overview; 3) and NewRequest wizard (5): NO CLICK PATH / conditional visibility.
5. P04 Admin 'Add attachment' (1) and P02 leg 5 (1): process spec (Receiver must edit each product line, InvoiceNumber, before 'Received'; P04 click does not leave the workflow list). Same on old and new.
6. Regression Atlas_TopBar_Customized.image2: BACKEND/THEME. New screenshots show the customised top bar broken under Atlas_Core 4.5.0 (menu bar items missing, Sign Out beside logo, logo click blocked).

## PARKED FOR A STRONG MODEL
- Gate policy: 46% baseline defects > 30%. Decide how to lower it honestly (seed data for clusters 1-2, fix click recipes for 3-4), do not raise the limit.
- Atlas_Core 4.5.0 top bar layout vs the customised PurchaseApprovals.Atlas_TopBar_Customized (cluster 6): needs a CSS/layout replay decision.
- P02 leg 5 and P04 specs (cluster 5): add Receiver per-line edit steps; find why 'Add attachment' stays on the list.
- Toolkit gaps: no repair row/automation for CE6779 (OQL v2), for WorkflowCommons 4.x comment API in own docs, and the processes generator should not emit "Assign to me" for single-target roles.
- NanoflowCommons UNSAVED accept (accept-unsaved.txt) and the MendixSSOUser rule replay (R11/R12) are assumptions to re-check.
