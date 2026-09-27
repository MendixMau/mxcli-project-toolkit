# Addendum to association-owner-ignored: owner Both across modules → CE0066

**Source:** marketplace-rnd, scratch copy probe 2026-09-27, mxcli v0.23.0 / Mendix 11.12.2.
**Status:** unreviewed inbox drop; extends `2026-09-27-association-owner-ignored.md`.

## Repro
`drop association` + `create association UserGroups.GuestGroup_App ... owner Both` where the
other end (`AppStore.App`) lives in another module. mxcli prints "Reconciled 3 access
rule(s)…" — only GuestGroup's rules. `AppStore.App`'s 13 rules get no MemberAccess for the new
association → `mx check`: `[CE0066] ... at Domain model of module 'AppStore'`.
Neither `update security` nor the audit-member strip script clears it.

## So
There is no mxcli path to owner Both on a cross-module association today: `create or modify`
ignores it, drop+create leaves the far side stale. Only the raw BSON patch works
(`mdlsource/guest-groups/14-one-to-one-guestgroup-app.py`, proven on a scratch copy, 0 errors).
The project fell back to owner Default and a 1-* convention.
