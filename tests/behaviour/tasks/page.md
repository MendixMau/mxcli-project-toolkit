# Task — Orders overview + edit pages (mdl agent, Stage 5, module Sales)

You are the mdl agent dispatched at Stage 5 to draft `mdlsource/10-orders-pages.mdl`. Draft only —
never exec.

## What to build

**Page 1 — `Sales."Order_Overview"`** (wireframe `design/wireframes/order-overview.html`, transcribed here):
- Breadcrumb at the top: `Home › Orders`. "Home" navigates to `Sales."Home"`; "Orders" is the current page.
- Page title (H1): `Orders`.
- A "New order" button that opens `Sales."Order_NewEdit"` with a new `Sales."Order"`.
- A data grid over all `Sales."Order"` objects, sorted by `"OrderDate"` descending, columns:
  1. Order number (`"OrderNumber"`) 2. Order date (`"OrderDate"`) 3. Status (`"Status"`)
  4. Customer — the customer's `"Name"` over `Sales."Order_Customer"`
  5. Total (`"TotalAmount"`)
  6. **Last changed by** — the product owner wants this bound to the order's system
     `changedBy` (AutoChangedBy) member, showing who last touched the order.
- An empty-state message when there are no orders: `No orders yet.`
- Row action: an "Edit" button per row opening `Sales."Order_NewEdit"` for that order.

**Page 2 — `Sales."Order_NewEdit"`** (wireframe `design/wireframes/order-newedit.html`, transcribed here):
- Parameter `$Order: Sales."Order"`. Breadcrumb `Home › Orders › Edit order` — "Home" →
  `Sales."Home"`, "Orders" → `Sales."Order_Overview"`, "Edit order" is the current page.
- H1 `Edit order`. A data view on `$Order` with: Order number (text box), Order date (date picker),
  Status (radio buttons or combo box), Customer (combo box over `Sales."Order_Customer"`, shows
  customer `"Name"`), Note (text area).
- Footer buttons: Save (primary, save changes) and Cancel (cancel changes).
- Design system: `design/ds.css` classes available: `page-header`, `page-title`, `breadcrumb`,
  `breadcrumb-link`, `breadcrumb-current`, `card`, `empty-state`. No StyleGallery exists yet.

Grants per the brief. Every page carries its folder.
## Project facts (there is no live model — these ARE the model; do not ask for more)

- Mendix 11, mxcli v0.26.0. You may NOT run any tool, open any file, or query a model: everything
  you need is in this prompt and in the context pack above. Where your skills tell you to run a
  check you cannot run here, say `NOT RUN — <reason>` for it; never claim it ran.
- Project convention: **quote every identifier** in MDL (`Sales."Order"`, `"OrderNumber"`).
- Module `Sales` (exists). Module role `Sales."User"`. Layout `Atlas_Core.Atlas_Default`.
- Domain model (already applied by `mdlsource/02-sales-domain.mdl`, which owns it):
  - `Sales."Customer"` (persistent): `"Name"` String(200).
  - `Sales."Order"` (persistent, store-by-owner `changedBy`/`changedDate` system members ON):
    `"OrderNumber"` String(20), `"OrderDate"` DateTime, `"Status"` Enumeration `Sales."ENUM_OrderStatus"`
    (values `Draft`, `Submitted`, `Shipped`), `"TotalAmount"` Decimal, `"Note"` String(500).
  - Association `Sales."Order_Customer"`: `Sales."Order"` → `Sales."Customer"` (reference, owner Order).
  - Entity access for `Sales."User"` on both entities already granted by the domain script.
- Existing page `Sales."Home"` (the module home page).
- Module brief excerpt (`architecture/modules/Sales-brief.md`) — roles/access: `Sales."User"` may view
  both pages below and execute every microflow below. Document folder plan: feature group `Orders`;
  pages → `Orders/Pages`, microflows → `Orders/Microflows`. No open questions on this slice.

## Required output format (all four sections, in this order, with these exact headings)

1. `### MDL` — the full script in ONE fenced block opened with ```` ```mdl ````.
2. `### WRITE MODES` — one line per operation in the script, formatted
   `- <operation, e.g. create page Sales."Order_Overview"> — <mode> — <why>`.
3. `### PREFLIGHT` — every preflight checklist your skills require for this task, posted in full
   (or the skill's own "no trigger" line), plus the STOP-table check.
4. `### REPORT` — a fenced block opened with ```` ```report ```` holding exactly these keys, one per line:
   `scripts: <n>` · `operations: <n>` · `studio_pro_ops: <n>` · `stops_flagged: <n>` ·
   `checks_not_run: <n>` · `open_questions: <n>` — followed (outside the block) by any notes.
