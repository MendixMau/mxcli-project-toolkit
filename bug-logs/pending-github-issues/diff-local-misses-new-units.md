**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-diff-local-misses-new-units` — found 2026-09-25 (field report on v0.23.0, reproduced on v0.24.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, diff-local
**Duplicate check:** searched 2026-09-25 (`diff-local does not show new untracked units`). No match. #1038 and #424 are different diff-local bugs; 0dce31214 (unreleased) fixes other diff-local defects but not this one. Consider filing the domain-model UUID rendering (`BUG-DRAFT-diff-local-module-uuid`) as a second issue or a comment here.

---

**Title:** `diff-local` does not report new documents: untracked `mprcontents` units are invisible

**Body:**

## Summary

On an MPR v2 project under git, a document created since the ref is a new, **untracked** `mprcontents/**.mxunit` file. `diff-local` builds its change list from `git diff --name-status <ref> -- <contentsDir>` (`mdl/executor/cmd_diff_local.go`), which never lists untracked files, so new microflows, pages and entities are missing from the output and the summary.

**Version:** mxcli v0.24.0 (also v0.23.0), Mendix 11.12.1, MPR v2.

## Repro

In a clean git checkout of an MPR v2 app:

```
create microflow ModuleA.SUB_New () begin log info node 'P' 'x'; end;
/
create persistent entity ModuleA.Thing (Code: String(20));
```

```
mxcli exec repro.mdl -p App.mpr
git status --short          # new mprcontents/... directories are untracked
mxcli diff-local -p App.mpr
```

## Measured (v0.24.0)

- Only new units (new module + entity + microflow + page): `No local changes found in mxunit files.`
- New entity in an existing module + new microflow: `Summary: 0 new, 1 modified, 0 deleted`. The domain model is listed; the microflow is not.
- After `git add -N <new dirs>`: `1 new`, but the new microflow renders as `create or modify microflow .SUB_New ()`, with an empty module qualifier.

## Expected

New units are listed as `new`, rendered with their module, and counted in the summary.

## Workaround

Build the list from `git diff --name-only <ref> -- mprcontents/` plus `git ls-files --others --exclude-standard mprcontents/` and resolve unit ids yourself.
