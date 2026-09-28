# Upstream log — mendixlabs/mxcli, September 2026

This is the index of what we sent upstream or have ready to send.
- The status line in each linked file is the source of truth.
- The remote is the final truth. Check it with `skills/upstream-feedback.md` §7 before you trust this page.

## Filed issues

| # | Filed | Title | State we last saw |
|---|---|---|---|
| mendixlabs/mxcli#1198 | 2026-09-25 | File Uploader simple-mode formats fail `mx check` with CE0463 | Open. Fix proposed in PR #1227 |
| mendixlabs/mxcli#1199 | 2026-09-25 | DESCRIBE of a File Uploader page does not re-execute (generic `DataSource:`) | Fixed upstream in commit 51b36dc0 (2026-09-25). Retest on the next release |
| mendixlabs/mxcli#1200 | 2026-09-25 | Pluggable widgets built from the .mpk lose their `<actionVariables>` (CE0463) | Open |
| mendixlabs/mxcli#1201 | 2026-09-25 | `ALTER PAGE … SET ImageUrl` on a pluggable widget reports success and changes nothing | Open |
| mendixlabs/mxcli#1223 | 2026-09-27 | Cross-module association with `owner Both`: the other module's access rules get no member entry, CE0066, `update security` says up to date | Open |
| mendixlabs/mxcli#1224 | 2026-09-27 | `create or modify association` keeps the old owner when the association crosses modules | Open |
| mendixlabs/mxcli#1225 | 2026-09-27 | `revoke … (write (<association>))` says "No access rules found", exits 0, changes nothing | Open |
| mendixlabs/mxcli#1226 | 2026-09-27 | MPR012 warns on legacy image widgets in a classic-client app (no CE0582 there) | Open |
| mendixlabs/mxcli#1228 | 2026-09-28 | `alter page` / `alter snippet` cannot `set RenderMode` on a dynamic text ("not a property of this built-in widget") | Open. Fix proposed in PR #1229 |

## Comments on existing issues

| On | Posted | What it adds |
|---|---|---|
| [mendixlabs/mxcli#1213](https://github.com/mendixlabs/mxcli/issues/1213#issuecomment-5856968276) | 2026-09-27 | Bare attribute names in a retrieve XPath are never resolved: 4 of 5 spellings pass `check`, fail `mx check`; `describe` prints `CreatedDate` |
| [mendixlabs/mxcli#671](https://github.com/mendixlabs/mxcli/issues/671#issuecomment-5856968540) | 2026-09-27 | Retrieve / call / delete in a loop get no lint finding; `activities_for()` exposes no loop containment |
| [mendixlabs/mxcli#1061](https://github.com/mendixlabs/mxcli/issues/1061#issuecomment-5856968798) | 2026-09-27 | A queue created earlier in the same script is "not found"; `exec` refuses a valid script |

## PRs

| Package | Closes | Status |
|---|---|---|
| `submitted-prs/mxcli/2026-09-27-file-uploader-nested-visibility/` | #1198 | OPENED as [mendixlabs/mxcli#1227](https://github.com/mendixlabs/mxcli/pull/1227) on 2026-09-28; linked from #1198 |
| `submitted-prs/mxcli/2026-09-28-alter-page-set-rendermode/` | #1228 | OPENED as [mendixlabs/mxcli#1229](https://github.com/mendixlabs/mxcli/pull/1229) on 2026-09-28; linked from #1228. Rebased from fork-only MendixMau/mxcli#1 (now closed) |

## Issue drafts

The seven 2026-09-27 drafts in `pending-github-issues/` were all filed on 2026-09-27: four as #1223–#1226 and three as comments (tables above). Each file's status line carries its link and how the filed text differs from the draft. Three changed on retest against main 95091765: `create-or-modify-assoc-ignores-owner` narrowed to cross-module only, `partial-revoke-member-noop` changed symptom (false "No access rules found", exit 0), and `xpath-system-member-case-ce0161` widened to all bare XPath member names.
