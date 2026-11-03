# mxpatch: three lookups that find nothing on a domain model or a flow's own documentation

**From:** a field project (anonymised) — a Mendix 10.24 app changed with mxcli v0.27.0 and this toolkit
**Date:** 2026-10-21
**Kind:** learning
**Field evidence:** hit while writing a byte patch that rewords documentation (a change MDL can't
express without rewriting the element). Each lookup below was re-run on the toolkit's own fixture
model (`tests/wave2/fixtures/mxpatch/`, rebuilt from `TestApp.mpr.sql` with `executescript`,
Mendix 11.14.0) with `project-bin/mxpatch.py` on master 393d253, so nothing here depends on the
field app.
**Proposed target:** the LIBRARY section of the `project-bin/mxpatch.py` docstring (a short
"lookups that miss" list), or `skills/learned-mdl-preflight.md` next to the line that says some
changes are "not MDL at all"

---

A patch author reaches for `find_unit` and `find_element` and gets `NotFound` three times. None of
the three is a bug; each is how the model is stored.

## 1. An entity's `$Type` is `DomainModels$EntityImpl`

The natural call, with the type spelled `DomainModels$Entity`, fails:

```
find_element(dm.doc, "Car", "DomainModels$Entity")
  -> NotFound: no element named Car (DomainModels$Entity) in this unit
find_element(dm.doc, "Car", "DomainModels$EntityImpl")     # works
```

On the fixture model, `find_elements(dm.doc, type_="DomainModels$EntityImpl")` returns the three
entities (`Car`, `VCar`, `ApprovalContext`), and nothing else is stored under `DomainModels$Entity`.
Leave the type off (`find_element(dm.doc, "Car")`) if the name is unique in the unit.

## 2. A domain-model unit has no `Name`

The unit's `Name` key is empty (`None`), so the unit is identified by its module, not by a name:

```
m.find_unit("DomainModels$DomainModel", "MyFirstModule")
  -> NotFound: no unit DomainModels$DomainModel MyFirstModule in <model.mpr>
mxpatch.py find <model.mpr> --type 'DomainModels$DomainModel'
  -> DomainModels$DomainModel	MyFirstModule.None	mprcontents/84/77/<uuid>.mxunit
```

The `.None` in the `find` output is the missing name. The CLI's `get` and `set` require `--name`
(`mxpatch: --type and --name are required`), so they can't select a domain model at all. Use the
library and pick the unit by module:

```
dms = [u for u in m.units("DomainModels$DomainModel") if m.module_of(u) == "MyFirstModule"]
car = mxpatch.find_element(dms[0].doc, "Car", "DomainModels$EntityImpl")
mxpatch.set_value(car, "Documentation", "A car.")
m.write_unit(dms[0], apply=False)        # dry run: prints the new byte count and ContentsHash
```

That sequence ran as written on the fixture model: `changed`, then a dry run for the one unit.

## 3. A flow's own documentation is on the unit root, and `find_element` skips the root

`find_elements` and `find_element` search "below the unit root" (`if d is doc: continue`,
`project-bin/mxpatch.py:181`). A microflow's `Documentation` is a key on the unit root,
so looking up the microflow by its own name finds nothing:

```
find_element(u.doc, "MyFirstLogic")           -> NotFound: no element named MyFirstLogic in this unit
get(u.doc, "Documentation")                   -> ''      # the key is on the root
```

Set it on the root. The CLI does this when `--element` is left out:

```
mxpatch.py set <model.mpr> --type 'Microflows$Microflow' --name MyFirstLogic --key Documentation --value 'Does X.'
  -> Documentation: '' -> 'Does X.'   (dry run; add --apply to write)
```

## Not checked

- Only a dry run was done; the patches were not applied and opened in Studio Pro.
- Only the microflow case was run for gotcha 3. Other unit types that keep their own documentation
  on the root (workflows, pages) were not tried.
