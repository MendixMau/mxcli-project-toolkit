# The UI measurement run — resolve the scroll root, or measure the top third of the app

**From:** a Mendix POC project (genericised) — UI review sweep, 2026-09-02
**Date:** 2026-09-02
**Kind:** skill-draft
**Field evidence:** A measurement run on a live Mendix Atlas app was reported as done and produced
nothing actionable; re-running it with the scroll root resolved raised measured page heights from a
constant 900px to 900–2907px across 12 captures, and surfaced three P1 defects that had been sitting
below the crop line for a week.
**Proposed target:** skills/ui-measurement-run.md

---

# Skill: ui-measurement-run — measure the rendered UI so the numbers can be checked

**Applies to:** any mxcli project with a running app whose UI is about to be reviewed, gated or
reported on.
**Runs:** before a judged UI review, a `Gate: UI`, or any claim about how the app actually looks.
**Purpose:** produce an evidence bundle — per-page measurements plus full-height captures — that a
reader can falsify. It measures. It does not judge.

**Read the owner, not a copy here:**

| Need | Read |
|---|---|
| The cheap per-page look during the build (one page, one screenshot, three questions) | `ui-loop.md` |
| The spacing scale, section rhythm, page-header scaffold this run measures against | `design-spacing.md` |
| Turning this bundle into a verdict | `judged-review-verdict.md` (proposed alongside this file, `contrib/inbox/2026-09-02-judged-review-trigger.md`) |
| Why the thresholds below stay thin and the judgement stays in prose | `skills-over-scripts.md` |
| Why a green instrument result is not a finding | `tool-output-is-not-ground-truth.md` |

---

## The incident this exists for

A UI measurement run was asked for, reported as done, and produced nothing anyone could act on. Two
symptoms, one cause.

**A Mendix Atlas app does not scroll the document.** It scrolls an inner container — measured live
as `div.mx-scrollcontainer-center` on 11 of 12 captures in the re-run. Therefore:

- `document.documentElement.scrollHeight` legitimately returned **900** on a 1440×900 run, on every
  long page. The document really is viewport-tall.
- Playwright's `page.screenshot({ fullPage: true })` measures that *same* document scroll height, so
  it captured the top 900px of every page and called it a full-page shot.

Real heights, once the right element was measured: **1322 / 2546 / 2604 / 1322 / 2907 / 2809 / 1339 /
2419 / 2671 / 1479 / 900 / 2409**. Roughly **two-thirds of every page had never been in the
evidence**. Three P1 defects lived below the crop line, including a widget cluster collapsed to
single-character labels ("A…" "R…" "S…") beside a ~68px-wide box with text clipped mid-word
("Not asses sed: …"). Five "page reviews" were five top-thirds, and nothing in the bundle said so.

**The correction that matters more than the fix.** The first report accused the instrument of
"fabricating" the scroll height, because 900 on a 2907px page looked impossible. **That was wrong,
and it is corrected here rather than quietly dropped.** The instrument read exactly what it was told
to read, correctly. It was asking the wrong element — and so was the screenshotter. The wrong
diagnosis is expensive in a specific way: "the tool is broken" leads to rewriting the tool, when the
repair was one selector probe and a style release. Before you conclude an instrument is lying, prove
which element it read.

---

## 1. Resolve the scroll root before measuring anything

Probe, in order, and take the first element whose `scrollHeight > clientHeight + 4`:

```
.mx-scrollcontainer-middle, .region-content, .mx-scrollcontainer-center
```

Fall back to `document.documentElement`. **Record which one was used, in the output**, alongside
both numbers:

```json
"viewport": { "w":1440, "h":900, "scrollHeight":2907,
              "scrollRoot":"div.mx-scrollcontainer-center",
              "documentScrollHeight":900 }
```

Both numbers, always. `scrollHeight` alone is unfalsifiable — a reader cannot tell a short page from
a cropped one. With both, the 900-vs-2907 gap is visible on the record itself.

**The failure this prevents:** in the field run, 11 of 12 captures scrolled the inner container and
**1 genuinely scrolled the document** — a persona home page that really did fit in 900px. Without a
recorded `scrollRoot`, that record and a cropped record are the same two lines of JSON. With it, the
instrument distinguishes "short page" from "cropped page", which it previously could not.

---

## 2. A full-height capture needs the clamp released

`fullPage: true` is not a full-page screenshot in an app with an inner scroller. It is a viewport
screenshot with a misleading option name.

Technique, in the page:

1. Find the scroller (§1). Record its `scrollHeight` as `contentPx`.
2. Walk from the scroller up to `documentElement`, saving each ancestor's inline `height`,
   `maxHeight`, `overflow`, `overflowY`, `position`; then set `height:auto`, `maxHeight:none`,
   `overflow/overflowY:visible`, and demote `absolute`/`fixed` to `relative`.
3. Settle (~400ms), read `document.documentElement.scrollHeight` as `capturedPx`, screenshot.
4. **Restore every property touched**, then settle again.

Return a record, not a boolean:

```json
"capture": { "ok":true, "method":"inner scroll container expanded, then fullPage",
             "capturedPx":2907, "contentPx":2907, "complete":true }
```

`complete = capturedPx >= contentPx - 8`. **A capture that came up short must say so on its own
record.** The whole defect above was a run in which every capture was short and every capture
reported success.

---

## 3. Measure before you capture

Releasing the clamp *mutates layout*: every `getBoundingClientRect()` moves, absolutely-positioned
chrome reflows, and section gaps are measured against a page that no longer exists in that shape.

Order per page, no exceptions: **dismiss → settle → measure → capture → restore.** Measuring after
the capture measures the mutation, and the numbers look plausible enough that nobody catches it.

---

## 4. Obstruction check before capture — a known, currently-unfixed gap

State honestly: **this is open, not solved.** In the field run, 1 of 12 captures was taken with a
modal dialog open over the page, covering two of four KPI tiles. The harness's `dismissModal` helper
did not clear it, and the instrument did not notice. That page's record is a measurement of a page
with a dialog over it, presented among eleven clean ones.

**The rule:** before capture, assert that no modal/overlay owns the viewport — a visible
`.mx-window`/`.modal`/`[role="dialog"]`, or any element whose rect covers a large fraction of the
viewport above the content — and **record the result on the page record** (`obstructed: false`, or
the selector and rect that says otherwise). An instrument that cannot tell "this page" from "this
page behind a dialog" is measuring the dialog and labelling it the page.

Until that check exists, a run must read its captures and say which ones were obstructed. The report
that carried this run said so; that is the minimum bar, not a substitute for the check.

---

## 5. Page identity and capture count are different denominators

The field run took **12 captures over 10 distinct page identities**. Two captures were the *same*
page — once clean, once with a modal open on top of it. The giveaway was identical pixel heights
(1322px twice), not the labels, which named two different pages.

Report both, always:

> 12 captures · 10 distinct pages · 1 unreachable · 3 personas

A report that says "12 pages" when it means "12 captures" overstates coverage by 20% and nobody can
see it from the outside.

---

## 6. Record the unreachable, never drop it

One planned page could not be opened at all: no navigation item and no button anywhere in the model
opened it (a model-wide `SEARCH` found only its own title and one microflow comment — it had been
superseded by a tab and left as an orphan).

It belongs **in the output**, with verdict `UNREACHABLE` and the evidence for why:

```json
{ "page":"<page>", "persona":"—", "verdict":"UNREACHABLE",
  "note":"No navigation item and no button opens this page (SEARCH finds only its own title). Superseded by a tab. Listed so the denominator stays honest." }
```

**A page silently missing from a run reads as a page that passed.** Dropping it also shrinks the
denominator, which makes coverage look better precisely where it got worse.

---

## 7. Run-stamp the screenshot folder

In the field run, six PNGs from a previous run — for a page since retired from the plan — sat in the
same directory as the current bundle, indistinguishable by name from current frames. Nothing in the
JSON referenced them; a human browsing the folder cannot tell.

Frames go in a per-run stamped folder: `screenshots/ui-review-<YYYYMMDD-HHMM>/`. That is the entire
fix, and it retires "is this frame from this run?" permanently.

---

## 8. Per-named-persona capture

A capture claimed for a persona must be taken **while logged in as that persona**, with a real logout
between blocks. Proxy substitution is a labelled exception, never a silent equivalence — see the
multi-persona-evidence rule in `e2e-workflow-evidence.md`; it is not restated here.

In this run: 3 personas, each with its own login, and a defect (a config menu visible to the vendor
persona) that only that persona's own session could show.

---

## 9. A declarative plan, not an imperative script

The coverage plan is **data** — a registry of persona blocks, each listing its pages, how each is
opened, and what proves it arrived:

```js
{ persona: 'role-A', steps: [
  { name: 'home',        open: (p) => nav(p, '<menu caption>') },
  { name: 'detail',      open: (p) => clickWidget(p, 'btnOpenDetail'),
    assert: '.mx-name-btnBack, .mx-name-ctnMasterCard', back: '<menu caption>' },
  { name: 'task',        open: (p) => clickWidget(p, 'btnOpenTaskMine'),
    assert: TASK_PAGE_SEL, identify: true, back: '<menu caption>' },
] }
```

Why data: the run can be re-ordered, filtered and resumed; the report and the plan read the same
structure instead of two parallel truths; and a step that FAULTs returns to a known page (`back`)
instead of cascading.

**The failure this prevents:** an earlier plan was menu captions only. The navigation menu carried
four business captions, so the run covered 5 of 11 full pages and **none** of the three task pages
where every business decision is actually taken. Everything not on the menu is reached the way a user
reaches it — a row button — and each step must name what proves it arrived (`assert`). For pages
whose identity depends on runtime data (a workflow task page opens whatever task was assigned),
**read** the identity off the rendered page (`identify: true` → H1/title) rather than asserting it;
labelling a screenshot with the task you assumed is exactly the false-green the multi-persona rule
exists to stop.

---

## 10. Selectors come from the model, never from imagination

Widget names are read out of the model — `DESCRIBE PAGE <Module>.<Page>`, `SHOW PAGES`, `SEARCH` —
before the plan is written. Per `query-the-model.md`: query the model, then read the source, then
guess never.

**The failure this prevents:** guessing widget names on the three task pages cost the field run four
instrument FAULTs in a single pass, each one costing a login cycle to discover. The three pages carry
different button names per decision type; no amount of reasoning about naming conventions produces
them.

---

## Completion criteria — with denominators

The run is done when **all** of these hold, and stated in the output:

| # | Criterion | Bound |
|---|---|---|
| 1 | Every planned page has a record | N records for N planned pages, no silent omissions |
| 2 | Every record names its scroll root | `scrollRoot` present on N of N, plus `documentScrollHeight` |
| 3 | Captures are complete | `capture.complete === true` on N of N, **or** the shortfall is stated per page |
| 4 | Coverage is stated twice | capture count AND distinct-page count, as separate numbers |
| 5 | Unreachable pages carry a verdict | `UNREACHABLE` + the evidence, never absence |
| 6 | Obstruction is stated | `obstructed` recorded, or — until the check ships — named per capture in the report |
| 7 | Instrument faults are separated from page defects | FAULT ≠ FAIL; a fault count of 0 is stated, not implied |
| 8 | Frames are in a run-stamped folder | folder name carries the run timestamp |

"NOT MEASURED" is a legal outcome with a reason (`degrade-to-judgement.md`). Silence is not.

**One measured example of criterion 7's value:** a page whose content root exposed fewer than two
stacked block children returned zero section-gap observations and still reported PASS. A pass over
zero observations is not evidence; that record now reads `UNMEASURED` with the reason attached.

---

## What this skill does NOT do

It **measures**. It does not judge.

Pixel counts, contrast ratios, gap distributions and screenshots are facts. Whether the page is
usable, whether three column widths on one page are a defect, whether a white panel in a dark app is
shippable — those are judgement, and they belong to `judged-review-verdict.md`
(`contrib/inbox/2026-09-02-judged-review-trigger.md`), read over the rendered captures at full size.

Per `skills-over-scripts.md`, moving "is this page usable" into a pixel threshold is the exact
violation this toolkit exists to prevent. Keep the instrument's thresholds thin, published on the
artifact (`majorSectionGapMinPx`, `buttonGapMinPx`, `contrastAA`), and treat every one of them as a
*flag for a human to look at*, not a verdict.

The instrument should also publish its own **measurement caveats** on the artifact — measured
examples from this run: Mendix's own `.mx-demouserswitcher` panel is excluded (it is not app UI and
sits off-canvas; its dark-on-dark headings had accounted for 12 of 14 "AA failures"); DataGrid2's
`.tr` / `.widget-datagrid-grid-body` have a 0×0 box under CSS grid, so occupancy flags computed
against that width had reported "5 buttons in 0px" and "19200% of container width"; Atlas emits
`color(srgb …)` as well as `rgb()`, and an rgb-only parser reported a green button at 1:1 contrast.
Every one of those was a defect that did not exist. **An instrument that does not publish what it
excludes cannot be audited.**

---

## Field run, cited

**2026-09-02, a Mendix POC project, live app at 1440×900.**

- **12 captures / 10 distinct page identities / 1 unreachable / 3 personas / 0 instrument faults.**
- `capture.complete` true on 12 of 12; measured heights 900–2907px (the single 900 self-reporting
  its scroll root as the document — a page that genuinely fits).
- Previous run, same plan family: 5 of 11 full pages, every capture 900px, 0 of them flagged short.

**What the full-height run found that the 900px-crop run could not have found:**

| Finding | Where it lived |
|---|---|
| A collapsed widget cluster — three labels truncated to "A…" "R…" "S…", beside a ~68px box with text clipped mid-word | below the 900px line on the vendor detail page |
| An embedded viewer rendering as a white panel with black text inside a dark app | below the fold on the detail page |
| All three decision pages rendering in the left ~60% of the window, in three unrelated column widths (~865 / ~800 / ~508px) | below the fold on all three task pages |
| KPI tiles contradicting their own grids (a tile reading 11 over a 10-row grid; a tile reading the all-records total) | visible only with tiles and grid in one frame |
| One capture taken with a modal open over the page | found by reading the frames, not by the instrument (§4) |

Four P1s, twelve P2s, over evidence that had previously read as "clean".

---

## Proposed routing row for `README.md` → "When to use which skill"

```
| Measuring a running app's UI — before any UI review, gate or report: resolve the real scroll root (`div.mx-scrollcontainer-center`, not the document) before measuring or capturing, or every page is silently cropped to the viewport; captures ≠ pages, and unreachable pages get a verdict | `skills/ui-measurement-run.md` |
```

---

## Triage notes

- The instrument that produced this evidence exists in the source project as a ~860-line
  `tests/e2e/ui-review-measure.js`. It is **not** proposed for `bin/` as-is: most of its length is
  colour maths and cluster heuristics that belong to the consuming project. What is generic — and
  what this skill states — is the scroll-root probe, the clamp-release capture, the record shape, and
  the denominators. If any code lands in the toolkit, it is those four things and nothing else
  (`skills-over-scripts.md`).
- §4 (obstruction) is a **known open defect**, deliberately shipped in the skill as such. If triage
  would rather not publish an unfixed rule, the honest alternative is to publish it with the same
  "currently unfixed" label, not to omit it — a run today can still *state* obstruction even though
  it cannot yet detect it.
- **Hypothesis, not finding:** the `.mx-scrollcontainer-middle` / `-center` split is likely
  Atlas-version-dependent. This run measured `-center` on 11 of 12 captures and never matched
  `-middle`, but only one app and one Atlas version were observed. The probe list is ordered
  defensively for that reason; treat the specific class as a probe candidate, not a constant.
