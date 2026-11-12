# Processes (example)

E2E-16. One block per user process: what a user does end to end, in their own words, with the outcome that proves it
worked. `bin/draft_processes.py` writes `status: draft` blocks; a human edits them and sets `status: confirmed`;
`bin/process_journeys.py` compiles the confirmed ones into journeys (one leg per role) that run on the old app first
and then on the new one. This example is illustrative: app, roles and captions are invented.

Format, per block:

- `## <ID>: <name>`: the ID (P01, ...) names the journeys (`proc-p01-01`, ...) and the plan row (`process:P01`).
- `status:` `draft` | `confirmed` | `dropped`. Only a human writes `confirmed`.
- `roles:` the roles that act, comma separated, as named in the app's security.
- `source:` where the process comes from: `model: ...`, `manual: <file> §<section>`, `interview: <file> §<heading>`.
- `steps:` numbered, one action each, `[Role]` in front when the process has more than one role:
  - `Open "<menu item>"` the navigation menu;
  - `Click "<caption>"` a button, link, card or row action; the caption, widget name or the page it opens must match
    ONE action the role may run, or pin it with `=> <action id>` (from actions.json);
  - `Fill "<attribute or widget>" with "<value>"` / `Select "<value>" in "<attribute or widget>"` typed into the form
    of the next click;
  - `Confirm` the confirmation dialog of the step before; `Start on the home page` nothing to click.
  - A step left as `=> ?` (with its `candidates:` line) is not resolved: the process is INVALID until someone picks.
- `expect: <Module.Entity> where <Attr> = "<value>" [and ...]` the row that must exist afterwards (the data rung,
  COUNT = 1). A value carries `${RUN_ID}` and is typed by a step, so a row an earlier run left cannot pass it.
  `expect text: "<text>"` adds a text that must show on the last screen.
- `park: <n> after leg <k>[, ...]` a fixture, not a check (PR-F33): before the second-pass journeys run, walk legs
  1..k n more times so n workflow instances wait for the roles that act after leg k, then assign each waiting task
  whose only target is one user to that user. Use it when the app's task pages need a task waiting for the role
  (each Approve / Reject / Unassign journey uses one up). n is 1..20; k is any leg of the process, the last one included.
- `notes:` free text.

## P01: Raise a purchase request
status: confirmed
roles: Requester
source: interview: interview-notes.md §Top 5 daily tasks item 1
steps:
1. [Requester] Open "My requests"
2. [Requester] Click "New request"
3. [Requester] Fill "Description" with "Toner ${RUN_ID}"
4. [Requester] Select "Office supplies" in "Category"
5. [Requester] Click "Submit"
expect: Purchasing.PurchaseRequest where Description = "Toner ${RUN_ID}" and Status = "Submitted"
notes: what breaking looks like: "the request stays in Draft and the manager never sees it"

## P02: Approve a purchase request
status: draft
roles: Requester, Manager
source: manual: user-guide.md §4.2 Approving requests (line 88)
steps:
1. [Requester] Open "My requests"
2. [Requester] Click "New request"
3. [Requester] Fill "Description" with "Chairs ${RUN_ID}"
4. [Requester] Click "Submit"
5. [Manager] Open "Approvals"
6. [Manager] Click "Approve"  => ?
   candidates: Purchasing.Request_Approve.approveButton | Purchasing.Task_Inbox.approveButton
expect: Purchasing.PurchaseRequest where Description = "Chairs ${RUN_ID}" and Status = "Approved"
notes: the manager's list shows the oldest request first; leg 2 clicks the first row (see steps/journeys.md)
