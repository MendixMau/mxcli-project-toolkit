**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## 🚨 CRITICAL: mxcli marketplace install collapses a split-model
project to monolithic .mpr and deletes mprcontents/ — breaks Studio Pro` (originally discovered
2026-07-22 on a PLM parts-flow project, mxcli v0.16.0, mxbuild 11.12.0)
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/879 (2026-08-13)
**Note:** re-verified twice before filing:
1. On the real SonnyPOC project (mxcli v0.17.0, mxbuild/Studio Pro 11.13.0) — installing
   Workflow Commons (content id 117066) deleted all 401 tracked `mprcontents/*.mxunit` files and
   grew `SonnyPOC.mpr` from 74 KB to 35 MB. Recovered via `git checkout HEAD -- SonnyPOC.mpr
   mprcontents/`; a follow-up `mxcli docker check` on a scratch copy of the restored project
   passed with 0 errors, confirming the restore was clean and the corruption was specific to the
   install step.
2. On a **fresh, disposable scratch project** created purely for this report (`mxcli new
   BugReproMktInstall --version 11.13.0 --theme none --skip-build`, never touching a real
   project), to rule out anything specific to SonnyPOC's history or prior edits. Same module,
   same result — see Steps to reproduce below. This is the repro filed here.

This is a second independent confirmation (different project, newer mxcli/Mendix version) of the
same defect first logged for mxcli v0.16.0/mxbuild 11.12.0 — it is a general, persistent defect
in `marketplace install`'s interaction with split-model storage, not project- or version-specific.

---

**Title:** `mxcli marketplace install` collapses a v2 split-model project to a single monolithic `.mpr` and deletes the entire `mprcontents/` directory

**Body:**

## Summary

Running `mxcli marketplace install <id> -p <project>.mpr` against a project stored in the Mendix
11 **split-model format** (a small `.mpr` index file plus a `mprcontents/` directory of
per-unit `.mxunit` BSON files — the format Studio Pro uses by default for git-tracked projects)
silently:

- **deletes every file under `mprcontents/`**, and
- **rewrites `<project>.mpr` as a single monolithic file**, tens of MB in size instead of tens
  of KB.

`mx check`/`mxbuild` on the resulting `.mpr` reports 0 errors and the installed module's
entities/microflows/pages are genuinely present — so the install *looks* successful from mxcli's
own output and from a build check. But the on-disk project shape has silently changed from
split to monolithic. On a project whose `mprcontents/*.mxunit` files are tracked in git, this
manifests as ~all of them being deleted in the working tree, and Studio Pro's Git provider then
fails to reopen the project with:

```
System.InvalidOperationException: Arg_InvalidOperationException
  at ...ObjectUtil.ThrowIfNull[T](T value)
  at ...LibGit2RepositoryProvider.WriteBaseFile(String versionedFilePath, String destinationPath)
```

because git-tracked `mprcontents/*.mxunit` paths vanished out from under it while a large new
binary `.mpr` appeared in their place.

## Environment

- mxcli: `v0.17.0` (`2026-08-10T05:12:17Z`) — current tagged **Latest** release
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: macOS (Darwin 25.6.0), arm64
- Marketplace module used in this repro: **Workflow Commons**, content id `117066`, version
  `4.11.0` (any module install appears to trigger it — this is the module on hand for the repro)

## Steps to reproduce

Create a fresh, disposable project in the split-model format (this is what `mxcli new` produces
by default):

```
$ mxcli new BugReproMktInstall --version 11.13.0 --output-dir /tmp/mxcli-bug-repro --theme none --skip-build
✓ Project 'BugReproMktInstall' created at /tmp/mxcli-bug-repro
```

Confirm the starting split-model state:

```
$ cd /tmp/mxcli-bug-repro
$ find mprcontents -name '*.mxunit' | wc -l
369
$ ls -la BugReproMktInstall.mpr
.rw-r--r-- 70k  BugReproMktInstall.mpr
```

Install a marketplace module:

```
$ mxcli marketplace install 117066 -p BugReproMktInstall.mpr
Imported module "WorkflowCommons" version 4.11.0 into BugReproMktInstall.mpr
```

Check the same two things again:

```
$ find mprcontents -name '*.mxunit' 2>&1 | wc -l
ls: mprcontents: No such file or directory
0
$ ls -la BugReproMktInstall.mpr
.rw-r--r-- 35M  BugReproMktInstall.mpr
```

`mprcontents/` — 369 tracked unit files a moment ago — no longer exists at all, and the `.mpr`
grew roughly 500x, from 70 KB to 35 MB, in a single command that reported success.

## Expected vs. actual

**Expected:** `marketplace install` (which shells out to `mx module-import` under the hood)
either preserves the project's existing storage format (split vs. monolithic), or clearly warns
the user before converting a split-model project to monolithic and deleting `mprcontents/`.

**Actual:** The conversion happens unconditionally and silently — no prompt, no warning, no
mention of it in the command's own success output (`Imported module "..." version ... into
....mpr`), even though it is a destructive, hard-to-reverse change to the project's on-disk
representation.

## Root cause (as far as can be determined from the outside)

`marketplace install` invokes `mx module-import`, which appears to always write its result as a
single monolithic `.mpr`, regardless of whether the project it was given was split or
monolithic to begin with. Every other mxcli write path exercised in this project (plain MDL
`exec` against entities/microflows/pages) preserves the split format correctly — only
`module-import` (and, per a related but separate report, `docker check`, which also collapses
the format on some versions) does not.

## Severity

**Critical.** This does not corrupt the model's *contents* — `mx check`/`mxbuild` report 0
errors and the imported module is genuinely usable — but it destroys the project's *storage
format* in a way that is invisible to the command's own success output, breaks git history for
every previously-tracked `mprcontents/*.mxunit` path, and breaks Studio Pro's ability to reopen
the project via its Git integration. Recovery is possible (`git checkout HEAD -- <app>.mpr
mprcontents/`, or restoring a pre-import snapshot) but only if the corruption is caught before a
commit buries it, and only because the previous split state still exists in git history — a
project without a prior clean commit to restore to would have no way back to split format at
all.

## Suggested fix

Either:
1. Make `mx module-import`/`marketplace install` preserve the input project's storage format
   (split vs. monolithic) when writing its result, the same way plain MDL `exec` already does,
   or
2. If preserving split format on import isn't feasible, have `marketplace install` detect a
   split-model target up front and refuse (or require an explicit `--allow-format-change` style
   flag) rather than silently converting and deleting `mprcontents/`.

## Related

- The toolkit's own bug log (linked as `Source` above) documents this same failure mode
  independently on a different project, an older mxcli release (`v0.16.0`) and Mendix version
  (`11.12.0`), suggesting this is a long-standing, general defect rather than a regression or
  edge case.
