# Roadmap — future scope, parked deliberately

**Created:** 2026-09-17 · **Owner:** MendixMau (with Claude Code)
**Purpose:** Hold work this toolkit has decided it *wants*, has assets for, and is
**not building yet** — so a parked idea stays findable instead of decaying in a chat
log or a stale draft PR.

This file is not a wish list. An entry earns a place here only if it already carries
the three things below; anything without them is a chat message, an inbox drop
(`contrib/inbox/`, see `CONTRIBUTING.md`), or an issue.

## Entry format

```
## RM-NN — <goal, stated as an outcome>
Status:      PARKED | IN FLIGHT | DONE (<commit>) | DROPPED (<reason>)
Assets:      what exists today, by path — the thing a future session picks up
Start when:  the concrete trigger that unparks this; never "when we have time"
Exit bar:    what has to be true to call it done, in checkable terms
Explicitly out of scope: the adjacent thing we are NOT doing, and why
```

`Start when` and `Exit bar` are the load-bearing fields. A roadmap entry without a
trigger never starts, and one without an exit bar never finishes — both failure modes
this repo has already lived through (`process/toolkit-worklog.md` rotted for exactly
the first reason).

---

## RM-01 — Kiro supported as a seat, then as an enforcement layer

**Status:** PARKED — assets built, nothing merged to `master`.

**Assets (today):**

| Asset | Path | State |
|---|---|---|
| Steering pointer generator | `bin/wire-agents.sh --with-kiro` → `.kiro/steering/mxtk-toolkit.md` | branch `claude/kiro-steering-pointer`, draft PR |
| Fixture | `tests/wave2/test-wire-agents-kiro.sh` | 11/11 asserts, same branch |
| Non-Claude-agent row | `skills/interview-protocol.md` §3 | same branch |
| Fit assessment (should we?) | `process/kiro-fit-2026-09-17.html` | merged to the branch |
| Loop visualisation (how would it work?) | `process/kiro-in-the-loop-2026-09-17.html` | merged to the branch |

The two HTML pages carry the argument as figures rather than prose: the layer stack,
where each harness's run-permission actually lives, the stage overlap, a three-lane
swimlane of one build step, the five hook points against the toolkit rules they could
enforce, and the three postures side by side. Read those before touching this entry —
they are the design, not a summary of it.

### Phase A — Kiro as a fifth supported seat

A seat owns exactly **one** of the six boxes in a build step: drafting. Validation
(`mxcli check`), writing (`bin/exec.sh` — snapshot · exec · mxbuild) and gating
(`gate-check.sh`, `PROJECT.md`, the drift-sync marker) are all shell and all
seat-agnostic. So supporting a new seat costs one generated pointer file and changes
nothing downstream. That is the entire integration.

**Start when:** someone has a real Kiro install and a real project to open in it.

**Exit bar:**
1. One module driven end to end in Kiro against a real model, cited in the commit
   that flips the PR to ready — the repo's field-proof rule 4, which this branch has
   owed since 2026-09-16.
2. The steering preamble's allowlist path corrected. It currently names
   `.kiro/settings/`; the workspace capability rules live under a hashed directory in
   the user's home, **outside the checkout**, so a clone cannot ship an allowlist at
   all. Kiro therefore belongs with Cursor and Windsurf in
   `install-harness-permissions.sh` (document, never write), not with Claude/Copilot/Aider.
3. The fixture still 11/11, and `render-routing.sh --check` in sync.

### Phase B — hooks as a mechanical enforcement layer

The genuinely new capability, and the reason this entry exists rather than being a
one-line changelog note. Kiro exposes five hook points; each maps to a toolkit rule
that today depends on an agent *choosing* to obey:

| Hook | Rule it could make mechanical |
|---|---|
| `agentSpawn` | inject the runbook and the current stage at session start — replaces the "read this first, every session" honour system |
| `userPromptSubmit` | stamp the stage and the toolkit commit on every prompt — the session-start ritual, enforced per turn |
| `preToolUse` | **refuse a bare `./mxcli exec`** and force `bin/exec.sh`, so no run happens without a snapshot |
| `postToolUse` | run `bin/check-no-client-data.sh` after every write — a leak caught at the write, not at the commit |
| `stop` | **refuse to end a turn on an `UNSYNCED` drift marker**, or on a gate question that was never asked |

The two in bold are the ones worth building. Nothing above exists.

**Start when:** Phase A's field run is cited **and** a second project has run in Kiro.
Two runs, not one — a hook that fires on every tool call in someone's editor is not
something to generalise from a single session.

**Exit bar:** a hook set that satisfies this repo's rules for a *blocking* instrument
(`CLAUDE.md` → "Shipping an instrument"), specifically:
- rule 6 — it accepts evidence it did not itself create (a recent commit, a recent
  handoff doc), never only its own stamp file;
- rule 7 — it never blocks the action that resolves it; warn once, then let through;
- rules 1–5 as usual, including golden input captured from a real Kiro session rather
  than hand-written, and both platforms (Git Bash on Windows included).

**Explicitly out of scope:**

- **Kiro spec mode replacing Stages 2–4.** Its requirements → design → tasks flow
  covers Requirements, Architecture & Design and Build Plan — *two of the four ✋ hard
  gates*. Running both gives a project two requirement sets, two plans, and no answer
  to which one a gate reads. The one-decision-register rule is what keeps a build from
  regressing itself; this trades it for a vendor's spec folder. Refused, not deferred.
- **Native Kiro agent definitions as hand-written files.** Kiro's custom agents take
  the same shape as the six roles `wire-agents.sh` already scaffolds, which makes them
  tempting — and makes them a second copy of the role definitions, which this repo's
  authoring rule forbids (pointers, never copies; the three-copy enrichment-report
  defect is the worked example). If they are ever generated, they are generated from
  the same source the existing stubs come from, or not at all.

**Known unknowns:** everything recorded about Kiro here is secondary-source — the
vendor's docs are unreachable from the sandbox these assessments were written in. Cost
is metered per spec run, and nobody has measured what one of this pipeline's stages
costs. Both figures are for the field run to supply.
