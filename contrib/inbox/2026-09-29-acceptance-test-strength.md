# Acceptance testing: what made the toolkit arm's tests stronger, and its three gaps

**From:** benchmark cook-off (mxcli + toolkit arm vs Studio Pro MCP arm, same frozen spec)
**Date:** 2026-09-29
**Kind:** learning
**Field evidence:** both arms ran the same acceptance rows, seed data and DONE bullets. Toolkit arm: 149 microflow unit tests (428 @expect) + 33 Playwright scripts with OQL DB checks, all committed; 20/20 scenario bullets (stitched from 3 runs); final E2E 62 pass / 0 fail / 7 not run. MCP arm: 0 committed unit tests or scripts; 11/20 in its official run; timers skipped.
**Proposed target:** `skills/testing-shape.md`, `skills/test-result-audit.md`

---

Keep (measured to matter):
- Tests and results committed per run, with a pass/fail trend (38/18 → 62/0).
- **Timer compression** (1-minute days) made timer scenarios testable — that run found an
  escalation bug (uncommitted change) the other arm never exercised.
- Fresh data per variant, not reuse of rehearsal data.

Gaps found (the other arm did these better):
- Menu/permission refusal checked client-side only — add a server-side probe (expect HTTP 560
  / access denied), not "the menu item is hidden".
- Unexpected 400/422 API responses treated as informational — make them failures.
- 20/20 was stitched from three runs — require one clean-database final run that includes the
  timer scenarios.
