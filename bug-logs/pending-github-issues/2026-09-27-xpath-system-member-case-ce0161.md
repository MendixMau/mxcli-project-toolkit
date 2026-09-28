Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **FILED — comment on https://github.com/mendixlabs/mxcli/issues/1213#issuecomment-5856968276 (2026-09-27)**. Retested before filing on mxcli main 95091765 in a neutral blank 11.12.2 app; the filed text (the live issue) supersedes this draft. WIDENED and filed as a comment on #1213: check resolves no bare attribute name in a retrieve XPath (4 of 5 spellings pass check, fail mx check); describe prints the member as CreatedDate.

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
