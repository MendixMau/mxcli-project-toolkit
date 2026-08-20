# Improvement Plan — e2e/regression test coverage and the UI-findings gap

**Author:** Maurits Visser (with Claude Code)
**Created:** 2026-08-20
**Status:** OPEN — findings confirmed against the toolkit's own source; no code changes made yet.
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

## To merge

A parallel investigation is running on another machine, hitting related issues from a different
project. Findings from that session are not yet included here — append them under a new heading
once available, rather than opening a second document, so there is one place tracking this.
