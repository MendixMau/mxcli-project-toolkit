# Source Triage — Coverage, Scope, and the Go/No-Go Gate Before Extraction
**Purpose:** Before running any extractor or generating any BRD, decide whether this toolkit's pipelines actually cover the source stack, whether automated extraction is even warranted at this app's size, and — if the source is large — recommend a bounded scope subset instead of processing everything at once.
**Upstream:** `migration-pipeline.md` Phase 1 (Source Analysis) — run this immediately after identifying the platform (1.1) and before scoping the extraction (1.3).
**Downstream:** `migration-pipeline.md` Phase 2/3 (extraction + BRD scaffolding) — **gated** on this skill's output. `modularize-domain.md` (module boundaries within *one* app — assumes the "how many apps" question this skill raises is already answered).
**Companion:** `assess-migration.md` (the manual technical/functional inventory this skill's coverage matrix checks against), `qa-loop-goal-pattern.md` (how to validate a newly-built extractor once this triage says one is needed).

---

## When to Use This Skill

- Starting a migration from a new or unfamiliar source stack
- Deciding whether to build a new extractor, reuse an existing pipeline (`pipelines/outsystems/`, `pipelines/java-angular/`), or skip automation entirely
- The source app is large enough that "migrate everything at once" feels risky, or big enough that even module-level decomposition (`modularize-domain.md`) might not be sufficient
- You're about to run `node run.js 3` (BRD scaffolding) on a stack nobody has validated extraction quality for yet

---

## Core Principle

**Do not generate BRDs, let alone start the Mendix build, until this triage produces three things:** an extraction-approach decision, a coverage/gap list, and — if the source is large — a bounded scope recommendation. Running Phase 3 before this is settled produces BRDs for a scope nobody agreed to, from a pipeline nobody confirmed is reliable for this stack.

---

## Step 1: Does This App Need an Extraction Pipeline At All?

Not every migration earns back the cost of the JSON extraction machinery. Decide explicitly — don't default into building one because that's what the last project did:

| Signal | Lean toward |
|---|---|
| Small app (rough guide: well under ~20 entities, ~20 screens, a handful of services/modules total) | **Manual-only** — walk `assess-migration.md`'s inventory by hand and author the BRD directly. Standing up an extractor for an app this size is more setup work than the automation saves. |
| Medium/large app, source platform already covered by `pipelines/outsystems/` or `pipelines/java-angular/` | **Reuse existing pipeline** — run Phase 2 as documented. |
| Medium/large app, source platform matches nothing in `migration-pipeline.md` 1.1's platform table | **Build new pipeline** — a real investment; confirm the size justifies it before starting. |

Record the decision explicitly as one of: **Manual-only / Reuse existing pipeline / Build new pipeline.** If "build new," `qa-loop-goal-pattern.md` governs validating the new extractor/linker/mapper against real source until output quality is genuinely high — don't skip straight to trusting its first run, and don't fold pipeline-development time into the migration timeline as if it were a fixed cost.

---

## Step 2: Business Capability Map

Map technical modules/components/services to business capabilities — not source file or class names. This is the shared input both Step 4 (scope) and `modularize-domain.md` (module boundaries) need later; do it once, here.

| Business capability | Source components | Rough size (entities/screens) | Owner / team (if known) |
|---|---|---|---|
| e.g. Order Management | `OrderController`, `OrderService`, 3 JSPs | 4 entities, 5 screens | Sales team |
| e.g. Inventory | `ItemController`, `StockService` | 2 entities, 3 screens | Warehouse team |

---

## Step 3: Coverage Matrix — What Can Actually Be Extracted, Mapped, and Trusted

Per business capability, answer the questions that decide whether its BRD comes from automation or a human:

- Can this be extracted automatically (does an extractor for this source shape exist)?
- Does a mapper exist to turn that extraction into a BRD?
- Is the output reliable enough to trust without heavy rework (check against `migration-pipeline.md` Phase 2's quality checklist once a sample run exists)?
- If not: does this need a new extractor, a new mapper, or is it just better done manually?

| Capability | Extractable? | Mapper → BRD? | Reliable? | Verdict |
|---|---|---|---|---|
| e.g. Order Management | Yes (Java extractor) | Yes (`domain-entity-mapper`, `microflow-mapper`) | Yes — sample checked | **Ready** |
| e.g. Reporting (JasperReports) | No extractor for this | — | — | **Manual** |
| e.g. Legacy batch jobs | Extracts fine | No mapper for cron/batch shape yet | Untested | **Extract-only** — needs a mapper built |

Verdict vocabulary (mirrors `architecture-blueprint.md`'s fit-gap vocabulary on purpose, so the two stay legible together): **Ready** (extract + map today, trust the output) · **Extract-only** (JSON extracts fine, no mapper yet) · **Manual** (skip automation, write this capability's BRD by hand) · **Defer** (out of scope for this phase, revisit later) · **Unknown** (can't assess yet — needs a spike).

---

## Step 4: Bounded Scope Recommendation

**Not always a "POC."** A bounded subset matters whenever the source is large, whether the actual goal is a proof-of-concept, a phased rollout, or an eventual full migration done in slices. Don't force POC framing onto a project that's committed to a full migration from day one — the underlying decision (which capabilities go first) is the same either way.

Recommend a first slice from Steps 2–3: capabilities that are **Ready**, business-valuable, and reasonably self-contained (few cross-capability dependencies — check against the wiring graph this feeds into `architecture-blueprint.md` Step 3 later). Two things this recommendation must NOT be based on alone:
- **Extraction cleanliness alone.** A capability that happens to extract cleanly but has low business priority is a bad first slice — ask the user about priority, don't infer it from code tidiness.
- **Silent scope creep in the other direction.** If everything is "Ready," that's not automatically a reason to do it all at once — a large first slice still needs the same dependency/priority reasoning as a small one.

Document as: **capability → verdict → recommended for this slice (yes/no/deferred) → why.**

---

## Step 5: Flag — Does This Need Multiple Mendix Apps, Not Just Modules?

`modularize-domain.md` decides module boundaries **within one Mendix app**, with its own over-/under-split signals (e.g. "one module past ~15–20 persistent entities"). At large enough scale, the real question isn't module count — it's whether this should be **more than one Mendix app**: separate runtimes and databases, integrated via REST/OData/Business Events, the closest Mendix equivalent to a microservices split.

**This skill does not define full multi-app decomposition criteria — that's a bigger architectural question this toolkit hasn't validated against a real large migration yet. Flag it, don't answer it unilaterally.** Raise it explicitly as an open question when:

- The business capability map (Step 2) surfaces capabilities with clearly independent release cadences, ownership, or security/regulatory domains, **and**
- The combined in-scope entity/screen count is large enough that `modularize-domain.md` would still land on many modules (rough signal: it's still recommending 8–10+ modules after applying its own merge criteria) rather than converging toward a handful.

If flagged, resolve "one app or several" as its own open issue **before** `modularize-domain.md` runs — that decision has to come first, not after modules are already being drawn inside a single domain model. If this is the first time your team has hit this question, say so plainly to the user rather than inventing a threshold to sound decisive.

---

## Output Template

```markdown
# Source Triage: [Application Name]

## Extraction Approach
Decision: Manual-only / Reuse existing pipeline (<which>) / Build new pipeline
Reasoning: [size, stack match, effort tradeoff]

## Business Capability Map
[Step 2 table]

## Coverage Matrix
[Step 3 table]

## Recommended Scope Subset
[Step 4: capability → verdict → in this slice? → why]

## Architecture Scale Flag
[Step 5 — "no concern" OR the open question raised, with the trigger conditions that fired]

## Sign-off
Confirmed by: [user] on [date] — required before Phase 2/3 proceed.
```

---

## Anti-Patterns This Skill Prevents

- **Building an extractor before checking if the app is even big enough to need one.** Wasted setup cost for a migration `assess-migration.md` could have covered by hand in less time.
- **Running Phase 3 (BRD scaffolding) the moment Phase 2 produces output, with no scope sign-off.** Produces BRDs for capabilities nobody agreed should come first.
- **Calling every bounded-scope decision a "POC."** Forces artificial throwaway framing onto phased full migrations, and invites treating the first slice's shortcuts as permanent.
- **Deciding module boundaries (`modularize-domain.md`) before asking whether this should be multiple apps.** The app-count question is upstream of the module-count question — answering them in the wrong order means redrawing module boundaries after discovering they should've been app boundaries.
- **Treating "extracts cleanly" as equivalent to "high priority."** The easiest capability to automate is not automatically the right one to migrate first.
