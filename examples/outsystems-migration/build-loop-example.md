# Build Loop Example: OrderRegistration Module
**Skill:** [iterative-build-loop.md](../../skills/iterative-build-loop.md)  
**Context:** OutSystems → Mendix migration, single module walkthrough  

This shows how the 12-step build loop was applied to one real module. Use it as a template for your own module walkthroughs.

---

## Module: OrderRegistration

**What it does:** Order registration flow — org selection, detail entry, confirmation, SAP submission (stubbed)  
**Pages to build:** Overview, OrgChoice, NewEdit, View, Confirm_Selection, popup (CorporationSearch)  
**Microflows:** ~12 (GET_, VAL_, ACT_, STUB_ variants)  
**Source:** 2 OS modules (`MXXXX_OrderRegist`, `OrderRegist_CS`)  

---

## Pre-Module Checklist (run before writing any MDL)

- [x] Read OS screenshots for all 6 pages top-to-bottom
- [x] Read F001 feature doc (order registration section)
- [x] Extract build checklist from feature doc:

| Field | Type | Rule | Widget |
|-------|------|------|--------|
| CompanyName | String | Mandatory, populated from org search | Textbox, Editable: Never |
| CorporateNo | String | Mandatory, populated from org search | Textbox, Editable: Never |
| PostalCode | String | Mandatory, triggers address lookup | Textbox + lookup button |
| Prefecture | String | Auto-filled after postal lookup | Textbox, Editable: Never |
| AccountGroup | String | Optional dropdown from SAP master | Combobox (from start — not textbox) |
| IsBelongApexGroup | Boolean | Conditional visibility rule | Checkbox |
| SalesAreaData | List | Repeating row, add/remove | Gallery with row inputs |
| Status | Enum | System-derived, read-only | DynamicText (not textbox) |
| ... | | | |

- [x] Forward references identified: `Order_Confirm_Selection` page doesn't exist yet when `Order_OrgChoice` is scripted → create stub first
- [x] MPR backup taken before starting

---

## Step-by-step Execution

### Scripts 01–02: Domain model

```
script: 01-orderreg-domain.mdl
  - OrderDetail entity (35 attributes)
  - OrderDetail_Dto (non-persistent, 38 attributes)
  - SalesAreaData_Dto (non-persistent, 3 attributes)
  - Enumerations: OrderRegistrationType, BillingRegistrationType
  
script: 02-orderreg-security.mdl
  - Module roles: OrderRegistration.User, OrderRegistration.Admin
  - GRANT on OrderDetail (create, read *, write *)
  → After this: Studio Pro "Update security" click required (CE0066)
```

**Lesson learned:** `SalesAreaData_Dto` is non-persistent — cannot be retrieved from DB. Must be passed as a parameter or retrieved via a GET_ microflow by association. Discovered this mid-build; added as a domain fact to session notes.

---

### Script 03: Stubs for forward references

```
script: 03-stub-pages.mdl
  - Order_Confirm_Selection (stub: title widget + "under construction" text)
  - OrderDetail_View (stub)
  - SNP_CorporationSearchPopup (stub)
  
Reason: Script 05 (Order_OrgChoice page) references all three.
Pattern: always apply stubs before the script that references them.
```

---

### Scripts 04–06: Microflows

```
script: 04-get-microflows.mdl
  - GET_OrderDetail_InitNew — creates new OrderDetail + Dto
  - GET_SalesAreaData_Dto_List — retrieves SalesAreaData_Dto list by association
  - GET_OrderCustomerBase_ByOrderDetail — reads shared customer base

script: 05-val-microflows.mdl
  - VAL_OrderDetail — validates mandatory fields (returns Boolean)
  - VAL_OrgChoice_BeforeNext — validates org selection before navigation

script: 06-act-microflows.mdl
  - ACT_OrderDetail_Save — save wrapper (calls VAL_ first, then commit)
  - ACT_OrderDetail_Submit — submit to WF_Engine (STUB_AW branch)
  - ACT_SNP_CorpSearch_Execute — executes corporation search (STUB_CorpSearch branch)
  - STUB_PostalCode_Lookup — returns hardcoded address data
```

**Lesson learned:** `VALIDATION FEEDBACK` activities need the `Variable` wired manually in Studio Pro after every mxcli exec (CE0639). Built this into the Studio Pro handoff checklist.

---

### Scripts 07–10: Pages

```
script: 07-overview-page.mdl
  - OrderRegistration_Overview
  - Gallery datasource: DATABASE OrderRegistration.OrderDetail
  - Filter container (empty stub — discovered later this was wrong)
  → mxcli docker check: 0 CE errors ✅

script: 08-orgchoice-page.mdl
  - Order_OrgChoice (org selection, search popup trigger)
  - References Order_Confirm_Selection (stub from script 03)

script: 09-newedit-page.mdl
  - OrderDetail_NewEdit (main form, 6 sections)
  - Section D (AccountGroup etc.) — built with combobox from start, not patched later
  - SalesAreaData gallery (add/remove rows)
  → Happy path test: save works, navigation to View succeeds ✅

script: 10-view-confirm-pages.mdl
  - OrderDetail_View (read-only, replaces stub from script 03)
  - Order_Confirm_Selection (replaces stub from script 03)
```

**What went wrong on script 07 (and caught by coverage check):**  
Overview filter panel — container existed, no filter controls inside. OS screenshot clearly shows 3 filter fields. Caught at step 11 (screenshot coverage check) before marking module done. Fixed in script 11 (patch).

---

### Gate: Steps 8–11

#### Step 8: CE check
```
./mxcli docker check -p Project.mpr
→ 0 errors ✅
```

#### Step 9: Security update (after script 02)
```
Studio Pro → domain model → "Update security" banner → click → Ctrl+S ✅
```

#### Step 10: Happy path walk (as demo user `demo.user`)
```
1. Log in as demo.user (HQDomestic role) ✅
2. Navigate to OrderRegistration_Overview ✅
3. Click "New" → Order_OrgChoice loads ✅
4. Search for corporation → select → navigates to OrderDetail_NewEdit ✅
5. Fill mandatory fields (CompanyName pre-filled, fill PostalCode, SalesArea row) ✅
6. Click Save → record created ✅
7. Navigate to OrderDetail_View ✅

ISSUE FOUND: CompanyName field is editable (should be Editable: Never)
→ Added to bug log, fixed in script 12
```

#### Step 11: Screenshot coverage check

| OS Screenshot element | Mendix widget | Status |
|----------------------|--------------|--------|
| Sec1: Company info block | DataView + 4 textboxes | ✅ |
| Sec2: Address block | DataView + postal lookup | ✅ |
| Sec3: Payment terms table | DataGrid | ✅ |
| Sec4: AccountGroup (dropdown) | Combobox txtAccountGroup | ✅ |
| Sec4: IsBelongApexGroup | Checkbox | ✅ |
| Sec4: TradingPartner | Combobox | ✅ |
| **Overview: Filter panel (3 fields)** | **Container with no controls** | ❌ |
| **Overview: Pagination** | **Missing** | ❌ |

→ Two gaps found. Added as explicit sub-tasks. Fixed in script 11 (filter) and script 13 (pagination).

---

## Module Done ✅

Marked done after:
- 0 CE errors
- Happy path walked and verified
- All coverage gaps documented and triaged (2 moved to next sprint as non-blocking for demo, 1 fixed immediately)

---

## Key Lessons from This Module

1. **`SalesAreaData_Dto` is non-persistent** — never retrieve from DB, always pass by association or parameter. Added as a domain fact to session notes to prevent repeat.
2. **Use the correct widget type from the start** — `AccountGroup` was initially coded as textbox, caught by checklist before scripting. Saved a painful `ALTER PAGE REPLACE` later.
3. **Filter panel was marked "container built" not "widgets inside container"** — binary coverage tracking missed this. Field-level coverage check is the only reliable gate.
4. **CE0639 after every `VALIDATION FEEDBACK`** — always budget 2 min Studio Pro time per VAL_ microflow.
