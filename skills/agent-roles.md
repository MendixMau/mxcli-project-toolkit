# Agent Roles — Discover / Design / Draft / Gate / Test / Review Split for mxcli Projects
**Applies to:** any mxcli project.
**Requires:** bash and Python 3 — this skill runs toolkit shell scripts. Run `bin/doctor.sh` once on a new machine; it names anything missing and how to get it. Windows: use Git Bash, and see the Prerequisites section of `conversion-runbook.md`.
**Purpose:** How to generate a project's `.claude/agents/*.md` subagent definitions so discovery, architecture, MDL drafting, post-exec verification, and UI testing are separate agents with separate tool rights — instead of one agent doing everything, including unreviewed writes to the `.mpr` or unowned interview gates.
**Upstream:** `bootstrap-project.md` — run that first if the project's `CLAUDE.md` doesn't exist yet or hasn't been checked against Baseline routing; this skill's Step 1 ("read the target project first") depends on that being reliable.
**Companion skills:** `conversion-runbook.md` (the stage/gate discipline `ba-agent` and `architect-agent` exist to run), `iterative-build-loop.md` (the gate/build/test discipline the build-phase trio makes executable), `query-the-model.md` (the lookup-before-ask rule every agent below follows), `mdl-cookbook-microflows.md`, `bug-logs/mxcli-bugs.md`, `test-app.md`, `ui-preflight-pages.md` (mandatory design cross-reference before building any page or snippet)
**Source:** The build-phase trio (mdl/gate/test) generalized from three project-specific agents built for a live mxcli project (a Java/Angular analysis project). `ba-agent` and `architect-agent` were added because Stages 0–4 had no owner, which was the mechanical reason interview gates never happened. `review-agent` was added because `module-review.md` stage 4 had no owner either, which was the mechanical reason the LOOK never happened.

---

## When to Use This Skill

- You're starting a new mxcli-based Mendix project and want repeatable dev-loop discipline from day one, not something you back into after a mutation mistake.
- You're asked to "set up agents for this project" or "create dev-process agents" on a fresh repo.
- An existing project's agents feel ad hoc or over-permissioned (e.g. one agent can both write MDL and run `mxcli exec`).

**This is a generation guide, not a copy-paste template.** The example bodies (in `agents/README.md`) are illustrative shapes — read the target project's own CLAUDE.md and skills first, then write agent files that match *that* project's actual commands, paths, and tooling. A gate-agent pointed at the wrong `.mpr` filename or a stale compile-gate command silently verifies nothing.

**Discharging the `dispatch` obligation:** the mdl-agent logs every dispatch per Workflow step 8a — the log line, path (`.claude/loop/dispatch/<Module>/scripts.tsv`) and format are in `agents/README.md` step 8a; one line per dispatch, no denominator owed.

**Mechanical scaffolding exists:** `bin/init-agents.sh <session-root> [p|build|all]` copies stub versions of all **six** agents (from the toolkit's `agents/` folder) into the project's `.claude/agents/` — `p` for the Stage-P pair (ba/architect), `build` for the Stage-5 quartet (mdl/gate/test/**review**). The stubs are safe by construction: each refuses to run while `{{PLACEHOLDER}}`s remain, so "downloaded but never configured" fails loudly instead of verifying nothing. Your job after scaffolding is Steps 1–4 below: fill every placeholder from the *actual* project, including the **Domain context** block.

> **The count is load-bearing. It is six.** Failure when this file said "five": sessions left
> `review-agent` an inert stub, and a module review ran journeys, DB assertions and the monkey pass
> but never looked at a single page (2026-08-20, `process/baseline-incident-history.md` §AR1).

---

**When to dispatch, in what batch, on which tier:** `conversion-runbook.md` §1c is the single source. **How to dispatch** — the four harness defaults to override on every call — is `dispatching.md`. This file is the setup.

The `model:` line of every completed agent is pinned to the shipped stub at `agents/<name>-agent.md` (never inherited) — see `conversion-runbook.md` §1c for the tiers.

## Dispatching

Moved to `dispatching.md` (2026-10-13).

## Why split into six roles

A single do-everything agent has no natural place to stop before mutating the real `.mpr`, and no natural place to stop before making a decision that's the user's to make. Splitting by role makes both boundaries structural instead of a hope:

| Role | Job | Runs `mxcli exec`? | Can write files? |
|------|-----|---------------------|-------------------|
| **ba-agent** | Owns discovery and the interview gates (`conversion-runbook.md` Stages P, 0–2, 7): runs the proposal-and-question loop, maintains `PROJECT.md`, chases `openQuestions` to closure, conducts the SME interview (Path C), turns answers into BRD enrichment | No | Yes — `PROJECT.md`, `intake.md`, `assessment.md`, `triage.md`, KB/BRD files, stage HTML surfaces, via `Bash` (no `Write`/`Edit` tool) |
| **architect-agent** | Owns Stages 3–4: modularize → blueprint → fit-gap → build plan. Hard rule: never touches mxcli. | No — never | Yes — `architecture/`, `design/`, `.mx-brd.json`, via `Bash` |
| **mdl-agent** | Draft + syntax-validate MDL scripts against the project's BRDs/specs and skill references | No — validates with `mxcli check` only | Yes, but only `.mdl` script files under the project's script folder, via `Bash` (no `Write`/`Edit` tool) |
| **gate-agent** | Run the project's build/quality gates (model check, compile gate, lint) *after* the main session has already executed a script | No | No — read-only/verification-only |
| **test-agent** | Walk UI test scenarios against the running app, cross-check against the database | No | No — read-only/verification-only |
| **review-agent** | Owns `module-review.md` — the one pass that closes a module. Stage 3's model-side instruments (`bin/review-module.sh`: conformance + graph sweep) **and stage 4, the LOOK**: every page in the module assessed against wireframe, design system and plain design judgement. Diagnostic only — never fixes what it finds | No — never | Yes, but only its own report under `design/ui-reviews/`, via `Bash` |

**Who records a change, who flushes it.** A mid-build change or decision is *marked* by the lead: the `PROJECT.md` `## Change log` row, the decision row, any `[sync:]` marker. `mdl-agent` and `gate-agent` report it and never write `PROJECT.md`. `ba-agent` flushes BRDs and module briefs, and `architect-agent` flushes wireframes and `architecture/`. The single source is the Owners section in `change-intake.md`.

**The one rule that matters more than any other: only the main session (the one talking to the user) ever runs the command that mutates the real `.mpr`.** All six subagents get `tools: Read, Grep, Glob, Bash` — never `Write`/`Edit`. Agents that need to produce files (`ba-agent`, `architect-agent`, `mdl-agent`) do so via `Bash` (shell redirection/heredoc), not the `Write` tool — that keeps "can this agent silently overwrite something outside its lane" a visible, auditable choice in its tool list rather than an assumption.

**A second rule specific to `ba-agent` and `architect-agent`: they never skip the interview protocol to save time.** A gate that "completes" because the agent picked a reasonable default without surfacing it is exactly the failure `conversion-runbook.md` §1 exists to prevent — unknowns get `ASSUMED` and recorded, they don't get silently decided.

This mirrors `iterative-build-loop.md`'s gate discipline (0 CE errors + happy path + full field coverage, verified *after* every script) and keeps the human-in-the-loop confirmation on `mxcli exec` that the main session already provides — subagents draft, decide-with-the-user, and verify; they don't get to skip those checkpoints.

---

## How to generate these for a new project

1. **Read the target project first**: its `CLAUDE.md`, `.ai-context/skills/` (or equivalent), and whatever it uses for build verification (mx check / mxbuild / lint), UI testing (Playwright integration, demo users), and business-rule source (BRDs, a requirements doc, or none yet). Don't guess any of this — if the project has no test setup yet, say so instead of inventing one.
1b. **Fill the Domain context block** (ba/architect/mdl agents) from the Stage-P intake: customer industry, the app's one-sentence purpose, a 5–10 term glossary (source-system name = meaning), the SME, and pointers to where the truth lives (KB/BRD/`PROJECT.md` paths). Keep it *short and pointer-shaped*: the agent should know the customer's **language** and **where the truth lives** — never memorize the truth itself. Use cases, business rules, and open questions stay in `PROJECT.md`/KB/BRDs and are read fresh each run; baking them into the agent file means it silently goes stale as understanding evolves.
2. **Scaffold all six stubs** (`bin/init-agents.sh <session-root>`), then **complete the ones whose stage is live**: `ba-agent.md`/`architect-agent.md` at Stage P–4 (discovery/architecture underway), `mdl-agent.md`/`gate-agent.md`/`test-agent.md`/`review-agent.md` at Stage 5 (Build) kickoff — adapting the shapes below and substituting every project-specific detail (mpr filename, exact check/compile/lint commands, skill file names, BRD/spec location, demo user, known gotchas, `PROJECT.md` path) for the real ones you just read. Uncompleted stubs stay inert by design.
   **Paths are centralized in the `## Wiring` block of `CLAUDE.local.md`** — not per-agent. Agents read that block at task start and resolve every path (MPR, briefs, wireframes, design system, gallery, architecture, build plan) from it. At Stage 5 kickoff your job is to confirm the Wiring block is correct and every path in it resolves (the `build-ready` gate checks this), not to fill six placeholders in each agent. This removes the drift risk of six agents each carrying their own path copies.
3. **Preserve the tool scoping exactly**: `tools: Read, Grep, Glob, Bash` on all of them, and an explicit line in each stating it never runs `mxcli exec` / never mutates the `.mpr` directly. `ba-agent` and `architect-agent` additionally never skip the interview protocol (`conversion-runbook.md` §1) to reach a decision faster.

   **One deliberate exception:** `test-agent` also carries `Write, Edit`, because it authors test
   specs rather than only walking a scenario list someone else wrote. Its boundary is therefore
   stated by *directory*, not by tool: it may write under the project's test directory and the
   journey directory and nowhere else, and the never-`exec`/never-`.mpr` rule binds it exactly
   as it binds the others. Nothing fills `{{TEST_DIR}}` for you: set it to the directory the
   project's specs actually live in (`tests/e2e/` where `install-tests.sh` installed the engine;
   check, don't assume). Journeys go to `journeys/` at the project root, never under
   `{{TEST_DIR}}` and never relocated (`fixture-manifest.sh` reads only `journeys/`): a
   test-agent that wrote them to `tests/e2e/journeys/` left the Stage-6 journey row owed until
   the project symlinked `journeys/` (#359).
   Do not widen any other agent's tools by analogy — this one is scoped by what it produces.
4. **Report back** which files you wrote, and flag any assumption you had to make because the project didn't document something (e.g. "assumed the demo user is X — couldn't find one specified, confirm").

---

## Getting improvements back OUT of a project

Distribution only ever flowed downhill. `sync-project.sh` refreshes a **pure stub**, but the
moment an agent is completed it is never touched again — and there was no way to see what it had
learned. In practice a rewritten agent, a working lint rule and two new instruments all sat in
one project for a week, invisible to the toolkit, because nothing surfaced the divergence.

```bash
bin/sync-project.sh <project-root> --diff-completed
```

Report-only, in both directions, for every completed agent:

- **template-only lines** — the project is missing a template improvement it never received.
- **project-only lines** — a candidate for promotion upstream.

Expect placeholder-substitution noise on project-fact lines (glossary, paths, commands). What
matters is **protocol that exists on one side only**.

**Promoting is a split, not a copy.** A completed agent is a mixture of transferable protocol and
project fact. Move only the protocol into the template, and leave a `{{PLACEHOLDER}}` where the
fact was — the same discipline as the Domain context block in step 1b. If you find yourself
pasting a module name, an mpr filename or a demo user into `agents/`, you are promoting the wrong
half.

Run this before a toolkit review, and after any session that meaningfully changed how an agent
works.

---

## Template shapes (adapt, don't copy verbatim)

The illustrative body for each of the six roles — frontmatter, ground rules, workflow, report-back —
is in **`agents/README.md`**; read it when completing a stub (step 2 above). The shipped stubs
`agents/<name>-agent.md` are the live templates and win where the two disagree. The rules every
completed agent must keep regardless of shape are in this file: the tool scoping (step 3), the one
rule on `.mpr` mutation, and the anti-patterns below. ba-agent works in two modes — **extraction**
(Stages P–2: produce BRDs via the interview protocol) and **translation** (Stage 4: turn BRDs into
module briefs, just-in-time, module N after N−1 gates); having BRDs does not mean its job is done.

---

## Anti-patterns to avoid

- **Don't give any of these six agents `Write`/`Edit` directly.** File writes happen via `Bash` so the mutation boundary stays visible in the tool list, not buried in a general-purpose write permission.
- **Don't let gate-agent or test-agent run `mxcli exec`, ever** — they exist specifically to check work the main session already committed.
- **Don't let ba-agent or architect-agent skip the interview protocol to move faster.** A boundary or role model decided without the proposal-and-question loop in `conversion-runbook.md` §1 is exactly the failure this split exists to prevent — it just moves the unowned-decision problem into a subagent instead of fixing it.
- **Don't copy the template shapes (`agents/README.md`) verbatim into a new project.** A gate-agent checking the wrong `.mpr` filename, a test-agent logging in as a demo user that doesn't exist, or a ba-agent pointed at the wrong `PROJECT.md` path will report false confidence instead of failing loudly.
- **Scaffold all six on day one; don't *complete* an agent before its stage starts.** The stubs are inert (refuse-to-run while placeholders remain), so having all six in `.claude/agents/` from kickoff is safe and avoids the "where's my mdl-agent?" confusion. The discipline moves to completion time: fill ba/architect at Stage P, mdl/gate/test/review at Stage 5 kickoff — completing a gate-agent before any build exists means filling its commands from guesses, which is exactly the false-confidence failure the placeholders exist to prevent. (A greenfield build starting at Stage 5 may simply never complete ba/architect — that's fine, they stay inert.)
