# Pending GitHub issue — mendixlabs/mxcli

**Status:** drafted, NOT yet filed. File to https://github.com/mendixlabs/mxcli/issues once the
same-module isolation test result is in, and after user review of final wording.

---

**Title:** CREATE ASSOCIATION into a marketplace/foreign-module entity corrupts MPR BSON storage (v0.16.0)

**Body:**

### Summary
Running `mxcli exec` on a script containing a single `CREATE ASSOCIATION` statement that
targets an entity owned by a marketplace/foreign module (e.g. `Administration.Account`,
which extends `System.User`) corrupts the `.mpr`'s BSON storage. The corruption is silent at
exec time — `mxcli exec` reports success — but `mx check` afterward reports errors, and
Studio Pro fails to reopen the project cleanly (`KeyNotFoundException` from BSON deserialization).

### Repro
```sql
CREATE ASSOCIATION TFC."Account_Supplier"
FROM Administration."Account" TO TFC."Supplier"
TYPE Reference
OWNER Default;
```
Run via `mxcli exec script.mdl -p Project.mpr` against a clean, freshly-checked `.mpr`.

- `mxcli check script.mdl -p Project.mpr --references` (pre-flight) passes clean — no warning.
- `mxcli exec script.mdl -p Project.mpr` reports success — association is created, no error shown.
- `mx check Project.mpr` run immediately after: reports errors.
- Reopening in Studio Pro: fails / crashes on load.

### Isolation
Confirmed the bare `CREATE ASSOCIATION` statement alone is sufficient — no accompanying
GRANT/REVOKE access-rule statements are needed to reproduce. This narrows the earlier
suspicion (that GRANT/REVOKE rule manipulation was the trigger) — the corruption appears to
be in association creation itself when the association touches an entity outside the
project's own module.

**Open question (test in progress):** whether this is specific to associations that cross into
a marketplace/foreign-module entity, or whether ANY `CREATE ASSOCIATION` via mxcli corrupts
the MPR regardless of which module owns the target entity. Will update this issue with the
same-module (both entities in the project's own module) test result before filing, or file
with this noted as an open question and follow up in a comment.

### Environment
- mxcli version: (fill in from `./mxcli --version` at time of filing)
- Mendix Studio Pro version: 11.12.1 (from `Connected to: ... (Mendix 11.12.1)` in exec output)
- OS/arch: macOS, arm64

### Workaround
Restore from a pre-exec snapshot (git or manual `.mpr` + `mprcontents/` copy) and perform the
association creation manually via Studio Pro's GUI instead of via `mxcli exec`.

---

## Notes for whoever files this

- Fill in exact `mxcli --version` output before submitting.
- Add the same-module test result (see below) once run — either "confirmed marketplace-specific"
  or "confirmed general association-creation defect" — this changes the title/summary.
- Attach `.mpr-snapshots/last-mxcheck-errors.json` content (or relevant excerpt) as reproduction
  evidence if still available.
- Cross-reference: `bug-logs/mxcli-bugs.md` entry dated 2026-07-22 for full incident history
  (original discovery, snapshot-restore recovery, `bin/exec.sh` gate hardening).
