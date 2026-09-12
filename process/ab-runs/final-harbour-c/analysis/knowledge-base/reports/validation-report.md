# BRD Validation Report — Harbour Berth Booking

Run against 7 BRDs (`F001`-`F007`) per `skills/brd-validation.md`. Docs-ready corpus: doc-KB is
the converted text under `analysis/knowledge-base/text/` (36 pages) plus the 4 root-level
Markdown files; there is no code-KB (requirements-driven, no legacy source).

## 1. Duplicate entities/concepts

None. Every one of the 11 entities named in `glossary.md` and the domain/data-dictionary
chapters (07, 12, 14, 18, 20, 26, 36) is defined in exactly one BRD's `domainEntities[]`
(mechanically checked: 11 unique names, 0 files defining the same name twice). No
near-identical attribute sets under different names.

## 2. Conflicting business rules

Four conflicts found, all between the prose chapters and either another prose chapter or a
prototype screenshot — never silently resolved, each recorded as an `openQuestions` entry
(`status: ASSUMED`, `consentBy`/`consentAt` set) on the owning BRD and cross-referenced from
`PROJECT.md`'s Rulings ledger:

| ID | BRD(s) | Conflict | Resolution taken |
|---|---|---|---|
| C1 | F003 (UC003-8), F005 (UC005-7, F005-Q1) | ch10 "free until 24h before ETA" vs ch19 "72h/50% fee" | ch19's 72h/50% rule adopted (Ruling R3) |
| C2 | F003 (UC003-11, F003-Q2) | ch28 states 3 nav screens; prototype screenshots show 5 | Built to the 5-item prototype nav (Ruling R4) |
| C3 | F002 (F002-Q1) | IMO number "up to 7 chars" (ch07/14) vs "exactly 7 digits" (ch09 screenshot) | Modelled as length-7 String + exact-7-digit validation (Ruling R5) |
| C4 | F004 (UC004-6, F004-Q2) | ApprovalDecision.Reason "Optional" (ch36) vs conditionally-required-on-Reject (ch21 screenshot) | Field stays Optional; conditional validation added (Ruling R6) |

None of these are treated as bugs in the source — two true things stated at two different
points/media in the same documentation set — each is a business call for a human to confirm or
overturn, not a pipeline decision, per this skill's "Tips" section.

## 3. Orphaned concepts

- **In the corpus but not in any BRD:** none found by content. The six "reference only"
  chapters (01 Home, 02 About, 03 Release notes, 06 News, 27 Privacy, 34 Contact) carry no
  business rule, entity or process statement — confirmed by reading each (see
  `analysis/source-sufficiency.json` inventory rows, `answers: []`) — and are cited only in
  `sourceKB`/the source ledger, not synthesised into fake use cases.
- **In a BRD with no traceable source:** none. Every `useCases[].sourceRef` and every
  `domainEntities[].sourceRef` names a specific converted-text file and line; two shape-changing
  gaps (cargo-manifest attachment, last-five-bookings panel) are cited to `workshop-notes.md`
  rather than a chapter, and are flagged in the BRD text as gaps, not presented as chapter fact.

## 4. Broken relationships

None. Every association's `target` resolves to an entity defined in the 7-BRD set (mechanically
checked: 0 unresolved targets across 11 entities / their associations). No `fk-unresolved` or
`no-db-table-found` gaps — there is no DB/ORM source to compare against in this corpus (Stage 0
triage: extraction rows N/A, text-native corpus).

## 5. Low-confidence rollup

Not applicable in the scaffolder sense (`confidence` is emitted by the code-extraction
mappers; these BRDs are hand-transformed from documents, `provenance: "documents"`). Doc-KB
corroboration is `doc-confirmed` on 46 of 54 use cases (the four conflict use cases are
`doc-conflict`, two shape-changing-gap use cases are `code-inferred` since no document confirms
them — see check 3).

## 6. Business process flow reconciliation

Every use case was written directly from the converted text/workshop notes (there was no
separate code-inferred scaffold to reconcile against), so `status` was set on first pass:
`doc-confirmed` (plain chapter statement), `doc-conflict` (checks 2 above), or `code-inferred`
(the two workshop-notes-only shape-changing gaps, S1/S2 — "code-inferred" here means "asserted
only by a raw workshop note, not yet confirmed by a formal chapter", the closest fit of the
three allowed values for this entry mode).

## 7. Negative claims and unearned numbers

Every numeric business rule (30-day max stay, 90-day/48h submission window, 120m fast-track,
0.5m draught clearance, 15%/80m late-arrival, 50%/72h cancellation, 21% VAT, 250/day shore
power, 3-invoice suspension threshold, 5-minute AIS poll) is cited to the exact chapter and line
that states it (`sourceRef`) — none are estimates or invented round numbers. The one open
numeric gap (attachment size limit) is left unfilled and raised as an open question (F003-Q3,
`status: RAISED`) rather than assigned a plausible-sounding default. No negative claims
("not implemented", "does not exist") appear in any BRD.

## Summary

- 7 BRDs, 54 use cases, 11 domain entities, 0 duplicate/orphaned concepts, 0 broken
  relationships.
- 4 genuine business-rule conflicts, all resolved as unattended `ASSUMED` rulings with
  cost-if-wrong stated in `PROJECT.md`, never silently picked.
- 3 shape-changing gaps from workshop notes carried forward as open questions / explicit BRD
  content, one (attachment size limit) still open pending a human answer.
- `bin/open-questions.sh` / `bin/gate-check.sh` are the mechanical readers of these
  `openQuestions` entries; see PROJECT.md's Open questions table for the same 7 items.

## Stop condition

Clean — 0 findings outside the four accepted, explicitly-ruled conflicts and the one still-open
attachment-size question, which is carried forward as an open question rather than counted as a
validation defect.
