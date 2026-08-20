# Park — toolkit-dryrun-fixes · 2026-08-19 16:58

## Cycle goal
Fix the defects a GitHub Copilot / Windows dry run of the toolkit surfaced, so a fresh
scaffold and a Stage 0 triage behave correctly on a non-Claude harness.

## Done this cycle
- Stage P false-green closed: intake bodies say `_Not yet asked._`, not the accepted marker. Generator-only scope (user's call) — existing projects were not retro-fixed.
- Lint-rule clobber fixed: `mxtk_install_lint_rules` moved AFTER `wire-agents.sh` in init-project.sh.
- `AskUserQuestion` portability: `skills/interview-protocol.md` §3 "Asking on a non-Claude agent" is now the single source; 6 other sites defer to it.
- Kickoff questions Q1–Q8 rewritten (entry mode, what/why, fidelity, scope boundary, what-must-not-change, licence, SME, open floor). Q9 byte-identical and pinned.
- `sources/` scaffolded by init with README; gitignored by default, `--ignore-sources`/`--track-sources`, TTY prompt.
- source-sufficiency.sh: scan now includes `.yaml/.yml/.json/.sql/.xml/.csv/.xlsx` + prunes; rubric is two-pass (`inventory` blocks scoring, prints before the grade).
- sync-project.sh reports kickoff questions an old intake never asked; appends only with `--repair-intake`.
- Template extracted to `bin/lib/intake-template.sh`, sourced by init + sync.
- All pushed to `master` (3 commits). Nothing executed against a Mendix model.

## Next action
Awaiting the user's Windows verification run: `git pull` in the toolkit, then
`bin/sync-project.sh <project>` on the USI-RoutingModule project. Expect it to name the
kickoff questions that were never asked (entry mode among them) and change nothing.

## Expensive findings
- **`## 9.` is a hardcoded locator** in `bin/gate-check.sh:276,284`, `bin/sync-project.sh` (3 sites), `tests/wave2/test-bug12-sync.sh`, `tests/wave2/test-stage-p.sh:82,99,133`. Renumber Q9 → sync appends a SECOND copy. Add questions at 1-8 or after 9.
- **`check_stage_P()` awk strips leading `[ \t>*_-]+`** — that is why `_Not yet asked._` normalises to a non-marker and correctly fails.
- **`mxcli init` re-seeds `.claude/lint-rules/` from stock**, and `wire-agents.sh`'s PRESERVE list does not cover it. Any lint-rule install must run after wire-agents.
- **Test baselines (do not re-derive):** `test-stage-p.sh bin/gate-check.sh` 14/0 · `test-guide-reopen.sh` 10/0 · `test-source-sufficiency.sh` 51/0 · `test-bug12-sync.sh bin/sync-project.sh` PASS=26 FAIL=6. **Those 6 are pre-existing and out of scope** (idempotency ×2, pristine-write ×2, plain-run-rewrote-intake, broken T9 fixture).
- **`test-bug12-sync.sh` is slow (~2 min)**: `mkproj` runs the real `init-project.sh` → real `mxcli init`, ~10s per case. Run it ONCE. Known smell: T7/T8/T10 only manipulate `intake.md` text and do not need a full scaffold; a `mkproj_light` would fix it (not done, separate change).
- Test fixtures must NOT recover templates from a git SHA — first T10 draft used `ef98d8e~1` (wrong commit, from the stale session log) and silently graded against the wrong template. Write fixtures inline.
- `timeout` is not on PATH on this Mac.
- Windows gaps seen in the dry run, NOT fixed: `jq` absent (open-questions gate degrades to MANUAL); Stage 0 message prints the same search path twice.

## In flight
Nothing mid-edit; working tree clean for my files. **Not mine, left untouched deliberately:**
`project-bin/close-task.sh`, `project-bin/exec.sh`, `skills/iterative-build-loop.md` (modified)
and untracked `project-bin/done-drift-check.sh` — neither committed nor reverted.
