# Upstream log — mendixlabs/mxcli, September 2026

This is the index of what we sent upstream or have ready to send.
- The status line in each linked file is the source of truth.
- The remote is the final truth. Check it with `skills/upstream-feedback.md` §7 before you trust this page.

## Filed issues

| # | Filed | Title | State we last saw |
|---|---|---|---|
| mendixlabs/mxcli#1198 | 2026-09-25 | File Uploader simple-mode formats fail `mx check` with CE0463 | Open. The fix is in the PR package below |
| mendixlabs/mxcli#1199 | 2026-09-25 | DESCRIBE of a File Uploader page does not re-execute (generic `DataSource:`) | Fixed upstream in commit 51b36dc0 (2026-09-25). Retest on the next release |
| mendixlabs/mxcli#1200 | 2026-09-25 | Pluggable widgets built from the .mpk lose their `<actionVariables>` (CE0463) | Open |
| mendixlabs/mxcli#1201 | 2026-09-25 | `ALTER PAGE … SET ImageUrl` on a pluggable widget reports success and changes nothing | Open |

## PRs (ready to send)

| Package | Closes | Status |
|---|---|---|
| `submitted-prs/mxcli/2026-09-27-file-uploader-nested-visibility/` | #1198 | READY-TO-SEND. The README has the send steps |

## Issue drafts (not filed)

All seven are in `pending-github-issues/`. Project names are replaced with placeholders.

| File | Kind |
|---|---|
| `2026-09-27-assoc-owner-both-cross-module-ce0066.md` | Bug: `owner Both` across modules leaves the other side's access rules without MemberAccess (CE0066) |
| `2026-09-27-create-or-modify-assoc-ignores-owner.md` | Bug: `create or modify association` silently ignores an owner change |
| `2026-09-27-partial-revoke-member-noop.md` | Bug: partial `revoke ... (write (<association>))` is a silent no-op |
| `2026-09-27-xpath-system-member-case-ce0161.md` | Bug: XPath system member in the wrong case passes `check`, fails at build (CE0161) |
| `2026-09-27-mpr012-assumes-react-client.md` | Bug: MPR012 assumes the React client |
| `2026-09-27-comment-1061-queue-same-script.md` | Comment on open #1061: `check --references` misses a queue created in the same script |
| `2026-09-27-lint-activity-in-loop-feature.md` | Feature: lint rule for REST call, retrieve, microflow call or delete inside a loop |
