# mxcli findings — Decompose/Rehost increment 1 (banking sample round trip, 10.24 fixture)

**From:** MendixMau — toolkit lab runs for the Decompose/Rehost plan (split from #293): increment 1a (Rehost, a public mxcli banking sample app, Mendix 11.13.0) and 1b (Decompose fixture, Mendix 10.24.0)
**Date:** 2026-10-12
**Kind:** bug
**Field evidence:** verbatim captures in the lab trees (not shipped); each item quotes the message seen. mxcli v0.26.0 (2026-10-11), Linux cloud container, no Studio Pro.
**Proposed target:** `bug-logs/mxcli-bugs.md` (items 1–8), `skills/learned-mdl-preflight.md` (items 9–11), toolkit scripts (12–14)

---

## mxcli defects and doc gaps (upstream candidates)

1. **`mxcli describe module <M>` (subcommand) emits only the module and its roles.** Output is `create or modify module Banking; create or modify module role …` and nothing else, for `--mdl 0` and `--format json` too. The whole-module emitter is the MDL statement `describe module <M> with all`, reachable only via `-c` and documented only in `mxcli changelog`.
2. **`describe module … with all` emits flows in catalog order, and `check` refuses its own output:** 14× `MDL-ORDER01 … references microflow Banking.SUB_SeedBillers before it is created (statement 145)`; exec then `Refusing to execute: 14 unresolved reference(s). Nothing was written.` (correct). mxcli knows the call graph and could emit in call order. Workaround: a topological reorder script (Rehost pipeline).
3. **`with all` omits image collections.** `MyFirstModule.Images` is `describable` in `project-tree --json` and `describe imagecollection` emits it; the module emitter leaves it out.
4. **`describe userrole` drops `CheckSecurity: false`.** Replaying the output re-creates the role with the default: a silent security change.
5. **`describe` of a doc comment loses a markdown `* ` bullet** (the one drift row of 155 on the banking round trip).
6. **Set-mode `check` prints "Check passed!" after an earlier failure in the same invocation.**
7. **`mxcli new --version 10.24.0` ships a layout that cannot build.** `App_Default` uses Atlas design properties (`Flex container`, `Align items Y`, …) the bundled Atlas_Core 3.17.0 does not know; mxbuild ends `BUILD FAILED`, yet `new` prints "Project created" and exits 0. Workaround: `ALTER PAGES SET LAYOUT = Atlas_Core.Atlas_Default WHERE LAYOUT = MyFirstModule.App_Default; DROP LAYOUT MyFirstModule.App_Default;`. 11.13.0 is fine.
8. **CE0463 on every mxcli-written DATAGRID on a 10.24 target** ("The definition of this widget has changed…"): mxcli writes Data grid 2 against a newer DataWidgets definition than the scaffold's 2.31.0. `mxcli fix widgets -p <app>.mpr` resolves it (15 units). Rule for 10.x targets: `fix widgets` after any page exec, before mxbuild. `bin/bug-lookup.sh CE0463` returns nothing for this today.

## MDL learnings (preflight candidates)

9. **CRLF inside string literals is load-bearing.** Studio Pro stores annotation text with `\r\n`; `describe` emits it verbatim; a tool that rewrites it as `\n` changes the flow, and `check` says `this change cannot be spliced into the stored flow: the free annotations change … [MDL-V1-REBUILD]`. Byte-preserving I/O only (`newline=''`).
10. **`RETURNS Boolean AS $Closed` does not declare `$Closed`.** `$Closed = true;` → "a reassignment says 'set' under mdl 1"; `SET $Closed = true;` → "variable 'Closed' is not declared". Write `DECLARE $Closed Boolean = false;` first.
11. **`LOG INFO NODE 'Util' $Message;` is not grammar.** Write `LOG INFO NODE 'Util' '{1}' WITH ({1} = $Message);`; wrap a non-String argument (`toString($Count)`).

## Toolkit items (ours)

12. `project-bin/app-facts.sh` hard-requires the `sqlite3` CLI for seven one-column guard queries, while the facts come from Python's `sqlite3` module. The CLI is not installable in the cloud container (`Unable to locate package sqlite3`). Route the guards through `$PY`. (#293 carried a fix.)
13. `project-bin/app-facts.sh` joins `refs` to `objects` by qualified name, so attribute-level refs (`member`, `xpath`) never reach `dependencies.json`.
14. `mxcli marketplace download <id> --output` takes a file path; a directory fails with `rename … file exists`.
