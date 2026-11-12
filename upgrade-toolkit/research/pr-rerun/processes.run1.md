# Processes

Purchase Request 3.3.0 (public sample app), rebuild run R. Format: templates/processes.example.md.
Rewritten from the actions.json of the old model (the earlier files were lost); steps confirmed by reading the pages' MDL
(Task_Approver, Task_POCreator, Vendor_Select, Task_Receiver, Task_InvoiceProcessor), not by a key user. See DECISIONS R7.

## P01: Submit a purchase request
status: confirmed
roles: Requester
source: model: actions.json, the New Request wizard (NewRequest_Step1..3, ProductLine_NewEdit)
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req ${RUN_ID}"
3. [Requester] Select "Marketing" in "Department"
4. [Requester] Fill "RequiredDeliveryDate" with "1/15/2027"
5. [Requester] Fill "ShippingAddress" with "Dock 4 ${RUN_ID}"
6. [Requester] Fill "RequestReason" with "Upgrade test ${RUN_ID}"
7. [Requester] Click "Next"  => PurchaseApprovals.NewRequest_Step1.actionButton1
8. [Requester] Click "Add product"  => PurchaseApprovals.NewRequest_Step2.actionButton4
9. [Requester] Select the first in "referenceSelector2"
10. [Requester] Fill "Quantity" with "3"
11. [Requester] Click "Save"  => PurchaseApprovals.ProductLine_NewEdit.actionButton1
12. [Requester] Click "Next"  => PurchaseApprovals.NewRequest_Step2.actionButton2
13. [Requester] Click "Submit"  => PurchaseApprovals.NewRequest_Step3.actionButton1
expect: PurchaseApprovals.Request where Title = "Req ${RUN_ID}"

## P02: A purchase request goes through approval, purchase order, receipt and invoice
status: confirmed
roles: Requester, Approver, PurchaseOrderCreator, Receiver, InvoiceProcessor
source: model: actions.json, TaskInbox and the Task_* pages; Task_POCreator MDL steps 1 to 4
park: 3 after leg 1, 4 after leg 2, 6 after leg 3, 8 after leg 4
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req ${RUN_ID}"
3. [Requester] Select "Marketing" in "Department"
4. [Requester] Fill "RequiredDeliveryDate" with "1/15/2027"
5. [Requester] Fill "ShippingAddress" with "Dock 4 ${RUN_ID}"
6. [Requester] Fill "RequestReason" with "Upgrade test ${RUN_ID}"
7. [Requester] Click "Next"  => PurchaseApprovals.NewRequest_Step1.actionButton1
8. [Requester] Click "Add product"  => PurchaseApprovals.NewRequest_Step2.actionButton4
9. [Requester] Select the first in "referenceSelector2"
10. [Requester] Fill "Quantity" with "3"
11. [Requester] Click "Save"  => PurchaseApprovals.ProductLine_NewEdit.actionButton1
12. [Requester] Click "Next"  => PurchaseApprovals.NewRequest_Step2.actionButton2
13. [Requester] Click "Submit"  => PurchaseApprovals.NewRequest_Step3.actionButton1
14. [Approver] Click "View"  => PurchaseApprovals.TaskInbox.actionButton7
15. [Approver] Click "Approve"  => PurchaseApprovals.Task_Approver.actionButton9
16. [PurchaseOrderCreator] Click "View"  => PurchaseApprovals.TaskInbox.actionButton7
17. [PurchaseOrderCreator] Click "Select Vendor"  => PurchaseApprovals.Task_POCreator.actionButton1
18. [PurchaseOrderCreator] Click "Select"  => PurchaseApprovals.Vendor_Select.actionButton4
19. [PurchaseOrderCreator] Click "Save"  => PurchaseApprovals.Vendor_Select.actionButton1
20. [PurchaseOrderCreator] Click "Create PO(s)"  => PurchaseApprovals.Task_POCreator.actionButton10
21. [PurchaseOrderCreator] Click "Complete PO(s)"  => PurchaseApprovals.Task_POCreator.actionButton5
22. [PurchaseOrderCreator] Fill "PromiseDate" with "1/20/2027"
23. [PurchaseOrderCreator] Click "Save"  => PurchaseApprovals.PurchaseOrder_Edit.actionButton1
24. [PurchaseOrderCreator] Click "Finish"  => PurchaseApprovals.Task_POCreator.actionButton9
25. [Receiver] Click "View"  => PurchaseApprovals.TaskInbox.actionButton7
26. [Receiver] Click "Received"  => PurchaseApprovals.Task_Receiver.actionButton9
27. [InvoiceProcessor] Click "View"  => PurchaseApprovals.TaskInbox.actionButton7
28. [InvoiceProcessor] Click "Complete"  => PurchaseApprovals.Task_InvoiceProcessor.actionButton9
expect: PurchaseApprovals.Request where Title = "Req ${RUN_ID}"
notes: no "Assign to me" legs: each smoke role has one user, so the task is auto-assigned on arrival (Task page shows Unassign; R17). park counts (D52): 3 requests wait for the Approver, 4 for the PO creator, 6 for the Receiver, 8 for the Invoice processor. Leg 3 needs a vendor linked to the chosen product and PromiseDate in listView1 (F43).

## P04: Attach a file to a workflow instance
status: confirmed
roles: Administrator
source: model: actions.json, Admin_Homepage container3 > Admin_Workflow_Overview > WorkflowDefinition_View > Admin_Workflow_Instance_View, comments tab, Add attachment (F44)
steps:
1. [Administrator] Click "Workflows"  => PurchaseApprovals.Admin_Homepage.container3
2. [Administrator] Click "workflow"  => PurchaseApprovals.Admin_Workflow_Overview.dataGrid21
3. [Administrator] Click "instance"  => PurchaseApprovals.WorkflowDefinition_View.actionButton19
4. [Administrator] Click "Add attachment"  => WorkflowCommons.Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton7
5. [Administrator] Fill "fileManager1" with "upg-seed.jpeg"
6. [Administrator] Click "Save"  => WorkflowCommons.WorkflowAttachment_New.actionButton3
expect text: "upg-seed.jpeg"
