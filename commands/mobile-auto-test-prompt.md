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

**Updated 2026-08-21 — the container can now stand the app up itself.** This file used to present
a laptop-hosted app plus a hand-rolled ngrok/cloudflared tunnel as the only options. It is no
longer the shortest path: given the project's repo, this session can run the app locally with
`mxcli docker run` or `mxcli run --local`, and publish it with `mxcli run --local --hub` (a public
URL via `mxcli tunnel-hub`, with `ApplicationRootUrl` set correctly for that origin). Option (c)
below is now the default; (a) and (b) remain valid when you specifically want to test an app
instance that already exists elsewhere.

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
   for OQL/DB assertions. This container cannot reach a laptop's localhost. In order of
   preference:
   (c) **stand it up here** — `mxcli docker run -p <app>.mpr --wait`, or `mxcli run --local`
       for a Docker-free warm loop (needs JDK 21 and a reachable PostgreSQL whose database
       already exists). Add `--hub` if I need to click through it from a browser myself.
       Verify with `mxcli docker status`; never infer "up" from the absence of an error.
   (a) it's already deployed at a reachable URL — set APP_URL to that, and PG_HOST/PG_PORT (or
       the M2EE admin port) to the reachable DB, or
   (b) tunnel an existing local instance out and set APP_URL/PG_HOST to the tunnel address:
       <FILL IN THE TUNNEL URL / DEPLOYED URL AND DB CONNECTION DETAILS HERE>.
   If none is possible, stop and say so rather than guessing — a runtime instrument that
   can't reach the app should report `fault`/`INVALID`, never be skipped silently or faked green.

Skill to follow: skills/existing-app-assurance.md — Track B (Regression / e2e test net).
No intake, no stages, no gates; this is à-la-carte tool-shelf use.

**Do not stop at a handful of obvious happy paths.** A prior run of this exact prompt produced
short, shallow tests that skipped ordinary workflow actions (adding a comment, adding a note) and
never checked UI styling/spacing at all. Both failures trace to skipped steps below — do not skip
them again.

For each module:
1. Stand up/extend the harness per skills/e2e-harness-base.md.
2. Inventory every workflow action from the model BEFORE writing any journey — not from a
   click-around, not from memory:
   `./mxcli -p <project>.mpr -c "SHOW PAGES IN <Module>"` and `"SHOW MICROFLOWS IN <Module>"`.
   List every button/action on every page — New, Edit, Delete, status/workflow transitions, add
   comment, add note, approve/reject, anything that calls a microflow. Write one journey per
   action, not one journey per screen. Report the count: "<N> actions found, <N> journeys
   written." Secondary actions (commenting, annotating, cancelling) are exactly what a quick pass
   skips — they are not optional because they aren't the module's headline feature.
3. Author/extend journeys/<Module>.journey.json per skills/journey-proof.md for every action
   from step 2's inventory (5 rungs: landing guard, screen text, ordered spans, data
   effects, outcome — each backed by its own mutant via --positive-control, never just "did
   something fail").
4. Add DB assertions per skills/learned-db-assertions.md — the UI can lie about whether a
   write landed, OQL/DB can't.
5. Run skills/wiring-sweep.md per module — every clickable element on every page via
   `mxcli playwright snapshot`/`click`, not just what a journey visits. Report "<N> of <N>
   elements swept." A dead button is invisible to step 3 by construction.
6. Run skills/module-review.md stage 4 (LOOK) per module — styling, spacing, information
   hierarchy, empty states, design-system reuse. Run `node tests/e2e/design-audit.js` first for
   the mechanical dimensions (class discipline, overflow, a11y), then 4c/4d/4e by eye for
   everything it cannot see (does it look right, is the hierarchy sane, is a built component
   reused vs reimplemented). This is the only place "does the UI look right" gets asked — skip it
   and styling is never actually reviewed, however green the journeys are.
7. Run project-bin/verify-module.sh <Module> for each module (it runs conformance-check,
   graph-sweep, coverage-check, journeys, journeys-control, and monkey — read its own header
   comment for flags; --parallel-runtime is opt-in only, there's a documented Mendix
   trial-license concurrent-session risk running journeys/monkey in parallel).
8. After every module, run project-bin/coherence-cadence.sh — when it reports DUE, run the
   full skills/process-coherence-pass.md sweep before moving to the next module, then run
   coherence-cadence.sh --record.
9. Run project-bin/build-plan-status.sh --html periodically to keep architecture/build-plan.html
   current — it shows built (done- prefixes) vs proven (verify-module.sh + improvement-register.md)
   as two separate views on purpose.

Findings go to docs/improvement-register.md (skills/improvement-register.md governs the format
and defect-class vocabulary) — never silently fixed from inside the harness; that's diagnostic
only, per journey-proof.md's own rule.

Deliverable: a findings report (what's broken/missing/should-improve, each with evidence) plus
a green, committed test suite. Ask me before fixing anything the audit finds — that's a
deliberate hop into build discipline, not a silent side effect of testing.
```
