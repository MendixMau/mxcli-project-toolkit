# Grill mode

**Applies to:** any mxcli project, any stage, any harness.

**Purpose:** an on-demand, sustained, adaptive Q&A session on one topic — for when the user
believes there isn't enough context yet and wants to be pushed on it hard, as opposed to a
checkpoint's fixed 2+1 (`skills/checkpoints/*.md`) or a single batch of open questions.

## Trigger

The user invokes it explicitly, at any moment, from any stage — "grill me on the security
model", "grill mode: architecture", "I don't think we have enough on X, dig in." This is
on-demand, not gate-fired. It does not replace a checkpoint (CAC) and a checkpoint does not
replace it: a CAC fires once, at a fixed transition, with exactly 2+1 questions and no
follow-up. Grill mode fires whenever asked, keeps going, and follows up on what it hears.

## Loop mechanics (loop-until-dry)

1. **Scope the topic.** If it maps to one or more `bin/source-sufficiency.sh` dimensions
   (`actors`, `domain`, `processes`, `rules`, `ui`, `integrations`, `nfr`, `tenancy`,
   `security_model`, `data_migration` — e.g. "security" → `security_model`, "architecture" →
   `tenancy` + `integrations` + `nfr`), read the current rubric row(s)
   (`analysis/source-sufficiency.json`) for their `demands`/`evidence`/`consequence` text
   first. Grill mode targets exactly the gap the rubric already named — it does not re-derive
   the topic from scratch. If the topic doesn't map to a dimension (e.g. "branding"), proceed
   topic-first with no rubric tie-in.
2. **Generate one batch of 3-5 sharp, specific questions.** Same rendering rule as everywhere
   else in this toolkit — see `skills/interview-protocol.md` §3: `AskUserQuestion` on Claude
   Code; plain numbered markdown with a "something else" option on any other harness. Every
   question carries two named options plus your recommendation, same as a checkpoint question.
   **Then end the turn and wait.** This is non-negotiable — the same rule every checkpoint
   already follows.
3. **Record every answer immediately**, one row per question, in the project's existing
   question log (`analysis/sme-questions.md` if the project has one, else the nearest
   equivalent this project already uses) — the exact table shape `bin/open-questions.sh`
   already parses:

   | id column | a question column | a Decision / Resolution / Status / Answer column |
   |---|---|---|
   | matches `[A-Z][A-Za-z0-9]*(-[A-Za-z0-9]+)*` with at least one digit, e.g. `GRILL-SEC-01` | the question as asked | the user's answer, verbatim or lightly cleaned up — "Not relevant" and its synonyms are valid answers, see rule 7 in `bin/open-questions.sh` |

   This is the one-decision-register rule (`CLAUDE.md` → "One decision register") applied to
   grill mode: it must not become a fourth place questions can rot in. No new file, no new
   script — append the row by hand, the same way you would append any other question to that
   file.
4. **Follow up adaptively.** Any answer that is hedged, vague, contradicts an earlier answer,
   or raises a new gap generates a sharper, more specific follow-up question in the *next*
   batch. This is what distinguishes grill mode from a checkpoint, which never follows up — the
   whole point of asking is to keep pulling on a thread until it's either resolved or explicitly
   dropped by the user.
5. **If the topic is rubric-tied, update the touched dimension row(s)** in
   `analysis/source-sufficiency.json` (`evidence`, `consequence`, and `rating`) at the end of
   the session, so the improvement is visible to `bin/source-sufficiency.sh report` afterward
   without a separate re-grading pass. Don't inflate the rating past what was actually
   established — an answer that names a vendor with no contract behind it is still `named`, not
   `specified` (see the instrument's own weighting note for why `named` scores nothing).

## Stop conditions (first one hit wins)

- The user explicitly says stop / enough / that's fine / move on.
- Two consecutive batches produce zero new questions worth asking — the topic is dry.
- If rubric-tied: every touched dimension has reached `specified` or `verified`.

Whichever one fires, close with one line naming which stop condition it was and how many
questions/answers were recorded this session, so the session has a legible end instead of
trailing off. If it stopped rubric-tied, mention the new band/pct so the user sees the effect
(`bin/source-sufficiency.sh report <project-dir>`).

## What this is not

- Not a new state file or a new schema — see step 3.
- Not a script. Generating sharp questions and judging which answers are hedgy is judgement,
  not a fact a script can fetch; see `skills/skills-over-scripts.md` for the boundary this
  toolkit draws between instruments (scripts) and instructions (skills).
- Not a replacement for `bin/gate-check.sh`'s Open Questions or Source Sufficiency checks —
  those are what a gate mechanically verifies; grill mode is how you close the gap those
  checks would otherwise catch as a FAIL.
