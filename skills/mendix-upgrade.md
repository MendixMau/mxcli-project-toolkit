# Upgrade a Mendix App — Studio Pro version plus Marketplace modules

**Applies to:** any mxcli project; upgrading an existing Mendix app's Studio Pro version, Marketplace
module versions, or both.
**Purpose:** Orchestrate the upgrade from triage to an honest progress report (N of M checks closed;
machine codes PASS / FAIL / INVALID, never a prose "looks good"). Method, gate and scripts: `upgrade-toolkit/`.
**Source:** field runs on several Mendix upgrade projects (E1–E7, two batches of parallel worker runs),
2026-08 through 2026-11.

## When this fires

- Someone asks to upgrade a Mendix app's Studio Pro version or its Marketplace modules.
- Someone asks whether an in-progress or finished upgrade is safe to ship.
- An upgrade's gate reports a regression, an INVALID rung, or a verdict nobody can explain.

This is **not** a platform migration (OutSystems, Java, Node — see the Pipelines table) and not a new
build. It is the same app, a newer Mendix/module version, same behaviour expected unless a change is
explicitly approved.

## Start here

Read `upgrade-toolkit/SKILL.md` — it names the step file and script for each stage, in order, and when
to stop. A person reading a finished run's result starts at `upgrade-toolkit/READING-THE-VERDICT.md`.

| Stage | Step file |
|---|---|
| Triage (version path, module plan, release-impact) | `upgrade-toolkit/steps/triage.md` |
| Plan (what changes, step records opened) | `upgrade-toolkit/steps/propose.md` |
| Upgrade (do the work, commits named by step) | `upgrade-toolkit/steps/upgrade.md` |
| Decide (mid-run choices, approve/reject) | `upgrade-toolkit/steps/decide.md` |
| Repair (a FAIL or INVALID rung) | `upgrade-toolkit/steps/repair.md` |
| Gate (every rung, the verdict) | `upgrade-toolkit/steps/gate.md` |
| Report (cockpit, progress line) | `upgrade-toolkit/steps/report.md` |

`upgrade-toolkit/bin/gate.sh` runs every rung (build, idcheck, const, data, rest, logdiff, smoke,
layout, journeys, screens, release, apis, widgets, trail) and writes `gate-summary.md`; a rung with
unset keys is NOT RUN, never silently skipped. `upgrade-toolkit/controls/run-controls.sh --fast` is
the toolkit's own synthetic test suite — run it before trusting a change to the toolkit itself.

## Not this skill

- Reading a legacy (non-Mendix) system into a Mendix app — the Pipelines table / migration entry mode.
- A company's own upgrade conventions or denylisted private names — `company-brain.md` /
  `upgrade-toolkit/bin/private_names.sh` (the list lives outside this repo).
