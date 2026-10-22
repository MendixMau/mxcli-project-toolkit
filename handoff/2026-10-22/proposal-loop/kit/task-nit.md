# Task — two small changes arrive mid-build (lead session, Stage 5, module Sales)

You are the **lead** session: the one talking to the user. You dispatch helpers, run gates and
ask the user. It is Stage 5. The Sales module is part-way built. Draft only: you cannot run
anything. Describe this turn exactly as you would carry it out.

## Where the build stands

- `mdlsource/10-orders-pages.mdl` is applied. It built `Sales."Order_Overview"` and
  `Sales."Order_NewEdit"`. Both pages got a LOOK. The screenshots are
  `tests/screens/order-overview.png` and `tests/screens/order-newedit.png`. Their fidelity rows
  are in `docs/PAGE-FIDELITY.tsv` (91% and 88%).
- Wireframes: `design/wireframes/order-overview.html` (route `order-overview`) and
  `design/wireframes/order-newedit.html` (route `order-newedit`). Both were approved at the
  Stage 3 gate. `design/prototype.html` is assembled from them.
- `mdlsource/11-orders-submit.mdl` is applied. It holds `Sales."SUB_Orders_SubmitReady"`, which
  loops over a list of orders and gives validation feedback on any order with no customer or a
  total ≤ 0.
- The `PROJECT.md` excerpt in your context pack is the current register. The last change request
  is CR-11.
- Session: Claude Code on the web (cloud). `CLAUDE_CODE_REMOTE=true`. There is no browser and no
  `open`/`xdg-open` on this machine. The user reads the chat.

## The user just typed this in chat

> Two small things. Rename the "Order date" column header on the orders overview to "Ordered on".
> And the submit microflow should log a warning line for every order it rejects, so we can see
> them in the logs.

## Project facts (there is no live model — these ARE the model; do not ask for more)

- Mendix 11, mxcli v0.26.0. You may NOT run any tool, open any file, or query a model. Where your
  skills tell you to run something, list it under ACTIONS as `- run <command>` and say what it
  would show. Never claim it ran.
- Project convention: **quote every identifier** in MDL.
- `Sales."Order"` (persistent): `"OrderNumber"` String(20), `"OrderDate"` DateTime, `"Status"`
  enumeration `Sales."ENUM_OrderStatus"` (`Draft`, `Submitted`, `Shipped`), `"TotalAmount"`
  Decimal, `"Note"` String(500).
- Log node for this module: `Sales`.

## Required output format (all five sections, in this order, with these exact headings)

1. `### CHAT` — exactly what you post to the user this turn. If you would ask a question
   (in Claude Code through `AskUserQuestion`), write the question and its options here as text.
2. `### ACTIONS` — every file you create, update or delete this turn, one per line, as
   `- create|update|delete <project-relative path> — <why>`, and every command, as
   `- run <command> — <why>`. Write `- none` if there are none.
3. `### NEXT` — one line: what happens after this turn, and whether you wait for the user first.
4. `### MDL` — only if you draft MDL this turn: the script in ONE fenced block opened with
   ```` ```mdl ````. Otherwise write `none this turn`.
5. `### REPORT` — a fenced block opened with ```` ```report ```` holding exactly these keys, one
   per line: `questions: <n>` · `new_html: <n>` · `updated_html: <n>` ·
   `waits_for_user: yes|no` · `mdl_drafted: yes|no`.
