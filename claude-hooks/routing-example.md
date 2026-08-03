# Agent Routing & Model Selection — Example Template

This is an example template. Copy it to a personal location (e.g. `~/.claude/routing.md`)
and replace the model names with the ones available on your setup.

---

## Philosophy

- Use the cheapest model that produces acceptable quality for the task
- Escalate to a stronger model only when the cheaper one fails or the task is genuinely hard
- One agent orchestrates; others implement or research

---

## Orchestrator (e.g. Claude)

| Task | Model tier | When to escalate |
|------|-----------|-----------------|
| Orchestration, gates, standard decisions | Mid-tier (default) | — |
| Architecture, ambiguous judgment, complex review | High-tier | When mid-tier hedges or misses nuance |
| Mechanical tasks (simple scaffolding) | Low-tier | When output quality is too low |

---

## Implementation agent (e.g. Codex, another coding model)

| Task | Model tier | When to escalate |
|------|-----------|-----------------|
| High-volume boilerplate | Low-tier | When syntax errors appear repeatedly |
| Standard implementation | Mid-tier (default) | When logic is non-trivial |
| Complex logic, hard integrations | High-tier | — |

**Default:** start mid-tier. Drop to low for bulk, escalate to high for hard tasks.

---

## Research/analysis agent (e.g. Gemini, long-context model)

| Task | Model tier | When to escalate |
|------|-----------|-----------------|
| High-volume doc reads, extraction | Low-tier | When extraction quality is poor |
| Standard analysis | Mid-tier (default) | When depth is insufficient |
| Critical deep analysis | High-tier | Only when flash models miss key details |

---

## Cost escalation rule

Before escalating to a stronger model, try once more with a better prompt or smaller scope.
Escalate the model only when the task is genuinely beyond the cheaper tier's capability.
