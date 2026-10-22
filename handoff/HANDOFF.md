# Handoff: merge desk, 2026-10-15 evening

Branch `claude/doctor-script-tool-install-qgjd5i` carries this file and the 1.0 release-notes draft
(`handoff/RELEASE-NOTES-1.0.md`, `handoff/NOTES-SOURCES.md`). **Do not merge this branch to master.**
All code work is already on master or on its own PR branch.

## What landed today (all squash-merged via PR, CI green, independent review)
#385 (night batch, 18 PRs), #388 Impact block, #389 behaviour suite, #391 trigger rewrites,
#392 + #393 rule dedupe, #394 authoring audit, #395 ranked bug-lookup, #396 `sync-project --only-bin`,
#341 #345 #342 #346 #344 #347 (decomposition pipeline, #293 closed), #374 mxpatch.

## Open, and what each needs

| PR / item | State | Next step |
|---|---|---|
| #384 exec-on-copy (draft) | Review MERGE | Maintainer Mac re-time (`cp -c` path + Ctrl-C recovery) and "ok size" (573 lines). Then merge master in, mark ready, merge. |
| #379 lock reap (draft) | Review MERGE; master merged in; head `9139841` | Maintainer runs `bash tests/wave2/bench-lock-race.sh` and `--old` on Git Bash. Then ready + merge. |
| #387 CarlesZ multilingual (fork) | Both review fixes verified in `2d9a6ba`; no conflicts | Maintainer approves fork CI, says "go 387". Closes #386. |
| #375 | HOLD | Design decision: (a) tamper-evident only, (b) CODEOWNERS + branch protection, (c) park. |
| #311, #333 | HOLD | Each needs a field run on a real project. |
| #273 | MERGE pending | Maintainer client-name check. |
| 18 issues already fixed on master | Not closed | Maintainer says "close the 18": #286 #285 #284 #282 #280 #278 #263 #261 #245 #236 #188 #171 #170 #168 #157 #69 #68 #297. |
| #390 field report | Open | Close once #384 lands (#396 and #374 cover the rest). |
| 243 stale remote branches | Not deleted | Maintainer runs the delete command on the Mac and enables "Automatically delete head branches". |
| 1.0 release | Draft notes here | After #384: prune the draft's "if merged" lines, decide whether it replaces or merges into `docs/releases/v1.0.md` (#334), Thanks names, then the maintainer runs `bin/cut-release.sh` and pushes the tag; then create the GitHub Release. |

## How merges are done here (the rules that bit us)
- PRs only; never push to master. Squash-merge with the full 40-char head SHA, only after green CI
  and an independent review by a fresh agent. Put the review text in the squash message.
- Each merge makes the other PRs conflict in CHANGELOG.md (GitHub has no union merge). Fix: in a
  scratch **worktree**, `git merge origin/master`, keep both sides of CHANGELOG hunks, run
  `bin/render-routing.sh --check` + `bin/check-pr-discipline.sh origin/master`, push. Any non-CHANGELOG
  conflict: resolve by hand and say what you kept.
- Never rebase, amend, force-push, `git stash`, `git add -A`, or `git checkout` in the shared clone.
  Commit with `git commit -F msg -- <paths>`.
- Drafts are marked ready via `POST repos/<o>/<r>/pulls/<n>/ccr/ready_for_review` (no GraphQL here).
- Scoped tests only; never the full suite unless the maintainer asks in that message.
- PR bodies need the five-row Impact block (RELEASE-PROCESS §4a); behaviour A/B for baseline-routed
  text and agent stubs.
- Client data: never read any path under the home directory except the toolkit clone and public
  mxcli test data. Whole-word grep added lines for client names before every merge. The leak guard:
  `LEAKGUARD_ALLOW_NO_DENYLIST=1 bin/check-no-client-data.sh`.
- Auto mode blocks bulk issue closes, branch deletes and unattended merge chains: do those one at a
  time or hand them to the maintainer.

## Follow-ups noted, not built
- Scorer: count `CLOSE_PAGE` crumbs and the `Folder:` property (`tests/behaviour/score.sh`).
- `render-routing --check` does not count routing words inside agent stubs.
- Architect mirror missing workflow rule row 12.
- `exec.sh --patch`: require `--expect-paths`.
- Bigger labelled no-CE no-match set for `bin/bug-lookup.sh`.
- Existing projects never regenerate completed agent stubs, so they miss the stub-diet savings.
- `.mpr-snapshots/` missing from the `.gitignore` that `init-project.sh` writes.

> **Newer handoff:** see `handoff/2026-10-22/HANDOFF.md`.
