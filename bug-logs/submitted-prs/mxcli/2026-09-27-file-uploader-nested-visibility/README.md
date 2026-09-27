Status: READY-TO-SEND (not yet opened) · closes mendixlabs/mxcli#1198 · base upstream main 95091765

# mxcli PR: null hidden object-list item TextTemplates (File Uploader simple mode, CE0463)

Per `skills/upstream-feedback.md` §3a. The patch is `0001-fix-pages-null-hidden-object-list-item-TextTemplates.patch`
(2 files, +168: `mdl/backend/widgetobj/builder.go` and a new test).

## Send it (from a machine with GitHub push access)

```bash
git clone https://github.com/<you>/mxcli.git && cd mxcli     # your fork of mendixlabs/mxcli
git remote add upstream https://github.com/mendixlabs/mxcli.git
git fetch upstream && git checkout -b fix/1198-nested-item-visibility upstream/main
git am <toolkit>/bug-logs/submitted-prs/mxcli/2026-09-27-file-uploader-nested-visibility/0001-*.patch
git commit --amend --reset-author --no-edit                  # makes you the author
make build && make test && make lint                         # upstream moves daily; re-prove on today's main
git push -u origin fix/1198-nested-item-visibility
gh pr create -R mendixlabs/mxcli --head <you>:fix/1198-nested-item-visibility \
  --title "fix(pages): null hidden object-list item TextTemplates under nested visibility rules (closes #1198)" \
  --body-file pr-body.md                                     # the section below, saved to a file
```

If `git am` conflicts or `make test` fails on the new main, stop and check whether upstream already fixed #1198 (that happened to #1199).
Upstream CONTRIBUTING asks for an approved issue before a PR; if #1198 has no maintainer reply yet, a short comment there linking the PR is enough.
Once it is open, update the status line: `Status: OPENED mendixlabs/mxcli#NNN <date>`.

## PR body (Part 1, publishable)

Closes #1198

**What it does**

When a pluggable widget's editorConfig hides a sub-property of an object-list **item** (a nested visibility rule, `ListPropertyKey` set), the builder kept the shipped default text in that item's required TextTemplate even while the rule hid it. Studio Pro stores `null` there, so `mx check` reports CE0463.

Found on File Uploader 2.5.0: `allowedFileFormats[].typeFormatDescription` is a required TextTemplate that is hidden when `configMode = "simple"`, so every simple-mode format failed `mx check`.

`ApplyVisibilityRules` now skips nested rules at the top level and evaluates them per item. When a rule can be decided from the item's own primitive values and it fires, that item's TextTemplate is set to `null`.

**Scope and blast radius**

- The code is generic. It applies to any pluggable widget whose editorConfig hides an object-list item sub-property, not only File Uploader.
- It is narrow on purpose:
  - Only the *hidden* direction is changed. Visible item templates keep the existing #891 handling.
  - Only `TextTemplate` values are touched.
  - A rule that cannot be decided leaves the item unchanged.
- Widgets without nested rules take an early return, so they are unchanged.
- DESCRIBE, the parser and top-level visibility handling are not changed.

**Testing**

- `make test`: all 84 packages ok, on upstream `main` 95091765. `gofmt` and `go vet` are clean.
- New unit test `TestApplyPropertyVisibility_NestedObjectListItem` covers two cases: a simple-mode item's hidden template is nulled, and an advanced-mode item's visible template is kept.

**Mendix validation (11.12.2)**

- Page: a File Uploader in files mode with one `simple` format (.txt) and one `advanced` format (.zip).
- Before: CE0463 on `typeFormatDescription`.
- After:
  - `mx check`: 0 errors.
  - Runtime (`mxcli run --local`): both files uploaded and stored, 2 of 2.
  - Download: the downloaded bytes are sha256-equal to the source files, 2 of 2.
  - A `.csv` file is rejected by the widget and creates 0 rows.

**Not tested:** image mode, and opening the model in Studio Pro.
