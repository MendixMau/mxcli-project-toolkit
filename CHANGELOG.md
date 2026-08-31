# Changelog

Newest first, grouped by date. **The entry lands in the same commit as the change** — that is
the whole discipline, and why this file replaced `process/toolkit-worklog.md` (which rotted the
moment updating it became a separate chore). One line per change:
`kind(area): what and why (field evidence / bug id) — contributor or source project`.
Kinds: `new` · `fix` · `learn` (a skill/learning) · `process` (rules, templates, CI).
Credit the person or project that surfaced the change — the credit line is the thank-you.

## 2026-08-31
- process(contrib): contribution pipeline — `contrib/inbox/` low-friction lane, `CONTRIBUTING.md`, PR template, CI checks on every PR, `bin/harvest-learnings.sh` to auto-draft inbox entries from a project's stored learnings; wired into `checkpoint-cutover.md` as the closing action so every project's wrap-up harvests
- process(leak-guard): init-project.sh ends with a three-line denylist nudge — new client at kickoff → add the name to .leakguard-deny and the LEAKGUARD_DENY secret; advisory only, never blocks
- process(changelog): this file, seeded from the last month; append rule added to `CLAUDE.md`
- fix(portability): `fixture-manifest.sh` and `report-disposition-check.sh` invoked a bare Python name — now resolve through `_common.sh` `require_py` (surfaced by promoting `check-portability.sh` to CI)

## 2026-08-28
- fix(page-scope): SHOW PAGES header rows with Excluded/Folder/Params columns were counted as pages — 6 real pages inflated to 13 (F-042, found in the MarkUseCase build) — Mark's session
- fix(e2e): two-tree layouts (`.mpr` under `app/`) now resolve — `project.config.template.js` root walk probes `app/`, `design-audit.js` probes beside the root; same bug as F-020, found twice (F-042 cluster)
- fix(verify-module): `page-scope.sh` wired in as a mandatory rung before the design audit — its artifact finally has a producer in the chain
- new(check-scripts): `bin/check-scripts.sh` parses every shipped script under its own interpreter at setup time (CRLF, bashisms, syntax); wired into `doctor.sh`, `init-project.sh`, `sync-project.sh`
- fix(design-audit): Windows-safe mxcli invocation — Node's `execFileSync` gets `.exe`/`.cmd` probes and an env override (MSYS maps bare names for bash, not for Node)
- process(shipping): "field-proof before merge" rule in `CLAUDE.md` — golden input captured never hand-written, both layouts, both platforms, one cited field run, a producer for every consumed artifact (root cause of the whole F-042 cluster)
- learn(theme): token port is not the component-CSS port — the theme-apply trap, from the MarkUseCase build
- new(page-fidelity): every score appended to the project's `docs/PAGE-FIDELITY.tsv`; first non-stub row per page is the first-build score of record vs the ≥80% target; `--stub` exempts declared forward-reference stubs
- process(install): `report-disposition-check.sh` declared noinstall — gate-check runs it from the toolkit clone — Mark

## 2026-08-27
- new(doctor): build-toolchain verification — mxbuild/java executed not just found (exit 126 = wrong-platform binary), Docker recommended for the self-verification stack
- new(page-fidelity): `project-bin/page-fidelity.js` — scored wireframe-fidelity instrument (headings/actions/content/classes, weighted), routed and installable; measured 32% median first-build on a real field corpus without it, 90% first-draft with it — VB-USI field runs
- new(check-page-shell): `project-bin/check-page-shell.sh` gates the drafted page shell (column, layout/nav, one H1) against the wireframe before exec — measured 0/10 on a real first build

## 2026-08-26
- learn(css): DROP MODULE removes no CSS — a model reset is not a styling reset — VB-USI
- fix(design-audit): expresses its own failure instead of being stamped PASS by the caller
- fix(sync): `--upgrade-bin` accumulates instead of keeping only the last entry
- process(exec): module brief bound to the write as a build-plan row; `exec.sh` advises, never refuses
- fix(privacy): genericized a leaked client name in a test-result audit

## 2026-08-25
- fix(windows): unrun mxbuild gate on Windows; gate-check's O(n²) fork storm under Git Bash (152 ms/fork with Defender measured)
