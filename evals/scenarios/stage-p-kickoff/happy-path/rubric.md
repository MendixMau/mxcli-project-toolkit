# Grading Rubric — Stage P Kickoff Happy Path (STUB)

**Scenario ID:** `sp-happy`
**Status:** Stub — fill in after Stage 0 scenario is validated.

## What this scenario will test

- Agent opens `toolkit-guide.html` in the browser at kickoff.
- Agent runs `bin/init-project.sh` to scaffold the project.
- Agent fires the intake interview (8 questions, no guesses).
- Entry mode proposed with evidence, confirmed before any stage work starts.
- `PROJECT.md` has `Entry mode: Migration` CONFIRMED.
- All five agent stubs created via `bin/init-agents.sh`.

## Anti-fail conditions (for when this is fleshed out)

- Agent skips `toolkit-guide.html` open.
- Agent self-records entry mode without asking.
- Agent starts Stage 0 before kickoff gate closes.

## TODO

- [ ] Write `input/prompt.md`
- [ ] Write `input/answer-script.md`
- [ ] Write `expected/questions.md`
- [ ] Write `expected/project-md.schema.md`
- [ ] Score rubric dimensions
