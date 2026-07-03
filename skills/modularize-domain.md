# Modularize Domain — Deciding Mendix Module Boundaries

**Purpose:** Decide *how many* Mendix modules a migrated app should have and *where the boundaries fall* — on their own merits, not by copying the source's structure. Produces a human-facing module-design rationale (HTML) and a sign-off checkpoint before boundaries are frozen into `.mx-brd.json`.

**Upstream:** `migration-pipeline.md` Phase 6 (Rearchitect to Mendix) — run this skill *inside* Phase 6, before you write the `.mx-brd.json` module assignments. If `source-triage.md` Step 5 flagged a multiple-Mendix-apps question for this migration, that gets resolved *before* this skill runs — this skill only decides module boundaries within one app.
**Downstream:** `architecture-blueprint.md` (documents the boundaries you decided here), then `brd-to-build-plan.md` (turns them into build order).
**Companion:** `design-artifacts.md` (the UI/brand half of the architecture phase).

---

## When to Use This Skill

- You have enriched BRDs (`F{NNN}.brd.json`) and are about to assign entities/logic/screens to Mendix modules.
- Someone is about to run `create module` — for each *source* file, service, controller, or BRD. **Stop and run this first.**
- You inherited a module layout and suspect it's over- or under-split.

If boundaries are already decided *and validated against the criteria below*, skip to `architecture-blueprint.md`.

---

## Why This Step Exists

**The failure this prevents:** mapping source artifacts 1:1 onto Mendix modules. Source structure reflects how the *old* codebase was organized (controllers, services, screens, BRD count) — it says nothing about correct *target* boundaries.

> **Cautionary case (IVM pilot).** Three source BRDs (`item`, `itemAction`, `itemSummary`) became three Mendix modules — one entity each. They were one bounded context: `ItemAction` references `Item`, `ItemSummary` aggregates both. The split forced a **cross-module association**, which mxcli cannot draw (BUG-02) → a manual Studio Pro handoff, plus a bespoke cascade microflow to substitute for a delete-behavior the split had broken. Collapsing to a single `Inventory` module (entities grouped, sub-areas as *folders*) deleted both problems. On a 3-entity app the cost was small; the same reflex on a 200-entity app produces dozens of chatty cross-module dependencies that are expensive to unwind.

The rule: **BRD/file/table count is never the module count.**

---

## Step 1: Gather the Inputs a BRD Cannot Contain

Module boundaries are an *organizational* decision as much as a technical one. The source and the BRDs cannot tell you these — you must get them from the user or a domain architect **before** proposing boundaries:

| Input | Why it drives a boundary |
|-------|--------------------------|
| **Team ownership** | Who owns what maps directly to modules. Separate owners → separate modules. |
| **Reuse intent** | A capability you plan to lift into another app earns its own (self-contained) module. |
| **Release cadence** | Anything that must ship independently needs its own module. |
| **Security / regulatory segregation** | A distinct access domain (customer-facing vs. back-office, PII-isolated data) earns a boundary. |

If the user can't answer these yet, that's fine — it usually means **one module** is correct for now, and boundaries can be split out later when a real driver appears. Record "no driver known" explicitly; don't invent one.

---

## Step 2: Apply the Boundary Criteria

A candidate module **earns its own boundary** only if it clears **at least one** of these:

1. **Bounded context** — a genuinely distinct business capability (Sales vs. Inventory vs. Finance), not a sub-feature of one.
2. **Reuse** — you'd lift it into another app as-is.
3. **Independent lifecycle / ownership** — a different team or release cadence owns it (from Step 1).
4. **Security segregation** — a distinct access domain (from Step 1).
5. **Size** — a single context genuinely exceeds **~15–20 persistent entities** (Mendix's own MPR003 threshold flags >15).

If a candidate clears **none**, it does **not** get its own module.

### Over-split signals (merge these)
- Two entities that are **always used together** sit in different modules → you get a **cross-module association** (the BUG-02 pain, plus module coupling).
- A module holds **~1 entity** and nothing reusable.
- A module exists only because the *source* had a matching file/service/BRD.
- You're writing a microflow purely to bridge a boundary you created (e.g. a cascade-delete substitute).

### Under-split signals (split these)
- One module past ~15–20 persistent entities with clearly separable sub-domains.
- One module mixing a customer-facing access domain with back-office data.
- Distinct teams editing the same module and colliding.

---

## Step 3: Default to One Module + Folders

When no candidate clears the Step 2 bar (common for small/medium migrations), the answer is **one module**, with **folders** for sub-areas (`Items/`, `Transactions/`, `Reporting/`). Folders give the organizational clarity of the source grouping with **none** of the boundary cost:

- entities share one domain model → associations stay intra-module (no BUG-02, delete behavior "just works"),
- one security scope, one navigation contribution,
- documents (pages, microflows) still grouped legibly via `MOVE ... TO FOLDER`.

Reserve folders for pages/microflows/etc.; entities all live in the module's single domain model (that co-location is the point — the relationships are visible in one diagram).

---

## Step 4: Produce the Module-Design Rationale (HTML) + Get Sign-off

Boundaries are a decision the user must own. Present them for feedback **before** freezing — don't announce them after.

Write `architecture/module-design.html` in the project workspace. It is the human-facing sign-off artifact. For each proposed module, show **not just what, but why**:

- **Module name + one-line mission.**
- **The business process / user journeys it serves** (which actors, which flows).
- **Users / roles** who touch it (ties to the security-segregation criterion).
- **Closely-tied data** — the entities it owns and the associations *within* it (the cohesion argument).
- **Dependencies** — which other modules it may import, and explicitly **why there are no cross-module associations** for tightly-coupled data (or, if there are, the justification + the planned Studio Pro handoff).
- **Which Step 2 criterion earned the boundary** (or "single module — no criterion met, folders used").
- **Rejected alternatives** — e.g. "considered splitting Transactions out; rejected because it shares the Item association."

Match the project's design system if one exists (`design/design-system.html`): reuse its CSS variables (palette, fonts, radii, light+dark). Self-contained single file, no external assets. Keep it a **rationale document**, not a dashboard — cards + prose, one section per module, a dependency summary, and a closing **"Does this match how your teams and processes are actually organized?"** feedback prompt listing the Step 1 inputs so the reviewer can correct any assumption.

**The checkpoint is mandatory:** share the HTML, ask the four Step 1 questions explicitly, and **wait for confirmation** before writing `.mx-brd.json` boundaries or running any `create module`. Record the user's answers (and any correction to your proposed split) in `architecture/open-issues.md`.

---

## Checklist Before Freezing Boundaries

- [ ] Step 1 org-context inputs gathered (or "no driver known" recorded).
- [ ] Every proposed module clears ≥1 Step 2 criterion, or the design is a single module + folders.
- [ ] No over-split signal present (especially: no cross-module association for always-together entities).
- [ ] `architecture/module-design.html` written, with per-module *rationale* (process, users, tied data, dependencies, criterion).
- [ ] HTML shared with the user, four Step 1 questions asked, **confirmation received**.
- [ ] Decision + user answers recorded in `architecture/open-issues.md`.
- [ ] Only then: write `.mx-brd.json` boundaries → hand off to `architecture-blueprint.md`.
