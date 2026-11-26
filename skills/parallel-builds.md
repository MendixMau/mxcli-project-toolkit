# Parallel builds in git worktrees

**Optional, advanced reference: offered at Stage 4 when the build plan shows it pays (`brd-to-build-plan.md` Step 4c), or used when the user asks. The default stays one writer per `.mpr` (`dispatching.md`).**

**Applies to:** any mxcli project where two or more builders (more than one agent building on the same repo) change the SAME app on separate branches at the same time. Opt-in.
**Purpose:** run N builders in N worktrees and bring their branches together without losing model units. Default stays one writer per `.mpr` (`dispatching.md`); here every worktree has its own `.mpr`, so still one writer each.

**Status: EXPERIMENTAL. Two evidence tiers, marked on each rule.**
- **Tier A, reproduced here** (mxcli v0.28, Mendix 11.13, 2026-11-11, fictional two-module app, 7 units on the lost side): plain-merge failure, script replay, check order, ports and disk.
- **Tier A, cloud run** (2026-11-25, #845: Linux container, no Studio Pro, mxcli upstream `7ec3d1c` ≈ v0.33, Mendix 11.13.0 and 11.12.2, blank apps): the `mxcli git merge` path (§4), its exit codes, which shared-unit changes stop for a decision and the `--plan` + replay remedy (§4), the engine-version trap (§4), cloud sessions (§7).
- **Tier B, field-tested by the maintainer with mxcli v0.30+, not reproduced here:** review file, rerun marks, isolation rewiring, commit discipline.
- **Nobody has proven:** more than two branches under this text; two apps in one repo; branches built in two separate cloud sessions; the merge command on a model with orphans; mxcli v0.30–0.32 specifically; the app size where parallel page authors beat serial (25 min against 16 serial, private copy per author). Team Server push after a merge: unverified.

## 0. Decide first

1. **Parallel or sequential.** Stories that each add or change their **own** modules: parallel is safe. Stories that both change a **shared unit** (navigation, security, menu bar, one entity's attributes): the merge stops for a decision even when the edits do not overlap (§4) — parallel only with a named owner and every shared-unit change in a script; otherwise sequential. Two stories changing the same document: sequential.
2. **Merge path.** `mxcli --version` ≥ 0.30 and `mxcli git --help` lists `merge`: §4 first choice. Below that: §4 second choice, or stay sequential.
3. **Where each branch is built.** Worktrees on one machine (§1) or one cloud session per branch (§7). The merge rules are the same.

Done when: the user has confirmed parallel or sequential, the merge path is named, and each shared unit has one owner.

## 1. Set up

1. **One builder = one worktree = one branch**, cut from the line it merges into, never from another branch (B). *Fails when:* a branch cut from a branch drags that branch's unreviewed model into the merge. Worktree branches are not pushed. Never open a worktree in Studio Pro: a branch with no upstream does not open (B).
2. **Ports and database.** Per worktree an app port, admin port, `--serve-port` (mxbuild) and its own database (`--db-type hsqldb`, or a separate Postgres database; only hsqldb was run here). Never the defaults 8080, 8090, 6543, nor the line's own ports (general practice; only 6543 was observed here). Record them in a ledger in `PROJECT.md` (this skill's suggestion). *Fails when:* builder B's `run --local` on default ports stops builder A's app, or both write one database. Copy the untracked `mxcli` binary into each fresh worktree.
3. **Isolation (B).** Rewire every constant whose default is a local URL: own apps to own ports, anything else to a closed port. List them and check where each points before the first start. Gap: no checked way to list local-URL constants is known here. `bin/constants-audit.sh` (installed from `project-bin/`) classifies every constant without printing a value, but it does not show URLs. `mxcli constant list` prints resolved values and masks only machine-store ones, and `show constants` prints defaults, so treat both like `describe constant` (`skills/learned-constants-and-secrets.md`): run neither on a model whose constants may hold a credential. *Fails when:* a hand-written start script missed two base-URL constants and the worktree app called the demo apps.
4. **Disk.** A built worktree is about 400 MB (A). Keep a handful of built worktrees; clear `deployment/` of stopped ones. *Fails when:* disk ran out with about 20 (B).
5. **Script number block per branch (B).** The brief names it; else the next free hundred above the highest number on the line. *Fails when:* two merge scripts both numbered 81.
6. **Owners.** One for shared parts (navigation, security, theme), one for cross-page flows and the shell (A; failure: a list does not refresh after another page's popup submit).
7. **Before cutting branches, once on the line:** `mxcli fix property-sets -p <app>.mpr` and commit it alone, when any document was written by mxcli before 0.26 — otherwise the merge engine throws "do not have the same properties" on those documents (mxcli's `docs-site/src/tools/outside-studio-pro.md`; not reproduced here).

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

**First choice: `mxcli git --help` lists `merge` (v0.30+, B; reproduced on v0.32 and ≈v0.33, A).** Merge through `mxcli git merge <branch> -p <app>.mpr`. One app per run (`-p` takes one model); a repo with two apps changed on both sides needs one run per app (no recipe proven here). Refused while Studio Pro has the model open.

**Engine version first (A, cloud run).** The command runs Studio Pro's merge engine (`mx merge`) of the version it finds, and up to at least `7ec3d1c` it takes **any** version: an `mx` on PATH, then any cached one. *Fails when:* an 11.12.2 project merged with only 11.13.0 cached — exit 0, merge committed, the project silently upgraded to 11.13.0 (`_ProductVersion`), while the log said "with mx 11.12.2". So before every merge: `mxcli setup mxbuild --version <project version>`, no other `mx` on PATH; after it, the project version is unchanged (`mxcli -p <app>.mpr -c "show version"` or the `.mpr`'s `_MetaData`). A fixed mxcli refuses the mismatch (fix on its way upstream).

Exit codes (v0.32+, A): **0** merged (or up to date), **1** failed, **3** stopped for a decision (a plan template `<app>.mpr.merge-plan.json` is written, the tree is back to the pre-merge state). Preconditions below (line checked out and clean, a review decision) are the maintainer's wrapper's (B).

| Result | Do |
|---|---|
| merged, model check passes | section 5 (orphan check, module count), then the full gates on the line |
| refused (no review decision, line dirty or not checked out) | fix what it names |
| units left open (exit 3) | read the engine's report, fill the merge plan, re-run with `--plan`; never pick ours/theirs without reading the units |
| merged, model check has errors | fix on the line with one MDL script, or check out a fresh branch from the rollback tag |
| text-file conflict after an aborted run | resolve, stage those files explicitly, commit |

**What stops for a decision (A, cloud run).** Disjoint modules: auto-merged. A different entity added to the same module on each side: auto-merged. The same attribute changed two ways: exit 3, both values shown. A **different** menu item appended to the same navigation profile on each side: **also exit 3**, and the report reads only "Yours: Menu item / Theirs: Menu item". `--plan` takes a unit **whole** from one side, so the other side's item is dropped without a warning. Remedy, proven: `--plan` with one side, then replay the other branch's script for that unit through `exec.sh`, then section 5. *Fails when:* the other side's change was made by hand and has no script — then Studio Pro (third choice) is the only way to keep both.

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

## 7. One cloud session per branch (A for the merge, untested for separate sessions)

Each cloud session builds one branch and pushes it; the merge then runs in **one** place, one branch at a time, per §4–5.

- **The merge can run in a cloud container.** The engine runs on Linux, and `mxcli setup mxbuild --version <project version>` downloads it from the Mendix CDN (cloud run: merge 8 s, full build 66 s). A session that clones an existing repo must run that setup itself; `mxcli new` does it only for new apps.
- **Dead ends without Studio Pro:** a decision that must mix both sides inside one unit, and units added, deleted or moved on both sides. Exit 3 there means: hand the merge to a machine with Studio Pro, or replay one side's scripts (§4).
- **Per session, as §1:** its own branch cut from the line, its own number block, its own ports and database if it runs the app. Never push to the line from a builder session.
- **Unverified:** branches built in two different sessions (the cloud run built both in one); pushing the merged model to Team Server.

## 8. EXPERIMENT: auto when modules split (branch `exp/branch-parallel-auto`)

Runs when the build plan reads `Branch-parallel: auto (experiment)` (`brd-to-build-plan.md`
Step 4c). Its purpose is to **measure** whether branch-parallel pays, so the log is the point.

1. **Before Stage 5:** §1 set-up for each slice: one worktree and branch per slice cut from the
   line, own ports and database, own script-number block, `mxcli` copied in, `bin/exec.sh`
   present. Shared parts (navigation, security, menu bar, seed data) are built **first, on the
   line, by their owner**, before the slices branch off, so no slice writes them.
2. **During Stage 5:** one implementer per slice, dispatched in one message, each told its
   worktree path, ports and number block, and that it applies only through `./bin/exec.sh` in
   that worktree and never touches the line. Each runs its own module gates there.
3. **Merge:** one slice at a time per §4–5, after a review file per §3. A shared-unit stop
   (exit 3) is resolved per §4 ("What stops for a decision") and logged.
4. **Log every run** in `docs/progress/branch-parallel-log.md`, one block per build:
   slices and their row counts; wall-clock start and end per slice; each merge's exit code,
   conflicted units and the resolution; `fix hashes` exit code; module count N of N; the
   project's Mendix version before and after; total wall time against the serial estimate in
   the build plan; anything that broke. Then run `bin/harvest-learnings.sh` at wrap-up so the
   numbers reach the toolkit.

*Fails when:* a slice's implementer applies to the line, or a slice writes a shared unit — the
merge then stops (§4) or, after a plain `git merge`, loses units silently (§5).

Done when: N of N slices merged per the §4–5 done-when, and the log block has every field
above filled or marked `not measured` with the reason.

A wrapper that automates these rules may come later; the rules stand without it.

**Done when:** the §0 decision is recorded; N of N branches merged, each with a written `Decision: merge`; `fix hashes` exit 0; N of N modules listed; shared units checked by eye; 0 duplicate names; build gate 0 errors; full gates on the line passed; the project's Mendix version unchanged; rollback tag still present; ledger rows released.
