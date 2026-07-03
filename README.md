# mxcli-project-toolkit

Shared skills, prompt templates, and learnings for **Mendix migration and development projects**.

Used across all mxcli-powered projects — OS migrations, Java/Angular migrations, and other client integration work.

---

## How a migration flows through this toolkit

Every migration moves through the same stages, regardless of source stack. Each stage has one skill that owns it, and each skill hands a concrete artifact to the next:

```
0. TRIAGE               source stack → coverage decision + bounded scope, signed off
   (source-triage.md, checked against assess-migration.md's inventory)
        │
        ▼
1. ANALYSIS            source code/docs → extracted JSON + KB markdown
   (migration-pipeline.md, source-*.md, kb-generation.md)
        │
        ▼
2. REQUIREMENTS         KB + extracted JSON → validated BRD JSON (per module)
   (brd-generation.md, brd-validation.md)
        │
        ▼
3. ARCHITECTURE & DESIGN   BRD → Mendix module boundaries, diagrams, fit-gap, design system
   (modularize-domain.md → architecture-blueprint.md + design-artifacts.md, run in parallel)
        │
        ▼
4. BUILD PLAN           BRD + architecture → dependency-ordered, numbered script plan
   (brd-to-build-plan.md)
        │
        ▼
5. BUILD                plan → running Mendix app, one module at a time, gated
   (iterative-build-loop.md, mdl-cookbook-microflows.md, bug-logs/mxcli-bugs.md)
        │
        ▼
6. TEST                 running app → verified behavior (Playwright + DB assertions)
   (e2e-harness-base.md)
```

**Stage 0 (Triage) is a gate, not a formality.** It decides whether this app is even big enough to justify an extraction pipeline (small apps: skip straight to manual `assess-migration.md` + hand-written BRD), checks whether existing extractors/mappers cover this source stack or new ones are needed, and — for large sources — recommends a bounded scope subset rather than processing everything at once. It also flags (without deciding) whether the app is large enough to raise a multiple-Mendix-apps question, which has to be resolved before Stage 3's module-boundary work. Stage 2 (BRD generation) does not start until this is signed off.

**Stage 1 (Analysis)** runs two independent paths that can happen in either order: Path A extracts structure straight from source code (XML/Java/C#/SQL → JSON), Path B extracts structure from business documents (Excel/Word/PDF/PPTX → KB markdown). Both feed the same merge step.

**Stages 3a/3b run in parallel**, not sequentially: `modularize-domain.md` decides module boundaries first (never map source files 1:1 onto Mendix modules), then `architecture-blueprint.md` (the structural diagrams) and `design-artifacts.md` (the UI/brand layer) both consume that decision at the same time.

**Nothing in stages 0–4 touches mxcli.** MDL scripting only starts at stage 5, against a plan that's already been reviewed. This is deliberate — it's cheaper to fix a wrong module boundary in a diagram (or a wrong scope decision before any extraction ran) than to fix it after 40 MDL scripts assume it.

See `examples/outsystems-migration/` for a worked run through all six build stages on a real project (that example predates the triage stage).

---

## What's in here

```
mxcli-project-toolkit/
  skills/
    migration-pipeline.md       ← Full pipeline phase guide (XML → KB → BRD → MDL)
    source-triage.md            ← Gate before extraction: coverage check, manual-vs-pipeline call, bounded scope
    modularize-domain.md        ← Deciding Mendix module boundaries (Phase 6): criteria, sign-off, HTML rationale
    architecture-blueprint.md   ← Target-architecture blueprint: diagrams, module defs, wiring, fit-gap, open-issues
    design-artifacts.md         ← UI/brand layer: versioned design system + annotated wireframes
    brd-to-build-plan.md        ← Plan definition: BRD + architecture → dependency-ordered, numbered build plan
    iterative-build-loop.md     ← Per-module build discipline: 12-step gate, CE triage, Studio Pro handoffs
    brd-generation.md           ← BRD JSON prompt templates + validation checklist
    kb-generation.md            ← Document extraction (Excel/Word/PDF → KB markdown)
    source-os11.md              ← OutSystems 11 XML schema reference
    os-xml-schema.md            ← OS eSpace XML structure details
    mdl-cookbook-microflows.md  ← MDL scripting patterns for microflows
    qa-loop-goal-pattern.md     ← Iterative /goal-driven pipeline validation technique
    e2e-harness-base.md         ← End-to-end test harness base
    assess-migration.md         ← Up-front migration assessment
    migrate-general.md          ← Source-agnostic migration guidance
    migrate-outsystems.md       ← OutSystems-specific migration guide
    agent-roles.md              ← Generate project-specific mdl/gate/test subagents with scoped tool rights
    learned-*.md                ← Validated learnings from live projects
  pipelines/                    ← Source-specific extraction tooling (code; node_modules gitignored)
    outsystems/                 ← OS XML → KB → BRD (imported with history) + sample-outputs
    java-angular/               ← Java + Angular/Spring Boot → KB → BRD
  examples/
    outsystems-migration/
      plan-overview.md          ← Worked example: 112 OS modules → 14 Mendix, architecture decisions
      build-loop-example.md     ← Worked example: single module (PayerRegistration) step-by-step
  bug-logs/
    mxcli-bugs.md               ← Known mxcli CLI bugs and workarounds
    bug-log-apex-m0022.md    ← Project-specific bug log (Apex M-0022)
  process/
    process-learnings.md        ← Cross-project process improvements
    test-plan-apex-m0022.md  ← Reference test plan
```

---

## When to use which skill

| Task | Skill to load |
|------|--------------|
| Deciding whether to extract at all, checking coverage, scoping a large source | `source-triage.md` |
| Running the extraction pipeline | `migration-pipeline.md` |
| Diagramming target architecture: module defs, wiring, fit-gap | `architecture-blueprint.md` |
| Designing the brand + wireframes before building pages | `design-artifacts.md` |
| Turning BRDs + architecture into an ordered build plan | `brd-to-build-plan.md` |
| Building a module with mxcli (verified, iterative) | `iterative-build-loop.md` |
| Writing or enriching a BRD JSON | `brd-generation.md` |
| Extracting Excel/Word/PDF specs | `kb-generation.md` |
| Understanding OS XML source | `source-os11.md` + `os-xml-schema.md` |
| Writing MDL microflow scripts | `mdl-cookbook-microflows.md` |
| Diagnosing a mxcli error | `bug-logs/mxcli-bugs.md` |
| Validating a new stack pipeline's extraction quality | `qa-loop-goal-pattern.md` |
| Deciding module boundaries before `create module` | `modularize-domain.md` |
| Assessing / planning a migration up front | `assess-migration.md` |
| Migrating an OutSystems app | `migrate-outsystems.md` |
| Running the OS or Java/Angular extraction pipeline | `pipelines/outsystems/` · `pipelines/java-angular/` |
| Seeing how it all fits together on a real project | `examples/outsystems-migration/` |
| Setting up dev-process subagents on a new project (draft/gate/test split) | `agent-roles.md` |

---

## How to add a new skill

1. Create a new `.md` file in `skills/` with this header:
   ```markdown
   # Skill Name — Purpose
   **Purpose:** one-line description
   **Source:** which project or session this came from
   ```
2. Structure it as a step-by-step guide with prompt templates where applicable
3. Add it to the "When to use which skill" table above
4. **If it applies on every MDL-writing session regardless of task** (not situational — e.g. a new universal MDL gotcha, not a phase-specific procedure), also add it to "Baseline routing" above. Situational skills stay out of that table; it's deliberately short.
5. Commit and push — available to all projects on next `git pull`

---

## How to add a project-specific learning

For validated patterns from a live project, add a file `skills/learned-{topic}.md`. These get loaded by Claude when relevant and accumulate into cross-project knowledge. If the pattern is universal enough to belong in "Baseline routing" (most `learned-microflow-patterns.md`-style discipline is), add it there too — don't leave it purely situational.

For bugs, append to `bug-logs/mxcli-bugs.md` or create a project-specific log.

---

## Consuming this toolkit

**Reference model (default):** clone once, point projects at it — no copies, no drift.
```
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
```
Each project's CLAUDE.md references `~/Mendix/mxcli-project-toolkit`. Pull updates with `git pull`.
For a self-contained handoff, add it as a git submodule instead. Per pipeline, run `npm install` inside `pipelines/<x>/pipeline` (node_modules is gitignored).

### Baseline routing — copy this into every new project's CLAUDE.md

The "When to use which skill" table above is *situational* — load a skill when a specific task calls for it. A few skills apply on **every** MDL-writing session regardless of task, and situational discovery quietly misses them, because nothing mid-task prompts loading them. Every consuming project's own `CLAUDE.md` (or wherever it tells agents what to read before writing MDL, e.g. its own `write-microflows.md`) should reference these directly, not rely on stumbling onto them:

| Always relevant for | Reference this |
|---|---|
| Writing or fixing any microflow | `skills/learned-microflow-patterns.md` — MDL gotchas + the annotation discipline (selective, not blanket; CE-error fixes always annotated) |
| A CE error or behavior that looks like a known mxcli quirk, not a modeling mistake | `bug-logs/mxcli-bugs.md` |
| Setting up a new project's dev-process subagents | `skills/agent-roles.md` — once, at project start, not "on demand" |
| Deciding whether to extract at all, before any BRD gets generated | `skills/source-triage.md` |

**Why this has to be explicit instead of implicit:** a project's own skill files are usually written before a given toolkit learning exists, or before a new one is added later — they never grow a cross-reference to it on their own. When you `git pull` this toolkit and it brings in a new baseline-worthy skill (most often a new `learned-*.md`), update every consuming project's routing to match — don't assume the next session will find it by chance.

**After cloning, set your local source paths** in `pipelines/<x>/pipeline/config.json` — the committed file ships with `<placeholder>` values; point them at your own source workspace. Never commit real local paths.

**Project output never lives here** (`analysis/`, `sources/`, `knowledge-base/`, `*.mpr` are gitignored) — each migration runs in its own workspace that references this repo.

**Your build plan and session notes live in your own project, not here.** This repo holds reusable tools + skills + small curated examples only. A project's architecture blueprint, numbered build plan, open-issues register, and running session diary belong in that project's own repo (e.g. `architecture/build-plan.md`, `SESSION-NOTES.md` at the project root) — never committed back into the toolkit. If a pattern from that plan turns out to be reusable across projects, promote it into a `skills/learned-*.md` file here instead of leaving the whole plan in place.

## Used by

- `pipelines/outsystems/` — OutSystems 11 → Mendix pipeline (was the standalone `os-migration-pipeline` repo)
- `pipelines/java-angular/` — Java + Angular/Spring Boot → Mendix pipeline
- Several other client integration and migration projects
