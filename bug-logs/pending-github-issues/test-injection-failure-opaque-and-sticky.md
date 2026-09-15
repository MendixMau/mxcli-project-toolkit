**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-test-injection-failure-opaque-and-sticky` — found 2026-09-15
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1104 (2026-09-15)
**Suggested labels:** bug, test, diagnosability

---

**Title:** `mxcli test` hides mxbuild's error on an injection failure, and one leftover broken document then fails every later run of any test file

**Body:**

## Summary

Two behaviours that compound into a bad loop.

**1. The build error is swallowed.** When the injected test microflow fails to build, the run
reports only:

```
Error: build failed: The project cannot be deployed, because it contains errors.
```

No CE code, no document name, no activity. The same mxbuild invocation run directly
(`mxcli docker check -p app.mpr`) prints the real line, e.g.
`[error] [CE0012] "The ‘List’ property is required." at Aggregate list activity 'Count'`. The
information exists and is discarded.

**2. A failed run leaves the project modified, and it is sticky.** Cleanup reports its own
failure:

```
ERROR: cleanup failed — the project has been left modified:
DROP MICROFLOW MxTest.Test_test_1: exit status 1: Error: microflow not found: MxTest.Test_test_1
Check the after-startup microflow and the MxTest module before committing.
```

Worse, **any unrelated broken document left in the project makes every subsequent `mxcli test`
run fail with the same opaque message**, including runs of a completely different, valid test
file — because injection rebuilds the whole project.

## Environment

- mxcli: `v0.22.0-15-g7b42100d` (`main` HEAD, 2026-09-15)
- Mendix: 11.13.0, blank `mxcli new` scaffold
- Reproducible: yes — any test file whose generated microflow does not build

## Steps to reproduce

1. Write a `.test.mdl` whose body produces a valid-to-`check` but unbuildable microflow (the
   nested `COUNT(FILTER(…))` in the sibling issue does it).
2. `mxcli test <file> -p app.mpr --attach` → the opaque `build failed` message above.
3. Now run a **known-good** test file: it fails identically, with nothing indicating the fault
   lies outside the file being run.
4. `mxcli docker check -p app.mpr` prints the real CE code and the offending document.
5. Drop that document; the known-good test runs again immediately.

Observed directly: a broken diagnostic microflow, unrelated to the tests, blocked a known-good
`wf-split.test.mdl` from running at all.

## Impact

The failure mode actively misdirects — the message says "the project" while the author is
looking at a test file, and the fix is usually in neither.

## Suggested fix

1. Surface mxbuild's actual error lines on an injection build failure; they are already captured.
2. On cleanup failure, name the leftover documents explicitly and offer the `DROP` script.
3. Pre-flight the project's existing build state and say so when the project was *already*
   broken before injection, so the author is not sent hunting in the test file.
