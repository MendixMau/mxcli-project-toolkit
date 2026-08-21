# Skill: Full harness audit — running the whole testing stack for real, not by title

**When to use:** the user asks for a "full end-to-end test," a "click-through proof," or "does
everything actually work" — and especially when they've already caught a report calling something
"e2e" that only covered one module or one action. Also use this as the entry point whenever you
are not sure which of the harness's many skills applies; it routes you to the right one instead of
guessing.

**What this is:** a map of the whole testing harness — every layer, every instrument, what each
one catches that its neighbors don't — plus a single reusable trigger prompt that actually engages
all of it in one connected pass. It does not replace any skill it names; it is the thing that
stops those skills from being individually correct and collectively never invoked.

**Why this exists.** On a live project (2026-08-21), an agent ran a real, narrated,
headed-browser click-through of one module, called it "the e2e test," and produced a report that
looked complete. The user asked a direct question — "this is not really e2e, is it?" — and it
wasn't: one module walked fully, one action spot-checked, four other built modules untouched, three
of four personas never logged in as. Separately, the same session found that
`process-coherence-pass.md` and `wiring-sweep.md` were both named in `gate-check.sh`'s required-
skill lists and both had a formal row in `obligations.tsv`, and neither had ever produced an
artifact in that project's history — not once, on any module. Being *listed* is not being *run*.
This skill exists so the next session doesn't have to re-derive either lesson from scratch.

---

## 1. The layer stack — what exists, and who owns it

Five layers. Layer 2 (model-side) never calls layer 3 (runtime), and layer 3 never calls layer 2 —
layer 1's orchestrators are the only place they meet. Full architectural detail, seams, and the
honest-degradation contract: `harness-architecture.md`. This section is the map; that file is the
territory.

```
LAYER 4  content        journeys/<Module>.journey.json · coverage-ledger.md · BRDs
LAYER 3  runtime engine  journey-runner.js · monkey.js · report-normalize/render.js
LAYER 2  model-side      test-stack-up.sh · conformance-check.sh · graph-sweep.sh ·
                         coverage-check.sh · fixture-manifest.sh
LAYER 1  orchestrators   review-module.sh (model-only) · verify-module.sh (full pass)
LAYER 0  spec (skills)   journey-proof.md · module-review.md · wiring-sweep.md ·
                         process-coherence-pass.md
```

**The exit contract**, everywhere: `PASS` (rc 0, measured correct) / `FINDING` (rc 1, measured
wrong) / `FAULT` (rc 2, did not run at all). A fault is absent, not amber — never let a missing
check read as a clean one. Full discipline: `journey-proof.md` §"Verdict discipline",
`testing-shape.md` §4.

## 2. Three passes that sound alike and get blurred — read this before running any of them

These are the ones a session reaches for interchangeably and shouldn't:

| Skill | Question it answers | What only it can catch |
|---|---|---|
| `module-review.md` (the LOOK) | Does this module render right, interaction by interaction? | A Save button that silently 4xx'd — the mechanical audit can't see this |
| `wiring-sweep.md` | Does every visible affordance on this page actually do something? | Dead wiring from the page/element side — a button with no action behind it |
| `process-coherence-pass.md` | Do individually-correct pieces actually chain into the process a requirement describes? | A component that's correctly built, correctly granted, referenced nowhere — none of the other passes look for this because each one is scoped to a single module or a single page |

None substitutes for the others. A module can pass `module-review.md` and `wiring-sweep.md` on
every page and still fail `process-coherence-pass.md` if nothing outside the module ever calls into
it. Run all three; don't let a pass on one stand in for the others in a report.

`module-review.md`'s LOOK stage also has a whole-app variant: the same human-eyes pass run once
across every page in every custom-built module, instead of one module at a time — reach for it
before a demo or after a batch of build work spanning several modules. It's not a different check,
just a different scope; a project may wire it as its own command (e.g. `/full-ui-loop`) rather than
adding a fourth row to the table above.

**Two UI-focused checks live inside/alongside LOOK and are easy to lose track of:**

- **`design-audit.js`** — not a skill, a Playwright script LOOK's Stage 4b runs automatically. Purely
  mechanical: invented CSS classes never promoted to the deployed theme, raw `class=` where a
  sanctioned design-system property exists, axe accessibility (serious/critical, one `h1`,
  landmarks), horizontal overflow at three widths. Has a `--static-only` mode for when the app
  isn't running. This is the answer when someone wants "just a UI check, not the whole human pass."
- **`learned-skill-ux-audit.md`** — a heavier, standalone, on-demand pass: Playwright screenshots
  the live app and the design-system reference side by side, then an agent scores gaps across
  color, typography, component-pattern reuse, and design-system features never built into the live
  app. Triggered explicitly ("run a UX audit", "compare to design system", `/ux-audit`) — it is
  **not** part of the automatic per-module close-out, unlike `design-audit.js`.

## 3. The five journey rungs — what "the golden path is proven" actually requires

One journey = one persona walking a path with carried state, asserted in this order (each rung is
only meaningful if the one above held):

| # | Rung | Catches |
|---|---|---|
| 1 | Landing guard | without it, every later assertion runs against the *previous* page |
| 2 | What the screen says | the machine can do the work right and the screen can still lie about it |
| 3 | Ordered spans | existence-only checks can't tell a skipped step from a reordered one |
| 4 | Data effects (3 claims: delta / assocMustBeSet / mustPointAt) | saved vs. saved-with-link vs. saved-with-the-*right*-link |
| 5 | Outcome | per-step deltas can each be right while the journey's net result is wrong |

Full spec, mutants, and the false-green register this exists to close: `journey-proof.md`,
`testing-shape.md` §4.

## 4. The cadence layer — the thing most likely to be silently unmet

`obligations.tsv` (`bin/lib/obligations.tsv`) is the mechanical trip-wire: it declares which passes
are owed, by whom, on what cadence, and what artifact discharges each one. Read it directly before
trusting any summary that claims coverage — it is the ground truth for what's owed, not a
description of what usually happens.

| Obligation | Owner | Scope | Discharged by |
|---|---|---|---|
| `look` | review | module | `design/ui-reviews/ui-review-*.html` |
| `sweep` | test | module | `.claude/loop/sweep/<Module>/sweep.md` |
| `journeys` | test | module | `.claude/loop/verify/<Module>/summary.tsv` |
| `coherence` | architect | cluster (every 2–3 proven modules) | `.claude/loop/coherence/last-cluster-pass.tsv` |

**Check every row against the filesystem, not against whether the relevant skill is *named* in
`gate-check.sh`'s required-skills list.** A skill being in that list means the gate will ask for its
artifact — it does not mean anyone has produced one. `bin/coherence-cadence.sh` mechanizes the
`coherence` row specifically — it counts modules proven since the last recorded pass and exits 1
(DUE) at threshold. Run it before any full-harness audit; do not assume "not due" without running
it, and do not trust a "not due" verdict on a project whose `architecture/modules/` doesn't follow
`module-brief.md`'s one-directory-per-module layout (see the fixed bug below — a project that
drifted from that convention made the script always report zero, silently, with no error).

**Known-fixed bug, worth re-checking on any project inheriting an older script copy:**
`coherence-cadence.sh` used to derive "which modules count" by listing `architecture/modules/*/`
subdirectories. `module-brief.md:70` specifies one directory per module — but a project that
instead keeps flat `<Module>.md` / `<Module>-brief.md` files at that path (a spec drift, not a
supported alternative) made the glob match zero directories, so the script reported **0 proven
modules, always**, no matter how many `.claude/loop/verify/<Module>/summary.tsv` files existed.
Fixed in `project-bin/coherence-cadence.sh` (and propagated by `sync-project.sh`) to read
`.claude/loop/verify/` directly — that directory is the actual record of what ran, and doesn't
depend on a second directory matching a convention it may not follow. Found and fixed on
A real project, 2026-08-21.

## 4.5. What fires automatically — the build-plan / module-brief / ledger timeline

Everything above is reached for on demand. This is the part that isn't optional — the fixed
sequence every module and every project walks through regardless of whether anyone remembers to
invoke a skill by name. Read this before assuming a stage's testing obligations were met just
because the pipeline moved past it.

**Module brief — the test plan gets decided, not yet run.** Written once at brief sign-off,
before the module's first script (`module-brief.md`'s "Test plan" section):
- which rungs apply (UI always, Data always, Unit yes/no, Trace yes/no) and the **Base set** — the
  scripts that must all be done before testing opens at all;
- the **Journeys** table, compiled straight into `journeys/<Module>.journey.json` — a projection
  of the brief's own Roles/journeys and Golden-path tables, never a separately hand-authored list;
- the **Interactive elements** table — the wiring sweep's denominator, decided here so the sweep
  later has something concrete to count against.

**Stage 4 gate — coverage ledger.** Once, before the build plan is signed off; re-run after any
BRD edit and again before each slice build (`coverage-ledger.md`). Every BRD leaf claimed by a
build-plan row or explicitly catalogued with a reason; UNCLAIMED/PHANTOM/DOUBLE-CLAIMED must all
be empty. **No ledger yet means `conformance-check.sh` and `coverage-check.sh` report FAULT on
every module that follows, forever, until one exists** — this is the correct response to a
genuinely missing input, not an instrument bug, and it is the single most common way a project
ends up with a wall of FAULT rows that look like tooling failure.

**Per module — the fixed five-step close-out.** Every module, Stage 5, before the next one opens:

```
1 BUILD    MDL drafted and validated (mxcli check --references, 0 errors)
2 GATE     snapshot → exec → mxbuild → auto-restore on failure; 0 errors, lint clean
3 PROVE    verify-module.sh, one shot: UI + Data journey rungs, wiring-sweep, monkey pass —
           fires once the brief's Base set is fully checked off, never before
4 LOOK     the human-eyes pass, every screen in the module — nothing mechanical substitutes
           for this; a green PROVE buys no exemption from it
5 CONFIRM  one report, denominator stated explicitly, then the next module opens
```

**Every 2–3 proven modules — the cluster cadence.** Counted automatically after each module's
CONFIRM step by `coherence-cadence.sh`, which exits DUE at threshold; `process-coherence-pass.md`
then runs and records itself when done. This is the only check that crosses module boundaries.
**Being named in a gate's required-skills list is not the same as this having ever fired** — check
the recorded-pass marker file (`.claude/loop/coherence/last-cluster-pass.tsv`) directly.

**Stage 6 — whole-project gate.** Once, before cutover: every module's module-review report
exists with zero open P1, a full-app `process-coherence-pass.md` if the cluster cadence hasn't
already covered the tail, optionally `e2e-evidence-report.md` to package the result for a
stakeholder audience.

## 5. Running a full harness audit — the reusable trigger

Use this prompt verbatim (substitute the project name) when someone asks for "a full end-to-end
test," "does everything work," or a click-through proof that should actually mean what it says.

```
Run a full harness audit of <ProjectName> — every layer, every module, every persona,
one connected pass. This is not a single-module walkthrough; if scope has to be cut, name
exactly what was cut in the final report, never round up to "full coverage."

0. Read harness-architecture.md and journey-proof.md if you haven't this session. Confirm
   PROJECT.md's acknowledged toolkit commit matches HEAD (conversion-runbook.md ritual).
   Check for other live sessions touching the .mpr (ListAgents) and coordinate before any
   mxcli exec / docker rebuild.

1. Run bin/coherence-cadence.sh. Read its verdict — do not assume "not due" without running
   it fresh. If it reports DUE, run process-coherence-pass.md's 4-pass review BEFORE the
   click-through, since an audit built on modules that don't actually chain together isn't
   proving what it claims to prove. Record with --record when the pass completes.

2. For every module that has been opened for work (not just the one most recently touched):
   a. bin/verify-module.sh <Module>   — read every rung's individual verdict, not just the
      top-line summary. A "journeys: FINDING" or any "*: FAULT" row is not covered by an
      overall green.
   b. wiring-sweep.md on that module's main pages — click every visible affordance, not
      just the happy-path buttons. Confirm nothing is dead-wired.
   c. module-review.md's LOOK stage — human-eyes pass, does an interaction silently fail
      in a way the mechanical audit can't see.

3. For every persona with materially different access (check the navigation profile, not
   an assumed role list) — log in as each one, confirm menu/page differences, and re-walk
   at minimum the one journey most likely to differ by role. Don't run every module as one
   persona and call that "full coverage across personas."

4. Back every claimed pass with DB evidence (OQL) or a runtime log line, per testing-shape.md
   §4 — call out explicitly wherever a step only has UI-observed evidence. If a dialog or
   error appears, read what it actually says before calling it a pass — a raw system "Error"
   dialog is a different finding than a designed empty-state message, even when neither one
   crashes.

5. If something is broken, name it and keep going — do not silently route around it. Log it
   as its own finding with reproduction steps.

6. Consolidate into ONE e2e-evidence-report.md-format artifact: self-contained HTML,
   organized by persona then by journey, headline states the denominator plainly
   ("N of M modules × P of Q personas actually exercised live, this pass"). Update
   docs/BUILD-LOG.md or the project's demo script wherever this pass contradicts a stale
   claim there.

7. Cross-check every obligations.tsv row against the filesystem (§4 above), not against
   whether gate-check.sh's required-skills list names the relevant skill. Report which
   obligations are actually discharged, which are FAULT, and for `coherence` specifically
   whether bin/coherence-cadence.sh itself can even count correctly on this project's
   architecture/modules/ layout before trusting its verdict.

Do not call the result "e2e" in the final summary unless every module and every
materially-distinct persona was actually walked this pass. State exactly what was covered.
```

## 6. Reporting the result

Package with `e2e-evidence-report.md`'s format and rigor discipline — read that file for the exact
per-step field list (action / screenshot / DB evidence / log evidence / verdict) and the
denominator rule. This skill tells you *what* to run and in what order; `e2e-evidence-report.md`
tells you how to package what you found so a stakeholder can trust it on sight.

---

**Related, not superseded:** `harness-architecture.md` (the machine), `journey-proof.md` (the
spec), `testing-shape.md` (the vocabulary and false-green register), `module-review.md` /
`wiring-sweep.md` / `process-coherence-pass.md` (the three passes §2 disambiguates),
`e2e-evidence-report.md` (the report format), `bin/lib/obligations.tsv` (the ground truth for
what's owed).
