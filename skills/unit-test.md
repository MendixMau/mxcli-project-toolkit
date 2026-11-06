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

## 2b. Choose the inputs: one baseline, then one change per decision

§1 decided that a flow gets a test. This decides **which inputs**. An author who picks the happy
value plus whatever the last test used misses the bug that lives in a decision: in a seeded-bug
field test (mxcli test lane, two runs, 2026-11) a condition weakened from `!= empty and trim(x) != ''`
to `!= empty` and a commit removed from a flow were both missed by both runs, because nobody tried
a whitespace-only value and nobody read the row back.

1. Read the flow: `mxcli -p App.mpr -c "describe microflow Module.Flow"`. Write down its
   parameters and **every decision**: if / split, XPath, validation, a comparison, a rounding.
2. Write ONE baseline test with every input valid.
3. Add one test per row below that the flow **actually contains**. Change one input per test; never
   cross the dimensions.

| The flow contains | Add | Field case |
|---|---|---|
| a string read in a condition: `!= empty`, `trim`, `length`, a validation, a mapping | blank `''` and whitespace-only `'   '` (two tests: they fail differently) | a whitespace-only IBAN passed `!= empty` |
| a comparison `>` `>=` `<` `<=` against a parameter, attribute or constant | the exact boundary, and one step to each side | `>=` written for `>` |
| a rounding or decimal expression | a value that rounds differently at 0 and at 2 places | `round(x, 0)` for `round(x, 2)` |
| an enum compared to a literal or filtered in an XPath | one row per value the flow **names**, plus one value it does not name | REJECTED handled like DISPUTED |
| a read through an association (`$x/Assoc/Attr`, `retrieve ... where Assoc = $x`) | the object with the association empty | null association |
| a date or datetime compared or formatted | empty, and the exact day boundary | |
| a commit, a create, or a change of a persistent object (even without a `commit`) | the read-back test of §2c | a `commit` deleted from the flow |

**Cap: 8 tests per flow** (baseline plus at most 7). If the table yields more, keep in this order:
boundary, blank and whitespace, enum, read-back (§2c), association, date. Put every case you drop
under `skipped:` in the report (§6), so the cap is visible and not silent. A flow with no
decision (a getter) gets the baseline only. Do not build the cross product. Tests cost little to
run (tens of milliseconds each, against minutes of injection and boot per file); the cap protects
authoring effort and review attention.

**The expected value comes from a requirement, never from running the flow.** Cite one in a
comment on the test: a BRD rule, a doc comment on the flow, or house rule H1 in
`unhappy-path-testing.md` ("required means non-blank"). Do not run the flow and paste what it
returned: that encodes the bug as the spec. No requirement and no house rule: **still write the test**, with
the value the flow gives, mark it `UNSPECIFIED` in the report, and do not count it as a pass.
Only the cap may drop a case. "The documents do not say" is not a reason to skip a blank or
whitespace-only input: that is exactly the case the author never thought of, and an UNSPECIFIED
line is how the owner finds out the rule is missing.

## 2c. Flows that commit: read the row back, from outside the test

A flow owes **one** test whose assertion is about the database, not about the variable when it
ends in `commit` or `change ... commit`, **or when its requirement says a value is stored on a
persistent object** (a `change` of an entity attribute, a created row) **even if the flow as
written has no `commit`**. A missing `commit` is one of the bugs this test exists to find, so
do not let the flow's current code decide whether it owes the test: a `change $X (...)` or
`create` on a persistent entity ending in `refresh` or nothing at all is the cue, not the excuse. `@expect $Order/Shipped = true` reads the object the flow just
changed. It stays true with the `commit` deleted, and `@cleanup rollback` leaves no other observer
(false-green row in `testing-shape.md` §4; measured on a seeded flow: the in-memory test passed,
the read-back test failed with `actual: false`).

`@verify` runs after the test body has returned, through the runtime's admin API: another
connection and another transaction, so it sees only what was committed.

```
/**
 * @test MarkShipped persists Shipped (requirement: order shows as shipped after the action)
 * @cleanup none
 * @expect $Done = true
 * @verify select o.Shipped as n from Orders.Order o where o.OrderNumber = 'PERSIST-SHIP-001' = true
 */
$Order = create Orders.Order (OrderNumber = 'PERSIST-SHIP-001', Total = 100.00) commit;
$Done = call microflow Orders.SUB_Order_MarkShipped(Order = $Order);
/
```

Rules, each from the runner's behaviour:

- `@cleanup none` is required: `@verify` is refused with `@cleanup rollback`. The test leaves its
  rows behind, so give it a **unique key** (`PERSIST-<flow>-001`) and put it **last in the file**, or
  in `<Module>.persist.test.mdl`. Later tests that count or `retrieve all` would see the rows.
- The query returns **one row, one column**, aliased (`as n`), compared with `=` to a number, a
  quoted string or `true`/`false`. Zero rows is an error, not a fail. **Persistent entities only**
  (not view or non-persistent ones).
- It runs only after the body passed, and only on `--local` or `--attach`. **Never with
  `--attach`:** the rows land in the live app's database. `--local` starts every run on an empty
  scratch database.
- Do not read back inside the body (`retrieve` after the call): same context, it may return the
  cached object. That is not a read-back.
- Keep the plain rollback test for the logic cases. The read-back is one extra test per committing flow.
- Path length: a copy of the app under a long path (a session scratch folder) made mxbuild fail with
  `IO_PathTooLong`. Run from a short path. `project-bin/test-scratch.sh` is affected too: it makes its copy under `${MXTK_SCRATCH_DIR:-${TMPDIR:-/tmp}}`, so on a machine with a long `TMPDIR` set `MXTK_SCRATCH_DIR` to a short folder such as `/tmp`.
- An enumeration value in `@verify` is a quoted string (`= 'CANCELLED'`), not `Module.Enum.CANCELLED`.
  `--list` shows it before a run.
- Fixture rows the test creates (users, vendors) stay too: unique keys for those as well, per file,
  or a later file fails with "already in use".

Gotchas found by a blind run of this section on seeded bugs (4 of 4 caught):

- `count()` is not allowed inside a `set` expression (CE0117): count into a variable first.
- A variable is `declare`d before its first `set`.
- An AutoNumber attribute cannot be set on create (CE0852). Its boundaries (9/10, 99/100) are
  reachable only by filler commits and still depend on the counter, so list them as skipped
  rather than guess.
- When the flow retrieves its own copy of an object, the test's variable is stale after the call:
  re-retrieve before asserting on it, or read it back with `@verify`.

## 3. Check before you run: free, no model write

```
mxcli test tests/unit/Orders.test.mdl -p App.mpr --list
```

On mxcli 0.21 and later add `--require-assertions`: a test that asserts nothing fails (BUG-LOCAL-30).
Pass only when **both** hold: the listed count equals the number of `/` separators in the file,
and **every** test shows its `@expect`. A plausible count with a missing test is BUG-LOCAL-29.

## 3b. Rollback covers one transaction: what survives it

`@cleanup rollback` undoes the main transaction and nothing else. Measured on a probe app (mxcli
test, hsqldb): a rolled-back test still left an outbound REST call, file bytes on disk, a consumed
autonumber, a separate-transaction commit (`commitInSeparateDatabaseTransaction`), a queued
microflow's commit and the log line. A green test around such a flow sends a mail or posts to an ERP
on every run, or leaves committed rows that break the next test.

Before the first run:

```
./bin/rollback-scan.sh tests/unit/Orders.test.mdl      # or Module.Flow names
```

It reads the catalog (`mxcli -p App.mpr -c "refresh catalog full"` once, or pass `--refresh`),
follows every call from the flows the test calls, and prints one line per effect: `A` survives and
is visible (REST, file, separate commit, queue, mail, workflow), `B` survives and is usually
ignorable (autonumber, log), `U` a Java action it cannot classify. It always exits 0: it advises.
`--json` gives the same for a tool. Teach it a new Java action with one row in
`rollback-effects.tsv`.

For **every A line**, do one of three things and write it in the report:

1. the effect is gated by a constant the test sets (`--constant Module.UseMock=true`);
2. the test is `@cleanup none` with a named cleanup test and unique keys;
3. the flow is not unit-tested; the report says `effect survives rollback: not asserted`.

A-class commits persist into the scratch database, so later tests can see them. B lines: mention
them, no action. Blind spots, so you do not over-trust a clean scan: a microflow name passed as a
string (queue, background) is not followed, an unlisted custom Java action is only a `U`, and an
effect behind a decision is reported as reachable.

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
  inputs: <n> tests for <flows> flow(s) · decisions covered <k> of <K> · skipped: <list or none>
  read-back: <flows that commit> flow(s), <m> with @verify · UNSPECIFIED expected values: <list or none>
  rollback: <n> A line(s) from rollback-scan, each handled by gate / @cleanup none / not asserted
  Read as: these flows return these values on this seed. Not: the feature is wired or secured.
```

A failing test is a finding for the user, not a cue to change the `@expect` until it passes.
Same rule as every test in this toolkit: diagnose, report, no unapproved fix
(`e2e-harness-base.md`).

## Related

- `skills/testing-shape.md`: the module shape, the strategy, §4 false greens, §6 controls
- `skills/learned-db-assertions.md`: asserting the row landed, from the outside
- `skills/unhappy-path-testing.md`: the same input classes at UI level (H1: required means non-blank)
- `skills/journey-proof.md`: what finds wiring defects a unit test cannot see
