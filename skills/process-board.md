# Process Board: Where Each Question Fits in the Work
**Applies to:** migration, requirements-driven build and existing-app change, at Stage 3, once the wireframes exist.
**Requires:** Node 18 or later (no packages). Windows: Git Bash, same commands.
**Purpose:** Draw one swimlane board per business process. Each step sits in the lane of the person or system that does it, shows the wireframe it happens on, says what the system does between screens, and carries a pin for every open question and ASSUMED decision about that moment. A reviewer who cannot place "Should a rejected order go back to draft?" in a list of sixty can answer it on the board.
**Upstream:** BRDs (Stage 2, mandatory: `useCases`, `openQuestions`, `pages`); `design/wireframes/*.html` (`design-artifacts.md` Step 3, mandatory at Stage 3); the `PROJECT.md` decisions table (every checkpoint); optionally a consolidated questions file the project already keeps.
**Downstream:** `checkpoints/checkpoint-design.md` (CAC-4 walks the questions on the board); `bin/gate-check.sh` check_stage_3 (fails a board older than its model or anchors); `journey-proof.md` (a process on the board is a journey to prove).
**Companion:** `architecture-blueprint.md` Step 3d (journey diagrams; the board is the screen-level version of the same picture and discharges the optional `swimlanes` artifact); `assemble-prototype` (the board links each step into `design/prototype.html` when it exists).
**Source:** field run on a requirements-driven rebuild POC, 2026-10-16. The reviewer said of the question list: "I really don't understand where in the process they fit." Result there: 9 processes, 73 steps, 102 pinnable items, 48 placed mechanically, 54 by review, 19 of those in a whole-app bucket, 0 unplaced.

---

## When

Run it at Stage 3 after the wireframes are drawn and before the Stage-3 gate interview, when any of these hold:

- the BRDs carry more than about ten open questions, or the register more than about ten ASSUMED decisions;
- more than one role touches the same record (an approval, a hand-over, a queue);
- the reviewer is a business owner, not a builder.

Skip it for a one-screen app or a project whose questions are all closed. Record the skip as one line in `PROJECT.md`.

## Inputs and outputs

| File | Who writes it | Notes |
|---|---|---|
| `design/process-model.json` | you, Step 2 | the processes, lanes and steps. The only hand-authored input. |
| `design/question-anchors.json` | `process-board.js anchor` plus you, Step 3 | where each item is pinned. Path is `model.anchors` if set. |
| `design/process-board.html` | `process-board.js build`, Step 4 | generated, never hand-edited, self-contained, light and dark. |

The script is `project-bin/process-board.js` (installed into a wired project's `bin/`). Run it from the project root or pass `--project`. For the nested layout (`analysis/<name>/design/`), pass `--model analysis/<name>/design/process-model.json`; outputs go next to the model.

## Step 1: Find the processes

Read the BRD use cases and the blueprint journeys. A process is one piece of work with a start and an end that a business person would name: "submit an order and get it approved", "report a fault and follow it up". Usually 4 to 10 for a small app. Every use case must end up on a step or in `standalone` with a reason. Lookups, exports and settings screens that belong to no flow go in `standalone`.

## Step 2: Write design/process-model.json

```json
{
  "schema": "process-model/1",
  "app": "Order desk",
  "questions": "analysis/questions/consolidated.json",
  "anchors": "design/question-anchors.json",
  "lanes": [
    { "id": "requester", "label": "Requester", "kind": "role" },
    { "id": "approver", "label": "Approver", "kind": "role" },
    { "id": "system", "label": "System", "kind": "system" }
  ],
  "processes": [
    { "id": "P1", "title": "Order approval: submit, approve or reject, notify",
      "summary": "One plain sentence a business owner recognises.",
      "steps": [
        { "id": "P1-01", "lane": "requester", "title": "Fill in and submit the order",
          "page": "Orders.Order_NewEdit", "useCases": ["F001:UC001"], "actions": ["ACT_Order_Submit"],
          "status": "Draft", "next": ["P1-02"] },
        { "id": "P1-02", "lane": "system", "kind": "system", "title": "Check and store the order",
          "does": "Validates the amount and sets the status to Submitted.", "next": ["P1-03"] },
        { "id": "P1-04", "lane": "approver", "kind": "decision", "title": "Approve or reject?",
          "next": [ { "to": "P1-05", "label": "Approve" }, { "to": "P1-06", "label": "Reject" } ] }
      ] }
  ],
  "standalone": [ { "useCase": "F001:UC005", "reason": "Nightly job, no screen, on no flow." } ]
}
```

Rules the validator enforces:

- **Lanes**: `kind` is `role`, `system`, `scheduled` or `external`. One lane per role from the Stage-3 role model, one for the app, one per scheduled job or outside system that acts on its own.
- **Steps**: `kind` is `task` (a person on a screen; needs `page`), `system` (the app does it, no screen), `decision` (needs two or more `next` outcomes, each with a `label`) or `end`. Default: `task` when `page` is set, else `system`.
- **page** resolves against the wireframes by `data-mx-page` (`Module.Page`), else the short name or the filename. A page with no wireframe is an error; set `"wireframeMissing": "<reason>"` when that is a recorded decision, and it becomes a warning.
- **useCases** are `"<BRD id>:<use case id>"`. An unknown one is an error.
- **next** may point into another process (the card shows "continues in"). A step that loops back draws a dashed edge over the top.
- **col** is the column. It counts up by itself; set it only to line steps up (two lanes in the same column) or to leave a gap. Two steps in one lane and column is an error.
- **actions**, **status**, **does** and **events** are what the reviewer reads as "what happens". Use microflow names in `actions`: they are also the strongest anchoring signal.
- **questions** (optional): a consolidated questions file, an array or `{ "questions": [...] }` with `cid`, `title`, `question`, `blocking`, `assumption`, `risk`, `askWho`, `sources: [{ "brd", "id" }]`. Without it, each BRD open question is its own item.
- **register** (optional, default `PROJECT.md`): any table with a Decision and a Status column. Rows whose status says ASSUMED become decision items.

Write titles as plain verbs a business owner says: "Approve or reject?", not "ACT_Approve". Microflow names go in `actions`, behind the technical details click.

Run `process-board.js validate` until it reports 0 errors. Read every warning; a wireframe on no step usually means a missing step.

## Step 3: Anchor every question and assumption

```bash
node bin/process-board.js anchor          # derive, keep judged entries, write the anchors file
node bin/process-board.js anchor --json   # the still-unanchored items as skeletons to fill in
```

`anchor` places what it can prove (`anchoredBy: "derived"`), strongest signal first:

1. the question text names a microflow in a step's `actions`;
2. a use case lists the question in its `openQuestions`, or the text names a use case (`F002 UC005`) or a screen (`Order_Overview`, or `Module.Page` for one-word names);
3. a business rule that names the question lands in a use case; the question and a use case cite overlapping source lines; an ASSUMED decision names a question that is already placed.

Derived entries are recomputed on every run. For each item left over, and for any derived placement that is wrong, add a judged entry:

```json
{ "id": "F001:Q04", "kind": "question", "anchoredBy": "judged",
  "targets": [ { "type": "global", "bucket": "Money" } ],
  "basis": "Applies to every amount in the app",
  "fingerprint": "<copy from anchor --json>" }
```

- Targets: `{ "type": "step", "step": "P1-03" }`, `{ "type": "page", "page": "Order_Overview" }` (a screen on no step), or `{ "type": "global", "bucket": "Hosting and operations" }`.
- Pin to the step where the answer changes what happens. Up to three targets.
- Use a global bucket only for items about the whole app or the way of working (hosting, build plan, look and feel, app structure). Global is allowed and counted, never hidden.
- `basis` is one plain sentence; the reviewer sees it as "Placed by review (...)".
- The fingerprint ties the judgment to the item text. When the item is reworded, the judged entry is dropped with a warning and the item is unanchored again, so a stale placement never survives silently.

Re-run `anchor` until it reports `0 unanchored`. `validate --strict` fails on any unanchored item.

## Step 4: Build

```bash
node bin/process-board.js build
```

Validates first and refuses on errors. Writes `design/process-board.html`: an index of process cards (a mini map of lanes, pin counts) plus the whole-app bucket, and one board per process. Rebuild after any change to the model, the anchors, a wireframe, a BRD or the register. `gate-check.sh` check_stage_3 fails when the board is older than `process-model.json` or `question-anchors.json`.

What the reviewer gets:

- red pin: open question that blocks the build; amber: open question; violet: an assumption to confirm;
- click a step: the wireframe large, a link to the screen full size and into the clickable prototype, what happens next, and each question as Question, We assume, If wrong, Ask; the use cases and microflows sit behind "Technical details";
- click a pin or a list row: the question card with links to every step it sits on;
- "Blocking only" hides the rest.

## Step 5: Verify by looking

A clean validate proves the data, not the picture. Screenshot the index and at least the two busiest boards, then open the PNGs and read them as the reviewer would.

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"   # Linux: google-chrome
B="file://$PWD/design/process-board.html"
"$CHROME" --headless=new --hide-scrollbars --window-size=1800,1400 --virtual-time-budget=8000 --screenshot=/tmp/board-index.png "$B#/"
"$CHROME" --headless=new --hide-scrollbars --window-size=3000,1300 --virtual-time-budget=8000 --screenshot=/tmp/board-P1.png "$B#/P1"
```

Use `--headless=new`: the old headless mode often paints the wireframe thumbnails blank. Check:

- every arrow reads as the real order (no line that seems to enter the wrong card);
- decision labels are readable and sit on their own branch;
- thumbnails show the screens;
- the busiest step does not carry ten pins (split the step, or the question is too broad);
- titles make sense to someone who has never seen the BRDs;
- dark mode (`--force-dark-mode`) is readable.

Fix the model or the anchors, rebuild, look again. Do not open the board for the user unasked; give the path.

## Gate

At the Stage-3 interview, walk the board process by process: blocking pins first, then the assumptions. Record each answer in `PROJECT.md` (CONFIRMED, or ASSUMED with the user's delegation), rebuild, and note the board path in the close-out block.
