# mxcli-project-toolkit

> **Agents: this README is orientation, not the spec.** For any pipeline work, the executable authority is `skills/conversion-runbook.md` (stages, gates, interview protocol) plus each stage's owning skill — load those before producing anything. Stage summaries here and in `toolkit-guide.html` are routing, not deliverable lists.

Shared skills, stage-gate tooling, and learnings for **Mendix migration and development projects**, driven by an AI coding agent over [`mxcli`](https://github.com/mendixlabs/mxcli).

Same stages, different entry points (`skills/conversion-runbook.md` → "Entry Modes"; the mode is a **confirmed Stage-P decision**, never silently inferred):

| You're starting from | Mode | Stages |
|---|---|---|
| Legacy source code (± docs, ± SME) | **Migration** | P, 0–7 |
| Requirements only — specs, BRDs, workshop output, a reverse-engineering brief | **Requirements-driven** | P, 0–6 |
| Just an idea, or a running start on the model | **Greenfield** | P (light), 0 (scope), 5–6 |
| An app you already have — audit, lint, regression net | **À la carte** | none: `skills/existing-app-assurance.md` |

---

## Quickstart

```bash
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
~/Mendix/mxcli-project-toolkit/bin/doctor.sh                      # 1. what this machine is missing
~/Mendix/mxcli-project-toolkit/bin/init-project.sh <project-root>  # 2. scaffold one project
```

`doctor.sh` probes the machine once and says in plain language what is missing — bash, Python 3,
sqlite3, line endings, Studio Pro or mxbuild — and exits non-zero if something will break a
stage. It replaces every "the toolkit is broken" that is really a missing prerequisite. When
the mxbuild toolchain is what's missing, `doctor.sh --install <project-root>` fetches the
project's `./mxcli` and the version-matched mxbuild (~90 MB + ~800 MB one-time, into
`~/.mxcli/`), printing the plan and asking first; agents and CI pass `--yes`.

`init-project.sh` scaffolds everything one project needs — `intake.md`, `PROJECT.md` (the
decision register), `CLAUDE.local.md` (runbook-first wiring + baseline routing, auto-loaded
every session), the six agent stubs, the `index.html` dashboard — and opens the visual guide.
Idempotent: re-running never overwrites. Then follow `skills/conversion-runbook.md`; it
interviews you through each stage, and each stage ends with
`bin/gate-check.sh <project-root> <stage>`.

**Or install the slash command once** and every project is a `/toolkit-init` away:

```bash
mkdir -p ~/.claude/commands && cp ~/Mendix/mxcli-project-toolkit/commands/toolkit-init.md ~/.claude/commands/
```

**New here? Open `toolkit-guide.html` in a browser** — the whole journey as a visual page. *Agents:* open it for the user only under the first-touch rule in `CLAUDE.md` (sentinel `<project-root>/.claude/.guide-shown` absent), never once per session.

---

## Choose your environment

The pipeline is the same everywhere. What differs is **where the model gets built and verified**,
and that decides which tools you have in Stage 5+. Decide once, at Stage P; intake asks.

| | **Cloud container** | **Laptop + Studio Pro** |
|---|---|---|
| What it is | Claude Code on the web / in the app, a GitHub Codespace, a CI runner — or the **same Linux image on your own machine** as a VS Code Dev Container (`mxcli init` ships `.devcontainer/`: Docker-in-Docker, Postgres, Claude Code preinstalled) | macOS or Windows with Studio Pro installed, the agent running beside it |
| Build gate | `mxbuild`, a plain binary: `doctor.sh --install` or `mxcli new` downloads it | the `mxbuild` inside the Studio Pro bundle (macOS) or install (Windows, set `MXBUILD_PATH`) |
| Write modes | **CLI only** — `bin/exec.sh script.mdl` (snapshot → exec → mxbuild gate → auto-restore) | CLI, plus **MCP + MDL** and **hand-rolled MCP** with Studio Pro open — see "Stage 5+" below |
| Run & test loop | `mxcli run --local` — warm, Docker-free: cold build ~10–15 s, then ~1 s incremental hot-reload; `--hub` adds a public URL to click from any phone (Linux binary only). `mxcli docker run` is the Compose-stack alternative when you want a throwaway Postgres + app container | Studio Pro's own Run Locally, or the same `mxcli run --local` / `mxcli docker run` |
| Verification | Playwright + OQL against the running app, headless; screenshots via `mxcli playwright` | same, plus a human looking at Studio Pro |
| Durability | **Ephemeral** — the git remote is the workspace; commit and push at every gate, before every idle | your disk |
| Owning skill | `skills/cloud-dev-environment.md` (setup order, session loop, the two container-only hazards); `skills/handoff-to-studio-pro.md` when a person needs to open what you built | this README + `skills/learned-mcp-patterns.md` |
| Field-proven | yes — one empty repo to pushed scaffold in a session, 2026-08-31; second run 2026-09-02 | yes — every project before 2026-08 |

**Which one?** The container is the *simpler* of the two, not the lesser: the whole pipeline
is headless, nothing on the critical path needs a GUI, and there is exactly one write mode to
get right. Choose Studio Pro when a human will be co-editing the model, or when you need the
MCP write modes for widget shapes MDL cannot express yet. Mixing is normal — build headless,
hand off to Studio Pro for the demo (`handoff-to-studio-pro.md` is exactly that). Stages 0–4
never touch the model at all, so the choice only bites at Stage 5.

**Platform notes** (the full list lives in `doctor.sh`, which checks rather than describes):

- **Windows: Git Bash, not WSL** — WSL cannot see Studio Pro or the process holding your `.mpr`. Python 3 from python.org with "Add to PATH" ticked, not the Store alias. Studio Pro automation (`save-sp.sh`, `restart-sp.sh`) is macOS-only (`osascript`); on Windows drive Studio Pro by hand at those points.
- **`exec.sh` never writes with its gate off silently — but it does write.** Without a reachable mxbuild it prints `GATE SKIPPED` and continues. On any platform the fix is `doctor.sh --install <project-root>`, or `export MXBUILD_PATH=...` to a Studio Pro install.
- **Linux/container: `mxcli run --local` collapses a split-model `.mpr`** to a monolith on start (CRITICAL, `bug-logs/mxcli-bugs.md`, 2026-09-01). Snapshot before every run, restore the split format and `git status` before the next commit. `cloud-dev-environment.md` carries the exact sequence.

---

## The project folder

This clone stays clean — project output never lands inside it. **Everything else lives inside one project folder** (usually one git repo — it is the session root, the workspace root, and the mxcli target all at once):

```
<project-root>/                          ← ONE folder per project; open your agent here
  PROJECT.md · intake.md · index.html    ← decision register + dashboard (bin/init-project.sh)
  CLAUDE.md · CLAUDE.local.md            ← mxcli init's + the toolkit wiring, in that order
  .claude/agents/                        ← agent stubs (bin/init-agents.sh)
  .devcontainer/ · ./mxcli               ← from mxcli init; the binary is gitignored, re-fetched per session
  sources/                               ← legacy source or requirements docs, read-only
  analysis/<source-name>/
    knowledge-base/                      ← extraction JSON + BRDs (config.json knowledgeBaseDir)
  architecture/ · design/                ← stage 3/4 artifacts
  mdlsource/                             ← MDL scripts
  <Project>.mpr + mprcontents/           ← the target app (split model; both halves travel together)
```

Order matters on a fresh repo: `./mxcli init` **overwrites**, `init-project.sh` adds alongside,
`bootstrap-project.md` (once an app exists) **merges**. Run them in that order and never re-run
`mxcli init`. Do **not** create `analysis/<project>/` as a sibling of the project; the one
exception (licence forbids storing client source beside the target app, intake Q2) is in
`migration-pipeline.md` → "Project Workspace Convention".

---

## How the pipeline flows

```
P  Kickoff        → intake + workspace scaffold                    [ba-agent]
0  Triage ✋       → scope signed off; extractor reuse-vs-build      [ba-agent]
1  Analysis       → code extractors + document extraction + SME     [ba-agent]
2  Requirements   → validated BRDs                                  [ba-agent]
3  Architecture ✋ → module boundaries, fit-gap, security, design    [architect-agent]
4  Build Plan ✋   → numbered, dependency-ordered scripts + briefs   [architect-agent]
5  Build          → working modules, gated                          [mdl-agent → gate-agent]
6  Test           → Playwright + DB assertions                      [test-agent]
7  Cutover ✋      → legacy data decision, rollback (migrations)     [ba-agent]
```

`✋` is a hard gate: the question is asked in chat, the agent waits, and the answer lands in
`PROJECT.md` as `CONFIRMED` or `ASSUMED` — the latter only when the user said "you decide".
Stage 0 is a gate, not a formality: it decides whether the app even justifies an extraction
pipeline, and bounds the scope. Everything stage-by-stage — owners, artifacts, what each gate
asks — is `skills/conversion-runbook.md`; `CONVERSION-RUNBOOK.md` at the root is the short
version and `toolkit-guide.html` the visual one.

**Before asking the user anything, or writing anything: query the model → read the source → ask the human, in that order.** Full source-of-truth table in `skills/query-the-model.md`. Two rules that are load-bearing and easy to skip under pressure: `SHOW ASSOCIATIONS` before every `CREATE ASSOCIATION` (MDL has no `IF NOT EXISTS`), and `SHOW ENTITIES IN <MarketplaceModule>` before referencing a marketplace module (`check --references` cannot validate what isn't imported).

---

## Stage 5+: writing to the model

**Stages 0–4 are pure LLM** — markdown, JSON, diagrams; no mxcli command runs, no `.mpr` is
touched. It is far cheaper to fix a wrong module boundary in a diagram than after 40 scripts
assume it.

**The default write mode, in every environment, is the CLI:** you write a readable MDL script,
`bin/exec.sh` snapshots both halves of the model, executes it, runs mxbuild, and restores on
failure. The script is version-controlled and reviewable before it runs, and one exec can
scaffold an entire module. Every pre-write rule — the STOP table of operations that corrupt
deterministically, the per-operation mode table — is `skills/learned-mdl-preflight.md`; read it
before the first line.

**With Studio Pro open you get two more**, for the refinement phase:

| Mode | When | Why |
|---|---|---|
| **MCP + MDL** (`mxcli --mcp exec script.mdl`) | UI iteration, targeted changes — anything where restarting Studio Pro between edits would kill your flow; also microflows with inline association sets | Same MDL, routed through Studio Pro's own engine: changes land live, and a class of BSON serializer bugs is sidestepped |
| **Hand-rolled MCP** (`pg_patch_page`, `ped_create_document`) | Widget JSON shapes MDL has no syntax for yet — DataGrid2 column configs, dropdown filters, visibility inside datagrid `customContent` | Raw payloads against the model API. Only when the other two genuinely cannot; patterns and save discipline in `skills/learned-mcp-patterns.md` |

**Studio Pro GUI** is not a write mode for agents — it is the human fallback for the two
operations that corrupt on every CLI/MCP retry: `ALTER SETTINGS` and dropping an attribute that
has security grants.

**The crash net.** An `.mpr` is two parts, `Project.mpr` (SQLite index) and `mprcontents/`
(BSON units). `bin/exec.sh` snapshots both before every batch, five rotate, and
`bin/restore-mpr.sh` rolls both back together — either alone is useless. Git commits at phase
gates are the real history; ad-hoc `.mpr.backup` copies are banned.

**Testing (Stage 6)** uses two independent layers because they catch different things:
Playwright walks the running app as a user (broken flows); OQL via `mxcli -p ... -c "SELECT ..."`
cross-checks what the UI shows against the database (silent data corruption). Both run before
any scenario is marked passing — `skills/testing-shape.md` says what "tested" means and lists
the confirmed ways a test reports green over a broken feature. With Studio Pro, a screenshot
before it recompiles is worthless: exec → reopen Studio Pro → confirm → `curl` port 200 →
only then screenshot.

---

## Something went wrong

| Symptom | Where | What to do |
|---|---|---|
| Studio Pro won't open the project / fails to load | SP | A bad write landed. `bin/restore-mpr.sh` restores **both** halves from the last snapshot; you lose at most one exec batch |
| Studio Pro hangs on launch | SP | A stale process holds the lock: `pkill -f studiopro`, then remove a stale `.mpr.lock` if it still won't start |
| Every exec reports `gate=skipped` | container / Windows | No mxbuild reachable — `doctor.sh --install <project-root>`. Nothing before it ran was verified; say so in the checklist |
| `git status` shows hundreds of `D` under `mprcontents/` and a 15 MB `.mpr` | container / Linux | The split-model collapse after `mxcli run --local` or `marketplace install`. `git checkout HEAD -- <App>.mpr mprcontents/` (or restore the pre-run snapshot). Never `git add -A` after a local run |
| The container was reclaimed | container | Anything not pushed is gone. Clone, re-fetch `./mxcli`, `gate-check.sh` tells you where the project actually stands — never memory |
| A CE error that looks like a tool quirk | any | `bug-logs/mxcli-bugs.md` first; the bundled `.ai-context/skills/` may teach a pattern that was unsafe on your version |

---

## Context cost — running an agent for weeks without burning the month in three days

A month's token allowance, 20% gone in three days, measured: 89% of cache-read spend came from
context above 200k tokens. The 1M window removed a cost governor and handed the job to you with
no meter. The finding, the numbers, and the tiered hooks that put the meter back
(`bin/install-claude-hooks.sh --basic | --full | --full --ceiling`) are in
**`process/context-cost.md`** — read it before installing anything; tier 3 blocks tool calls
and is never a default.

---

## Division of labor: this toolkit vs bundled mxcli skills

Every mxcli project has a `.ai-context/skills/` directory (bundled by `mxcli init`, refreshed with each release) containing syntax references, widget patterns, CRUD templates, and how-to guides. **This toolkit does not duplicate those.**

| Layer | Owned by | Contents | Updated by |
|---|---|---|---|
| `.ai-context/skills/` | mxcli (bundled) | MDL syntax, widget patterns, CRUD/data-processing templates, integration guides | `mxcli` release |
| `mxcli-project-toolkit/skills/` | This repo | Conversion runbook, migration pipeline, build discipline, agent roles, STOP rules from real corruption incidents | You (via `git pull`) |

**When the two disagree, this toolkit's STOP rules take precedence** — until explicitly retested and the result stamped in `bug-logs/mxcli-bugs.md`. Migration assessment (`assess-migration`) is bundled with mxcli; `skills/assess-migration.md` here is a pointer plus toolkit-specific deltas only.

---

## When to use which skill

<!-- Generated from bin/lib/skill-routing.tsv by bin/render-routing.sh.
     Do not hand-edit between the markers: add or change the ROW, then re-render. -->
<!-- ROUTING:BEGIN readme-situational -->

**Spine — what am I doing, who decides, how do I ask**

| Task | Skill to load |
|---|---|
| Deep, adaptive interview on one topic, on demand, when a checkpoint's 2+1 or a single question batch isn't enough | `skills/grill-mode.md` |
| CAC-1, closing Stage 0 in EVERY entry mode — scope IN: full scope or a slice, and in what order. Opens with a brainstorm, not options | `skills/checkpoints/checkpoint-scope.md` |
| CAC-1b, after Stage 1 — scope OUT: is what extraction produced what you meant. No gate stops you; run it late against the BRDs if it was skipped | `skills/checkpoints/checkpoint-extraction.md` |
| CAC-2, after BRD scaffolding and before enrichment — capability grouping and enrichment order | `skills/checkpoints/checkpoint-brd.md` |
| CAC-3, after BRD validation and before architecture locks — the hidden business rules that are expensive to discover later | `skills/checkpoints/checkpoint-architecture.md` |
| CAC-4, after rearchitect sign-off and before any design artifact — branding and UI direction. Opens with a brainstorm | `skills/checkpoints/checkpoint-design.md` |
| CAC-5, after design sign-off and before the build plan — build order and slice boundaries. Opens with a brainstorm | `skills/checkpoints/checkpoint-build.md` |
| CAC-6, after Stage 6 passes and before any cutover step — migration mode only, and a hard gate: every answer lands CONFIRMED, no ASSUMED defaults | `skills/checkpoints/checkpoint-cutover.md` |
| Generating a new project's CLAUDE.md — baseline routing plus project-specific facts | `skills/bootstrap-project.md` |
| Setting up or resuming an mxcli project in a cloud/ephemeral container — the one-time setup order (mxcli download → mxcli init → init-project.sh → sources decision → push) and the commit-and-push loop that survives container reclaim | `skills/cloud-dev-environment.md` |
| Cutover and retrospective — promoting proven patterns back into the toolkit | `skills/close-the-loop.md` |
| Before citing ANY behavioural claim about the harness, the Mendix runtime or a test tool as evidence — a claim not in the register may not be cited | `skills/measured-claims.md` |
| Any review pass that runs more than once — module-review, coherence, monkey, wiring-sweep: findings accumulate across runs, a per-run report cannot show a trend | `skills/improvement-register.md` |

**Source — reading a legacy system (migration entry mode)**

| Task | Skill to load |
|---|---|
| Rendering a filled triage.md for review — the triage.html surface Stage 0 names. Renders only; the Stage 0 verdict stays with gate-check and the judgement with source-triage.md | `bin/triage-report.sh` |
| Reviewing what the extraction actually produced — the Stage 1 surface, and the file the Stage 1 gate looks for. Renders a code-extracted and a document knowledge base alike, so a requirements-driven project gets the surface too; prints no zero that a second record does not agree with | `bin/extraction-report.sh` |
| Assessing or planning a migration up front, before any pipeline is chosen | `skills/assess-migration.md` |
| Running the extraction pipeline | `skills/migration-pipeline.md` |
| Migrating from a stack that has no dedicated pipeline | `skills/migrate-general.md` |
| Migrating an OutSystems app | `skills/migrate-outsystems.md` |
| Understanding OutSystems 11 source | `skills/source-os11.md` |
| Reading the OutSystems XML export schema | `skills/os-xml-schema.md` |
| Understanding Node/Express+React source, its layout assumptions and its gaps | `skills/source-node-express-react.md` |
| Scanning or classifying an unstructured document folder | `skills/document-discovery.md` |
| Validating an extractor's output before its BRDs are trusted | `skills/extractor-quality-loop.md` |
| Extracting Excel/Word/PDF specs into a knowledge base | `skills/kb-generation.md` |

**Requirements — what must be built**

| Task | Skill to load |
|---|---|
| Reviewing what the BRDs actually say — the Stage 2 surface, for BRDs from any source. Reads every knowledge base at once, and keeps a section that is absent-because-not-applicable apart from one that is absent-because-expected | `bin/brd-report.sh` |
| Validating a new stack pipeline's extraction quality | `skills/qa-loop-goal-pattern.md` |
| Writing or enriching a BRD JSON | `skills/brd-generation.md` |
| Validating BRDs against the code and document KB | `skills/brd-validation.md` |
| Turning BRDs plus architecture into a numbered, dependency-ordered build plan | `skills/brd-to-build-plan.md` |
| Building the Stage 4 coverage ledger — every requirement either claimed by a build-plan row or catalogued with a reason, never invisible | `skills/coverage-ledger.md` |
| Checking a coverage ledger against its BRD — every scalar leaf CLAIMED, LEDGERED, UNCLAIMED, PHANTOM or DOUBLE-CLAIMED, so coverage is measured rather than remembered | `bin/coverage-check.sh` |
| Writing an actual .journey.json — the worked field-by-field reference for the contract journey-proof.md argues for | `skills/journey-examples.md` |
| Extracting structured requirements from a large delivered document corpus into per-scope knowledge-base files | `skills/corpus-extraction-integrity.md` |

**Architecture — how it is shaped**

| Task | Skill to load |
|---|---|
| Diagramming target architecture — module defs, wiring, fit-gap, marketplace, security, NFRs, integrations | `skills/architecture-blueprint.md` |
| Deciding module boundaries before "create module" | `skills/modularize-domain.md` |

**Design — how it looks, before any MDL**

| Task | Skill to load |
|---|---|
| Before porting ds.css into SCSS, and at the Stage-3 gate — greps the stylesheet for rules that cannot match the HTML Mendix emits (rem against the real root, table/th/td selectors, positional row selectors). mx check, mxcli check and mxcli lint are all blind to CSS | `project-bin/check-design-portability.sh` |
| Designing the brand and ONE ANNOTATED WIREFRAME PER SCREEN before building pages — the design system alone is half the deliverable | `skills/design-artifacts.md` |
| Before a wireframe or a design commits to a WIDGET — and when a page script hits a parse error that looks like a syntax mistake: the short list of things MDL cannot write at all, and the four-minute probe that answers it at Stage 3 instead of at build time | `skills/learned-mdl-cannot-express.md` |

**Build — the loop itself**

| Task | Skill to load |
|---|---|
| Building a module with mxcli — verified, iterative, coverage-checklist gated | `skills/iterative-build-loop.md` |
| After marking a module done, or any time "how much is built vs proven" is asked — renders build-plan.html from done- prefixes and verify-module.sh/improvement-register.md, kept as two honestly separate views | `project-bin/build-plan-status.sh` |
| Turning a client-derived Mendix app into a clean, shareable demo with zero client fingerprint — branding, data, custom widgets | `skills/anonymize-client-app-for-demo.md` |
| Handing a headless-built model to a person — opening it in Studio Pro, a free sandbox, or a colleague's machine: the model travels, the demo data and runtime config (keys, an agent's bound model) do not, and each needs its own re-establish step | `skills/handoff-to-studio-pro.md` |

**Build · MDL — the language and tool reference**

| Task | Skill to load |
|---|---|
| Writing MDL microflow scripts — worked recipes | `skills/mdl-cookbook-microflows.md` |
| Writing a single MDL script that takes a project from nothing to a working vertical slice — execution order, why it is deliberately non-idempotent, the instrument hierarchy, and the silent failures that pass every check | `skills/build/mdl/oneshot-mdl-method.md` |
| Writing a popup page's microflow with a retry/validation-failure branch that re-shows the same popup — missing close page stacks duplicate dialogs | `skills/learned-popup-navigation.md` |
| Writing MDL for a datagrid column with ShowContentAs customContent that needs to display a bound value | `skills/learned-datagrid-customcontent-binding.md` |
| Writing a popup whose primary button creates/commits an object or triggers a backend flow — MDL has no native toast, so feedback must be explicit | `skills/learned-popup-feedback-pattern.md` |

**Build · Pages — page-building patterns**

| Task | Skill to load |
|---|---|
| Building and auditing Mendix pages — widget patterns, datasource shapes | `skills/learned-page-patterns.md` |
| Generating a whole page tree in one script — the structure patterns that survive it | `skills/oneshot-page-structure-patterns.md` |
| Building or auditing a collapsible sidebar nav — Atlas Core's collapsed state needs icons assigned per menu item or it silently clips label text | `skills/learned-sidebar-collapse-icons.md` |
| Building or altering any data grid — native DATAGRID vs pluggable DG2 decision rule, the ALTER PAGE INSERT corruption, sort-by and filter-binding traps | `skills/learned-dg2-patterns.md` |

**Build · Agents — Mendix AI agents, tools, knowledge bases, chat UI**

| Task | Skill to load |
|---|---|
| Building a Mendix AI agent — the agent is runtime data not a model document, so JSON import, tool microflows, knowledge base chunk loading and the runtime wiring all sit outside MDL, and mxbuild stays green when they are wrong | `skills/mendix-agents.md` |
| Embedding a copilot chat panel — the frame is yours, ConversationalUI owns the conversation; wireframe to tokens to snippet to page placement | `skills/mendix-agent-ui.md` |
| Standing up a project's GenAI agents in any environment — MxCloud key import, model-to-agent binding, KB indexing and the agent-answers-a-question proof are all UI-only (no MDL/SQL path), driven with Playwright; you need the resource keys handed to you as env vars first | `skills/mendix-agent-setup.md` |

**Build · Workflow**

| Task | Skill to load |
|---|---|
| Writing or debugging a Mendix native Workflow (CREATE WORKFLOW/USER TASK/OUTCOMES) — syntax, the 11 workflow microflow statements, DECISION vs CALL MICROFLOW, and the two corruption classes (binary-version $Type, and create-before-reference) | `skills/learned-workflow-patterns.md` |

**Build · Integration**

| Task | Skill to load |
|---|---|
| Building a REST integration (consumed or published) for the first time on a project — the checks that avoid a rebuild after the first live call | `skills/rest-integration-first-time-right.md` |

**Verify — does it work**

| Task | Skill to load |
|---|---|
| Auditing or regression/e2e-testing an EXISTING app — no intake, no stages, no gates | `skills/existing-app-assurance.md` |
| Running the ledger rung alone — recompute every stored ledger status against the live model and catch the STALE rows that claim built for something the model no longer has | `project-bin/conformance-check.sh` |
| Running the wiring rung alone — a module imported but never reached, an element built but wired to nothing, a boundary crossed; mxbuild and e2e are blind to all three | `project-bin/graph-sweep.sh` |
| Before any runtime test — brings the stack up unattended and PROVES the thing that answered is this project's app; --check makes it report-only | `project-bin/test-stack-up.sh` |
| Standing up or extending the Playwright e2e harness | `skills/e2e-harness-base.md` |
| Writing DB assertion tests that cross-check UI state against the database | `skills/learned-db-assertions.md` |
| Establishing the data and identities a journey run needs — BEFORE it runs. Derive and measure with project-bin/fixture-manifest.sh first; interview only the residue, and never seed from inside the harness | `skills/fixture-seeding.md` |
| Proving a module's user journey end-to-end — the deep form of step 3 PROVE; use whenever an instrument reports green and you cannot say what would have made it red | `skills/journey-proof.md` |
| Running the fuzz/crash net on a module whose journeys are already green — and reading the result, which is NOT evidence the module works | `skills/monkey-test.md` |
| UX audit and screenshot-loop discipline | `skills/learned-skill-ux-audit.md` |
| Tracking scope delta between the BRD and the built state | `skills/learned-skill-scope-delta.md` |
| Writing or reading docs/report.json — the append-only contract every instrument writes to and every renderer reads; open BEFORE building a new instrument or a second renderer | `skills/report-schema.md` |
| Installing, extending, debugging or porting the verification harness — which part owns what, which parts run standalone, and what a missing part must report | `skills/harness-architecture.md` |
| Checking whether the whole journey hangs together rather than each piece — finds correctly-built components nothing reaches, which per-element conformance and UI tests both miss | `skills/process-coherence-pass.md` |
| After every module's CONFIRM stage — counts proven modules since the last cluster/full coherence pass and exits DUE once the threshold is reached, so the cadence isn't left to memory | `project-bin/coherence-cadence.sh` |
| Turning an already-rigorous run into a narrated proof a stakeholder can trust without running anything | `skills/e2e-evidence-report.md` |
| Recording a narrated screen-capture demo of a running app for a human to watch — opening on the app instead of a blank frame, and keeping captions synced to the pixels | `skills/record-demo-video.md` |
| Running lint as a gate rather than a report — per-rule ratchet against a committed baseline, plus the crash and collapse guards that stop a blind rule passing | `project-bin/lint-gate.sh` |
| Reading a lint result, or writing/repairing any .star rule — lint's failure mode is a confident clean pass, so 0 findings is a claim needing evidence | `skills/lint-that-actually-runs.md` |
| Every module before it is called done — does every clickable thing actually do something; run AFTER the happy-path journey is green, never before | `skills/wiring-sweep.md` |
| The user asks for a full end-to-end test, a click-through proof, or does-everything-actually-work — or you are unsure which harness skill applies; this one routes you | `skills/full-harness-audit.md` |
| End of any build+test cycle that wrote docs/report.json — did the testing itself hold up, not just get filed; one level up from finding-disposition | `skills/test-result-audit.md` |
| Any report from a test/review run is about to be published — no report ends without a disposition for every finding | `skills/finding-disposition.md` |

**Diagnose — something is broken and it may be the tooling**

| Task | Skill to load |
|---|---|
| Studio Pro will not load the project, or the .mpr looks gutted — recover before relaunching SP, never git checkout | `skills/mpr-corruption-and-sp-load-errors.md` |
| Preparing an mxcli/Studio Pro bug for submission — scope pinning, read-back-vs-write-path verification, gate-sensitivity negative controls, severity scoping, before it's called filable | `skills/bug-submission-checklist.md` |
| A page/grid/combobox renders empty (blank cells, zero rows, zero options) during UI review or an e2e run — before assuming a single cause | `skills/empty-widget-triage.md` |
| Suspecting an mxcli/mxbuild tool defect and deciding whether to swap a binary — proving it's version-specific without risking the real model | `skills/sandbox-ab-tool-defect-probe.md` |
| Restarting Studio Pro on macOS — the reopen bug, the port bug, and detecting a real hang vs a slow load | `skills/restart-sp-reopen-and-hang-detection.md` |
| Driving the whole toolkit pipeline on a real source to find what the written skills don't say — the toolkit is the subject, not the app it builds | `skills/field-run.md` |
| Needing Studio Pro load evidence without a human at the GUI — direct-binary launch and log capture; a capture technique, NOT a validated pass/fail oracle | `skills/scriptable-sp-verification.md` |
| A runtime test reads/writes data that then is not there, or vice versa — three local Postgres instances can answer on this box; resolve the real port from the project's own compose file first | `skills/learned-local-db-confusion.md` |
| gate-check.sh reports a Stage 0 file not found that plainly exists — ANALYSIS_BASE falls back to project root until Stage 1; move the file, do not debug the script | `skills/gate-check-file-locations.md` |

**Reference — lookup tables, not method**

| Task | Skill to load |
|---|---|
| Working with the Mendix Epics board programmatically — creating/reading stories and epics, updating workflow state, or integrating BRDs with the portal | `skills/mendix-epics-api.md` |
<!-- ROUTING:END -->

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

**Lower-friction path — use it liberally:** drop what you have (a bug-log entry, a diff, three
sentences) into `contrib/inbox/` and open a PR — no quality bar, triage does the polishing. Or
let it be drafted for you: `bin/harvest-learnings.sh <project-root>` scans a project's bug
logs, register promotion tables and locally-patched toolkit scripts and writes ready-to-PR
inbox files. Full picture, lanes and review process: `CONTRIBUTING.md`. Merged contributions
get a `CHANGELOG.md` credit line naming you or your project.

---

## Consuming this toolkit

**Reference model (default):** clone once, point projects at it — no copies, no drift.
```
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
```
Each project's `CLAUDE.local.md` references `~/Mendix/mxcli-project-toolkit`. Pull updates with `git pull` — **everything referenced (skills, runbook, checkpoints, gate-check) updates instantly for all projects.** The three artifacts that were *copied* into a project (intake.md, agent stubs, the baseline-routing table in its CLAUDE.md) don't: run `bin/sync-project.sh <project-root>` after a pull — it appends new intake questions, refreshes untouched agent stubs (never completed ones), and flags a stale baseline routing. Then tell any already-running session to re-read the runbook.
For a self-contained handoff, add it as a git submodule instead. Per pipeline, run `npm install` inside `pipelines/<x>/pipeline` (node_modules is gitignored).

### Baseline routing — copy this into every new project's CLAUDE.md / CLAUDE.local.md

The "When to use which skill" table above is *situational* — load a skill when a specific task calls for it. A few skills apply on **every** MDL-writing session regardless of task, and situational discovery quietly misses them, because nothing mid-task prompts loading them. Every consuming project's own `CLAUDE.md`/`CLAUDE.local.md` (or wherever it tells agents what to read before writing MDL, e.g. its own `write-microflows.md`) should reference these directly, not rely on stumbling onto them:

<!-- Generated from bin/lib/skill-routing.tsv by bin/render-routing.sh.
     Do not hand-edit between the markers: add or change the ROW, then re-render. -->
<!-- ROUTING:BEGIN readme-baseline -->
| Always relevant for | Reference this |
|---|---|
| Any pipeline work at all — every session, before producing any stage artifact (not just "when unsure"); READMEs and the guide are orientation only | `skills/conversion-runbook.md` |
| Any question before asking the user or writing anything — query the model, then read the source, then ask the human, in that order | `skills/query-the-model.md` |
| Before writing any .js or .sh for a check, gate or report — and before adding a rule to an existing one: judgement goes in a skill, code only fetches facts a reader cannot | `skills/skills-over-scripts.md` |
| Any pass whose input is missing, stale or unresolvable — before recording UNMEASURED, N/A or a silent skip: name what was missing, say what you assessed against instead, still deliver a verdict | `skills/degrade-to-judgement.md` |
| Putting a question TO the user — any gate, any stage: ask in chat not in a file, two named options plus your recommendation, one batch per gate then end the turn | `skills/interview-protocol.md` |
| Any stage transition — the 2+1 format every CAC uses, and the one-register rule (answers land in PROJECT.md, never in a separate state file). The seven CACs themselves are routed per stage in the situational table | `skills/checkpoints/checkpoint-template.md` |
| Setting up or completing a project's dev-process subagents — once, at project start, not "on demand" | `skills/agent-roles.md` |
| Deciding whether to extract at all, before any BRD gets generated | `skills/source-triage.md` |
| Taking in a new source — before generating anything from it. Grades what the source can support; nothing else in this toolkit reads a source | `bin/source-sufficiency.sh` |
| Deciding who answers a question — before putting any batch to the user. gap/conflict/choice/user-only is what keeps a gate batch at four questions instead of 127 | `bin/question-kinds.sh` |
| Writing BRDs, especially several in parallel — "build" before the fan-out, "check" before any BRD is called done | `bin/facts-lock.sh` |
| Building any module — before the first script. The mdl-agent's single per-module input | `skills/module-brief.md` |
| Writing ANY MDL script — before the first line. Step 0 picks the write mode, then the STOP table overrides it for corrupting operations | `skills/learned-mdl-preflight.md` |
| Placing any document in a module — before the first `create`. Feature group, then Pages/Microflows/Services/Resources; the path comes from the brief's folder plan, and the table says which types mxcli can actually place | `skills/module-folder-convention.md` |
| Writing or fixing any microflow — MDL gotchas plus annotation discipline | `skills/learned-microflow-patterns.md` |
| Building any page or snippet — before the first widget. Wireframe, tokens, gallery reuse, cross-check; no wireframe means STOP | `skills/ui-preflight-pages.md` |
| Writing or reviewing any page or snippet — the spacing scale (8/16/24/32/48), section rhythm, and the page-header scaffold every full page starts with; sections at 0px apart and pages with no H1 are the defects it retires | `skills/design-spacing.md` |
| After every page-building script, and any time the UI looks wrong — the cheap repeatable look during the build: one page, one screenshot, three questions. Feeds Gate: UI, never replaces it | `skills/ui-loop.md` |
| Building or using the in-app design gallery | `skills/learned-stylegallery.md` |
| Before exec'ing ANY page script — compares the drafted MDL's shell against the wireframe's: page column, layout/nav shell, one H1. Measured 0/10 pages on a real first build, repaired wholesale 47 scripts later | `project-bin/check-page-shell.sh` |
| After drafting and again after exec'ing any page script — scores the page MDL (or `mxcli describe` output on stdin) against its wireframe: headings/actions/content/classes, weighted. The scored companion to check-page-shell's binary gate; 32% median measured without it, 90% first-draft with it. Every run is appended to the project's docs/PAGE-FIDELITY.tsv — first non-stub row per page = first-build score of record vs the ≥80% target (forward-reference stubs score with --stub, exempt) | `project-bin/page-fidelity.js` |
| Choosing CLI vs MCP+MDL vs hand-rolled MCP, or any MCP write session — three co-equal write modes, not CLI-only | `skills/learned-mcp-patterns.md` |
| Reviewing any module before calling it done — the ONE pass: build, gate, prove, LOOK (is it logical, does it look right, does it match our design, over every page not just the tested ones), confirm with the denominator stated | `skills/module-review.md` |
| Before calling any module tested — what testing a module means, and the false-green register of confirmed ways a test reports green over a broken feature | `skills/testing-shape.md` |
| Finishing any module — before calling it done. One command that runs every instrument and keeps "instrument faulted" apart from "feature failed"; in a wired project run the installed copy at bin/verify-module.sh | `project-bin/verify-module.sh` |
| A CE error or behavior that looks like a known mxcli quirk rather than a modeling mistake | `bug-logs/mxcli-bugs.md` |
| Any time an exit code, a tool's output or a subagent's report is about to become a stated finding — verify before you conclude | `skills/tool-output-is-not-ground-truth.md` |
| Before trusting a green check/exec/DESCRIBE result as proof, or when a runtime symptom appears over a fully green model — the register of constructs that pass early rungs and fail later ones | `skills/learned-detection-gaps.md` |
| Creating any entity, or calling a module security-ready — entity and grants land in one script, and ready means SHOW SECURITY MATRIX proves it | `skills/security-is-not-a-later-script.md` |
<!-- ROUTING:END -->

**Why this has to be explicit instead of implicit:** a project's own skill files are usually written before a given toolkit learning exists, or before a new one is added later — they never grow a cross-reference to it on their own. When you `git pull` this toolkit and it brings in a new baseline-worthy skill (most often a new `learned-*.md`), update every consuming project's routing to match — don't assume the next session will find it by chance.

**After cloning, set your local source paths** in `pipelines/<x>/pipeline/config.json` — the committed file ships with `<placeholder>` values; point them at your own source workspace. **Never commit real local paths.**

**Project output never lives here** (`analysis/`, `sources/`, `knowledge-base/`, `*.mpr` are gitignored) — each project runs in its own project folder (with `analysis/` inside it) that references this repo.

**Your build plan, `PROJECT.md`, and session notes live in your own project, not here.** This repo holds reusable tools + skills + small curated examples only. A project's architecture blueprint, numbered build plan, decision register, and running session diary belong in that project's own repo (e.g. `architecture/build-plan.md`, `PROJECT.md`, `SESSION-NOTES.md` at the project root) — never committed back into the toolkit. If a pattern from that plan turns out to be reusable across projects, promote it into a `skills/learned-*.md` file here instead of leaving the whole plan in place.

## Used by

- `pipelines/outsystems/` — OutSystems 11 → Mendix pipeline (was the standalone `os-migration-pipeline` repo)
- `pipelines/java-angular/` — Java + Angular/Spring Boot → Mendix pipeline
- `pipelines/node-express-react/` — Node/Express + React → Mendix pipeline (regex-based, proven on one source shape — see its README)
- Several other client integration and migration projects
