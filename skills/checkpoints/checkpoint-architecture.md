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

### Q3 — Workflow & Agent-Wiring scope

**When to ask:** Always. Before asking, scan every validated BRD (`F{NNN}.brd.json`, or the
BRD markdown for hand-authored/SME-sourced BRDs — this runs in all three entry modes, not just
migration) for two independent signal groups:
- *Workflow-shaped:* approval, escalation, SLA, user task, hand-off between roles over time,
  "waits for", queue-and-claim language.
- *Agent-shaped:* AI agent, LLM, copilot, assistant, autonomous, chatbot, "ask the model".

This generalizes `checkpoint-brd.md`'s existing state-machine question (which only fires from
migration scaffold detection) to fire from BRD *content* in every entry mode.

**Skip if:** zero signals in both groups — still record that explicitly ("no workflow/agent scope
detected") so a later reviewer sees it was checked, not missed.

**How to generate options:** cite which BRDs/features triggered each signal group.

**Workflow half** (reuses `checkpoint-brd.md`'s phrasing):

> "Found [N] workflow-shaped requirements (approval/escalation/SLA language) in [BRDs]. How should
> these map to Mendix?"
> - A) Native Mendix Workflow for the human-approval parts, microflows for automated transitions
>   *(recommended)* — produces a workflow diagram in the blueprint (`architecture-blueprint.md`
>   Step 3b) and flags the module's build brief to read `learned-workflow-patterns.md` first
> - B) Microflows only — simpler, no Workflow module dependency, no extra diagram
> - C) Flag for manual review — decide per process

**Agent-wiring half:**

> "Found [M] agent-wiring signals (AI agent/LLM/copilot language) in [BRDs]. Is this a real,
> scoped integration point?"
> - A) Yes — document which module/microflow calls the agent, sync/async, timeout/fallback, and
>   produce an agent-wiring diagram (`architecture-blueprint.md` Step 3c), and flag the module's
>   build brief to read `skills/mendix-agents.md` first — an agent is runtime data, not a model
>   document, so none of it is declarable in MDL and mxbuild stays green when it is wrong
> - B) No — just terminology in a user story, not a real integration
> - C) Not yet — flag as an open question, decide once the integration is scoped

**Record as:** `PROJECT.md` → `## Decisions` → `Workflow scope:` / `Agent-wiring scope:`, each
listing which BRDs/features triggered it and the chosen option.

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
  Workflow scope: [BRDs/features triggered + chosen option, or 'none detected']
  Agent-wiring scope: [BRDs/features triggered + chosen option, or 'none detected']
  NFRs: [list or 'none for POC']
```
