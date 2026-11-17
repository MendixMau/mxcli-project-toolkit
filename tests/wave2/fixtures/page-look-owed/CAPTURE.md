# page-look-owed — provenance

Golden input for `tests/wave2/test-page-look-owed.sh` (`CLAUDE.md` → "Shipping an instrument",
rule 1). Nothing here is hand-written MDL.

**The field case (2026-11-17).** A requirements-driven project, handed a ready spec and clickable
prototypes, started at the build stage: six apps under `apps/<App>/` (one `.mpr` each, about 78
pages per app), no `architecture/build-plan.md`, no `architecture/modules/<Module>/` briefs, no
wireframes, no `.claude/loop/verify/` runs, 0 files in `design/ui-reviews/`. It reached its last
level with 0 pages ever looked at. `field-gate-check-5.before.txt` is the three verdict lines
`bin/gate-check.sh <project> 5` printed there, verbatim.

**The tree the fixture builds** reproduces that layout — `apps/<App>/<App>.mpr`, scripts under
`apps/<App>/mdlsource/`, a supplied `prototypes/<app>/<screen>.html`, a `PROJECT.md` with no brief,
no plan and no review — from MDL that was captured or executed against a real model:

| fixture path | source (verbatim copy, read at test time) | pages |
|---|---|---|
| `apps/Procure/mdlsource/10-request-edit.mdl` | `../affected-tests/field-describe-Purchasing.Request_Edit.out` (mxcli v0.26.0 DESCRIBE, five-app lab project) | Purchasing.Request_Edit |
| `apps/Procure/mdlsource/11-request-list.mdl` | `../affected-tests/field-describe-Purchasing.Request_List.out` (same) | Purchasing.Request_List |
| `apps/Shop/mdlsource/10-shop.mdl` | `../affected-tests/shop.mdl` (exec'd against Studio Pro 11.12.0) | Shop.Order_Edit, Shop.Order_Overview |
| `apps/Catalog/mdlsource/20-product.mdl` | `../page-fidelity-popup/product-newedit-describe-v023.mdl` (mxcli v0.23.0 DESCRIBE) | Sales.Product_NewEdit |
| `apps/Gallery/mdlsource/90-gallery-home.mdl` | `examples/stylegallery/mdlsource/gallery/90-gallery-home.mdl` (its header comments mention `create or replace`, which must not count) | StyleGallery.Gallery_Home |
| `prototypes/procure/request-list.html` | `../page-fidelity-mocks/grouped-overview.html` (real wireframe structure, text changed) | the visual target of Request_List |

So the asserted denominator is **6 pages in 4 modules**, counted by hand from the sources above.

**Not reproduced here:** the field project's own scripts and prototypes (a client's; the toolkit
never carries them). The fixture copies them by layout, not by content. The re-run of the fixed
gate-check on the field project is cited in the commit that ships this fixture, or marked owed there.
