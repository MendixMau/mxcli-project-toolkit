# Tool Output Is Not Ground Truth — Verifying Before You Conclude

**Applies to:** any agent-driven work against a model, database, or codebase read through tooling.
Written after a single session on a live Mendix project (2026-07-29) produced **three separate false findings**
of the same shape, one of which nearly caused a destructive "fix" to a working page.

**Companion:** `mpr-corruption-and-sp-load-errors.md` (the incident this session also produced).

---

## The failure mode, in one sentence

**A thing missing from a tool's output looks exactly like a thing missing from the model.**

There is no visual difference between "the property is not set" and "the tool doesn't emit that
property." Both render as silence. An agent scanning for defects will read silence as a defect
every time, because that is the interpretation that produces a finding — and producing findings
feels like doing the job.

## Why LLMs specifically keep hitting this

1. **Absence is unfalsifiable without a control.** Presence is self-evidencing; absence is not.
2. **Finding a bug is rewarded, saying "my method may be wrong" is not.** The incentive gradient
   points at the false positive.
3. **Tool output looks authoritative.** Structured, machine-generated text reads as fact, not as
   one lossy projection of the underlying state.
4. **Grep destroys structure.** Flattening a hierarchy to search it discards exactly the nesting
   that would have explained the "missing" thing.
5. **Confidence compounds.** Once written down as a finding, it gets cited by the next step as an
   established premise. In the incident below, a false finding became the stated justification in
   a subagent brief, and the subagent dutifully built on it.

---

## THE RULE: run a control before reporting an absence

Before concluding "X is missing / broken / unset", check your method against something you **know**
is correct. If the known-good case also looks broken, your method is broken — not the model.

```bash
# WRONG — a bare finding
grep -rl "MyMicroflow" mprcontents/          # → 0 hits → "the work is gone!"

# RIGHT — control first
grep -rl "DefinitelyExistingThing" mprcontents/   # → 0 hits → the METHOD is broken
grep -ral "DefinitelyExistingThing" mprcontents/  # → hits → needed -a for binary
grep -ral "MyMicroflow" mprcontents/              # → now trustworthy
```

Cost: one extra command. In the session below it caught a false alarm instantly, the one time it
was used.

---

## Three real instances from one session

### 1. "All your work is gone" — read during a write

Read the `.mpr` while Studio Pro was mid-rewrite, saw 6 microflows instead of 13, and told the user
the whole session's work was lost. It was not; the file was simply being written at that instant.

**Antidote:** confirm against an independent source before declaring loss.
```bash
git hash-object Project.mpr            # working tree
git rev-parse <commit>:Project.mpr     # committed
```
Identical hashes mean the tree *is* the checkpoint, whatever a stale read said. Also re-run the
query — caches (`.mxcli/catalog.db`) lag.

### 2. "mxcli converts v2→v1 on read" — correlation asserted as cause

The project kept flipping from MPR v2 to a single-file form. Noticed the conversions happened
around read-only `mxcli` commands and reported mxcli as the culprit — plausible, and wrong. A
subagent later checked mtime before and after its own mxcli calls: unchanged. Something else was
doing it.

**Antidote:** to claim tool T causes effect E, run T in isolation and observe E. Timing correlation
in a tree with multiple concurrent writers is not evidence. Instrument (record state before/after
your own calls) rather than infer.

### 3. "These filters are unbound" — a lossy DESCRIBE

`DESCRIBE PAGE` emitted `dropdownfilter fEquipType` with no `Attributes:` property. Reported as a
live shipping bug across two pages, and a corrective script was drafted. The user pushed back:
the filters had been tested working many times. They were right.

Two compounding errors:
- **`grep` flattened the hierarchy**, hiding that the filters sat in a deliberately built filter bar
  with paired labels.
- **Disconfirming evidence was already in hand and ignored.** `mxcli check` on the corrective script
  emitted `MDL-WIDGET07: property columnsFilterable is not recognized and will be silently dropped`
  — an explicit admission that mxcli's model of that widget family is incomplete. A tool that does
  not understand a sibling property cannot be trusted to round-trip a child one.

Had it been executed, it would have rebuilt a working page containing `customContent` columns —
the single highest-risk construct for load-time BSON corruption in this stack. **All risk, zero
benefit, from a finding that never existed.**

---

## Checklist before reporting any absence-based finding

- [ ] Did I run a **control** against a known-good element with the same method?
- [ ] Is the tool **known to be lossy** here? Check for warnings like `not recognized`,
      `will be silently dropped`, `experimental`, or a bug log entry for the same widget/feature.
- [ ] Did I **grep away the structure**? Re-read the raw output with context (`-A/-B`) or in full.
- [ ] Is there a **second, independent source**? Git, a sibling element, the running app, the user.
- [ ] Could this be a **race**? Is another process writing right now?
- [ ] **Does a human already know?** "It's tested and works" from the person who built it outranks
      any inference from tool output. Ask before drafting a fix.

## When you cannot get certainty

Say so, in those words, and label the confidence. These are different claims and must not be
written as if they were the same:

- "`SHOW ACCESS` reports no roles for X" — an observation
- "X has no grants in the model" — an inference from a possibly-lossy tool
- "X will fail at runtime" — a prediction requiring both of the above to hold

Report the observation, state the inference as an inference, and name what would actually settle it
(open it in the IDE, run the app, click the thing).

## The asymmetry that should govern the response

A false negative costs a missed bug. A false positive can cost a **destructive fix to working
code** — and generated "fixes" are executed with far less scrutiny than they deserve, because they
arrive pre-validated by a checker that cannot see the real problem.

When the proposed remedy is destructive (rebuild a page, drop a document, restore a snapshot,
delete files), **raise the evidence bar before acting, not after.** Validation passing is not
evidence of correctness: in this session `mxcli check` passed on the original "broken" version, on
the unnecessary fix, and on a script that had silently omitted every security grant it claimed to
add.

---

# Part 2 — The inverse: success output is not a write

*Added 2026-07-29, later the same session, after three constructs were found that report success
and write nothing.*

Part 1 is about **false negatives**: silence in tool output misread as a missing property.
This is the mirror image, and it is more dangerous because nothing looks wrong at all.

## The failure mode

```
$ ./mxcli exec script.mdl -p app.mpr
Created rest client Module.Api (1 operations)      ← printed
$ ./mxcli check script.mdl -p app.mpr --references
✓ All references valid                             ← passed
$ mxbuild ...
0 errors                                           ← clean
```

…and the operation in the model has none of the properties the script declared.

Three instances found in one session, all in mxcli, all silent:

| Construct | Declared | Actually stored |
|---|---|---|
| `create rest client` op with `Query:` / `Response:` | full operation | `Method`, `Path`, `Timeout` only |
| `create import mapping` with quoted identifiers | `Mod.Entity` | literal `Mod."Entity"` — resolves to nothing |
| `datagrid (datasource: microflow ...)` | microflow datasource | **no datasource at all** |

## Why every layer of validation misses it

- **`--references` validates names *before* serialization.** These defects happen *during* it.
  A green reference check means the names resolve, and nothing more. It is not a write receipt.
- **The success line is printed by the caller, not the writer.** "Created X (1 operations)" is
  emitted after the call returns, not after reading back what landed.
- **The model checker only sees the stored model.** It cannot flag a missing property until
  something *else* references it. One of these surfaced days-equivalent later as
  `CE1571 "No argument has been selected for parameter 'Filter'"` — which reads like a missing
  argument on a datasource call, not like a datasource that was never written.

So the gate passes, the commit happens, and the defect surfaces attributed to whatever change
happened to expose it.

## THE RULE: read the element back

Symmetrical to Part 1's control rule. Before believing a write, `DESCRIBE` it:

```bash
# after writing a REST client operation
./mxcli -p app.mpr -c "DESCRIBE REST CLIENT Mod.Client" | grep -c "Response: none"

# after writing a widget datasource
./mxcli -p app.mpr -c "DESCRIBE PAGE Mod.Page" | grep -i "datasource"

# after writing an import mapping — quotes visible in the stored name are the tell
./mxcli -p app.mpr -c "DESCRIBE IMPORT MAPPING Mod.IMM_X" | grep '"'
```

⚠️ **Combine with Part 1.** `DESCRIBE` is itself a lossy projection — a property absent from its
output may exist in the model. So a read-back that *shows* the property proves the write landed;
a read-back that *doesn't* proves nothing on its own. Confirm against a known-good element of the
same kind before concluding the write failed.

That asymmetry is the whole discipline in one line:

> **Presence in tool output is evidence. Absence is not — in either direction.**

## Workaround pattern that did work

Where the document-level construct silently dropped its properties, the *inline* equivalent
persisted intact. A REST client operation lost `Query:`/`Response:`; an inline
`rest call ... returns mapping Mod.IMM_X as Mod.Entity` inside a microflow kept everything,
headers included.

**When a construct silently no-ops, look for a different construct that expresses the same
intent** before escalating to GUI work. Probe it on the real model with a throwaway element,
read it back, then delete the probe.

---

## The measurement instrument lies too — `$?` after a pipeline

**Added 2026-08-04** (toolkit hardening session), where this fired **three times in one sitting**
and twice nearly produced a false bug report against a script that was working correctly.

```bash
./checker.sh --summary "$FILE" | tail -20 ; echo "exit=$?"     # WRONG
```

`$?` is the exit status of the **last command in the pipeline** — `tail` — which is essentially
always 0. Every guard in this toolkit signals its verdict through the exit code, so piping the
output into `head`/`tail`/`grep` to keep the terminal readable **discards the only thing you were
measuring**, and replaces it with a constant 0. A failing gate reads as passing.

It is worse than a plain wrong answer, because the failure mode is *biased toward green*. You will
never see a spurious failure from this; you will only ever see spurious success.

Real instances from the one session:

| Observed | Concluded | Actually |
|---|---|---|
| `coverage-check ... \| tail; exit=0` with 323 UNCLAIMED | "exit 0 on a dirty ledger — new bug!" | exit **1**, correct |
| `gate-check ... \| head; exit=0` printing "Gate BLOCKED" | "a blocked gate passes — 5th false-PASS!" | exit **1**, correct |
| `exec.sh ... \| tail; EXIT=` (empty) | inconclusive | exit **3**, correct |

**THE RULE: measure the exit code on an unpiped run.**

```bash
./checker.sh --summary "$FILE" >/dev/null 2>&1 ; echo "exit=$?"   # RIGHT
./checker.sh ... > /tmp/out.log 2>&1 ; echo "exit=$?" ; tail -5 /tmp/out.log
```

Redirect to a file and read it separately, or use `${PIPESTATUS[0]}` **immediately** — note that
even `PIPESTATUS` is clobbered by any intervening command, including the `echo` you were about to
use to print it.

Two corollaries, both of which cost real time here:

- **A checker that only ever exits non-zero is as useless as one that only ever exits 0.** Both
  real ledgers in the repo were dirty, so "exit 1" proved nothing about the pass path. Build a
  minimal *positive control* — a fixture that must exit 0 — before believing the checker works.
- **Exercise the failure branch of your own fix.** Two defects this session lived only there: a
  gate-check message that spliced an em-dash into a variable name (`$remaining—`, fatal under
  `set -u` on byte-oriented bash 3.2), and an `exec.sh` verdict claiming "the gate is clean" on a
  run where the gate had been *skipped*. Both pass paths were green. The failure path is where
  error-reporting code lives, and it is the path nobody runs.

---

# Part 3 — A passing gate is not a working model

*Added 2026-08-05, after a day lost to a defect that every gate in the stack reported as clean.*

Parts 1 and 2 are about a tool's output misreporting **its own** work. This is a third case: a gate
that runs correctly, reports honestly, and is simply **not sensitive to the defect you have**.

## The instance

Scripted a Mendix workflow with five `CALL MICROFLOW` activities.

- `mxcli check --references` → `Check passed!`
- `mxcli exec` → `Created workflow`
- `mx check` (Studio Pro's own validator) → **`0 errors`**
- Studio Pro **opened the model** without complaint

Four green signals. Every activity was a **red pin** that could not be clicked, and the app would
have refused to boot: `Class 'Workflows$CallMicroflowTask' could not be found`.

mxcli `v0.16.0` writes a `$Type` that Mendix renamed at 11.9. `mx check` does not validate that
name. The upstream fix commit states this outright — *"Both checkers passed... the runtime refused
to load the ENTIRE model at boot."*

## Why it cost a day rather than an hour

A six-variant probe had been run to find the trigger boundary, varying `WITH`-clause forms. **Every
arm was graded by `mx check`.** All six passed, so the conclusion was "syntax X is safe" — and all
six were broken in exactly the same way, because the variable that mattered was never varied.

> A control that cannot distinguish your arms will confirm whichever hypothesis you brought.

The probe was well-designed in every respect except the one that counted: nobody asked *what is
this gate actually sensitive to?*

## The rule

**Before trusting a gate to grade an experiment, establish that it can fail for the reason you
care about.** A gate that has never gone red on this defect class has told you nothing.

Cheapest form — a **negative control**: produce one deliberately-broken artifact and confirm the
gate rejects it. If it passes, the gate is blind and the experiment is unscored.

## Gate sensitivity, where it is known

| Gate | Sees | Blind to |
|---|---|---|
| `mxcli check` | MDL grammar | anything about what gets written |
| `mxcli check --references` | referenced names exist | stored structure, storage names |
| `mx check` | model loads + CE-rule validation | wrong `$Type` storage names; DataGrid2 col configs |
| Studio Pro **opens** the model | the loader accepts the file | whether individual activities render |
| Studio Pro **renders the element** | the element is well-formed | runtime behaviour |
| Clicking it in a running app | it actually works | — |

These are a **ladder**, not alternatives. Each rung is blind to things the next one catches, and it
is always tempting to stop at the cheap rung that just went green. For workflows specifically, the
first rung that catches a storage-name defect is *"open it in SP and look at the icons."*

## The tell that should trigger this check

You have a defect that is **visible to a human in one glance** but invisible to every automated
gate. That gap is not luck — it means the gates are structurally blind to the layer the defect
lives in. Find the cheapest human-observable check and put it in the loop, rather than adding
another arm to a probe scored by an instrument that cannot see.

## When a known-good twin exists, diff it

If a hand-built equivalent of the broken artifact exists in the same model, **stop theorising and
diff the stored bytes.** Everything the two share is exonerated; the difference is the bug.

```bash
LC_ALL=C strings -n 3 <hand-built>.mxunit > /tmp/good.txt
LC_ALL=C strings -n 3 <scripted>.mxunit   > /tmp/bad.txt
diff /tmp/good.txt /tmp/bad.txt
```

One line of output, one minute, after a day of syntax hypotheses. A known-good twin beats any
amount of reasoning about what *should* be equivalent.

See [[workflow-patterns]] for the workflow-specific version, and [[sandbox-ab-tool-defect-probe]]
for varying one cause at a time once you have a candidate. Once a defect is verified, see
[[bug-submission-checklist]] for what has to be true before it goes upstream as a filed issue.
