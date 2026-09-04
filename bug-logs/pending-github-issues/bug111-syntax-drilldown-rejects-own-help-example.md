**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-111` — found 2026-09-03 (mxcli v0.20.0)
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1025 (2026-09-04)
**Suggested labels:** bug, cli, docs

---

**Title:** `mxcli syntax` drill-down rejects the example printed in its own help text
(`Unknown topic: workflow user-task targeting`)

**Body:**

## Summary

`mxcli syntax` lists, under Examples:

```
mxcli syntax workflow user-task targeting     # Drill down to targeting
```

Running exactly that returns `Unknown topic: workflow user-task targeting`. The same happens
for `mxcli syntax workflow user-task` and `mxcli syntax workflow parallel-split`, even though
`mxcli syntax workflow` lists all of those as sub-topics. Only `mxcli syntax workflow --json`
returns the per-construct syntax and examples.

## Environment

- mxcli: `v0.20.0` (2026-08-28)
- Reproducible: yes, 100%

## Steps to reproduce

```
mxcli syntax                                  # prints the example above
mxcli syntax workflow                         # lists user-task, parallel-split, … as sub-topics
mxcli syntax workflow user-task targeting     # Unknown topic: workflow user-task targeting
mxcli syntax workflow user-task               # Unknown topic
mxcli syntax workflow --json                  # works — the only way to reach the sub-topics
```

## Why it matters

Low severity, but it costs every agent a discovery round-trip on a grammar that is not
otherwise documented, and it pushes them to guess — which, for workflows, is how BUG-107's
segfault spelling gets written.

## Expected

Either the drill-down path resolves the listed sub-topics, or the help example and the
sub-topic list are removed so the `--json` route is the only advertised one.
