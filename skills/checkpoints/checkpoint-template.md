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
no MDL before CAC-5). Ask the questions in chat via `AskUserQuestion`, then **end the turn
and wait** — never answer your own questions and continue. Source evidence powers the
recommended option; it never substitutes for asking. `ASSUMED` may only be recorded after
the user was actually asked and delegated ("you decide").

---

## The 2 + 1 Question Structure

### Predefined questions (x2)
- Generated from what the extractor/BRD/KB actually found
- Options are context-derived, not generic
- Use `AskUserQuestion` with 3–4 options so answers are clickable in the UI
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

Never re-ask a resolved decision in a later stage. If a decision is found already recorded in
`PROJECT.md`, skip that question.

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
[Predefined Q1 — via AskUserQuestion]

[Predefined Q2 — via AskUserQuestion]

[Open Q — plain text]

---
```

---

## The 5 Checkpoints in the Pipeline

| ID | Fires After | Skill |
|---|---|---|
| CAC-1 | Source Triage (Phase 1) | `checkpoint-scope.md` |
| CAC-2 | BRD Scaffold (Phase 3) | `checkpoint-brd.md` |
| CAC-3 | BRD Enrichment + Validation (Phase 5) | `checkpoint-architecture.md` |
| CAC-4 | Architecture sign-off (Phase 6) | `checkpoint-design.md` |
| CAC-5 | Design sign-off (before Phase 7 MDL gen) | `checkpoint-build.md` |
| CAC-6 | Test pass (before Stage 7 cutover — `✋`, CONFIRMED only) | `checkpoint-cutover.md` |

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
