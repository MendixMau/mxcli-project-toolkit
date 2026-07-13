# Query the Model — Source-of-Truth Order Before Any Question or Write

**Applies to:** any mxcli project (migration and greenfield alike).

**Purpose:** Fix the one rule that makes every other gate in `conversion-runbook.md` work: **query the model → read the source → ask the human, in that order, and never skip to the last one.** An agent that asks the user something it could have derived wastes their attention and teaches them to stop trusting the interviews. An agent that guesses instead of querying produces scripts that look right and fail at `mxbuild`, or silently drift from what the Mendix model actually contains.

**Upstream:** none — this is baseline discipline, load before drafting any MDL or running any interview.
**Downstream:** `conversion-runbook.md` (every gate's step 1, "the agent does its homework first", is this skill), `learned-mdl-preflight.md` (STOP rule 8 is one of the two load-bearing query rules below, restated here as a habit rather than a buried table row).

---

## When to Use This Skill

- Before asking the user any question in an interview gate.
- Before writing any `CREATE ASSOCIATION`, or any reference into a marketplace or otherwise-not-yet-imported module.
- Before proposing a recommendation that depends on "what the model currently contains" or "what depends on this."
- Any time you're about to write "I assume..." — stop and check whether a query would turn that assumption into a fact.

---

## The Rule

**Every question has exactly one right source. Answering it from the wrong one is how the pipeline goes quietly wrong.**

| The question is about… | Answer it from | Never from |
|---|---|---|
| What the legacy system *does* | Extracted KB JSON + the source itself | The BRD (it's derived — a summary, not evidence) |
| What the legacy system *means* (intent, business rules, why) | KB docs → then the SME interview (Path C) | The code alone. Intent isn't in code, and inventing it is the single worst failure mode. |
| What the Mendix model *currently contains* | **Query it**: `SHOW ENTITIES`, `DESCRIBE ENTITY`, `SHOW ASSOCIATIONS`, `SEARCH`, catalog OQL | The BRD or the build plan — those say what was *planned*, not what exists. Drift is guaranteed. |
| Blast radius of a change | `SHOW CALLERS / CALLEES / IMPACT OF` | Reading files and hoping |
| A decision (boundaries, buy-vs-build, roles, volumes) | **The user** — via a proposal with evidence | Yourself, silently |

Read is always safe; write goes through the STOP table (`learned-mdl-preflight.md`). Queries (`SHOW`, `DESCRIBE`, `SEARCH`, catalog OQL) never corrupt anything and can run on any path — that asymmetry is why "query first" costs nothing and is worth making a habit, not just a rule you remember under pressure.

---

## The Two Load-Bearing Query Rules

These are already true today; this skill is where they become a discipline instead of trivia buried in a preflight table.

1. **`SHOW ASSOCIATIONS` before every `CREATE ASSOCIATION`.** MDL has no `IF NOT EXISTS` — re-running a CREATE silently duplicates the association, and mxbuild then throws CE0065/CE0069. Only write `CREATE ASSOCIATION` for a name that does not yet appear in `SHOW ASSOCIATIONS` output. (= `learned-mdl-preflight.md` STOP rule 8.)
2. **`SHOW ENTITIES IN <MarketplaceModule>` before writing a single line against a marketplace module.** `mxcli check --references` cannot validate a reference into a module that isn't imported yet, so a guessed entity/attribute name produces a script that passes a naive read-through and fails at `mxbuild`. Query the module's actual contents before referencing it. (Currently buried in `brd-to-build-plan.md`; this is its canonical home.)

---

## How This Feeds the Interview Protocol

`conversion-runbook.md`'s interview protocol step 1 is "the agent does its homework first... anything answerable from the source, the extraction, or the model must be answered from there." This skill is the lookup table for *where* "there" is. A gate that asks "should this module import `Marketplace.Payments`?" without first running `SHOW ENTITIES IN Marketplace.Payments` is asking a question it could partly answer itself — do the query, then ask only the part that's genuinely a decision (buy vs. build), not the part that's a fact (whether the entity exists).

---

## Checklist Before Asking or Writing

- [ ] If the question is about legacy behavior — checked the KB/source, not inferred from the BRD.
- [ ] If the question is about legacy intent — checked KB docs, then queued for SME (Path C) if still open. Never invented from code alone.
- [ ] If the question is about the current Mendix model — ran the actual `SHOW`/`DESCRIBE`/catalog query, not read from BRD or build plan.
- [ ] If about to write `CREATE ASSOCIATION` — ran `SHOW ASSOCIATIONS` first, confirmed the name doesn't already exist.
- [ ] If about to reference a marketplace module — ran `SHOW ENTITIES IN <module>` first.
- [ ] If the question is a genuine decision (boundaries, buy/build, roles, volumes, integrations) — that's the one class of question that *does* go to the user, via a proposal with evidence, not a silent default.
