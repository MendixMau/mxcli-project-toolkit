# Processes

Purchase Request 3.3.0 (public sample app), rebuild run R. Format: templates/processes.example.md.
Rewritten from the actions.json of the old model (the earlier files were lost); steps confirmed by reading the pages' MDL
(Task_Approver, Task_POCreator, Vendor_Select, Task_Receiver, Task_InvoiceProcessor), not by a key user. See DECISIONS R7.

Run 3 (R29): P01, P02 (leg 4 changed), P04 (changed), P04b, P05-P08, P10, P12, P13 and P06b/P06c; P09 stays a draft (P12/P13 are named so they run after P10: their popup stays open) are `status: confirmed` (agent-written, needs key-user confirmation): I wrote them
from the page MDL and upgrade-toolkit/research/design-2026-10-14/pr-baseline.md; no key user has read them. The owner
confirms or edits them later. P11 (second approver) is not written: see DECISIONS R29.

## P01: Submit a purchase request
status: confirmed
roles: Requester
source: model: actions.json, the New Request wizard (NewRequest_Step1..3, ProductLine_NewEdit)
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P01 ${RUN_ID}"
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
expect: PurchaseApprovals.Request where Title = "Req P01 ${RUN_ID}"

## P02: A purchase request goes through approval, purchase order, receipt and invoice
status: confirmed (agent-written, needs key-user confirmation)
roles: Requester, Approver, PurchaseOrderCreator, Receiver, InvoiceProcessor
source: model: actions.json, TaskInbox and the Task_* pages; Task_POCreator MDL steps 1 to 4; leg 4 per pr-baseline.md cluster 3 (the Receiver confirms each product line: invoice number, Complete, Save, then Received)
park: 5 after leg 1, 4 after leg 2, 6 after leg 3, 8 after leg 4
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P02 ${RUN_ID}"
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
26. [Receiver] Click "Edit product line"  => PurchaseApprovals.Task_Receiver.actionButton4
27. [Receiver] Click "Complete"  => PurchaseApprovals.ProductLine_Edit_Receiver.actionButton1
28. [Receiver] Fill "InvoiceNumber" with "INV-${RUN_ID}"
29. [Receiver] Fill "InvoiceDate" with "1/16/2027"
30. [Receiver] Click "Save"  => PurchaseApprovals.ProductLine_Edit_Receiver.actionButton2
31. [Receiver] Click "Received"  => PurchaseApprovals.Task_Receiver.actionButton9
32. [InvoiceProcessor] Click "View"  => PurchaseApprovals.TaskInbox.actionButton7
33. [InvoiceProcessor] Click "Complete"  => PurchaseApprovals.Task_InvoiceProcessor.actionButton9
expect: PurchaseApprovals.Request where Title = "Req P02 ${RUN_ID}"
notes: no "Assign to me" legs: each smoke role has one user, so the task is auto-assigned on arrival (Task page shows Unassign; R17). park counts (D52): 5 requests wait for the Approver (run 3: at least 5 so the own-comment and outcome journeys do not run dry), 4 for the PO creator, 6 for the Receiver, 8 for the Invoice processor. Leg 3 needs a vendor linked to the chosen product and PromiseDate in listView1 (F43). Leg 4 (run 3): Task_Receiver row button (Awaiting delivery) > ProductLine_Edit_Receiver: Complete, Invoice number, Save.

## P04: Attach a .jpeg file to a workflow instance
status: confirmed (agent-written, needs key-user confirmation)
roles: Administrator
source: model: actions.json, Admin_Homepage container3 > Admin_Workflow_Overview > WorkflowDefinition_View > Admin_Workflow_Instance_View, Comments and attachments tab, Add attachment (F44); run 3 adds the .pdf and the attachment view (pr-baseline.md clusters 10 and 11)
steps:
1. [Administrator] Click "Workflows"  => PurchaseApprovals.Admin_Homepage.container3
2. [Administrator] Click "workflow"  => PurchaseApprovals.Admin_Workflow_Overview.dataGrid21
3. [Administrator] Click "instance"  => PurchaseApprovals.WorkflowDefinition_View.actionButton19
4. [Administrator] Fill "Content" with "Seed jpeg ${RUN_ID}"
5. [Administrator] Click "Submit"  => WorkflowCommons.Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton1
6. [Administrator] Click "Add attachment"  => WorkflowCommons.Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton7
7. [Administrator] Fill "fileManager1" with "upg-seed.jpeg"
8. [Administrator] Click "Save"  => WorkflowCommons.WorkflowAttachment_New.actionButton3
expect text: "upg-seed.jpeg"
notes: an attachment hangs on a comment (the Add attachment button sits in the comment row, only rendered once a comment exists; found run 3). Seeds one .jpeg workflow attachment through the UI (F44 upload verb). The .pdf and the attachment view are P04b.

## P04b: Attach a .pdf file to a workflow instance
status: confirmed (agent-written, needs key-user confirmation)
roles: Administrator
source: model: actions.json, WorkflowAttachment_New (fileManager1); run 3 cluster 10 (second seeded attachment, .pdf)
steps:
1. [Administrator] Click "Workflows"  => PurchaseApprovals.Admin_Homepage.container3
2. [Administrator] Click "workflow"  => PurchaseApprovals.Admin_Workflow_Overview.dataGrid21
3. [Administrator] Click "instance"  => PurchaseApprovals.WorkflowDefinition_View.actionButton19
4. [Administrator] Fill "Content" with "Seed pdf ${RUN_ID}"
5. [Administrator] Click "Submit"  => WorkflowCommons.Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton1
6. [Administrator] Click "Add attachment"  => WorkflowCommons.Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton7
7. [Administrator] Fill "fileManager1" with "upg-seed.pdf"
8. [Administrator] Click "Save"  => WorkflowCommons.WorkflowAttachment_New.actionButton3
expect text: "upg-seed.pdf"
notes: the generated file is a text file named .pdf (journey-verbs.js upload): the app only looks at the name.

## P12: Administrator previews and downloads the .jpeg attachment
status: confirmed (agent-written, needs key-user confirmation)
roles: Administrator
source: model: actions.json, Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton17, WorkflowAttachment_View.actionButton1; run 3 cluster 10. Needs the attachment P04 uploaded to the same (newest) workflow
steps:
1. [Administrator] Click "Workflows"  => PurchaseApprovals.Admin_Homepage.container3
2. [Administrator] Click "workflow"  => PurchaseApprovals.Admin_Workflow_Overview.dataGrid21
3. [Administrator] Click "instance"  => PurchaseApprovals.WorkflowDefinition_View.actionButton19
4. [Administrator] Click "Preview"  => WorkflowCommons.Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton17
5. [Administrator] Click "Download"  => WorkflowCommons.WorkflowAttachment_View.actionButton1
expect text: "upg-seed.jpeg"

## P13: Administrator previews the .pdf attachment
status: confirmed (agent-written, needs key-user confirmation)
roles: Administrator
source: model: actions.json, Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton16; run 3 cluster 10. Needs the attachment P04b uploaded
steps:
1. [Administrator] Click "Workflows"  => PurchaseApprovals.Admin_Homepage.container3
2. [Administrator] Click "workflow"  => PurchaseApprovals.Admin_Workflow_Overview.dataGrid21
3. [Administrator] Click "instance"  => PurchaseApprovals.WorkflowDefinition_View.actionButton19
4. [Administrator] Click "Preview"  => WorkflowCommons.Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton16
expect text: "upg-seed.pdf"

## P05: Requester adds and removes a wizard attachment and a product line, downloads them
status: confirmed
roles: Requester
source: model: actions.json, NewRequest_Step1..3 (attachment list: download container7, delete actionButton3/actionButton4; product line delete Step2.actionButton1); run 3 cluster 4, F44 upload
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P05 ${RUN_ID}"
3. [Requester] Select "Marketing" in "Department"
4. [Requester] Fill "RequiredDeliveryDate" with "1/15/2027"
5. [Requester] Fill "ShippingAddress" with "Dock 4 ${RUN_ID}"
6. [Requester] Fill "RequestReason" with "Upgrade test ${RUN_ID}"
7. [Requester] Click "New Attachment"  => PurchaseApprovals.NewRequest_Step1.actionButton5
8. [Requester] Fill "fileManager1" with "upg-seed.jpeg"
9. [Requester] Click "Add"  => PurchaseApprovals.Attachment_NewEdit.actionButton1
10. [Requester] Click "Download"  => PurchaseApprovals.NewRequest_Step1.container7
11. [Requester] Click "Delete"  => PurchaseApprovals.NewRequest_Step1.actionButton3
12. [Requester] Click "New Attachment"  => PurchaseApprovals.NewRequest_Step1.actionButton5
13. [Requester] Fill "fileManager1" with "upg-seed.pdf"
14. [Requester] Click "Add"  => PurchaseApprovals.Attachment_NewEdit.actionButton1
15. [Requester] Click "Next"  => PurchaseApprovals.NewRequest_Step1.actionButton1
16. [Requester] Click "Add product"  => PurchaseApprovals.NewRequest_Step2.actionButton4
17. [Requester] Select the first in "referenceSelector2"
18. [Requester] Fill "Quantity" with "2"
19. [Requester] Click "Save"  => PurchaseApprovals.ProductLine_NewEdit.actionButton1
20. [Requester] Click "Delete"  => PurchaseApprovals.NewRequest_Step2.actionButton1
21. [Requester] Confirm
22. [Requester] Click "Add product"  => PurchaseApprovals.NewRequest_Step2.actionButton4
23. [Requester] Select the first in "referenceSelector2"
24. [Requester] Fill "Quantity" with "2"
25. [Requester] Click "Save"  => PurchaseApprovals.ProductLine_NewEdit.actionButton1
26. [Requester] Click "Next"  => PurchaseApprovals.NewRequest_Step2.actionButton2
27. [Requester] Click "Download"  => PurchaseApprovals.NewRequest_Step3.container7
28. [Requester] Click "Delete"  => PurchaseApprovals.NewRequest_Step3.actionButton4
29. [Requester] Click "Submit"  => PurchaseApprovals.NewRequest_Step3.actionButton1
expect: PurchaseApprovals.Request where Title = "Req P05 ${RUN_ID}"

## P06: PO creator declines a request once the vendors are chosen
status: confirmed (agent-written, needs key-user confirmation)
roles: Requester, Approver, PurchaseOrderCreator
source: model: actions.json + Task_POCreator MDL (POState buttons); run 3, pr-baseline.md cluster 5 (Decline at Ready_to_create_PO)
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P06 ${RUN_ID}"
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
20. [PurchaseOrderCreator] Click "Decline"  => PurchaseApprovals.Task_POCreator.actionButton11
expect: PurchaseApprovals.Request where Title = "Req P06 ${RUN_ID}"

## P06b: PO creator declines a request after the purchase orders are created
status: confirmed (agent-written, needs key-user confirmation)
roles: Requester, Approver, PurchaseOrderCreator
source: model: actions.json + Task_POCreator MDL (POState buttons); run 3, pr-baseline.md cluster 5 (Decline at Please_fill_out_the_missing_fields)
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P06b ${RUN_ID}"
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
21. [PurchaseOrderCreator] Click "Decline"  => PurchaseApprovals.Task_POCreator.actionButton12
expect: PurchaseApprovals.Request where Title = "Req P06b ${RUN_ID}"

## P06c: PO creator declines a request once the purchase orders are completed
status: confirmed (agent-written, needs key-user confirmation)
roles: Requester, Approver, PurchaseOrderCreator
source: model: actions.json + Task_POCreator MDL (POState buttons); run 3, pr-baseline.md cluster 5 (Decline at Ready_to_complete_the_task)
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P06c ${RUN_ID}"
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
24. [PurchaseOrderCreator] Click "Decline"  => PurchaseApprovals.Task_POCreator.actionButton14
expect: PurchaseApprovals.Request where Title = "Req P06c ${RUN_ID}"

## P07: PO creator chooses, deselects and re-chooses a vendor
status: confirmed (agent-written, needs key-user confirmation)
roles: Requester, Approver, PurchaseOrderCreator
source: model: actions.json + Task_POCreator MDL (POState buttons); run 3, pr-baseline.md cluster 5 (Vendor_Select.Deselect)
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P07 ${RUN_ID}"
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
19. [PurchaseOrderCreator] Click "Deselect"  => PurchaseApprovals.Vendor_Select.actionButton5
20. [PurchaseOrderCreator] Click "Select"  => PurchaseApprovals.Vendor_Select.actionButton4
21. [PurchaseOrderCreator] Click "Save"  => PurchaseApprovals.Vendor_Select.actionButton1
expect: PurchaseApprovals.Request where Title = "Req P07 ${RUN_ID}"

## P08: PO creator edits a product line
status: confirmed (agent-written, needs key-user confirmation)
roles: Requester, Approver, PurchaseOrderCreator
source: model: actions.json + Task_POCreator MDL (POState buttons); run 3, pr-baseline.md cluster 5 (ProductLine_Edit_POCreator.Save changes)
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P08 ${RUN_ID}"
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
17. [PurchaseOrderCreator] Click "Edit product"  => PurchaseApprovals.Task_POCreator.actionButton2
18. [PurchaseOrderCreator] Click "Save changes"  => PurchaseApprovals.ProductLine_Edit_POCreator.actionButton1
expect: PurchaseApprovals.Request where Title = "Req P08 ${RUN_ID}"

## P09: Approver writes, edits and deletes an own comment
status: draft
roles: Requester, Approver
source: model: actions.json, Comments_TaskInbox (Submit 1, edit 17, delete 16), WorkflowCommentHelper_Edit.Save changes; run 3 cluster 6 (the other task roles share the snippet, one role is walked)
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P09 ${RUN_ID}"
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
15. [Approver] Fill "Content" with "Note ${RUN_ID}"
16. [Approver] Click "Submit"  => PurchaseApprovals.Comments_TaskInbox.actionButton1
17. [Approver] Click "Edit comment"  => PurchaseApprovals.Comments_TaskInbox.actionButton17
18. [Approver] Fill "Content" with "Edited ${RUN_ID}"
19. [Approver] Click "Save changes"  => WorkflowCommons.WorkflowCommentHelper_Edit.actionButton5
20. [Approver] Click "Delete comment"  => PurchaseApprovals.Comments_TaskInbox.actionButton16
expect: PurchaseApprovals.Request where Title = "Req P09 ${RUN_ID}"
notes: DRAFT, not walked: the compiler refuses Fill "Content" on Comments_TaskInbox (textArea3 is conditionally visible, dataView7 State = InProgress), and an empty Submit saves no comment, so no own comment exists to edit or delete. Parked in RUN-3.md (gate policy: a process may assert a conditionally visible field).

## P10: Administrator comments on a workflow, then pauses, unpauses, aborts and restarts it
status: confirmed (agent-written, needs key-user confirmation)
roles: Requester, Administrator
source: model: actions.json, Admin_Workflow_Instance_View, Snip_WorkflowView_CommentsAndAttachments_Admin, Snip_Workflow_MoreActions; run 3 clusters 8 and 9. The Requester leg makes the newest workflow, which the Administrator opens first
steps:
1. [Requester] Click "New Request"  => PurchaseApprovals.MyRequests.actionButton2
2. [Requester] Fill "Title" with "Req P10 ${RUN_ID}"
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
14. [Administrator] Click "Workflows"  => PurchaseApprovals.Admin_Homepage.container3
15. [Administrator] Click "workflow"  => PurchaseApprovals.Admin_Workflow_Overview.dataGrid21
16. [Administrator] Click "instance"  => PurchaseApprovals.WorkflowDefinition_View.actionButton19
17. [Administrator] Fill "Content" with "Admin note ${RUN_ID}"
18. [Administrator] Click "Submit"  => WorkflowCommons.Snip_WorkflowView_CommentsAndAttachments_Admin.actionButton1
19. [Administrator] Click "Pause Workflow"  => WorkflowCommons.Snip_Workflow_MoreActions.actionButton16
20. [Administrator] Click "Unpause Workflow"  => WorkflowCommons.Snip_Workflow_MoreActions.actionButton17
21. [Administrator] Click "Abort Workflow"  => WorkflowCommons.Snip_Workflow_MoreActions.actionButton15
22. [Administrator] Click "Restart Workflow"  => WorkflowCommons.Snip_Workflow_MoreActions.actionButton14
notes: the comment-row buttons (edit, delete, Snip_Admin.3/4/8) are not walked here: a delete click in the row opened the attachment view (run 3 debug), see RUN-3
expect: PurchaseApprovals.Request where Title = "Req P10 ${RUN_ID}"

