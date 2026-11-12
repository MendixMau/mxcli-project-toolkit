# SCORECARD: Checklist to go 1.0.0 (9.24.2) -> 10.24.27.128337 -> 11.12.5 (batch 6, B6T2)

**Overall verdict as the gate prints it (last rung, 10.24.27 -> 11.12.5): INVALID (exit 2)**: `7 PASS/PASS*, 0 EXCEPT, 0 FAIL, 1 INVALID, 1 required NOT RUN` (`gate-summary-rung2-full.md`).
The pipeline's own final line for the same rung reads `PASS gate 10.24.27.128337 -> 11.12.5 (fixed steps)` (`pipeline-SUMMARY-rung2.md`): it means "no judgment stop remained" and its gate run selects only build, idcheck, const, data, logdiff, screens (+ release); it does **not** include the journeys rung. With the journeys rung (and the smoke rung) the gate says INVALID. I do not round it up. **Not PASS.** 3 gate rounds used on the last rung, then stopped.

Versions: source 9.24.2.6130; rung 1 target 10.24.27.128337 (newest 10.24: release notes list 10.24.27 of 2026-10-08, CDN builds found by scan, D1); rung 2 target 11.12.5. App kept module: Administration 2.1.2 (data-bearing removal, D4): "complete except kept modules", never "upgraded".

**Coverage line (rung 2, as printed):** `actions 295 found · 179 generated (116 todo: no-click-path 59, no journey 53, external-call 3, combobox 1) · 53 pass on baseline (126 defect) · 53 pass on new · 0 regression · coverage 53/295 (17%)`; rung 1: `actions 292 found · 179 generated (113 todo: no-click-path 58, no journey 55) · 51 pass on baseline (128 defect) · 53 pass on new · 0 regression · coverage 51/292 (17%)`.

## Verdict per gate rung

| rung | step | verdict | evidence |
|---|---|---|---|
| 1 (9.24 -> 10.24.27) | build / mx check | PASS (after 6 repair passes, D4-D8) | work/build-10.24.27.128337.log, work/check-*.log |
| 1 | idcheck, const, data, logdiff | PASS / PASS* with allow files (D14) | gate-summary-rung1-round1.md, work/diff.md |
| 1 | smoke | baseline defect identical old/new (0 PASS, 2 FAIL, 1 INVALID, 10 SKIPPED, 0 regressions), not a pass | work/smoke-after.json, D9 |
| 1 | journeys | INVALID (exit 3): old 65 PASS / 130 FAIL / 114 INVALID; new 67 PASS / 128 FAIL, 0 regression, coverage 51/292; effects 65 PASS | journeys-before-rung1.out, journeys-after-rung1.out, D10-D13 |
| 1 | screens | 60 REVIEW + 128 INVALID NOT judged at rung 1 (D15). One of them is the real stacked filter/grid regression that I found only at rung 2 | work/e2e-after |
| 1 | release | NOT filled (218+ Studio Pro rows open) | work/release-impact.md |
| 1 | **rung verdict** | **not completed: INVALID/REVIEW** (rung 1's app state still carries the stacked layout; its mx check/build/data are green) | gate-summary-rung1-round1.md |
| 2 (10.24.27 -> 11.12.5) | build | PASS (D17-D24) | work/rung2/build-11.12.5.log, check-24.log |
| 2 | idcheck | PASS (1 RED approved: System.TokenInformation.ReadOnlyHashKey, D28) | gate-summary-rung2-full.md |
| 2 | const / data / logdiff | PASS / PASS* (3 rows) / PASS | work/rung2/diff.md, constants.md, logdiff.md |
| 2 | smoke | NOT RUN as a gate rung; walk equals baseline (D9/D25) | work/rung2/smoke-after.json |
| 2 | journeys | **INVALID** (exit 3): no REGRESSION, no open REVIEW; 119 journeys INVALID, 3 SCREEN INVALID, 126 fail on the OLD app, 2 coverage rules broken; effects 67 PASS; screens 16 PASS / 360 PASS* / 3 INVALID | journeys-after-rung2.out |
| 2 | screens (smoke pairs) | PASS* (2, Switch user popup) | shot-accept-smoke-rung2.txt |
| 2 | release | PASS: 166 of 166 rows (162 by reviewed script, 4 by hand with limits) | release-impact-rung2.md, release-fill-rung2.py, D30 |
| 2 | rest, apis, scanner | NOT RUN / scanner INVALID (ingest not in repo, as in batch 4) | pipeline-SUMMARY-rung2.md |
| 2 | mutant control | RUN by hand: exit 1 on the mutated attribute | mutant-control-rung2.out |

## Blockers on the last rung (every one listed)
1. **journeys rung INVALID**: 126 of 179 generated action journeys fail on the OLD app although the app works (generator limits: widgets inside closed accordions, popups opened from groups, per-row buttons; the pages are reached, screenshots show them). 119 journeys are todo/skipped: `profile` 53 (Phone/Tablet navigation profile), `no-click-path` 59-61, no-role 35, external-call 3, combobox 1. Coverage 53/295 (18%). Not repairable with a documented option: `--baseline-evidence` needs FIXTURE/OLD-APP/FLAKY facts that do not exist.
2. **UNREACHABLE evidence refused for all 61 no-click-path rows**: 12 are reachable through a non-click caller (correct refusal), 49 are blocked by a dangling reference to a module "Checklist" that is neither in the model nor in modules/ (B6T2-18).
3. **smoke rung**: the first menu step "Switch user" (stranded DemoUserSwitcher) fails identically on old and new, so every later step of the role is skipped (0 PASS): the smoke rung has no measuring power on this app (B6T2-9).
4. scanner rung INVALID (ingest not in the repo), rest/apis NOT RUN (optional).
5. Administration 2.1.2 kept (REMOVED association EmployeeManagement.Employee_Account); MES_Atlas_Extension and DemoUserSwitcher stranded (no Marketplace versions); DeepLink 10.0.10 Java hand-ported to 11 (module edit).
6. **Open app risks** (from the release rows, none exercised by a journey): Generate Document (deprecated, still used by Checklist_Reporting.Report_GenerateChecklistReport), string concatenation of empty values (row 89), WSDL import mappings cannot be excluded by tool (row 96), Dojo client still in use (removed in Mendix 12), production database/storage not covered by the gate DB (rows 6, 20, 90, 105, 115), Atlas 4 restyle accepted by hash after opening 6 pairs of 363.

## Batch 4 vs batch 6: INVALID and FAIL counted by cause
Batch 4 = runs/b4-checklist (10.24.26 only, one rung). Batch 6 = this run; rung 2 is the comparable "final" state, rung 1 in brackets where it differs.

| cause | batch 4 | batch 6 | toolkit fix that explains it |
|---|---|---|---|
| journeys: action inventory not wired, nothing walked (INVALID) | 291 of 292 actions without click path, 297 journeys INVALID, coverage 0/292 | wired: 179 journeys generated, 53 pass, coverage 53/295 (17%); no-click-path 59 (was 291) | PR-F22 inventory in the pipeline; role-aware paths |
| journeys: impact todos not closed by journeys (INVALID) | todo rows for role homes open | role homes `covered` by login journeys: 3 covered, 3 todo left (plan.json) | PR-F23 |
| dead pages reported as unreachable (PASS*) | not available | 0 accepted: 49 refused by an unreadable-module rule (B6T2-18), 12 reachable | PR-F24 (exists, did not help here) |
| journeys: baseline-defect FAILs on the old app | 1 FAIL (gallery1, evidenced) | 126 FAIL (rung 1: 128) = generator limits + fixture + destructive order; **new class**, because 179 journeys now click instead of 12 | PR-F25 data waves exist but do not cover `_destructive` (B6T2-14) |
| smoke walk FAIL/INVALID (baseline defects) | 3 FAIL + 1 INVALID | 2 FAIL + 1 INVALID (Switch user), 10 steps SKIPPED | none |
| instrument controls (`make fast`) | 14 FAIL of 829 | 0 FAIL of 1266 (15 skipped) | B4T6-2/3 fixes (fixtures un-ignored, proxy env) |
| data rung INVALID (no after log) | 1 | 0 | B4T6-7 `--log-cmd` default |
| effects INVALID | 1 (covered home) | 0 | B4T6-11 |
| screens: baseline-defect pair INVALID | 1 (journeys), 2 smoke pairs | 3 SCREEN INVALID (journeys), 2 smoke pairs accepted by hash | none |
| scanner rung INVALID | 1 | 1 | not fixed (ingest not in repo) |
| release rows open before hand-fill | 163 | 166 (rung 2) / 218+ (rung 1, not filled) | none; hand/subagent fill |
| journeys coverage INVALID (rule) | 1 (0/292) | 2 coverage rules broken (70% of generated journeys fail on baseline; defects without evidence) | PR-F22 turned a denominator-less INVALID into a measured one |
| real app regressions the gate caught | 2 reported FAIL (calendar open on load / stacked, React teardown) | 1 real (stacked filter + grid layout: same `display:block !important` line; the calendar is closed after the fix); caught by opening screens at rung 2, **not** by a rung that FAILed; React teardown not reproduced (DepartmentManager dashboard opened ~100 times in journeys on 11.12.5, no page error in the logs; smoke steps for that role were skipped) | none |

Net: batch 4's INVALID on "nothing walked" is replaced by a measured 17% coverage and an INVALID on "the instrument fails on the old app" (the generated journeys are not yet robust: closed accordions, popups, destructive order, per-role profile). The overall verdict stays INVALID, not PASS, with different and more informative causes.

## Repairs made to the app (smallest change, HANDWORK.md has the why)
Rung 1: CE1613 Translate microflows (batch-4 MDL), CE0114 x3 `@applyentityaccess` on role-home NAV flows, CE0117 x2 Administration MendixSSO flows, vendorlib pins (44 jars), 45 stale jars removed, Atlas_Core/DeepLink via `--accept-unsaved`. Rung 2: Atlas_Core.FeedbackWidget recreated empty, AnyChart_BuildingBlocks module dropped, theme: `rgba(#C5CFDE, ..)`, `#fdfdfd`, `#ffffff`, `#e9eaeb`, `$brand-info`, `$brand-inverse`, DeepLink Java (2 call sites), MES_Atlas_Extension `.table{display:block !important}` removed, Atlas_Web_Content/NanoflowCommons through `--force-ui --accept-unsaved`.
