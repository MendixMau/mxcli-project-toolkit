Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **FILED — comment on https://github.com/mendixlabs/mxcli/issues/671#issuecomment-5856968540 (2026-09-27)**. Retested before filing on mxcli main 95091765 in a neutral blank 11.12.2 app; the filed text (the live issue) supersedes this draft. Filed as a comment on the open PERF-series proposal #671, not a new issue; activities_for() exposes no loop containment.

--- everything above this line is stripped before filing ---

**Title:** Feature: lint rule for REST call / retrieve / microflow call / delete inside a loop

## Environment

- mxcli **v0.23.0**
- Mendix / mxbuild **11.12.2**, MPR v1
- Linux (cloud container)

Commit-in-loop is covered (CONV011); REST calls with commits inside a loop were the #1 finding of a
best-practices review and nothing flagged them. Blocker noted in the toolkit: the Starlark API exposes
no loop containment. Ask: expose the enclosing loop (or a `in_loop` flag) on activities, or ship a Go rule.
