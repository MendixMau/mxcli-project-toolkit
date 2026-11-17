# Interaction Model — Who Lands Where, and What Object Each Page Is About

**Applies to:** migration | requirements-driven | POC | change an existing app (any project that draws wireframes)
**Purpose:** Before the first wireframe, write down how each role reaches each page and which object
each page is about, so the wireframes, the build and the journeys all start from one page-parameter
contract instead of one persona looking at one record.
**Upstream:** the CONFIRMED role model (Stage 3 ④), BRD `pages` / `useCases` / user tasks, the
Screen Inventory (`design-artifacts.md` Step 2).
**Downstream:** every wireframe's `wf-contract` block (`design-artifacts.md` Step 3), page scripts
(`ui-preflight-pages.md`), journeys and seed data (two objects, two roles).

---

## When to reach for this

- **Stage 3, after the role model is CONFIRMED and before the first wireframe** — the artifact is
  `design/interaction-model.md`.
- Adding a page that shows **one** object (a detail, an edit form, a process step, a task page).
- Adding a navigation menu item, a home page, or a "go to the next step" button.
- A microflow is about to be a page's data source and its name says *Current*, *Active*, *Latest*
  or *First*.

---

## Why this exists

Every check after Stage 3 compares the build with the wireframe. A wireframe drawn as one role
looking at one record hides a page that shows "the first open record" instead of the clicked one.
In one app built with this toolkit (2026-10), 8 pages did exactly that, all 6 roles shared one
home, and 3 of 6 menu items were process stages — while Stage 3/4 gates, page fidelity, lint and
a 69/69 e2e run (one seeded record) all passed. Adding the parameter later breaks every
`show page` already calling the page without one, so it is decided here.

---

## Step 1: Role homes

One row per role in the CONFIRMED role model:

| Role | Home page | Comes to do |
|---|---|---|
| Reviewer | `Review_Inbox` | Work through the reviews waiting for them |
| Manager | `Order_Overview` | Find an order and follow it |

The default home is the role's **inbox** if it has user tasks, otherwise its main object list.
Six roles sharing one home is a finding to raise with the user, never a default.

## Step 2: Inboxes and object hubs

- **Every BRD user task or approval** → an inbox row: which role, which inbox page, how rows are
  grouped, and what a row opens. The row opens the task page **with its object**.
- **Every object people follow over time** (an order, a case, a change) gets a hub page that takes
  that object as its parameter. Process steps are reached **from the hub**, never from the menu.

## Step 3: The per-page table (the contract)

One row per screen in the Screen Inventory, no exceptions:

| Page | How reached | Page parameter / context object | Data view source | Nav entry | Role(s) |
|---|---|---|---|---|---|
| `Order_Overview` | menu; home for Manager | none — list page | grid: database `Sales.Order` | Orders | Manager |
| `Order_Detail` | row of `Order_Overview`; row of `Review_Inbox` | `Sales.Order` | page parameter | — | Manager, Reviewer |
| `Order_Review` | stage tile on `Order_Detail` | `Sales.Order` | page parameter | — | Reviewer |
| `AppSettings_Edit` | menu | none — singleton | microflow `DS_AppSettings_Get` (one row by design) | Settings | Admin |

Write the parameter column as `Module.Entity` or `none — <reason>` (list page, home, singleton),
exactly as the wireframe's `Page parameter:` line carries it.

Rules the table must satisfy:

1. **A page about one object takes that object as a page parameter**, and its root data view's
   source is that parameter. A named singleton (settings, "my profile") is the one exception;
   say so in the row.
2. **"How reached" names every caller**, and every caller passes the object. A menu item cannot
   pass a page parameter, so a page whose Nav entry is filled in has `none — …` in the parameter
   column.
3. **Menu items are object lists, inboxes or tools — never a process stage.** One navigation per
   concept: a stepper on the hub *or* the menu, not both.
4. **Lists:** one main grid per page. Sibling sets go in tabs with counts, other objects in link
   cards.

Then copy each row's parameter, "How reached" and role into that screen's `wf-contract` block
(`design-artifacts.md` Step 3), so the wireframe carries the contract the build is checked against.

---

## The failure modes this table prevents

Each was measured in a built app; each passed every gate. Generic names below.

| Failure | One-line bad example | What it does |
|---|---|---|
| Parameterless "current/first" root data view | `retrieve $Order from Sales.Order where Status != Closed sort by Number asc first;` as the data view source of `Order_Detail` | With two open orders, every user sees the first one, whichever they clicked |
| `show page` without its argument | stepper tile action `show page Sales.Order_Review;` on a snippet that has `$Order` in hand | The stepper on order B opens the step for order A |
| Home pages not matching the design | `home page Sales.Order_Overview for` all six roles, while the design said reviewers land on their inbox | The reviewer has no place to start; their work is reached through a stage in the top bar |
| Process stages in the menu | top bar: Orders, **Reviews**, **Approvals**, Reports | Each stage page is forced to be parameterless (rule 2), which brings back failure 1 |
| Grid min-width | `.order-grid table { min-width: 1280px; }` added to fix squashed columns | Horizontal scrollbar at 1440 px on a grid that would have fitted; nothing else flags it |
| Read-only drawn but not specified | wireframe row `Read-only: yes` with no rendering | Built as grey disabled inputs; say "renders as text" (data view `ReadOnlyStyle: Text`) |
| Save reopens its own page | inline cell `OnChange` → `close page; show page Plan_Edit(Plan = $Plan);` | Every edit jumps the user back to the top; a save must not close and reopen its own page |

---

## Step 4: Walk it with two objects and two roles

Before the Stage-3 ✋, walk the prototype (`design/prototype.html`) with **2+ open objects and 2+
roles** — a paper walk over the per-page table unless the wireframes actually draw two records: as each role, start at its home, find the work for the **second** object, and complete
one step. Write the route taken under each role in `design/interaction-model.md`. A route that
goes through "the first one" or through a menu stage is a defect in the table, fixed here.

## Done when

- Role homes: **N of N roles** in the role model have a row.
- Inboxes: **N of N BRD user tasks / approvals** have an inbox row, or a reason they need none.
- Per-page table: **N of N screens** in the Screen Inventory have a row; every one-object page names
  its parameter; every "How reached" caller passes it.
- The walk: one recorded route per role, for the second object. "Not walked" is legal only as
  an open question in `PROJECT.md`; silence is not.

Ask the user the questions this raises — who lands where, how each role finds its work — in the
Stage-3 batch (`interview-protocol.md`). The layout question (top bar or sidebar) is not the
navigation question.
