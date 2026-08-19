# RnD (mendixlabs/mxcli) main retest — 2026-08-06

Investigation only. No GitHub issues filed. No real Mendix project touched — all
testing done in scratch sandboxes copied from `/private/tmp/ivm-baseline/`.

## Gate 0 — commit tested

- Repo: `~/Mendix/mxcli` (remote `https://github.com/mendixlabs/mxcli.git`)
- Before this session: `504aec67`
- `git fetch --all` found `origin/main` at `4fda072f` (78 commits ahead)
- One local uncommitted change blocked `pull --ff-only`: a 1-line diff in
  `cmd/mxcli/lsp_completions_gen.go` (a generated file, byproduct of a prior
  `make build` run in this same clone). Discarded with `git checkout --
  cmd/mxcli/lsp_completions_gen.go`, then `git pull --ff-only` fast-forwarded
  cleanly.
- **Commit tested: `4fda072f`** (`git rev-parse --short HEAD` after pull)

## Build / version stamping

- Build command: `make build` (target reads `Makefile`; `VERSION ?= $(shell git
  describe --tags --always --dirty ...)`, baked in via
  `-ldflags "-X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME)"`,
  further stripped by `RELEASE_LDFLAGS` with `-s -w`).
- Build succeeded: `Built bin/mxcli ( 82M) bin/source_tree`.
- `git describe --tags --always --dirty` resolved to `nightly-36-g4fda072f`
  (repo has real semver tags up to `v0.9.0`; 36 commits past the nearest tag,
  short hash `g4fda072f`).
- **Verified with `--version`:**
  ```
  $ ~/Mendix/mxcli/bin/mxcli --version
  mxcli version nightly-36-g4fda072f (2026-08-06T06:50:50Z)
  ```
  Version stamping works correctly and cites the exact commit (`4fda072f`).
  No deviation needed here.

## Sandbox setup

Three fresh copies of the clean baseline project, each with the freshly built
binary copied in:
- `/tmp/rnd-retest-security/` (+ `mxcli`, project file `EmptyTest.mpr`)
- `/tmp/rnd-retest-mapping/` (+ `mxcli`, project file `EmptyTest.mpr`)
- `/tmp/rnd-retest-widget/` (+ `mxcli`, project file `EmptyTest.mpr`)

Note: `EmptyTest.mpr` (copied from `/private/tmp/ivm-baseline/`) already
contains some ambient, pre-existing `mx check` errors unrelated to any of
these repros (a `CE0066` on module `RouteShowcase` and two `CE5015` "Root"
MinOccurs/MaxOccurs errors) — these show up in every `mx check` run below
regardless of which test script was executed, and are baseline noise, not a
finding of this retest.

---

## Test 1 — security/GRANT — PASS (no crash, grant persists)

**Sandbox:** `/tmp/rnd-retest-security/`

RnD's microflow syntax requires `begin ... end` with a mandatory (even if
empty) parameter-list `()` — confirmed via `./mxcli syntax microflow.create`.
Also confirmed `GRANT EXECUTE ON MICROFLOW ... TO <role>` requires the role to
already exist (`./mxcli syntax security.module-role`,
`./mxcli syntax security.microflow-access`), so the repro creates a module
role first.

**Script (`repro-security.mdl`):**
```
create module "ZSecTest";
/
create module role "ZSecTest"."User";
/
create persistent entity "ZSecTest"."TestEntity" (
  "Name": String(100)
);
/
create microflow "ZSecTest"."SM_TestMicroflow" ()
begin
end;
/
grant execute on microflow "ZSecTest"."SM_TestMicroflow" to "ZSecTest"."User";
```

**Command 1 — syntax + reference check:**
```
$ ./mxcli check repro-security.mdl -p EmptyTest.mpr --references
Checking syntax: repro-security.mdl
✓ Syntax OK (5 statements)

Validating references against: EmptyTest.mpr
(Note: References to objects created within the script are skipped)
Connected to: EmptyTest.mpr (Mendix 11.12.0)
✓ All references valid

Check passed!
```

**Command 2 — exec:**
```
$ ./mxcli exec repro-security.mdl -p EmptyTest.mpr
Connected to: EmptyTest.mpr (Mendix 11.12.0)
Created module: ZSecTest
Created module role: ZSecTest.User
Created entity: ZSecTest.TestEntity
Created microflow: ZSecTest.SM_TestMicroflow
Granted execute access on ZSecTest.SM_TestMicroflow to ZSecTest.User
EXIT: 0
```
No crash, no error.

**Command 3 — separate process, fresh `show access` (to rule out "read own
write" masking):**
```
$ ./mxcli -p EmptyTest.mpr -c "SHOW ACCESS ON MICROFLOW \"ZSecTest\".\"SM_TestMicroflow\";"
Allowed module roles for ZSecTest.SM_TestMicroflow:
  ZSecTest.User
EXIT: 0
```

**Result: PASS.** No crash on `grant`, and the grant is visible in a brand-new
`mxcli` invocation (separate process from the one that wrote it), so it is a
real persisted write, not read-own-write. This exact minimal repro shows no
sign of the security/GRANT pain point on `4fda072f`.

---

## Test 2 — import mapping array JsonPath — FAIL (bug still present)

**Sandbox:** `/tmp/rnd-retest-mapping/`

**Script (`repro-mapping.mdl`, exactly as specified):**
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
✓ Syntax OK (4 statements)

Check passed!
```

**Command 2 — exec:**
```
$ ./mxcli exec repro-mapping.mdl -p EmptyTest.mpr
Connected to: EmptyTest.mpr (Mendix 11.12.0)
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
[error] [CE5015] "The mapping does not align with the underlying schema anymore. ... Attribute 'MinOccurs' does not match schema element '(Object)'." at Object mapping element 'Root'
[error] [CE5015] "The mapping does not align with the underlying schema anymore. ... Attribute 'MaxOccurs' does not match schema element '(Object)'." at Object mapping element 'Root'
The app contains: 4 errors.
Error: project check failed: exit status 1
```
`CE5015` on `IMM_R13`/`routing_code` still fires, with the error text itself
citing path `(Object)/routing_code` (missing the `items` array segment).

**BSON verification (source of truth, not CLI read-back):**

Located the `.mxunit` file for `IMM_R13` under `mprcontents/`:
```
$ find mprcontents -iname "*.mxunit" | xargs grep -l "IMM_R13"
mprcontents/f3/6f/f36f160b-8d41-4ac4-8467-dc63122a6e7b.mxunit

$ strings mprcontents/f3/6f/f36f160b-8d41-4ac4-8467-dc63122a6e7b.mxunit | grep -n -A2 -B2 "JsonPath|routing_code|IMM_R13|RoutingCode"
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

The stored `JsonPath` for `RoutingCode` is literally `(Object)|routing_code` —
it does **not** contain an `items` array segment
(i.e. not `(Object)|items|(Object)|routing_code`), even though the source
JSON structure wraps the mapped fields inside an `items` array. This is the
broken/flat form.

**Result: FAIL — bug still present on `4fda072f`.** `CE5015` still fires and
the BSON-stored `JsonPath` still drops the `items` array segment, consistent
with the pre-2026-08-05 finding (`bug-logs/bakeoff-2026-07-31/BUG-LOCAL-13.md`).
Not fixed by any of the 78 commits pulled in this session.

---

## Test 3 — pluggable widget update nag (#716) — PASS (0 CE0463 in both modes)

**Sandbox:** `/tmp/rnd-retest-widget/`

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
✓ Syntax OK (3 statements)

Check passed!
```

**Command 2 — exec:**
```
$ ./mxcli exec repro-widget.mdl -p EmptyTest.mpr
Connected to: EmptyTest.mpr (Mendix 11.12.0)
Created module: ZWID716
Created entity: ZWID716.Customer
2026/08/06 14:53:16 info: updated widget definitions for EmptyTest.mpr
Created page ZWID716.CustomerList
EXIT: 0
```
Note: `exec` itself already logs "updated widget definitions" — this build's
executor appears to run a widget-definition sync step automatically as part
of `exec`, ahead of any explicit `check`/`docker check` step.

**Deviation from plan:** the plan looked for a `--update-widgets` flag on
`docker check`. This build does not have that flag; instead
`./mxcli docker check --help` shows the *opposite* default has changed:
```
By default, 'mx update-widgets' runs before 'mx check' to normalize
pluggable widget definitions and prevent false CE0463 errors. Use
--no-update-widgets to skip this step.
...
      --no-update-widgets     Skip 'mx update-widgets' before check
```
So on `4fda072f`, `mx update-widgets` runs automatically by default, and the
flag to test the "raw"/unfixed path is `--no-update-widgets` (inverse of what
was expected). Ran both:

**Command 3 — default (update-widgets enabled):**
```
$ ./mxcli docker check -p EmptyTest.mpr
Using mx: /Applications/Mendix Studio Pro 11.12.0 Beta.app/Contents/modeler/mx
Updating widget definitions in EmptyTest.mpr...
Widget definitions updated.
Checking project EmptyTest.mpr...
...
[error] [CE0066] "Entity access is out of date. ..." at Domain model of module 'RouteShowcase'   <- ambient baseline noise, unrelated
[error] [CE5015] ... Attribute 'MinOccurs' ... 'Root'                                             <- ambient baseline noise, unrelated
[error] [CE5015] ... Attribute 'MaxOccurs' ... 'Root'                                              <- ambient baseline noise, unrelated
The app contains: 3 errors.
Error: project check failed: exit status 1

$ ./mxcli docker check -p EmptyTest.mpr 2>&1 | grep -c "CE0463"
0
```

**Command 4 — `--no-update-widgets`:**
```
$ ./mxcli docker check -p EmptyTest.mpr --no-update-widgets
Checking app for errors...
[error] [CE0066] ... 'RouteShowcase'   <- ambient baseline noise, unrelated
[error] [CE5015] ... 'Root' (MinOccurs)   <- ambient baseline noise, unrelated
[error] [CE5015] ... 'Root' (MaxOccurs)   <- ambient baseline noise, unrelated
The app contains: 3 errors.
Error: project check failed: exit status 1

$ ./mxcli docker check -p EmptyTest.mpr --no-update-widgets 2>&1 | grep -c "CE0463"
0
```

**Result: PASS — 0 `CE0463` errors in both the default (update-widgets
enabled) and `--no-update-widgets` modes.** All 3 remaining errors in both
runs are the pre-existing ambient `RouteShowcase`/`Root`-mapping errors
present in the baseline project before this test's script ran (identical set
in both modes, and identical to the unrelated ambient errors seen in Test 2's
sandbox), not `CE0463` and not attributable to the `ZWID716.CustomerList`
page created by this repro.

---

## Summary

| Test | Result | Key evidence |
|---|---|---|
| 1. Security/GRANT | PASS | No crash on exec; `SHOW ACCESS` in a fresh process confirms the grant persisted |
| 2. Import mapping array JsonPath | FAIL (bug persists) | `CE5015` still fires; BSON-stored `JsonPath` for `RoutingCode` is `(Object)|routing_code`, missing the `items` array segment |
| 3. Widget update nag (#716) | PASS | 0 `CE0463` errors with default (`update-widgets` auto-runs) and with `--no-update-widgets` |

Commit tested: `4fda072f` (mendixlabs/mxcli, pulled 2026-08-06, was `504aec67`
before this session). Binary: `mxcli version nightly-36-g4fda072f
(2026-08-06T06:50:50Z)`.
