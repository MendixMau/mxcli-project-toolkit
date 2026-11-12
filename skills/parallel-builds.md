# Parallel builds in git worktrees

**Optional, advanced reference, used only when the user asks for it. The default stays one writer per `.mpr` (`dispatching.md`); the pipeline does not call this skill.**

**Applies to:** any mxcli project where two or more builders (more than one agent building on the same repo) change the SAME app on separate branches at the same time. Opt-in.
**Purpose:** run N builders in N worktrees and bring their branches together without losing model units. Default stays one writer per `.mpr` (`dispatching.md`); here every worktree has its own `.mpr`, so still one writer each.

**Status: EXPERIMENTAL. Two evidence tiers, marked on each rule.**
- **Tier A, reproduced here** (mxcli v0.28, Mendix 11.13, 2026-11-11, fictional two-module app, 7 units on the lost side): plain-merge failure, script replay, check order, ports and disk.
- **Tier B, field-tested by the maintainer with mxcli v0.30+, not reproduced here:** the `mxcli git merge` path, review file, rerun marks, isolation rewiring, commit discipline.
- **Nobody has proven:** more than two branches under this text; the merge command on a model with orphans; the app size where parallel page authors beat serial (25 min against 16 serial, private copy per author). Team Server push after a merge: unverified.

## 1. Set up

1. **One builder = one worktree = one branch**, cut from the line it merges into, never from another branch (B). *Fails when:* a branch cut from a branch drags that branch's unreviewed model into the merge. Worktree branches are not pushed. Never open a worktree in Studio Pro: a branch with no upstream does not open (B).
2. **Ports and database.** Per worktree an app port, admin port, `--serve-port` (mxbuild) and its own database (`--db-type hsqldb`, or a separate Postgres database; only hsqldb was run here). Never the defaults 8080, 8090, 6543, nor the line's own ports (general practice; only 6543 was observed here). Record them in a ledger in `PROJECT.md` (this skill's suggestion). *Fails when:* builder B's `run --local` on default ports stops builder A's app, or both write one database. Copy the untracked `mxcli` binary into each fresh worktree.
3. **Isolation (B).** Rewire every constant whose default is a local URL: own apps to own ports, anything else to a closed port. List them and check where each points before the first start. Gap: no checked way to list local-URL constants is known here. `bin/constants-audit.sh` (installed from `project-bin/`) classifies every constant without printing a value, but it does not show URLs. `mxcli constant list` prints resolved values and masks only machine-store ones, and `show constants` prints defaults, so treat both like `describe constant` (`skills/learned-constants-and-secrets.md`): run neither on a model whose constants may hold a credential. *Fails when:* a hand-written start script missed two base-URL constants and the worktree app called the demo apps.
4. **Disk.** A built worktree is about 400 MB (A). Keep a handful of built worktrees; clear `deployment/` of stopped ones. *Fails when:* disk ran out with about 20 (B).
5. **Script number block per branch (B).** The brief names it; else the next free hundred above the highest number on the line. *Fails when:* two merge scripts both numbered 81.
6. **Owners.** One for shared parts (navigation, security, theme), one for cross-page flows and the shell (A; failure: a list does not refresh after another page's popup submit).

Done when: N worktrees, N ledger rows, 0 shared ports, 0 local-URL constants left unchecked, N distinct number blocks, 1 owner each for shared parts and cross-page flows.

## 2. Build

- Every model change goes through a numbered script run by `./bin/exec.sh`. A Studio Pro edit cannot be replayed.
- **Rerun mark (B).** Line 2 of every script, after `mdl 1;`: `-- rerun: ok (why)` or `-- rerun: once (why)`. Check: exec the script, then `./bin/idempotence-check.sh <script.mdl>` (one `mxcli diff`; PASS means a second run writes nothing). A script the check refuses is `rerun: once`. *Fails when:* an unmarked script is replayed and writes twice.
- A script must not REPLACE a whole shared unit (A). `create or modify navigation` in branch B silently dropped branch A's menu item and the gate stayed green. `alter navigation insert` was not rerun-safe on v0.28.
- Tests name the worktree's ports explicitly (B).
- **Commits: explicit paths only (B).** `mxcli git commit` (v0.30+) stages everything in the checkout, so screenshots and run logs ride along (failure: 39 stray files). Commit only the model (`.mpr`, `mprcontents/`), `mdlsource/` and the review folder.

## 3. Review before merge (B)

A local review file per branch, committed on the branch: what changed per app, the gate results, and `Decision: merge | changes | drop` with who and why. No merge without it. *Fails when:* a branch merges on the builder's say-so and nobody read the units.

## 4. Merge

Never a plain `git merge` of the model (A; section 5 shows what it does).

**On every merge, either path, one at a time:** commit work; create the rollback tag on the line first (`git tag pre-merge-<date>`); merge; section 5; the model check; the full gates on the line; then the next branch. Recovery: fallback path → check out the target and delete the merge branch; merge-command path (it merges ON the line) → cut a fresh branch from the rollback tag and continue there, never a hard reset of the line. The line keeps the bad merge until the maintainer decides; nothing is reset.

**First choice: `mxcli git --help` lists `merge` (v0.30+, B).** Merge through `mxcli git merge`. One app per run is what #744 reports for the command; a repo with two apps changed on both sides needs one run per app (no recipe proven here).

Outcomes as reported by the maintainer's wrapper (B); the bare command's exit codes are not in #744 — read `mxcli git merge --help`. Preconditions below (line checked out and clean, a review decision) are the wrapper's.

| Result | Do |
|---|---|
| merged, model check passes | section 5 (orphan check, module count), then the full gates on the line |
| refused (no review decision, line dirty or not checked out) | fix what it names |
| units left open | read the engine's report, fill the merge plan, re-run with the plan; never pick ours/theirs without reading the units |
| merged, model check has errors | fix on the line with one MDL script, or check out a fresh branch from the rollback tag |
| text-file conflict after an aborted run | resolve, stage those files explicitly, commit |

**Same name added on both sides (B).** Two builders each creating a folder with the same name merge cleanly, then the model check fails with CE0081. After merging, check for duplicates; fix by moving the documents out, dropping both, moving them into one.

**Second choice: v0.28, or no `merge` command. Scripts are the merge source (A, worked once, two modules).** **STOP unless** every branch script is marked `rerun: ok` and verified, every model change went through a script, and the number blocks do not overlap. *Fails when:* any of those is false (B): in a field run, replaying a module from its scripts failed and had to be undone.
1. Commit uncommitted work on the target; `git tag pre-merge-<date>` on it (as above).
2. Attempt on a fresh branch cut from the tag; the target stays untouched.
3. Take branch A's model wholesale: `git merge --ff-only <branch-a>`. If `--ff-only` refuses, nothing changed: delete the merge branch, recut the worktrees from the target's head, or take the other branch as A.
4. From branch B only its scripts: `git checkout <branch-b> -- mdlsource/<its files>`; never its `.mpr` or `mprcontents/`. Commit.
5. Replay in number order through `exec.sh --commit-first` (without it the second script stops on "uncommitted model changes"). A failing script: check out the target, `git branch -D <merge-branch>`, fix it on its own branch.
6. Section 5. Pass: `git checkout <target>; git merge --ff-only <merge-branch>`.

**Third: Studio Pro** "Merge Changes Here", a person at the screen. `mx merge` leaves CE0137 on any unit changed on both sides; clearing it needs Studio Pro (A).

## 5. Check after every merge, in this order (A)

1. `mxcli fix hashes -p <app>.mpr` exits 0 with 0 orphan and 0 missing. Capture: `tests/wave2/fixtures/worktree-merge/`. A plain merge that takes one side of the `.mpr` conflict leaves the other branch's units on disk, unregistered: the module vanishes while `mx check` and the mxbuild gate report 0 errors. On ORPHAN lines do NOT run the `mxcli diag --check-units --fix` that the output suggests: it deletes the unregistered files, which are the lost module. Recover as in section 4 ("On every merge").
2. `mxcli show modules -p <app>.mpr` lists N of N modules.
3. Shared units by eye: menu items N of N, each branch's role assignments present.
4. Then the build gate. The gates alone are blind to orphans: *fails when* step 4 runs first and its green is read as proof.

## 6. Never

- `mxcli diag --check-units --fix` on a suspect merge: it deletes unindexed files, which is the lost module.
- `git add -A`, or an unscoped `mxcli git commit`.
- Team Server push after a merge: the field needed an extra step (the settings unit's ContentsHash, #741 item 7) that `teamserver-alignment.md` does not cover; unverified here.

A wrapper that automates these rules may come later; the rules stand without it.

**Done when:** N of N branches merged, each with a written `Decision: merge`; `fix hashes` exit 0; N of N modules listed; shared units checked by eye; 0 duplicate names; build gate 0 errors; full gates on the line passed; rollback tag still present; ledger rows released.
