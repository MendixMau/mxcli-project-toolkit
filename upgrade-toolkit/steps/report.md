# Step 6: report (grade and history)

The gate reports PASS, FAIL, INVALID and explicit exceptions such as EXCEPT or PASS (except ...). The report records the upgrade delivered, bugs found and fixed, verification
coverage and the human handoff. Keep the machine verdict as evidence; explain the app outcome in plain language.

1. **Gate summary.** `gate.sh` writes `gate-summary.md` and, as its last act, runs `bin/grade.py gate-summary.md --stamp`:
   one `Grade:` line right under `Overall:`, and the same line on the console. The grade sits next to the verdict word and
   never replaces it. A failing grade.py never changes the verdict or the exit code.
2. **Findings the gate did not see.** A crash found by hand or by a probe after a clean gate goes into
   `grade-notes.tsv` next to `gate-summary.md` (tab separated: `rung, bucket, owner, text`; bucket `waiting`,
   `untestable` or `open`). A note can only lower a rung, never raise one. Rung `-` adds an open item without touching a
   rung. The finding must also become a gate rung or probe (BACKLOG #111).
3. **History.** `bin/grade.py gate-summary.md --history FILE --run ID --app "<generic name>" --path "A > B" ...` adds or
   updates the row of that run id in FILE (columns: date, run id, app, Mendix path, toolkit commit, duration, gate verdict,
   grade, regressions found/fixed, kept modules, open items, lesson prefix). The pipeline calls it at the end of the gate
   step (`record_grade` in `bin/cloud/upgrade-pipeline.sh`) and writes to the run-local `$WORK/history-row.md`, never into
   the toolkit checkout (runs use a pinned, detached toolkit worktree). `UPG_HISTORY` chooses another file; `UPG_RUN_ID`
   and `UPG_APP_NAME` set the run id (default: the gate's own run id) and the app name (default: "unnamed app"). Run the same command again with the columns the pipeline cannot
   know (duration, regressions, lesson prefix): it updates the row in place and keeps what you do not pass.
   **The row reaches `runs/HISTORY.md` through a toolkit PR, with a generic app name, made by the person or the
   orchestrator.** Use a code name such as "field app F1"; no customer app name goes into the repo.
3b. **Run log.** At the end of the gate step the pipeline runs `bin/runlog.py --work $WORK`, which appends one row to
   `FIELD-RUNS.md` (the permanent run log: code names only, `not recorded` for anything the folder does not hold, a duplicate
   run id or a customer name is refused, and so is a row with no app code name). Set `UPG_APP_CODE` (or `UPG_APP_NAME`) and
   `UPG_APP_TYPE` to code names before the run; commit `FIELD-RUNS.md` and `CHANGES.md` through a toolkit PR (the pipeline prints
   that reminder). A refusal or failure never changes the gate verdict or the exit code: the reason is printed, written as a
   `Run log:` line in `gate-summary.md` and as an information section in `NEEDS-JUDGMENT.md`. The row has two timing columns,
   "run time (machine)" and "person wait", from `$WORK/state/timing.tsv`; the same numbers are the `Time:` line of
   `gate-summary.md`. Quote them in the report; `not recorded` means the run has no timing file.
4. **Metadata only.** The history holds no app content, screenshots or logs.
5. **Open and pending work.** `grade.py` lists every rung that is not done with an owner: `person` (a decision or a look),
   `customer` (their systems, keys, licence) or `toolkit` (an open regression, or an instrument that did not measure).
   Copy that list into the run's report.
6. **Upgrade completion and bugs.** For each requested version target, give a delivery status (`COMPLETED`,
   `COMPLETED WITH HANDOFF`, `IN PROGRESS` or `BLOCKED`), exact source and target versions, branch or commit, build and
   start evidence, changes made, and data-preservation findings. List each confirmed upgrade bug with its repair and
   recheck, each baseline defect separately, and each accepted exclusion with the owner's decision. Apply the completion
   rules in [PLAN.md](../PLAN.md#upgrade-completion-and-handoff-strategy). Missing test access by itself is not an app
   regression. A real unresolved blocker, unproven data loss, or an unbuilt target prevents a completion claim.
7. **Human handoff, required even when empty.** Use [templates/upgrade-handoff.md](../templates/upgrade-handoff.md).
   For every remaining check or decision, name the feature and role, exact steps and expected result, what was tried,
   evidence, the unmet prerequisite, the owner and what will close the action. State "No remaining human checks" only
   when supported. Attempt full coverage and available instrument or fixture repairs before handing work off. Name
   real-service tests still needed after stand-in tests. Keep pending owner sign-off explicit.
8. **Across-session summary.** Group attempts by stable app identity and preserve their run IDs and outcomes. Report
   attempts per app, version paths attempted and completed, bugs found and fixed, and specific remaining checks.
   Deduplicate repeated observations of the same bug. State which sessions and evidence sources were audited; do not
   present a partial branch inventory as the complete history. Keep upgrade-completion, verification and owner-closure
   counts separate. Record unknowns instead of deriving success from build results or a zero-FAIL count.

How the buckets are defined: [READING-THE-VERDICT.md](../READING-THE-VERDICT.md) section 6.

## Cockpit page

`bin/cockpitpage.py` writes one self-contained `COCKPIT.html` for the run (the pipeline hook `cockpit_regen` calls it).
Layout, top to bottom: the header with the app name on the left and the version route on the right (one chip per
version: done green, current amber, next grey, each with its gate). Below it two columns. The main column holds the
readiness strip of 12 chips, the legend, the matrix (rows grouped App and platform, Steps of this run, Testing setup and
Go-live; columns Triage, Plan, Upgrade and Test), the test health panel and the feed. The counts by kind (upgrade items
done, regressions, problems resolved, tested, things that need you) sit folded above it. The right column is a sticky
sidebar with the result: the headline, "items closed successfully" with its chips, and "open topics still to validate"
with group and owner per topic. Under 1000 px wide the sidebar moves above the matrix. The matrix is the page: the
result never pushes it below the fold. The generator never decides: every verdict is copied from a run file, and a
missing file shows a grey "Not yet" cell, never a pass. Every non-green cell shows a proposed solution box (Found,
Proposed, Trying, Fixed), or "No proposal yet" when none is known. Purple "needs you" cells are real owner decisions only.

Rows come from the run files (runtime, modules, local edits, Java, findings, regressions, decisions, sign-off, outside
systems, click paths, self-heal). The 12 chips are source, test database, outside systems, login, brokers and messaging,
seed data, click paths, unreadable modules, test users per role, files and storage, target environment, backup and way
back. Broker, files, target and backup stay grey "not checked" unless the items file says otherwise.

The optional file `work/cockpit-items.json` is merged over the derived rows and chips:

```
{
 "items": {
  "<row id>": {
   "key": "<derived row id this entry is the same item as; optional>",
   "name": "...", "sub": "...", "group": "app|setup|golive",
   "kind": "upgrade|testgap|owner|golive (optional; default derived, also allowed on ready chips)",
   "cells": {"triage|plan|upgrade|test": {"status": "ok|wait|bad|you|none", "label": "...", "steps": ["..."],
                                          "late": false, "deploy": false}},
   "triage_missed": false, "seen_as": ["<words a triage file uses for this item>"], "decisions": ["D53"],
   "loop": "Found|Proposed|Trying|Fixed (or 0 to 3)",
   "problem": "...", "proposal": "...", "steps": ["..."], "result": "...", "help": "...", "learn": "..."
  }
 },
 "ready": {
  "<chip id>": {"status": "ok|wait|bad|none", "label": "...", "row": "<row id>", "loop": "...", "problem": "...",
                "proposal": "...", "steps": ["..."], "result": "...", "help": "...", "learn": "..."}
 },
 "feed": [{"time": "2026-01-03T08:00:00Z", "text": "..."}],
 "kpi": {"closed": [{"n": 7, "label": "..."}], "open": [{"group": "Your call", "text": "...", "owner": "you"}], "hide": ["text part"]}
}
```

The optional file `work/cockpit-trail.json` fills the drawer with what happened per action, stage by stage:

```
{"rows": {"<row id>": [{"name": "...", "sub": "...", "status": "done|open|gap",
  "stages": {"triage|plan|upgrade|test": {"say": "plain words for a person", "why": "...", "who": "...", "options": ["..."],
             "facts": ["..."], "results": [["what", "pass|fail|partly|gap", "detail"]], "gap": false,
             "proof": [{"kind": "text|quote|decision|commit|image", "src": "...", "text": "...",
                        "h": "<sha>", "d": "<date>", "s": "<commit subject>"}]}}}]}}
```

A row with a trail shows its actions instead of the single proposal box; an unknown row id is dropped. The proof sits
behind a toggle; `say` stays free of code and file names. On the Plan column the drawer also shows the proposed plan for
that topic, read from `PROPOSAL.md` (its P-n items and their status), with the whole plan one click further. This file is
the input for runs without step records (`STEP-RECORDS-PLAN.md`).

When `work/steps.jsonl` exists, the cockpit reads it instead: every step is one row in the group "Steps of this run" (found, plan with its
approval, changes, test), and the drawer shows what was found, what was proposed and why, the approval, the commits and the test result,
with the proof behind a toggle. An approval that is only `assumed` reads "Needs your OK" and is listed under open topics as "Your call";
a step with no passing test for a rung it closes by reads "Test gap". The open-topic count on the sign-off item comes from the steps, not
from `AGENT-DECISIONS.md`. `cockpit-trail.json` and `AGENT-DECISIONS.md` are then not read for the drawer and the count. A missing
`steps.jsonl` changes nothing; a damaged one (a line that is not an event, or a record without a commit sha or a test verdict) is
reported as one open topic "To fix" and the page is built from the older inputs.

The result sidebar is derived, never typed: the headline and regressions from the build rung, "items closed successfully" as the sum of
non-overlapping counts (upgrade problems, test gaps, fixes, then the release, journeys, apis or rest, and const rungs of gate-summary.md; a
missing rung drops out), and "open topics still to validate" from the matrix (purple cells are "Your call", open deploy cells "At deploy",
other open cells "Coverage", red ones "To fix"). An open topic is listed once: when the same row and cell text is open
on more versions of a ladder run, the versions are merged into one line ("... (Mendix 10.24.28, 11.12.7)"). Under
"Your call" the cell text "Needs your OK" is dropped, since the group already says it. `kpi.closed` replaces the count of a chip with the same label or adds one, `kpi.open`
adds topics, `kpi.hide` drops chips or topics whose text contains a given part. The page is written as HTML by the generator, so it
reads without JavaScript; `cockpitpage.py --standalone` wraps it for a file opened directly.

An id (or the optional `key`, alias `matches`) that names a derived row or chip overrides only the fields given, so one item is one
row. An unknown id creates a new row, placed right after the entry declared before it in the same group, so declared order holds.
`triage_missed` turns empty Triage and Plan cells into the dashed "Not flagged" only when no triage or plan file mentions the item
(the key, the id or a `seen_as` word); otherwise they read "Seen in triage" and "In the plan". `decisions` lists agent decision ids whose latest titles are added to the Test cell steps. An item triage saw is never called missed: its
Plan cell shows the plan, the ledger answer or the agent decision that handled it. The gate's `open regression N` is the tile; an open
REGRESSION line in the agent decisions becomes a red row with its options as the proposal. Apis and release cells read their counts from the gate rows.
Open questions from the decision
ledger show as a purple cell on the item they belong to, closed ones only in the feed. The page uses the system font stack and
makes no external request. "Not needed" is shown only where a stage does not apply.
The regressions tile is the gate's `open regression N`; when it is 0, an older decision or judgment entry for the test stage shows
as resolved, not as a question. Decisions are made on this page.
`triage_missed` draws the dashed red outline (triage should have caught it). Chip ids: source, testdb, outside, login,
broker, seed, clicks, unreadable, users, files, target, backup. The feed shows the newest 8 entries together with run
events. Controls: `cockpit-matrix-*` in `controls/run-controls.sh`.
