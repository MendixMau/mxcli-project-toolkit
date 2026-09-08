# Retesting a learned rule before you obey it

**Applies to:** any mxcli project.

**Purpose:** a `learned-*.md` rule is a measurement of a *binary at a moment*, not a law. mxcli
ships frequently; every STOP, workaround and "not supported" in this toolkit has a half-life.
This file is the cheap probe that decides whether a rule still holds, and the discipline for
writing one down so the next reader can re-run it instead of re-deriving it.

## When this fires

Before you act on a learned rule that would make your work **more complicated than the obvious
approach** — a STOP that routes you to Studio Pro or MCP, a "wrap it in a nanoflow", a "not
supported, use X instead". Rules that merely tell you the correct syntax cost nothing to obey;
rules that add a workaround cost a lot, and are the ones that rot expensively.

Do **not** fire on every rule on every session. The trigger is: *this rule is about to cost me
a detour, and it carries a version stamp older than my binary.*

## The probe, in order — stop at the first honest answer

1. **`./mxcli --version`.** Compare against the rule's stamp. Same or older binary → the rule
   stands, obey it. Newer → continue.
2. **`./mxcli check <scratch>.mdl`** on the smallest script that expresses the forbidden thing.
   A parse error is a real answer: the grammar is absent, stop here.
3. **Exec it and read a real gate.** `mxcli check` passing is not evidence — most of this
   toolkit's STOP rules describe constructs that pass `check` and corrupt on write. Run the
   project's `bin/exec.sh` (or exec + `mx check`/mxbuild) and read the **mxbuild verdict**, not
   the exit code. Then `DESCRIBE` the element and look at what was actually stored.
4. **Drop the probe.** A scratch element left in a real model is a defect you introduced while
   proving one did not exist.

## What a probe must never do

- Never conclude from **documentation**. `mxcli syntax` and the bundled `.ai-context/skills/`
  are not the grammar; the parser is. The incident that produced this file: a rule stating "MDL
  has no show-message activity anywhere" was derived by reading two skill files' statement
  lists. The activity had existed the whole time; `mxcli syntax` documents it nowhere, so the
  documentation sweep could only ever return "absent". Worse, mxcli's own bundled
  `write-nanoflows.md` used a **level-first grammar the shipped binary rejects** — so an agent
  that did find the skill got a parse error and reached the same wrong conclusion.
- Never conclude from a **binary's embedded strings or examples**. `strings ./mxcli` will happily
  show you syntax the shipped grammar refuses.
- Never conclude from **one green `mxcli check`**. See step 3.

## Writing the result down — four things, or it rots again

Whatever the verdict, edit the rule **in place** in its `learned-*.md`. A retest recorded
somewhere else is a second source of truth, and the older, louder one wins.

1. **Both stamps.** The binary and Mendix version you tested on, and the date. A rule with no
   stamp cannot be retested by anyone; it can only be believed or ignored.
2. **The verdict word, in the first sentence** — `STILL HOLDS`, `DOES NOT REPRODUCE`, or
   `RETIRED`. A reader skimming for the trigger must not have to reach paragraph three.
3. **The evidence, with its denominator** — what you ran, how many cases, and which gate said
   what ("a probe microflow with a bare literal, a concatenation and all three severity levels,
   executed, real mxbuild 0 errors"). "Retested, fine" is not a receipt.
4. **Keep the old rule underneath, marked as history.** Projects pin different binaries; a rule
   deleted outright strands every project still on the old one. Say which binary each half
   applies to.

## Completion criteria

The retest is done when: the rule's own text carries a verdict word and two version stamps; the
probe element is gone from the model (`SHOW MICROFLOWS`/`SHOW PAGES` returns 0 matches for its
name); and every *other* file in the toolkit asserting the same thing has been reconciled —
`grep -ril '<the claim>' skills/ bug-logs/` returning exactly the files you edited. That last
check is not optional: the show-message incident had the correct knowledge in
`learned-microflow-patterns.md` and the flatly wrong claim in `learned-popup-feedback-pattern.md`
**at the same time**, in the same repo, for three weeks. Two files, two answers, no one reading
both.
