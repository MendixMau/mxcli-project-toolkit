# KB File Generation — Prompt Template
**Applies to:** migration or requirements-driven build (works from documents/SME input — no legacy source needed).
**Purpose:** How to turn raw source documents (xlsx, docx, PDF) into KB_*.md knowledge
base files that Claude can load as context for BRD and MDL generation.
**Source:** Apex M-0022 — 9 KB files produced across 4 sessions, 2026-05.

**Upstream step:** this skill assumes you already know *which* files are worth processing.
For an unstructured folder that hasn't been inventoried yet — and especially one that might
contain source code, DB artifacts, or sensitive files mixed in with documents — run
`document-discovery.md` first. It classifies every file, routes non-document artifacts away
from this process, and produces the human-approved file list this skill then works through
one file at a time.

---

## What a KB file is

A KB (Knowledge Base) file is a structured English markdown summary of one source
document or domain area. It is produced by Claude reading the raw source and
synthesising the key facts into a format optimised for downstream prompting.

KB files are NOT verbatim translations. They extract:
- Screen/entity/field names and their business meaning
- Business rules and validation constraints
- Integration points and API specs
- Role-based access rules
- Decisions and open questions resolved by the document

---

## File naming convention

```
KB_{SourceCode}_{Topic}.md

Examples:
  KB_M0022_RequirementsSpec_V5.md   ← main requirements doc
  KB_M0022_FieldLabels_EN.md        ← field label translations
  KB_M0022_QA.md                    ← QA/clarification sheet
  KB_C0031_CorporateSearch.md       ← common component C-0031
  KB_CorpSearch_API.md                  ← external API manuals (combined)
  KB_CommonComponents.md            ← internal common components
  KB_DevStandards.md                ← development standards
```

Store in: `extraction/knowledge-base/share/`

---

## Note on code extraction

KB files (this skill) cover **document extraction** (xlsx, docx, PDF → KB_*.md).
For **code extraction** (XML, Java, C# → JSON knowledge base), use the pipeline directly:

```bash
node run.js 2 xml       # extracts all XMLs → knowledge-base/ JSONs (full corpus, not a subset)
node run.js 3           # BRD mapper → knowledge-base/brd/*.brd.json
node generate-report.js # → knowledge-base/extraction-report.html (open in browser for review)
```

The HTML report is the primary review artifact after code extraction — it shows all 114 modules,
confidence per module, gap heatmap, and full BRD summary per module. Use it before deciding
which KB document files to process in depth.

---

## Step 1 — Read the source document

The source is often Japanese. Use these extraction methods:

| Format | Method |
|--------|--------|
| `.xlsx` | Extract as ZIP → read `xl/sharedStrings.xml` for cell text. For images in cells: read visually if embedded PNG/JPEG is accessible. |
| `.docx` | Extract as ZIP → read `word/document.xml` → strip XML tags to get plain text. |
| `.pdf` | Use `pdftotext` (text-based PDFs) or read visually (scanned PDFs). |
| `.md` | Read directly. |

**PowerShell ZIP extraction for xlsx/docx:**
```powershell
Add-Type -Assembly System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead('path\to\file.xlsx')
$entry = $zip.Entries | Where-Object { $_.FullName -eq 'xl/sharedStrings.xml' }
$reader = New-Object System.IO.StreamReader($entry.Open())
$content = $reader.ReadToEnd()
$reader.Close(); $zip.Dispose()
$content
```

---

## Step 2 — Prompt Claude to write the KB file

Use this prompt template. Paste after the raw document content.

---

### Prompt template

```
You are writing a KB (Knowledge Base) markdown file for an OutSystems → Mendix migration project.

SOURCE DOCUMENT: [describe the document — what it is, what function it covers]
TARGET FILE: extraction/knowledge-base/share/KB_[Name].md

Read the source document above and write a structured KB file in English.
The KB file will be used as context when generating BRD JSON and MDL scripts.

## What to extract:

1. **Document overview** — title, version, function ID, what it covers (2-3 sentences)

2. **Screens / pages** — for each screen:
   - Name (OS name + English translation)
   - Purpose (what the user does here)
   - Input parameters
   - Key fields with: field name, Japanese label, data type, mandatory/optional, validation rules
   - Actions/buttons and what they trigger

3. **Business rules** — numbered list. Each rule: what triggers it, what it enforces,
   what happens on violation. Include duplicate check rules, approval conditions,
   field-level constraints.

4. **Roles and permissions** — who can see/edit what. If there's an edit permission
   matrix, reproduce it as a table.

5. **Integration points** — external systems called, API names, parameters.
   Include stub-ability assessment (can this be stubbed for POC?).

6. **Entities and fields** — if table definitions are present: entity name, all
   attributes with type/length/mandatory. Note any audit fields
   (IsActive, LockVersion, CreatedOn, CreatedBy, etc.).

7. **Open questions / decisions** — anything ambiguous, conflicting, or requiring
   client confirmation. Format as: D[n]: [question] — [status: Open/Resolved/Deferred]

## Format:
- English throughout (translate Japanese terms; keep Japanese originals in parentheses)
- Use markdown tables for field lists and permission matrices
- Use numbered lists for business rules
- Keep it dense — this is reference material, not prose
- Add `**Source sheet/section:**` cross-references where useful
```

---

## Step 3 — KB file structure (what good output looks like)

Based on the Apex KB files. Adapt sections to what the source contains.

```markdown
# [Topic] — [EN Title]

**Source:** `Share/[folder]/[filename]`
**Category:** A (requirements) / B (common components) / C (standards)
**Processed:** YYYY-MM-DD
**Method:** [extraction method used]

---

## 1. Document Structure

Brief description of what the document contains (sections, sheets, etc.)

---

## 2. Business Overview

Function ID, purpose, users/roles, scope.

---

## 3. Screens

### Screen 01 — [Name] ([Japanese Name])

**Purpose:** ...
**Input parameters:** [list]

| Field | Label (JA) | Type | Mandatory | Rules |
|-------|-----------|------|-----------|-------|
| PayerCode | Order code | Text(10) | Yes | Auto-generated |

**Actions:**
- [Button name]: [what it does]

---

## 4. Business Rules

1. **[Rule name]:** [description]. Violation: [what happens].
2. ...

---

## 5. Roles and Permissions

| Section | ApplyingDept | ReceivableMgmt | MasterMgmt |
|---------|-------------|----------------|------------|
| Section A | Edit | Read-only | Hidden |

---

## 6. Integration Points

| System | Action | Parameters | Stub-able? |
|--------|--------|-----------|-----------|
| CorpSearch | Corporate search | CID, keyword | Yes — return hardcoded result |

---

## 7. Entities

### ENPayerDetail

| Attribute | Type | Length | Mandatory |
|-----------|------|--------|-----------|
| PayerCode | Text | 10 | Yes |

---

## 8. Open Questions / Decisions

- D1: [question] — **Open**
- D2: [question] — **Resolved:** [answer]
```

---

## Tips from M-0022 processing

- **Japanese document, multiple tabs:** Process one tab at a time. Extract the sheet
  list first, then ask Claude to process the most relevant sheets.
- **Embedded images in xlsx:** If sheets contain screen mockups as PNG images, note
  them in the KB as `[Screen mockup — [sheet name] — read visually]` and describe
  what you see.
- **Combined KB files:** If multiple source docs cover the same topic (e.g. two API
  manuals for the same external system), combine into one KB file with separate
  sections per document.
- **Version conflicts:** If V4 and V5 of the same spec exist, process only V5.
  Note the version in the KB header.
- **Skip if redundant:** JA-only user manuals with no new field/rule content can be
  skipped; note the skip in EXTRACTION_LOG.md.

---

## Tracking processed files

Maintain an `EXTRACTION_LOG.md` (session diary):

```markdown
## Session: YYYY-MM-DD

**Files processed:**
- `[path]` → `KB_[Name].md` ✅

**Method:** [what you did]

**Critical findings:**
- [anything surprising or decision-relevant]

**Remaining:**
- [files still to process]
```

One entry per processing session, newest at top.
