# MXXXX Order Registration — Test Plan (POC Phase)

> Generated 2026-05-19. Covers happy-path and key risk scenarios for the OutSystems → Mendix POC.
> Update this document as pages and scripts are completed.

---

## 1. Prerequisites before first test run

| # | Prerequisite | How | Status |
|---|---|---|---|
| P1 | Studio Pro "Update Security" click (CE0066 in BusinessApp_Common) | Studio Pro → domain model → "Update security" → Ctrl+S | ⬜ |
| P2 | Steps 7f + 7f2 + 7g scripts applied (SNP popup, Confirm, NewEdit) | mxcli exec | ⬜ |
| P3 | Seed data: Employee record with UserId = demo user's login name | Step 7j / manual | ⬜ |
| P4 | Seed data: at least 1 SalesOrganization record | Step 7j / manual | ⬜ |
| P5 | Seed data: CommonCategory records for status codes (optional for first test) | Step 7j | ⬜ |
| P6 | Studio Pro "Update All Widgets" on Order_OrgChoice (org gallery CE0463) | Studio Pro | ⬜ |
| P7 | App running (mx check = 0 errors, or only CE0066 after Studio Pro fix) | mxcli / Studio Pro | ⬜ |

**Minimum to start testing (happy path no-workflow):** P1 + P2 + P3 + P4.
P5, P6, P7 are needed for a complete demo-ready test.

---

## 2. Demo users assumed

| User | Role | Employee record needed? |
|---|---|---|
| `demo_user` (or MxAdmin) | OrderRegistration.User | Yes — must have Employee with UserId = login name |

> **Risk:** `ACT_OrderDetail_InitNew` calls `Org_Master.GET_Employee_ByUserId($currentUser/Name)`. If no match exists, it shows a user error and returns empty — Order_OrgChoice will not load correctly.

---

## 3. Happy path — new order registration (no workflow)

### Scenario H1: Register a new order (Save / Save Draft)

| Step | Action | Expected result | Risk / Note |
|---|---|---|---|
| H1-1 | Navigate to OrderRegistration_Overview | Gallery loads; 0 records if fresh DB | — |
| H1-2 | Click + New registration request | Order_OrgChoice opens; ApplicantDept pre-filled from Employee record | Fails if no Employee (P3) |
| H1-3 | ContractorLocationCode shows "01" (default) | Field shows '01' | — |
| H1-4 | Click Corporate search | SNP_CorporationSearchPopup opens as popup | Stub exists; popup layout |
| H1-5 | Enter any keyword → click Search and select | Stub returns Contoso K.K.; popup closes; SelectedCompanyName + SelectedCorporateNo populate on OrgChoice | STUB always returns hardcoded result regardless of keyword |
| H1-6 | Click Next | Order_Confirm_Selection opens; shows company + org summary | P7f2 script needed |
| H1-7 | Click Create order | OrderDetail_NewEdit opens | P7g script needed |
| H1-8 | Fill required fields (currency, etc.) | Form accepts input | Fields TBD in script |
| H1-9 | Click Save | ACT_OrderDetail_SaveDraft runs; OrderDetail created in DB; status → '01'; navigate to Overview | Wrapper MF needed (see §6) |
| H1-10 | Overview shows new record with status '01' | Row appears in gallery | Status shows raw '01' until CommonCategory seeded (P5) |
| H1-11 | Click Detail on the new record | OrderDetail_View opens | P7h script needed |

### Scenario H2: Submit for workflow approval (WF request)

> Requires Step 7i (native Mendix Workflow, Studio Pro only) to be complete.

| Step | Action | Expected result |
|---|---|---|
| H2-1 | Follow H1-1 through H1-8 | Same as above |
| H2-2 | Click WF request instead of Save | ACT_Order_Submit runs: SaveDraft → validation → duplicate check → STUB_ACT_WFApplication_Submit |
| H2-3 | Status → '02' (In progress) on Overview | Record shows updated status |
| H2-4 | Admin approves via Workflow task page | Status → '03' (Approved) |

---

## 4. Key business logic to verify

### BL1 — Employee lookup in ACT_OrderDetail_InitNew
- **What:** `GET_Employee_ByUserId($currentUser/Name)` → pre-fills ApplicantDept
- **Pass:** ApplicantDept shows department name from Employee record
- **Fail:** User error dialog shown; page does not load
- **How to test:** Log in as demo user; open OrgChoice; verify ApplicantDept field value matches Employee.DeptName

### BL2 — ChoiceOrg_Dto list creation
- **What:** ACT_OrderDetail_InitNew loops SalesOrganization records → creates ChoiceOrg_Dto NPEs linked to Dto
- **Pass:** Org selection gallery shows all active SalesOrganizations with checkboxes
- **Fail:** Gallery empty (no seed data) or CE0463 (needs Studio Pro "Update All Widgets")
- **Note:** CE0463 means this CANNOT be verified via mxcli-built page alone — Studio Pro step P6 required

### BL3 — Company search result applied to Dto
- **What:** ACT_SNP_CorpSearch_Execute calls STUB → copies CompanyName + CorporateNumber to Dto attributes + sets association
- **Pass:** SelectedCompanyName = 'Contoso K.K.', SelectedCorporateNo = '1234567890123' after popup closes
- **Fail:** Fields remain empty; or popup doesn't close
- **Note:** STUB always returns Contoso K.K. regardless of keyword — expected behavior for POC

### BL4 — ACT_OrderDetail_SaveDraft creates all entities
- **What:** One save call creates: ApplicationCommonHeader + OrderApplicationHeader + OrderCustomerBase + OrderDetail + OrderAreaData
- **Pass:** Record appears in Overview; DB has all 5 entities linked correctly
- **Fail:** Partial create (one of the sub-calls fails); check Mendix log for error node 'OrderRegistration'
- **Risk:** Cross-module MF calls (BusinessApp_Common, Customer_Common) must succeed

### BL5 — ACT_Order_Submit validation chain
- **What:** Submit runs: GET_OrderDetail_Dto → VAL_OrderDetail_BeforeSubmit → ACT_DuplicateCheck_Run → STUB_ACT_WFApplication_Submit
- **Pass:** Status changes to '02'; WF task created
- **Fail:** Silent failure (returns false + logs warning) — check Mendix log

### BL6 — Duplicate check
- **What:** ACT_DuplicateCheck_Run checks for existing order with same company
- **Pass on second submit of same company:** Should be blocked (IsDuplicate=true)
- **Note:** Logic depends on CorporateNumber match — STUB always returns same number, so second registration with same company SHOULD fail

---

## 5. Known limitations in POC

| Limitation | Detail | Workaround / When fixed |
|---|---|---|
| Org selection gallery missing | CE0463 in Mendix 11.10 — mxcli cannot build NPE list widget with association datasource | Studio Pro "Update All Widgets" (P6) |
| STUB search always returns Contoso K.K. | No real CorpSearch API connected | Phase 2 — replace STUB with real REST call |
| Status displayed as raw code ('01', '02') | CommonCategory labels not seeded | Step 7j seed |
| Workflow (7i) Studio Pro only | Native Mendix Workflow must be configured manually | Step 7i — Studio Pro |
| ChoiceOrg selection not persisted | ChoiceOrg_Dto NPE checked boxes are read in save microflow (if wired) | Review in ACT_OrderDetail_SaveDraft — ChoiceOrg records need commit |

---

## 6. Implementation gaps found during planning

| Gap | Detail | Fix needed |
|---|---|---|
| **ACT_OrderDetail_SaveDraft takes 2 params** | Signature: `(Dto, SearchResult)`. The save button on NewEdit can only pass objects in scope. DataView cannot use association (CE6705), so SearchResult is not in scope directly. | Wrapper MF: `ACT_OrderDetail_Save(Dto)` that navigates `$Dto/Assoc` to get SearchResult in the microflow body, then calls SaveDraft |
| **ChoiceOrg records not committed in SaveDraft** | ACT_OrderDetail_SaveDraft creates OrderDetail but does NOT loop ChoiceOrg_Dto list and create committed ChoiceOrg records | To be added in script 7g (NewEdit), or as an addition to ACT_OrderDetail_SaveDraft |

---

## 7. Test execution log

| Date | Tester | Scenario | Result | Notes |
|---|---|---|---|---|
| — | — | — | — | First run pending completion of scripts 7f/7f2/7g |

---

## 8. Script completion tracker (happy path)

| Step | Script | Status | Blocks |
|---|---|---|---|
| 7e | 17–17e (applied) | ✅ | — |
| 7f | 18-page-snp-corpsearch.mdl | ⬜ | H1-4, H1-5 |
| 7f2 | 19-page-confirm-selection.mdl | ⬜ | H1-6 |
| 7g | 20-page-newediit.mdl | ⬜ | H1-7 through H1-10 |
| 7h | 21-page-orderdetail-view.mdl | ⬜ | H1-11 |
| 7i | Studio Pro only | ⬜ | H2 |
| 7j | 22-seed-data.mdl | ⬜ | P3, P4, P5 |
