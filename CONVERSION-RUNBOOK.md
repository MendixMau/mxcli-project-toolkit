# Conversion Runbook — Start Here

This is the thin front door. The executable detail lives in **`skills/conversion-runbook.md`** — the stage matrix, the interview protocol every gate runs, and the done-checklist. This file only tells you how to start and what to expect.

**Prefer a visual walkthrough?** Open **`toolkit-guide.html`** in a browser (`open toolkit-guide.html`) — the same journey as a guided page, including the "something went wrong" section. Agents: open it *for* the user at Stage P kickoff.

---

## How to start

```bash
git clone https://github.com/MendixMau/mxcli-project-toolkit.git ~/Mendix/mxcli-project-toolkit
~/Mendix/mxcli-project-toolkit/bin/init-project.sh <project-root>
```

`<project-root>` is your project's own folder (usually its git repo) — scaffolding, analysis output, architecture, and the `.mpr` all live **inside** it. Never create a sibling `analysis/<project>/` next to the project.

Then open your agent (Claude Code or equivalent) in the workspace and say what you're starting from. The agent picks the **entry mode** (`skills/conversion-runbook.md` → "Entry Modes"):

| Starting from | Mode | Stages |
|---|---|---|
| Legacy source code | Migration | P, 0–7 |
| Requirements/specs only, no code | Requirements-driven | P, 1–6 |
| Just an idea / existing plan | Greenfield | P (light), 5–6 |

## What to expect

- The pipeline **interviews you** at every gate: the agent proposes 2–4 options with evidence from your actual source, states its assumptions, and asks you to correct it — it never asks what it can derive itself.
- If you don't know an answer, the run doesn't stall: the recommendation is applied and recorded as `ASSUMED` in `PROJECT.md` with the risk if wrong. Hard gates (`✋`) are the exception — those need an explicit `CONFIRMED` answer.
- Every stage ends with `bin/gate-check.sh <project-dir> <stage>` — a mechanical check that required artifacts exist, which also regenerates your project dashboard (`index.html`).
- Every decision ends up in exactly one place: **`PROJECT.md`**, your project's decision register.

## The stages at a glance

```
P  Kickoff        → intake + workspace scaffold
0  Triage ✋       → extractor reuse-vs-build decision, scope ordering
1  Analysis       → code extractors + document extraction + SME interview
2  Requirements   → validated BRDs
3  Architecture ✋ → module boundaries, buy-vs-build, security, NFRs, branding
4  Build Plan ✋   → numbered, dependency-ordered script plan
5  Build          → working modules, gated (CE-error-free ≠ done)
6  Test           → Playwright + DB assertions
7  Cutover ✋      → legacy data decision, rollback plan (migrations only)
```

Full detail, gates, owners and artifacts: `skills/conversion-runbook.md`.
