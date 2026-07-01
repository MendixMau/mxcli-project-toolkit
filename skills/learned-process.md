# Process Rules — Build Discipline for This Project

---

## Widget References — Always Include Full Location Context

**Rule:** When referring to a widget in any handoff, instruction, or pending-action list, always identify it by: **Page name → Section name (container ID / Japanese label) → sub-context if inside a DataView or gallery → widget name (attribute name)**.

Never use bare widget names like "txtAccountGroup" alone — the user cannot locate a widget in Studio Pro without knowing which page and section it lives in.

**Format:**
> Page `Module.PageName`, Section **Name** (`containerID` / Japanese label)[, inside DataView `dvName`, sub-section **Japanese label**]: widget `widgetName` (`AttributeName`) → property = value

**Example (correct):**
> Page `PayerDetail_NewEdit`, Section D (`ctnSec4` / General data): textbox `txtAccountGroup` (AccountGroup) → Editable = Never

**Example (wrong — do not use):**
> Set `txtAccountGroup` to Editable = Never

This applies to: pending Studio Pro steps, CE error descriptions, any instruction asking the user to find and click a widget.

---

## Design Sources — Where to Look Before Implementing

**Rule:** Consult design sources before any domain model change, CE error fix, or logic implementation. Never improvise from memory.

| Priority | Path | Use when |
|----------|------|----------|
| 1 | `docs/domain-design-enriched/F001–F012.md` | Any entity, attribute, association, or microflow question |
| 2 | `docs/poc-plan.md` | Scope boundary, stub vs. real, integration decisions |
| 3 | `extraction/knowledge-base/brd/F001–F012.brd.json` | OS original behavior, field names, flow logic |
| 4 | `extraction/knowledge-base/share/KB_*.md` | Requirements detail, field labels, CorpSearch/SAP API specs |
| 5 | `docs/interface-registry.md` | Cross-module calls, parameter contracts |
| 6 | `docs/mxcli-bugs.md` | Unexpected mxcli behavior — check here before assuming a script bug |

**F-doc index:** F001=Payer Reg UI, F002=Approval Workflow, F003=Master Data, F004=Corporate Search, F005=SAP Integration, F006=Common Components, F010=WF Backend, F011=Customer Common, F012=Payer Backend. F007–F009 are out of POC scope.

**Do NOT use:** `docs/domain-design/` (superseded), `docs/domain-design-patched/` (superseded), `docs/superpowers/` (pipeline planning), `extraction/extractors/`, `extraction/generators/`.

---

## CE Error Triage — Mandatory 5-Step Approach

**Rule:** Never propose or execute a fix for a CE error without first tracing its root cause through the executed scripts AND the design documents.

1. **Collect:** run `./mxcli docker check -p Contoso-TestRunOS.mpr` to get full CE error list.
2. **Trace to script:** review latest scripts in `mdlsource/layer2/` (highest number = most recent). For each error: which script created/modified the flagged element? Is it a **script bug** (wrong wiring) or a **design gap** (element never built)?
3. **Consult design docs** (only for design gaps, in the priority order above).
4. **Propose with justification:** state root cause, proposed fix, and the F-doc section or poc-plan decision that justifies it. Wait for user approval.
5. **Execute:** only after explicit approval. Back up MPR first if the fix touches pages or cross-module associations.

**Never:** add attributes/entities to silence errors without requirement justification. Never fix the model to match a broken page binding — the page may be wrong.

---

## MPR Backup — Mandatory Before Any Build Sequence

The MPR is a SQLite database (~290 KB) — copying it is instant.

```bash
# Before starting
cp Contoso-TestRunOS.mpr Contoso-TestRunOS.mpr.backup

# After verifying success
rm Contoso-TestRunOS.mpr.backup

# If Studio Pro crashes or MPR is corrupt
cp Contoso-TestRunOS.mpr.backup Contoso-TestRunOS.mpr
```

**Mandatory (not optional) when:**
- Any contentparams write (BUG-04 null GUID risk)
- Any script touching cross-module associations or entity-qualified paths
- Any sequence of 3+ mxcli exec calls in one session
- Before scripting new pages with complex widget trees

**Corruption detection:**
- `mxcli check --references` → syntax/reference errors (before exec)
- `mxcli docker check` → CE errors (after exec)
- Neither catches BSON-level null GUIDs (BUG-04) — only Studio Pro opening reveals these

**Do NOT use** `git checkout HEAD -- Contoso-TestRunOS.mpr` as recovery — it discards all good MPR changes since the last commit. Use the `.backup` file.

---

## Page Build Discipline — Field Fidelity Rules

Learned after Phase 3 produced pages with wrong widget types, empty sections, and inaccessible fields.

**Rule: Read the F-doc field-by-field before building any page — not just the prototype.**

The prototype HTML is a simplified mockup. It omits fields, flattens sections, and makes everything look like a text input. The authoritative source is:
1. `extraction/knowledge-base/share/KB_M0022_FieldLabels_EN.md` — field labels + types
2. `extraction/knowledge-base/share/KB_M0022_RequirementsSpec_V5.md` — field rules + mandatory/optional
3. `Share/WorkFlow//07_Form.md` — section structure
4. `docs/domain-design-enriched/F001–F012.md` — entity bindings

**Rule: Cross-check DTOs against pages before calling a phase done.**

When domain model and pages are built in separate sessions, verify that every DTO created in the domain phase is actually bound to a DataView on some page. A DTO with 34 attrs that no page renders is invisible.

**Rule: After any page build, test with a non-admin user before moving to the next task.**

Write access on NPE DTOs is not inherited from persistent entity rules. Failing to grant `write *` to User roles produces greyed-out forms. Test with `yoko.taoka` (HQDomestic) immediately after page creation.

**Rule: Stub banners must name the script that will replace them.**

Replace the generic `[STUB] SAP handles this` pattern with `[STUB: Script 44 will replace this section]`. This makes placeholders trackable and prevents them from being forgotten as sessions progress.

**Rule: Use the correct widget type from the start — don't plan to change textbox → combobox later.**

`ALTER PAGE` widget type changes are painful (BUG-08: replacement must use a different name). Build with combobox/radiobuttons/datepicker from the start. If the field has a master data source or enumeration, it gets the correct widget in the original page script, not in a patch.

---

## MDL Script Versioning — New Scripts, Not Edits to Old Ones

**Rule:** Once an MDL script has been executed against the MPR, it is frozen. Write a new numbered script for any fix or change.

- Old scripts = historical record of what was built and when
- Re-running old scripts causes conflicts (demo users already exist, entities already created)
- `create or replace` / `create or modify` in a new script rewrites the MPR element cleanly
- The MPR is the source of truth, not the scripts
- Exception: a script that has NOT yet been executed can be edited in place
