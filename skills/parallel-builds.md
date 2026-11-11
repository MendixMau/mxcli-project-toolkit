# Parallel builds in git worktrees

**Applies to:** any mxcli project where two or more builders change the SAME app on separate branches at the same time. On-demand.
**Purpose:** run N builders in N worktrees and bring their branches together without losing model units. The default stays one writer per `.mpr` (`dispatching.md`, which also covers who may run in parallel without touching the model); this is the advanced path where every worktree has its own `.mpr` and so still has one writer.

**Status: EXPERIMENTAL.** Field-tested once: mxcli v0.28.0, Mendix 11.13.0, 2026-11-11, on a fictional two-module app (7 units on the lost side). Unproven: more than two branches; the original field run's 63-unit loss itself; `mx git-merge` inside a repo; a Team Server push after such a merge; the app size where parallel page authors beat serial (on a 4-page app they took 25 min against 16 serial).

## 1. When, and when not

Use it when branches must run side by side for days, or page authors need to look at their own page. Do not use it for a small app: serial finishes sooner. Parallel authors gained no speed, only 5 integration defects against 7.
*Fails when:* the lead splits a 4-page app four ways and spends the saved time merging.

## 2. Set up

1. One worktree and one branch per builder from one base commit; then `git tag pre-merge-<date>` on the target branch.
2. Copy the untracked `mxcli` binary into each fresh worktree. `exec.sh` itself works unchanged there.
3. Port ledger in `PROJECT.md`: per worktree an app port, admin port, `--serve-port` (mxbuild) and `--db-type hsqldb`. Never the defaults 8080, 8090, 6543. A running app costs about 0.5 GB and boots in 28 s; a built worktree is about 400 MB.
   *Fails when:* B's `run --local` stops A's app, or both write one database.
4. One script number block per branch (A 20-29, B 30-39, merge scripts 90 up).
5. Name one owner for shared parts (navigation, security, theme) and one for cross-page flows and the shell.
   *Fails when:* a list does not refresh after another page's popup submit and no author owned that flow.

Done when: N worktrees, N ledger rows, 0 shared ports, N distinct number blocks, 1 owner each for shared parts and cross-page flows, 1 rollback tag.

## 3. While building

- Every model change goes through a numbered script run by `./bin/exec.sh`, passing `./bin/idempotence-check.sh`. A Studio Pro edit cannot be replayed.
- A script must not REPLACE a whole shared unit. `create or modify navigation` in branch B silently dropped branch A's menu item and the gate stayed green. Shared units are additive or owned. `alter navigation insert` is not rerun-safe on v0.28.
- Page authors on private copies replay their page scripts into the main app in order. The shared parts they use go first. Write the journey after the app is up.

## 4. Merge

Never a plain `git merge` of the model. It conflicts on the `.mpr` unit index; taking one side leaves the other branch's units on disk, unregistered, so the module vanishes while `mx check` and the `exec.sh` mxbuild gate both report 0 errors.

Pick the path (one app per run):

1. Run `mxcli git --help`. v0.28 has only `note`; a newer CLI may offer `merge`, unverified here. If it exists, prefer it and still run section 5.
2. **Scripts are the merge source** (worked once, two modules). Check out the target at the rollback tag, then replay the other branch's scripts in number order through `exec.sh --commit-first`. Preconditions, all three: every change went through a script, every script is rerun-safe, number blocks do not overlap. If one is false, stop.
3. **Studio Pro** "Merge Changes Here", a person at the screen. `mx merge BASE MINE THEIRS` auto-merges units changed on one side but leaves CE0137 on any unit changed on both, and clearing it needs Studio Pro. Not hands-off.

Merge scripts for units both sides touched (menu, role assignments) take numbers in the 90 block.
*Fails when:* back-to-back runs without `--commit-first` stop at "uncommitted model changes".

## 5. Check after every merge, in this order

1. `mxcli fix hashes -p <app>.mpr` exits 0 with 0 orphan and 0 missing. The failure capture is `tests/wave2/fixtures/worktree-merge/`: exit 1, 7 orphans named.
2. `mxcli show modules -p <app>.mpr` lists N of N modules.
3. Shared units by eye: menu items N of N, each branch's role assignments present.
4. Then the `exec.sh` build gate.
*Fails when:* step 4 runs first and its green is read as proof.

On a failure, `git reset --hard pre-merge-<date>` and take another path.

## 6. Never

`mxcli diag --check-units --fix` on a suspect merge: it deletes unindexed files, which is the lost module. The `fix hashes` output itself suggests it.

Team Server push after a merge: `teamserver-alignment.md`; do not restate it here.

**Done when:** N of N branches merged; `fix hashes` exit 0; N of N modules listed; menu and role assignments checked by eye; build gate 0 errors; rollback tag still present; ledger rows released.
