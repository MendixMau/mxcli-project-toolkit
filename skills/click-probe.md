# Click probe: a button under an invisible layer, a page that scrolls sideways

**Applies to:** any mxcli project with a running app; module close, after the LOOK.
**Purpose:** two defects no screenshot shows. Advisory: it never changes a verdict or an exit code.

## Run

`node tests/e2e/click-probe.js` (app up: `bin/test-stack-up.sh`; `--pages /p/a,/p/b`, `--json`).
`bin/module-close.sh` runs it and prints one `click probe:` line. It is read-only: it navigates,
scrolls and measures, and never clicks or submits.

## Read it

- A result counts only over its `denominator:` line (page-views, personas, controls checked,
  skipped). Exit 4 means nothing was measured (app down, login failed, no pages): report
  "NOT RUN", never "clean".
- `click does not land: /p/flashcards btnFlip "Show meaning" covered by promoStrip` — an invisible
  container sat over two buttons, taps did nothing, and the screenshot looked perfect. Fix the
  covering element (size, z-index, pointer-events), then re-run.
- `page scrolls sideways at 390: /p/team, widest element filterBar, 17 px over` — a 393 px filter
  bar on a phone. Fix the element named, not the page.
- Accept a finding only in `.claude/loop/click-probe-accepted.tsv`: `kind<TAB>page<TAB>element<TAB>reason`
  (`click` or `sideways`). A line with no reason is ignored and the finding stays.

## What it cannot see

A button that lands but does nothing: `wiring-sweep.md`. A list that is stale after an action:
a journey must assert the change without reloading (`journey-examples.md`, "Common mistakes").
