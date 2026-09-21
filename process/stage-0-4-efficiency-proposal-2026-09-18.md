# Stages P–4 efficiency — proposal (2026-09-18, re-verified 2026-09-21)

**Status:** proposal, draft PR. Most of the original plan has since shipped on master under its
own commits (table below) — this revision keeps only what has not. Nothing here is adopted
until merged and field-run.
**Prompt:** users report that Stages 0–4 (triage → build plan) burn too many tokens and too much
wall-clock, and asked for more parallel fan-out and for cheap-vs-capable model choice by purpose
and importance ("cheap is not always the answer").
**Evidence base:** `process/token-path-ab-2026-09-09.md` (A/B, three corpora); the routing table
(`bin/lib/skill-routing.tsv`, `bin/render-routing.sh --check`); the runbook's dispatch table
(`skills/conversion-runbook.md` §1c) and its tier section, "Three tiers, not three product
names"; and PR #99 (`claude/stage-sliced-baseline`, open, not yet merged), which reslices the
baseline pack per stage and adds a Stage-5 dispatch obligation — cited below wherever it
overlaps an item still open here.

---

## Already landed — do not re-propose these

Verified against `origin/master` (commit `7437053`) on 2026-09-21. Each row is the original
proposal item, superseded by a real commit.

| # | Original ask | Shipped as | Where |
|---|---|---|---|
| P1 | Deliver the model tiers so subagents don't inherit the main session's model | Agent templates in `skills/agent-roles.md` are pinned (not `model: inherit`), matching the tier each stub in `agents/*.md` already carries; `bin/sync-project.sh` warns on a completed agent whose model drifted from the toolkit's, with `--pin-models` to fix it | `skills/agent-roles.md` (frontmatter of all six templates, plus the note that pinning is the rule); `bin/sync-project.sh` (`--pin-models` flag, drift warn/pin logic) |
| P4 | A real cost instrument, not a word-count proxy | `bin/token-burn.sh` — sums transcript tokens by model and by day, cache-read shown separately, per-cwd attribution, `NOT AVAILABLE` (exit 0) where no transcript tree exists; `bin/status.sh --brief` gained a tokens-this-stage line | `bin/token-burn.sh`; `bin/status.sh`; fixture at `tests/wave2/test-token-burn.sh` + `tests/wave2/fixtures/token-burn/` |
| P5 | A small-project tier so a 3-file corpus doesn't pay the full artifact set | `skills/small-project-tier.md` — declared at CAC-1 (never inferred from a thin sources folder), bounds given (1 module, ≤8 screens, ≤25 use cases), waiver register lines a project un-waives explicitly if it grows | `skills/small-project-tier.md`; `skills/checkpoints/checkpoint-scope.md` (CAC-1 gained a conditional Q3); `bin/gate-check.sh` reads the waivers |
| §5 | "Model choice by purpose" written as a table with vendor names | Landed instead as prose in the runbook itself, purpose-first and vendor-name-free: three tiers (cheap / mid / strong) defined by the check that follows the unit, a harness-mapping table (Claude Code stub aliases vs. "the vendor's small/standard/largest reasoning tier" for every other harness), the same-tier-retry rule, and the effort/context cost ordering this proposal's §1.2 word counts fed into | `skills/conversion-runbook.md` §1c, "Three tiers, not three product names" |

§1.2's own "Unreconciled" three baseline word counts (78,124 / 77,774 / 72,001) are also
resolved, not by this proposal: PR #99 traced the spread to locale (`wc -w` under a UTF-8
locale counts ~1,900 words more than under `LC_ALL=C`) and pinned the count to `LC_ALL=C`
everywhere, in `bin/render-routing.sh`.

---

## What's still open

Four items from the original eight survive contact with current master. Numbering kept from
the original doc so old discussion still points at the right thing.

### P2 — Read the span, not the file (gap: whole-runbook reads)

Still open, though PR #99 narrows it. PR #99 adds a per-stage `ADVISORY baseline pack: <n>
words across <m> files` line to `bin/gate-check.sh` — but it prints at the **end** of a gate
check, after the stage's work is already done, and it's a word count, not a citation. The
runbook itself (`skills/conversion-runbook.md` line 62) still tells the reader "read §1b + your
own stage section", and nothing enforces that at the point a session actually opens the file.

- `bin/status.sh --brief` (session-start, before the stage begins — not `gate-check.sh`,
  end-of-stage) prints `Read for this gate: <file> lines A–B`, using the same span the gate
  already computes for its own end-of-check print (`gate-check.sh`'s `RB_STAGE` span logic —
  reuse it, don't reimplement it).
- `checkpoints/checkpoint-*.md` and the agent stubs cite that span form, never "read the
  runbook".
- Check: no baseline/routing row or stub says "read `conversion-runbook.md`" with no section
  qualifier. `bin/render-routing.sh --check` stays green.
- Overlap with PR #99: once #99 merges, `routing_baseline_pack()` in
  `bin/lib/skill-routing.sh` is the one place both the end-of-gate advisory and this
  start-of-stage span should read from, so they report the same number from the same function.
- Risk: a session that needs another stage's section still has to go find it; that's already
  true today.

### P3 — Enforce §1c at the gate (gap: fan-out is prose, not checked)

Still open for Stages 1–4. PR #99 ships a **dispatch obligation** — but it is scoped to Stage 5
only (`bin/lib/obligations.tsv`: `dispatch  mdl  module  ...  5  agents/mdl-agent.md` — one
mark per module, owed by `mdl-agent`, proving a script was dispatched instead of drafted
inline). That is the same *mechanism* this item needs, one stage earlier than where it's
already landing.

- Extend the obligation-check pattern PR #99 establishes to Stages 1–4: one register line per
  fan-out batch (`Dispatch <stage>: <n> units, <tier>, <check>, <date>`), written by the main
  session when it spawns the batch. Missing line → `PENDING` with the §1c row printed;
  `Dispatch <stage>: single-session, reason: <harness>` is the legal opt-out for harnesses
  without subagents.
- Add the row(s) to `bin/lib/obligations.tsv` once #99's row is in and its shape is proven in
  the field, rather than inventing a second dispatch-obligation shape in parallel.
- Check: fixture with the line present / absent / opted-out, mirroring PR #99's own
  `test-bug12-sync.sh` treatment of its Stage-5 row; field run on one project.
- Risk: one more register line per stage. It is also the input P4's per-stage cost
  attribution wants next: `token-burn.sh` already has a stage-attribution TODO for `Dispatch`
  lines once they exist.

### P6 — Batch the interview stops in Stage P/0 (gap: wall-clock, not tokens)

Still open. `interview-protocol.md` §3 ("Batch per gate, then end the turn and wait") batches
questions at the six stage-transition checkpoints, but Stage P's own intake mechanism
(`bin/lib/intake-template.sh`) still asks one question, ends the turn, and waits, repeated
across all eight intake questions — the batching rule was never extended upstream of the first
checkpoint.

- `bin/lib/intake-template.sh` / the Stage P skill: collect Stage P's intake questions into one
  turn, same shape as a CAC checkpoint, not one round-trip per question.
- Not a token change; it is the wall-clock people feel before the pipeline does anything.
- Check: read `intake-template.sh` after the change — it should read like a CAC prompt (one
  block, all questions, "something else" available), not a loop.

### P7 — Pilot-one-rep rule, for rate limits

Still open, still text-only. Before any fan-out wider than 3 units, run one unit, read its cost
with `bin/token-burn.sh` (now that it exists — this item was blocked on P4, which has since
shipped), then dispatch the rest. No "pilot" language exists anywhere in `agent-roles.md`,
`conversion-runbook.md` §1c, or `README.md` today. Add one paragraph to §1c's dispatch table
preamble. The incident that motivated it stands: a fan-out that skipped this hit a provider
rate limit mid-run and spent for a batch that never finished.

### P8 — Bundled-skill tax — unchanged, still out of scope here

21k words of mxcli-bundled "read first" skills load for MDL-writing sessions (Stage 5+, not
Stages 0–4, so it was never this document's target — noted only so nobody attributes it to the
stages this proposal covers). Still a separate PR against upstream's file set, not this
toolkit's.

---

## Order

**P3 next**, because it is now an extension of a mechanism PR #99 is already landing rather
than a new one — reuse its obligation shape, don't invent a second. **P2 and P6 are text-only**
and can land alongside it. **P7 is a paragraph**, blocked on nothing now that P4 is shipped.
**P8 stays a separate PR.**

Not proposed, unchanged from the original:

- **No automatic model switching, no per-token budgets in code.** Thresholds without data are
  the unfalsifiable-checklist defect; `bin/token-burn.sh` now produces the data a later PR
  could propose numbers from.
- **No new fan-out for Stages P and 0.** They are interview stages by design.
- **No rewrite of §1c or the stage matrix.** It has already been rewritten once since this
  proposal was drafted (the tier section, 2026-09-19) — text that keeps changing under a
  hunch is exactly what CLAUDE.md's authoring rule 2 warns against; the remaining asks here
  are additive (a dispatch obligation, a span print), not another rewrite of the table.
- **No full-suite reruns to prove any of this.** Each item names its scoped check.

## Open questions for the maintainer

1. P3's register line: one line per batch, or one per stage with a count? PR #99's Stage-5
   `dispatch` obligation is per-module, not per-batch — should Stages 1–4 match that shape
   (one line per module/unit) instead of the per-batch shape this proposal originally
   suggested, so all dispatch obligations look the same in `PROJECT.md`?
2. Does `token-burn.sh`'s existing `UNMAPPED` bucket stay until P3 lands, or is a rough
   date-based stage attribution (already implemented) good enough to ship P4's reporting line
   without waiting on P3 at all? (It already shipped without waiting — this just asks whether
   that was the right call or whether P3 should be pulled forward.)
3. P5 shipped with concrete bounds (1 module, ≤8 screens, ≤25 use cases) rather than the
   placeholder this proposal floated — is that calibration considered final, or does it want a
   revisit once `token-burn.sh` has data from a few more small projects?
