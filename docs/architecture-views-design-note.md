# Design note: architecture views over app-analysis facts

**Status:** proposal plus one working prototype. Nothing here is merged into `bin/app-report.sh` or
`project-bin/app-facts.sh`; the changes those two would need are written out below as diff shaped
proposals, not applied.
**Date:** 2026-09-16. **Branch:** `feat/app-analysis`.
**Question this answers, verbatim from the user:** *"can we based on this, make a proper architecture
diagram, dependency overview, module boundaries, bla bla, maybe even wireframes out of this? To align
it with our pipeline, or what makes sense? keeping in mind we want to continue DEV or is it too much
overkill? Maybe new wireframes are overkill, but arch can help, or what?"*

**Short answer.** One view is worth building and it is built (`bin/app-layer-map.sh`). Two more are
worth building once a fact we do not collect today exists. Four are not worth building, wireframes
among them, and the reasoning for each is below. The overall call is **not overkill, but only just**:
the toolkit currently produces facts nothing reads, and adding pictures nothing reads would be worse
than adding nothing. Every view below is therefore tied to a named stage and a named decision, and a
view with no decision behind it is rejected in this note rather than shipped and quietly ignored.

---

## 1. The test each view had to pass

Four questions, in order. A view that fails any one is rejected.

1. **Which named pipeline stage consumes it?** Stages are `P, 0, 1, 2, 3, 4, 5, 6, 7` from
   `skills/conversion-runbook.md` section 2, read through the per stage inversion table in
   `skills/existing-app-change.md`. "It would be nice to have" is not a stage.
2. **Which decision does a developer make differently because they saw it?** Not "understands the
   app better". A decision with two outcomes.
3. **Do the facts we already collect support it?** `inventory.json`, `dependencies.json`,
   `loops.json`, `manifest.json`, and nothing else. If not, exactly which fact is missing.
4. **Does it survive a refresh?** The dossier is a standing document
   (`skills/app-analysis.md`, "Refresh discipline"). A view that changes shape every run teaches
   people to stop looking at it.

A fifth constraint sits over all of them, from `skills/coverage-ledger.md`: **you never reverse
derive a requirement from the live model.** Every view here describes what the app IS. The moment a
view starts reading as what the app SHOULD be, it has to be adopted by a person at a Stage 3
checkpoint or it does not exist. That line is what separates a description from a fabricated
decision, and it is why the layer map's own skill file makes "no layering was ever declared" a
`manual` verdict rather than a `fail`.

---

## 2. Verdict table

| # | view | verdict | stage | the decision it changes |
|---|---|---|---|---|
| 1 | **Layer map**: computed stack order, only the edges that point back up, plus a cut ladder | **BUILD. Built, prototype below** | 3, and 0 for blast radius | which module does my slice really touch, and which edge is the first untangling PR |
| 2 | Module dependency graph, all nodes and all edges | **REJECT** | 3 | none. Unreadable at this size and unreadable is not a decision aid |
| 3 | **Entity ownership map**: which module's microflows write which module's entities | **BUILD LATER**, needs one new fact | 3 | is this boundary a real owner or a shared writable table |
| 4 | **Scheduled event reach map**: which flows run unattended and what they touch | **BUILD LATER**, facts exist but are not joined | 4, 6 | can this slice ship without a maintenance window |
| 5 | Wireframes of existing screens | **REJECT** | 3 | none. See section 5 |
| 6 | Domain model / entity relationship diagram | **REJECT at app scale**, allow per slice by hand | 3 | none at 799 entities |
| 7 | Layered "target architecture" diagram in the `architecture-blueprint.md` style | **REJECT for an existing app** | 3 | it fabricates a decision nobody took |
| 8 | Call graph of microflows | **REJECT** | none | 2,686 nodes, no stage asks |

---

## 3. The one that got built: the layer map

### The problem it had to solve

The probe app has 73 own modules, 293 edges between them, 5,385 references across those edges, and
**one strongly connected component containing 52 of the 73 modules**. Inside a strongly connected
component every module reaches every other. That has a hard consequence for drawing: there is no
arrangement of those 52 modules in which the arrows all run one way, so every layout of them is
equally correct and equally useless. This is why view 2 is rejected and why "just draw the
dependency graph" was never going to work. Any tool that draws it produces the same hairball.

It also has a consequence for the pipeline, which is worse. `skills/existing-app-change.md` tells you
that if the module you are changing sits in a tangle, the blast radius is the tangle. On this app
that instruction says the blast radius is 52 modules, which means the regression net is the whole
application, which means in practice that nobody builds it. **An unusable answer at Stage 0 is how
ground rule 1 gets skipped.**

### The move

Stop drawing the graph. Draw the **order**.

1. Compute the linear order of the own modules that puts as little reference weight backwards as
   possible: greedy feedback arc ordering (Eades, Lin and Smyth) followed by a sifting pass.
2. Set the backward edges aside and compute **levels** on what is left, which is by construction
   acyclic. Level is the longest path to a module with no outbound own module edge.
3. Draw the modules as rows, grouped by level. **Draw no forward edges at all**: the order already
   states them, and 231 lines that say what the row order says is the hairball again.
4. Draw only the backward edges, as arcs, weighted by reference count.
5. Under the picture, a **cut ladder**: for each module that sources a backward edge, what the
   largest tangle becomes if only its upward edges are set aside, and what it becomes cumulatively.

### What it found on the probe app, and why that changes the conversation

| number | value |
|---|---|
| dependency edges between own modules | 293 |
| edges that point back up the computed stack | **62** |
| modules that source those 62 edges | **25** |
| reference weight, total | 5,385 |
| reference weight pointing backwards | **343** |
| share of coupling weight already layered | **93.6 percent** |
| levels in the computed stack | 14 |
| largest tangle | 52 |

Two of those rows are the whole argument.

**93.6 percent already layered.** An app that reads as "one tangle of 52 modules, hopeless" is
actually a 14 level stack with 343 references out of 5,385 running the wrong way. That is not a
rewrite, it is a backlog.

**62 edges from 25 modules**, and one module, the app's central one, sources 19 of the 62. The cut
ladder then gives an ordered untangling backlog: setting aside that one module's upward edges takes
the largest tangle from 52 to 48, the next four take it to 27, and eight rows in it is 10. Every row
carries the reference count and the ref kinds, so a reader can tell a cheap cut (six references, all
`call`, a utility flow living one level too high) from an expensive one (thirty seven references
including `associate`, which is an ownership decision about the domain model and not a move).

That is the deliverable. "One tangle of 52" has no next action. "These eight edges, cheapest first,
and here is what each one buys" is a Stage 3 conversation and a Stage 4 build order.

### Why inline SVG and not Mermaid

`skills/architecture-blueprint.md` uses Mermaid everywhere, and for its purpose that is right: a
hand written diagram of a dozen target modules belongs in markdown, where it is diffable and the
markdown stays the source of truth. This view is not that, for four reasons.

1. **Rendering Mermaid needs Mermaid.** In an HTML page that means a CDN script tag, which is an
   external network call, or a bundled copy, which is a new runtime dependency of roughly 3 MB.
   `bin/app-report.sh` produces one self contained file with no JavaScript at all, and that property
   is why the page can be mailed to a stakeholder. Inline SVG keeps it.
2. **Mermaid lays out for you, and the layout IS the finding here.** The entire value of this view is
   that the rows are in a computed order and the forward edges are deliberately absent. Handing 73
   nodes to an auto layout gives back the hairball we started from.
3. **Determinism.** The page is refreshed at every milestone and the diff between two refreshes is
   supposed to be readable. A computed SVG changes only when the facts change.
4. **It survives.** No JavaScript means it prints, it works in an email client preview, and it works
   in five years.

The cost is honest: the layout code is about 60 lines of coordinate arithmetic in the renderer, and a
person cannot hand edit the diagram. Neither matters for a generated view over facts, and both would
matter for `architecture-blueprint.md`, which is why that skill keeps Mermaid.

### What it does when a fact is missing

Every degradation prints on the page rather than silently changing the picture, per the
`skills/app-analysis.md` rule that an omitted section reads as "nothing wrong here".

| missing | behaviour |
|---|---|
| `dependencies.json` | exit 2 with the message naming `bin/app-facts.sh`. There is nothing to draw |
| `inventory.json` | page renders, module size column blank, amber banner saying so |
| `manifest.json` | page renders, amber banner saying it cannot state how old the facts are |
| `scope.own_modules` | module set derived from the edges, amber banner saying a module with no edge at all is now invisible |
| `kinds` on an edge | the cell reads `not recorded` rather than being blank |
| `counts.largest_tangle` disagrees with the recomputed components | **red banner at the top of the page** saying neither number is usable until the instrument is checked. This exists because a join bug once zeroed the bidirectional pair count on 302 edges with everything reporting green |
| the graph is already acyclic | the arc gutter is empty, the cut ladder section is omitted entirely, and the lede says every edge already runs down the stack |

All six were exercised against invented fixtures, not against the probe app.

---

## 4. The two worth building later, and the facts they need

### View 3, entity ownership map

**The decision.** `skills/modularize-domain.md` says a boundary is earned by a bounded context, and
the clearest violation of one is two modules writing the same entity. Today the dossier can say
module A references module B some hundreds of times; it cannot say **who writes B's data**. A module that only
reads another's entities is a consumer, which is layering working. A module that writes them is a
co owner, and that is a boundary that does not hold. Those two look identical in every view we have.

**Why it is not built.** `dependencies.json` already carries `kinds` per edge, including `change`,
`create`, `delete` and `commit`, but only aggregated per module pair. To say "module A writes
`B.Order`" the fact has to be per target entity.

**Exactly what `project-bin/app-facts.sh` would have to add.** One more section in
`dependencies.json`, from the catalog the script already builds, no new mxcli call:

```json
"entity_writers": [
  {"entity": "B.Order", "owner_module": "B", "writers": [
     {"module": "A", "kinds": {"change": 41, "create": 3}},
     {"module": "B", "kinds": {"change": 180, "create": 22, "delete": 4}}]}
]
```

The query is the same join the script already does for `edges`, grouped by `r.TargetName` instead of
by target module, filtered to `objects.ObjectType = 'ENTITY'` and to the write ref kinds. Cost is one
extra SQL pass over `refs`, which is seconds. Collect it and this view is a table first and a diagram
only if the table is too long.

### View 4, scheduled event reach map

**The decision.** Stage 4 orders the build, Stage 6 signs off the test. Both need to know which of
the changed flows runs unattended, because a slice that touches a nightly job cannot ship the way one
that touches a button can. `skills/app-analysis.md` already weights "reachable from an enabled
scheduled event" at +2 in the severity table, so the pipeline already believes this matters.

**Why it is not built.** The facts exist and are not joined. `inventory.json` has 40 scheduled events
with their microflow and enabled flag. `loops.json` has `reachable_from_scheduled_events` per
microflow. Neither says which **modules** a scheduled event reaches, which is the unit the rest of
the dossier works in.

**Exactly what would have to change.** Nothing in `project-bin/app-facts.sh` if the reachability walk
is kept in the renderer: the transitive closure over microflow calls is already computed for
`loops.json`, it is simply not exported as a set. The cheapest fix is one added key per scheduled
event in `inventory.json`:

```json
{"QualifiedName": "X.SCH_Nightly", "Enabled": 1, "IntervalSeconds": 3600,
 "Microflow": "X.SE_Nightly",
 "reaches_modules": ["X", "Y", "Z"],
 "reaches_microflows": 37}
```

Then the view is a small matrix, scheduled events down the side, modules across the top, enabled ones
in a stronger colour. On the probe app that is 40 rows by 73 columns, which fits one screen, and the
answer to "does my slice touch the nightly path" becomes a glance instead of a trace.

**Correction, checked against the facts on 2026-09-16.** An earlier draft of this note said every
scheduled event on the probe app was disabled, and that the view would therefore render an empty
page. That is wrong. The probe app has 40 scheduled events of which 16 are enabled, and 8 loop
microflows carrying a real finding are reachable from an enabled one. So this view would render
with content on the first app we tried it on, and it ranks higher than this note first judged. The
caveat the skill must still carry is the opposite one: a disabled event is not the same as no
event, and the two must never be summed into a single reach count.

---

## 5. Wireframes: rejected, and the reasoning

The initial read was that wireframes are overkill because the app already has 448 working screens. I
tested that and it holds, but the strongest reason is a different one.

**The weak argument** is the one that came first: a wireframe of a screen that exists is a worse copy
of the screen. A person can open the app. That is true but it is not decisive, because a change slice
does redraw the screens it changes, and `skills/existing-app-change.md` Stage 3 already allows exactly
that: *"Wireframes only for screens that change"*. So the pipeline already has the right rule and it
already says no to the general case.

**The decisive argument** is that a generated wireframe cannot come from these facts without
inventing things, and what it would invent is the part that matters. `inventory.json` gives a page
count per module. It does not give the widget tree, the layout, the data source bindings or the
navigation. A picture built from a page count is a box with a name in it, which tells a reader
nothing they did not get from the number 448. To build a real one you would have to read every page
document, which is the `mxcli describe` path that already takes 230 seconds for 423 microflows and
would be far worse for 448 pages, and the output would be a redrawing of a screen anyone can open.

**The sharpest argument** is the one from `skills/coverage-ledger.md`. A wireframe is a specification
artifact. Generating one from the live model reverse derives a requirement from the implementation,
which is the exact thing the ledger forbids. A generated wireframe of an existing screen says "this
is what the screen should look like" on the sole evidence that this is what it does look like, and it
launders a fact into a decision. That is not an efficiency saving, it is a category error, and it is
the same reason view 7 is rejected.

**What to build instead, if screens ever become the question.** Not wireframes. A page inventory that
answers a decision: which pages bind to the entities my slice changes. That is a blast radius fact,
it belongs in view 3's family, and it needs the same per entity reference fact. Until somebody asks
that question with a slice in hand, build neither.

## 6. The other rejections, briefly

**View 2, the full dependency graph.** 73 nodes, 293 edges, one component of 52. Rejected on the
mathematics, not on taste: within a strongly connected component no layout can be right. Anyone who
asks for it should be shown the layer map instead, which is the same data with the unreadable 78
percent of the edges removed on purpose.

**View 6, a domain model diagram.** 799 entities. The same hairball argument, one order of magnitude
worse. Per slice, by hand, in Studio Pro, which already draws it. There is no version of this that a
generator does better than the tool the developer already has open.

**View 7, a target architecture diagram for an existing app.** This is the tempting one and it is the
one to refuse hardest. `skills/architecture-blueprint.md` Step 2 draws a layer diagram for an app the
pipeline is about to build, from boundaries a person signed off at a Stage 3 checkpoint. Generating
the same shaped picture from a live model inverts it: it would present a computed order as the
intended architecture, with no checkpoint, no sign off and no `CONFIRMED` line. The layer map is
deliberately drawn so it cannot be mistaken for this. It is labelled a reading, its skill file makes
"nobody declared a layering" a `manual` verdict rather than a `fail`, and adopting the computed order
is written up as a Stage 3 decision a person takes.

**View 8, a microflow call graph.** 2,686 nodes. No stage asks for it. `mxcli` answers the targeted
question directly, which is what `skills/query-the-model.md` is for.

---

## 7. Pipeline alignment

| stage | does an architecture view change what this stage does for an existing app | how |
|---|---|---|
| **Stage 0, Triage and Scope** | **Yes, and this is the largest single gain** | Stage 0 in this mode asks two questions and the second is the blast radius. Today the answer for a module inside a tangle is "the tangle", which on this app is 52 modules and is therefore ignored. The layer map replaces that with a list: the modules above yours that reach it, plus the sources of backward edges into it. That is the honest radius and it is small enough to build a regression net for. Nothing else in this note is needed at Stage 0 |
| **Stage 1, Analysis** | **No. This stage needs nothing** | Stage 1 is Path D, querying the live model into the knowledge base scoped to the slice. A picture of the whole app does not scope a query, and `mxcli` already answers the scoped ones. The one thing worth adding here is not a view at all: Stage 1 should record the facts run's `manifest.json` counts alongside the `SHOW ...` counts, so a reader can see the slice against the app. That is a sentence in the skill, not a diagram |
| **Stage 3, Architecture and Design** | **Yes, and it is the stage the view was designed for** | The Stage 3 row for this entry mode reads *"which existing module owns this, and does that still hold"*, with the instruction never to invent new boundaries. That is a check with no instrument behind it: `modularize-domain.md` is written for drawing boundaries and `architecture-blueprint.md` for documenting intended ones, and neither can check a live one. `skills/layering-review.md` plus the layer map is that instrument. The output is `LAYER-DRIFT` and `LAYER-SRC` findings that join the dossier's existing `DEP-*` findings and carry dispositions like everything else |
| **Stage 4, Build Plan** | **Weakly, and only through Stage 3's output** | Stage 4 orders the build, and its ordering constraint in this mode is that you cannot stub what is already live. A view does not change that. What the cut ladder does give Stage 4, once Stage 3 has turned rows into decisions, is a dependency order for the untangling slices, which is the same job `architecture-blueprint.md` Step 3 does for a greenfield build. Worth one line in `brd-to-build-plan.md`; not worth a new artifact |

**Stages P, 2, 5, 6 and 7 need nothing**, and saying so is part of the answer. Stage 2 writes BRDs for
the slice and a layering picture does not help write one. Stages 5 and 6 are the build loop and the
regression net, which are governed by module gates. Stage 7 is N/A in this entry mode already.

---

## 8. Overkill verdict

**Not overkill, on two conditions, and it would have been overkill without them.**

The user is right to ask, and the honest risk is not the cost of building a view. It is that the
toolkit already has a wiring problem here. A separate analysis of this branch established that
**nothing in the toolkit reads the dossier or `analysis/app-facts/*.json` except the renderer**, that
`existing-app-change.md` recomputes blast radius by hand from associations and a graph report,
duplicating what the facts already hold, that there is no delta between refreshes, and that there is
no eval scenario for the existing app path. Adding pictures on top of facts nobody reads makes the
unread pile prettier and larger. That is the failure mode to avoid, and it is a real one.

So the two conditions:

**One. The view has to be wired to the stage that already asks the question, not offered as an extra
artifact.** That is why `skills/layering-review.md` exists and is routed at stages 0 and 3, and why
this note spends more space on the Stage 3 row of `existing-app-change.md` than on the drawing. A
view routed nowhere is the eighteenth unrouted skill, and `bin/lib/skill-routing.tsv` exists because
that happened seventeen times.

**Two. It has to reduce, not add.** The layer map earns its place only because it deletes 78 percent
of the edges from the picture on purpose and turns an unactionable count into a named, ordered list.
Views 2, 6 and 8 fail exactly this test and are rejected, even though all three are easier to build
than the one that shipped. **Easy to generate and worth reading are unrelated properties**, and in
this problem they point in opposite directions.

**What to build instead of the rejected views, in order.** These are all higher value than any
further diagram:

1. **Make the existing facts readable by the change skill.** `existing-app-change.md`'s blast radius
   section walks associations and `mxcli graph-report` by hand, recomputing what `dependencies.json`
   already holds. Point it at the facts and at the layer map. This is a documentation change with no
   new code and it is the highest value item on the list.
2. **A delta between refreshes.** The dossier is a standing document refreshed at every milestone,
   and there is no way to see what changed. "Three new backward edges since the last milestone" is a
   better artifact than any static picture, because it is the only one that gets read on the tenth
   run rather than the first.
3. **The `entity_writers` fact** in section 4, which unlocks the boundary question the pipeline
   actually asks at Stage 3 and which no current view can answer.
4. **An eval scenario for the existing app path.** There is none. Every other entry mode has one.

Only after those does a fifth view earn consideration.

---

## 9. Proposed changes to files this note did not touch

Written as diff shaped proposals per the file ownership rule on this branch. None applied.

### 9a. `bin/app-report.sh`, fold the layer map into the one page

The dossier's reading surface should be one page, not two. Once the prototype is accepted, the
renderer gains a subsection under section 3 rather than the standalone page shipping as a second
artifact. Proposed, precisely:

* In the usage block, after the `--json` line, add:
  `#   bin/app-report.sh --no-layer-map              # skip the layer map subsection`
* Beside the existing `dep = load("dependencies.json")`, nothing changes: the layer map needs no new
  input.
* Add one function, `layer_map(dep)`, returning `(svg_string, summary_dict)`, lifted verbatim from
  the prototype's SVG block. It must return `(None, None)` when `dep.get("edges")` is falsy, so a
  faulted dependency section renders the existing fault note and no picture.
* In section 3's assembly, immediately after the existing dependency tables and before the dossier
  block, insert:
  `parts.append(fold("Layer map", back_rows, headers, rows_html=svg_and_ladder))`
  so it collapses like every other block over `COLLAPSE_ROWS`.
* In the `app-report.json` payload, add a `layer_map` key carrying `back_edges`, `back_edge_weight`,
  `layered_weight_pct`, `levels` and `cut_ladder`. **This is the part that matters**: the page is for
  people and the JSON is what the next agent reads, and a view that exists only in HTML is a view no
  agent can act on.
* Do not add a severity weight for `LAYER_*` to `app-report.sh`. The weights live in the Severity
  table in `skills/app-analysis.md` and `skills/layering-review.md` reuses the existing three rather
  than adding a fourth, precisely so the two files cannot drift.

### 9b. `project-bin/app-facts.sh`, one new fact

Only one is proposed, the `entity_writers` section from section 4 above. Precisely:

* In the section that builds `dependencies.json`, after the `edges` query, add a second query over
  the same `refs` join, grouped by `r.TargetName` where `objects.ObjectType = 'ENTITY'` and
  `r.RefKind IN ('change','create','delete','commit')`, emitting the `entity_writers` array shown
  above.
* Add `entity_writers` to `manifest.json` under `sections`, with the same `status` treatment as the
  others, so a version that cannot collect it says `fault` rather than omitting it.
* Do **not** add the scheduled event reach fact here. Section 4 shows it can be joined in the
  renderer from facts already collected, and a fact that can be derived should not be stored twice.

### 9c. `skills/existing-app-change.md`, two sentences

Owned by nobody on this branch but out of scope for this note to edit. Proposed:

* In the Stage 3 row, after *"which existing module owns this, and does that still hold"*, add:
  `Check it with skills/layering-review.md; do not re-derive the boundary by hand.`
* In the "Blast radius" section, before the numbered list, add:
  `Read analysis/app-facts/dependencies.json and the layer map first. Steps 1 to 4 below recompute
  by hand what those already hold; use them to confirm and to reach what the catalog cannot see
  (Java actions, published REST operations called by name, workflow references), not to start.`

---

## 10. How to run the prototype

```bash
bin/app-layer-map.sh <project-dir>                   # -> <project>/analysis/app-layer-map.html
bin/app-layer-map.sh --facts <dir> -o <out.html>     # explicit paths
bin/app-layer-map.sh --facts <dir> --json            # the same numbers, for an agent
```

It reads `dependencies.json`, and optionally `inventory.json` and `manifest.json`, from the facts
directory. It makes no network call, runs no `mxcli`, never touches the model, and adds no dependency
beyond the bash and Python 3 the toolkit already requires. It lives in `bin/` rather than
`project-bin/` for the same reason `bin/app-report.sh` does: it is a renderer the toolkit runs against
a project's facts, not an instrument a project runs against its own model. Moving it to
`project-bin/` later costs one line in `MXTK_PROJECT_BIN` in `bin/lib/install-manifest.sh`.

The prototype's output for the probe app is kept outside this repository, with the facts it was built
from, and no module, entity, microflow or business figure from that app appears anywhere in this
branch.
