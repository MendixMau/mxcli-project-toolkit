# Processes

Purchase Request (public sample app), run 3, P05: the New Request wizard's New Attachment, then the popup's Add.

## P05: Add a wizard attachment
status: confirmed
roles: Requester
source: model: actions.json, NewRequest_Step1.actionButton5 (a microflow shows Attachment_NewEdit) and Attachment_NewEdit.actionButton1; run 3 P05
steps:
1. [Requester] Click "New Attachment"  => PurchaseApprovals.NewRequest_Step1.actionButton5
2. [Requester] Fill "fileManager1" with "upg-seed.jpeg"
3. [Requester] Click "Add"  => PurchaseApprovals.Attachment_NewEdit.actionButton1
expect text: "upg-seed.jpeg"
