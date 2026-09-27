# Grants injecting System.owner/changedBy member access → CE0066 (fixed upstream; record the version)

**Source:** marketplace-rnd probe `analysis/probes/2026-09-26-d13-ce0066/`. **Status:** unreviewed.

## Failure
Grant scripts added MemberAccess entries for `System.owner` / `System.changedBy` on entities
without those audit members (AppCategory, AppContentType, InIDE.CatalogMenu) → CE0066.
Fixed upstream in mxcli 2455ee9f; **not reproduced on v0.23.0** (three probes, 0 errors).
The Mac exec almost certainly used an older mxcli on PATH (v0.21.0 seen there) instead of the
project's.

## Ledger entry + process point
- Ledger: symptom, "fixed in 2455ee9f / ≥ v0.22", interim `strip-audit-member-access.py`.
- BUILD-LOG rows should record `mxcli --version` actually executed; exec.sh can stamp it.
  A bug "reproduced" on the wrong binary costs a probe day (see `retesting-learned-rules.md`).
