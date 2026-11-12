# Processes

Purchase Request (public sample app), real run D52. Format: templates/processes.example.md.

## P03: Complete a purchase order
status: confirmed
roles: PurchaseOrderCreator
source: model: actions.json, PurchaseOrder_Edit (PromiseDate is a required input in listView1); D52
steps:
1. [PurchaseOrderCreator] Fill "PromiseDate" with "1/20/2027"
2. [PurchaseOrderCreator] Click "Save"  => PurchaseApprovals.PurchaseOrder_Edit.actionButton1
expect text: "Saved"
