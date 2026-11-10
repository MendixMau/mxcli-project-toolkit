# PROJECT.md — base Decision Register

Every gate decision lands here as `CONFIRMED` or `ASSUMED`, never silently decided. See
`conversion-runbook.md` §1 for the interview protocol this file supports.

## Current stage

**Stage 5 — Build**, in progress (manual gate: its verdict is a Decisions row, not a file) — gates passed: P, 0, 1, 2, 3, 4 · manual: 5 (derived by gate-check on 2026-10-27; re-run it rather than editing this line).

Toolkit commit: a088b4e0
Exec approval: auto
Permission profile: project
Unit tests default: no
Unit modules: Purchasing
Interview mode: auto
Pipeline mode: balanced
Entry mode: Requirements-driven
Size tier: full — 2 modules of equal weight (Purchasing, Approval) exceeds the small-tier bound of 1 (CAC-1, ASSUMED)

<!-- The bold line above is a READOUT: bin/gate-check.sh rewrites it on every full run from the
     verdicts it just produced (first stage neither PASS nor WAIVED). Do not edit it by hand.
     Where this project joins the pipeline: nothing recorded, so it starts at Stage P — the
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
| P | Entry mode: Requirements-driven | ASSUMED | Evidence: only sources/requirements.md exists, no legacy code, no .mpr content to change. Rejected: greenfield (specs exist). Cost if wrong: stages 0-4 would be skipped, reversible. (consentBy: auto-mode, consentAt: 2026-10-27) |
| P | Interview mode auto, exec approval auto, permission profile project, unit tests default no | ASSUMED | User explicitly asked for an unattended A/B test run. Rejected: steering. Reversible. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 5 | Pipeline mode: balanced (intake Q15) | ASSUMED | Experiment arm for PR #700 run 3 (end-to-end): maintainer asked for two arms high-speed / balanced; this arm is balanced. Rejected: the other mode (it is the other arm). (consentBy: auto-mode, consentAt: 2026-11-09) |
| 0 | D-1 Scope: whole app in two slices (Purchasing first, Approval second); extraction N/A (text-native corpus) | ASSUMED | Rejected: extract pipeline (nothing to extract). Cost if wrong: low. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 0 | Size tier: full - 2 modules exceeds the small-tier bound of 1 | ASSUMED | Rejected: small tier (module count bound fails). Reversible by declaring small at next gate. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 1 | D-2 Path B only: KB from requirements.md; Path A N/A, Path C no SME | ASSUMED | Rejected: SME interview (none available). Gaps recorded as ASSUMED. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 2 | BRD: two BRDs F001/F002, 15 use cases, validated Clean; open questions Q1,Q2 resolved ASSUMED | ASSUMED | Rejected: one BRD for both modules. Cost if wrong: re-split BRD, cheap. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 3 | D-3 Module boundary: Purchasing + Approval, Approval depends on Purchasing, ApprovalRecord written at decision time (no cycle) | ASSUMED | Rejected: one module with folders; Common supplier module. Cost if wrong: moving entities between modules after build is costly (reversible only before row 3). (consentBy: auto-mode, consentAt: 2026-10-27) |
| 3 | D-4 Look: Atlas defaults basis, sidebar nav, design/ds.css; no ideation-library fetch | ASSUMED | Rejected: ui-ux-pro-max directions. Cost if wrong: token swap in ds.css, cheap. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 3 | D-5 Roles: Requester, Approver, Admin; approver cannot decide own request; >5000 EUR needs approval comment | ASSUMED | Rejected: manager hierarchy. Cost if wrong: grants and microflow changes. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 3 | Single app, no multi-app split (Architecture Scale Flag: no) | ASSUMED | Triggers did not fire. Cost if wrong: high but unlikely. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 3 | Stage 3 sign-off: blueprint, fit-gap, module-design, design system, 8 wireframes, prototype | ASSUMED | Signed off by agent under auto mode; no human reviewed. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 4 | StyleGallery module: No (POC, 2 modules, Atlas defaults) | ASSUMED | Rejected: StyleGallery module. Cost if wrong: retrofit of tokens. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 4 | Build plan: 30 rows, 20 BUILD, ratio 1.33, one use case per row; acceptance per module in plan | ASSUMED | Rejected: per-entity/per-page rows (2.5x cost). Cost if wrong: re-slice rows. (consentBy: auto-mode, consentAt: 2026-10-27) |
| 4 | Stage 4 sign-off: architecture/build-plan.md, coverage ledger clean (307 + 175 leaves claimed) | ASSUMED | Signed off by agent under auto mode; no human reviewed. (consentBy: auto-mode, consentAt: 2026-10-27) |

## Change log

Feedback and change requests, one row each, written BEFORE any edit (`skills/change-intake.md`). Status: open → refined → agreed → applied → proven, or rejected (reason); Closed-by cites the commit, journey or test. Escape a `|` inside the ask as `\|`.

| CR | Date | Source | Verbatim ask | Class | Size | Entry artifact | Status | Closed-by |
|---|---|---|---|---|---|---|---|---|

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|

## Assumptions (ASSUMED, unresolved)

None yet.

## Toolkit position

Waived stage 3: unattended A/B fixture (Interview mode: auto): all Stage 3 artifacts present and checked, but the sign-off decisions are ASSUMED by design, and the gate accepts only CONFIRMED

## Toolkit position

Waived stage 4: unattended A/B fixture (Interview mode: auto): build-plan.md and closing rows verified present, but the Stage-4 decision is ASSUMED by design, and the gate accepts only CONFIRMED
