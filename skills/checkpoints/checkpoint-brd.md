# CAC-2 — BRD Checkpoint

**Fires after:** Phase 3 BRD Scaffolding
**Feeds into:** Phase 5 BRD Enrichment + Validation
**Template:** See `checkpoint-template.md` for format rules.

---

## What to Surface

Pull from `knowledge-base/brd/*.brd.json` scaffold output:
- Number of BRDs generated and which capabilities they cover
- Total entity / logic / screen counts from KB
- Any `fk-unresolved` gaps or `openQuestions` already flagged by the mapper
- Source patterns that the mapper tagged as ambiguous (e.g. soft-delete, multi-tenant, computed fields)

## What's Next

Phase 5 enriches the scaffold BRDs with business rules, use case narratives, and any Path B
document knowledge. This is the stage where human input matters most — the scaffold is structural,
the enrichment is semantic.

---

## Predefined Questions

### Q0 — Capability grouping (ask FIRST — enrichment order is meaningless on wrong units)

**When to ask:** Whenever `brd/grouping-proposal.md` exists (java-angular / node-express-react pipelines write it at Phase 3).

**How to generate options:** Read the proposal table. Surface (a) how many raw packages became how many capability BRDs, (b) every raw name left *(unchanged)* that looks technical (`api`, `events`, `state`, …) — those had no path evidence and are the likeliest misgroupings.

> "The mapper grouped 19 packages into 17 capability BRDs (proposal attached). `api` and `events` couldn't be grouped automatically — where do they belong?"
> - A) Accept the proposal as-is; fold `api`/`events` into [nearest capability from context] *(recommended if evidence supports it)*
> - B) Accept the proposal but keep `api`/`events` separate for now — regroup at Stage 3
> - C) Adjust: [specific corrections] → set `config.json` → `brdGrouping` and re-run Phase 3

**Record as:** `PROJECT.md` → `## Decisions` → `BRD grouping:` — and if corrections were made, re-run Phase 3 *before* Q1, then confirm the regenerated set. Note: this fixes BRD granularity only; Mendix module boundaries are still Stage 3's decision (`modularize-domain.md`).

### Q1 — Use case coverage priority

**When to ask:** Always.

**How to generate options:** Look at screen count per BRD and logic count per BRD. Surface the
BRD with most screens/logics as the "most complex." Offer priority ordering options.

> "We scaffolded [N] BRDs covering [capabilities]. Which should we enrich first?"
> - A) [Highest dependency BRD — e.g. Auth/Users] — all other BRDs depend on it *(recommended)*
> - B) [Largest feature BRD by screen count] — get the core user flow detailed first
> - C) Enrich all in parallel — fastest if scope is small (< 4 BRDs)

**Record as:** `PROJECT.md` → `## Decisions` → `BRD enrichment order:`

---

### Q2 — Flagged source patterns

**When to ask:** When mapper detected any of: soft-delete fields, `balance`/`amount` fields updated
by logic, multi-user access patterns, external FK references, state machine patterns.

**Skip if:** No such patterns found in the scaffold.

**How to generate options:** Surface the specific pattern found and offer the 2–3 Mendix
approaches. Examples:

**Soft-delete pattern found:**
> "The source uses a soft-delete pattern (isDeleted flag). How should Mendix handle deleted records?"
> - A) Keep IsDeleted flag — filter all queries, never hard-delete *(recommended for data integrity)*
> - B) Hard delete in Mendix — simpler but loses history
> - C) Archive to a separate entity on delete

**State machine pattern found (XState / Workflow):**
> "The source has [N] state machine definitions. How should these map to Mendix?"
> - A) Mendix Workflow for human-approval flows, microflows for automated transitions *(recommended)*
> - B) Microflows only — simpler, no Workflow module dependency
> - C) Flag for manual review — decide per state machine

**Record as:** `PROJECT.md` → `## Decisions` → named per pattern found

---

## Open Question

> "Are there business rules, validation constraints, or compliance requirements that aren't
> visible in the source code? (e.g. 'amount can never exceed account balance', field-level
> regulations, audit requirements). List them or say 'none.'"

**What to do with the answer:**
- Each rule gets added as a `mendixNotes` entry in the relevant BRD's JSON before enrichment runs
- If compliance-related: flag in `brd-validation.md` as a hard requirement

---

## Decision Recording

```
PROJECT.md → ## Decisions:
  BRD enrichment order: [list]
  [Pattern name]: [chosen approach]
  Business rules (not in code): [list or 'none confirmed']
```
