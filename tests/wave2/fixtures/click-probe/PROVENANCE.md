Captured from a toolkit-built demo app, clean and with planted defects, 2026-11-16.

The four `stageA-*` files are the verbatim output of the first version of the probe (an early
prototype of `project-tests/e2e/click-probe.js`) run against two copies of one demo app: one clean,
one with six planted defects, two of them visual: an invisible container laid over two buttons, and
a filter bar 393 px wide on a 390 px phone. Nothing was edited except that no path appeared in them.
Persona names (`learner1`, `trainer1`) and page names are the demo app's generic ones.

- `stageA-clean.json` / `stageA-clean.txt`: 20 page-views, 0 findings.
- `stageA-seeded.json` / `stageA-seeded.txt`: 24 page-views, 6 with findings.

The prototype's record shape (`persona, width, page, landed, checked, covered[{label, cls,
coveredBy}], overflowPx`) is the one `viewFindings()` still reads, so the fixture parses these
captures with the shipped code. The prototype did not record the widest element or the skipped
counts; the current probe adds `widest` and `skipped`, which these captures therefore lack.

`probe-clean.txt`, `probe-findings.txt`, `probe-not-run.txt` (+ `.rc`, the exit code) are the verbatim
combined stderr+stdout of the CURRENT `click-probe.js` run against the local stand-in pages that
`tests/wave2/test-click-probe.sh` serves (clean pages / a covered button, a 393 px bar and an
accepted-list line without a reason / app not reachable), 2026-11. `test-module-close.sh` C4 replays
them through a stub probe to check how `project-bin/module-close.sh` turns each into its one advisory line.
