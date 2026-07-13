# Skill: scope-delta — Compare Code Extraction vs Business Requirements
**Applies to:** migration.

## Purpose

Produce a structured delta document that shows what business requirements add, correct, or contradict compared to the code-extraction design docs. The output tells the architecture/domain-design colleague exactly what needs to change in the domain-design docs before MDL generation can begin.

**This skill does NOT produce a generic "what's different" report.** Every finding must answer: *does this block, risk, or enhance the Mendix build?*

---

## Code Generation Pipeline (context)

```
OS XML
  → BRD JSON (raw extraction — what OS had)
  → domain-design F001–F012 (colleague's Mendix interpretation — what to build)
  → MDL generation → Mendix app
```

Domain-design docs are the **primary target for code gen**. BRD JSON is the fallback when domain design under-specifies. The delta doc's job is to identify what must change in domain-design (and BRD where relevant) before MDL generation is safe.

---

## Input Sides

| Side | Sources | Represents |
|------|---------|------------|
| **A — Code extraction** | `docs/arch-overview.md`, `docs/interface-registry.md`, `docs/domain-design/F00X-*.md`, `extraction/knowledge-base/brd/F00X-*.json` | What the colleague extracted and interpreted from the OS source |
| **B — Business requirements** | `extraction/knowledge-base/share/KB_M0022_RequirementsSpec_V5.md`, `KB_M0022_QA.md`, `KB_M0022_FieldLabels_EN.md`, `KB_M0022_CS_FieldLabels_EN.md`, `KB_C0031_CorporateSearch.md`, `KB_CorpSearch_API.md`, `KB_DevStandards.md`, `KB_CommonComponents.md`, `KB_M0022_PayerCreation_UserManual_EN.md` | What the business documents say the system should do |

---

## Finding Categories

| Category | Definition | Example |
|----------|-----------|---------|
| **Correction** | B says something that contradicts A — one must change | Design doc says field is optional; requirements spec marks it mandatory |
| **Gap-in-A** | B provides detail that A does not mention at all | Requirements spec defines a 3-query duplicate check; BRD has no duplicate check entry |
| **Gap-in-B** | A mentions something B does not address | Design doc defines an entity; requirements never describe its business purpose |
| **Ambiguity** | Both mention it but with inconsistent or incomplete detail | Both reference J001 approval route but with different step counts |
| **Mx-Reframing** | OS concept that needs explicit Mendix translation note | BPT async pattern → Mendix Task Queue; no contradiction, just a platform gap |

---

## Severity for Code Generation

| Severity | Meaning | What happens without resolution |
|----------|---------|----------------------------------|
| **Blocking** | MDL will be wrong or incomplete | Wrong entity shape, missing microflow, incorrect validation rule |
| **Risk** | MDL generates but business logic will be incorrect at runtime | Missing validation, wrong field constraint, incomplete approval route |
| **Enhancement** | Design is correct but implementation needs more detail | Field label, exact dropdown value list, screen layout |

---

## Comparison Dimensions

Analyse findings across these 6 dimensions:

1. **Entities & Attributes** — field names, types, lengths, mandatory constraints, enumerations, default values
2. **Business Rules & Validation** — formulas, conditions, thresholds, uniqueness rules, cross-field dependencies
3. **Microflow Logic** — process steps, branching conditions, error paths, orchestration sequences
4. **Integration Points** — external APIs, SAP fields, file formats, credentials, endpoint contracts
5. **UI & Permissions** — screen layout, field visibility per role, edit permissions per workflow state
6. **Cross-cutting** — audit fields, security roles, NFR, data migration, infrastructure

---

## Output Format

### Module-Level Delta (per F00X)

```markdown
## Delta: [Module Name] (F0XX)

**Side A sources read:** domain-design/F0XX-*.md, brd/F0XX-*.json
**Side B sources read:** KB_M0022_RequirementsSpec_V5.md (sheets X–Y), KB_M0022_QA.md, ...

### Findings

| # | Dimension | Finding | Category | Severity | Action |
|---|-----------|---------|----------|----------|--------|
| 1 | Entities | ... | Gap-in-A | Blocking | Update F0XX domain-design: add field X to entity Y |
| 2 | Validation | ... | Correction | Risk | Correct F0XX: rule Z is mandatory per requirements, optional per BRD |
```

### Top-Level Delta (analysis docs)

Same table format, but Side A = `analysis-design-architecture.md`, Side B = `analysis-business-requirements.md`. Findings are cross-module architecture-level discrepancies.

---

## Process

1. Read both sides for the target module/scope
2. For each dimension, list what each side says
3. Identify findings — only record things where the two sides differ or where one side is silent
4. Assign category and severity
5. Write the action in the form: *"Update [specific doc]: [specific change]"*
6. Do NOT record things both sides agree on — only differences

---

## Usage Examples

**Module-level:** "Run scope-delta on F001 PayerRegistration — compare domain-design/F001 + brd/F001 vs KB_M0022_RequirementsSpec + KB_M0022_QA"

**Top-level:** "Run scope-delta on the two analysis docs — compare analysis-design-architecture.md vs analysis-business-requirements.md"

**Output location:** `docs/04-delta/delta-code-vs-requirements.md`
