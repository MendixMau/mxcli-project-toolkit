# NEEDS JUDGMENT: step journeys, exit 11

run folder: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1
work: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work
source 10.24.0.73019 -> target 11.12.5
Rule: a FAIL or INVALID below is not a pass. Fix or accept it in writing (allow/approved files named in steps/*.md), then rerun:

    /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/night/prrebuild/upgrade-toolkit/bin/cloud/upgrade-pipeline.sh --app-zip /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/dl/Purchase_Request.mpk --source 10.24.0.73019 --target 11.12.5 --work /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work --from journeys

## Journeys on the NEW app (exit 1): REGRESSION/FAIL is a gate FAIL, INVALID blocks DONE, SCREEN REVIEW needs both images opened and a reason in shot-accept.txt (exit 11)

file: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/journeys-after.out

```
  PASS    act-PurchaseApprovals.MyRequests.actionButton2           [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step1.actionButton1     [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step1.actionButton5     [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step1.navigationList2   [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step1.navigationList2_2  [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step2.actionButton2     [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step2.actionButton3     [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step2.actionButton4     [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step2.navigationList2   [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step2.navigationList2_2  [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step3.actionButton1     [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step3.actionButton3     [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step3.navigationList2   [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.NewRequest_Step3.navigationList2_2  [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.ProductLine_NewEdit.actionButton1  [SCREEN REVIEW] screen REVIEW 25% of the page changed; 11% of the page had content before and
  PASS    login-Requester                                          [SCREEN REVIEW] screen REVIEW 34% of the page changed; 14% of the page had content before and
  PASS    menu_My_requests-Requester                               [SCREEN REVIEW] screen REVIEW 34% of the page changed; 14% of the page had content before and
  PASS    proc-p01-01                                              [SCREEN REVIEW] screen REVIEW 34% of the page changed; 14% of the page had content before and effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    proc-p02-01                                              [SCREEN REVIEW] screen REVIEW 38% of the page changed; 14% of the page had content before and effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    login-Approver                                           [SCREEN REVIEW] screen REVIEW 21% of the page changed; 8% of the page had content before and 
  PASS    menu_Task_Inbox-Approver                                 [SCREEN REVIEW] screen REVIEW 21% of the page changed; 8% of the page had content before and 
  PASS    proc-p02-02                                              [SCREEN REVIEW] screen REVIEW 21% of the page changed; 8% of the page had content before and  effect REVIEW step3 System.WorkflowEndedUserTask: old +0, new +1; step3 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    login-PurchaseOrderCreator                               [SCREEN REVIEW] screen REVIEW 21% of the page changed; 8% of the page had content before and 
  PASS    proc-p02-03                                              [SCREEN REVIEW] screen REVIEW 21% of the page changed; 8% of the page had content before and  effect REVIEW step9 System.WorkflowEndedUserTask: old +0, new +1; step9 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    login-Receiver                                           [SCREEN REVIEW] screen REVIEW 21% of the page changed; 8% of the page had content before and 
  PASS    proc-p02-04                                              [SCREEN REVIEW] screen REVIEW 21% of the page changed; 8% of the page had content before and 
  PASS    login-InvoiceProcessor                                   [SCREEN REVIEW] screen REVIEW 21% of the page changed; 8% of the page had content before and 
  FAIL    proc-p02-05                                             FAIL 27. Click "View": actions completed .mx-name-actionButton7 not visible [BASELINE DEFECT (before FAIL): no evidence] screen REVIEW 21% of the page changed; 8% of the page had content before and 
  PASS    act-PurchaseApprovals.Admin_Homepage.container2          [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.Admin_Homepage.container3          [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.Admin_Homepage.container4          [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.Admin_Homepage.container7          [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.Admin_Homepage.container8          [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  PASS    act-PurchaseApprovals.Atlas_TopBar_Customized.container6  [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  FAIL    act-PurchaseApprovals.Atlas_TopBar_Customized.image2    FAIL microflow 'image2' on PurchaseApprovals.Atlas_TopBar_Customized (unknown): actions completed locator.click: Timeout 30000ms exceeded. [REGRESSION] screen INVALID no NEW screenshot (journey or step missing after the upgrade) [shown only if image2: conditional]
  PASS    act-WorkflowCommons.Snip_WorkflowDashboard_Header.actionButton2  [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  PASS    create-save                                              [SCREEN REVIEW] screen REVIEW 23% of the page changed; 9% of the page had content before and 
  PASS    login-Administrator                                      [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  PASS    menu_Home-Administrator                                  [SCREEN REVIEW] screen REVIEW 27% of the page changed; 11% of the page had content before and
  FAIL    proc-p04-01                                             FAIL 4. Click "Add attachment": reached ".mx-name-fileManager1" never appeared — screenshot proc-p04-01-step5-NOT-REACHED.png; INVALID 4. Click "Add a [BASELINE DEFECT (before FAIL): no evidence] screen INVALID BASELINE DEFECT: OLD step NOT-REACHED and NEW too: fix the pla
  PASS    act-PurchaseApprovals.MyRequests.container6              [SCREEN REVIEW] screen REVIEW 40% of the page changed; 14% of the page had content before and
  FAIL    act-PurchaseApprovals.NewRequest_Step1.container7       FAIL microflow 'container7' on PurchaseApprovals.NewRequest_Step1 (no-db-effect): actions completed .mx-name-container7 not visible [BASELINE DEFECT (before FAIL): no evidence] screen REVIEW 40% of the page changed; 14% of the page had content before and
  FAIL    act-PurchaseApprovals.NewRequest_Step3.container7       FAIL microflow 'container7' on PurchaseApprovals.NewRequest_Step3 (no-db-effect): actions completed .mx-name-container7 not visible [BASELINE DEFECT (before FAIL): no evidence] screen REVIEW 40% of the page changed; 14% of the page had content before and
  PASS    act-PurchaseApprovals.Attachment_NewEdit.actionButton1   [SCREEN REVIEW] screen REVIEW 26% of the page changed; 9% of the page had content before and 
  PASS    act-PurchaseApprovals.Attachments.actionButton2          [SCREEN REVIEW] screen REVIEW 26% of the page changed; 9% of the page had content before and 
  PASS    act-PurchaseApprovals.Attachments.container12            [SCREEN REVIEW] screen REVIEW 26% of the page changed; 9% of the page had content before and 
  PASS    act-PurchaseApprovals.Comments_TaskInbox.actionButton1   [SCREEN REVIEW] screen REVIEW 26% of the page changed; 9% of the page had content before and 
  FAIL    act-PurchaseApprovals.Comments_TaskInbox.actionButton17 FAIL open PurchaseApprovals.Task_Approver: reached ".mx-name-actionButton17" never appeared — screenshot act-PurchaseApprovals.Comments_TaskInbox.acti [BASELINE DEFECT (before FAIL): no evidence] screen INVALID BASELINE DEFECT: OLD step NOT-REACHED and NEW too: fix the pla [shown only if actionButton17: $currentObject/System.owner = [%CurrentUser%]]
  PASS    act-PurchaseApprovals.TaskInbox.actionButton11           [SCREEN REVIEW] screen REVIEW 26% of the page changed; 9% of the page had content before and 
  FAIL    act-PurchaseApprovals.TaskInbox.actionButton12          FAIL role home PurchaseApprovals.TaskInbox: reached ".mx-name-actionButton12" never appeared — screenshot act-PurchaseApprovals.TaskInbox.actionButton [BASELINE DEFECT (before FAIL): no evidence] screen INVALID BASELINE DEFECT: OLD step NOT-REACHED and NEW too: fix the pla [shown only if actionButton12: $currentObject = empty]
  PASS    act-PurchaseApprovals.TaskInbox.actionButton13           [SCREEN REVIEW] screen REVIEW 25% of the page changed; 8% of the page had content before and 
  PASS    act-PurchaseApprovals.TaskInbox.actionButton7            [SCREEN REVIEW] screen REVIEW 26% of the page changed; 9% of the page had content before and 
  FAIL    act-PurchaseApprovals.TaskInbox.actionButton8           FAIL role home PurchaseApprovals.TaskInbox > tab 'Open tasks': reached ".mx-name-actionButton8" never appeared — screenshot act-PurchaseApprovals.Task [BASELINE DEFECT (before FAIL): no evidence] screen INVALID BASELINE DEFECT: OLD step NOT-REACHED and NEW too: fix the pla [shown only if actionButton8: $currentObject = empty]
  PASS    act-PurchaseApprovals.TaskInbox.actionButton9            [SCREEN REVIEW] screen REVIEW 25% of the page changed; 8% of the page had content before and 
  PASS    act-PurchaseApprovals.TaskInbox.container20              [SCREEN REVIEW] screen REVIEW 26% of the page changed; 9% of the page had content before and 
  PASS    act-PurchaseApprovals.TaskInbox.container25              [SCREEN REVIEW] screen REVIEW 25% of the page changed; 8% of the page had content before and 
  FAIL    act-PurchaseApprovals.Task_Approver.actionButton10      FAIL microflow 'Reject' on PurchaseApprovals.Task_Approver (task-outcome): actions completed .mx-name-actionButton10 not visible [BASELINE DEFECT (before FAIL): no evidence] screen REVIEW 25% of the page changed; 8% of the page had content before and  [shown only if container6: $currentObject = [%CurrentUser%]; LayoutGridRow: $dataView13/PurchaseApprovals.Request_MendixSSOUser_FirstApprover != empty 
  FAIL    act-PurchaseApprovals.Task_Approver.actionButton11      FAIL microflow 'Approve' on PurchaseApprovals.Task_Approver (task-outcome): actions completed .mx-name-actionButton11 not visible [BASELINE DEFECT (before FAIL): no evidence] screen REVIEW 25% of the page changed; 8% of the page had content before and  [shown only if container6: $currentObject = [%CurrentUser%]; LayoutGridRow: $dataView13/PurchaseApprovals.Request_MendixSSOUser_FirstApprover != empty 
  PASS    act-PurchaseApprovals.Task_Approver.actionButton15       [SCREEN REVIEW] screen REVIEW 25% of the page changed; 8% of the page had content before and 
  FAIL    act-PurchaseApprovals.Task_Approver.actionButton19      FAIL open PurchaseApprovals.Task_Approver: reached ".mx-name-actionButton19" never appeared — screenshot act-PurchaseApprovals.Task_Approver.actionBut [BASELINE DEFECT (before FAIL): no evidence] screen INVALID BASELINE DEFECT: OLD step NOT-REACHED and NEW too: fix the pla [shown only if LayoutGridRow: $dataView1/System.WorkflowUserTask_Assignees = empty; actionButton19: $dataView1/State = System.WorkflowUserTaskState.InProgress
```

## Evidence (exit 11)

summary: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/e2e-after/after/summary.json ; plan: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/journeys/plan.json ; screens: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/e2e-after
