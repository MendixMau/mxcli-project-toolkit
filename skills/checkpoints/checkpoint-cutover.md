# CAC-6 — Cutover Checkpoint

**Fires after:** Stage 6 (Test) has passed — never before; you don't migrate real data onto an app that hasn't cleared its E2E gate.
**Feeds into:** Stage 7 (Cutover) execution — migration scripts and the cutover checklist.
**Template:** See `checkpoint-template.md` for format rules.
**Hard gate:** Stage 7 is a `✋` gate — every answer here must land in `PROJECT.md` as `CONFIRMED`. No `ASSUMED` defaults past this checkpoint; if the user can't answer yet, the pipeline waits.

Migration-mode only. Greenfield and requirements-driven builds with no legacy data skip Stage 7 entirely — record that skip in `PROJECT.md` as a one-line decision ("no legacy system, no cutover"), don't leave it implicit.

---

## What to Surface

Pull from the actual project state:
- Stage 6 result: scenarios passed / failed / re-run (from `test-report.html`)
- What legacy data exists: entities and row counts if a legacy DB is reachable, otherwise what the KB/BRDs say the legacy system stores
- What the app currently runs on: Stage 5 seed data? empty?
- Any integrations that flip endpoints at cutover (from Stage 3's integration contracts)

## What's Next

Stage 7 produces legacy-data migration scripts (if any) and a cutover checklist naming who does what, when, and how to roll back.

---

## Predefined Questions

### Q1 — Legacy data disposition

**When to ask:** Always — this is the decision Stage 7 exists for.

**How to generate options:** From the legacy data surfaced above. Always include the "drop it" option — throwing legacy data away is a legitimate, recordable decision, not a failure.

Example:
> "The legacy system holds ~40k asset records and 3 years of transaction history. What happens to it?"
> - A) Migrate all of it — full history preserved *(only if the BRDs actually require history)*
> - B) Migrate master data only, drop transactional history *(recommended when reports don't need it)*
> - C) Go live empty / with Stage 5 seed data — legacy stays read-only as an archive

**Record as:** `PROJECT.md` → `## Decisions` → `Cutover — data:` (must be `CONFIRMED`)

---

### Q2 — Cutover execution and rollback

**When to ask:** Always.

**How to generate options:** From who's available (intake's SME/owner answers) and what the deployment target is (Stage 4's DTAP decision). Options differ in window and rollback posture, not in vague "carefully".

Example:
> "Who flips the switch, and what's the rollback if day one goes wrong?"
> - A) Big-bang over a weekend, legacy kept warm for 2 weeks as rollback *(recommended)*
> - B) Parallel run — both systems live for N weeks, users migrate in groups
> - C) Soft launch — new app live for one team first, rest follow

**Record as:** `PROJECT.md` → `## Decisions` → `Cutover — execution:` (must be `CONFIRMED`, with a named owner and date)

---

## Open Question

> "Is there anything about the legacy system's retirement that isn't in the code or the data — contractual retention obligations, an audit that needs the old system readable, a licence that expires, a team that still depends on a report nobody mentioned?"

Plain text — this is exactly the class of knowledge only the human has. Record the answer (or "none") in `PROJECT.md` → `## Decisions` → `Cutover — constraints:`.

---

## Skip Rule

Per `checkpoint-template.md`: this checkpoint may only be skipped if all three answers are already recorded `CONFIRMED` in `PROJECT.md`. Being a `✋` gate, it never auto-skips on `ASSUMED` values.
