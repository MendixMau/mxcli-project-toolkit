**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-112` — observed 2026-09-02/03 on a Claude Code
web container (mxcli v0.20.0 / Mendix 11.14.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, cli, new, hang

---

**Title:** `mxcli new` warns that the project path exceeds the MxToolset 259-character limit,
then hangs forever in the first build instead of failing

**Body:**

## Summary

`mxcli new` correctly detects an over-length output path at step 2 and prints a clear warning.
It then continues to *"Step 6/7: Running the first build"* and never returns: no output, no
timeout, no non-zero exit. Observed hung for ~10 hours. The project itself is created and
fully usable; only the settle-build hangs.

## Environment

- mxcli: `v0.20.0` (2026-08-28)
- Mendix / mxbuild: `11.14.0`
- OS: Linux amd64 (Claude Code web container; session scratch directories are ~126 characters
  before the project name is appended)
- Reproducible: yes, on any output path over the limit

## Steps to reproduce

```
mkdir -p /some/very/deep/scratch/path/…   # such that <path>/<App>/… exceeds 259 chars
mxcli new App --version 11.14.0 --output-dir /some/very/deep/scratch/path
```

Output at step 2:

```
Warning: this project's path is 49 characters longer than Mendix tooling allows.
  Total 308 exceeds the 259-character limit MxToolset enforces.
  ... `mx` commands against it can fail with PathTooLongException.
```

Then `Step 6/7: Running the first build` — and nothing further, indefinitely.

## Why it matters

An unattended or background `mxcli new` in a deep directory consumes the entire run silently:
there is no error to react to and no exit to wait on.

## Expected

Having detected the condition, either refuse before step 6 (exit non-zero with the warning as
the reason) or bound the first build with a timeout that fails loudly. A warning followed by an
unbounded blocking call is the worst of both.

## Workaround

Create in a short path (`/tmp/<short>/`), or pass `--skip-build` — the project produced
without step 6 is fully usable (verified: `SHOW MODULES`, `exec`, and native `mx check` all
work against it).
