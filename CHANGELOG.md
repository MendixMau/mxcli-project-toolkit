# Changelog

Newest first, grouped by date. **The entry lands in the same commit as the change** — that is
the whole discipline, and why this file replaced `process/toolkit-worklog.md` (which rotted the
moment updating it became a separate chore). One line per change:
`kind(area): what and why (field evidence / bug id) — contributor or source project`.
Kinds: `new` · `fix` · `learn` (a skill/learning) · `process` (rules, templates, CI).
Credit the person or project that surfaced the change — the credit line is the thank-you.

## 2026-08-31
- process(bug-logs): second archive pass, older resolutions — 8 entries resolved earlier than the v0.20.0 retest (BUG-20/21/27 and BUG-WF03/WF06 fixed in v0.17.0 upstream #854/#838/#836/#845/#846, the #835 DataGrid2-parameter-binding entry fixed in v0.17.0, BUG-24 superseded/misdiagnosed by BUG-WF06, BUG-28 reclassified as an enhancement request) appended to `bug-logs/archive-resolved-2026-08-31.md` under its own "older resolutions" section, stubs left in `mxcli-bugs.md`; still-open, PARTIAL, and fork-scoped-remainder entries (BUG-47/50/WF02/WF05, the Engalar-only sections, the cross-module half of the inline-association-set entry) left untouched
- process(bug-logs): archive consolidation for the v0.20.0 retest — the 17 resolved / not-reproduced entries (BUG-01/58/64/66/69/71/74/79/80/81/82/85/90/91/97, the GRANT multi-rule entry, the uppercase-`AND`+`!=` entry) moved wholesale to `bug-logs/archive-resolved-2026-08-31.md`, leaving the standard header+pointer stubs; `mxcli-bugs.md` slims from ~4.8k to ~3.8k lines, still-open and PARTIAL entries (incl. BUG-75) untouched
- learn(bug-logs): mxcli v0.20.0 retest (`bug-logs/mxlabs-v0.20.0-retest-2026-08-31.md`) — 27 log entries stamped against tag v0.20.0 on real Linux mxbuild 11.13: 13 resolved (BUG-01/58/64/66/69/71/74/80/82/85/90/91, GRANT additive/multi-rule via v0.19 #936), BUG-81 and BUG-97 not reproduced (write-count cap downgraded), 8 confirmed still open incl. BUG-76 workflow-DECISION corruption (byte-exact signature) and the BUG-70/95 show_page-args gap that v0.19's MDL-PAGEARG01 misses on page-level buttons; `learned-mdl-preflight.md` gains a v0.20 delta block (braced ALTER PAGE form, DataGrid2 derived column names, rule 17/1c retired at ≥v0.20) — retested in a disposable `mxcli new` 11.13 container project
- fix(graph-sweep): GNU-first `stat` try-order — on GNU, `stat -f` doesn't fail, it reads `-f`/`-t` as filesystem-info flags and prints plausible garbage, so the BSD-first fallback never fired and every Linux run FAULTed as "catalog is stale"; found independently on two projects (2026-08-19 and 2026-08-14), verified on a Linux field box — a PLM-workflow migration project & a martial-arts-academy PoC
- learn(bug-logs): BUG-96 (cross-module `ALTER PAGE … INSERT` of a DataGrid2 column writes malformed BSON — Studio Pro loader crashes, mxcli's own reader silently omits the column, only `create or replace page` clears it) and BUG-97 (~15th cumulative write-class exec op corrupts the whole project; recovery lesson: the `.mpr` alone is not a backup, `mprcontents/` is primary storage) — a martial-arts-academy PoC project
- process(contrib): first harvest-triage round — two project harvests triaged: graph-sweep fix and BUG-96/97 promoted (source drafts deleted per the same-commit rule), 7 remaining defect/process items queued genericized in `contrib/inbox/`; stale-install diffs identified as sync debt, not toolkit fixes
- learn(contrib): three steal-candidates queued in `contrib/inbox/` — generated interactive walkthroughs for human-only steps, a "Ruling:" decision ledger for unattended runs, skill-authoring meta-guidance — obra/superpowers & mattpocock/skills (public repos, patterns only)
- learn(ui-preflight): controlled A/B baseline of `ui-preflight-pages.md` (5 drafting reps per arm, same page) — skill inlined: 0 judgement violations across all reps; skill absent: every ToeicBuddy field defect reproduced. Delivery rule added (dispatch prompts must inline the file — a citation is not a read), stale class/gallery caches replaced with read-the-real-file instructions, page-column promotion path added (`process/preflight-skill-baseline-2026-08-31.md`) — ToeicBuddy
- process(skills): authoring rules for behaviour-shaping skills added to `CLAUDE.md` "Adding new skills" — baseline-test like an instrument, prohibitions vs recipes by failure type, denominators on completion criteria, no cached copies of another project's environment
- new(design): branding interview can borrow the public ui-ux-pro-max-skill style/palette/typography database as ideation input when the client has no brand — data only, never its CSS-framework implementation guidance (`design-artifacts.md` Step 0b)
- process(leak-guard): CI leak-guard step no longer hard-fails without a denylist — generic probes (emails, GUIDs, local paths) still gate every PR; the client-name check is the maintainer's personal local hook (`bin/install-hooks.sh` + gitignored `.leakguard-deny`), not a contributor requirement
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
