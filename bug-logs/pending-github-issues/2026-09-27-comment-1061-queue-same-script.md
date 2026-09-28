Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **DRAFT, not filed** (Comment on open #1061). Duplicate search done 2026-09-27. Retest on the current mxcli release before filing.

--- everything above this line is stripped before filing ---

**Title:** (comment on open #1061) `check --references` misses a queue created in the same script

## Environment

- mxcli **v0.23.0**
- Mendix / mxbuild **11.12.2**, MPR v1
- Linux (cloud container)

A task queue created earlier in the same script is reported unresolved by `check --references`,
though exec creates and resolves it. Add as a repro comment on #1061 rather than a new issue.
