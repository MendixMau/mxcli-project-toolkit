Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **DRAFT, not filed** (Bug). Duplicate search done 2026-09-27. Retest on the current mxcli release before filing.

--- everything above this line is stripped before filing ---

**Title:** Association `owner Both` across modules leaves the other entity's access rules without MemberAccess (CE0066)

## Environment

- mxcli **v0.23.0**
- Mendix / mxbuild **11.12.2**, MPR v1
- Linux (cloud container)

**Repro:** `drop association <ModA>.<Child>_<Parent>;` then
`create association <ModA>.<Child>_<Parent> from <ModA>.<Child> to <ModB>.<Parent> ... owner Both;`
**Expected:** every access rule on both ends gets a MemberAccess for the association (as Studio Pro does).
**Actual:** "Reconciled 3 access rule(s)" (<Child> side only); <ModB>.<Parent>'s 13 rules untouched →
`mx check`: `[CE0066] ... at Domain model of module '<ModB>'`. `update security` does not fix it.
**Workaround:** raw BSON patch of the unit (add MemberAccess None on the far side's rules, recompute ContentsHash).
**Related:** #1067 (closed), #758, #867, #610 — none cover this.
