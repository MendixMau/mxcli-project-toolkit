**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-20: Cross-module association traversal as widget
datasource writes null DestinationEntityId` (originally discovered 2026-07-06, retested and
still broken on v0.13.0 and v0.16.0 as of 2026-07-13)
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/854 (2026-08-06)
**Note:** re-verified fresh in an isolated scratch sandbox on 2026-08-06 against the current
tagged `v0.16.0` release binary before filing (Gate 0). This re-verification independently
BSON-decoded the actual stored value (Gate 1) rather than relying on `describe`/read-back or on
the prior write-up's prose — `DestinationEntity` is confirmed empty string (not merely
"not printed"). It also got a live Studio Pro crash, not just the documented BSON/`mx`-crash
evidence. One nuance vs. the original write-up: in this retest `mxcli docker check` did **not**
report a clean "0 errors" — it crashed immediately with the identical exception during its own
project-load step (widget-definition sync forces a full model load on a never-before-checked
project). The original 2026-07-13 conversion-project retest reported a clean "0 errors" from the
build gate before a *separate* Studio Pro crash on open. Both are consistent with the same root
cause (the checker's error-counting logic never runs when the loader itself throws first) — call
this out in the issue rather than silently picking one description over the other.

---

**Title:** Cross-module association datasource writes null `DestinationEntityId`, crashes Studio Pro (and mxbuild's own project loader) on open

**Body:**

## Summary

A `datagrid`/`dataview`/`listview` widget whose `datasource` traverses a **cross-module**
association (`$currentObject/OtherModule.Assoc`, where the association is declared in a
different module than the one being edited) is written with an empty/null `DestinationEntity`
on the underlying `DomainModels$EntityRefStep` BSON. `mxcli exec` reports success. Any
subsequent load of the resulting `.mpr` — by Studio Pro opening the project, or by `mx`/mxbuild's
own project-load step — throws `ArgumentNullException` from
`EntityRefStep.set_DestinationEntityId` and fails hard. **The project becomes unopenable.**

Same-module association traversals are unaffected; the defect is isolated to associations that
cross a module boundary.

## Environment

- mxcli: `v0.16.0` (`2026-07-12T11:44:17Z`) — the current tagged **Latest** release
- Mendix Studio Pro / mxbuild: `11.12.0 Beta` (also reproduced previously on 11.12.1 in a real
  conversion project, 2026-07-13)
- OS: macOS (Darwin 25.5.0), arm64

## Reproduction

```sql
create module "BUG20A";
/
create module "BUG20B";
/
create persistent entity "BUG20A"."EntityA" (
  "Name": string
);
/
create persistent entity "BUG20B"."EntityB" (
  "SomeAttr": string
);
/
create association "BUG20A"."Assoc_AToB"
from "BUG20A"."EntityA" to "BUG20B"."EntityB"
type reference;
/
create page "BUG20A"."Page_EntityA" (
  params: { $Obj: "BUG20A"."EntityA" },
  title: 'EntityA Page',
  layout: Atlas_Core.Atlas_Default
) {
  dataview dv1 (datasource: $Obj) {
    datagrid dgItems (
      datasource: $currentObject/"BUG20A"."Assoc_AToB"
    ) {
      column colAttr (attribute: SomeAttr, caption: 'Some Attr')
    }
  }
}
/
```

```bash
./mxcli check bug20-repro.mdl                    # => Syntax OK (6 statements), Check passed!
./mxcli exec bug20-repro.mdl -p EmptyTest.mpr    # => reports success on every statement:
#   Created module: BUG20A
#   Created module: BUG20B
#   Created entity: BUG20A.EntityA
#   Created entity: BUG20B.EntityB
#   Created association: BUG20A.Assoc_AToB
#   Created page BUG20A.Page_EntityA

./mxcli docker check -p EmptyTest.mpr
#   Using mx: /Applications/Mendix Studio Pro 11.12.0 Beta.app/Contents/modeler/mx
#   Updating widget definitions in EmptyTest.mpr...
#   ERROR: System.AggregateException: One or more errors occurred. (An error occurred when
#   trying to set the 'DestinationEntity' property of a Entity ref step in a Page with ID
#   58d21118-e0ad-49d5-b9bc-1071848a5276.)
#    ---> System.InvalidOperationException: An error occurred when trying to set the
#   'DestinationEntity' property of a Entity ref step in a Page with ID
#   58d21118-e0ad-49d5-b9bc-1071848a5276.
#    ---> System.ArgumentNullException: Value cannot be null. (Parameter 'value')
#      at Mendix.Modeler.DomainModels.Refs.EntityRefStep.set_DestinationEntityId(EntityIdentifier value)
#      ...
#   Error: project check failed: exit status 1
```

Independently decoding the raw BSON of the affected page unit
(`mprcontents/58/d2/58d21118-e0ad-49d5-b9bc-1071848a5276.mxunit`, the exact unit ID named in the
crash) with `bson.decode()` (Python `pymongo`) shows the field directly, rather than relying on
the crash message or a `describe`/read-back command:

```json
{
  "$Type": "DomainModels$EntityRefStep",
  "Association": "BUG20A.Assoc_AToB",
  "DestinationEntity": ""
}
```

`Association` correctly resolves; `DestinationEntity` is an empty string where a fully-qualified
entity identifier (`BUG20B.EntityB`) is expected.

Opening the same `.mpr` in a fresh Studio Pro 11.12.0 Beta instance reproduces the crash visually:
Studio Pro shows an "Error" dialog window and the process then terminates.

## Expected behavior

The datagrid/dataview loads objects across the association from the current context object; the
`.mpr` remains loadable by both `mx check`/mxbuild and Studio Pro.

## Actual behavior

- `mxcli exec` reports success with no warning.
- `mxcli check --references` / `mx check` do not reliably surface a build error for this
  defect — in this retest, `mxcli docker check` (which invokes Studio Pro's own bundled `mx`
  tool) crashed outright with the same exception during its own project-load step, rather than
  returning a clean error count; in the original 2026-07-13 finding on a real conversion project,
  the same construct produced a clean "0 errors" from the build gate, with Studio Pro crashing
  separately on its own subsequent project open. Either way, **no build-time error is ever
  reported for the actual defect** — the tooling either crashes before it can count errors, or
  passes clean and defers the crash to Studio Pro.
- Studio Pro cannot open the resulting project at all: `ArgumentNullException` at
  `EntityRefStep.set_DestinationEntityId`, project load aborts.

## Root cause (inferred)

mxcli's page/widget writer does not resolve the destination entity's module-qualified identifier
when constructing the `DomainModels$EntityRefStep` for a datasource expression that traverses an
association declared in a different module than the widget's own context (`$currentObject/
OtherModule.Assoc`). The `DestinationEntity` field is written as an empty string instead of the
resolved `<Module>.<Entity>` identifier. Same-module traversals resolve correctly, which is
consistent with the writer looking up the destination entity relative to the wrong (or no)
module context specifically for the cross-module case.

## Severity

**Critical**, for Mendix 11.12.x (the version tested here and in the original 2026-07-06/07-13
findings) — the defect makes the entire `.mpr` unopenable in Studio Pro, with no warning at
`mxcli exec` time and no reliable build-time error to catch it before that point.

## Workaround

Write the page via MDL without the cross-module association datasource widget, `exec` and verify
Studio Pro opens cleanly, then add the cross-module datasource widget via `mxcli --mcp`'s
`pg_patch_page` while Studio Pro is open (that write path does not go through the same
buggy writer).
