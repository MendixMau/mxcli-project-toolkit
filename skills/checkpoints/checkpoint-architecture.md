# CAC-3 — Architecture Checkpoint

**Fires after:** Phase 5 BRD Enrichment + Validation
**Feeds into:** Phase 6 Rearchitect to Mendix (.mx-brd.json via `modularize-domain.md`)
**Template:** See `checkpoint-template.md` for format rules.

---

## What to Surface

Pull from validated `F{NNN}.brd.json` files:
- Total: entities, enumerations, microflows, pages, cross-module associations
- Any entity referenced by 3+ BRDs (candidate for a Common/Shared module)
- Any BRD with 0 cross-module dependencies (can be built independently)
- Resolved open questions that affect architecture (e.g. auth strategy, data ownership)

## What's Next

`modularize-domain.md` maps feature BRDs to Mendix module boundaries — this is NOT a 1:1 mapping.
The decisions made here determine module names, cross-module associations, and the Common module
strategy before `.mx-brd.json` files are written.

---

## Predefined Questions

### Q1 — Module split strategy

**When to ask:** Always.

**How to generate options:** Count entities per BRD and cross-BRD associations.
- If all BRDs have isolated entities: suggest feature-module-per-BRD
- If many cross-BRD associations: suggest a Common domain module
- If one BRD is much larger: suggest splitting it

> "Given [N] features with [M] cross-module associations, how should we structure the Mendix modules?"
> - A) One module per feature ([Auth, Accounts, Transactions]) *(recommended — matches BRD boundaries)*
> - B) One module per feature + a Common module for shared entities ([Auth.User] is shared)
> - C) Single module for POC — simplest, refactor later

**Record as:** `PROJECT.md` → `## Decisions` → `Module structure:`

---

### Q2 — Cross-module data strategy

**When to ask:** When 2+ BRDs reference the same entity across module boundaries (e.g. Auth.User
referenced by Accounts and Transactions).

**Skip if:** All entity references are within a single module.

**How to generate options:** Show which entity is shared and by how many modules.

> "[Auth.User] is referenced by [N] modules. How should cross-module access work?"
> - A) Direct association (Mendix cross-module CREATE ASSOCIATION) *(recommended for POC)*
> - B) Duplicate a lightweight UserRef entity in each module — looser coupling, more data
> - C) Expose via OData/REST between modules — needed only for multi-app architecture

**Record as:** `PROJECT.md` → `## Decisions` → `Cross-module strategy:`

---

## Open Question

> "Are there non-functional requirements we should design around? (e.g. 'this must handle 10k
> concurrent users', 'must integrate with [system X] before launch', 'must run on-prem',
> 'must be certified for [standard]'). Drop them here or say 'none for POC.'"

**What to do with the answer:**
- Add to `project-profile.md` under `## Non-Functional Requirements`
- Flag any that directly affect module structure (e.g. multi-tenancy → affects all XPath constraints)
- Note deferred NFRs in `PROJECT.md` so they aren't lost

---

## Decision Recording

```
PROJECT.md → ## Decisions:
  Module structure: [list of Mendix modules]
  Cross-module strategy: [chosen approach]
  NFRs: [list or 'none for POC']
```
