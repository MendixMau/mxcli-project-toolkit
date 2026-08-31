# Generated interactive walkthroughs for human-only steps (steal from mattpocock/skills `wizard`)

**From:** public repo review — mattpocock/skills (`wizard` skill), MIT-licensed
**Date:** 2026-08-31
**Kind:** skill-draft
**Field evidence:** none in this toolkit yet — this is a pattern observed in a public skill repo, not a field finding. Labelled hypothesis until a project runs one.
**Proposed target:** Stage 7 cutover checklist (`skills/checkpoints/checkpoint-cutover.md`) and `bin/init-project.sh`'s GitHub-settings guidance

---

The `wizard` pattern: when a task ends in steps only the human can perform (clicking
through a vendor UI, approving a setting, plugging in a device), the agent does not dump
a prose checklist — it **generates a small interactive bash script** that walks the human
through the steps one at a time: print step, wait for Enter/confirmation, verify what is
verifiable from the shell (curl the endpoint, check the file appeared), then advance.
The human gets pacing and per-step verification; the agent gets a machine-readable record
of which steps were actually confirmed rather than skimmed.

Where this toolkit has exactly that shape today:

1. **Stage 7 cutover** — DNS/user-comms/Team Server steps the agent cannot do. Today the
   checkpoint emits a checklist; a generated `cutover-walkthrough.sh` could confirm each
   step and leave a timestamped confirmation log next to the register (which also gives
   the obligation check something to point at, instead of trusting prose sign-off).
2. **GitHub settings at project setup** — branch protection and the LEAKGUARD_DENY secret
   are browser-only steps that `init-project.sh` can only print advice about. A wizard
   could verify each one afterwards via the API where a token exists, or at minimum
   collect an explicit y/N per step.

Hypothesis to test on the next real cutover: does the walkthrough form measurably beat
the checklist form (steps actually done vs. reported done)? That is the same
self-graded-vs-instrumented gap the obligation check exists for, applied to human steps.

Credit: Matt Pocock's public skills repo — pattern only; no text copied.
