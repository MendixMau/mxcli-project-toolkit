# Expected Live Checklist Behaviour — Stage 0 Scope Happy Path

Grader checks the transcript for these chat-visible checklist events.

---

## Initial post (must appear before any triage work starts)

The agent must post a Stage 0 checklist in chat **before** the first unit of work.
Accept any format that includes these items (or equivalents), with status marks:

```
Stage 0 — Source Triage
⬜ 1. Load source-triage.md and scan source directory
⬜ 2. Classify modules (business vs framework)
⬜ 3. Build capability map + extractor coverage
⬜ 4. Present triage results in chat
⬜ 5. Run scope brainstorm
⬜ 6. CAC-1 Scope checkpoint (Q1 + open question)
⬜ 7. Write decisions to PROJECT.md
⬜ 8. Run gate-check.sh and paste output
```

**Pass:** Checklist posted at stage start with ⬜ (or equivalent pending mark) for all items.
**Fail:** Agent begins triage work without posting a checklist first.

---

## Incremental updates (during the stage)

After each item completes, a one-line update must appear in chat:
- Example: "✅ 2/8 — 18 modules classified, 4 business, 14 framework."
- Must not go more than 2 completed items without a chat line.

**Pass:** At least one inline update visible between checklist post and gate questions.
**Fail:** Agent completes triage and posts gate questions with no intermediate updates (silent stretch).

---

## Full repost before gate

The agent must repost the **full checklist** with updated marks immediately before firing Q1.

**Pass:** Full checklist reposted with ✅ marks for completed triage items and ⬜/🔄 for remaining gate steps.
**Fail:** Agent fires Q1 without a full checklist repost.

---

## Final repost before gate closes

After the last answer (open-floor) and before writing decisions, the agent reposts the final checklist with all items ✅ or ⏭ (with reason).

**Pass if:** Final repost shows full stage completion.
**Fail if:** Gate closes (PROJECT.md written) without a final checklist repost.
