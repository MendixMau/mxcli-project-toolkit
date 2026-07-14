# Conversion Runbook — The Interview-Driven Stage Pipeline

**Applies to:** any mxcli project — see Entry Modes below for where your project type enters the pipeline.

**Purpose:** The spine the toolkit was missing. Each stage below has an owning skill and each skill is good — but until now nothing said *what a stage must produce before the next one starts*, *what the user has to decide*, or *whose job it is to ask them*. This skill is that layer: a stage completes when a decision is on record, not when the agent stops typing.

**Upstream:** `bootstrap-project.md` (Stage P scaffolding), `query-the-model.md` (the lookup-before-ask discipline every gate depends on).
**Downstream:** every stage skill listed in §2 — this runbook sequences them, it does not replace their content.
**Root pointer:** `CONVERSION-RUNBOOK.md` at the repo root is a thin pointer to this skill plus "how to start"; this file is the executable detail. `toolkit-guide.html` at the repo root is the same journey as a visual page — **open it in the user's browser at Stage P kickoff** (`open toolkit-guide.html`), before the first interview question. It doubles as the shared CSS shell/token source for every stage HTML surface.

---

## Entry Modes — Where Your Project Enters the Pipeline

The stages are the same for everyone; what differs is where you enter and which analysis paths exist for you.

**The entry mode is a Stage-P interview decision, not a silent inference.** The agent proposes a mode *with evidence* ("you have specs in X and source in Y, so…") and records it `CONFIRMED` in `PROJECT.md` before any stage is skipped. A skipped stage in the wrong mode is a gap; in the confirmed mode it's correct. Classification rules — apply in order, first match wins:

1. **Any legacy/source code exists** (even a reference implementation you're not "migrating" — if it encodes behavior you want, it gets analyzed) → **Migration** (or at minimum, Stage 1 Path A runs on it).
2. **Any requirements artifacts exist** — specs, BRDs, context docs, wireframes, workshop outputs → **Requirements-driven**. Having "complete" specs does *not* mean skipping to Stage 5: stages 2–4 are where those specs become validated BRDs, an architecture, module boundaries, a design system, and an ordered plan. Skipping them means improvising all of that mid-build.
3. **Neither** — you're genuinely starting from a conversation → **Greenfield**. This is the narrowest mode, not the default for "no legacy system."

(Real misrouting incident, 2026-07-14: a project with full specs + analyzable source was classified greenfield "because there's nothing to migrate," proposing to skip 0–4 — exactly what rules 1–2 exist to prevent.)

| You're starting from… | Mode | Stages that run | What changes |
|---|---|---|---|
| **Legacy source code** (± docs, ± SME) | **Migration** | P, 0–7 (all) | The default everything below describes. Path A (code extractors) always runs. |
| **Requirements only** — BRDs, specs, workshop outputs, wireframes; no legacy code | **Requirements-driven** | P, 1–6 (skip 0 and 7) | Stage 0's reuse-vs-build extractor call is meaningless with no source — replace it with `document-discovery.md` over the requirements corpus (still a `✋` gate: the user signs off on the document inventory and what's missing). Stage 1 runs Path B (`kb-generation.md`) + Path C (SME) only; Path A is declared not-applicable, not "skipped". Stages 2–6 run unchanged — BRDs come from documents instead of extraction. Stage 7 only if legacy data exists somewhere to cut over. |
| **Just an idea / a running start on the model** | **Greenfield** | P (light), 5–6 | Stages 0–4 collapse to whatever plan the user already has. If you find yourself inventing requirements mid-build, you're actually in requirements-driven mode — back up to Stage 2. |

**No pipeline at all — à-la-carte tool use.** An existing Mendix app that just needs an audit, lint pass, or a regression/e2e test net doesn't enter this pipeline: no intake, no stages, no gates. Route straight to `existing-app-assurance.md` (which points at `query-the-model.md`, `e2e-harness-base.md`, `learned-db-assertions.md`, and the bundled lint/graph/quality skills). The pipeline is for *producing* an app; the tool shelf is for everything else.

## When to Use This Skill

- Starting any conversion (legacy source → Mendix), requirements-driven build, or greenfield mxcli build.
- You're not sure whether a stage is "done" — check its gate row in §2, not your own sense of completion.
- A decision got made without the user's sign-off and it's now biting — that's this skill's gate being skipped, not a one-off mistake. Fix the gate, don't just redo the decision.

---

## 1. The Interview Protocol — How a Gate Works

Every gate in §2 runs the same six-step shape. This is the thing that should be visible in every stage transcript:

1. **The agent does its homework first.** It never asks what it can derive. Anything answerable from the source, the extraction, or the model must be answered from there — see `query-the-model.md` for exactly which source answers which class of question. The intake rule already enforces the fallback: `"Unverified — how to verify: …"`, never a guess.
2. **The agent proposes, with evidence.** 2–4 concrete options, a recommendation, and *why* — citing the artifact that supports it. ("Your source has 4 auth roles, 3 of which are never checked; I recommend collapsing to 2.")
3. **The agent states its assumptions out loud** — the list of things it took for granted to reach that recommendation, so the user can correct the premise, not just the conclusion.
4. **The user answers in the terminal** — multiple choice, "other" always available.
5. **The decision is written to two places**: the stage's HTML proposal doc (the artifact, customer-showable) and `PROJECT.md` (the register), marked `CONFIRMED`.
6. **If the user doesn't know**: the agent applies its recommended option, marks it `ASSUMED` in `PROJECT.md` with the risk if wrong, and the run continues. A solo run never stalls; assumptions stay visible instead of silently baked in.

A proposal beats a questionnaire because it asks the user to **correct** something rather than supply it cold — and by the time each gate arrives, the agent has read the source and has evidence to put behind its recommendation.

**Unknowns are not blockers.** If nobody can answer a question yet, default + record + proceed (step 6). The pipeline only actually stops at a `✋` gate (§2) — every other stage keeps moving with `ASSUMED` markers trailing behind it for someone to reconcile later.

**The packaged form of this protocol is a checkpoint.** `skills/checkpoints/` ships ready-made Context-Aware Checkpoints (CAC) for the five busiest transitions (scope, BRD, architecture, design, build) — each runs the protocol above as a "2 predefined questions + 1 open question" script, derived from what the pipeline actually found. Use them where they exist; run the raw six steps where they don't. Either way the decisions land in `PROJECT.md` — checkpoints keep no state file of their own.

---

## 2. The Stage Matrix

Eight stages (plus Stage P kickoff). For each: what the user co-defines, what the agent produces, the review surface, the gate, and who owns it. `✋` marks a hard stop — the pipeline does not proceed past it without an explicit `CONFIRMED` decision (unknowns may still resolve to `ASSUMED` at non-✋ gates).

### Stage P — Kickoff

| | |
|---|---|
| **User defines** | Which source folder. Licence/security constraints on storing the client source. Is an SME available, and who? |
| **Agent produces** | Workspace scaffold (`bin/init-project.sh`), `CLAUDE.local.md` (paths, tools, routing), `PROJECT.md` (empty register), the Stage-P agent pair (`bin/init-agents.sh <session-root> p`, then complete placeholders + domain context per `agent-roles.md`), `intake.md` (8 questions, no guesses). The build trio (mdl/gate/test) is scaffolded later, at Stage 5 kickoff: `bin/init-agents.sh <session-root> build`. |
| **Surface** | `index.html` — the project dashboard, created here, grows every stage. |
| **Gate** | Every intake question has an answer or an explicit "Unverified — how to verify". No blanks. |
| **Owner** | `ba-agent` |

### Stage 0 — Triage ✋

| | |
|---|---|
| **User defines** | Reuse-vs-build-new extraction pipeline (agent proposes with a coverage matrix — two-way call, not three-way; see `source-triage.md`). Policy per missing dependency: acquire / stub / declare-not-implemented. Slice ordering if the source is too big for one pass — **a slice is an ordering, not an exclusion**. |
| **Agent produces** | `assessment.md` (inventory, 6 areas, risks), `triage.md` (pipeline decision, capability + coverage matrix, boundary handling, multi-app flag). If "build new": the new extractor, validated against hand-built ground truth. |
| **Surface** | `triage.html` |
| **Gate ✋** | User signs off on the extraction-pipeline decision and every missing-dependency policy. No BRDs are written before this. |
| **Owner** | `ba-agent` |

### Stage 1 — Analysis

Three extraction methods, not two. Each is either **done** or **explicitly declared unavailable by a named person** — never silently skipped.

| | |
|---|---|
| **User defines** | Do documents exist that aren't in the folder (specs, manuals, field-label sheets, screenshots)? DB schema? Sample data? Who has them? SME access for what neither code nor docs answer. |
| **Agent produces** | **Path A — code → AST extractors** (always runs). **Path B — documents → LLM extraction** (`kb-generation.md`). **Path C — SME interview** (closes `openQuestions` that neither code nor docs answer). |
| **Surface** | `extraction-report.html` |
| **Gate** | 4 extraction quality checks pass with evidence. Paths B and C are done or declared-unavailable, with attribution (who declared it, when). |
| **Owner** | `ba-agent` |

### Stage 2 — Requirements

| | |
|---|---|
| **User defines** | Confirms business rules the code implies. Answers `openQuestions` (via SME). Narrative is never invented. |
| **Agent produces** | BRD scaffolds → enrichment from `KB.md` → validation to clean. `F{NNN}.brd.json`. |
| **Surface** | `enrichment-summary.html` |
| **Gate** | Every BRD validation-clean; `validation-report.md` has 0 issues; open questions are chased to closure, not merely logged. |
| **Owner** | `ba-agent` |

### Stage 3 — Architecture & Design ✋

The biggest gap before this runbook existed. Module boundaries, wiring diagrams and fit-gap were already handled well by `modularize-domain.md` and `architecture-blueprint.md`. Everything else on this row was a silent gap the pipeline never asked about.

| | |
|---|---|
| **User defines** | ① One Mendix app or several (if flagged at Stage 0). ② **Module boundaries** (agent proposes with `modularize-domain.md` criteria). ③ **Buy vs build vs stub, per fit-gap item** — the confirming step `brd-to-build-plan.md` assumed already happened. ④ **Target security / role model** — not just whether auth existed in the source, but what the target should be. ⑤ **Data volumes, concurrency, NFRs** — these decide indexing, pagination, datagrid-vs-paged-gallery, loop batch sizes. ⑥ **Integration contracts** — real or stub, endpoint, credentials, owner, test environment. ⑦ **Branding inputs** — logo, palette, type, spacing, per `design-artifacts.md`. |
| **Agent produces** | `.mx-brd.json`, `architecture/` (module defs, layer diagram, wiring diagram, `fit-gap.md`), `design/` (`design-system.html`, annotated wireframes). |
| **Surface** | `module-design.html` · `architecture.html` · `design-system.html` + `wireframes/*.html` |
| **Gate ✋** | Boundaries approved. Marketplace calls made. Role model, volumes, integrations and branding either `CONFIRMED` or recorded as `ASSUMED` with risk. |
| **Owner** | `architect-agent` (interviews run by `ba-agent`) |

### Stage 4 — Build Plan ✋

| | |
|---|---|
| **User defines** | **Acceptance criteria per module** — what "done" means beyond CE-error-free. **Environment / DTAP / deployment target.** Iteration granularity. |
| **Agent produces** | `architecture/build-plan.md` — numbered, dependency-ordered (marketplace imports → entities → associations → microflows → pages → demo users/roles), with pending decisions promoted to the top. |
| **Surface** | `build-plan.html` |
| **Gate ✋** | Pending-decisions list empty or fully answered. User approves. |
| **Owner** | `architect-agent` |

### Stage 5 — Build

**Not migration-specific.** This is the standard Mendix build discipline — greenfield builds start here. Already well codified: layer1 (entities/associations/enums, `security-setup.mdl` last) → layer2 (microflows) → layer3 (pages); the guard chain (uncommitted → SP-open → concurrent-writer → snapshot → exec → mxbuild gate → auto-restore → manual SP reopen); the stale-build protocol; the STOP conditions in `learned-mdl-preflight.md`.

| | |
|---|---|
| **User defines** | Confirms the per-module **business-rule coverage checklist** — the definition of "done" for the module, not CE-error-free. |
| **Agent produces** | Working modules, one at a time, each passing the build loop's gates. Seed/demo data (per `demo-data.md`) is produced here too — you can't validate a coverage checklist against an empty database, so seeding is part of Build, not a separate stage. |
| **Surface** | `ux-review-*.html` |
| **Gate** | Every build-plan script passes its gates **and** its coverage checklist. CE-error-free ≠ done. |
| **Owner** | `mdl-agent` → `gate-agent` |

### Stage 6 — Test

Also not migration-specific — the shared E2E discipline (`e2e-harness-base.md`, `test-app.md`).

| | |
|---|---|
| **User defines** | Test scope beyond the golden path; which edge cases matter. |
| **Agent produces** | Playwright golden-path + edge-case tests, DB assertions, results reported verbatim. |
| **Surface** | `test-report.html` |
| **Gate** | Golden path + edge cases + DB assertions pass. Failures fixed and re-run. |
| **Owner** | `test-agent` |

### Stage 7 — Cutover

Migration-specific — greenfield builds have no legacy system to cut over from and skip this stage. Runs **after** Stage 6, deliberately: don't migrate real production data and flip users onto an app that hasn't passed its E2E gate yet.

| | |
|---|---|
| **User defines** | Is legacy data migrated, or is the app going live empty/with only the Stage 5 seed data? Who cuts over, and when? Rollback plan? |
| **Agent produces** | Legacy-data migration scripts (if any), cutover checklist. |
| **Gate ✋** | Stage 6 passed. Decision recorded in `PROJECT.md` — even if the decision is "throw the legacy data away". |
| **Owner** | `ba-agent` → `mdl-agent` |

### Wrap-up

Promote proven patterns into `skills/learned-*.md`. **Every point where the pipeline's silence forced an improvised decision is a runbook defect** — fix it in this file or the relevant stage skill, not by working around it locally on the next project. Log new mxcli bugs in `bug-logs/mxcli-bugs.md`. Archive the project workspace.

---

## 3. The Three Project Files (No Overlap)

| File | Job | Lifetime |
|---|---|---|
| `CLAUDE.local.md` | Machine context: absolute paths, tool versions, skill routing. What agents auto-load every session. | The conversion |
| **`PROJECT.md`** | The human record: scope, dependencies (missing source deps, marketplace, integrations), every decision with its options and rationale, assumptions marked `ASSUMED` / `CONFIRMED`, open questions. Written at every gate. Absorbs `architecture/open-issues.md`. | Outlives the build |
| `architecture/build-plan.md` | The executable sequence the build loop consumes and ticks off. | Dies when the build finishes |

`fit-gap.md` stays separate from `PROJECT.md` — it's analysis, not decisions.

---

## 4. Decision Flow: mxcli vs MCP vs Studio Pro GUI

Before writing any MDL, check the STOP table in `learned-mdl-preflight.md`:

```
Write MDL  →  check the STOP table
                ├─ clean            → mxcli exec (SP closed)
                ├─ STOP → MCP       → mxcli --mcp exec (SP open) — bypasses the BSON serializer
                ├─ STOP → GUI       → Studio Pro by hand (settings, security-bearing drops)
                └─ no MDL syntax    → hand-rolled MCP (pg_patch_page)
Crashed anyway? → bin/restore-mpr.sh  (restores .mpr AND mprcontents/ — either alone is useless)
                → log it in bug-logs/mxcli-bugs.md
```

An MPR is two parts: `Project.mpr` (SQLite index) and `mprcontents/` (BSON units with the actual model). `bin/exec.sh` snapshots **both** automatically before every batch; 5 rotate; `bin/restore-mpr.sh` rolls back; git commits at phase gates are the real history. Ad-hoc `.mpr.backup` copies are banned.

---

## Checklist Before Calling a Stage "Done"

- [ ] Run `bin/gate-check.sh <project-dir> <stage>` — it fails loudly if required artifacts are missing; a stage isn't done until this passes. This is mechanical (file-existence/grep checks), not something to self-attest from memory.
- [ ] The stage's gate ran the full 6-step interview protocol (§1) for every user-facing decision — not just a yes/no on something already built.
- [ ] Every decision is written to both the stage HTML surface and `PROJECT.md`, marked `CONFIRMED` or `ASSUMED` (never silently defaulted with no record).
- [ ] `✋` gates have an explicit `CONFIRMED` decision — no `ASSUMED` allowed to pass a hard stop.
- [ ] `query-the-model.md` was followed before any question was asked (nothing asked that a query or a read could have answered).
- [ ] The stage's surface HTML is linked from `index.html`.
- [ ] Any point where the pipeline was silent and forced an improvised decision is logged as a runbook defect, not just patched locally.
