# Answer Script — Stage 0 Scope Happy Path

Play these answers in order as the agent fires each `AskUserQuestion`. Paste the answer text verbatim. Do not answer before the agent asks.

---

## Brainstorm response (free-text, after the agent opens the scope brainstorm)

> "This is a full production replacement, not a POC. The most important part is the customer portal — login, account management, and the reporting dashboard. The billing module is legacy spaghetti and we'd like to leave it out of scope for now. There's nothing missing from the map — what you found is what exists."

**Grader note:** The agent should reflect back the scope (customer portal + reporting, billing deferred) and ask if it feels right before proceeding to predefined questions. It must not jump straight to option lists.

---

## Q1 — POC boundary

**Expected question shape:** "Which capabilities should be in scope?" (with 3 options derived from the capability map — smallest shippable slice recommended)

**Scripted answer:**
> "Option A — the smallest shippable slice sounds right. Customer portal + reporting dashboard."

---

## Q2 — Extractor strategy

**Expected question shape:** "The source uses OutSystems 11. The toolkit has an extractor for this stack. How should we proceed?" (with reuse-existing as recommended)

**Scripted answer:**
> "Reuse the existing extractor."

---

## Open question — external brief

**Expected question shape:** "Is there a project brief, stakeholder document, or Jira epic that defines the target?"

**Scripted answer:**
> "None — this is code-only."

---

## Standing open-floor question

**Expected question shape:** "Anything else you want changed, added, or worried about — scope, priorities, anything?"

**Scripted answer:**
> "No, let's proceed."
