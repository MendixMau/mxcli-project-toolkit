# What MDL cannot express — find out at design time, not at build time

**Applies to:** any mxcli project.

**Purpose:** a short list of things a Mendix design routinely calls for that **mxcli's MDL
cannot write**, and a 60-second probe that answers "can I build this?" before a wireframe
promises it. Read it when a design names a widget, or when a page script hits a parse error
that looks like a syntax mistake and is actually a missing capability.

**Why this exists (2026-08-31, a dashboard-publishing migration).** Two of that build's three
central screens shipped with labelled gaps, and both were discovered at **build time, after the
wireframes were signed off, the BRDs were written, the architecture was decided and the
microflows behind them were finished and gate-clean**. Neither was a modelling mistake. Both
would have taken four minutes to find at Stage 3, when the design was still cheap to change.

---

## The list

| The design says | MDL offers | Status |
|---|---|---|
| A **file upload** control | nothing. `mxcli syntax page.widgets` prints the complete keyword set and there is no `filemanager`/`fileuploader`/`imageuploader` in it — `filemanager fm (…)` is a parse error, not an unknown property | ⛔ **not buildable** |
| A **pluggable widget with a list-valued property** (an HTML element's `attributes`, a chart's `series`, a datagrid's `columns` written by hand) | nothing. On v0.20.0 a pluggable widget takes **scalar properties in parens and no body at all**: `pluggablewidget '<id>' <name> ( tagName: 'div' )` parses, and *every* body form is rejected with `mismatched input '<keyword>' expecting '}'` — the object-list keywords (`attribute`, `event`) and the child-slot keywords (`tagcontentcontainer`) alike | ⛔ **not buildable** |
| A page-level **boolean a button toggles** (a collapsible section, a show/hide) | page `variables:` exist and can be READ by `visible:`, but nothing in MDL writes one — that needs a nanoflow | ⛔ **not buildable** |
| A **gallery empty-placeholder** | no `emptyState`/`emptyplaceholder` block on `gallery` (`datagrid` DOES have `emptyplaceholder`) | ⚠️ **workaround**: a one-attribute non-persistent entity the page switches on |
| An **aggregate over an association** inside a gallery/listview template | client expressions have no `count()`; XPath does, but a template expression is not XPath | ⚠️ **workaround**: denormalise, with ONE writer that recomputes rather than increments |
| A **pluggable widget you want to configure** | only its scalar properties, and **case-sensitively** — `ItemSelectionMode` fails where `itemSelectionMode` works, even though the rest of MDL is case-insensitive | ⚠️ works, read the widget's own doc |

## The probe — four minutes, at Stage 3

Run these against the real project before a wireframe commits to a control:

```bash
./mxcli syntax page.widgets                       # 1. the COMPLETE widget keyword set
./mxcli widget init -p <app>.mpr                  # 2. generate docs from the project's own .mpk files
ls .ai-context/skills/widgets/                    # 3. every pluggable widget you can actually place
grep -n 'Object Lists' .ai-context/skills/widgets/<w>.md   # 4. does it need a list property?
```

Step 2 is the one people skip. It writes one file per widget **from the .mpk that is really in
the project**, including its full property table, its child slots and its object lists. A widget
that is not in that directory is not placeable, whatever the Mendix documentation says: the
platform's FileUploader parses fine as a `pluggablewidget` and fails at exec with
`no definition for widget com.mendix.widget.web.fileuploader.FileUploader`, because it is
Studio-Pro-bundled and appears in `widget init`'s own "skipped (built-in)" count.

**Step 4 is the one that matters most**, because a widget with an object list is exactly the
case that parses and then fails. If the doc has an "Object Lists" section and you need those
properties, MDL cannot configure it.

## What to do when the answer is "cannot"

The temptation is a workaround that renders something. Resist it where the workaround changes a
property the design chose deliberately — that is how a security decision gets undone by a
convenience.

> **The generated widget docs will tell you the opposite. Do not believe them — probe.**
> `mxcli widget init` writes `app/.ai-context/skills/widgets/<widget>.md` for every widget the
> project has, explicitly for an agent to read, and for a pluggable widget those files carry an
> **MDL Example**, a **Child Slots (curly-brace blocks)** table and an **Object Lists (repeating
> child entries)** table — all showing `PLUGGABLEWIDGET '<id>' widget1 { attribute item1 … }`.
> On v0.20.0 not one of those keywords parses. The doc is authoritative-looking, written for you,
> and on disk from the first `widget init`.
>
> This cost two sessions on one build: the first concluded "not buildable" from guessed syntax
> (and a wrong widget id — `...widget.custom.htmlelement...` for `...widget.web.htmlelement...`,
> which makes mxcli answer `no definition for widget`, which reads as "not available"); the
> second read `htmlelement.md`, believed the feature was available, announced it, and had to
> retract after four probes. **The right conclusion was reached twice by the wrong route.**
>
> So: the four-minute probe below is not optional when a generated doc disagrees with you, and
> `mxcli diff -p <app>.mpr <probe>.mdl` is how to run it — read-only, no exec, no snapshot risk.
> Filed upstream as `bug-logs/pending-github-issues/widget-init-docs-do-not-parse.md`.

The field case: a sandboxed HTML frame (`iframe` + `sandbox="allow-scripts"`, deliberately no
`allow-same-origin`) was unbuildable because the widget's `attributes` is an object list. But
`tagContentMode: 'innerHTML'` is a plain scalar property — it parses, and it would have rendered
the uploaded dashboard the same afternoon, **same-origin inside the Mendix page, where the
uploaded document's JS could call client APIs as the signed-in user.** That is precisely the
regression the architecture decision had rejected when it turned down a plain iframe.

So the page shipped an explicit "not available yet" state instead. **Visibly incomplete beats
invisibly unsafe**, and the difference is only visible to whoever knows what the workaround
traded away — which is why it goes in the script header and the register, not in a commit
message.

Three rules for the blocked case:

1. **Say it on the screen.** A labelled gap ("File picker not yet wired — see build plan row
   16b") is a defect a user can report. A control that looks real and does nothing is a defect
   they blame themselves for.
2. **Make it a row, and make it BLOCKED — not failed, not passed.** In a journey harness, a
   blocked step naming the row that blocks it keeps the gap in every test report. Collapsing it
   into "passed" claims capability the app lacks; into "failed" blames the model for a missing
   widget.
3. **Say what IS built.** Both field blockers had everything behind them finished and proven —
   validation, storage, access checks, the file bytes actually in Mendix's file store. Recording
   "blocked" without that reads as "not started", and the next person rebuilds it.

## Related

- `learned-detection-gaps.md` — the register of things that pass a rung and fail later; the
  `item …` parse-then-exec-fail case is one of its shapes.
- `learned-mcp-patterns.md` — CLI, MCP and hand-rolled are **three co-equal write modes**. Every
  ⛔ above is a CLI-mode limit; MCP or Studio Pro clears them. A build that uses one mode for
  everything pays this list in full, and that is a choice worth making on purpose.
- `ui-preflight-pages.md` Step 4 — "flag an element MDL cannot express before drafting" is the
  instruction; this file is the list that makes it actionable.
