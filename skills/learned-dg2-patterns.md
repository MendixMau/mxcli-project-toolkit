# DataGrid patterns — native DATAGRID vs pluggable DG2, filters, toolbar

**Applies to:** any mxcli project
**Purpose:** building a filterable data grid through MDL — which of the two grid forms to
use when, the worked toolbar/filter pattern, and the reconciliation of two field-proven
skills that gave opposite advice. Companion: `learned-datagrid-customcontent-binding.md`
(binding text inside a customContent column), `learned-detection-gaps.md` (the `sort by`
rule and the filter-persistence trap).

---

## Two grid forms, and the contradiction resolved

Two projects wrote opposite rules, both from real evidence:

- One (mxcli v0.16.0, Mendix 11.12.1): *use MDL-native `DATAGRID`, not the pluggable
  widget* — because textfilter attribute binding on the pluggable form breaks with CE1613.
- Another (same era): *always pluggable DG2, never native `DATAGRID`* — because ALTER-PAGE
  column insertion into a grid corrupts the MPR (BSON), and that project had been burned.

Both observations are correct; the second project's *rule* over-reached. The corruption
belongs to `ALTER PAGE ... INSERT`, not to the native grid form (and cross-module DG2 column
inserts corrupt too — BUG-96). So:

**Decision rule**

1. **Never insert columns into any grid via `ALTER PAGE`.** New/changed columns go through
   `CREATE OR REPLACE PAGE` with the full tree written out. This retires the reason for the
   "never native DATAGRID" ban.
2. **Need per-column filters written in MDL → native `DATAGRID`.** `TEXTFILTER` inside a
   column `{}` is auto-wired to the column's attribute; the pluggable form's textfilter
   binding is not persisted correctly (CE1613).
3. **Pluggable DG2 only when MCP (`pg_patch_page`) will configure what MDL cannot** —
   custom-content action columns, real badge widgets, filter wiring to page variables — or
   when you need DG2-only properties. Omit textfilters from its MDL; add via MCP if needed.

## Worked pattern — filterable native DATAGRID with Reset + Export toolbar

Confirmed working on mxcli v0.16.0 / Mendix 11.12.1.

```mdl
-- 1. Reset Filters nanoflow
CREATE OR REPLACE NANOFLOW Module."NF_ResetFilters" ()
BEGIN
  CALL JAVASCRIPT ACTION DataWidgets."Reset_All_Filters" (
    "targetName" = 'dgMyGrid',        -- must EXACTLY match the DATAGRID widget name
    "setToDefault" = true
  );
  RETURN;
END;
/

-- 2. Export to Excel nanoflow
CREATE OR REPLACE NANOFLOW Module."NF_ExportToExcel" ()
RETURNS Boolean AS $Result
BEGIN
  $Result = CALL JAVASCRIPT ACTION DataWidgets."Export_To_Excel" (
    "datagridName" = 'dgMyGrid', "fileName" = 'MyExport', "sheetName" = 'Sheet1',
    "includeColumnHeaders" = true, "chunkSize" = 500
  );
  RETURN $Result;
END;
/

-- 3. Toolbar row above the grid
ROW "rowToolbar" {
  COLUMN "colToolbar" (DesktopWidth: 12) {
    CONTAINER "gridToolbar" (Class: 'filter-actions') {   -- class from YOUR design system
      ACTIONBUTTON "btnReset"  (Caption: 'Reset filters',   Action: NANOFLOW Module."NF_ResetFilters")
      ACTIONBUTTON "btnExport" (Caption: 'Export to Excel', Action: NANOFLOW Module."NF_ExportToExcel")
    }
  }
}

-- 4. The grid — note the explicit SORT BY (mandatory, see below)
ROW "rowGrid" {
  COLUMN "colGrid" (DesktopWidth: 12) {
    CONTAINER "gridWrap" (Class: 'ds-table') {
      DATAGRID "dgMyGrid" (
        DataSource: DATABASE FROM Module."MyEntity" SORT BY "CreatedOn" DESC,
        Action: SHOW_PAGE Module."MyEntity_Detail" ("MyEntity": $currentObject),
        PageSize: 25, PagingPosition: Both,
        DesignProperties: ['Compact': On, 'Hover': On, 'Striped': On]
      ) {
        COLUMN "colId"   (Attribute: "Id",   Caption: 'ID')   { TEXTFILTER "fId"   }
        COLUMN "colName" (Attribute: "Name", Caption: 'Name') { TEXTFILTER "fName" }
        COLUMN "colStatus" (Attribute: "Status", Caption: 'Status') {
          DROPDOWNFILTER "fStatus" (Attributes: [Module."MyEntity"."Status"])
        }
        COLUMN "colCreated" (Attribute: "CreatedOn", Caption: 'Created')
      }
    }
  }
}
```

Hard rules baked into the pattern:

- **Every database DataSource carries an explicit `SORT BY`** — without one the runtime can
  silently return `attributes:{}` for every row but the first (blank grid; invisible to
  `mx check`; found via live `/xas/` capture on a WMS conversion project — see
  `learned-detection-gaps.md`).
- **`DROPDOWNFILTER` needs the fully-qualified `Attributes: [Module.Entity.Attr]`**, and
  the paths go **unquoted where they are member accesses** (quoted bindings corrupt — same
  register). ⚠️ On at least one later setup the dropdownfilter binding **never persisted at
  all** despite green checks (BUG-005 class, a martial-arts-academy PoC project): after any
  filter-widget write, confirm with `DESCRIBE PAGE` that the attribute binding survived,
  and be prepared to drop the widget if it did not.
- **Filter widget attributes must be qualified by the *declaring* entity**: an attribute
  inherited from `System.FileDocument` is `System.FileDocument.Name`, not
  `Module.Entity.Name` — the sub-entity form passes `check --references` but fails CE1613.
- Do NOT add grid/flex layout classes to the wrapper container — it hijacks
  `.widget-datagrid`'s own scaffolding.

## Pluggable DG2 skeleton (when MCP owns the rest)

Property names are lowercase on this form:

```mdl
pluggablewidget 'com.mendix.widget.web.datagrid.Datagrid' "dgName" (
  datasource: database from Module."Entity" sort by "Attribute" desc,
  pageSize: 25, pagination: buttons, pagingPosition: both,
  columnsFilterable: true,
  onClick: SHOW_PAGE Module."Entity_Detail"(Entity: $currentObject),
  dynamicRowClass: 'if $currentObject/IsExclusive then ''row-exclusive'' else '''''
) {
  column "colAttr" (attribute: "Attribute", caption: 'Label')
  column "colStatus" (attribute: "Status", caption: 'Status',
    dynamicCellClass: 'if $currentObject/Status = Module.ENUM_Status.Open then ''badge-open'' else ''badge-default''')
  column "colStatus2" (attribute: "Status", caption: 'Status') {
    filter "filterStatus" { dropdownfilter "fStatus" (attributes: [Module."Entity"."Status"]) }
  }
}
```

- `dynamicCellClass` styles the cell wrapper; the enum caption renders as plain text inside.
  Real badge widgets (coloured pill + icon) need MCP `pg_patch_page`.
- **No textfilters in MDL on this form** (CE1613, binding lost) — add via MCP.
- **No action/kebab columns in MDL** — a DG2 column body only supports `filter {}` blocks,
  and conditional visibility inside DG2 customContent corrupts storage (BUG-18): MCP only.
- On the native `DATAGRID` form, `DynamicRowClass` is not MDL-able either (MDL-WIDGET01) —
  set it via MCP after exec (`pg_patch_page`, path `.../object/dynamicRowClass`).

## Column sizing at phone width — shrink what may ellipsize, floor what must read whole

mxcli writes every DG2 column's `minWidth` as `auto` with no MDL property for it, and a column
`Size` is only legal with `ColumnWidth: manual` (MDL-WIDGET10). So column minimums live in the
theme. Two facts decide the CSS:

- DG2 puts `min-width: 0` on every `.th` and `.td`, so a `1fr` column shrinks below its content.
- A custom-content cell's wrapper `.td-custom-content` is a flex item of `.td` and keeps
  `min-width: auto`, so long text in it grows past the column and runs under the next one.

**Before (the obvious fix, wrong):** `.td > .td-custom-content { min-width: 0; }` on every cell.
Long names ellipsize — and every status pill and id shrinks below its width and spills out of its
cell. Field case (a card-disbursement requirements-driven build, Mendix 11.13.0, 2026-09-27):
20 of 20 pills spilled on one list page at 390px, 5 of 5 on the dashboard, and a header read
"Packa…".

**After:** shrink only the wrapper around text that may ellipsize, floor every header and every
cell that must read whole, and let the grid scroll sideways inside its card:

```scss
.td > .td-custom-content:has(.<text-class>) { min-width: 0; }          // may ellipsize
.widget-datagrid-grid .th,
.widget-datagrid-grid .td:has(.<id-class>, .<pill-class>, .<time-class>) { min-width: max-content; }
.widget-datagrid-content { overflow-x: auto; }
.widget-datagrid-grid { min-width: <the wireframe's grid minimum>; }
```

The class names in `<…>` are your design system's — grep the theme for them, do not copy these.
Measured after: 0 of 20 and 0 of 5 spilled at 390, names still ellipsized, desktop widths
unchanged. Measure per cell (spilled / total, at 390 and 1280); a screenshot glance misses one
clipped pill in twenty.

## Grants

A grid is a widget on a page — no separate grant beyond the page VIEW grant. Access to the
*rows* is entity access on the source entity, per `security-is-not-a-later-script.md`.
