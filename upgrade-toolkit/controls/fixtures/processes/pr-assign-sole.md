# Processes

Purchase Request 3.3.0 (public sample app), captured from a real rebuild run (P02 of its processes.md, unchanged). The four "Assign to me" steps are the QW-2 golden input. Format: templates/processes.example.md.

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
15. [Approver] Click "Assign to me"  => PurchaseApprovals.Task_Approver.actionButton19
16. [Approver] Click "Approve"  => PurchaseApprovals.Task_Approver.actionButton9
17. [PurchaseOrderCreator] Click "View"  => PurchaseApprovals.TaskInbox.actionButton7
18. [PurchaseOrderCreator] Click "Assign to me"  => PurchaseApprovals.Task_POCreator.actionButton19
19. [PurchaseOrderCreator] Click "Select Vendor"  => PurchaseApprovals.Task_POCreator.actionButton1
20. [PurchaseOrderCreator] Click "Select"  => PurchaseApprovals.Vendor_Select.actionButton4
21. [PurchaseOrderCreator] Click "Save"  => PurchaseApprovals.Vendor_Select.actionButton1
22. [PurchaseOrderCreator] Click "Create PO(s)"  => PurchaseApprovals.Task_POCreator.actionButton10
23. [PurchaseOrderCreator] Click "Complete PO(s)"  => PurchaseApprovals.Task_POCreator.actionButton5
24. [PurchaseOrderCreator] Fill "PromiseDate" with "1/20/2027"
25. [PurchaseOrderCreator] Click "Save"  => PurchaseApprovals.PurchaseOrder_Edit.actionButton1
26. [PurchaseOrderCreator] Click "Finish"  => PurchaseApprovals.Task_POCreator.actionButton9
27. [Receiver] Click "View"  => PurchaseApprovals.TaskInbox.actionButton7
28. [Receiver] Click "Assign to me"  => PurchaseApprovals.Task_Receiver.actionButton19
29. [Receiver] Click "Received"  => PurchaseApprovals.Task_Receiver.actionButton9
30. [InvoiceProcessor] Click "View"  => PurchaseApprovals.TaskInbox.actionButton7
31. [InvoiceProcessor] Click "Assign to me"  => PurchaseApprovals.Task_InvoiceProcessor.actionButton19
32. [InvoiceProcessor] Click "Complete"  => PurchaseApprovals.Task_InvoiceProcessor.actionButton9
expect: PurchaseApprovals.Request where Title = "Req ${RUN_ID}"
notes: park counts (D52): 3 requests wait for the Approver, 4 for the PO creator, 6 for the Receiver, 8 for the Invoice processor. Leg 3 needs a vendor linked to the chosen product and PromiseDate in listView1 (F43).
