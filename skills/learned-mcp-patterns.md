# MCP Patterns — mxcli + MCP Hybrid Workflow for Mendix Development
**Purpose:** When to use MCP vs mxcli, how to handoff safely between them, and the confirmed JSON patterns for operations mxcli cannot do. This is the primary reference for MCP-augmented development — read it before any MCP write.

**Source:** A live Mendix 11.12.0 Beta project, 2026-07-06/07. Corruptions and near-total module loss from that session informed every rule here.

**Companion skills:** `learned-mdl-preflight.md` (the STOP table that routes to MCP), `iterative-build-loop.md` (exec.sh discipline), `bug-logs/mxcli-bugs.md` (incident detail)

---

## Why this hybrid pattern exists

mxcli's MDL is the primary, high-velocity tool — it handles entities, associations, microflows, enums, demo users, navigation, and most pages in a single script. But mxcli has a class of operations where it silently writes invalid BSON that only mxbuild or Studio Pro detects at load time, causing project corruption. MCP (Studio Pro's in-process API) is the safe fallback for those operations: it writes through SP's own model APIs, which maintain BSON integrity by construction.

This is not a "mxcli is broken, use MCP for everything" pattern. MCP is slower, requires SP to be running, and has its own constraints (schema limits, no autosave). The right mental model is: **mxcli for bulk structure, MCP for the narrow category of writes mxcli corrupts** (see `learned-mdl-preflight.md`'s STOP table).

---

## Hard rules — read before any MCP session

### 1. MCP writes are in-memory only — save after every write

`ped_update_document`, `pg_patch_page`, `ped_create_document` only update Studio Pro's in-memory model. Nothing is flushed to disk until SP saves. **Run `./bin/save-sp.sh` after every MCP write, no exceptions.**

`save-sp.sh` triggers `Cmd+S` via AppleScript:
```bash
osascript -e 'tell application "Mendix Studio Pro ..." to activate'
sleep 0.5
osascript -e 'tell application "System Events" to keystroke "s" using command down'
```

If AppleScript is blocked by macOS accessibility permissions, ask the user to press `Cmd+S` manually and confirm before proceeding. Killing or crashing SP before saving silently discards all MCP edits — this cost two full redo cycles in one session.

### 2. Never run mxcli exec while SP has the project open

SP's in-memory model and mxcli's direct `.mpr`/`mprcontents/` file writes will silently clobber each other. This is split-brain corruption, confirmed as data loss. **Treat MCP-mode and mxcli-mode as mutually exclusive for a given unit of work.** The correct handoff sequence:

```
MCP session → save-sp.sh → git commit Project.mpr mprcontents/ → close SP → exec.sh
```

`exec.sh` enforces this: it reads the SP lock file (`Project.mpr.lock`) and refuses to run if SP has the project open with a live PID.

### 3. Never run two concurrent build streams on the same .mpr

Two Claude sessions, or one Claude session + a manual exec, writing to the same `.mpr`/`mprcontents/` concurrently has caused near-total module loss (confirmed 2026-07-06). `exec.sh` enforces this with a `.exec.lock` file and checks for a running `mxcli exec` process. One writer at a time, always.

### 4. Commit before exec — the uncommitted MPR guard

`exec.sh` refuses to run if `Project.mpr` or `mprcontents/` have uncommitted git changes. The reason: if mxbuild fails after exec, exec.sh auto-restores from the pre-exec snapshot, silently losing any MCP work done since the last commit. **The required sequence before any exec:**

```
Cmd+S in SP → save-sp.sh → git commit Project.mpr mprcontents/ → close SP → exec.sh
```

Override with `FORCE_EXEC=1` only when you are certain the disk state is safe and accept the restore-regression risk.

### 5. ped_check_errors after every write — zero errors required

Run `ped_check_errors` after every `pg_patch_page` / `ped_update_document` / `ped_create_document`. Zero errors required before moving on. If errors appear, attempt ONE fix via `ped_update_document`, then re-check. If errors persist after one fix, report to the user and stop — do not iterate blindly.

### 6. Create an MCP record file for traceability

After every MCP write, create a record file so the change is traceable and repeatable:
```
mdlsource/<module>/NN-mcp-<desc>.mdl
```
Add an entry to `MIGRATION-PROGRESS.md`. MCP changes that aren't recorded look like magic — the next session won't know what was applied or whether it can be replayed.

---

## MCP tool quick reference

| Tool | What it does | Notes |
|------|---|---|
| `pg_patch_page` | Add/replace/remove page widgets via JSON Patch | Pages only; schema rejects some valid Mendix shapes (see BUG-LOCAL-06) |
| `pg_read_page` | Read current page widget tree | Start shallow (depth 2-3), drill with `paths` |
| `ped_create_document` | Create a new microflow/domain element shell | Use for shell only — add activities via `ped_update_document` |
| `ped_update_document` | Add/set/remove elements in a microflow or domain model | Atomically validated; stops on first error |
| `ped_find_document` | Find documents by module+type | Returns qualified names only |
| `ped_read_document` | Read microflow/domain model content | Expand one level at a time via `paths` |
| `ped_check_errors` | Check a document for CE errors | Mandatory after every write |
| `ped_get_schema` | Get the JSON schema for an element type | Mandatory before adding any new element type |

**Check MCP connectivity before starting a session:**
```bash
curl -s -X POST http://localhost:7782/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}' \
  | python3 -c "import json,sys; r=json.load(sys.stdin); print('MCP OK' if 'result' in r else 'MCP DOWN')"
```

MCP is only available when Studio Pro has the project open. If it's down, open SP first.

---

## Confirmed JSON patterns

These were learned through failed attempts and debugging. Use them verbatim — the field names, `$Type` values, and nesting structure are all load-bearing.

### `pg_patch_page` — base call shape
```json
{
  "moduleName": "MyModule",
  "pageName": "MyPage",
  "patches": [
    { "op": "replace", "path": "/widgets/0/widgets/1", "value": { ... } }
  ]
}
```
`op` values: `"replace"`, `"add"`, `"remove"`. Path is a JSON Pointer into the LightPage structure from `pg_read_page`. To append to an array, use `/-` as the final segment.

### `ped_check_errors` — call shape
```json
{
  "documents": [
    { "documentType": "Pages$Page", "documentName": "Module.PageName" }
  ]
}
```
Document types: `Pages$Page`, `Microflows$Microflow`, `DomainModels$DomainModel`.

### `ped_find_document` — call shape
```json
{ "moduleName": "MyModule", "documentType": "Microflows$Microflow" }
```
Returns a list of qualified names only (`{ "foundDocuments": [{ "qualifiedName": "Module.Name", "folderPath": "..." }] }`).

### `ped_create_document` — minimal shell (add activities separately)
```json
{
  "documents": [{
    "documentType": "Microflows$Microflow",
    "moduleName": "MyModule",
    "documentName": "ACT_DoSomething",
    "folderPath": "SubFolder",
    "documentContent": {
      "documentation": "What this does",
      "microflowReturnType": { "$Type": "Microflows$NoReturnType" },
      "allowedModuleRoles": []
    }
  }]
}
```
Avoid building the full activity graph in `documentContent` — use `ped_update_document` to add activities after creation.

### `DatagridDropdownFilter` in association (ref) mode — confirmed working
```json
{
  "$Type": "CustomWidgets$CustomWidget",
  "widgetId": "com.mendix.widget.web.datagriddropdownfilter.DatagridDropdownFilter",
  "object": {
    "baseType": "ref",
    "refEntity": {
      "$Type": "DomainModels$IndirectEntityRef",
      "steps": [{
        "$Type": "DomainModels$EntityRefStep",
        "association": "Module.AssocName",
        "destinationEntity": "Module.TargetEntity"
      }]
    },
    "refOptions": {
      "$Type": "Pages$MicroflowSource",
      "microflowSettings": {
        "$Type": "Pages$MicroflowSettings",
        "parameterMappings": [],
        "outputMappings": [],
        "microflow": "Module.DS_MicroflowName",
        "progressBar": "None",
        "asynchronous": false,
        "formValidations": "All"
      },
      "forceFullObjects": false
    },
    "refCaptionSource": "attr",
    "refCaption": { "$Type": "DomainModels$AttributeRef", "attribute": "Module.TargetEntity.CaptionAttr" },
    "refSearchAttr": { "$Type": "DomainModels$AttributeRef", "attribute": "Module.TargetEntity.SearchAttr" },
    "fetchOptionsLazy": false,
    "filterable": true,
    "multiSelect": false,
    "clearable": true,
    "selectedItemsStyle": "text",
    "selectionMethod": "rowClick"
  },
  "name": "filterWidgetName",
  "tabIndex": 0,
  "editable": "Always"
}
```

**Key constraints:**
- `refOptions` microflow MUST be no-param — the filter widget cannot pass parameters to it
- `refEntity` uses `DomainModels$IndirectEntityRef` (not `AssociationRef`)
- `refOptions` uses `Pages$MicroflowSource` (not `CustomWidgets$CustomWidgetMicroflowSource`)

---

## MCP known limitations

### BUG-LOCAL-06: `pg_patch_page` cannot set typed array properties (e.g. `attributes: AttributeRef[]`)

Setting a DataGrid2 external filter widget's `attributes` property to an array of `AttributeRef` objects is **rejected by `pg_patch_page`'s input schema** (MCP error -32602), even when the shape is exactly what SP itself writes. The schema only accepts page-widget types, `PageParameter`, or `LocalVariable` as array values — not arbitrary element arrays.

**Workaround:** Do this in Studio Pro's GUI — drag the filter widget into the grid's Filter section by hand. SP's own UI sets up the attribute link correctly via internal wiring not exposed through `pg_patch_page`.

### MCP cannot save — explicit save always required

No MCP tool exposes a "save project" operation. Every write session requires `save-sp.sh` (or manual `Cmd+S`) before the session ends. If SP is killed without saving, all MCP writes since the last save are silently lost.

### `ped_update_document` on pages — use `pg_patch_page` instead

Studio Pro's MCP system prompt forbids `ped_update_document` for `Pages$Page` documents — `pg_*` tools only. Attempting `ped_update_document` on a page is rejected.

### Cross-module datasource in DataGrid/ListView → use MCP, not mxcli

mxcli writes null `DestinationEntityId` for cross-module association traversals used as widget datasources. Use `pg_patch_page` instead (see `learned-mdl-preflight.md` rule 7).

---

## MCP-only operations (never use mxcli for these)

Based on confirmed corruption patterns — for these operations, mxcli has no safe path:

| Operation | Use | Notes |
|---|---|---|
| Widget `visible:` / `editable:` conditional expressions | `pg_patch_page` | BSON corruption |
| Project settings / database config | SP GUI only | Neither mxcli nor MCP is safe |
| Inline assoc-set in microflow CHANGE/CREATE | `ped_update_document` | mxcli writes invalid AttributeIdentifier |
| COMBOBOX in association mode | `pg_patch_page` | mxcli rejects Entity property |
| DatagridDropdownFilter in ref mode | `pg_patch_page` | Use confirmed pattern above |
| Cross-module assoc traversal as widget datasource | `pg_patch_page` | Null DestinationEntityId |
| count() in a declare expression | `ped_create_document` + AggregateListAction | CE0117 |
