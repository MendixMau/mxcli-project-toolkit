Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **FILED — https://github.com/mendixlabs/mxcli/issues/1225 (2026-09-27)**. Retested before filing on mxcli main 95091765 in a neutral blank 11.12.2 app; the filed text (the live issue) supersedes this draft. SYMPTOM CHANGED: current main prints a false 'No access rules found matching …' and exits 0; the qualified spelling (write (Mod.Assoc)) is now a parse error — use the short association name.

--- everything above this line is stripped before filing ---

**Title:** Partial `revoke ... (write (<association>))` is a silent no-op

## Environment

- mxcli **v0.23.0**
- Mendix / mxbuild **11.12.2**, MPR v1
- Linux (cloud container)

**Repro:** `revoke Mod.Role on Mod.Entity (write (Mod.Assoc));` on a rule with ReadWrite on the association.
**Expected:** member right drops to ReadOnly.
**Actual:** success message, rule unchanged.
**Workaround:** re-grant the whole rule with the desired member list.
**Related:** #947 (closed; grant replaces instead of merging).
