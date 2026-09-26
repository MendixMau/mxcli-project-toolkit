# report-normalize.js --selftest fails on a stock checkout and on a real project

**From:** card-disbursement requirements-driven build (build-plan row 3.9)
**Date:** 2026-09-26
**Kind:** bug
**Field evidence:** `node report-normalize.js --selftest` at toolkit f38f808 and at its parent, same result both times: 41 ok, 4 FAIL, then a TypeError.
**Proposed target:** `project-tests/e2e/report-normalize.js` `selftest()` (~l.2631)

---

Pre-existing — the f38f808 two-tree fix did not change it (same output before and after).

With a project's own `project.config.js`:

```
FAIL missing full-app-walkthrough → fault instrument  got=undefined want="fault"
FAIL missing full-app-walkthrough → carries a reason  got=false want=true
FAIL missing mobile-fieldscan → fault instrument  got=undefined want="fault"
FAIL missing mobile-fieldscan → carries a reason  got=false want=true
.../tests/e2e/report-normalize.js:2631
    [inst(empty, 'full-app-walkthrough').canExpressFault, inst(empty, 'full-app-walkthrough').evidenceStrength],
TypeError: Cannot read properties of undefined (reading 'canExpressFault')
```

With the template config in a directory that has no `.mpr` above it, it never reaches the
selftest: `project.config.js` throws "no .mpr found" at require time.

Reading of the cause (from the code, not debugged further): the selftest asserts on instruments
named `full-app-walkthrough` and `mobile-fieldscan` that only exist when the project config
declares those walkthroughs; the real project declares neither. The selftest should build its
own config, or skip the walkthrough cases when none is declared — and it should not need a
`.mpr` at all.
