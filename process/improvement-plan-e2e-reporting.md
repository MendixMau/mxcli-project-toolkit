# Improvement Plan — e2e/regression test coverage and the UI-findings gap

**Author:** Maurits Visser (with Claude Code)
**Created:** 2026-08-20
**Status:** OPEN — fixes in flight. Findings 1–4 confirmed against the toolkit's own source;
Findings 5–11 merged 2026-08-20 from the PROJECT-A postmortem and a toolkit-wide wiring audit;
Findings 12–15 merged 2026-08-22 from PROJECT-C, the first end-to-end pipeline run this document
has evidence from. Decisions taken are recorded mid-document and govern the work now underway.
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

## Merged — PROJECT-A postmortem + toolkit-wide wiring audit (2026-08-20)

The parallel investigation completed. Its project was `PROJECT-A`; a static wiring audit of the
whole toolkit ran alongside it. Both are folded in below. **Status of this document changes from
OPEN/no-code-changes to OPEN/fixes-in-flight** — see "Decisions taken" at the end, which resolves
several options Findings 1–4 above left undecided.

### The trigger, from the other side

A full harness run against PROJECT-A (6 modules) reported 611 checks: **205 pass / 23 fail /
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

Harness code was ruled out as the cause: diffed against sibling `PROJECT-C` at the same
toolkit commit `5acd442`, `monkey.js` / `design-audit.js` / `report-normalize.js` are byte-identical
and PROJECT-A's `journey-runner.js` is actually ahead by two local fixes.

### Finding 5 — `full-app-walkthrough.js` has never existed in this repo

`project-tests/e2e/project.config.template.js:381` declares the instrument slot; `report-normalize.js`
treats it as expected and at `:1143` stamps it `canExpressFault:false, evidenceStrength:'weak'`.
There is no `full-app-walkthrough.js` anywhere in the toolkit. `PROJECT-C` hand-authored its
own because the toolkit never shipped one; PROJECT-A never got one. So the fault above was not a
misconfiguration — the script does not exist.

This is the same disease as Finding 2, one step earlier: Finding 2 is a real instrument that never
gets *called*; Finding 5 is a declared instrument that was never *written*.

### Finding 6 — the e2e harness never installs into any project

`bin/lib/install-manifest.sh:317-348` documents this against itself and it is still true at HEAD:
`grep -n 'install-tests' bin/init-project.sh bin/sync-project.sh` returns nothing. `MXTK_PROJECT_TESTS`
(16 files in `project-tests/e2e/`) installs nowhere — while `project-bin/verify-module.sh` *is*
installed and drives `journey-runner.js`, four skills cite `tests/e2e/*` paths, and
`skill-routing.tsv:81` routes `verify-module.sh` as a **baseline** skill for stages 5–6.

Confirmed from the project side: PROJECT-A's `tests/e2e/` is a hand-assembled partial copy. Missing
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
sound but **does not apply to PROJECT-A**, and the discrepancy exposes a deeper bug.

`PROJECT-A/PROJECT.md:16` records `Entry mode: Migration (Stages P, 0–7 all run)` — CONFIRMED,
2026-08-06. It has `blueprint.md`, `build-plan.md`, 7 module briefs, 12 BRDs. It should have
ledgers. It has none. Meanwhile `PROJECT.md:10` records that the *current* work is à-la-carte
Track B assurance with no pipeline stage active. **A Migration project running a Track B pass** —
so entry mode alone cannot decide the verdict, and `conformance-check.sh:53` faults identically in
both cases.

**Second, separate defect:** `architecture/modules/` in PROJECT-A is flat (`Approval-brief.md`,
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
   a defect — PROJECT-A must not start reading as broken. Backfilling PROJECT-A is a separate, optional
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
  Measured against PROJECT-A: **4012 leaves across 12 BRDs, level 3, zero traceable.**
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
  PROJECT-A and throwaway `/tmp` dirs that wrote nothing. The code is reviewed, not proven.
- **Finding 4 is untouched and is now larger.** There is still zero automated coverage over the
  runtime-verification seam, and today's work added to what that seam carries. This is the single
  biggest remaining exposure in this document: every fix above is exactly the kind of change the
  missing fixtures would have caught.
- `bin/install-tests.sh` has no `--dry-run`; sync short-circuits before the call to keep its own
  dry-run honest.
- `checkpoint-cutover.md` is migration-only but the routing table has no mode column, so it routes
  at stages 6-7 in every entry mode. A mode column is the real fix; it is a table-schema change.
- Backfilling `claims` into PROJECT-A's build plan (12 BRDs, 4012 leaves, against a built app) — not
  scheduled, and explicitly optional.
- Two known engine/config violations still logged at `install-manifest.sh:130-132`
  (`helpers.js:473-540` hardcodes one app's widget names; `dismissModal` uses a literal selector).

---

## Merged — PROJECT-C plan-vs-execution review (2026-08-22)

### What this is

PROJECT-C ran the pipeline end to end — Stages P through 6, requirements-driven entry mode, one
module, 50 build-plan steps, a real booted app. It is the first full-pipeline run this document has
evidence from; Findings 1–11 were written from an à-la-carte Track B pass and from PROJECT-A, a
Migration project that never ran the later stages. Reviewed against the toolkit at `f2d1a5a`.

**It independently confirms Findings 5, 9, 10 and 11 from a third project**, which matters: those
were diagnosed on projects that had *skipped* stages, leaving open the reading that the artifacts
were missing because the stage never ran. PROJECT-C ran every stage, passed every gate through
Stage 4, and still produced no ledger, no journeys and no Stage 5/6 surface. So the cause is not a
skipped stage. It is that **nothing in the spine ever asks for them.**

Findings 12–15 below are the delta — none of them are restatements of 5–11.

### What went well, and it is not a courtesy paragraph

The property this whole document exists to protect **held under a full autonomous run**:

- Coverage reported `UNMEASURED`, not PASS. Graph-sweep reported `FAULT` (missing `sqlite3`), not
  skipped. The module was denied its `done-` prefix on the strength of those two, with the reasons
  named. A gate that had every incentive to round up did not.
- 15 improvement-register rows, each carrying status, evidence and commit; the two it could not fix
  are logged as open rather than waived. The no-silent-fix rule survived contact.
- Self-correction inside the run: the first fix for IR-10 was wrong, was re-probed against the live
  runtime, and was corrected — `$currentUser/Name` is Mendix `empty`, not `''`, so the original
  guard let nulls through. The same bug class was then found twice more independently.
- IR-12 — the app could only ever boot once, because the seed microflow's idempotent branch returned
  `false` and the runtime reads that as startup failure. A deploy blocker, found and proven fixed
  across ten restarts.
- **IR-15 vindicates Finding 1's fix.** A live browser walk found that `ACT_RoutingVersion_Approve`
  never created the record the Approval History page reads, so that screen was permanently empty for
  every approval ever made. Eight of eight passing MDL tests did not catch it. Nothing but looking
  would have.

The gaps below are all *producer-side*. None of them are a discipline failure by the run.

### Finding 12 — the ledger has eleven consumers and no producer in the spine

The ledger is read by eleven executable files — `gate-check.sh`, `brd-report.sh`, `verify-module.sh`,
`conformance-check.sh`, `coverage-preflight.sh`, `review-module.sh`, `report-disposition-check.sh`,
`report-normalize.js`, `report-render.js`, `review-report.js`, plus the routing table — and is cited
as normative by ten other skills and all four build-side agent files. It is a hub artifact. Its producer side is broken
in three independent places, all in the two files a session is *required* to read:

1. **`conversion-runbook.md` Stage 4 "Agent produces"** names `architecture/build-plan.md` and the
   first module brief. It does not name `coverage-ledger.md`. The spine never asks for the artifact.
2. **The Stage 4 `✋` gate row** asks for pending-decisions, the role-to-access table, and CONFIRMED
   decisions mapping to build-plan rows. It says nothing about coverage, `claims`, or the ledger.
3. **`check_stage_4()` (`bin/gate-check.sh:953-966`) checks exactly two things** — that
   `build-plan.md` exists, and that `PROJECT.md` carries a Stage-4 CONFIRMED decision. A build plan
   with zero `claims:` blocks passes Stage 4 cleanly, which is what happened.

Meanwhile `skills/coverage-ledger.md:264-272` carries a section headed **"Integration with Stage 4
Gate"** whose body is an instruction — *"Add to the Stage 4 (✋) checklist in
`conversion-runbook.md`"* — followed by three checkboxes. **That edit was never made.** The skill has
documented its own integration as though it exists for as long as it has existed.

**A contributing cause worth naming separately: a name collision.** The runbook uses the phrase
*"coverage checklist"* at Stage 5 for the per-module business-rule checklist out of `module-brief.md`
— a different artifact with a different producer, granularity and purpose. The words *"coverage
ledger"* appear nowhere in `conversion-runbook.md`. An agent reading the spine sees coverage
addressed at Stage 5, produces the thing the spine named, and never learns a second coverage artifact
was owed at Stage 4.

**This is a gap in Decision 6, not a contradiction of it.** Requiring `claims` on new rows only is
right. But `claims` is authored into the build plan at Stage 4, and Stage 4 is precisely where
nothing asks for it — so on current wiring a brand-new project reaching Stage 4 tomorrow still
produces a plan with no `claims`, and the four-level fallback lands on level 3 forever. The producer
edit is what makes Decision 6 reachable.

### Finding 13 — the cross-persona journey has no owner, and its tombstone only half-landed

The swim-lane view of a process — one flow, across modules, across personas, with the handoffs
asserted — is exactly what a per-module journey suite structurally cannot see. The toolkit has
approached it twice and currently ships neither.

**Design-time half: dropped, correctly, on 2026-08-21.** `skills/journey-map.md` was a 529-line
method (L0→L3 binding, normative L1 table schema, refusal classes, a `journey-lint` list). Its own
falsification trial failed — 2a `INVALID` on every pairing, 2b untested — and it is now a 20-line
tombstone. That is the promote-only-on-a-watched-red rule working on itself, and it was the right
call.

**But the tombstone did not reach the routing table.** `bin/lib/skill-routing.tsv:145` still carries
the row, tagged `experimental`, routed to `ba`, `architect` and `test` at stages 2, 3 and 4 — and it
has therefore been rendered into `ROUTING.md:89`, `agents/ba-agent.md:77`,
`agents/architect-agent.md:58` and `agents/test-agent.md:56`, each advertising it by its original
description ("Authoring the cross-module user journey ONCE at design time…"). Three agent roles are
still told a tombstoned method is an available option. The comparison that makes this a slip rather
than a judgement call: the repo's two other tombstones, `ui-review-loop` and
`module-completion-loop`, have **no** row in the tsv. This one does.

The tombstone's own text also asserts the file "was never reachable from README.md's routing tables
or `conversion-runbook.md`". True of `README.md` and the runbook; not true of `ROUTING.md` or the
three agent files, which are generated from the same table. Worth correcting when the row goes.

**Executable half: Finding 5, still open.** `full-app-walkthrough.js` is the cross-role instrument —
log in as A, do A's work, assert the DB effect, *log out*, log in as B, assert B can see what A
produced. Its slot is declared in `project.config.template.js` and `report-normalize.js` grades it;
the script has never existed in this repo. PROJECT-C is the project that hand-authored one, and its
header states the requirement better than any toolkit file currently does: *"it LOGS OUT and logs in
as role B — no session reuse, no impersonation switch — and asserts that B can see the state A
produced. That assertion is the handoff, and it is the reason this file is not six journey files."*
When Finding 5's fix lands, that file is the reference implementation, not a blank page.

**It did not run in PROJECT-C either**, for a third reason independent of both halves:
`tests/e2e/project.config.js` still carries another project's placeholder values — module
`RoutingManagement` against an app whose module is `RoutingMgmt`, users `erika.engineer` against demo
users named `route.*`, a `PROBE_PAGE` naming a page that does not exist here, port 8081 against an
app served on 8080. The run logged this and made an explicit, recorded judgement call to substitute a
hand-driven live browser walk. That substitution is what found IR-15, so it was not a bad call — but
porting the config is a real per-project cost that no stage currently owns.

**So the need is unmet on all three fronts, and PROJECT-C shows the shape of the hole**: twelve
wireframes, one per screen, full coverage — and no artifact anywhere claiming a screen *order* or a
persona handoff. Every module green, the seams between them measured by nothing. Dropping the
unproven method was right; it leaves the requirement unowned, and that should be recorded as an open
need rather than closed with the file.

The executable half of the same idea is Finding 5's `full-app-walkthrough.js`, and PROJECT-C is the
project that hand-authored one. Worth recording that its header states the requirement better than
any toolkit file currently does: *"it LOGS OUT and logs in as role B — no session reuse, no
impersonation switch — and asserts that B can see the state A produced. That assertion is the
handoff, and it is the reason this file is not six journey files."* When Finding 5's fix lands, that
file is the reference implementation, not a blank page.

**It did not run in PROJECT-C either**, for a reason that is neither the banner nor Finding 5:
`tests/e2e/project.config.js` still carries another project's placeholder values — module
`RoutingManagement` against an app whose module is `RoutingMgmt`, users `erika.engineer` against demo
users named `route.*`, `PROBE_PAGE` naming a page that does not exist here, port 8081 against an app
served on 8080. The run logged this as friction and made an explicit, recorded judgement call to
substitute a hand-driven live browser walk. That substitution is what found IR-15, so it was not a
bad call — but it is a per-project porting cost that currently has no step that owns it.

### Finding 14 — the HTML surfaces stop dead at the Stage 4/5 boundary, and Stage 6 cannot pass

The runbook promises a surface per stage. Measured against PROJECT-C:

| Stage | Promised surface | Present |
|---|---|---|
| P | `index.html` | yes |
| 0 | `source-sufficiency.html`, `triage.html` | yes, both |
| 1 | `extraction-report.html` | yes |
| 2 | `analysis/brd-report.html` | yes |
| 3 | `module-design.html`, `blueprint.html`, `design-system.html`, `wireframes/*.html` | yes, all four (12 wireframes) |
| 4 | `build-plan.html` | yes |
| 5 | `design/ui-reviews/ui-review-<date>.html` | **no** |
| 6 | `test-report.html`, `ui-review-*.html`, `docs/report.json` | **no, none of the three** |

Not a gradual decline — a clean break at one boundary, and the boundary is structural. **Every
Stage 0–4 surface has a generator in `bin/` that some stage procedure tells you to run**
(`source-sufficiency.sh report`, `triage-report.sh`, `brd-report.sh`, the blueprint render).
**No Stage 5 or 6 surface has one.** The rendering code exists and is substantial —
`report-normalize.js` and `report-render.js` are ~310KB between them, both self-testing and
deterministic — and Finding 2 already records that `verify-module.sh` never invokes it. What
PROJECT-C adds is the consequence at the *gate*:

**`check_stage_6()` (`bin/gate-check.sh:968-987`) requires both `test-report.html` and a
`ui-review-*.html` under a `ui-reviews/` directory, and fails naming each.** Nothing in the toolkit
produces either file. So Stage 6 is not merely un-surfaced, it is **structurally un-passable in every
project** — the terminal gate of the pipeline cannot be satisfied by any sequence of correct work.
PROJECT-C did the Stage 6 work (real boot, live OQL, 8/8 microflow proofs, a full live lifecycle walk
across two roles, ten verified restarts) and still cannot pass the gate that asks whether Stage 6
happened.

This also answers the question the run's own `artifacts.md` raises honestly and cannot resolve: it
records that no Stage 5/6 HTML was produced and attributes it to the sweep being interactive rather
than scripted. That is true of *that* sweep, but it is not the cause. The cause is that no procedure
anywhere invokes the renderer.

### Finding 15 — `page-scope.sh` is a third phantom, and it is the one that weakens the LOOK rung

`design-audit.js:55` and `page-audit.js:66` both read `.claude/loop/page-scope.json`.
`harness-architecture.md` documents its producer four times — `:75` in the machine diagram, `:142` in
the run sequence (`./bin/page-scope.sh`), `:174` on scope-flag handling, `:342` in the
instrument/scope table. `examples/port-the-harness.prompt.md:83` already flags it in passing.
**No such script exists in the toolkit or in any project.**

Same class as Findings 5 and 11, but it evades the fix those got.
`_mxtk_manifest_check_walkthroughs()` parses `script:` slots out of the config template; this
reference lives in skill prose and in two `require`-time path constants. It is Finding 10's blind
spot (a skill citing a file that was never written) with an executable consumer attached — the
combination neither existing check covers.

**Why it matters more than the other two:** `design-audit.js` degrades to `--static-only` without a
scope file, which is the correct fail-loud behaviour and is exactly what PROJECT-C did. But that
means **the LOOK rung runs at reduced evidence in every project, by construction, and always has.**
The original complaint that opened this document was an e2e run reporting zero UI findings. Finding 2
explains why the *report* was thin; this explains why the *instrument* was too.

### The single pattern, now seen six times

Findings 2, 5, 10, 11, 12, 13 and 15 are one defect wearing seven faces:

> **A consumer was written, routed and gated against an artifact whose producer was never wired into
> the stage that owns it.**

The toolkit's central rule — *absence is never a pass* — is correct, is implemented, and is working:
every one of these surfaces as a FAULT or an UNMEASURED rather than a false green. But the rule is
only ever applied at the **consumer** end. Nothing applies its mirror at the **producer** end:

> If any script, gate or skill reads artifact X, some stage's *"Agent produces"* row must name X, and
> that stage's gate must check that it exists.

Without that mirror, every correctly fail-closed consumer becomes a permanent red that no amount of
correct work can clear — and a permanent red gets routed around, which costs more than the guard was
ever worth. PROJECT-C is that outcome, measured: two instruments permanently faulted, one gate
permanently unpassable, all three logged honestly and all three unfixable from inside the project.

**The check this implies is mechanical and is the one that would have caught all seven.** Walk every
artifact path read by `bin/`, `project-bin/` and `project-tests/e2e/`, and every path cited as
normative in a `skills/*.md` body; assert each appears in some runbook stage's produces row or is
explicitly declared optional. That is `render-routing.sh --check` shaped — a cross-file consistency
assertion over files that already exist — and it belongs next to
`_mxtk_manifest_check_walkthroughs()`, which is the same idea applied to one file format.

### Finding 16 — the architecture artifact set has the same three breaks, and one of them is a diagram nobody drew

Prompted by the question *"on architecture, don't we also need other artifacts — and if there's a
workflow in the app, shouldn't we draw the process flow?"* Checked, and the answer is that the
toolkit already specifies all of it. Three separate producer-side breaks stopped it landing.

**16a — the state diagram is bound to the implementation, not the domain shape.**
`architecture-blueprint.md` Step 3b already specifies exactly the artifact the question asks for: one
Mermaid `stateDiagram-v2` per Workflow-shaped process, states as tasks, transitions as outcomes,
embedded in `blueprint.md`. It is conditional on `checkpoint-architecture.md` CAC-3 Q3, whose two
options are:

> - A) Native Mendix Workflow for the human-approval parts, microflows for automated transitions
> - B) Microflows only — simpler, no Workflow module dependency, **no extra diagram**

So the state view is bundled to the *implementation technology* and traded away with it. This is
backwards. The diagram is a **comprehension** artifact, and its value does not depend on where the
states are stored — if anything option B needs it *more*, because a native Workflow at least renders
itself in Studio Pro, while an enum-plus-microflows lifecycle is drawn nowhere by anything, ever.

PROJECT-C is the demonstration. Its entire domain is a six-state, role-gated lifecycle —
`ENUM_ReleaseStatus` (Draft → Validated → Submitted → Approved → Released → Retired), three module
roles, a separation-of-duties guard on Approve, and a whole entity (`RouteStateHistory`) that exists
solely to record transitions. Zero native Workflow constructs, so option B, so no diagram.
`blueprint.md` carries two Mermaid blocks: layer and wiring. **There is no picture of the lifecycle
anywhere in the project** — not in the blueprint, not in the module brief, not in the wireframes.
The one thing a reviewer most needs to see to judge whether the process is right is the one thing
nothing draws.

**And the trigger never actually fired.** `checkpoint-architecture.md:101` requires the answer be
recorded as `PROJECT.md` → `## Decisions` → `Workflow scope:`. PROJECT-C's `PROJECT.md` contains no
such line, and `run/decisions.md` — 31KB of every gate exchange verbatim — contains no occurrence of
"Workflow" at all. So this was not "option B chosen deliberately". **The question that decides
whether the process gets drawn was never put to the user.** Same producer-side shape as Findings 12
and 13: the artifact is specified, its trigger is specified, and nothing makes the trigger happen.

**16b — the Step 1 module definition doc is not produced, and the path shape disagrees.**
`architecture-blueprint.md` Step 1 mandates one module definition doc per module, and its own
"Output of This Skill" tree names `architecture/modules/<ModuleName>.md` — entities, key microflows,
pages, security, dependencies, at Stage 3. PROJECT-C has `architecture/modules/RoutingMgmt/module-brief.md`,
which is the **Stage 4** artifact from a different skill. The Stage 3 doc does not exist.

Note the path shape: the skill says `modules/<ModuleName>.md` (a file), the project has
`modules/<ModuleName>/module-brief.md` (a directory). That is the same file-vs-directory disagreement
Finding 9 recorded for the ledger glob, on a different artifact — worth checking whether anything
globs for the Step 1 doc and silently finds nothing.

**16c — `open-issues.md` is superseded in the runbook and still live in the skill.**
`conversion-runbook.md:589` states `PROJECT.md` "Absorbs `architecture/open-issues.md`". But
`architecture-blueprint.md` still lists it in its output tree (`:44`), still has a whole Step 5
producing it (`:204`), still routes gaps into it from the fit-gap vocabulary (`:196`) and from Step
6's three decisions (`:245`) — and `brd-to-build-plan.md` still consumes it as a named upstream input
(`architecture-blueprint.md:6`: "the open-issues register as the questions the plan must answer
before script 01"). PROJECT-C produced no `open-issues.md`, correctly per the runbook, which means
the downstream consumer's named input does not exist.

**This is the journey-map tombstone pattern exactly**: a supersession that landed in one file and not
in the file that produces the thing. Either the skill drops Step 5 and points at `PROJECT.md`, or the
runbook line is wrong. Both cannot be right.

**The general shape.** Two of the three architecture artifacts a reviewer would most want — the
process state view and the per-module definition — are specified, unproduced, and unnoticed, because
in each case the *only* thing standing between spec and artifact was a conditional nobody evaluated
or a producer nobody ran. Add the cross-persona journey (Finding 13) and the pattern is complete:
**the toolkit's design-time comprehension artifacts — the ones that answer "is this the right
process?" rather than "did it build?" — are the least mechanically enforced things in it.**

### Proposed, not decided — the full register

Every proposal arising from Findings 12–16, ordered by cost. All producer-side. **None of them
gating** — Decision 1 stands, and nothing here adds a new blocking check.

| # | Proposal | Closes | Cost |
|---|---|---|---|
| P1 | Add `architecture/coverage-ledger.md` to the runbook's Stage 4 "Agent produces" row, and make the three checkboxes `coverage-ledger.md:266-270` has been asking for since it was written. Resolve the "coverage checklist" / "coverage ledger" name collision by naming both in the Stage 5 row. | 12 | 3 lines |
| P2 | Finish the `journey-map.md` tombstone: drop its row from `bin/lib/skill-routing.tsv` and re-render, as both earlier tombstones already are; correct the tombstone's claim about which tables reached it. | 13 | 1 row + render |
| P3 | Reconcile `open-issues.md`: either drop Step 5 from `architecture-blueprint.md` and repoint its four internal references plus `brd-to-build-plan.md`'s named input at `PROJECT.md`, or correct `conversion-runbook.md:589`. One of the two is wrong. | 16c | 1 file |
| P4 | Rebind Step 3b's trigger from the implementation to the domain shape: draw the `stateDiagram-v2` whenever a lifecycle enum drives role-gated transitions, whether or not it is a native Mendix Workflow. Delete "no extra diagram" from CAC-3 Q3 option B — it is not a benefit. | 16a | 1 skill + 1 checkpoint |
| P5 | Make CAC-3 Q3 actually fire. The question was never put in PROJECT-C and its `PROJECT.md` line is absent; whatever makes the other checkpoint questions reliable should cover this one. | 16a | needs diagnosis first |
| P6 | Add `design/journeys/` (or whatever replaces it) to the runbook's Stage 3 "Agent produces", once Finding 13's open need has an owner. Not actionable until then. | 13 | blocked on P2 |
| P7 | Produce the Step 1 module definition doc at Stage 3, and reconcile `modules/<Module>.md` (file, per the skill) against `modules/<Module>/` (directory, per every project) — the same shape disagreement Finding 9 found on the ledger glob. | 16b | 1 skill + a glob audit |
| P8 | Write `page-scope.sh`, **or** delete its four citations from `harness-architecture.md` and record `--static-only` as the supported mode. Either is honest; the current state is not. | 15 | script, or 4 deletions |
| P9 | Invoke the renderer from the Stage 5/6 procedure (Finding 2's fix). `check_stage_6()` needs no change — it becomes satisfiable the moment something produces its two inputs. | 2, 14 | procedure + wiring |
| P10 | The producer-side mirror check: walk every artifact path read by `bin/`, `project-bin/`, `project-tests/e2e/` and every path cited as normative in a `skills/*.md` body; assert each appears in some stage's "Agent produces" row or is explicitly declared optional. | all | the expensive one |

**P1–P3 are the cheap, unambiguous ones** — each is a correction to a file that already contains the
contradiction, and none of them require a decision about what the toolkit should do, only that it
stop saying two things at once.

**P10 has the least evidence behind it.** It is a proposal generalized from a pattern seen eight
times, not a measured fix, and it should be judged that way — it is also the only one that stops
the ninth.

### The through-line, stated plainly

Findings 2, 5, 10, 11, 12, 13, 15 and 16 are one defect. But 13 and 16 sharpen what kind:

> The toolkit enforces **"did it build?"** mechanically and **"is this the right process?"** not at
> all.

Every instrument that measures construction — lint, gates, conformance, journeys, monkey, the
verdict vocabulary — is wired, fail-closed and hard to skip. Every artifact that supports *judgement*
— the state view, the cross-persona journey, the module definition doc, the per-step narrative report
— is conditional, unproduced, or tombstoned, and nothing notices when it is missing. That asymmetry
is not an accident of any one file; it is what happens when the producer-side mirror rule (P10) has
never existed, because construction artifacts have scripts that emit them and comprehension artifacts
only ever had prose asking someone to write them.
