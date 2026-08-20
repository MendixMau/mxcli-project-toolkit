# Improvement Plan — e2e/regression test coverage and the UI-findings gap

**Author:** Maurits Visser (with Claude Code)
**Created:** 2026-08-20
**Status:** OPEN — fixes in flight. Findings 1–4 confirmed against the toolkit's own source;
Findings 5–9 merged 2026-08-20 from the VB-USI-main postmortem and a toolkit-wide wiring audit.
Decisions taken are recorded at the end of this document and govern the work now underway.
**Purpose:** Record what a run of the mobile e2e prompt against a real app surfaced — shallow
journeys, zero UI findings, ledger faults nobody expected — trace each one to its actual cause in
this repo, and lay out resolution options before any fix lands. Written to merge with a parallel
investigation running on another machine; see "To merge" at the bottom.

---

## The trigger

Running `commands/mobile-auto-test-prompt.md` (Track B / `existing-app-assurance.md`) against a
real app produced tests that were short, skipped ordinary workflow actions (adding a comment,
adding a note), and reported **zero** UI/styling findings. Separately, running `verify-module.sh`
against another project failed while "comparing a ledger" that had never been created. Neither
was a fluke — both trace to real, specific gaps in this toolkit, confirmed by reading the actual
scripts, not by guessing.

---

## Finding 1 — Track B had no completeness discipline (FIXED this session)

`skills/existing-app-assurance.md` Track B said "walk the app's real golden paths — derive from
navigation... not guesses," with no requirement to enumerate every workflow action per module
before deciding what to test. A session could stop after 2-3 obvious happy paths and call it
done — silently skipping secondary actions like commenting or adding a note.

**Fixed in commit `a6cc392`** (branch `claude/e2e-testing-module-validation-5o6mly`): Track B now
requires a model-derived action inventory per module (`SHOW PAGES`/`SHOW MICROFLOWS`, one journey
per action not per screen, with a reported "N actions found, N journeys written" count) before any
journey gets written, and adds `wiring-sweep.md` (dead-click detector) and `module-review.md`
stage 4 (LOOK — styling, spacing, wireframe conformance) as **required** steps in Track B, not
optional ones. `commands/mobile-auto-test-prompt.md` was updated to match, with an explicit
warning not to repeat the shallow-coverage pattern.

## Finding 2 — the rich per-step report exists in code and is never invoked

`skills/report-schema.md` defines a report that is explicitly **"a per-persona journey, not a
test log"** — for every page in the process, in order, it answers what ran against it, where it
sits in the flow, what data change was expected, was it seen, does it match its wireframe, does it
match general design practice. That last pair (wireframe conformance / design practice) is exactly
the "doesn't match the wireframe / could improve spacing" signal we said the report should always
carry when relevant.

The renderer for this is real, working code — `project-tests/e2e/report-normalize.js` and
`report-render.js` — not a spec waiting to be built. `design-audit.js` is the instrument that
would populate the UI/wireframe findings in that report.

**None of this is called by `project-bin/verify-module.sh`**, the one command every module-review
and every mobile test run is told to run. It runs journeys and monkey, dumps their raw output into
a terse tab-separated `summary.tsv` plus log files, and stops — it never calls `design-audit.js`
and never calls the normalizer/renderer. The script says so itself, in its own final line:
*"it says nothing about UI/design quality — that instrument is not part of this chain."* So the
"0 UI improvements" in the run that triggered this wasn't a real zero — the instrument that finds
UI problems was never run, and the report that would show findings per step was never generated.

**Resolution options (undecided):**
1. Wire `design-audit.js` into `verify-module.sh` as an informational rung (like `monkey` — doesn't
   gate pass/fail, just reports), and add a final step that runs `report-normalize.js` +
   `report-render.js` so every run ends by producing `docs/verification/report.html` automatically.
   No manual step, no chance to forget it. (Leaning toward this one — matches the script's own
   stated design principle: "Scheduling deep verification last is the same as not having it... this
   script makes it ONE command.")
2. Keep `verify-module.sh` narrow (model + journeys + monkey only) and make the render step an
   explicit, always-required second command in `module-review.md`'s PROVE stage.
3. Leave the scripts as-is; just fix the deliverable language in `existing-app-assurance.md` and
   the mobile prompt to point at `docs/verification/report.html` as what to open.

## Finding 3 — ledger/BRD-dependent instruments always fault on a Track-B app, by design, with no signposting

Traced the "comparing a ledger that was never created" failure to `conformance-check.sh` and
`coverage-check.sh`, both invoked from `verify-module.sh`. They are working exactly as designed —
`conformance-check.sh` line 53: `[ -f "${LEDGERS[0]}" ] || { echo "FAULT: no ledger for module
'$MODULE'" >&2; exit 2; }` — refusing to silently pass with nothing to check against, and saying
so loudly instead. Not a crash.

The actual problem: `coverage-ledger.md` and the BRD are **build-loop artifacts**, created only
when a module goes through the migration/greenfield pipeline (BRD written → ledger generated →
module built against it). Track B (`existing-app-assurance.md`) is explicitly "no pipeline, no
BRD, no stages" — it audits an app that already exists, it doesn't trace one back to a spec. A
Track-B-onboarded module was never going to have a ledger. So `verify-module.sh`'s `conformance`
and `coverage` instruments will **fault on every single run, forever**, for a reason that has
nothing to do with anything being broken — and nothing currently tells whoever's running it that
this is expected for their entry mode.

**Resolution options (undecided):**
1. Downgrade to declared-out-of-scope rather than FAULT for a Track-B module — same shape as the
   existing `--skip-monkey`/`--skip-journeys` flags, so the noise stops without lying about it.
2. Auto-derive a minimal ledger from the live model. Leaning against this — a ledger represents
   *decided* requirements; reverse-deriving one from existing code inverts that meaning, and
   `report-schema.md` is explicit elsewhere that a requirement pointer must never be synthesized.
3. Leave the FAULT as-is, just document in Track B / the mobile prompt that these two lines are
   expected and by design for an existing-app audit, so it reads as "doesn't apply here" instead
   of "something's wrong."

## Finding 4 — none of this had automated test coverage

Checked all 25 fixtures in `tests/wave2/` (the toolkit's entire automated test suite). None
reference `verify-module.sh`, `report-normalize.js`, or `report-render.js` — every fixture
exercises the intake/stage-gate/dashboard side of the toolkit. There is zero automated coverage
over the runtime-verification pipeline's own integration. Nothing tests this seam, so nothing
could have caught it silently not being wired — this isn't a regression, it's a gap that was
always there.

---

## Merged — VB-USI-main postmortem + toolkit-wide wiring audit (2026-08-20)

The parallel investigation completed. Its project was `VB-USI-main`; a static wiring audit of the
whole toolkit ran alongside it. Both are folded in below. **Status of this document changes from
OPEN/no-code-changes to OPEN/fixes-in-flight** — see "Decisions taken" at the end, which resolves
several options Findings 1–4 above left undecided.

### The trigger, from the other side

A full harness run against VB-USI-main (6 modules) reported 611 checks: **205 pass / 23 fail /
353 fault / 30 skipped**. It read as roughly 90% healthy. It is 34% — over half the checks never
executed. A manual walkthrough minutes later found a runtime crash (`Remark CreatedBy`), a broken
Attachment widget, an unstyled page, and a live data-integrity double-fork bug in
`ACT_ApprovalRun_CreaVersionForkConfirm` confirmed by `mxcli oql` before/after evidence. Every one
of those four sat on a surface nothing had actually exercised.

The report did not lie. `instruments[]` shows `coverage-ledger`, `conformance`, `deferrals` and
`full-app-walkthrough` all at verdict `fault`, and the walkthrough's reason verbatim:
*"tests/e2e/artifacts/findings.json does not exist — the instrument did not run, or ran without
writing."* Nothing anywhere treated 353 non-runs differently from 353 passes, and nothing blocked
Stage 4 sign-off.

Harness code was ruled out as the cause: diffed against sibling `WMS-Demo-main` at the same
toolkit commit `5acd442`, `monkey.js` / `design-audit.js` / `report-normalize.js` are byte-identical
and VB-USI's `journey-runner.js` is actually ahead by two local fixes.

### Finding 5 — `full-app-walkthrough.js` has never existed in this repo

`project-tests/e2e/project.config.template.js:381` declares the instrument slot; `report-normalize.js`
treats it as expected and at `:1143` stamps it `canExpressFault:false, evidenceStrength:'weak'`.
There is no `full-app-walkthrough.js` anywhere in the toolkit. `WMS-Demo-main` hand-authored its
own because the toolkit never shipped one; VB-USI never got one. So the fault above was not a
misconfiguration — the script does not exist.

This is the same disease as Finding 2, one step earlier: Finding 2 is a real instrument that never
gets *called*; Finding 5 is a declared instrument that was never *written*.

### Finding 6 — the e2e harness never installs into any project

`bin/lib/install-manifest.sh:317-348` documents this against itself and it is still true at HEAD:
`grep -n 'install-tests' bin/init-project.sh bin/sync-project.sh` returns nothing. `MXTK_PROJECT_TESTS`
(16 files in `project-tests/e2e/`) installs nowhere — while `project-bin/verify-module.sh` *is*
installed and drives `journey-runner.js`, four skills cite `tests/e2e/*` paths, and
`skill-routing.tsv:81` routes `verify-module.sh` as a **baseline** skill for stages 5–6.

Confirmed from the project side: VB-USI's `tests/e2e/` is a hand-assembled partial copy. Missing
every self-test (`journey-runner.selftest.js`, `monkey.selftest.js`, `journey-rung4-scope.test.js`,
`example.journey.json`); extra local files (`pk-probe.js`, `project.config.js`, `artifacts/`, a
stray `tmp-sketchnumbers-skagent.journey.json`). **The harness in a real project cannot check
itself** — which is Finding 4's blind spot reproduced downstream.

The documented workaround (`bin/check-requirements.sh --fix`) is pointed at by nothing, and
`check-requirements.sh:30-38` `exit 2`s unless an `.mpr` is present, which a Stage-P project has not
got.

### Finding 7 — `docs/progress/RESUME.md` is dead on day one, in every project, as instruction #1

`bin/wire-agents.sh:93` writes into all six generated entry points (`CLAUDE.md`, `AGENTS.md`,
`.github/copilot-instructions.md`, `.cursorrules`, `.windsurfrules`, `.aider.conf.yml`):

> `1. **Read `docs/progress/RESUME.md` first, and nothing else yet.**`

Nothing in the init path creates `docs/`. The only writers are `project-bin/close-task.sh:142` and
`claude-hooks/bin/checkpoint.sh:138`, both of which fire at close-the-loop time — after a session
ends. The same instruction block explicitly forbids reading `PROJECT.md` to get oriented, so the
fallback is closed off. **Widest blast radius of anything found: all entry modes, 100% of new
projects, first instruction.**

### Finding 8 — three `project-bin` scripts routed and cited, never installed

`project-bin/coherence-cadence.sh`, `build-plan-status.sh`, `done-drift-check.sh` are absent from
`MXTK_PROJECT_BIN` (`install-manifest.sh:62`) while `MXTK_PROJECT_BIN_NOINSTALL` (`:68`) is empty.
`skill-routing.tsv` rows 125–126 route the first two and `agents/*-agent.md` cite them. The reverse
self-check `_mxtk_manifest_check_bin_unnamed()` (`:182-200`) is emitting a stderr warning about all
three on every sourced run today — the exact failure it was written to catch, recurring.

Related: `skills/checkpoints/` has **no row in `skill-routing.tsv` at all**, though
`conversion-runbook.md:202,253,337,420` calls the CAC files mandatory and `gate-check.sh:737`
depends on `checkpoint-extraction.md`. The files exist; the wiring that makes them reachable does
not.

~~Also unwired: `bin/lib/skill-routing.sh:316` defines `routing_missing_paths()`, called by
nothing.~~ **RETRACTED 2026-08-20** — this was wrong. It is called at `bin/render-routing.sh:174`
as the advisory `GHOSTS` note, in both render and check modes, and was already present at
`40c63ac`. The audit that reported it read the tree correctly and drew the wrong conclusion; it is
recorded here rather than deleted because a retraction that leaves no trace is how a false finding
gets rediscovered and re-fixed.

### Finding 9 — the ledger check cannot tell "never applicable" from "genuinely missing"

Finding 3 above concluded that ledger faults on a Track B app are by-design. That reasoning is
sound but **does not apply to VB-USI**, and the discrepancy exposes a deeper bug.

`VB-USI-main/PROJECT.md:16` records `Entry mode: Migration (Stages P, 0–7 all run)` — CONFIRMED,
2026-08-06. It has `blueprint.md`, `build-plan.md`, 7 module briefs, 12 BRDs. It should have
ledgers. It has none. Meanwhile `PROJECT.md:10` records that the *current* work is à-la-carte
Track B assurance with no pipeline stage active. **A Migration project running a Track B pass** —
so entry mode alone cannot decide the verdict, and `conformance-check.sh:53` faults identically in
both cases.

**Second, separate defect:** `architecture/modules/` in VB-USI is flat (`Approval-brief.md`,
`ProductNumbers.md`), zero subdirectories — but `conformance-check.sh:52` and
`verify-module.sh:286` glob `architecture/modules/<Module>/coverage-ledger.md`, requiring per-module
*directories*, and `verify-module.sh:287` falls back to a project-level `architecture/coverage-ledger.md`,
a third shape. Nothing creates the shape the scripts want.

**Third:** `architecture/build-plan.md` contains **zero** occurrences of `claims`. It was produced
2026-08-06 at toolkit commit `d80f883`, predating the convention. So the join that
`skills/coverage-ledger.md` describes ("generated from the BRD and the build plan's `claims` field")
has only one of its two inputs.

### Finding 10 — `build-plan-method.md` is cited as an authority and has never existed

`skills/coverage-ledger.md` cites `build-plan-method.md` four times as normative: `:7` (when the
method applies), `:11` (the `claims` field is defined "per" it), `:51` ("**Block form, never table
form.** See `build-plan-method.md` §3"), `:199` (the `acceptance` field, "per §6").

`git log --all --diff-filter=A -- '*build-plan-method*'` returns nothing. **No commit on any ref
ever added the file.** Two of the four citations name section numbers of a document that was never
written.

Consequence: **"block form, never table form" and the `acceptance` field are specified nowhere in
this repo.** The second one is load-bearing — `:199` is the line arguing that coverage proves
accounting rather than correctness, and that `acceptance` is the defence against a row claiming
`/rightPanel` and building the wrong panel. That defence does not exist.

This is the cheapest possible illustration of the failure this whole document is about: a citation
carrying a section number reads as *more* authoritative than plain prose, and nothing anywhere
checks that its target exists. `routing_missing_paths()` (Finding 8) would not have caught this
either — the reference is in skill body text, not in a routing row.

### Why the small case works and the large one does not

Asking an LLM to write one e2e test works because author and consumer are the same agent in the
same context: it writes, runs, sees the real failure, fixes it, and the loop closes in ninety
seconds. Nothing crosses a boundary. At harness scale — config → script → runner → normalizer →
renderer → gate — the contracts live in the gaps between files, and an agent authoring a journey
file never executes the far end of the chain, so it never learns its contract was wrong.

Worse, aggregation *launders* absence. To produce any report across 611 checks the normalizer must
tolerate a missing input, otherwise one absent instrument kills the run. But fault-tolerance is
absence-tolerance: the moment you can survive a missing instrument, "did not run" becomes a table
row instead of a crash, and table rows average. At one test, absence is a stack trace in your face.

### Decisions taken (2026-08-20, with the repo owner)

These close options left open in Findings 1–4 and set the constraints for the fixes now in flight.

1. **Nothing blocks.** This is a shared toolkit; other people run it on their own projects. A
   surprising new gate would be switched off rather than obeyed, spending the toolkit's credibility
   to fix one project. The postmortem's original ask — make `fault` block Stage 4 — is **rejected**.
2. **The number stops lying instead.** The report leads with coverage, not pass-rate: *"58% of
   checks did not run"* above the fold, and no percentage anywhere may use a denominator that
   excludes faults. This blocks nobody and is the only thing that actually failed.
   Precedent already in-repo: `bin/questions-report.sh:72` refuses to render a clean-looking zero.
3. **Plumbing before gating.** Findings 5–8 are fixed first, so that any later signal fires on
   instruments that are actually present.
4. **Four fallback levels for the ledger check**, keyed on what is present rather than declared
   entry mode (Finding 9 shows entry mode is not decisive): ledger → derive from BRD+`claims`
   (labelled DERIVED) → BRD only, report an honest denominator plus the named remedy → no BRD, not
   applicable, said quietly.
5. **Never reverse-derive requirements from the live model.** Finding 3 option 2 stands rejected.
   Deriving from BRD + build plan is a join over *decided* artifacts; deriving from shipped code
   inverts what a requirement means. `report-schema.md` already forbids synthesizing a requirement
   pointer.
6. **`claims` required on new build-plan rows only.** Written at authoring time, when it costs one
   line and the author knows the answer. Existing plans without `claims` are an accepted state, not
   a defect — VB-USI must not start reading as broken. Backfilling VB-USI is a separate, optional
   track.
7. **Module briefs are not a ledger substitute.** Prose design intent, no leaf pointers, and the
   granularity does not line up (7 briefs vs 12 feature BRDs). Usable as a cross-check only.

### Finding 11 — a second phantom instrument, and the check that would have caught both

`mobile-fieldscan` was declared at `project.config.template.js` alongside `full-app-walkthrough`.
`git log --all --diff-filter=A -- '*mobile-fieldscan*'` finds no commit that ever added it either.
Two of the template's declared slots were scripts nobody wrote.

Neither `_mxtk_manifest_check_bin` nor `_mxtk_manifest_check_tests` could catch this: both walk
*manifest lists*, and these references live in a `script:` string inside a config template. Fixed
by a new forward check, `_mxtk_manifest_check_walkthroughs()` in `bin/lib/install-manifest.sh`,
which parses `script:` out of the uncommented slots and hard-fails on any that names a missing
file. Commented-out slots are ignored deliberately — parking an instrument that way is legitimate,
and `mobile-fieldscan` is now parked exactly so.

### What landed, 2026-08-20

All in the working tree, uncommitted, none of it executed (see "Still open").

- **Findings 5, 11** — `full-app-walkthrough.js` written (config-driven, multi-role, signs out and
  back in at every handoff, refuses to report a single-persona run as end-to-end); added to
  `MXTK_PROJECT_TESTS`; `mobile-fieldscan` slot parked; `_mxtk_manifest_check_walkthroughs()` added.
- **Finding 6** — `install-tests.sh` wired into `init-project.sh` and a new `sync-project.sh`
  section 4b that diffs before installing and never overwrites `project.config.js` or `artifacts/`.
  `_mxtk_manifest_check_tests_wiring()` promoted from warning to hard failure, as its own comment
  had instructed.
- **Finding 7** — `bin/lib/resume-template.sh` added; `init-project.sh` scaffolds
  `docs/progress/RESUME.md` create-if-absent, `sync-project.sh` section 4a backfills it, and
  `wire-agents.sh:93-99` now names its producer and a real fallback. The template deliberately
  asserts no stage — a scaffold guessing "Stage P" would be confidently wrong on any mid-flight
  project it is backfilled into.
- **Finding 8** — the three scripts added to `MXTK_PROJECT_BIN`. Note `close-task.sh:86` resolved
  `done-drift-check.sh` as its own sibling, so the backstop `iterative-build-loop.md:49` describes
  as "surfaced automatically" had been surfacing nothing in every project. Eight
  `skills/checkpoints/` routing rows added; `render-routing.sh --check` passes.
- **Finding 9** — `project-bin/coverage-preflight.sh` implements the four levels. Canonical shape
  stays `architecture/modules/<Module>/coverage-ledger.md`; the flat and project-level shapes are
  read but not canonical, and all three are printed by name when none is found.
  `conformance-check.sh` no longer hard-FAULTs, and refuses level 2 for itself specifically — a
  derived ledger has no `acceptance` cells and synthesizing them is the inversion being refused.
  Measured against VB-USI: **4012 leaves across 12 BRDs, level 3, zero traceable.**
- **Finding 10** — the four phantom citations repointed; block form and the `acceptance` field now
  specified inline in `coverage-ledger.md`, written against what `conformance-check.sh` actually
  reads so the two cannot drift.
- **Decision 2** — one denominator throughout `report-render.js`, coverage band above the verdict,
  no pass rate anywhere, "produced no evidence" as its own instrument axis, and faults now name
  their producer. No schema change: `schemaVersion` stays 1.2.
- **Decision 6** — Step 5b in `brd-to-build-plan.md`, new rows only, non-blocking.
- **Also fixed, found late:** `verify-module.sh`'s coverage rung short-circuited on
  `[ -f "$LEDGER" ] && [ -n "$BRD" ]`, which made levels 2-4 unreachable from the one command every
  module review runs — the grading layer would have shipped dead on arrival, Finding 2's failure
  repeated on the same day it was being fixed. Now routes through the preflight, with a direct-engine
  fallback for projects that have not synced.

### Still open

- **Nothing here has been executed.** Per this repo's standing rule no test was run — not
  `run-all.sh`, not a fixture, not a selftest. Verification was `bash -n`, `node --check`,
  inspection, and (flagged by its author) three read-only runs of the new preflight against
  VB-USI and throwaway `/tmp` dirs that wrote nothing. The code is reviewed, not proven.
- **Finding 4 is untouched and is now larger.** There is still zero automated coverage over the
  runtime-verification seam, and today's work added to what that seam carries. This is the single
  biggest remaining exposure in this document: every fix above is exactly the kind of change the
  missing fixtures would have caught.
- `bin/install-tests.sh` has no `--dry-run`; sync short-circuits before the call to keep its own
  dry-run honest.
- `checkpoint-cutover.md` is migration-only but the routing table has no mode column, so it routes
  at stages 6-7 in every entry mode. A mode column is the real fix; it is a table-schema change.
- Backfilling `claims` into VB-USI's build plan (12 BRDs, 4012 leaves, against a built app) — not
  scheduled, and explicitly optional.
- Two known engine/config violations still logged at `install-manifest.sh:130-132`
  (`helpers.js:473-540` hardcodes one app's widget names; `dismissModal` uses a literal selector).
