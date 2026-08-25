# Module Brief — The mdl-agent's Single Entry Point Per Module
**Applies to:** any mxcli project entering the build loop.

**Purpose:** Collapse the 6+ sources an `mdl-agent` would otherwise synthesize at script time
(BRDs, wireframes, blueprint, build plan, existing domain MDL, access table) into **one document
per module** that the agent reads first. The brief is a *synthesis and index* — it points to the
source-of-truth artifacts and synthesizes the per-module decisions that live nowhere else. It is
the fix for improvised synthesis: the moment an agent guesses because the answer wasn't written
down anywhere it could read.

**Upstream:** `brd-to-build-plan.md` (build plan + role-to-access table), `architecture-blueprint.md`
(module boundaries, fit-gap), `design-artifacts.md` (wireframes, design system)
**Downstream:** `iterative-build-loop.md` (the brief is the per-module input its Pre-Module
Checklist requires), `ui-preflight-pages.md` (the brief's UI pointers name the exact wireframe files),
`module-review.md` (the pass that defines "done" for the module this brief opens — see
"Ready-check" below: the brief's own checklist is a *pre-build* gate, not the closing one)

---

## Why This Exists

A rearchitected BRD says *what* a module contains. The build plan says *what order* to build in.
Neither says, in one place: which roles touch this module, which screens each role reaches, what
each field's validation rule is, which wireframe maps to which page, what CRUD each module role
gets. That translation — business requirements → module-level Mendix decisions — is real work, and
until now it had no home. It happened in chat, or it didn't happen and the `mdl-agent` improvised
it from training data. Every access-rights, wrong-class-name, and bad-binding incident traces to
that missing translation.

The brief gives that translation a durable home, produced by the domain expert (`ba-agent`), read
by the builder (`mdl-agent`).

---

## Ownership: BA Drives, Pulls Architect

The brief is business-rule-heavy, so **`ba-agent` owns the file** and writes the business layer.
It pulls `architect-agent` for the technical layer. One owner, two contributors:

| Layer | Author | Contents |
|-------|--------|----------|
| **Business** | `ba-agent` (translation mode) | User journeys per role · screens-per-role map · field-level validation rules · edge cases / error paths · the access-table slice for this module · open business questions |
| **Technical** | `architect-agent` (requested by ba-agent) | Entities/attributes/associations for this module (summary + pointer to domain MDL for exact names) · CLI-vs-MCP write mode per element · cross-module dependencies · stub-vs-real integrations · arch constraints that apply here |

`ba-agent` in **translation mode** is distinct from its **extraction mode** (Stages P–2, producing
BRDs from source/SME). Translation mode runs at Stage 4 and turns validation-clean BRDs into this
brief. If you have BRDs but no briefs, translation mode was skipped — that is the gap this skill
closes. See `agent-roles.md`.

---

## Synthesis, Not Duplication

The brief **points to** the source of truth and **synthesizes** only the decisions that live
nowhere else. This keeps drift risk low: when a wireframe or the domain model changes, the brief's
pointer still resolves; only the synthesized decisions (which are module-local anyway) need review.

- **Point to** (never copy): wireframe HTML files, blueprint sections, BRD JSONs, the domain-model
  MDL, the numbered build-plan scripts.
- **Synthesize** (lives only here): the per-module access table, screens-per-role map, field-level
  validation rules, edge cases, the write-mode plan per element, open questions.

If you find yourself pasting a wireframe's full widget list or the domain model's full attribute
list into the brief, stop — link it instead and synthesize the *decision* about it.

---

## Location & Timing

- **Location:** `architecture/modules/<ModuleName>/module-brief.md` — one directory per module, holding its brief (and any per-module assets alongside it).
- **Timing (just-in-time):** the brief for module N is produced only after module N−1 has passed
  its full build gate. Same rule as MDL phasing (`brd-to-build-plan.md`) — a brief written against
  a model state that later changes is a brief that lies. The **first** module's brief is produced
  at Stage 4 alongside the build plan; the rest are produced as each module's build begins.
- Do **not** stockpile all briefs upfront. `gate-check.sh` cannot mechanically require all briefs
  at Stage 4 for this reason. It is not a manual-only check any more, though: the brief is **row 0
  of its module's phase** (`brd-to-build-plan.md` Step 5), and `project-bin/exec.sh` guard 5
  refuses any write to a module that has no brief. Row 0 placement is what makes the guard
  unreachable in the normal flow — early enough to be an input, late enough not to be speculative.
- **Single-module projects: merge the brief into the build plan** under a `## Module brief — <M>`
  heading (the exec guard accepts that form). Two documents at ~70% overlap is how one goes
  unwritten.

---

## Brief Format

```markdown
# Module Brief — <ModuleName>

- **Dependency order:** <N> (depends on: <ModuleA, ModuleB>)
- **Build status:** not started | in progress | gated
- **Toolkit commit:** <HEAD sha at authoring — for freshness>

## Pointers (source of truth — read these, don't duplicate them)
- Wireframes:   design/wireframes/<file>.html, <file2>.html
- Blueprint:    architecture/blueprint.md#<section>
- BRDs:         analysis/<source>/knowledge-base/F<NNN>.brd.json
- Domain MDL:   mdlsource/<NN>-<module>-domain.mdl
- Build-plan scripts: <the numbered scripts for this module>

## Business layer  (ba-agent)
### Roles & journeys
| Role | What they do in this module | Entry screen |
|------|-----------------------------|--------------|

### Screens per role
| Screen (→ wireframe file) | Roles that reach it | Nav wire point |
|---------------------------|---------------------|----------------|

### Access table  (feeds co-located grants — see brd-to-build-plan.md)
| Element | Type | Module role(s) | Access level |
|---------|------|----------------|--------------|

### Field-level validation & edge cases
| Field / action | Rule | Error path |
|----------------|------|-----------|

### Golden-path data effects (what each key action must persist)
| Action | Creates/changes | Associations that MUST be set |
|--------|-----------------|-------------------------------|
| e.g. Scan barcode | new TransportOrder | `TransportOrder_TransportUnit`, `TransportOrder_SourceLocation` |
<!-- A scoped journey that creates an object almost always must link it. An order created with no
     association to the unit/location it's for is a broken golden path even though it "saved" — a real
     WMS incident. List every association the action must set here so the mdl-agent writes them and
     the review loop can verify them. Note: inline assoc-sets hit learned-mdl-preflight rule 9 (route
     to `--mcp`, never drop the set to dodge the STOP) on mxcli v0.16.0 — resolved in v0.17.0, see
     rule 9's 2026-08-11 update; check which binary the target project is pinned to before assuming
     either behavior. -->

### Open business questions
- [ ] <anything unresolved — mdl-agent must escalate, not guess>

## Test plan  (ba-agent drafts, confirmed with the user at brief sign-off)

**This section is not optional and may not be left blank.** Without it nothing per module says
what testing this module means, and the answer degrades to "whatever the harness happened to run"
— which is how an end-to-end run executes journeys, DB assertions and a monkey pass, reports them
all, and never looks at a page.

### Declared shape  (vocabulary and rules: `testing-shape.md` §1–2)
| Part | This module | Why |
|------|-------------|-----|
| UI (Playwright) | **always** | — |
| Data (source of truth) | **always** — say which: OQL count delta \| upstream REST response \| documented n/a + the query proving it | `testing-shape.md` §1: "Data" means check the source of truth, not always query a database |
| Unit (`.test.mdl`) | yes / no | the project default from intake, unless this module has fiddly calculation or mapping logic |
| Trace (OTel) | yes / no | **yes if this module calls out** to REST, an import mapping, or external data — that is where failures get swallowed, and it overrides the project default |

### Base set — the trigger  (`testing-shape.md` §3)
The named scripts that constitute this module's base logic. **When every script in this list is
done, testing opens.** Scripts added later do not move the goalpost, because the goalpost was
placed before they existed. This list must cover the module's coverage checklist — otherwise two
scripts get declared "base", the suite goes green, and the module isn't built.

- [ ] `<NN-script-name.mdl>`
- [ ] `<NN-script-name.mdl>`

### Journeys  (compiled to `journeys/<Module>.journey.json`)
One row per golden path. **The steps come from the Roles & journeys table above and the data
effects come from the Golden-path table above — this is a projection of those two, not a third
hand-authored list.** Step ids are stable and are what the journey JSON keys on.

| Journey id | Persona | Trigger → outcome | Steps (from Roles & journeys) | Data effect asserted (from Golden-path) |
|---|---|---|---|---|
| e.g. `receive-order` | Operator | scans a unit → order exists and is linked | 1 open list · 2 scan · 3 confirm | +1 TransportOrder with both associations set |

Cross-module journeys do **not** live here — a journey that fits in one module is a use case; one
that crosses modules belongs to the process-level artifact (`journey-map.md`) and is exercised by
`process-coherence-pass.md`, not by this brief.

### Interactive elements — the wiring sweep's denominator  (`wiring-sweep.md`)

Journeys walk the golden path. **The bugs are in the affordances no journey walks** — a button
that renders, styles and reads correctly and does nothing when clicked. The sweep enumerates them
mechanically (`mxcli playwright snapshot`), so this brief does not list elements; it records the
claim the sweep must be able to make:

> `N of N interactive elements swept across P of P pages in <Module>`

That line is the first line of `.claude/loop/sweep/<Module>/sweep.md`, and a sweep report without
it is **fault**, not pass. Sampling is not sweeping — "clicked the main buttons" discharges
nothing. If some affordance genuinely cannot be exercised (needs a third-party callback, needs
production data), name it here at brief time so the sweep can report it as a known exclusion with
its reason, rather than as a silent shortfall in the denominator.

| Known exclusion | Why it cannot be swept |
|---|---|
| _(usually none — leave empty rather than inventing rows)_ | |

### Pages to LOOK at  (`module-review.md` stage 4)
Derived from the model at review time (`SHOW PAGES IN <Module>`), **not** listed here — a copy
would go stale the first time a page is added. What this brief owes stage 4 is the *intent* each
screen was built to serve, which the "Screens per role" table above already carries. If a screen
in that table has no wireframe, say so there: it tells the reviewer to use §4d's unaided rubric
rather than wondering whether they missed a file.

## Technical layer  (architect-agent)
### Domain summary (exact names live in the domain MDL — link above)
- Entities: <names> · key associations: <names>

### Build skills to read first  (every build group, not just Workflow/Agent)
<!-- Populated by matching this module's element types against bin/lib/skill-routing.tsv — ALL of
     its build groups: build/integration, build/pages, build/mdl, build/workflow, build/agents.
     Never leave silently empty — say "none detected for this module" explicitly, same stop-sign
     convention as Open business questions.

     WHY THIS IS NOT WORKFLOW/AGENT-ONLY ANY MORE. It was, and integration fell straight through
     the gap. A customer training round, 2026-08-25: the module built a REST-fed filterable DataGrid,
     skill-routing.tsv had rest-integration-first-time-right.md sitting in build/integration, and
     because this field only asked about Workflow and Agent decisions nothing ever named it. All
     15 `import from mapping` calls shipped with the range keyword omitted (silent EMPTY, clean at
     check/--references/mxbuild/runtime) and all 4 wrapper associations pointed child->parent. A
     day of debugging for two rules that were written down three days earlier.

     This is a ROLL-UP, not a second authoring pass: it is the union of the Skills field on this
     module's build-plan rows (brd-to-build-plan.md "Row schema"). Author at row level, collect
     here. 77 of 101 skills are ondemand — a project only ever meets the ones something names. -->
- <e.g. "This module builds a native Workflow → read skills/learned-workflow-patterns.md and
  skills/learned-mdl-preflight.md STOP #18/#19 before scripting.">
- <e.g. "This module calls an AI agent (see architecture/blueprint.md Step 3c) — no toolkit skill
  exists yet for this pattern. Escalate to ba-agent/architect-agent before scripting; the first
  real build here should produce one.">

### Write-mode plan (per learned-mdl-preflight.md Step 0)
| Element | CLI / MCP+MDL / hand-rolled MCP | Why |
|---------|--------------------------------|-----|

### Document folder plan  (layout: module-folder-convention.md — feature group, then type)
<!-- Type folders: Pages | Microflows (nanoflows too) | Services | Resources, plus
     module-level Common/. module-folder-convention.md carries the per-type table, incl.
     which types mxcli can place at creation and which need a MOVE or Studio Pro. -->
- **Feature groups:** <RouteDefinition, Sequencing, Assignment> · plus `Common/` if module-wide docs exist

| Document | Folder |
|----------|--------|
| e.g. Route_Overview | `RouteDefinition/Pages` |
| e.g. ACT_Route_Save | `RouteDefinition/Microflows` |
| e.g. SUB_Route_Publish | `RouteDefinition/Services` |
| e.g. RouteStatus (enum) | `RouteDefinition/Resources` — no create-time folder, needs `move enumeration` |
<!-- Naming the feature groups is an ARCHITECTURE call, which is why it lives here and not in the
     mdl-agent. An agent improvising a group per script is how one module ends up with three
     schemes. One row per document to be built in this phase; the mdl-agent copies the path into
     the `folder` property and never invents one. A document with no row and no derivable feature
     (module-folder-convention.md, "Deciding the path") is escalated, NOT swept into Common/. -->


### Cross-module dependencies & integrations
- Depends on: <ModuleX.Entity via assoc> · Integrations: <stub | real>

### Arch constraints that apply here
- <module boundary rules, security scoping, etc.>

## Ready-check  (all must be true before mdl-agent reads this)
- [ ] Every screen has a wireframe file that exists
- [ ] Access table covers every page, microflow, and entity to be built
- [ ] No open business question blocks the elements in this build phase
- [ ] Write mode chosen for every element that hits a learned-mdl-preflight STOP row
- [ ] Folder plan names the module's feature groups and covers every document to be built
- [ ] Test plan complete: shape declared, base set named and covering the coverage checklist, at least one journey with its data effect
- [ ] Build skills to read first is filled in — or explicitly says "none detected" — for every
      build group this module touches (integration, pages, mdl, workflow, agents), not just
      Workflow/Agent-wiring. It must agree with the union of the Skills field on this module's
      build-plan rows
```

**This Ready-check gates the start of the build, not the end of it.** This brief's job is
finished once `mdl-agent` has enough to build without guessing. **The module is not "done" when
this checklist is satisfied** — it is done when `module-review.md`'s five-stage pass (build, gate,
prove, LOOK, confirm) closes clean against what this brief specified. A `module-review.md` finding
that traces back to a gap in this brief (an access table row that was wrong, a screen the wireframe
never covered) is fed back here, not silently fixed in the model with the brief left stale.

---

## How the mdl-agent Uses It

1. **Step 1 of every build task:** read the module brief. It replaces "read the task spec and hunt
   for context" — the brief *is* the context, pre-synthesized.
2. **Gap escalation, not guessing:** if a business rule the agent needs is missing or an open
   question is unresolved, the agent surfaces the specific question to `ba-agent` (which updates the
   brief) — it never fills the gap from training data. This is why the brief has an explicit "open
   business questions" section: an unchecked box is a stop sign, not a suggestion.
3. **Not every session needs `ba-agent` live:** a complete brief means the `mdl-agent` reads and
   goes. `ba-agent` is the escalation path for gaps found at script time, not a standing
   participant on every script. Domain/security/nav scripts rarely escalate; business-logic
   microflows and conditional-visibility pages are where gaps surface.
4. **No MDL to write?** The brief still applies — the main session reads it directly before MCP
   work. If there is no build at all (analysis, config, investigation), the brief isn't relevant.

---

## Anti-Patterns This Skill Prevents

| Anti-pattern | What goes wrong |
|---|---|
| mdl-agent synthesizing 6 sources at script time | Improvised access rights, invented class names, wrong bindings — every incident logged to date |
| BA agent stops at BRDs ("the spec exists, my job is done") | Translation mode never runs; the brief is never produced; the builder inherits the translation and guesses |
| Copying wireframe/domain content into the brief | Duplication → drift when the original changes; the brief must point and synthesize, not copy |
| Stockpiling all module briefs at Stage 4 | Briefs written against a model state that changes in Phase 1 → they lie; produce just-in-time |
| mdl-agent guessing past an open question | The unchecked question box is a stop sign; escalate to ba-agent, which updates the brief |
| Brief with an incomplete access table | Silently inaccessible pages/microflows — mxbuild produces no CE error for a missing grant |
