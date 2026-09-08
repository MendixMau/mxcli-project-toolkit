# Expected Questions — Stage 0 Scope Happy Path

The agent must ask these questions, in this order, during the eval run.
Each entry defines: what the question must contain, what form it takes, and what a grader accepts.

---

## BQ-1 — Scope brainstorm (open conversation, not AskUserQuestion)

**Form:** Free-text agent message, NOT an `AskUserQuestion` call.
**Must contain:**
- A summary of what was found in the source (module count, in-scope vs deferred candidates).
- An explicit invitation to discuss — no option lists.
- At least one of: "What is this project for?", "Full scope or a slice?", "Anything missing from the map?"

**Pass if:** The agent's brainstorm message contains the source summary AND an open-ended invitation (any of the above or equivalent). No `AskUserQuestion` call at this step.

**Fail if:** The agent skips directly to option lists, or fires `AskUserQuestion` here instead of a conversational message.

---

## BQ-2 — Brainstorm convergence check (before moving to predefined questions)

**Form:** Agent reflects back the scope the user described, then asks if it feels right.
**Must contain:**
- A paraphrase of the user's scoping intent (customer portal + reporting, billing deferred).
- A direct question like "Does that feel like the right scope?" or "Shall we lock this and move to the predefined questions?"

**Pass if:** Agent reflects back scope correctly AND asks for convergence confirmation before firing Q1.

**Fail if:** Agent proceeds directly to Q1 without confirming convergence.

---

## Q1 — POC boundary (AskUserQuestion)

**Form:** `AskUserQuestion` call.
**Question text must:** Ask which capabilities should be in scope.
**Options must:**
- Include at least 2–3 options derived from the triage (not generic placeholders).
- Mark one as recommended (smallest shippable slice).
- One option should be "full scope / migrate everything."

**Agent behaviour after Q1:**
- Must **end its turn** and wait for the user's answer.
- Must NOT answer its own question or continue working in the same turn.

**Pass if:** `AskUserQuestion` fired with scope-derived options AND turn ends.
**Fail if:** Agent answers Q1 itself, continues past Q1 without waiting, or uses generic non-fixture-derived options.

---

## Q2 — Extractor strategy (AskUserQuestion, conditional)

**Form:** `AskUserQuestion` call.
**Condition:** Ask only if extractor coverage < 80%. Given the fixture (85% coverage), this question should be **skipped**.

**Pass if:** Q2 is NOT asked (fixture coverage ≥ 80% → skip-eligible).
**Fail if:** Q2 is asked despite the fixture's 85% coverage — this is an unnecessary gate question.

**Grader note:** If the agent does ask Q2 anyway, check whether it correctly notes the existing extractor is recommended. A wrong skip AND a wrong non-skip are both fails, but different kinds.

---

## Open question — external brief (AskUserQuestion or inline)

**Form:** `AskUserQuestion` or inline question in agent message.
**Must ask:** Whether a project brief, stakeholder doc, or Jira epic exists for the target.

**Pass if:** Question is asked in some form after Q1 resolves.
**Fail if:** Question is skipped entirely.

---

## Standing open-floor question (AskUserQuestion or inline)

**Form:** `AskUserQuestion` or inline.
**Must ask:** An open invitation for any remaining concerns — scope, priorities, anything.
**Must appear:** After Q1 and the open question, before the gate closes.

**Pass if:** Open-floor question appears and agent waits for answer before writing `CONFIRMED` decisions.
**Fail if:** Gate closes (decisions written to PROJECT.md) before open-floor question is asked.
