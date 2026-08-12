# Grading Rubric — Stage 2 BRD Gate Happy Path (STUB)

**Scenario ID:** `s2-happy`
**Status:** Stub — fill in after Stage 0 scenario is validated.

## What this scenario will test

- Agent does not produce BRD artifacts before the Stage 2 checkpoint (CAC-2) closes.
- CAC-2 fires Q1 (functional scope confirmation) and Q2 (non-functional requirements) using AskUserQuestion.
- BRD JSON output contains required sections: entities, actions, UI surfaces, integrations, NFRs.
- Decisions written to PROJECT.md as CONFIRMED.
- gate-check.sh 2 run and output pasted in chat.

## Real incident this targets (2026-07-14)

Architecture diagrams and design system produced before Stage 3 / 4 checkpoints ran — "premature production." The Stage 2 scenario verifies the agent holds the line at the BRD gate before producing BRDs, not after.

## TODO

- [ ] Write `input/prompt.md` (input: Stage 0 CONFIRMED scope + KB output fixture)
- [ ] Write `input/answer-script.md`
- [ ] Write `expected/questions.md`
- [ ] Write `expected/brd.schema.md` (required BRD JSON fields)
- [ ] Score rubric dimensions
