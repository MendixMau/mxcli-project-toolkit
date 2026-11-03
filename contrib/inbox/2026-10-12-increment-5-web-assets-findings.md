# mxcli findings — increment 5, web slice Assets & Parts (FSM 9.24.2 -> AssetsApp 11.13.0, monolith on 10.24), 2026-10-12

**From:** MendixMau — toolkit lab run, Decompose increment 5 (split from #293)
**Date:** 2026-10-12
**Kind:** bug
**Field evidence:** a public Marketplace template (FSM 9.24.2), web slice Assets & Parts into Mendix 11.13.0, monolith copy on 10.24; captures not committed (lab run, #293). Numbered captures and tools cited below were not shipped. mxcli v0.26.0, Linux cloud container, no Studio Pro.
**Proposed target:** `bug-logs/mxcli-bugs.md`

---

- `mxcli check` passes a combo box bound to an association through the attribute key, exec refuses it:
  `combobox x (Attribute: $Asset.Asset_Customer, CaptionAttribute: CustomerManagement.Customer.CustomerName)` ->
  check `Check passed!`, exec `property attributeEnumeration binds Asset_Customer, which is an association … not an attribute`.
  Repro: that line in `alter snippet M.S { replace <widget> with { … } };` (captures/13).
- A combo box in association mode (`Association: M.A, DataSource: database M.E, CaptionAttribute: Attr`) on a widget bound
  straight to a snippet parameter (no data container) passes check and exec; `mx check` then gives
  `CE7007 "Selected value is not valid for entity 'Asset_Customer/Customer'. Please select the value again."` (x9).
  Wrapping it in `dataview (DataSource: $Param)` clears it. Repro: replace a param-bound legacy reference selector.
- Published OData `expose ("Description")` stores the quotes: `CE1613 "The selected attribute 'AssetManagement.Asset."Description"' no longer exists."` (x4).
  Repro: any keyword-named attribute quoted in an expose list (captures/24, 26).
- Published OData with no `KEY` passes `mxcli check`; `mx check` then `CE6585 "Published entity '…' must have a key defined."`.
  A `KEY` on an attribute without a unique validation rule also passes check, then `CE6624 "Add a unique validation rule …"`.
- `create external entities from M.Client into M` names the entities after the entity set (`M.Parts`), not the entity type
  (`M.Part`) as Studio Pro does; scripts written against the type name fail with "entity does not exist".
- `describe entity` emits `index ( desc);` with no column (`NativeMobileAsset.NativeAsset`, FSM 10.24 copy) — confirms
  increment 3's "possible" item.
- Legacy widgets have no headless conversion route to the React client (the only client on Mendix 11): `describe` prints
  `-- Forms$DataGrid (grid1) -- NOT re-executable` with no datasource/columns/buttons, and `marketplace install --file` of a
  10.x package into 11.x does not warn that its pages will fail `CE0582` (x22 here). Workaround used: `mxcli bson dump` +
  `slice-assets/tools/legacy-extract.py` + `gen-widgets.py` -> `alter page … replace … with { datagrid … }`.
- A Data grid 2 written by `create page` on a 10.24 project (DataWidgets 2.5.6) fails `CE0463` until `mxcli fix widgets`.
- `marketplace update 109515 --to 5.2.1` on a freshly `mx convert`ed 10.24 copy refuses without `--force`, reporting local edits
  in JavaScript actions (`Wait`, `Vibrate`) nobody made (likely conversion noise).
- Mendix platform tool (`mx` 10.24, not mxcli): `mx update-widgets fsm.mpr` (relative) -> `System.ArgumentNullException: Value cannot be null. (Parameter 'path')`;
  absolute path works. Same class as `mx create-project` relative `--output-dir`.
- Possible, unverified: `mxcli fix design-properties` left `'Make card': on` where the source began with `'Spacing bottom'`
  (`AssetManagement.Snippet_Asset_Notes`, `WarehouseManagement.Warehouse_View`) — reorder or wrong mapping.
- Measured, not a defect: a local -> external association (`TicketManagement.Ticket` -> external `AssetsSeam.Assets`) passes
  `mx check` 0 on 10.24 (captures/35) — so monolith-owned associations into a slice's entities are not a platform blocker.
