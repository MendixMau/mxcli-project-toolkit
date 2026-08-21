# Skill: Harness architecture — the parts, the seams, and how to run each alone

**When to use:** you are installing, extending, debugging or porting the verification harness, and
you need to know which piece owns what, which piece you can run on its own, and what a missing
piece is allowed to report.

**What this is:** the architecture reference. `journey-proof.md` is the *spec* — five rungs, seven
mutants, verdict discipline. This file is the *machine* that implements it: the layers, the seams
between them, the command for each part, and the honest-degradation contract.

**What this is not:** a tutorial. Author your first journey from `journey-examples.md`; establish
its preconditions from `fixture-seeding.md`.

Claims below are marked **VERIFIED** (read out of the artifact cited) or **INFERRED** (reasoned,
not read). An INFERRED claim is not a fact and must not be cited as one.

---

## 0. Two derivations you need before anything else

Nothing in this harness may hardcode a project's identity. Two values are derived, and every part
derives them the same way. If you find a part that hardcodes either, that is a defect in the part.

**The model file.** The project's single `*.mpr` in the project root, resolved by `find_mpr()` in
`project-bin/_common.sh`. **Zero matches or two or more matches is a hard failure, never a guess** —
picking the wrong model means writing to, or restoring over, the wrong project. `MPR_FILE`
overrides when a repo legitimately holds more than one. **VERIFIED** (`project-bin/_common.sh:23`).

**The app port, with its ownership.** Read from `.claude/loop/stack.env`, which
`test-stack-up.sh` publishes as *two* facts, never one:

```
APP_PORT=<port>
APP_OWNERSHIP=verified | unverified | asserted | unknown
```

`verified` means a container owned by this project's `.docker` is serving that port. `unverified`
means a Mendix answered a port from the `APP_PORTS` fallback scan list — *a* Mendix, not
necessarily yours. **A harness must refuse an unverified port** unless the operator sets
`ALLOW_UNVERIFIED_APP=1`, and must record the ownership it acted on. **VERIFIED**
(`project-bin/test-stack-up.sh:150-198`).

This is not defensive decoration. On one measured occasion a published `stack.env` named a port
that belonged to a *different* project's Mendix, which answered 200 with a real login page. Every
downstream rung then measured a foreign app and reported plausibly. See `measured-claims.md` §3.

---

## 1. The layers

```
┌─ LAYER 4 · CONTENT ────────────────────────────────────────────────────────────┐
│  journeys/<Module>.journey.json     the contract: persona, steps, spans,        │
│                                      data effects, BRD pointers                 │
│  architecture/modules/<M>/coverage-ledger.md    what was claimed built          │
│  analysis/*/brd/*.brd.json                      what was decided                │
│  design/ wireframes + design system              what it should look like       │
└────────────────────────────────────────────────────────────────────────────────┘
                                    ▲ read by
┌─ LAYER 3 · ENGINE (Node) ──────────────────────────────────────────────────────┐
│  journey-runner.js    rungs 1-5 + 7 mutants        → artifacts/journey-*.json   │
│  design-audit.js      the separate design/a11y instrument (see §6)              │
│  monkey.js            seeded crash net             → artifacts/monkey-*.json    │
│  helpers.js config.js otel.js       shared: login, nav, data queries,           │
│                                      port ownership, spans                      │
│  report-normalize.js  N artifacts → one report.json (versioned schema)          │
│  report-render.js     report.json → report.html (deterministic)                 │
│  review-report.js     model-side TSVs → report.json                             │
└────────────────────────────────────────────────────────────────────────────────┘
                                    ▲ invoked by
┌─ LAYER 2 · MODEL-SIDE INSTRUMENTS (shell, app not needed) ─────────────────────┐
│  conformance-check.sh   ledger claim  vs  live model                            │
│  graph-sweep.sh         wiring shape, orphans                                   │
│  coverage-check.sh      BRD leaves    vs  ledger  (UNCLAIMED/PHANTOM/DOUBLE)    │
│  page-scope.sh          which pages are reachable and first-party               │
│  test-stack-up.sh       the precondition: is the app up, and is it OURS         │
│  fixture-manifest.sh    do the journeys' preconditions exist                    │
└────────────────────────────────────────────────────────────────────────────────┘
                                    ▲ orchestrated by
┌─ LAYER 1 · ORCHESTRATORS ──────────────────────────────────────────────────────┐
│  review-module.sh       model-side only  → report.json + report.html            │
│  verify-module.sh       module-end deep pass: stack → model → runtime           │
│  run-journey-proof.prompt.md   the FULL pipeline — and it is a PROMPT, not a    │
│                                script, because parts of it need judgement       │
└────────────────────────────────────────────────────────────────────────────────┘
                                    ▲ specified by
┌─ LAYER 0 · SPEC (skills) ──────────────────────────────────────────────────────┐
│  journey-proof.md · journey-examples.md · testing-shape.md · fixture-seeding.md │
│  coverage-ledger.md · module-review.md · wiring-sweep.md · monkey-test.md ·     │
│  process-coherence-pass.md                                                      │
│  (one-line-each index: README.md "When to use which skill" → Verify section)    │
└────────────────────────────────────────────────────────────────────────────────┘
```

The layering is enforced, not aspirational: **layer 2 never imports layer 3, layer 3 never shells
out to layer 2, and layer 1 is the only place they meet.** **VERIFIED** by reading every script's
invocations in the reference implementation.

---

## 2. The exit contract — the seam that makes the parts independent

Every instrument's entire contract with its orchestrator is **an exit code plus a log file**:

| rc | Meaning | Bucket |
|---|---|---|
| **0** | measured, correct | `pass` |
| **1** | measured, wrong — the thing is broken | `fail` / finding |
| **2** | **the instrument did not run** | `fault` |

`fault` is **absent**, not amber. Amber means "ran, degraded". "The test could not run" and "the
feature is broken" go to different people, and blending them is how a week gets spent debugging a
page that was never reached.

Two corollaries that this harness has paid for:

- **An empty result set is never a pass.** `[].every()` is `true`; a trace assertion over zero
  spans passes vacuously. Guard non-emptiness *first*, then assert.
- **A pipeline can eat an exit code.** `cmd | tail` reports `tail`'s status. Measure unpiped, or
  set `pipefail`. This defect has been observed inside a measurement of this very contract
  (`measured-claims.md` §3, method note).

Because the contract is only rc + stdout, you can rewrite any layer-2 instrument in another
language and the orchestrator neither knows nor cares. That is the seam. Preserve it.

The report path has a second, stronger seam: `report-normalize.js` and `report-render.js` are
decoupled by a **versioned JSON contract** (`report-schema.md`), and the renderer **refuses** a
major-version mismatch rather than rendering something plausible. Both are self-testing
(`--selftest`) and deterministic — byte-identical across runs, so a diff in the report means a diff
in the project, never a diff in the weather. **VERIFIED.**

---

## 3. Running each part alone

Substitute your own module name; `<M>` is a first-party module (§7). Paths assume the toolkit's
installed layout — `bin/` in the project for shell instruments, `tests/e2e/` for the engine.

```bash
# ── preconditions ────────────────────────────────────────────────────────────
./bin/test-stack-up.sh --check       # is the app up, and is it OURS? publishes stack.env
./bin/page-scope.sh                  # which pages are in scope at all
./bin/fixture-manifest.sh            # 0 = sufficient · 1 = short · 2 = could not measure

# ── model side (the app may be DOWN) ─────────────────────────────────────────
./bin/conformance-check.sh --module <M>
./bin/graph-sweep.sh --module <M> --tsv
./bin/coverage-check.sh --summary <brd.json> <coverage-ledger.md>
./bin/review-module.sh <M>           # the three above, as one report.json + .html

# ── runtime side (the app must be UP and OWNED) ──────────────────────────────
node tests/e2e/journey-runner.js journeys/*.journey.json
node tests/e2e/journey-runner.js journeys/*.journey.json --positive-control
node tests/e2e/design-audit.js                 # separate instrument — see §6
node tests/e2e/design-audit.js --static-only   # same, with the app DOWN
node tests/e2e/monkey.js --rounds 24 --seed 42 # seeded, so findings reproduce

# ── report ───────────────────────────────────────────────────────────────────
node tests/e2e/report-normalize.js
node tests/e2e/report-render.js --in <report.json> --out <report.html>
node tests/e2e/report-normalize.js --selftest
node tests/e2e/report-render.js --selftest

# ── the composed passes ──────────────────────────────────────────────────────
./bin/verify-module.sh <M>           # stack + model + runtime
./bin/verify-module.sh <M> --quick   # skips the crash net and the control run
```

**Pass every journey file to ONE `journey-runner.js` invocation.** It logs in once and then loops.
Invoking it per file burns one login session per journey and will hit the runtime's concurrent-session
cap — which the login page then misreports as a credential failure (`measured-claims.md` §4).

**Argument-surface warning.** Flag coverage across the parts is uneven: `-h/--help` and `--module`
are honoured by some instruments and not others, and at least one (`page-scope.sh`) parses no
arguments at all and is whole-project only. Check `-h` before assuming a flag exists; if it prints
nothing, read the script's header block.

---

## 4. Honest degradation — a missing part is a fault, not silence

This is the contract that makes the composition trustworthy, and it is worth more than any
individual rung. `verify-module.sh` classifies every rung into three buckets and **refuses to print
a pass while any rung faulted**:

> *This is NOT a pass with caveats. The unrun checks are absent, not green.*
> — `project-bin/verify-module.sh`

Each optional input is *discovered* rather than assumed, with an override
(`JOURNEY_DIR`, `JOURNEY_RUNNER`, `MONKEY_JS`, `BRD_FILE`, `LEDGER_FILE`, `COVERAGE_CHECK`), and
each absence produces a **named reason**. **VERIFIED** line by line:

| Missing | Result |
|---|---|
| `test-stack-up.sh` | FAULT + "the app port is a guess" |
| `conformance-check.sh` | FAULT |
| `graph-sweep.sh` | FAULT |
| `coverage-check.sh` | FAULT — after looking in the project's `bin/` **and** the toolkit's `bin/`, and it declines to manufacture its own fault |
| ledger or BRD | FAULT + "traceability is UNMEASURED, not clean" |
| `review-module.sh` | FAULT |
| stack down | FAULT; runtime rungs skipped, not silently passed |
| `journey-runner.js` | FAULT + a pointer at `journey-proof.md` |
| `journeys/<M>.journey.json` | FAULT + "the golden path is UNTESTED" |

The same discipline holds inside the report layer: the normalizer emits an `instruments[]` row
**whether or not the input file exists**, so a missing instrument is a `fault` row, never an
absence. Instruments also carry `canExpressFault` and `evidenceStrength`, so a green from a source
that can only say pass/fail is visibly weaker evidence than a journey green.

### Two known holes in that discipline — CLOSED, 2026-08-21

Both were present in the reference implementation at an earlier time of writing and are now fixed
in `project-bin/verify-module.sh`. **VERIFIED** by reading the current file, not inferred:

1. **The crash net's absence used to be recorded as `SKIPPED` with rc 0** and did not increment the
   fault count. It is now a `fault "monkey" "not installed at ..."` call (a missing `--skip-monkey`
   flag still records `SKIPPED`/rc0 — that path is an operator's deliberate choice, not absence,
   and stays exit 0 on purpose).
2. **The CLEAN verdict text used to be unconditional.** It is now generated by `print_scope()` from
   the run's own summary TSV — it names only rungs whose verdict was PASS/INFO, and lists every
   `SKIPPED` row (flag-skips, and the always-present "look" row) under an explicit
   `NOT MEASURED: <rung> (<reason>)` line the CLEAN/FINDINGS/INCOMPLETE branches all print.

The shape that fixed both: **generate the scope sentence from the run summary**, naming only rungs
whose verdict was PASS, and append an explicit `NOT MEASURED: <rung> (<reason>)` line. An
operator-requested skip may still exit 0 — they asked for it — but **the verdict text must never
claim what the flag suppressed.** Keep this discipline when adding new rungs (e.g. `design-audit.js`,
§6): a missing or faulted instrument goes through `fault()`, never a bespoke `SKIPPED` row.

There is a related open disagreement about the crash net's authority. One position: absence must be
a fault and zero crashes is a legitimate flat bar. The other, recorded in the orchestrator itself:
on one measured project the crash net scored zero while the scripted journeys found all nine real
defects, so letting it gate would grant it authority the measured yield does not support. The
reconciliation both sources can accept: **required to have run (absence = fault), not gating on
findings (findings = info).**

---

## 5. Where the report path forks — the one seam that is not clean

```
review-module.sh ──> review-report.js ──> report.json ──> report-render.js ──> report.html
                                                                             (per-module)
journey-runner.js ─┐
design-audit.js  ──┼─> report-normalize.js ──> report.json ──> report-render.js ──> report.html
monkey.js        ──┘                                                            (full)
```

Two producers of `report.json`, one renderer — and in the reference implementation
`report-normalize.js` **is invoked by no orchestrator at all**, only by hand and by the pipeline
prompt. **VERIFIED** by grepping every orchestrator. So `verify-module.sh` runs the journeys and
then never normalizes or renders them: the richest artifact in the harness is unreachable from the
harness's main command.

Two structural improvements, in order of value:

1. **Add a final normalize → render rung to `verify-module.sh`**, emitted *unconditionally* —
   including on a faulted run. Copy the pattern `review-module.sh` already uses: a
   `trap emit_report EXIT` that produces the report on every exit path, **including SIGINT and
   including a module that does not exist**. Most harnesses produce nothing when interrupted, and
   "aborted" then looks indistinguishable from "never started".
2. **Make `report-normalize.js` the single composer**, with `review-report.js` demoted to an input
   adapter that writes `artifacts/review-<module>.json`. One composer means one place where "a
   missing instrument is a `fault` row, never silence" is enforced.

`review-report.js` is also the one engine file with **no argv parsing at all** — it is driven
entirely by environment variables set by its orchestrator, so it cannot be run or tested alone. It
is a subroutine wearing a `.js` extension. Giving it an argv interface is cheap and makes the
engine uniformly testable.

---

## 6. Rungs 6 and 7 are a separate instrument, not part of the journey

**The journey ships FIVE rungs and SEVEN mutants** (rungs 3 and 4 each carry two independent
claims). `design-audit.js` produces artifacts labelled *rung 6* and *rung 7*; those labels refer to
**that separate instrument**, not to a sixth and seventh rung of the journey.

Do **not** merge them into one 1-7 table. Do **not** cite rung 6 or 7 in a gate, a module brief or
a report as though they were part of the shipped spec — `journey-proof.md` forbids exactly this,
and the reason is the discipline the whole harness rests on: they pass their own positive control
but have not yet gone red on real work a human then agreed was a real defect. Promoting an
instrument on a green run is the move this harness exists to forbid.

Run them, read them, report what they say. They are not verdicts.

### The mandatory guard when you do run them — mxcli #891

**An object-list item's content-slot children are never read.** A data grid nested inside an
accordion or similar container describes as an *empty group*, so a class sweep reports clean
**without having looked**.

Any page whose structural output shows an empty content slot must be recorded as
`partially-read` → **`fault`, never `pass`.** A suspiciously clean design sweep: suspect this
first, before concluding the pages are fine.

`design-audit.js` and `module-review.md` **compose; neither supersedes the other.** The mechanical
audit cannot see that a Save button silently 4xx'd. The agent loop cannot reliably diff a class
corpus across hundreds of pages. Interaction checking and empty-state judgement live only in the
agent loop; a11y scanning and class-promotion diffing live only in the audit.

---

## 7. Nothing may be hardcoded — the derivation table

A harness that only runs in the project it was born in is that project's test suite. These are the
derivations that make it portable. Where no derivation exists, that is stated plainly, along with
the one place the value is configured.

| Value | Derivation |
|---|---|
| The model file | the single `*.mpr` in the project root, via `find_mpr()`; zero or many = hard fail, `MPR_FILE` overrides |
| App port + ownership | `APP_PORT` / `APP_OWNERSHIP` from `.claude/loop/stack.env`, published by `test-stack-up.sh`; refuse `unverified` unless `ALLOW_UNVERIFIED_APP=1` |
| First-party modules | `SHOW MODULES`, take rows whose **Source column is empty**, then subtract the Mendix-shipped set (System, Administration, Atlas/theme modules, and any marketplace module carrying a source) |
| Personas / roles | the navigation profile's roots plus page permissions — the roles that can actually reach a page. Never a role-name list carried from another project |
| Selectors | `.mx-name-<widgetName>`, where `<widgetName>` comes from `DESCRIBE PAGE` on **this** project's page. Never invented, never carried between projects — a widget name is whatever the page's author typed |
| Journey preconditions | measured by `fixture-manifest.sh` (0 sufficient · 1 short · 2 could not measure), then the residue interviewed per `fixture-seeding.md` |
| BRD / ledger locations | discovered, with `BRD_FILE` / `LEDGER_FILE` overrides; absence is a fault, never an invented substitute |
| **Test identity (user + password)** | **No derivation exists.** It must be configured, in exactly one place: the engine's config module (`config.js`), reading `TEST_USER` / `TEST_PASS` from the environment. Nothing else in the harness may name a credential |
| **Database connection** | **No derivation exists** for a non-default stack. Configure it once in `config.js`; see `learned-db-assertions.md` for which instrument to prefer. A harness with no working data instrument has **no data rung** while still reporting "e2e" |

**Assert the identity you logged in as, not merely that login succeeded.** A login helper that
silently falls back to an admin account makes every role-scoped assertion vacuously green while
looking identical to a real run. This has happened; it is in the false-green register.

---

## 8. What travels, and what you must supply

**Ships with the toolkit and is portable:** `_common.sh`, `test-stack-up.sh`,
`conformance-check.sh`, `graph-sweep.sh`, `verify-module.sh`, `fixture-manifest.sh`, plus the
Layer-0 skills and the journey validator in `examples/`. **VERIFIED**: no project-specific string
in any of them, `find_mpr()` used throughout, `APP_PORTS` overridable.

**Does not ship, at the time of writing — you must supply it:**

| Missing | Consequence on a fresh project |
|---|---|
| the engine (`journey-runner.js`, `design-audit.js`, `monkey.js`, the three libraries, and the report pair) | rung 1-5 verification does not exist; `verify-module.sh` faults at the first runtime rung |
| `journeys/` for this project | nothing to run even once the engine is present — author from `journey-examples.md` |
| `review-module.sh`, `review-report.js` | the model-side composite rung faults permanently |
| `page-scope.sh` | no scope instrument |
| `coverage-check.sh` | recovered via the orchestrator's toolkit-`bin/` fallback — good design, working as intended |

**Consequence, stated plainly:** on a project with none of the above, `verify-module.sh` exits 2
every time. That is honest, but a gate that can only ever say one thing is not a gate. Either
supply the engine or state in the module brief that this project's journey rung is UNMEASURED.

**Manifest self-check.** An install manifest that verifies "every named file exists" is only half a
check; nothing then verifies "every existing file is named". That one-directional check is exactly
how a shipped script stayed invisible for months. The toolkit's manifest now carries the reverse
check plus an explicit *deliberately-not-installed* list, so a new file in `project-bin/` must be
either delivered or declared undelivered — "nobody noticed" is no longer a third option. Keep it
that way when you add a script.

---

## 9. Do NOT split these

Four couplings are load-bearing. Breaking them produces a harness that runs faster and proves less.

- **The five rungs of `journey-runner.js`.** They are ordered and conditional: rung 1's landing
  guard is what makes rungs 2-5 mean anything. A `--rung-3-only` flag would assert traces against
  a page the walk never reached — the original false green, re-manufactured.
- **The control run from the real run.** `--positive-control` must stay a *mode of the same
  binary*. A separately-maintained mutant runner drifts from the runner it vouches for, and a
  mutant set that no longer matches the rungs proves nothing while looking identical to one that
  does. Its output must go to its own file: a control run once overwrote a real walk's raw
  evidence in the shared slot, 24 real results replaced by 146 mutant ones.
- **`test-stack-up.sh` from everything downstream.** It resolves and publishes the port *and* the
  ownership assertion. Skipping it does not make a run faster; it makes it a run against an
  unknown app.
- **The three claims of rung 4.** `delta` / `assocMustBeSet` / `mustPointAt` look like one check
  and are three. Exposing only the cheap one is how *"it saved"* becomes *"it saved the right
  thing"*.

---

## 10. What is already good, and should be copied rather than reinvented

- The **fault / finding / pass trichotomy**, implemented consistently across nine instruments in
  two languages, with a portable macOS-safe timeout that remaps a SIGKILL into the *fault* bucket
  rather than the *fail* bucket.
- **`review-module.sh` emits its report on every exit path**, including SIGINT.
- **The report contract is versioned, self-testing and deterministic**, and the renderer refuses a
  major-version mismatch rather than rendering something plausible.
- **The degradation table** in §4: every missing input produces a named reason, and — with the two
  holes called out there — no missing input produces silence.

---

## 11. Known live contradiction — the Stage 6 gate

`gate-check.sh` gates Stage 6 on the existence of `*/ui-reviews/ui-review-*.html` and accepts **no**
substitute. **VERIFIED** (`bin/gate-check.sh:578-587`). A project that ran this entire harness and
produced a full verification report still fails Stage 6 for lack of the older artifact.

This is a live process contradiction, not a documentation nit. **Do not work around it by renaming
a file to match the glob** — that is manufacturing a pass, and it defeats every discipline above.
Report it, and run the UI review loop as well if the gate must be satisfied today.
