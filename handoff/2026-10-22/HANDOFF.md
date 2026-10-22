# Handoff: merge desk, 2026-10-22

Start a new session by reading this file. **Do not merge this branch to master**; it only carries
notes and research. All code is on master or on its own PR branch.

## Where everything lives

| What | Where |
|---|---|
| Shipped work | `master`, 13 squash merges since the 1.0 tag `v2026.10.19`; each has a CHANGELOG line under `## Unreleased` |
| Open work | GitHub PRs and issues (lists below) |
| Research and the proposal for #506/#507/#508 | this folder: `research/`, `proposal-loop/` |
| The draft wireframe-first skill, for hand testing | branch `try/propose-before-build` (one file, unrouted, no PR) |
| Merge-desk rules | `CLAUDE.md` (repo), plus the rules section below |

## Merged 2026-10-21 (all CI green, independent review)

#497 lint gate (#496) · #501 verify-module + HARNESS evidence (#446) · #500 macOS sed (#488) ·
#499 one project root, multi-app pick (#489) · #498 restatement guard (#269) ·
#503 stale-DESCRIBE warning + preflight row 21 (#261; behaviour A/B passed, 66 reps) ·
#526 HARNESS rows become one sign-off status per module.

## Waiting on the maintainer

- Cut the release: `bin/cut-release.sh`, then `git push origin master --tags`.
- Close #311 (replaced by #498 + #503).
- Mac check for #500: `bash bin/bug-lookup.sh --index | grep -c .` prints 222.
- Drafts: #384 (Mac timing, size OK, conflicts with today's exec.sh), #379 (Git Bash run, conflicts),
  #375 (design decision + split), #333 (field run).
- Field runs on a real project for everything merged since 1.0.

## Paused until tested: #506, #507, #508

- `proposal-loop/PROPOSAL.md`: why/how/where, options, cost, and the 12-rep trial results
  (with the skill: change 3/3 asked once and stopped, nit 3/3 silent, 0 new HTML files).
  Re-run the trial from a folder with no project `CLAUDE.md` before trusting the numbers.
- Three decisions for the maintainer: ask on small typed visible changes? `Display: artifact`
  consent by typed line or by question? keep wireframes current after build?
- Hand test: `git worktree add ~/Mendix/toolkit-try origin/try/propose-before-build`, set
  `Proposals: batch` in a test project, tell the session to read the skill, try one visible change
  and one nit in Claude Code desktop, web, VS Code and Codex.
- #508 parked, narrowed to a change view. Prototype: `research/model-viz/` (public mxcli test
  models only).
- #506's guide-marker bug (sentinel written when nothing opened) is real and still unfixed.

## Follow-up issues filed 2026-10-21

#502 (#446 leftovers) · #504 (ledger misses git pull) · #505 (gate-log fixture flake, on master too) ·
#506 · #507 · #508.

## Merge-desk rules (keep)

- PRs only, squash with the full head SHA, after green CI and an independent review; the review
  text goes in the squash message. Never rebase, force-push or `git add -A` in the shared clone;
  use worktrees and `git commit -F msg -- <paths>`.
- A PR changing always-loaded text or an agent stub needs the behaviour A/B (`tests/behaviour/`).
- Performance is a hard condition: no extra mxcli/mxbuild calls on the happy path.
- Scoped tests only; never the full suite unless the maintainer asks.
- Never read or use client projects as evidence. Grep added lines for client names before merge.
- Merging one PR usually conflicts the next on CHANGELOG: merge master into the PR branch and
  keep both sides.
