# Stuck items: ask, record, re-measure

Use when an item cannot be upgraded as it is. A decision here never closes a check: it moves the item from "needs a
decision" to "decided, pending <closes by>". The check closes only when the gate measures its rung PASS or PASS* again.

## Triggers
- a RED localedits module on the plan (SKILL stop rule); a stepupdate kept module or a data-bearing idcheck finding
- convertcheck or repair leaves a Java action that no longer compiles; vendorjava COMMENTED-OUT or EMPTIED
- dojo_report "can't move"; a replacement_check row still hitting a deprecated module
- widgets UNRENDERED, or a widget crash on the new client
- a REGRESSION still open after two repair attempts on the same page

Not triggers: INVALID from missing inputs (fix the measurement), a first-seen regression (repair first), REVIEW pairs
(accept-file judgement, READING-THE-VERDICT.md section 4).

## Options per kind (at most 4, plus "something else")
| kind | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Marketplace module | keep old version (kept list) | replace with the Marketplace equivalent (`replacements.tsv` row) | rebuild locally, drop the module | hand to a named person |
| page / snippet | keep as converted, accept the look (PASS* path) | rebuild with the new widgets | remove if dead (`impact_map`) | hand to a named person |
| widget (.mpk) | keep old package, accept the risk | swap to the successor (`dojo-successors.tsv`) | rebuild as pluggable / native | hand to a named person |
| Java action / vendor Java | keep old jar, pin | port to the new API | replace with a Marketplace module or a microflow | hand to a named person |

Widget swap, properties with no counterpart: map every property the source widget had; for the rest run `bin/widget_defaults.py --widget <target> --mapped <list>` and commit the swap with its `--commit APP --subject ... -- <paths>` form. Rows verified `doc` or `manifest` in `playbooks/widget-config-defaults.tsv` are applied and written into the commit subject as `defaulted: <property> = <value> (best practice|widget default, <source>)`, which `bin/changelog.py` shows in CHANGES.md; `unverified` rows are listed as "not defaulted" and left at the widget's own value. The closing count line (table rows, mapped, defaulted, unverified) is the denominator: paste it in the decision.

## Asking
One question per item, with the options above and the evidence path in the question. On Claude Code use AskUserQuestion;
on any other harness print the same as a numbered markdown list ending "5. something else". Either way end the turn and
wait. Recommending an option from the evidence is fine; choosing silently is not. UNATTENDED runs keep the existing
default (keep at the old version) and record it ASSUMED.

## Pattern catalogue (playbooks/rearchitecture.md)
Before asking, look for an RA entry for the item: bin/proposal.py already cites it in section 3 (`[RA-n, status]`). Ask with that
entry's options and recipe. When the owner answers **rebuild** or **replace** (options 2-3), the run, in the same commit as the
DECISIONS.md line:
- an RA entry exists: update it. Add the app code name, the decision id (S-n / P-n), the result and the date to `evidence`, and move
  `status` (idea -> tried once after one run; tried once -> proven after a second run or a gate that measured it). Fix `options` or
  `recipe` where the run found them wrong. Never raise a status without a run.
- none exists: append `### RA-<next n> <title>` with the fields in the file's entry format (topic, match, trigger, why, options,
  recommendation, effort, recipe, evidence, status, cards) as `tried once` (or `idea` before any run), and a FEEDBACK row.
- no company or customer names; apps by code name. Line format of the record in DECISIONS.md gets the id at the end:
  `... | CONFIRMED | closes by: <rung> | RA-3`

## Record
`$W/DECISIONS.md`, one line per item, append-only:

`S-1 | widgets: Viewer3D.mpk | widget | swap to successor | <reason> | <who> | CONFIRMED (or ASSUMED) | closes by: widgets rung PASS`

- A kept item stays listed as "kept (S-n)" in every later report; a kept module is never reported as upgraded.
- The progress line never reads DECISIONS.md.
- Owner sign-off cannot close while DECISIONS.md holds an ASSUMED line or a hand-off with no name. Only a person writes APPROVED.

## Step records
Every item above is a step in `$W/steps.jsonl` (`S-n`; a plan item keeps its `P-n` as an alias, see [propose.md](propose.md)). An answer is also the approval of that step:
- `decisions.py add --item S-n --choice approve|reject --by NAME --source chat` (or the P-n with its option key) writes the ledger row and the step approval together. `decisions.py import` does the same for page rows, and a second import adds nothing.
- A step answered this way is not changed by a later plan sign-off. An `assumed` approval (unattended) is replaced by a person's answer.
- The sign-off row is still never added from chat.

## Choice or log (which D row becomes a step the owner must see)
Every row of AGENT-DECISIONS.md is one of two kinds. Decide before you open anything.
- **A choice**: the agent picked between real alternatives that change what the app does, what users see, or what it costs. Signals: the row names options or alternatives, says "instead of", "chose", "kept", "dropped", "replaced", "removed", or changes a screen, a login, a widget or a module version. Examples: jQuery scripts bridged or rewritten, keeping the SSO login page, the heal policy, keeping a module at its old version. A choice is a step with an `assumed` approval and is the only thing that becomes an open "Needs your OK" topic.
- **A log**: everything else. A finding, a tool error, a mishap, a retry, a routine module bump, a count, an observation, a test-side fix. A log never opens a step of its own. Write the parent step in the row (`| D71b (agent, log) S-14 | ... |`), so the text becomes evidence on that step. When no step fits, the log joins the one roll-up step of the run. A log has no buttons and no open topic: its step is `approved` by the agent with source `routine`.
- Unsure? Ask yourself: if the owner never read this row, could the app end up different from what they would have wanted? Yes means choice. `python3 $B/steps.py kind --title "<row title>" --choice "<the choice column>"` prints `choice` or `log` with the same rule the legacy import uses.
- Words on the page: the step title, the finding and the proposal are plain words (`steps.plain`). A title says WHAT is being chosen, starts with a capital and is never a bare module name or a decision id. Use a template from the kind plus the subject ("Keep or update module OIDC", "How to keep the Atlas_Web_Content style edits", "Seed data for the journeys"); when nothing better exists, "A choice about <topic>". `steps.py open` and `propose --new` refuse a bare name or a decision id as a title. A row whose own text is technical (file names, error output, version arrows) gets such a title, and the raw row goes into `--evidence`, behind the toggle.
- One topic is one step. A second choice about the same subject (the same module, widget or page) joins the open step instead of opening another.

## Mid-run decisions (the agent decides on its own)
A **choice** the agent makes during a run, outside the stuck-item list above, is a step too (a log is not: see Choice or log). Example: the agent moves 88 jQuery scripts into
JavaScript actions because the new client cannot run them. Written only as a D row in AGENT-DECISIONS.md, the owner never sees it as a topic.
- Every D row names its step id: write `S-n` in the row (for example `| D71 (agent) S-14 | ... |`). A follow-up row such as D71b may leave it out.
- No step yet: open one in the same command that records the decision, with plain words in `--found` and `--say`:
  `python3 $B/steps.py propose --work $W --new --topic scripts:HTMLSnippet --title "jQuery scripts on the new client" --found "The new client cannot run 88 jQuery scripts." --say "Run each script from a JavaScript action." --why "Same behaviour at the lowest cost." --option "Bridge now (recommended)" --option "Rewrite as widgets" --recommend 0 --decision D71`
  It prints the new `S-n`. The approval is `assumed` by the agent: the step stays an open topic until a person answers it (`decisions.py add --item S-n`, above).
- Then write the D row with that `S-n`, and pass the same `S-n` to the commits that do the work (`appcommit.sh --step S-n`, upgrade.md).
- `python3 $B/steps.py check --work $W` fails a D row that names no step, or a step that does not exist ("MISSING D71: the agent decided ..."). A log row passes when it names its parent step.
