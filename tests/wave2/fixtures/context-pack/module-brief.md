# Sales — module brief (fixture)

### Arch constraints
- Approvals write an audit row in the same transaction.

### Document folder plan
| Document | Folder |
|----------|--------|
| ACT_ApprovalStep_Approve | SalesOrder/Microflows |
| Product_NewEdit | Catalog/Pages |

### Build steps  (one row per dispatch, i.e. per script)
| Step | Builds | Reads | Example | Slice |
|------|--------|-------|---------|-------|
| 5.1 | Sales.ACT_ApprovalStep_Approve | Sales.ApprovalStep, Sales.ApprovalStatus | Sales.ACT_ApprovalStep_Reject | 02-approvals |
| 5.2 | Sales.Product_NewEdit | Sales.Product | Sales.Product_Overview | — |
| 5.3 | Sales.ACT_ApprovalStep_ApproveAll | Sales.ApprovalStepp | — | — |
