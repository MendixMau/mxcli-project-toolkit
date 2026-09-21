# Skill: layering-review, judging whether an existing app's module boundaries still hold

**Use when:** Stage 3 of `skills/existing-app-change.md`, where the question is not "what boundaries
should this app have" but "do the boundaries it has still hold, and does my slice cross one".
Also when an app dossier's dependency section says `DEP-TANGLE-nn` and the next reader asks what
anybody is supposed to do about it.

**Do not use for:** drawing boundaries on an app that does not exist yet (`skills/modularize-domain.md`),
documenting a target architecture (`skills/architecture-blueprint.md`), or listing the dependency
facts (`skills/module-dependency-review.md`, which owns dossier section 3 and stays the owner).
This skill is the judgement on top of one extra view over the same facts.

**Instrument:** `bin/app-layer-map.sh` over `analysis/app-facts/dependencies.json`. It writes
`analysis/app-layer-map.html` and `analysis/app-layer-map.json`. It has no opinion: it computes an
order, the levels, the edges that break the order, and a cut ladder. Every verdict below is yours.

---

## The one rule

> A tangle is not a finding you can act on. **A named edge is.** This skill exists to turn
> "N modules are mutually reachable" into a list of edges with a weight, a ref kind and an owner,
> because the first sentence has no next action and the list is a backlog.

## Why a layer view and not a dependency graph

`module-dependency-review.md` already reports the edges, the pairs, the cohesion and the tangles.
What it cannot do in a table is say **which way the app is supposed to flow**, and that is the only
thing a boundary check needs. Drawing the graph does not help: inside a strongly connected component
every module reaches every other, so every layout of it is equally true and equally unreadable.

The layer map takes the other route. It computes the linear order that puts as few references as
possible backwards, groups that order into levels, and then draws **only the edges that point the
wrong way**. Measured once, on one large app (2026-09-16, the only run so far, so treat the ratio as
an observation and not a rule): the drawn edges fell to under a quarter of the total, and over nine
tenths of the coupling weight turned out to already point one way. Read the second number first
whenever it is high. An app people call "a big ball of mud" is often a layered app with a few dozen
edges in the wrong direction, and those edges have names.

## Procedure

1. **Run the dossier first.** This view is meaningless without `skills/app-analysis.md` section 3:
   the layer map re-reads the same `dependencies.json` and adds nothing the dossier has not already
   measured. If the dossier's dependency section is `fault`, this page is `fault` too, whatever it
   draws.
2. **Run `bin/app-layer-map.sh <project>`.** Read the banner first. If it says the facts disagree
   with themselves (recomputed components against `counts.largest_tangle`), stop: fix
   `project-bin/app-facts.sh`, not the page. That check exists because a join bug once zeroed the
   bidirectional-pair count on 302 edges and nothing noticed.
3. **Look at the page.** `skills/measured-claims.md`: a render you did not look at is not verified.
4. **Ask the three questions below**, in order. They are the whole skill.
5. **Write findings into the dossier**, section 3, with the ids in this file. They join the existing
   `DEP-*` findings rather than replacing them: the tangle finding says the tangle exists, a
   `LAYER-*` finding says which edge to pick up first.

## Question 1: does the computed order match a layering anybody declared

The order is a reading of the app, never its intention. Three cases, and they have different verdicts.

| what you find | verdict | what to write |
|---|---|---|
| the app has a declared layering (`architecture/blueprint.md`, a naming convention such as `*_API` over `*Integration` over a shared kernel, a team's own diagram) and the computed levels agree | `pass` | one sentence naming the declared layering and the fact that the map found it |
| a declared layering exists and the computed levels contradict it: a module the team calls shared sits mid stack, a UI module sits below a domain module | `fail`, one `LAYER-DRIFT-nn` per contradicting module | the module, its computed level, the level the declaration implies, and the edges that put it there |
| no layering was ever declared | `manual` | say so plainly. An app with no declared layering cannot fail a layering check; the map is then a proposal, and Stage 3 is where somebody decides whether to adopt it |

The third row is the common one and it is the honest answer, not a cop out. Per
`skills/coverage-ledger.md` you never reverse derive a requirement from the live model, and the same
restraint applies here: **the computed order is not the architecture and writing it down as though
the team chose it manufactures a decision nobody made.** Adopting it is a Stage 3 `✋` decision with
a `CONFIRMED` line in `PROJECT.md`, taken by a person, or it does not exist.

## Question 2: which backward edges are worth a slice

Read the cut ladder, then the backward edge list. Four readings, from the same table in
`module-dependency-review.md` extended to a direction:

| the edge | default reading | the slice it implies |
|---|---|---|
| kinds are all `call`, target is a `SUB_` or utility flow | a shared helper living in the wrong module | move the helper into a module below both. Usually the cheapest cut in the app |
| kinds include `associate` | the domain model crosses the boundary, and cutting it is an ownership decision, not a move | do not size this as a slice until somebody says which side owns the data |
| kinds include `retrieve` or `change` in volume | the lower module is reaching up into the higher one's data | almost always the higher module should expose a microflow and the lower one should call it |
| kinds include `show_page`, `layout` or `datasource` | a page crossing a module, which `app-analysis.md` explicitly does not count as a finding | not a finding. Note it under Method and move on |

Thresholds, overridable at the top of the dossier under `Thresholds`:

| constant | default | used for |
|---|---|---|
| `MAX_BACK_EDGE_SOURCES` | 3 | a module sourcing more backward edges than this is a `LAYER-SRC-nn` finding in its own right: it is not one bad edge, it is a module sitting at the wrong level |
| `CHEAP_CUT_REFS` | 5 | a backward edge at or under this reference count is a candidate for a single slice, and a list of them is the first untangling PR |
| `LAYER_SPAN_ROWS` | 20 | a backward edge reaching this many rows up the stack is a finding even when it is cheap: distance, not weight, is what makes a change unpredictable |

Severity uses the table in `skills/app-analysis.md` unchanged. `LAYER-SRC` scores as `DEP_TANGLE`
(3) because it is the same defect named more precisely; a single `LAYER-BACK` edge scores as
`DEP_PAIR` (2); a `LAYER-DRIFT` scores as `DEP_COHESION` (1) unless the drifting module is depended
on by `WIDE_BLAST_INBOUND` or more, which the severity table already handles. **Never let the same
defect be counted twice**: an edge inside a tangle that already carries `DEP-TANGLE-01` gets a
`LAYER-BACK` id only when it is being proposed as a slice, and the disposition line says which
tangle it belongs to.

## Question 3: does my change slice cross one of these edges

This is why the view exists at Stage 3 rather than at a review. `existing-app-change.md` says the
blast radius is the tangle when the module you are changing is in one. On a tangle holding most of
the app that is an unusable answer: it makes the regression net the whole application, so the net
does not get built.

The layer map narrows it honestly:

1. Find your module's row. Read its level and its inbound coupling weight.
2. The modules **above** it that reach it are the ones a change to its interface can break. That is
   the real blast radius for a signature or behaviour change, and it is a list, not the tangle.
3. The **backward edges into it** are the ones that make step 2 incomplete: a module below it that
   also calls up into it will not appear in a naive downward trace. That is the whole reason the
   naive answer was "the tangle".
4. State the blast radius in `triage.md` as: the modules above, plus the sources of backward edges
   into this module, plus anything reached through a published service. Name the count.

**Do not use this to shrink a regression net you have not proven.** Ground rule 1 of
`existing-app-change.md` stands: the Track B baseline over the touched modules comes first. This
narrows which modules are touched; it does not excuse skipping the baseline for them.

## Verdict for the section

- `pass`: a layering is declared and the computed levels agree with it, or every `LAYER-*` finding
  has a decision in the dossier's Dispositions section.
- `fail`: any `LAYER-DRIFT` or `LAYER-SRC` without a decision.
- `fault`: the instrument's self check reports the recomputed components disagree with
  `counts.largest_tangle`, or `dependencies.json` carried no edges on an app with more than three
  own modules.
- `manual`: no layering was ever declared, so there is nothing to be wrong against. This is the
  normal first verdict and it is not a failure.
- `skipped`: the change slice touches one module and crosses no boundary. Say so in one line rather
  than running the view for completeness.

## What is NOT a finding

- A backward edge whose kinds are only `show_page`, `layout` or `datasource`. Pages cross modules by
  design and `skills/app-analysis.md` already says so.
- A module at level 0 with no inbound edges. That is an orphan or an entry point, and the dead
  element section already covers it.
- A module moving a few rows between two refreshes. The order minimises a cost that has ties, so the
  rows are not stable and were never meant to be. A module changing **level**, or an arc appearing
  where there was none, is the signal.
- Anything about a marketplace module. Not ours, and the instrument excludes them.
- The computed order itself. It is arithmetic. Disagreeing with it is a Stage 3 conversation, not a
  defect report against the instrument.

## What this view cannot see

Say this out loud in the dossier's Method section every time, because a picture is believed more
than a table. The catalog cannot see Java actions, JavaScript actions, published REST operations
called by name, workflow references or page URLs. **An edge that exists only through one of those is
absent from this page**, so a cut is confirmed in Studio Pro with "Find usages" before it becomes a
slice, and a module that looks clean here may not be.

## Related

`skills/module-dependency-review.md` (owns the dependency facts and dossier section 3),
`skills/app-analysis.md` (owns the dossier and the severity table),
`skills/existing-app-change.md` (Stage 3 in this mode, and the blast radius),
`skills/modularize-domain.md` (drawing boundaries, for an app that has none yet),
`skills/architecture-blueprint.md` (documenting a target architecture, not checking a live one),
`skills/measured-claims.md` (look at the render), `skills/skills-over-scripts.md` (the instrument
computes, this file judges).
