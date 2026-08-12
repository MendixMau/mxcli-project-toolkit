# Grading Rubric — Stage 3 Architecture Gate Happy Path (STUB)

**Scenario ID:** `s3-happy`
**Status:** Stub — fill in after Stage 0 and Stage 2 scenarios are validated.

## What this scenario will test

- Agent does not launch Stage 4 (design) agents in parallel with Stage 3.
- CAC-3 (architecture checkpoint) fires before any architecture HTML is produced.
- Architecture HTML contains: module diagram, fit-gap table, marketplace recommendations, security notes, NFR summary.
- Agent self-declares complete only AFTER gate-check.sh 3 output is pasted in chat.

## Real incident this targets (2026-07-14)

Stage 3 and Stage 4 agents launched in parallel; both self-declared complete with open questions outstanding, no wireframes, gate-check never run.

## TODO

- [ ] Write `input/prompt.md` (input: CONFIRMED BRDs fixture)
- [ ] Write `input/answer-script.md`
- [ ] Write `expected/questions.md`
- [ ] Write `expected/architecture-html.schema.md` (required sections)
- [ ] Score rubric dimensions
