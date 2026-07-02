# BRD Validation — Consistency Checks & Iterate-to-Clean
**Purpose:** Once BRDs exist — whether the auto-generated per-module scaffold from
`node run.js 3` or the enriched `F{NNN}.brd.json` from `brd-generation.md` — validate them
against every KB source before calling the extraction/mapping pass done. Catches duplicates,
conflicts between code and documents, orphaned concepts, and broken relationships that neither
the extractor nor the mapper layer currently detects.
**Companion skills:** `migration-pipeline.md` (Phase 5 — where this runs), `brd-generation.md`
(the BRD schema being validated), `document-discovery.md` + `kb-generation.md` (the doc-KB this
cross-checks against)

---

## When to Use This Skill

- After `node run.js 3` has produced scaffold BRDs and a `KB.md` exists from Phase 4 (document
  discovery) to cross-reference against
- After a manual BRD enrichment pass (`brd-generation.md`), before treating a BRD as final
- Any time extractor or mapper logic changes and you need to confirm nothing regressed

**Note:** no duplicate/conflict/orphan detection exists in the extraction pipeline today — the
current `merger.js` only does exact-key dedup, and BRD `confidence` is purely a gap-count
heuristic (0 gaps = high, 1–3 = medium, 4+ = low). Everything in this skill is a validation
*layer on top of* that, not a replacement for it.

---

## Inputs

| Source | Where it comes from | What it's checked for |
|---|---|---|
| Code-KB JSON | `knowledge-base/*.json` (Phase 2 — code extraction) | ground truth for what exists in source |
| Doc-KB | `knowledge-base/share/KB.md` + `KB_*.md` (Phase 4 — document discovery) | ground truth for documented business intent |
| Generated BRD | `knowledge-base/brd/*.brd.json` (Phase 3 scaffold) and/or `F{NNN}.brd.json` (Phase 5 enrichment) | what the migration will actually build |

If `KB.md` doesn't exist yet for a module (no documents were found or processed for it), skip
the code-vs-doc checks for that module and validate structurally only — absence of
documentation is not itself a conflict.

---

## Checks

### 1. Duplicate entities/concepts

Same entity or business concept appears under different names in different modules, or the
same name means different things in different modules, without any cross-reference noting it.

- Look for: attribute sets that are near-identical across two `domainEntities` entries with
  different names; the same source table/entity referenced from two BRDs without a shared
  association or explicit note.
- Fix at the root cause: usually a rearchitecting decision (Phase 6 — promote to a Common
  module) got skipped, not a mapper bug.

### 2. Conflicting business rules

Code says one thing, the doc-KB says another (or two doc-KB sources disagree and neither was
marked superseded).

- Look for: a validation rule inferred from code (`microflows[].validations`) that contradicts
  a rule stated in a `KB_*.md`'s "Business Rules" section for the same field/action.
- Fix at the root cause: usually means the code is the *current* behavior and the doc is stale
  (or vice versa) — this needs a human/business call, record it as an `openQuestions` entry on
  the BRD, don't silently pick one side.

### 3. Orphaned concepts

Something exists in one KB but has no trace in the BRD, or exists in the BRD with no traceable
source in either KB.

- **In code-KB but not in BRD:** an extracted entity/logic/screen that never made it into any
  mapper output — usually a mapper bug (check the relevant `brd-mappers/*.js` for a filter
  condition silently excluding it) or a module boundary that dropped it during Phase 6
  rearchitecting.
- **In doc-KB but not in BRD:** a business rule or field documented in a `KB_*.md` with no
  corresponding BRD entry — usually an incomplete enrichment pass (Step 3 of
  `brd-generation.md`), not an extractor issue.
- **In BRD but not in either KB:** a hallucinated or manually-added field/rule with no source —
  flag for removal or explicit sourcing.

### 4. Broken relationships

Extends the existing gap system rather than replacing it — a `fk-unresolved:{Entity}` or
`no-db-table-found` gap that isn't in this project's accepted "known gap noise" list (see the
project's `CLAUDE.md`) is a real broken relationship, not noise, and should block a clean
validation pass.

### 5. Low-confidence rollup

Reuse the existing gap-count-based `confidence` field (`brd-mappers/index.js`), but weight it:
a `low` confidence module that now has strong doc-KB corroboration (business rules, field
definitions confirmed by a real spec) is a better candidate for manual review than one with
neither code confidence nor doc coverage — surface both signals together in the report, not
`confidence` alone.

### 6. Business process flow reconciliation (code-inferred vs. documented)

`use-case-mapper.js` now produces a best-effort `mainFlow` and `appType` per module from code
alone (`status: 'code-inferred'`), instead of blank TODOs — see `migration-pipeline.md` Phase 3.
Once `KB.md` exists (Phase 4), reconcile each use case against it:

- **Confirmed:** the doc-KB describes the same flow/rule → flip `status` to `doc-confirmed`,
  and if it answers one of the use case's `openQuestions`, mark that question resolved and cite
  the `KB_*.md` source.
- **Contradicted:** the doc-KB describes a different flow/rule for the same screen/action → flip
  `status` to `doc-conflict` and add an `openQuestions` entry for business sign-off — same rule
  as check #2, don't have the pipeline silently pick a side.
- **No coverage:** doc-KB says nothing about this screen/action → leave `status` as
  `code-inferred`. This is not itself a finding; it just means Phase 4 didn't cover that area.

**Update these fields in place on the BRD JSON, not in a separate reconciliation file** — this
is what makes re-running `node generate-report.js` produce the combined code+doc report for
free, and it's exactly what `brd-mappers/index.js`'s overwrite guard exists to protect: a BRD
with any `doc-confirmed`/`doc-conflict` use case (or a resolved `openQuestions` entry) will not
be clobbered by a later `node run.js 3` — the fresh scaffold goes to
`{module}.brd.scaffold.json` instead.

---

## Procedure

```
run validator  →  validation-report.md
                        │
              review findings, group by check type
                        │
        fix ROOT CAUSE, not the symptom:
          - extractor bug            → patch extractors/{type}-extractor.js
          - mapper bug/gap           → patch generators/brd-mappers/{name}-mapper.js
          - linker rule missing      → patch lib/linker.js
          - genuine business conflict → record openQuestions on the BRD, don't silently resolve
          - stale/incomplete BRD     → re-run the enrichment pass (brd-generation.md)
                        │
        re-run: node run.js 2 xml && node run.js 3 && validator
                        │
              repeat until clean or only accepted gaps remain
```

`validation-report.md` follows the same shape as the existing `reports/gaps-report.md` — one
section per check type, each finding with: module, concept, sources checked, severity.

**Stop condition:** clean means zero findings outside the project's documented "known gap
noise" baseline (e.g. `no-db-table-found` when there's genuinely no DB source,
`fk-unresolved:User/Group/Role` mapping to platform entities). Don't chase every reference
below the ~15% gap threshold already used as a Phase 2 quality gate — that threshold exists so
this loop has a stopping point instead of running forever.

---

## Tips

- **Fix the extractor/mapper, not the JSON output by hand, for anything that should hold for
  every module** (a wrong purpose-inference regex, a missing gap code). If a mapper's assumption
  is wrong for this project, patch the mapper — that class of fix isn't protected by the
  overwrite guard and will be silently redone by the next `node run.js 3`.
- **Module-specific enrichment (use-case review, doc reconciliation) is safe to hand-edit in
  place** — that's exactly what the overwrite guard in `brd-mappers/index.js` protects (see
  check #6 above). Don't confuse the two: structural/mapper-level fixes go in code, per-module
  business content goes in the BRD JSON directly.
- **A conflict is not automatically a bug.** Code and docs disagreeing is often two true things
  at two points in time (code changed after the spec was written, or vice versa) — record it as
  an `openQuestions` entry for business sign-off, don't have the pipeline "decide."
- **Run this before Phase 6 rearchitecting, not after.** Orphaned/duplicate concepts are much
  cheaper to fix while everything is still 1:1 with source modules than after they've been
  consolidated into Mendix modules.
