# Skill: ui-loop — look at the page you just built, before you build the next one

**Applies to:** any project building pages or snippets.
**Runs:** after every page-building script, and any time someone says the UI looks wrong.
**Cost:** minutes. That is the point — it is cheap enough to run ten times per module.

---

## What this is, and what it is NOT

This is the **cheap, repeatable look during the build**. One page, one screenshot, three questions,
no report. Run it, fix what it finds, keep building.

**It does NOT discharge `Gate: UI`** (`iterative-build-loop.md` step 14), and it does not replace
`module-review.md` stage 4. Those are the *one* review a module gets before it is called done —
every page in the module derived from the model, a written verdict each, a stated denominator, an
HTML report with the screenshots embedded. That pass still runs, unchanged, at module close.

> **Read this before deciding the two are redundant.** `ui-review-loop.md` was tombstoned in this
> toolkit precisely because a second UI skill competed with the module-close review *for the same
> job at the same moment*, and the one that got skipped was always the looking. This skill is not
> that: it is a different **cadence**, not a second verdict. It finds defects while they are one
> script old; the module-close pass is still what decides whether the module is done. If you ever
> find yourself running this *instead of* stage 4, you have re-created the bug the tombstone
> records — stop and run the real pass.

---

## Why cadence is the whole point

`Gate: UI` fires **per module**. On a single-module app that is once, at the very end, after every
page already exists.

Measured (2026-08-24, field validation run): a two-column detail page shipped stacked full-width
because its layout class was never defined in the real theme. It was introduced in build script
09 and survived scripts 10, 11, 12 and all of Stage 6 prep — mxbuild clean, every journey green,
21 of 21 interactive elements wired — until a human looked at module close. Nothing before that
moment asks what a page looks like. Four scripts of blast radius, from a defect that a
thirty-second look at script 09 would have caught.

The gate was not missing. Its cadence was too coarse to catch anything early.

---

## The loop

After a script that creates or changes a page:

1. **Run it and open the page** — through real navigation, as a real user role, not a direct URL.
2. **Screenshot it.**
3. **Ask three questions** against the page's wireframe (or the design system if there is no
   wireframe):
   - **What's missing?** A field, button, column or whole section that should be there and isn't.
   - **What looks wrong or unfinished?** Broken or stacked layout, unstyled elements, sections
     jammed together, duplicated headings, placeholder text, no page title.
   - **Would you put this in front of the customer tomorrow?** If not, one sentence why.
4. **Fix it now, or write it down now.** A defect that survives into the next script costs more to
   find and more to place.

**Judge from the screenshot, never from the CSS.** A page can have a perfect stylesheet and render
wrong — that is the exact escape this loop exists to close (`module-review.md`, the pixel rule).

---

## The prompt

Hand this to an agent, or run it yourself:

```
Run the app and open <page>, logged in as a real user role. Screenshot it.

Compare what you see against its wireframe in design/wireframes/ (or against
design/ds.css if there's no wireframe) and tell me:
  - What's missing — a field, button, column or section that should be there and isn't.
  - What looks wrong or unfinished — broken or stacked layout, unstyled elements,
    sections jammed together, duplicated headings, placeholder text, no page title.
  - Would you put this page in front of a customer tomorrow? If not, one sentence why.

Judge from the screenshot, not from the CSS. Don't fix anything yet, just give me the list.
```

Deliberately unprimed: no list of known bugs to hunt for. Tell someone to look for two specific
things and they find those two and stop, and whatever else is wrong with *this* app goes unseen.

---

## What the loop costs — measured

Greenfield pilot, cloud container, mxcli v0.20.0 `run --local --watch` kept warm, 2026-09-04,
one page script (`create or replace page`, one class changed):

| Step | Time |
|---|---|
| `bin/exec.sh` (doctor-quick + check + snapshot + exec + mxbuild gate) | 44 s |
| watch rebuild + hot-apply (runs *inside* the 44 s — it reacts to the write, not the gate) | 18 s, overlapped |
| journey to the page + screenshot, warm browser | 3 s |
| **edit → screenshot in hand** | **~47 s** |

So the look costs under a minute per page script, and the watch surfaced a real error
(CE6083, a design property the theme does not support) in its own log **before** exec.sh's
gate reported it — two independent readings of the same build. What the look then showed:
the "fix" (`Class: 'form-vertical'`) landed in the model, passed the gate, and changed
nothing on screen, because the theme, not the page, decides the form orientation — the
first row of the table below, met on the first attempt.

## When it finds something — which side is actually wrong

The symptom is easy to see. **Where the fix goes is not, and the instinct is usually wrong.**

| Symptom | Check first | Where the fix goes |
|---|---|---|
| Page renders unstyled / stacked / ignoring its layout | Does the class the page references actually exist in `themesource/<module>/web/main.scss`? | Usually the **theme**, not the page. A wireframe's own inline `<style>` can hold real page-specific layout CSS that `ds.css` does not — if nobody ported the rule, the page is correct and the theme is missing it. Add the rule. See `learned-stylegallery.md` § "Don't Stop at ds.css". |
| A popup shows its title twice | Does the body restate the popup's own `Title:` as an H1? | The **page**. The popup chrome already renders a title bar; delete the in-body heading. See `learned-page-patterns.md` § "Popup Pages — Never Duplicate the Chrome Title". |
| Sections flush together, no page title, off-scale gaps | The spacing scale and page scaffold | The **page**. `design-spacing.md` §2–3. |
| Referenced class exists nowhere at all | — | Either: invent the rule, or the class name is a typo. Decide which; do not delete a class that the wireframe genuinely specifies. |

**Warning on `design-audit.js`:** its `rung6/wireframe-chrome` finding cannot yet tell genuinely
wireframe-only annotation markup apart from real page layout CSS that was never ported. Its wording
reads as *"delete this class"*; for row 1 above the correct fix is the opposite. Check which case
you have before acting on it.

---

## Related

- `iterative-build-loop.md` step 14 — `Gate: UI`, the per-module gate this loop feeds. Still
  mandatory; this does not discharge it.
- `module-review.md` stage 4 (LOOK) — the full pass: every page in the module, 9-row rubric,
  stated denominator, HTML report. The verdict of record.
- `ui-preflight-pages.md` — read *before* building a page; this skill is the check *after*.
- `design-spacing.md` — the spacing scale and page scaffold this loop judges against.
- `ui-review-loop.md` — tombstone. Read it before proposing to merge this file into
  `module-review.md`; it explains what merging cost last time, and why cadence is the difference.
- **Mechanical instruments that run alongside the eyeball look, added 2026-08-25/26 from a
  second field run** (a `rem`-vs-10px-root defect family this loop's own "look at it" step
  cannot see by eye — a 1.6× size error reads as merely "a bit small," not as broken):
  - `project-bin/check-design-portability.sh` — greps `ds.css`/theme for units and selectors
    that cannot match what Mendix emits (`rem` against the real root, `table`/`th`/`td`
    selectors, positional `nth-child` rows). Run before porting, and at the Stage-3 gate.
  - `project-bin/check-page-shell.sh` — a binary gate on the page shell (column, layout/nav,
    one H1) against the wireframe, before `exec`.
  - `project-bin/page-fidelity.js` — the scored companion: headings/actions/content/classes
    against the wireframe, weighted. Run it after drafting and again after `exec`. Every run
    is appended to the project's `docs/PAGE-FIDELITY.tsv` — the first **non-stub** row per
    page is the first-build score of record against the ≥80% target; later rows are the
    rework curve. Forward-reference stubs are scored with `--stub` (row marked `stub`,
    exempt from the target — declared at scoring time, never claimed afterwards).
    A page with no row was never scored, and that absence is itself a finding.
  - `learned-stylegallery.md` § "The Mendix DOM contract" and § "Every class states its
    carrier" — the same class can render correctly on one widget and half-apply on another
    (Atlas's compound selectors on `ACTIONBUTTON` beat a single design-system class); state
    the intended carrier in the component table, don't assume it.
  None of these replace the look — a portability check cannot tell you a heading is missing,
  and this loop cannot tell you a `rem` is 62.5% of what was authored. Run both.
