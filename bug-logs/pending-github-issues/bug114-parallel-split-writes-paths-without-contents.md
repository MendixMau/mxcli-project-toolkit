**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-114` — observed 2026-09-04 building script `84`
of VB-USI-main (Mendix 11.13.0)
**Status:** DRAFT — not yet filed
**Suggested labels:** bug, workflow, mdl, silent-corruption

---

**Title:** A scripted `PARALLEL SPLIT` writes its paths but not their contents — the workflow
loads, validates, and deadlocks at run time

**Body:**

## Summary

`PARALLEL SPLIT` in a `create workflow` script produces a split with the correct number of
paths, each **empty**. The activities written inside each path are dropped. The resulting
workflow:

- loads in Studio Pro without complaint,
- passes `mxbuild` / `mx check` with zero errors,
- and at run time reaches the split and never leaves it, because no path contains the user task
  that would complete it.

## Why this is worse than BUG-76

BUG-76 (a scripted workflow `DECISION` corrupts the `.mpr` so it will not load) fails **loudly**,
at load, immediately. This one fails **silently**, at run time, after the model has passed every
gate the pipeline has. On this project the whole downstream chain was made unreachable and
nothing in the toolchain said so — it was found by walking the workflow in the running app.

## Impact

The parallel split is the central structural feature of the workflow being converted. It has had
to be dropped from the scripted build entirely and re-added by hand in Studio Pro, which breaks
the "the `.mpr` is reproducible from the numbered scripts" property the whole pipeline depends
on. Script `84` now builds the definition **sequentially** with a comment pointing here.

## Expected

Either write the path contents, or refuse the statement with an error. A structure writer that
produces a valid-looking, non-executing model is the worst of the three outcomes.

## Environment

mxcli against Mendix 11.13.0, native workflow engine, Linux container.

## Related

BUG-76 (scripted workflow `DECISION` corrupts the `.mpr` on load). Both are workflow *structure*
writers emitting models the runtime will not execute as written.
