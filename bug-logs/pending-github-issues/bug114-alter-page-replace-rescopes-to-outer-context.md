**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-114` (discovered 2026-09-01, re-confirmed independently 2026-09-02, dashboard-publishing migration project, Mendix 11.12.1, mxcli v0.20.0) and `## BUG-118` (discovered 2026-08-25, a language-learning app conversion, Mendix 11.13.0, mxcli `39c7d94`) — root cause located in the mxcli source at the 2026-09-07 merge review (`mdl/backend/pagemutator/mutator.go`, HEAD `191a0c9`). One issue for both: same walker, two symptoms.
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1076 (2026-09-09). `bug118-replace-in-gallery-template-drops-binding.md` is folded in below as reproduction 2; do not file it separately.
**Suggested labels:** bug, mdl, pages, alter-page, silent-corruption

---

**Title:** `ALTER PAGE … REPLACE` / `INSERT BEFORE|AFTER` resolve the new widget's attribute bindings against the wrong data context when the target sits under a selection-driven data view or a flow-sourced pluggable list — `mxcli check` and `exec` clean, model breaks at `mx check` (CE1613 / CE0402)

**Body:**

## Summary

`ALTER PAGE … REPLACE <widget> WITH { … }` (and the sibling `INSERT BEFORE` / `INSERT AFTER`) resolve
the new widgets' attribute references through `Mutator.EnclosingEntity(target)`. That walk
(`findEnclosingEntityContext` → `findEntityContextInWidgets` → `widgetOwnEntity`) takes an entity
from a container only when its `DataSource` document carries an `EntityRef`. Two common page
shapes contribute no `EntityRef`, so the walk **skips the target's real scope** and keeps
whatever it last saw:

| Target sits inside | Stored as | Walk yields | Symptom at `mx check` |
|---|---|---|---|
| a **selection-driven data view** (`DataSource: SELECTION <list>`), nested in a page-level data view over another entity | `Forms$ListenTargetSource` — no `EntityRef` | the **outer** page-level entity | `CE1613 "The selected attribute 'Module.Outer.Attr' no longer exists."` — the binding is re-scoped to an entity that does not have the attribute |
| a **gallery / DataGrid 2 template** whose list is sourced by a microflow, nanoflow, or an association without a direct `EntityRef`, on a page with no outer data view | pluggable `datasource` property, no `EntityRef.Entity` | **empty** | `CE0402 "No value specified."` — `DESCRIBE PAGE` shows `ContentParams: [{1} = <unbound>]` |

In both cases `mxcli check --references` passes, `mxcli exec` reports success, and in the
re-scope case `DESCRIBE PAGE` even prints the intended attribute back correctly, so nothing on the
mxcli side shows the damage. It surfaces at `mxbuild` / Studio Pro load, after the write has
landed — on the first project that meant the running app was down until the snapshot was
restored.

Widgets authored in the same position by `CREATE PAGE` are bound correctly, and a `REPLACE` whose
target is a direct child of the page body is bound correctly too. The defect is specific to the
enclosing-scope walk used by the ALTER PAGE mutations.

## Environment

- mxcli v0.20.0 (reproduction 1, both occurrences) and `39c7d94` / 2026-08-25 (reproduction 2); the walker is unchanged at HEAD `191a0c9` (2026-09-07) and the release notes through 0.19.0 carry nothing for it
- Mendix 11.12.1 (reproduction 1), 11.13.0 (reproduction 2)
- macOS and Linux (container)

## Reproduction 1 — selection-driven data view: binding re-scoped to the OUTER entity (CE1613)

Page shape: a page-level data view over `Dashboard`, containing a list over its versions and a
selection-driven data view over `DashboardVersion`, which holds a `dynamictext` bound to an
attribute of `DashboardVersion`.

```sql
create module "BUG114";
/
create persistent entity "BUG114"."Dashboard" ( "Name": string );
/
create persistent entity "BUG114"."DashboardVersion" ( "PeriodLabel": string );
/
create association "BUG114"."DashboardVersion_Dashboard" from "BUG114"."DashboardVersion" to "BUG114"."Dashboard";
/
create page "BUG114"."Dashboard_View" (
  title: 'Dashboard', layout: Atlas_Core.Atlas_Default,
  params: { $Dashboard: "BUG114"."Dashboard" }
) {
  dataview dvDashboard (datasource: $Dashboard) {
    listview lvVersions (datasource: association "BUG114"."DashboardVersion_Dashboard") {
      dynamictext txtRow (content: '{1}', ContentParams: [{1} = PeriodLabel])
    }
    dataview dvSelected (datasource: selection lvVersions) {
      dynamictext txtPreviewPeriod (content: 'Period: {1}', ContentParams: [{1} = PeriodLabel])
    }
  }
}
/
```

```bash
./mxcli exec bug114-setup.mdl -p Test.mpr
~/.mxcli/mxbuild/*/modeler/mx check Test.mpr        # 0 errors — CREATE PAGE bound txtPreviewPeriod correctly
```

Now replace the inner widget with the same binding:

```sql
alter page "BUG114"."Dashboard_View" {
  replace txtPreviewPeriod with {
    dynamictext txtPreviewPeriod (content: 'Preview · {1}', ContentParams: [{1} = PeriodLabel])
  }
};
```

```bash
./mxcli check bug114-replace.mdl -p Test.mpr --references   # Check passed!
./mxcli exec bug114-replace.mdl -p Test.mpr                 # Altered page — no error
./mxcli -p Test.mpr -c "DESCRIBE PAGE BUG114.Dashboard_View"
#   -> dynamictext txtPreviewPeriod (Content: 'Preview · {1}', ContentParams: [{1} = PeriodLabel])   ← looks right
~/.mxcli/mxbuild/*/modeler/mx check Test.mpr
#   [error] [CE1613] The selected attribute 'BUG114.Dashboard.PeriodLabel' no longer exists.
```

The stored reference is `Dashboard.PeriodLabel` — the page's outer entity — not
`DashboardVersion.PeriodLabel`. Seen twice on the source project on two different pages
(`txtPreviewPeriod` inside a selection data view; `txtVersionMeta` inside a gallery template with
`ContentParams: [{1} = SizeLabel, {2} = UploadedAt]`, both re-resolved to the outer `Dashboard`).

## Reproduction 2 — gallery template, no outer data view: binding dropped (CE0402)

```sql
create module "BUG118";
/
create persistent entity "BUG118"."Item" ( "Name": string );
/
create page "BUG118"."Page_Gallery" ( title: 'Gallery', layout: Atlas_Core.Atlas_Default ) {
  gallery galItems (datasource: database "BUG118"."Item") {
    template t1 {
      container ctnCard {
        dynamictext txtName (content: '{1}', ContentParams: [{1} = Name])
      }
    }
  }
}
/
```

```sql
alter page "BUG118"."Page_Gallery" {
  replace txtName with {
    container ctnWrap {
      dynamictext txtName2 (content: '{1}', ContentParams: [{1} = Name])
    }
  }
};
```

```bash
./mxcli check bug118-replace.mdl -p Test.mpr --references   # Check passed!
./mxcli exec bug118-replace.mdl -p Test.mpr                 # Altered page — no error
./mxcli -p Test.mpr -c "DESCRIBE PAGE BUG118.Page_Gallery"
#   -> dynamictext txtName2 (Content: '{1}', ContentParams: [{1} = <unbound>])
~/.mxcli/mxbuild/*/modeler/mx check Test.mpr
#   [error] [CE0402] "No value specified." at Text 'txtName2'
```

Same result with the explicitly qualified form `ContentParams: [{1} = $currentObject/Name]`, which
rules out attribute rooting as the cause. The original template widget (`txtName`, written by
`CREATE PAGE`) was bound correctly; only the REPLACE-introduced widget loses it. Reproduced on the
2026-08-25 build; note that on v0.20.0 a database-sourced gallery may already resolve (see
"Where it is in the code" — `entityFromEntityRef` was extended for association sources), so run
this reproduction with the gallery sourced by a microflow returning `List of BUG118.Item` if the
database form has since been fixed. The selection-driven data view of reproduction 1 fails on
v0.20.0 regardless.

## Where it is in the code (`mdl/backend/pagemutator/mutator.go`, HEAD `191a0c9`)

- `Mutator.EnclosingEntity` → `findEnclosingEntityContext` → `findEntityContextInWidgets`: the
  recursive walk carries `currentEntity` down and replaces it only when `widgetOwnEntity(wDoc)`
  returns non-empty.
- `widgetOwnEntity` = `extractEntityFromDataSource` (reads `DataSource.EntityRef` only) or
  `extractPluggableDataSourceEntity` (reads the pluggable `datasource` property's
  `DataSource.EntityRef` only).
- A selection-driven data view stores `DataSource` as `Forms$ListenTargetSource` with a
  `ListenTarget` widget reference and **no `EntityRef`**, so `widgetOwnEntity` returns `""` and the
  walk keeps the outer entity → reproduction 1.
- A flow-sourced list stores `MicroflowSettings` / `NanoflowSettings`, also without `EntityRef`.
  `EnclosingDataSourceFlow` (FINDINGS #55) covers the flow case only for the *nearest* data source,
  and only where the caller consults it; the gallery-template path in reproduction 2 still came
  back empty → `<unbound>`.
- `CREATE PAGE` does not go through this walk, which is why the same widget in the same position
  is bound correctly at page creation.

## Expected behavior

The replacement / inserted widget's attribute references resolve against the target's nearest
enclosing data context, exactly as `CREATE PAGE` resolves them in the same position and as
`DESCRIBE PAGE` prints them back. Concretely:

1. `widgetOwnEntity` (or the walk around it) resolves a `Forms$ListenTargetSource` by following
   `ListenTarget` to the referenced list widget and taking **that** widget's entity.
2. Flow-sourced containers resolve through the flow's return type at every level of the walk, not
   only for the nearest source.
3. When the walk cannot determine the context, `mxcli check --references` / `exec` should fail
   loudly instead of writing an `<unbound>` or outer-scoped reference — a page mutation that
   cannot bind its attribute has no correct output to write.

## Actual behavior

Reproduction 1: binding silently re-scoped to the page's outer entity; every mxcli-side read
(including `DESCRIBE PAGE`) shows the intended attribute, and the model fails to build.
Reproduction 2: binding silently dropped (`<unbound>`), visible in `DESCRIBE PAGE`, model fails
`mx check`.

## Severity

**High.** Silent through `check --references` and `exec`; in the re-scope case invisible to
`DESCRIBE PAGE` as well. On the first project the failed build overwrote the previous
deployment, so the running app was down until the `.mpr` snapshot was restored.

## Workaround

- Do not `REPLACE` / `INSERT` a widget carrying an attribute binding when the target sits under a
  selection-driven data view or a pluggable list template. If the same attribute stays bound and
  only the text changes, `SET Content = '…' ON <widget>` leaves the existing binding untouched and
  is unaffected (the first project's actual fix).
- A genuine rebind has no narrower ALTER PAGE form today — `SET ContentParams = […]` and the
  per-index spellings are hard parse errors — so it needs `CREATE OR REPLACE PAGE` or Studio Pro.
- Gate every ALTER PAGE on the real `mx check`, not on `mxcli check --references` alone.
