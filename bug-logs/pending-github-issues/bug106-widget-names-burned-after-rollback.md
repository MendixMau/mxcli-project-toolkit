**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-106` (discovered 2026-08 on a real project; mxcli built from source at `4b58b89`; Mendix 11.13.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, cache, pages
**Duplicate check:** #978 (DESCRIBE PAGE derived widget names rejected by check) is about name derivation, not the cache. Nothing on cache survival across a file restore, 2026-09-03.

---

**Title:** Widget names claimed by a failed exec stay "taken" after the `.mpr` is restored from a snapshot — retrying the corrected script fails with duplicate-name errors for names that no longer exist

**Body:**

## Summary

Workflow: a page script execs, mxbuild fails, the `.mpr` (and `mprcontents/`) is restored from a snapshot taken before the exec. The corrected script is re-run. mxcli rejects it with duplicate-widget-name errors for names that **only existed in the rolled-back attempt**. `DESCRIBE PAGE` on the restored model shows those names absent.

The widget-name registry appears to be keyed on the project path, not on file contents, so it survives a restore of the files underneath it.

## Environment

- mxcli built from source at `4b58b89` (2026-08-26); Mendix 11.13.0
- Reproducible within a session, deterministic once the first exec has claimed the names

## Steps to reproduce

1. Snapshot `App.mpr` + `mprcontents/`.
2. Exec a `CREATE PAGE M.P { … textbox "txtName" … }` script that fails later in the same script (or fails mxbuild).
3. Restore the snapshot. `DESCRIBE PAGE M.P` → page absent or without `txtName`.
4. Exec the corrected script → `duplicate widget name: txtName`.

## Expected vs. actual

**Expected:** the name registry reflects the model on disk; after a restore the names are free.

**Actual:** names stay burned until the cache is cleared or the process restarts; authors rename widgets `_v2` to get past it, which is how several real pages ended up with `_v2` names permanently.

## Workaround

Suffix the widget names, or clear/refresh the catalog cache before retrying.

## Suggested fix

Key the registry on a content hash or mtime of the affected units, or invalidate it when the `.mpr` mtime goes backwards (a restore is the only way that happens).
