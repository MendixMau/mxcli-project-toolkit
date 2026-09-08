**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-124` — observed 2026-09-07 re-emitting four start
microflows in script `87` of a topbar-titled portal project (Mendix 11.13.0)
**Status:** DRAFT — not yet filed
**Suggested labels:** bug, describe, round-trip, microflows, silent-behaviour-change

---

**Title:** `DESCRIBE MICROFLOW` omits `without events`, so a DESCRIBE → exec round-trip silently
turns commit event handlers back on

**Body:**

## Summary

mxcli's bare `commit $X;` now defaults to **WITH EVENTS**, matching Studio Pro. It previously
meant events OFF. That change is defensible on its own — the defect is that **`DESCRIBE
MICROFLOW` prints a bare `commit $X;` for both settings**. The events flag is not round-tripped.

So the standard repoint workflow — `DESCRIBE` a microflow, change one activity, re-exec it —
silently flips the commit semantics of every commit in the flow that had events off.

## Why nothing catches it

- `mxcli check --references` passes.
- `mxbuild` / `mx check` pass — the model is structurally valid.
- The behaviour change appears only at run time, in whatever the event handlers do.

On the project where this was found it happened to be inert (no entity in any of seven modules
declares an event handler, checked) — which is exactly why it would have shipped unnoticed on a
project where one does. The only reason it surfaced at all is that mxcli's own `MDL067` info
message fired on a large enough re-emitted flow.

## Expected

`DESCRIBE` emits `commit $X without events;` whenever the stored activity has events off. **A
round-trip must not change behaviour.**

Failing that, `MDL067` should fire on *every* bare commit in a script that also contains a
`create or modify microflow`, rather than on a heuristic that a smaller flow slips past.

## Related

BUG-103 (`DESCRIBE MICROFLOW` emits `log` strings with embedded doubled quotes that `mxcli check`
then rejects). Same class: `DESCRIBE` output that is not a faithful, re-executable representation
of the model.
