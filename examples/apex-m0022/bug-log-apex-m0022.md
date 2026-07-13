# Bug Log — Apex Payer Registration POC

Bugs discovered during Playwright E2E testing and DOM inspection.
Each entry has: symptom, reproduction steps, evidence, suspected root cause, and suggested fix.

---

## BUG-E2E-01 — SelectedCompanyName not populated after org selection

**Severity:** High — validation fires on a field the user cannot fill  
**Status:** Open  
**Discovered:** 2026-05-25 via Playwright e2e-01-empty-submit

### Symptom
After the full OrgChoice → Next → Confirmation → Create flow, the `txtCompanyName` field on `PayerDetail_NewEdit` is **empty** (`value=""`). When the user clicks Save without touching that field, the validation gate fires: *"Company name is mandatory"*.

The user has no way to know they need to fill this — they just selected a company in the previous screen. It feels broken.

### Evidence
DOM inspection after navigating to NewEdit via org selection:
```
txtCompanyName: { inputValue: "", readOnly: false, disabled: false }
txtApplicantDept: { inputValue: "ISP" }   ← init microflow DID set this
```
Playwright test output:
```
"Company name is mandatory" fires on empty save — 3 errors instead of expected 2
```

### Suspected root cause
The init microflow for `PayerDetail_NewEdit` (or `ACT_PayerDetail_SaveDraft`) does not copy `CompanySearchResult.Name` (or equivalent) into `PayerDetail_Dto.SelectedCompanyName` when creating the Dto from the OrgChoice selection.

### Suggested fix (do not implement without approval)
In the microflow that initialises `PayerDetail_Dto` from the selected org/search result, add:
```
CHANGE $Dto (SelectedCompanyName = $SearchResult/Name);
```
Check which microflow creates the Dto — likely `ACT_PayerDetail_InitNew` or the `btnCreate` action on the Confirmation page.

---

## BUG-E2E-02 — txtCompanyName and txtCorporateNo are editable — should be read-only

**Severity:** Medium — UX/data integrity concern  
**Status:** Open  
**Discovered:** 2026-05-25 via Playwright DOM inspection

### Symptom
`txtCompanyName` and `txtCorporateNo` on `PayerDetail_NewEdit` are fully editable inputs (`readOnly: false`, `disabled: false`). These values came from the org selection / SNP corporate search and should not be manually overrideable by the user.

A user could type any company name and bypass the corporate lookup, creating invalid records.

### Evidence
```
txtCompanyName: { hasInput: true, readOnly: false, disabled: false }
txtCorporateNo: { hasInput: true, readOnly: false, disabled: false }
```

### Suggested fix (do not implement without approval)
In Studio Pro, set `Editable: Never` on `txtCompanyName` and `txtCorporateNo` on `PayerDetail_NewEdit`. These widgets should display the SNP-sourced values read-only.

---

## BUG-E2E-03 — "Page not available" modal fires on fast navigation after login

**Severity:** Low — transient UX issue, does not block flow  
**Status:** Open  
**Discovered:** 2026-05-25 — user observed during Playwright visible-browser runs

### Symptom
After login and redirect, navigating immediately to `PayerDetail_Overview` sometimes triggers a Mendix "This page is not available" or "Page could not be loaded" dialog. The app then recovers and reloads correctly.

Happens because the Mendix client navigates before the session is fully initialised server-side.

### Evidence
User report: *"there is a recurring error after sign in, saying this page was not available, and it restarts again. but then the flow runs"*

### Suggested fix (do not implement without approval)
In the Playwright test helpers, add a longer post-login wait and an extra modal dismiss before navigating:
```js
await page.waitForTimeout(3500);   // allow Mendix session to settle
await dismissModal(page);           // catch any "page not available" dialog
```
This is a test-side fix only — the app behaviour is standard Mendix and not a product bug.

---

## BUG-E2E-04 — Playwright fillCurrency crashes on txtCurrency container div

**Severity:** Low — test infrastructure bug only, not an app bug  
**Status:** Open (test fix pending)  
**Discovered:** 2026-05-25 via e2e-02 and e2e-03 errors

### Symptom
Playwright throws `Element is not an <input>` when `fillCurrency()` tries to fill `txtCurrency`. The helper's comma-selector fallback matched the container `<div>` before the child `<input>`.

### Evidence
```
Error: elementHandle.fill: Element is not an <input>, <textarea>, <select> or [contenteditable]
Selector used: .mx-name-txtCurrency input, .mx-name-txtCurrency
DOM confirmed: .mx-name-txtCurrency DOES contain a child <input type="text">
```

### Suggested fix (test infra only — safe to apply)
Change selector in `helpers.js` `fillCurrency()` from:
```js
await page.$('.mx-name-txtCurrency input, .mx-name-txtCurrency')
```
to:
```js
await page.$('.mx-name-txtCurrency input')
```

---

## BUG-E2E-05 — No values visible in the second column of NewEdit layout

**Severity:** Medium — visual/data gap  
**Status:** Open — needs investigation  
**Discovered:** 2026-05-25 — user observation during visible-browser run

### Symptom
User reports seeing no values in the second column of the NewEdit page form. Multiple fields appear empty that should either have defaults or carry-over values from the org selection step.

### Evidence
User observation: *"I see no values for the 2nd column"*  
Corroborated by DOM inspection: `txtCompanyName` empty, `txtCorporateNo` likely empty.  
Linked to BUG-E2E-01 (SelectedCompanyName not populated).

### Suspected root cause
Same root cause as BUG-E2E-01 — the init microflow is not copying org-selection data into the Dto attributes that feed the second column widgets.

### Next step to investigate
Run `DESCRIBE MICROFLOW` on whatever microflow is called by `btnCreate` on `Payer_Confirm_Selection`, and trace whether it sets: `SelectedCompanyName`, `CorporateNo`, `FormalName`, and other pre-populated fields.

---

---

## BUG-POC-01 — CountryCode unique constraint removed as POC workaround

**Severity:** Low (POC only) — data integrity concern in production  
**Status:** Resolved (workaround applied 2026-05-26)  
**Discovered:** 2026-05-26 — app startup crash after partial seed run

### Symptom
After-startup action crashed with:
```
An exception occurred while running the after-startup-action.
Object id: ..., validation errors: (member: CountryCode, message: CountryCode must be unique)
```

### Root cause
`ACT_SeedData_Run` guard checks `CommonCategory limit 1`. A previous startup created `Country` records (JP/US/DE) but crashed before reaching `CommonCategory`. On next restart, guard finds no `CommonCategory` → tries to re-seed → hits UNIQUE constraint on `CountryCode`.

### Fix applied
Removed the UNIQUE constraint on `Common_Lookups.Country.CountryCode` in Studio Pro domain model (2026-05-26).

### Production note
Before go-live, either: (a) restore the UNIQUE constraint and fix `ACT_SeedData_Run` to guard on `Country` instead of `CommonCategory`, or (b) add per-entity guards (retrieve existing → skip if found) throughout the seed microflow.

---

## Summary table

| ID | Severity | Area | Status | One-liner |
|----|----------|------|--------|-----------|
| BUG-E2E-01 | High | Microflow | Open | SelectedCompanyName empty after org selection → validation fires on hidden field |
| BUG-E2E-02 | Medium | Page/UX | Open | CompanyName + CorporateNo should be read-only on NewEdit |
| BUG-E2E-03 | Low | Test infra | Open | "Page not available" modal on fast post-login navigation |
| BUG-E2E-04 | Low | Test infra | Open | fillCurrency helper crashes — wrong selector |
| BUG-E2E-05 | Medium | Page/Data | Open | Second column fields empty — no carry-over from org selection |
| BUG-POC-01 | Low | Domain/Seed | Resolved | CountryCode UNIQUE constraint removed as POC workaround — restore before go-live |
