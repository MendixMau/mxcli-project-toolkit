**Repo:** `mendixlabs/mxcli`
**Source:** field build on mxcli **v0.20.0** (2026-08-28T13:22:53Z build), Mendix 11.12.1, Linux container
**Status:** DRAFT — not yet filed (`add_repo` refused `mendixlabs/mxcli` in the filing session — see "Why not filed" below)
**Severity:** High — a class of pluggable-widget page (Gallery) authored entirely through mxcli
passes every mxcli-side check yet permanently fails headless `mxbuild`, and no mxcli command
(`check`, `widget sync`, full page regeneration, or single-widget regeneration with a fresh
element ID) can repair it.

---

# mxcli-authored Gallery widget fails mxbuild CE0463 even after full regeneration

## Summary

A `gallery` widget (`com.mendix.widget.web.gallery.Gallery`, installed package version 3.4.0)
authored via `CREATE PAGE` (and reproduced again via `ALTER PAGE ... REPLACE` with a brand-new
widget instance) is accepted by every mxcli-side validator but is rejected by headless
`mxbuild` at deploy/run time with:

```
CE0463: "The definition of this widget has changed. Update this widget by right-clicking it
and selecting 'Update widget', or select 'Update all widgets' to update all widgets in the app."
```

This is the **only** error in an otherwise clean build (everything else is Warning/Deprecation).
It reproduces identically across a fresh element ID, so it is not stale/corrupted instance
data — it is something structural in how mxcli serializes a Gallery widget's stored
configuration that headless `mxbuild`'s strict validator rejects but Studio Pro's own headless
modeler (`mx check`) silently tolerates (and apparently auto-normalizes in-memory, since it
reports 0 errors on the same file).

## Environment

- mxcli `v0.20.0` (2026-08-28T13:22:53Z)
- Mendix 11.12.1, mxbuild `~/.mxcli/mxbuild/11.12.1`
- Gallery pluggable widget package version 3.4.0 (`com.mendix.widget.web.gallery.Gallery`)
- Linux container, split-model `.mpr` (`mprcontents/*.mxunit`)

## Reproduce

```bash
./mxcli docker check -p <project>.mpr        # reports 0 errors — "looks fine" baseline
timeout 60 ./mxcli run --local -p <project>.mpr --ensure-db 2>&1   # runs mxbuild --serve; CE0463 fires here
```

MDL that authors the widget (module `DashboardPublishing`, page `Dashboard_Overview`):

```sql
gallery galDashboards (
  datasource: microflow DashboardPublishing.GET_Dashboard_ListForOwner,
  DesktopColumns: 3,
  TabletColumns: 2,
  PhoneColumns: 1,
  pagination: 'loadMore',
  pageSize: 12
) {
  template tplDashboardCard {
    container ctnCard (class: 'card dashboard-card') {
      dynamictext txtCardTitle (content: '{1}', contentparams: [{1} = Title], class: 'dashboard-card-title')
      dynamictext txtCardDesc (content: '{1}', contentparams: [{1} = Description], class: 'dashboard-card-desc', visible: [trim(Description) != ''])
      container ctnCardMeta (class: 'dashboard-card-meta') {
        container ctnCountBadge (visible: [VersionCount > 0]) {
          dynamictext txtCardCount (content: '{1} versions', contentparams: [{1} = VersionCount], class: 'badge')
        }
        container ctnNoneBadge (visible: [VersionCount = 0]) {
          dynamictext txtCardNone (content: 'No versions', class: 'badge')
        }
        container ctnLatest (visible: [VersionCount > 0]) {
          dynamictext txtCardLatest (content: 'latest {1}', contentparams: [{1} = LatestVersionLabel])
        }
      }
      container ctnCardOpen (class: 'row-end') {
        actionbutton btnOpen (caption: 'Open', class: 'btn btn-secondary btn-sm', action: microflow DashboardPublishing.ACT_Dashboard_Open)
      }
    }
  }
}
```

## Evidence that this is not stale-instance corruption

1. `mxcli check <script>.mdl -p <project>.mpr --references` passes clean.
2. `mx check` (Studio Pro's own headless modeler, `~/.mxcli/mxbuild/11.12.1/modeler/mx check`)
   reports **0 errors** on the exact same `.mpr` — it appears to tolerate/auto-normalize the
   mismatch in-memory rather than surface it.
3. `mxcli widget sync -p <project>.mpr` reports either "nothing to do" or fixes unrelated
   widgets elsewhere in the project (Image widgets) — it never touches this Gallery instance.
4. Regenerating the **entire containing page** from scratch (re-running the full page's
   `CREATE OR REPLACE PAGE` script) does **not** fix it — identical CE0463 persists.
5. Regenerating **only this one widget instance** via
   `ALTER PAGE ... REPLACE galDashboards WITH { gallery galDashboards (...) { ... } }` — a
   brand-new instance with a fresh internal element ID — **still** produces the identical
   CE0463 error, on the new element ID.

(4) and (5) rule out stale/orphaned data: a fresh element, freshly written, in a freshly
regenerated page, still fails the same way. The defect is in what mxcli writes for a Gallery
widget's stored definition, not in leftover state.

## Exact error (headless `mxbuild`, via `mxcli run --local --ensure-db`)

```json
{
  "name": null,
  "severity": "Error",
  "message": "The definition of this widget has changed. Update this widget by right-clicking it and selecting 'Update widget', or select 'Update all widgets' to update all widgets in the app.",
  "locations": [
    {
      "elementId": "db5c7c96-0b95-4937-95dc-cb83eaefec84",
      "unitId": "ce6c5469-d790-441b-aadf-21e1a6c7cb00",
      "element": "Gallery 'galDashboards'",
      "document": "Page 'Dashboard_Overview'",
      "module": "DashboardPublishing"
    }
  ],
  "errorCode": "CE0463"
}
```

## Suspected root cause

CE0463 in Mendix normally means a pluggable widget's persisted config is missing a
property/version stamp the widget's current `.xml` definition expects (the same class of
error Studio Pro's own GUI fixes with "Update widget"). mxcli's page-authoring code likely
omits or mis-stamps a field in the serialized Gallery widget configuration (property version,
or a property the 3.4.0 definition added) that headless `mxbuild`'s stricter widget-definition
check enforces but Studio Pro's `mx check` does not.

## Suggested fix, in preference order

1. Compare the BSON a `gallery` block produces against a Gallery instance placed via Studio
   Pro's GUI (same widget version) and align the missing/mismatched property or version stamp.
2. Extend `mxcli widget sync` to actually detect and repair this case — currently it reports
   "nothing to do" against the very widget that's broken, which is misleading: the tool that is
   supposed to fix "widget definition changed" errors does not recognize this one.
3. Failing (1)/(2) short-term, `mxcli check`/`widget sync` should at minimum warn that Gallery
   (and possibly other pluggable widgets with template/child-slot bodies) is a known-risky
   `CREATE PAGE` target that should be verified with a real `mxbuild` run, not just `mx check`,
   before being trusted.

## Why not filed

The filing session's tool for adding a GitHub repo (`add_repo`) refused: this session already
had `mxcli-project-toolkit` (owner `mendixmau`) attached, and cross-owner repo attachment is not
supported in one session (error: `cross-tier adds are not supported in v1: requested
"mendixlabs/mxcli" but session already has repos from owner(s) [mendixmau]`). A session started
fresh with `mendixlabs/mxcli` as its initial source should be able to attach and file this
directly.
