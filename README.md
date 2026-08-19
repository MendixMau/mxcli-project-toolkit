# mxcli-project-toolkit

> **Agents: this README is orientation, not the spec.** For any pipeline work, the executable authority is `skills/conversion-runbook.md` (stages, gates, interview protocol) plus each stage's owning skill — load those before producing anything. Stage summaries here and in `toolkit-guide.html` are routing, not deliverable lists.

Shared skills, prompt templates, and learnings for **Mendix migration and development projects**.

Serves three audiences — same stages, different entry points (see `skills/conversion-runbook.md` "Entry Modes"; the mode is a **confirmed Stage-P decision**, never silently inferred — if source code exists it gets analyzed, if specs exist stages 2–4 run, and greenfield is only for starting from a conversation):

- **Migrations** (legacy source code) — all stages.
- **Requirements-driven builds** (specs/BRDs/SME input, no legacy code) — stages 1–6; document discovery replaces source triage, extraction Path B/C replaces code extractors.
- **Greenfield mxcli builds** — Stage 5 onward; the standard Mendix build discipline is not migration-specific.
- **Existing apps — à la carte, no pipeline** — audit, lint, or put a regression/e2e test net under a Mendix app you already have. No intake, no stages, no gates: start at `skills/existing-app-assurance.md` and grab only the tools you need.

Used across all mxcli-powered projects — OS migrations, Java/Angular migrations, Node/Express+React migrations, and other client integration work.

---

## Quickstart

```bash
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
~/Mendix/mxcli-project-toolkit/bin/doctor.sh          # <- run this first, on any platform
```

`doctor.sh` probes the machine once and says in plain language what is missing — bash, a Python 3,
sqlite3, line endings, Studio Pro — and exits non-zero if something will break a pipeline stage.
It takes a second and it replaces every "the toolkit is broken" that is really a missing
prerequisite. **Windows and Linux users: do not skip it.** See *Platform support* below.

This clone stays clean — project output never lands inside it. **Everything else lives inside one project folder** (usually one git repo — it is the session root, the workspace root, and the mxcli target all at once):

```
<project-root>/                          ← ONE folder per project; open your agent here
  PROJECT.md · intake.md · index.html    ← decision register + dashboard (bin/init-project.sh)
  .claude/agents/                        ← agent stubs (bin/init-agents.sh)
  source/                                ← legacy source or requirements docs, read-only
  analysis/<source-name>/
    knowledge-base/                      ← extraction JSON + BRDs (config.json knowledgeBaseDir)
                                           (single-source projects may flatten to analysis/knowledge-base/)
  architecture/ · design/                ← stage 3/4 artifacts
  mdlsource/                             ← MDL scripts
  <Project>.mpr                          ← the target app
```

Do **not** create `analysis/<project>/` as a sibling of the project — analysis output belongs *inside* the project folder. The only exception is when licence/security constraints (intake Q2) forbid storing the client source alongside the target app; that split-workspace variant is described in `migration-pipeline.md` → "Project Workspace Convention".

**New here? Open `toolkit-guide.html` in a browser first** — the whole journey as a visual page: entry modes, the 9 stages, what each gate asks of you, and the don't-panic section. *Agents:* open it for the user only when `<project-root>/.claude/.guide-shown` is absent, then `touch` it — see the first-touch rule in `CLAUDE.md`. Never once per session.

**Install is one command per project:**

```bash
~/Mendix/mxcli-project-toolkit/bin/init-project.sh <project-root>
```

It scaffolds everything — `intake.md`, `PROJECT.md`, `CLAUDE.local.md` (runbook-first wiring + baseline routing, auto-loaded every session), all five agent stubs (inert until completed per `skills/agent-roles.md`), the `index.html` dashboard — and opens the visual guide. Idempotent: re-running never overwrites. Then just follow `skills/conversion-runbook.md` — it interviews you through each stage below.

**Even easier — install the slash command once**, and every project is a `/toolkit-init` away:

```bash
mkdir -p ~/.claude/commands && cp ~/Mendix/mxcli-project-toolkit/commands/toolkit-init.md ~/.claude/commands/
```

Typing `/toolkit-init` in any Claude Code session then runs the install, reads the runbook, and starts the Stage-P interview (or runs `sync-project.sh` if the project is already wired). Each stage's "done" checklist runs `bin/gate-check.sh <project-dir> <stage>`, which fails loudly if required artifacts are missing and regenerates `index.html` from the project's real state.

---

## Platform support

The toolkit is bash plus Python 3. Most of it is platform neutral; the exceptions are listed
here rather than discovered halfway through a stage.

| | macOS | Linux | Windows (Git Bash) |
|---|---|---|---|
| Analysis, BRDs, architecture, build plan, gates, reports | yes | yes | yes |
| MDL authoring and `mxcli` | yes | yes | yes |
| Context-cost hooks | yes | yes | yes |
| **Studio Pro automation** — `save-sp.sh`, `restart-sp.sh`, the SP handling in `exec.sh` | yes | no | **no** |

**Windows: use Git Bash, not WSL.** WSL is a separate Linux machine — it cannot see Studio Pro,
cannot find the process holding your `.mpr`, and reaches a locally running app only over a host
network hop with path translation on every file argument. The toolkit does none of that plumbing.
Git Bash runs where Studio Pro, `mxcli` and your model already live, and ships with Git for
Windows. `doctor.sh` detects WSL and warns.

**Windows: install Python 3 from python.org with "Add python.exe to PATH" ticked.** If typing
`python3` opens the Microsoft Store, that is the Store *alias stub*, not an interpreter. The
toolkit detects and skips it, but turn it off anyway: Settings → Apps → Advanced app settings →
App execution aliases.

**What Studio Pro automation being macOS-only actually costs you.** It is built on `osascript`,
`lsof` and `open -a`. `save-sp.sh`, `restart-sp.sh` and `check-sp-health.sh` detect a non-macOS
platform, say so, and exit — they will not half-run. Drive Studio Pro by hand at the points where
they would have saved, restarted or reopened it. Everything either side of that still works.

> **Known hazard on Windows and Linux — `bin/exec.sh` writes with its safety gate off.**
>
> `exec.sh` validates every model write by running `mxbuild`, which lives *inside a macOS Studio
> Pro application bundle*. When it cannot find it, it prints `mxbuild or java not found — GATE
> SKIPPED` and **continues with the write anyway**. You get a clean-looking exec with nothing
> verifying it. Set this before any write and the gate works normally:
>
> ```bash
> export MXBUILD_PATH="/c/Program Files/Mendix/<version>/modeler/mxbuild.exe"
> ```
>
> Same file, second gap: the guard that refuses two concurrent writes uses `pgrep`, which Git Bash
> does not have, so it silently never fires. Do not run two write sessions against one model on
> Windows. Both are tracked for a proper fix.

**Existing clone from before 2026-08-18?** You predate `.gitattributes`, so if git checked the
scripts out with CRLF they will not run. Fix once:

```bash
cd ~/Mendix/mxcli-project-toolkit
git config core.autocrlf false && git rm --cached -r . && git reset --hard
bin/install-claude-hooks.sh --full     # re-install: the installed copies are the old ones
```

Then re-run `bin/sync-project.sh <project-root>` per project to refresh its copied scripts.


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
   (brd-to-build-plan.md)                              [architect-agent]
    + per-module brief (module-brief.md)  [ba-agent drives, pulls architect-agent]
        │
        ▼
5. BUILD                plan + brief → running Mendix app, one module at a time, gated
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

`✋` marks a hard gate — the pipeline does not proceed without an explicit, recorded decision. At every gate the question is actually asked in chat and the agent waits; `ASSUMED` is only recorded when the user was asked and delegated ("you decide"), never because asking was skipped. See `skills/conversion-runbook.md` §1 for the exact interview mechanics every gate runs.

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

*(A worked end-to-end example used to live in `examples/`. It was removed on 2026-08-03 because it was a client architecture document rather than a synthetic sample. A replacement built from invented data is on the backlog.)*

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

## Context cost — read the finding before you install anything

A month's token allowance, 20% of it gone in three days: about **2x the sustainable rate**. The
cause was not carelessness. Measured across 10,855 main-loop calls on one project:

| model | calls | median ctx | p90 | max | over 200k |
|---|---:|---:|---:|---:|---:|
| Sonnet 4.6 — 200k window | 2,416 | 104k | 147k | 166k | **0%** |
| Opus 5 — 1M window | 8,439 | 296k | 689k | 907k | **70%** |

**89% of cache-read spend ($1,276 of $1,437) came from context above 200k** — territory that was
*structurally impossible* on the older model.

The 200k window was a **cost governor disguised as a limitation**. It was experienced as friction
— "I have to compact constantly" — while doing the budgeting for free, on every call. The 1M
window did not make sessions cheaper; it removed the thing that was making them cheap and handed
the job to you, with no meter and no alarm. A habit that had been enforced became optional, and
optional habits decay.

Two things people reach for that do not fix it:

- **A cheaper model.** Sonnet 5 is also a 1M window. It cuts the *rate* ~40% and leaves the 89%
  untouched. Per call: Opus@341k $0.17, Sonnet@341k $0.10, **Opus@100k $0.05**. Context discipline
  is a 3.4x lever; model tier is 1.67x.
- **Just remembering to `/clear`.** The cost is on the other side. After a `/clear`, rediscovering
  state from `PROJECT.md` + checkpoints + progress + handoffs cost **100k tokens** — and whatever
  a session reads at startup rides in its prefix and is re-read on *every subsequent call*. ~$10,
  paid ~300 times. That is what `RESUME.md` and `checkpoint.sh` exist to prevent; see
  `skills/close-the-loop.md`.

### The hooks, and why they are tiered

```bash
bin/install-claude-hooks.sh              # prints the tier table, installs nothing
bin/install-claude-hooks.sh --basic      # tier 1
bin/install-claude-hooks.sh --full       # tier 1 + 2
bin/install-claude-hooks.sh --full --ceiling   # + tier 3, which BLOCKS tool calls
bin/install-claude-hooks.sh --uninstall
```

These hooks are **user-global**: `~/.claude/hooks/` fires in every repo and every concurrent
session on the machine, Mendix or not. That asymmetry is the whole reason for the tiers — a bad
skill wastes tokens, **a bad global hook blocks work everywhere**.

| Tier | Flag | What you get | Who it is for |
|---|---|---|---|
| 1 | `--basic` | `shrink-image-read` (downscales screenshots before they enter context), plus `checkpoint.sh` / `close-task.sh` in `~/.claude/bin` | Anyone, day one. Non-blocking, no failure mode |
| 2 | `--full` | `context-watch` (advisory cost meter), `work-boundary`, `precompact-guard` | People who have felt the pain. Noise before that |
| 3 | `--ceiling` | `context-ceiling` — **refuses tool calls** above a limit; the session goes write-only | A deliberate, informed choice. Never a default |

Tier 3 refuses Read/Grep/WebFetch/Agent and most Bash, and keeps Write/Edit/checkpoint/git open,
so the escape route is open by construction. Every hook also has an env-var escape that needs no
reinstall: `CLAUDE_CTX_WATCH=0`, `CLAUDE_CTX_CEILING=0`, `CLAUDE_PRECOMPACT_GUARD=0`,
`CLAUDE_WORK_BOUNDARY=0`. The uninstall line is printed on every run.

**Do not install tier 3 on someone else's machine.** Evidence: an earlier guard blocked a session
that had done everything right — handoff doc, scope status, 18 BRDs written — but had not used
`checkpoint.sh`, the one artifact the guard recognised. An expert user's reaction was *"I can't
even compact?"*. Two rules fell out of that, and they generalise to any guard:

1. A blocking guard must accept **evidence it did not itself create** — a recent commit, a
   recently modified doc — not only its own stamp file.
2. A guard must **never block the action that resolves it.** Blocking `/compact` when compaction
   is the remedy is perverse. Warn once, then let it through.

`init-project.sh` mentions this section and never installs global hooks silently.

**Hand someone the hooks without the numbers above and you get cargo cult** — they disable the
ceiling the first time it fires, because nobody told them what it was protecting them from. Lead
with the finding, not the install command.

---

## What's in here

```
mxcli-project-toolkit/
  CONVERSION-RUNBOOK.md         ← thin front door: how to start, entry modes
  toolkit-guide.html            ← visual onboarding page + shared CSS shell for stage HTMLs
  bin/
    init-project.sh             ← Stage P scaffold: intake.md, PROJECT.md, index.html (opens the guide)
    init-agents.sh              ← scaffold all five agent stubs into a project's .claude/agents/
    gate-check.sh               ← mechanical stage gates (P–7) + self-regenerating dashboard
    sync-project.sh             ← after toolkit git pull: refresh the artifacts copied into a project
    split-claude-md.sh          ← move MDL/lint reference out of CLAUDE.md into load-on-demand files
    install-claude-hooks.sh     ← tiered context-cost hooks → ~/.claude (see "Context cost" above)
    install-hooks.sh            ← unrelated: the git pre-commit client-data guard for THIS repo
  claude-hooks/                 ← sources for the above: hooks/ (5) + bin/ (checkpoint, close-task)
  agents/                       ← the five agent stub templates (ba/architect/mdl/gate/test)
  skills/
    conversion-runbook.md       ← [any project] The spine: stage matrix + interview protocol + entry modes + gates
    checkpoints/                ← CAC checkpoint scripts (scope/BRD/architecture/design/build/cutover)
    query-the-model.md          ← [any project] Query-before-ask source-of-truth ordering
    interview-protocol.md       ← [any project] How a question is put to the user: chat not files, options + recommendation, batch per gate, record the answer
    existing-app-assurance.md   ← [any project] Audit / regression-test an existing app — no pipeline
    agent-roles.md              ← [any project] Generate ba/architect/mdl/gate/test subagents with scoped tool rights
    bootstrap-project.md        ← [any project] Generate a new project's CLAUDE.md: Baseline routing + project-specific facts
    extractor-quality-loop.md   ← [migration] Scored quality loop for building/validating extractors
    ui-preflight-pages.md       ← [any project] Mandatory wireframe→tokens→StyleGallery cross-check before any page MDL
    learned-stylegallery.md     ← [any project] Turn ds.css into a live in-app StyleGallery module
    migration-pipeline.md       ← [migration] Full pipeline phase guide (XML → KB → BRD → MDL)
    source-triage.md            ← [migration] Gate before extraction: coverage check, reuse-vs-build-new call, bounded scope
    modularize-domain.md        ← [migration] Deciding Mendix module boundaries (Stage 3): criteria, sign-off, HTML rationale
    architecture-blueprint.md   ← [migration] Target-architecture blueprint: diagrams, module defs, wiring, fit-gap, marketplace, security, NFRs, integrations
    design-artifacts.md         ← [migration] UI/brand layer: versioned design system + annotated wireframes + branding interview
    brd-to-build-plan.md        ← [migration] Plan definition: BRD + architecture → dependency-ordered, numbered build plan
    module-brief.md             ← [any project] Per-module brief: ba-agent synthesizes BRD/wireframe/access into the mdl-agent's single entry point
    iterative-build-loop.md     ← [any project] Per-module build discipline: gate loop, coverage checklist, CE triage, Studio Pro handoffs
    ui-review-loop.md           ← [any project] Post-build functional+visual verification gate: render/nav/reuse/wireframe-divergence, graceful degradation, diagnostic-only
    brd-generation.md           ← [migration] BRD JSON prompt templates + validation checklist
    brd-validation.md           ← [migration] Validating BRDs against code + doc KB
    document-discovery.md       ← [migration] Scanning/classifying an unstructured document folder
    kb-generation.md            ← [migration] Document extraction (Excel/Word/PDF → KB markdown)
    source-os11.md              ← [migration] OutSystems 11 XML schema reference
    os-xml-schema.md            ← [migration] OS module XML structure details
    source-node-express-react.md ← [migration] Node/Express+React extraction layout + known gaps
    mdl-cookbook-microflows.md  ← [any project] MDL scripting patterns for microflows
    qa-loop-goal-pattern.md     ← [any project] Iterative /goal-driven pipeline validation technique
    e2e-harness-base.md         ← [any project] End-to-end test harness base
    assess-migration.md         ← [migration] Up-front migration assessment
    migrate-general.md          ← [migration] Source-agnostic migration guidance
    migrate-outsystems.md       ← [migration] OutSystems-specific migration guide
    learned-*.md                ← [any project] Validated learnings from live projects
  pipelines/                    ← Source-specific extraction tooling (code; node_modules gitignored)
    outsystems/                 ← OS XML → KB → BRD (extraction tooling; output is gitignored)
    java-angular/                ← Java + Angular/Spring Boot → KB → BRD
    node-express-react/          ← Node/Express + React → KB → BRD — regex-based, proven on one source shape only; read its README first
  bug-logs/
    mxcli-bugs.md               ← Known mxcli CLI bugs and workarounds (shared)
  process/
    process-learnings.md        ← Cross-project process improvements
```

`[any project]` vs `[migration]` above mirrors each skill's own `Applies to:` header line — greenfield mxcli builds only need the `[any project]` set, starting at Stage 5. The stage 1–4 skills (document discovery, KB/BRD generation and validation, modularization, architecture, design, build plan) also apply to **requirements-driven builds** with no legacy source — their headers say so explicitly.

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

<!-- Generated from bin/lib/skill-routing.tsv by bin/render-routing.sh.
     Do not hand-edit between the markers: add or change the ROW, then re-render. -->
<!-- ROUTING:BEGIN readme-situational -->
| Task | Skill to load |
|---|---|
| Deep, adaptive interview on one topic, on demand, when a checkpoint's 2+1 or a single question batch isn't enough | `skills/grill-mode.md` |
| Rendering a filled triage.md for review — the triage.html surface Stage 0 names. Renders only; the Stage 0 verdict stays with gate-check and the judgement with source-triage.md | `bin/triage-report.sh` |
| Generating a new project's CLAUDE.md — baseline routing plus project-specific facts | `skills/bootstrap-project.md` |
| Auditing or regression/e2e-testing an EXISTING app — no intake, no stages, no gates | `skills/existing-app-assurance.md` |
| Assessing or planning a migration up front, before any pipeline is chosen | `skills/assess-migration.md` |
| Running the extraction pipeline | `skills/migration-pipeline.md` |
| Migrating from a stack that has no dedicated pipeline | `skills/migrate-general.md` |
| Migrating an OutSystems app | `skills/migrate-outsystems.md` |
| Understanding OutSystems 11 source | `skills/source-os11.md` |
| Reading the OutSystems XML export schema | `skills/os-xml-schema.md` |
| Understanding Node/Express+React source, its layout assumptions and its gaps | `skills/source-node-express-react.md` |
| Scanning or classifying an unstructured document folder | `skills/document-discovery.md` |
| Validating an extractor's output before its BRDs are trusted | `skills/extractor-quality-loop.md` |
| Validating a new stack pipeline's extraction quality | `skills/qa-loop-goal-pattern.md` |
| Extracting Excel/Word/PDF specs into a knowledge base | `skills/kb-generation.md` |
| Writing or enriching a BRD JSON | `skills/brd-generation.md` |
| Validating BRDs against the code and document KB | `skills/brd-validation.md` |
| Diagramming target architecture — module defs, wiring, fit-gap, marketplace, security, NFRs, integrations | `skills/architecture-blueprint.md` |
| Deciding module boundaries before "create module" | `skills/modularize-domain.md` |
| Designing the brand and ONE ANNOTATED WIREFRAME PER SCREEN before building pages — the design system alone is half the deliverable | `skills/design-artifacts.md` |
| Turning BRDs plus architecture into a numbered, dependency-ordered build plan | `skills/brd-to-build-plan.md` |
| Building the Stage 4 coverage ledger — every requirement either claimed by a build-plan row or catalogued with a reason, never invisible | `skills/coverage-ledger.md` |
| Checking a coverage ledger against its BRD — every scalar leaf CLAIMED, LEDGERED, UNCLAIMED, PHANTOM or DOUBLE-CLAIMED, so coverage is measured rather than remembered | `bin/coverage-check.sh` |
| Building a module with mxcli — verified, iterative, coverage-checklist gated | `skills/iterative-build-loop.md` |
| Writing MDL microflow scripts — worked recipes | `skills/mdl-cookbook-microflows.md` |
| Building and auditing Mendix pages — widget patterns, datasource shapes | `skills/learned-page-patterns.md` |
| Generating a whole page tree in one script — the structure patterns that survive it | `skills/oneshot-page-structure-patterns.md` |
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
| Cutover and retrospective — promoting proven patterns back into the toolkit | `skills/close-the-loop.md` |
| Writing or reading docs/report.json — the append-only contract every instrument writes to and every renderer reads; open BEFORE building a new instrument or a second renderer | `skills/report-schema.md` |
| Installing, extending, debugging or porting the verification harness — which part owns what, which parts run standalone, and what a missing part must report | `skills/harness-architecture.md` |
| Before citing ANY behavioural claim about the harness, the Mendix runtime or a test tool as evidence — a claim not in the register may not be cited | `skills/measured-claims.md` |
| Checking whether the whole journey hangs together rather than each piece — finds correctly-built components nothing reaches, which per-element conformance and UI tests both miss | `skills/process-coherence-pass.md` |
| Turning an already-rigorous run into a narrated proof a stakeholder can trust without running anything | `skills/e2e-evidence-report.md` |
| Studio Pro will not load the project, or the .mpr looks gutted — recover before relaunching SP, never git checkout | `skills/mpr-corruption-and-sp-load-errors.md` |
| Running lint as a gate rather than a report — per-rule ratchet against a committed baseline, plus the crash and collapse guards that stop a blind rule passing | `project-bin/lint-gate.sh` |
| Reading a lint result, or writing/repairing any .star rule — lint's failure mode is a confident clean pass, so 0 findings is a claim needing evidence | `skills/lint-that-actually-runs.md` |
<!-- ROUTING:END -->

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
| Putting a question TO the user — any gate, any stage: ask in chat not in a file, two named options plus your recommendation, one batch per gate then end the turn | `skills/interview-protocol.md` |
| Setting up or completing a project's dev-process subagents — once, at project start, not "on demand" | `skills/agent-roles.md` |
| Deciding whether to extract at all, before any BRD gets generated | `skills/source-triage.md` |
| Taking in a new source — before generating anything from it. Grades what the source can support; nothing else in this toolkit reads a source | `bin/source-sufficiency.sh` |
| Deciding who answers a question — before putting any batch to the user. gap/conflict/choice is what keeps a gate batch at four questions instead of 127 | `bin/question-kinds.sh` |
| Writing BRDs, especially several in parallel — "build" before the fan-out, "check" before any BRD is called done | `bin/facts-lock.sh` |
| Building any module — before the first script. The mdl-agent's single per-module input | `skills/module-brief.md` |
| Writing ANY MDL script — before the first line. Step 0 picks the write mode, then the STOP table overrides it for corrupting operations | `skills/learned-mdl-preflight.md` |
| Placing any document in a module — before the first `create`. Feature group, then Pages/Microflows/Services/Resources; the path comes from the brief's folder plan, and the table says which types mxcli can actually place | `skills/module-folder-convention.md` |
| Writing or fixing any microflow — MDL gotchas plus annotation discipline | `skills/learned-microflow-patterns.md` |
| Building any page or snippet — before the first widget. Wireframe, tokens, gallery reuse, cross-check; no wireframe means STOP | `skills/ui-preflight-pages.md` |
| Building or using the in-app design gallery | `skills/learned-stylegallery.md` |
| Choosing CLI vs MCP+MDL vs hand-rolled MCP, or any MCP write session — three co-equal write modes, not CLI-only | `skills/learned-mcp-patterns.md` |
| Reviewing any module before calling it done — the ONE pass: build, gate, prove, LOOK (is it logical, does it look right, does it match our design, over every page not just the tested ones), confirm with the denominator stated | `skills/module-review.md` |
| Before calling any module tested — what testing a module means, and the false-green register of confirmed ways a test reports green over a broken feature | `skills/testing-shape.md` |
| Finishing any module — before calling it done. One command that runs every instrument and keeps "instrument faulted" apart from "feature failed"; in a wired project run the installed copy at bin/verify-module.sh | `project-bin/verify-module.sh` |
| A CE error or behavior that looks like a known mxcli quirk rather than a modeling mistake | `bug-logs/mxcli-bugs.md` |
| Any time an exit code, a tool's output or a subagent's report is about to become a stated finding — verify before you conclude | `skills/tool-output-is-not-ground-truth.md` |
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
