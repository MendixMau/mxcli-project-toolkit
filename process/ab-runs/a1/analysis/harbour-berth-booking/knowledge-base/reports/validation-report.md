# BRD Validation Report — Harbour Berth Booking

**Run:** 2026-09-09, unattended · **BRDs checked:** F001–F006 (6) · **Sources checked
against:** `share/KB_HarbourBerthBooking_Functional.md` (canonical `KB.md`), `share/entities.json`

Per `skills/brd-validation.md`. This is a requirements-driven project — there is no code-KB,
so checks that compare code vs. documents (check 2's code-vs-doc half, check 6) do not apply;
everything else runs against the single doc-KB.

---

## 1. Duplicate entities/concepts

Checked: every `domainEntities[].name` across all 6 BRDs for near-identical attribute sets
under different names, and every entity name for appearing in more than one BRD.

**Finding: none.** All 11 entities (`glossary.md`'s own list) appear in exactly one BRD each —
Terminal/Berth/Vessel/ShippingAgent in F001, BookingRequest in F002, ApprovalDecision in F003,
Tariff/Invoice in F004, Inspection/InspectionItem in F005, AuditEntry in F006. No entity
attribute set is repeated under a second name.

## 2. Conflicting business rules

Checked: every numbered rule in the KB's SS4 Business Rules against every BRD `useCases[]`/
`microflows[].validations` that cites it, for contradiction.

**Finding: none.** Single-source corpus (no code extraction ran, per Stage 0's Extraction
Approach decision), so there is no second, independently-derived rule set to disagree with the
KB. No two chapters state contradictory figures for the same rule (cross-checked the
figures that appear twice: Berth attributes ch07 vs ch12 — identical; BookingRequest fields
ch07 vs ch09/ch36 — identical; VAT/fee figures appear once each, no restatement to conflict
with).

## 3. Orphaned concepts

Checked: every KB SS4 business rule (1–31) against the BRDs' `useCases`/`microflows` for a
citing entry; every BRD domain entity/rule against the KB for a source.

**Finding, fixed:** rule 10 (berth allocation fit-check, ch13 SS9.1 — vessel length <= berth
max length AND vessel draught >= 0.5m below berth max draught) was in the KB but not reflected
in any BRD. Root cause: it reads as Berth/Vessel master-data logic so was drafted only into
F001, which covers those entities but not the moment the rule actually fires (booking
submission). **Fixed by adding it** to F002's `UC102` main flow and
`ACT_BookingRequest_Submit`'s validations, noted as a cross-module read of F001's Berth/Vessel
— this is the correct home, since the fit-check runs when a booking pairs a specific vessel
with a specific berth, not when either master-data record is edited.

Every other rule (1–9, 11–31) is cited in at least one BRD (verified by grep of each rule's
chapter/section reference — e.g. "ch13 SS9.3" for rule 11 — against all 6 `.brd.json` files).

No entry in any BRD lacks a KB source: every `useCases[].mainFlow` and
`microflows[].purpose`/`.validations` line carries a chapter/section citation traceable to
`KB_HarbourBerthBooking_Functional.md`.

## 4. Broken relationships

Checked: every `domainEntities[].associations[].target` resolves to an entity that exists
somewhere in the BRD set (even across modules), matching the 13 relationships in
`entities.json`.

**Finding: none blocking.** Several associations are cross-module by design (e.g. F002's
BookingRequest associates to F001's Vessel/ShippingAgent/Berth) — expected for a
capability-scoped BRD split, not a broken relationship; noted here rather than silently
passed over. All 13 relationships from `entities.json` are represented; none reference an
entity absent from the full BRD set.

## 5. Low-confidence rollup

`confidence` is `null` on every BRD (hand-written from documents, no code-extraction
scaffolder ran) — `bin/brd-report.sh` labels the pair `documents/cited` on all 6, which is
`unranked` under this check's table (confidence is not `low`/`medium`). Nothing to rank.

## 6. Business process flow reconciliation (code-inferred vs. documented)

N/A — no code-inferred use cases exist (`provenance: documents` throughout, no scaffolder
was run; Stage 0's Extraction Approach decision explicitly declared no code path).

## 7. Negative claims and unearned numbers

Checked every negative claim ("no endpoint specified", "no schema... anywhere") and every bare
number for provenance.

- **D3** (AIS integration contract) and **D5** (data-migration source) both carry negative
  claims. **Fixed:** both now carry a `searchScope` field on their `openQuestions` entry naming
  what was searched (all 36 chapters, full text) and when (2026-09-09), per this check's rule
  that a negative claim needs a search scope, not a softer adjective.
- All numeric rules (VAT 21%, late-arrival surcharge 15%, late-cancellation fee 50%, shore
  power 250/day, 120m fast-track threshold, 0.5m draught clearance, 30-day due date, etc.) carry
  a chapter/section citation in the KB and in the BRDs — none is a bare, unsourced number.

---

## Stop condition

Clean. All 7 checks run; the one orphaned-concept finding (rule 10) and the two
uncited-negative-claim findings (D3, D5) were fixed in the BRDs before this report was written,
not logged as outstanding. No duplicate, conflicting, or broken-relationship findings remain.
`bin/brd-report.sh --json` confirms 0 unreadable keys and 0 fault verdicts across all 6 BRDs.
`bin/facts-lock.sh check` confirms all 6 BRDs agree (0 frozen facts, 0 conflicts — single-author
pass, so no cross-agent identifier drift was possible in this run).
