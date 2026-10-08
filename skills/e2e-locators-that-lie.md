# Playwright locators that lie about a Mendix page — four harness defects that accuse the app

**Applies to:** any mxcli project with a Playwright e2e suite against Mendix pages — hand-written specs first (see "Runner status" below).
**Purpose:** stop an e2e rung from reporting a confident, specific defect **in the app** that is really a defect in the instrument. Three of the four below were false FAILs; one was a false PASS, which is worse.
**Companion skills:** `e2e-harness-base.md` (widget discovery, `.mx-name-*` selectors), `journey-proof.md` (rung 1 landing guard and the UI text rung), `fixture-seeding.md` (where fixture values come from), `tool-output-is-not-ground-truth.md` (verify before you conclude), `unhappy-path-testing.md` (absence assertions on denied affordances).

Measured 2026-09-17 on a user-group administration module (a tabbed detail page with a members
grid and a per-row role dropdown). Net effect before the four were found: a module with no UI
defect looked broken, and an interaction that did nothing looked green.

---

## 1. A widget name is unique per PAGE, not per rendered DOM

Studio Pro guarantees `dataGrid21` is unique in the page model. It guarantees nothing about how many
times that page renders it. A tabbed page renders each pane's widgets, and the hidden panes are in
the DOM at zero height.

```
.mx-name-dataGrid21  →  2 nodes:  [0] hidden, height 0
                                  [1] visible, height 686   ← the one the user sees
```

`.first().isVisible()` therefore answered **false** about a grid that was on screen, and the landing
guard reported "never appeared". Worse, `.first().click()` and `.first()` on a `<select>` drove the
**hidden** pane: the assertion read its committed value back successfully and passed, while no
microflow ran and the data assertions three lines later failed.

**Rule:** never `.first()` a Mendix widget class unqualified. Either scope it (`within`, `hasText`)
or restrict to `:visible`; and for assertions check **every** match, polling until one is visible:

```js
// interactions: resolve to what a user can actually reach
page.locator(`.mx-name-${n}:visible`).first()

// assertions (landing guard, widget-present, widget-absent): any match visible, within a deadline
async function anyVisible(page, sel, timeout) {
  const deadline = Date.now() + timeout;
  do {
    const loc = page.locator(sel);
    const n = await loc.count().catch(() => 0);
    for (let k = 0; k < n; k++)
      if (await loc.nth(k).isVisible().catch(() => false)) return true;
    await page.waitForTimeout(250);
  } while (Date.now() < deadline);
  return false;
}
```

For an **absence** assertion this matters more than anywhere else: with `.first()` a hidden first
node makes an on-screen affordance read as "not rendered", and an authorisation test passes for
free (`unhappy-path-testing.md`).

## 2. `click({ force: true })` on a Mendix tab does nothing, and does not throw

The tab handler is bound to the inner `<a>`. A forced click dispatches at the `<li>` centre with no
actionability check, so it is swallowed — the tab never switches and the click reports success.

This also defeats the usual fallback idiom, because the `catch` never fires:

```js
await el.click({ force: true }).catch(() => el.click());                   // WRONG — force never throws
await el.click({ timeout: 6000 }).catch(() => el.click({ force: true }));  // right order
```

Plain click first: it waits for actionability and hits the real target. Force is a fallback for a
genuinely obstructed element, not a default. (A hit-test before a forced click, as the shipped
runner does, catches a *cover*; it does not catch a handler bound to a child node.)

## 3. A grid re-renders on the response, not on the click

After a confirmed delete the row was still on screen at 3.5s and gone by 5s. A single text read at
the step's settle time produced *"the screen contradicts the data"* — an accusation against an app
that was refreshing correctly.

**Rule:** assert the eventual state. Poll until the property holds, fail only if it never does,
within a bounded timeout. This is strictly stronger than one read: nothing that passed can start
failing, and a screen that truly never updates still fails.

```js
const awaitText = async (needle, wantPresent, deadlineMs = 15000) => {
  const deadline = Date.now() + deadlineMs;
  do {
    const body = await page.locator('body').innerText().catch(() => '');
    if (body.includes(needle) === wantPresent) return true;
    await page.waitForTimeout(250);
  } while (Date.now() < deadline);
  return false;   // the only FAIL: the screen never reached the claimed state
};
```

Apply it in both directions — `textPresent` and `textAbsent` — or the absence check keeps the
single-read race.

## 4. A fixture constant the fixture script itself writes measures nothing

A check asserted `MemberCount = 6`. The reset script wrote the literal `6`. So the assertion could
only ever confirm the reset had run — and it broke the day the group's real population changed,
failing against a correct app.

**Rule:** derive fixture values from the rows, and assert the *property* the test claims rather than
a magic number. Here "membership must stay single" became a join across both association tables
looking for anyone present in each — independent of how many people the fixture holds, and stronger,
since it catches a double membership for any person rather than just the seeded one. See
`fixture-seeding.md` for where the values should come from in the first place.

## Runner status

`project-tests/e2e/journey-runner.js` (the shipped runner, as of this skill's promotion) does
**not** yet apply rules 1–3: its widget lookup is `.mx-name-<n>` + `.first()` without `:visible`,
its click order is force-then-plain, and its `textPresent` / `textAbsent` rungs read the body once.
So until that lands, the four rules apply to hand-written specs **and** are the first things to check
when a runner verdict names the app. Rule 4 is about the journey's `sql` checks and fixture script,
which the runner cannot fix for you.

## The meta-lesson

Every one of these reported a defect in the software under test. When an e2e rung fails, the first
question is not "what did the app break" but **"did the instrument look at the right thing"** — take
the screenshot, count the matching nodes, and poll before concluding
(`tool-output-is-not-ground-truth.md`).
