# Skill: Journey-Proof — end-to-end verification that can be shown to fail

**When to use:** at the end of a module, when you need to answer *"is this built and correct?"*
for a human who will not read your logs. Also whenever an instrument reports green and you cannot
say what it would have taken for it to report red.

**What it is:** one walk per user journey, asserted at five independent rungs, every rung proven
non-vacuous by a deliberately-broken control, and rendered as a narrated walk through the app with
screenshots, data deltas and requirement pointers.

**What it is not:** unit tests. Nothing here mocks anything. Every claim is measured against a
running app and a live database.

**Scope:** this is the deep implementation of **step 3 (PROVE)** of the module-completion loop, not a
replacement for that loop. It says nothing about build, gate, monkey testing, what counts as
acceptable, or the handoff to the next module — that loop still owns all of those.

**Worked examples:** `journey-examples.md` — a field-by-field reference plus three runnable example
journeys (minimal / full / no-seed) in a neutral domain. Read it before authoring your first
journey; it also lists the places where this spec and the runner currently disagree.

**What is shipped here: rungs 1–5 only.** Every rung, mutant, trap and pipeline stage below has been
run on real work and watched going red. That is the whole of the claim.

> **Rungs 6 and 7 — UI/design quality (`design-audit.js`) — are deliberately NOT part of this
> skill.** They exist, they are written, and they pass their own `--positive-control`; what they have
> not done is go red on real work that a human then agreed was a real defect. Until that happens they
> stay in the personal toolkit and out of the shared pipeline, because promoting an instrument on a
> green run is the exact move this skill exists to forbid: *a green is worthless until the same check
> has been watched going red.* Do not cite rungs 6–7 in a gate, a module brief or a report as though
> they were available here. When one of them catches something real, promote it then, with the
> incident attached.
>
> So: **five rungs, seven mutants** (rung 3 and rung 4 each carry two). "Rung 6/7" in a
> `design-audit` artifact refers to that separate instrument, not to a sixth and seventh rung of the
> journey.

---

## The problem it exists to solve

Every instrument in the Mendix stack has been observed reporting success while measuring nothing.

| Instrument | Observed failure |
|---|---|
| `mxcli check --references`, native `mx check`, mxbuild | All three cleared a miswire that made 13,078 calls in 22s, and a pair of integration flows that had **likely never persisted real parsed data since inception** |
| Playwright UI spec | Asserted `li.ok` and only *printed* `li.user`; every spec silently ran as `MxAdmin`, bypassing the role grants the specs existed to test |
| OTel trace assertion | `[].every()` is `true` — the assertion passed on **zero spans** |
| Microflow span | Stays `OK` while its activity spans are `ERROR`; a caught error reads as success |
| A screenshot | Looked perfect on a step that committed the wrong row (below) |

The common shape: **the instrument could not have failed, and nobody had checked.** Journey-proof's
central discipline is that a green is worthless until the same check has been *watched going red*.

---

## Verdict discipline (the one rule to keep if you keep nothing else)

**PASS / FAIL / INVALID are never collapsed** — full statement, and why, is canonical in
`testing-shape.md` §4 ("Verdict discipline"). In one line: `PASS` measured-correct, `FAIL`
measured-wrong, `INVALID` **the instrument did not run** — absent, never green. Everything below
in this spec assumes that discipline; it is what makes a rung's mutant meaningful rather than
decorative.

---

## The five rungs

One journey = a persona walking a path with carried state. Not a list of page stops. Per step, in
this order — the ordering matters, because each rung is only meaningful if the one above held.

| # | Rung | Asserts | Why it is not covered by the rung above |
|---|---|---|---|
| 1 | **Landing guard** | the step's `ready` widget is visible | Without it, every later assertion runs against the *previous* page and screenshots it under the new page's title |
| 2 | **What the screen says** | `textPresent` / `textAbsent` | The machine can do the work correctly and the screen still lie about it. This is the rung that found the one real product defect in the pilot |
| 3 | **Ordered spans** | microflows fired, **in order**, plus `mustNotFire` | `assertFired` is existence-only: it cannot tell a skipped step from a reordered one |
| 4 | **Data effects** | row-count delta, `assocMustBeSet`, `mustPointAt` | See below — three distinct claims that look like one |
| 5 | **Outcome** | one OQL query over the end state | Per-step deltas can each be right while the journey's net result is wrong |

### Rung 4 is three claims, not one

```
delta          the row was created            →  "something was saved"
assocMustBeSet the FK is non-null             →  "it was saved WITH its association"
mustPointAt    the FK points at the SEEDED value → "…at the RIGHT one"
```

`assocGap` is the measurement for the middle claim: `INNER JOIN` silently drops null-FK rows, so
`total − linked` is exactly the count of rows saved without their association. An order created
with no link to the unit it is for is a broken golden path even though it saved.

`mustPointAt` is the third claim and the expensive one to skip. **Set-ness is not correctness.**

---

## Non-vacuity: one control per rung, never a boolean

Run the journey again with one deliberately broken precondition, and require that **the targeted
check** failed. Not that *something* failed.

**MEASURED, and the reason this is per-rung:** the first control implementation broke exactly one
thing — step 1's landing selector — and reported *"assertions can fail"* for the whole journey. But
breaking step 1 **stops the walk**, so the trace, data and outcome rungs were never challenged at
all. On the live run those were **20 of the 24 results**. One boolean licensed a claim about all of
them from evidence about one, and the rung it did prove was the least interesting in the harness.

So: at least one mutant per rung — seven in all, because rungs 3 and 4 each make two independent
claims — each requiring its own targeted check to be the one that went red.
Accepting any FAIL would let a mutant that breaks by accident vouch for a rung it never reached —
the same vacuity bug one level up.

| Mutant | Breaks | Proves |
|---|---|---|
| `ui-landing` | first step's `ready` selector | the guard that stops the walk |
| `ui-text` | expect text the page never renders | the screen-says rung |
| `trace-order` | expect a microflow that never fires | span ORDER, not existence |
| `trace-negative` | assert a microflow that *did* run must not have | the negative trace claim |
| `data-delta` | expect +2 from a +1 action | the row-count delta |
| `data-target` | `mustPointAt` a value never picked | the association *target* |
| `outcome` | unreachable floor on the outcome query | the end-to-end claim |

**A rung with no mutant is UNPROVEN, which is `fault` — never `pass`.** Same discipline as INVALID.

### Two traps the control run itself sprang

1. **Reset between journeys.** Without one, 5 of 7 mutants died at step 1 on the *real* selector:
   mutant 2 finished standing on a different page, so mutant 3 began its walk from there, where the
   home button is absent and the nav group was already expanded (clicking it *collapses* it). Five
   rungs reported "unproven" for a reason that had nothing to do with the rung.
   A `goto` **reset between independent journeys is legitimate**; the forbidden one is `page.goto`
   as *mid-journey recovery*, which hides state carry-over inside a walk. Here, carry-over between
   walks is precisely the bug.
2. **A control run writes real rows.** The mutants that get past step 1 commit real records
   (pilot: one transactional table went 50 → 57 rows). Never run controls against anything you are also using as a
   demo baseline, and never against production.

### Control output goes in its own file

`journey-findings.json` is a single slot. A control run used to overwrite the real walk in it —
silently, 24 real results replaced by 146 mutant ones. The raw evidence for that day's real walk is
gone; only its normalized copy survived.

Two guards, both required, because files outlive the code that wrote them:
- the runner writes control runs to `journey-findings-control.json`;
- the normalizer **faults** on a file with `positiveControl: true` sitting in the real slot.

These two files answer different questions — *"does the app work"* and *"can this harness tell when
it doesn't"* — and must never share storage.

---

## The walk: screenshots as evidence, never as verdict

The rungs answer *did it work*. The walk answers *what did it do* — which page, which button, what
was typed, and what the screen looked like **at the moment each assertion was taken**.

**A screenshot is not an assertion.** The step's status comes from its checks; the image is
attached to them. This is load-bearing, and here is the receipt: a Downshift combobox off-by-one
committed *"Harbour Depot North"* where the journey asked for *"Harbour Depot Northeast"* — a
real, valid, neighbouring row. Every downstream signal was green: the row saved, both FKs non-null,
the span OK. **The screenshot of that step looked perfect.** Only the committed-value assertion
caught it.

Therefore:
- Screenshots are for **locating and understanding** a failure, never for establishing one.
- **Timing: `testing-shape.md` §4a rule 7 is canonical** — shot after actions and landing guard,
  before text/trace/data. A shot taken later is not evidence for the checks printed beside it.
- A step with **zero checks is `fault`**, however good its screenshot. An empty check list passing
  is `[].every()` in another costume.
- Precedence for a step's status: **fault > fail > pass**. "Could not measure" outranks "everything
  we did measure was fine".

Record actions in reviewer language (`Click "Receive"`) *and* the selector (`.mx-name-bReceive`) —
the sentence is for the person reading, the selector for the person fixing.

---

## Requirement carry-through

Every check carries a BRD JSON Pointer (`F007#/rules/3`), taken from the coverage-ledger row and
the module brief's **golden-path data effects** table. Without it, "23 pass" is a statement about
the app, not about the spec — and the governance question was never *did it work*, it was **did we
build what was decided**.

A module with a ledger and no journey is a `fault`, not a silent pass.

---

## Pipeline

```
journeys/<Module>.journey.json          the contract (persona, steps, spans, data, requirement)
  → tests/e2e/journey-runner.js         the walk        → artifacts/journey-findings.json
  → tests/e2e/journey-runner.js --positive-control      → artifacts/journey-findings-control.json
  → tests/e2e/report-normalize.js       5 instruments   → docs/report.json
  → tests/e2e/report-render.js          → docs/verification/report.html
```

The normalizer names every input in one table and emits an `instruments[]` row **whether or not the
file exists** — a missing instrument is reported as `fault`, never as silence. Instruments carry
`canExpressFault` and `evidenceStrength`, so a green from a source whose enum is `pass`/`fail` only
(it cannot say "did not run") is visibly weaker evidence than a journey green.

Both normalizer and renderer are self-testing (`--selftest`) and deterministic — byte-identical
across runs, so a diff in the report means a diff in the project.

---

## Traps, measured

| Trap | What it looks like | Fix |
|---|---|---|
| Downshift combobox | committed a valid *neighbouring* row | Step the highlight and **read `aria-activedescendant` each time**; commit only when it matches. Never compute the index — Downshift's highlight index is a different coordinate system from the DOM array index |
| `CSS.escape` in Node | `CSS is not defined` | `page.locator('[id="..."]')`, not `#id` |
| Nav groups | child vanishes on click | **See `testing-shape.md` §4a rule 4** — groups toggle, never force-click nav |
| Two windows, one account | menu entries disappear mid-run, read as "role restriction" | One account per window; a menu that *loses* entries mid-run is never a role restriction |
| `DEMO_SPEED` raised | four real-looking failures | It divides hand-tuned pauses too |
| Seeds return nothing | whole journey INVALID | Usually a race: runner fired while the runtime was still warming. **INVALID, not FAIL** |
| Raw `curl` to M2EE | "Authentication failed" | The scheme is not plain base64-in-a-header. Use the tool that works, and do not conclude an outage from your own broken client |

---

## Checklist before calling a module verified

- [ ] One journey per golden path, each carrying BRD pointers.
- [ ] All five rungs asserted; none quietly absent.
- [ ] `--positive-control` run, **all seven mutants proven** (every one of rungs 1–5 covered),
      results in their own file.
- [ ] Zero `INVALID` in the real run — or each one explained as an instrument fault, not a feature.
- [ ] Walk renders: every step has actions, a shot (or an honest placeholder), and its checks.
- [ ] Ledger rows the journey exercises are marked, and modules with a ledger and no journey are
      visible as `fault`.
- [ ] The report states which run it describes, and when.

**Do not fix defects from inside the harness.** It is diagnostic. Findings go to the human.
