# CAC-5 — Build Plan Checkpoint

**Fires after:** Design sign-off (design-artifacts.md complete)
**Feeds into:** `brd-to-build-plan.md` + Phase 7 MDL generation
**Template:** See `checkpoint-template.md` for format rules.

---

## Close out Stage 4 first

This checkpoint fires at the close of Stage 4. Open the message with the generated block —
`bin/gate-check.sh --closeout <project-root> 4` — pasted as-is (`checkpoint-template.md`
→ "Stage close-out and stage open"). It carries the plan, brief and ledger as produced (or
PENDING), every Stage-4 decision, everything still open going into the build, the Stage-4
gate line in plain words, and the Stage-5 open: what the build does and how it is worked
and tested (snapshot → exec → mxbuild gate → happy path per script; build, gate, prove, LOOK
per module with the denominator stated; live checklist in chat throughout), the governing
skills and instruments, and the optional artifacts on offer. The brainstorm below then
starts from a reader who knows where the project stands.

## What to Surface

Pull from all `.mx-brd.json` files and design decisions:
- Full POC scope: modules, entity count, microflow count, page count
- Dependency order already determined by `modularize-domain.md`
- Any deferred items (marked in BRDs as post-POC, flagged in validation)
- Known tech-debt items from enrichment (`mendixNotes` entries)

## What's Next

`brd-to-build-plan.md` turns `.mx-brd.json` + design decisions into a dependency-ordered,
numbered build plan (which layer1 scripts first, which microflows before which pages).
Phase 7 MDL generation follows the build plan strictly — no ad-hoc ordering.

---

## Brainstorm First (before any predefined question)

This checkpoint opens with a **divergent conversation** about build scope. Present the
module/script map from the build plan with rough effort per module, then genuinely discuss:

- Build everything in the plan, or a subset first? What ordering delivers value soonest?
- Anything to add that the plan missed, or to defer/kill now that you see the full list?
- Any constraints the plan should bend around — deadlines, demos, people?

No option lists — iterate until the user says the plan's scope feels right. Then run the
predefined questions below to record it, and quote any Stage-3/4 decisions being reused
(never skip silently — see checkpoint-template.md's skip conditions).

## Predefined Questions

### Q1 — MDL layer strategy

**When to ask:** Always.

**How to generate options:** Count entities + enumerations (layer1), microflows (layer2), pages
(layer3). If page count > 5, suggest generating pages in batches.

**Hard rule regardless of the answer:** this question decides the *drafting unit within a phase*,
never the gate cadence. MDL for phase N is drafted only after phase N−1 has passed its full gate
(exec.sh mxbuild gate + SP reopen + happy-path verification) — no option below authorizes writing
all scripts upfront. See `brd-to-build-plan.md` ("The build plan contains no MDL").

> "We have [N] entities, [M] microflows, [P] pages to generate. Within each phase, how should we approach MDL drafting?"
> - A) Phase-by-phase in dependency order — draft + exec + verify each phase before drafting the next *(recommended — default)*
> - B) Layer by layer with review between — generate layer1, validate, then layer2, then layer3
> - C) Feature-by-feature — complete one BRD end-to-end before moving to the next

**Record as:** `PROJECT.md` → `## Decisions` → `MDL generation strategy:`

---

### Q2 — Security setup timing

**When to ask:** When security level in BRDs is Production or Prototype (not Off/Demo).

**Skip if:** All BRDs have security marked as Demo or Off (POC-only, no role enforcement needed yet).

**How to generate options:** Check which module roles and user roles were defined in BRDs.

> "Security roles are defined for [N] modules. When should we wire up security?"
> - A) Layer 1 — create roles and grants immediately after domain model *(recommended — catch issues early)*
> - B) Last — build everything first, add security as a final step
> - C) Per-feature — add security immediately after each feature's MDL is complete

**Record as:** `PROJECT.md` → `## Decisions` → `Security setup timing:`

---

## Optional artifacts for Stage 5 (the Offer — ask after Q2, before the open question)

> "Before the first script: anything else you want written down?"
> - Demo script — the narrated walk-through a human will give: beats, pages, fixtures on
>   screen, what the audience must see happen *(recommended whenever the open question below
>   names a demo — the build then front-loads what the demo needs)*
> - Test plan (if not taken at the Stage-4 open) — per module: journeys to prove, fixtures,
>   DB assertions, edge cases
> - Acceptance criteria per module (if not taken at the Stage-4 open) — what "done" means
>   beyond CE-error-free
> - Something else — name it

**Record as:** `Opt-in artifact <id>: <why>` lines in `PROJECT.md` (`demo-script`,
`test-plan`, `acceptance-criteria`), or `Optional artifacts: none for Stage 5` as a Stage-4
decision.

## Open Question

> "Is there a deadline, a demo milestone, or a specific feature that must be working first?
>
> If yes — name the feature and the date. We'll front-load it in the build plan.
> If no — say 'no deadline' and we'll optimize for dependency order."

**What to do with the answer:**
- If a deadline is given: convert to absolute date, record in `PROJECT.md` under `## Decisions` → `Deadline:`
- If a specific feature is prioritized: move its BRD to top of build order in `brd-to-build-plan.md`, even if it creates a non-ideal dependency order
- If 'no deadline': proceed with pure dependency-ordered build plan

---

## Decision Recording

```
PROJECT.md → ## Decisions:
  MDL generation strategy: [phase-by-phase / layer-by-layer / feature-by-feature]
  Security setup timing: [layer1 / last / per-feature]
  Deadline: [date or 'none']
  Priority feature: [name or 'none']
  Optional artifacts: [none for Stage 5 | one "Opt-in artifact <id>: <why>" line per artifact taken]
```
