Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **FILED — https://github.com/mendixlabs/mxcli/issues/1226 (2026-09-27)**. Retested before filing on mxcli main 95091765 in a neutral blank 11.12.2 app; the filed text (the live issue) supersedes this draft. Measured on a classic-client (UseOptimizedClient = No) 11.12.2 app: 57 × MPR012, mx check 0 errors, 0 × CE0582.

--- everything above this line is stripped before filing ---

**Title:** MPR012 assumes the React client

## Environment

- mxcli **v0.23.0**
- Mendix / mxbuild **11.12.2**, MPR v1
- Linux (cloud container)

On a Dojo-client project MPR012 reports a React-only issue (false alarm). Ask: read the project's
client setting and skip/downgrade when not React. No existing issue found.
