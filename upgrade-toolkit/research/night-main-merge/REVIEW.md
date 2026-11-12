# night/2026-10-13 + main: merge review

Branch `night-main-merge` = `origin/night/2026-10-13` (832b6b7e) + `origin/main` (dff00c8c). Merge commit bc956c08.
Main brought 5 commits the night branch did not have: PR 85 (research/seeding), PR 86 (SD-1 seed_snapshot BLOCKS fix
with two controls) and dff00c8c (gh-issues doc). PRs 78 and 79 (the AM fixes) were already in night's base (7aad1de5).

## 1. Conflicts and how they were resolved

| file | resolution | why |
|---|---|---|
| bin/seed_snapshot.py | night's IGNORED regex kept; main's `\|INSERT INTO BLOCKS VALUES` dropped | night (PLM-4, 97537fce) ignores `INSERT INTO (PUBLIC\.)?BLOCKS\b`, which covers main's statement and the schema-qualified form; `\b` keeps `BLOCKSX` UNMAPPED, so main's not-blanket control still holds |
| controls/run-controls.sh | both blocks kept, in order: PLM-4 `seed-snapshot-hsqldb-internals-pass` then SD-1 `seed-snapshot-blocks-bookkeeping-catch` / `-not-blanket-pass` | different names, different temp folders (`$T/snapint`, `$T/snapblocks`); `bash -n` clean; no control name defined twice |
| FEEDBACK.md | every night row plus SD-1 (the only main row night lacked; the 355 rows both sides hold are byte equal); Counts recomputed by the status column | 499 rows, no duplicate id: fixed 294, doc 75, closed 12, won't fix 7, unproved 7, backlog 104, open 0. SD-1's "where" now names the kept regex (same fix as PLM-4) |

BACKLOG.md: no conflict and no clash. Items 1 to 80 each appear once. Main's #28 to #32 (page by URL, update-widgets
reset, release_impact PDS removals, git-history proof for unedited theme files, design-property scan) keep their numbers.
Night's NS-11 item, called "BACKLOG 28" in the message of 8dd23d1a, is #33 in the file, and FEEDBACK row NS-11 says #33.
AM-T6, AM-U10 (#28), AM-U2 (#29), AM-U3 (#30), AM-U9 (#31) and AM-M3 (#32) are unchanged.

Mutation check of the kept regex: with `|INSERT INTO (PUBLIC\.)?BLOCKS\b` removed, all three seed-snapshot BLOCKS
controls go red (hsqldb-internals-pass, blocks-bookkeeping-catch, blocks-not-blanket-pass). Restored: green.

## 2. Scoped controls on the overlap

Regex: `gate-timeout|gate-g-var|toolcheck-|mxversion|mx10-preload|design-props-crash|seturl|timer-listento|visible-widget|landing-guard|runapp-|smokewalk-login|gate-smoke-login|localedits|stepupdate-kept|jardedupe|release-impact|seed-snapshot|setup-`,
run with PLAYWRIGHT_NODE_PATH=/root/mendix-playwright/node_modules, then the same regex on a plain
origin/night/2026-10-13 worktree.

| tree | run | passed | failed | skipped |
|---|---|---|---|---|
| night-main-merge | 320 | 319 | 1 (stepupdate-keptdeps-invalid-catch) | 0 |
| plain night | 318 | 317 | 1 (stepupdate-keptdeps-invalid-catch) | 0 |

The pass/fail lists are the same except the two SD-1 controls, which exist only on the merge and pass there.
stepupdate-keptdeps-invalid-catch fails the same way on both trees (`.stepupdate/keptdeps.txt` missing: it needs an
earlier control's files), so the merge broke nothing. Failures caused by the merge: 0.

Per overlap item (all controls named here ran green):
- gate.sh watchdog: AM-C6 gate-timeout-watchdog-* (4) and gate-timeout-invalid-catch, plus night PV-12 gate-watchdog-warn-once-pass
  (run separately). run_limited runs in the gate's own shell (line 373), so `WD_WARNED` lasts for the whole run.
- rc 139: AM-M1 mx10-preload-* (4), AM-M2 design-props-crash-139-* (2), plus night NR2-15/17 mx10-crash-139-retry-pass,
  -gives-up-catch, mx10-crash-off-streams-catch, mx10-plain-failure-no-retry-pass, mxcli-fix-aborted-retry-pass (run
  separately: 6/6 with the watchdog control). After a retry gives up the rc is still 139, so AM-M2's CRASHED handling still applies.
- jardedupe: AM-U4 jardedupe-sources-* (3) with night PLM-23/24 jardedupe-only-classes-kept-catch, -shadowed-* (3): 14 green.
- release_impact pipes: AM-M5 release-impact-check-pipe-catch / -pass, release-impact-pipe-write-warns green with
  night's MC-15/PV-4/NR1 changes (90 release-impact controls).
- stepupdate kept count: AM-U1 stepupdate-kept-count-skip-catch / -none-pass green.
- toolcheck (13), localedits / themefiles (44), setup- (33), runapp- (44): green.

## 3. The two commits with no control in their own diff

- **71dd0bd4** (convertnoise: theme-cache/** and `_generated-exclusion-variables.scss` are regenerated, MC-4): logic.
  A control exists in a later commit: 7007ad85 added `convertnoise-theme-generated-pass` and
  `convertnoise-theme-own-scss-catch` (controls/run-controls.sh, MC-4 block). Mutation test: with convertnoise.py from
  71dd0bd4^, convertnoise-theme-generated-pass goes red (5 of 6 convertnoise controls pass). Restored: 6/6. The
  own-scss-catch case covers the opposite mistake (making all of themesource/ regenerated). No new control needed.
- **92e91260** (triage: check own modules against the catalog; gate report: list carried debt, NS-4, NS-12): docs only
  (steps/triage.md, steps/gate.md; no code). FEEDBACK rows NS-4 and NS-12 say `doc`, control "none (docs)". That is
  correct, so no control was written.

## 4. Review of the 56 night commits (correctness risk)

I read the diffs of restoreunit (1d973d40), planorder (8bace0f5), convertpre (81c74fbe), rolecheck (7007ad85),
jardedupe (fe7ca374), the data rung (b3e5b96a), diff.py --emit-allow (8edac9ff), the gate widgets rung (c3f4be63, e0229d05),
plus gate.sh PV-12 (5583ad53), the mxrun crash retry (e3c49836) and the stepupdate backslash move (70e00216).
These are defects only. None of them is fixed here: they are the night thread's code.

1. **bin/diff.py:236-239, `--emit-allow` blanket-accepts a whole category.** The restart control writes one allow line
   per check id with no detail pattern. Several check ids are shared by every row of their kind: `log.new_error`, and
   `log.start.<kind>`. One noise error between two starts of the old app writes `log.new_error # start noise`. The real
   upgrade diff then accepts EVERY new log error as PASS*. Reproduced: restart diff with a new `NoiseError: cache warmup`
   gives the allow file, and the upgrade diff turns `3x NullPointerException in ACT_Save` into
   `PASS* ... (accepted: start noise ...)`. Trigger: any restart-control run with a new error or a start-log change. Fix
   direction: emit `check detail` (with fnmatch metacharacters escaped), not the check id alone.
2. **bin/restoreunit.py:83-85, 108-112: false REFUSED on nearly every page and microflow.** The broken-reference guard
   counts every `Module.Name` string that is not a document and not an entity as removed. Module roles
   (`AllowedModuleRoles`) and associations are neither. Reproduced on mkmodel fixtures: a microflow with
   `AllowedModuleRoles: [Shop.Clerk]` gives `REFUSED ... names Shop.Clerk which the target does not have`, and one with
   `Association: Shop.Order_Customer` is refused the same way, though both exist in the target. A plain microflow
   restores. The only way past is `--force`, and that also switches off the Studio Pro lock guard. The guard also misses
   the opposite case: `Module.Entity.Attribute` (three parts) never matches `QN_ONLY`, so a removed attribute is not
   caught. The controls use only a layout (no roles), so they do not show this.
3. **bin/widgetcover.py:157-163 and 190: an unreadable .mpk is skipped, and the verdict is PASS.** The docstring says
   unreadable = exit 2. In fact `package()` returning None only counts it in the header, and exit is 0. A Git LFS
   pointer or a truncated .mpk therefore passes the widgets rung unchecked. The same happens with no widgets/ folder:
   0 packages, `verdict: PASS`, a vacuous pass with no denominator guard.
4. **bin/widgetcover.py:190 with bin/gate.sh:294: waived widgets show as plain PASS, not PASS\*.** The gate gives
   PASS\* only when the output matches `PASSSTAR` (`PASS\* N` or `N PASS\*`). widgetcover prints `verdict: PASS (every
   used package is rendered by a walk or waived)`, so a run in which every gap was waived reads the same as a full render.
5. **bin/rolecheck.py:81-85 with bin/stepupdate.sh:465-473: DANGLING is judged on the whole model, at every step.**
   `dangling()` walks all user roles of NEW, not only those of the module this step updated. One dangling reference that
   was there before the batch (or came from step k) is printed under NEW-ROLES at every later step and saved in
   newroles.txt under each stepped module's name. The summary then lists it N times and blames the wrong modules.
6. **bin/planorder.py:94, 112: `--write` loses a line when a module is planned twice.** `pos` and `by` are keyed by
   module name, so with two lines for one module (two version steps) the rewrite writes the second line for both
   places. The first step's version disappears from plan.txt (the original survives only as plan.txt.orig). stepupdate
   does not pass `--write`, so this happens only on a hand run.

A risk that is not proven, for the night thread to check: bin/mx10.sh sets UPG_RETRY_CRASH=2 for every call, `mx convert`
included (bin/mxrun.sh:51-58). If a crashed convert has already written part of the project in place, the retry runs
on a half-converted model. Confirm that convert writes nothing before it crashes, or exclude it from the retry.

Read and found no defect: convertpre.py (it does skip merge commits, because `diff-tree` without `-m` lists no files for
them, but that is an edge case), jardedupe PLM-23/24 (it works alongside AM-U4's -sources split), the data rung anonymous
users (PLM-27), the gate.sh widgets wiring (optional rung, NOT RUN allowed by design) and the PV-12 warn-once flag.
