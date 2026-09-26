# `mxcli run --local` starts with scheduled events off — a job-driven feature is never exercised locally

**From:** card-disbursement requirements-driven build (build-plan row 5.6)
**Date:** 2026-09-26
**Kind:** learning
**Field evidence:** mxcli v0.24.0, Mendix 11.13.0, hsqldb. Two starts of the same model, runtime log `app/.mxcli/runtime.log`:
default start logs `Core: Synchronizing scheduled events: None`; with `--runtime-setting ScheduledEventExecution=ALL`
it logs `Synchronizing scheduled events: All` and `ActionManager: Scheduling <Module>.<ScheduledEvent> to run every 1 minutes`.
**Proposed target:** `skills/testing-shape.md` (false-green register) and whichever skill documents `run --local` for Stage 5 proofs

---

A module whose behaviour hangs off a scheduled event (a status refresh every minute) passes every
local journey without the job ever running: the default `run --local` start does not execute
scheduled events. The journeys looked complete — the manual "Check now" path calls the same
microflow — but the timer path itself was never observed.

Measured proof with the setting on: two ticks (13:34:00, 13:35:00) each wrote one integration-call
row (10 → 12) and advanced the status table's CheckedOn to the tick time; 0 ERROR/WARN lines after start.

What the project did, and what I'd suggest the toolkit say:
1. Prove scheduled work in its **own** start with `--runtime-setting ScheduledEventExecution=ALL`,
   counting rows before and after ≥ 2 ticks, and grep the runtime log for the `Scheduling …` line.
2. Keep journeys on the default (off) when they count rows exactly — a tick inside a step adds a row.
   Say so in the journey's `_note`, so nobody "fixes" the count later.
3. Candidate false-green row: "scheduled event never ran — `run --local` default" (Rung: data / behaviour).

Related, same row (already fixed in `project-tests/e2e/journey-runner.js`, see CHANGELOG): a forced
click skips Playwright's actionability check, so an overlay (toast, popup underlay) receives it and
the step reads as done. Candidate false-green row: "forced click landed on an overlay".
