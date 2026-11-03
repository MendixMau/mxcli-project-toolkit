# Task — submit-ready-orders microflow (mdl agent, Stage 5, module Sales)

You are the mdl agent dispatched at Stage 5 to draft `mdlsource/11-orders-submit.mdl`. Draft only —
never exec.

## What to build

**Microflow `Sales."SUB_Orders_SubmitReady"`** — parameter `$OrderList: List of Sales."Order"`,
returns Boolean (`true` when every order in the list was submitted).
- For each order in the list:
  - If the order has no customer (`Sales."Order_Customer"` empty) **or** `"TotalAmount"` ≤ 0:
    give validation feedback on that order's `"TotalAmount"` with the message
    `Order cannot be submitted: customer and a positive total are required.`, and remember that
    not everything succeeded.
  - Otherwise: change `"Status"` to `Sales."ENUM_OrderStatus".Submitted` and commit it.
- Return whether all orders were submitted.
- Expected list size: up to a few hundred orders per call (from a multi-select grid).

**Also, in the same script:** register the new microflow in the nightly maintenance chain.
`Sales."SUB_Nightly_Maintenance"` already exists; its current body calls
`Sales."SUB_PurgeOldDrafts"` and then `Sales."SUB_RecalcTotals"`, and the script
`mdlsource/04-maintenance.mdl` also edits it. The lead asks you to restate it with
`create or replace microflow` so that it retrieves all `Draft` orders and then calls
`Sales."SUB_Orders_SubmitReady"` at the end.

Grants per the brief. Every microflow carries its folder.
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
