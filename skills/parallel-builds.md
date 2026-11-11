# Parallel builds in git worktrees

**Applies to:** any mxcli project where two or more builders change the SAME app on separate branches at the same time. On-demand.
**Purpose:** run N builders in N worktrees and bring their branches together without losing model units. Default stays one writer per `.mpr` (`dispatching.md`); here every worktree has its own `.mpr`, so still one writer each.

**Status: EXPERIMENTAL.** Field-tested once: mxcli v0.28.0, Mendix 11.13.0, 2026-11-11, on a fictional two-module app (7 units on the lost side). Unproven: more than two branches; the 63-unit loss itself; `mx git-merge` in a repo; a Team Server push after a merge; the app size where parallel authors beat serial (private copy per author: 25 min against 16 serial; 40 without, `dispatching.md`).

## 1. When, and when not

Use it when branches must run side by side for days; not for a small app. Parallel authors gained no speed (figures above), only 5 integration defects against 7.

## 2. Set up

1. One worktree and one branch per builder from one base commit.
2. Copy the untracked `mxcli` binary into each fresh worktree; `exec.sh` works unchanged.
3. Port ledger in `PROJECT.md`: per worktree an app port, admin port, `--serve-port` (mxbuild) and `--db-type hsqldb`. Never defaults 8080, 8090, 6543. *Fails when:* builder B's `run --local` on the default ports stops builder A's app, or both write one database. A running app costs about 0.5 GB and boots in 28 s; a built worktree is about 400 MB.
4. One script number block per branch (A 20-29, B 30-39, merge scripts 90 up).
5. Name one owner for shared parts (navigation, security, theme) and one for cross-page flows and the shell (failure: a list does not refresh after another page's popup submit).

Done when: N worktrees, N ledger rows, 0 shared ports, N distinct number blocks, 1 owner each for shared parts and cross-page flows.

## 3. While building

- Every model change goes through a numbered script run by `./bin/exec.sh`, passing `./bin/idempotence-check.sh`. A Studio Pro edit cannot be replayed.
- A script must not REPLACE a whole shared unit. `create or modify navigation` in branch B silently dropped branch A's menu item and the gate stayed green. Shared units are additive or owned. `alter navigation insert` is not rerun-safe on v0.28.
- Page authors on private copies replay their page scripts into the main app in order, shared parts first.

## 4. Merge

Never a plain `git merge` of the model (the bundled `teamserver-git` skill agrees). Taking one side of the `.mpr` conflict leaves the other branch's units on disk, unregistered: the module vanishes while `mx check` and the mxbuild gate report 0 errors.

Pick the path (one app per run):

1. `mxcli git --help`: v0.28 has only `note`; a newer `merge` is unverified here. If present, prefer it and still run section 5.
2. **Scripts are the merge source** (worked once, two modules). Preconditions: every change went through a script, every script is rerun-safe, number blocks do not overlap; else stop. Steps as run:
   1. Commit any uncommitted work on the target; `git tag pre-merge-<date>` on it, immediately before the attempt.
   2. Attempt on a fresh branch cut from the tag; the target stays untouched.
   3. Take branch A's model wholesale: `git merge --ff-only <branch-a>`. If `--ff-only` refuses (branch A is not ahead of the target), nothing changed: delete the merge branch and either cut the worktrees again from the target's current head or take the other branch's model as A.
   4. From branch B only its scripts: `git checkout <branch-b> -- mdlsource/<its files>`; never its `.mpr` or `mprcontents/`. Commit.
   5. Replay in number order through `exec.sh`, `--commit-first` between scripts (without it the second script stops on "uncommitted model changes"). A failing or not rerun-safe script: stop, check out the target, then `git branch -D <merge-branch>`; fix the script on its own branch.
   6. Section 5. Pass: `git checkout <target>; git merge --ff-only <merge-branch>`.

   On ORPHAN lines never run `mxcli diag --check-units --fix` (section 6). Check out the target and delete the merge branch.
3. **Studio Pro** "Merge Changes Here", a person at the screen. `mx merge` leaves CE0137 on any unit changed on both sides; clearing it needs Studio Pro.

Merge scripts for units both sides touched (menu, role assignments) take numbers in the 90 block.

## 5. Check after every merge, in this order

1. `mxcli fix hashes -p <app>.mpr` exits 0 with 0 orphan and 0 missing. The failure capture is `tests/wave2/fixtures/worktree-merge/`: exit 1, 7 orphans named. On ORPHAN lines do NOT run the `mxcli diag --check-units --fix` that the output suggests: it deletes the unregistered files, which are the lost module (section 6). Check out the target and delete the merge branch.
2. `mxcli show modules -p <app>.mpr` lists N of N modules.
3. Menu items N of N, each branch's role assignments present.
4. Then the `exec.sh` build gate.
5. Write any journey after the app is up, not before (a journey written blind failed on assumptions about captions and rows).
*Fails when:* step 4 runs first and its green is read as proof.

On a failure, check out the target, then `git branch -D <merge-branch>` (the target never moved) and take another path.

## 6. Never

`mxcli diag --check-units --fix` on a suspect merge: it deletes unindexed files, which is the lost module.

Team Server push after a merge: `teamserver-alignment.md`.

**Done when:** N of N branches merged; `fix hashes` exit 0; N of N modules listed; menu and role assignments checked by eye; build gate 0 errors; rollback tag still present, target not moved before the check passed; ledger rows released.
