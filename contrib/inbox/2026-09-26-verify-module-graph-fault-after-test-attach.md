# verify-module: graph sweep FAULTs "catalog is stale" after any `mxcli test --attach`

**From:** card-disbursement requirements-driven build (build-plan row 4.8)
**Date:** 2026-09-26
**Kind:** bug
**Field evidence:** ran the journey seed with `mxcli test … --attach`, then `bin/verify-module.sh Integration`: `11-graph` FAULT "catalog is stale" and the run read INCOMPLETE. After `REFRESH CATALOG FULL` (6 s), verify-module ran the graph sweep normally. The model units were byte-identical before and after the attach (a sqlite compare of the `Unit` table found 0 of 666 rows different; only `_Transaction` moved).
**Proposed target:** `project-bin/verify-module.sh` (the graph step), `skills/module-review.md`

---

An attach run rewrites the `.mpr`: it creates the MxTest test microflows, then removes them. So the file
ends up newer than `.mxcli/catalog.db` although the model has not changed. The graph step correctly refuses a stale
catalog. But its FAULT line does not say what to do, and the obvious sequence (seed the data with
`test --attach`, then verify) always trips it.

Options, cheapest first:
1. The FAULT line names the remedy: "run `REFRESH CATALOG FULL`, then re-run".
2. verify-module refreshes the catalog itself when the only newer thing is the `.mpr` mtime. Hypothesis:
   a content hash of the `Unit` table would tell "touched" from "changed".
3. The module-review skill orders it: seed → `REFRESH CATALOG FULL` → verify-module.
