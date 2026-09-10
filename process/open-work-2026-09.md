# Open work — toolkit field review, September 2026

Parked 2026-09-10, reconciled against `master` the same day. Between the review session and this
file, other sessions merged the review branch into master, filed most of the upstream drafts
(mendixlabs/mxcli #1023–#1037, #1067–#1071, #1076), made the baseline budget advisory, gave
`status.sh --no-html`, and merged PRs #11–#35. So the list below is what is genuinely still open.
Strike a row when it lands; do not let this file become a second changelog (`CHANGELOG.md` is).
The review itself, with the evidence, is the "Toolkit Field Review" page (Claude artifact).

## Waiting on a person

| # | Item | Owner | Next step |
|---|---|---|---|
| 1 | **File the 8 drafts still marked NOT YET FILED** in `bug-logs/pending-github-issues/`: BUG-100 (Compose project name), BUG-102 (DataGrid `SET DataSource` no-op), BUG-104 (quoted `$Param`), BUG-106 (burned widget names), BUG-115 (file manager widget), `create-association-corrupts-mpr` (held back as not filing-ready — needs a fresh repro on v0.20), `exec-non-transactional-silent-skip`, `feature-mxcli-doctor`. | Maurits (only account with access) | `bash bug-logs/pending-github-issues/render-paste-ready.sh` renders them paste-ready again; write each URL back into the draft's Status line. |
| 2 | **Pilot 2: a real greenfield app in a Claude Code container**, on master. Three things to report back: where the agent skipped a step anyway, where `status.sh` named the wrong next action, how long exec and the look really took. | Maurits | Order: `doctor.sh --install --yes` → `mxcli new --output-dir ./app` → `init-project.sh` → skeleton → look after every page script. |
| 3 | **Mac + devcontainer field run** of the September instruments (proven on Linux only). macOS has no `timeout`, so `doctor --quick` falls back to the ~14 s probe; the exec doctor hook, `status.sh` and the skeleton are untested there. | Maurits, "another time" | Run `doctor.sh --quick <project>` and `status.sh <project>` on the Mac, paste both. |
| 4 | **PR #2 in this repo** (Mac-local divergence). Its two unique commits were salvaged on 2026-09-08 (`fd60fb8`), so it may now be closable. | Maurits (needs the Mac) | Confirm `372e2ac`/`8b5a8bb` content is on master, close PR #2, reset the Mac's local master. |

## Review items not started (in the order the review proposed)

| # | Item | Size | Notes |
|---|---|---|---|
| 5 | **Page archetype templates + fidelity as a refusing gate in `exec.sh`** (review item 3). Overview / detail / edit / dashboard / task MDL templates derived from the StyleGallery; `exec.sh` runs `check-page-shell.sh` + `page-fidelity.js` on page scripts and refuses under 80% unless `--stub`; Stage 3 exits only when every wireframe class exists in the theme. | 3 days | Separate files from anything a project touches; can run beside pilot 2. |
| 6 | **Inline-at-dispatch for baseline skills** (review item 2b). One mechanism in the agent stubs that pastes the trigger skill's text into the dispatch, the way `ui-preflight-pages.md` demands — the A/B showed 0/5 vs 5/5. | 2 days | Rewrites the rendered agent files; coordinate with routing renders. Depends on #7. |
| 7 | **Plugin vs `git pull` as the delivery mechanism** (personal-toolkit `TOOLKIT-UPGRADE-PLAN.md` §2a). A 5-minute symlink experiment decides it and has not been run. | ½ day | Decide before #6. |
| 8 | **Announce-before-act template and the five-line recommendation shape** in the agent stubs (review item 5, second half; `status.sh` covered the first half). | 1 day | Stubs only. |
| 9 | **Curate the baseline tier so the budget can block again.** The ratchet went advisory (2026-09-08) because two of the five largest baseline entries are scripts an agent runs, not reads, and ordinary edits tripped it. Decide what counts, then set `MXTK_BASELINE_BUDGET_STRICT=1` in CI. | ½ day | `bin/render-routing.sh` header has the history. |

## Small defects found during pilot 1, not fixed

| # | Item | Where |
|---|---|---|
| 10 | `exec.sh` pre-flight baseline prints `Model ALREADY has ? error(s) [?]` when its errors file cannot be read (seen while `run --local --watch` held a build). Should say "baseline unreadable", not a count. | `project-bin/exec.sh` pre-flight block |
| 11 | `page-fidelity.js` scores the wireframe's own `bind` annotation class as a missing page class (71% on a page that matched its wireframe). Known scorer defect, re-confirmed. | `project-bin/page-fidelity.js` |
| 12 | `exec.sh` ends with "Studio Pro needs a restart" on a headless container; `doctor.sh` on the cloud lane says Docker is needed for screenshots though `run --local` + Playwright does it. Both messages should be lane-aware. | `project-bin/exec.sh`, `bin/doctor.sh` |
| 13 | `mxcli run --local` did **not** collapse the split model on pilot 1 (v0.20.0, Mendix 11.13.0, 5 runs, `git status` clean). The CRITICAL ledger entry says it does. Not a retraction — one machine, one version — but the entry should carry the observation and the command that would falsify it. | `bug-logs/mxcli-bugs.md` |
| 14 | `gate-check.sh` on a large stale checkout takes 55 s (obligation forks); `status.sh` inherits it. 2 s on a small project. A `--fast` path for the status read would help. | `bin/gate-check.sh` |

## Upstream proposals drafted, not sent

`feature-mxcli-doctor` is in #1. The page archetype skill pack (#5) is a candidate for an mxcli skill pack once it has worked here.
