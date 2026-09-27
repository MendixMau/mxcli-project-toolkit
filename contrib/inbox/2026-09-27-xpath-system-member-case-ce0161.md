# XPath system member in wrong case (`CreatedDate`) passes `mxcli check`, then CE0161

**Source:** marketplace-rnd guest-groups script 13. mxcli v0.23.0, Mendix 11.12.2.
**Status:** unreviewed inbox drop; ledger candidate (`bug-logs/mxcli-bugs.md`), upstream draft
in `2026-09-27-mxcli-upstream-issues.md`.

## Repro (scratch copy only)
`retrieve $G from UserGroups.Guest where [CreatedDate >= $Since];`
- `mxcli check --references` → "Check passed!"
- exec + `mx check` → `[CE0161] "Error(s) in XPath constraint." at Retrieve object(s) activity`

## Fix
System members are lowercase in XPath: `[createdDate >= $Since]` (also `changedDate`,
`owner`, `changedBy`). Built clean with 0 errors.

## Related (works as designed)
`[Assoc = empty]` on an association is caught by check as MDL047 with a `not(Assoc/Target)` hint.
