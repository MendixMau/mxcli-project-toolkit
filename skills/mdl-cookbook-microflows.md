# MDL Cookbook — Real Microflow Examples
**Source project:** Apex-TestRunOS-main (M-0022 OutSystems → Mendix migration)
**Date:** 2026-07-01

These are the five largest and most complex microflows from the project, with full MDL
and a plain-language explanation of every decision. Read alongside
`learned-microflow-patterns.md` for the rule behind each pattern.

---

## 1. `GET_PayerDetail_Dto` — DTO builder with chained cross-module XPath retrieves

**What it does:** Fetches the current workflow status for a PayerDetail record by
walking two association hops across two modules, then packages selected fields into a
Non-Persistent DTO for use by validation and page binding.

**Patterns demonstrated:**
- Guard-early-return on empty input
- XPath retrieve using an association path (`where AssocName = $Var limit 1`)
- Nested IF for multi-hop null safety
- Building a non-persistent entity (NPE) as the return value

```sql
create or modify microflow PayerRegistration.GET_PayerDetail_Dto (
  $PayerDetail: PayerRegistration.PayerDetail
)
returns PayerRegistration.PayerDetail_Dto as $Dto
folder 'PayerDetail'
begin
  -- PATTERN: Guard-early-return. Always check input before touching DB.
  if $PayerDetail = empty then
    return empty;
  end if;

  -- PATTERN: XPath retrieve over association.
  -- "where AssocName = $Object limit 1" is the standard 1:1 follow pattern.
  -- Association name is fully qualified: Module.Entity1_Entity2
  retrieve $AppHeader from PayerRegistration.PayerApplicationHeader
    where PayerRegistration.PayerDetail_PayerApplicationHeader = $PayerDetail
    limit 1;

  -- Default value for the field we're trying to read
  declare $Status String = '01';

  -- PATTERN: Nested null-check before second hop.
  -- Never chain a second retrieve inside an IF without checking the first result.
  if $AppHeader != empty then
    -- Second hop: cross-module retrieve (PayerRegistration → BusinessApp_Common)
    retrieve $Header from BusinessApp_Common.ApplicationCommonHeader
      where PayerRegistration.PayerApplicationHeader_ApplicationCommonHeader = $AppHeader
      limit 1;
    if $Header != empty then
      set $Status = $Header/Status;
    end if;
  end if;

  -- PATTERN: Build NPE from persistent sources + computed variables.
  -- NPEs are never committed. Return directly from CREATE.
  $Dto = create PayerRegistration.PayerDetail_Dto (
    Status = $Status,
    CustomerCode = $PayerDetail/CustomerCode,
    CurrencyCode = $PayerDetail/CurrencyCode,
    ContractorLocationCode = $PayerDetail/ContractorLocationCode,
    IsBelongApexGroup = false,
    In_WfMode = ''
  );
  return $Dto;
end;
/
```

**Why two XPath retrieves instead of one OQL join?**
mxcli/Mendix microflows don't have an OQL JOIN statement for single-object retrieval.
You walk the association graph hop by hop, checking for empty at each step.
Each `retrieve ... where AssocName = $Var limit 1` is equivalent to SQL:
`SELECT * FROM target WHERE assoc_fk = $Var.id LIMIT 1`.

---

## 2. `ACT_PayerDetail_Save` — Multi-gate validation with accumulated feedback

**What it does:** The main "Save" button handler for the payer registration form.
Runs three validation gates, accumulates all failures before aborting, then delegates
persistence to a sub-microflow.

**Patterns demonstrated:**
- Accumulate-all-errors pattern (`$IsValid` flag, all gates fire before aborting)
- `validation feedback $Dto/Attr message '...'` (shown in Studio Pro as inline error)
- `trim(expr) = ''` for blank-string check
- `not($IsValid)` (requires parentheses — bare `not $IsValid` is a parse error)
- Retrieve over NPE association — `$Dto/PayerRegistration.PayerDetail_Dto_CompanySearchResult`
- Delegating persistence to a sub-microflow (single responsibility)

```sql
create or modify microflow PayerRegistration.ACT_PayerDetail_Save (
  $Dto: PayerRegistration.PayerDetail_Dto
)
returns PayerRegistration.PayerDetail as $PayerDetail
folder 'PayerDetail'
begin
  -- PATTERN: Retrieve over NPE association (not XPath — association owner is the NPE itself).
  -- CE0018/CE0136 warnings from mxcli are a known limitation; Mendix runtime handles it correctly.
  -- Do NOT try to convert this to an XPath retrieve — NPEs have no DB table to query.
  retrieve $SearchResult from $Dto/PayerRegistration.PayerDetail_Dto_CompanySearchResult;

  -- PATTERN: Accumulate-all-errors.
  -- $IsValid starts true. Every gate sets it false AND fires validation feedback.
  -- We check not($IsValid) only AFTER all gates, so user sees all errors at once.
  declare $IsValid Boolean = true;

  -- GATE 1: SelectedCompanyName — populated by the SNP corporate search step.
  -- trim() guards against whitespace-only strings (common in Japanese input).
  if trim($Dto/SelectedCompanyName) = '' then
    set $IsValid = false;
    validation feedback $Dto/SelectedCompanyName message 'Company name is mandatory';
  end if;

  -- GATE 2a: CurrencyCode — string field, same trim check.
  if trim($Dto/CurrencyCode) = '' then
    set $IsValid = false;
    validation feedback $Dto/CurrencyCode message 'CurrencyCode is mandatory';
  end if;

  -- GATE 2b: Deadline — DateTime, check for empty (not trim).
  if $Dto/Deadline = empty then
    set $IsValid = false;
    validation feedback $Dto/Deadline message 'Deadline is mandatory';
  end if;

  -- PATTERN: not() requires parentheses. `if not($IsValid)` not `if not $IsValid`.
  if not($IsValid) then
    return empty;   -- return empty, not false — this returns an Object type
  end if;

  -- All gates passed. Fetch AreaDto and delegate to SaveDraft.
  $AreaDto = call microflow PayerRegistration.GET_PayerArea_Dto(Dto = $Dto) on error rollback;

  -- PATTERN: Single-responsibility save sub-microflow.
  -- ACT_PayerDetail_Save owns validation; ACT_PayerDetail_SaveDraft owns persistence.
  $PayerDetail = call microflow PayerRegistration.ACT_PayerDetail_SaveDraft(
    Dto = $Dto, SearchResult = $SearchResult, AreaDto = $AreaDto
  ) on error rollback;

  -- Navigate to read-only view after save.
  show page PayerRegistration.PayerDetail_View($PayerDetail = $PayerDetail);
  return $PayerDetail;
end;
/
```

**Known CE behaviour:**
- `validation feedback` activities need to be re-wired in Studio Pro after every `mxcli exec`.
  The activity is created but the Variable binding (which widget to highlight) is empty.
  This is CE0639 — a known mxcli limitation. After exec, open Studio Pro and wire each
  validation feedback activity to its variable manually.

---

## 3. `ACT_PayerDetail_SaveDraft` — Full object graph creation with association wiring and loop

**What it does:** Creates the full persistent object graph for a new draft registration:
ApplicationCommonHeader → PayerApplicationHeader → PayerCustomerBase → PayerDetail →
PayerAreaData → SalesAreaData (0..n rows). Each entity is created, wired by association,
then committed before the next is created.

**Patterns demonstrated:**
- Layered CREATE + CHANGE + COMMIT pattern (mandatory order)
- `change $Entity (AssocName = $Other)` to wire associations after creation
- `commit ... on error rollback` for safe persistence
- `[%CurrentDateTime%]` for system timestamps
- Conditional attribute value in CREATE: `if $Dto != empty then $Dto/Field else ''`
- LOOP over a retrieved association list (NPE → NPE list)
- `retrieve $List from $Dto/AssocName` (association traverse, not XPath)
- BUG-15b annotation pattern for XPath constraints lost after mxcli exec

```sql
create or modify microflow PayerRegistration.ACT_PayerDetail_SaveDraft (
  $Dto: PayerRegistration.PayerDetail_Dto,
  $SearchResult: Customer_Lookups.CompanySearchResult,
  $AreaDto: PayerRegistration.PayerArea_Dto
)
returns PayerRegistration.PayerDetail as $PayerDetail
folder 'PayerDetail'
begin
  -- Step 1: ApplicationCommonHeader — cross-module header tracking function + applicant.
  $Header = call microflow BusinessApp_Common.ACT_ApplicationCommonHeader_Create(
    FunctionId = 'M0022', Applicant = $currentUser/Name
  ) on error rollback;

  -- Step 2: Sequence number for PayerCode. GET_Sequence_NextId returns an Integer.
  $PayerCodeSeq = call microflow Common_Utils.GET_Sequence_NextId(
    FunctionName = 'PayerRegistration', EntityName = 'Payer'
  ) on error rollback;

  -- Step 3: PayerCustomerBase — delegates to Customer_Common module.
  $PayerCustomerBase = call microflow Customer_Common.ACT_PayerCustomerBase_Create(
    Header = $Header, SearchResult = $SearchResult
  ) on error rollback;

  -- Step 4: PayerApplicationHeader.
  -- PATTERN: CREATE sets primitive attributes only. Associations wired separately with CHANGE.
  $AppHeader = create PayerRegistration.PayerApplicationHeader (
    ApplyCategory = $Dto/ApplyCategory,
    RegistrationDue = $Dto/Deadline,
    MessageToApprover = $Dto/MessageToApprover,
    IsActive = true,
    LockVersion = 0,
    CreatedOn = [%CurrentDateTime%],
    CreatedBy = $currentUser/Name
  );
  -- PATTERN: Wire association AFTER create, BEFORE commit.
  change $AppHeader (PayerRegistration.PayerApplicationHeader_ApplicationCommonHeader = $Header);
  commit $AppHeader on error rollback;

  -- Step 5: PayerDetail — central entity.
  -- toString($PayerCodeSeq) — GET_Sequence_NextId returns Integer; PayerCode is String.
  -- 'Not assigned' = "not yet assigned" — initial placeholder, updated later.
  $PayerDetail = create PayerRegistration.PayerDetail (
    PayerCode = toString($PayerCodeSeq),
    CustomerCode = 'Not assigned',
    CurrencyCode = $Dto/CurrencyCode,
    ContractorLocationCode = $Dto/ContractorLocationCode,
    IsActive = true,
    LockVersion = 0,
    CreatedOn = [%CurrentDateTime%],
    CreatedBy = $currentUser/Name
  );
  change $PayerDetail (PayerRegistration.PayerDetail_PayerApplicationHeader = $AppHeader);
  change $PayerDetail (PayerRegistration.PayerDetail_PayerCustomerBase = $PayerCustomerBase);
  commit $PayerDetail on error rollback;

  -- Step 6: PayerAreaData — optional section; all fields default to '' if AreaDto is empty.
  -- PATTERN: Inline conditional in CREATE for optional sub-DTO.
  $PayerAreaData = create PayerRegistration.PayerAreaData (
    PrefixOfAbbreviation = if $AreaDto != empty then $AreaDto/PrefixOfAbbreviation else '',
    LBCOfficeCode        = if $AreaDto != empty then $AreaDto/LBCOfficeCode else '',
    EMail                = if $AreaDto != empty then $AreaDto/EMail else '',
    SearchTermEN         = if $AreaDto != empty then $AreaDto/SearchTermEN else '',
    TaxCategory1         = if $AreaDto != empty then $AreaDto/TaxCategory1 else '',
    TaxId1               = if $AreaDto != empty then $AreaDto/TaxId1 else '',
    TaxCategory2         = if $AreaDto != empty then $AreaDto/TaxCategory2 else '',
    TaxId2               = if $AreaDto != empty then $AreaDto/TaxId2 else '',
    TaxCategory3         = if $AreaDto != empty then $AreaDto/TaxCategory3 else '',
    TaxId3               = if $AreaDto != empty then $AreaDto/TaxId3 else '',
    DUNS_NUMBER          = if $AreaDto != empty then $AreaDto/DUNS_NUMBER else '',
    IndividualTaxId      = if $AreaDto != empty then $AreaDto/IndividualTaxId else '',
    IsActive = true,
    LockVersion = 0,
    CreatedOn = [%CurrentDateTime%],
    CreatedBy = $currentUser/Name
  );
  change $PayerAreaData (PayerRegistration.PayerAreaData_PayerDetail = $PayerDetail);
  commit $PayerAreaData on error rollback;

  -- Step 7: SalesAreaData rows — 0..n rows, each persisted inside the loop.
  -- PATTERN: Retrieve NPE list via association traverse (no XPath — NPE has no table).
  -- BUG-15b: After mxcli exec, this retrieve's XPath constraint may be empty in Studio Pro.
  -- Required constraint: [PayerRegistration.SalesAreaData_Dto_PayerDetail_Dto = $Dto]
  -- Check after exec and restore manually if missing.
  retrieve $SalesAreaDtoList from $Dto/PayerRegistration.SalesAreaData_Dto_PayerDetail_Dto;

  -- PATTERN: LOOP over list — create + wire + commit each row inside the loop body.
  loop $SalesAreaDtoRow in $SalesAreaDtoList
  begin
    $SalesAreaData = create PayerRegistration.SalesAreaData (
      AccountSettingGroup  = $SalesAreaDtoRow/AccountSettingGroup,
      TaxClassCode         = $SalesAreaDtoRow/TaxClassCode,
      CustomerInAccountId  = $SalesAreaDtoRow/CustomerInAccountId,
      IsActive = true,
      LockVersion = 0,
      CreatedOn = [%CurrentDateTime%],
      CreatedBy = $currentUser/Name
    );
    change $SalesAreaData (PayerRegistration.SalesAreaData_PayerDetail = $PayerDetail);
    commit $SalesAreaData on error rollback;
  end loop;

  -- Set status to 01 (Draft editing) via shared header microflow.
  $UpdateOk = call microflow BusinessApp_Common.ACT_ApplicationCommonHeader_UpdateStatus(
    Header = $Header, NewStatus = '01'
  ) on error rollback;

  return $PayerDetail;
end;
/
```

**Association direction rule:**
The association name always reads `Owner_Target`. You must use `change $target (Owner_Target = $owner)`.
Check the domain model for who owns each side. Getting it backwards gives a CE0018.

---

## 4. `ACT_Payer_Submit` — Orchestration flow with guard chain and $currentUser

**What it does:** The submit button handler. Runs five sequential guards (each returns early
on failure), then calls three sub-microflows in sequence: DTO build → validation →
duplicate check → WF stub submission → status update. Uses `$currentUser/Name` for the
applicant field.

**Patterns demonstrated:**
- Guard chain pattern (early-return at each step, no deep nesting)
- `$currentUser/Name` — built-in variable for the logged-in user's name
- XPath retrieve chained across two modules (same as GET_PayerDetail_Dto)
- `$Obj/Attr` path navigation after retrieve
- log with string concatenation: `'{1}' with ({1} = 'prefix' + $Var)`
- STUB_ microflow call (external system integration placeholder)
- `show page Module.Page` at end (navigate after action)

```sql
create or modify microflow PayerRegistration.ACT_Payer_Submit (
  $PayerDetail: PayerRegistration.PayerDetail
)
returns Boolean as $Success
folder 'OrgChoice'
begin
  declare $Success Boolean = false;

  -- GUARD 1: Input check.
  if $PayerDetail = empty then
    log warning node 'PayerRegistration' 'ACT_Payer_Submit: PayerDetail is empty';
    return false;
  end if;

  -- GUARD 2: Build DTO (contains current status). Fail if DTO build fails.
  $Dto = call microflow PayerRegistration.GET_PayerDetail_Dto(
    PayerDetail = $PayerDetail
  ) on error rollback;

  -- GUARD 3: Run field validation. VAL_ returns Boolean.
  $IsValid = call microflow PayerRegistration.VAL_PayerDetail_BeforeSubmit(
    Dto = $Dto
  ) on error rollback;
  if $IsValid = false then
    log warning node 'PayerRegistration' 'ACT_Payer_Submit: validation failed';
    return false;
  end if;

  -- GUARD 4: Duplicate check. ACT_DuplicateCheck_Run returns a result object.
  -- Navigate result object: $DupResult/IsDuplicate, $DupResult/ExistingCustomerCode
  $DupResult = call microflow PayerRegistration.ACT_DuplicateCheck_Run(
    PayerDetail = $PayerDetail
  ) on error rollback;
  if $DupResult/IsDuplicate = true then
    -- PATTERN: Log with string concatenation via {1} placeholder.
    log warning node 'PayerRegistration'
      '{1}' with ({1} = 'ACT_Payer_Submit: duplicate found. ExistingCode=' + $DupResult/ExistingCustomerCode);
    return false;
  end if;

  -- GUARD 5a: Walk association chain to find ApplicationCommonHeader.
  -- Hop 1: PayerDetail → PayerApplicationHeader
  retrieve $AppHeader from PayerRegistration.PayerApplicationHeader
    where PayerRegistration.PayerDetail_PayerApplicationHeader = $PayerDetail
    limit 1;
  if $AppHeader = empty then
    log warning node 'PayerRegistration' 'ACT_Payer_Submit: PayerApplicationHeader not found for PayerDetail';
    return false;
  end if;

  -- Hop 2: PayerApplicationHeader → ApplicationCommonHeader (cross-module)
  retrieve $Header from BusinessApp_Common.ApplicationCommonHeader
    where PayerRegistration.PayerApplicationHeader_ApplicationCommonHeader = $AppHeader
    limit 1;
  if $Header = empty then
    log warning node 'PayerRegistration' 'ACT_Payer_Submit: ApplicationCommonHeader not found';
    return false;
  end if;

  -- All guards passed. Build workflow request object.
  -- PATTERN: $currentUser/Name — built-in, always resolves to logged-in user's display name.
  -- PATTERN: NPE created inline, passed as parameter — never committed.
  $WFRequest = create WF_Engine.WFSubmitRequest (
    RegistrationNo = $PayerDetail/PayerCode,
    ApplicationModule = 'PayerRegistration',
    ApplicantEMP_ID = '',
    ApplicantName = $currentUser/Name,
    RouteCode = 'J001'
  );

  -- STUB_ call: real WF engine not yet integrated. Same signature as real call.
  $WFResult = call microflow WF_Engine.STUB_ACT_WFApplication_Submit(
    Request = $WFRequest
  ) on error rollback;

  if $WFResult/IsSuccess = false then
    log warning node 'PayerRegistration'
      '{1}' with ({1} = 'ACT_Payer_Submit: WF submission failed. ' + $WFResult/ErrorMessage);
    return false;
  end if;

  -- Update status to 02 (Submitted) via shared header microflow.
  $Updated = call microflow BusinessApp_Common.ACT_ApplicationCommonHeader_UpdateStatus(
    Header = $Header, NewStatus = '02'
  ) on error rollback;

  set $Success = true;
  -- Navigate to overview after submit.
  show page PayerRegistration.PayerRegistration_Overview;
  return $Success;
end;
/
```

**Guard chain vs nested IF:**
Each guard does a single `return false` at the top. This keeps the "happy path" at
the left margin and avoids 5-level nesting. The pattern: check → log → return false;
proceed only if all checks passed.

---

## 5. `ACT_Payer_ExpansionApply_Save` — Cross-module XPath retrieve with BUG-15b workaround annotation

**What it does:** Creates a new PayerDetail for an *existing* customer (expansion
registration, as opposed to new registration). Reuses the existing PayerCustomerBase
instead of creating a new one. The key challenge: finding the PayerCustomerBase by
CustomerCode using a deep cross-module XPath, which BUG-15b may erase after mxcli exec.

**Patterns demonstrated:**
- XPath retrieve with deep reverse-association path (3-level)
- BUG-15b annotation: document the XPath in a `@annotation` so Studio Pro can restore it
- Verify-step pattern after a potentially-broken retrieve
- `create ... ( Attr = if $Dto != empty then $Dto/Field else '' )` again (same as SaveDraft)
- Two separate `change` calls for two associations on the same entity
- Status '02' → using ApplyCategory from Dto (expansion vs new registration)

```sql
create or modify microflow PayerRegistration.ACT_Payer_ExpansionApply_Save (
  $Dto: PayerRegistration.PayerDetail_Dto,
  $AreaDto: PayerRegistration.PayerArea_Dto
)
returns PayerRegistration.PayerDetail as $NewPayerDetail
folder 'OrgChoice'
begin
  -- GUARD: CustomerCode must be set. Expansions require an existing customer.
  if $Dto/CustomerCode = '' then
    log error node 'PayerRegistration'
      '{1}' with ({1} = 'ACT_Payer_ExpansionApply_Save: CustomerCode is empty -- cannot save expansion.');
    return empty;
  end if;

  -- Store in local var for use in XPath below.
  -- PATTERN: Always extract attribute to $Var before using in XPath.
  -- Directly using $Dto/CustomerCode in the XPath filter can cause mxcli parse issues.
  declare $CCode String = $Dto/CustomerCode;

  -- Create ApplicationCommonHeader and get sequence number (same as new registration).
  $Header = call microflow BusinessApp_Common.ACT_ApplicationCommonHeader_Create(
    FunctionId = 'M0022', Applicant = $currentUser/Name
  ) on error rollback;
  $PayerCodeSeq = call microflow Common_Utils.GET_Sequence_NextId(
    FunctionName = 'PayerRegistration', EntityName = 'Payer'
  ) on error rollback;

  -- PATTERN: Deep reverse XPath retrieve.
  -- Goal: find PayerCustomerBase for the EXISTING customer with this CustomerCode.
  -- Path: Customer_Common.PayerCustomerBase ← PayerDetail (via PayerDetail_PayerCustomerBase)
  --       ← filtered by PayerDetail.CustomerCode = $CCode
  -- This is a REVERSE traverse: start from PayerCustomerBase, filter via PayerDetail's attribute.
  --
  -- BUG-15b WARNING: After `mxcli exec`, the XPath constraint text is stored empty in Studio Pro.
  -- Required constraint: [PayerRegistration.PayerDetail_PayerCustomerBase/PayerRegistration.PayerDetail/CustomerCode = $CCode]
  -- After exec: open Studio Pro → find this retrieve → paste the constraint above → save.
  retrieve $ExistingBase from Customer_Common.PayerCustomerBase
    where PayerRegistration.PayerDetail_PayerCustomerBase/PayerRegistration.PayerDetail/CustomerCode = $CCode
    limit 1;

  if $ExistingBase = empty then
    log error node 'PayerRegistration'
      '{1}' with ({1} = 'ACT_Payer_ExpansionApply_Save: no PayerCustomerBase found for CustomerCode=' + $CCode
             + '. If Constraint is empty in Studio Pro, set it to: [PayerRegistration.PayerDetail_PayerCustomerBase/PayerRegistration.PayerDetail/CustomerCode = $CCode]');
    return empty;
  end if;

  -- Verify step: check that the retrieve wasn't silently unfiltered (BUG-15b worst case).
  -- If XPath was empty, the retrieve returns any PayerCustomerBase — which may be wrong.
  retrieve $VerifyLink from PayerRegistration.PayerDetail
    limit 1;
  if $VerifyLink = empty then
    log warning node 'PayerRegistration'
      '{1}' with ({1} = 'ACT_Payer_ExpansionApply_Save: no PayerDetail found for CustomerCode=' + $CCode
             + '. Cannot verify $ExistingBase is correct.');
  end if;

  -- Create PayerApplicationHeader for this expansion.
  -- ApplyCategory comes from Dto (e.g. '02' = expansion vs '01' = new registration).
  $AppHeader = create PayerRegistration.PayerApplicationHeader (
    ApplyCategory = $Dto/ApplyCategory,
    RegistrationDue = $Dto/Deadline,
    MessageToApprover = $Dto/MessageToApprover,
    IsActive = true,
    LockVersion = 0,
    CreatedOn = [%CurrentDateTime%],
    CreatedBy = $currentUser/Name
  );
  change $AppHeader (PayerRegistration.PayerApplicationHeader_ApplicationCommonHeader = $Header);
  commit $AppHeader on error rollback;

  -- Create new PayerDetail — reuses existing $ExistingBase, does NOT create a new one.
  -- CurrencyCode: fallback to 'JPY' if empty (expansion may not change currency).
  $NewPayerDetail = create PayerRegistration.PayerDetail (
    PayerCode = toString($PayerCodeSeq),
    CustomerCode = $CCode,
    CurrencyCode = if $Dto/CurrencyCode != '' then $Dto/CurrencyCode else 'JPY',
    ContractorLocationCode = $Dto/ContractorLocationCode,
    IsActive = true,
    LockVersion = 0,
    CreatedOn = [%CurrentDateTime%],
    CreatedBy = $currentUser/Name
  );
  -- Wire TWO associations on the same entity — two separate CHANGE statements.
  change $NewPayerDetail (PayerRegistration.PayerDetail_PayerApplicationHeader = $AppHeader);
  change $NewPayerDetail (PayerRegistration.PayerDetail_PayerCustomerBase = $ExistingBase);
  commit $NewPayerDetail on error rollback;

  -- Create PayerAreaData from AreaDto (same conditional pattern as SaveDraft).
  $PayerAreaData = create PayerRegistration.PayerAreaData (
    PrefixOfAbbreviation = if $AreaDto != empty then $AreaDto/PrefixOfAbbreviation else '',
    LBCOfficeCode        = if $AreaDto != empty then $AreaDto/LBCOfficeCode else '',
    EMail                = if $AreaDto != empty then $AreaDto/EMail else '',
    SearchTermEN         = if $AreaDto != empty then $AreaDto/SearchTermEN else '',
    TaxCategory1         = if $AreaDto != empty then $AreaDto/TaxCategory1 else '',
    TaxId1               = if $AreaDto != empty then $AreaDto/TaxId1 else '',
    TaxCategory2         = if $AreaDto != empty then $AreaDto/TaxCategory2 else '',
    TaxId2               = if $AreaDto != empty then $AreaDto/TaxId2 else '',
    TaxCategory3         = if $AreaDto != empty then $AreaDto/TaxCategory3 else '',
    TaxId3               = if $AreaDto != empty then $AreaDto/TaxId3 else '',
    DUNS_NUMBER          = if $AreaDto != empty then $AreaDto/DUNS_NUMBER else '',
    IndividualTaxId      = if $AreaDto != empty then $AreaDto/IndividualTaxId else '',
    IsActive = true,
    LockVersion = 0,
    CreatedOn = [%CurrentDateTime%],
    CreatedBy = $currentUser/Name
  );
  change $PayerAreaData (PayerRegistration.PayerAreaData_PayerDetail = $NewPayerDetail);
  commit $PayerAreaData on error rollback;

  -- Set status to 01 (Draft) on the new header.
  $UpdateOk = call microflow BusinessApp_Common.ACT_ApplicationCommonHeader_UpdateStatus(
    Header = $Header, NewStatus = '01'
  ) on error rollback;

  show page PayerRegistration.PayerDetail_View($PayerDetail = $NewPayerDetail);
  return $NewPayerDetail;
end;
/
```

---

## Pattern Summary — Quick Reference

| Pattern | Syntax | Notes |
|---------|--------|-------|
| XPath retrieve (1:1 follow) | `retrieve $X from Module.Entity where Module.Assoc = $Obj limit 1` | Always `limit 1` for 1:1 |
| XPath retrieve (deep reverse) | `retrieve $X from Module.Target where Owner.Assoc/Owner.Entity/Attr = $Var limit 1` | BUG-15b: check XPath after exec |
| NPE association traverse | `retrieve $List from $Dto/Module.Assoc` | No XPath; NPE has no DB table |
| Check empty | `if $X = empty then` | For entities and DateTime |
| Check blank string | `if trim($X/Attr) = ''` | For String attributes |
| not() | `if not($IsValid)` | Parentheses required |
| Accumulate errors | `declare $IsValid Boolean = true; ... set $IsValid = false; ... if not($IsValid)` | All gates fire before abort |
| Wire association | `change $Entity (Module.Assoc = $Other); commit $Entity` | CHANGE then COMMIT, never in CREATE |
| $currentUser | `$currentUser/Name`, `$currentUser/Email` | Built-in, no retrieve needed |
| Log with concat | `log warning node 'N' '{1}' with ({1} = 'prefix' + $Var)` | Use {1} placeholder, not + in main string |
| Inline conditional | `Attr = if $Dto != empty then $Dto/Attr else ''` | In CREATE parameter list |
| Loop with persist | `loop $Row in $List begin ... create ... change ... commit ... end loop` | commit inside loop body |
| STUB_ call | `$Result = call microflow Module.STUB_OpName(Param = $val) on error rollback` | Identical signature to real op |
| Navigate after action | `show page Module.Page($Param = $var)` | After last commit, before return |
| Safe sub-call | `... on error rollback` | On every CALL MICROFLOW that modifies data |
