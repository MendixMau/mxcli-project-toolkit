### MDL

```mdl
-- 10-orders-pages.mdl  (Sales, feature group Orders)
-- Draft only: NOT checked, NOT executed. Owner of: Sales.Order_Overview, Sales.Order_NewEdit and the six
-- microflows below. Does not touch the domain model (02-sales-domain.mdl owns it).
-- Deliberate deviation from the request: NO "Last changed by" column. Binding a widget to the
-- AutoChangedBy member (changedBy) is STOP #4 in learned-mdl-preflight.md (check passes, mx check
-- gives CE1613). See the report notes for the decision the main session must take.
-- Forward reference: the microflows that show Order_Overview / Order_NewEdit are written before the
-- pages. Overview -> NewEdit -> Overview is a cycle, so one forward reference is unavoidable.
-- No @position anywhere (microflow-preflight.md, Layout).

-- ===================== Microflows =====================

create or modify microflow Sales."NAV_Home" ()
folder 'Orders/Microflows'
begin
  show page Sales."Home";
end;

create or modify microflow Sales."NAV_Order_Overview" ()
folder 'Orders/Microflows'
begin
  show page Sales."Order_Overview";
end;

create or modify microflow Sales."ACT_Order_New" ()
folder 'Orders/Microflows'
begin
  $NewOrder = create Sales."Order" ();
  show page Sales."Order_NewEdit"($Order = $NewOrder);
end;

create or modify microflow Sales."ACT_Order_Edit" ($Order: Sales."Order")
folder 'Orders/Microflows'
begin
  show page Sales."Order_NewEdit"($Order = $Order);
end;

create or modify microflow Sales."ACT_Order_Save" ($Order: Sales."Order")
folder 'Orders/Microflows'
begin
  commit $Order with events refresh;
  close page;
end;

create or modify microflow Sales."ACT_Order_Cancel" ($Order: Sales."Order")
folder 'Orders/Microflows'
begin
  rollback $Order refresh;
  close page;
end;

grant execute on microflow Sales."NAV_Home" to Sales."User";
grant execute on microflow Sales."NAV_Order_Overview" to Sales."User";
grant execute on microflow Sales."ACT_Order_New" to Sales."User";
grant execute on microflow Sales."ACT_Order_Edit" to Sales."User";
grant execute on microflow Sales."ACT_Order_Save" to Sales."User";
grant execute on microflow Sales."ACT_Order_Cancel" to Sales."User";

-- ===================== Page 1: Order_Overview =====================

create or replace page Sales."Order_Overview" (
  Title: 'Orders',
  Layout: Atlas_Core.Atlas_Default,
  Folder: 'Orders/Pages'
)
{
  container ctnPageHead (Class: 'page-header spacing-outer-bottom-large') {
    container ctnCrumb (Class: 'breadcrumb') {
      linkbutton lnkHome (Caption: 'Home', Class: 'breadcrumb-link', Action: MICROFLOW Sales."NAV_Home"())
      dynamictext txtCrumbSep (Content: ' › ')
      dynamictext txtCrumbCurrent (Content: 'Orders', Class: 'breadcrumb-current')
    }
    dynamictext txtTitle (Content: 'Orders', RenderMode: H1, Class: 'page-title')
    actionbutton btnNewOrder (Caption: 'New order', ButtonStyle: Primary, Action: MICROFLOW Sales."ACT_Order_New"())
  }

  container ctnOrders (Class: 'card spacing-outer-bottom-large') {
    datagrid dgOrders (DataSource: database from Sales."Order" sort by "OrderDate" desc) {
      column colOrderNumber (Attribute: "OrderNumber", Caption: 'Order number')
      column colOrderDate (Attribute: "OrderDate", Caption: 'Order date')
      column colStatus (Attribute: "Status", Caption: 'Status')
      column colCustomer (Attribute: Order_Customer/Name, Caption: 'Customer')
      column colTotal (Attribute: "TotalAmount", Caption: 'Total')
      column colEdit (Caption: 'Actions', ShowContentAs: customContent) {
        actionbutton btnEditOrder (Caption: 'Edit', Action: MICROFLOW Sales."ACT_Order_Edit"(Order: $currentObject))
      }
      EmptyPlaceholder: {
        container ctnEmpty (Class: 'empty-state') {
          dynamictext txtEmpty (Content: 'No orders yet.')
        }
      }
    }
  }
}

grant view on page Sales."Order_Overview" to Sales."User";

-- ===================== Page 2: Order_NewEdit =====================

create or replace page Sales."Order_NewEdit" (
  Params: { $Order: Sales."Order" },
  Title: 'Edit order',
  Layout: Atlas_Core.Atlas_Default,
  Folder: 'Orders/Pages'
)
{
  container ctnPageHead (Class: 'page-header spacing-outer-bottom-large') {
    container ctnCrumb (Class: 'breadcrumb') {
      linkbutton lnkHome (Caption: 'Home', Class: 'breadcrumb-link', Action: MICROFLOW Sales."NAV_Home"())
      dynamictext txtCrumbSep1 (Content: ' › ')
      linkbutton lnkOrders (Caption: 'Orders', Class: 'breadcrumb-link', Action: MICROFLOW Sales."NAV_Order_Overview"())
      dynamictext txtCrumbSep2 (Content: ' › ')
      dynamictext txtCrumbCurrent (Content: 'Edit order', Class: 'breadcrumb-current')
    }
    dynamictext txtTitle (Content: 'Edit order', RenderMode: H1, Class: 'page-title')
  }

  container ctnForm (Class: 'card spacing-outer-bottom-large') {
    dataview dvOrder (DataSource: $Order) {
      textbox txtOrderNumber (Label: 'Order number', Attribute: "OrderNumber")
      datepicker dpOrderDate (Label: 'Order date', Attribute: "OrderDate")
      radiobuttons rbStatus (Label: 'Status', Attribute: "Status")
      combobox cbCustomer (Label: 'Customer', Attribute: Order_Customer, DataSource: database from Sales."Customer" sort by "Name" asc, CaptionAttribute: "Name")
      textarea taNote (Label: 'Note', Attribute: "Note")
      footer ftOrder {
        actionbutton btnSave (Caption: 'Save', ButtonStyle: Primary, Action: MICROFLOW Sales."ACT_Order_Save"(Order: $Order))
        actionbutton btnCancel (Caption: 'Cancel', Action: MICROFLOW Sales."ACT_Order_Cancel"(Order: $Order))
      }
    }
  }
}

grant view on page Sales."Order_NewEdit" to Sales."User";
```

### WRITE MODES

- create or modify microflow Sales."NAV_Home" — CLI via ./bin/exec.sh (Studio Pro closed) — Step 0 default; plain show-page flow, no STOP row applies.
- create or modify microflow Sales."NAV_Order_Overview" — CLI via ./bin/exec.sh — same; carries a forward reference to the page created later in the script.
- create or modify microflow Sales."ACT_Order_New" — CLI via ./bin/exec.sh — create-object plus show-page, no association set, no STOP row.
- create or modify microflow Sales."ACT_Order_Edit" — CLI via ./bin/exec.sh — single show-page with a parameter.
- create or modify microflow Sales."ACT_Order_Save" — CLI via ./bin/exec.sh — commit with events plus refresh, then close page (page-triggered, so refresh applies).
- create or modify microflow Sales."ACT_Order_Cancel" — CLI via ./bin/exec.sh — rollback with refresh, then close page.
- grant execute on microflow Sales."NAV_Home" to Sales."User" — CLI via ./bin/exec.sh — co-located grant per the brief.
- grant execute on microflow Sales."NAV_Order_Overview" to Sales."User" — CLI via ./bin/exec.sh — co-located grant per the brief.
- grant execute on microflow Sales."ACT_Order_New" to Sales."User" — CLI via ./bin/exec.sh — co-located grant per the brief.
- grant execute on microflow Sales."ACT_Order_Edit" to Sales."User" — CLI via ./bin/exec.sh — co-located grant per the brief.
- grant execute on microflow Sales."ACT_Order_Save" to Sales."User" — CLI via ./bin/exec.sh — co-located grant per the brief.
- grant execute on microflow Sales."ACT_Order_Cancel" to Sales."User" — CLI via ./bin/exec.sh — co-located grant per the brief.
- create or replace page Sales."Order_Overview" — CLI via ./bin/exec.sh — grid has no conditional visible/editable inside customContent (STOP #1 not hit); association column written unquoted (STOP #26); the AutoChangedBy column is omitted (STOP #4).
- grant view on page Sales."Order_Overview" to Sales."User" — CLI via ./bin/exec.sh — co-located grant per the brief.
- create or replace page Sales."Order_NewEdit" — CLI via ./bin/exec.sh — combobox in association mode is CLI-writable on v0.24+ (Step 0); no Editable or Visible expressions used.
- grant view on page Sales."Order_NewEdit" to Sales."User" — CLI via ./bin/exec.sh — co-located grant per the brief.

### PREFLIGHT

**Step 0 write mode.** Default CLI through `./bin/exec.sh`, Studio Pro closed. No operation needs Studio Pro by hand or MCP. Per-document folder, read off the brief's folder plan: pages go to `Orders/Pages`, microflows to `Orders/Microflows`. All 8 created documents carry a `folder` (6 microflows, 2 pages). No enumerations or constants are created, so no `move` statements are needed.

**microflow-preflight** (one block per microflow, all Simple):
- `microflow-preflight: no trigger` — Sales.NAV_Home (linear, 1 activity, no loop).
- `microflow-preflight: no trigger` — Sales.NAV_Order_Overview (linear, 1 activity, no loop).
- `microflow-preflight: no trigger` — Sales.ACT_Order_New (tier Simple: 2 activities, no loop, one entity).
- `microflow-preflight: no trigger` — Sales.ACT_Order_Edit (tier Simple: 1 activity).
- `microflow-preflight: no trigger` — Sales.ACT_Order_Save (tier Simple: 2 activities; one commit, not in a loop; refresh used because page-triggered).
- `microflow-preflight: no trigger` — Sales.ACT_Order_Cancel (tier Simple: 2 activities).
- Layout: no `@position` anywhere. Annotations: none; no activity has a non-obvious why.

**ui-preflight-pages (pages Order_Overview, Order_NewEdit):**
- Step 0, entry points: `mxcli impact` / `callers` / `DESCRIBE PAGE Sales."Home"` — NOT RUN, no tools or model available. Known from the prompt: `Sales."Home"` exists. Both new pages are reached only through the breadcrumb and button microflows written here. No navigation item is added; the brief requests none.
- Step 1, wireframes: `design/wireframes/order-overview.html` and `order-newedit.html` — NOT READ as files (file access not allowed); worked from the transcription in the task. Binding table taken from that transcription.
- Step 2, design system: `design/ds.css` not opened. Only the classes the task lists are used: `page-header`, `page-title`, `breadcrumb`, `breadcrumb-link`, `breadcrumb-current`, `card`, `empty-state`. The only other classes are the Atlas spacing utility `spacing-outer-bottom-large` (the section-rhythm class from design-spacing.md §2). No inline styles. No invented class.
- Step 2, hard rule B0 (`project-bin/check-design-reaches-app.sh`, `docs/design-reaches-app.md`) — NOT RUN, no build or tools. Binding UNPROVEN.
- Page column: the task states no wireframe width cap and `ds.css` lists no page-column class. Gap flagged: if the wireframes cap `main`, a `.page-column` class must be promoted into `main.scss` and added to the page body containers. Not done here, because `main.scss` is out of scope.
- Step 3, gallery: no StyleGallery exists, so nothing to reuse. Fallback is the design-system classes above. The empty state uses the `empty-state` class. Status renders as the plain enum column: no badge component exists to reuse, and none was reimplemented.
- Step 4, cross-check:
  - Bindings match the task's column and field list, with `Last changed by` omitted (STOP #4).
  - Block separation: each section sits in a `card`.
  - Page scaffold: `ctnPageHead` has a breadcrumb plus exactly one `RenderMode: H1` on each page.
  - Spacing: every top-level section carries `spacing-outer-bottom-large`.
  - Empty state: the grid has one.
  - Response after a write: Save commits then closes the page, Cancel rolls back then closes the page, and New/Edit navigate.
  - Validation feedback: no required or unique fields were specified, so none is added. No VAL_ microflow was requested, so none is invented.
  - Conditional visibility: none used.
  - Class carrier: classes sit on CONTAINER, DYNAMICTEXT and LINKBUTTON. `breadcrumb-link` on a LINKBUTTON follows the task's class list, and its carrier is unverified because ds.css was not read.
  - Computed class names: no DynamicClasses.
- Accessibility floor: one H1 per page, visible labels on all inputs, no images.

**STOP-table check (learned-mdl-preflight.md), every row against the planned operations:**
- #1 (visible/editable inside customContent): not hit. The only customContent column holds one button with no expression.
- #1b (`Editable:`): not used.
- **#4 (AutoChangedBy binding): HIT. The requested "Last changed by" column bound to system `changedBy` is not written. STOP flagged.** Alternative per the row: omit it, or bind `AutoChangedDate`. The date column was not added unprompted. See the notes.
- #12 (ContentParams): all dynamictext content is quoted literals, none bound.
- #14 (narrowing a grant): not applicable, only new grants are written.
- #16 (CurrentUser XPath): not applicable.
- #18 (workflow): not applicable.
- #21 (DROP+CREATE of a shared document): no `drop`. All six microflows and both pages are new and owned by this script.
- #22 (idempotence): every create uses `create or modify` (microflows) or `create or replace` (pages). No bare `alter entity ... add attribute`, no bare `CREATE ASSOCIATION`.
- #23 (`mxcli diff -p <app>.mpr 10-orders-pages.mdl --format struct`): NOT RUN, no tool access. Must run before exec to confirm none of the six microflow or two page names already exist.
- #24 (DesignProperties): none used.
- #25 (loop, more than 20 activities, list from list): not applicable.
- #26 (DG2 association column): written unquoted as `Order_Customer/Name`. The module-qualified form was not used because the row's example is the unqualified form; unverified.
- #28 (changing a microflow near a return): not applicable, all microflows are new.
- Gotchas:
  - `refresh` is placed at the end of the statement.
  - GRANT roles are module-qualified.
  - No `elseif`.
  - No `mdl 1;` header.
  - Unquoted association binding on the combobox is the same convention as #26.

**Final self-check re-read** against the table: no conditional visibility in customContent, the one association path is unquoted, no unprefixed association steps in expressions (there are none), no `Editable:`. Done by reading only. `mxcli check --references` — NOT RUN.

**UI cross-reference block:**

```
UI cross-reference:
  Wireframe:       design/wireframes/order-overview.html, order-newedit.html [NOT READ as files - transcription in the task used]
  Design system:   design/ds.css [NOT OPENED] - classes used: page-header, page-title, breadcrumb, breadcrumb-link, breadcrumb-current, card, empty-state, spacing-outer-bottom-large (Atlas utility)
  Gallery example:  none - no StyleGallery exists
  Components reused: none needed
  Reuse skipped:    none (no gallery component exists)
  Empty states:     yes - dgOrders has an empty-state container reading "No orders yet."
  Gaps / MCP fallbacks: STOP #4 - Last changed by column not built. Page column class unknown. No MCP fallback needed.
  Shell check:      bin/check-page-shell.sh - NOT RUN, no tool access
  Fidelity score:   page-fidelity.js - NOT RUN, no tool access (docs/PAGE-FIDELITY.tsv not written)
  Class promotion:  self-audit diff - NOT RUN, no tool access
```

### REPORT

```report
scripts: 1
operations: 16
studio_pro_ops: 0
stops_flagged: 1
checks_not_run: 9
open_questions: 1
```

Notes for the main session:

- **Script:** `mdlsource/10-orders-pages.mdl` creates 6 microflows (`NAV_Home`, `NAV_Order_Overview`, `ACT_Order_New`, `ACT_Order_Edit`, `ACT_Order_Save`, `ACT_Order_Cancel`) and 2 pages (`Order_Overview`, `Order_NewEdit`). The 6 microflows carry `folder 'Orders/Microflows'` and the 2 pages `Folder: 'Orders/Pages'`. Each is followed by its grant to `Sales."User"`. Operations: 8 creates and 8 grants. Nothing needs Studio Pro or MCP.
- **Open question and STOP #4 (for the product owner):** the "Last changed by" column was not built. Binding a widget to the system `changedBy` member passes `mxcli check` and then fails `mx check` with CE1613. Options:
  1. Ship without the column. This is what the script does.
  2. Show `changedDate` ("Last changed") instead, which binds cleanly.
  3. Add a stored String attribute, for example `"LastChangedByName"`, set in `ACT_Order_Save` from `$currentUser/Name`. This needs a domain-script change.
  My recommendation is option 3 if the user's name is the requirement, otherwise option 2. The brief listed no open questions, so this is new, and the module brief and BRD should be updated once the owner decides.
- **Checks not run (9):**
  1. `mxcli check --references`.
  2. `mxcli diff --format struct` (STOP #23).
  3. `check-page-shell.sh`.
  4. `page-fidelity.js`.
  5. The class-promotion diff.
  6. `check-design-reaches-app.sh`.
  7. The Step 0 `impact` / `callers` / `DESCRIBE PAGE`.
  8. The dispatch log line (`.claude/loop/dispatch/Sales/scripts.tsv`, which cannot be written without a write tool outside the output path).
  9. Reading the wireframe, ds.css and brief files.
  The exec is also not run, as instructed.
- **Unverified syntax risks.** Written from the skills and CLAUDE.md summaries; each needs `mxcli check` before exec.
  - The microflow `folder '...'` placement before `begin`.
  - Page-level `Params: { ... }`.
  - The `EmptyPlaceholder: { ... }` block on the data grid.
  - The `database from ... sort by ... desc` data-grid source.
  - `ShowContentAs: customContent` with a nested action button.
  - Combobox `DataSource` and `CaptionAttribute`.
  - `DataSource: $Order` on the data view.
  - `$currentObject` as the microflow argument inside the row button.
  - The association column path `Order_Customer/Name`.
  - Status as a plain radio group bound to the enumeration.
- **Forward reference.** `NAV_Order_Overview` and `ACT_Order_New` / `ACT_Order_Edit` show pages created later in the same script. `Overview -> NewEdit -> Overview` is a cycle, so one forward reference cannot be avoided. If `exec` refuses it, split the script and use a `Stub:` page for the first, scored with `--stub`.
- **Behaviour choices.** New order: `ACT_Order_New` creates an uncommitted object and Save commits it. Cancel rolls it back, which discards a new object. No validation microflow was added, because no required or unique fields were specified.
- **Page column.** Possible gap, see PREFLIGHT.
