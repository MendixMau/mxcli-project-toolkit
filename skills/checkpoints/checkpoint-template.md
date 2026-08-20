# Checkpoint Template — Context-Aware Checkpoint (CAC)

**Applies to:** All migration pipeline stage transitions.
**Purpose:** Structured human-in-the-loop gate between every major deliverable. Surfaces findings,
previews what's next, asks 2 intelligence-driven questions + 1 open question per deliverable.

**Relationship to `conversion-runbook.md`:** checkpoints are the *mechanism* that implements the
runbook's interview protocol (§1) at each gate — the 2+1 question structure is how "propose with
evidence, then ask" runs in practice. There is **one** decision register: `PROJECT.md` (the
runbook's, scaffolded by `bin/init-project.sh`). Checkpoints write to it; they do not keep a
separate state file. At a `✋` gate, answers must land as `CONFIRMED` — `ASSUMED` defaults are
only allowed at soft gates.

---

## What Every Checkpoint Does

1. **Surface** — Digest of what was just produced (counts, key findings, gaps named)
2. **Project** — What the next stage will do and what it needs from the user
3. **Steer** — 2 predefined questions (inferred from KB/BRD findings) + 1 open question (can't be inferred from code)

Checkpoints are **decision gates, not artifact producers**. They never generate files —
they produce decisions that propagate into the next stage's inputs via `PROJECT.md`.

**Timing and stopping are non-negotiable:** a checkpoint fires *before* the next stage's
artifacts are produced (no architecture diagram before CAC-3, no design system before CAC-4,
no MDL before CAC-5). Ask the questions in chat — on Claude Code via `AskUserQuestion`, on any
other harness as plain numbered markdown (`AskUserQuestion` is a Claude Code built-in and
cannot be installed; see `interview-protocol.md` §3 "Asking on a non-Claude agent") — then
**end the turn and wait, on every harness**. Never answer your own questions and continue: the
stopping is what makes a checkpoint a checkpoint, and it is the half a non-Claude session drops
first. Source evidence powers the recommended option; it never substitutes for asking. `ASSUMED` may only be recorded after
the user was actually asked and delegated ("you decide").

---

## The 2 + 1 Question Structure

### Predefined questions (x2)
- Generated from what the extractor/BRD/KB actually found
- Options are context-derived, not generic
- 3–4 options, rendered with `AskUserQuestion` on Claude Code so answers are clickable; as a
  numbered `1.`/`2.`/`3.` list plus "something else" on any other harness
- Always mark the recommended option clearly

### Open question (x1)
- One per checkpoint, deliverable-specific
- Cannot be answered by reading source code
- Asked as plain text (no predefined options — the answer is too variable)
- Captures what only the human knows: external references, branding, constraints, deadlines

---

## Decision Recording

After the user answers, record every decision in `PROJECT.md` under `## Decisions`, marked
`CONFIRMED` (user answered) or `ASSUMED` (recommended default applied, with the risk if wrong —
per `conversion-runbook.md` §1 step 6). Unanswered open questions go to `PROJECT.md` →
`## Open questions`, not silently dropped. If a BRD or mx-brd file is already open, propagate
relevant answers into `mendixNotes` or `openQuestions[].answer` fields.

Never re-ask a resolved decision in a later stage — **but skipping has two conditions**:
(1) the recorded decision was answered by the user in chat (an agent-recorded `CONFIRMED` the
user never saw doesn't count — re-ask it), and (2) when skipping, **quote the prior decision
back in chat** ("skipping X — you confirmed at Stage 3: '…', PROJECT.md row N") so the user can
veto a decision they don't recognize as theirs.

## Open Floor (every checkpoint, after the 2+1)

Before closing any checkpoint, ask one standing open question — plain text, no options:
> "Anything else you want changed, added, or worried about — scope, priorities, anything?"

CAC-1 (scope) and CAC-5 (build) go further: they **open with a divergent brainstorm** before any
predefined question — present the scope/module map with effort signals and discuss freely
(full scope or slice? what's this for? what's missing?) until the user says it feels right.
See `conversion-runbook.md` §1 "Two open brainstorms".

---

## Checkpoint Format

Present in this order:

```
---
## [Stage Name] Checkpoint

### What we found
[2–4 bullet digest of the previous stage's outputs — counts, patterns, key gaps]

### What's next
[1–2 sentences describing the next stage and what it needs]

---
[Predefined Q1 — AskUserQuestion on Claude Code, numbered options otherwise]

[Predefined Q2 — AskUserQuestion on Claude Code, numbered options otherwise]

[Open Q — plain text]

---
```

Then **end the turn.** The block above is the last thing in the message, on every harness.

---

## The Checkpoints in the Pipeline

**These are wired to STAGES, from `conversion-runbook.md` §2.** They used to be described only in
terms of the migration pipeline's phase numbers, and reachable only from `migration-pipeline.md`
— so a project running no pipeline (requirements-driven, greenfield) fired none of them, and
CAC-1's scope brainstorm silently did not exist outside migration mode. Phase numbers are kept
below as a secondary reference for migration projects; the stage is the wiring.

| ID | Fires at the close of | Phase (migration) | Skill |
|---|---|---|---|
| CAC-1 | Stage 0 — Triage & Scope | Source Triage (Phase 1) | `checkpoint-scope.md` |
| CAC-1b | Stage 1 — Analysis | after extraction, before any BRD | `checkpoint-extraction.md` |
| CAC-2 | Stage 2 — BRD scaffold | BRD Scaffold (Phase 3) | `checkpoint-brd.md` |
| CAC-3 | Stage 2 — BRDs validated | BRD Enrichment + Validation (Phase 5) | `checkpoint-architecture.md` |
| CAC-4 | Stage 3 — Architecture & Design | Architecture sign-off (Phase 6) | `checkpoint-design.md` |
| CAC-5 | Stage 4 — Build Plan | Design sign-off (before Phase 7 MDL gen) | `checkpoint-build.md` |
| CAC-6 | Stage 6 — Test | before Stage 7 cutover — `✋`, CONFIRMED only | `checkpoint-cutover.md` |

---

## Intelligence Rules (How to Generate Predefined Options)

Each checkpoint's predefined questions must be derived from actual findings. The generating skill
specifies which KB/BRD fields to inspect. General rules:

- If a source pattern has a direct Mendix equivalent, offer that as recommended
- If source used a pattern that has multiple Mendix mappings, offer the 2–3 realistic options
- If a finding is ambiguous, say so in the option label rather than hiding it
- Never offer an option that isn't a real choice (no "TBD" options)

Example — if KB entities.json shows a `balance` field updated on every transaction:
> "User.Balance is stored per-user and updated on every transaction. How should we handle concurrent updates?"
> - A) Single microflow with commit + rollback-on-failure *(recommended — simplest)*
> - B) Calculate balance from transaction history on-read (no stored field)
> - C) Flag for tech review before deciding

---

## When to Skip a Checkpoint

A checkpoint may be skipped if:
- All its predefined questions can be answered from already-recorded decisions in `PROJECT.md`
- The open question has already been answered (e.g. user provided a Figma link earlier)

In that case, show a one-line summary ("Scope checkpoint: all decisions already recorded — proceeding")
and continue. Never silently skip a checkpoint without acknowledging it.
