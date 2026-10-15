# mxcli and runtime findings — increment 4, seam probe (FSM monolith -> NativeNote slice, Mendix 11.13.0), 2026-10-12

**From:** MendixMau — toolkit lab run, Decompose increment 4 (split from #293)
**Date:** 2026-10-12
**Kind:** bug
**Field evidence:** a public Marketplace template (FSM) monolith → NativeNote slice (Mendix 11.13.0) over published REST; captures not committed (lab run, #293). mxcli v0.26.0, Linux cloud container, no Studio Pro.
**Proposed target:** `bug-logs/mxcli-bugs.md`; runtime bullets to `skills/mendix-service-seam.md` or a `learned-*` skill

---

- `mxcli run --local` cannot run a Mendix 9 app. It resolves JDK 21 even with JAVA_HOME set to 17,
  and mxbuild 9.24's Gradle 7.6 fails: `Unsupported class file major version 65`. A 9.x model has no
  JavaVersion setting to steer it. Repro: `JAVA_HOME=<jdk17> mxcli run --local --db-type hsqldb -p <9.24 app>`.
- A microflow cannot be created in a 9.x project:
  `this Mendix 9.24.2 project cannot store Microflows$Microflow.StableId (Mendix 10.2.0+); Microflows$SequenceFlow.CaseValues (Mendix 10.15.0+)`.
  Repro: `mxcli -p <9.24.mpr> -c "create microflow M.X () begin return; end;"`. Blocks any monolith-side
  seam authoring on 9.x.
- `alter microflow` that adds an activity in a 9.x project is refused: `cannot store Microflows$SequenceFlow.CaseValues (Mendix 10.15.0+)`.
- `mxcli check` passes scripts that exec then refuses for a version reason, and exec is not atomic. The
  drop + create that `MDL-V1-REBUILD` recommends ran the `drop` and then failed on the `create`. The flow
  was deleted, and `mx check` reported 2 × CE1613.
- `mxcli check` accepts `change $E (…)` and `$E = empty` when `$E` comes from `retrieve … limit 1`, which
  is a list under `mdl 1`. `mx check` then reports
  `CE1613 "The selected attribute 'List of M.Ent.Attr' no longer exists."` (4 ×).
- After `limit 1` is changed to `first`, `create or modify` reports `spliced: 1 replaced` and describe
  shows `first`, but `mx check` keeps the 4 CE1613. Only drop + create clears them.
- `alter settings runtime ( JavaVersion: '17' )` on a 9.x model prints `Unchanged model settings`. It
  does not say the property does not exist in that version.
- `marketplace update` leaves 27 × CE0463 (widget definitions changed) and does not run or mention
  `mx update-widgets`. It also warns
  `skipping com.mendix.widget.web.PopupMenu.mpk: package.xml: zip: checksum error`.
- Runtime: the Mendix 9.24.2 runtime boots headless on Linux.
  - It needs Java 11; 17 is refused with `Incompatible java version: 17.0.20.1 … Java 11 is required.`
  - The launcher needs `MX_INSTALL_PATH`, or it fails with `Error finding mx install path.`
  - Every constant must be passed in `update_configuration`, or it fails on `MendixSSO.TokenEncryptionKey`.
  - Start takes 10 s on an empty HSQLDB (2378 DDL commands).
  - mxbuild 9.24 builds with `--java-home=<jdk17>`.
- Runtime: a REST call from 10.24 to 11.13 works with nothing tied to a Mendix version.
  `create published rest service` with primitive microflow parameters, called by
  `call rest service post … returns String`, needed no mappings.
- Converted 10.24 copy: getting it to boot needed one-time fixes nobody had measured:
  - 2 marketplace updates;
  - `mx update-widgets`;
  - 1 XPath (CE0161 on a widget mxcli cannot author);
  - JavaVersion 21;
  - custom index.html removed;
  - 3 Java edits: `final` generated parameters in DeepClone, and `rollbackTransAction` → `rollbackTransaction`.
