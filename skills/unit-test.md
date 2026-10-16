# Skill: unit-test — write and run a microflow unit test that can fail

**Applies to:** any mxcli project with a runnable app, pipeline or not.
**Purpose:** the how of `.test.mdl` tests: what is worth a test, how to write one whose
assertion is live, how to run it without breaking the live app, and how to report it.
**Source:** field projects on mxcli v0.19 to v0.27, Mendix 11.13 to 11.15, 2026-08 to 2026-10;
the false-green rows are `testing-shape.md` §4.

**Whether** a module gets unit tests, and **when** they run, is the project's test strategy
(PROJECT.md `## Test strategy`, `Unit modules:` or per flow in the module brief's `Unit flows:`, decided at CAC-5). Each change runs only the
touched unit tests of opted-in modules or listed flows; module done runs that module's; build complete and
before each later deploy run everything once. This file does not decide that. When the user asks for unit tests outside a pipeline, they have decided.

---

## 1. Pick the flow, or say why not

| Worth a unit test | Not worth one |
|---|---|
| calculation, money, dates, rounding | a page or layout change: that owes a journey and a look |
| mapping (import/export, JSON shaping) | a flow that only retrieves and shows |
| REST or Java action logic behind a stable contract | wiring: a test cannot see that no button calls the flow |
| a flow where a bug was fixed: the test pins the fix | anything needing the user's session or module security (the runner switches security off) |

Measured the other way round: a 143-minute microflow run on one project found stale strings and
not one logic bug. Spend unit tests where logic is, not everywhere.

## 2. Write it so the assertion is live

```
/**
 * @test Discount: order total of 1000.00 gets 5 percent
 * @expect $Discount = 50.00
 * @cleanup rollback
 */
$Discount = call microflow Orders.CALC_Discount(Total = 1000.00);
/
```

- One block per test, closed by a `/` line. Seed data inline (`create` + `commit`) before the
  call; `@cleanup rollback` undoes it.
- **Equality only in `@expect`:** `$Var = value` or `$Entity/Attr = value`. `length(...)`,
  `!= empty` and `> 0` parse to **no assertion at all** (8 of 14 tests in one file, BUG-LOCAL-30).
  Compute the number in the block and compare with `=`.
- **No file-level `/** */` header.** The runner silently drops the first test (BUG-LOCAL-29).
- `@verify <OQL>` and `@setup` really run from mxcli v0.19.0. Before that they were parsed and
  ignored, so an old suite re-run on a new binary can surface real failures. That is a finding,
  not a regression in the test.
- Test helpers (`TEST_` microflows a test calls) live in the real module and ship with it.
  Lint flags them (QUAL004, CUSTOM002): baseline with a reason (`lint-that-actually-runs.md`),
  and keep them read-only or seed-only. Hypothesis, not yet observed: a helper that writes data
  is a production entry point nobody secured.

## 3. Check before you run: free, no model write

```
mxcli test tests/unit/Orders.test.mdl -p App.mpr --list
```

On mxcli 0.21 and later add `--require-assertions`: a test that asserts nothing fails (BUG-LOCAL-30).
Pass only when **both** hold: the listed count equals the number of `/` separators in the file,
and **every** test shows its `@expect`. A plausible count with a missing test is BUG-LOCAL-29.

## 4. Run it without breaking anything

`mxcli test` writes to the model: it injects a TestRunner, sets security off, builds into
`deployment/`, starts a runtime and restores. In the live project that broke a running app
(`NoClassDefFoundError`, field run 2026-10-12, #278). So:

| Situation | Command |
|---|---|
| Default | `./bin/test-scratch.sh -- tests/unit/Orders.test.mdl --local` (scratch copy, port lock, live app untouched) |
| Fast loop against an already warm app started with `--test-endpoint` | `mxcli test <file> -p App.mpr --attach` (seconds, not ~30 s; it writes into the live app, and the catalog goes stale until `REFRESH CATALOG FULL`) |
| No scratch helper in the project | close Studio Pro, snapshot the `.mpr`, run, then **verify the restore**: `git status` clean, after-startup not `MxTest.*`, security back on |

A run stopped by a signal leaves after-startup on `MxTest.*`; the next run recurses
(BUG-157). `test-scratch.sh` refuses that state and prints the repair. Only one
`mxcli test --local` per machine at a time: the test ports are machine-wide.

Cost to plan for: the model injection dominates. One file took 9 min 21 s for 848 ms of
tests; one module's suite took ~76 s (`rest-between-mendix-apps.md`).

## 5. Prove it can fail, once

Change one `@expect` to a wrong value and run. It must fail, naming expected and actual. Field
example: a control copy of a 6-test file failed 1 of 6 (expected `Bay Z`, actual `Bay A`). An
assertion never seen failing is a claim about your test code, not about the app
(`testing-shape.md` §6). Revert the control; do not commit it.

## 6. Report

```
unit · <module> · <file> · mxcli <version>
  listed <L> = separators <S> · every test has @expect: yes
  <P> pass / <F> fail · positive control: failed as expected (<date>)
  Read as: these flows return these values on this seed. Not: the feature is wired or secured.
```

A failing test is a finding for the user, not a cue to change the `@expect` until it passes.
Same rule as every test in this toolkit: diagnose, report, no unapproved fix
(`e2e-harness-base.md`).

## Related

- `skills/testing-shape.md`: the module shape, the strategy, §4 false greens, §6 controls
- `skills/learned-db-assertions.md`: asserting the row landed, from the outside
- `skills/journey-proof.md`: what finds wiring defects a unit test cannot see
