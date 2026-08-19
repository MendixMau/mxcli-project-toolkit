**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-11: ALTER PAGE cannot change a DataView's datasource
type` (originally discovered 2026-05-22 on Mendix 11.10.0, mxcli pre-v0.13.0; never previously
retested)
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/855 (2026-08-06)
**Note:** re-verified fresh in an isolated scratch sandbox on 2026-08-06 against the current
tagged `v0.16.0` release binary (Gate 0), copied off `/private/tmp/ivm-baseline`, never touching
a real project. The retest **substantially narrows** the original claim (Gate 5/7):
- The original "Additional finding" — CE6705 (`"Data view cannot have a data source of type
  association"`) blocking creation of *any* DataView with an association-traversal datasource —
  did **not** reproduce. Both previously-failing forms (`dataview (DataSource:
  $Param/Module.Assoc)` outside a parent DataView, and `$currentObject/Module.Assoc` nested
  inside one) now create successfully and build with 0 related errors via `mxcli docker check`
  (Mendix 11.12.0 Beta `mx`). This half appears fixed. No fix-commit attribution is claimed here
  (issue #198, which touched DATAGRID/LISTVIEW/GALLERY association datasources, is a candidate
  but its own scope statement doesn't mention DATAVIEW — not verified by reading its diff, so not
  credited).
- The remaining half — `ALTER PAGE ... SET` cannot reassign an existing DataView's datasource
  *type* — **does** still reproduce, cleanly, with an explicit rejection message rather than
  silent corruption. But a full MDL-only workaround now exists (`ALTER PAGE ... REPLACE`), which
  the original write-up didn't test and claimed didn't exist ("no MDL syntax... Studio Pro manual
  step" as the only path). Severity is downgraded from the original **Medium** to **Low**
  accordingly — filing only this narrower, corrected version.
- `bug-logs/mxcli-bugs.md`'s `## BUG-11` entry gets a dated correction banner (Gate 7) pointing
  here; the original text is left intact below it.

---

**Title:** `ALTER PAGE ... SET` rejects reassigning a DataView's datasource type (`unsupported DataSource type for alter page set: parameter`) — `REPLACE` succeeds where `SET` does not

**Body:**

## Summary

`alter page ... { set datasource = <new-datasource> on <dataview-widget> }` unconditionally
rejects any attempt to change an existing DataView's datasource to a different structural type
(e.g. from a `microflow` datasource to a page-parameter/context-bound one), with:

```
Error: failed to set: unsupported DataSource type for alter page set: parameter
```

The identical structural change succeeds cleanly via `alter page ... { replace <widget> with {
dataview <widget> (datasource: <new-datasource>) { ... } } }` — i.e. `REPLACE` already has a code
path that can build a DataView with any datasource type `CREATE PAGE` supports, but `SET` does
not share it.

## Environment

- mxcli: `v0.16.0` (`2026-07-12T11:44:17Z`) — current tagged **Latest** release
- Mendix Studio Pro / mxbuild: `11.12.0 Beta`
- OS: macOS (Darwin 25.5.0), arm64

## Steps to reproduce

Setup (module, entity, microflow, and a page whose DataView uses a `microflow` datasource):

```sql
create module "Bug11Test";

create persistent entity "Bug11Test"."Parent" (
  "Name": string(100)
);

create microflow "Bug11Test"."ACT_GetParent" ()
returns "Bug11Test"."Parent" as $Result
begin
  $Result = create "Bug11Test"."Parent" ("Name" = 'Test');
  return $Result;
end;

create page "Bug11Test"."TestPageAlterType"
(
  params: { $ParentParam: "Bug11Test"."Parent" },
  title: 'Bug 11 Alter Type Change',
  layout: Atlas_Core.Atlas_Default
)
{
  dataview dv2 (datasource: microflow Bug11Test.ACT_GetParent) {
    textbox txtName (label: 'Name', attribute: "Name")
  }
};
```

`./mxcli exec setup.mdl -p EmptyTest.mpr` — succeeds, creates everything as expected.

Now attempt to change `dv2`'s datasource from the microflow to the page parameter (a
`Context`-type datasource) via `SET`:

```sql
alter page "Bug11Test"."TestPageAlterType" {
  set datasource = $ParentParam on dv2
};
```

```
$ ./mxcli exec alter-set.mdl -p EmptyTest.mpr
Connected to: EmptyTest.mpr (Mendix 11.12.0)
Error: failed to set: unsupported DataSource type for alter page set: parameter
```

`./mxcli check alter-set.mdl` reports `Syntax OK` beforehand — the rejection only happens at
`exec` time, and the page is left completely unchanged (confirmed via `describe page`: `dv2`
still shows the original `microflow` datasource).

Workaround — the same structural change via `REPLACE` instead of `SET` succeeds:

```sql
alter page "Bug11Test"."TestPageAlterType" {
  replace dv2 with {
    dataview dv2 (datasource: $ParentParam) {
      textbox txtNameNew (label: 'Name', attribute: "Name")
    }
  }
};
```

```
$ ./mxcli exec alter-replace.mdl -p EmptyTest.mpr
Connected to: EmptyTest.mpr (Mendix 11.12.0)
Altered page Bug11Test.TestPageAlterType
```

`describe page` afterwards confirms `dv2` now has `DataSource: $ParentParam` (a `Context`
datasource), and `mxcli docker check -p EmptyTest.mpr` builds it with 0 errors attributable to
this page/widget.

Note: reusing the exact same child widget name (`txtName`) inside the `REPLACE` block — even
though the parent `dv2` itself is the thing being replaced — fails with `duplicate widget name
'txtName': widget names must be unique within a page`. Renaming the child widget (`txtNameNew`
above) avoids this; it may be a separate, narrower quirk in the same `REPLACE` code path, not
filed separately here since it doesn't block the workaround.

## Expected vs. actual

**Expected:** Either `SET` performs the same structural rebuild that `REPLACE` already does when
the new datasource has a different type than the current one, or the `SET` error explicitly says
to use `REPLACE` instead.

**Actual:** `SET` aborts with `unsupported DataSource type for alter page set: parameter` and no
pointer to the working alternative. A user hits this as one more undocumented trial-and-error
wall (in the same spirit as #157's broader "ALTER PAGE limitations... excessive trial-and-error"
report, though this specific symptom isn't covered there).

## Root cause

The `set` operation's DataSource handling only mutates within a fixed structural shape (e.g.
swapping which microflow/entity a `microflow`/`database` datasource points at) and explicitly
rejects a `parameter`-typed replacement value — see the literal error string `unsupported
DataSource type for alter page set: parameter`. `replace`, by contrast, discards and rebuilds the
targeted widget via the same construction path `create page` uses, which already supports every
datasource type (`microflow`, `nanoflow`, `database`, `$Variable`/context, association-path).
`set`'s DataSource branch was never extended to fall through to that same construction path when
the target type differs from the widget's current one.

## Severity

**Low.** A complete, Studio-Pro-free MDL workaround exists (`ALTER PAGE ... REPLACE`, restating
the widget and its nested content, with distinct child widget names). This is a confusing/dead-end
error message and an inconsistency between two ALTER PAGE operations that should be capable of the
same thing, not a functionality blocker.

## Related

- #157 (open) — general "ALTER PAGE limitations and syntax inconsistencies cause excessive
  trial-and-error" — this is one more instance of that pattern; not a duplicate, since #157 does
  not mention datasource-type reassignment.
