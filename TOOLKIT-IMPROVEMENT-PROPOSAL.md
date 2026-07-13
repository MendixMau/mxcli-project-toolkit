# Toolkit Improvement Proposal — Interview-Driven Conversion Pipeline

**Status:** Proposal for review. Nothing in `skills/`, `pipelines/`, or `README.md` has been changed yet.
**Trigger:** A colleague's `CONVERSION-RUNBOOK.md` supplied the missing gate layer; reviewing it surfaced what the toolkit is actually missing.
**Goal:** A person clones the toolkit, points it at any source, and the pipeline *interviews them* through to a running Mendix app — with every gate producing a customer-showable artifact and every decision recorded.

---

## 1. The diagnosis

The toolkit has strong knowledge and no spine.

Each stage has an owning skill, and each skill is good. But nothing says *what a stage must produce before the next one starts*, nothing says *what the user has to decide*, and nobody's job is to ask them. The result: a stage "completes" when the agent stops typing, not when a decision is on record.

Three specific holes:

1. **No deliverables-and-gates layer.** Searching all 29 skills for "deliverable" returns one incidental hit. Only `modularize-domain.md` has a real gate (rationale HTML + sign-off) — and its shape is exactly right, it was just never generalized to the other stages.
2. **No interviews.** Where the user is needed, the toolkit says "get sign-off" — a yes/no on something already built. It never *proposes options with evidence and asks the user to correct them*. `modularize-domain.md` again is the sole exception, closing with "Does this match how your teams and processes are actually organized?"
3. **No owner for discovery.** `agent-roles.md` defines three agents — mdl, gate, test — **all build-phase**. Stages 0–4 (analysis, requirements, architecture, planning) have no agent role at all. That's the mechanical reason the interviews never happen.

Plus a structural observation that cuts across everything: **roughly half the toolkit isn't about migration.** `iterative-build-loop`, `learned-mdl-preflight`, `learned-mcp-patterns`, `learned-page-patterns`, `learned-db-assertions`, `learned-skill-ux-audit`, `e2e-harness-base`, `agent-roles`, `bootstrap-project`, `design-artifacts`, `architecture-blueprint`, `mdl-cookbook-microflows` and the bug logs apply to **any** mxcli Mendix project. Stages 5–6 of a conversion aren't migration steps — they're the Mendix build discipline, which greenfield needs identically.

---

## 2. Decisions taken (settled — recorded so we don't relitigate)

| Decision | Choice | Rationale |
|---|---|---|
| Project workspace | **Outside the toolkit clone** | Keeps the existing Project Workspace Convention. Rejects the runbook's in-clone model, which forces one-conversion-per-clone, mixes client source into a repo you `git pull`, and needs a "tracked file you must never commit" exception for `config.json`. |
| Delivery | **Skill + thin runbook** | `conversion-runbook.md` (agent-executed, stops at gates) + a short root runbook that lists stages and how to start. The gate is the gate — not the act of a human pasting a prompt. |
| Extraction | **Always stand up an extractor. Reuse where available, build new per stack.** | Field finding: reading source without an extractor missed information even on small apps. The extractor *is* the coverage gate. `source-triage.md`'s three-way call collapses to two-way (reuse vs build new); the manual-only path is removed. |
| Scope | **Whole source is in scope; a slice is an ordering, not an exclusion** | Sharper than today's "bounded scope subset." Taken from the runbook. |
| Colleague's doc | **Merge into the toolkit; English authoritative** | We can't own a doc whose truth lives in a Korean original. |
| Co-definition | **Per-stage inputs, asked when actionable** | No upfront mega-questionnaire. You can't sensibly answer stage-5 questions before stage 1 has told you anything. |
| Interview UX | **Terminal Q&A + HTML artifact** | Multiple-choice questions with a recommendation and evidence in the terminal; the decision is written into that stage's HTML proposal doc. Fast to answer, permanent record, customer-showable. |
| Unknowns | **Default + record assumption + proceed** | Agent applies its recommended option, marks it `ASSUMED` with the risk if wrong, and moves on. A solo run never stalls; assumptions stay visible. |
| Skill scope | **Tag, don't move** | Add `Applies to: migration \| any mxcli project` per skill; split the routing tables. No files move, no cross-references break. |
| JS runtime | **node / npm** | All three pipelines ship `package-lock.json`; both READMEs say `npm install`. The runbook's `bun` is a gratuitous switch. |

---

## 3. The interview protocol — how a gate works

This is the thing that should stand out about the pipeline. Every gate runs the same shape:

1. **The agent does its homework first.** It never asks what it can derive. Anything answerable from the source, the extraction, or the model must be answered from there. (The intake rule already enforces this: `"Unverified — how to verify: …"`, never a guess.)
2. **The agent proposes, with evidence.** 2–4 concrete options, a recommendation, and *why* — citing the artifact that supports it ("your source has 4 auth roles, 3 of which are never checked; I recommend collapsing to 2").
3. **The agent states its assumptions out loud** — the list of things it took for granted to reach that recommendation, so the user can correct the premise, not just the conclusion.
4. **The user answers in the terminal** (multiple choice; "other" always available).
5. **The decision is written to two places**: the stage's HTML proposal doc (the artifact) and `PROJECT.md` (the register), marked `CONFIRMED`.
6. **If the user doesn't know**: the recommended option is applied, marked `ASSUMED` in `PROJECT.md` with the risk if wrong, and the run continues.

A proposal beats a questionnaire because it asks the user to **correct** something rather than supply it cold — and by the time each gate arrives, the agent has read the source and has evidence to put behind its recommendation.

---

## 3b. Query before you ask, and query before you write — **new skill: `query-the-model.md`**

Step 1 of the interview protocol ("never ask what you can derive") only works if the agent knows *where to look*. That's not written down anywhere at toolkit level today, and it's the same root cause as the missing BA agent: nobody owns discovery.

**Every question has exactly one right source. Answering from the wrong one is how the pipeline goes quietly wrong.**

| The question is about… | Answer it from | Never from |
|---|---|---|
| What the legacy system *does* | Extracted KB JSON + the source itself | The BRD (it's derived — a summary, not evidence) |
| What the legacy system *means* (intent, business rules, why) | KB docs → then the SME interview (Path C) | The code alone. Intent isn't in code, and inventing it is the single worst failure mode. |
| What the Mendix model *currently contains* | **Query it**: `SHOW ENTITIES`, `DESCRIBE ENTITY`, `SHOW ASSOCIATIONS`, `SEARCH`, catalog OQL | The BRD or the build plan — those say what was *planned*, not what exists. Drift is guaranteed. |
| Blast radius of a change | `SHOW CALLERS / CALLEES / IMPACT OF` | Reading files and hoping |
| A decision (boundaries, buy-vs-build, roles, volumes) | **The user** — via a proposal with evidence | Yourself, silently |

**Two query rules that are already load-bearing and undocumented as a discipline:**

- **`SHOW ASSOCIATIONS` before every `CREATE ASSOCIATION`.** MDL has no `IF NOT EXISTS`; re-running a CREATE silently duplicates the association and mxbuild then throws CE0065/CE0069. (This is STOP rule 8 — currently visible only to someone reading the preflight table.)
- **`SHOW ENTITIES IN <MarketplaceModule>` before writing a single line against a marketplace module.** `mxcli check --references` cannot validate a reference into a module that isn't imported yet, so guessed names produce scripts that look right and fail. (Buried in `brd-to-build-plan.md`.)

**Read is always safe; write goes through the STOP table.** Queries (`SHOW`, `DESCRIBE`, `SEARCH`, catalog OQL) never corrupt anything and can run on any path. That asymmetry is why "query first" costs nothing and is worth making a rule.

Cheap, and it turns three scattered facts into one habit: **query the model → read the source → ask the human. In that order, and never skip to the last one.**

---

## 4. The stage matrix

Eight stages. For each: what the user co-defines, what the agent produces, the review surface, the gate, and who owns it.

### Stage P — Kickoff

| | |
|---|---|
| **User defines** | Which source folder. Licence/security constraints on storing the client source. Is an SME available, and who? |
| **Agent produces** | Workspace scaffold (init script), `CLAUDE.local.md` (paths, tools, routing), `PROJECT.md` (empty register), the 5 subagents, `intake.md` (8 questions, no guesses). |
| **Surface** | `index.html` (the project dashboard — created here, grows every stage) |
| **Gate** | Every intake question has an answer or an explicit "Unverified — how to verify". No blanks. |
| **Owner** | ba-agent |

### Stage 0 — Triage ✋

| | |
|---|---|
| **User defines** | Reuse-vs-build-new pipeline (agent proposes with a coverage matrix). Policy per missing dependency: acquire / stub / declare-not-implemented. Slice ordering if the source is too big for one pass. |
| **Agent produces** | `assessment.md` (inventory, 6 areas, risks), `triage.md` (pipeline decision, capability + coverage matrix, boundary handling, multi-app flag). If "build new": the new pipeline, validated against hand-built ground truth. |
| **Surface** | `triage.html` — **new** |
| **Gate ✋** | User signs off on the pipeline decision and every missing-dependency policy. No BRDs before this. |
| **Owner** | ba-agent |

### Stage 1 — Analysis

Three extraction methods, not two. Each is either **done** or **explicitly declared unavailable by a named person** — never silently skipped.

| | |
|---|---|
| **User defines** | Do documents exist that aren't in the folder (specs, manuals, field-label sheets, screenshots)? DB schema? Sample data? Who has them? SME access for what neither code nor docs answer. |
| **Agent produces** | **Path A — code → AST extractors** (always runs). **Path B — documents → LLM extraction** (`kb-generation.md`). **Path C — SME interview** *(new — today the intake asks whether an SME exists, then never uses them; the SME is the third source and the one that closes `openQuestions`)*. |
| **Surface** | `extraction-report.html` (exists) |
| **Gate** | 4 extraction quality checks pass with evidence. Paths B and C are done or declared-unavailable, with attribution. |
| **Owner** | ba-agent |

### Stage 2 — Requirements

| | |
|---|---|
| **User defines** | Confirms business rules the code implies. Answers `openQuestions` (via SME). Narrative is never invented. |
| **Agent produces** | BRD scaffolds → enrichment from `KB.md` → validation to clean. `F{NNN}.brd.json`. |
| **Surface** | `enrichment-summary.html` — **exists in java-angular only; port to outsystems + node-express-react** |
| **Gate** | Every BRD validation-clean; `validation-report.md` has 0 issues; open questions are chased, not merely logged. |
| **Owner** | ba-agent |

### Stage 3 — Architecture & Design ✋

The biggest gap today. Wiring diagrams, module definitions and fit-gap already exist and are good. Four things are missing entirely.

| | |
|---|---|
| **User defines** | ① One Mendix app or several (if flagged). ② **Module boundaries** (agent proposes with criteria). ③ **Buy vs build vs stub, per fit-gap item** — *new; today `brd-to-build-plan.md` Step 0 imports "confirmed" marketplace modules, but nothing in the toolkit ever does the confirming*. ④ **Target security / role model** — *new; intake asks whether auth exists in source, never what the target should be*. ⑤ **Data volumes, concurrency, NFRs** — *new; zero mentions anywhere in the toolkit today, and they decide indexing, pagination, datagrid-vs-paged-gallery, loop batch sizes*. ⑥ **Integration contracts** — *new; real or stub, endpoint, credentials, owner, test environment*. ⑦ **Branding inputs** — *`design-artifacts.md` already says to request logo/palette/type/spacing from the client; no stage ever asks*. |
| **Agent produces** | `.mx-brd.json`, `architecture/` (module defs, layer diagram, wiring diagram, `fit-gap.md`), `design/` (`design-system.html`, annotated wireframes). |
| **Surface** | `module-design.html` (exists) · `architecture.html` — **new** · `design-system.html` + `wireframes/*.html` (exist) |
| **Gate ✋** | Boundaries approved. Marketplace calls made. Role model, volumes, integrations and branding either confirmed or recorded as `ASSUMED` with risk. |
| **Owner** | architect-agent (interviews run by ba-agent) |

### Stage 4 — Build Plan ✋

| | |
|---|---|
| **User defines** | **Acceptance criteria per module** — what "done" means beyond CE-error-free. **Environment / DTAP / deployment target** — *new, absent today*. Iteration granularity. |
| **Agent produces** | `architecture/build-plan.md` — numbered, dependency-ordered (marketplace imports → entities → associations → microflows → pages → demo users/roles), with pending decisions promoted to the top. |
| **Surface** | `build-plan.html` — **new** |
| **Gate ✋** | Pending-decisions list empty or fully answered. User approves. |
| **Owner** | architect-agent |

### Stage 5 — Build

**This stage is not migration-specific.** It is the standard Mendix build discipline, and the runbook should *point at it*, not re-describe it. Already well codified: layer1 (entities/associations/enums, `security-setup.mdl` last) → layer2 (microflows) → layer3 (pages); the guard chain (uncommitted → SP-open → concurrent-writer → snapshot → exec → mxbuild gate → auto-restore → manual SP reopen); the stale-build protocol; the 11 STOP conditions.

| | |
|---|---|
| **User defines** | Confirms the per-module **business-rule coverage checklist** — *new. `process-learnings.md` §C already identified this ("this checklist becomes the definition of 'done' for the module, not CE-error-free") and asked "who owns the coverage checklist review?" Nobody ever built it.* |
| **Agent produces** | Working modules, one at a time, each passing the build loop's gates. |
| **Surface** | `ux-review-*.html` (exists) |
| **Gate** | Every build-plan script passes its gates **and** its coverage checklist. CE-error-free ≠ done. |
| **Owner** | mdl-agent → gate-agent |

### Stage 5.5 — Data Migration & Cutover — **new, absent from the toolkit entirely**

| | |
|---|---|
| **User defines** | Is legacy data migrated, seeded, or dropped? Who cuts over, and when? Rollback plan? |
| **Agent produces** | Migration/seed scripts, cutover checklist. |
| **Gate** | Decision recorded in `PROJECT.md` — even if the decision is "throw it away". |
| **Owner** | ba-agent → mdl-agent |

### Stage 6 — Test

Also not migration-specific — the shared E2E discipline.

| | |
|---|---|
| **User defines** | Test scope beyond the golden path; which edge cases matter. |
| **Agent produces** | Playwright golden-path + edge-case tests, DB assertions, results reported verbatim. |
| **Surface** | `test-report.html` — **new** |
| **Gate** | Golden path + edge cases + DB assertions pass. Failures fixed and re-run. |
| **Owner** | test-agent |

### Wrap-up

Promote proven patterns into `skills/learned-*.md`. **Runbook defects** — every point where the pipeline's silence forced an improvised decision — get fixed in the template, not worked around locally. New mxcli bugs into the bug log. Archive the project workspace.

---

## 5. The three project files (no overlap)

| File | Job | Lifetime |
|---|---|---|
| `CLAUDE.local.md` | Machine context: absolute paths, tool versions, skill routing. What agents auto-load every session. | The conversion |
| **`PROJECT.md`** *(new)* | The human record: scope, dependencies (missing source deps, marketplace, integrations), every decision with its options and rationale, assumptions marked `ASSUMED` / `CONFIRMED`, open questions. Written at every gate. **Absorbs today's `architecture/open-issues.md`.** | Outlives the build |
| `architecture/build-plan.md` | The executable sequence the build loop consumes and ticks off. | Dies when the build finishes |

`fit-gap.md` stays separate from `PROJECT.md` — it's analysis, not decisions.

---

## 6. Agents — two new roles

Today: mdl / gate / test. All build-phase. Stages 0–4 have no owner, which is why the interviews don't happen.

- **`ba-agent`** *(new)* — owns discovery and the interviews. Runs the proposal-and-question loop at every gate, maintains `PROJECT.md`, chases `openQuestions` to closure, conducts the SME interview (Path C), turns answers into BRD enrichment. **This is the keystone: without it, the co-definition layer stays theoretical.**
- **`architect-agent`** *(new)* — owns modularize → blueprint → fit-gap → build plan. Hard rule: never touches mxcli.
- `mdl-agent` / `gate-agent` / `test-agent` — unchanged. Drafting, gating and testing stay separate hands.

---

## 7. The README rewrite

The current README explains the toolkit to someone who already knows it. It needs to explain it to someone who just cloned it. Proposed structure:

1. **What this is, in three sentences** — and the fact that it serves *two* audiences: migrations (all stages) and greenfield Mendix builds (stages 5–6 only).
2. **Quickstart** — clone, run the init script, open the agent, answer the questions. Show the folder layout it creates, in the user's own workspace root:
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
3. **The stage table** — eight rows: what you'll be asked, what you get, what the gate is.
4. **Decision flow: query vs build.** Before writing anything: *query the model → read the source → ask the human*, in that order (§3b). Reads are free and safe; writes are not.
5. **Decision flow: mxcli vs MCP vs Studio Pro GUI.** The knowledge exists (`learned-mdl-preflight.md`'s three write paths + 11 STOP rules) but it's buried in a `learned-*` skill where a new user will never find it before they need it. Surface it as a flow:
   ```
   Write MDL  →  check the STOP table
                   ├─ clean            → mxcli exec (SP closed)
                   ├─ STOP → MCP       → mxcli --mcp exec (SP open) — bypasses the BSON serializer
                   ├─ STOP → GUI       → Studio Pro by hand (settings, security-bearing drops)
                   └─ no MDL syntax    → hand-rolled MCP (pg_patch_page)
   Crashed anyway? → bin/restore-mpr.sh  (restores .mpr AND mprcontents/ — either alone is useless)
                   → log it in bug-logs/mxcli-bugs.md
   ```
6. **The crash net, stated plainly.** An MPR is two parts: `Project.mpr` (SQLite index) and `mprcontents/` (BSON units with the actual model). `bin/exec.sh` snapshots **both** automatically before every batch; 5 rotate; `bin/restore-mpr.sh` rolls back; git commits at phase gates are the real history. Ad-hoc `.mpr.backup` copies are banned.
7. **Routing tables, split by "Applies to"** — Migration vs Any mxcli project.
8. **Baseline routing** — unchanged, still the always-on discipline.

Plus **`toolkit-guide.html`** at the repo root: a self-contained onboarding page opened when a conversion starts — the stages, what each gate needs *from you*, where artifacts land, which pipeline exists for your stack. It doubles as the shared shell and token source for every stage HTML (which is how the "one gate = one HTML surface" convention stops being a promise).

---

## 8. HTML review surfaces — make the convention real

It exists in fragments: `extraction-report.html` (all pipelines), `enrichment-summary.html` (**java-angular only**), `module-design.html`, `design-system.html` + wireframes, `ux-review-*.html`. Missing at triage, build plan, and test. Two defects:

- **Chicken-and-egg:** `modularize-domain.md` tells you to reuse `design-system.html`'s CSS variables — but stage 3a runs *before* 3c creates that file. Fix: neutral bootstrap tokens ship with `toolkit-guide.html` and are superseded by `design-system.html` once it exists.
- **Client name leak:** `learned-skill-ux-audit.md` says "the Stockpilot standard location" / "Stockpilot tokens". Strip it.

Target: **one gate = one HTML artifact, shared shell, all linked from `index.html`** — the project dashboard, and the thing you actually show a customer.

---

## 9. What I'd change, concretely

**New files**
- `skills/conversion-runbook.md` — the stage matrix + the interview protocol. The spine.
- `skills/query-the-model.md` — query the model → read the source → ask the human (§3b). Applies to any mxcli project, not just migrations. Baseline-routing worthy.
- `CONVERSION-RUNBOOK.md` (root) — thin: stages, how to start, pointer to the skill. English authoritative.
- `toolkit-guide.html` — onboarding page + shared HTML shell/tokens.
- `bin/init-project.sh` — creates the workspace, `CLAUDE.local.md`, `PROJECT.md`, the agents, `index.html`.
- `TOOLKIT-IMPROVEMENT-PROPOSAL.md` — this file (delete once merged).

**Changed**
- `README.md` — rewrite per §7.
- `agent-roles.md` — add `ba-agent`, `architect-agent`.
- `source-triage.md` — three-way call → two-way (reuse vs build new); record the extractor-as-coverage-gate rationale; adopt "a slice is an ordering, not an exclusion".
- `architecture-blueprint.md` — add marketplace buy-vs-build evaluation, security/role model, NFRs & data volumes, integration contracts.
- `brd-to-build-plan.md` — Step 0 now *consumes* the stage-3 marketplace decision instead of assuming someone made it; add acceptance criteria + environment/DTAP.
- `iterative-build-loop.md` — add the per-module business-rule coverage checklist as the definition of done (closes `process-learnings.md` §C and its open question).
- `design-artifacts.md` — branding inputs become a real interview, not a footnote.
- `migration-pipeline.md` — defer stage/gate ownership to `conversion-runbook.md`; stop duplicating.
- `learned-skill-ux-audit.md` — strip the client name.
- All skills — add `Applies to: migration | any mxcli project`; split the routing tables accordingly.
- `pipelines/outsystems/` + `pipelines/node-express-react/` — port `generate-enrichment-report.js`.

**Harvested from the colleague's runbook** (credit where due — these are good and we don't have them):
- Vendor/customization classification **at file granularity with evidence**, never blanket folder exclusion — vendor folders carry project customizations, and vendor originals stay as reference for interpreting screen definitions.
- **"An improvised decision is a runbook defect"** — fix the template, don't work around it locally.
- The **8 intake questions**.
- `CLAUDE.local.md` as the project context file.
- "A slice is an **ordering**, not an **exclusion**."

**Housekeeping**
- `pipelines/node-express-react/` is untracked and invisible — register it in the README and CLAUDE.md tables, give it the `README.md` and `source-node-express-react.md` its own bootstrap checklist requires. Its `enrichers/` (Cypress use-case enrichment) is a capability the generic pipeline spec doesn't yet account for.
- Commit or drop the working-tree changes to `README.md`, `iterative-build-loop.md`, `learned-mdl-preflight.md`, the bug log, and the deleted `learned-skill-migrate-general.md`.

---

## 10. Suggested order

1. `conversion-runbook.md` + `toolkit-guide.html` + `bin/init-project.sh` — the spine and the front door.
2. `agent-roles.md`: `ba-agent` + `architect-agent` — otherwise the interviews have no owner.
3. README rewrite.
4. The four stage-3 additions (marketplace, security, NFRs, integrations) and stage-5's coverage checklist — the real content gaps.
5. Reconciliations (`source-triage`, skill tagging, npm) + housekeeping.
6. Run a real source end-to-end. Every point where the pipeline forces an improvised decision is a defect — fix it here, not in that project.

---

## 11. Still open

- Feedback to the colleague: what we took, and the two rules we rejected (in-clone workspace, `bun`) with reasons.
- Whether `bin/init-project.sh` should also clone/register the chosen pipeline, or leave that to stage 0 once triage has picked one. Leaning: stage 0 — the init script shouldn't guess the stack.
