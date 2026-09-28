Repo: mendixlabs/mxcli
Source: toolkit inbox `contrib/inbox/2026-09-27-mxcli-upstream-issues.md`, probes on scratch copies 2026-09-27
Status: **DRAFT, not filed** (Bug). Duplicate search done 2026-09-27. Retest on the current mxcli release before filing.

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
