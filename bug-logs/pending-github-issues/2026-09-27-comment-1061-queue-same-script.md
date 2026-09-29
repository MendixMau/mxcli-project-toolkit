Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **FILED — comment on https://github.com/mendixlabs/mxcli/issues/1061#issuecomment-5856968798 (2026-09-27)**. Retested before filing on mxcli main 95091765 in a neutral blank 11.12.2 app; the filed text (the live issue) supersedes this draft. Reproduced: check exits 1, exec refuses; --no-check build has 0 errors.

--- everything above this line is stripped before filing ---

**Title:** (comment on open #1061) `check --references` misses a queue created in the same script

## Environment

- mxcli **v0.23.0**
- Mendix / mxbuild **11.12.2**, MPR v1
- Linux (cloud container)

A task queue created earlier in the same script is reported unresolved by `check --references`,
though exec creates and resolves it. Add as a repro comment on #1061 rather than a new issue.
