# mxcli v0.26.0 defects on native-mobile documents — FSM template round trip

**From:** MendixMau — toolkit lab run, native-module bug hunt (split from #293)
**Date:** 2026-10-12
**Kind:** bug
**Field evidence:** a public Marketplace template (FSM, Mendix 9.24.2), its 12 own `Native*` modules (1142 documents, all described). Method: `describe module <M> with all` plus the `project-tree` fill-in → `mxcli check -p <source app>` with a quarantine loop (every error below is mxcli rejecting mxcli's own output) → `exec` into a source copy with the 12 modules dropped. Minimal repros D1–D3: `pipelines/mendix-mpr/samples/fsm-template-9.24.2/native-bughunt/`. Counts are error lines across all quarantine rounds.
**Proposed target:** `bug-logs/mxcli-bugs.md`; upstream drafts in `bug-logs/pending-github-issues/2026-10-12-mxcli-0.26-round-trip-report.md` (U-ids)

---

## Defects

- **D3 (confirmed), blocks round trip.** No microflow or nanoflow can be written to a 9.24.2 project: `this Mendix 9.24.2 project cannot store Microflows$Microflow.StableId (Mendix 10.2.0+); Microflows$SequenceFlow.CaseValues (Mendix 10.15.0+)`. An empty `create or modify microflow Repro.MF_Min () begin return; end;` fails on a fresh 9.24.2 app (`D3-…mdl`). 100% of flows tried.
- **D1 (new), blocks.** `describe entity` prints `index ( desc);` (no column); check: `index on unknown attribute 'desc'`. 23 errors in 10 modules; everything naming the entity cascades (NativeReason: 3 of 45 statements clean in check, 37 rejected). Repro `D1-…mdl`.
- **D2 (new), blocks.** Native Repeater: `` `content` is not a container of `repeater` — it declares: template [MDL-WIDGET26] ``. 32 errors, 7 modules. Repro `D2-…mdl` (needs the Repeater `.mpk` + `mxcli widget init`). Same family as SafeAreaView (D11).
- **D4 (new), blocks or drifts.** `nanoflow data source … has no argument for parameter 'NativeInstanceItem' — Mendix rejects this with CE1571` (also nanoflow actions). describe prints the call without the parameter mapping. 70 errors, 7 modules. Not isolated (blocked by D3).
- **D5 (new).** `Attribute 'Search' is bound but there is no enclosing data container providing entity context` (also date pickers). describe loses or never emits the data view; unverified which. 11.
- **D6 (new).** `ContentParams parameter {1} is written as "$currentObject/NotResolvedReason"`. 2.
- **D7 (new).** `selection DataSource references 'grid1' but no widget with that name exists on this page` — describe names a widget it did not emit. 1.
- **D8 (new).** `enum split has 28 branches; at most 16 branches are supported` — a create limit describe does not respect. 1.
- **D9 (new).** Lint `MDL-REST04: authentication microflow … has parameter $Token, which Mendix does not supply … (CE0336)` on valid source. 1.
- **D10–D14 (confirmed).** JS action type parameter `Name<Entity>(…)` → `mismatched input '<'`; SafeAreaView `content` slot; `with all` omits nanoflows, snippets and JS actions and truncates at 10 000 lines; exec refuses forward and cross-module references and a grant before its association, and is not atomic; image collection not found (seen only against an empty scratch app, not re-tested).

Cosmetic, not counted: the `commit` default-events notice and `Wrap dataview … in layoutgrid` hints.

## Per module (summary)

1201 `create` statements across the 12 modules: 441 clean in check, 702 rejected (root cause or cascade of D1, D2, D4–D9). Executed into the 9.24.2 target: only modules, roles and 3 NativeRestAPI constants. Exec blockers: D3 (every flow) and D13 (cross-module references, grant before association). Largest: NativeMobile 461 statements, 308 rejected; NativeMobilePart 156/99; NativeMobileForm 104/62. Missing dependencies: 0.

Not tested, because D3 and D13 stop exec first: target `describe` versus source `describe`. Re-run once D3 is fixed, or against an 11.x target (the native modules then need the Blank Native Mobile starter), to expose the next layer.
