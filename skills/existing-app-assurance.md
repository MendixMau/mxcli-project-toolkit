# Existing App Assurance — Audit & Regression-Test a Mendix App You Already Have
**Applies to:** any mxcli project — an existing Mendix app with nothing to migrate or build.
**Purpose:** The recipe for pointing this toolkit at an app that already exists: analyze it, lint it, and put a regression net under it. **No pipeline, no stages, no gates** — this is à-la-carte tool-shelf use; grab the track you need and go.
**Source:** Toolkit review 2026-07-14 — the `[any project]` skills always worked on existing apps, but nothing said so, and nothing routed the "I just want e2e tests / an audit" user anywhere.

---

## When to Use This Skill

- "Can you audit this Mendix app?" — quality, security, architecture boundaries.
- "Build a regression / e2e test suite for our existing app."
- Before a Mendix version upgrade or a big refactor: record what the app does *today* so you can prove it still does it afterwards.
- You inherited an app and need to understand it before touching it.

Not for building anything new — that's `conversion-runbook.md` (pick an entry mode there).

## Ground rules

- **Read-only by default.** Everything here is queries, lint, and tests — nothing writes to the `.mpr`. That's why no gates are needed.
- If the audit finds things worth *fixing*, that's a deliberate hop into the build discipline (`iterative-build-loop.md` + the STOP table), agreed with the user first — never a silent side-effect of the audit.
- A minimal `PROJECT.md` (decision register) is still worth keeping if findings lead to decisions; skip it for a pure test-suite job.

---

## Track A — Analyze / audit the model

| Question | Tool |
|---|---|
| What's in the model? | `SHOW MODULES / ENTITIES / ASSOCIATIONS`, `DESCRIBE ENTITY`, `SEARCH` — see `query-the-model.md` |
| Is it well-structured? | `mxcli graph-report` (community detection, dependency tangles) — `graph-analysis.md` (bundled) |
| Does it violate best practices / architecture boundaries? | `mxcli lint` + Starlark rules — `write-lint-rules.md` (bundled) for custom rules (naming, security, cross-module data) |
| Is it secure? | `manage-security.md` (bundled) as the reference; lint's `sec_*` rules; grep access rules via `DESCRIBE` |
| Overall quality scan | `assess-quality.md` (bundled) |

**Deliverable:** a findings report (markdown or HTML — reuse `toolkit-guide.html`'s tokens), each finding with evidence (the query/lint output) and a proposed disposition: fix now / log / accept. Triage the list *with the user* — dispositions are their call.

## Track B — Regression / e2e test net

1. Stand up the harness per `e2e-harness-base.md` (Playwright + demo user + app-start discipline).
2. Walk the app's real golden paths — derive scenarios from navigation + the user's "what must never break" list, not from guesses.
3. Add DB assertions (`learned-db-assertions.md`): the UI can lie about whether a create/update/delete landed; OQL can't.
4. Commit the suite **and the baseline**: "this is what the app does today, proven." That baseline is the acceptance yardstick for any future upgrade, refactor — or migration Stage 6.
5. Optionally generate `test-agent` for repeat runs: `bin/init-agents.sh <session-root> build` (use just test-agent; complete its placeholders per `agent-roles.md`).

**Deliverable:** a green, committed test suite + `test-report.html`.

---

## Why this exists as a named recipe

The toolkit's staged pipeline is for *producing* an app. But half the toolkit (`query-the-model`, `e2e-harness-base`, `learned-db-assertions`, lint rules, the bundled analysis skills) is just tools — and tools don't need a pipeline. This file is the router so "I just want tests/an audit" never gets funneled through intake questions it doesn't need.
