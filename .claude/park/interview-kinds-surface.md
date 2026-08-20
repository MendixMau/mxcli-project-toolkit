# Park — interview-kinds-surface · 2026-08-19 18:25

## Cycle goal
Turn the PROJECT-B field log (`~/Desktop/PIPELINE_PROGRESS.md`) into toolkit changes:
#2 the `user-only` question kind, #1 gate-check reporting the runbook's Surface column.

## Done this cycle
- Analysed the field log. Six findings; headline is that gates caught absence, the user caught wrongness.
- Committed `003ae54` — another session's 44-file generic-first work, intact, unreviewed line by line (said so in the message).
- Committed `d2abc2c` — item #2 complete: `user-only` kind in `question-kinds.sh` + `interview-protocol.md`, carve-outs in rules 2 and 3, `test-question-kinds.sh` 27→38 assertions, 5 stale routing lines updated.

## Next action — REASSIGNED 2026-08-19, do not start
Peer session `mxcli-project-toolkit-10` claimed `bin/gate-check.sh` for item #1 and pushed `e6efb4b`
(sync-project.sh convergence + brd-report routing row + re-rendered routing surfaces) — this tree has
not pulled it. Full spec for item #1, including the verified per-stage parse output, was sent to that
session as text; nothing was written here. Pull before touching anything generated. Original brief:

Item #1: parse the Surface column out of
`skills/conversion-runbook.md`'s stage table — parse, do not hardcode, the drift IS the disease — and
emit `PASS (gate) · Surface MISSING: enrichment-summary.html` instead of a bare `PASS`, plus one line
saying gate PASS means present, not correct.

## Expensive findings
- **Measured, and it limits the claim:** a correctly-tagged `user-only` ALREADY blocked before `d2abc2c`, via the `UNCLASSIFIED` fallback. A *mis-tagged* one (branding tagged `gap`, the real 2026-08-19 defect) is invisible before AND after. The counter sees the tag, never the question. Don't re-derive this — it's in the test file header.
- `run-all.sh` already resolves each fixture's subject from its own `# Usage:` line. **The mapping for a `--for <file>` flag exists in code** — ~10 lines to expose, no new table.
- `test-question-kinds.sh` hardcodes `QK="$ROOT/bin/question-kinds.sh"` and ignores `$1`. To run a positive control you must copy the old version *into `bin/`* — it resolves `lib/discover-brds.sh` relative to its own dir, so `/tmp` fails silently with empty counts.
- The three sync failures (`test-bug12-sync`, `test-dryrun-writes-nothing`, `test-bug05`) were measured across a `git stash` that changed `bin/` mid-run. **Invalid — discard, re-run alone.**
- `test-bug05.sh` wants a pre-fix control at `/tmp/wave2/gate-check-PREFIX.sh` (doesn't exist) and `run-all.sh` passes only one arg → its discrimination half never runs. Unrelated suite defect.
- 23 of 24 fixtures use per-run `mktemp`; bug05's is the only fixed path, so cross-run collision is a non-issue otherwise.
- No CI anywhere (`.github/workflows/` absent). Only git hook is `pre-commit` → `check-no-client-data.sh`.
- Nothing consumes `question-kinds.sh --json`, so adding fields is safe. `jq` present on this mac.
- Remaining unbuilt wins, cheapest first: `run-all.sh --for`, a lockfile, a committed `BASELINE.txt`. These are what actually stop the suite chaos; the new `CLAUDE.md` rule relies on every future agent reading it.

## In flight
Nothing. Working tree clean except `.claude/` scratch. Another session's cycle is parked at
`.claude/park/toolkit-dryrun-fixes.md` — not mine, not read.
