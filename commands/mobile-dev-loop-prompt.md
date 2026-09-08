---
description: Self-contained prompt to paste into a fresh Claude Code (mobile/cloud) session to run the drafting/static-check half of iterative-build-loop.md against an existing project repo
---

Copy everything below the line into a new Claude Code session that has no access to your local
machine. Fill in the `<...>` blanks first.

**Why this is scoped the way it is.** This prompt is the *drafting* half of the build loop, for
when you want MDL written and statically checked against a project repo without standing up a
runtime. That is a scope choice, not a platform limit.

> **Correction, 2026-08-21 — this file previously claimed the build gate requires Studio Pro. It
> does not, and that claim blocked cloud sessions at a boundary that isn't real.** The gate is
> `mxbuild`, a plain binary that `project-bin/exec.sh` invokes directly; `exec.sh`'s only Studio
> Pro coupling is a *lock check* (refuse to write while SP holds the `.mpr`), which is a no-op
> where no SP exists. `mxcli new` creates a project headlessly, `mxcli docker run` or
> `mxcli run --local` runs it, `mxcli run --hub` exposes it at a public URL, and
> `mxcli playwright` / `mxcli oql` / `mxcli test --local` exercise it. A container can run the
> whole loop. For the full headless build-and-prove run, use the full-e2e cloud prompt in
> `personal-toolkit/prompts/` instead of this one.

---

```
This is a fresh Claude Code session with no prior context. Task: draft and static-check the next
phase of a Mendix build plan, using mxcli-project-toolkit's iterative-build-loop.md. Scope is
deliberately static: MDL drafted and applied, model-side checks run, no runtime stood up.

Setup (do this first, in order):
1. Add and clone these repos:
   - https://github.com/MendixMau/mxcli-project-toolkit.git  (skills + harness scripts)
   - https://github.com/mendixlabs/mxcli.git                  (the mxcli CLI — build/install it)
   - <PASTE THE ACTUAL MENDIX APP PROJECT REPO URL HERE>       (contains the .mpr this session
                                                                 will read/write against)
2. From the toolkit clone, run `bin/doctor.sh <project-dir>`. A warning that Studio Pro
   automation is unavailable is expected here and is not a problem to fix — nothing in this
   prompt's scope uses it. Everything else it reports missing, fix before continuing.
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

OUT OF SCOPE for this prompt — do not attempt, and hand these back to me explicitly instead.
These are excluded because this run is deliberately static, NOT because they are impossible here:
- Gate: BUILD (project-bin/exec.sh's mxbuild run + snapshot/auto-restore). Runs fine headless;
  it is out of scope only because nothing here stands up a runtime to prove the result.
- Gate: UI (module-review.md's PROVE/LOOK stages, project-bin/verify-module.sh, the happy-path
  walk) — these need a running app + reachable DB, which this prompt does not set up.
- Renaming any script to its `done-` prefix — that rename only happens after the FULL gate
  (mxbuild + happy-path) passes, which this session does not verify.

Deliverable: the drafted/applied MDL for this phase, syntax-clean per step 6, plus the results of
the four static instruments in step 7, plus a short handoff note listing exactly what's left
(mxbuild gate, happy-path walk, module-review.md, done- rename) for me to run in a session that
stands up the app.

If you hit anything requiring a judgement call outside this scope (an ambiguous CE error, a
requirements gap, whether to touch a shared module), stop and ask rather than guessing — same
discipline as any other build session.
```
