# BRD Validation Report — Harbour Berth Booking

Run against all 7 BRDs (`F001`–`F007`) in `analysis/knowledge-base/brd/`, per
`skills/brd-validation.md`'s seven checks. All BRDs are hand-written from the converted
document corpus (`provenance: "documents"`), so checks 5 and 6 (which read the auto-scaffolder's
`confidence`/`status` fields) are not applicable — there is no extractor confidence to roll up
and no code-inferred narrative to reconcile against documents; every use case here already *is*
the document-derived narrative.

## 1. Duplicate entities/concepts

None. Each of the 11 domain entities named in `glossary.md` / the appendix data dictionary is
defined exactly once: Vessel, ShippingAgent, Terminal, Berth (F001); BookingRequest (F002);
ApprovalDecision (F003); Tariff, Invoice (F004); Inspection, InspectionItem (F005); AuditEntry
(F006). Other BRDs reference these entities only via `associations[].target`, never a second
`domainEntities[]` definition.

## 2. Conflicting business rules

Two were found while reading the corpus and are **not** silently resolved inside the BRD prose:
each is recorded as an `openQuestions` entry (status `ASSUMED`, with `consentBy`/`consentAt`)
on the BRD it affects, and mirrored as a full Ruling in `PROJECT.md`:

- F002-OQ2 — fast-track auto-approval (ch08 §4.4) vs. manual-review-only (ch15 §11.4).
- F003 UC003 mainFlow note / PROJECT.md Ruling — dangerous-goods approval-gate carve-out
  (ch22 §18.1 vs §18.2), resolved as a carve-out rather than a true conflict.
- F001-OQ1 — IMONumber "up to 7 characters" (ch07/36) vs. "exactly 7 digits" (validation
  screenshot); resolved in favour of the more specific screenshot rule.

No other rule pair in `analysis/rules-extract.md`'s 51-row table contradicts another.

## 3. Orphaned concepts

None. Cross-checked every entity in `glossary.md` and `36-appendix-data-dictionary.md` against
the 7 BRDs' combined `domainEntities[]` — all 11 are present. Cross-checked every named screen
(`28-navigation-and-screens.md`, `29`, `30`, `31`, `09`, `21`) against the BRDs' `pages[]` —
all present. The two workshop-only items (manifest attachment, last-5-bookings) are not
"orphaned" — they are explicitly raised as open questions (F006-OQ1, F003-OQ1) and deferred,
not silently dropped.

## 4. Broken relationships

None. Every `associations[].target` in every BRD resolves to an entity defined in this same
BRD set (see the entity list above) — no association points at an entity name absent from
every BRD, and no external module reference exists (single-app project, no multi-app flag).

## 5. Low-confidence rollup

Not applicable — no BRD in this set was scaffolder-generated, so none carries a `confidence`
field to roll up.

## 6. Business process flow reconciliation (code-inferred vs. documented)

Not applicable — no `useCases[].status` values of `code-inferred`/`doc-confirmed`/`doc-conflict`
exist in this set; every use case's `mainFlow` already cites its document source directly via
`sourceRef`.

## 7. Negative claims and unearned numbers

No BRD or this report claims "0 open questions" or "all green" without qualification. The true
count is 5 `openQuestions` across the set, all `ASSUMED` (verified: `bin/open-questions.sh
/tmp/abproj --stage 2` → `UNRAISED=0 RAISED=0 ANSWERED=0 ASSUMED=5 MOOT=0 UNRECOGNISED=0`,
0 blocking). `bin/brd-report.sh /tmp/abproj` reports 0 unreadable keys and 0 fault sections
across all 7 BRDs (30 pass, 33 skipped-with-reason, 0 fault of 63 total sections).

## Stop condition

Clean. All 7 BRDs pass checks 1–4 and 7 with no unresolved finding; checks 5–6 are not
applicable to a documents-provenance BRD set. Every contradiction and shape-changing gap found
in the source is recorded as an `openQuestions` entry and a `PROJECT.md` Ruling, not silently
picked.
