# Wengao fork (engalar/mxcli) 5-Aug build retest — 2026-08-06

Investigation only. No GitHub issues filed. No real Mendix project touched — all
testing done in scratch sandboxes copied from `/private/tmp/ivm-baseline/`.

This mirrors the identical 3-test repro run against `mendixlabs/mxcli` main in
`rnd-main-retest-2026-08-06.md`, same day, against a different binary, for a
direct comparison.

## Gate 0 — binary tested

- Location: `/tmp/wengao-mxcli-5aug-test/mxcli`, extracted earlier this session
  from `~/Downloads/mxcli-engalar-5Aug.zip` (still present, re-extraction not
  needed).
- **Verified with `--version`:**
  ```
  $ /tmp/wengao-mxcli-5aug-test/mxcli --version
  mxcli version bc3d94ef4-dirty (2026-08-05T04:41:15Z) commit bc3d94ef46be725503363e38239aaa0bd0306ee8
  ```
  Matches the exact identity string expected going in. `-dirty` suffix means
  this build has uncommitted local changes on top of `bc3d94ef4` — Wengao's
  own local build, not a tagged release.
- Fork: `engalar/mxcli` (third-party fork of `mendixlabs/mxcli`), not the RnD
  main branch. Uses `{ }` brace syntax for microflow/page bodies instead of
  RnD's `begin ... end`.

## Sandbox setup

Three fresh copies of the clean baseline project, each with this binary copied in:
- `/tmp/wengao-retest-security/` (+ `mxcli`, project file `EmptyTest.mpr`)
- `/tmp/wengao-retest-mapping/` (+ `mxcli`, project file `EmptyTest.mpr`)
- `/tmp/wengao-retest-widget/` (+ `mxcli`, project file `EmptyTest.mpr`)

Same baseline noise as the RnD retest applies here too: `EmptyTest.mpr`
already contains a pre-existing `CE0066` on module `RouteShowcase` and two
`CE5015` "Root" MinOccurs/MaxOccurs errors, present in every `mx check` run
below regardless of which repro ran — baseline noise, not a finding.

---

## Test 1 — security/GRANT — PASS (no crash, grant persists)

**Sandbox:** `/tmp/wengao-retest-security/`

Reused the existing repro at
`/tmp/wengao-5aug-test/security-repro/bug-engalar-01.mdl` (brace-syntax
microflow body, no explicit `create module role` statement — this build
apparently tolerates/auto-resolves the bare `ZSEC01.User` role reference in
the `grant` statement without a prior `CREATE MODULE ROLE`).

**Script (`repro-security.mdl`):**
```
create module ZSEC01;
/
create persistent entity ZSEC01.Widget (
  Name: string(50)
);
/
create microflow ZSEC01.ACT_DoSomething ()
returns boolean as $Result
{
  declare $Result boolean = false;
  set $Result = true;
  return $Result;
}
/
grant execute on microflow ZSEC01.ACT_DoSomething to ZSEC01.User;
/
show access on microflow ZSEC01.ACT_DoSomething;
```

**Command 1 — syntax + reference check:**
```
$ ./mxcli check repro-security.mdl -p EmptyTest.mpr --references
Checking syntax: repro-security.mdl

Validating references against: /tmp/wengao-retest-security/EmptyTest.mpr
Connected to: /tmp/wengao-retest-security/EmptyTest.mpr (Mendix 11.12.0)
  ✓ Check passed! (5 statements)
```

**Command 2 — exec:**
```
$ ./mxcli exec repro-security.mdl -p EmptyTest.mpr
Connected to: /tmp/wengao-retest-security/EmptyTest.mpr (Mendix 11.12.0)
Created module: ZSEC01
Created entity: ZSEC01.Widget
  ⚠  ZSEC01.Widget has no access rules — run SHOW PROJECT SECURITY and GRANT to configure entity-level access
Created microflow: ZSEC01.ACT_DoSomething
Granted execute access on ZSEC01.ACT_DoSomething to ZSEC01.User
Allowed module roles for ZSEC01.ACT_DoSomething:
  ZSEC01.User
EXIT: 0
```
No crash, no error.

**Command 3 — separate process, fresh `show access` (rule out read-own-write):**
```
$ ./mxcli -p EmptyTest.mpr -c "show access on microflow ZSEC01.ACT_DoSomething;"
Connected to: /tmp/wengao-retest-security/EmptyTest.mpr (Mendix 11.12.0)
Allowed module roles for ZSEC01.ACT_DoSomething:
  ZSEC01.User
```

**Result: PASS.** No crash on `grant`, and the grant is visible in a
brand-new `mxcli` invocation (separate process from the one that wrote it),
so it is a real persisted write, not read-own-write. Consistent with the
earlier-this-session finding that this build fixes BUG-ENGALAR-01.

---

## Test 2 — import mapping array JsonPath — FAIL (bug still present)

**Sandbox:** `/tmp/wengao-retest-mapping/`

**Script (`repro-mapping.mdl`, exactly as specified, no brace-syntax
microflows needed):**
```
create module ZZB;
/
create non-persistent entity ZZB."RouteListItem" (
  "RoutingCode": String(100),
  "RoutingName": String(200)
);
/
create json structure ZZB."JSON_R13List"
  snippet $${
  "items": [{"routing_code": "R-1", "routing_name": "Widget Route"}]
}$$;
/
create import mapping ZZB."IMM_R13"
  with json structure ZZB."JSON_R13List"
{
  create ZZB.RouteListItem {
    RoutingCode = routing_code,
    RoutingName = routing_name
  }
};
```

**Command 1 — check:**
```
$ ./mxcli check repro-mapping.mdl -p EmptyTest.mpr
Checking syntax: repro-mapping.mdl
  ✓ Check passed! (4 statements)
```

**Command 2 — exec:**
```
$ ./mxcli exec repro-mapping.mdl -p EmptyTest.mpr
Connected to: /tmp/wengao-retest-mapping/EmptyTest.mpr (Mendix 11.12.0)
Created module: ZZB
Created entity: ZZB.RouteListItem
Created json structure: ZZB.JSON_R13List
Created import mapping ZZB.IMM_R13
EXIT: 0
```

**Command 3 — `mx check` via `mxcli docker check`:**
```
$ ./mxcli docker check -p EmptyTest.mpr
...
[error] [CE0066] "Entity access is out of date. ..." at Domain model of module 'RouteShowcase'   <- ambient baseline noise, unrelated
[error] [CE5015] "The mapping does not align with the underlying schema anymore. Please right-click on this error and select 'Resolve by updating from schema' to update the mapping. Details: Could not find element with path '(Object)/routing_code'." at Value mapping element 'routing_code'
[error] [CE5015] ... Attribute 'MinOccurs' ... 'Root'   <- ambient baseline noise, unrelated
[error] [CE5015] ... Attribute 'MaxOccurs' ... 'Root'   <- ambient baseline noise, unrelated
The app contains: 4 errors.
project check failed: exit status 1
```
`CE5015` on `IMM_R13`/`routing_code` fires, citing path `(Object)/routing_code`
(missing the `items` array segment) — same as RnD.

**BSON verification (source of truth, not CLI read-back):**
```
$ find mprcontents -iname "*.mxunit" | xargs grep -l "IMM_R13"
mprcontents/53/be/53be2256-9875-4bee-ac39-ddb8ec0d6cdc.mxunit

$ strings mprcontents/53/be/53be2256-9875-4bee-ac39-ddb8ec0d6cdc.mxunit | grep -n -A2 -B2 "JsonPath|routing_code|IMM_R13|RoutingCode"
2-ImportMappings$ImportMapping
3-Name
4:IMM_R13
...
18-ExposedName
19-Root
20:JsonPath
21-(Object)
22-XmlPath
...
31-ImportMappings$ValueMappingElement
32-Attribute
33:ZZB.RouteListItem.RoutingCode
34-ExposedName
35:routing_code
36:JsonPath
37:(Object)|routing_code
38-XmlPath
...
64-ExposedName
65-routing_name
66:JsonPath
67-(Object)|routing_name
68-XmlPath
```

The stored `JsonPath` for `RoutingCode` is literally `(Object)|routing_code`
— it does **not** contain an `items` array segment (i.e. not
`(Object)|items|(Object)|routing_code`), even though the source JSON
structure wraps the mapped fields inside an `items` array. This is the
broken/flat form — byte-for-byte the same defect signature as the RnD-main
retest and the earlier `BUG-LOCAL-13` finding
(`~/Mendix/WMS-Demo-main/bug-logs/bakeoff-2026-07-31/BUG-LOCAL-13.md`).

**Result: FAIL — bug still present on `bc3d94ef4-dirty`.** `CE5015` still
fires and the BSON-stored `JsonPath` still drops the `items` array segment.
Not fixed by this build.

---

## Test 3 — pluggable widget update nag (#716) — PASS (0 real CE0463 in both modes)

**Sandbox:** `/tmp/wengao-retest-widget/`

**Script (`repro-widget.mdl`, exactly as specified):**
```
create module ZWID716;
/
create entity ZWID716.Customer ( Name: String );
/
create or replace page ZWID716.CustomerList
( Title: 'Customers', Layout: Atlas_Core.Atlas_Default )
{
  datagrid dgCustomers (datasource: database ZWID716.Customer) {
    column colName (attribute: Name, caption: 'Name')
  }
}
```

**Command 1 — check:**
```
$ ./mxcli check repro-widget.mdl -p EmptyTest.mpr
Checking syntax: repro-widget.mdl
  ✓ Check passed! (4 statements)
```

**Command 2 — exec:**
```
$ ./mxcli exec repro-widget.mdl -p EmptyTest.mpr
Connected to: /tmp/wengao-retest-widget/EmptyTest.mpr (Mendix 11.12.0)
Created module: ZWID716
Created entity: ZWID716.Customer
  ⚠  ZWID716.Customer has no access rules — run SHOW PROJECT SECURITY and GRANT to configure entity-level access
Created page ZWID716.CustomerList
EXIT: 0
```
Unlike the RnD build, `exec` here does **not** log "updated widget
definitions" — this build's default behavior for MPR v2 projects (see
below) is to skip that step automatically.

**Deviation from plan, `--help` checked first:** this build's flag semantics
differ from both the plan's assumption and from RnD's build. `./mxcli docker
check --help` shows format-aware defaults:
```
For MPR v1 projects, 'mx update-widgets' runs before 'mx check' by default
to normalize pluggable widget definitions and prevent false CE0463 errors.

For MPR v2 projects (mprcontents/ folder format, Mendix 10.18+), widget
update is skipped by default to preserve the v2 format. Use --update-widgets
to force the update (note: this may convert the project to v1 format).
...
      --no-update-widgets     Skip 'mx update-widgets' before check (v1 MPR)
      --update-widgets        Force 'mx update-widgets' even for MPR v2 (may convert to v1 format)
```
`EmptyTest.mpr` is a v2 project (`mprcontents/` layout), so the default here
is *skip*, and the flag to force the alternate path is `--update-widgets`
(and it warns the conversion to v1 is irreversible without git restore — a
disposable scratch sandbox, so ran it anyway).

**Command 3 — default (v2, widget update skipped):**
```
$ ./mxcli docker check -p EmptyTest.mpr
Warning: MPR v2 format detected (mprcontents/ layout).
         Widget definition update is SKIPPED by default to prevent Mendix mx from
         silently converting your project from v2 (mxunit files) to v1 (monolithic MPR).
         ...
[error] [CE0066] "Entity access is out of date. ..." at Domain model of module 'RouteShowcase'   <- ambient baseline noise, unrelated
[error] [CE5015] ... 'Root' (MinOccurs)   <- ambient baseline noise, unrelated
[error] [CE5015] ... 'Root' (MaxOccurs)   <- ambient baseline noise, unrelated
The app contains: 3 errors.
project check failed: exit status 1

$ ./mxcli docker check -p EmptyTest.mpr 2>&1 | grep -n "CE0463"
6:         Pluggable widget CE0463 errors (if any) may be false positives.
```
The only `CE0463` string match is inside the tool's own informational
warning text, not an actual `[error] [CE0463]` line. Confirmed with a
stricter grep:
```
$ ./mxcli docker check -p EmptyTest.mpr 2>&1 | grep -c "\[error\] \[CE0463\]"
0
```

**Command 4 — `--update-widgets` (forces v2→v1 conversion):**
```
$ ./mxcli docker check -p EmptyTest.mpr --update-widgets
Warning: --update-widgets specified on a v2 MPR.
         Mendix mx will convert mprcontents/ (v2) to monolithic MPR (v1).
         This is IRREVERSIBLE without git restore. Proceeding...
Updating widget definitions in /tmp/wengao-retest-widget/EmptyTest.mpr...
Widget definitions updated.
[error] [CE0066] ... 'RouteShowcase'   <- ambient baseline noise, unrelated
[error] [CE5015] ... 'Root' (MinOccurs)   <- ambient baseline noise, unrelated
[error] [CE5015] ... 'Root' (MaxOccurs)   <- ambient baseline noise, unrelated
The app contains: 3 errors.
project check failed: exit status 1
```
0 `[error] [CE0463]` lines here too.

**Result: PASS — 0 real `CE0463` errors in both the default (v2 skip) mode
and the `--update-widgets` (forced, v1-converting) mode.** All 3 remaining
errors in both runs are the pre-existing ambient `RouteShowcase`/`Root`-mapping
errors present in the baseline project, not `CE0463` and not attributable to
the `ZWID716.CustomerList` page created by this repro.

---

## Summary

| Test | Result | Key evidence |
|---|---|---|
| 1. Security/GRANT | PASS | No crash on exec; `show access` in a fresh process confirms the grant persisted |
| 2. Import mapping array JsonPath | FAIL (bug persists) | `CE5015` still fires; BSON-stored `JsonPath` for `RoutingCode` is `(Object)|routing_code`, missing the `items` array segment |
| 3. Widget update nag (#716) | PASS | 0 real `[error] [CE0463]` lines in default (v2 skip) mode and `--update-widgets` mode |

Binary tested: `mxcli version bc3d94ef4-dirty (2026-08-05T04:41:15Z) commit
bc3d94ef46be725503363e38239aaa0bd0306ee8` (`engalar/mxcli` fork, local build
from `~/Downloads/mxcli-engalar-5Aug.zip`).

## Comparison to RnD main (`4fda072f`, `rnd-main-retest-2026-08-06.md`)

| Test | RnD main (`4fda072f`) | Wengao fork (`bc3d94ef4-dirty`) | Comparison |
|---|---|---|---|
| 1. Security/GRANT | PASS | PASS | Both fixed |
| 2. Import mapping array JsonPath | FAIL | FAIL | Both still broken |
| 3. Widget update nag (#716) | PASS | PASS | Both fixed, different mechanism (see below) |

All three results match between the two binaries. The one notable
implementation difference: RnD's build runs `mx update-widgets`
automatically by default (any MPR format) and offers `--no-update-widgets`
to opt out; Wengao's build treats v1 and v2 MPR differently — it *skips*
widget update by default specifically for v2 projects (to avoid an
irreversible v1 conversion) and requires an explicit `--update-widgets` to
force it. Net effect on the `CE0463` nag itself is identical (0 real
`CE0463` errors either way), but Wengao's build is more conservative about
not silently mutating a v2 project's file format as a side effect of
running `check`.
