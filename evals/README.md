# Agent Evals Framework

**Purpose:** Catch regressions in agent behaviour — wrong gate questions, missing artifacts, silent skips, wrong routing — before they reach a live project. Each eval is a frozen scenario: a fixture input, a scripted user-answer playbook, and a grading rubric.

**Not in the pipeline.** This directory is never referenced by a stage skill, gate check, or `bin/gate-check.sh`. It exists alongside the pipeline, not inside it.

---

## Mental model

```
input/            ← what the agent receives (source fixture, prior artifacts, PROJECT.md seed)
answer-script.md  ← scripted user replies to every AskUserQuestion the agent should fire
expected/         ← what the agent must produce (artifact shapes, required questions, decisions)
rubric.md         ← pass/fail criteria — the grader reads this, not code
transcripts/      ← gitignored; where a run's raw transcript lands for post-hoc inspection
```

An eval run is:
1. Set up the input (copy fixtures into a temp project dir).
2. Start an agent session with the scenario's `prompt.md` as the opening message.
3. Play the answer script (paste each scripted answer when the agent asks a gate question).
4. After the session, run the assertions in `runner/assertions/` against the produced artifacts.
5. Grade against `rubric.md`.

---

## What we evaluate

| Dimension | What we check | Tooling |
|-----------|--------------|---------|
| **Gate questions fired** | Did the agent call `AskUserQuestion` with the expected questions, in order? | `runner/assertions/check-questions.sh` — diff expected vs transcript |
| **Gate stop** | Did the agent end its turn after each gate question (not answer its own question)? | Transcript inspection — look for agent text after the Q before the user's A |
| **Artifact shape** | Does the produced artifact (PROJECT.md, BRD JSON, architecture HTML, intake.md) contain the required sections/fields? | `runner/assertions/check-artifact.sh` — per-artifact schema |
| **Decision register** | Did `PROJECT.md` get `CONFIRMED`/`ASSUMED` rows for every gate decision? | `runner/assertions/check-project-md.sh` |
| **Live checklist** | Did the agent post the stage checklist in chat and use the right status marks (✅/🔄/⬜/❌/⏭)? | Transcript grep |
| **Routing** | Did the agent propose the correct entry mode for the given fixture? | Rubric — manual check against fixture's expected mode |
| **No premature production** | Did the agent refrain from producing next-stage artifacts before the current gate closed? | Rubric — scan transcript for out-of-order artifact mentions |

---

## Scenario registry

| ID | Stage | Scenario | Gate under test | Status |
|----|-------|----------|----------------|--------|
| `s0-happy` | Stage 0 — Scope | Clean OutSystems source, extractor coverage ≥80% | CAC-1 Scope gate | **draft** |
| `sp-kickoff` | Stage P — Kickoff | New project, migration mode | Stage P / intake | **stub** |
| `s2-brd` | Stage 2 — BRD | Generated KB → BRD scaffold | CAC-2 BRD gate | **stub** |
| `s3-arch` | Stage 3 — Architecture | Approved BRDs → architecture blueprint | CAC-3 Architecture gate | **stub** |

Add new scenarios here as they're built. Each gets a unique ID (`s<stage>-<variant>`).

---

## Running an eval (manual, today)

Until a runner script exists, run evals manually:

```bash
# 1. Set up temp project
cp -r evals/scenarios/stage-0-scope/happy-path/input /tmp/eval-s0/

# 2. Start agent session, paste prompt.md content as the first message
# 3. Play answer-script.md — paste each scripted answer when prompted
# 4. After session ends, run assertions:
bash evals/runner/assertions/check-artifact.sh \
  --artifact /tmp/eval-s0/PROJECT.md \
  --schema evals/scenarios/stage-0-scope/happy-path/expected/project-md.schema.json

# 5. Grade with rubric.md
```

---

## Adding a new scenario

1. Create `evals/scenarios/<stage>-<name>/<variant>/`.
2. Copy the directory layout from an existing scenario.
3. Write `input/prompt.md` — the opening user message the agent sees.
4. Write `input/answer-script.md` — one entry per expected gate question, with the scripted user answer.
5. Populate `input/` with any fixture files (source excerpt, prior-stage artifacts).
6. Write `expected/questions.md` — the exact questions (or question shapes) the agent must ask.
7. Write `expected/` artifact schemas or shape checklists.
8. Write `rubric.md` — pass/fail criteria for a human grader.
9. Add the scenario to the registry table above.

---

## Priority order

Built in order of most regression risk (real incidents drove the order):

1. **Stage 0** — Scope gate: wrong routing (greenfield vs migration) was the most common live regression.
2. **Stage P** — Kickoff: silent self-recording of mode without asking the user.
3. **Stage 2** — BRD gate: premature artifact production before gate closed.
4. **Stage 3** — Architecture gate: parallel stage launch, self-declared complete.
5. Stage 4, 5, 6 as regressions are observed.

---

## What belongs in `transcripts/`

Raw session exports (text or JSON). These are gitignored — they're large and contain run-specific paths. Keep them locally for post-hoc grading; commit only the rubric and the final pass/fail verdict in a `run-log.md` alongside the scenario if you want a record.
