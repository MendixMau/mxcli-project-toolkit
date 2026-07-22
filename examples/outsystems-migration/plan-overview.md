# Example Plan: OutSystems 11 → Mendix Migration
**Project type:** OutSystems enterprise app → Mendix 10/11  
**Source size:** 112 OS modules  
**Target:** 14 Mendix modules  
**Approach:** AI-assisted mxcli + MDL scripting, iterative build loop per module  

This is a condensed worked example showing how the [migration pipeline](../../skills/migration-pipeline.md) and [iterative build loop](../../skills/iterative-build-loop.md) were applied on a real project. Use it as a template — substitute your own numbers, domains, and decisions.

---

## Step 1: Source Analysis and Scope

**Count before committing:**

| Category | Count |
|----------|-------|
| Total OS modules | 112 |
| Business modules (to migrate) | ~60 |
| Framework/platform modules (skip) | ~50 |
| Design documents available | Yes (requirements spec, field labels, QA sheets) |

**Framework modules skipped (not migrated):**  
OS runtime infrastructure, `OutSystemsUI`, `RichWidgets`, `OSF_*`, `OSLogger`, `IdP`, `SAML` — replaced by Mendix platform equivalents.

---

## Step 2: Module Consolidation (112 OS → 14 Mendix)

OS modules are fine-grained and follow a `_CS` (server) / `_CW` (client) / `_VE` (validation) / `_BL` (business logic) / `_IS` (integration) split. Mendix modules are coarser — consolidate by business domain.

**Consolidation rules applied:**
- `ModuleName_CS` + `ModuleName_CW` + `ModuleName_VE` + `ModuleName_BL` → one Mendix module
- `*_API_SAP` + `*_IS` → `SAP_Integration` (one dedicated integration module)
- All client-side UI frameworks → absorbed by Mendix Atlas theme (zero Mendix modules)

**Resulting module map:**

| Mendix Module | Layer | Source OS modules (collapsed) |
|--------------|-------|-------------------------------|
| `Common_Utils` | Common | AppCommon_BaseUtils, AppCommon_MSG, AppCommon_BatchJob, ... (~25 modules) |
| `Common_Lookups` | Common | RegionMaster_CS/CW, ZipCodeMaster_CS/CW, PaymentTerms_CS/CW, ... |
| `Security_Access` | Common | Users, IdP, IdPCustomizations, MasterManagement_AW_CS, ... |
| `BusinessApp_Common` | Common | ApplicationCommonHeader_CS, BusinessAppCommon_CS/CW/VE, COM_BL/DAO |
| `WF_Engine` | Logic+UI+Integration | COM_WF, COM_WF_DAO, WFManagement_CS/Email/RWCW |
| `Customer_Common` | Domain+Logic | CustomerAppCommon_CS/CW/VE, CustomerAppCommon_API |
| `Customer_Lookups` | Common | CorporationSearch_CW/IS, SAPCustomerMaster_CW/IS, ... |
| `SAP_Integration` | Integration | BusinessAppCommon_IS_SAP, BusinessAppCommon_IS_SAP_WT |
| `Org_Master` | Domain+Logic+UI | EmployeeService_CS/RWCW, DepartmentMaster_CS/CW |
| `MailInquiry` | Domain+Logic | MailInquiryManagement_CS |
| `OrderRegistration` | Domain+Logic+UI | MXXXX_OrderRegist, OrderRegist_CS |
| `ContractorRegistration` | Domain+Logic+UI+Integration | ContractorRegistration_BL/CS/VE, ContractorExpansion_CS |
| `EndCustomerRegistration` | Domain+Logic+UI+Integration | EndCustomerRegistration_BL/CS/VE |
| `ShipmentRegistration` | Domain+Logic+UI+Integration | ShipmentRegistration_BL/CS/VE |

**Layer model:**
```
Common (no business logic, referenced by all)
  └─ BusinessApp_Common, Common_Utils, Common_Lookups, Security_Access, Customer_Lookups
Domain+Logic (business feature modules)
  └─ OrderRn, ContractorRegistration, EndCustomerRegistration, ShipmentRegistration
      Customer_Common, Org_Master, MailInquiry
Workflow platform
  └─ WF_Engine (Logic + UI + Integration in one module — justified by tight coupling)
Integration
  └─ SAP_Integration
```

**Dependency rule:** Feature modules depend on Common — never the reverse. WF_Engine depends on BusinessApp_Common but not on any registration module directly.

---

## Step 3: Naming Conventions

Decided upfront, enforced throughout:

| Concept | Convention | Example |
|---------|-----------|---------|
| Persistent entity | PascalCase singular, no prefix | `Order`, `ShipmentDestination` |
| Non-persistent (DTO) | Suffix `_Dto` | `OrderDetail_Dto`, `SearchCondition_Order` |
| Action microflow | `ACT_` | `ACT_OrderDetail_Save` |
| Validation microflow | `VAL_` | `VAL_Order` |
| Read/retrieve microflow | `GET_` | `GET_OrderByCode` |
| Sub-microflow (internal) | `SUB_` | `SUB_FormatCustomerCode` |
| Integration call | `IVK_` | `IVK_SAP_GetCustomerBasic` |
| Scheduled event | `SE_` | `SE_SyncSAPCustomerMaster` |
| Overview page | `{Entity}_Overview` | `Order_Overview` |
| Edit page | `{Entity}_NewEdit` | `Order_NewEdit` |
| Detail/read-only page | `{Entity}_View` | `Order_View` |
| Popup/search page | `{Entity}_Popup` | `Corporation_Popup` |
| Snippet | `SNP_{Function}` | `SNP_AddressInfoSection` |

---

## Step 4: Cross-Module Interface Contracts

Decided before scripting — avoids mid-build surprises about what module owns what.

**Key contracts:**

| Provider module | Exposed microflow | Consumed by |
|----------------|------------------|-------------|
| `WF_Engine` | `ACT_WFApplication_Submit` | All 4 registration modules |
| `WF_Engine` | `GET_WFStatus_ByApplicationHeader` | All 4 registration modules |
| `SAP_Integration` | `IVK_SAP_GetCustomerBasic` | Customer_Common, registration modules |
| `Customer_Common` | `ACT_OrderCustomerBase_CreateOrUpdate` | OrderRegistration, ContractorRegistration |
| `BusinessApp_Common` | `GET_ApplicationCommonHeader_ById` | All registration modules |
| `Org_Master` | `GET_Employee_ByUserId` | WF_Engine, registration modules |

**Cross-module association direction rule:** Feature module entities hold associations pointing *to* Common entities (not the reverse). WF_Engine references BusinessApp_Common.ApplicationCommonHeader as the bridge — it never directly references individual registration module entities.

---

## Step 5: Architecture Questions to Resolve Before MDL Scripting

These four questions were identified as blockers before any MDL could be written:

| # | Question | Resolution |
|---|----------|-----------|
| 1 | Which module owns `ApplicationCommonHeader`? | `BusinessApp_Common` — it's a shared header used by all 4 registration flows |
| 2 | Cross-module associations: mxcli or Studio Pro? | **mxcli** via `CREATE ASSOCIATION` (BUG-02 fixed in v0.13.0) — decide ownership (which module's script creates each) before scripting |
| 3 | Iteration granularity for MDL scripts? | One script per layer (domain / microflows / pages) per module — gives clean rollback without too many files |
| 4 | Integration strategy: stub or live for POC? | Stub all external integrations (SAP, CorpSearch) via boolean constants — swap at Phase 1 |

Resolving these before scripting avoids mid-build design pivots that require rewriting already-executed scripts.

---

## Step 6: Stub Architecture

All external integrations stubbed via boolean constants:

```
CONST_STUB_SAP   = true  → SAP read/write calls return hardcoded data
CONST_STUB_AW    = true  → Approval workflow always returns "approved"
CONST_STUB_CorpSearch = true → Corporation search returns a hardcoded result
```

**Stub content rule:** Every stubbed section must display at least one data field with a real (hardcoded or DTO-bound) value. A stub banner with nothing below it is invisible in demos.

---

## MDL Script Sequence (abbreviated)

Scripts applied in this order — each is a separate `.mdl` file, numbered, frozen after exec:

```
01 - domain model (entities, enumerations)
02 - security roles + grants
03 - stubs for forward-referenced pages (applied before pages that reference them)
04 - microflows: GET_ retrievals
05 - microflows: VAL_ validations
06 - microflows: ACT_ actions (save, submit)
07 - pages: overview
08 - pages: NewEdit
09 - pages: View
10 - pages: popups + search
11 - seed data (idempotent — retrieve-before-create pattern)
12 - navigation + security matrix
... (patch scripts as needed, always new numbers)
```

After every script: `./mxcli docker check -p Project.mpr` → must be 0 CE errors before next script.

---

## What the POC Proved

- **MDL scripting via mxcli is fast for domain model and microflows.** A 14-module domain model with ~60 entities was scripted and validated in 2 sessions.
- **Pages are slower** due to Studio Pro handoff points and MDL page-widget bugs. Budget 30–50% more time per page than for the equivalent microflow.
- **The 12-step build loop with the 3-step gate (CE check + happy path + screenshot coverage)** is the correct unit of "done." Skipping the gate produces pages that look done but are wrong.
- **Stub architecture + session memory** are the two highest-leverage practices for multi-session AI-assisted development.

See [build-loop-example.md](./build-loop-example.md) for a concrete single-module walkthrough.
