# Page Patterns — MDL Page Build Rules
**Applies to:** any mxcli project.

**Convention:** each rule is stated generically so it transfers to any project. Where a rule has a
concrete illustration, it's kept as a **labeled example** (often from the Apex M-0022 OS→Mendix PoC —
Japanese captions, `PayerRegistration`/`PayerDetail` names). Read the rule as the portable part; the
example is just there to show the shape. Some older sections below are still written in project-
specific terms and haven't been generalized yet — treat their project names as examples too.

---

## Widget References — Always Include Full Location Context

**Rule:** When referring to a widget in any handoff, instruction, or pending-action list (e.g. a Studio Pro step the user has to click), identify it by its **full path**, never a bare name:

> Page → Section (container ID / label) → sub-context if inside a DataView or gallery → widget name (attribute) → property = value

A bare `txtAccountGroup` is unfindable in Studio Pro — the user has no way to know which page and section it lives in.

**Format:**
> Page `Module.PageName`, Section **Name** (`containerID` / label)[, inside DataView `dvName`, sub-section **label**]: widget `widgetName` (`AttributeName`) → property = value

**Correct:**
> Page `PayerDetail_NewEdit`, Section D (`ctnSec4` / General data): textbox `txtAccountGroup` (AccountGroup) → Editable = Never

**Wrong — do not use:**
> Set `txtAccountGroup` to Editable = Never

Applies to: pending Studio Pro steps, CE-error descriptions, and any instruction asking the user to find and click a widget.

---

## Buttons — Always Define a Caption Before Adding

**Rule:** Every `ACTIONBUTTON` in an MDL script MUST include a `Caption:` property. Never add a button without one.

mxcli generates buttons with an empty label when `Caption:` is omitted — the button works functionally but shows nothing in the UI, requiring a Studio Pro fix after every exec. Keep a project caption glossary (in the target language) so captions are consistent and never left blank; if the correct label is uncertain, look it up in the project's field-label source before writing the script rather than shipping an empty caption.

**Example — Apex M-0022 (Japanese caption glossary):**

| Action | Japanese caption |
|--------|-----------------|
| Add row | ` Add row` |
| Delete row | `Delete` |
| Save | `Save` |
| Cancel | `Cancel` |
| Back to list | `Back to list` |
| Next | `Next` |
| Search | `Search` |
| New | `New` |

```mdl
ACTIONBUTTON btnAddSalesAreaRow (
  Caption: ' Add row',
  ButtonStyle: Success,
  Action: MICROFLOW PayerRegistration.ACT_SalesAreaData_AddRow(Dto: $PayerDetail_Dto)
)
```
> In that project the glossary lived in `extraction/knowledge-base/share/KB_M0022_FieldLabels_EN.md`.

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

---

## New Page — Always Plan and Wire Its Entry Point

**Rule:** Never create a page without deciding — and implementing, in the **same build step** —
**how it is reached**. An orphan page is unreachable at runtime and invisible to testing. This
is routinely forgotten; make it part of creating any page.

Decide the entry point by page type:
- **Overview / landing / home page** → add it to **navigation** (a navigation item / menu item
  in the relevant profile). If it's the app's main screen, consider making it the home page.
- **Detail / edit / new page** → wire the `show page` from its **caller** — a page action
  button, or `show page Module.Page($Param = $obj)` in the microflow that opens it.
- **Popup / snippet-hosted** → confirm the button or action that opens it exists.

```mdl
-- Detail page reached from an overview button (Action wired in the same step)
actionbutton btnOpen (Caption: 'Detail', Action: show_page ItemManagement.Item_Detail(Item: $currentObject))
```

For overview/home pages, add the navigation item in the same step — see `manage-navigation.md`
for the exact `navigation` MDL syntax; don't leave the page out of the nav profile.

**Checklist when adding a page:** (1) who opens it? (2) is that entry point created in this same
script/session? (3) if it's an overview, is it in navigation? State the entry point when you
report the page as done — **a page with no wired caller is not "done."**

---

## Page Build Discipline — Field Fidelity

Learned after a build phase produced pages with wrong widget types, empty sections, and inaccessible fields. These rules are universal; the paths/users in the examples are project-specific.

**Rule: Read the authoritative spec field-by-field before building any page — not the prototype.** A prototype/mockup HTML omits fields, flattens sections, and makes everything look like a text input. Build from the field-level spec (labels, types, mandatory/optional, section structure) and the domain-model bindings, not the mockup.
> *Example — Apex M-0022:* authoritative sources were `KB_M0022_FieldLabels_EN.md` (labels + types), `KB_M0022_RequirementsSpec_V5.md` (rules), `07_Form.md` (section structure), and `docs/domain-design-enriched/F001–F012.md` (entity bindings).

**Rule: Cross-check DTOs/NPEs against pages before calling a phase done.** When the domain model and pages are built in separate sessions, verify every DTO created in the domain phase is actually bound to a DataView on some page. A 34-attribute DTO that no page renders is invisible — a silent gap.

**Rule: After any page build, test with a non-admin user before moving on.** Write access on non-persistent (DTO) entities is not inherited from persistent-entity access rules; failing to grant `write *` to the relevant User roles produces greyed-out forms that look built but aren't usable. Log in as a real end-user role immediately after page creation.
> *Example — Apex M-0022:* tested with `yoko.taoka` (HQDomestic role) right after each page.

**Rule: Stub banners must name the script that will replace them.** Use `[STUB: Script 44 will replace this section]`, never a bare `[STUB] handled elsewhere` — named stubs are trackable and don't get forgotten as sessions progress. (A stub banner with nothing rendered beneath it is invisible in a demo — always render at least one real data field below it.)

**Rule: Use the correct widget type from the start** — don't plan to change textbox → combobox later. Widget-type swaps via `ALTER PAGE` are painful (BUG-08: the replacement must use a different name). If a field has a master-data source or enumeration, give it the correct widget (combobox/radiobuttons/datepicker) in the original page script, not a later patch.

---

## Navigation Sidebar — Icons Only, No Text Labels

**Rule:** Navigation menu items must use icon-only display. Never set a text `Caption` on sidebar nav items — use a glyph or SVG icon class only.

This applies to:
- All `NAVIGATIONLIST` items in any sidebar navigation profile
- Any future `CREATE OR REPLACE NAVIGATION` MDL that configures a side nav

**Why:** Text labels in the sidebar violate the Stockpilot design system spec, which shows icon-only nav items in the 220px side panel. Text alongside icons makes the sidebar visually heavy and inconsistent with the design.

**How to apply in MDL:**

```mdl
-- Icon-only nav item: set Caption to empty string, apply glyph class
navigationitem navItems (
  Caption: '',
  Icon: 'glyphicon-list',
  Action: show_page Inventory.Item_Overview
)
```

For custom SVG icons, apply a CSS class and leave Caption empty. Never populate Caption with a human-readable label on sidebar profiles.
