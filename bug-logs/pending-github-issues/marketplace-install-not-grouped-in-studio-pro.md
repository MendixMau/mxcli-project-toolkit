**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-marketplace-install-not-grouped-in-studio-pro` — found 2026-09-28 (field report on v0.24.0; cause read from source on upstream `main` 95091765)
**Status:** NOT YET FILED — fix patch ready in `bug-logs/submitted-prs/mxcli/2026-09-28-marketplace-install-fromappstore/`; file this first, then open the PR with "closes #<n>"
**Suggested labels:** bug, marketplace
**Duplicate check:** searched 2026-09-28 (`marketplace install FromAppStore`, `Marketplace modules App Explorer`, `AppStoreVersionGuid`). No match. #879 (closed, v0.21.0) was the format collapse; the stamp that this issue is about was added by its fix and has always written three fields.

---

**Title:** `marketplace install` / `update` stamp 3 of 5 marketplace identity fields, so Studio Pro lists the module among the app's own modules instead of under "Marketplace modules"

**Body:**

## Summary

A module Studio Pro installs from the Marketplace carries five fields on its `Projects$ModuleImpl`: `FromAppStore`, `AppStoreVersion`, `AppStoreGuid`, `AppStoreVersionGuid`, `AppStorePackageIdString`. `StampMarketplaceVersion` (`cmd/mxcli/marketplace/update.go`) writes only the first three, so a module installed by `mxcli marketplace install <content-id>` or updated by `marketplace update` has an empty `AppStoreVersionGuid` and `AppStorePackageIdString`. Studio Pro reads all five: the module is shown in the App Explorer among the app's own modules instead of under "Marketplace modules", and it is treated as the app's own code from then on. `marketplace install --file <package.mpk>` writes none of the five (`FromAppStore` stays `false`), so the same happens there, and `SHOW MODULES` (which reads `FromAppStore` only) shows `Marketplace v<x>` in the first case and nothing in the second — neither says what Studio Pro will do.

**Version:** mxcli v0.24.0 (`StampMarketplaceVersion` on `main` 95091765 is the same), Mendix 11.13.0, MPR v2.

## Repro

```
mxcli new App --mendix-version 11.13.0
mxcli marketplace install 1011 -p App/app/App.mpr          # Encryption
mxcli -p App/app/App.mpr -c "SHOW MODULES"                 # Source: Marketplace v11.x.y
```

Open `App.mpr` in Studio Pro 11.13.0 → App Explorer: Encryption is listed among the app's modules, not under "Marketplace modules".

The module's unit shows why (`mprcontents/<xx>/<yy>/<unit>.mxunit`, decoded BSON of the `Projects$ModuleImpl`):

```
FromAppStore             true
AppStoreVersion          "11.x.y"
AppStoreGuid             "<version uuid>"
AppStoreVersionGuid      ""            <- empty
AppStorePackageIdString  ""            <- empty
```

The same module installed by Studio Pro in another project:

```
FromAppStore             true
AppStoreVersion          "11.1.1"
AppStoreGuid             "<version uuid>"
AppStoreVersionGuid      "<the same version uuid>"
AppStorePackageIdString  "1011"
```

With `marketplace install --file Encryption.mpk` all five stay at their defaults (`FromAppStore` false, four empty strings).

## Measured

- Fresh 11.13.0 project, `--file` install of a marketplace package: module unit has `FromAppStore=false` and all four strings empty (read with a BSON decoder over the `.mxunit`).
- A Studio Pro-installed module in a real project: all five set, `AppStoreGuid == AppStoreVersionGuid`, `AppStorePackageIdString` is the content id as decimal text.
- Reading `cmd/mxcli/marketplace/update.go` on `main`: the stamp is three `set*Field` calls; the content id is not threaded into `PerformInstall` / `PerformUpdate` at all.

## Expected

After `marketplace install <content-id>` or `marketplace update`, the module carries the same five fields a Studio Pro install writes, and Studio Pro lists it under "Marketplace modules".

## Proposed fix (PR follows)

Thread the resolved content id into `PerformInstall` / `PerformUpdate` and have the stamp write the version UUID into both `AppStoreGuid` and `AppStoreVersionGuid` and the content id into `AppStorePackageIdString`, still only assigning keys the document already has (ADR-0005). One helper, unit-tested. `--file` stays unstamped in that PR (a package on disk has no identity).

## Follow-up ask (separate)

Let `marketplace install --file` take `--content-id <n>` and `--version <x.y.z>` and resolve the version UUID through the marketplace client, so an offline install can carry the same identity. Until then the workaround is to install by content id.

## Workaround

Install by content id, never `--file`, for a module that must read as a Marketplace module. Check `SHOW MODULES` Source reads `Marketplace v<version>`. The Studio Pro grouping cannot be fixed from mxcli ≤ v0.24.0; a one-off BSON patch that copies `AppStoreGuid` into `AppStoreVersionGuid` and writes the content id into `AppStorePackageIdString` is what the fix does.
