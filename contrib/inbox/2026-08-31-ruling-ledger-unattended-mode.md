# "Ruling:" ledger for unattended runs (steal from obra/superpowers)

**From:** public repo review — obra/superpowers, MIT-licensed
**Date:** 2026-08-31
**Kind:** process
**Field evidence:** none here yet — pattern observed in a public skill repo. This toolkit's own `ASSUMED` mechanism is the adjacent, weaker form.
**Proposed target:** `skills/interview-protocol.md` (unattended mode section); register conventions in `skills/conversion-runbook.md`

---

In superpowers, an agent running without a human answers its own blocked questions but must
log **every** self-made decision in a fixed one-line shape — effectively
`Ruling: <what was decided> — <why> — <cost if wrong>` — so the human reviews a compact
decision ledger afterwards instead of reconstructing choices from the diff.

This toolkit's `Interview mode: unattended` currently says gate questions may be
self-answered and recorded as `ASSUMED`. Two upgrades the Ruling form offers:

1. **The "cost if wrong" field.** An `ASSUMED` line records the decision and sometimes the
   reason; it never records the blast radius. "Cost if wrong: Stage 5 rework of one page"
   vs "cost if wrong: domain model rebuild" is exactly what the human needs to prioritise
   which assumptions to review first when they return.
2. **Coverage beyond gate questions.** `ASSUMED` only exists at interview/checkpoint
   moments. An unattended session makes dozens of smaller calls (naming, module placement,
   which workaround to apply) that today land nowhere. The Ruling discipline is "every
   self-made decision of consequence gets a line", not "every gate question".

Concrete proposal for triage: in unattended mode, `PROJECT.md` gains a `## Rulings
(unattended)` section; every `ASSUMED` register line and every consequential non-gate
decision appends `Ruling: what — why — cost if wrong`. The human's re-entry ritual is
reading that section top to bottom.

Fits the existing rule that `ASSUMED` is earned by asking — in unattended mode nobody can
be asked, so the ledger is the compensating control.

Credit: obra/superpowers — pattern only; no text copied.
