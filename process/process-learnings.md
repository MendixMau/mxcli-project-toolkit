# Process Learnings — M-0022 POC

**Project:** Apex M-0022 Payer Registration POC (OutSystems → Mendix)
**Author:** Maurits Visser
**Created:** 2026-05-22
**Purpose:** Retrospective on what worked, what didn't, and how to run this more structured in Phase 1 and beyond. Written to share with the team.

---

## Context

This POC used an AI-assisted development approach (Claude Code + mxcli MDL scripting) to migrate the M-0022 Payer Registration flow from OutSystems to Mendix. The POC was built iteratively over ~3 weeks across ~18 sessions.

---

## What Worked Well

- **MDL scripting via mxcli** — generating domain models, microflows, and pages from structured scripts is fast and repeatable. Domain model (Phase 1) went cleanly.
- **Stub architecture** — constant-gated stubs (`STUB_SAP=true`, `STUB_CORPSEARCH=true`) let us build the full flow without live integrations. The pattern is clean and easy to swap out.
- **Enriched design docs (F001–F012)** — having a detailed requirements doc alongside OS screenshots meant design decisions could be grounded in spec, not guesswork.
- **Iterative bug discovery** — mxcli/MDL bugs (BUG-01 through BUG-13) were discovered and documented as project rules, preventing repeated mistakes across sessions.
- **Session memory** — maintaining a running project state doc meant each session could pick up without re-reading all prior scripts.

---

## What Didn't Work Well

### 1. Page coverage tracked at wrong granularity

We tracked pages as binary: `✅ Built` or `⬜ Not started`. A page with sec4 as an empty stub banner counted as "built." We only discovered missing sections weeks later by doing a systematic screenshot comparison.

**What happened:** `PayerDetail_NewEdit` was marked done. Sec4 (AccountGroup, IsBelongApexGroup, TradingPartner, CommissionBurdenCode, ReconciliationAccount) had a stub banner and nothing else. OS image36/37 clearly shows these as real form fields.

**Root cause:** We never did a field-level coverage check between OS screenshots and Mendix widgets before marking a page done.

---

### 2. Design docs used as reference, not as checklist

F001 is 1092 lines. We read relevant sections when building specific functionality, then moved on. We never did a systematic sweep: "F001 field X → is there a widget for it?"

**What happened:** Validation rules (BR-001 through BR-017), mandatory fields, and system-derived read-only fields were documented in F001 but not translated into a build checklist. We re-discovered them later via ad-hoc testing ("save does nothing," "can proceed without filling fields").

---

### 3. OS screenshots underused as ground truth

Screenshots in `Share/converted/v5_pages/` are the clearest picture of what the user actually sees. We referenced them per-section when writing a page script, but never did a full systematic comparison: screenshot left-to-right → Mendix page top-to-bottom.

**What happened:** Filter panel on Overview — container exists, no filter controls inside it. Payment Condition Table — not built at all. Both are clearly visible in the screenshots.

---

### 4. Process gate was incomplete

Our build loop was:
```
Write MDL script → mxcli check (syntax) → mxcli exec → mxcli docker check (CE errors) → ✅ Done
```

A CE-error-free page is not the same as a correct page. No CE errors means the model is consistent — it does not mean the UI matches the spec or that stub data is visible.

---

### 5. Validation and save flow not verified end-to-end early

We built the domain model, microflows, and pages in that order. We never walked the actual happy path (fill form → save → navigate to next page) until late in the POC. When we did, we found the save button does nothing (CompanySearchResult guard fails silently) and navigation has no validation at all.

---

## Recommended Improvements for Phase 1

### A. Add a coverage gate to the page build step

Before marking any page as done, run a coverage check:
1. Open the corresponding OS screenshot
2. List every visible field/section in the screenshot
3. Verify each has a widget with a real datasource binding in Mendix (not just a stub banner)
4. Document any gaps as explicit `⬜` sub-items — not hidden inside "page built"

This turns the tracker from "page built" → "page verified against source of truth."

---

### B. Build and walk the happy path per page, not at the end

After building each page, do a quick end-to-end walk:
1. Log in as a non-admin demo user (not Administrator)
2. Navigate to the page
3. Fill in the minimum required fields
4. Click save / next
5. Confirm a record was created or navigation succeeded

This catches silent failures immediately rather than 3 weeks later.

---

### C. Translate F001 business rules into a build checklist before scripting

Before starting a module, extract from F001:
- Mandatory fields (BR-* rules) → translate to a checklist of widget `Required` settings
- System-derived fields (auto-calculated) → checklist of `Editable: Never` settings
- Conditional visibility rules → checklist of container `Visible` expressions
- Validation rules → checklist of VAL_ microflows to implement

This checklist becomes the definition of "done" for the module, not CE-error-free.

---

### D. Stub data must be visible, not hidden

Any stubbed section should render with placeholder/hardcoded values so the demo looks complete. A stub banner with nothing below it is effectively a missing feature in the demo.

**Rule for Phase 1:** Every section that shows a `[STUB]` banner must also have:
- At least one data field with a hardcoded or DTO-bound value visible below the banner
- OR a clear stub table/list with example rows

A stub banner alone means "this section is missing" — not "this is stubbed."

---

### E. Separate page build sessions by OS screenshot, not by Mendix section

When building a page, work from the screenshot top-to-bottom, not from the domain model outward. Map each visual block in the screenshot to a widget group before writing any MDL. This ensures the page reflects what the user sees, not what the data model suggests.

---

## Proposed Phase 1 Build Loop (Updated)

```
For each module:
  1. Read OS screenshots for this module (top-to-bottom)
  2. Read F001 section for this module
  3. Extract checklist: fields, mandatory rules, validation rules, system-derived fields, conditional visibility
  4. Sketch page data-view nesting → derive microflow signatures
  5. Write + apply microflows
  6. Write + apply pages (following screenshot top-to-bottom)
  7. Run: mxcli docker check → 0 CE errors
  8. Walk the happy path as demo user → verify save + navigation work
  9. Run screenshot coverage check → every visible field has a widget
  10. Mark module done
```

Steps 7–9 are the phase gate that was missing in the POC.

---

## What This Changes for Tooling

- **mxcli** works well for domain model and microflows. Page generation is slower due to MDL bugs (BUG-01 through BUG-13) and Studio Pro handoff steps. Phase 1 should budget more Studio Pro time per page.
- **Coverage checks** should be scripted if possible — an mxcli `SELECT` query against `CATALOG.ENTITIES` + page widget lists to auto-detect unbound widgets.
- **Happy path test** can be Playwright-automated after the first working build. Running it per module catches regressions early.

---

## Open Questions for Team Discussion

1. **Should Phase 1 use the same AI-assisted MDL approach, or switch to more Studio Pro direct?** The MDL approach is fast for domain models and microflows but has friction on pages. Hybrid may be optimal.
2. **How do we handle the 13 known mxcli bugs (BUG-01 through BUG-13)?** Some require Studio Pro workarounds that add unpredictable time. Should these be tracked as a known-issue backlog for mxcli?
3. **Who owns the coverage checklist review?** The AI can generate the checklist from F001, but a developer should sign off on coverage before a module is called done.
4. **Phase 1 scope cut:** With a more structured process, which modules are realistic for Phase 1 given the team size?
