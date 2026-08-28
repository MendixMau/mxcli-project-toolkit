# mxcli-project-toolkit — Claude Context

## What this repo is
Shared skills, stage-gate tooling, and learnings for **Mendix migration and development projects**.
Serves three entry modes (see `skills/conversion-runbook.md` → "Entry Modes"): **migration** (legacy source, all stages), **requirements-driven** (specs/SME input, no legacy code, stages 1–6), and **greenfield** (stage 5 onward). Plus **à-la-carte use with no pipeline at all** — auditing or regression/e2e-testing an existing app routes straight to `skills/existing-app-assurance.md`, skipping intake/stages/gates entirely.

## The front door
- `CONVERSION-RUNBOOK.md` (root) — thin "how to start" pointer.
- `toolkit-guide.html` (root) — the visual onboarding page. **First-touch rule — this is the single source of the rule; every other mention defers here:**

  ```
  [ -e "<project-root>/.claude/.guide-shown" ] && DO NOT OPEN
  ```

  Open it in the user's browser (`open toolkit-guide.html` / `xdg-open`) **only** when that sentinel is absent, and immediately `touch` it so no later session repeats. `bin/init-project.sh` opens it at scaffold time and writes the sentinel then. The user may also ask for it by name at any time — that's always allowed and does not consult the sentinel.

  **Do not re-open it on a hunch** that the user "seems unsure" — a session cannot tell a first-timer from someone who has seen it fifty times, and every session that guesses guesses "yes". The sentinel is the only test. (Real incident, 2026-08-12: this rule was stated conditionally here and in `README.md` but *unconditionally* in `skills/conversion-runbook.md`, `CONVERSION-RUNBOOK.md`, and inside `toolkit-guide.html` itself. Because the runbook is the one file every session is required to read first, every pipeline session opened the guide, and the user got a browser tab per session.)

  It's also the shared CSS shell/tokens for every stage HTML surface — that use has nothing to do with opening it.
- `skills/conversion-runbook.md` — **the spine**: 9-stage matrix, interview protocol, gates, entry modes. Start here when unsure what stage anything is in.
- `bin/init-project.sh <project-root>` — **the one-command install**: `intake.md`, `PROJECT.md`, `CLAUDE.local.md` (runbook wiring), all six agent stubs, `index.html` dashboard; opens the guide. Idempotent.
- `bin/gate-check.sh <project-dir> [stage]` — mechanical stage gates; regenerates the project dashboard from real files. Verdicts are `PASS` / `PENDING` (nothing there yet) / `FAIL` (there and wrong) / `WAIVED` (declared out of scope in the register, with a reason, via `--adopt` / `--waive`) / `MANUAL`. Never infer a project's position — read the register line, or ask. It also runs the **obligation check** (`bin/lib/obligations.tsv` + `bin/lib/obligation-check.sh`): per-module *passes* that owe a mark — LOOK, wiring sweep, journeys, coherence — each with the artifact that proves it and the denominator that artifact must state. A pass nobody performed reports `PENDING`/`FAULT`, never green-by-absence; `--waive look/<Module> --reason "..."` records a pass deliberately not performed, and obligations below an `--adopt` point report `ADOPTED`. Alongside it runs the **artifact check** (`bin/lib/artifact-manifest.tsv` + `bin/lib/artifact-check.sh`): the producer-side mirror — one row per artifact a stage's "Agent produces" row promises, each row citing the consumer that reads it, so a stage that never emitted its artifact reports `PENDING` out loud instead of being found by a human reading a failed project. File presence only, never content quality; waivers are register lines (`Waived artifact <id>: reason`, or the stage-level waiver covering its artifacts wholesale).
- `bin/sync-project.sh <project-root>` — run after every toolkit `git pull`: refreshes the artifacts that were *copied* into the project (new intake questions, untouched agent stubs) and flags stale baseline routing. Referenced skills need no sync — they update with the pull.

## Live checklist — every stage, in the chat
Every stage and module build follows the **Live Checklist Protocol** (`skills/conversion-runbook.md` §1b): post the stage's checklist in chat at start, update with ✅/🔄/⬜/❌/⏭ marks as items land, full repost before every gate. No stage works silently between gates. This is not build-phase-only.

## One decision register
All gate decisions land in the consuming project's `PROJECT.md`, marked `CONFIRMED` or `ASSUMED`. The `skills/checkpoints/` CAC files are the packaged mechanism that runs the runbook's interview protocol at the six busiest transitions — they write to `PROJECT.md`, never to a separate state file.

**Ask, then stop.** Gate questions are actually asked in chat — on Claude Code via `AskUserQuestion` (clickable options), on any other harness as plain numbered markdown with "something else" always available — and **either way the agent ends its turn and waits for the answer**. `AskUserQuestion` is a Claude Code built-in, not something a Copilot/Cursor/Windsurf session can install; the rendering is tool-specific, the asking and the stopping are not. `skills/interview-protocol.md` §3 → "Asking on a non-Claude agent" is the single source of that rule; every other mention defers there. `ASSUMED` is earned by asking (user said "you decide"), never by skipping the question — finding the answer in the source justifies the *recommendation*, not silence. Unattended runs are opt-in only (`Interview mode: unattended` in `PROJECT.md`, at the user's explicit request).

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
| Setting up dev-process subagents (ba/architect/mdl/gate/test/review) | `skills/agent-roles.md` |
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

## Writing in this toolkit — generic first

**Authoring rule. This section governs work *on* this repo. It is not shipped guidance:
consuming projects load their own generated `CLAUDE.local.md`, and the per-tool files
(`AGENTS.md`, `.github/copilot-instructions.md`, `.cursorrules`, `.windsurfrules`) are
POINTERS, never copies — see `project-bin/check-root-clean.sh`.**

> **Build it generic. Source-specific work stops at the extractor. Everything downstream of
> the BRD must work for any input — extracted code, documents, SME interview, or requirements
> typed by hand — and therefore lives in `bin/`, not in `pipelines/<platform>/`.**

The BRD is the platform boundary. Upstream of it a source is OutSystems, Java, or a folder of
epics. Downstream of it there are only entities, microflows, pages and use cases. This repo
serves three entry modes (migration, requirements-driven, greenfield) plus à-la-carte use, and
only the first of those runs a pipeline at all.

**Where things go.**

| Kind of thing | Home | Why |
|---|---|---|
| Reading a specific source shape | `pipelines/<platform>/extractors/` | genuinely per-stack; `extractor-quality-loop.md` governs building one for a new stack |
| Anything reading BRDs | `bin/`, via `bin/lib/discover-brds.sh` | BRDs arrive from extractors, `kb-generation.md`, SME interviews, or by hand — the reader must not care |
| Judgement, verdicts, gates | `skills/` | `skills-over-scripts.md` is the governing rule and it wins over this one |

**Specialisation is the consumer's job, and it is already supported** — `extractor-quality-loop.md`
(any stack: interface, validator contract, `run.sh`, 6 scored dimensions, 95% gate) plus three
worked pipelines to copy. Do not add a scaffold that stamps those files out; a prose spec and
worked examples are the correct form here.

**Why this is written down (2026-08-19).** `generate-enrichment-report.js` — the Stage 2 surface
— was built three times, once inside each pipeline, because nothing said it shouldn't be. The
three copies drifted onto three different BRD shapes (`module` vs `modules[]`, `attributeCount`
vs `attributes[]`, `a.to` vs `target`), so a BRD written by hand per `brd-generation.md` rendered
a page of `undefined` and zeros that looked complete. Requirements-driven and greenfield projects
got no Stage 2 surface at all, though `conversion-runbook.md` promises one unconditionally. The
same disease had already been diagnosed one layer down a week earlier — see the header of
`bin/lib/discover-brds.sh`: *"That is what duplication costs: the fix does not travel."*

**Before adding any file under `pipelines/`, ask: does this read a source, or does it read a
BRD?** If it reads a BRD, it is in the wrong directory.

## Shipping an instrument — field-proof before merge

Every defect in the F-042 cluster (2026-08-28) shipped the same way: an instrument written
against **imagined** input and merged without ever executing against real input. The
selftests all passed — selftests prove the logic, and the logic was fine; what was wrong was
the assumptions. So, before a new or materially changed instrument under `bin/`,
`project-bin/` or `project-tests/` merges:

1. **Golden input is captured, never hand-written.** A parser of tool output (`SHOW PAGES`,
   `SHOW MODULES`, mxbuild logs) gets a verbatim capture from a real model committed beside
   its fixture, with the parsed counts asserted. Hand-written test input encodes the same
   assumption the code makes — F-042's header-row bug (6 real pages counted as 13) was
   invisible to anything but real output, because real output had columns nobody imagined.
2. **Both layouts.** Paths resolve through `_common.sh` / config-derived roots, probed on
   single-tree AND two-tree (`.mpr` under `app/`) checkouts. F-020 and F-042 are the same
   bug found twice, three weeks apart, in different files.
3. **Both platforms.** Bash runs under Git Bash on Windows, where MSYS maps `foo` →
   `foo.exe` transparently — but Node does not: never `execFileSync` a bare wrapper name
   without an `.exe`/`.cmd` probe or env override. Guard mac-only tools (`sips`,
   `/usr/libexec/java_home`) behind `mxtk_platform` / `process.platform`.
4. **One field run, cited.** The commit that ships an instrument names the real project it
   ran against and what it measured there. An instrument nobody has run is a claim, not a
   check.
5. **A producer for every consumer.** If the instrument reads an artifact
   (`page-scope.json`, `stack.env`), say in its header which **mandatory** chain step
   produces that artifact — "documented in a skill" is how design-audit.js sat installed
   and never ran for an entire build. If no mandatory step produces it, wire one before
   shipping the consumer.

## Adding new skills
Create `skills/{topic}.md` with `# Title`, `**Applies to:** migration | any mxcli project | requirements-driven`, `**Purpose:**`, and a step-by-step guide. Add it to `README.md`'s "When to use which skill" table. **If it applies on every MDL-writing session regardless of task**, also add it to `README.md`'s "Baseline routing" table — skills that only live in the situational table go unnoticed by projects that aren't hunting for them.

## Committing in this clone — never `git add -A`

Several Claude sessions routinely have this clone open at once, in **one working tree and
therefore one git index**. So:

> **Stage and commit in the same breath, or pass explicit paths: `git commit -- <paths>`.
> Never `git add -A`.** Before resetting a commit, look at what else is in the index.

**Why (real incident, 2026-08-21).** A session ran `git commit` with no pathspec while another
session had 29 unrelated files staged. Git takes the whole index, so that work landed inside a
commit titled "Log BUG-95: …". The resulting `git reset` restored the 29 files — and silently
took the committer's *own* bug-log entry out of the working tree with it, where it survived
only in a dangling commit. Authorship is not readable from mtimes either: eight files were
mislabelled as a peer's until someone read the diffs.

Same root cause as the testing rule below — a shared, moving tree makes any whole-tree
operation untrustworthy. Coordinate with `ListAgents` / `SendMessage` before committing, and
if a peer's untracked scratch file trips the pre-commit leak guard
(`bin/check-no-client-data.sh` scans untracked files too), ask them to fix it. Do not gitignore
it and do not narrow the denylist.

## Testing this toolkit — scoped by default

`tests/wave2/run-all.sh` runs every fixture in the suite. **Do not run it as a reflex "did I
break anything" check after a normal edit.** Run only the fixture(s) that exercise the file(s)
you actually touched (e.g. changed `bin/open-questions.sh` → run `test-open-questions.sh`;
changed `bin/gate-check.sh` → also run `test-bug03-gates.sh`, `test-source-sufficiency-gate.sh`,
whatever else targets it). Grep `tests/wave2/` for the filename you changed if you're unsure
which fixtures cover it.

**Why:** this repo is routinely edited by more than one agent session at once (real incident,
2026-08-19 — a peer session mid-edit reported known, unrelated failures already present in the
shared working tree). A full-suite run over a moving target mixes someone else's in-flight
breakage into your result and tells you nothing trustworthy about your own change — it looks
like verification but isn't. It is also strictly slower for no more signal than the scoped run,
since the untouched fixtures were never at risk.

**Run the full suite only when the user explicitly asks for it in that message. There is no
other trigger, and none of the following is one: about to open a PR, closing out a multi-file
change, or a change that looks like it had wide blast radius.** Those read as licence to
self-authorize, and they were — the rule said "ask first" and then handed out three reasons not
to. Wide blast radius is a reason to pick the right *scoped* check, not to run everything: for
`bin/lib/skill-routing.tsv` and its re-render (README.md, ROUTING.md, every agent template, and
`gate-check.sh`'s stage map at once) that check is `bin/render-routing.sh --check`.

**Asking is also required for a single fixture** — name it, say what it will tell us, and wait.

Where a fixture's assertions are greps over a file you changed, prefer verifying by inspection:
read the fixture, replicate its greps against the changed file, and report that. Same signal, no
suite run, no interference with whatever another session has in the tree right now.
