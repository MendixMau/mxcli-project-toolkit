# Three ways an end-to-end test goes green over a feature that is not there

**From:** DealIQ (Mendix build project, ~30 modules of BRD-driven work, 21 Playwright e2e tests)
**Date:** 2026-09-13
**Kind:** learning
**Field evidence:** All three were found in one day of e2e work against a live `mxcli run --local`
runtime; each is stated with the measurement that proved it, not as a hypothesis.
**Proposed target:** `skills/testing-shape.md` — its "false-green register" is exactly this shape.
Item 3 may also belong in `skills/module-review.md` as part of LOOK.

---

Three distinct false-green mechanisms, all measured, all cheap to check for.

## 1. A row-scoping test that only counts will pass over a deleted constraint

The entity's read rule carried three XPath conjuncts: same organisation, shared state, and
*owner's team is managed by the current user*. The fixture had **one organisation and one team**,
so the team conjunct was trivially true for every row: delete that clause from the model and not
one count in the test changes.

The fix is to falsify rather than count. The test now moves one shared row to an account that is
in the same organisation but on no team, asserts that exactly that row disappears from what the
manager can retrieve, and moves it back in a `finally`:

```
-- measured: manager retrieves 2 of 227 active rows before, 1 after, 2 again after restore
```

Generalises to any XPath conjunct: **a constraint is only tested if some fixture row fails it.**
If the fixture cannot produce such a row, the test must create one for the duration.

Second, smaller point from the same test: ask the runtime what a session may *retrieve*, not what
a page happens to paint. In Mendix that is `mx.data.get({xpath, filter, callback, error})`
evaluated in the signed-in browser — a real server round trip with that session's entity access
applied. Scraping a list view measures the list view's own filters as well.

## 2. A table with rows and no reader is dead data, and every count-based test passes over it

A whole-app audit joined two mechanical readings — every table with a row count, and every model
element that *reads* it (from the model catalog's cross-reference table, not from a report that
truncates) — and found reference data seeded on every startup by eight microflows and read by
nothing: no page data source, no microflow outside the seeders, no agent tool. It survived
because a *derived integer* on the same records was used everywhere, so all the arithmetic
assertions passed while the human-readable half had never been shown to anyone.

Note what the ordinary dead-code sweep could not see: those records had plenty of inbound
references — all of them **writes**. A sweep for "zero inbound refs" structurally cannot find
this. The reusable instrument is one line:

> For every table with rows, name the model elements that **read** it. If the list is empty or
> contains only the thing that wrote it, the data is dead however well-sourced it is.

Note also `grep -rl <table> tests/` is a generous ranking proxy for "is this covered", never a
verdict — it finds the name, not an assertion.

## 3. An idempotency guard that tests a sibling can never backfill

A seeder's guard read: find the parent record, then retrieve *any* child of one kind and return
early if one exists ("already seeded, skipping"). A later build step added two attributes to a
*different* child entity. Every startup since has short-circuited on the sibling, so those two
attributes were never written to the pre-existing record.

The visible result: the page binds `'{1} · {2}'` over an absent second half, so the tab has
rendered a title, a dangling separator, and an empty body in every demo since — measured in the
browser, and invisible to any test that counted rows.

> **A seeder that returns early on any existing child row can never backfill an attribute added
> later.** So every attribute a later build step adds to a seeded entity is silently absent in
> exactly the environments that have been running longest — the demo environment first.

Guard on the thing you are about to write, not on a sibling that happens to exist.

## What the tests do with a defect they find

All three tests stayed green. Registered defects are printed as `gap` lines rather than
failures, each naming the register row, so the suite is green today and the line flips to `ok`
the day the defect is fixed — and the defect cannot be forgotten in the meantime, because it is
read out on every run.
