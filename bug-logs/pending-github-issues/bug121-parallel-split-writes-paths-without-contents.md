**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-121` — observed 2026-09-04 building script `84`
of a topbar-titled portal project (Mendix 11.13.0)
**Status:** DRAFT — not yet filed. **Re-probed 2026-09-08 on v0.21.0: still open** (see the
re-probe section at the end of this file — include it when filing).
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

---

## Re-probe on v0.21.0 (2026-09-08) — include when filing

The identical probe script was executed through **v0.20.0** and **v0.21.0** on two separate
throwaway copies of the same project, and each resulting workflow unit dumped with
`mxcli bson dump --type workflow`. After blanking the `$ID` GUIDs the two dumps differ by
**zero lines** — v0.21.0 writes a byte-identical model, so the runtime behaviour is unchanged.

One correction to the title, for whoever picks this up: the path contents **are** present in the
stored BSON, on both versions —

```
Workflows$ParallelSplitActivity
  Workflows$ParallelSplitOutcome
    Workflows$Flow
      Workflows$SingleUserTaskActivity   <- the task IS here
```

which is why `DESCRIBE` round-trips and why `check` and `mxbuild` are both clean. So "writes the
paths but not their contents" names the runtime symptom rather than the mechanism, and the
mechanism is still unidentified. A maintainer comparing this unit against a Studio-Pro-authored
parallel split would likely find it in one field.
