# Journey-Map — the user journey as a source artifact, authored once

**Status:** UNPROVEN method. Personal toolkit only. Do not cite it in a gate, a runbook stage or a
module brief until the falsification trial at the bottom has been run and its findings attached.
**Applies to:** any mxcli project with BRDs/requirements, wireframes, and a module split.
**Fits into:** `conversion-runbook.md` Stage 3 (`✋`), as an addition to `design-artifacts.md`.

---

## The problem: the pipeline reconstructs the journey four times and stores it zero times

| Where | Who rebuilds it | From what | Scope | Stage |
|---|---|---|---|---|
| `module-brief.md` §Roles & journeys | `ba-agent` | BRDs + SME | one module | 4 |
| `process-coherence-pass.md` pass 1 | review agent, read-only, *tens of thousands of tokens* | requirements, re-derived at review time | ad hoc | 6+ |
| `journey-proof.md` `journeys/<M>.journey.json` | test author | BRDs + the live model | one module | 6 |
| wireframe set | *nobody* | — | — | 3 |

Four derivations, four inputs, four stages, four agents, **no shared identifiers** — so no two can
be compared, and none can be reused. The fourth row is the tell: because nothing owns the flow at
design time, a wireframe set becomes a pile of screens with a menu. (Observed: a project's
`wf-nav.js` cross-link bar referenced by **zero** of its 18 wireframes, half of which were never
listed in it. Dead for months; nothing could have noticed, because no artifact claimed a screen
order.)

**This skill adds no fifth derivation. It moves the first one earlier and makes the other three
read it.** If it does not delete work downstream, it has failed and should be dropped.

### What a journey is *not*

- Not a requirements format. It **references** BRD rules by pointer; it never restates one.
  A rule written in two places means the corpus has two truths.
- Not module-scoped. A journey that fits inside one module is a use case; write it in the brief.
  This artifact exists for the flows that **cross** modules, because nothing else covers those.
- Not a test. `journey-proof.md` still owns rungs, mutants and verdicts — **unchanged for
  single-persona journeys only.** See the handoff limit below; do not repeat the flat claim.

---

## One file, four layers, bound progressively

Author at the stage where the information first exists. Each later layer is a *binding*, never a
rewrite, so the step list is written once and survives to the test run.

| Layer | Stage | Adds | Payoff at that stage |
|---|---|---|---|
| **L0 process** | 2 (inventory only) | name, personas, trigger → outcome, modules spanned — one line per journey | feeds module boundaries; `modularize-domain.md` already asks "which user journeys does this module serve" and nothing supplies the answer |
| **L1 screens** | 3 ✋ | numbered steps in business language, step → wireframe, persona handoffs, exception branches | turns a screen pile into a flow; exposes screens nobody designed and steps with no owning module |
| **L2 model** | 4/5 | step → microflow, data effects, BRD pointer | this *is* the brief's golden-path table — it becomes a projection, not a second hand-authored table |
| **L3 executable** | 6 | step `id`, selectors, seeds, spans | compiles to `journeys/*.journey.json`; runs unchanged **for single-persona journeys** |

**L0+L1 is the deliverable that matters and the only one a human writes by hand.** L2/L3 are
mechanical once the model exists.

### Location

```
design/journeys/J-<cap>-<nn>.journey.md      the source (L0–L2, human-readable)
design/journeys/index.html                   rendered flow map, links ds.css, links wireframes in order
journeys/<id>.journey.json                   COMPILED from the source — never hand-edited
```

`design/` because at L1 it is a design artifact and its reviewer is a designer or an SME, not a
test author.

---

## The one rule that decides whether this works: compile, never cross-reference

If the journey document and the executable journey are two files a human keeps in sync, this fails
inside three sprints and leaves you worse off than having neither — a plausible document that lies
is more expensive than no document. So:

- **L3 is generated from the source.** Divergence is a build error, not a discrepancy nobody sees.
- **Stable step IDs** (`J-RCV-01#3`) are the join key, and L1 must emit one per step — the runner
  cannot invent them. **Measured in a live runner, two different identity bugs, so an `id` has to
  reach both surfaces or history stays fragile on one of them:**
  findings are keyed by the step's *name* (`record(rung, `${step.name}: ${check}`, ...)`), so a
  **rename** orphans a step's history; screenshots are keyed by *position*
  (`${j.id}-step${i+1}`), so an **insert or reorder** silently re-points every later step's images
  onto the wrong step. Renaming is harmless to the second, reordering harmless to the first.
- **The compiled artifact records the source hash.** Stale compile ⇒ `fault`, never silence —
  same discipline as a missing instrument in `journey-proof.md`'s normalizer.
- **Migration: the fault must be conditional on a source existing.** Projects already hold
  hand-written `.json` journeys (one project: five, one of them executed end-to-end against a live
  stack). The day L3 generation lands, those become generated artifacts. If the stale-hash fault
  ships unconditionally, **every existing project faults every journey on day one, and people route
  around the guard** — which costs more than the guard was ever worth. So: no source file at all ⇒
  *warning*, hand-written journey still runs. Source present and out of date ⇒ *fault*. The guard
  goes red only once there is something for it to be right about.
  **And it cannot be armed against an L0/L1 source at all.** An L1 file and its `journey.json` will
  *always* differ — the target legitimately holds six field families the source never had — so a
  hash guard armed at L1 fires permanently on every correctly-authored pair, which trains people to
  ignore it. Arm it **only against sources that declare an L2/L3 layer.**

### Presence is not content — the rule that turned honesty into a pass

**Measured, and it flipped a red to green.** A source recorded, correctly, that no requirement
existed for a step: `*(none — see lint below)*`. The traceability check tested *cell is non-empty*.
So **writing "there is no requirement here" scored as citing one**, and that journey's traceability
went FAIL → PASS on a reformat that changed nothing about its coverage.

Two rules, neither optional in a required column:

1. **Validate a required cell for shape, not for presence.** Any check of the form *"the author
   filled it in"* converts an honest disclosure into compliance. Same fail-open family as defaulting
   `Executable` to yes, and as `[].every()` being true: the honest author and the negligent one
   produce the same green.
2. **Absence gets one canonical marker, and it is not prose.** The bare literal `none` — normalised
   alongside `n/a`, `tbd`, `—` — so a parser can separate "no pointer exists" from "here is a
   pointer" without reading English. Prose in a pointer column is a smell both ways: it cannot be
   validated, and it is where an author hides an explanation no instrument will ever read — the same
   defect as burying a rung's justification in an underscore-prefixed prose key.

3. **A finding that does not change the verdict is decoration.** Detecting a defect and reporting
   `PASS` is *worse* than not detecting it: the green now carries evidence against itself, and
   anyone reading the verdict column instead of the detail column is misled by a check that
   worked. **Measured:** a reconciler rendered its `missing` list as a footnote on a green verdict,
   so target steps with **no landing guard at all** scored `PASS` — each one carrying the detected
   defect in its own detail string. Different mechanism from rules 1 and 2, same effect: the honest
   and the negligent produce identical greens, here not because the check could not tell them apart
   but because **the verdict never asked**. Any rung that accumulates sub-findings can grow this.
   If the check found a defect, the defect **is** the verdict.

**A guard must discriminate.** The same audit found the landing-guard field validated with
`if (!ui.ready)` — which accepts `body`, `html`, `*` and the literal `"TBD"`. A selector that
matches every page distinguishes none of them: it is the *absence* of a guard wearing the shape of
one. Validate the field that everything else leans on hardest for what it must exclude, not for
whether it was filled in.

**Corollary — verdict-flip hygiene, both directions.** An expected-red going green is a prompt to
re-measure, never proof of a fix. So is a red going green on a change that should not have touched
it. Both were caught only because someone asked *why* a verdict moved instead of banking the
improvement.

### L2 binding: the id passes through untouched, and lands in the target

L2 adds microflow names, data effects and BRD pointers to each step. It **must not renumber,
re-key, merge or split** a step: the L1 `id` passes through unchanged, and L3 emits it into the
target as `sourceStep: "J-XX-NN#n"` on the step it produced.

That one field is what lets reconcile be **id-based set matching** — missing / extra / reordered —
instead of walking two lists by index. **Measured cost of not having it:** with positional matching,
a reconciler reported PASS whenever a target step merely existed at the same ordinal, so a source
step "the list loads, site-scoped" was scored as agreeing with a target step "refresh the list".
Five PASSes, zero comparisons, on a pairing the instrument could not actually decide.

Until a target carries `sourceStep`, a positional reconcile must report `INVALID` — the steps may
correspond, the instrument cannot tell, and an instrument that cannot decide reports absent rather
than green.

Splitting or merging a step is a **source** edit: change L1, keep the ids stable for the steps that
survive, and give genuinely new steps new ids. Never let L2 quietly re-key what L1 declared.

### L1 is a SPEC, not a convention — and the evidence is self-inflicted

**Measured:** one author produced **two incompatible L1 schemas inside a single session.** The first
journey, written before the schema existed, used `# | Step | Persona | Module | Screen | BRD | State`
— no `id`, no `Executable`. The two written afterwards used the table below. A reconciler run
against the first returned `rc 2 FAULT — no L1 step table found`, refusing to parse rather than
reading 8 steps and reporting a clean admissibility section. Coverage: zero. Two persona handoffs in
that file were invisible to it.

The fault behaviour was right; the source was wrong. And note what the evidence actually is — not
"three authors disagreed," which would argue for tolerance, but **one author drifting in an
afternoon**, which argues that a convention cannot hold at all. So: the schema below is normative,
`journey-lint` faults on a table that does not match it, and the parser never infers a missing
column from a present one — inferring `Executable` from `Persona` is the same fail-open as
defaulting it to yes.

### The L1 schema — ONE table, header-driven, every column on every row

**Measured defect in the first two sources written to this skill:** they used two tables with
different schemas — a main step table carrying `Persona`, and an exception-branch table carrying
`Screen must say` in roughly the same position. A positional parser read the assertion as the
persona and reported two exception branches as persona handoffs. **The parser was at fault for
reading by position; the source was at fault for offering two shapes.** Fix both ends: parse by
header, and author one table.

| Column | Required | Notes |
|---|---|---|
| `#` | yes | ordinal, for humans only — never a join key |
| `id` | yes | `J-<cap>-<nn>#<n>` (branches: `#E1`). **The join key.** Must survive L2 unchanged and be emitted into the target as `sourceStep`, or every reconcile silently scores on position |
| `Step` | yes | business language, what the person does |
| `Persona` | yes | on **every** row, branches included — an exception branch usually runs as the same persona, and omitting it is what let a parser invent a handoff |
| `Screen` | yes | a location |
| `Screen must say` | no | an assertion. **Deliberately a different column from `Screen`** — conflating a location with an assertion is how a compiler starts inventing selectors |
| `BRD` | yes | a pointer that **looks like** one (`F\d{3}`, `MBR-n`, `UCn`, `ACT-n`, `BR-n`, or a `#/` JSON pointer), or the bare literal `none`. **No prose, ever** — see below |
| `Executable` | yes | `yes`, or `no:<class>[,<class>] — <reason>`. The reason is quoted verbatim into the refusal so no tool puts words in the source's mouth; the **class is a token, never inferred from the prose** — see below |

Exception branches are **steps, not footnotes** — same table, same columns, ids `#E1`, `#E2`. Most
are executable; only a persona handoff is not.

### `Executable` is a MANDATORY L1 column, and lint faults on its absence

Every L1 step declares `Executable: yes | no (<reason>)`. **A compiler cannot infer it**, and a
source that omits it makes the refusal silent — the handoff step compiles to a walkable step and
passes as the wrong persona. Defaulting to executable is fail-open, the same class of defect as
`[].every()` being true. **Measured in the first reconcile trial: the compiler refused the handoff
step correctly, and only because the source carried the column explicitly.** So: absent column ⇒
`journey-lint` fault, never a default.

### A refusal is a cost, and it carries a class

**Measured, defect 7:** a process journey with 3 of 8 steps executable reported an admissibility
section with **zero failures**. Refusal had been treated as a blameless terminal state, so unbuilt
scope laundered into a clean verdict — the same family as everything else here, honest and empty
scoring alike. It is worst on a process journey, where refusals cluster at the *end*: steps 1–3
walked, 4–8 did not, including both handoffs and the seam into an unowned module.

So refusals are **accounted, not absorbed**: report executable/total with the refused ids, as a
verdict rather than a footnote — *"3/8 steps executable (38%), 5 refused: #4 #5 #6 #7 #8."*

**And a refusal declares WHY, as a token.** "Not walkable" hides three different situations that a
coverage report must not merge, and the class must never be inferred from the reason prose —
reading "exec pending" as temporary encodes one author's phrasing, the same move as inferring
executability from `Persona`:

| Class | Meaning | Resolves when | What it is |
|---|---|---|---|
| `no:runner` | the harness cannot express it, whatever the app does — a persona handoff is the canonical case | the harness gains a capability | a boundary |
| `no:unbuilt` | the app does not have it yet, and the plan says it will | the build lands | debt |
| `no:unscoped` | nothing owns it and no plan says it will ever exist | a human makes a scope decision | **a question, not debt** |

A step may carry more than one — `no:runner,unscoped` is a handoff to a screen nobody has planned,
and both facts matter. **Do not collapse `unscoped` into "structural."** It is the class that names
the most important thing a process journey finds: a step in the middle of a real user path that no
module claims. Filed as a boundary it looks permanent and acceptable; filed as `unscoped` it goes to
the interview batch, where it belongs.

What the classes buy once they exist, none of it visible while they share one state:
- an `unbuilt` refusal still refused three builds later is a **finding**;
- a `runner` refusal that suddenly becomes executable is a **verdict flip** — re-measure, per the
  hygiene rule above;
- an `unscoped` refusal never resolves by building, so it must never sit in a debt column waiting.

`journey-lint` faults on a bare `no`, and on an unknown class token.

### The handoff limit — the one place L1 outruns the runner

L1 records **persona handoffs**, and the handoff assertion is the highest-value claim in the whole
idea: the seam between two modules is exactly where per-module verification is structurally blind.
It is also the one thing a compiled L3 cannot execute today.

**Measured in a live runner, not assumed:** `H.login(page)` is called **once per run** — outside
the journey loop, not per journey — and `persona` is read only as a journey-level label
(`j.persona`), never per step. One browser context, one identity, for every journey in the run.
So *"operator commits, supervisor now sees it in their queue"* has no representation at all, and a
compiled journey containing a handoff would walk the second half as the first persona and pass.

Consequences for anyone adopting this skill:

- A multi-persona journey is **authorable at L1 and not yet executable at L3.** Say so in the file.
- Compiling one anyway produces a **silently wrong green** — the worst outcome in this toolkit.
  Until the runner supports a second context, a compiler MUST refuse a handoff step, or emit it as
  `INVALID`. Never emit it as a normal step.
- The runner extension is small but real, and it belongs to whoever owns the runner, not to this
  skill.

### A "no writes" rule is a data claim, not an exemption from one

Where a journey is read-only by design — a browse flow, or a BRD rule forbidding writes to a system
of record — the tempting move is to mark rung 4 not-applicable. **Prefer asserting it.** "No row was
created during this run" is `delta 0` with a scope watermark: cheaper than an exemption, and it
turns the read-only constraint from a reason to skip the rung into the thing the rung proves.

Only where there is genuinely nothing to assert does an exemption apply, and then it is **declared,
never inferred** — an explicit key carrying its reason and BRD citation. An empty data block with no
such key stays a fault, so the default remains fail-closed and every exemption is greppable and
countable. It renders as its own state and never inside the pass count.

**Two exemptions, not one — they carry different obligations, so the reason is a CODE plus the
measurement, never free prose:**

| Code | Situation | What is still owed |
|---|---|---|
| `readOnlyByDesign` | a write rule exists and forbids writes | rung 4 is *available*: assert `delta 0` + scope watermark. **Rung 5 mandatory.** |
| `notPersistable` | the entities are non-persistent, so OQL cannot observe them | rungs 4 **and** 5 are structurally unavailable; `delta 0` is unassertable too. Rung 5 cannot be demanded |

The distinction is load-bearing. Demanding rung 5 whenever rung 4 is exempt sounds strict and is
wrong: a `notPersistable` journey can never satisfy it, so the rule would hold it permanently red —
and a permanent red gets routed around, the same failure mode the unconditional stale-hash fault
would have had. Strictness that cannot be satisfied buys nothing.

A journey exempt on both rungs is labelled **UI+trace-only** in coverage: covered, weakly evidenced,
**never counted as conformant**. It does not go green and it does not go red — the honest state
stays visible in its own column instead of being forced into pass or fail. Note the cost: such a
journey's strongest evidence is a string comparison on screen text, so its screen-says rung is
carrying nearly everything.

**Expected-red hygiene.** Where a check is deliberately expected to fail against a known defect, say
what a *green* would mean — usually not "fixed". A `textAbsent` that starts passing is also what a
page which failed to render its grid at all would produce, and the landing guard alone does not
separate those. An expected-red going green is a prompt to re-measure, never proof of a fix.

### `journey-lint` — checks that can go red

A journey artifact with no failing check is decoration. At minimum, fault on:

| Check | Catches |
|---|---|
| step with no BRD pointer | a step the requirements never asked for |
| BRD feature reachable from no journey step | built, and nobody does it — the coverage-ledger question asked from the other end |
| step referencing a wireframe that does not exist | L1 written ahead of design |
| wireframe on no journey step | the orphan case above |
| check referencing an unknown step ID | drift between runner and source |
| journey whose last step has no screen | **the outcome is unobservable** — see below |

That last one is the highest-value check and the cheapest. A capability whose payoff step has no
screen cannot be demonstrated, and per-module review cannot see it, because every individual
deferral that produced it was reasonable on its own.

---

## Reconciling an L1 table against an executable target — by hand, not by parser

**This was a 304-line script (`journey-compile.js`). It is now this section.** Seven defects
were found *in the script*, none in the journeys it checked — the classic signature of encoding
judgement as code (`skills-over-scripts.md`). Do this by reading. It takes about two minutes per
journey and it does not have its own bugs.

Read the L1 table and the target side by side, and apply these in order.

**1. Find columns by their header, never by position.** Journey tables get reordered and gain
columns. A reader does this automatically; positional indexing silently reads `Screen must say`
as `Screen` the moment someone inserts a column. Note in particular that **`Screen` and
`Screen must say` are different things** — one is a location, the other an expectation.

**2. Bind steps by id, never by row order.** If the target's step *n* has no explicit pointer
back to an L1 step id, the pairing is a coincidence, not a binding. That is **INVALID** — the
reconcile did not happen — not a mismatch. Two tables of different length paired positionally
will produce confident, meaningless output.

**3. A `BRD` cell must contain a pointer, not prose.** `F013 UC002` is a pointer. "derived from
the workshop notes" is not, and neither is `—`, `n/a`, `TBD`, or an empty cell. Prose that cites
nothing is the same as no citation: say so. Do not count it as traceable because the cell was
non-empty — **presence is not content.**

**4. Every step declares `Executable`, and a refusal declares its class.** Bare `no` is
malformed and must **FAULT**, not pass. The grammar is `no:<class>` where class is exactly one
or more of:

| Class | Means | Verdict | Why that verdict |
|---|---|---|---|
| `runner` | the harness cannot do this yet (e.g. a second persona login) | **PASS** | A harness boundary. Resolves when the runner gains a capability. When it becomes executable that is a **verdict flip — re-measure**, do not assume it passes. |
| `unbuilt` | the feature does not exist yet | **FAIL** | Build debt. Must return as executable when the build lands. Still refused three builds later is itself a finding. |
| `unscoped` | nobody has decided whether this is in scope | **INVALID** | **Nobody owns this.** It never resolves by building. Route it to the interview batch, not to a debt column. |

Anything else in that cell is malformed → **FAULT**.

**5. A landing guard must discriminate.** Every executable step needs a selector proving it
arrived. Reject `body`, `html`, `*`, `:root` — they match every page, so they guard nothing and
will pass on the wrong screen. Reject `TBD`, `TODO`, `none`, `?`. A guard that cannot fail is
not a guard.

**6. A step with an empty action list does nothing.** Flag it. It will pass forever.

**7. Rung exemptions carry a reason code, and the codes are not interchangeable.**
`readOnlyByDesign` (the journey legitimately writes nothing) is different from `notPersistable`
(the entities are non-persistent, so OQL cannot see them *at all*). The second is the binding
one where both apply, because it also removes rung 5's end state. A journey exempt on either is
**UI+trace-only: covered, weakly evidenced, never counted as conformant.** Do not let an
exemption on rung 4 silently make rung 5 mandatory — on a non-persistent module that holds it
permanently red for a reason nobody can fix.

**The verdict rule that outranks all seven:** a finding that does not change the verdict is
decoration. If you list a problem and still call the journey PASS, either the problem is not
real or the verdict is wrong. Pick one.

## The failure this whole layer exists to prevent, one level up

Every rule above is about a check that goes green without looking. The same failure recurs at the
level of a *suite*, and it is the reason L0 owns the process inventory:

**A set of green per-module journeys can stand in for a process nobody tested.** Measured on a real
project: eight steps spanning four modules, five per-module journey targets, and **no cross-module
target — nor any possible under a per-module target shape.** Every module passes in isolation. The
spine is never walked as a spine. The two things a process journey exists to protect — that a
handoff carries the right state, and that the next module can consume it — are precisely the two
that nothing asserts.

So a report can be green on every module while the process they compose is broken at every seam,
and nothing in the harness would say so. That is not a gap in any module's coverage; it is a gap
between them, and only an artifact that owns the whole spine can name it.

## Two renderings, both free

**Tester script (UAT)** — L0/L1 with the expected observable result per step in human language,
plus "what to do if it disagrees." Generated *before* the run, for a human who does not know the
app. This is what makes the journey useful to people who will never read a `.json`.

**User manual** — the same spine rendered *from a passing run*, using the per-step screenshots
`journey-proof.md` already captures (taken after the landing guard, before the assertions — exactly
the frame a manual wants).

The property worth naming: **a failing journey produces no manual.** A manual generated this way
cannot document a flow that does not work, which is not true of any hand-written manual. That is
the argument for the manual living in the testing skill rather than a docs skill.

Caveat: a manual built from test data shows test data. Decide early whether the demo seed doubles
as the manual seed, or the manual reads as obviously synthetic.

---

## Gate additions (Stage 3 ✋, alongside `design-artifacts.md`)

- [ ] Every cross-module flow in the L0 inventory has an L1 journey.
- [ ] Every wireframe is reachable from at least one journey step.
- [ ] Every journey step names a screen **or is recorded as a gap with an owner question**.
- [ ] Steps whose module is not yet built are `blocked`, never absent — an unbuilt step is a
      visible hole in the flow, not a shorter flow.

That fourth point is deliberately uncomfortable: for most of a build the headline number looks bad,
and someone will ask to hide it. It is the honest number.

---

## Updating

The journey is **source**, so a requirement change lands there first and propagates down. Anything
else re-creates the drift this skill exists to remove. Concretely: change L0/L1 → recompile L3 →
stale-hash fault clears. A change that lands only in a `.json` is a defect in the process, not a
shortcut.

---

## What is NOT proven, and the trial that would settle it

Nothing here has been run. The problem statement (four derivations, orphaned nav) is **measured**;
every claimed benefit is **judged**. Promoting an instrument before watching it work is the exact
move `journey-proof.md` forbids, so this stays personal until the following trial runs on a real
project:

1. Write L0+L1 by hand for one cross-module flow. Does it surface a gap that the module briefs,
   blueprint and fit-gap **individually already record but nobody had composed**? (First attempt:
   yes — it reshaped four separately-reasonable deferrals into "the capability has no walkable
   ending and its payoff step has no owning module." Reshaped, not discovered. Judge whether that
   is worth an artifact.)
2. **This was one question and it is two.** Separating them is the most important correction this
   skill has taken, because 2a passing reads like the skill clearing its own bar, and it does not:
   - **2a — does the L1 spine reconcile against an existing target?** **NOT PASSED. Every pairing
     is `INVALID`, on both journeys tried.** Read the history, because it is the point:

     | Run | Reported | Actual |
     |---|---|---|
     | sighted, journey A | spine 5/5 PASS | **withdrawn** — the reconciler emitted PASS whenever a target step merely *existed* at the same ordinal. Five PASSes, zero comparisons |
     | blind, journey B | 4 source steps vs 2 target, 2 PASS | those two PASSes were the same defect |
     | corrected, both | — | `INVALID` on every pairing: the target carries no L1 step id, so the instrument **cannot decide** whether the steps correspond |

     `INVALID`, not `FAIL` — the steps may well correspond; the instrument cannot tell, and an
     instrument that cannot decide reports absent, never green. **So no journey has a proven spine
     reconcile today.** The fix is target-side: `journey.json` steps must carry
     `sourceStep: "J-XX-NN#n"`, turning reconcile into id-based set matching (missing / extra /
     reordered) instead of index walking. Until then, positional reconcile stays `INVALID` by
     design rather than fake-green.

     **The divergence found on the way is the valuable output — but read it correctly, because the
     first reading was wrong and the misreading would have caused the wrong fix.**

     First reading: "the target is thinner than the requirement." It asserted
     `textAbsent: ["No items found"]`, which looks like *the grid must never be empty* — the
     opposite of the source's empty-state branch. Wrong. Opening the target's own annotations shows
     the assertion carries two claims, and the second is the source's branch verbatim: *if the grid
     has no rows, the app must show the designed empty state rather than Mendix's default string*,
     cited to the same alt-flow and to the wireframe's `.empty-state` block. It is a deliberate
     expected-red against a confirmed defect. Target and requirement **agree**.

     The target's absent rungs are likewise measured, not skipped: `data: null` for two independent
     reasons (the brief's read-only statement, and `DESCRIBE ENTITY` showing all five module
     entities non-persistent), `outcome` omitted and named as omitted.

     **So the real finding is a schema gap, not an authoring failure.** Every one of those
     justifications lives in an underscore-prefixed prose key that no instrument reads. Under the
     fail-closed rule this target is `fault` — correctly, because the machine cannot distinguish it
     from one that simply skipped the rung. The reasoning existed; it had nowhere machine-readable
     to land. Filed as "thin target" it reads as neglect and someone adds data blocks that cannot
     exist. Filed as a schema gap, the fix is a field.

     What genuinely is uncovered: the RFC 9457 problem-banner branch. The empty-state branch is
     already partly covered by the expected-red.

   - **2b — does an L2/L3-bound source compile to a runnable target losslessly?** **UNTESTED, and
     it is the real go/no-go.** The target carries 16 field families; an L0+L1 source binds one
     (`name`). Six are hand-authored in every target today: `ui.ready`, `actions[]`,
     `ui.textPresent`/`textAbsent`, `spans.ordered`, `data[]` (delta / assocMustBeSet / mustPointAt
     + mandatory `scope`), `outcome`. Until a source declares an L2/L3 layer there is nothing to
     compile *from*, so no reconcile result — however green — can settle this.

   **Self-authored agreement is not independent evidence.** Where a reconcile is scored against
   sources written by the party that owns the matcher — or by a single author, however careful —
   label the result weakly evidenced, exactly as a UI+trace-only journey is labelled. The matcher is
   *built* against those sources; it is not *validated* by them. Hold it UNPROVEN until it runs
   against a journey neither party wrote, and prefer it failing there to passing here.

   **Nothing here has passed. 2a is INVALID and 2b is untested, so the skill is a document, not a
   compiler.** Say exactly that wherever the trial is reported.

   **Method finding, and it generalises well past this skill: have the source authored blind, by a
   different party than the one that owns the reconciler.** **Six fail-open defects** were found in
   one reconciler, every one of them traceable to material its author did not write:

   | # | Defect | Surfaced by |
   |---|---|---|
   | 1 | row filter silently dropped every non-numeric step id | a source with `E1`-keyed branches |
   | 2 | positional parser read an assertion column as a persona | a source with two table schemas |
   | 3 | `PASS` emitted whenever a target step existed at the same ordinal — zero comparisons | a blind source of a different length |
   | 4 | traceability tested cell-non-empty, so `*(none)*` scored as a citation | an honestly-marked absent pointer |
   | 5 | landing guard validated by presence, accepting `body` / `*` / `"TBD"` | applying #4's rule to its own code |
   | 6 | detected defects rendered as footnotes on a green verdict | a positive-control mutant built for #5 |

   Three of the six came from **one** source file — the one with exception branches and a
   different-length target. None would have surfaced against the first journey alone: one table, no
   branches, a same-length target, one author. **That configuration is blind by construction.**
   Blind authoring by a second party did the work a positive-control mutant does elsewhere, and
   then #5 and #6 show the two compounding: a rule learned from cross-authoring, turned on its own
   code, found two more. Treat it as trial protocol, not an accident of who was available.

   **Corollary, measured: positional matching is too weak a contract between source and target.**
   Blind-authored L1 and hand-authored L3 do not agree on step granularity — one splits "load" and
   "read", the other folds them — so ordinal alignment manufactures agreement where none exists.
   The L1 step `id` must survive into whatever L2 emits, and the target must carry it, or every
   reconcile silently scores on position.
3. Does the tester script read usefully to someone who does not know the app? Ask one.
4. Does `process-coherence-pass.md` pass 1 get **cheaper** when it reads a journey instead of
   re-deriving one? That pass currently budgets tens of thousands of tokens. If the number does not
   move, the deduplication claim is false.

Fail 2 or 4 and drop this. Passing 1 and 3 alone makes it a documentation tax with a nice story.
