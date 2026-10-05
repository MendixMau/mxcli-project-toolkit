# Procurement — module brief (fixture)

### Arch constraints
- Approvals write an audit row in the same transaction.

### Document folder plan
| Document | Folder |
|----------|--------|
| ACT_ApprovalStep_Approve | Requisition/Microflows |
| CatalogItem_NewEdit | Supplier/Pages |

### Build steps  (one row per dispatch, i.e. per script)
| Step | Builds | Reads | Example | Slice |
|------|--------|-------|---------|-------|
| 5.1 | Procurement.ACT_ApprovalStep_Approve | Procurement.ApprovalStep, Procurement.ApprovalStatus | Procurement.ACT_ApprovalStep_Reject | 02-approvals |
| 5.2 | Procurement.CatalogItem_NewEdit | Procurement.CatalogItem | Procurement.CatalogItem_Overview | — |
| 5.3 | Procurement.ACT_ApprovalStep_ApproveAll | Procurement.ApprovalStepp | — | — |
