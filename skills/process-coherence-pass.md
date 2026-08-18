# Process-coherence pass — does the whole journey hang together, not just each piece

**Applies to:** any mxcli project with BRDs/requirements docs and a runnable app.

> `testing-shape.md` is **promoted — it lives in the shared toolkit**, not here. There is no local
> copy and there must not be one: the shared file is canonical, and a personal duplicate drifts
> invisibly because nothing syncs the two. Same for `journey-proof.md`.

**Relationship to `testing-shape.md`:** that skill owns UI/Data/Unit/Trace — four ways of checking
that a given, already-identified piece of the app works. This skill answers a question none of
those four can: **is the piece being tested even the right piece**, and **do the pieces that each
individually pass actually chain into the process the requirements describe?** Read
`testing-shape.md` first; this is not a fifth rung on that ladder (D11 killed numbered rungs on
purpose) — it's a different axis, run at a different cadence.

## The failure mode this catches

A component can be internally correct, correctly granted, correctly named, syntactically valid —
and still be dead. `mxbuild` compiles it. A targeted requirements-conformance check ("does element
X match BRD field Y") passes it, because the question asked was about the element's own shape, not
about whether anything calls it. A UI test never finds it either, because UI tests walk the screens
that exist, not the screens a requirement implies should exist. Only tracing the actual reachable
path a user walks surfaces a microflow that was built for a button nobody ever added.

First observed on a live conversion project, 2026-08-13: a submit-to-downstream microflow —
correctly built, correctly granted, **zero references anywhere in the model**. Then found repeatedly
across the same project once looked for systematically: two BRD-named decision screens each had a
working microflow sitting next to their "record decision" button, and the button was never wired.
Not one bug — a pattern, invisible to every other check in place.

## The four passes

Run as a read-only review task (no Write/Edit, never touches the real model) — this is
intentionally a *broader* trace than a targeted conformance question, so budget tens of thousands
of tokens across dozens of instrument calls, not the few-thousand-token budget a single-question
check runs on. Still purposeful: no full-document reads (pull specific fields with `jq`), no
open-ended search without a specific term in mind.

1. **Full call-graph trace per persona journey.** Walk each persona's intended journey hop-by-hop
   as the requirements describe it. At every hop, confirm the *next* step is actually reachable
   from the current one — not just that both individually exist. Use whatever this project's
   tooling exposes for caller/callee/reference graphs (mxcli: `SHOW CALLERS OF` / `SHOW CALLEES OF`
   / `SHOW REFERENCES OF` *and* `SHOW REFERENCES TO` — the `OF` direction misses page-button/grid-
   action bindings, which only show up as references *to* the microflow, not calls *from* one).
   A step nothing before it can reach is the same defect as a step that dead-ends going forward.

2. **State-machine coherence.** Pull the full value set of whatever enumeration drives the
   lifecycle, and the full transition graph of whatever drives it (a workflow definition, a set of
   microflows). Cross-reference: is every value reachable? Does every branch land somewhere
   something downstream actually looks for (a dead terminal state — reachable, but nothing ever
   queries for it again — reads identically to a typo until you check both sides)?

3. **Cross-document consistency.** Requirements documents authored somewhat independently can each
   be locally coherent while disagreeing at their overlap. Pull the specific fields at each overlap
   point (via `jq`, never a whole document) and check they agree in vocabulary *and* granularity —
   one document's 5-value outcome enum against another's 2-value status field is not automatically
   a bug (it might be an already-recorded, deliberate narrowing) but it needs a citation either way.

4. **Goal-to-outcome traceability.** For each requirement, pull its stated outcome/postcondition,
   then trace forward through what passes 1–3 actually found built. This pass is necessarily
   `Judged`, not `Measured` — say so, and cite the specific evidence the judgment rests on.

Label every finding `Measured` (a command ran, output directly supports the claim) or `Judged` (a
view formed from cited evidence, always overrulable at a glance) — same discipline a targeted
conformance review uses, applied to broader claims instead of single fields.

## The judgment call this pass exists to make — do not skip it

When this pass finds a dead component sitting next to a working parallel path (the pattern
above: dead grid-button microflows next to a fully-functional workflow-task path doing the same
job), **the fix is not automatically "wire the dead thing in."** Two live paths to the same outcome
is a duplicate/race risk — whichever fires last wins, or both fire and double-process. Diagnose
which path is real before touching either:

- If one path already works end-to-end and the other is unreferenced scaffolding: correct the
  requirements doc to describe the mechanism that actually works, and archive the dead code. This
  is a documentation-and-cleanup fix, not new functionality, and it is usually the right call.
- Only wire the dead path in if the working path is the one that's actually wrong (rare — verify
  with the same rigor before concluding this).
- Never "complete" a dead component reflexively just because you found it and it looks unfinished.
  Ask what it would collide with if it started running.

## Cadence — when to run this, not "how deep"

This is not a per-module rung (that debate — depth 1–4, tiers — is `testing-shape.md`'s and it was
explicitly settled the other way there: no tiers, no numbers). This pass runs at coarser, named
checkpoints instead:

- Once requirements-conformance and UI/Data testing are both clean for a module or a related
  cluster of modules — this pass assumes the pieces already checked out individually and is
  specifically hunting for composition failures between them. Running it before the component
  checks are clean just re-discovers component bugs at ten times the token cost.
- On demand, whenever a user asks "does this actually work end to end" or "does the process make
  sense" — that phrasing is the tell that they want this pass, not another component sweep.
- Before a milestone/demo that will be walked live by someone who isn't the builder — this is
  exactly the class of gap ("the screen you'd naturally click doesn't do the thing") that burns
  trust fastest in front of an audience.

## Output shape

A structured findings list, each row: what's claimed vs. what's built, `Measured`/`Judged`, the
exact instrument calls behind it, and a suggested owner (the role that corrects requirements docs
vs. the role that writes fix code vs. "needs a human decision" for anything touching intent). A
persona journey with no findings gets stated as clean, not padded — this pass is expensive enough
that a false "found something" pressure to justify the cost is a real risk; resist it.
