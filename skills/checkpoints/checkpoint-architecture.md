# CAC-3 — Architecture Checkpoint

**Fires after:** Phase 5 BRD Enrichment + Validation
**Feeds into:** Phase 6 Rearchitect to Mendix (.mx-brd.json via `modularize-domain.md`)
**Template:** See `checkpoint-template.md` for format rules.

---

## Close out Stage 2 first

This checkpoint fires at the close of Stage 2. Open the message with the generated block —
`bin/gate-check.sh --closeout <project-root> 2` — pasted as-is (`checkpoint-template.md`
→ "Stage close-out and stage open"). It carries the BRDs produced, the Stage-2 decisions,
every question still open (with the status word that keeps it open), the Stage-2 gate line
in plain words, and the Stage-3 open: what architecture and design will do, how (propose
with evidence, you confirm at the ✋ gate, nothing touches the .mpr), its checkpoints (CAC-4
before any design system), the governing skills, and the optional artifacts on offer.

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
>   *(recommended)* — flags the module's build brief to read `learned-workflow-patterns.md` first
> - B) Microflows only — simpler, no Workflow module dependency; the lifecycle lives in a status
>   enum plus transition microflows
> - C) Flag for manual review — decide per process

**Both A and B produce the state diagram in the blueprint (`architecture-blueprint.md` Step 3b).**
The answer decides the *implementation*, never whether the process gets drawn — a native Workflow
at least renders itself in Studio Pro, while an enum-driven lifecycle is drawn nowhere by anything
else, so B needs the diagram more, not less. (Measured cost of bundling them: a six-state,
role-gated lifecycle built under option B with no picture of it anywhere in the project.)

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

## Optional artifacts for Stage 3 (the Offer — ask after Q3, before the open question)

Stage 3 is where the pictures get drawn, so this is the checkpoint where people most often
wish afterwards that they had asked for one more. The close-out block lists what is on offer
(the `optin` rows of `bin/lib/artifact-manifest.tsv` for stage 3); ask it as one multi-select
question, recommended options first, derived from the BRDs the same way Q3's signals are:

> "Beyond the blueprint, fit-gap, design system and wireframes, which of these do you want
> defined before we build?"
> - Workflow design — one state diagram per process: states, transitions, who moves it, SLA
>   *(recommended whenever Q3's workflow half found signals — under option B it is the only
>   picture of the lifecycle anywhere)*
> - Swimlanes — who does what per process, one lane per role *(recommended when the BRDs
>   carry more than one persona)*
> - Sequence diagrams — per integration or agent call: caller, microflow, external system,
>   sync/async, timeout, fallback *(recommended whenever Q3's agent-wiring half found signals)*
> - Entity diagram across modules (ERD) *(recommended when Q2 fired — shared entities)*
> - NFR sheet — target, how measured, where enforced *(recommended when the open question
>   below comes back non-empty)*
> - Integration contracts — endpoint, auth, payload, errors, test double, per integration
> - Something else — name it

**Record as:** one `Opt-in artifact <id>: <why>` line in `PROJECT.md` per artifact taken
(ids: `workflow-design`, `swimlanes`, `sequence-diagrams`, `erd`, `nfr-sheet`,
`integration-contracts`), and `Optional artifacts: none for Stage 3` as a Stage-2 decision
when nothing is taken — so the next session does not re-offer. A taken artifact is then
owed like any other: `architecture-blueprint.md` produces it alongside the blueprint, and
the artifact check reports it PENDING until it exists.

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
  Optional artifacts: [none for Stage 3 | one "Opt-in artifact <id>: <why>" line per artifact taken]
```
