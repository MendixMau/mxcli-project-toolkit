---
description: Self-contained prompt to paste into a fresh Claude Code (mobile/cloud) session to run a full e2e regression test on an existing Mendix app, across all modules, using existing-app-assurance.md Track B
---

Copy everything below the line into a new Claude Code session that has no access to your local
machine (mobile, web, or any cloud container) — it names every repo and every piece of local
runtime state that session needs but can't discover on its own. Fill in the two `<...>` blanks
before sending it.

**Why this file exists:** the toolkit, `mxcli`, and a project's app are normally consumed as
local clones referenced by path (`~/Mendix/mxcli-project-toolkit`, a locally running app at
`localhost:8080`, a local Postgres DB). A cloud/mobile session starts from an empty container —
it has no filesystem in common with your laptop and cannot reach `localhost` on it. This prompt
exists so that gap gets stated up front, once, instead of being rediscovered as a confusing
`fault` deep into a run.

---

```
This is a fresh Claude Code session with no prior context. Task: run a full e2e regression
test on an EXISTING Mendix app, across all modules — audit + test-suite, no build, no pipeline.

Setup (do this first, in order):
1. Add and clone these repos:
   - https://github.com/MendixMau/mxcli-project-toolkit.git  (skills + harness scripts)
   - https://github.com/mendixlabs/mxcli.git                  (the mxcli CLI — needed to build/install it)
   - <PASTE THE ACTUAL MENDIX APP PROJECT REPO URL HERE>
2. From the toolkit clone, run `bin/doctor.sh` and fix anything it reports missing before
   continuing — it names exactly what's absent (Python, mxcli binary, etc.) and how to get it.
3. This app must be RUNNING and reachable from this container, plus its database reachable
   for OQL/DB assertions. This container cannot reach a laptop's localhost. Either:
   (a) it's deployed at a reachable URL — set APP_URL to that, and PG_HOST/PG_PORT (or the
       M2EE admin port) to the reachable DB, or
   (b) tunnel the local instance out (ngrok/cloudflared) and set APP_URL/PG_HOST to the
       tunnel address: <FILL IN THE TUNNEL URL / DEPLOYED URL AND DB CONNECTION DETAILS HERE>.
   If neither is possible, stop and say so rather than guessing — a runtime instrument that
   can't reach the app should report `fault`/`INVALID`, never be skipped silently or faked green.

Skill to follow: skills/existing-app-assurance.md — Track B (Regression / e2e test net).
No intake, no stages, no gates; this is à-la-carte tool-shelf use.

For each module:
1. Stand up/extend the harness per skills/e2e-harness-base.md.
2. Walk each module's real golden paths — derive them from actual navigation and any
   "what must never break" list, not guesses. Author/extend journeys/<Module>.journey.json
   per skills/journey-proof.md (5 rungs: landing guard, screen text, ordered spans, data
   effects, outcome — each backed by its own mutant via --positive-control, never just "did
   something fail").
3. Add DB assertions per skills/learned-db-assertions.md — the UI can lie about whether a
   write landed, OQL/DB can't.
4. Run project-bin/verify-module.sh <Module> for each module (it runs conformance-check,
   graph-sweep, coverage-check, journeys, journeys-control, and monkey — read its own header
   comment for flags; --parallel-runtime is opt-in only, there's a documented Mendix
   trial-license concurrent-session risk running journeys/monkey in parallel).
5. After every module, run project-bin/coherence-cadence.sh — when it reports DUE, run the
   full skills/process-coherence-pass.md sweep before moving to the next module, then run
   coherence-cadence.sh --record.
6. Run project-bin/build-plan-status.sh --html periodically to keep architecture/build-plan.html
   current — it shows built (done- prefixes) vs proven (verify-module.sh + improvement-register.md)
   as two separate views on purpose.

Findings go to docs/improvement-register.md (skills/improvement-register.md governs the format
and defect-class vocabulary) — never silently fixed from inside the harness; that's diagnostic
only, per journey-proof.md's own rule.

Deliverable: a findings report (what's broken/missing/should-improve, each with evidence) plus
a green, committed test suite. Ask me before fixing anything the audit finds — that's a
deliberate hop into build discipline, not a silent side effect of testing.
```
