# App dossier: PurchaseRequests (fixture)
Generated 2026-09-15 from PurchaseRequests.mpr (0000000000000000) with mxcli v0.21.0 · facts: analysis/app-facts/

## 1. Verdict summary
| section | status | reason |
|---|---|---|
| 2. Inventory | **pass** | three own modules, one wide entity (numbered cell and bold verdict on purpose: the renderer must accept both) |
| Dependency shape | fail | DEP-TANGLE-01 has no disposition yet |
| Flow risk patterns | pass | all four loop microflows dispositioned |
| Security posture | pass | (deliberately wrong: the instrument did not collect it; the renderer must show fault) |
| Lint baseline | skipped | not run this milestone |

## 2. Inventory
Three own modules. `Orders.PurchaseOrder` carries 23 attributes (`MAX_ATTRIBUTES_PER_ENTITY` 20).

## 3. Dependency shape
One tangle of three modules: Approvals, Orders, Suppliers. **DEP-TANGLE-01**.

## 4. Flow risk patterns
| id | microflow | pattern | evidence |
|---|---|---|---|
| LOOP-TQ-01 | Orders.SUB_SyncOrderLines | LOOP_TQ, REST_IN_LOOP, LOOP_NESTED | mdl/Orders.SUB_SyncOrderLines.mdl:13 |

## 5. Security posture
Status: pass

## 6. Lint baseline
Status: skipped

## 8. Dispositions
- LOOP-TQ-01 · fix · team · slice S-03, retrieve once, commit list

## 9. Method
Thresholds: defaults. Dead elements section deliberately omitted from this fixture dossier.
