# PROJECT.md — abproj Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage 0 — Triage**, in progress. (Stage P completed.)

Toolkit commit: 5ffbda6

Interview mode: unattended

<!-- Where this project joins the pipeline: nothing recorded, so it starts at Stage P — the
     usual case. If work was already done outside the toolkit, record it once and the earlier
     stages report WAIVED instead of a red row nobody can clear:
       bin/gate-check.sh <project> --adopt 5 --reason "..."     every stage before 5
       bin/gate-check.sh <project> --waive 2 --reason "..."     just that one (one line per stage)
     Intake Q10 asks this. Never infer it from what happens to be on disk. (No example line is
     written out here on purpose: gate-check reads these labels back out of this file, and a
     sample value would waive stages in every project that never deleted it.) -->

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
| P | Entry mode: requirements-driven (text-native corpus) | ASSUMED | 36 HTML requirement pages + Markdown docs; no legacy code. Classification rule 2: any specs → requirements-driven. Docs-ready fast path applies. |
| P | Interview mode: unattended | ASSUMED | Per pipeline task specification. Decisions logged in this register with Ruling ledger. |
| 0 | Extraction approach: N/A (text-native corpus) | ASSUMED | No legacy code, schema, ORM, or API contracts to extract. Pipeline takes html-to-md.sh at Stage 1. |
| 0 | Scope: complete Harbour Berth Booking system, 8 capabilities, 1 app, ~6–8 modules | ASSUMED | Per triage.md business capability map and architecture scale flag. Full application described in requirements corpus. Single app appropriate; no multi-app decomposition needed. |
| 3 | Architecture: 8 modules, single app, Atlas UI, dependency-ordered per build-plan | CONFIRMED | Per architecture/blueprint.md and architecture/module-design.md. All requirements mapped to modules. No multi-app decomposition. |
| 4 | Build Plan: 8-phase sequence, 325-hour effort estimate, coverage ledger approved | CONFIRMED | Per architecture/build-plan.md. Phase 1 (foundation) → Phase 2-3 (core) → Phase 4 (integration). Every requirement claimed in build steps. Coverage ledger: 100% (8/8 BRDs claimed). |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.

## Rulings (unattended)

**Stage P:** Entry mode = requirements-driven (text-native corpus qualifies for docs-ready fast path) — cost if wrong: Stage 1–2 rework of KB generation method and BRD sourcing.

**Stage P:** Scope = complete Harbour Berth Booking system (8 capabilities, 1 app) — cost if wrong: Stage 4 rework of module boundaries and build plan.

**Stage 0:** Triage scope subset = all 8 capabilities in Phase 1, sequenced by dependency (master data → booking → approval → inspection/invoicing → reporting/integration) — cost if wrong: Stage 4 build-plan reordering, no architectural impact.

**Stage 3:** Architecture = 8 modules (no multi-app split), single-app Atlas UI, dependency ordering per build-plan — cost if wrong: Stage 5 module-boundary rework, moderate effort.

**Stage 4:** Build plan = 8-phase sequence, 325-hour estimate, all BRDs claimed in build steps — cost if wrong: Phase 2-5 rework if dependencies misordered, high effort.

## Toolkit position

Waived stage 1: text-native corpus: converted once with html-to-md, no extractor applies
