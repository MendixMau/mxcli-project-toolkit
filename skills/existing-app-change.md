# Change an Existing App — Adding To or Altering a Mendix App You Already Have

**Applies to:** any mxcli project — a live Mendix app, built by people, with no BRDs, no architecture
document and no wireframes, that you now need to change.
**Requires:** the app's `.mpr`, a runnable local environment, bash and Python 3. Run `bin/doctor.sh`
once on a new machine. Windows: Git Bash, and see `conversion-runbook.md` → Prerequisites.
**Purpose:** The recipe for changing an app the pipeline never built. The knowledge base comes from
**the model itself**, not from an extractor, and stages 2–4 run over the **slice you are changing** —
not over the whole application.
**Source:** Field run #1, 2026-08-20. The three entry modes all assume the target app does not exist
yet, and the classification rules sent an existing `.mpr` to Migration — i.e. to migrating the app to
itself. `existing-app-assurance.md` covers audit and testing and says in as many words *"not for
building anything new"*, which sent you back to the three modes that did not fit. This file closes
that loop.

---

## When to Use This Skill

- "Add click-and-collect to our webshop."
- "The approval flow needs a second approver above €250."
- "Replace the CSV export with a real ERP integration."
- "This module is a mess and we want to restructure it" — restructuring is a change like any other.

**Not this skill:**

| You want | Go to |
|---|---|
| To understand, audit or lint the app; a regression net; no change planned | `existing-app-assurance.md` |
| To rebuild the app on Mendix from a non-Mendix source | `conversion-runbook.md` → Migration |
| A brand-new app | `conversion-runbook.md` → Requirements-driven or Greenfield |
| A one-line fix you would not open a ticket for | Just do it. This skill is overhead for a typo. |

The line between "a change" and "a new app inside an old one" is scope, and Stage 0 draws it. If the
slice turns out to be most of the app, you are in Migration mode with a Mendix source — say so and
switch.

---

## Ground rules

**1. The regression net comes first, and it is not optional.**

Every other entry mode has a specification to check the result against. This one does not: the app is
its own specification and nobody wrote it down. The substitute is a proven statement of what the app
does *today*, before you touch it — `existing-app-assurance.md` Track B, at minimum over the modules
your change touches.

Skip it and you have no way to tell a bug you introduced from behaviour that was always like that.
That is the entire risk of this entry mode, concentrated in one decision.

**2. The slice is the unit of work, not the app.**

You are not writing BRDs for a five-year-old application. You are writing them for what changes, plus
what that change touches. Everything downstream — the ledger denominator, the coverage claim, the
gates — is scoped to the slice. A coverage number that silently means "of the slice" while reading
like "of the app" is the false-green this toolkit keeps producing; say which one you mean, every time.

**3. The model is ground truth. Memory and the UI are not.**

Ask the model, not the app's screens and not the person who thinks they remember. `query-the-model.md`
is baseline routing for a reason, and here it is the primary instrument rather than a convenience.

**4. Record the as-is before you record the to-be.**

For each thing you change, write what it does now and what it should do. The as-is half is the piece
that gets skipped and the piece that has no other home — after the change it is unrecoverable except
from git history of a `.mpr`, which is not a readable record.

---

## Where the knowledge base comes from — Path D

`conversion-runbook.md` Stage 1 names three paths: **A** code → AST extractors, **B** documents → LLM
extraction, **C** SME interview. This entry mode adds a fourth.

**Path D — the live model.** No extractor, no parsing, no regex. `mxcli` reads the `.mpr` and answers
directly:

```bash
./mxcli -p <project>.mpr -c "SHOW MODULES"
./mxcli -p <project>.mpr -c "SHOW ENTITIES IN <Module>"
./mxcli -p <project>.mpr -c "SHOW ASSOCIATIONS"
./mxcli -p <project>.mpr -c "DESCRIBE ENTITY <Module>.<Entity>"
./mxcli -p <project>.mpr -c "SHOW PAGES IN <Module>"
./mxcli -p <project>.mpr -c "SHOW MICROFLOWS IN <Module>"
mxcli graph-report          # dependency tangles, community detection
```

**Path D does not have Path A's failure mode, and that is the main reason this entry mode is safer
than it looks.** A code extractor guesses at files and silently returns zero for a construct class
whose layout it did not anticipate — field run #1 lost 39 Angular components, 35 REST endpoints and
18 SQL tables that way, with every instrument reporting green. The model cannot do this. It either
answers or errors, and `SHOW ENTITIES` is the count, not an estimate of the count.

Still record the counts. `SHOW MODULES` returning 6 when the person who asked for the change said
"about twenty" is a scope conversation you want to have at Stage 0, not at Stage 4.

---

## Blast radius — the question Stage 0 exists to answer here

In every other mode, Stage 0 asks *what do we build first*. Here it asks a second question that has no
equivalent elsewhere: **what does this change touch that nobody mentioned?**

Work outward from the entities the change affects:

1. **Associations** — `SHOW ASSOCIATIONS`, then `DESCRIBE ENTITY` each end. An entity you are changing
   that is on the far end of an association from a module nobody mentioned is your blast radius.
2. **Microflows that read or write those entities** — `SEARCH` for the entity name across microflows.
   A change to a validation rule lands in every flow that writes the entity, not only the one on the
   screen you were shown.
3. **Pages bound to them** — `SHOW PAGES IN <Module>`, and check which are bound to the entity.
4. **Module dependencies** — `mxcli graph-report`. If the module you are changing is in a tangle, the
   blast radius is the tangle.
5. **Published and consumed services** — a changed entity behind a published REST service is a
   contract change, and the consumer is not in the `.mpr`.

**Write the blast radius into `triage.md` as its own section and get it confirmed.** It is the single
most valuable output of Stage 0 in this mode, and it is the thing the person requesting the change is
least able to give you — they know what they want, not what it touches.

---

## What runs, stage by stage

| Stage | Runs? | What changes in this mode |
|---|---|---|
| **P — Kickoff** | Yes, light | `bin/init-project.sh` as normal. Many intake questions are already answered by the app existing — answer them from the model, not by asking. Record entry mode `Change an existing app` `CONFIRMED` in `PROJECT.md`. |
| **0 — Triage & Scope ✋** | **Yes, always** | Two questions, not one: which slice, and its blast radius (above). The Coverage Matrix's *extraction* rows are N/A — Path D has no extractor to choose. The Business Capability Map is built from `SHOW MODULES` + the change request. **CAC-1 runs.** |
| **1 — Analysis** | Yes, **Path D** | Query the model into the knowledge base, scoped to the slice **plus** its blast radius. Path A is declared not-applicable with attribution, not "skipped". Path C (SME) matters more here than anywhere: the model tells you what the app does and nobody wrote down why. **CAC-1b runs** — its scope-out diff is the slice-vs-app statement. |
| **2 — Requirements** | Yes, **slice only** | One BRD per capability *being changed*, each carrying **as-is** and **to-be**. Do not BRD untouched capabilities; record explicitly that you did not, and why. **CAC-2 and CAC-3 run.** |
| **3 — Architecture & Design ✋** | **Conditionally** | Run it in full if the change crosses module boundaries, adds an integration, or alters the domain model. Otherwise it collapses to: which existing module owns this, and does that still hold. **Never invent new module boundaries for an app that already has them** — `modularize-domain.md` is being used to *check* a boundary here, not to draw one. Wireframes only for screens that change; the design system is the app's existing styling, captured, not designed. **CAC-4 runs, scoped to what changes.** |
| **4 — Build Plan ✋** | Yes, **slice only** | `brd-to-build-plan.md` as normal, over the slice's BRDs. Ordering must respect what already exists: you cannot stub an entity that is live and has data in it. **CAC-5 runs.** |
| **5–6 — Build & Verify** | Yes, unchanged | `iterative-build-loop.md`, the STOP table, module briefs, gates. Plus the rule below. |
| **7 — Cutover** | **N/A** | There is no legacy system to cut over from. Mark it N/A in the register with that reason — an unstated skip and a settled one are different things, which is the whole reason the register exists. |

---

## The rule that is specific to this entry mode

**Every gate from Stage 5 onward is also a regression gate.**

In the other modes a gate asks *did we build what we said*. Here it asks that, and one more thing:
*does everything the app did yesterday still work*. That second question is answered by the Track B
baseline from Ground Rule 1, re-run, and by nothing else.

A module gate that is green on the new work and was never run against the baseline has answered half
the question and reported it as the whole. Re-run the baseline at every module gate, not once at the
end — a regression found three modules later costs the same to fix and much more to find.

---

## Coverage in this mode

`coverage-ledger.md`'s denominator is **the slice's BRD leaves**, never the app's. This is the one
number most likely to be read as more than it is.

State it in the ledger header, in these terms: *"N leaves across M BRDs, covering the click-and-collect
change and its blast radius. The remaining 14 modules of this app have no BRD and are not claimed by
this ledger."* A ledger that says `100% covered` without that sentence is telling the reader the app is
fully specified, and it is not.

`existing-app-assurance.md` documents four fallback levels for a missing ledger and calls **Level 4 ·
NOT APPLICABLE** the normal state for an audited app. In this mode the changed modules move up to a
real ledger and the untouched ones stay at Level 4. Both verdicts in one project is correct here, and
it is the only entry mode where that is true.

---

## Deliverables

- `PROJECT.md` — decision register, entry mode `CONFIRMED`, blast radius confirmed, Stage 7 marked N/A with its reason.
- `triage.md` — slice + blast radius, signed off.
- Knowledge base — Path D, scoped, with counts recorded.
- BRDs for the changed slice, each with as-is and to-be.
- A build plan over the slice.
- **A regression baseline that was green before the change and is green after it.** Without this the rest is unverified.
- Anything reusable learned about the app → `skills/learned-*.md`; process learnings → `process/process-learnings.md`.
