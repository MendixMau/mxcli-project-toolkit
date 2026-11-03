### MDL

```mdl
-- 10-orders-pages.mdl (DRAFT, not executed). Syntax drafted from general knowledge; no skill text loaded.

CREATE OR REPLACE PAGE Sales."Order_Overview"
(
  Title: 'Orders',
  Layout: Atlas_Core.Atlas_Default,
  Folder: 'Orders/Pages'
)
{
  CONTAINER cntHeader (Class: 'page-header') {
    CONTAINER cntBreadcrumb (Class: 'breadcrumb') {
      ACTIONBUTTON btnCrumbHome (Caption: 'Home', Class: 'breadcrumb-link', Action: PAGE Sales."Home")
      DYNAMICTEXT txtCrumbOrders (Content: 'Orders', Class: 'breadcrumb-current')
    }
    DYNAMICTEXT txtTitle (Content: 'Orders', RenderMode: H1, Class: 'page-title')
    ACTIONBUTTON btnNew (Caption: 'New order', ButtonStyle: Primary, Action: PAGE Sales."Order_NewEdit" (NEW Sales."Order"))
  }

  DATAGRID dgOrders (DataSource: DATABASE Sales."Order" SORT BY "OrderDate" DESC)
  {
    COLUMN colNumber (Caption: 'Order number', Attribute: "OrderNumber")
    COLUMN colDate (Caption: 'Order date', Attribute: "OrderDate")
    COLUMN colStatus (Caption: 'Status', Attribute: "Status")
    COLUMN colCustomer (Caption: 'Customer', Attribute: Sales."Order_Customer"/Sales."Customer"/"Name")
    COLUMN colTotal (Caption: 'Total', Attribute: "TotalAmount")
    -- UNVERIFIED: system member changedBy (association to System.User); path form not checked
    COLUMN colChangedBy (Caption: 'Last changed by', Attribute: System."changedBy"/System."User"/"Name")
    COLUMN colActions (Caption: 'Actions') {
      ACTIONBUTTON btnEdit (Caption: 'Edit', Action: PAGE Sales."Order_NewEdit" ($Order: $currentObject))
    }
  }

  -- Empty state: UNVERIFIED mechanism (no verified grid empty-text property known)
  CONTAINER cntEmpty (Class: 'empty-state', Visible: 'count($dgOrders) = 0') {
    DYNAMICTEXT txtEmpty (Content: 'No orders yet.')
  }
};

CREATE OR REPLACE PAGE Sales."Order_NewEdit"
(
  Title: 'Edit order',
  Layout: Atlas_Core.Atlas_Default,
  Folder: 'Orders/Pages',
  Params: { $Order: Sales."Order" }
)
{
  CONTAINER cntHeader (Class: 'page-header') {
    CONTAINER cntBreadcrumb (Class: 'breadcrumb') {
      ACTIONBUTTON btnCrumbHome (Caption: 'Home', Class: 'breadcrumb-link', Action: PAGE Sales."Home")
      ACTIONBUTTON btnCrumbOrders (Caption: 'Orders', Class: 'breadcrumb-link', Action: PAGE Sales."Order_Overview")
      DYNAMICTEXT txtCrumbEdit (Content: 'Edit order', Class: 'breadcrumb-current')
    }
    DYNAMICTEXT txtTitle (Content: 'Edit order', RenderMode: H1, Class: 'page-title')
  }

  DATAVIEW dvOrder (DataSource: $Order, Class: 'card') {
    TEXTBOX txtOrderNumber (Label: 'Order number', Attribute: "OrderNumber")
    DATEPICKER dpOrderDate (Label: 'Order date', Attribute: "OrderDate")
    RADIOBUTTONS rbStatus (Label: 'Status', Attribute: "Status")
    COMBOBOX cbCustomer (Label: 'Customer', Attribute: Sales."Order_Customer", CaptionAttribute: "Name")
    TEXTAREA taNote (Label: 'Note', Attribute: "Note")
    FOOTER {
      ACTIONBUTTON btnSave (Caption: 'Save', ButtonStyle: Primary, Action: SAVE_CHANGES)
      ACTIONBUTTON btnCancel (Caption: 'Cancel', Action: CANCEL_CHANGES)
    }
  }
};

GRANT VIEW ON PAGE Sales."Order_Overview" TO Sales."User";
GRANT VIEW ON PAGE Sales."Order_NewEdit" TO Sales."User";
```

### WRITE MODES

- create page Sales."Order_Overview" — `./bin/exec.sh mdlsource/10-orders-pages.mdl` — plain page, no custom widget config; Studio Pro closed.
- create page Sales."Order_NewEdit" — `./bin/exec.sh` — the combobox is in association mode (Order_Customer), which in the project's write-mode table needs hand-rolled MCP (`pg_patch_page`) with Studio Pro open. This page must be split out or the combobox patched via MCP.
- datagrid column over cross-module path System.changedBy/User/Name — MCP/Studio Pro — cross-module datasource traversal is a hand-rolled MCP case in the project table; also unverified.
- grant view on pages — `./bin/exec.sh` — plain access grant, Studio Pro closed.

### PREFLIGHT

No project skills or preflight files were loaded in this session (the pack contains only a generic role line), so I have no checklist to post. Skill-level "no trigger" lines: NOT APPLICABLE, nothing loaded.

STOP-table check: NOT RUN — `learned-mdl-preflight.md` was not in my context and I may not open files. I cannot claim the script clears it.

Checks not run: `mxcli check` syntax, `check --references`, mx check, mxbuild, and a capability probe of the v0.26.0 binary. All NOT RUN — I cannot execute tools.

Items I could not verify from context:
1. Page and widget property syntax (Folder, Params, SORT BY, Visible expression, FOOTER, SAVE_CHANGES/CANCEL_CHANGES) is drafted from general MDL knowledge.
2. "Last changed by": `changedBy` is an association to System.User, not a plain attribute. The path syntax is a guess. Showing the user name also needs Sales."User" read access to System.User (not granted in this slice).
3. Empty state: I know of no verified datagrid empty-text property; the visibility expression on a sibling container is a guess.
4. Identifiers are quoted per project convention; the unquoted forms Sales."Order_Customer"/System."changedBy" are used as qualified names.

### REPORT

```report
scripts: 1
operations: 4
studio_pro_ops: 2
stops_flagged: 3
checks_not_run: 5
open_questions: 3
```

Notes: Open questions: (1) correct MDL path for the changedBy column and the System.User read access it needs; (2) mechanism for the grid empty state; (3) whether the association-mode combobox goes via MCP or is split into a separate script. Nothing was executed. stops_flagged counts the changedBy traversal, the association combobox and the unverified empty state.
