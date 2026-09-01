# Wizard Walkthrough — generated interactive scripts for human-only steps

**Applies to:** any mxcli project
**Purpose:** when a task ends in steps only the human can perform, generate a small paced
bash walkthrough instead of dumping a prose checklist — so each step is confirmed (and
verified where the shell can verify it), leaving a machine-readable record.

**Status: experimental — hypothesis, no field run yet.** Routed at the experimental tier
on purpose: discoverable, but never the reason a gate fails. The hypothesis to test on the
next real cutover: does the walkthrough form measurably beat the checklist form (steps
actually done vs. reported done)? That is the self-graded-vs-instrumented gap the
obligation check exists for, applied to human steps. After the first field run, either
promote this to ondemand with the evidence cited, or tombstone it. (Pattern credit: Matt
Pocock's public `wizard` skill — pattern only, no text copied.)

## The failure this prevents

A prose checklist reports "done" at the granularity of the whole list: the human skims,
the agent trusts the skim, and nothing distinguishes a step performed from a step read.
The toolkit already refuses that shape everywhere a script can check — this extends the
refusal to steps a script *cannot perform* but can still pace and often verify.

## When to reach for it

Steps that are genuinely human-only, arriving as a batch at a known moment:

- **Stage 7 cutover** — DNS, user comms, Team Server settings the agent cannot touch.
  Generate `cutover-walkthrough.sh` next to the register; its confirmation log gives the
  obligation check something to point at instead of trusting prose sign-off.
- **GitHub settings at project setup** — branch protection and the LEAKGUARD_DENY secret
  are browser-only; `init-project.sh` can only print advice. A walkthrough collects an
  explicit y/N per step, and verifies via the API where a token exists.

One or two human steps do not need a wizard — ask in chat. The form pays off when the
list is long enough to skim.

## Shape of a generated walkthrough

Per step, in order:

1. **Print the step** — one action, the exact place to do it (URL, menu path), and what
   "done" looks like.
2. **Wait** — Enter to continue, or an explicit `y/N` where the step can be declined;
   a declined step is recorded as declined, never silently skipped.
3. **Verify what the shell can verify** — curl the endpoint, check the file appeared,
   query the API. Where nothing is verifiable, the human's `y` is the record — say so in
   the log line (`confirmed-by-human`, not `verified`).
4. **Append a timestamped line** to a log file beside the script before advancing.

The log is the artifact: which steps were confirmed, which verified, which declined, when.
Write it where the consuming check expects it (for cutover, next to `PROJECT.md`), and
name that consumer in the script's header — an artifact without a reader is the
design-audit.js lesson.
