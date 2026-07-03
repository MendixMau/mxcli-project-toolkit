# mxcli-project-toolkit

Shared skills, prompt templates, and learnings for **Mendix migration and development projects**.

Used across all mxcli-powered projects — OS migration, ClientB, future Java/Angular migrations, and others.

---

## What's in here

```
mxcli-project-toolkit/
  skills/
    migration-pipeline.md       ← Full pipeline phase guide (XML → KB → BRD → MDL)
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
    bug-log-contoso-m0022.md    ← Project-specific bug log (Contoso M-0022)
  process/
    process-learnings.md        ← Cross-project process improvements
    test-plan-contoso-m0022.md  ← Reference test plan
  SESSION-NOTES.md              ← Running session diary
```

---

## When to use which skill

| Task | Skill to load |
|------|--------------|
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

---

## How to add a new skill

1. Create a new `.md` file in `skills/` with this header:
   ```markdown
   # Skill Name — Purpose
   **Purpose:** one-line description
   **Source:** which project or session this came from
   ```
2. Structure it as a step-by-step guide with prompt templates where applicable
3. Add it to the table above in this README
4. Commit and push — available to all projects on next `git pull`

---

## How to add a project-specific learning

For validated patterns from a live project, add a file `skills/learned-{topic}.md`. These get loaded by Claude when relevant and accumulate into cross-project knowledge.

For bugs, append to `bug-logs/mxcli-bugs.md` or create a project-specific log.

---

## Consuming this toolkit

**Reference model (default):** clone once, point projects at it — no copies, no drift.
```
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
```
Each project's CLAUDE.md references `~/Mendix/mxcli-project-toolkit`. Pull updates with `git pull`.
For a self-contained handoff, add it as a git submodule instead. Per pipeline, run `npm install` inside `pipelines/<x>/pipeline` (node_modules is gitignored).

**Project output never lives here** (`analysis/`, `sources/`, `knowledge-base/`, `*.mpr` are gitignored) — each migration runs in its own workspace that references this repo.

## Used by

- `pipelines/outsystems/` — OutSystems 11 → Mendix pipeline (was the standalone `os-migration-pipeline` repo)
- `pipelines/java-angular/` — Java + Angular/Spring Boot → Mendix pipeline
- ClientB integration project
