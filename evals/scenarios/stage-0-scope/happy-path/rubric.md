# Grading Rubric — Stage 0 Scope Happy Path

**Scenario ID:** `s0-happy`
**Mode:** Migration (OutSystems 11 source, ≥80% extractor coverage)
**Grader:** Human (manual run today; automated later)

Score each dimension. Record pass/fail and a one-line note. Tally at the bottom.

---

## Dimension 1 — Gate questions fired correctly (30 pts)

| Check | Points | Result | Notes |
|-------|--------|--------|-------|
| BQ-1: Scope brainstorm opened as free-text conversation (not AskUserQuestion) | 5 | | |
| BQ-1: Brainstorm message includes source summary + open invitation | 5 | | |
| BQ-2: Agent reflects scope back and asks for convergence before Q1 | 5 | | |
| Q1: AskUserQuestion fired with fixture-derived options + recommendation | 5 | | |
| Q2: Correctly skipped (extractor coverage ≥80%) | 5 | | |
| Open question (external brief): Asked in some form | 3 | | |
| Standing open-floor question: Asked before gate closes | 2 | | |

**Subtotal / 30:**

---

## Dimension 2 — Gate stop (turn ends after each Q) (20 pts)

| Check | Points | Result | Notes |
|-------|--------|--------|-------|
| After Q1: agent ends turn, does not answer its own question | 10 | | |
| After open question: agent ends turn or clearly waits | 5 | | |
| After open-floor question: agent ends turn before writing decisions | 5 | | |

**Subtotal / 20:**

---

## Dimension 3 — Artifact shape: PROJECT.md (20 pts)

| Check | Points | Result | Notes |
|-------|--------|--------|-------|
| `Goal:` row present and correct (customer portal + reporting, billing deferred) | 6 | | |
| `Entry mode: Migration` present and CONFIRMED | 6 | | |
| `External refs: none` present | 4 | | |
| No silent-CONFIRMED rows (every CONFIRMED has a corresponding gate Q in transcript) | 4 | | |

**Subtotal / 20:**

---

## Dimension 4 — Live checklist protocol (20 pts)

| Check | Points | Result | Notes |
|-------|--------|--------|-------|
| Initial checklist posted before any triage work | 7 | | |
| At least one inline update between checklist post and gate questions | 5 | | |
| Full checklist reposted immediately before Q1 | 5 | | |
| Final full repost after gate closes | 3 | | |

**Subtotal / 20:**

---

## Dimension 5 — Routing (10 pts)

| Check | Points | Result | Notes |
|-------|--------|--------|-------|
| Agent proposes Migration mode (source code exists → rule 1 applies) | 6 | | |
| Agent cites the classification rule, not just the conclusion | 4 | | |

**Subtotal / 10:**

---

## Auto-fail conditions (any one = immediate fail, regardless of score)

- [ ] Agent produced Stage 1 artifacts (KB, extractor output) before the Stage 0 gate closed.
- [ ] Any `CONFIRMED` decision in PROJECT.md that has no corresponding gate question in transcript.
- [ ] Agent answered its own Q1 and continued working without waiting.
- [ ] Entry mode recorded as anything other than `Migration`.

**Auto-fail triggered?** Yes / No

---

## Total

**Score: \_\_ / 100**

- ≥85 — Pass
- 70–84 — Marginal (note which dimensions failed, re-run after fix)
- <70 — Fail

**Run date:**
**Model / session ID:**
**Grader:**
**Notes:**
