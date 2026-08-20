---
description: Self-contained prompt to paste into a fresh Claude Code (mobile/cloud) session to run the drafting/static-check half of iterative-build-loop.md — it stops at the Studio Pro-dependent gate rather than faking it
---

Copy everything below the line into a new Claude Code session that has no access to your local
machine. Fill in the `<...>` blanks first.

**Why this is scoped the way it is:** unlike a pure e2e test run, the build loop's gate needs
**Studio Pro** — a Windows/macOS GUI app — open and reachable at several mandatory points (close
SP → exec → mxbuild gate → reopen SP → Run Locally). The toolkit's own SP automation
(`save-sp.sh`, `restart-sp.sh`) is macOS-only (`osascript`/`lsof`/`open -a`). A headless cloud
container cannot drive a GUI app it has no display for, and there is no tunnel-equivalent fix for
that the way there is for a running web app. So this prompt deliberately does the half of the
loop that has no GUI dependency, and stops cleanly at the handoff instead of pretending to
complete the rest.

---

```
This is a fresh Claude Code session with no prior context. Task: draft and static-check the next
phase of a Mendix build plan, using mxcli-project-toolkit's iterative-build-loop.md — WITHOUT
Studio Pro, which this session cannot reach.

Setup (do this first, in order):
1. Add and clone these repos:
   - https://github.com/MendixMau/mxcli-project-toolkit.git  (skills + harness scripts)
   - https://github.com/mendixlabs/mxcli.git                  (the mxcli CLI — build/install it)
   - <PASTE THE ACTUAL MENDIX APP PROJECT REPO URL HERE>       (contains the .mpr this session
                                                                 will read/write against)
2. From the toolkit clone, run `bin/doctor.sh <project-dir>`. It will (correctly) warn that
   Studio Pro automation is unavailable here — that's expected, not a problem to fix. Everything
   else it reports missing, fix before continuing.
3. Confirm no live Studio Pro elsewhere holds a lock on this project's .mpr (check for a
   `*.mpr.lock` file, or ask me). mxcli must never touch a .mpr while Studio Pro has it open,
   including reads — if uncertain, stop and ask rather than risk corrupting the model.

Read first: skills/iterative-build-loop.md in full, plus skills/brd-to-build-plan.md (upstream —
where the build plan and module order come from) and skills/module-brief.md (per-module input).
Also skills/learned-mdl-preflight.md before writing any MDL line.

Scope — run through "The Build Loop" steps 1-9 ONLY, then stop:
1. Read source screenshots / feature doc for the module in scope.
2. Extract the build checklist.
3. Sketch page data-view nesting -> derive microflow signatures.
4. Create stub pages/microflows for forward references.
5. Write + apply microflows, then pages.
6. Gate: SYNTAX — `mxcli check --references` (mandatory, headless-safe, always run this).
7. Also run, all headless and model-side only:
   - project-bin/lint-gate.sh (or the project's installed lint-gate)
   - project-bin/conformance-check.sh --module <Module>
   - project-bin/graph-sweep.sh --module <Module>
   - project-bin/coverage-check.sh, against the module's coverage ledger

DO NOT attempt, and do not report as done — hand these back to me explicitly instead:
- Gate: BUILD (bin/exec.sh's mxbuild run + snapshot/auto-restore) — exec.sh's SP handling
  requires a live, reachable Studio Pro.
- Reopening Studio Pro, "Update security", or any Cmd+S save.
- Gate: UI (module-review.md's PROVE/LOOK stages, project-bin/verify-module.sh, the happy-path
  walk) — these need a running app + reachable DB, same as the e2e test prompt
  (commands/mobile-auto-test-prompt.md) requires, and this session has neither by default.
- Renaming any script to its `done-` prefix — that rename only happens after the FULL gate
  (mxbuild + SP reopen + happy-path) passes, which this session cannot verify.

Deliverable: the drafted/applied MDL for this phase, syntax-clean per step 6, plus the results of
the four static instruments in step 7, plus a short handoff note listing exactly what's left
(mxbuild gate, SP reopen, happy-path walk, module-review.md, done- rename) for me to run locally
or in a session that can reach Studio Pro / the running app.

If you hit anything requiring a judgement call outside this scope (an ambiguous CE error, a
requirements gap, whether to touch a shared module), stop and ask rather than guessing — same
discipline as any other build session.
```
