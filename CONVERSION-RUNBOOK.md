# Conversion Runbook — Start Here

This is the thin front door. The executable detail lives in **`skills/conversion-runbook.md`** — the stage matrix, the interview protocol every gate runs, and the done-checklist. This file only tells you how to start and what to expect.

**Prefer a visual walkthrough?** Open **`toolkit-guide.html`** in a browser (`open toolkit-guide.html`) — the same journey as a guided page, including the "something went wrong" section. *Agents:* open it for the user only under the first-touch rule in `CLAUDE.md` (sentinel `<project-root>/.claude/.guide-shown` absent), never once per session.

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

## Where you run this — pick one, or take the default

Every stage of this pipeline runs **headless**: the build gate is `mxbuild` (a plain binary),
`mxcli new` creates the app, `mxcli run --local` serves it, Playwright and OQL test it. Studio Pro
is never on the critical path. So the only question is *which machine*:

| Option | What you need | What you get | Pick it when |
|---|---|---|---|
| **A — Cloud container** (Claude Code on the web / mobile) — **the default** | An empty GitHub repo; a Claude Code environment on it whose network policy allows `cdn.mendix.com` and GitHub Releases (`hub.mxcli.org` too, for a preview link) | Zero install, works from a managed laptop or an iPad, every stage P–7 end to end, a public preview URL via `mxcli run --hub` | You have no machine you may install on, or you want the pipeline to run while you are not at a desk |
| **B — Devcontainer** (VS Code, local Docker) | Docker Desktop + VS Code; `mxcli init` writes the `.devcontainer/` | The same Linux lane as A on your own disk: nothing is ephemeral, no network policy to negotiate | You have a machine you may install on and want it local |
| **C — Local machine with Studio Pro** (macOS/Windows) | Studio Pro + mxcli installed; on Windows, Git Bash | The two write modes that need Studio Pro open (`--mcp`, hand-rolled MCP) and the SP-only operations (`ALTER SETTINGS`, security level) | Your day job is in Studio Pro anyway, or you are polishing UI live |

**If you have no preference: take A.** It needs nothing installed, it is where this toolkit is
field-proven end to end (`skills/cloud-dev-environment.md` — the setup order and the
commit-and-push loop, which is the one rule the cloud adds), and the model it produces travels
to any Studio Pro afterwards (`skills/handoff-to-studio-pro.md`). B is A without the
ephemerality; choose it when you would rather not push at every gate. C is not "the real one" —
it is the option that adds Studio Pro's two extra write modes, at the cost of one platform-specific
setup (`README.md` → *Platform support*).

**Agents:** the lane is a Stage-P fact, recorded once in `PROJECT.md` (`Environment: cloud |
devcontainer | local`). Never conclude "this cannot be built here" from the absence of Studio Pro —
probe `./mxcli --version` and `bin/doctor.sh` and let the result decide (real misfire, 2026-09-03:
a cloud session read the local-first front door and announced Stages 5–7 impossible in the container,
before `mxcli run --local` was even probed).

## What to expect

- The pipeline **interviews you** at every gate: the agent proposes 2–4 options with evidence from your actual source, states its assumptions, and asks you to correct it — it never asks what it can derive itself.
- If you don't know an answer, the run doesn't stall: the recommendation is applied and recorded as `ASSUMED` in `PROJECT.md` with the risk if wrong. Hard gates (`✋`) are the exception — those need an explicit `CONFIRMED` answer.
- Every stage ends with `bin/gate-check.sh <project-dir> <stage>` — a mechanical check that required artifacts exist, which also regenerates your project dashboard (`index.html`).
- Verdicts: `PASS`, `PENDING` (not there yet — **not started is not failed**), `FAIL` (something *is* there and it is wrong), `WAIVED`, `MANUAL`.
- **Already underway when you wired this in?** Say so once — `bin/gate-check.sh <project-dir> --adopt <stage> --reason "..."` — and every earlier stage reports `WAIVED` instead of red. `--waive <stage>` does one stage. See the runbook's "What a gate verdict means" in §2.
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
