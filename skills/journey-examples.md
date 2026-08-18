# Journey examples — a guided tour of the contract

**Companion to `journey-proof.md`.** That skill argues *why* a journey is asserted at five rungs and
why each rung needs a mutant. This one is the worked reference for the file you actually have to
write: what every field does, what reads it, and what happens when you leave it out.

**Preconditions are a different skill.** What the seeds need to find, who is allowed to create it,
and how the fixture gets reset between a real run and a control run: `fixture-seeding.md`.

## The files

| File | What it shows |
|---|---|
| `examples/journeys/minimal.journey.json` | The smallest thing the runner will still walk: login, land, one text assertion. Two rungs, and it says so. |
| `examples/journeys/full.journey.json` | Every field the runner reads, and the only one of the three that supports all seven control mutants. **Copy this one.** |
| `examples/journeys/no-seed.journey.json` | A screen fed from a mock/REST source: empty `seeds[]` with a `_seedNote` explaining why there is nothing to seed, and rungs 4–5 named as absent instead of faked. |
| `examples/brd/F101-purchase-requests.brd.json` | A trimmed BRD so the requirement pointers in the journeys actually resolve. |
| `examples/validate-journeys.js` | Static contract checks with no app, no browser, no database. `--selftest` proves each rule can fail. |

The domain is invented (purchase requests and a supplier catalogue). Nothing in it corresponds to
any real project.

```bash
node examples/validate-journeys.js --selftest                                  # 16 rules, each watched going red
node examples/validate-journeys.js --brd examples/brd examples/journeys/*.json # the examples themselves
node examples/validate-journeys.js --brd <brdDir> journeys/*.journey.json      # your project
```

---

## Read this before the field table

**Everything below was read out of `tests/e2e/journey-runner.js`.** Where the runner does not
consume a field, it is documented as *not read* rather than described from the spec — because a
field that appears in a real journey and is ignored by the engine is a finding, not an example.

Three of those are worth knowing before you write anything:

1. **`persona` is a label, not a credential.** The runner prints it and copies it into the walk. It
   authenticates with `cfg.user` / `cfg.pass` (env `TEST_USER` / `TEST_PASS`) and can fall back to
   `cfg.fallbackUser`. Nothing reconciles the two. A journey whose `persona` says `approver_test_user`
   while `TEST_USER` is unset walks as whatever `config.js` defaults to, and the report names the
   persona anyway. On a fallback the runner records `login INVALID` and **skips every journey** — the
   findings file then contains one row and no walk at all.
2. **Any key you invent is ignored.** All the `_why` / `_note` / `_seedNote` / `_dataRungGap` keys in
   the real journeys and in these examples are author commentary; the runner never reads them. That
   is what makes JSON journeys tolerably self-documenting. The exception is a comment object dropped
   *inside* an array the runner iterates (`textPresent`, `ordered`, `checks`) — there it becomes an
   assertion.
3. **The `rung` field in the findings is not a number.** It is one of `ui`, `trace`, `data`,
   `outcome`, `control`. The runner's own header comment numbers the rungs differently from
   `journey-proof.md` (see *Spec vs. runner* at the end). Do not build tooling on the numbers.

---

## Field reference

### Journey level

| Field | Required? | What reads it | If omitted | Worked value |
|---|---|---|---|---|
| `id` | in practice, yes | walk record, control-mutant ids, screenshot filenames, the outcome finding's name | the string `undefined` appears in all of those | `"J-PR-01"` |
| `title` | no | printed; copied into the walk | blank title in the report | `"Purchase request — pick a supplier, submit for approval"` |
| `persona` | no | **printed and copied into the walk only** — never used to log in | the walk shows `cfg.user` instead | `"approver_test_user"` |
| `requirement[]` | no, but see below | fallback pointer list for every step that declares none; also attached to the seed-failure and outcome findings | findings carry an empty requirement — "23 pass" becomes a claim about the app, not the spec | `["F101#/useCases/0/mainFlow/0"]` |
| `seeds[]` | no | resolved in array order before the walk | nothing to substitute; the walk still runs | see below |
| `steps[]` | **yes** | the walk | nothing happens | see below |
| `outcome` | no | rung 5, after the last step | rung 5 is absent, which `journey-proof.md` classes as `fault` — say why in a `_outcomeGap` note | see below |

### `seeds[]`

```json
{ "name": "supplierName",
  "sql": "SELECT Name AS n FROM Procurement.Supplier WHERE SupplierCode = '{{supplierCode}}' LIMIT 1" }
```

| Field | Required? | Behaviour |
|---|---|---|
| `name` | yes | becomes `{{name}}` |
| `sql` | yes | run through `helpers.oqlScalar` — **first cell of the first row**. Every column must be aliased (`AS n`); mxcli rejects an unaliased `SELECT`. |

- Seeds resolve **in array order** and may reference **earlier** seeds. That is the whole reason
  `supplierName` is keyed off `supplierCode` rather than being a second `LIMIT 1`: two unordered
  `LIMIT 1` queries can return different rows, and then the journey selects supplier A and asserts
  about supplier B.
- A seed returning `null` or `""` **aborts the journey** with a single `INVALID` finding. Not `FAIL`.
  `fixture-seeding.md` lists four causes of that with four different owners — never report it as one.
- There is **no way to generate a run-unique value**. Seeds read the database; they do not mint. This
  is why the data rung's queries are whole-table (below).
- Substitution happens in: `actions[].value`, `actions[].match`, `ui.textPresent[]`,
  `ui.textAbsent[]`, `data.oql[].sql`, `data.assocMustBeSet[].mustPointAt.value`, `outcome.sql`, and
  later seeds' `sql`. **Not** in `ui.ready`, `ui.checks[]`, `spans.*`, `data.creates`, or
  `assocMustBeSet.assoc` / `.target` / `.entity`.

### `steps[]`

| Field | Required? | What reads it | If omitted |
|---|---|---|---|
| `name` | in practice, yes | prefixes every finding this step records, and names it in the walk | every finding reads `undefined: …` |
| `requirement[]` | no | **replaces** the journey list for this step's findings | inherits the journey list |
| `actions[]` | no | performed in order before any rung | the step asserts about wherever the walk already is (legitimate for a first landing step) |
| `ui` | no | rungs 1–2 | no landing guard: later rungs may measure the previous page |
| `spans` | no | rung 3 | no trace assertion |
| `data` | no | rung 4 | no data assertion. `null` is fine and is what the read-only real journeys use |

If a step's actions throw, or its landing guard fails, the runner records the failure and **returns
from the whole journey** — later steps and the outcome rung produce no rows at all. A missing outcome
row means "the walk did not get there", never "not applicable".

### `actions[]`

| `do` | Fields read | Notes |
|---|---|---|
| `nav` | `group`, `item` | Anchor `title` attributes, clicked as a user would. Nav groups **toggle** — clicking an expanded one collapses it, so journeys must start from a reset state. |
| `click` | `widget` | Waits for attached, scrolls into view, requires visible, then `click({force:true})`. Not visible → throws → step `FAIL`. |
| `fill` | `widget`, `value` | Targets `input`/`textarea` inside the widget. `value` is substituted. |
| `combobox` | `widget`, `match` | The heavy one — see below. |
| `dismissModal` | — | Clicks up to three modal-footer buttons. |
| `wait` | `ms` | **`ms`, not `settleMs`.** |
| anything else | — | throws `unknown action` → step `FAIL`. |

Every action also reads `settleMs` (default 1200, applied *after* the action) and `label`
(**display only** — the walk narrates `Click "Submit for approval"` while keeping `.mx-name-btnSubmit`
for whoever has to fix it). `widget` is a bare Mendix widget name; the runner prepends `.mx-name-`.

**`combobox` asserts as it goes**, and this is the most instructive code in the runner. It reads the
option list, refuses to proceed if nothing matches `match` (rather than falling back to option 0),
steps the highlight while re-reading `aria-activedescendant` each time, then re-reads the committed
input value and requires it to contain `match`. It emits its own `PASS` row for that. The reason is
recorded in the source: a fallback-to-index-0 once committed a real, valid, *neighbouring* row, and
every downstream rung agreed with it — the row saved, both FKs were non-null, the span was `OK`, and
the screenshot looked perfect.

### `ui` — rungs 1 and 2

| Field | Vocabulary | Behaviour |
|---|---|---|
| `ready` | **full CSS selector** | Rung 1. `page.locator(ready)`, 12s. Fail → `FAIL` + a `NOT-REACHED` screenshot, and every rung below is recorded `INVALID`. |
| `checks[]` | **bare widget names** | Visibility of `.mx-name-<name>`, 4s each. `FAIL`, not `INVALID`. |
| `textPresent[]` | strings, substituted | Substring of `body.innerText`, case-sensitive. |
| `textAbsent[]` | strings, substituted | Present → `FAIL` with `"the screen contradicts the data"`. |

`ready` and `checks` take **different vocabularies**, and mixing them up is the easiest mistake in
the format: `checks: [".mx-name-btnGo"]` becomes `.mx-name-.mx-name-btnGo`, which reports as a
missing button rather than as a broken contract.

The success screenshot is taken **after the actions and the landing guard, before the text, trace and
data rungs** — so the image is the page state those rungs measured. A shot taken later shows the app
after any navigation the rungs provoked and quietly stops being evidence for the checks printed
beside it.

### `spans` — rung 3

```json
"spans": { "ordered": ["Procurement.ACT_Request_Save", "Procurement.ACT_Request_Submit"],
           "mustNotFire": ["ACT_Request_Delete"] }
```

| Field | Behaviour |
|---|---|
| `ordered[]` | Matched **exactly** against the `mx.microflow.name` tag, so **module-qualified**. Subsequence check over span start time: incidental flows between them are tolerated, a reorder or a skip is not. Spans sharing a start time are treated as concurrent. |
| `mustNotFire[]` | Compiled with `new RegExp(n)` against the same tag, so an unqualified name works as a substring. |

**Verified trap: the entire trace block runs only when `ordered` is present and non-empty.** Capture,
the non-empty guard, `assertNoErrors` *and* `mustNotFire` all live inside that `if`. A step declaring
only `mustNotFire` is silently never checked. Always pair them. `validate-journeys.js` fails on it.

Declaring `ordered` buys `assertNoErrors` for free, and that is the check worth having: it walks
**activity** spans, so it sees a caught error that leaves the microflow span `OK` while the work did
not happen. Zero spans captured is `INVALID`, never a pass — `[].every()` is `true`.

### `data` — rung 4, which is three claims

| Field | Behaviour |
|---|---|
| `creates` | Entity name. Row count is baselined **once, before the walk**, for every distinct `creates` in the journey; after each check the baseline advances to the observed count. |
| `delta` | Expected change. **Defaults to 1** when `creates` is set — declare `0` explicitly if the step must write nothing. |
| `assocMustBeSet[]` | `{entity?, assoc, target, mustPointAt?}`. `entity` defaults to `data.creates`. |
| `mustPointAt` | `{attr, value}` — `value` is substituted. |
| `oql[]` | `{label, sql, expect \| atLeast}`. |

```
delta           the row was created              → "something was saved"
assocMustBeSet  the FK is non-null               → "…WITH its association"
mustPointAt     the FK points at the seeded value → "…at the RIGHT one"
```

`assocMustBeSet` is measured as an **assocGap**: `COUNT(*)` minus `COUNT(*)` over an `INNER JOIN`,
because the join silently drops null-FK rows, so the difference is exactly the rows that saved
without their link.

**Set-ness is not correctness, and the scope caveat is bigger than the spec implies.** Both queries
run over the **whole table**, not over the row this run created:

- `assocMustBeSet` goes red forever if one legacy row has a null FK, whatever this run did.
- `mustPointAt` passes if **any** row anywhere points at the seed — including one an earlier run
  wrote. It is only a per-run claim on a fixture that is reset between runs.

Since seeds cannot mint a run-unique value, there is no way to scope these to "my row" inside the
contract. Reset the fixture, or state the weakening in the report. `fixture-seeding.md` §"One more
contract" is where the reset belongs; note that `--positive-control` writes real rows too.

An `oql` entry (or an `outcome`) with **neither `expect` nor `atLeast`** is recorded `INVALID`, not
`PASS` — the runner refuses to print a green cell for a check that cannot go red. Prefer `atLeast`
when the fixture carries history: "at least one linked row now exists" is honest where "exactly one"
is a lie about the data.

### `outcome` — rung 5

`{sql, expect | atLeast}`, substituted, run once after the last step. Per-step deltas can each be
right while the net result is wrong: a request that saved, linked correctly, and never left `Draft`
passes every rung above and fails here. The runner reads `outcome.sql` specifically — a journey that
spells it `query` gets no rung 5 and no complaint.

---

## Requirement pointers

Format: `<BRD id>#<RFC 6901 JSON Pointer>`, e.g. `F101#/useCases/0/mainFlow/6`, resolving into
`F101-*.brd.json`. `examples/brd/F101-purchase-requests.brd.json` is a trimmed BRD in the real
schema so that every pointer in the examples resolves; `validate-journeys.js --brd <dir>` checks them.

**The runner does not resolve them.** It copies the string into every finding it records and never
looks at it. Nothing in the harness will tell you a pointer is dangling — which matters, because a
dangling pointer looks in the report exactly like a satisfied one.

Two conventions the real journeys got right and are worth copying:

- **Point at what the check actually exercises**, not at the module. A nav step points at
  `#/useCases/0/mainFlow/0` and `#/security/rolesToPages/0`; a submit step points at the flow line
  and the page action.
- **Do not attach a pointer a walk cannot cover.** One real journey deliberately leaves a
  site-scoping requirement off every step and records in a note that no check can catch it, because
  it is a static property of the model and the page renders identically either way. An attached
  pointer is a claim of coverage.

If a journey has no BRD at all, say so in a `_requirementGap` note and leave `requirement` empty.
Inventing a pointer to fill the cell is the exact failure the harness exists to prevent.

---

## Common mistakes

Each of these is either an error path in the runner or a correction recorded in a real journey.

| Mistake | How it presents | Fix |
|---|---|---|
| `checks` given a selector, or `ready` given a bare widget name | a missing-button `FAIL` that sends you to the page instead of the contract | `ready` = selector, `checks` = bare names |
| `mustNotFire` with no `ordered` | silence — the claim is never evaluated and nothing says so | pair it with a non-empty `ordered` |
| Unqualified name in `ordered` | `FAIL` on a microflow that did run | qualify it; `ordered` is an exact match on `mx.microflow.name` |
| `ready` guessing where a commit lands | one real journey expected the commit to return to the home page; it stays put and updates in place. The guard failed loudly and marked the rest `INVALID` | that is the guard working — fix the contract, not the app |
| `oql` / `outcome` with no `expect` or `atLeast` | `INVALID` on every run, forever | declare a bar; prefer `atLeast` on a fixture with history |
| Two independent `LIMIT 1` seeds | the journey selects one row and asserts about another | key the second seed off the first |
| Unaliased seed SQL | seed resolves to `null` → whole journey `INVALID` | `SELECT Name AS n …` |
| `wait` with `settleMs` | the wait is 1200ms, not what you wrote | `wait` reads `ms` |
| A `_note` object inside `textPresent` / `ordered` / `checks` | the comment becomes an assertion | comment on the parent object, never inside an iterated array |
| Treating "seeds returned nothing" as a feature failure | someone debugs the app for a fixture gap | `INVALID`; see `fixture-seeding.md`'s four-cause table |
| `persona` drifting from `TEST_USER` | the report names an identity that never walked | keep them in step; check `usedFallback` in the findings file |
| Reading a green `assocMustBeSet` as "linked to the right row" | the wrong-but-valid neighbour passes everything | add `mustPointAt`, and reset the fixture so it means something |
| Running `--positive-control` against a demo baseline | the control run writes real rows | separate fixture; the runner already writes controls to `journey-findings-control.json` |

---

## What each example proves under `--positive-control`

`journey-proof.md` requires all **seven** mutants, and a rung with no mutant is `fault`, never `pass`.
Mutants that a journey cannot support are skipped silently, so a "green control run" over the wrong
journey proves less than it looks like:

| Journey | Mutants it can produce |
|---|---|
| `full` | all seven — `ui-landing`, `ui-text`, `trace-order`, `trace-negative`, `data-delta`, `data-target`, `outcome` |
| `no-seed` | four — the two UI and the two trace mutants |
| `minimal` | two — `ui-landing`, `ui-text` |

Report the count, not the colour.

---

## Spec vs. runner — divergences found while writing this

Stated so a reader is not surprised, and so whoever owns the spec can decide which side to change.

1. **`persona` implies authentication in the spec's pipeline table; the runner never uses it.**
2. **Rung numbering does not agree.** `journey-proof.md` numbers landing/text/spans/data/outcome 1–5;
   the runner's header says "four rungs" and its inline comments label spans as rung 2, data as 3 and
   outcome as 4. The emitted `rung` field is a string enum (`ui`/`trace`/`data`/`outcome`/`control`).
3. **`mustNotFire` is gated on `ordered`.** The spec presents it as an independent rung-3 claim.
4. **Rung 4's queries are whole-table**, so `mustPointAt` is a weaker claim than "the row this run
   created points at the seed" unless the fixture is reset.
5. **A journey that bails early emits no outcome row at all** — silence, where the spec's discipline
   would ask for `fault`.
6. **The pointer example `F007#/rules/3` in `journey-proof.md` does not resolve** against the real BRD
   schema, which has no `rules` key. Point at `useCases` / `pages` / `security` / `microflows`.
7. **"A step with zero checks is `fault`" is not enforced by the runner** — such a step simply records
   nothing. Whether the normalizer catches it was not verified here.

## Honesty note

The three example journeys **have never been executed.** There is no app behind
`Procurement.PurchaseRequest`. They are validated statically — they parse, and they pass all 16 rules
in `validate-journeys.js`, whose own `--selftest` shows each of those rules going red on a
deliberately broken input. Everything stated about runner behaviour was read out of
`tests/e2e/journey-runner.js`, `helpers.js` and `otel.js`; anything that could not be settled by
reading is marked *not verified* rather than guessed.
