**Companion to:** `bug141-alter-page-set-rendermode-dynamictext.md`
**Patch:** `bug141-fix.patch` (git format-patch, 3 commits — fix, docs, test comment; author is a placeholder —
`git commit --amend --reset-author` after `git am`)
**Branch, ready to use:** `MendixMau/mxcli:fix/alter-page-set-rendermode` (fork PR MendixMau/mxcli#1)
**Status:** verified 2026-09-22 against `mendixlabs/mxcli` main `31eee45`; NOT YET submitted —
mxcli's CONTRIBUTING requires the issue to be filed and approved before a PR

---

# BUG-141 fix — how to turn it into the upstream PR

## What is in it (8 files, one concern)

| File | Change |
|---|---|
| `mdl/backend/pagemutator/mutator.go` | `rendermode` case in `setRawWidgetPropertyMut`: dynamic text only; `Text`, `Paragraph`, `H1`–`H6`, any casing, stored canonical; any other value or widget is an error naming the allowed set |
| `mdl/backend/pagemutator/dynamictext_rendermode_test.go` | `TestSetWidgetProperty_DynamicTextRenderMode` (every value, mixed casing) and `…Invalid` (`H7`, and a non-dynamic-text widget) |
| `mdl-examples/bug-tests/alter-page-set-rendermode-dynamictext.mdl` | page and snippet repro with the expected output |
| `.claude/skills/fix-issue/findings/mdl-backend.jsonl` | the finding (symptom, root cause, the MCP/MPR drift) |
| `.claude/skills/mendix/alter-page/SKILL.md` | RenderMode in the SET table |
| `docs-site/src/language/alter-page.md` | same |
| `docs/01-project/MDL_QUICK_REFERENCE.md` | table row and "Supported SET properties" list |
| `cmd/mxcli/syntax/features_page.go` | `mxcli syntax page.alter` shows the `SET RenderMode` line |

## Evidence already gathered

- **Test first:** both new tests fail on `31eee45` and pass with the fix; reverting the
  `mutator.go` hunk makes them fail again.
- `make build && make test && make lint` pass (ANTLR 4.13.2, Go toolchain from `go.mod`).
- **Real model:** on a scratch copy of an 11.14.0 project, the unfixed binary refused
  `set RenderMode = H2 on compTitle`; the fixed binary printed `Altered page`, `describe page`
  showed `RenderMode: H2`, native `mx check` reported 0 errors, and exactly one `.mxunit` changed.
- **Agentic:** the statement was written by Claude Code from the skill text, with no hints.

## Steps (mxcli CONTRIBUTING, Steps 1–6)

1. File the issue: paste the companion draft (`bash render-paste-ready.sh` strips the local
   header). Wait for the maintainer's go-ahead and assign yourself. Note the number `NNN`.
2. Get the code, either way:
   ```bash
   # a) straight from the fork branch
   git clone https://github.com/MendixMau/mxcli && cd mxcli
   git checkout fix/alter-page-set-rendermode
   git checkout -b fix/NNN-alter-page-set-rendermode
   # b) or onto a fresh upstream checkout
   git checkout -b fix/NNN-alter-page-set-rendermode origin/main
   git am <toolkit>/bug-logs/pending-github-issues/bug141-fix.patch
   ```
   Then `git rebase -i origin/main` → squash to one commit if the maintainer prefers, reword it to
   `fix: ALTER PAGE/SNIPPET SET RenderMode on a dynamic text (closes #NNN)`, `--reset-author`,
   and drop trailers you do not want upstream. Optionally rename the bug-test to
   `NNN-alter-page-set-rendermode-dynamictext.mdl` (upstream names most bug-tests by issue).
3. Re-verify on the current main:
   ```bash
   make -C mdl/grammar bootstrap && export ANTLR4_TOOLS_ANTLR_VERSION=4.13.2
   make build && make test && make lint
   ```
4. Push to your fork and open the PR against `mendixlabs/mxcli:main`. Compare URL for the
   ready-made branch:
   https://github.com/mendixlabs/mxcli/compare/main...MendixMau:mxcli:fix/alter-page-set-rendermode
5. PR body — paste this, filling in `NNN`:

```markdown
Closes #NNN

## What does it do?

`ALTER PAGE` / `ALTER SNIPPET` can now set `RenderMode` on a dynamic text:

    alter page Mod.Page { set RenderMode = H2 on txtTitle };

`CREATE PAGE` already wrote this property and the MCP backend's mutator already set it; the MPR
backend's fixed property list in `setRawWidgetPropertyMut` did not include it, so it fell through
to the pluggable-widget setter and failed. The new case:

- applies only to a dynamic text (`Forms$DynamicText`); any other widget gets an error naming it
- accepts `Text`, `Paragraph`, `H1`–`H6` in any casing and stores the canonical spelling
- rejects anything else with `invalid RenderMode "H7" for dynamic text "txtTitle": expected one of Text, Paragraph, H1, H2, H3, H4, H5, H6`

## Testing

- New unit tests in `mdl/backend/pagemutator/dynamictext_rendermode_test.go`, written first:
  they fail on main and pass with the fix (verified by reverting the fix).
- Bug-test `mdl-examples/bug-tests/…-alter-page-set-rendermode-dynamictext.mdl` (page + snippet).
- `make build`, `make test`, `make lint` pass.

## Mendix validation

Mendix 11.14.0: on a copy of a real project, `set RenderMode = H2` on an existing dynamic text →
`Altered page`; `describe page` shows `RenderMode: H2`; `mx check` 0 errors; one `.mxunit` changed.

## Docs

Skill `alter-page`, docs-site `alter-page.md`, `MDL_QUICK_REFERENCE.md`, `mxcli syntax page.alter`,
and a finding in `.claude/skills/fix-issue/findings/mdl-backend.jsonl`.

## Agentic Code Testing

- [x] Tested with Claude Code in dev container
- [x] Claude can generate correct MDL for this feature
- [x] Skills updated (if applicable)
- [x] error messages are helpful for debugging

## Out of scope

`set Content` / `ContentParams` on a dynamic text (grammar-level), `RenderMode` on a container,
`RenderType` on a button.
```

6. After merge and release: mark BUG-141 RESOLVED in `mxcli-bugs.md`, and in the consuming
   project drop the `replace` workaround in favour of `set RenderMode`.
