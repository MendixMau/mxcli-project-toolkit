Status: READY TO SEND, NOT SENT (go test ./... 84 packages ok, 0 FAIL; gofmt/vet clean; on 95091765) · issue NOT YET FILED — draft in `bug-logs/pending-github-issues/marketplace-install-not-grouped-in-studio-pro.md`; file it, then open the PR with "closes #<n>" · base upstream main 95091765 · field proof: partial (see below)

# mxcli PR: `marketplace install` / `update` stamp all five marketplace identity fields

Per `skills/upstream-feedback.md` §3a. Not yet sent. The patch is
`0001-marketplace-stamp-all-five-identity-fields-so-Studio.patch` (5 files, +109/-24 incl. a new test file):
`cmd/mxcli/marketplace/update.go` (the `stampModuleDoc` helper and the content id threaded into
`StampMarketplaceVersion` / `PerformInstall` / `PerformUpdate`), the two cobra commands that now pass the
resolved content id down, the existing security test's call sites, and `update_stamp_test.go` (3 tests).

## How to send it

```bash
git clone https://github.com/<your-fork>/mxcli && cd mxcli
git fetch https://github.com/mendixlabs/mxcli main && git checkout -b fix/marketplace-install-fromappstore FETCH_HEAD
git am /path/to/0001-marketplace-stamp-all-five-identity-fields-so-Studio.patch
make test && make lint          # re-run on the day; main moves
git push -u origin fix/marketplace-install-fromappstore
```

File the issue from the draft first, then open the PR with the body below and `closes #<n>`.

## What is proven, what is not

- **Cause:** read from source on `main` 95091765. `StampMarketplaceVersion` wrote `FromAppStore`,
  `AppStoreVersion`, `AppStoreGuid` and nothing else; the content id never reached it.
- **Reference values:** a Studio Pro-installed module (Encryption 11.1.1) in a real project has all five
  fields set, `AppStoreGuid == AppStoreVersionGuid`, `AppStorePackageIdString == "1011"`. A `--file`
  install on a fresh 11.13.0 probe has `FromAppStore` false and four empty strings. Both read by
  decoding the module's `.mxunit` BSON.
- **Unit tests:** `TestStampModuleDoc_*` — all five set when the keys exist; empty content id leaves
  `AppStorePackageIdString` alone; absent keys are not invented (ADR-0005). `go test` on
  `cmd/mxcli/marketplace` and `cmd/mxcli` passes; full suite result is on the status line.
- **NOT proven:** a content-id install with the patched binary followed by a Studio Pro open showing the
  module under "Marketplace modules". The content-id path needs a Mendix PAT and Studio Pro needs a Mac
  or Windows machine, neither of which the drafting session had. **Before sending:** build the branch,
  `mxcli marketplace install 1011 -p <scratch>.mpr`, decode the module unit (or `SHOW MODULES` plus a
  BSON dump) and confirm the five fields, then open it in Studio Pro and confirm the grouping. Put the
  Mendix version and the result into the PR body's "Field" paragraph.

## PR body (to send)

**Closes #<n>.**

A module Studio Pro installs from the Marketplace carries five fields on its `Projects$ModuleImpl`:
`FromAppStore`, `AppStoreVersion`, `AppStoreGuid`, `AppStoreVersionGuid` and `AppStorePackageIdString`.
`marketplace install <content-id>` and `marketplace update` stamped only the first three, and Studio Pro
reads all of them: the module was listed among the app's own modules in the App Explorer instead of under
"Marketplace modules". `SHOW MODULES` reads `FromAppStore` only, so mxcli's own output could not show it.

This threads the resolved content id from the marketplace lookup through `installModule` →
`installModuleFromFile` → `installByTransplant` → `PerformInstall`, and from the update command into
`PerformUpdate`, and has `StampMarketplaceVersion` write the version UUID into both `AppStoreGuid` and
`AppStoreVersionGuid` and the content id into `AppStorePackageIdString`, through one helper
(`stampModuleDoc`). The helper keeps the ADR-0005 rule: it only assigns keys the document already has.

`--file` installs still record no identity (a package on disk has none); a `--content-id`/`--version`
pair for `--file` is a separate ask on the issue.

**Tests:** three unit tests on the helper; the `security_test.go` call sites updated. `CGO_ENABLED=0 go test ./...` on
`main` 95091765: 84 packages ok, 0 FAIL; gofmt and go vet clean.

**Field:** <fill in: mxcli built from this branch, `marketplace install 1011` on a fresh Mendix <ver>
project, the five fields read from the unit, Studio Pro <ver> shows Encryption under "Marketplace modules">.
