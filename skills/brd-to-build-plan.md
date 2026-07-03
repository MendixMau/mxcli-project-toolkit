# BRD to Build Plan — Plan Definition Before Scripting
**Purpose:** Turn validated BRDs + Mendix architecture into a concrete, dependency-ordered build plan — the step between architecture and the first line of MDL.
**Upstream:** `migration-pipeline.md` (phases 1–6: extraction → BRD → Mendix rearchitecture)
**Downstream:** `iterative-build-loop.md` (per-module execution against the plan produced here)
**Example:** `../examples/outsystems-migration/plan-overview.md` is the worked output of this skill

---

## When to Use This Skill

- You have `.mx-brd.json` files (Mendix-rearchitected BRDs) from `migration-pipeline.md` Phase 6
- You are about to start MDL scripting and need the build order, not just the module list
- You keep discovering architecture questions *mid-build* that should have been settled up front

If you're still deciding module boundaries or naming conventions, that's `migration-pipeline.md` Phase 6 — use `modularize-domain.md` for the boundary decision (criteria, over-split signals, one-module-plus-folders default, user sign-off). This skill assumes those are already decided and turns them into an executable plan.

---

## Why This Step Exists

A rearchitected BRD tells you *what* modules exist and *what* they contain. It does not tell you:
- What order to build them in (dependency graph)
- What granularity to script at (per-layer vs per-page)
- What's stubbed vs real for this phase
- What questions would derail a build if left unanswered until you hit them

Skipping this step means these decisions get made ad hoc, mid-script, by whoever's typing — which produces rework when module B's script assumes something about module A that turns out to be wrong.

---

## Output of This Skill

A single **build plan document** per project (or per phase, for large projects), containing:

1. Module dependency order
2. Resolved architecture questions (with the questions that were asked, not just the answers)
3. Iteration granularity decision
4. Stub/real scope boundary for this phase
5. The numbered script sequence, per module, respecting dependency order
6. Demo user / role mapping (needed before any security script)

This becomes the checklist `iterative-build-loop.md` executes against.

---

## Step 1: Build the Module Dependency Graph

From the rearchitected BRDs' cross-reference sections, build a directed graph: module A → module B means "A's microflows/pages call into B."

```
Common modules (no dependencies)
  → Domain+Logic modules (depend on Common)
    → UI-heavy feature modules (depend on Domain+Logic + Common)
      → Integration modules (depended on by feature modules, but built stub-first)
```

**Rule:** Build order follows the dependency graph, not the BRD list order. A module that nothing else depends on can be built last even if its BRD number is F001.

**Concretely, in dependency order:**
1. Master data / enumerations (zero dependencies)
2. Common/shared modules (depend only on master data)
3. Business feature modules (depend on Common + master data)
4. Integration modules (stubbed first, real implementation can slot in later without reordering)

This mirrors the BRD generation order in `migration-pipeline.md` Phase 5 — if you generated BRDs in dependency order, the build plan inherits that order for free.

---

## Step 2: Resolve Architecture Questions Before Scripting

Every project has open questions that block scripting until answered. Common ones (answer these explicitly, in writing, before script 01):

| # | Question | Why it blocks scripting |
|---|----------|------------------------|
| 1 | **Iteration granularity** — one script per layer (domain/microflows/pages) or per page cluster? | Determines script numbering scheme and rollback unit |
| 2 | **Cross-module association ownership** — which module's domain model holds each cross-module association, and when is the Studio Pro session scheduled? | mxcli cannot create these (see `bug-logs/mxcli-bugs.md` BUG-02) — must be planned as a manual step, not discovered mid-script |
| 3 | **Stub vs. real scope for this phase** — which integrations are stubbed, which are live? | Determines whether `STUB_` microflows or real `IVK_` microflows get scripted first |
| 4 | **Demo user / role mapping** — which target roles map to which source system roles? | Needed before any `GRANT` script; changing role mapping after grants means rewriting security scripts |

Add project-specific questions as they surface (e.g. "which module owns the shared application header entity?"). The rule is: **if answering it wrong would require rewriting an already-executed script, it belongs on this list and must be answered before scripting starts** — not discovered as a CE error three scripts later.

Document both the question and the resolution — future sessions (and future you) need the *why*, not just the decision.

---

## Step 3: Choose Iteration Granularity

Pick one granularity for the whole project (or per-module, if complexity varies):

| Granularity | Script unit | Best for |
|------------|------------|----------|
| **Per layer** | `01-{module}-domain.mdl`, `02-{module}-microflows.mdl`, `03-{module}-pages.mdl` | Most modules — clean rollback, manageable file count |
| **Per page cluster** | One script per page + its supporting microflows | Complex multi-section pages where partial recovery during a build session is likely |
| **Per domain (whole module in one script)** | `01-{module}-full.mdl` | Small modules only (<5 entities, <3 pages) — avoid for anything bigger |

**Default recommendation:** per-layer. Drop to per-page-cluster only for modules you already know are complex (many sections, many validation rules, heavy conditional visibility).

---

## Step 4: Set the Scope Boundary

For this build phase, explicitly list:
- **In scope, real:** integrations/features built for real this phase
- **In scope, stubbed:** integrations gated behind `CONST_STUB_*`, to be swapped later
- **Out of scope:** modules/features deferred to a later phase entirely

This becomes the reference for "is this a design gap or an intentional deferral?" during CE triage (see `iterative-build-loop.md`'s CE Error Triage section) — without it, every missing feature looks like a bug.

---

## Step 5: Produce the Numbered Script Sequence

Combine Steps 1–4 into a concrete, ordered list. Template:

```
Phase: <name>
Granularity: <per-layer | per-page-cluster | per-domain>

Module: <CommonModuleA>          (dependency order: 1 — no dependencies)
  01-<module>-domain.mdl
  02-<module>-security.mdl

Module: <CommonModuleB>          (dependency order: 2 — depends on ModuleA)
  03-<module>-domain.mdl
  ...

Module: <FeatureModule>          (dependency order: 3 — depends on Common)
  0N-<module>-domain.mdl
  0N-<module>-stub-pages.mdl     ← forward-reference stubs, always before...
  0N-<module>-microflows.mdl
  0N-<module>-pages.mdl
  0N-<module>-seed-data.mdl      ← idempotent (retrieve-before-create)

Module: <IntegrationModule>      (dependency order: 4 — stubbed first)
  0N-<module>-stub-microflows.mdl
```

Number sequentially across the whole plan, not per-module — this preserves a single audit trail matching `iterative-build-loop.md`'s "scripts are frozen once executed" rule.

---

## Step 6: Demo User and Role Mapping

Before any `GRANT` script, decide and document:

| Target role | Maps to source role(s) | Notes |
|-------------|------------------------|-------|
| e.g. `HQDomestic` | e.g. source "Domestic HQ User" | Primary demo/test user |
| e.g. `Admin` | e.g. source "System Administrator" | Used for setup only, never for happy-path testing |

**Rule:** happy-path testing in `iterative-build-loop.md` step 10 always uses the non-admin demo user — decide who that is now, not when you hit the first login screen.

---

## Handoff to the Build Loop

Once Steps 1–6 are done, the plan is ready for `iterative-build-loop.md` to execute module-by-module. The build loop's Pre-Module Checklist assumes:
- The module's position in the dependency graph is already known (Step 1)
- The 4 standing architecture questions are already answered (Step 2) — no re-litigating mid-build
- The granularity for this module's scripts is already chosen (Step 3)
- Whether each integration is stub or real is already decided (Step 4)
- Script numbers are pre-allocated per the sequence (Step 5)
- The demo user for happy-path testing is already named (Step 6)

If a build session discovers a gap in the plan (a dependency missed, a question not anticipated), fix the plan document first, then resume the build loop — don't patch it ad hoc in a script comment.

---

## Anti-Patterns This Skill Prevents

- **Bulk MDL generation from BRDs with no build plan.** Produces a mountain of scripts with no dependency order, no granularity decision, and no way to tell "was this stubbed on purpose or missed."
- **Discovering cross-module association ownership mid-script.** Always a Studio Pro operation (BUG-02) — if not scheduled, it becomes a surprise blocker.
- **Deciding role mapping after security scripts are already applied.** Forces a rewrite of every `GRANT` statement.
- **Treating every CE error as equally investigatable.** Without a scope boundary, "is this stubbed on purpose" and "is this a design gap" look identical.
