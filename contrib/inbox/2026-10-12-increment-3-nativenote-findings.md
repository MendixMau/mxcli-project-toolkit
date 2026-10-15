# mxcli findings — increment 3, NativeNote slice (FSM 9.24.2 -> Mendix 11.13.0), 2026-10-12

**From:** MendixMau — toolkit lab run, Decompose increment 3 (split from #293)
**Date:** 2026-10-12
**Kind:** bug
**Field evidence:** a public Marketplace template (FSM 9.24.2), NativeNote slice moved into Mendix 11.13.0; captures not committed (lab run, #293). mxcli v0.26.0, Linux cloud container, no Studio Pro.
**Proposed target:** `bug-logs/mxcli-bugs.md`; last bullet to the Rehost pipeline's topo-order script

---

- `describe javascript action` with a type parameter emits `Name<Entity>(Entity: "Entity" not null, …)`,
  which `check` refuses (`mismatched input '<' expecting {FOLDER, '('}`). An *object of type parameter*
  parameter is not expressible: `Entity: Entity` resolves to entity `.Entity`; `Entity: entity <Entity>`
  is an entity-type parameter and the caller then fails mx check CE0115.
- `describe layout` of a native layout with SafeAreaView emits `content { … }`; exec: `content needs a
  name`. After `mxcli widget init` the slot is `template content { … }`, and exec refuses the layout:
  `declares no placeholder at all` — placeholders inside a pluggable widget's child slot are not seen.
- exec's reference pre-check does not see an image collection created earlier in the same script
  (`unknown image collection "FSM_Specific.Material_Design_Icons"`), refusing the whole script.
- exec is not atomic after the pre-check: a widget-build error left 18 earlier statements written.
- Re-running `create or modify javascript action` overwrites a hand-restored `.js`; the generated file
  lacks the source's EXTRA CODE import, which describe emits only as a `-- EXTRA CODE:` comment.
- mxcli cannot create a native navigation profile (`create or replace navigation NativePhone` → "a web
  profile's home is a page or a microflow"); a native slice needs the Blank Native Mobile App starter
  (Marketplace 109511) via `mx create-project` instead of `mxcli new`.
- Commands without `-p` silently pick a stray `.mpr` in the working directory (`Using project: …`).
- `describe module … with all` omits all nanoflows (35 in NativeNote) — as in increment 2.
- Observed, untested: `describe entity` emitted `index ( desc);` (empty column) for
  `NativeTechnician.NativeTechnician`.
- Not mxcli: `mx create-project` 11.13 with a relative `--output-dir` → `System.UriFormatException`.
- Toolkit: `pipelines/mendix-mpr/lib/topo-order-mdl.py` cannot order an entity whose after-commit
  microflow takes the entity, nor an entity grant naming an association created later — candidates
  for the extractor once its current run is finished.
