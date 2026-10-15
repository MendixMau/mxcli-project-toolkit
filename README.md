# mxcli-project-toolkit

> **Agents: this README is orientation, not the spec.** For any pipeline work, the executable authority is `skills/conversion-runbook.md` (stages, gates, interview protocol) plus each stage's owning skill — load those before producing anything. Stage summaries here and in `toolkit-guide.html` are routing, not deliverable lists.

## What it is

A shared process layer for building and changing **Mendix apps with an AI coding agent** and
[mxcli](https://github.com/mendixlabs/mxcli). You clone it once; each of your projects points at
it. It gives the agent a staged pipeline, a single place to record decisions, skills it loads
only when a task calls for them, and mechanical checks that report what is actually in your
project rather than what the agent believes is there.

It is for Mendix developers and leads who already use (or want to use) an agent such as Claude
Code to migrate a legacy app, build from requirements, or change a live app, and who want the
result to be reviewable: every decision written down, every stage gated, every rule backed by a
real incident.

## How it works

- **Stages and gates.** Work moves through the same stages for every project: kickoff (P),
  triage (0), analysis (1), requirements (2), architecture and design (3), build plan (4), build
  (5), test (6), and cutover (7, migrations only). Your entry mode decides which of them run
  (next section). Hard gates stop until you answer. Detail: `skills/conversion-runbook.md`.
- **One decision register.** Every gate question is asked in chat, and the answer lands in your
  project's `PROJECT.md` as `CONFIRMED` or `ASSUMED`. `ASSUMED` means you said "you decide", never
  that the question was skipped (`skills/interview-protocol.md`).
- **Skills on demand.** `skills/*.md` hold the method: how to triage a source, write a BRD, draw a
  module boundary, build a page, review a module. The agent loads a skill when its trigger
  happens, not all at once; the routing tables under [Reference](#reference) say which trigger
  loads which file. A small always-on set is kept under a word budget
  (`bin/render-routing.sh --check`).
- **Mechanical gates.** `bin/gate-check.sh <project> <stage>` checks the artifacts a stage owes,
  the per-module passes nobody may skip (LOOK, wiring sweep, journeys), and that every source
  file was used. It reports `PASS` / `PENDING` / `FAIL` / `WAIVED` / `MANUAL` and regenerates the
  project dashboard (`index.html`). `bin/status.sh` gives the one next action.
- **Instruments in your project.** `bin/init-project.sh` copies `project-bin/` into your project
  as `bin/`: `exec.sh` (every model write: snapshot, mxbuild gate, lint gate, restore on failure),
  `verify-module.sh`, `page-fidelity.js`, `lint-gate.sh` and the rest. `bin/sync-project.sh`
  keeps the copies you did not edit current.

```
P kickoff → 0 triage ✋ → 1 analysis → 2 requirements → 3 architecture & design ✋
          → 4 build plan ✋ → 5 build (module by module, gated) → 6 test → 7 cutover ✋
```

`✋` is a hard gate. Nothing before Stage 5 touches the model: a wrong module boundary is cheaper
to fix in a diagram than after 40 MDL scripts assume it. Each entry mode's walk, with the
commands that run at every step: `docs/pipeline-walks.html`.

## Ways to use it

Four pipeline entry modes share the same stages, plus one route with no pipeline at all. The
agent proposes the mode at kickoff with evidence and you confirm it; it is never silently
inferred (`skills/conversion-runbook.md` → "Entry Modes").

| Mode | Pick it when | Stages | Start from |
|---|---|---|---|
| **Migration** | Legacy source code exists (OutSystems, Java/Angular, Node/React, or another stack) | P, 0–7 | `bin/init-project.sh`, then `skills/conversion-runbook.md`; extractors in `pipelines/` |
| **Requirements-driven** | Specs, BRDs, workshop output or wireframes, no legacy code | P, 0–6 | `bin/init-project.sh`; document discovery replaces code extraction |
| **Greenfield** | Starting from a conversation or a plan you already have | P (light), 0 (scope), 5–6 | `bin/init-project.sh` |
| **Change an existing app** | A live `.mpr` you are adding to or altering, the rest stays | P, 0–6 per change | `bin/init-project.sh`, then `skills/existing-app-change.md` |
| **À la carte assurance** | Audit, lint, or put a regression/e2e net under an app you have, no pipeline | none | `skills/existing-app-assurance.md` |

## Quick start

```bash
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
~/Mendix/mxcli-project-toolkit/bin/doctor.sh                       # what is missing on this machine
~/Mendix/mxcli-project-toolkit/bin/init-project.sh <project-root>  # one command per project
```

1. **`doctor.sh`** names any missing prerequisite (bash, Python 3, sqlite3, line endings, mxcli,
   mxbuild) and exits non-zero if a stage would break. `doctor.sh --install <project>` fetches
   mxcli and mxbuild after showing the plan and asking. Windows and Linux: read
   [Platform support](#platform-support) first.
2. **`init-project.sh`** scaffolds the project folder: `intake.md`, `PROJECT.md`,
   `CLAUDE.local.md` (the wiring every session reads), the six agent stubs, `bin/` instruments
   and the `index.html` dashboard. It is idempotent and never overwrites. Optional on Claude
   Code: copy `commands/toolkit-init.md` to `~/.claude/commands/` and type `/toolkit-init` in any
   project instead.
3. **The visual guide.** `toolkit-guide.html` walks the whole journey in a browser. The scaffold
   opens it once per project; agents follow the first-touch rule in `CLAUDE.md`.
4. **Open your agent in the project folder and say where you are starting from**, for example:
   *"Start the toolkit pipeline. I have the legacy source in `source/`."* or *"I want to add an
   approval flow to this app."* The agent reads the runbook, proposes an entry mode and starts
   the kickoff interview. In later sessions, `bin/status.sh` is the first command.
5. **Upgrade** with `git -C ~/Mendix/mxcli-project-toolkit pull`, then
   `bin/sync-project.sh <project-root>` for each project. Skills update with the pull; sync
   refreshes what was copied into the project and prints the `Toolkit release:` you are on once
   release tags are published (from 1.0 on), or `none tagged yet` before that.

Everything a project produces lives inside its own folder; this clone stays clean
([Consuming this toolkit](#consuming-this-toolkit)).

## Make it yours

The toolkit is opinionated, and every opinion has a supported way to adjust it that survives
`git pull` + `sync-project.sh`. Use these instead of editing toolkit files in place, which is the
drift a fork gets.

| What you want | How | Where it lives |
|---|---|---|
| **House conventions, naming, lint rules, MDL snippets, approved components** for every project in your company | A private *company brain* repo: `bin/init-company-brain.sh <dir>` creates it from the template; `bin/init-project.sh <project> --company <dir>` (or `bin/wire-company-brain.sh`) wires a project to it. The public toolkit never cites it | `templates/company-brain/`, `skills/company-brain.md` |
| **Project-specific instructions** | Add your own sections to the project's `CLAUDE.local.md`. Sync rewrites only its generated blocks (baseline routing, session ritual) and keeps the rest | `<project>/CLAUDE.local.md` |
| **A lint rule tuned or off** | Rule options and `enabled: false` under `rules:` in the project's lint config; for a toolkit rule you never want installed, a line in `.claude/lint-rules-disabled.txt` with a `# reason:`. Either is your decision, recorded in `PROJECT.md`; never delete the `.star` file (sync reinstalls it) | `<project>/.claude/lint-config.yaml`, `lint-rules/README.md` |
| **Skip a stage or pass on purpose** | Record it instead of leaving it red: `bin/gate-check.sh <project> --adopt <stage> --reason "..."` for a project that joined mid-flight, `--waive <stage>` or `--waive look/<Module>` for one deliberate skip. Each lands as a register line | `PROJECT.md`; `skills/conversion-runbook.md` §2 |
| **Fewer questions, or more** | Interview mode `steering` (default: every consequential question is asked), `assist` (batched at gates, low-stakes ones assumed and reported) or `auto` (nothing blocks, every position recorded). Set an `Interview mode:` line in `PROJECT.md`, or `bin/interview-mode.sh <project> --set <mode>` (kept in `.claude/.interview-mode` until `--clear`); `$CLAUDE_INTERVIEW_MODE` overrides for one session | `skills/interview-protocol.md` |
| **No prompt before every model write** | `bin/exec-approval.sh` decides whether the agent asks before an exec; `bin/permission-profile.sh` (`wrappers` / `project` / `full`, picked at intake) decides what the harness allows without prompting | intake Q12; `bin/doctor.sh` shows the current profile |
| **Your own team roles** | The six agent stubs (ba, architect, mdl, gate, test, review) are yours to complete and edit; sync refreshes only stubs you never touched | `<project>/.claude/agents/`, `skills/agent-roles.md` |
| **A different agent** | Claude Code is the primary harness. `bin/wire-agents.sh` writes pointer files for Copilot, Cursor, Continue, Windsurf and Aider (and Kiro with `--with-kiro`) so every agent starts from the same wiring; `bin/install-harness-permissions.sh` sets each one's command allow-list where it has one | `toolkit-guide.html` → section 9 |
| **A source stack with no extractor** | Build one with the scored quality loop and copy a worked pipeline | `skills/extractor-quality-loop.md`, `pipelines/` |

If an opinion is wrong for everyone, not just you, change it upstream: see
[We need your input](#we-need-your-input).

## Testing and quality

**What the toolkit tests about itself.**

- `tests/run-tests.sh`: the guard scripts, each proven to fail on a case it must catch.
- `tests/wave2/`: about a hundred fixtures, one per instrument or bug, each taking its subject as
  an argument (read its `usage:` line); `tests/lint-rules/` covers every toolkit lint rule.
- CI (`.github/workflows/checks.yml`) runs on every PR: script parsing, routing render and word
  budget, portability, the client-data and private-citation guards, PR discipline, and both
  fixture suites.
- **Field proof before merge.** A new or changed instrument needs captured (never hand-written)
  input, both checkout layouts, both platforms and one cited run on a real project (`CLAUDE.md` →
  "Shipping an instrument").
- **Independent review.** Every PR is reviewed by someone who did not write it before it merges.
  Test tiers and the triage rubric: `docs/RELEASE-PROCESS.md` §2–§3.

**What it tests in your app.**

- **Gates:** `bin/gate-check.sh` per stage, plus the obligation, artifact and source-ledger checks.
- **Every model write:** `bin/exec.sh` snapshots, runs the mxbuild gate and the lint gate, and
  restores on failure.
- **Lint:** mxcli's built-in rules plus the toolkit's Starlark rules (`lint-rules/`), against a
  baseline so a rise is blamed on the script that caused it.
- **Pages:** `bin/check-page-shell.sh` and `bin/page-fidelity.js` score built pages against their
  wireframes; the LOOK pass opens every page.
- **Behaviour:** Playwright journeys plus OQL database assertions (`skills/testing-shape.md`,
  `skills/journey-proof.md`), and `bin/verify-module.sh` to run every instrument at module close.

## We need your input

Every rule in this toolkit traces to something that went wrong on a real project: a corrupted
model, a gate that went green over a broken feature, a question nobody asked. That is also its
limit. It knows the walls its users have hit so far, and it learns about yours only if you tell
it. Field feedback is how it improves.

Ways in, from least to most effort ([CONTRIBUTING.md](CONTRIBUTING.md) has the detail):

1. **Drop a file in `contrib/inbox/`** (copy `contrib/inbox/TEMPLATE.md`) and open a PR. No
   quality bar: a bug-log entry, a diff, three sentences, raw terminal output.
2. **Run `bin/harvest-learnings.sh <project-root>` at project wrap-up.** It drafts inbox files
   from your project's bug logs, decision-register promotions and locally patched toolkit
   scripts. Review them, then PR.
3. **Open a direct PR** into `skills/`, `bin/` or `bug-logs/`, held to the field-proof bar.
4. **Open a GitHub issue.** For a bug: the exact command, its verbatim output, and the
   `Toolkit release:` line `bin/sync-project.sh` prints. For an idea: the failure it would
   prevent.

**No client data**, anywhere: no client, partner or person names, codenames, internal hosts or
real paths. Genericize first; the leak guard runs in CI but cannot know your client.

Merged contributions get a `CHANGELOG.md` line crediting you or your project by name, and the
release notes name contributors too.

## Releases

Merged changes ship on a release train tagged `vYYYY.MM.DD` (the cycle is defined at the top of
`CHANGELOG.md`). Tags are published from 1.0 on; earlier dated CHANGELOG sections were never
pushed as tags. On top of the train, named milestones get curated notes: start
with [**1.0**](docs/releases/v1.0.md). What a milestone promises, major versus minor, deprecation,
and how to check, upgrade or pin the version a project uses: `docs/RELEASE-PROCESS.md` §8.

---

## Reference

The rest of this page is lookup material: platform notes, the stage-by-stage flow, write modes,
the skill routing tables and how projects consume the toolkit.

### Platform support

**Where does this run? Wherever you started the chat.** `doctor.sh` detects the lane — Claude
Code on the web (cloud container), a devcontainer, or your own machine with Studio Pro — and the
agent records it; nobody is asked. Every stage runs headless in all three; what each lane changes
is in `CONVERSION-RUNBOOK.md` → *Where you run this*. Do not assume "no Studio Pro = no build".

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

**This is about the shell you type in, not about Docker.** `mxcli new` writes a `.devcontainer/`
and VS Code then offers to "Reopen in Container" — **say no, work locally.** The container is a
second machine (no `claude` login, no dotfiles, a fragile install step), and the toolkit's path
is plain local use: `bin/init-project.sh` parks that folder under `.mxtk-backup/` so the prompt
stops. If you already clicked yes: F1 → "Dev Containers: Reopen Folder Locally", nothing is lost.
Real incident, 2026-10-08: a first-time user landed in the container with "claude: command not
found" and a fresh login prompt. The `devcontainer` lane in `CONVERSION-RUNBOOK.md` stays
supported for those who want it (`MXTK_KEEP_DEVCONTAINER=1`), it is just not the default.

**The lanes mix freely on one project.** Do the headless stages in the Dev Container, then open
the same `.mpr` in Studio Pro from Git Bash for the steps MDL cannot express and UI polish, and go back.
The only rule is one writer at a time: do not have the container building or writing the `.mpr`
while Studio Pro holds it open (`skills/handoff-to-studio-pro.md`).

![Where you run this: cloud, Dev Container and local + Studio Pro all work on one project folder, one git repo, one .mpr; Windows: Docker Desktop's WSL2 backend is fine, a WSL prompt as your shell next to Studio Pro is not; build headless, polish in Studio Pro, one writer at a time](docs/where-you-run-this.svg)

*Source: `toolkit-guide.html` → section 5, which also has the side-by-side table.*

**"Why a Dev Container instead of just working locally?"** The container is where the build is
*reproducible* — a colleague clones and gets the identical Java, Node and mxcli from
`.devcontainer/`, nothing to align by hand. Local is where the build is *visible* — Studio Pro
open, MCP live, UI polish with the app in front of you. Cloud is local's opposite: nothing
installed, a preview link for stakeholders, but ephemeral. Most projects use two of the three;
`toolkit-guide.html` → *Where you run this* has the side-by-side table.

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
> `bin/doctor.sh --install <project>` closes the gap without Studio Pro: it fetches a
> version-matched mxbuild that `exec.sh` then finds on its own.

**Existing clone from before 2026-08-18?** You predate `.gitattributes`, so if git checked the
scripts out with CRLF they will not run. Fix once:

```bash
cd ~/Mendix/mxcli-project-toolkit
git config core.autocrlf false && git rm --cached -r . && git reset --hard
bin/install-claude-hooks.sh --full     # re-install: the installed copies are the old ones
```

Then re-run `bin/sync-project.sh <project-root>` per project to refresh its copied scripts.

### How a migration flows through this toolkit

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

#### How `assess-migration` and the extraction pipeline complement each other

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

### Which tools do what — and when

#### Stage 5+: write modes

Once you have a reviewed build plan, the default way to write the `.mpr` is the **CLI** (`./bin/exec.sh script.mdl`, Studio Pro closed). On mxcli v0.24 it writes everything MDL can express — domain model, microflows (inline association sets included), pages (association-mode comboboxes and dropdown filters, cross-module datasources), access rules, security level and project settings, navigation, workflows. It is also the only mode that exists in a cloud container or devcontainer (no Studio Pro there — `CONVERSION-RUNBOOK.md` → *Where you run this*). You write a readable, version-controlled MDL script; `exec.sh` snapshots the model first, runs the mxbuild gate after, and restores on failure.

**Studio Pro by hand** covers only what MDL cannot express (`skills/learned-mdl-cannot-express.md`, and the STOP rows in `skills/learned-mdl-preflight.md`) — a human step, sequenced by the main session: save and close Studio Pro before the next CLI write.

#### Per-operation reference table

Use this before every write. Full per-rule detail (root causes, bug IDs, retest stamps) is in `skills/learned-mdl-preflight.md`.

| Operation | Mode | SP state |
|---|---|---|
| Entities, attributes, enumerations | CLI | Closed |
| Associations | CLI | Closed |
| Microflows (inline association sets included), pages, workflows | CLI | Closed |
| Access rules, module roles, demo users, navigation | CLI | Closed |
| `visible:`/`editable:` inside `datagrid customContent` columns (`learned-mdl-preflight.md` row 1) | Studio Pro by hand | **Open** |
| After any MPR corruption or load error | `bin/restore-mpr.sh` | Closed |

**The crash net.** An MPR is two parts: `Project.mpr` (SQLite index) and `mprcontents/` (BSON units). `bin/exec.sh` snapshots both before every batch; 5 rotate; `bin/restore-mpr.sh` rolls back both together (either alone is useless). Git commits at phase gates are the real history. Ad-hoc `.mpr.backup` copies are banned. By design, `exec.sh` refuses to run at all while the model has uncommitted changes — its snapshot would not cover them, so a later auto-restore could silently lose that work; commit the model first (`FORCE_EXEC=1` overrides, at your own risk).

#### Something went wrong? Don't panic.

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

### Context cost — read the finding before you install anything

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

#### The hooks, and why they are tiered

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

### What's in here

```
mxcli-project-toolkit/
  CONVERSION-RUNBOOK.md   ← thin front door: how to start, entry modes, where you run this
  toolkit-guide.html      ← visual onboarding page + shared CSS shell for stage HTMLs
  skills/                 ← the method: runbook, checkpoints/, stage skills, learned-*.md from live projects
  bin/                    ← toolkit-side tools: init/sync/doctor, gate-check, status, render-routing, guards
    lib/                  ← manifests: skill-routing.tsv, obligations.tsv, artifact-manifest.tsv, install manifest
  project-bin/            ← instruments copied into each project as bin/ (exec.sh, verify-module.sh, lint-gate.sh, …)
  project-tests/e2e/      ← journey runner and Playwright/OQL harness copied into each project
  agents/                 ← the six agent stub templates (ba/architect/mdl/gate/test/review)
  lint-rules/             ← toolkit Starlark lint rules + README (options, how to turn one off)
  pipelines/              ← source-specific extractors (OutSystems, Java/Angular, Node/React)
  templates/              ← templates/company-brain/ (private-tier template), manual-steps.md
  claude-hooks/           ← sources for the tiered context-cost hooks (see "Context cost")
  commands/               ← /toolkit-init slash command
  bug-logs/mxcli-bugs.md  ← known mxcli bugs and workarounds (look up with bin/bug-lookup.sh)
  contrib/inbox/          ← contribution drop (unreviewed, nothing loads it)
  process/                ← process learnings, roadmap, incident history
  docs/                   ← release process, release notes, pipeline walks
  tests/                  ← the toolkit's own fixtures (run-tests.sh, wave2/, lint-rules/)
```

Each skill's own `Applies to:` header says whether it is for any project or migrations only;
the routing tables below say when each one loads.

---

### Division of labor: this toolkit vs bundled mxcli skills

Every mxcli project has a `.ai-context/skills/` directory (bundled by `mxcli init`, refreshed with each release) containing syntax references, widget patterns, CRUD templates, and how-to guides. **This toolkit does not duplicate those.** The two sets are complementary:

| Layer | Owned by | Contents | Updated by |
|---|---|---|---|
| `.ai-context/skills/` | mxcli (bundled) | MDL syntax, widget patterns, CRUD/data-processing templates, integration guides | `mxcli` release |
| `mxcli-project-toolkit/skills/` | This repo | Conversion runbook, migration pipeline, build discipline, agent roles, STOP rules from real corruption incidents | You (via `git pull`) |

**When the two disagree, this toolkit's STOP rules take precedence** — until explicitly retested and the result stamped in `bug-logs/mxcli-bugs.md`. The bundled skills may teach patterns that were unsafe on older mxcli versions; the bug log's `Retested on vX.Y.Z` field is the authoritative reconciliation record. References to bundled skills in this toolkit's docs are marked with "(bundled)".

---

### When to use which skill

<!-- Generated from bin/lib/skill-routing.tsv by bin/render-routing.sh.
     Do not hand-edit between the markers: add or change the ROW, then re-render. -->
<!-- ROUTING:BEGIN readme-situational -->

**Spine — what am I doing, who decides, how do I ask**

| Task | Skill to load |
|---|---|
| Applying or proving a change request (CR row), a change whose class, size or status is unclear, or a "Change log:" gate line to explain: full class/size/ask tables, the wrong-vs-right example, apply and prove steps, the owners table and what the warn-only gate check counts | `skills/change-intake-detail.md` |
| Deep, adaptive interview on one topic, on demand, when a checkpoint's 2+1 or a single question batch isn't enough | `skills/grill-mode.md` |
| CAC-1, closing Stage 0 in EVERY entry mode — scope IN: full scope or a slice, and in what order. Opens with a brainstorm, not options | `skills/checkpoints/checkpoint-scope.md` |
| CAC-1b, after Stage 1 — scope OUT: is what extraction produced what you meant. No gate stops you; run it late against the BRDs if it was skipped | `skills/checkpoints/checkpoint-extraction.md` |
| CAC-2, after BRD scaffolding and before enrichment — capability grouping and enrichment order | `skills/checkpoints/checkpoint-brd.md` |
| CAC-3, after BRD validation and before architecture locks — the hidden business rules that are expensive to discover later | `skills/checkpoints/checkpoint-architecture.md` |
| CAC-4, after rearchitect sign-off and before any design artifact — branding and UI direction. Opens with a brainstorm | `skills/checkpoints/checkpoint-design.md` |
| CAC-5, after design sign-off and before the build plan — build order and slice boundaries. Opens with a brainstorm | `skills/checkpoints/checkpoint-build.md` |
| CAC-6, after Stage 6 passes and before any cutover step — migration mode only, and a hard gate: every answer lands CONFIRMED, no ASSUMED defaults | `skills/checkpoints/checkpoint-cutover.md` |
| Stage 0 sign-off when the inventory is at or under 1 module / 8 screens / 25 use cases, or the user says the app is small — declare the tier, then apply its per-stage caps and the three artifact waivers | `skills/small-project-tier.md` |
| Generating a new project's CLAUDE.md — baseline routing plus project-specific facts | `skills/bootstrap-project.md` |
| Setting up or resuming an mxcli project in a cloud/ephemeral container — the one-time setup order (mxcli download → mxcli init → init-project.sh → sources decision → push) and the commit-and-push loop that survives container reclaim | `skills/cloud-dev-environment.md` |
| Changing an EXISTING Mendix app — adding a feature, altering a flow, restructuring a module — when it has no BRDs, no architecture doc and no wireframes: the knowledge base comes from the live model (Path D), stages 2–4 run over what changes plus what it touches, nothing more, and the Track B regression baseline is the precondition; audit-only stays in existing-app-assurance | `skills/existing-app-change.md` |
| Setting up or wiring a COMPANY BRAIN — the private tier between the toolkit and a project for own skills, conventions, lint rules, MDL snippets and approved MPKs; and deciding whether something goes to the toolkit, the company brain or docs/brain/ | `skills/company-brain.md` |
| Cutover and retrospective — promoting proven patterns back into the toolkit | `skills/close-the-loop.md` |
| Before citing ANY behavioural claim about the harness, the Mendix runtime or a test tool as evidence, or counting tokens from transcripts — a claim not in the register may not be cited | `skills/measured-claims.md` |
| Any review pass that runs more than once — module-review, coherence, monkey, wiring-sweep: findings accumulate across runs, a per-run report cannot show a trend | `skills/improvement-register.md` |

**Source — reading a legacy system (migration entry mode)**

| Task | Skill to load |
|---|---|
| Images to read listed by images-to-md or the documents index — describe each unique picture once, into its own file, before Stage 2 closes | `skills/image-transcription.md` |
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
| Collecting the facts an app dossier is written from: forces a full catalog build, module edges through the real module column, strongly connected components, describes every loop-containing microflow and parses the loop bodies; exit 2 on a stale, fast-mode or schema-incomplete catalog, never a verdict | `project-bin/app-facts.sh` |
| Building or refreshing the standing dossier of an EXISTING app before changing it: inventory, module dependency shape, loop risk patterns, each section with a verdict and a fault where nothing was measured (a standing document; nothing else in the toolkit reads it yet) | `skills/app-analysis.md` |
| Checking whether an EXISTING app's module boundaries still hold: the layer map (bin/app-layer-map.sh) computes the order the modules would stack in and draws only the edges that point back up, so one tangle of N mutually reachable modules becomes a named list of edges with a weight and a ref kind; Stage 3 in existing-app-change mode, and the honest blast radius for a slice | `skills/layering-review.md` |
| Judging module tangles, bidirectional pairs, cohesion and hubs from analysis/app-facts/dependencies.json; stock graph_module_* views split names on the first dot and are not trusted | `skills/module-dependency-review.md` |
| Diagramming target architecture — module defs, wiring, fit-gap, marketplace, security, NFRs, integrations | `skills/architecture-blueprint.md` |
| Deciding module boundaries before "create module" | `skills/modularize-domain.md` |

**Design — how it looks, before any MDL**

| Task | Skill to load |
|---|---|
| Building or using the in-app design gallery | `skills/learned-stylegallery.md` |
| Before porting ds.css into SCSS, and at the Stage-3 gate — greps the stylesheet for rules that cannot match the HTML Mendix emits (rem against the real root, table/th/td selectors, positional row selectors). mx check, mxcli check and mxcli lint are all blind to CSS | `project-bin/check-design-portability.sh` |
| After every wireframe edit: assembles design/wireframes/*.html into design/prototype.html, one hash-routed page a stakeholder can click through instead of twenty separate files. Generated, never edited (design-artifacts.md Step 3) | `project-bin/assemble-prototype.js` |
| Before wireframes pass to the build loop, and with --brd before a BRD is signed off: dead #/route links, orphan screens, controls with no data-bind and no data-cut, BRD routes no screen has, screens no use case walks (design-artifacts.md Step 3c, brd-validation.md check 8) | `project-bin/check-prototype-links.js` |
| Designing the brand and ONE ANNOTATED WIREFRAME PER SCREEN before building pages — the design system alone is half the deliverable | `skills/design-artifacts.md` |
| Stage 3, after the role model is CONFIRMED and BEFORE THE FIRST WIREFRAME — and any time a page shows ONE object, a menu item or home page is added, or a data source retrieves the current/first record: role homes, inboxes, and per page how it is reached and which object it takes as parameter | `skills/interaction-model.md` |
| Before a wireframe or a design commits to a WIDGET, when a requirement shows a widget to one role and not another, and when a page script hits a parse error that looks like a syntax mistake: the short list of things MDL cannot write at all, and the four-minute probe that answers it at Stage 3 instead of at build time | `skills/learned-mdl-cannot-express.md` |

**Build — the loop itself**

| Task | Skill to load |
|---|---|
| Dispatching a build step to a helper — generate its one-file pack (the brief's Build steps row, mxcli brain brief, live DESCRIBEs, example, folder) and hand over the path instead of a reading list. Measured: 25-38% fewer tool calls and 30-41% less time, same quality; the token saving is not proven | `project-bin/context-pack.sh` |
| An exec.sh guard refused a write (not a permission prompt), or building a module with mxcli — verified, iterative, coverage-checklist gated; on a refusal: commit, wait or stop, never FORCE_EXEC | `skills/iterative-build-loop.md` |
| After marking a module done, or any time "how much is built vs proven" is asked — renders build-plan.html from done- prefixes and verify-module.sh/improvement-register.md, kept as two honestly separate views; --json writes architecture/build-plan.json parsed from build-plan.md's Phase headings (a plan with no Phase headings gets no file) | `project-bin/build-plan-status.sh` |
| Turning a client-derived Mendix app into a clean, shareable demo with zero client fingerprint — branding, data, custom widgets | `skills/anonymize-client-app-for-demo.md` |
| Handing a headless-built model to a person — opening it in Studio Pro, a free sandbox, or a colleague's machine: the model travels, the demo data and runtime config (keys, an agent's bound model) do not, and each needs its own re-establish step | `skills/handoff-to-studio-pro.md` |
| Stage 5 start, before the first module of any entry mode — one entity, flow, page, nav, demo user, journey and screenshot proven in the running app, so build/run/look/test are known to work before a module depends on them | `skills/walking-skeleton.md` |
| At project birth (before the first build script) and any time a model needs a platform home: creating the Team Server app, adopting an existing GitHub-born model into it without rewriting history, or deploying; also when the Platform SDK returns 403, git rejects the PAT, a deploy cannot be triggered from a PAT, or the app turns out to be a Free App | `skills/platform-link.md` |
| Promoting an app to a deployed sandbox or cloud node, or before a customer tests a deployment — "it works locally" is not evidence about a deployment; also when a test suite fails only against the remote URL | `skills/deploy-to-sandbox.md` |

**Build · MDL — the language and tool reference**

| Task | Skill to load |
|---|---|
| Reading what loop bodies do (LOOP_TQ, deferred commit, nested loop, REST in loop, transaction control per item, scheduled-event reachability) from described MDL; the catalog holds top-level activities only and cannot see inside a loop | `skills/microflow-loop-antipatterns.md` |
| Writing MDL microflow scripts — worked recipes | `skills/mdl-cookbook-microflows.md` |
| Writing a single MDL script that takes a project from nothing to a working vertical slice — execution order, why it is deliberately non-idempotent, the instrument hierarchy, and the silent failures that pass every check | `skills/build/mdl/oneshot-mdl-method.md` |
| Writing a popup page's microflow with a retry/validation-failure branch that re-shows the same popup — missing close page stacks duplicate dialogs | `skills/learned-popup-navigation.md` |
| Writing MDL for a datagrid column with ShowContentAs customContent that needs to display a bound value | `skills/learned-datagrid-customcontent-binding.md` |
| Writing ANY microflow behind a button that commits, completes a workflow task, or triggers a backend flow — popup or full page: it owes the user a message, a close, and a control that stops offering the action once done | `skills/learned-popup-feedback-pattern.md` |

**Build · Pages — page-building patterns**

| Task | Skill to load |
|---|---|
| Building and auditing Mendix pages, or starting a UI fix round across many pages — widget patterns, datasource shapes; for a round: SCSS first, four regressions to check | `skills/learned-page-patterns.md` |
| Generating a whole page tree in one script — the structure patterns that survive it | `skills/oneshot-page-structure-patterns.md` |
| Building or auditing a collapsible sidebar nav — Atlas Core's collapsed state needs icons assigned per menu item or it silently clips label text | `skills/learned-sidebar-collapse-icons.md` |
| Building or altering any data grid — native DATAGRID vs pluggable DG2 decision rule, the ALTER PAGE INSERT corruption, sort-by and filter-binding traps | `skills/learned-dg2-patterns.md` |
| Putting any file upload / attachment / document field on a page, an uploader page failing mx check with CE0463, or an uploader DESCRIBE that will not re-execute — the File Uploader MDL shape proven end to end on v0.23 and v0.24, the widgets mxcli cannot author, and the upload instrument | `skills/learned-file-upload-widget.md` |

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
| Designing or reviewing a Workflow's SHAPE before or after the MDL — where a path may end, boundary event vs event sub-process, parallel-split limits, outcome minimums, targeting from the sentence, multi-user decision methods, which edits break running instances; and any CE6689/CE1844/CE1845/MW0012 after a clean mxcli check | `skills/workflow-structure-rules.md` |

**Build · Integration**

| Task | Skill to load |
|---|---|
| Building a REST integration (consumed or published) for the first time on a project — the checks that avoid a rebuild after the first live call | `skills/rest-integration-first-time-right.md` |
| Adding a constant, installing a marketplace module, deploying to a new environment, or needing a Mendix PAT — where an encryption key, API credential, endpoint or access token gets its value, why a free node has only one channel, and why a token missing from the files you grepped is not missing | `skills/learned-constants-and-secrets.md` |

**Verify — does it work**

| Task | Skill to load |
|---|---|
| Auditing or regression/e2e-testing an EXISTING app — no intake, no stages, no gates | `skills/existing-app-assurance.md` |
| Running the ledger rung alone — recompute every stored ledger status against the live model and catch the STALE rows that claim built for something the model no longer has | `project-bin/conformance-check.sh` |
| Running the wiring rung alone — a module imported but never reached, an element built but wired to nothing, a boundary crossed; mxbuild and e2e are blind to all three | `project-bin/graph-sweep.sh` |
| Before any runtime test — brings the stack up unattended and PROVES the thing that answered is this project's app; --check makes it report-only | `project-bin/test-stack-up.sh` |
| Standing up or extending the Playwright e2e harness | `skills/e2e-harness-base.md` |
| Writing DB assertion tests that cross-check UI state against the database | `skills/learned-db-assertions.md` |
| Seed data, test data, demo data or fixtures are needed, or pages come up empty — BEFORE a journey run. Explore the data structure, choose rows by use case, scan for reset/delete actions, derive and measure with project-bin/fixture-manifest.sh, interview only the residue, never seed from inside the harness | `skills/fixture-seeding.md` |
| Proving a module's user journey end-to-end — the deep form of step 3 PROVE; use whenever an instrument reports green and you cannot say what would have made it red | `skills/journey-proof.md` |
| Writing or running e2e cases beyond the happy journeys (blank/whitespace required fields, over-length, duplicates, cancel, double submit, wrong state, wrong role, backend down, stale write, empty search) — every case cites a requirement first, UNSPECIFIED is re-scored against house rules, GAP counts carry the denominator; runs after journey-proof and before monkey-test | `skills/unhappy-path-testing.md` |
| Running the fuzz/crash net on a module whose journeys are already green — and reading the result, which is NOT evidence the module works | `skills/monkey-test.md` |
| UX audit and screenshot-loop discipline | `skills/learned-skill-ux-audit.md` |
| Tracking scope delta between the BRD and the built state | `skills/learned-skill-scope-delta.md` |
| Writing or reading docs/report.json — the append-only contract every instrument writes to and every renderer reads; open BEFORE building a new instrument or a second renderer | `skills/report-schema.md` |
| Installing, extending, debugging or porting the verification harness — which part owns what, which parts run standalone, and what a missing part must report | `skills/harness-architecture.md` |
| Checking whether the whole journey hangs together rather than each piece — finds correctly-built components nothing reaches, which per-element conformance and UI tests both miss | `skills/process-coherence-pass.md` |
| After every module's CONFIRM stage — counts proven modules since the last cluster/full coherence pass and exits DUE once the threshold is reached, so the cadence isn't left to memory | `project-bin/coherence-cadence.sh` |
| Turning an already-rigorous run into a narrated proof a stakeholder can trust without running anything | `skills/e2e-evidence-report.md` |
| Recording a narrated screen-capture demo of a running app for a human to watch — opening on the app instead of a blank frame, and keeping captions synced to the pixels | `skills/record-demo-video.md` |
| Sending a demo guide, screenshots or a quickstart doc OUTSIDE the repo — to a customer, prospect or reviewer: relative image paths and "the name shown above" both break the moment the file travels alone, and the usernames a login panel displays are not the ones it accepts | `skills/share-demo-package.md` |
| Running lint as a gate rather than a report — per-rule ratchet against a committed baseline, plus the crash and collapse guards that stop a blind rule passing | `project-bin/lint-gate.sh` |
| Reading a lint result, or writing/repairing any .star rule — lint's failure mode is a confident clean pass, so 0 findings is a claim needing evidence | `skills/lint-that-actually-runs.md` |
| Every module before it is called done — does every clickable thing actually do something; run AFTER the happy-path journey is green, never before | `skills/wiring-sweep.md` |
| The user asks for a full end-to-end test, a click-through proof, or does-everything-actually-work — or you are unsure which harness skill applies; this one routes you | `skills/full-harness-audit.md` |
| End of any build+test cycle that wrote docs/report.json — did the testing itself hold up, not just get filed; one level up from finding-disposition | `skills/test-result-audit.md` |
| Any report from a test/review run is about to be published — no report ends without a disposition for every finding | `skills/finding-disposition.md` |
| Exposing a container-run app at a public URL (mxcli run --hub) — demo/stakeholder preview: the db-name default trap, the runtime REST client ignoring JVM proxy settings (GenAI 403 "Host not in allowlist" that is really a proxy bypass), and stale-app detection | `skills/preview-over-hub-tunnel.md` |
| Starting a hub-tunnelled preview with the flags outbound calls actually need — wraps mxcli run --hub with db-name and the runtime proxy settings from preview-over-hub-tunnel.md | `bin/run-hub.sh` |
| Before any first deploy to a new environment, and after installing or updating any marketplace module — which constants would be blank where nobody can set them, and which now carry a secret in the model. Never prints a value | `project-bin/constants-audit.sh` |

**Diagnose — something is broken and it may be the tooling**

| Task | Skill to load |
|---|---|
| Reading a whole class of tool defects (a retest, a new mxcli release, an audit) — for one CE code or symptom use bin/bug-lookup.sh instead; the ledger is 32k words | `bug-logs/mxcli-bugs.md` |
| An e2e rung reports a UI defect (widget never appeared, click did nothing, screen contradicts the data, fixture count wrong) — check the locator before blaming the app: :visible, click order, poll, derived fixtures | `skills/e2e-locators-that-lie.md` |
| Any refused, denied or blocked command — BEFORE rewriting a permission rule and before telling the user a tool is blocked. A rule matches the START of the command line, so an allowlisted tool prefixed with cd matches nothing | `skills/agent-permission-friction.md` |
| Studio Pro will not load the project, or the .mpr looks gutted — recover before relaunching SP, never git checkout | `skills/mpr-corruption-and-sp-load-errors.md` |
| Preparing an mxcli/Studio Pro bug for submission — scope pinning, read-back-vs-write-path verification, gate-sensitivity negative controls, severity scoping, before it's called filable | `skills/bug-submission-checklist.md` |
| About to open an issue, PR or discussion against mxcli or the toolkit — before drafting, choosing which repo and vehicle it belongs to | `skills/upstream-feedback.md` |
| A page/grid/combobox renders empty (blank cells, zero rows, zero options) during UI review or an e2e run — before assuming a single cause | `skills/empty-widget-triage.md` |
| doctor.sh reports FAIL or WARN, or someone asks whether a red setup line blocks them — check what is actually on the machine before naming a fix; a wrong-arch binary, a missing one and a broken self-check all read the same | `skills/doctor-triage.md` |
| Suspecting an mxcli/mxbuild tool defect and deciding whether to swap a binary — proving it's version-specific without risking the real model | `skills/sandbox-ab-tool-defect-probe.md` |
| Restarting Studio Pro on macOS — the reopen bug, the port bug, and detecting a real hang vs a slow load | `skills/restart-sp-reopen-and-hang-detection.md` |
| Driving the whole toolkit pipeline on a real source to find what the written skills don't say — the toolkit is the subject, not the app it builds | `skills/field-run.md` |
| Needing Studio Pro load evidence without a human at the GUI — direct-binary launch and log capture; a capture technique, NOT a validated pass/fail oracle | `skills/scriptable-sp-verification.md` |
| A runtime test reads/writes data that then is not there, or vice versa — three local Postgres instances can answer on this box; resolve the real port from the project's own compose file first | `skills/learned-local-db-confusion.md` |
| gate-check.sh reports a Stage 0 file not found that plainly exists — ANALYSIS_BASE falls back to project root until Stage 1; move the file, do not debug the script | `skills/gate-check-file-locations.md` |

**Reference — lookup tables, not method**

| Task | Skill to load |
|---|---|
| Asked "is there a Mendix best practice for this", or mapping a lint rule that rose in the ratchet back to the practice and the skill that prevents it — one row per area: Mendix docs page, bundled assess-quality section, toolkit skill before the write, lint rule after exec | `skills/mendix-best-practices-index.md` |
| Working with the Mendix Epics board programmatically — creating/reading stories and epics, updating workflow state, or integrating BRDs with the portal | `skills/mendix-epics-api.md` |
<!-- ROUTING:END -->

---

### How to add a new skill

1. Create a new `.md` file in `skills/` with this header:
   ```markdown
   # Skill Name — Purpose
   **Applies to:** migration | any mxcli project
   **Purpose:** one-line description
   **Source:** which project or session this came from
   ```
2. Structure it as a step-by-step guide with prompt templates where applicable
3. Add its routing row to `bin/lib/skill-routing.tsv` and run `LC_ALL=C bin/render-routing.sh` — the tables in this README are generated from it, never hand-edited
4. **If it applies on every MDL-writing session regardless of task**, mark its row baseline so it lands in "Baseline routing" below; the always-on tier has a word budget that `render-routing.sh --check` enforces. Authoring rules for behaviour-shaping skills: `CLAUDE.md` → "Adding new skills"
5. Commit and push — available to all projects on next `git pull`

---

### Consuming this toolkit

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

**Reference model (default):** clone once, point projects at it — no copies, no drift.
```
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
```
Each project's `CLAUDE.local.md` references `~/Mendix/mxcli-project-toolkit`. Pull updates with `git pull` — **everything referenced (skills, runbook, checkpoints, gate-check) updates instantly for all projects.** The artifacts that were *copied* into a project (intake.md, agent stubs, and — only on a project with no `CLAUDE.local.md` — the baseline-routing table in its `CLAUDE.md`) don't: run `bin/sync-project.sh <project-root>` after a pull — it appends new intake questions, refreshes untouched agent stubs (never completed ones), refreshes the Baseline and situational tables in `CLAUDE.local.md` when one exists, and otherwise flags a stale baseline routing table in `CLAUDE.md` for hand update. It also warns (never fetches) when the toolkit clone itself is off `master` or behind `origin/master`; `MXTK_SYNC_SKIP_CLONE_CHECK=1` skips that one check, for the toolkit's own test suite only — real users leave it unset. Then tell any already-running session to re-read the runbook.
For a self-contained handoff, add it as a git submodule instead. Per pipeline, run `npm install` inside `pipelines/<x>/pipeline` (node_modules is gitignored).

Company-specific material goes to a private company brain, never into this repo: [Make it yours](#make-it-yours).

#### Baseline routing — every consuming project needs this table

The "When to use which skill" table above is *situational* — load a skill when a specific task calls for it. A few skills apply on **every** MDL-writing session regardless of task, and situational discovery quietly misses them, because nothing mid-task prompts loading them. Every consuming project needs this table somewhere an agent reads it before writing MDL — but "somewhere" is not "copy it into `CLAUDE.md`": a project scaffolded with `bin/init-project.sh` already has it in `CLAUDE.local.md`, refreshed by every `bin/sync-project.sh` run, and `CLAUDE.md` there should carry only a short pointer to it (`skills/bootstrap-project.md` Step 2 has the exact block). Paste the table itself into `CLAUDE.md` only on a project with no `CLAUDE.local.md` convention (a non-Claude harness, or one bootstrapped before `init-project.sh` existed):

<!-- Generated from bin/lib/skill-routing.tsv by bin/render-routing.sh.
     Do not hand-edit between the markers: add or change the ROW, then re-render. -->
<!-- ROUTING:BEGIN readme-baseline -->
Each row is a trigger, not a reading list: open a row's file when the first column happens in this session, and only rows whose Stage(s) cell says *every stage* or names the stage the register (PROJECT.md) says you are in. Do not read the table ahead — a build session that only writes pages never opens the microflow rows.

Then filter by Role(s). A helper dispatched with a role stub (ba, architect, mdl, gate, test, review) reads only rows that say *every role* or name its role — its stub lists the same files, and it never opens another role's rows. The main session is **lead**: *every role* and lead rows, plus the rows of any role whose work it does itself instead of dispatching.

| Always relevant for | Reference this | Stage(s) | Role(s) |
|---|---|---|---|
| Before writing any .js or .sh for a check, gate or report — and before adding a rule to an existing one: judgement goes in a skill, code only fetches facts a reader cannot | `skills/skills-over-scripts.md` | every stage | every role except mdl, review (on demand for those) |
| Any pass whose input is missing, stale or unresolvable — before recording UNMEASURED, N/A or a silent skip: name what was missing, say what you assessed against instead, still deliver a verdict | `skills/degrade-to-judgement.md` | every stage | every role |
| Any time an exit code, a tool's output or a subagent's report is about to become a stated finding — verify before you conclude | `skills/tool-output-is-not-ground-truth.md` | every stage | every role |
| Before obeying any learned-* STOP or workaround that costs a detour — probe the binary you actually have, then stamp the verdict back into the rule | `skills/retesting-learned-rules.md` | every stage | every role |
| Any pipeline work at all — every session, before producing any stage artifact: read §1b plus your own stage's section, not the whole file (gate-check.sh prints the line spans); READMEs and the guide are orientation only | `skills/conversion-runbook.md` | P,0,1,2,3,4,5,6,7 | lead, ba, architect |
| Any pipeline work at all, as a helper — every dispatch, before producing anything: run the toolkit's bin/runbook-slice.sh <stage>, which prints §1b plus your stage's section of the conversion runbook; never open skills/conversion-runbook.md whole | `bin/runbook-slice.sh` | P,0,1,2,3,4,5,6,7 | mdl, gate, test, review |
| Any question before asking the user or writing anything — query the model, then read the source, then ask the human, in that order | `skills/query-the-model.md` | P,0,1,2,3,4,5,6,7 | every role |
| Putting a question TO the user — any gate, any stage: ask in chat not in a file, two named options plus your recommendation, one batch per gate then end the turn | `skills/interview-protocol.md` | P,0,1,2,3,4,5,6,7 | lead, ba, architect |
| The user gives feedback or asks for a change mid-project — "change X", "it also needs Y", a remark on a screenshot or the running app, a stakeholder's ask relayed in chat: log a CR row in PROJECT.md ## Change log BEFORE any edit, size it, then edit the highest artifact it alters (BRD, decision, architecture, wireframe), never the MDL first | `skills/change-intake.md` | 2,3,4,5,6,7 | lead, ba |
| Any stage transition — the 2+1 format every CAC uses, and the one-register rule (answers land in PROJECT.md, never in a separate state file). The seven CACs themselves are routed per stage in the situational table | `skills/checkpoints/checkpoint-template.md` | 0,1,2,3,4,6,7 | lead, ba, architect |
| Setting up or completing a project's dev-process subagents — once, at project start, not "on demand" | `skills/agent-roles.md` | P,4,5 | lead |
| Starting a subagent, sending it a fix round, or reading an agent-stop notice — name the model, fresh not fork, fresh fixer not resume, coalesce notices | `skills/dispatching.md` | P,1,2,3,4,5,6 | lead |
| Deciding whether to extract at all, before any BRD gets generated | `skills/source-triage.md` | 0 | ba |
| Taking in a new source — before generating anything from it. Grades what the source can support; nothing else in this toolkit reads a source | `bin/source-sufficiency.sh` | 0,1 | ba |
| Closing Stage 1, or adding files to a source folder — every inventoried file must name the artifact that consumed it (text AND embedded diagrams), or carry a waiver; blocks Stages 1–2 until it does | `bin/source-ledger.sh` | 0,1,2 | ba |
| HTML in the source corpus — convert once before anyone reads it: `bin/html-to-md.sh <project>` writes each page as Markdown under analysis/knowledge-base/text/ (3–10× fewer tokens than the raw export; inline images decoded to files; section list with line numbers as the read's denominator) plus documents-index.md over EVERY file, which one ledger glob mark points at. A session that opens a .html itself has skipped this | `bin/html-to-md.sh` | 0,1 | ba |
| Pictures in the source corpus — decks, Word files, PDFs, screenshots: one worklist of unique images with context, one description file each, coverage checked | `bin/images-to-md.sh` | 0,1,2 | ba |
| Deciding who answers a question — before putting any batch to the user. gap/conflict/choice/user-only is what keeps a gate batch at four questions instead of 127 | `bin/question-kinds.sh` | 1,2,3 | ba |
| Writing BRDs, especially several in parallel — "build" before the fan-out, "check" before any BRD is called done | `bin/facts-lock.sh` | 2 | ba |
| Building any module — before the first script. The mdl-agent's single per-module input | `skills/module-brief.md` | 4,5 | ba, mdl |
| Writing ANY MDL script — before the first line. Step 0 picks the write mode, then the STOP table overrides it for corrupting operations | `skills/learned-mdl-preflight.md` | 5 | mdl |
| Placing any document in a module — before the first `create`. Feature group, then Pages/Microflows/Services/Resources; the path comes from the brief's folder plan, and the table says which types mxcli can actually place | `skills/module-folder-convention.md` | 4,5 | architect, mdl |
| Writing or fixing any microflow — MDL gotchas plus annotation discipline | `skills/learned-microflow-patterns.md` | 5 | mdl |
| Writing a microflow with any loop, a retrieve/commit/call inside a loop, nested or multiple loops, >20 activities counting loop bodies, or a list built from a list — post the checklist before the first MDL line | `skills/microflow-preflight.md` | 5 | mdl |
| Building any page or snippet — before the first widget. Wireframe, tokens, gallery reuse, cross-check; no wireframe means STOP | `skills/ui-preflight-pages.md` | 5 | mdl |
| Writing or reviewing any page or snippet — the spacing scale (8/16/24/32/48), section rhythm, and the page-header scaffold every full page starts with; sections at 0px apart and pages with no H1 are the defects it retires | `skills/design-spacing.md` | 5 | mdl, review |
| After every page-building script, and any time the UI looks wrong — the cheap repeatable look during the build: one page, one screenshot, four questions, scored when a wireframe exists. Feeds Gate: UI, never replaces it | `skills/ui-loop.md` | 5 | review (mdl: on demand) |
| After the FIRST build that follows any design-system port, and before any page is built on it — reads the BUILT stylesheet and reports how many framework knobs point at a design token, how many tokens arrived, how many component classes arrived, each with its denominator. Measured on a real run: 55 tokens ported correctly into the right file, 0 of 35 knobs bound and 0 of 20 classes present, two build phases shipped in the framework's default blue with mx check, mxcli lint, the MDL suite and two e2e journeys all green | `project-bin/check-design-reaches-app.sh` | 3,5 | architect, mdl, gate, review |
| Before exec'ing ANY page script — compares the drafted MDL's shell against the wireframe's: page column, layout/nav shell, one H1. Measured 0/10 pages on a real first build, repaired wholesale 47 scripts later | `project-bin/check-page-shell.sh` | 5 | mdl, gate, review |
| After drafting and again after exec'ing any page script — scores the page MDL (or `mxcli describe` output on stdin) against its wireframe: headings/actions/content/classes, weighted. The scored companion to check-page-shell's binary gate; 32% median measured without it, 90% first-draft with it. Every run is appended to the project's docs/PAGE-FIDELITY.tsv — first non-stub row per page = first-build score of record vs the ≥80% target (forward-reference stubs score with --stub, exempt) | `project-bin/page-fidelity.js` | 5 | mdl, gate, review |
| Reviewing any module before calling it done — the ONE pass: build, gate, prove, LOOK (is it logical, does it look right, does it match our design, over every page not just the tested ones), confirm with the denominator stated | `skills/module-review.md` | 5,6 | review, test (mdl: on demand) |
| Before any mxcli exec / exec.sh / --mcp write — ask or run? the knob decides | `bin/exec-approval.sh` | 5,6 | mdl, gate |
| Before calling any module tested, or before re-running tests after a change — what testing a module means, which re-runs a change owes (UI-only vs logic lane), and the false-green register of confirmed ways a test reports green over a broken feature | `skills/testing-shape.md` | 5,6 | test, gate, review |
| Finishing any module — before calling it done. One command that runs every instrument and keeps "instrument faulted" apart from "feature failed"; in a wired project run the installed copy at bin/verify-module.sh | `project-bin/verify-module.sh` | 5,6 | mdl, gate, test, review |
| A style change that appears to have done nothing, a focus ring that paints on every page landing, or an app still grey after a design port every instrument called green — the three ways a correct rule paints nothing (matches nothing / matches chrome / loses the cascade), the two reads that tell them apart, and the class that arrived in the stylesheet and is bound to no widget | `skills/learned-css-that-never-applied.md` | 5,6 | review, gate (mdl: on demand) |
| Before trusting a green check/exec/DESCRIBE result as proof, or when a runtime symptom appears over a fully green model — the register of constructs that pass early rungs and fail later ones | `skills/learned-detection-gaps.md` | 5,6 | mdl, gate, review |
| Creating any entity, or calling a module security-ready — entity and grants land in one script, and ready means SHOW SECURITY MATRIX proves it | `skills/security-is-not-a-later-script.md` | 5 | mdl, gate, review |
| A CE error or behavior that looks like a known mxcli quirk rather than a modeling mistake — `bin/bug-lookup.sh CE0117` / `BUG-102` / "keyword" prints the matching ledger entries, so the session reads one entry, not the 32k-word ledger | `bin/bug-lookup.sh` | 5,6 | mdl, gate |
| The first command of every session, and any time someone asks "where are we" or "what next" — one screen: stage, done/overdue, the ONE next action, from the instruments, never from memory | `bin/status.sh` | P,0,1,2,3,4,5,6,7 | every role |
| Any session that will push a model to Mendix Team Server, and BEFORE telling the user a Team Server push is blocked — which remote is authoritative, settle-then-push order, and the four checks that have to fail first | `skills/teamserver-alignment.md` | 5,6,7 | gate (mdl, review: on demand) |
<!-- ROUTING:END -->

**Why this has to be explicit instead of implicit:** a project's own skill files are usually written before a given toolkit learning exists, or before a new one is added later — they never grow a cross-reference to it on their own. When you `git pull` this toolkit and it brings in a new baseline-worthy skill (most often a new `learned-*.md`), update every consuming project's routing to match — don't assume the next session will find it by chance.

**After cloning, set your local source paths** in `pipelines/<x>/pipeline/config.json` — the committed file ships with `<placeholder>` values; point them at your own source workspace. **Never commit real local paths.**

**Project output never lives here** (`analysis/`, `sources/`, `knowledge-base/`, `*.mpr` are gitignored) — each project runs in its own project folder (with `analysis/` inside it) that references this repo.

**Your build plan, `PROJECT.md`, and session notes live in your own project, not here.** This repo holds reusable tools + skills + small curated examples only. A project's architecture blueprint, numbered build plan, decision register, and running session diary belong in that project's own repo (e.g. `architecture/build-plan.md`, `PROJECT.md`, `SESSION-NOTES.md` at the project root) — never committed back into the toolkit. If a pattern from that plan turns out to be reusable across projects, promote it into a `skills/learned-*.md` file here instead of leaving the whole plan in place.

### Pipelines

- `pipelines/outsystems/` — OutSystems 11 → Mendix pipeline (was the standalone `os-migration-pipeline` repo)
- `pipelines/java-angular/` — Java + Angular/Spring Boot → Mendix pipeline
- `pipelines/node-express-react/` — Node/Express + React → Mendix pipeline (regex-based, proven on one source shape — see its README)
