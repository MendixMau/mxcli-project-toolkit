**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-112` (2026-09-02/03, mxcli v0.20.0, Mendix 11.14.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, new, hang
**Duplicate check:** none found for `new path too long hang` on 2026-09-03.

---

**Title:** `mxcli new` warns that the project path exceeds the 259-character MxToolset limit, then hangs forever in "Step 6/7: Running the first build" instead of failing

**Body:**

## Summary

`mxcli new` detects the condition and says so at step 2:

```
Warning: this project's path is 49 characters longer than Mendix tooling allows.
  Total 308 exceeds the 259-character limit MxToolset enforces.
  ... `mx` commands against it can fail with PathTooLongException.
```

It then proceeds to *Step 6/7: Running the first build* and never returns. Observed hung for about 10 hours: no output, no timeout, no non-zero exit. The project itself is created and usable; only the settle-build hangs.

## Why it matters

Agent sessions routinely scaffold into deep scratch directories (about 126 characters before the project name in one common harness). A background `mxcli new` there consumes the entire unattended run silently.

## Environment

- mxcli v0.20.0 (2026-08-28); Mendix 11.14.0; Linux

## Steps to reproduce

1. `mkdir -p` a directory whose absolute path is over 200 characters.
2. `mxcli new LongApp --version 11.14.0` inside it.
3. Observe the warning at step 2, then the hang at step 6.

## Expected

Having detected the over-length path, either refuse before step 6 with a non-zero exit, or bound the first build with a timeout and report it. A warning followed by an unbounded blocking call is the worst of both.
