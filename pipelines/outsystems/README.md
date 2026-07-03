# OS Migration Skills — Extraction Pipeline

Reusable engine for migrating **OutSystems 11 applications to Mendix**.

Takes OS eSpace XML files → structured JSON knowledge base → BRD scaffolds per module → interactive HTML report.

> For the interactive step-by-step guide, open **`pipeline-guide.html`** in your browser.

---

## Quickstart (3 commands)

```bash
cd pipeline

# 1. Extract all OS XML files into a JSON knowledge base
node run.js 2 xml

# 2. Generate BRD scaffolds (one .brd.json per module)
node run.js 3

# 3. Build the HTML report and open it
node generate-report.js
# → knowledge-base/extraction-report.html
```

Set your source paths in `pipeline/config.json` before running.

---

## Configuration

`pipeline/config.json`:

```json
{
  "blueprintDir": "path/to/OS-ExtractedXML",
  "shareDir":     "path/to/Share/docs",
  "dbDir":        "",
  "docsDir":      "path/to/Share/design-specs"
}
```

---

## Folder structure

```
OS-migration-skills/
  pipeline/
    config.json             ← source paths
    run.js                  ← phase orchestrator (node run.js <1|2|3>)
    generate-report.js      ← HTML report generator
    extractors/
      xml-extractor.js      ← ACTIVE: parses OS eSpace XML → extracted/
      README.md             ← how to add a new extractor
    generators/
      brd-mappers/
        index.js            ← orchestrator: runs all 5 mappers per module
        domain-entity-mapper.js
        microflow-mapper.js
        page-mapper.js
        use-case-mapper.js
        integration-mapper.js
        README.md           ← how to add a new mapper
      mappers/              ← Phase 4 (future): MDL generation from agreed BRDs
      lib/                  ← type-converter, flow-translator, widget-translator
    lib/
      merger.js             ← deduplicates + merges extracted items
      linker.js             ← cross-reference linking + gap detection
      key-resolver.js       ← resolves OS internal keys across XMLs
  skills/
    migrate-general.md
    assess-migration.md
  sample-outputs/           ← reference BRD examples
  pipeline-guide.html       ← interactive pipeline guide (open in browser)
```

---

## What gets extracted from OS XML

Every eSpace XML contains the **full stack** for one OS module:

| OS Concept | KB type | Mendix equivalent |
|---|---|---|
| Server Action | `logic/action` | Microflow |
| Client / Screen Action | `logic/clientAction` | Nanoflow |
| BPT Process | `logic/process` | Workflow *(deferred)* |
| WebScreen | `screen` | Page |
| WebBlock | `webBlock` | Building Block |
| Entity | `entity` | Persistent Entity |
| Static Entity | `staticEntity` | Enumeration |
| Structure | `structure` | Non-persistent Entity |
| ServiceAction | `serviceApi` | Published REST operation |
| Timer | `timer` | Scheduled Event |

---

## How to add a new source type

See `pipeline/extractors/README.md` for the full guide. Short version:

1. Create `pipeline/extractors/{type}-extractor.js` — must write to `pipeline/extracted/{type}.json` following the item interface in `pipeline/lib/interfaces.js`
2. Add a sampler at `pipeline/samplers/{type}-sampler.js`
3. Wire both into `run.js` phase1 and phase2 blocks
4. Add linker rules in `pipeline/lib/linker.js` if cross-references apply

## How to add a new BRD mapper

See `pipeline/generators/brd-mappers/README.md`. Short version:

1. Create the mapper file — receives `(moduleItems, allItems)`, returns an array
2. Export it from `brd-mappers/index.js` and call it in the `mapModule()` function
3. Add the output key to the BRD JSON schema and update `generate-report.js` to display it

---

## Shared toolkit

Cross-project skills, prompt templates, and bug logs live in `mxcli-project-toolkit/` (separate repo):
- `skills/migration-pipeline.md` — full pipeline phase descriptions
- `skills/brd-generation.md` — BRD enrichment prompt templates
- `skills/kb-generation.md` — document extraction (Excel, Word, PDF → KB files)
