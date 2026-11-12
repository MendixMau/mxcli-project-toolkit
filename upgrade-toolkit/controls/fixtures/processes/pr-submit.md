# Processes

Purchase Request (public sample app), real run D19. Format: templates/processes.example.md.

## P01: Submit a purchase request
status: confirmed
roles: Requester
source: model: actions.json, the New Request wizard (NewRequest_Step1..3, ProductLine_NewEdit); D19
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
