# Document Discovery — Recursive Scan, Classify, Route
**Purpose:** Before any document gets turned into a KB file, figure out what's actually in an
unstructured project folder — it is rarely just documents. Scan recursively, classify every
file, route source code and DB artifacts away from the document pipeline, never silently drop
anything unsupported, and get human sign-off on what's worth extracting before spending effort
on it.
**Companion skills:** `kb-generation.md` (how to turn one approved file into a `KB_*.md`),
`brd-validation.md` (what consumes the resulting `KB.md` downstream), `migration-pipeline.md`
(Phase 4 — where this fits in the overall pipeline)

---

## When to Use This Skill

- A project hands you a folder of "documents" (design specs, requirements, manuals) that hasn't
  been inventoried yet
- Before running `kb-generation.md` on anything — this skill decides *what* to run it on
- Any time a document folder might contain more than documents (source code exports, DB tooling,
  credential sheets) and you need to be sure nothing gets missed or wrongly extracted

---

## Step 1 — Recursive scan & classify

Walk every file under the target folder, no exceptions. Every file gets exactly one
classification:

| Classification | Meaning | Example |
|---|---|---|
| `document` | Text-extractable business/design content | `.xlsx`, `.docx`, `.pdf`, `.pptx`, `.txt`, `.md` |
| `source-code` | Application source, generated or hand-written | `.cs`, `.aspx`, `.js`, `.java`, `.py`, a full app export folder |
| `database-artifact` | Schema, connection info, DB tooling | `.sql`, `.mdb`, `.a5er`, a bundled DB client install |
| `sensitive` | Content that looks like it holds credentials/secrets | filenames flagging "handle-with-care" / "confidential" / "credentials", connection-string sheets |
| `binary-unsupported` | Not text-extractable, or impractically large | `.exe`, `.dll`, fonts, images, archives, multi-GB files |
| `unclassified` | Doesn't fit any rule above with confidence | anything ambiguous |

### Classification signals

Use these together, not any single one in isolation:

1. **Extension map** — the fast path for the common cases in the table above.
2. **Path/folder keyword heuristics** — folder and filename names are often the strongest
   signal, especially in non-English projects. Real examples seen in practice: `requirements specification`
   (requirements spec) and `user manual` (user manual) → `document`; `source code` /
   `_output_sourcecode` / `output/full` → `source-code`; `DB connection info` (DB connection info) →
   `database-artifact`, and if paired with a "handle with care" marker in the filename →
   also `sensitive`.
3. **Structural signals** — a folder containing hundreds of `.cs`/`.dll`/`.cache` files plus
   `bin/`/`obj/`-style subfolders is a compiled app export, not a document, even if one stray
   `.pdf` sits next to it. A folder containing an installer (`.exe`) plus `license.txt`/
   `readme.txt`/`history.txt` is a bundled tool, not project documentation.
4. **Size threshold** — anything impractical to process in full (multi-GB archives, VM images,
   CAD models) is `binary-unsupported` regardless of extension. Don't guess a fixed number;
   flag anything that would clearly dominate the extraction budget for one file.

**When signals conflict or nothing matches confidently, classify as `unclassified` — never
force a best guess into `document`.** A wrong `document` classification wastes extraction
effort on something meaningless; an `unclassified` entry just waits in `Review_Later.md`.

---

## Step 2 — Routing rules per category

| Classification | What happens |
|---|---|
| `document` | Goes to Step 3 (relevance ranking) → Step 4 (checkpoint) → `kb-generation.md` |
| `source-code` | **Never** extracted as KB text. Cross-check against the project's known source inventory (e.g. match module/file names against the code-extraction pipeline's source folder). If a match exists, record `alreadyCovered: true` and move on — it's redundant deployment output. If no match, record `alreadyCovered: false` and surface it prominently in the discovery summary as **"NEW SOURCE FOUND — not in existing code pipeline, recommend running it manually."** Do not auto-trigger extraction or touch any pipeline config — this is a flag for a human decision, every time. |
| `database-artifact` | Same treatment as `source-code`: never extracted as KB text, checked for overlap with what the code pipeline already knows about the data model (e.g. entity/table names), flagged if it looks like new schema information that could resolve existing extraction gaps (unresolved foreign keys, missing tables) — but only ever surfaced as a recommendation. |
| `sensitive` | Logged by path and reason only. **Contents are never read into any KB file, discovery summary, or log** — a `sensitive` file existing is noteworthy; what's inside it is not information this pipeline should be carrying around in plaintext markdown. |
| `binary-unsupported` | Appended to `Review_Later.md`: path, size, reason for skipping, estimated relevance (best guess from filename/folder context alone). |
| `unclassified` | Same as `binary-unsupported` — appended to `Review_Later.md`, reason recorded as "could not classify confidently." |

Nothing is ever silently dropped. Every file ends up either processed, flagged for a pipeline
hand-off, or listed in `Review_Later.md`.

---

## Step 3 — Relevance / priority ranking (documents only)

Every file classified as `document` gets a tier, reusing the category convention already used
per-file in `kb-generation.md`:

| Tier | Category | Typical content |
|---|---|---|
| A | Requirements / specifications | Main feature spec, functional requirements |
| B | Common components / shared reference | Shared component docs, field/label sheets |
| C | Standards / manuals | Dev standards, user manuals, training material |

Within a tier, break ties using:
- **Keyword strength** — a folder/filename containing "requirements definition" outranks
  "user manual," which outranks "incident log" or "meeting notes," for BRD purposes.
- **Version recency** — if V4 and V5 of the same document both exist, only V5 is ranked;
  note the superseded version in the discovery summary but don't queue it for extraction.
- **Redundancy** — a JA-only user manual that duplicates a spec already ranked above it can be
  deprioritized to "process only if time allows" rather than dropped outright.

---

## Step 4 — Human checkpoint

Discovery does **not** feed straight into extraction. Once every file is classified and ranked,
present a summary and wait for confirmation before running `kb-generation.md` on anything:

- Counts per classification category
- The ranked `document` list (tier + file + one-line reason for its rank)
- Everything flagged `source-code` / `database-artifact` (with `alreadyCovered` status)
- Anything flagged `sensitive` (path + reason only)
- The `Review_Later.md` list (unsupported/unclassified, with reasons)

The user reviews this and can reprioritize, exclude items, correct a misclassification, or
approve as-is. Only the approved `document` set moves to Step 5. This keeps effort focused —
a hundred files classified doesn't mean a hundred files get extracted.

---

## Step 5 — Extraction (approved set only)

Hand off each approved file to `kb-generation.md`'s per-file process, in rank order (Tier A
first). That skill owns the extraction methods table, the prompt template, and the `KB_*.md`
file structure — this skill does not duplicate it.

---

## Step 6 — Canonical merge into KB.md

Once every approved file has a `KB_*.md`, run a synthesis pass producing one `KB.md`:

- Cross-reference every `KB_*.md` and the original source document it came from
- Call out duplicates and conflicts explicitly in an "Open Conflicts / Duplicates" section —
  don't silently pick one side
- This `KB.md` is what `brd-validation.md` consumes downstream, alongside the code-derived KB

---

## Completion rule

- **Discovery** is done when every reachable file has a classification and a re-scan produces
  no new `Review_Later.md` entries or unclassified files.
- **Extraction** is done when every file in the approved set has a `KB_*.md` and `KB.md` has
  been resynthesized to include it.

If the source folder changes later (new files added), re-run discovery — it should only surface
the delta, not reclassify everything from scratch.

---

## Output structure

```
knowledge-base/
  share/
    discovery-manifest.json   ← mechanical scan record: path, ext, size, classification,
                                 tier, alreadyCovered flag (source-code/DB only)
    Review_Later.md           ← unsupported / unclassified files — path, size, reason, guess
    KB_{Module}_{Topic}.md    ← one per approved source document (see kb-generation.md)
    KB.md                     ← canonical merge across all KB_*.md
    EXTRACTION_LOG.md         ← session diary (see kb-generation.md for format)
```

---

## Inline script — recursive scan + classifier

Mechanical scanning belongs in code, not in a per-file manual read. This produces
`discovery-manifest.json`; the semantic judgment calls (relevance tier, sensitivity,
already-covered check) still get a human/Claude review pass before Step 4's checkpoint.

```javascript
// discover.js — recursive scan + first-pass classification
const fs = require('fs');
const path = require('path');

const DOC_EXT = new Set(['.xlsx', '.docx', '.pdf', '.pptx', '.txt', '.md', '.xls']);
const CODE_EXT = new Set(['.cs', '.aspx', '.js', '.java', '.py', '.ts', '.cshtml']);
const DB_EXT = new Set(['.sql', '.mdb', '.a5er', '.dms']);
const BINARY_EXT = new Set(['.exe', '.dll', '.png', '.jpg', '.gif', '.ico', '.zip', '.woff', '.woff2']);
const SENSITIVE_HINTS = ['handle-with-care', 'confidential', 'credential', 'password', 'connection info'];
const TOO_LARGE_BYTES = 50 * 1024 * 1024; // flag, don't hard-skip — human decides

function classify(filePath, sizeBytes) {
  const ext = path.extname(filePath).toLowerCase();
  const lower = filePath.toLowerCase();
  if (SENSITIVE_HINTS.some(h => lower.includes(h.toLowerCase()))) return 'sensitive';
  if (sizeBytes > TOO_LARGE_BYTES) return 'binary-unsupported';
  if (DB_EXT.has(ext)) return 'database-artifact';
  if (CODE_EXT.has(ext)) return 'source-code';
  if (DOC_EXT.has(ext)) return 'document';
  if (BINARY_EXT.has(ext)) return 'binary-unsupported';
  return 'unclassified';
}

function scan(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) { scan(full, out); continue; }
    const size = fs.statSync(full).size;
    out.push({ path: full, ext: path.extname(full).toLowerCase(), sizeBytes: size, classification: classify(full, size) });
  }
  return out;
}

const manifest = scan(process.argv[2] || '.');
fs.writeFileSync('discovery-manifest.json', JSON.stringify(manifest, null, 2));
console.log(`Scanned ${manifest.length} files.`);
```

Optional deps worth adding to a project's pipeline for raw text extraction once the approved
set is known (`kb-generation.md`'s manual PowerShell-zip approach still works without these,
but doesn't scale to a large approved set): `mammoth` (docx → text), `xlsx` (spreadsheet cells),
`pdf-parse` (text-based PDFs). These only extract raw text — Claude still does the semantic
structuring into `KB_*.md` per `kb-generation.md`'s prompt template.

---

## Tips

- **Compiled/generated source code found inside a "document" folder is common** — OutSystems,
  Java, and .NET deployment exports often get copied alongside the docs describing them. Check
  `alreadyCovered` before treating it as new information; it usually isn't.
- **A DB tool installation (client, not schema) is `database-artifact`, not `document`** —
  license/readme/history files bundled with it don't need extraction either.
- **Don't try to programmatically strip credentials from a `sensitive` file to "half-extract"
  it** — if a file is flagged sensitive, its content stays out of every KB artifact entirely.
  If genuinely needed later, that's a manual, explicit, human-only step outside this pipeline.
