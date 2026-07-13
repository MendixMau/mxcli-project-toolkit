# mxcli-project-toolkit

Shared skills, prompt templates, and learnings for **Mendix migration and development projects**.

Serves two audiences: **migrations** (all stages below) and **greenfield mxcli builds** (Stage 5 onward — the standard Mendix build discipline is not migration-specific).

Used across all mxcli-powered projects — OS migrations, Java/Angular migrations, Node/Express+React migrations, and other client integration work.

---

## Quickstart

```bash
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
```

This clone stays clean — project output never lands inside it. Your workspace root holds this clone as a sibling to your source and project folders:

```
<workspace-root>/
  mxcli-project-toolkit/     ← this clone (stays clean; project output never lands here)
  sources/<project>/         ← the original source, read-only
  analysis/<project>/        ← everything the pipeline produces
    PROJECT.md               ← decisions, assumptions, dependencies, open questions
    intake.md · assessment.md · triage.md
    knowledge-base/          ← extraction JSON + BRDs
    architecture/ · design/
    index.html               ← the project dashboard
  mendix/<project>/          ← the target .mpr
```

Clone, run `skills/bootstrap-project.md` to scaffold `CLAUDE.local.md` + the subagents, then follow `skills/conversion-runbook.md` — it interviews you through each stage below.

---

## How a migration flows through this toolkit

Every migration moves through the same stages, regardless of source stack. Each stage has one skill that owns it, one agent responsible for running it, and hands a concrete artifact + a recorded decision to the next. The full stage-by-stage detail — what you're asked, what gate stops the pipeline, who owns it — lives in `skills/conversion-runbook.md`; this is the summary:

```
P. KICKOFF              source folder, constraints, SME availability → workspace scaffold
   (bootstrap-project.md, agent-roles.md)                                        [ba-agent]
        │
        ▼
0. TRIAGE ✋             source stack → coverage decision + bounded scope, signed off
   (source-triage.md, checked against assess-migration.md's inventory)           [ba-agent]
        │
        ▼
1. ANALYSIS             source code/docs/SME → extracted JSON + KB markdown
   (migration-pipeline.md, source-*.md, kb-generation.md)                        [ba-agent]
        │
        ▼
2. REQUIREMENTS         KB + extracted JSON → validated BRD JSON (per module)
   (brd-generation.md, brd-validation.md)                                        [ba-agent]
        │
        ▼
3. ARCHITECTURE & DESIGN ✋   BRD → module boundaries, diagrams, fit-gap, design system,
   (modularize-domain.md →        security model, NFRs, integration contracts, branding
    architecture-blueprint.md + design-artifacts.md, run in parallel)      [architect-agent]
        │
        ▼
4. BUILD PLAN ✋         BRD + architecture → dependency-ordered, numbered script plan
   (brd-to-build-plan.md)                                                 [architect-agent]
        │
        ▼
5. BUILD                plan → running Mendix app, one module at a time, gated
   (iterative-build-loop.md, mdl-cookbook-microflows.md, bug-logs/mxcli-bugs.md)
                                                              [mdl-agent → gate-agent]
        │
        ▼
5.5 DATA MIGRATION & CUTOVER   legacy data: migrate, seed, or drop → cutover checklist
                                                                     [ba-agent → mdl-agent]
        │
        ▼
6. TEST                  running app → verified behavior (Playwright + DB assertions)
   (e2e-harness-base.md)                                                       [test-agent]
```

`✋` marks a hard gate — the pipeline does not proceed without an explicit, recorded decision. Every other stage still records decisions, but unknowns may default to a recommended option (marked `ASSUMED` in `PROJECT.md`) rather than blocking a solo run. See `skills/conversion-runbook.md` §1 for the exact interview mechanics every gate runs.

**Stage 0 (Triage) is a gate, not a formality.** It decides whether this app is even big enough to justify an extraction pipeline (small apps: skip straight to manual `assess-migration.md` + hand-written BRD), whether existing extractors/mappers cover this source stack or a new one needs building, and — for large sources — recommends a bounded scope subset (**an ordering, not an exclusion**) rather than processing everything at once. It also flags (without deciding) whether the app is large enough to raise a multiple-Mendix-apps question, resolved before Stage 3's module-boundary work. Stage 2 (BRD generation) does not start until this is signed off.

### How `assess-migration` and the extraction pipeline complement each other

These are two tools for the same stage — they work together, not instead of each other:

| Tool | What it does | When to use it |
|------|-------------|----------------|
| `assess-migration.md` | AI-guided manual inventory: reads source files, produces a human-readable markdown report covering entities, business logic, integrations, security, and migration risks. | Always — for small apps this is sufficient on its own; for large apps it provides the human-readable layer on top of the pipeline output. Run it before or after the extraction pipeline. |
| Extraction pipeline (`pipelines/<stack>/`, e.g. `outsystems/`, `java-angular/`, `node-express-react/`) | Automated extraction: parses source code into normalized KB JSON, runs BRD mappers, generates a per-module BRD and HTML report. | Medium/large apps where manual reading would miss classes or where you need machine-processable output for BRD generation. |

**The correct combined flow for a medium/large app:**

```
assess-migration.md          ←  AI reads source, produces markdown triage report
        +
<stack>-extractor.js (Phase 2) ←  parser extracts all entities/logic/endpoints → KB JSON
        +
BRD mappers (Phase 3)        ←  KB JSON → structured BRD per module
        ↓
source-triage.md             ←  human reviews both outputs, signs off on scope + approach
        ↓
stages 1–6 proceed
```

`assess-migration.md`'s output feeds `source-triage.md`'s coverage matrix — it tells you *what* is in the source. The extraction pipeline tells you the same thing in machine-readable form. Together they cross-validate each other: discrepancies between the two (e.g. the AI found a rule the extractor missed, or the extractor found 40 entities the AI only sampled 15 of) are exactly the gaps `source-triage.md` is designed to surface before Phase 2 BRDs are generated.

**Stage 1 (Analysis)** runs three independent paths, not two: **Path A** extracts structure straight from source code (XML/Java/C#/TypeScript/SQL → JSON) — always runs. **Path B** extracts structure from business documents (Excel/Word/PDF/PPTX → KB markdown). **Path C** is the SME interview — the source no code or document answers (intent, "why", business rules that were never written down). Each path is either done or explicitly declared unavailable by a named person; never silently skipped.

**Stages 3a/3b run in parallel**, not sequentially: `modularize-domain.md` decides module boundaries first (never map source files 1:1 onto Mendix modules), then `architecture-blueprint.md` (structural diagrams, marketplace buy-vs-build, security model, NFRs, integration contracts) and `design-artifacts.md` (UI/brand layer, branding as a real interview) both consume that decision at the same time.

**Nothing in stages 0–4 touches mxcli.** MDL scripting only starts at stage 5, against a plan that's already been reviewed. This is deliberate — it's cheaper to fix a wrong module boundary in a diagram (or a wrong scope decision before any extraction ran) than to fix it after 40 MDL scripts assume it.

See `examples/outsystems-migration/` for a worked run through all six build stages on a real project (that example predates the triage stage and the interview protocol).

---

## Decision flow: query the model, then read the source, then ask the human

Before asking the user anything, or writing anything: **query the model → read the source → ask the human, in that order.** Never skip to the last one. Full source-of-truth table (which class of question answers from which source, and why) in `skills/query-the-model.md`. The two rules that are already load-bearing and easy to skip under pressure:

- **`SHOW ASSOCIATIONS` before every `CREATE ASSOCIATION`** — MDL has no `IF NOT EXISTS`; re-running a CREATE silently duplicates it.
- **`SHOW ENTITIES IN <MarketplaceModule>` before referencing a marketplace module** — `mxcli check --references` can't validate a module that isn't imported yet.

Reads are always safe and free; writes go through the STOP table below.

## Which tools do what — and when

### Stages 0–4: pure LLM, no mxcli needed

Triage, analysis, BRD generation, architecture, and design are entirely model-driven. The LLM reads source code, documents, and SME input; produces markdown, JSON, and diagrams; and hands a reviewed, signed-off plan to stage 5. No mxcli command runs, no `.mpr` is touched. This is deliberate — it is far cheaper to fix a wrong module boundary in a diagram than after 40 MDL scripts assume it.

### Stage 5+: three write modes

Once you have a reviewed build plan, you have three tools to write to the `.mpr`. Pick by what you're building:

| Mode | When to use it | Why |
|---|---|---|
| **CLI** (`mxcli exec script.mdl`) | Initial build: entities, attributes, enumerations, associations, microflow logic, access rules, navigation, demo users — anything that is large, structural, and done once | You write a readable MDL script, the CLI writes the whole batch to disk in one shot, SP stays closed. The big advantage is scale — you can scaffold an entire module in a single exec. The script is version-controlled and reviewable before it runs. Automatic snapshot before every exec means you can iterate without fear. The tradeoff: SP must be closed and restarted after each exec, which takes time. |
| **MCP + MDL** (`mxcli --mcp exec script.mdl`) | Targeted changes, UI tweaks, iterative refinement — anything you're actively tuning where restarting SP between each change would kill your flow | SP stays open the whole time. You make a change, it lands in the live model, SP reflects it immediately — no restart, no wait, no recompile cycle. This is the mode for UI work: adjusting a page layout, wiring a widget, fixing a visibility expression. The feel is closer to live editing. You still write MDL, so the script is readable — you just route it through SP's own engine instead of the CLI's disk writer, which also sidesteps a class of BSON serializer bugs. |
| **Hand-rolled MCP** (`pg_patch_page`, `ped_create_document`) | Widget JSON shapes that MDL has no syntax for yet — DataGrid2 column configs, dropdown filter wiring, complex visibility inside datagrid customContent | Same SP-stays-open benefit as MCP+MDL, but you're writing raw JSON payloads directly against SP's model API. No MDL involved. Use only when the other two modes genuinely have no syntax for the operation. Confirmed patterns are in `learned-mcp-patterns.md`; save discipline is critical (uncommitted MPR guard before every write). |

**In practice:** use CLI to build, use MCP to refine. A typical module goes: one CLI exec to scaffold the domain model and microflows → MCP+MDL for page iteration and UI tweaks → hand-rolled MCP only for the specific widget shapes MDL can't reach.

**Studio Pro GUI** is not a write mode for agents — it's the fallback for two operations that corrupt deterministically on every CLI/MCP retry: `ALTER SETTINGS` and dropping an attribute that has security grants. Those go to the human.

### Stage 6: testing

Testing runs after a gate-agent pass and uses two independent layers:

- **Playwright** (via `test-agent`) — walks the running app as a real user: login flows, form submission, navigation, happy-path and edge cases per BRD use case. Driven by the same use-case list from `migration/knowledge-base/brd/`.
- **DB assertions** (`mxcli -p ... -c "SELECT ..."` OQL queries) — cross-checks what the UI shows against what's actually in the database. UI alone can't confirm a create/update/delete landed correctly; OQL can. Patterns in `learned-db-assertions.md`.

These two layers catch different things — Playwright catches broken flows; OQL catches silent data corruption. Both run before any scenario is marked passing.

**Screenshot discipline.** `mxcli exec` writes the model file but the browser serves a JS bundle compiled by Studio Pro — not the raw model. Screenshots before SP recompiles are worthless. Protocol: exec → user closes and reopens SP manually → wait for confirmation → `curl` port 200 → only then screenshot or run UI assertions. Never auto-kill/relaunch SP from a script. Add this rule to each project's `CLAUDE.md` at setup.

### Per-operation reference table

Use this before every write. Full per-rule detail (root causes, bug IDs, retest stamps) is in `skills/learned-mdl-preflight.md`.

| Operation | Mode | SP state |
|---|---|---|
| Entities, attributes, enumerations | CLI | Closed |
| Associations (after `SHOW ASSOCIATIONS` check) | CLI | Closed |
| Microflows — no inline assoc-sets | CLI | Closed |
| Access rules, module roles, demo users, navigation | CLI | Closed |
| Microflows — with inline assoc-sets (`CHANGE $Obj (Assoc = $Other)`) | MCP + MDL | **Open** |
| `visible:`/`editable:` inside `datagrid customContent` columns | Hand-rolled MCP (`pg_patch_page`) | **Open** |
| DataGrid2 column configs, dropdown filter wiring | Hand-rolled MCP (`pg_patch_page`) | **Open** |
| Cross-module association traversal as widget datasource | Hand-rolled MCP (`pg_patch_page`) | **Open** |
| `ALTER SETTINGS`, `ALTER PROJECT SECURITY LEVEL` | Studio Pro GUI | N/A |
| Drop an attribute that has security grants | Studio Pro GUI | N/A |
| After any MPR corruption or load error | `bin/restore-mpr.sh` | Closed |

**The crash net.** An MPR is two parts: `Project.mpr` (SQLite index) and `mprcontents/` (BSON units). `bin/exec.sh` snapshots both before every batch; 5 rotate; `bin/restore-mpr.sh` rolls back both together (either alone is useless). Git commits at phase gates are the real history. Ad-hoc `.mpr.backup` copies are banned.

### Something went wrong? Don't panic.

Two things go wrong regularly on active projects. Both are recoverable.

---

**"Studio Pro won't open / the project fails to load"**

This almost always means the MPR got a bad write — an exec that produced malformed BSON, an interrupted write, or a serializer bug that slipped through the preflight check. It sounds catastrophic but it isn't, because `bin/exec.sh` snapshots automatically before every batch.

What to do:
1. Tell Claude: *"The project won't load — restore the last snapshot."*
2. Claude runs `bin/restore-mpr.sh` — this restores **both** `Project.mpr` and `mprcontents/` together. Restoring only one of the two will not work; the SQLite index and the BSON units must be in sync.
3. SP opens cleanly from the restored snapshot. You've lost at most one exec batch.

Why it happens: the CLI writes model units as BSON directly to disk, bypassing SP's own engine. Most operations are clean, but a handful of edge cases (see the STOP table) produce BSON that SP's loader rejects. The `bin/exec.sh` snapshot-before-exec pattern exists precisely because this is a known failure mode, not an exceptional one.

---

**"Studio Pro won't start / hangs on launch"**

This almost always means a stale SP process is still running in the background — a previous session didn't exit cleanly, or a restart left a ghost process holding the port or the project lock.

What to do:
1. Tell Claude: *"SP won't start — kill any stale Studio Pro processes."*
2. Claude checks for running SP processes and kills them: `pkill -f "studiopro"` (or the equivalent for your OS).
3. Reopen SP normally.

You don't need to restart your machine or reinstall anything. The stale process is the entire problem 95% of the time. If SP still won't start after killing the process, check for a stale `.mpr.lock` file in the project directory and remove it — that's the other 5%.

---

## What's in here

```
mxcli-project-toolkit/
  skills/
    conversion-runbook.md       ← [any project] The spine: 8-stage matrix + interview protocol + gates
    query-the-model.md          ← [any project] Query-before-ask source-of-truth ordering
    agent-roles.md              ← [any project] Generate ba/architect/mdl/gate/test subagents with scoped tool rights
    bootstrap-project.md        ← [any project] Generate a new project's CLAUDE.md: Baseline routing + project-specific facts
    migration-pipeline.md       ← [migration] Full pipeline phase guide (XML → KB → BRD → MDL)
    source-triage.md            ← [migration] Gate before extraction: coverage check, reuse-vs-build-new call, bounded scope
    modularize-domain.md        ← [migration] Deciding Mendix module boundaries (Stage 3): criteria, sign-off, HTML rationale
    architecture-blueprint.md   ← [migration] Target-architecture blueprint: diagrams, module defs, wiring, fit-gap, marketplace, security, NFRs, integrations
    design-artifacts.md         ← [migration] UI/brand layer: versioned design system + annotated wireframes + branding interview
    brd-to-build-plan.md        ← [migration] Plan definition: BRD + architecture → dependency-ordered, numbered build plan
    iterative-build-loop.md     ← [any project] Per-module build discipline: gate loop, coverage checklist, CE triage, Studio Pro handoffs
    brd-generation.md           ← [migration] BRD JSON prompt templates + validation checklist
    brd-validation.md           ← [migration] Validating BRDs against code + doc KB
    document-discovery.md       ← [migration] Scanning/classifying an unstructured document folder
    kb-generation.md            ← [migration] Document extraction (Excel/Word/PDF → KB markdown)
    source-os11.md              ← [migration] OutSystems 11 XML schema reference
    os-xml-schema.md            ← [migration] OS eSpace XML structure details
    source-node-express-react.md ← [migration] Node/Express+React extraction layout + known gaps
    mdl-cookbook-microflows.md  ← [any project] MDL scripting patterns for microflows
    qa-loop-goal-pattern.md     ← [any project] Iterative /goal-driven pipeline validation technique
    e2e-harness-base.md         ← [any project] End-to-end test harness base
    assess-migration.md         ← [migration] Up-front migration assessment
    migrate-general.md          ← [migration] Source-agnostic migration guidance
    migrate-outsystems.md       ← [migration] OutSystems-specific migration guide
    learned-*.md                ← [any project] Validated learnings from live projects
  pipelines/                    ← Source-specific extraction tooling (code; node_modules gitignored)
    outsystems/                 ← OS XML → KB → BRD (imported with history) + sample-outputs
    java-angular/                ← Java + Angular/Spring Boot → KB → BRD
    node-express-react/          ← Node/Express + React → KB → BRD — regex-based, proven on one source shape only; read its README first
  examples/
    outsystems-migration/
      plan-overview.md          ← Worked example: 112 OS modules → 14 Mendix, architecture decisions
      build-loop-example.md     ← Worked example: single module (PayerRegistration) step-by-step
    apex-m0022/                 ← Project-specific artifacts, kept as reference examples (not shared rules)
      bug-log-apex-m0022.md     ← Project-specific bug log (Apex M-0022)
      test-plan-apex-m0022.md   ← Reference test plan
  bug-logs/
    mxcli-bugs.md               ← Known mxcli CLI bugs and workarounds (shared)
  process/
    process-learnings.md        ← Cross-project process improvements
    learned-process-apex.md     ← Apex M-0022 project-scoped process notes (not in Baseline routing)
```

`[any project]` vs `[migration]` above mirrors each skill's own `Applies to:` header line — greenfield mxcli builds only need the `[any project]` set, starting at Stage 5.

---

## Division of labor: this toolkit vs bundled mxcli skills

Every mxcli project has a `.ai-context/skills/` directory (bundled by `mxcli init`, refreshed with each release) containing syntax references, widget patterns, CRUD templates, and how-to guides. **This toolkit does not duplicate those.** The two sets are complementary:

| Layer | Owned by | Contents | Updated by |
|---|---|---|---|
| `.ai-context/skills/` | mxcli (bundled) | MDL syntax, widget patterns, CRUD/data-processing templates, integration guides | `mxcli` release |
| `mxcli-project-toolkit/skills/` | This repo | Conversion runbook, migration pipeline, build discipline, agent roles, STOP rules from real corruption incidents | You (via `git pull`) |

**When the two disagree, this toolkit's STOP rules take precedence** — until explicitly retested and the result stamped in `bug-logs/mxcli-bugs.md`. The bundled skills may teach patterns that were unsafe on older mxcli versions; the bug log's `Retested on vX.Y.Z` field is the authoritative reconciliation record. References to bundled skills in this toolkit's docs are marked with "(bundled)".

---

## When to use which skill

| Task | Skill to load |
|------|--------------|
| Starting any conversion or greenfield build; not sure what stage you're in | `conversion-runbook.md` |
| Deciding what source to answer a question from, before asking the user | `query-the-model.md` |
| Deciding whether to extract at all, checking coverage, scoping a large source | `source-triage.md` |
| Running the extraction pipeline | `migration-pipeline.md` |
| Scanning/classifying an unstructured document folder | `document-discovery.md` |
| Diagramming target architecture: module defs, wiring, fit-gap, marketplace, security, NFRs, integrations | `architecture-blueprint.md` + `graph-analysis.md` (bundled — run `mxcli graph-report` for community-detection data before drawing module boundaries) |
| Designing the brand + wireframes before building pages | `design-artifacts.md` |
| Turning BRDs + architecture into an ordered build plan | `brd-to-build-plan.md` |
| Building a module with mxcli (verified, iterative, coverage-checklist gated) | `iterative-build-loop.md` |
| Writing or enriching a BRD JSON | `brd-generation.md` |
| Validating BRDs against code + doc KB | `brd-validation.md` |
| Extracting Excel/Word/PDF specs | `kb-generation.md` |
| Understanding OS XML source | `source-os11.md` + `os-xml-schema.md` |
| Understanding Node/Express+React source, its layout assumptions and gaps | `source-node-express-react.md` |
| Writing MDL microflow scripts | `mdl-cookbook-microflows.md` |
| Checking what's safe to write in MDL vs MCP vs SP GUI before drafting (STOP table) | `skills/learned-mdl-preflight.md` |
| Using MCP alongside mxcli — handoff sequence, save discipline, confirmed JSON patterns, known bugs | `skills/learned-mcp-patterns.md` + `live-edit-with-studio-pro.md` (bundled) |
| Diagnosing a mxcli error | `bug-logs/mxcli-bugs.md` |
| Enforcing module-graph architecture boundaries via lint rules | `write-lint-rules.md` (bundled — Starlark rules over `mxcli lint`) |
| Writing DB assertion tests (cross-check UI state against the database) | `learned-db-assertions.md` |
| Building and auditing Mendix pages (widget patterns, datasource shapes) | `learned-page-patterns.md` |
| UX audit / screenshot loop discipline | `learned-skill-ux-audit.md` |
| Scope delta tracking between BRD and built state | `learned-skill-scope-delta.md` |
| Cross-project process improvements and retrospective learnings | `process/process-learnings.md` |
| Validating a new stack pipeline's extraction quality | `qa-loop-goal-pattern.md` |
| Deciding module boundaries before `create module` | `modularize-domain.md` |
| Assessing / planning a migration up front | `assess-migration.md` |
| Migrating an OutSystems app | `migrate-outsystems.md` |
| Running an extraction pipeline | `pipelines/outsystems/` · `pipelines/java-angular/` · `pipelines/node-express-react/` |
| Seeing how it all fits together on a real project | `examples/outsystems-migration/` |
| Generating a new project's CLAUDE.md (Baseline routing + project-specific facts) | `bootstrap-project.md` |
| Setting up dev-process subagents on a new project (ba/architect/mdl/gate/test split) | `agent-roles.md` |

---

## How to add a new skill

1. Create a new `.md` file in `skills/` with this header:
   ```markdown
   # Skill Name — Purpose
   **Applies to:** migration | any mxcli project
   **Purpose:** one-line description
   **Source:** which project or session this came from
   ```
2. Structure it as a step-by-step guide with prompt templates where applicable
3. Add it to the "When to use which skill" table above
4. **If it applies on every MDL-writing session regardless of task** (not situational — e.g. a new universal MDL gotcha, not a phase-specific procedure), also add it to "Baseline routing" below. Situational skills stay out of that table; it's deliberately short.
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
Each project's `CLAUDE.local.md` references `~/Mendix/mxcli-project-toolkit`. Pull updates with `git pull`.
For a self-contained handoff, add it as a git submodule instead. Per pipeline, run `npm install` inside `pipelines/<x>/pipeline` (node_modules is gitignored).

### Baseline routing — copy this into every new project's CLAUDE.md / CLAUDE.local.md

The "When to use which skill" table above is *situational* — load a skill when a specific task calls for it. A few skills apply on **every** MDL-writing session regardless of task, and situational discovery quietly misses them, because nothing mid-task prompts loading them. Every consuming project's own `CLAUDE.md`/`CLAUDE.local.md` (or wherever it tells agents what to read before writing MDL, e.g. its own `write-microflows.md`) should reference these directly, not rely on stumbling onto them:

| Always relevant for | Reference this |
|---|---|
| Any question before asking the user or writing anything | `skills/query-the-model.md` — query the model, then read the source, then ask the human, in that order |
| Writing **any** MDL script — before the first line | `skills/learned-mdl-preflight.md` — STOP conditions (each backed by a real corruption incident); check every planned operation here before drafting |
| Writing or fixing any microflow | `skills/learned-microflow-patterns.md` — MDL gotchas + annotation discipline (placement rules — never before `if`; CE-error fixes always annotated) |
| Using MCP alongside mxcli — any MCP write session | `skills/learned-mcp-patterns.md` — save discipline, uncommitted-MPR guard, pre-exec handoff sequence, confirmed JSON patterns |
| A CE error or behavior that looks like a known mxcli quirk, not a modeling mistake | `bug-logs/mxcli-bugs.md` |
| Setting up a new project's dev-process subagents | `skills/agent-roles.md` — once, at project start, not "on demand" |
| Deciding whether to extract at all, before any BRD gets generated | `skills/source-triage.md` |
| Not sure what stage a conversion is in, or what a gate requires | `skills/conversion-runbook.md` |

**Why this has to be explicit instead of implicit:** a project's own skill files are usually written before a given toolkit learning exists, or before a new one is added later — they never grow a cross-reference to it on their own. When you `git pull` this toolkit and it brings in a new baseline-worthy skill (most often a new `learned-*.md`), update every consuming project's routing to match — don't assume the next session will find it by chance.

**After cloning, set your local source paths** in `pipelines/<x>/pipeline/config.json` — the committed file ships with `<placeholder>` values; point them at your own source workspace. **Never commit real local paths.**

**Project output never lives here** (`analysis/`, `sources/`, `knowledge-base/`, `*.mpr` are gitignored) — each migration runs in its own workspace that references this repo.

**Your build plan, `PROJECT.md`, and session notes live in your own project, not here.** This repo holds reusable tools + skills + small curated examples only. A project's architecture blueprint, numbered build plan, decision register, and running session diary belong in that project's own repo (e.g. `architecture/build-plan.md`, `PROJECT.md`, `SESSION-NOTES.md` at the project root) — never committed back into the toolkit. If a pattern from that plan turns out to be reusable across projects, promote it into a `skills/learned-*.md` file here instead of leaving the whole plan in place.

## Used by

- `pipelines/outsystems/` — OutSystems 11 → Mendix pipeline (was the standalone `os-migration-pipeline` repo)
- `pipelines/java-angular/` — Java + Angular/Spring Boot → Mendix pipeline
- `pipelines/node-express-react/` — Node/Express + React → Mendix pipeline (regex-based, proven on one source shape — see its README)
- Several other client integration and migration projects
