# Extractors — How to Add a New Source Type

Extractors parse a raw source (XML, C#, JS, SQL, Excel) and write normalized JSON items to `pipeline/extracted/`.

The merger (`lib/merger.js`) picks up everything in `extracted/`, deduplicates, and cross-links.

---

## Active extractors

| File | Source | Status |
|------|--------|--------|
| `xml-extractor.js` | OutSystems module XML | Active — extracts full OS stack |
| `cs-extractor.js` | C# compiled output | Stub — skipped when no CS source |
| `js-extractor.js` | JS compiled output | Stub — skipped when no JS source |

---

## Item interface

Every item written to `extracted/` must follow this shape (defined in `../lib/interfaces.js`):

```json
{
  "type":      "entity | logic | screen | structure | serviceApi | timer | staticEntity | webBlock | role | extEntity",
  "linkId":    "xml:{type}:{name}:{uniqueId}",
  "uniqueId":  "{Kind}:{base64key}",
  "name":      "PascalCase name",
  "module":    "ModuleName",
  "_source":   "absolute path to source file",
  "_gaps":     [],
  "_links":    []
}
```

`_gaps` and `_links` are populated by `lib/linker.js` after extraction — leave them as empty arrays.

---

## Step-by-step: adding a new extractor

### 1. Create the extractor file

`pipeline/extractors/{type}-extractor.js`

```js
'use strict';
const fs   = require('fs');
const path = require('path');

const sourceDir  = process.argv[2];                           // passed by run.js
const outputFile = path.join(__dirname, '..', 'extracted', '{type}.json');

const items = [];

// Parse your source files here, push normalized items to items[]

fs.mkdirSync(path.dirname(outputFile), { recursive: true });
fs.writeFileSync(outputFile, JSON.stringify(items, null, 2), 'utf8');
console.log(`Extracted ${items.length} {type} items`);
```

Key rules:
- `type` must match one of the allowed values in the interface above (or add a new one to `interfaces.js`)
- `linkId` must be globally unique — prefix with `{type}:` to avoid collisions
- `module` must match the module name used by other extractors for the same module
- Never write directly to `knowledge-base/` — write to `extracted/` only

### 2. Create a sampler

`pipeline/samplers/{type}-sampler.js` — reads a small subset and writes a schema summary:

```js
'use strict';
const fs = require('fs');
const path = require('path');

const sourceDir = process.argv[2];
const n         = parseInt(process.argv[3] || '5', 10);

// Read n sample files, derive schema shape
const schema = { sampleCount: n, fields: [] /* ... */ };

const outFile = path.join(__dirname, '..', 'samples', '{type}-schema.json');
fs.writeFileSync(outFile, JSON.stringify(schema, null, 2), 'utf8');
console.log(`Sampled ${n} {type} files`);
```

### 3. Wire into run.js

In `phase1()`:
```js
if (!only || only === '{type}')
  jobs.push(run('node', [path.join('samplers', '{type}-sampler.js'), CONFIG.{type}Dir, '8'], '{type}-sampler'));
```

In `phase2()`:
```js
if (!only || only === '{type}')
  jobs.push(run('node', [path.join('extractors', '{type}-extractor.js'), CONFIG.{type}Dir], '{type}-extractor'));
```

Add `{type}Dir` to `config.json`.

### 4. Add linker rules (optional)

If your new type has cross-references to existing types, add rules in `lib/linker.js`.
Follow the existing Rule X1–X6 patterns: iterate items, look up target by name/key, push to `linkedTo[]` or `gaps[]`.

### 5. Add to merger

`lib/merger.js` automatically picks up any JSON written to `extracted/` — no change needed unless you need custom deduplication logic.

### 6. Wire into the HTML report

Add a bucket call in `generate-report.js`:
```js
const myItems = readJson('{type}.json');
bucket(myItems, '{type}s');
```

Then add display logic in the `showModule()` JS function.

---

## Noise reduction in linker.js

Some gaps are expected/irrelevant and should be suppressed:

| Gap type | Cause | Action |
|----------|-------|--------|
| `no-db-table-found` | OS XML doesn't expose SQL table names | Suppress when no DB source provided |
| `fk-unresolved:User` | OS platform system entity | Map to `Administration.Account` in Mendix |
| `fk-unresolved:Group` | OS platform system entity | Map to `Administration.UserRole` |
| `fk-unresolved:Espace` | OS internal concept | No Mendix equivalent — ignore |
| `fk-unresolved:Role` | OS platform role entity | Map to `Administration.UserRole` |

Add new suppression rules to the `PLATFORM_ENTITIES` constant in `lib/linker.js`.
