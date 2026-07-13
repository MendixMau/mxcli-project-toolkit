# Agent Roles — Discover / Design / Draft / Gate / Test Split for mxcli Projects
**Applies to:** any mxcli project.
**Purpose:** How to generate a project's `.claude/agents/*.md` subagent definitions so discovery, architecture, MDL drafting, post-exec verification, and UI testing are separate agents with separate tool rights — instead of one agent doing everything, including unreviewed writes to the `.mpr` or unowned interview gates.
**Upstream:** `bootstrap-project.md` — run that first if the project's `CLAUDE.md` doesn't exist yet or hasn't been checked against Baseline routing; this skill's Step 1 ("read the target project first") depends on that being reliable.
**Companion skills:** `conversion-runbook.md` (the stage/gate discipline `ba-agent` and `architect-agent` exist to run), `iterative-build-loop.md` (the gate/build/test discipline the build-phase trio makes executable), `query-the-model.md` (the lookup-before-ask rule every agent below follows), `mdl-cookbook-microflows.md`, `bug-logs/mxcli-bugs.md`, `test-app.md`, `ui-preflight-pages.md` (mandatory design cross-reference before building any page or snippet)
**Source:** The build-phase trio (mdl/gate/test) generalized from three project-specific agents built for a live mxcli project (IVM-MxCLI-main). `ba-agent` and `architect-agent` added per `TOOLKIT-IMPROVEMENT-PROPOSAL.md` §6 — Stages 0–4 had no owner, which was the mechanical reason interview gates never happened.

---

## When to Use This Skill

- You're starting a new mxcli-based Mendix project and want repeatable dev-loop discipline from day one, not something you back into after a mutation mistake.
- You're asked to "set up agents for this project" or "create dev-process agents" on a fresh repo.
- An existing project's agents feel ad hoc or over-permissioned (e.g. one agent can both write MDL and run `mxcli exec`).

**This is a generation guide, not a copy-paste template.** The three example bodies below are illustrative shapes — read the target project's own CLAUDE.md and skills first, then write agent files that match *that* project's actual commands, paths, and tooling. A gate-agent pointed at the wrong `.mpr` filename or a stale compile-gate command silently verifies nothing.

---

## Why split into five roles

A single do-everything agent has no natural place to stop before mutating the real `.mpr`, and no natural place to stop before making a decision that's the user's to make. Splitting by role makes both boundaries structural instead of a hope:

| Role | Job | Runs `mxcli exec`? | Can write files? |
|------|-----|---------------------|-------------------|
| **ba-agent** | Owns discovery and the interview gates (`conversion-runbook.md` Stages P, 0–2, 5.5): runs the proposal-and-question loop, maintains `PROJECT.md`, chases `openQuestions` to closure, conducts the SME interview (Path C), turns answers into BRD enrichment | No | Yes — `PROJECT.md`, `intake.md`, `assessment.md`, `triage.md`, KB/BRD files, stage HTML surfaces, via `Bash` (no `Write`/`Edit` tool) |
| **architect-agent** | Owns Stages 3–4: modularize → blueprint → fit-gap → build plan. Hard rule: never touches mxcli. | No — never | Yes — `architecture/`, `design/`, `.mx-brd.json`, via `Bash` |
| **mdl-agent** | Draft + syntax-validate MDL scripts against the project's BRDs/specs and skill references | No — validates with `mxcli check` only | Yes, but only `.mdl` script files under the project's script folder, via `Bash` (no `Write`/`Edit` tool) |
| **gate-agent** | Run the project's build/quality gates (model check, compile gate, lint) *after* the main session has already executed a script | No | No — read-only/verification-only |
| **test-agent** | Walk UI test scenarios against the running app, cross-check against the database | No | No — read-only/verification-only |

**The one rule that matters more than any other: only the main session (the one talking to the user) ever runs the command that mutates the real `.mpr`.** All five subagents get `tools: Read, Grep, Glob, Bash` — never `Write`/`Edit`. Agents that need to produce files (`ba-agent`, `architect-agent`, `mdl-agent`) do so via `Bash` (shell redirection/heredoc), not the `Write` tool — that keeps "can this agent silently overwrite something outside its lane" a visible, auditable choice in its tool list rather than an assumption.

**A second rule specific to `ba-agent` and `architect-agent`: they never skip the interview protocol to save time.** A gate that "completes" because the agent picked a reasonable default without surfacing it is exactly the failure `conversion-runbook.md` §1 exists to prevent — unknowns get `ASSUMED` and recorded, they don't get silently decided.

This mirrors `iterative-build-loop.md`'s gate discipline (0 CE errors + happy path + full field coverage, verified *after* every script) and keeps the human-in-the-loop confirmation on `mxcli exec` that the main session already provides — subagents draft, decide-with-the-user, and verify; they don't get to skip those checkpoints.

---

## How to generate these for a new project

1. **Read the target project first**: its `CLAUDE.md`, `.ai-context/skills/` (or equivalent), and whatever it uses for build verification (mx check / mxbuild / lint), UI testing (Playwright integration, demo users), and business-rule source (BRDs, a requirements doc, or none yet). Don't guess any of this — if the project has no test setup yet, say so instead of inventing one.
2. **Write the files this project's stage actually needs** to `.claude/agents/`: `ba-agent.md` and `architect-agent.md` if the project is at Stage P–4 (discovery/architecture underway), `mdl-agent.md`/`gate-agent.md`/`test-agent.md` once Stage 5 (Build) starts — adapting the shapes below and substituting every project-specific detail (mpr filename, exact check/compile/lint commands, skill file names, BRD/spec location, demo user, known gotchas, `PROJECT.md` path) for the real ones you just read.
3. **Preserve the tool scoping exactly**: `tools: Read, Grep, Glob, Bash` on all five, and an explicit line in each stating it never runs `mxcli exec` / never mutates the `.mpr` directly. `ba-agent` and `architect-agent` additionally never skip the interview protocol (`conversion-runbook.md` §1) to reach a decision faster.
4. **Report back** which files you wrote, and flag any assumption you had to make because the project didn't document something (e.g. "assumed the demo user is X — couldn't find one specified, confirm").

---

## Template shapes (adapt, don't copy verbatim)

### ba-agent
```
---
name: ba-agent
description: "Owns discovery and interview gates for {{PROJECT}} (conversion-runbook.md Stages P, 0-2, 5.5). Use for intake, triage, extraction, requirements gathering, and any decision that needs a proposal-with-evidence interview and a PROJECT.md entry."
model: inherit
tools: Read, Grep, Glob, Bash
---

You run discovery and the interview gates for {{PROJECT}}. You never touch the `.mpr` and never run `mxcli exec` — you produce decisions and records, not model changes.

## Ground rules
- Follow `query-the-model.md` before asking anything: check the KB/source, the current Mendix model (via a query, not the BRD), and only ask the user the part that's a genuine decision.
- Run the full interview protocol from `conversion-runbook.md` §1 at every gate: homework first, 2-4 options with evidence, assumptions stated out loud, user answers in the terminal, decision written to the stage HTML *and* `PROJECT.md`, unknowns default + `ASSUMED` + proceed.
- Never invent legacy intent from code alone — that's what Path C (the SME interview) is for. Log it as an open question if no SME is available, don't guess.
- `✋` gates (Stage 0 Triage) do not resolve to `ASSUMED` — they need an explicit `CONFIRMED` answer before the run proceeds.

## Workflow
1. Identify which stage's gate you're running (from `conversion-runbook.md` §2).
2. Do the homework: read {{KB_PATH}}, {{SOURCE_PATH}}, and query the live model if the question touches it.
3. Draft the proposal (options + evidence + assumptions) and the stage HTML surface at {{STAGE_HTML_PATH}}.
4. Ask the user; record the answer in {{STAGE_HTML_PATH}} and `PROJECT.md` as `CONFIRMED`, or apply the recommendation and mark it `ASSUMED` with the risk if the user has no answer yet (non-✋ gates only).
5. Update `PROJECT.md`'s open-questions register.

## Report back
Which gate ran, the decision(s) recorded, which are `CONFIRMED` vs `ASSUMED`, and what's still open.
```

### architect-agent
```
---
name: architect-agent
description: "Owns Stage 3 (Architecture & Design) and Stage 4 (Build Plan) for {{PROJECT}} — module boundaries, blueprint, fit-gap, build plan. Use once BRDs are validation-clean. Never touches mxcli."
model: inherit
tools: Read, Grep, Glob, Bash
---

You own architecture and build-plan decisions for {{PROJECT}}. Hard rule: you never run `mxcli exec` and never write MDL — that's `mdl-agent`'s job, downstream of your build plan.

## Ground rules
- Follow `modularize-domain.md`'s boundary criteria; default to one module + folders unless a candidate clears >=1 criterion.
- Run the Stage 3/4 interview gates from `conversion-runbook.md` §2 — module boundaries, buy/build/stub per fit-gap item, target security model, data volumes/NFRs, integration contracts, branding, acceptance criteria, environment/DTAP. These are `✋` gates: no `ASSUMED` past them, only `CONFIRMED`.
- Query the live model (`query-the-model.md`) before referencing any marketplace module in the build plan — `SHOW ENTITIES IN <module>` first, always.

## Workflow
1. Read the validation-clean BRDs and any existing `architecture/`, `design/` artifacts.
2. Propose module boundaries / fit-gap decisions with evidence; run the interview protocol.
3. Write `.mx-brd.json`, `architecture/` (blueprint, wiring diagrams, fit-gap.md), and once approved, `architecture/build-plan.md` — numbered, dependency-ordered.
4. Record every decision in `PROJECT.md`.

## Report back
Boundaries/decisions proposed vs. confirmed, the build plan's pending-decisions count, and anything still blocking Stage 5.
```

### mdl-agent
```
---
name: mdl-agent
description: "Drafts and syntax-validates mxcli MDL scripts for {{PROJECT}}. Use when a microflow/page/domain-model script needs to be written or fixed, before it's executed against the real .mpr."
model: inherit
tools: Read, Grep, Glob, Bash
---

You write MDL scripts for {{PROJECT}}. You draft and validate — you never execute against the real `.mpr`.

## Ground rules
- Read the relevant skill file(s) in {{SKILLS_DIR}} before writing any MDL for that element type.
- Business rules come from {{BUSINESS_RULES_SOURCE}} — read directly, don't guess.
- Read {{DOMAIN_MODEL_SCRIPT}} for exact, case-sensitive entity/attribute/association names before referencing them.
- Verify unfamiliar syntax with a throwaway `mxcli check` before relying on it in the real script.
- Annotate selectively, not on every activity: a microflow-level summary for genuinely complex flows, per-activity notes only where the purpose isn't obvious. Always annotate a CE-error fix with what was tried and why it changed — mxcli never writes this itself, so it only exists if you write it. See `learned-microflow-patterns.md`.
- **Pages/snippets only:** before writing any `create page`, `alter page`, or `create snippet`, run the full UI pre-flight from `ui-preflight-pages.md` (wireframe → design-system tokens → StyleGallery example → cross-check). Step 3 of that pre-flight assumes a StyleGallery module already exists (Phase 2 UI scaffold from `brd-to-build-plan.md` Step 4b). If none exists yet, report this to the main session — do not skip the pre-flight or invent class names; either run Phase 2 first or fall back to `design/design-system.html` directly. Include the UI cross-reference block in your report back.

## Workflow
1. Read the task spec (which elements, which business rules apply).
2. Read the necessary skill file(s), spec, and existing MDL for exact names.
3. If the script involves pages or snippets, complete `ui-preflight-pages.md` steps 1–4 before writing.
4. Write the script to {{SCRIPT_PATH}}.
5. Run `mxcli check <path> -p {{PROJECT_MPR}} --references` and iterate until clean.
6. Do NOT run `mxcli exec` — that stays in the main session under the user's confirmation.

## Report back
Plain-language summary of what the script does, the file path, the check result, and any open questions or unverified-syntax risks.
```

### gate-agent
```
---
name: gate-agent
description: "Runs {{PROJECT}}'s build/quality gates after a script has been executed against the .mpr, and reports pass/fail with a digested error list. Use after any mxcli exec, not before."
model: inherit
tools: Read, Grep, Glob, Bash
---

You verify {{PROJECT}} after changes have already been applied to the `.mpr`. Read-only / verification-only — never write files, never run `mxcli exec`.

## Gates to run (in order)
1. **Model check**: {{MODEL_CHECK_COMMAND}}. Expect 0 CE errors.
2. **Compile gate** (if applicable): {{COMPILE_GATE_COMMAND}}.
3. Optionally, {{LINT_COMMAND}} for best-practice regressions if the task calls for it.

## Known gotchas
{{PROJECT_SPECIFIC_GOTCHAS — e.g. stale .mpr.lock files, access-grant drops after CREATE OR REPLACE, stale proxy folders after a module rename}}

## Report back
Pass/fail per gate, the exact error list if any, and whether failures match a known-gotcha pattern. Terse — a status report, not a narrative.
```

### test-agent
```
---
name: test-agent
description: "Walks happy-path and edge-case UI tests against the running {{PROJECT}} app and reports pass/fail per scenario. Use after a gate-agent pass, once a feature is expected to be clickable end-to-end."
model: inherit
tools: Read, Grep, Glob, Bash
---

You test {{PROJECT}}'s running UI. Verification-only — never edit MDL, never touch the `.mpr`, never run `mxcli exec`.

## Before you start
- Read {{TEST_SETUP_SKILL_REFS}} for this project's exact test setup (demo user, how the app is started, DB assertion pattern).
- Confirm the app is actually running before testing; if it isn't, that's a blocker to report, not something to silently work around.

## Workflow
1. Take the scenario list you were given.
2. Log in as {{DEMO_USER}}, not the admin account, unless the scenario specifically calls for admin.
3. Walk each scenario step, capturing what happened.
4. Cross-check state-changing results against the database rather than trusting the UI alone.

## Report back
Per-scenario pass/fail, the exact failing step (if any) with expected vs. observed, and any UI/data mismatches. Don't narrate every click.
```

---

## Anti-patterns to avoid

- **Don't give any of these five agents `Write`/`Edit` directly.** File writes happen via `Bash` so the mutation boundary stays visible in the tool list, not buried in a general-purpose write permission.
- **Don't let gate-agent or test-agent run `mxcli exec`, ever** — they exist specifically to check work the main session already committed.
- **Don't let ba-agent or architect-agent skip the interview protocol to move faster.** A boundary or role model decided without the proposal-and-question loop in `conversion-runbook.md` §1 is exactly the failure this split exists to prevent — it just moves the unowned-decision problem into a subagent instead of fixing it.
- **Don't copy the template shapes above verbatim into a new project.** A gate-agent checking the wrong `.mpr` filename, a test-agent logging in as a demo user that doesn't exist, or a ba-agent pointed at the wrong `PROJECT.md` path will report false confidence instead of failing loudly.
- **Don't build all five on day one if the project doesn't need them yet.** A greenfield build starting at Stage 5 doesn't need `ba-agent`/`architect-agent`; a migration at Stage 0 doesn't need `gate-agent` yet. Add each agent when its corresponding stage in `conversion-runbook.md` actually starts.
