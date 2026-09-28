Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **DRAFT, not filed** (Bug). Duplicate search done 2026-09-27. Retest on the current mxcli release before filing.

--- everything above this line is stripped before filing ---

**Title:** XPath system member in the wrong case passes `check`, fails at build (CE0161)

## Environment

- mxcli **v0.23.0**
- Mendix / mxbuild **11.12.2**, MPR v1
- Linux (cloud container)

**Repro:** `retrieve $G from <Module>.<Entity> where [CreatedDate >= $Since];`
**Expected:** `mxcli check` flags `CreatedDate` (system members are `createdDate`, `changedDate`, `owner`, `changedBy`), ideally with a fix hint like MDL047.
**Actual:** "Check passed!"; after exec `mx check` → `[CE0161] Error(s) in XPath constraint`.
**Workaround:** lowercase. **Related:** #641 (closed).
