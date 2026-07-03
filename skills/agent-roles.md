# Agent Roles — Draft / Gate / Test Split for mxcli Projects
**Purpose:** How to generate a project's `.claude/agents/*.md` subagent definitions so MDL drafting, post-exec verification, and UI testing are separate agents with separate tool rights — instead of one agent doing everything, including unreviewed writes to the `.mpr`.
**Companion skills:** `iterative-build-loop.md` (the gate/build/test discipline this pattern makes executable), `mdl-cookbook-microflows.md`, `bug-logs/mxcli-bugs.md`, `test-app.md`
**Source:** Generalized from three project-specific agents built for a live mxcli project (IVM-MxCLI-main), after real use.

---

## When to Use This Skill

- You're starting a new mxcli-based Mendix project and want repeatable dev-loop discipline from day one, not something you back into after a mutation mistake.
- You're asked to "set up agents for this project" or "create dev-process agents" on a fresh repo.
- An existing project's agents feel ad hoc or over-permissioned (e.g. one agent can both write MDL and run `mxcli exec`).

**This is a generation guide, not a copy-paste template.** The three example bodies below are illustrative shapes — read the target project's own CLAUDE.md and skills first, then write agent files that match *that* project's actual commands, paths, and tooling. A gate-agent pointed at the wrong `.mpr` filename or a stale compile-gate command silently verifies nothing.

---

## Why split into three roles

A single do-everything agent has no natural place to stop before mutating the real `.mpr`. Splitting by role makes the boundary structural instead of a hope:

| Role | Job | Runs `mxcli exec`? | Can write files? |
|------|-----|---------------------|-------------------|
| **mdl-agent** | Draft + syntax-validate MDL scripts against the project's BRDs/specs and skill references | No — validates with `mxcli check` only | Yes, but only `.mdl` script files under the project's script folder, via `Bash` (no `Write`/`Edit` tool) |
| **gate-agent** | Run the project's build/quality gates (model check, compile gate, lint) *after* the main session has already executed a script | No | No — read-only/verification-only |
| **test-agent** | Walk UI test scenarios against the running app, cross-check against the database | No | No — read-only/verification-only |

**The one rule that matters more than any other: only the main session (the one talking to the user) ever runs the command that mutates the real `.mpr`.** All three subagents get `tools: Read, Grep, Glob, Bash` — never `Write`/`Edit`. `mdl-agent` still needs to produce files, but it does so via `Bash` (shell redirection/heredoc), not the `Write` tool — that keeps "can this agent silently overwrite something outside its lane" a visible, auditable choice in its tool list rather than an assumption.

This mirrors `iterative-build-loop.md`'s gate discipline (0 CE errors + happy path + full field coverage, verified *after* every script) and keeps the human-in-the-loop confirmation on `mxcli exec` that the main session already provides — subagents draft and verify, they don't get to skip that checkpoint.

---

## How to generate these for a new project

1. **Read the target project first**: its `CLAUDE.md`, `.ai-context/skills/` (or equivalent), and whatever it uses for build verification (mx check / mxbuild / lint), UI testing (Playwright integration, demo users), and business-rule source (BRDs, a requirements doc, or none yet). Don't guess any of this — if the project has no test setup yet, say so instead of inventing one.
2. **Write three files** to `.claude/agents/`: `mdl-agent.md`, `gate-agent.md`, `test-agent.md`, adapting the shapes below — substitute every project-specific detail (mpr filename, exact check/compile/lint commands, skill file names, BRD/spec location, demo user, known gotchas) for the real ones you just read.
3. **Preserve the tool scoping exactly**: `tools: Read, Grep, Glob, Bash` on all three, and an explicit line in each stating it never runs `mxcli exec` / never mutates the `.mpr` directly.
4. **Report back** which three files you wrote, and flag any assumption you had to make because the project didn't document something (e.g. "assumed the demo user is X — couldn't find one specified, confirm").

---

## Template shapes (adapt, don't copy verbatim)

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

## Workflow
1. Read the task spec (which elements, which business rules apply).
2. Read the necessary skill file(s), spec, and existing MDL for exact names.
3. Write the script to {{SCRIPT_PATH}}.
4. Run `mxcli check <path> -p {{PROJECT_MPR}} --references` and iterate until clean.
5. Do NOT run `mxcli exec` — that stays in the main session under the user's confirmation.

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

- **Don't give any of these three agents `Write`/`Edit` directly.** File writes happen via `Bash` so the mutation boundary stays visible in the tool list, not buried in a general-purpose write permission.
- **Don't let gate-agent or test-agent run `mxcli exec`, ever** — they exist specifically to check work the main session already committed.
- **Don't copy the template shapes above verbatim into a new project.** A gate-agent checking the wrong `.mpr` filename, or a test-agent logging in as a demo user that doesn't exist in this project, will report false confidence instead of failing loudly.
- **Don't build all three on day one if the project doesn't need them yet.** A project with no MDL scripting underway yet doesn't need a gate-agent; add each agent when its corresponding stage of `iterative-build-loop.md` actually starts.
