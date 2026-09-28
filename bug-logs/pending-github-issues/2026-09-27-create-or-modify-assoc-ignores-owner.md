Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **DRAFT, not filed** (Bug). Duplicate search done 2026-09-27. Retest on the current mxcli release before filing.

--- everything above this line is stripped before filing ---

**Title:** `create or modify association` silently ignores an owner change

## Environment

- mxcli **v0.23.0**
- Mendix / mxbuild **11.12.2**, MPR v1
- Linux (cloud container)

**Repro:** existing association with owner Default; `create or modify association ... owner Both;`
**Expected:** owner becomes Both, or an error stating owner cannot be modified.
**Actual:** "Modified association"; `describe association` still shows `owner Default`.
**Workaround:** drop+create — but that mints a new ID (DB links lost, member rights reset to None) and hits #1 cross-module.
