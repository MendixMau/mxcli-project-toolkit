# Process Map: Where Each Question Fits in the Work
**Name:** this is the app's business process, drawn from its BRDs. It is not the progress report, which shows the toolkit's own stages.
**Applies to:** migration, requirements-driven build and existing-app change. Two passes: a draft at Stage 2 close (processes and question pins, no screens yet), the full map at Stage 3 once the wireframes exist.
**Requires:** Node 18 or later (no packages). Windows: Git Bash, same commands.
**Purpose:** Draw one swimlane map per business process. Each step sits in the lane of the person or system that does it, shows the wireframe it happens on, says what the system does between screens, and carries a pin for every open question and ASSUMED decision about that moment. A reviewer who cannot place "Should a rejected order go back to draft?" in a list of sixty can answer it on the map.
**Upstream:** BRDs (Stage 2, mandatory: `useCases`, `openQuestions`, `pages`); `design/wireframes/*.html` (`design-artifacts.md` Step 3, mandatory at Stage 3); the `PROJECT.md` decisions table (every checkpoint); optionally a consolidated questions file the project already keeps.
**Downstream:** `checkpoints/checkpoint-architecture.md` (CAC-3 shows pass 1); `checkpoints/checkpoint-design.md` (CAC-4 uses it; pass 2 is walked at the Stage 3 gate); `bin/gate-check.sh` check_stage_3 (fails a map older than its model, anchors or wireframes); `journey-proof.md` (a process on the map is a journey to prove).
**Companion:** `architecture-blueprint.md` Step 3d (journey diagrams; the map is the screen-level version of the same picture and discharges the optional `swimlanes` artifact); `assemble-prototype` (the map links each step into `design/prototype.html` when it exists).
**Source:** field run on a requirements-driven rebuild POC, 2026-10-16. The reviewer said of the question list: "I really don't understand where in the process they fit." Result there: 9 processes, 73 steps, 102 pinnable items, 48 placed mechanically, 54 by review, 19 of those in a whole-app bucket, 0 unplaced.

---

## When

Two passes over one model. The hand work (Steps 1 to 3) happens once, at Stage 2 close; Stage 3 only re-runs the script.

- **Pass 1, Stage 2 close.** Right after the BRDs validate and the open questions are consolidated, before they are raised with the user. Author the model and the anchors, build the map. With no wireframes in `design/wireframes/`, `validate` allows a step to name a screen that is not drawn yet (shown as a label with "No wireframe yet") or to have no `page`; a step in a role lane is still a person step (a solid card), only steps in system lanes or marked `kind: system` are dashed automatic cards. As soon as one wireframe exists the strict rules apply again. This is the moment the reviewer has to answer the questions, so this is when they need to see where each one fits. The draft is also input for Stage 3: the processes and lanes feed module boundaries (`modularize-domain.md`), the journeys (`architecture-blueprint.md` Step 3d) and the screen list (`design-artifacts.md`).
- **Pass 2, Stage 3.** After the wireframes, set `page` on any step that gained a screen, re-run `anchor` for new questions and `build`. No re-authoring. The Stage-3 gate checks this pass (map present and not older than its model, its anchors or any wireframe).

Do it when any of these hold:

- the BRDs carry more than about ten open questions, or the register more than about ten ASSUMED decisions;
- more than one role touches the same record (an approval, a hand-over, a queue);
- the reviewer is a business owner, not a builder.

Skip it for a one-screen app or a project whose questions are all closed. Record the skip as one line in `PROJECT.md`.

## Where the map shows up

- **Stage 2.** `bin/brd-report.sh` draws the pass-1 map at the top of `analysis/brd-report.html` (it calls `process-map.js build --embed`, the same renderer, so nothing is copied). Under it the report lists every requirement (use case) and every open question or assumption with the steps it is about. A click on a step filters that list to its rows; a row on no step stays under "whole app". This page replaced `docs/open-questions.html`. The report needs no extra step: re-run it after `anchor`.
- **Stage 3.** `design/process-map.html` (the full map, with screens) sits beside the wireframes. `assemble-prototype.js` adds a "Process map" link to `design/prototype.html` whenever `design/process-model.json` exists, and the map's header has a "Wireframes" button back to the prototype. The progress report links to both.

## Inputs and outputs

| File | Who writes it | Notes |
|---|---|---|
| `design/process-model.json` | you, Step 2 | the processes, lanes and steps. The only hand-authored input. |
| `design/question-anchors.json` | `process-map.js anchor` plus you, Step 3 | where each item is pinned. Path is `model.anchors` if set. |
| `design/process-map.html` | `process-map.js build`, Step 4 | generated, never hand-edited, self-contained, light and dark. |

The script is `project-bin/process-map.js` (installed into a wired project's `bin/`). When the project `bin/` has no copy (an older or scratch project), call it by its toolkit path, `node <toolkit>/project-bin/process-map.js`. Run it from the project root or pass `--project`. For the nested layout (`analysis/<name>/design/`), pass `--model analysis/<name>/design/process-model.json`; outputs go next to the model.

## Step 1: Find the processes

Read the BRD use cases and the blueprint journeys. A process is one piece of work with a start and an end that a business person would name: "submit an order and get it approved", "report a fault and follow it up". Usually 4 to 10 for a small app. Keep a process to at most 10 to 12 steps; a longer one reads better split in two. Every use case must end up on a step or in `standalone` with a reason. Lookups, exports and settings screens that belong to no flow go in `standalone`.

Rule of thumb for dashboards and exports: they are steps inside the process that produces the data, unless they have their own actor and their own trigger. Then they are a process of their own. A screen reached from several flows is a step in the most used flow.

## Step 2: Write design/process-model.json

```json
{
  "schema": "process-model/1",
  "app": "Order desk",
  "questions": "<path to the consolidated questions file>",
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
- **Steps**: `kind` is `task` (a person on a screen; needs `page` once wireframes exist), `system` (the app does it, no screen), `decision` (needs two or more `next` outcomes, each with a `label`) or `end`. Default: `task` when `page` is set or the lane is a `role` lane, else `system`.
- **page** resolves against the wireframes by `data-mx-page` (`Module.Page`), then `design/wireframes/PAGE-MAP.tsv` (short name, tab, file; for wireframes without `data-mx-page`), then the filename stem. The error names what was tried. A page with no wireframe is an error; set `"wireframeMissing": "<reason>"` when that is a recorded decision, and it becomes a warning.
- **useCases** are `"<BRD id>:<use case id>"`. The part before the colon is the BRD's `id` field. When the use case ids carry their own prefix, it is `"F004:UC-F004-01"`. An unknown one is an error.
- **next** may point into another process (the card shows "continues in"). A step that loops back draws a dashed edge over the top.
- **col** is the column. It counts up by itself; set it only to line steps up (two lanes in the same column) or to leave a gap. Two steps in one lane and column is an error.
- **actions**, **status**, **does** and **events** are what the reviewer reads as "what happens". Use microflow names in `actions`: they are also the strongest anchoring signal.
- **questions** (optional): a consolidated questions file (look under the analysis questions folder; omit the key when the project keeps none), an array or `{ "questions": [...] }` with `cid`, `title`, `question`, `blocking`, `assumption`, `risk`, `askWho`, `sources: [{ "brd", "id" }]`. Without it, each BRD open question is its own item.
- **register** (optional, default `PROJECT.md`): any table with a Decision and a Status column. Rows whose status says ASSUMED become decision items. Expect many of them to be build plan and environment decisions; most end in a global bucket.
- **What each state looks like.** A BRD question shows as answered (green, with the answer on the row and the card), as assumed and consented (teal, with who agreed), as assumed and waiting for confirmation (purple), or as open (amber, red when it blocks the build). A consolidated question takes its state from the BRD questions it lists: answered only when every one is answered. The header counts only what is still open; answered and decided items get their own tile, and the "Open only" filter hides them.
- **CONFIRMED register rows are shown as decided, on purpose.** They appear green in the "Decided in the project register" group at the bottom, so a reviewer sees what is settled. They are never pinned to a step and never need an anchor, so they add nothing to the unanchored count.
- **ignorePages** (optional): a list of wireframe pages (`Module.Page`, short name or filename) that are layout sketches, not screens. They need no step and do not trigger the "wireframe on no step" warning. A name that matches no wireframe warns. On an existing app the wireframe index and the navigation pages usually belong here.
- **brdDirs** (optional): the folders that hold the `*.brd.json` files. Default search: `analysis/knowledge-base/brd`, `analysis/*/knowledge-base/brd`, `knowledge-base/brd`. A use case not found lists the folders searched; set `brdDirs` when yours is elsewhere.

Write titles as plain verbs a business owner says: "Approve or reject?", not "ACT_Approve". Microflow names go in `actions`, behind the technical details click.

Run `process-map.js validate` until it reports 0 errors. When most errors share one cause (BRD path or page names) it prints one `CAUSE` line with the fix first; apply that, then re-run. Read every warning; a wireframe on no step usually means a missing step.

## Step 3: Anchor every question and assumption

```bash
node bin/process-map.js anchor          # derive, keep judged entries, write the anchors file
node bin/process-map.js anchor --json   # the still-unanchored items as skeletons to fill in (pure JSON on stdout, status lines on stderr)
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
- Standard bucket names for global items, so the whole-app list stays short: `Build plan`, `Hosting and operations`, `Security`, `Data`, `Scope`, `Look and feel`, `App structure`. ASSUMED register rows about build, environment, security, data or scope usually land here.
- Use a global bucket only for items about the whole app or the way of working (hosting, build plan, look and feel, app structure). Global is allowed and counted, never hidden; the map groups them by bucket and collapses each group, so use the standard names (39 globals on an existing app then read as seven short groups, not a wall).
- `basis` is one plain sentence; the reviewer sees it as "Placed by review (...)".
- The fingerprint ties the judgment to the item text. When the item is reworded, the judged entry is dropped with a warning and the item is unanchored again, so a stale placement never survives silently.

Judged entries go into the `anchors` array of the anchors file, next to the derived ones. The skeletons from `anchor --json` already carry `anchoredBy: "judged"` and empty `targets`: fill `targets` and `basis` in place and keep `id`, `kind` and `fingerprint` (`text` can go).

`anchor` prints `carried over: N judged from <file>`; a project whose model still points `anchors` at an old path runs `process-map.js migrate` once: it moves the entries to `design/question-anchors.json`, keeps the old file as `*.bak` and rewrites the model key.

Re-run `anchor` until it reports `0 unanchored`. `anchor` exits 1 while items remain; that is expected, not an error. `validate --strict` fails on any unanchored item.

## Step 4: Build

```bash
node bin/process-map.js build
```

Validates first and refuses on errors. Writes `design/process-map.html`: an index of process cards (a mini map of lanes, pin counts) plus the whole-app bucket, and one map per process. Rebuild after any change to the model, the anchors, a wireframe, a BRD or the register. `gate-check.sh` check_stage_3 fails when the map is older than `process-model.json`, `question-anchors.json` or the newest wireframe.

What the reviewer gets:

- red pin: open question that blocks the build; amber: open question; violet: an assumption to confirm;
- click a step: the wireframe large, a link to the screen full size and into the clickable prototype, what happens next, and each question as Question, We assume, If wrong, Ask; the use cases and microflows sit behind "Technical details";
- click a pin or a list row: the question card with links to every step it sits on;
- "Blocking only" hides the rest.

## Step 5: Verify by looking

A clean validate proves the data, not the picture. Screenshot the index and at least the two busiest maps, then open the PNGs and read them as the reviewer would.

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"   # Linux: google-chrome
B="file://$PWD/design/process-map.html"
shot() { perl -e 'alarm 120; exec @ARGV' "$CHROME" --headless=new --hide-scrollbars --virtual-time-budget=8000 "$@"; }   # Linux: timeout 120
shot --window-size=1800,1400 --screenshot=/tmp/map-index.png "$B#/"
shot --window-size=3000,1300 --screenshot=/tmp/map-P1.png "$B#/P1"
```

Use `--virtual-time-budget` and wrap the call in a timeout as shown. Never use Chrome's `--timeout` flag: it made the run hang past two minutes. A process above 12 steps is scaled to fit its box (down to 50%); a wide one with fewer steps scrolls sideways inside its own box, never the page. Screenshot at 1440 for a long process and at 3000 for a wide one (validate warns above 12 steps: split the process).

Use `--headless=new`: the old headless mode often paints the wireframe thumbnails blank. Check:

- every arrow reads as the real order (no line that seems to enter the wrong card);
- decision labels are readable and sit on their own branch;
- thumbnails show the screens;
- the busiest step does not carry ten pins (split the step, or the question is too broad);
- titles make sense to someone who has never seen the BRDs;
- dark mode (`--force-dark-mode`) is readable.

Fix the model or the anchors, rebuild, look again. Do not open the map for the user unasked; give the path.

## Gate

At the Stage 3 gate close-out (Stage 3 has no closing checkpoint; pass 1 was shown at CAC-3), walk the map process by process: blocking pins first, then the assumptions. Record each answer in `PROJECT.md` (CONFIRMED, or ASSUMED with the user's delegation), rebuild, and note the map path in the close-out block.
