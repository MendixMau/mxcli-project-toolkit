# obligation-check: LOOK staleness reads the FIRST `VALID AT`, so a report with addenda goes STALE

**From:** card-disbursement requirements-driven build (build-plan row 4.8)
**Date:** 2026-09-26
**Kind:** bug
**Field evidence:** `gate-check.sh <proj> 5` printed "Obligation look STALE: … valid-at <row-3.8 commit>, 10 model commit(s) since". Every page in the report had been looked at again after its last model change, in three dated addenda further down the same file.
**Proposed target:** `bin/lib/obligation-check.sh` (look), `skills/module-review.md` (report shape)

---

The project keeps one dated review file (`ui-review-<date>.html`) and appends an addendum per build
row, each with its own `VALID AT`. The check reads the first `VALID AT` in the first 8000 bytes, which is
the headline's original stamp, so the file went STALE after later model commits.

Workaround used: a report-level `VALID AT: <newest>` in the headline, with the justification written
beside it; the original stamp was renamed "First true at". That tripped the proof rule next. Every
`PROOF-OF-LOOK:` line anywhere in the file must cite a shot newer than that stamp, so the older rows'
proof lines FAULTed ("screenshots older than VALID AT"). Fix used: re-shoot the pages on the current
commit, keep only current `PROOF-OF-LOOK:` lines, and turn the older ones into plain "earlier (superseded)" lines.
After that, look went 3 of 4 discharged.

Two coherent fixes; pick one and say it in module-review.md:
- the check reads the NEWEST `VALID AT` and only the proofs at or after it; or
- the skill says "one report per LOOK pass, never addenda", and the check warns when a file holds more than one `VALID AT`.
