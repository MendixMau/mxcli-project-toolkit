# Page Patterns — MDL Page Build Rules for This Project

---

## Buttons — Always Define Caption (Japanese) Before Adding

**Rule:** Every `ACTIONBUTTON` in an MDL script MUST include a `Caption:` property. Never add a button without one.

mxcli generates buttons with an empty label when `Caption:` is omitted — the button works functionally but shows nothing in the UI, requiring a Studio Pro fix after every exec.

**Standard captions for this project:**

| Action | Japanese caption |
|--------|-----------------|
| Add row | ` Add row` |
| Delete row | `Delete` |
| Save | `Save` |
| Cancel | `Cancel` |
| Back to list | `Back to list` |
| Next | `Next` |
| Search | `Search` |
| New (payer) | `New` |

**Example:**
```mdl
ACTIONBUTTON btnAddSalesAreaRow (
  Caption: ' Add row',
  ButtonStyle: Success,
  Action: MICROFLOW PayerRegistration.ACT_SalesAreaData_AddRow(Dto: $PayerDetail_Dto)
)
```

If the correct Japanese caption is uncertain, check `extraction/knowledge-base/share/KB_M0022_FieldLabels_EN.md` before writing the script — don't leave Caption blank.

---

## Forward References — Never Reference What Doesn't Exist Yet

**Rule:** Never include a forward reference in an mxcli exec script if the target does not yet exist in the MPR.

mxcli exec hard-fails with `"failed to resolve page: page not found: Module.PageName"` if any referenced element is missing. The script aborts mid-way, leaving the MPR in a partial state.

- Before writing any script that calls `show_page`, `call microflow`, or traverses an association, confirm the target already exists (`SHOW PAGES IN Module` / `SHOW MICROFLOWS IN Module`).
- If the target page doesn't exist yet, create a stub first (`create or replace page` with minimal content), apply it, then apply the page that references it.
- Association traversal in microflows requires the association to exist in the MPR — always apply domain model changes before microflows.

---

## Stub Pages — Use `create or modify` When Filling In

**Rule:** When replacing a stub page with real content, always use `create or modify page`, never `create or replace page`.

`create or replace` deletes and recreates with a new internal ID. Any existing `show_page` button references break immediately.

- Stub creation: `create or replace page` is fine — no references exist yet.
- Fill-in: `create or modify page "Module"."PageName" (...) { ... }` — rewrites content in-place, preserving the document ID.
- Same rule applies to snippets: `create or modify snippet`.

**Risk in this project:** `15b-stub-pages.mdl` created stubs for `Payer_OrgChoice` and `PayerDetail_View`. Steps 7e and 7h MUST use `create or modify` to fill them in.

---

## Page Title Bug (BUG-03) — Never Combine `title:` with `Params:`

**Rule:** Never use `title:` in `create page` / `create or modify page` when the page also has `Params:`.

mxcli writes the title as `Forms$ClientTemplate` instead of `Mendix.Modeler.Texts.Text`. Studio Pro crashes on load.

- Omit `title:` entirely when `Params:` is present.
- Set title separately after page creation:
  ```mdl
  alter page "Module"."PageName" { set title = 'Page Title'; }
  ```
- `title:` without `Params:` works correctly.

---

## ContentParams — Never Use Entity-Qualified Paths for Cross-Module Multi-Hop (BUG-04)

`Assoc1/Assoc2/Module.Entity/Attribute` in contentparams writes a null `AttributeId` GUID → Studio Pro crashes on load.

| Syntax | Context | Result |
|--------|---------|--------|
| `Assoc1/Assoc2/Attribute` | Gallery (database datasource) | Works at runtime |
| `Assoc1/Assoc2/Attribute` | DataView (page param datasource) | CE error, but loads |
| `Assoc1/Assoc2/Module.Entity/Attribute` | Any | MPR crash |

For DataView cross-module multi-hop: use a static placeholder, denormalize, or single-hop only.

---

## Gallery Filter Placement — Filters Go INSIDE the Gallery `filter {}` Block

**Rule:** Gallery filters (`textfilter`, `dropdownfilter`, `datefilter`) must be placed inside the gallery's `filter { }` block — never as standalone textboxes in a toolbar row outside the gallery.

A regular textbox outside the gallery has no filter binding → CE0544 + CE7005.

**Multi-attribute textfilter syntax (mxcli quirk — BUG-10):**
- The mxcli syntax checker rejects qualified `Module.Entity.Attribute` format with dots inside `Attributes` lists.
- The executor silently skips short names (`[CustomerCode]`) — "invalid attribute path: expected Module.Entity.Attribute format".
- **Workaround:** use `mxcli -c` inline with the qualified format (bypasses the syntax checker):
  ```bash
  ./mxcli -p Project.mpr -c "alter page \"Module\".\"Page\" { replace oldFilter with { textfilter newFilter (Attributes: [Module.Entity.Attr1, Module.Entity.Attr2]) } }"
  ```
- Note: due to BUG-08, the replacement widget must use a **different name** than the one being replaced.

**Association-path filters (BUG-09):** Mendix Gallery supports filtering over associated entity attributes (including 2-hop) at runtime. However, mxcli cannot express association-path filter attributes in MDL — only direct entity attributes work. Configure association-based filters manually in Studio Pro.

---

## DataView Datasource — Prefer Context over Microflow

**Rule:** When a nested DataView shows an object reachable via a direct association from the page parameter, use the **Context** datasource type, not a microflow datasource.

- Context datasource: `DataSource: $PayerDetail/PayerRegistration.PayerDetail_PayerCustomerBase`
- Simpler, faster, no extra microflow needed.
- Only use microflow datasource when retrieval requires filtering, aggregation, or multi-hop XPath logic.

**mxcli limitation:** `ALTER PAGE` has no syntax for changing a DataView's datasource type. This must be done manually in Studio Pro: DataView properties → Data source → Type: Context → navigate association tree from page parameter.

**Affected pages (not yet converted):**
- `PayerDetail_View`: `dvPayerCustomerBase` — use path `PayerDetail_PayerCustomerBase/PayerCustomerBase`
- `PayerDetail_View`: `dvPaymentTermData` — check if direct association path exists

---

## Dynamic Class on Gallery Template Widgets — Not Settable via mxcli

`dynamicclass` (expression-based CSS class) cannot be set on any widget inside a gallery template via `alter page` — the gallery template stores widget properties differently from regular page widgets. Both `class` and `dynamicclass` fail with "property not found (widget has no pluggable Object)".

**Workaround:** wrap the widget in a container with a static base class, then set the dynamic class expression in Studio Pro: select the container → Properties → Dynamic class → enter expression.

**Association path syntax in expressions — no module prefix:** use just the association/entity name, not `Module.AssocName`. Example for 2-hop Status from PayerDetail:

```
if $currentObject/PayerDetail_PayerApplicationHeader/PayerApplicationHeader_ApplicationCommonHeader/Status = '01' then 'badge-editing'
else if $currentObject/PayerDetail_PayerApplicationHeader/PayerApplicationHeader_ApplicationCommonHeader/Status = '02' then 'badge-submitted'
else if $currentObject/PayerDetail_PayerApplicationHeader/PayerApplicationHeader_ApplicationCommonHeader/Status = '03' then 'badge-approved'
else if $currentObject/PayerDetail_PayerApplicationHeader/PayerApplicationHeader_ApplicationCommonHeader/Status = '04' then 'badge-returned'
else if $currentObject/PayerDetail_PayerApplicationHeader/PayerApplicationHeader_ApplicationCommonHeader/Status = '99' then 'badge-cancelled'
else 'badge-default'
```

**Note:** `txtStatus2` inside `ctnStatus` is currently unbound — re-bind its contentparam to the same 2-hop path in Studio Pro.

---

## ALTER PAGE — Known Constraints

- **Cannot INSERT rows into a layoutgrid by row name:** `insert after row5 { row newRow { ... } }` fails with "widget not found". ALTER PAGE can only INSERT widgets within an existing column. To add a full new row, use `create or modify page` to rebuild the section, or do it in Studio Pro.
- **SET content on dynamictext with ContentParams (BUG-07):** fails with "property 'content' not found (widget has no pluggable Object)". Use REPLACE with a different widget name instead.
- **REPLACE with same widget name (BUG-08):** fails with "duplicate widget name". Always use a different name in the replacement body — the old name is dropped when the old widget is removed.
- **CONTAINER inside dataview/form slot corrupts BSON (BUG-18):** Wrapping a widget in a new CONTAINER via `replace txtWidget with { container cWrapper { textbox txtWidget } }` inside a `dataview` writes a `DivContainer` into a BSON slot typed for `WidgetObject` — SP crashes on load with `InvalidCastException`. Use SCSS to fake affixes/wrappers instead. Never REPLACE a widget with a container wrapping it inside a form/dataview body.
- **REPLACE on datagrid custom-content columns drops them (observed IVM-MxCLI, 2026-07-05):** `replace colName with { column colName (...) { ... } }` silently deletes the column instead of swapping it. Use `insert after dgName.LastColumn { column ... }` to re-add dropped columns, or rebuild the full datagrid with `create or modify page`.

## Studio Pro Launch — Use Binary Path, Not `open -a`

**Rule:** Never use `open -a "Mendix Studio Pro X.Y.Z Beta" file.mpr` in scripts. macOS `-a` name matching is unreliable and fails with "data format" or error -600.

**Always launch via the binary directly:**

```bash
"/Applications/Mendix Studio Pro X.Y.Z Beta.app/Contents/MacOS/studiopro" "$MPR" &
```

This matches exactly what Finder does when you double-click the MPR. The `&` backgrounds it so the script continues. Works reliably regardless of macOS session state, version selector, or app display name quirks.
