# mxcli-project-toolkit — Claude Context

## What this repo is
Shared skills, stage-gate tooling, and learnings for **Mendix migration and development projects**.
Serves three entry modes (see `skills/conversion-runbook.md` → "Entry Modes"): **migration** (legacy source, all stages), **requirements-driven** (specs/SME input, no legacy code, stages 1–6), and **greenfield** (stage 5 onward). Plus **à-la-carte use with no pipeline at all** — auditing or regression/e2e-testing an existing app routes straight to `skills/existing-app-assurance.md`, skipping intake/stages/gates entirely.

## The front door
- `CONVERSION-RUNBOOK.md` (root) — thin "how to start" pointer.
- `toolkit-guide.html` (root) — the visual onboarding page. **First-touch rule:** the first time a session uses this toolkit for a project (new conversion, new user, or the user seems unsure how the pipeline works), open it in their browser (`open toolkit-guide.html` / `xdg-open`) before the first interview question — `bin/init-project.sh` also does this automatically at scaffold time. Don't re-open it every session for a user who already knows it. It's also the shared CSS shell/tokens for every stage HTML surface.
- `skills/conversion-runbook.md` — **the spine**: 9-stage matrix, interview protocol, gates, entry modes. Start here when unsure what stage anything is in.
- `bin/init-project.sh <project-dir>` — Stage P scaffold (`intake.md`, `PROJECT.md`, `index.html`).
- `bin/gate-check.sh <project-dir> [stage]` — mechanical stage gates; regenerates the project dashboard from real files.

## Live checklist — every stage, in the chat
Every stage and module build follows the **Live Checklist Protocol** (`skills/conversion-runbook.md` §1b): post the stage's checklist in chat at start, update with ✅/🔄/⬜/❌/⏭ marks as items land, full repost before every gate. No stage works silently between gates. This is not build-phase-only.

## One decision register
All gate decisions land in the consuming project's `PROJECT.md`, marked `CONFIRMED` or `ASSUMED`. The `skills/checkpoints/` CAC files are the packaged mechanism that runs the runbook's interview protocol at the six busiest transitions — they write to `PROJECT.md`, never to a separate state file.

**Ask, then stop.** Gate questions are actually asked in chat (`AskUserQuestion`), and the agent ends its turn to wait for the answer. `ASSUMED` is earned by asking (user said "you decide"), never by skipping the question — finding the answer in the source justifies the *recommendation*, not silence. Unattended runs are opt-in only (`Interview mode: unattended` in `PROJECT.md`, at the user's explicit request).

## Key skills and when to load them

Load skill files **on demand when the task calls for it** — not all upfront. Full routing table: `README.md` → "When to use which skill". The always-on set (`README.md` → "Baseline routing"): `query-the-model.md`, `learned-mdl-preflight.md`, `learned-microflow-patterns.md`, `learned-mcp-patterns.md`, `bug-logs/mxcli-bugs.md`.

| Task | Read this file |
|------|---------------|
| Any conversion/build — what stage, what gate, who owns it | `skills/conversion-runbook.md` |
| Audit / lint / regression-test an existing app (no pipeline) | `skills/existing-app-assurance.md` |
| Deciding what source answers a question, before asking the user | `skills/query-the-model.md` |
| Running a stage-transition checkpoint (2+1 questions) | `skills/checkpoints/checkpoint-*.md` |
| Extract-vs-not, extractor coverage, scoping a large source | `skills/source-triage.md` |
| Building/validating a new extractor for an uncovered stack | `skills/extractor-quality-loop.md` |
| Running or explaining the extraction pipeline | `skills/migration-pipeline.md` |
| Mendix module boundaries (Stage 3, before `create module`) | `skills/modularize-domain.md` |
| Architecture blueprint: diagrams, fit-gap, marketplace, security, NFRs, integrations | `skills/architecture-blueprint.md` |
| UI/brand layer: design system, wireframes, branding interview | `skills/design-artifacts.md` |
| BRDs + architecture → ordered build plan | `skills/brd-to-build-plan.md` |
| Per-module build discipline (gates, coverage checklist) | `skills/iterative-build-loop.md` |
| Writing/validating/enriching BRD JSON | `skills/brd-generation.md`, `skills/brd-validation.md` |
| Document folder scan / Excel-Word-PDF extraction | `skills/document-discovery.md`, `skills/kb-generation.md` |
| OS XML structure | `skills/source-os11.md` + `skills/os-xml-schema.md` |
| MDL microflow scripting patterns | `skills/mdl-cookbook-microflows.md` |
| Page/snippet pre-flight (wireframe → tokens → StyleGallery) | `skills/ui-preflight-pages.md`, `skills/learned-stylegallery.md` |
| Diagnosing a mxcli CLI error | `bug-logs/mxcli-bugs.md` |
| Generating a new project's CLAUDE.md | `skills/bootstrap-project.md` (run `mxcli init` FIRST — init overwrites, bootstrap merges) |
| Setting up dev-process subagents (ba/architect/mdl/gate/test) | `skills/agent-roles.md` |
| Past process decisions | `process/process-learnings.md` |

Migration assessment (`assess-migration`) is **bundled with mxcli** (`.ai-context/skills/`); `skills/assess-migration.md` here is a pointer plus toolkit-specific deltas only — the toolkit never duplicates bundled skills.

## Pipelines (extraction tooling — code lives in this repo)

| Source platform | Pipeline | Run |
|-----------------|----------|-----|
| OutSystems | `pipelines/outsystems/` | `cd pipelines/outsystems/pipeline && npm install` — see its `README.md` / `pipeline-guide.html` |
| Java + Angular / Spring Boot | `pipelines/java-angular/` | `cd pipelines/java-angular/pipeline && npm install` — see its `README.md` |
| Node/Express + React | `pipelines/node-express-react/` — **regex-based, proven on one source shape only; read its README's "Known gap" sections first** | `cd pipelines/node-express-react/pipeline && npm install` |

`node_modules/` is gitignored — `npm install` locally per pipeline. Set local paths in `pipelines/<x>/pipeline/config.json`; **never commit real local paths**. Curated sample outputs live under each pipeline.

## Consuming this toolkit (reference model)
Clone once, point projects at it — no copies, no drift:
```
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
```
Each project's `CLAUDE.md`/`CLAUDE.local.md` references this clone and copies the **Baseline routing** table from `README.md`. For a self-contained handoff, use a git submodule.

**Project output never lives here** — `analysis/`, `sources/`, `knowledge-base/`, `*.mpr` are gitignored. A project's build plan, `PROJECT.md`, and session notes live in that project's own repo; promote reusable patterns into `skills/learned-*.md` instead of accumulating project docs here.

## Adding new skills
Create `skills/{topic}.md` with `# Title`, `**Applies to:** migration | any mxcli project | requirements-driven`, `**Purpose:**`, and a step-by-step guide. Add it to `README.md`'s "When to use which skill" table. **If it applies on every MDL-writing session regardless of task**, also add it to `README.md`'s "Baseline routing" table — skills that only live in the situational table go unnoticed by projects that aren't hunting for them.
