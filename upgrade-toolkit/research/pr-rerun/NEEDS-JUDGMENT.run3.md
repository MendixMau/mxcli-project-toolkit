# NEEDS JUDGMENT: step journeys, exit 11

run folder: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1
work: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work
source 10.24.0.73019 -> target 11.12.5
Rule: the items below are pending, not passed: a REGRESSION is fixed, the rest are decided in writing (allow/approved files named in steps/*.md), then rerun:

    /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/night/prrebuild/upgrade-toolkit/bin/cloud/upgrade-pipeline.sh --app-zip /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/dl/Purchase_Request.mpk --source 10.24.0.73019 --target 11.12.5 --work /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work --from journeys

## Journeys on the NEW app (exit 1): REGRESSION/FAIL is a gate FAIL, INVALID blocks DONE, SCREEN REVIEW needs both images opened and a reason in shot-accept.txt (exit 11)

file: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/journeys-after.out

```
  PASS    act-PurchaseApprovals.NewRequest_Step1.navigationList2   [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f
  PASS    act-PurchaseApprovals.NewRequest_Step1.navigationList2_2  [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f
  PASS    act-PurchaseApprovals.NewRequest_Step2.actionButton3     [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f
  PASS    act-PurchaseApprovals.NewRequest_Step2.navigationList2   [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f
  PASS    act-PurchaseApprovals.NewRequest_Step2.navigationList2_2  [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f
  PASS    act-PurchaseApprovals.NewRequest_Step3.actionButton3     [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:649a8a75303c
  PASS    act-PurchaseApprovals.NewRequest_Step3.navigationList2   [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f
  PASS    act-PurchaseApprovals.NewRequest_Step3.navigationList2_2  [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f
  PASS    login-Requester                                          [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f
  PASS    menu_My_requests-Requester                               [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f
  PASS    proc-p01-01                                              [SCREEN REVIEW] screen REVIEW 25% of the page changed; new @sha256:d332b4aecd0f effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    proc-p02-01                                              [SCREEN REVIEW] screen REVIEW 38% of the page changed; 4% of the page had content before and  effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    proc-p05-01                                              [SCREEN REVIEW] screen REVIEW 39% of the page changed; 4% of the page had content before and  effect REVIEW step18 WorkflowCommons.UserTaskView: old +1, new +0; step18 WorkflowCommons.UserTaskView_TargetUsers: old +1, new
  PASS    proc-p06-01                                              [SCREEN REVIEW] screen REVIEW 40% of the page changed; 4% of the page had content before and  effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    proc-p06b-01                                             [SCREEN REVIEW] screen REVIEW 40% of the page changed; 4% of the page had content before and  effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    proc-p06c-01                                             [SCREEN REVIEW] screen REVIEW 41% of the page changed; 4% of the page had content before and  effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    proc-p07-01                                              [SCREEN REVIEW] screen REVIEW 41% of the page changed; 4% of the page had content before and  effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    proc-p08-01                                              [SCREEN REVIEW] screen REVIEW 41% of the page changed; 4% of the page had content before and  effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    proc-p10-01                                              [SCREEN REVIEW] screen REVIEW 41% of the page changed; 4% of the page had content before and  effect REVIEW step7 WorkflowCommons.UserTaskView: old +1, new +0; step7 WorkflowCommons.UserTaskView_TargetUsers: old +1, new +
  PASS    act-PurchaseApprovals.Admin_Homepage.container2          [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.Admin_Homepage.container4          [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.Admin_Homepage.container7          [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.Admin_Homepage.container8          [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.Atlas_TopBar_Customized.container6  [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.Atlas_TopBar_Customized.image2     [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-WorkflowCommons.Snip_WorkflowDashboard_Header.actionButton2  [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    create-save                                              [SCREEN REVIEW] screen REVIEW 22% of the page changed; 9% of the page had content before and 
  PASS    login-Administrator                                      [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    menu_Home-Administrator                                  [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    proc-p04-01                                              [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1 effect REVIEW step5 WorkflowCommons.WorkflowComment_WorkflowView: old +1, new +0
  PASS    proc-p04b-01                                             [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1 effect REVIEW step5 WorkflowCommons.WorkflowComment_WorkflowView: old +1, new +0
  FAIL    proc-p10-02                                             FAIL 20. Click "Unpause Workflow": actions completed pop_upMenu5: none of the 1 pop-up menu trigger(s) on the page opened .mx-name-pop_upMenu5 [BASELINE DEFECT (before FAIL): no evidence] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    proc-p12-01                                              [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    proc-p13-01                                              [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    login-Approver                                           [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:42c64e4d5890
  PASS    menu_Task_Inbox-Approver                                 [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:42c64e4d5890
  PASS    proc-p02-02                                              [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:42c64e4d5890 effect REVIEW step3 System.WorkflowEndedUserTask: old +0, new +1; step3 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    proc-p06-02                                              [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:1148ca2a1ebf effect REVIEW step3 System.WorkflowEndedUserTask: old +0, new +1; step3 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    proc-p06b-02                                             [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:a81c559a56ef effect REVIEW step3 System.WorkflowEndedUserTask: old +0, new +1; step3 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    proc-p06c-02                                             [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:55cc4e566671 effect REVIEW step3 System.WorkflowEndedUserTask: old +0, new +1; step3 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    proc-p07-02                                              [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:e582cdd4a8d5 effect REVIEW step3 System.WorkflowEndedUserTask: old +0, new +1; step3 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    proc-p08-02                                              [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:0b70dc15ab6e effect REVIEW step3 System.WorkflowEndedUserTask: old +0, new +1; step3 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    login-PurchaseOrderCreator                               [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:a81c559a56ef
  PASS    proc-p02-03                                              [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:a81c559a56ef effect REVIEW step9 System.WorkflowEndedUserTask: old +0, new +1; step9 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    proc-p06-03                                              [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:55cc4e566671 effect REVIEW step6 System.WorkflowEndedUserTask: old +0, new +1; step6 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    proc-p06b-03                                             [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:e582cdd4a8d5 effect REVIEW step7 System.WorkflowEndedUserTask: old +0, new +1; step7 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    proc-p06c-03                                             [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:0b70dc15ab6e effect REVIEW step9 System.WorkflowEndedUserTask: old +0, new +1; step9 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    proc-p07-03                                              [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:391b80d18fe3
  PASS    proc-p08-03                                              [SCREEN REVIEW] screen REVIEW 31% of the page changed; new @sha256:e8f003401e31
  PASS    login-Receiver                                           [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:32cfa25b8706
  PASS    proc-p02-04                                              [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:32cfa25b8706 effect REVIEW step6 System.WorkflowEndedUserTask: old +0, new +1; step6 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  PASS    login-InvoiceProcessor                                   [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:32cfa25b8706
  PASS    proc-p02-05                                              [SCREEN REVIEW] screen REVIEW 29% of the page changed; new @sha256:32cfa25b8706 effect REVIEW step3 System.WorkflowEndedUserTask: old +0, new +1; step3 System.WorkflowEndedUserTaskOutcome: old +0, new +1; st
  FAIL    act-PurchaseApprovals.MyRequests.container6             FAIL role home PurchaseApprovals.MyRequests: reached ".mx-name-container6" never appeared — screenshot act-PurchaseApprovals.MyRequests.container6-ste [REGRESSION] screen INVALID NEW step NOT-REACHED, OLD reached it; new @sha256:6ff8a18c5dfc [shown only if container5: $currentObject != empty]
  PASS    act-PurchaseApprovals.Admin_Workflow_Instance_View.actionButton1  [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.MendixSSOUserOverview.actionButton1  [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.MendixSSOUserOverview.grid1        [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.Product_Overview.actionButton1     [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.Product_Overview.grid1             [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
  PASS    act-PurchaseApprovals.Vendor_Overview.actionButton1      [SCREEN REVIEW] screen REVIEW 27% of the page changed; new @sha256:a145fcbd2aa1
```

## Evidence (exit 11)

summary: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/e2e-after/after/summary.json ; plan: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/journeys/plan.json ; screens: /tmp/claude-0/-home-user/f6fa2bc2-de01-585e-8723-73c458210247/scratchpad/real/run1/work/e2e-after
