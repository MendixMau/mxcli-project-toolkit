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

**Status:** PARKED — Phase A has not started (see Start when); the assets below exist on a
branch pending merge, but this line does not track merge state — check the branch itself.

**Assets (today):**

| Asset | Path | State |
|---|---|---|
| Steering pointer generator | `bin/wire-agents.sh --with-kiro` → `.kiro/steering/mxtk-toolkit.md` | branch `claude/kiro-steering-pointer`, draft PR |
| Fixture | `tests/wave2/test-wire-agents-kiro.sh` | 12/12 asserts, same branch |
| Non-Claude-agent row | `skills/interview-protocol.md` §3 | same branch |
| Fit assessment (should we?) | `process/kiro-fit-2026-09-17.html` | merged to the branch |
| Loop visualisation (how would it work?) | `process/kiro-in-the-loop-2026-09-17.html` | merged to the branch |
| Developer view (what changes on Monday?) | `process/kiro-same-repo-two-editors-2026-09-17.html` | merged to the branch |

The three HTML pages carry the argument as figures rather than prose: the layer stack,
where each harness's run-permission actually lives, the stage overlap, a three-lane
swimlane of one build step, the five hook points against the toolkit rules they could
enforce, the three postures side by side, and — for the developer who just wants to know
what changes — the two-editor view, where one line below the editor everything is the
same clone, the same scripts and the same `.mpr`. Read those before touching this entry —
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
2. **Done, `bin/wire-agents.sh` 2026-09-21.** The steering preamble no longer names a path —
   it previously and wrongly claimed `.kiro/settings/`. The workspace capability rules
   actually live under a hashed directory in the user's home, **outside the checkout**, so a
   clone cannot ship or point at that allowlist at all; the preamble now says exactly that and
   tells the user to grant `./mxcli`/`./bin/*.sh` once themselves, in Kiro's own settings UI.
   A future doc that walks a user through that grant for Cursor, Windsurf and Kiro alike would
   belong alongside them, tentatively named `install-harness-permissions.sh` — nothing under
   that name exists in this repo yet; this is a placeholder for future work, not a citation.
3. The fixture still 12/12, and `render-routing.sh --check` in sync.

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

---

## RM-02 — Every toolkit release is measured for build speed and token cost, so a regression is caught in a week, not a cook-off

**Status:** PARKED — the evidence is in; the measuring harness does not exist yet.

**The regression nobody spotted.** Between the copy a cloud build used (`247729fd`, 2026-09-21)
and `c9dedb11`, 184 commits landed, 36 of them in `project-bin/exec.sh` (819 → 2,289 lines). Each
added a check after a real failure — lint per exec (`8d70fbda`), score per exec (`a7221405`), the
chat-approval baseline refusal (`b6a13380`), the row as the unit of work (`a7653197`) — and none was
ever removed or re-costed. No release measured what the sum did to a build. A cook-off did
(run 2, ProcureFlow, 2026-10-26/27, arm C = mxcli + this toolkit at `c9dedb11`):

| Measured | Value |
|---|---|
| Scripts per build-plan row | 0.93 (the cloud build: 0.34) — every row paid the full exec chain |
| Lint + score after every exec | 18.3 min; the ratchet read ROSE on 123 of 147 rows and nobody read it — while 6 real SEC010 warnings sat in it |
| Checks that never ran | `verify-module`, `gate-check`, the LOOK ledger: 0 runs (nothing calls them) |
| `mxcli docker reload` | failed every time (curl not in the JRE image) → a container restart per change |
| Outcome | stopped by the user after 10 h 50 min at row 121 of 147, no acceptance test; the HAM arm finished 137/137 and 12/12 in 602 min |
| Lead tokens | 2,878 model calls, median 139,895 tokens of context per call, 399 M input tokens in total |
| Fixed load per call | 40,161 tokens, incl. 188 skills, 7 user plugins and 4 MCP servers — **0** Skill and **0** MCP calls in the whole run |

**Assets (today):**

| Asset | Path | State |
|---|---|---|
| Fixes under test (arm D of the cook-off) | `project-bin/reload.sh` (hot reload via `--direct`), `project-bin/module-close.sh` (lint, score, check, verify-module, LOOK once per module), `project-bin/row-groups.sh` + an `exec.sh` gate (low-risk rows grouped into one script, high-risk rows alone), `skills/iterative-build-loop.md` (row groups, diff only on overlap) | local branch `run3-speed` (9b2774db, 78e34c93), not pushed; measured in arm D before any merge |
| Lean session switches | `claude -p --setting-sources project,local --strict-mcp-config [--mcp-config .mcp.json]` → 37,536 tokens per call (from 40,161); with `--disable-slash-commands` 33,329 | measured once, one call |
| Run analysis | `procureflow-ham-runs/OBSERVER-FINDINGS.md` O-49 … O-56; `personal-toolkit/research/2026-10-27-run2-toolkit-speed/` | written |

**What to build:**

1. **A speed benchmark per release.** A small fixed reference build (a slice of a real build plan,
   ~10 rows, one module) run headless on each release candidate. Record: execs per row, instrument
   seconds per exec, minutes per row, model calls, median context tokens per call, fixed load per
   call. Compare with the previous release; a rise of more than 15% on any of these blocks the
   release until it is explained in the CHANGELOG.
2. **Every check carries its cost and its reader.** A new step in `exec.sh` (or any per-exec hook)
   states in its header: seconds per exec, tokens of output per exec, and who reads the result and
   when. A check whose output no step reads is moved to a cadence (per module, per checkpoint) or
   removed. Review the list at each weekly toolkit review; removing is a normal outcome.
3. **Cadence over repetition.** Per exec: only what protects the model (check, apply, mxbuild gate).
   Per module: lint, score, verify-module, LOOK (`module-close.sh`). Per checkpoint: docker
   check/build, the test suite. A check that "must" run is called by a gate, never only by a prompt.
4. **Quiet by default.** `exec.sh` prints the verdict and the errors; the long form goes to a log
   file. Every line printed is re-read on every later model call until the next compaction.
5. **Lean sessions by default.** Headless and build sessions start with the project's settings only:
   the project's own MCP servers (`.mcp.json`) stay, so teams that use an MCP server keep it; user
   plugins, user skills and connectors a build never calls are left out.

**Start when:** arm D's numbers are in (same plan, `run3-speed`, solo) — or the next toolkit release,
whichever comes first.

**Exit bar:** the benchmark runs on every release and its table is in the release notes; `exec.sh`
lists cost and reader for each step; lint/score/verify-module run at module close under a gate
(not a prompt), with a non-zero run count in a field build; a headless build's fixed load per call
is reported and below 35k tokens.

**Explicitly out of scope:**

- **Removing lint, the score or the mxbuild gate.** They find real defects (the 6 SEC010 above).
  The fix is when they run and who reads them, not whether they exist.
- **Tuning for one arm of the cook-off.** The benchmark measures the toolkit on a fixed plan; it is
  not a race against HAM or the cloud build.
