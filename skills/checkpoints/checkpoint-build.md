# CAC-5 — Build Plan Checkpoint

**Fires after:** Design sign-off (design-artifacts.md complete)
**Feeds into:** `brd-to-build-plan.md` + Phase 7 MDL generation
**Template:** See `checkpoint-template.md` for format rules.

---

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

## Predefined Questions

### Q1 — MDL layer strategy

**When to ask:** Always.

**How to generate options:** Count entities + enumerations (layer1), microflows (layer2), pages
(layer3). If page count > 5, suggest generating pages in batches.

> "We have [N] entities, [M] microflows, [P] pages to generate. How should we approach MDL generation?"
> - A) Full generation in dependency order — all layers in one session *(recommended for < 20 items)*
> - B) Layer by layer with review between — generate layer1, validate, then layer2, then layer3
> - C) Feature-by-feature — complete one BRD end-to-end before moving to the next

**Record as:** `pipeline-state.md` → `## Decisions Made` → `MDL generation strategy:`

---

### Q2 — Security setup timing

**When to ask:** When security level in BRDs is Production or Prototype (not Off/Demo).

**Skip if:** All BRDs have security marked as Demo or Off (POC-only, no role enforcement needed yet).

**How to generate options:** Check which module roles and user roles were defined in BRDs.

> "Security roles are defined for [N] modules. When should we wire up security?"
> - A) Layer 1 — create roles and grants immediately after domain model *(recommended — catch issues early)*
> - B) Last — build everything first, add security as a final step
> - C) Per-feature — add security immediately after each feature's MDL is complete

**Record as:** `pipeline-state.md` → `## Decisions Made` → `Security setup timing:`

---

## Open Question

> "Is there a deadline, a demo milestone, or a specific feature that must be working first?
>
> If yes — name the feature and the date. We'll front-load it in the build plan.
> If no — say 'no deadline' and we'll optimize for dependency order."

**What to do with the answer:**
- If a deadline is given: convert to absolute date, record in `pipeline-state.md` under `## Decisions Made` → `Deadline:`
- If a specific feature is prioritized: move its BRD to top of build order in `brd-to-build-plan.md`, even if it creates a non-ideal dependency order
- If 'no deadline': proceed with pure dependency-ordered build plan

---

## Decision Recording

```
pipeline-state.md → ## Decisions Made:
  MDL generation strategy: [full / layer-by-layer / feature-by-feature]
  Security setup timing: [layer1 / last / per-feature]
  Deadline: [date or 'none']
  Priority feature: [name or 'none']
```
