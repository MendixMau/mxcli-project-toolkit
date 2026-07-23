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
4. **The question is actually asked, in the chat** — multiple choice (use `AskUserQuestion` where available), "other" always available. **Then the agent ends its turn and waits.** Do not answer your own question and keep working in the same turn — a gate that never reaches the user's screen is not a gate. Finding the answer in the source does not waive the question: source evidence powers the *recommendation* (step 2), it never replaces the *asking*.
5. **The decision is written to two places**: the stage's HTML proposal doc (the artifact, customer-showable) and `PROJECT.md` (the register), marked `CONFIRMED`.
6. **`ASSUMED` is earned by asking, never by skipping.** An answer may be recorded `ASSUMED` only after the question was actually posed and the user said "don't know" / "you decide" — that is delegation-by-consent, recorded with the risk if wrong. Deriving an answer yourself and not asking is a protocol violation, not an `ASSUMED`.

A proposal beats a questionnaire because it asks the user to **correct** something rather than supply it cold — and by the time each gate arrives, the agent has read the source and has evidence to put behind its recommendation.

**Unattended mode is opt-in, never inferred.** The "default + record + proceed" behavior (skipping the wait, not the question — questions still get logged in `PROJECT.md` open-questions) is only legal when the user explicitly said to run unattended, recorded at Stage P in `PROJECT.md` (`Interview mode: unattended`). Default is **attended**: every gate question is asked in chat and the turn ends there. (Real incident, 2026-07-14: an attended run produced architecture diagrams and a design system through Stage 3 without a single question reaching the user — "a solo run never stalls" was read as "never ask." It means "an *authorized* solo run doesn't deadlock," nothing more.)

**Reused decisions must be shown, not silently applied.** A question may only be skipped because "it was already decided upstream" if (a) that decision was itself answered by the user in chat — an agent-recorded `CONFIRMED` the user never saw is a protocol violation, not a decision — and (b) the agent **quotes the prior decision back in chat** when skipping ("skipping acceptance criteria — you confirmed at Stage 3: *'happy path + validation rules per module'*, PROJECT.md row 12"). If the user doesn't recognize the quoted decision, it wasn't theirs: re-ask it. (Real incident, 2026-07-14: Stage 4's ✋ questions were skipped citing Stage-3 decisions that had themselves been self-recorded without an interview — laundering one silent decision into a skip-license for the next gate.)

**Two open brainstorms are part of the pipeline — not everything is multiple choice.** Closed 2+1 questions capture decisions; they never surface what the user wanted to say unprompted. Two moments are explicitly *divergent conversation*, run before their gate's predefined questions:

- **Scope brainstorm (Stage 0, before triage sign-off):** present the source/requirements map with effort signals, then discuss openly — full rebuild or a slice? What is this project actually for (POC, replacement, demo)? What matters most to you, what can be dropped, what's missing from the map entirely? No option lists; talk until the user says the scope feels right, then record it.
- **Build-scope brainstorm (Stage 4, before the plan locks):** present the module/script map with rough effort, then discuss openly — build everything or a subset? Ordering by value? Anything to add, defer, or kill? Same rule: conversation first, then the closed gate questions, then `CONFIRMED`.

And at **every** checkpoint, after the 2+1 questions: one standing open-floor question — "anything else you want changed, added, or worried about — scope, priorities, anything?" — before the gate closes.

**Lightweight-change carve-out — small, unambiguous, already-decided changes skip dispatch, never skip the record.** Not every BRD/architecture edit needs the six-step protocol or a `ba-agent`/`architect-agent` round-trip. If the change is small in scope (renaming a field, adding one or two entities/attributes whose shape was already settled in the current conversation, fixing a stale line that contradicts an already-CONFIRMED decision) *and* unambiguous (no real alternatives to weigh, nothing left for the user to correct), the acting agent may edit the BRD/architecture doc directly instead of dispatching a subagent. It still MUST: (a) log a `PROJECT.md` decision row for the change, (b) set or flip the drift-sync marker on any BRD/wireframe it touched, per §3b. What this carve-out buys back is the interview/dispatch overhead, not the paper trail — a change made without a recorded decision or marker is exactly the drift this runbook exists to catch, however small the diff. Anything touching module boundaries, the security model, a new integration, or requiring a judgment call between real alternatives still runs the full protocol. (Real incident, 2026-07-23: a "flip 2 entities to persistent + add 2 new entities" change — already fully settled in conversation — was routed through ba-agent twice and architect-agent once, ~270k combined tokens, for what was fundamentally a handful of document edits. The user called it out directly. The fix isn't skipping the record, it's skipping the dispatch when there's nothing left to decide.)

**The packaged form of this protocol is a checkpoint — and checkpoints are mandatory where they exist.** `skills/checkpoints/` ships ready-made Context-Aware Checkpoints (CAC) for the six busiest transitions (scope, BRD, architecture, design, build, cutover) — each runs the protocol above as a "2 predefined questions + 1 open question" script, derived from what the pipeline actually found. Run the raw six steps only where no checkpoint exists. **A checkpoint fires *before* the next stage's artifacts are produced** — creating architecture diagrams or a design system before their checkpoint ran is a protocol violation: stop, run the checkpoint, and be prepared to throw the premature artifact away. Either way the decisions land in `PROJECT.md` — checkpoints keep no state file of their own.

---

## 1b. The Live Checklist Protocol — Progress Is Shown in the Chat

Gates inform the user at stage *transitions*; this protocol informs them *during* a stage.
The failure it fixes (reported by a live user, 2026-07-14): the agent works silently against
file-based checklists for a whole stage, and the user has no idea what is being done until
the next gate. File checklists are the record; **the chat is the display.**

Rules — these apply to every stage and every per-module build loop:

1. **Post the checklist at stage/module start.** Before the first unit of work, print the
   stage's checklist in chat as a numbered list with status marks. For a build module this is
   the confirmed coverage checklist + the build-step sequence; for a pipeline stage it is that
   stage's gate row broken into its concrete steps. Keep it ≤ ~12 items — group, don't dump.
2. **Status marks:** ✅ done · 🔄 in progress · ⬜ pending · ❌ failed/blocked · ⏭ skipped
   (always with a one-line reason).
3. **Update as you go, compactly.** After each item completes or fails, post a one-line delta
   ("✅ 4/9 — domain model applied, 12 entities, 0 CE errors"). Repost the *full* checklist at
   milestones (roughly every 3–4 items, and always right before a gate) so the user never has
   to scroll back to reconstruct state.
4. **No silent stretches.** Never complete more than two checklist items without a chat line.
   Long single items (an extractor run, a big exec) get a line when they start, not only when
   they finish.
5. **Subagent work counts.** When work is delegated, the main session posts which item the
   subagent owns before dispatch, and updates the checklist from its verdict when it returns.
   Delegation is not an exemption from visibility.
6. **Chat mirrors the file, never replaces it.** `PROJECT.md`, the build plan, and stage
   checklists remain the durable record; the chat checklist is a view of them. If they
   disagree, the file is wrong or stale — fix it immediately.

The final full-checklist repost before a gate doubles as the gate's evidence: the user should
be able to approve the gate by reading that one message.

---

## 2. The Stage Matrix

Eight stages (plus Stage P kickoff). For each: what the user co-defines, what the agent produces, the review surface, the gate, and who owns it. `✋` marks a hard stop — the pipeline does not proceed past it without an explicit `CONFIRMED` decision. At non-✋ gates unknowns may resolve to `ASSUMED` — but only per §1 step 6: the question was asked and the user delegated; never because asking was skipped.

**Stages are sequential; gates are paste-proven.** Never start stage N+1's work — including launching background agents for it — before stage N's gate is closed: its `✋` decisions `CONFIRMED` **and** `bin/gate-check.sh <project-root> N` run with its output **pasted in chat**. Self-attesting "stage complete" without showing the gate-check output is a protocol violation. Parallelism is fine *within* a stage (e.g. Stage 3's blueprint and design tracks), never *across* stages — Stage 4 consumes Stage 3's *approved* outputs, so a build plan drafted alongside the architecture is a plan built on unreviewed guesses. (Real incident, 2026-07-14: Stage 3 and Stage 4 agents launched in parallel, then both stages self-declared complete with open questions outstanding, no wireframes, and gate-check never run.)

**"Let's ideate" means stop producing.** If the user asks to ideate, discuss, or explore a direction (branding, design, scope — anything), that is a request for a brainstorm conversation *now*: no artifact generation, no background agents, until the conversation converges and the user says to proceed. Producing the artifact first and offering to "review the direction together" afterwards inverts the protocol. (Same incident: the user answered a layout question with "let's ideate further on the actual design" — and the design system was generated anyway.)

**These rows are routing, not specs.** Before producing any stage artifact, open the stage's owning skill file and follow *its* output list end-to-end — the summary here (and in the README / `toolkit-guide.html`) names the highlights, not the full deliverable. (Real incident, 2026-07-14: a Stage-3 run worked from the summary, produced a design system, and skipped the one-wireframe-per-screen requirement that only `design-artifacts.md` spells out — half the deliverable, and the half the build loop depends on.)

### Stage P — Kickoff

| | |
|---|---|
| **User defines** | Which source folder. Licence/security constraints on storing the client source. Is an SME available, and who? |
| **Agent produces** | Workspace scaffold (`bin/init-project.sh`), `CLAUDE.local.md` (paths, tools, routing), `PROJECT.md` (empty register), **all five agent stubs** (`bin/init-agents.sh <session-root>` — stubs are inert until completed, so all five exist from day one), `intake.md` (8 questions, no guesses). Complete ba/architect placeholders + domain context now (per `agent-roles.md`); complete mdl/gate/test at Stage 5 kickoff. |
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
| **Agent produces** | `.mx-brd.json`, `architecture/` (module defs, layer diagram, wiring diagram, `fit-gap.md`, `blueprint.html` checkpoint render), `design/` per `design-artifacts.md`'s full output list: `ds.css` + `design-system.html` + **`wireframes/*.html`, one annotated wireframe per screen** — the design system without the wireframes is half the deliverable and fails the gate. |
| **Surface** | `module-design.html` · `architecture/blueprint.html` (generated render of `blueprint.md` — architecture-blueprint.md Step 7, never hand-edited) · `design-system.html` + `wireframes/*.html` |
| **Gate ✋** | Boundaries approved. Marketplace calls made. Role model, volumes, integrations and branding **each asked and answered**: `CONFIRMED`, or explicitly delegated by the user ("you decide" → `ASSUMED` with risk). Never `ASSUMED` without the question having reached the user. **No architecture/design artifact is produced before its checkpoint ran.** |
| **Owner** | `architect-agent` (interviews run by `ba-agent`) |

### Stage 4 — Build Plan ✋

| | |
|---|---|
| **User defines** | **Acceptance criteria per module** — what "done" means beyond CE-error-free. **Environment / DTAP / deployment target.** Iteration granularity. |
| **Agent produces** | `architecture/build-plan.md` — numbered, dependency-ordered (marketplace imports → module roles → entities + entity grants → associations → microflows + execute grants → pages + view grants → demo users), grants **co-located** with the element they protect (never a deferred security script), the role-to-access table for every element, with pending decisions promoted to the top. Plus the first module's **module brief** (`architecture/modules/<Module>-brief.md`, per `module-brief.md`) — subsequent briefs are produced just-in-time as each module's build begins. |
| **Surface** | `build-plan.html` |
| **Gate ✋** | Pending-decisions list empty or fully answered. Role-to-access table complete for every element. **Every CONFIRMED decision from Stages 0–3 maps to a build-plan script or an explicit `descoped` note** — a confirmed decision with no build disposition is how scoped work silently vanishes (a real WMS incident: the CONFIRMED Phone-Web nav profile, wireframe and all, was never built and nothing flagged it). User approves. |
| **Owner** | `architect-agent` for the build plan; `ba-agent` drives each module brief (pulling `architect-agent` for the technical layer). |

> **Before Stage 5 starts — run the build-ready check:** `bin/gate-check.sh <project-dir> build-ready`.
> It asserts, in one shot, that the project is actually wired to build: `CLAUDE.local.md` has a
> `## Wiring` block, baseline routing includes the UI-quality skills, all 5 agents are present with no
> placeholders, at least one module brief exists, and wireframes + a design system are present. It
> fails loud listing every missing item. This is the preflight that catches a project that looks
> wired but is UI-blind (a real WMS-class miss).

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

Also not migration-specific — the shared E2E discipline (`e2e-harness-base.md`, `test-app.md`) plus
the full-app UI review loop (`ui-review-loop.md`) run across every page, not just per-module.

| | |
|---|---|
| **User defines** | Test scope beyond the golden path; which edge cases matter. |
| **Agent produces** | Playwright golden-path + edge-case tests, DB assertions, results reported verbatim. Plus a full-app **UI review loop** pass (`ui-review-loop.md`): a diagnostic punch-list (`design/ui-reviews/ui-review-<date>.html`) covering render/interaction/reuse/wireframe-divergence across every page, with the `ba-agent` conformance cross-check. |
| **Surface** | `test-report.html` · `design/ui-reviews/ui-review-<date>.html` |
| **Gate** | Golden path + edge cases + DB assertions pass. **UI review loop: zero open P1** (blank required fields, unclickable nav, empty grids, wrong-page wiring, silent save failures). Failures fixed and re-run. |
| **Owner** | `test-agent` (E2E) + the UI review loop (diagnostic; fixes routed back through the build loop) |

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

## 3b. Requirements drift-sync — BRDs stay the source of truth after Stage 2

The BRDs (`analysis/knowledge-base/brd/*.brd.json`) are what every downstream stage reads:
`architect-agent` builds the blueprint from them, `mdl-agent` synthesizes scripts from them,
`gate-agent` checks coverage against them, a module brief inherits whatever they say. `PROJECT.md`'s
Decisions table is an **append-only log of what was decided** — it is not itself the current
definition of behavior. So when a Stage-3+ decision (an architecture refinement, a build-time
judgment call, a bug found mid-scripting) changes something a BRD or wireframe *already asserts* and
the BRD is never updated, the two diverge silently, and the next agent to read that BRD inherits a
stale assertion. This is a real, observed failure mode, not a hypothetical — see the incident note in
`iterative-build-loop.md` → "Requirements Drift-Sync Rule" (where the detection mechanics — which
BRD fields count as "asserted" — live).

**Ownership is split, on purpose:**
- **Whoever confirms the decision** (`architect-agent`, `mdl-agent`, `gate-agent`, or `ba-agent`
  itself) is responsible for **marking** it at the moment it logs the decision to `PROJECT.md`.
- **`ba-agent`** owns the actual **BRD/wireframe edit** (the flush) — it is the BRD artifact owner.

**Cadence — mark always, flush just-in-time, gate at the boundary** (do *not* batch by a fixed
count; the cost that matters is the drift *window*, not the sync *frequency*):
1. **Mark** every BRD-touching decision immediately, inline in its `PROJECT.md` Notes cell, using the
   marker convention below. This is ~free — one tag on a row you're already writing.
2. **Flush** (ba-agent re-syncs the named BRD/wireframe) before the next agent *reads* that artifact —
   batched, just-in-time, the same "never stockpiled" discipline the build loop uses for MDL. This
   avoids re-syncing a decision that gets revised again in the same session.
3. **Gate**: a BRD-touching decision must be flushed before any stage gate it precedes. `gate-check.sh`
   enforces this mechanically (see below) — nothing crosses a stage boundary with a pending marker.

**Marker convention** (the exact string `gate-check.sh` greps for):
- Pending: append `[sync: <files> UNSYNCED]` to the decision's Notes cell (e.g. `[sync: F003, F001 UNSYNCED]`).
- Flushed: `ba-agent` flips it to `[sync: <files> synced <YYYY-MM-DD>]`.
- Touches no BRD: no marker (the default) — or `[sync: none]` to record a conscious "checked, nothing to sync".

**Enforcement:** `bin/gate-check.sh` computes a **BRD drift-sync** line alongside the protocol-freshness
check and **blocks every stage gate** while any `[sync: … UNSYNCED]` marker remains in `PROJECT.md`
(message names the offending rows). Projects that never adopt the convention have no markers → the
check is inert (PASS) for them. This is the layer that makes the rule survive deadline pressure — a
prose-only rule was skipped for a week on a real project, which is exactly how the drift it now guards
against was introduced.

**Wireframes** follow the same mark/flush/gate rule, filtered further: only re-render a wireframe when
the decision changes something *visually observable* (new field, button, flow, state/color) — not for
logic-only changes invisible in the UI.

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
