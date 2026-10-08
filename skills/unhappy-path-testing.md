# Skill: unhappy-path-testing — every case cites a requirement, or a house rule, before it runs

**Applies to:** any built module with a form, a role-gated action, or a REST backend; any mxcli project.
**Purpose:** e2e beyond the happy journeys — missing fields, invalid values, wrong state, wrong role,
a down or slow backend, stale data, double clicks — with every case tied to a cite so its result can
be *judged*, not just recorded. Also for the moment an agent must decide whether odd behaviour is a defect.
**Source:** a warehouse-management demo project, 2026-09-24/25 — 45 cases, 5 modules, 5 overnight runs,
then one fix loop. Promoted 2026-10-08.
**Companion skills:** `journey-proof.md` (runs first), `monkey-test.md` (runs after), `learned-db-assertions.md`,
`e2e-harness-base.md`, `testing-shape.md`.

---

## Why it is not fuzzing

`monkey-test.md` measured random input at **0 defects against 9 for scripted journeys**. Unhappy
paths find defects only when each case asks a *specific* question that a requirement answers.
Without a requirement, a result cannot be judged. The case then records behaviour and the
defect hides in plain sight.

## The matrix comes first, the code second

Write `docs/handoffs/unhappy-path-matrix.md` before any spec. One row per case:

| ID | Requirement cite | Scenario | Expected per requirement | Assertion (UI **and** DB) | Status |

- **Cite** is a quote with its source, e.g. a BRD business rule, the entity's own doc comment, a
  `not null error '…'` in the domain model, a page's `Visible:` expression, or a grant line read
  with `DESCRIBE`. Read the **live model**, not `mdlsource/`: a committed script is not an
  executed one (`tool-output-is-not-ground-truth.md`).
- **Status** is filled by the run, never by hand:
  - **PASS**: the app does what the cite says.
  - **GAP**: the app does what the cite forbids, or does not do what it demands. A real finding.
  - **UNSPECIFIED**: the cite is silent; the behaviour is recorded, not judged.
- **Reject a source that is about something else.** Check every BRD you cite against the entity
  it is meant to cover. In the source project a BRD titled "equipment management" turned out to
  describe a different domain's module that happened to share the word; it was read, rejected in
  writing at the top of the matrix, and the module's cases were grounded in the live entity's own
  doc-comment rules instead. Citing it would have produced confident nonsense.

## The categories to cover, per module

For each entity or screen, write at least one case per applicable row:

1. **Required fields**: blank, and a single space (does `not null` stop whitespace?).
2. **Length and format**: one past the column width, a bad format against a stated pattern.
3. **Duplicates**: a second record with the same business key.
4. **Cancel**: fill the form, cancel, check that no row exists.
5. **Double submit**: two clicks under 300 ms; count the rows.
6. **Wrong state**: act on a record whose state forbids it (released, closed, retired).
7. **Wrong role**: log in as a read-only role, then assert the button is absent **and** that the
   microflow refuses (hiding is not access control).
8. **Backend errors** (REST modules): down (connection refused), 4xx with problem details,
   5xx, empty body, slow. Assert the user sees a sentence, not a stack trace or a blank list.
9. **Concurrency**: two sessions, one stale write; the app should say so, not overwrite.
10. **Empty results**: a search that matches nothing; is there an empty-state message?
11. **Security posture**: grants read from the model (anonymous CRUD, over-broad module roles).
    Report as findings; do not drive them through Playwright.

## The house-rules fallback: UNSPECIFIED must not be a hiding place

In the source project, 13 of 45 cases came back UNSPECIFIED. Reviewing those rows afterwards, at
least 6 were defects a user would report: whitespace passing "required", silent truncation at the
20- and 200-character column widths, no empty-state text. Nothing flagged them, because no
requirement spoke. This is `degrade-to-judgement.md` applied to a test matrix: a missing
requirement changes what you assess *against*, never *whether* you assess.

So every UNSPECIFIED result is scored a second time against these **house rules**, and a failure
is reported as **GAP-HOUSE**, a separate count from GAP:

| House rule | Fails when |
|---|---|
| H1 Required means non-blank | A value of only spaces passes a required field |
| H2 Never truncate silently | Stored value is shorter than typed, and no message said so |
| H3 Empty is explained | A list that matches nothing shows a blank area, with no text |
| H4 Errors are sentences | The user sees a code, a stack trace, JSON, or nothing |
| H5 One click, one record | A double submit creates two rows |
| H6 Cancel leaves nothing | A row exists after Cancel |
| H7 Hidden is also refused | A role that cannot see a button can still run its microflow |

The house rules are not requirements. Put GAP-HOUSE rows in front of the product owner as
Decisions ("fix, or accept as designed?"); do not fix them unasked.

## Assertions that cannot pass vacuously

- **UI and DB, both.** "Error text visible" alone passes when the form never saved anyway. Count
  rows in the DB before and after, with the same filter the case is about
  (`learned-db-assertions.md` for the mechanics).
- **Guard the precondition.** Assert that the record under test exists and is in the state the
  case needs, before acting. A case on a released route passes trivially if the seed has none.
- **Log in as a real non-admin role, and assert the username on screen.** A harness that falls
  back to an admin account on a failed login makes every role case pass.
- **Assert the nav landed** (page title or a page-unique element) before reading anything —
  see `e2e-locators-that-lie.md` for the locator side of this.
- **Never count visible rows** as a total; they stop at the page size.
- For REST modules, **stop or break the backend on purpose** in the down cases, and check that it
  really was down (a health probe fails) before asserting the message.

## Running and reporting

- One spec per module (`tests/e2e/unhappy/unhappy-<module>.js`), one runner that writes
  `results.json` with an ID, status, the cite, the observed behaviour, and a screenshot path per
  case.
- The report headline is counts **with the denominator**: `27/45 PASS, 5 GAP, 6 GAP-HOUSE,
  7 UNSPECIFIED, 0 ERROR`. An ERROR (the test itself broke) is never folded into PASS or GAP.
  A missing `results.json` is reported as missing, never as `0/45` (`measured-claims.md`).
- Every GAP gets a line: the fix, or the Decision it maps to. In the source project all 5
  remaining GAPs mapped one-to-one to open product Decisions; that mapping is the useful output.
- Look at the screenshots of every GAP and GAP-HOUSE before reporting. A GAP whose screenshot
  shows the previous page is a test defect, not an app defect.
- Expect the early runs to be dominated by **instrument faults, not app faults**: in the source
  project run 2 reported 17 GAPs, 10 of which were one module's spec using a deep link the
  runtime answered with HTTP 404. Triage every GAP cluster that lands on a single module as a
  harness suspect first.

## Where this came from

A warehouse-management demo project, 2026-09-24 and 25: matrix `docs/handoffs/unhappy-path-matrix.md`,
specs under `tests/e2e/unhappy/`, run log in the overnight handoff. Five runs went
16 → 19 → 22 → 21 → 25 of 45 PASS as harness faults and app fixes landed; the next day's fix loop
took it to **27/45 PASS, 5 GAP, 13 UNSPECIFIED**, with every GAP an open Decision. The house-rules
fallback is the lesson from reviewing the 13 UNSPECIFIED rows afterwards; it had not yet been run
as a second scoring pass in that project, so GAP-HOUSE counts above are the shape, not a measurement.

Related: `e2e-locators-that-lie.md`, `measured-claims.md`, `tool-output-is-not-ground-truth.md`,
`degrade-to-judgement.md`, `testing-shape.md` §4a (why a green UI report can still be lying).
