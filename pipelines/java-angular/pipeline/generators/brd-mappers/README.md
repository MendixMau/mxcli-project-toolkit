# BRD Mappers — How to Add a New Mapper

BRD mappers transform normalized KB JSON (output of Phase 2) into structured BRD sections per module.

Each mapper is responsible for one section of the BRD JSON. They are all called by `index.js` per module.

---

## Active mappers

| File | Input KB types | BRD section |
|------|---------------|-------------|
| `domain-entity-mapper.js` | `entities[]` + `staticEntities[]` | `domainEntities[]` |
| `microflow-mapper.js` | `logics[]` | `microflows[]` |
| `page-mapper.js` | `screens[]` + `webBlocks[]` | `pages[]` + `webBlocks[]` |
| `use-case-mapper.js` | `screens[]` | `useCases[]` *(scaffold only)* |
| `integration-mapper.js` | `serviceApis[]` + `extEntities[]` | `integrations[]` |

---

## BRD JSON schema (per module)

```json
{
  "module":       "ModuleName",
  "generatedAt":  "ISO timestamp",
  "confidence":   "high | medium | low",
  "summary": {
    "entityCount":       0,
    "enumerationCount":  0,
    "microflowCount":    0,
    "nanoflowCount":     0,
    "bptProcessCount":   0,
    "pageCount":         0,
    "webBlockCount":     0,
    "useCaseCount":      0,
    "integrationCount":  0,
    "timerCount":        0,
    "openGapCount":      0
  },
  "domainEntities": [],
  "microflows":     [],
  "pages":          [],
  "webBlocks":      [],
  "useCases":       [],
  "integrations":   [],
  "timers":         [],
  "openGaps":       []
}
```

Confidence scoring: **high** = 0 open gaps, **medium** = 1–3, **low** = 4+.

---

## Mapper interface

Each mapper is a function with this signature:

```js
/**
 * @param {Object} moduleItems  - { entities, logics, screens, ... } for this module only
 * @param {Object} allItems     - same shape but across all modules (for cross-module lookups)
 * @returns {Array}             - array of mapped BRD items
 */
function map(moduleItems, allItems) {
  return [];
}

module.exports = { map };
```

- Mappers are **pure functions** — no file I/O, no side effects
- Return an **empty array** if the module has none of this type (never return null)
- Add gap strings to `item._gaps[]` for anything unresolvable — these roll up into `openGaps[]` and affect confidence

---

## Step-by-step: adding a new mapper

### 1. Decide what it maps

What KB item type(s) does it consume? What BRD section does it produce?

Examples of things you might add:
- `role-mapper.js` → maps `roles[]` to a `permissions[]` section (role-based access matrix)
- `workflow-mapper.js` → maps `logics[kind=process]` to `workflows[]` (BPT → Mendix Workflow)
- `structure-mapper.js` → maps `structures[]` to `nonPersistentEntities[]`

### 2. Create the mapper file

`pipeline/generators/brd-mappers/{name}-mapper.js`:

```js
'use strict';

function map(moduleItems, allItems) {
  const results = [];

  for (const item of (moduleItems.{sourceType} || [])) {
    const gaps = [];

    // ... your mapping logic ...

    results.push({
      name:      item.name,
      module:    item.module,
      // ... mapped fields ...
      mendixType: '...',
      _gaps:     gaps,
    });
  }

  return results;
}

module.exports = { map };
```

### 3. Wire into index.js

In `brd-mappers/index.js`, import and call your mapper in the `mapModule()` function:

```js
const { map: mapRoles } = require('./role-mapper');

function mapModule(moduleName, moduleItems, allItems) {
  // ... existing mappers ...
  const permissions = mapRoles(moduleItems, allItems);

  return {
    // ... existing fields ...
    permissions,
    // update summary:
    summary: {
      // ...
      permissionCount: permissions.length,
    },
    openGaps: [
      // ... existing gaps ...
      ...permissions.flatMap(p => p._gaps || []),
    ],
  };
}
```

### 4. Update the HTML report

In `generate-report.js`, add a display block for your new section inside the `showModule()` JavaScript function. Follow the existing pattern (table with columns matching your mapper's output shape).

### 5. Update generate-report.js stats

Add a count to the dashboard stat cards if relevant (e.g. total permissions across all modules).

---

## Adding a new Mendix concept mapping

When OutSystems adds a new concept type (or you encounter one not yet mapped), update:

1. `pipeline/extractors/xml-extractor.js` — parse it from XML, emit with the right `type`
2. A new mapper in `brd-mappers/` — transform to the Mendix equivalent
3. `mxcli-project-toolkit/skills/source-os11.md` — document the OS concept
4. `mxcli-project-toolkit/skills/migration-pipeline.md` — add to the concept mapping table

---

## Deferred: Mendix Workflow mapper (BPT processes)

BPT processes (`logicKind: 'process'`) are extracted into `logics[]` but not yet mapped.
They appear as `bptProcessCount` in the BRD summary.

Before building `workflow-mapper.js`, a business conversation is needed to understand:
- Approval chain structure (single route vs branching)
- Escalation rules and SLA timers
- Which roles participate at each step

Once that's clear, the mapper should produce a `workflows[]` section with steps, transitions, and role assignments.
